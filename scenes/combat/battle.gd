extends Node2D
## M1 기반, 턴 구조와 명중률 미리보기. 동작 실행은 다음 단계에서 연결한다.

const MAP_SIZE: Vector2i = Vector2i(10, 10)

var units: Array[CombatUnit] = []
var turns: CombatTurns = CombatTurns.new()
var preview_target: CombatUnit

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
	hud.end_turn_requested.connect(turns.end_turn)
	turns.changed.connect(_on_turn_changed)
	var dice: RandomNumberGenerator = RandomNumberGenerator.new()
	dice.randomize()
	turns.start(units, dice)


func _on_unit_selected(unit: CombatUnit) -> void:
	turns.select_unit(unit)


func _unhandled_input(event: InputEvent) -> void:
	if (event is not InputEventMouseButton or not event.pressed
		or event.button_index != MOUSE_BUTTON_LEFT):
		return
	var world_position: Vector2 = get_canvas_transform().affine_inverse() * event.position
	for unit: CombatUnit in units:
		if Rect2(-7, -20, 14, 22).has_point(unit.to_local(world_position)):
			if not preview_enemy(unit):
				preview_target = null
				_update_turn_ui()
			get_viewport().set_input_as_handled()
			return
	preview_target = null
	_update_turn_ui()


func preview_enemy(target: CombatUnit) -> bool:
	if (turns.current_unit == null or not turns.current_unit.is_ally
		or target not in units or target.is_ally or target.hit_points <= 0):
		return false
	# 이번 단계에서는 같은 대상을 두 번 눌러도 공격을 실행하지 않는다.
	preview_target = target
	_update_turn_ui()
	return true


func _on_turn_changed() -> void:
	preview_target = null
	_update_turn_ui()


func _update_turn_ui() -> void:
	for unit: CombatUnit in units:
		unit.is_selected = unit == turns.current_unit
		unit.is_previewed = unit == preview_target
	# 아직 입력 가능한 이동·공격·스킬이 없다. 반응은 종료 강조에서 제외한다.
	var can_act: bool = (turns.current_unit != null
		and turns.current_unit.has_available_turn_action(false, false, false))
	hud.refresh(turns, can_act)
	if preview_target != null:
		var preview: CombatChecks.AttackPreview = CombatChecks.attack_preview(
			turns.current_unit, preview_target, units)
		hud.show_attack_preview(preview_target, preview)
