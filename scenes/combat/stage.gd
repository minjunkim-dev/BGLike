class_name CombatStage
extends Resource
## 스테이지별 맵과 아군 시작 칸, 적 배치. M5에서 각 스테이지 데이터를 교체한다.

@export var map_size: Vector2i = Vector2i(10, 10)
@export var tile_set: TileSet
@export var ally_cells: Array[Vector2i] = [Vector2i(4, 9), Vector2i(5, 9)]
@export var enemies: PackedScene
