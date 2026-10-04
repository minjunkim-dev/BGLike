extends Node2D
## M1 동작과 전투 화면. 적 AI는 이후 단계에서 연결한다.

const MAP_SIZE: Vector2i = Vector2i(10, 10)

var units: Array[CombatUnit] = []
var turns: CombatTurns = CombatTurns.new()
var actions: CombatActions = CombatActions.new()
var preview_target: CombatUnit
var selected_action: String = "attack"
var preview_cell: Vector2i = Vector2i(-1, -1)
var preview_path: Array[Vector2i] = []
var movement_cells: Array[Vector2i] = []
var _last_ally: CombatUnit

@onready var map: TileMapLayer = $Map
@onready var camera: Camera2D = $Camera
@onready var hud: CombatTurnHud = $UI/TurnHud


func _ready() -> void:
	for x: int in range(MAP_SIZE.x):
		for y: int in range(MAP_SIZE.y):
			map.set_cell(Vector2i(x, y), 0, Vector2i((x + y) % 2, 0))

	# Units의 자식은 모두 CombatUnit 장면이다.
	for child: Node in $Units.get_children():
		var unit: CombatUnit = child as CombatUnit
		units.append(unit)
		unit.position = map.map_to_local(unit.cell)

	# 고정 카메라. 창이 넓어져도 격자는 화면 가운데에 남는다.
	camera.position = (map.map_to_local(Vector2i.ZERO)
		+ map.map_to_local(MAP_SIZE - Vector2i.ONE)) / 2.0

	hud.unit_selected.connect(_on_unit_selected)
	hud.end_turn_requested.connect(_end_turn)
	hud.action_selected.connect(_on_action_selected)
	hud.reaction_selected.connect(actions.resolve_reaction)
	hud.restart_requested.connect(_restart)
	actions.initialize(units, turns)
	actions.changed.connect(_update_turn_ui)
	actions.logged.connect(hud.add_log)
	actions.feedback.connect(func(unit: CombatUnit, text: String) -> void: unit.show_feedback(text))
	actions.reaction_requested.connect(hud.show_reaction)
	turns.changed.connect(_on_turn_changed)
	var dice: RandomNumberGenerator = RandomNumberGenerator.new()
	dice.randomize()
	_last_ally = units[0]
	turns.start(units, dice)
	for unit: CombatUnit in turns.ordered_units:
		hud.add_log("이니셔티브 %s: d20 %d + %d = %d" % [
			unit.get_display_name(), unit.initiative_roll, unit.get_dexterity(), unit.get_initiative()])


func _restart() -> void:
	if actions.is_over() and not actions.busy:
		get_tree().reload_current_scene()


func _on_unit_selected(unit: CombatUnit) -> void:
	if not actions.busy and not actions.is_over():
		turns.select_unit(unit)


func _end_turn() -> void:
	if not actions.busy and not actions.is_over():
		turns.end_turn()


func _on_action_selected(action: String) -> void:
	var actor: CombatUnit = turns.current_unit
	if actor == null or not actor.is_ally or not actions.can_use(actor, action):
		return
	if action == selected_action and action in ["second_wind", "surge", "disengage", "potion"]:
		_clear_preview()
		actions.use_self(actor, action)
		selected_action = "attack"
	else:
		selected_action = action
		_clear_preview()
	_update_turn_ui()


func _unhandled_input(event: InputEvent) -> void:
	if (event is not InputEventMouseButton or not event.pressed
		or event.button_index != MOUSE_BUTTON_LEFT):
		return
	if actions.busy or actions.is_over():
		return
	var world_position: Vector2 = get_canvas_transform().affine_inverse() * event.position
	var cell: Vector2i = map.local_to_map(map.to_local(world_position))
	var actor: CombatUnit = turns.current_unit
	# 이동 버튼을 고른 경우에는 몸통에 가려진 빈 칸도 먼저 선택한다.
	if selected_action == "move" and actor != null and actor.is_ally and actions.can_move(actor, cell):
		get_viewport().set_input_as_handled()
		await _select_move_cell(cell)
		return
	var candidates: Array[CombatUnit] = []
	for unit: CombatUnit in units:
		if unit.hit_points > 0 and Rect2(-7, -20, 14, 22).has_point(unit.to_local(world_position)):
			candidates.append(unit)
	candidates.sort_custom(func(a: CombatUnit, b: CombatUnit) -> bool:
		if a.position.y != b.position.y:
			return a.position.y > b.position.y
		return a.get_index() > b.get_index()
	)
	if not candidates.is_empty():
		var unit: CombatUnit = candidates[0]
		get_viewport().set_input_as_handled()
		if unit == preview_target and actions.can_target(turns.current_unit, unit, selected_action):
			await _execute_target(unit)
		elif not preview_enemy(unit):
			_clear_preview()
			_update_turn_ui()
		return
	await _select_move_cell(cell)


func _select_move_cell(cell: Vector2i) -> void:
	var actor: CombatUnit = turns.current_unit
	if actor != null and actor.is_ally and actions.can_move(actor, cell):
		if cell == preview_cell:
			_clear_preview()
			if await actions.move_to(actor, cell):
				selected_action = "attack"
		else:
			_clear_preview()
			preview_cell = cell
			preview_path = actions.path_to(actor, cell)
	else:
		_clear_preview()
	_update_turn_ui()


func preview_enemy(target: CombatUnit) -> bool:
	if (turns.current_unit == null or not turns.current_unit.is_ally
		or target not in units or target.is_ally or target.hit_points <= 0):
		return false
	_clear_preview()
	preview_target = target
	_update_turn_ui()
	return true


func _on_turn_changed() -> void:
	_clear_preview()
	selected_action = "attack"
	_update_turn_ui()


func _clear_preview() -> void:
	preview_target = null
	preview_cell = Vector2i(-1, -1)
	preview_path.clear()
	queue_redraw()


func _execute_target(target: CombatUnit) -> void:
	var actor: CombatUnit = turns.current_unit
	var action: String = selected_action
	_clear_preview()
	match action:
		"attack", "shock":
			await actions.attack(actor, target, action == "shock")
		"mark":
			actions.mark(actor, target)
		"shove":
			actions.shove(actor, target)
	selected_action = "attack"
	_update_turn_ui()


func _update_turn_ui() -> void:
	for unit: CombatUnit in units:
		unit.has_mark = false
		for source: CombatUnit in units:
			if source.hit_points > 0 and source.marked_target == unit:
				unit.has_mark = true
				break
		unit.position = map.map_to_local(unit.cell)
		unit.visible = unit.hit_points > 0
		unit.is_selected = unit == turns.current_unit
		unit.is_previewed = unit == preview_target or (not preview_path.is_empty()
			and actions.can_target(turns.current_unit, unit, "attack", preview_cell))
		unit.queue_redraw()
	if turns.current_unit != null and turns.current_unit.is_ally:
		_last_ally = turns.current_unit
	var can_act: bool = actions.has_available_action(turns.current_unit)
	hud.refresh(turns, can_act)
	hud.refresh_actions(actions, selected_action, _last_ally)
	movement_cells.clear()
	if selected_action == "move":
		for x: int in range(MAP_SIZE.x):
			for y: int in range(MAP_SIZE.y):
				var cell: Vector2i = Vector2i(x, y)
				if turns.current_unit != null and turns.current_unit.is_ally and actions.can_move(turns.current_unit, cell):
					movement_cells.append(cell)
	if preview_target != null:
		var preview: CombatChecks.AttackPreview = CombatChecks.attack_preview(
			turns.current_unit, preview_target, units)
		hud.show_attack_preview(preview_target, preview)
		if selected_action == "mark":
			hud.preview_label.text = "표식 대상" if actions.can_target(turns.current_unit, preview_target, "mark") else "표식을 사용할 수 없음"
		elif selected_action == "shove":
			if actions.can_target(turns.current_unit, preview_target, "shove"):
				var cell: Vector2i = actions.shove_destination(turns.current_unit, preview_target)
				hud.preview_label.text = "밀려날 칸: %d, %d" % [cell.x, cell.y]
			else:
				hud.preview_label.text = "밀치기를 사용할 수 없음"
		elif selected_action == "move":
			hud.preview_label.text = "유닛이 있는 칸은 이동할 수 없음"
	elif not preview_path.is_empty():
		var actor: CombatUnit = turns.current_unit
		var targets: int = _attack_targets_from(preview_cell).size()
		var attack_text: String = "도착 시 공격 가능: %d명" % targets
		if actor.action_left == 0:
			attack_text = "도착 시 공격 불가: 행동을 이미 씀"
		elif targets == 0:
			attack_text = "도착 시 공격 불가: 사거리 안 적 없음"
		hud.preview_label.text = "이동 %d칸 → %d칸 남음\n%s\n같은 칸을 다시 눌러 이동" % [
			preview_path.size(), actor.movement_left - preview_path.size(), attack_text]
	# 이동 정보는 왼쪽 설명 패널에 모아 격자 오른쪽을 가리지 않는다.
	var showing_move: bool = selected_action == "move" or not preview_path.is_empty()
	hud.preview_label.visible = not showing_move
	if showing_move and not hud.preview_label.text.is_empty():
		hud.help_title.text = "이동 미리보기"
		hud.help_label.text = hud.preview_label.text + "\n\n행동 소비 없음.\n" + hud.movement_caution(turns.current_unit)
	if actions.is_over():
		hud.round_label.text = "승리" if _all_enemies_down() else "패배"
		hud.show_result(_all_enemies_down())
	queue_redraw()


func _all_enemies_down() -> bool:
	for unit: CombatUnit in units:
		if not unit.is_ally and unit.hit_points > 0:
			return false
	return true


func _draw() -> void:
	for cell: Vector2i in movement_cells:
		var center: Vector2 = map.map_to_local(cell)
		var color: Color = Color(0.22, 0.56, 0.92, 0.4)
		if not _attack_targets_from(cell).is_empty():
			color = Color(0.22, 0.8, 0.5, 0.45)
		draw_colored_polygon(PackedVector2Array([center + Vector2(-14, 0),
			center + Vector2(0, -7), center + Vector2(14, 0), center + Vector2(0, 7)]), color)
	if preview_path.is_empty():
		return
	var points: PackedVector2Array = [map.map_to_local(turns.current_unit.cell)]
	for cell: Vector2i in preview_path:
		points.append(map.map_to_local(cell))
	draw_polyline(points, Color("f4cf69"), 1.0)
	draw_circle(points[-1], 3.0, Color("f4cf69"), false)


func _attack_targets_from(cell: Vector2i) -> Array[CombatUnit]:
	var targets: Array[CombatUnit] = []
	for unit: CombatUnit in units:
		if actions.can_target(turns.current_unit, unit, "attack", cell):
			targets.append(unit)
	return targets
