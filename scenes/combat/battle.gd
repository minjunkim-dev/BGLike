extends Node2D
## 전투 화면과 3막 진행. 적 묶음은 이니셔티브 순서대로 실행한다.

const MOVE_STEP_TIME: float = 0.09
const ARROW_FLIGHT_TIME: float = 0.16

@export var stages: Array[CombatStage] = []

var progress: CombatActProgress
var map_size: Vector2i
var party: Array[CombatUnit] = []

var units: Array[CombatUnit] = []
var turns: CombatTurns = CombatTurns.new()
var actions: CombatActions = CombatActions.new()
var enemy_ai: CombatEnemyAi = CombatEnemyAi.new()
var _enemy_turn_running: bool = false
var selection: CombatSelection = CombatSelection.new()
var movement_cells: Array[Vector2i] = []
var _last_ally: CombatUnit
var loot: CombatLoot = CombatLoot.new()
var preparation: CombatPreparation

@onready var map: CombatMap = $Map
@onready var camera: Camera2D = $Camera
@onready var hud: CombatTurnHud = $UI/TurnHud


func _ready() -> void:
	assert(stages.size() == 9, "전투 진행에는 스테이지 데이터9개가 필요합니다.")
	progress = CombatActProgress.new(stages.size())
	# 파티 노드를 유지해 같은 막의 HP와 스킬 횟수를 이어 간다.
	for child: Node in $Units.get_children():
		party.append(child as CombatUnit)
	preparation = CombatPreparation.new()
	preparation.name = "Preparation"
	$UI.add_child(preparation)
	preparation.finished.connect(_finish_preparation)

	hud.unit_selected.connect(_on_unit_selected)
	hud.end_turn_requested.connect(_end_turn)
	hud.action_selected.connect(_on_action_selected)
	hud.reaction_selected.connect(actions.resolve_reaction)
	hud.restart_requested.connect(_restart)
	actions.changed.connect(_on_actions_changed)
	actions.logged.connect(hud.add_log)
	actions.feedback.connect(func(unit: CombatUnit, text: String) -> void:
		unit.show_feedback(text, hud.feedback_obstacles()))
	actions.hit_landed.connect($HitSound.play)
	actions.reaction_requested.connect(hud.show_reaction)
	actions.movement_animation = _animate_movement
	actions.attack_animation = _animate_attack
	turns.changed.connect(_on_turn_changed)
	turns.order_rotated.connect(hud.prepare_order_rotation)
	_start_stage(true)


func _exit_tree() -> void:
	actions.movement_animation = Callable()
	actions.attack_animation = Callable()


func _start_stage(restore_act: bool) -> void:
	progress.begin_stage()
	var stage: CombatStage = stages[progress.stage_index]
	assert(stage != null, "스테이지 데이터가 비어 있습니다: %d" % (progress.stage_index + 1))
	assert(stage.ally_cells.size() == party.size(),
		"아군 시작 칸 수가 파티 크기와 다릅니다: " + stage.resource_path)
	for unit: CombatUnit in party:
		unit.begin_stage(restore_act)
	for unit: CombatUnit in units:
		if not unit.is_ally:
			unit.free()
	for child: Node in $Units.get_children():
		if child is Label:
			child.free()
	units = party.duplicate()
	map_size = stage.map_size
	actions.grid.map_size = map_size
	actions.grid.heights = stage.heights.duplicate()
	map.build_grid(actions.grid, stage.tile_set)
	for index: int in range(party.size()):
		party[index].cell = stage.ally_cells[index]
		party[index].facing_left = false
	var enemies: Node = stage.enemies.instantiate()
	for child: Node in enemies.get_children():
		(child as CombatUnit).act_number = progress.act_number()
	$Units.add_child(enemies)
	for child: Node in enemies.get_children():
		var unit: CombatUnit = child as CombatUnit
		unit.reparent($Units, false)
		units.append(unit)
	enemies.free()
	camera.position = (map.map_to_local(Vector2i.ZERO)
		+ map.map_to_local(map_size - Vector2i.ONE)) / 2.0
	selection.reset()
	hud.begin_stage(progress.act_number(), progress.stage_in_act())
	actions.initialize(units, turns)
	var dice: CombatDice = CombatDice.new()
	dice.randomize()
	var living: Array[CombatUnit] = []
	for unit: CombatUnit in units:
		if unit.hit_points > 0:
			living.append(unit)
	_last_ally = living[0]
	turns.start(living, dice)


func _restart() -> void:
	if not actions.is_over() or actions.busy or _enemy_turn_running:
		return
	if actions.is_victory():
		if progress.graduated or preparation.visible:
			return
		preparation.open_rewards(loot, party, progress.rewards, progress.is_final_stage(),
			progress.is_last_in_act())
		hud.hide_result()
		return
	progress.restart_act()
	_start_stage(progress.starts_act())


func _finish_preparation() -> void:
	if not actions.is_over() or actions.busy or _enemy_turn_running or not actions.is_victory():
		return
	progress.advance()
	if progress.graduated:
		_update_turn_ui()
		return
	_start_stage(progress.starts_act())


func _process(_delta: float) -> void:
	var actor: CombatUnit = turns.current_unit
	if (actor != null and not actor.is_ally and not actions.busy
		and not actions.is_over() and not _enemy_turn_running):
		_play_enemy_turn(actor)


func _play_enemy_turn(actor: CombatUnit) -> void:
	_enemy_turn_running = true
	await _pause_enemy_action()
	await enemy_ai.play_turn(actor, actions, _pause_enemy_action)
	if not actions.is_over() and turns.current_unit == actor:
		turns.end_turn()
	_enemy_turn_running = false
	_update_turn_ui()


func _pause_enemy_action() -> void:
	if actions.is_over():
		return
	await get_tree().create_timer(0.35).timeout


func _on_unit_selected(unit: CombatUnit) -> void:
	if actions.busy or actions.is_over() or unit not in units or unit.hit_points <= 0:
		return
	selection.clear_preview()
	# 조작 가능한 아군만 전환한다. 다른 초상은 정보만 표시한다.
	turns.select_unit(unit)
	selection.inspect(unit)
	_update_turn_ui()


func _end_turn() -> void:
	if (turns.current_unit != null and turns.current_unit.is_ally
		and not actions.busy and not actions.is_over()):
		turns.end_turn()


func _on_action_selected(action: String) -> void:
	var actor: CombatUnit = turns.current_unit
	if actor == null or not actor.is_ally or not actions.can_use(actor, action):
		return
	if selection.select_action(action):
		actions.use_self(actor, action)
		selection.finish_execution()
	_update_turn_ui()


func _input(event: InputEvent) -> void:
	if event is not InputEventKey or event.keycode != KEY_TAB or preparation.visible:
		return
	# GUI보다 먼저 소비해 전투 중 기본 Tab 포커스 이동을 막는다.
	get_viewport().set_input_as_handled()
	if (not event.pressed or event.echo or actions.busy or actions.is_over()
		or hud.reaction_dialog.visible or hud.get_node("Result").visible):
		return
	var actor: CombatUnit = turns.current_unit
	if actor == null or not actor.is_ally:
		return
	var group: Array[CombatUnit] = turns.get_current_group()
	var index: int = group.find(actor)
	var direction: int = -1 if event.shift_pressed else 1
	for step: int in range(1, group.size() + 1):
		var unit: CombatUnit = group[wrapi(index + step * direction, 0, group.size())]
		if turns.select_unit(unit):
			selection.inspect(unit)
			_update_turn_ui()
			return


func _unhandled_input(event: InputEvent) -> void:
	if (event is not InputEventMouseButton or not event.pressed
		or event.button_index not in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT]):
		return
	if actions.busy or actions.is_over():
		return
	var world_position: Vector2 = get_canvas_transform().affine_inverse() * event.position
	var cell: Vector2i = map.surface_to_map(map.to_local(world_position))
	var actor: CombatUnit = turns.current_unit
	if actor == null or not actor.is_ally:
		return
	selection.begin_field_input(event.button_index == MOUSE_BUTTON_LEFT)
	# 우클릭은 몸통에 가려진 칸도 격자 위치로 이동 판정한다.
	if event.button_index == MOUSE_BUTTON_RIGHT:
		get_viewport().set_input_as_handled()
		await _select_move_cell(cell)
		return
	var candidates: Array[CombatUnit] = []
	for unit: CombatUnit in units:
		var body_point: Vector2 = unit.to_local(world_position) - Vector2(0, unit.floor_offset_y)
		if unit.hit_points > 0 and Rect2(-7, -20, 14, 22).has_point(body_point):
			candidates.append(unit)
	candidates.sort_custom(func(a: CombatUnit, b: CombatUnit) -> bool:
		if a.position.y != b.position.y:
			return a.position.y > b.position.y
		return a.get_index() > b.get_index()
	)
	if not candidates.is_empty():
		var unit: CombatUnit = candidates[0]
		get_viewport().set_input_as_handled()
		if unit.is_ally and selection.selected_action != "shove":
			selection.clear_preview()
		elif selection.select_target(unit, actions.can_target(actor, unit, selection.selected_action)):
			await _execute_target(unit)
		_update_turn_ui()
		return
	selection.clear_preview()
	_update_turn_ui()


func _select_move_cell(cell: Vector2i) -> void:
	var actor: CombatUnit = turns.current_unit
	var path: Array[Vector2i] = []
	if actor != null and actor.is_ally and actions.can_move(actor, cell):
		path = actions.grid.path_to(actor, cell)
	if selection.select_move(cell, path):
		if await actions.move_to(actor, cell):
			selection.finish_execution()
	_update_turn_ui()


func preview_enemy(target: CombatUnit) -> bool:
	if (turns.current_unit == null or not turns.current_unit.is_ally
		or target not in units or target.is_ally or target.hit_points <= 0):
		return false
	selection.preview_unit(target)
	_update_turn_ui()
	return true


func _on_actions_changed() -> void:
	if actions.is_over() and actions.is_victory():
		var dice: CombatDice = CombatDice.new()
		dice.randomize()
		var monster_count: int = 0
		for unit: CombatUnit in units:
			if unit.can_drop_extra_reward():
				monster_count += 1
		progress.record_victory(loot, monster_count, dice)
	_update_turn_ui()


func _on_turn_changed() -> void:
	selection.reset()
	_update_turn_ui()


func _execute_target(target: CombatUnit) -> void:
	var actor: CombatUnit = turns.current_unit
	var action: String = selection.begin_execution()
	match action:
		"attack", "shock":
			await actions.attack(actor, target, action == "shock")
		"mark":
			actions.mark(actor, target)
		"shove":
			actions.shove(actor, target)
	selection.finish_execution()
	_update_turn_ui()


func _animate_movement(unit: CombatUnit, cell: Vector2i) -> void:
	var destination: Vector2 = map.map_to_local(cell)
	unit.face_toward(destination)
	unit.is_moving = true
	var tween: Tween = create_tween().set_parallel()
	tween.tween_property(unit, "position", destination, MOVE_STEP_TIME)
	tween.tween_property(unit, "floor_offset_y", map.map_to_surface(cell).y - destination.y, MOVE_STEP_TIME)
	tween.tween_property(unit, "body_offset_y", -3.0, MOVE_STEP_TIME / 2.0)
	tween.tween_property(unit, "body_offset_y", 0.0, MOVE_STEP_TIME / 2.0).from(-3.0).set_delay(MOVE_STEP_TIME / 2.0)
	await tween.finished
	unit.position = destination
	unit.body_offset_y = 0.0
	unit.is_moving = false


func _animate_attack(actor: CombatUnit, target: CombatUnit) -> void:
	actor.face_toward(target.position)
	if actor.kind != CombatUnit.Kind.ARCHER:
		return
	var arrow: Polygon2D = Polygon2D.new()
	arrow.name = "Arrow"
	arrow.polygon = PackedVector2Array([
		Vector2(-4, -1), Vector2(4, -1), Vector2(4, 1), Vector2(-4, 1)
	])
	arrow.color = Color("efe4c8")
	arrow.z_index = 1
	arrow.position = actor.position + Vector2(0, actor.floor_offset_y - 14)
	var destination: Vector2 = target.position + Vector2(0, target.floor_offset_y - 14)
	arrow.rotation = (destination - arrow.position).angle()
	add_child(arrow)
	var tween: Tween = create_tween()
	tween.tween_property(arrow, "position", destination, ARROW_FLIGHT_TIME)
	await tween.finished
	arrow.queue_free()


func _update_turn_ui() -> void:
	selection.discard_incapacitated_inspection()
	for unit: CombatUnit in units:
		unit.has_mark = actions.is_marked(unit)
		if not unit.is_moving:
			unit.position = map.map_to_local(unit.cell)
			unit.floor_offset_y = map.map_to_surface(unit.cell).y - unit.position.y
		unit.visible = unit.hit_points > 0
		unit.is_occluded = map.occludes(unit.cell,
			map.to_local(unit.to_global(Vector2(0, unit.floor_offset_y - 10))))
		unit.is_selected = unit == turns.current_unit
		unit.is_previewed = unit == selection.preview_target or (not selection.preview_path.is_empty()
			and actions.can_target(turns.current_unit, unit, "attack", selection.preview_cell))
		unit.queue_redraw()
	if turns.current_unit != null and turns.current_unit.is_ally:
		_last_ally = turns.current_unit
	var can_act: bool = actions.has_available_action(turns.current_unit)
	hud.refresh(turns, can_act)
	movement_cells.clear()
	if selection.selected_action == "move" and turns.current_unit != null and turns.current_unit.is_ally:
		movement_cells.assign(actions.reachable_cells(turns.current_unit).keys())
	var attack_cells: Array[Vector2i] = []
	for cell: Vector2i in movement_cells:
		if not _attack_targets_from(cell).is_empty():
			attack_cells.append(cell)
	map.show_movement(movement_cells, attack_cells, selection.preview_path,
		turns.current_unit.cell if turns.current_unit != null else Vector2i.ZERO)
	if selection.preview_target != null:
		var preview: CombatChecks.AttackPreview = actions.grid.attack_preview(
			turns.current_unit, selection.preview_target)
		hud.show_attack_preview(selection.preview_target, preview)
		if selection.selected_action == "mark":
			hud.show_target_note("표식 대상" if actions.can_target(turns.current_unit, selection.preview_target, "mark") else "표식을 사용할 수 없음")
		elif selection.selected_action == "shove":
			if actions.can_target(turns.current_unit, selection.preview_target, "shove"):
				var cell: Vector2i = actions.grid.push_destination(turns.current_unit.cell, selection.preview_target.cell)
				hud.show_target_note("밀려날 칸: %d, %d" % [cell.x, cell.y])
			else:
				hud.show_target_note("밀치기를 사용할 수 없음")
	elif selection.inspected_unit != null:
		hud.show_unit(selection.inspected_unit)
	var showing_move: bool = selection.selected_action == "move" or not selection.preview_path.is_empty()
	hud.refresh_actions(actions, selection.selected_action, _last_ally)
	hud.show_move_mode(showing_move)
	if actions.is_over():
		hud.show_outcome(actions.is_victory())
		if not preparation.visible:
			hud.show_result(actions.is_victory(), progress.graduated, _enemy_turn_running or actions.busy)
	queue_redraw()


func _attack_targets_from(cell: Vector2i) -> Array[CombatUnit]:
	var targets: Array[CombatUnit] = []
	for unit: CombatUnit in units:
		if actions.can_target(turns.current_unit, unit, "attack", cell):
			targets.append(unit)
	return targets
