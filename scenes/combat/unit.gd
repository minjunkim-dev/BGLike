class_name CombatUnit
extends Node2D
## 팀과 직업, 격자 위치를 가진 임시 사각형 유닛.

enum Kind { WARRIOR, ARCHER }

const ALLY_COLOR: Color = Color("509be0")
const ENEMY_COLOR: Color = Color("df6256")
const OUTLINE_COLOR: Color = Color("202b35")
const WEAPON_COLOR: Color = Color("f4ead1")

@export var kind: Kind = Kind.WARRIOR
@export var is_ally: bool = true
@export var start_cell: Vector2i = Vector2i.ZERO

var cell: Vector2i = Vector2i.ZERO


func _ready() -> void:
	cell = start_cell
	queue_redraw()


func _draw() -> void:
	var body_color: Color = ALLY_COLOR if is_ally else ENEMY_COLOR
	draw_rect(Rect2(-6, -1, 12, 3), OUTLINE_COLOR)
	draw_rect(Rect2(-6, -19, 12, 18), OUTLINE_COLOR)
	draw_rect(Rect2(-5, -18, 10, 16), body_color)

	if kind == Kind.WARRIOR:
		# 검: 직선 칼날과 가로 손잡이.
		draw_rect(Rect2(-1, -16, 2, 9), WEAPON_COLOR)
		draw_rect(Rect2(-3, -8, 6, 2), WEAPON_COLOR)
	else:
		# 활: 꺾인 활대와 곧은 시위.
		draw_polyline(PackedVector2Array([
			Vector2(-2, -16), Vector2(2, -12), Vector2(-2, -8)
		]), WEAPON_COLOR)
		draw_line(Vector2(-2, -16), Vector2(-2, -8), WEAPON_COLOR)
