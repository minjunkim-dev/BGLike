class_name TitleBackdrop
extends Node2D
## 타이틀 배경(#557): 1막 1스테이지의 실제 맵과 전사·궁수 대기 도트를 어둡게 깐 정지 그림이다.
## 새 그림 파일 없이 전투와 같은 자산을 런타임에 조합한다. 입력도 매 프레임 처리도 없다.

const STAGE_PATH: String = "res://scenes/combat/stages/act1_stage1.tres"
const UNIT_IDS: Array[String] = ["warrior", "archer"]
## 맵을 2배로 키운다. 지형·유닛 원본이 0.5배라 텍셀이 논리 px와 1:1이 된다(docs/design/pixel-art.md UI 절).
const MAP_SCALE: float = 2.0
## 배경을 어둡게 한다. 값은 원본 화면을 보고 정했다.
const DIM: Color = Color(0.38, 0.38, 0.48)

var stage: CombatStage
var map: CombatMap
var unit_sprites: Array[Sprite2D] = []


func _ready() -> void:
	modulate = DIM
	scale = Vector2.ONE * MAP_SCALE
	stage = load(STAGE_PATH) as CombatStage
	var grid: CombatGrid = CombatGrid.new()
	grid.map_size = stage.map_size
	grid.heights = stage.heights.duplicate()
	grid.pits = stage.pits.duplicate()
	grid.blocked_cells = stage.get_blocked_cells()
	grid.trees = stage.tree_cells()
	grid.water_cells = stage.water_cells.duplicate()
	map = CombatMap.new()
	map.y_sort_enabled = true
	add_child(map)
	map.build_grid(grid, stage.tile_set, stage)
	for index: int in range(UNIT_IDS.size()):
		var sprite: Sprite2D = Sprite2D.new()
		sprite.name = UNIT_IDS[index].capitalize()
		sprite.texture = load("res://scenes/combat/art/units/%s/idle/right/000.png" % UNIT_IDS[index]) as Texture2D
		sprite.centered = false
		sprite.offset = Vector2(-32, -56)
		sprite.scale = Vector2.ONE * 0.5
		sprite.material = preload("res://scenes/combat/art/pixel_art.tres")
		sprite.position = map.map_to_surface(stage.ally_cells[index])
		map.add_child(sprite)
		unit_sprites.append(sprite)
	get_viewport().size_changed.connect(_center)
	_center()


## 바닥 칸 표면의 가운데를 화면 가운데에 둔다. 정수 논리 px에 맞춰 텍셀이 흔들리지 않게 한다.
func _center() -> void:
	var low: Vector2 = Vector2(INF, INF)
	var high: Vector2 = Vector2(-INF, -INF)
	for cell: Vector2i in map.get_used_cells():
		var point: Vector2 = map.map_to_surface(cell)
		low = low.min(point)
		high = high.max(point)
	position = (get_viewport_rect().size / 2.0 - (low + high) / 2.0 * MAP_SCALE).round()
