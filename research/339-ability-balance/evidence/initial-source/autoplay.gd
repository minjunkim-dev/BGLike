extends SceneTree
## Issue #278 balance-statistics autoplay. Loads the product main scene unchanged (no HP, placement,
## number or stage changes; test-only RNG subclasses fix both independent streams). Allies are driven through pointer
## and key events (Input.parse_input_event) with a fixed policy; Button.pressed.emit() is a counted fallback.
## Run headless with --fixed-fps 60 so frames/60 = seconds a player would wait at 1x speed (no Space held).
## User args: --out=<dir> --policy=nearest|mother --run=<n>

## Harness limits, not game rules: a run that hits one stops and is reported as unfinished.
const ROUND_CAP: int = 60
const ATTEMPT_CAP: int = 10

class SeededDice extends CombatDice:
	var next_seed: int
	func randomize() -> void:
		seed = next_seed
		next_seed += 1

class SeededTurns extends CombatTurns:
	var next_seed: int
	func start(combat_units: Array[CombatUnit], dice: CombatDice) -> void:
		dice.seed = next_seed
		next_seed += 1
		super.start(combat_units, dice)

var out_dir: String = ""
var policy: String = "mother"
var run_id: int = 0
var battle: Node2D
var hud: Control
var actions: CombatActions
var turns: CombatTurns
var selection: CombatSelection
var preparation: CombatPreparation
var progress: CombatActProgress
var map: CombatMap
var party: Array[CombatUnit] = []

var frames: int = 0
var cur_stage: int = -1
var attempts: Dictionary = {}  # stage index -> attempt count
var rec: Dictionary = {}  # current attempt record
var rows: Array[Dictionary] = []
var streak_rows: Array[String] = []
var segment_rows: Array[String] = []
var ally_streak: int = 0
var enemy_streak: int = 0
var seg_start: int = -1
var seg_round: int = 0
var pointer_fallbacks: int = 0
var field_click_failures: Array[String] = []
var invisible_candidates: Array[String] = []
var movement_records: Array[Dictionary] = []
var movement_failures: Array[String] = []
var wall_t0: int = 0
var _done: bool = false


func _initialize() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			out_dir = arg.trim_prefix("--out=")
		elif arg.begins_with("--policy="):
			policy = arg.trim_prefix("--policy=")
		elif arg.begins_with("--run="):
			run_id = int(arg.trim_prefix("--run="))
	assert(policy in ["nearest", "mother"] and run_id >= 1 and run_id <= 1000000 and not out_dir.is_empty())
	_run.call_deferred()


func _process(_delta: float) -> bool:
	frames += 1
	if turns == null or _done or rec.is_empty():
		return false
	var actor: CombatUnit = turns.current_unit
	var enemy_now: bool = actor != null and not actor.is_ally and not actions.is_over()
	if enemy_now and seg_start < 0:
		seg_start = frames
		seg_round = turns.round_number
	elif not enemy_now and seg_start >= 0:
		_close_segment()
	return false


func _close_segment() -> void:
	var seconds: float = (frames - seg_start) / 60.0
	seg_start = -1
	rec["enemy_time_s"] = float(rec["enemy_time_s"]) + seconds
	rec["enemy_segment_max_s"] = maxf(float(rec["enemy_segment_max_s"]), seconds)
	rec["enemy_segments"] = int(rec["enemy_segments"]) + 1
	segment_rows.append("%s,%d,%s,%d,%d,%.3f" % [policy, run_id, rec["stage"], rec["attempt"], seg_round, seconds])


func _p(text: String) -> void:
	print("[R278 %s#%d %6.1fs] %s" % [policy, run_id, (Time.get_ticks_msec() - wall_t0) / 1000.0, text])


func _stage_name(index: int = -1) -> String:
	if index < 0:
		index = progress.stage_index
	return "%d-%d" % [index / 3 + 1, index % 3 + 1]


func _run() -> void:
	GameSave.autosave = false
	GameSave.path = "user://tests/321_autoplay/%d/save.bin" % OS.get_process_id()
	GameSettings.path = "user://tests/321_autoplay/%d/settings.cfg" % OS.get_process_id()
	wall_t0 = Time.get_ticks_msec()
	create_timer(4 * 3600.0).timeout.connect(func() -> void: _finish(2, "watchdog"))
	var main: Node = (load("res://scenes/game.tscn") as PackedScene).instantiate()
	battle = main.get_node("Battle") as Node2D
	var seeded: SeededDice = SeededDice.new()
	seeded.next_seed = run_id * 100000
	(battle.get("actions") as CombatActions).dice = seeded
	var seeded_turns: SeededTurns = SeededTurns.new()
	seeded_turns.next_seed = run_id * 100000 + 50000
	battle.set("turns", seeded_turns)
	root.add_child(main)
	current_scene = main
	hud = battle.get_node("UI/TurnHud") as Control
	actions = battle.get("actions")
	turns = battle.get("turns")
	selection = battle.get("selection")
	preparation = battle.get_node("UI/Preparation") as CombatPreparation
	progress = battle.get("progress")
	map = battle.get_node("Map") as CombatMap
	party = battle.get("party")
	# Before the first process frame, both initial initiative and action RNGs have been seeded.
	if "--fixture-precheck" in OS.get_cmdline_user_args():
		assert(party.size() == 2 and actions.units.size() >= 3)
		print("[AUTOPLAY_PREFLIGHT] PASS")
		main.queue_free()
		await process_frame
		quit(0)
		return
	actions.logged.connect(_on_log)
	_p("start policy=%s display=%s" % [policy, DisplayServer.get_name()])
	_begin_attempt()
	await _loop()


func _on_log(message: String) -> void:
	if rec.is_empty():
		return
	if message.contains(" 새끼 낳기: "):
		rec["spawned"] = int(rec["spawned"]) + 1
		return
	if not (message.contains(" 공격(") or message.contains(" 방어:")):
		return
	var missed: bool = message.ends_with("빗나감")
	var ally_attack: bool = message.begins_with("아군")
	if message.contains(" 방어:"):
		ally_attack = not ally_attack
	if ally_attack:
		rec["ally_attacks"] = int(rec["ally_attacks"]) + 1
		if missed:
			rec["ally_misses"] = int(rec["ally_misses"]) + 1
			ally_streak += 1
		else:
			_end_streak("ally")
	else:
		rec["enemy_attacks"] = int(rec["enemy_attacks"]) + 1
		if missed:
			rec["enemy_misses"] = int(rec["enemy_misses"]) + 1
			enemy_streak += 1
		else:
			_end_streak("enemy")


## A streak is a maximal run of consecutive missed attack rolls by one side within one stage attempt.
func _end_streak(side: String) -> void:
	var length: int = ally_streak if side == "ally" else enemy_streak
	if length > 0:
		streak_rows.append("%s,%d,%s,%d,%s,%d" % [policy, run_id, rec["stage"], rec["attempt"], side, length])
		rec[side + "_streak_max"] = maxi(int(rec[side + "_streak_max"]), length)
	if side == "ally":
		ally_streak = 0
	else:
		enemy_streak = 0


func _begin_attempt() -> void:
	var index: int = progress.stage_index
	attempts[index] = int(attempts.get(index, 0)) + 1
	cur_stage = index
	ally_streak = 0
	enemy_streak = 0
	seg_start = -1
	var extra: int = 0
	for unit: CombatUnit in actions.units:
		if unit.can_drop_extra_reward():
			extra += 1
	rec = {"policy": policy, "run": run_id, "stage": _stage_name(index), "attempt": attempts[index],
		"result": "", "rounds": 0, "game_s": 0.0, "start_frame": frames,
		"warrior_hp": 0, "warrior_max": 0, "archer_hp": 0, "archer_max": 0, "downed": 0,
		"start_potions": party[0].potion_left + party[1].potion_left, "potions_used": 0,
		"potions_warrior": 0, "potions_archer": 0,
		"rewards": 0, "rewards_weapon": 0, "rewards_armor": 0, "rewards_potion": 0, "extra_eligible": extra,
		"spawned": 0, "enemy_time_s": 0.0, "enemy_segment_max_s": 0.0, "enemy_segments": 0,
		"ally_attacks": 0, "ally_misses": 0, "ally_streak_max": 0,
		"enemy_attacks": 0, "enemy_misses": 0, "enemy_streak_max": 0,
		"bag_end": 0, "discarded": 0}
	_p("stage %s attempt %d %s" % [rec["stage"], rec["attempt"], _ally_status()])


func _close_attempt(result: String) -> void:
	if rec.is_empty() or not str(rec["result"]).is_empty():
		return
	if seg_start >= 0:
		_close_segment()
	_end_streak("ally")
	_end_streak("enemy")
	rec["result"] = result
	rec["rounds"] = turns.round_number
	rec["game_s"] = (frames - int(rec["start_frame"])) / 60.0
	rec["warrior_hp"] = party[0].hit_points
	rec["warrior_max"] = party[0].get_max_hit_points()
	rec["archer_hp"] = party[1].hit_points
	rec["archer_max"] = party[1].get_max_hit_points()
	rec["downed"] = party.filter(func(u: CombatUnit) -> bool: return u.hit_points <= 0).size()
	rec["potions_warrior"] = party[0].potion_left
	rec["potions_archer"] = party[1].potion_left
	_p("%s %s rounds=%d %s" % [result, rec["stage"], rec["rounds"], _ally_status()])


func _flush_attempt() -> void:
	if rec.is_empty():
		return
	rec["bag_end"] = preparation.loot.bag.size()
	rec.erase("start_frame")
	rows.append(rec)
	rec = {}
	_write_outputs(-1, "")


func _ally_status() -> String:
	var parts: Array[String] = []
	for unit: CombatUnit in party:
		parts.append("%s HP%d/%d 물약%d" % [unit.get_display_name(), unit.hit_points,
			unit.get_max_hit_points(), unit.potion_left])
	return ", ".join(parts)


func _frames(count: int) -> void:
	for index: int in range(count):
		await process_frame


func _loop() -> void:
	var idle_guard: int = 0
	while not _done:
		await process_frame
		var result: Control = hud.get_node("Result") as Control
		if turns.round_number >= 1 and not actions.is_over() and progress.stage_index != cur_stage:
			_begin_attempt()
		if hud.reaction_dialog.visible:
			await _answer_reaction()
			continue
		if result.visible:
			var text: String = (hud.get("result_label") as Label).text
			if text == "3막 졸업":
				_flush_attempt()
				_finish(0, "graduated")
				return
			var button: Button = hud.get("restart_button")
			if button.disabled:
				continue
			if text == "승리":
				_close_attempt("win")
				await _press(button, "result:보상 확인")
			else:
				_close_attempt("wipe")
				_flush_attempt()
				if int(attempts.get(progress.stage_index, 0)) >= ATTEMPT_CAP:
					_finish(6, "attempt cap %d at %s" % [ATTEMPT_CAP, _stage_name()])
					return
				await _press(button, "result:막 재시작")
				cur_stage = -1
			await _frames(3)
			continue
		if battle.get("waiting_for_start") and not preparation.visible:
			await _press((battle.get("staging") as Control).get_child(2) as Button, "staging:전투 시작")
			continue
		if preparation.visible:
			await _handle_preparation()
			continue
		if not rec.is_empty() and turns.round_number > ROUND_CAP:
			_close_attempt("timeout")
			_flush_attempt()
			_finish(4, "round cap %d at %s" % [ROUND_CAP, _stage_name()])
			return
		var actor: CombatUnit = turns.current_unit
		if actor != null and actor.is_ally and not actions.busy and not actions.is_over() and not battle.get("_enemy_turn_running"):
			await _play_ally_turn(actor)
			idle_guard = 0
		else:
			idle_guard += 1
			if idle_guard > 60 * 600:
				_finish(3, "stall actor=%s busy=%s over=%s" % [actor, actions.busy, actions.is_over()])
				return


func _answer_reaction() -> void:
	# Policy: always accept opportunity attacks and parry when offered.
	await _frames(2)
	if hud.reaction_dialog.visible:
		hud.reaction_dialog.get_ok_button().pressed.emit()
	await _frames(2)


# ---------------------------------------------------------------- input helpers

func _key(code: int) -> void:
	var key: InputEventKey = InputEventKey.new()
	key.keycode = code as Key
	key.physical_keycode = code as Key
	key.pressed = true
	Input.parse_input_event(key)
	await process_frame
	key.pressed = false
	Input.parse_input_event(key)
	await process_frame
	await process_frame


func _click_canvas(point: Vector2, button_index: MouseButton = MOUSE_BUTTON_LEFT) -> void:
	var event: InputEventMouseButton = InputEventMouseButton.new()
	event.position = root.get_final_transform() * point
	event.global_position = event.position
	event.button_index = button_index
	event.pressed = true
	var motion: InputEventMouseMotion = InputEventMouseMotion.new()
	motion.position = event.position
	motion.global_position = event.position
	Input.parse_input_event(motion)
	Input.parse_input_event(event)
	await process_frame
	event.pressed = false
	Input.parse_input_event(event)
	await process_frame
	await process_frame


func _press(button: BaseButton, _label: String, offset: Vector2 = Vector2.ZERO) -> void:
	var state: Dictionary = {"hit": false}
	var probe: Callable = func() -> void: state["hit"] = true
	button.pressed.connect(probe, CONNECT_ONE_SHOT)
	if button.is_visible_in_tree() and not button.disabled:
		await _click_canvas(offset + button.get_global_rect().get_center())
	if not state["hit"]:
		if button.pressed.is_connected(probe):
			button.pressed.disconnect(probe)
		pointer_fallbacks += 1
		button.pressed.emit()
		await process_frame


func _press_dialog(dialog: Window, button: BaseButton, label: String) -> void:
	await _press(button, label, Vector2(dialog.position))


func _settle() -> void:
	for frame: int in range(60 * 30):
		if hud.reaction_dialog.visible:
			await _answer_reaction()
			continue
		var moving: bool = false
		for unit: CombatUnit in actions.units:
			moving = moving or (is_instance_valid(unit) and unit.is_moving)
		if not moving and not battle.has_node("Arrow") and not actions.busy:
			# 다음 프레임에는 사망한 아군 대신 적 AI가 새 행동을 시작할 수 있다.
			return
		await process_frame


func _enemies() -> Array[CombatUnit]:
	var list: Array[CombatUnit] = []
	for unit: CombatUnit in actions.units:
		if is_instance_valid(unit) and not unit.is_ally and unit.hit_points > 0:
			list.append(unit)
	return list


func _can_act(actor: CombatUnit) -> bool:
	return (turns.current_unit == actor and actor.hit_points > 0 and not actions.is_over()
		and not hud.get_node("Result").visible)


func _slot_of(action: String) -> int:
	var slots: Array = hud.get("_action_slots")
	var buttons: Dictionary = hud.get("_actions")
	return slots.find(buttons[action])


## Selects a skill by its number key (#248), falling back to a pointer click on the icon.
func _use_button(action: String, actor: CombatUnit) -> bool:
	var buttons: Dictionary = hud.get("_actions")
	var button: Button = buttons[action]
	if button.disabled or not actions.can_use(actor, action):
		return false
	var slot: int = _slot_of(action)
	var bonus_before: int = actor.bonus_action_left
	var selected_before: String = selection.selected_action
	if slot >= 0 and slot < 9:
		await _key(KEY_1 + slot)
		var worked: bool = selection.selected_action == action or actor.bonus_action_left < bonus_before
		if action == selected_before and action not in CombatActionRules.SELF_TARGET:
			worked = true
		if worked:
			return true
	await _press(button, "skill:" + action)
	return true


func _use_self(actor: CombatUnit, action: String) -> bool:
	if not actions.can_use(actor, action):
		return false
	var before: int = actor.bonus_action_left
	await _use_button(action, actor)
	if selection.selected_action == action and actor.bonus_action_left == before:
		await _use_button(action, actor)
	await _settle()
	var ok: bool = actor.bonus_action_left < before
	if ok and action == "potion" and not rec.is_empty():
		rec["potions_used"] = int(rec["potions_used"]) + 1
	return ok


func _unit_point(target: CombatUnit) -> Variant:
	var candidates: Array[Vector2] = []
	for dy: int in [-14, -10, -18, -6, -22, -26, -4]:
		for dx: int in [0, -2, 2, -4, 4, -6, 6]:
			candidates.append(Vector2(dx, target.floor_offset_y + dy))
	for offset: Vector2 in candidates:
		var world: Vector2 = target.global_position + offset
		if not target.contains_body_point(target.to_local(world)):
			continue
		var top: CombatUnit = target
		for unit: CombatUnit in actions.units:
			if unit == target or not is_instance_valid(unit) or unit.hit_points <= 0 or not unit.visible:
				continue
			if unit.contains_body_point(unit.to_local(world)):
				if unit.position.y > top.position.y or (unit.position.y == top.position.y and unit.get_index() > top.get_index()):
					top = unit
		if top != target:
			continue
		var prop: CombatGrid.Prop = map.prop_at_point(map.to_local(world))
		# Same rule as battle.gd _unhandled_input: an outlined (occluded) enemy wins over the prop in front.
		if prop != null and not target.is_occluded and map.map_to_local(prop.cell).y >= target.position.y:
			continue
		var canvas: Vector2 = battle.get_canvas_transform() * world
		if _over_gui(canvas):
			continue
		return canvas
	return null


func _cell_point(cell: Vector2i) -> Variant:
	for offset: Vector2 in [Vector2.ZERO, Vector2(0, 2), Vector2(0, -2), Vector2(3, 0), Vector2(-3, 0), Vector2(0, 4)]:
		var world: Vector2 = map.to_global(map.map_to_surface(cell) + offset)
		if map.surface_to_map(map.to_local(world)) != cell:
			continue
		var canvas: Vector2 = battle.get_canvas_transform() * world
		if _over_gui(canvas):
			continue
		return canvas
	return null


func _over_gui(canvas: Vector2) -> bool:
	if canvas.x < 1 or canvas.y < 1:
		return true
	var size: Vector2 = root.get_visible_rect().size
	if canvas.x > size.x - 1 or canvas.y > size.y - 1:
		return true
	return _gui_blocks(hud, canvas)


func _gui_blocks(node: Node, canvas: Vector2) -> bool:
	for child: Node in node.get_children():
		if child is Control:
			var control: Control = child
			if not control.is_visible_in_tree():
				continue
			if control.mouse_filter == Control.MOUSE_FILTER_STOP and control.get_global_rect().has_point(canvas):
				return true
			if _gui_blocks(control, canvas):
				return true
	return false


func _attack(actor: CombatUnit, target: CombatUnit, action: String = "attack") -> bool:
	if not _can_act(actor) or not actions.can_target(actor, target, action):
		return false
	if selection.selected_action != action:
		await _use_button(action, actor)
		if selection.selected_action != action:
			field_click_failures.append("%s select %s failed" % [_stage_name(), action])
			return false
	var point: Variant = _unit_point(target)
	if point == null:
		field_click_failures.append("%s no body point %s" % [_stage_name(), target.get_display_name()])
		return false
	var before_action: int = actor.action_left
	var before_bonus: int = actor.bonus_action_left
	await _click_canvas(point)
	if selection.preview_target != target:
		field_click_failures.append("%s no preview %s" % [_stage_name(), target.get_display_name()])
		return false
	point = _unit_point(target)
	if point == null:
		return false
	await _click_canvas(point)
	await _settle()
	var ok: bool = actor.action_left < before_action or actor.bonus_action_left < before_bonus
	if not ok:
		field_click_failures.append("%s no execute %s" % [_stage_name(), action])
	return ok


func _move(actor: CombatUnit, cell: Vector2i) -> bool:
	if not _can_act(actor) or actor.cell == cell or not actions.can_move(actor, cell):
		return false
	var point: Variant = _cell_point(cell)
	if point == null:
		field_click_failures.append("%s no surface point %s" % [_stage_name(), cell])
		return false
	await _click_canvas(point, MOUSE_BUTTON_RIGHT)
	if selection.preview_cell != cell:
		field_click_failures.append("%s no move preview %s" % [_stage_name(), cell])
		return false
	var origin: Vector2i = actor.cell
	var before_movement: int = actor.movement_left
	var before_hp: int = actor.hit_points
	var path: Array[Vector2i] = actions.grid.path_to(actor, cell)
	var expected: Array[Vector2i] = [origin]
	expected.append_array(path)
	var visited: Array[Vector2i] = [origin]
	var observe: Callable = func() -> void:
		if is_instance_valid(actor) and actor.cell != visited.back():
			visited.append(actor.cell)
	actions.changed.connect(observe)
	await _click_canvas(point, MOUSE_BUTTON_RIGHT)
	await _settle()
	actions.changed.disconnect(observe)
	if not is_instance_valid(actor):
		movement_failures.append("%s moving actor freed" % _stage_name())
		return false
	var settled: bool = not actions.busy and not actor.is_moving and not battle.has_node("Arrow") and not hud.reaction_dialog.visible and actions.pending_reactor == null
	var arrived: bool = actor.cell == cell
	var interrupted: bool = actor.hit_points <= 0 or actions.is_over()
	var prefix_ok: bool = visited == expected.slice(0, visited.size())
	var spent: int = before_movement - actor.movement_left
	var cost_ok: bool = spent == visited.size() - 1
	var ok: bool = settled and prefix_ok and cost_ok and (arrived or interrupted)
	var outcome: String = "arrived" if arrived else ("interrupted_death" if actor.hit_points <= 0 else ("interrupted_battle_end" if actions.is_over() else "failed"))
	movement_records.append({"stage": _stage_name(), "round": turns.round_number, "actor": actor.get_display_name(),
		"from": str(origin), "target": str(cell), "actual": str(actor.cell), "expected_path": str(expected), "visited": str(visited),
		"hp_before": before_hp, "hp_after": actor.hit_points, "movement_before": before_movement, "movement_spent": spent,
		"settled": settled, "path_prefix_ok": prefix_ok, "cost_ok": cost_ok, "outcome": outcome, "passed": ok})
	if not ok:
		movement_failures.append("%s move %s -> %s actual=%s settled=%s prefix=%s cost=%s hp=%d" % [_stage_name(), origin, cell, actor.cell, settled, prefix_ok, cost_ok, actor.hit_points])
	return ok


# ---------------------------------------------------------------- policies

func _distance(a: CombatUnit, b: CombatUnit, from_cell: Vector2i = Vector2i(-1, -1)) -> int:
	var cell: Vector2i = from_cell if from_cell != Vector2i(-1, -1) else a.cell
	return actions.grid.nearest_distance(cell, [b] as Array[CombatUnit])


## nearest: the closest attackable enemy, ties to lower HP.
## mother: 엄마 거미 first, then the archer's marked target, then lowest HP.
func _best_target(actor: CombatUnit, from_cell: Vector2i = Vector2i(-1, -1), skip: Array = []) -> CombatUnit:
	var best: CombatUnit = null
	for enemy: CombatUnit in _enemies():
		if enemy in skip or not actions.can_target(actor, enemy, "attack", from_cell):
			continue
		if best == null:
			best = enemy
			continue
		if policy == "nearest":
			var d: int = _distance(actor, enemy, from_cell)
			var bd: int = _distance(actor, best, from_cell)
			if d < bd or (d == bd and enemy.hit_points < best.hit_points):
				best = enemy
			continue
		var spawner: bool = enemy.kind == CombatUnit.Kind.MOTHER_SPIDER
		var best_spawner: bool = best.kind == CombatUnit.Kind.MOTHER_SPIDER
		if spawner != best_spawner:
			if spawner:
				best = enemy
			continue
		var marked: bool = actor.marked_target == enemy
		var best_marked: bool = actor.marked_target == best
		if marked != best_marked:
			if marked:
				best = enemy
			continue
		if enemy.hit_points < best.hit_points:
			best = enemy
	return best


func _adjacent_enemies(cell: Vector2i) -> int:
	var count: int = 0
	for enemy: CombatUnit in _enemies():
		if actions.grid.are_adjacent(cell, enemy.cell) and not enemy.is_stunned:
			count += 1
	return count


func _choose_move(actor: CombatUnit) -> Variant:
	var reach: Dictionary = actions.reachable_cells(actor)
	var archer: bool = actor.kind == CombatUnit.Kind.ARCHER
	var mothers: Array[CombatUnit] = _enemies().filter(func(e: CombatUnit) -> bool: return e.kind == CombatUnit.Kind.MOTHER_SPIDER)
	var chase: Array[CombatUnit] = mothers if policy == "mother" and not mothers.is_empty() and not archer else _enemies()
	var best: Variant = null
	var best_score: float = -INF
	for cell: Vector2i in reach:
		if cell != actor.cell and _cell_point(cell) == null:
			var label: String = "%s %s" % [_stage_name(), cell]
			if label not in invisible_candidates:
				invisible_candidates.append(label)
			continue
		var score: float = -float(reach[cell])
		var target: CombatUnit = _best_target(actor, cell)
		if target != null:
			score += 1000.0
			if policy == "mother" and target.kind == CombatUnit.Kind.MOTHER_SPIDER:
				score += 500.0
			if archer:
				score += 20.0 * actions.grid.height_at(cell)
		else:
			score -= 10.0 * actions.grid.nearest_distance(cell, chase)
		if archer:
			score -= 300.0 * _adjacent_enemies(cell)
		if score > best_score:
			best_score = score
			best = cell
	return best


func _play_ally_turn(actor: CombatUnit) -> void:
	var start_round: int = turns.round_number
	if OS.has_environment("R278_DEBUG") and start_round in [25, 26]:
		var parts: Array[String] = []
		for e: CombatUnit in _enemies():
			parts.append("%s@%s h%d hp%d tgt=%s" % [e.get_display_name(), e.cell, actions.grid.height_at(e.cell), e.hit_points, actions.can_target(actor, e, "attack")])
		_p("DEBUG r%d %s@%s h%d act%d mov%d best=%s move=%s reach=%d enemies=%s" % [start_round, actor.get_display_name(), actor.cell, actions.grid.height_at(actor.cell), actor.action_left, actor.movement_left, _best_target(actor), _choose_move(actor), actions.reachable_cells(actor).size(), parts])
	var max_hp: int = actor.get_max_hit_points()
	if actor.hit_points * 2 < max_hp and actions.can_use(actor, "second_wind"):
		await _use_self(actor, "second_wind")
	if _can_act(actor) and actor.hit_points * 5 < max_hp * 2 and actions.can_use(actor, "potion"):
		await _use_self(actor, "potion")
	var archer: bool = actor.kind == CombatUnit.Kind.ARCHER
	if archer and _can_act(actor):
		var current_target: CombatUnit = _best_target(actor)
		if _adjacent_enemies(actor.cell) > 0 and actions.can_use(actor, "disengage"):
			await _use_self(actor, "disengage")
		elif actor.mark_left > 0 and actor.bonus_action_left > 0:
			var strongest: CombatUnit = null
			for enemy: CombatUnit in _enemies():
				if actions.can_target(actor, enemy, "mark") and (strongest == null or enemy.hit_points > strongest.hit_points):
					strongest = enemy
			if strongest != null and strongest.hit_points >= 10:
				await _attack(actor, strongest, "mark")
		if current_target == null or _adjacent_enemies(actor.cell) > 0:
			var cell: Variant = _choose_move(actor)
			if cell != null and cell != actor.cell:
				await _move(actor, cell)
	elif _can_act(actor) and _best_target(actor) == null:
		var cell: Variant = _choose_move(actor)
		if cell != null and cell != actor.cell:
			await _move(actor, cell)
	# Targets hidden behind a crowd cannot be clicked; like a player, try the next one.
	var hidden: Array = []
	for attempt: int in range(6):
		if not _can_act(actor) or actor.action_left <= 0:
			break
		var target: CombatUnit = _best_target(actor, Vector2i(-1, -1), hidden)
		if target == null:
			break
		if _unit_point(target) == null:
			hidden.append(target)
			continue
		var used: String = "attack"
		if archer and actor.shock_left > 0:
			var shock_target: CombatUnit = null
			for enemy: CombatUnit in _enemies():
				if not enemy.is_boss() and not enemy.is_stunned and actions.can_target(actor, enemy, "shock") and enemy.hit_points >= 6:
					if shock_target == null or enemy.hit_points > shock_target.hit_points:
						shock_target = enemy
			if shock_target != null:
				target = shock_target
				used = "shock"
		if not await _attack(actor, target, used):
			break
	if _can_act(actor) and actor.kind == CombatUnit.Kind.WARRIOR and actor.action_left == 0 and _best_target(actor) != null and actions.can_use(actor, "surge"):
		if await _use_self(actor, "surge"):
			var target2: CombatUnit = _best_target(actor)
			if target2 != null:
				await _attack(actor, target2)
	if _can_act(actor) and archer and _adjacent_enemies(actor.cell) > 0 and actor.disengaged and actor.movement_left > 0:
		var away: Variant = null
		var reach: Dictionary = actions.reachable_cells(actor)
		for cell: Vector2i in reach:
			if _adjacent_enemies(cell) == 0 and (away == null or int(reach[cell]) < int(reach[away])):
				away = cell
		if away != null:
			await _move(actor, away)
	await _settle()
	if _can_act(actor) and turns.current_unit == actor and turns.round_number == start_round:
		await _press(hud.get("end_button"), "end_turn")
		await _settle()


# ---------------------------------------------------------------- maintenance (layout A, #227)

func _item_score(item: Dictionary) -> int:
	var total: int = 0
	if item.is_empty():
		return 0
	for stat: String in item["stats"]:
		total += int(item["stats"][stat]) * (1 if stat == "max_hit_points" else 3)
	return total


func _find_named(node: Node, name: String) -> Node:
	for child: Node in node.get_children():
		if child.name == name and not child.is_queued_for_deletion():
			return child
		var found: Node = _find_named(child, name)
		if found != null:
			return found
	return null


func _select_cell(name: String) -> bool:
	var cell: Button = _find_named(preparation, name) as Button
	if cell == null:
		return false
	await _press(cell, "prep:select " + name)
	await _frames(2)
	return true


func _detail_button(name: String) -> Button:
	return _find_named(preparation.detail, name) as Button


## Gain for handing this item to this ally; 0 or less means keep it out of their hands.
func _gain(unit: CombatUnit, item: Dictionary) -> int:
	if not preparation.loot.can_receive(unit, item):
		return 0
	match str(item["kind"]):
		"weapon":
			return _item_score(item) - _item_score(unit.weapon)
		"armor":
			return _item_score(item) - _item_score(unit.armor)
		"potion":
			return 10 - unit.potion_left
	return 0


## Gives the cell's item to the ally with the largest gain. Returns true when something was given.
func _give_best(cell_name: String, item: Dictionary) -> bool:
	var best_ally: int = -1
	var best_gain: int = 0
	for ally: int in range(party.size()):
		var gain: int = _gain(party[ally], item)
		if gain > best_gain:
			best_gain = gain
			best_ally = ally
	if best_ally < 0:
		return false
	await _select_cell(cell_name)
	var button: Button = _detail_button("Ally%d" % best_ally)
	if button == null or button.disabled:
		return false
	await _press(button, "prep:give")
	await _frames(2)
	return true


func _handle_preparation() -> void:
	await _frames(3)
	if not preparation.maintaining:
		for item: Dictionary in preparation.rewards:
			rec["rewards"] = int(rec["rewards"]) + 1
			rec["rewards_" + str(item["kind"])] = int(rec["rewards_" + str(item["kind"])]) + 1
		await _press(preparation.continue_button, "prep:정비하기")
		await _frames(2)
		return
	# Rewards: equip upgrades, potions to whoever has fewer.
	var guard: int = 0
	var index: int = 0
	while index < preparation.rewards.size() and guard < 40:
		guard += 1
		if not await _give_best("Item%d" % index, preparation.rewards[index]):
			index += 1
	# Bag: equip upgrades and hand out stored potions.
	guard = 0
	index = 0
	while index < preparation.loot.bag.size() and guard < 40:
		guard += 1
		if not await _give_best("BagItem%d" % index, preparation.loot.bag[index]):
			index += 1
	for attempt: int in range(30):
		if not preparation.visible:
			break
		if preparation.discard_dialog.visible:
			await _press_dialog(preparation.discard_dialog, preparation.discard_dialog.get_ok_button(), "prep:ok")
			await _frames(2)
			continue
		if preparation.bag_notice.visible:
			# Bag full: discard the lowest-scoring equipment (potions last).
			var worst: int = -1
			for bag_index: int in range(preparation.loot.bag.size()):
				var item: Dictionary = preparation.loot.bag[bag_index]
				var score: int = 1000 if item["kind"] == "potion" else _item_score(item)
				if worst < 0 or score < (1000 if preparation.loot.bag[worst]["kind"] == "potion" else _item_score(preparation.loot.bag[worst])):
					worst = bag_index
			await _select_cell("BagItem%d" % worst)
			var discard: Button = _detail_button("DiscardItem")
			if discard != null:
				await _press(discard, "prep:discard")
				await _frames(2)
				if preparation.discard_dialog.visible:
					await _press_dialog(preparation.discard_dialog, preparation.discard_dialog.get_ok_button(), "prep:discard ok")
					await _frames(2)
					rec["discarded"] = int(rec["discarded"]) + 1
			continue
		await _press(preparation.continue_button, "prep:" + preparation.continue_button.text)
		await _frames(2)
	if preparation.visible:
		_finish(5, "preparation did not close")
		return
	_flush_attempt()


# ---------------------------------------------------------------- output

func _finish(code: int, reason: String) -> void:
	if _done:
		return
	_done = true
	if not movement_failures.is_empty():
		code = 7
		reason = "movement postcondition failure"
	_write_outputs(code, reason)
	_p("DONE code=%d %s wall=%.1fs game=%.1fs" % [code, reason, (Time.get_ticks_msec() - wall_t0) / 1000.0, frames / 60.0])
	# fixed-fps는 오디오 스레드보다 빨라 종료 전에 실제 시간으로 믹서 정리를 기다린다.
	(battle.get_node("HitSound") as AudioStreamPlayer).stop()
	var audio_deadline: int = Time.get_ticks_msec() + 500
	while Time.get_ticks_msec() < audio_deadline:
		await process_frame
	if actions.logged.is_connected(_on_log):
		actions.logged.disconnect(_on_log)
	current_scene.queue_free()
	await process_frame
	party.clear()
	_clear_references()
	await process_frame
	quit(code)


func _clear_references() -> void:
	actions = null
	turns = null
	selection = null
	preparation = null
	progress = null
	hud = null
	map = null
	battle = null


func _write_outputs(code: int, reason: String) -> void:
	if out_dir.is_empty():
		return
	DirAccess.make_dir_recursive_absolute(out_dir)
	var keys: Array = ["policy", "run", "stage", "attempt", "result", "rounds", "game_s",
		"warrior_hp", "warrior_max", "archer_hp", "archer_max", "downed", "start_potions", "potions_used",
		"potions_warrior", "potions_archer", "rewards", "rewards_weapon", "rewards_armor", "rewards_potion",
		"extra_eligible", "spawned", "enemy_time_s", "enemy_segment_max_s", "enemy_segments",
		"ally_attacks", "ally_misses", "ally_streak_max", "enemy_attacks", "enemy_misses", "enemy_streak_max",
		"bag_end", "discarded"]
	var lines: Array[String] = [",".join(keys)]
	for row: Dictionary in rows:
		var values: Array[String] = []
		for key: String in keys:
			var value: Variant = row.get(key, "")
			values.append("%.3f" % value if value is float else str(value))
		lines.append(",".join(values))
	_store("attempts.csv", "\n".join(lines) + "\n")
	_store("streaks.csv", "policy,run,stage,attempt,side,length\n" + "\n".join(streak_rows) + ("\n" if not streak_rows.is_empty() else ""))
	_store("enemy_segments.csv", "policy,run,stage,attempt,round,seconds\n" + "\n".join(segment_rows) + ("\n" if not segment_rows.is_empty() else ""))
	_store("run.json", JSON.stringify({"policy": policy, "run": run_id, "exit_code": code, "reason": reason,
		"action_seed_base": run_id * 100000, "initiative_seed_base": run_id * 100000 + 50000,
		"wall_s": (Time.get_ticks_msec() - wall_t0) / 1000.0, "game_s": frames / 60.0,
		"pointer_fallbacks": pointer_fallbacks, "field_click_failures": field_click_failures, "invisible_candidates": invisible_candidates, "movement_records": movement_records, "movement_failures": movement_failures}, "  "))


func _store(name: String, text: String) -> void:
	var file: FileAccess = FileAccess.open(out_dir.path_join(name), FileAccess.WRITE)
	file.store_string(text)
	file.close()
