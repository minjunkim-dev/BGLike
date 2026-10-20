class_name CombatStage
extends Resource
## 스테이지별 맵과 아군 시작 칸, 적 배치. M5에서 각 스테이지 데이터를 교체한다.

@export var map_size: Vector2i = Vector2i(10, 10)
@export var heights: Dictionary[Vector2i, int] = {}
@export var pits: Array[Vector2i] = []
@export var tile_set: TileSet
@export var ally_cells: Array[Vector2i] = [Vector2i(1, 4), Vector2i(0, 5)]
@export var enemies: PackedScene
