class_name CombatStage
extends Resource
## 스테이지별 실제 지형·장식과 기존 아군·적 시작 배치.

const SCENERY_SIZE: Dictionary[String, Vector2i] = {
	"tree": Vector2i.ONE, "ruin_wall": Vector2i.ONE, "cottage": Vector2i(2, 2)
}

@export var map_size: Vector2i = Vector2i(10, 10)
@export var heights: Dictionary[Vector2i, int] = {}
@export var pits: Array[Vector2i] = []
@export var blocked_cells: Array[Vector2i] = []
@export var water_cells: Array[Vector2i] = []
@export var crate_cells: Array[Vector2i] = []
@export var rock_cells: Array[Vector2i] = []
@export var path_cells: Array[Vector2i] = []
@export var stone_cells: Array[Vector2i] = []
@export var scenery: Dictionary[Vector2i, String] = {}
@export var tile_set: TileSet
@export var ally_cells: Array[Vector2i] = [Vector2i(1, 4), Vector2i(0, 5)]
@export var enemies: PackedScene


func get_blocked_cells() -> Array[Vector2i]:
	var result: Array[Vector2i] = blocked_cells.duplicate()
	for anchor: Vector2i in scenery:
		var size: Vector2i = SCENERY_SIZE[scenery[anchor]]
		for y: int in range(size.y):
			for x: int in range(size.x):
				var cell: Vector2i = anchor + Vector2i(x, y)
				if not result.has(cell):
					result.append(cell)
	return result
