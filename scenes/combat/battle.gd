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
var preview_target: CombatUnit
var selected_action: String = "attack"
var preview_cell: Vector2i = Vector2i(-1, -1)
var preview_path: Array[Vector2i] = []
var movement_cells: Array[Vector2i] = []
var _last_ally: CombatUnit
var _inspected_unit: CombatUnit
var loot: CombatLoot = CombatLoot.new()
var preparation: CombatPreparation

@onready var map: TileMapLayer = $Map
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
	actions.feedback.connect(func(unit: CombatUnit, text: String) -> void: unit.show_feedback(text))
	actions.hit_landed.connect($HitSound.play)
	actions.reaction_requested.connect(hud.show_reaction)
	actions.movement_animation = _animate_movement
	actions.attack_animation = _animate_attack
	turns.changed.connect(_on_turn_changed)
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
	map.clear()
	map.tile_set = stage.tile_set
	actions.map_size = map_size
	for x: int in range(map_size.x):
		for y: int in range(map_size.y):
			map.set_cell(Vector2i(x, y), 0, Vector2i((x + y) % 2, 0))
	for index: int in range(party.size()):
		party[index].cell = stage.ally_cells[index]
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
	_inspected_unit = null
	_clear_preview()
	selected_action = "attack"
	hud.begin_stage(progress.act_number(), progress.stage_in_act())
	actions.initialize(units, turns)
	var dice: RandomNumberGenerator = RandomNumberGenerator.new()
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
	_clear_preview()
	if selected_action == "move":
		selected_action = "attack"
	# 조작 가능한 아군만 전환한다. 다른 초상은 정보만 표시한다.
	turns.select_unit(unit)
	_inspected_unit = unit
	_update_turn_ui()


func _end_turn() -> void:
	if (turns.current_unit != null and turns.current_unit.is_ally
		and not actions.busy and not actions.is_over()):
		turns.end_turn()


func _on_action_selected(action: String) -> void:
	var actor: CombatUnit = turns.current_unit
	if actor == null or not actor.is_ally or not actions.can_use(actor, action):
		return
	_inspected_unit = null
	if action == selected_action and action in CombatActionRules.SELF_TARGET:
		_clear_preview()
		actions.use_self(actor, action)
		selected_action = "attack"
	else:
		selected_action = action
		_clear_preview()
	_update_turn_ui()


func _unhandled_input(event: InputEvent) -> void:
	if (event is not InputEventMouseButton or not event.pressed
		or event.button_index not in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT]):
		return
	if actions.busy or actions.is_over():
		return
	var world_position: Vector2 = get_canvas_transform().affine_inverse() * event.position
	var cell: Vector2i = map.local_to_map(map.to_local(world_position))
	var actor: CombatUnit = turns.current_unit
	if actor == null or not actor.is_ally:
		return
	_inspected_unit = null
	# 우클릭은 몸통에 가려진 칸도 격자 위치로 이동 판정한다.
	if event.button_index == MOUSE_BUTTON_RIGHT:
		get_viewport().set_input_as_handled()
		await _select_move_cell(cell)
		return
	if selected_action == "move":
		selected_action = "attack"
		_clear_preview()
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
	_clear_preview()
	_update_turn_ui()


func _select_move_cell(cell: Vector2i) -> void:
	var actor: CombatUnit = turns.current_unit
	selected_action = "move"
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


func _on_actions_changed() -> void:
	if actions.is_over() and actions.is_victory():
		var dice: RandomNumberGenerator = RandomNumberGenerator.new()
		dice.randomize()
		progress.record_victory(loot, units.size() - party.size(), dice)
	_update_turn_ui()


func _on_turn_changed() -> void:
	_inspected_unit = null
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


func _animate_movement(unit: CombatUnit, cell: Vector2i) -> void:
	var destination: Vector2 = map.map_to_local(cell)
	unit.face_toward(destination)
	unit.is_moving = true
	var tween: Tween = create_tween().set_parallel()
	tween.tween_property(unit, "position", destination, MOVE_STEP_TIME)
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
	arrow.position = actor.position + Vector2(0, -14)
	arrow.rotation = (target.position - actor.position).angle()
	add_child(arrow)
	var tween: Tween = create_tween()
	tween.tween_property(arrow, "position", target.position + Vector2(0, -14), ARROW_FLIGHT_TIME)
	await tween.finished
	arrow.queue_free()


func _update_turn_ui() -> void:
	if _inspected_unit != null and _inspected_unit.hit_points <= 0:
		_inspected_unit = null
	for unit: CombatUnit in units:
		unit.has_mark = actions.is_marked(unit)
		if not unit.is_moving:
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
	movement_cells.clear()
	if selected_action == "move" and turns.current_unit != null and turns.current_unit.is_ally:
		movement_cells.assign(actions.reachable_cells(turns.current_unit).keys())
	if preview_target != null:
		var preview: CombatChecks.AttackPreview = CombatChecks.attack_preview(
			turns.current_unit, preview_target, units)
		hud.show_attack_preview(preview_target, preview)
		if selected_action == "mark":
			hud.show_target_note("표식 대상" if actions.can_target(turns.current_unit, preview_target, "mark") else "표식을 사용할 수 없음")
		elif selected_action == "shove":
			if actions.can_target(turns.current_unit, preview_target, "shove"):
				var cell: Vector2i = actions.shove_destination(turns.current_unit, preview_target)
				hud.show_target_note("밀려날 칸: %d, %d" % [cell.x, cell.y])
			else:
				hud.show_target_note("밀치기를 사용할 수 없음")
	elif _inspected_unit != null:
		hud.show_unit(_inspected_unit)
	var showing_move: bool = selected_action == "move" or not preview_path.is_empty()
	hud.refresh_actions(actions, selected_action, _last_ally)
	hud.show_move_mode(showing_move)
	if actions.is_over():
		hud.show_outcome(actions.is_victory())
		if not preparation.visible:
			hud.show_result(actions.is_victory(), progress.graduated, _enemy_turn_running or actions.busy)
	queue_redraw()


func _draw() -> void:
	var half: Vector2 = Vector2(map.tile_set.tile_size) / 2.0
	for cell: Vector2i in movement_cells:
		var center: Vector2 = map.map_to_local(cell)
		var color: Color = Color(0.22, 0.56, 0.92, 0.4)
		if not _attack_targets_from(cell).is_empty():
			color = Color(0.22, 0.8, 0.5, 0.45)
		draw_colored_polygon(PackedVector2Array([center + Vector2(0, -half.y),
			center + Vector2(half.x, -half.y / 2.0), center + Vector2(half.x, half.y / 2.0),
			center + Vector2(0, half.y), center + Vector2(-half.x, half.y / 2.0),
			center + Vector2(-half.x, -half.y / 2.0)]), color)
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
