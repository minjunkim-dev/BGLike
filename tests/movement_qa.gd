extends SceneTree
## #336: PCK 이동 후조건의 통제 사례. 자연 플레이·밸런스·화면 확인의 근거는 아니다.
const ScriptedDice = preload("scripted_dice.gd")

var out_dir: String
var battle: Node2D
var hud: Control
var actions: CombatActions
var turns: CombatTurns
var selection: CombatSelection
var map: CombatMap
var field_click_failures: Array[String] = []
var movement_records: Array[Dictionary] = []
var movement_failures: Array[String] = []

var checks: int = 0
var failures: int = 0
var fixture_results: Array[Dictionary] = []
var drop_confirm: bool = false
var right_clicks: int = 0


func _initialize() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			out_dir = arg.trim_prefix("--out=")
	assert(not out_dir.is_empty())
	_run.call_deferred()

func _stage_name() -> String:
	return "1-1"

func _check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)

func _run() -> void:
	GameSave.autosave = false
	GameSave.path = "user://movement-fixtures/save.bin"
	GameSettings.path = "user://movement-fixtures/settings.cfg"
	for case: String in ["multi_step", "opportunity_miss", "opportunity_incapacitated", "battle_end", "dropped_confirm"]:
		var scene: PackedScene = load("res://scenes/combat/battle.tscn")
		battle = scene.instantiate()
		battle.stages[0] = load("res://scenes/combat/stage.tres")
		root.add_child(battle)
		current_scene = battle
		battle.set_process(false)
		await _frames(2)
		hud = battle.get_node("UI/TurnHud")
		actions = battle.get("actions")
		turns = battle.get("turns")
		selection = battle.get("selection")
		map = battle.get_node("Map")
		var units: Array[CombatUnit] = battle.get("units")
		_check(units.size() == 4, "fixture has two allies and two enemies")
		if units.size() != 4:
			quit(1)
			return
		for i: int in range(4):
			units[i].cell = [Vector2i(0, 0), Vector2i(0, 9), Vector2i(9, 0), Vector2i(9, 9)][i]
			units[i].hit_points = units[i].get_max_hit_points()
			units[i].parry_left = 0
		var reaction_case: bool = case.begins_with("opportunity")
		var actor: CombatUnit = units[1] if reaction_case else units[0]
		actor.cell = Vector2i(5, 4) if reaction_case else Vector2i(1, 4)
		var target: Vector2i = Vector2i(6, 4) if reaction_case else Vector2i(1, 6)
		if case == "battle_end":
			target = Vector2i(1, 7)
		if reaction_case:
			units[2].cell = Vector2i(4, 4)
			_check(units[2].kind == CombatUnit.Kind.WARRIOR and not units[2].is_ally, "enemy warrior fixture")
		ScriptedDice.arrange_turns(turns, units, [actor])
		# 적 전사 STR d10 / 아군 궁수 STR d8, 적 기본 공격 피해 d4.
		if case == "opportunity_incapacitated":
			actor.hit_points = 1
			actions.dice = ScriptedDice.new([10, 1, 1], [10, 8, 4])
		elif case == "opportunity_miss":
			actions.dice = ScriptedDice.new([1, 8], [10, 8])
		elif case == "battle_end":
			# 전투 종료는 보상 d7 1회와 추가 드랍 확률 2회까지 실행한다.
			actions.dice = ScriptedDice.new([7], [7], [0.99, 0.99])
		else:
			actions.dice = ScriptedDice.new([], [])
		battle.call("_update_turn_ui")
		await _frames(2)
		_check(_can_act(actor) and actions.can_move(actor, target), "%s movement precondition" % case)
		movement_records.clear()
		movement_failures.clear()
		field_click_failures.clear()
		drop_confirm = case == "dropped_confirm"
		right_clicks = 0
		var before: Vector2i = actor.cell
		var finish_battle: Callable = Callable()
		if case == "battle_end":
			# 신호 처리 중 전투가 끝나는 재진입 경계만 통제한다. 자연 진행 통계가 아니다.
			var ended: Array[bool] = [false]
			finish_battle = func() -> void:
				if not ended[0] and actor.cell == Vector2i(1, 5):
					ended[0] = true
					for enemy: CombatUnit in units.duplicate():
						if not enemy.is_ally and enemy.hit_points > 0:
							enemy.hit_points = 0
							actions.incapacitate(enemy)
			actions.changed.connect(finish_battle)
		var ok: bool = await _move(actor, target)
		if finish_battle.is_valid():
			actions.changed.disconnect(finish_battle)
		_check(right_clicks == 2, "%s first preview then confirmation attempted" % case)
		_check(movement_records.size() == 1, "%s exactly one postcondition record" % case)
		if movement_records.size() == 1:
			var record: Dictionary = movement_records[0]
			fixture_results.append({"case": case, "expected_pass": not drop_confirm, "returned": ok, "record": record.duplicate(true), "movement_failures": movement_failures.duplicate()})
			if drop_confirm:
				_check(not ok and not record.passed and record.outcome == "failed" and movement_failures.size() == 1, "oracle rejects a missing confirmation")
				_check(actor.cell == before and actor.movement_left == 6 and not actions.busy, "negative probe preserves original cell/resources")
			elif case == "battle_end":
				_check(ok and record.passed and record.outcome == "interrupted_battle_end" and movement_failures.is_empty(), "battle end is a classified interruption")
				_check(actor.hit_points > 0 and actor.cell == Vector2i(1, 5) and actor.movement_left == 5 and actions.is_over(), "battle end stops after first paid step while actor is alive")
			elif case == "opportunity_incapacitated":
				_check(ok and record.passed and record.outcome == "interrupted_incapacitated" and movement_failures.is_empty(), "lethal opportunity is a classified interruption")
				_check(actor.hit_points == 0 and actor.cell == before and actor.movement_left == 6 and units[2].reaction_left == 0, "death stops before leaving and consumes enemy reaction")
			else:
				_check(ok and record.passed and record.outcome == "arrived" and movement_failures.is_empty(), "%s arrival verified" % case)
				_check(actor.cell == target and actor.movement_left == (5 if reaction_case else 4), "%s arrival and path cost" % case)
				if reaction_case:
					_check(actor.hit_points == actor.get_max_hit_points() and units[2].reaction_left == 0, "missed opportunity continues without damage")
		_check(field_click_failures.is_empty(), "%s preview input succeeded" % case)
		var dice_problems: Array[String] = ScriptedDice.finish()
		if not fixture_results.is_empty():
			fixture_results.back()["dice_problems"] = dice_problems
		_check(dice_problems.is_empty(), "%s exact dice consumed: %s" % [case, dice_problems])
		await _free_fixture()
	_store("fixtures.json", JSON.stringify({"checks": checks, "failures": failures, "cases": fixture_results}, "  "))
	print("[MOVEMENT_FIXTURES] %d checks, %d failures;" % [checks, failures])
	quit(0 if failures == 0 else 1)

func _free_fixture() -> void:
	(battle.get_node("HitSound") as AudioStreamPlayer).stop()
	var deadline: int = Time.get_ticks_msec() + 150
	while Time.get_ticks_msec() < deadline:
		await process_frame
	battle.queue_free()
	await _frames(2)
	_clear_references()


func _frames(count: int) -> void:
	for index: int in range(count):
		await process_frame


func _answer_reaction() -> void:
	# Policy: always accept opportunity attacks and parry when offered.
	await _frames(2)
	if hud.reaction_dialog.visible:
		hud.reaction_dialog.get_ok_button().pressed.emit()
	await _frames(2)




func _click_canvas(point: Vector2, button_index: MouseButton = MOUSE_BUTTON_LEFT) -> void:
	if button_index == MOUSE_BUTTON_RIGHT:
		right_clicks += 1
		if drop_confirm and right_clicks == 2:
			await _frames(3)
			return
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


func _settle() -> void:
	for frame: int in range(60 * 30):
		if hud.reaction_dialog.visible:
			await _answer_reaction()
			continue
		var moving: bool = false
		for unit: CombatUnit in actions.units:
			moving = moving or (is_instance_valid(unit) and unit.is_moving)
		if not moving and not battle.has_node("Arrow") and not actions.busy:
			await process_frame
			return
		await process_frame


func _can_act(actor: CombatUnit) -> bool:
	return (turns.current_unit == actor and actor.hit_points > 0 and not actions.is_over()
		and not hud.get_node("Result").visible)


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
	var outcome: String = "arrived" if arrived else ("interrupted_incapacitated" if actor.hit_points <= 0 else ("interrupted_battle_end" if actions.is_over() else "failed"))
	movement_records.append({"stage": _stage_name(), "round": turns.round_number, "actor": actor.get_display_name(),
		"from": str(origin), "target": str(cell), "actual": str(actor.cell), "expected_path": str(expected), "visited": str(visited),
		"hp_before": before_hp, "hp_after": actor.hit_points, "movement_before": before_movement, "movement_spent": spent,
		"settled": settled, "path_prefix_ok": prefix_ok, "cost_ok": cost_ok, "outcome": outcome, "passed": ok})
	if not ok:
		movement_failures.append("%s move %s -> %s actual=%s settled=%s prefix=%s cost=%s hp=%d" % [_stage_name(), origin, cell, actor.cell, settled, prefix_ok, cost_ok, actor.hit_points])
	return ok




func _clear_references() -> void:
	actions = null
	turns = null
	selection = null
	hud = null
	map = null
	battle = null


func _store(name: String, text: String) -> void:
	var file: FileAccess = FileAccess.open(out_dir.path_join(name), FileAccess.WRITE)
	file.store_string(text)
	file.close()
