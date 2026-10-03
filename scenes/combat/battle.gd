extends Node2D
## M1 기반과 턴 구조. 이동·공격·스킬은 동작 단계에서 연결한다.

const MAP_SIZE: Vector2i = Vector2i(10, 10)

var units: Array[CombatUnit] = []
var turns: CombatTurns = CombatTurns.new()

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
	turns.changed.connect(_update_turn_ui)
	var dice: RandomNumberGenerator = RandomNumberGenerator.new()
	dice.randomize()
	turns.start(units, dice)


func _on_unit_selected(unit: CombatUnit) -> void:
	turns.select_unit(unit)


func _update_turn_ui() -> void:
	for unit: CombatUnit in units:
		unit.is_selected = unit == turns.current_unit
	# 아직 입력 가능한 이동·공격·스킬이 없다. 반응은 종료 강조에서 제외한다.
	var can_act: bool = (turns.current_unit != null
		and turns.current_unit.has_available_turn_action(false, false, false))
	hud.refresh(turns, can_act)
