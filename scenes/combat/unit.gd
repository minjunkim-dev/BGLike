class_name CombatUnit
extends Node2D
## 팀과 직업, 격자 위치와 유닛별 턴 자원을 가진 임시 유닛.

enum Kind { WARRIOR, ARCHER }
enum TurnResource { ACTION, BONUS_ACTION, REACTION }

const MOVEMENT_PER_TURN: int = 6

const ALLY_COLOR: Color = Color("509be0")
const ENEMY_COLOR: Color = Color("df6256")
const OUTLINE_COLOR: Color = Color("202b35")
const WEAPON_COLOR: Color = Color("f4ead1")

@export var kind: Kind = Kind.WARRIOR
@export var is_ally: bool = true
@export var start_cell: Vector2i = Vector2i.ZERO

var cell: Vector2i = Vector2i.ZERO
var initiative_roll: int = 0
var movement_left: int = MOVEMENT_PER_TURN
var action_left: int = 1
var bonus_action_left: int = 1
var reaction_left: int = 1
var is_selected: bool = false:
	set(value):
		is_selected = value
		queue_redraw()


func get_dexterity() -> int:
	return 1 if kind == Kind.WARRIOR else 3


func get_initiative() -> int:
	return initiative_roll + get_dexterity()


func get_display_name() -> String:
	return ("아군 " if is_ally else "적 ") + ("전사" if kind == Kind.WARRIOR else "궁수")


func begin_turn() -> void:
	movement_left = MOVEMENT_PER_TURN
	action_left = 1
	bonus_action_left = 1
	reaction_left = 1


func spend_movement(cost: int) -> bool:
	if cost <= 0 or cost > movement_left:
		return false
	movement_left -= cost
	return true


func spend_resource(resource: TurnResource) -> bool:
	match resource:
		TurnResource.ACTION:
			if action_left == 0:
				return false
			action_left = 0
		TurnResource.BONUS_ACTION:
			if bonus_action_left == 0:
				return false
			bonus_action_left = 0
		TurnResource.REACTION:
			if reaction_left == 0:
				return false
			reaction_left = 0
		_:
			return false
	return true


func has_available_turn_action(
	has_move_destination: bool, has_action_target: bool, has_bonus_action_target: bool
) -> bool:
	# 반응은 자기 턴의 종료 가능 여부에 영향을 주지 않는다.
	return (movement_left > 0 and has_move_destination
		or action_left > 0 and has_action_target
		or bonus_action_left > 0 and has_bonus_action_target)


func _ready() -> void:
	cell = start_cell
	queue_redraw()


func _draw() -> void:
	var body_color: Color = ALLY_COLOR if is_ally else ENEMY_COLOR
	if is_selected:
		draw_rect(Rect2(-7, -20, 14, 20), Color("f4cf69"), false)
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
