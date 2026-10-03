extends Node2D
## M1 기반: 평지 격자와 고정 배치. 턴과 조작은 다음 단계에서 추가한다.

const MAP_SIZE: Vector2i = Vector2i(10, 10)

var units: Array[CombatUnit] = []

@onready var map: TileMapLayer = $Map
@onready var camera: Camera2D = $Camera


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
