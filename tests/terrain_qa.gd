extends SceneTree
## #347 반복 검수. 원래 지형·로스터에서 아군 차례/조작 위치만 통제하며 자연 진행·OS 입력과 구분한다.
const ScriptedDice = preload("res://tests/scripted_dice.gd")
var output: String
var preflight: bool
var checks: int = 0
var failures: int = 0
var game: Node
var battle: Node
var records: Array[Dictionary] = []

func _initialize() -> void:
	_run.call_deferred()

func ck(ok: bool, message: String) -> bool:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)
	return ok

func _run() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--capture-dir="):
			output = arg.trim_prefix("--capture-dir=")
	preflight = "--fixture-precheck" in OS.get_cmdline_user_args()
	assert(not output.is_empty())
	DirAccess.make_dir_recursive_absolute(output)
	GameSave.autosave = false
	GameSave.path = output.path_join("unused-save.bin")
	GameSettings.path = output.path_join("unused-settings.cfg")
	game = load("res://scenes/game.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	battle = game.get_node("Battle")
	battle.set_process(false)
	for index: int in range(9):
		(battle.get("progress") as CombatActProgress).stage_index = index
		battle.call("_start_stage", true)
		battle.call("start_battle")
		var units: Array[CombatUnit] = battle.get("units")
		var party: Array[CombatUnit] = battle.get("party")
		var actor: CombatUnit = party[0]
		var actions: CombatActions = battle.get("actions")
		var map: CombatMap = battle.get("map")
		var selection: CombatSelection = battle.get("selection")
		ScriptedDice.arrange_turns(battle.get("turns"), units, party)
		battle.call("_update_turn_ui")
		await _settle()
		if not ck(units.size() >= 3 and (battle.get("turns") as CombatTurns).current_unit == actor
			and actions.grid.props.size() == 2 and actor.action_left == 1, "실제 로스터·아군 턴·물체2개·행동1"):
			break
		var label: String = "%d-%d" % [index / 3 + 1, index % 3 + 1]
		var row: Dictionary = {"stage": label, "window": str(root.size), "viewport": str(root.get_visible_rect()),
			"crate": str(actions.grid.props[0].cell), "rock": str(actions.grid.props[1].cell)}
		records.append(row)
		await _capture(label + "-initial")
		var destination: Vector2i = Vector2i(2, 4)
		if not ck(actions.reachable_cells(actor).has(destination), "입력 전 실제 이동 가능 칸 확인"):
			break
		await _click(map.get_global_transform_with_canvas() * map.map_to_surface(destination), MOUSE_BUTTON_RIGHT)
		if not ck(selection.selected_action == "move" and not selection.preview_path.is_empty()
			and actor.cell == Vector2i(1, 4) and actor.movement_left == 6, "우클릭은 이동 범위·경로 미리보기만 표시"):
			break
		await _capture(label + "-movement")
		if index <= 1:
			var prop: CombatGrid.Prop = actions.grid.props[index]
			var stand: Vector2i = prop.cell + Vector2i.LEFT
			if not ck(not actions.grid.path_to(actor, stand).is_empty(), "통제 공격 위치에 실제 보행 경로 존재"):
				break
			actor.cell = stand
			selection.reset()
			battle.call("_update_turn_ui")
			await _settle()
			if not ck(actions.can_attack_prop(actor, prop), "현재 행동·거리·높이로 물체 공격 가능"):
				break
			var point: Vector2 = _prop_point(map, prop, units)
			if not ck(point != Vector2.INF, "유닛에 가리지 않은 실제 물체 몸통 입력점"):
				break
			var sides: int = ScriptedDice.damage_sides(actor)[0]
			if index == 0:
				if not ck(sides > 0 and sides + actor.get_damage_bonus() >= prop.hit_points,
					"상자 공격은 명중 굴림 없이 피해 능력치 주사위1회로 파괴 가능한 fixture"):
					break
				actions.dice = ScriptedDice.new([sides], [sides])
			else:
				actions.dice = ScriptedDice.new([])
			var before: int = units[2].hit_points
			await _click(point)
			if not ck(selection.preview_prop == prop and actor.action_left == 1, "몸통 첫 클릭은 비용 없는 물체 미리보기"):
				break
			await _capture(label + "-prop-preview")
			await _click(point)
			if not ck(actor.action_left == 0 and (prop not in actions.grid.props if index == 0
				else units[2].hit_points == before - 4), "재클릭으로 상자 파괴/기존 바위 충돌4피해 실행"):
				break
			row["interaction"] = "crate destroyed" if index == 0 else "rock damage4"
			await _capture(label + "-prop-after")
		if not ck(ScriptedDice.finish().is_empty(), "주사위 면수·순서·미소비 확인"):
			break
	var file: FileAccess = FileAccess.open(output.path_join("measurements.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks": checks, "failures": failures, "stages": records}, "\t"))
	print("[TERRAIN_FIXTURE_READY]" if preflight and failures == 0 else "[TERRAIN_DONE] %d checks, %d failures;" % [checks, failures])
	game.queue_free()
	await process_frame
	quit(0 if failures == 0 else 1)

func _settle() -> void:
	for frame: int in range(3):
		await process_frame

func _click(point: Vector2, button: MouseButton = MOUSE_BUTTON_LEFT) -> void:
	var event: InputEventMouseButton = InputEventMouseButton.new()
	event.position = root.get_final_transform() * point
	event.global_position = event.position
	event.button_index = button
	event.pressed = true
	Input.parse_input_event(event)
	await _settle()
	event.pressed = false
	Input.parse_input_event(event)
	for frame: int in range(240):
		await process_frame
		if not (battle.get("actions") as CombatActions).busy:
			return
	ck(false, "입력 후 동작 종료 제한 시간")

func _prop_point(map: CombatMap, prop: CombatGrid.Prop, units: Array[CombatUnit]) -> Vector2:
	var center: Vector2 = map.map_to_surface(prop.cell)
	for y: int in range(-24, 1):
		for x: int in range(-12, 13):
			var point: Vector2 = center + Vector2(x, y)
			if map.prop_at_point(point) == prop and not units.any(func(unit: CombatUnit) -> bool:
				return unit.hit_points > 0 and unit.contains_body_point(unit.to_local(map.to_global(point)))):
				return map.get_global_transform_with_canvas() * point
	return Vector2.INF

func _capture(label: String) -> void:
	if preflight:
		return
	await RenderingServer.frame_post_draw
	ck(root.get_texture().get_image().save_png(output.path_join(label + ".png")) == OK, "원본 PNG 저장")
