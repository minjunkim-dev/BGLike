extends "res://tests/presentation_qa.gd"
## #351: 실제 _process 적 AI와 연출을 유지하는 Mac 장기 관찰. 아군 정책은 자동이며 사람 플레이가 아니다.
## 5분은 검수 종료 조건이다. 전투·증식 상한이나 성능 합격 기준으로 쓰지 않는다.
const DURATION_SECONDS: int = 300
var started: int
var frame_file: FileAccess
var peak_alive: int = 0
var spawned: int = 0
var saves: int = 0
var fights: int = 0
var next_capture: int = 30
var save_costs: Array[int] = []
var enemy_frames: int = 0

func _run() -> void:
	kind = "live"
	preflight = "--fixture-precheck" in OS.get_cmdline_user_args()
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--capture-dir="): directory = arg.trim_prefix("--capture-dir=")
	assert(not directory.is_empty())
	DirAccess.make_dir_recursive_absolute(directory)
	GameSave.autosave = false
	GameSave.path = directory.path_join("qa-only-save.bin")
	GameSettings.path = directory.path_join("qa-only-settings.cfg")
	game = load("res://scenes/game.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	battle = game.get_node("Battle")
	(battle.get("progress") as CombatActProgress).stage_index = 6
	battle.call("_start_stage", true)
	_equip()
	var actions: CombatActions = battle.get("actions")
	assert((battle.get("units") as Array).size() == 7 and battle.is_processing())
	assert((battle.get("party") as Array).all(func(unit: CombatUnit) -> bool: return unit.hit_points == unit.get_max_hit_points()))
	if preflight:
		var bag: Array = (battle.get("loot") as CombatLoot).bag.duplicate(true)
		for retry: int in range(5):
			battle.call("_start_stage", true)
			_equip()
		assert((battle.get("loot") as CombatLoot).bag == bag)
		print("[SOAK_FIXTURE_READY]")
		game.queue_free()
		await process_frame
		quit()
		return
	GameSave.autosave = true
	battle.connect("autosaved", func() -> void: saves += 1)
	actions.logged.connect(func(message: String) -> void:
		if " 새끼 낳기:" in message: spawned += 1)
	frame_file = FileAccess.open(directory.path_join("performance.csv"), FileAccess.WRITE)
	frame_file.store_line("usec,delta_s,static_memory_bytes,alive,enemy,paused,waiting")
	var listener: Inputs = Inputs.new()
	listener.tree = self
	listener.process_mode = Node.PROCESS_MODE_ALWAYS
	root.add_child(listener)
	print("[SOAK_READY] native Start required; current loot maximum rolls, normal HP/AI/spawn; automatic nearest policy")
	await capture("initial")
	started = -1
	while started < 0 or (Time.get_ticks_msec() - started) / 1000 < DURATION_SECONDS:
		await create_timer(0.1).timeout
		if FileAccess.file_exists(directory.path_join("capture")):
			DirAccess.remove_absolute(directory.path_join("capture"))
			await capture("checkpoint")
		if paused or battle.get("waiting_for_start"): continue
		if started < 0: started = Time.get_ticks_msec()
		if FileAccess.file_exists(directory.path_join("hold")): continue
		if (Time.get_ticks_msec() - started) / 1000 >= next_capture:
			await capture("periodic")
			next_capture += 30
		if actions.is_over():
			if actions.busy or battle.get("_enemy_turn_running"): continue
			fights += 1
			await capture("fight-ended")
			battle.call("_start_stage", true)
			_equip()
			battle.call("start_battle")
			continue
		await _step()
	# 실제 적 턴이 끝난 저장 가능한 상태에서 마지막 원본과 비용을 남긴다.
	var deadline: int = Time.get_ticks_msec() + 30_000
	while (actions.busy or battle.get("_enemy_turn_running")) and Time.get_ticks_msec() < deadline:
		if actions.pending_reactor != null: actions.resolve_reaction(true)
		await process_frame
	assert(battle.call("_can_save") and enemy_frames > 0)
	for probe: int in range(3):
		var state: Dictionary = battle.call("combat_state")
		var before: int = Time.get_ticks_usec()
		battle.call("_autosave", state)
		save_costs.append(Time.get_ticks_usec() - before)
		assert(GameSave.read().sections.combat == state)
	await capture("final")
	frame_file.flush()
	var summary: Dictionary = {"seconds": (Time.get_ticks_msec() - started) / 1000.0, "completed_fights": fights,
		"peak_alive": peak_alive, "spawned_cumulative": spawned, "autosaves": saves, "enemy_frames": enemy_frames,
		"save_cost_usec": save_costs, "normal_process": battle.is_processing(), "time_scale": Engine.time_scale}
	FileAccess.open(directory.path_join("summary.json"), FileAccess.WRITE).store_string(JSON.stringify(summary, "\t"))
	print("[SOAK_DONE] ", JSON.stringify(summary))
	quit()

func _equip() -> void:
	var loot: CombatLoot = battle.get("loot")
	for unit: CombatUnit in battle.get("party"):
		for item_kind: String in ["weapon", "armor"]:
			var equipped: Dictionary = unit.get(item_kind)
			if not equipped.is_empty(): continue
			var item: Dictionary = loot.data.items.filter(func(value: Dictionary) -> bool: return value.kind == item_kind)[0].duplicate(true)
			for stat: String in item.stats: item.stats[stat] = int(item.stats[stat][-1][1])
			assert(loot.receive(unit, item))
		unit.hit_points = unit.get_max_hit_points()
		unit.potion_left = int(loot.data.potion_limit)
	(battle.get("actions") as CombatActions).dice.seed = 351 + fights
	var dice: CombatDice = CombatDice.new()
	dice.seed = 10351 + fights
	(battle.get("turns") as CombatTurns).start(battle.get("units"), dice)
	battle.call("_update_turn_ui")

## combat_save_test의 단순 정책을 재사용한다. 적 턴은 직접 호출하지 않는다.
func _step() -> void:
	var actions: CombatActions = battle.get("actions")
	if actions.pending_reactor != null:
		actions.resolve_reaction(true)
		return
	var actor: CombatUnit = (battle.get("turns") as CombatTurns).current_unit
	if actions.busy or battle.get("_enemy_turn_running") or actor == null or not actor.is_ally: return
	for heal: String in ["second_wind", "potion"]:
		if actor.hit_points * 2 <= actor.get_max_hit_points() and actions.can_use(actor, heal):
			actions.use_self(actor, heal)
			return
	var targets: Array[CombatUnit] = actions.units.filter(func(unit: CombatUnit) -> bool: return not unit.is_ally and unit.hit_points > 0)
	targets.sort_custom(func(a: CombatUnit, b: CombatUnit) -> bool: return actor.cell.distance_squared_to(a.cell) < actor.cell.distance_squared_to(b.cell))
	for target: CombatUnit in targets:
		if actions.can_target(actor, target, "attack"):
			await actions.attack(actor, target, actions.can_target(actor, target, "shock"))
			return
	var cell: Vector2i = CombatEnemyAi.new().approach_cell(actor, actions)
	if cell != actor.cell and actions.can_move(actor, cell):
		await actions.move_to(actor, cell)
	else:
		battle.call("_end_turn")

func sample(delta: float) -> void:
	if frame_file == null or battle == null: return
	var alive: int = (battle.get("units") as Array).filter(func(unit: CombatUnit) -> bool: return unit.hit_points > 0).size()
	peak_alive = maxi(peak_alive, alive)
	var enemy: bool = battle.get("_enemy_turn_running")
	if enemy: enemy_frames += 1
	frame_file.store_line("%d,%.6f,%d,%d,%d,%d,%d" % [Time.get_ticks_usec(), delta,
		int(Performance.get_monitor(Performance.MEMORY_STATIC)), alive, int(enemy), int(paused), int(battle.get("waiting_for_start"))])
