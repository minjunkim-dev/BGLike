class_name CombatUnit
extends Node2D
## 팀과 직업, 격자 위치와 유닛별 턴 자원을 가진 임시 유닛.

enum Kind { WARRIOR = 0, ARCHER = 1, SPIDERLING = 2, MOTHER_SPIDER = 3, SCRAP_ROBOT_1000 = 4, SCRAP_ROBOT_2000 = 5, SCRAP_ROBOT_3000 = 6 }
enum TurnResource { ACTION, BONUS_ACTION, REACTION }
enum Attribute { STRENGTH, DEXTERITY, CONSTITUTION, MENTAL }

const MOVEMENT_PER_TURN: int = 6
const FEEDBACK_RISE: float = 12.0

const ALLY_COLOR: Color = Color("509be0")
const ENEMY_COLOR: Color = Color("df6256")
const OUTLINE_COLOR: Color = Color("202b35")
const WEAPON_COLOR: Color = Color("f4ead1")

class StatusEffect extends RefCounted:
	var kind: String
	var source: CombatUnit
	var turns_left: int
	var save_dc: int

	func _init(effect_kind: String, caster: CombatUnit, duration: int) -> void:
		kind = effect_kind
		source = caster
		turns_left = duration
		save_dc = caster.get_save_dc()


@export var kind: Kind = Kind.WARRIOR
@export var is_ally: bool = true
@export var start_cell: Vector2i = Vector2i.ZERO

var cell: Vector2i = Vector2i.ZERO
var is_moving: bool = false
var facing_left: bool = false
# 깊이 정렬의 기준점은 높이를 빼기 전 바닥에 두고 그림만 올린다.
var floor_offset_y: float = 0.0:
	set(value):
		floor_offset_y = value
		queue_redraw()
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
var overloaded: bool = false
var pull_cooldown: int = 0
var _lost_hit_points: int = 0
var hit_points: int = 12:
	set(value):
		if value != hit_points:
			_lost_hit_points = maxi(0, get_max_hit_points() - value)
		hit_points = value
		if (is_boss() and not overloaded
			and hit_points <= get_max_hit_points() / 2):
			overloaded = true
			action_left += 1
var stun_source: CombatUnit
var status_effects: Array[StatusEffect] = []
var is_stunned: bool = false:
	set(value):
		is_stunned = value
		if not value:
			stun_source = null
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
var is_occluded: bool = false
var _silhouette: Node2D


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


func get_status_count(kind_name: String) -> int:
	var count: int = 0
	for effect: StatusEffect in status_effects:
		if effect.kind == kind_name:
			count += 1
	return count


func get_periodic_status_text() -> String:
	var states: Array[String] = []
	for kind_name: String in ["burn", "poison"]:
		var count: int = get_status_count(kind_name)
		if count > 0:
			states.append("%s%d" % ["화상" if kind_name == "burn" else "독", count])
	return " ".join(states)


func is_boss() -> bool:
	return not is_ally and bool(CombatEnemyDefinitions.for_kind(kind).get("boss", false))


func can_drop_extra_reward() -> bool:
	return not is_ally and kind != Kind.SPIDERLING


func begin_turn() -> void:
	disengaged = false
	pull_cooldown = maxi(0, pull_cooldown - 1)
	movement_left = (MOVEMENT_PER_TURN if is_ally
		else int(CombatEnemyDefinitions.for_kind(kind).get("movement", MOVEMENT_PER_TURN)))
	action_left = action_capacity + (1 if overloaded else 0)
	bonus_action_left = bonus_action_capacity
	reaction_left = reaction_capacity


func begin_stage(restore_act: bool) -> void:
	overloaded = false
	pull_cooldown = 0
	if restore_act:
		hit_points = get_max_hit_points()
		CombatActionRules.restore_uses(self)
	# 물약은 막 시작과 재시작에서도 현재 개수를 유지한다.
	is_stunned = false
	status_effects.clear()
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
	_silhouette = Node2D.new()
	_silhouette.z_index = 1
	_silhouette.visible = false
	_silhouette.draw.connect(func() -> void:
		var color: Color = Color("f4cf69") if is_selected else (ALLY_COLOR if is_ally else ENEMY_COLOR)
		_silhouette.draw_rect(Rect2(-6, -19, 12, 18), color, false)
	)
	add_child(_silhouette)
	cell = start_cell
	hit_points = get_max_hit_points()
	begin_turn()
	queue_redraw()


func face_toward(destination: Vector2) -> void:
	if absf(destination.x - position.x) > 0.5:
		facing_left = destination.x < position.x
		queue_redraw()


func _draw() -> void:
	_silhouette.visible = is_occluded
	_silhouette.position = Vector2(0, floor_offset_y + body_offset_y)
	_silhouette.queue_redraw()
	draw_set_transform(Vector2(0, floor_offset_y))
	draw_rect(Rect2(-9, -25, 18, 4), OUTLINE_COLOR)
	draw_rect(Rect2(-8, -24, 16.0 * hit_points / get_max_hit_points(), 2), Color("70c76d"))
	var status: String = get_periodic_status_text()
	if is_stunned:
		status = "기절" + (" " + status if not status.is_empty() else "")
	if has_mark:
		status += " ◎"
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
	draw_set_transform(Vector2(0, floor_offset_y + body_offset_y), 0.0, Vector2(-1 if facing_left else 1, 1))
	draw_rect(Rect2(-6, -19, 12, 18), OUTLINE_COLOR)
	draw_rect(Rect2(-5, -18, 10, 16), body_color)

	if is_boss():
		draw_rect(Rect2(-4, -16, 8, 5), WEAPON_COLOR)
		draw_rect(Rect2(-3, -15, 2, 2), OUTLINE_COLOR)
		draw_rect(Rect2(1, -15, 2, 2), OUTLINE_COLOR)
		draw_line(Vector2(-3, -7), Vector2(3, -7), WEAPON_COLOR)
	elif kind != Kind.ARCHER:
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


func show_feedback(text: String, obstacles: Array[Rect2] = []) -> void:
	var popup: Label = Label.new()
	popup.z_index = 10
	popup.text = text
	popup.mouse_filter = Control.MOUSE_FILTER_IGNORE
	popup.add_theme_font_size_override("font_size", 10)
	popup.add_theme_color_override("font_color", WEAPON_COLOR)
	popup.add_theme_color_override("font_outline_color", OUTLINE_COLOR)
	popup.add_theme_constant_override("outline_size", 2)
	popup.set_meta("feedback_unit", get_instance_id())
	# 전투 불능 유닛도 마지막 피해를 표시한다.
	get_parent().add_child(popup)
	popup.size = popup.get_combined_minimum_size()
	popup.position = _feedback_position(popup, obstacles)
	var tween: Tween = popup.create_tween()
	tween.tween_property(popup, "position:y", popup.position.y - FEEDBACK_RISE, 0.8)
	tween.parallel().tween_property(popup, "modulate:a", 0.0, 0.8)
	tween.tween_callback(popup.queue_free)


func _feedback_position(popup: Label, obstacles: Array[Rect2]) -> Vector2:
	var canvas: Transform2D = (get_parent() as Node2D).get_global_transform_with_canvas()
	var popup_size: Vector2 = (canvas * Rect2(Vector2.ZERO, popup.size)).size
	var rise: float = absf(canvas.basis_xform(Vector2(0, -FEEDBACK_RISE)).y)
	var padding: float = 2.0 * maxf(absf(canvas.get_scale().x), absf(canvas.get_scale().y))
	var viewport: Rect2 = get_viewport().get_visible_rect()
	var origin: Vector2 = canvas * (position + Vector2(-16, floor_offset_y - 42))
	var first: Vector2 = viewport.position + Vector2(padding, rise + padding)
	var best: Vector2 = origin.clamp(first, viewport.end - popup_size - Vector2.ONE * padding)
	var distance: float = INF
	var occupied: Array[Rect2] = obstacles.duplicate()
	# 새 기절·표식과 현재 화상·독을 함께 읽을 수 있는 상태 표시 영역을 예약한다.
	var font: Font = ThemeDB.fallback_font
	for child: Node in get_parent().get_children():
		if child is CombatUnit:
			var periodic: String = child.get_periodic_status_text()
			var status: String = "기절 %s ◎" % periodic if not periodic.is_empty() else "기절 ◎"
			var width: float = font.get_string_size(status, HORIZONTAL_ALIGNMENT_LEFT, -1, 10).x
			var status_rect: Rect2 = Rect2(Vector2(-width / 2.0, -29 - font.get_ascent(10)),
				Vector2(width, font.get_height(10)))
			var elevated_status: Rect2 = Rect2(status_rect.position + Vector2(0, child.floor_offset_y), status_rect.size)
			occupied.append((child.get_global_transform_with_canvas() * elevated_status).grow(padding))
		elif child is Label and child != popup and child.has_meta("feedback_unit"):
			var area: Rect2 = canvas * child.get_rect()
			area.position.y -= rise
			area.size.y += rise
			occupied.append(area.grow(padding))
	var candidates: Array[Vector2] = [best]
	var step: Vector2 = popup_size + Vector2(padding * 2, rise + padding * 2)
	for row: int in range(ceili(viewport.size.y / step.y)):
		for column: int in range(ceili(viewport.size.x / step.x)):
			candidates.append(first + Vector2(column, row) * step)
	for candidate: Vector2 in candidates:
		# 위로 뜨는 전체 경로를 예약해 연출 중에도 팝업과 HUD를 피한다.
		var area: Rect2 = Rect2(candidate - Vector2(0, rise), popup_size + Vector2(0, rise)).grow(padding)
		if not viewport.encloses(area):
			continue
		var available: bool = true
		for blocked: Rect2 in occupied:
			if area.intersects(blocked):
				available = false
				break
		var candidate_distance: float = candidate.distance_squared_to(origin)
		if available and candidate_distance < distance:
			best = candidate
			distance = candidate_distance
	return canvas.affine_inverse() * best
