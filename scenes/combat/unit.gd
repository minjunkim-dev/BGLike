class_name CombatUnit
extends Node2D
## 팀과 직업, 격자 위치와 유닛별 턴 자원을 가진 임시 유닛.

enum Kind { WARRIOR, ARCHER }
enum TurnResource { ACTION, BONUS_ACTION, REACTION }
enum Attribute { STRENGTH, DEXTERITY, CONSTITUTION, MENTAL }

const MOVEMENT_PER_TURN: int = 6

const ALLY_COLOR: Color = Color("509be0")
const ENEMY_COLOR: Color = Color("df6256")
const OUTLINE_COLOR: Color = Color("202b35")
const WEAPON_COLOR: Color = Color("f4ead1")

@export var kind: Kind = Kind.WARRIOR
@export var is_ally: bool = true
@export var start_cell: Vector2i = Vector2i.ZERO

var cell: Vector2i = Vector2i.ZERO
var is_moving: bool = false
var facing_left: bool = false
var body_offset_y: float = 0.0:
	set(value):
		body_offset_y = value
		queue_redraw()
var initiative_roll: int = 0
var movement_left: int = MOVEMENT_PER_TURN
var action_capacity: int = 1
var bonus_action_capacity: int = 1
var reaction_capacity: int = 1
var action_left: int = 1
var bonus_action_left: int = 1
var reaction_left: int = 1
var act_number: int = 1
var _lost_hit_points: int = 0
var hit_points: int = 12:
	set(value):
		if value != hit_points:
			_lost_hit_points = maxi(0, get_max_hit_points() - value)
		hit_points = value
var is_stunned: bool = false
var has_mark: bool = false
var disengaged: bool = false
var marked_target: CombatUnit
var second_wind_left: int = 1
var parry_left: int = 2
var surge_left: int = 1
var mark_left: int = 1
var shock_left: int = 1
var disengage_left: int = 2
var potion_left: int = 0
var weapon: Dictionary = {}
var armor: Dictionary = {}:
	set(value):
		var lost: int = maxi(_lost_hit_points, get_max_hit_points() - hit_points)
		armor = value
		if hit_points > 0:
			hit_points = maxi(1, get_max_hit_points() - lost)
			# 최소1 보정 전의 손실을 다음 장비 교체에도 보존한다.
			_lost_hit_points = lost
		queue_redraw()
var is_previewed: bool = false:
	set(value):
		is_previewed = value
		queue_redraw()
var is_selected: bool = false:
	set(value):
		is_selected = value
		queue_redraw()


func get_dexterity() -> int:
	if not is_ally:
		return int(CombatEnemyDefinitions.for_kind(kind)["dexterity"])
	return 1 if kind == Kind.WARRIOR else 3


func get_attribute(attribute: Attribute) -> int:
	if not is_ally:
		var key: String = ["strength", "dexterity", "constitution", "mental"][attribute]
		return int(CombatEnemyDefinitions.for_kind(kind)[key])
	match attribute:
		Attribute.STRENGTH:
			return 3 if kind == Kind.WARRIOR else 0
		Attribute.DEXTERITY:
			return get_dexterity()
		Attribute.CONSTITUTION:
			return 2 if kind == Kind.WARRIOR else 1
		Attribute.MENTAL:
			return -1 if kind == Kind.WARRIOR else 1
	return 0


func get_max_hit_points() -> int:
	var base: int = 12 if kind == Kind.WARRIOR else 14
	if not is_ally:
		return int(CombatEnemyDefinitions.for_kind(kind)["max_hit_points"])
	return base + _equipment_stat("max_hit_points")


func get_armor_class() -> int:
	if not is_ally:
		return int(CombatEnemyDefinitions.for_kind(kind)["armor_class"])
	return (16 if kind == Kind.WARRIOR else 14) + _equipment_stat("armor_class")


func get_attack_bonus() -> int:
	if not is_ally:
		return int(CombatEnemyDefinitions.for_kind(kind)["attack_bonus"])
	return 5 + _equipment_stat("attack_bonus")


func get_damage_bonus() -> int:
	if not is_ally:
		return int(CombatEnemyDefinitions.for_kind(kind)["damage_bonus"])
	return (3 if kind == Kind.WARRIOR else 1) + _equipment_stat("damage_bonus")


func get_damage_sides() -> int:
	if not is_ally:
		return int(CombatEnemyDefinitions.for_kind(kind)["damage_sides"])
	return 8 if kind == Kind.WARRIOR else 6


func get_save_dc() -> int:
	return 13 if is_ally else int(CombatEnemyDefinitions.for_kind(kind)["save_dc"])


func _equipment_stat(stat: String) -> int:
	return int(weapon.get("stats", {}).get(stat, 0)) + int(armor.get("stats", {}).get(stat, 0))


func get_attack_range() -> int:
	if not is_ally:
		return int(CombatEnemyDefinitions.for_kind(kind)["attack_range"])
	return 1 if kind == Kind.WARRIOR else 6


func get_initiative() -> int:
	return initiative_roll + get_dexterity()


func get_display_name() -> String:
	if not is_ally:
		return CombatEnemyDefinitions.for_kind(kind)["name"]
	return "아군 " + ("전사" if kind == Kind.WARRIOR else "궁수")


func begin_turn() -> void:
	disengaged = false
	movement_left = MOVEMENT_PER_TURN
	action_left = action_capacity
	bonus_action_left = bonus_action_capacity
	reaction_left = reaction_capacity


func begin_stage(restore_act: bool) -> void:
	if restore_act:
		hit_points = get_max_hit_points()
		CombatActionRules.restore_uses(self)
	# 물약은 막 시작과 재시작에서도 현재 개수를 유지한다.
	is_stunned = false
	has_mark = false
	marked_target = null
	is_selected = false
	is_previewed = false
	begin_turn()


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
			action_left -= 1
		TurnResource.BONUS_ACTION:
			if bonus_action_left == 0:
				return false
			bonus_action_left -= 1
		TurnResource.REACTION:
			if reaction_left == 0:
				return false
			reaction_left -= 1
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
	hit_points = get_max_hit_points()
	queue_redraw()


func face_toward(destination: Vector2) -> void:
	if absf(destination.x - position.x) > 0.5:
		facing_left = destination.x < position.x
		queue_redraw()


func _draw() -> void:
	draw_rect(Rect2(-9, -25, 18, 4), OUTLINE_COLOR)
	draw_rect(Rect2(-8, -24, 16.0 * hit_points / get_max_hit_points(), 2), Color("70c76d"))
	var status: String = ("기절" if is_stunned else "") + (" ◎" if has_mark else "")
	if not status.is_empty():
		var font: Font = ThemeDB.fallback_font
		var width: float = font.get_string_size(status, HORIZONTAL_ALIGNMENT_LEFT, -1, 10).x
		draw_string(font, Vector2(-width / 2.0, -29), status, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, WEAPON_COLOR)
	var body_color: Color = ALLY_COLOR if is_ally else ENEMY_COLOR
	if is_selected:
		draw_rect(Rect2(-7, -20, 14, 20), Color("f4cf69"), false)
	elif is_previewed:
		draw_rect(Rect2(-7, -20, 14, 20), Color("f4ead1"), false)
	draw_rect(Rect2(-6, -1, 12, 3), OUTLINE_COLOR)
	draw_set_transform(Vector2(0, body_offset_y), 0.0, Vector2(-1 if facing_left else 1, 1))
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
	draw_set_transform(Vector2.ZERO)


func show_feedback(text: String) -> void:
	var popup: Label = Label.new()
	popup.z_index = 10
	popup.text = text
	popup.mouse_filter = Control.MOUSE_FILTER_IGNORE
	popup.add_theme_font_size_override("font_size", 10)
	popup.add_theme_color_override("font_color", WEAPON_COLOR)
	popup.add_theme_color_override("font_outline_color", OUTLINE_COLOR)
	popup.add_theme_constant_override("outline_size", 2)
	popup.position = Vector2(-16, -42)
	# 같은 유닛의 판정과 피해가 함께 떠도 글자가 겹치지 않는다.
	for child: Node in get_parent().get_children():
		if child is Label and child.get_meta("feedback_unit", 0) == get_instance_id():
			popup.position.y = minf(popup.position.y,
				child.position.y - position.y - popup.get_combined_minimum_size().y - 16)
	popup.set_meta("feedback_unit", get_instance_id())
	# 전투 불능 유닛도 마지막 피해를 표시한다.
	get_parent().add_child(popup)
	popup.position += position
	var tween: Tween = popup.create_tween()
	tween.tween_property(popup, "position:y", popup.position.y - 12, 0.8)
	tween.parallel().tween_property(popup, "modulate:a", 0.0, 0.8)
	tween.tween_callback(popup.queue_free)
