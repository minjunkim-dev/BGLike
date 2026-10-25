class_name CombatUnit
extends Node2D
## 팀과 직업, 격자 위치와 유닛별 턴 자원·도트 애니메이션.

enum Kind { WARRIOR = 0, ARCHER = 1, SPIDERLING = 2, MOTHER_SPIDER = 3, SCRAP_ROBOT_1000 = 4, SCRAP_ROBOT_2000 = 5, SCRAP_ROBOT_3000 = 6 }
enum TurnResource { ACTION, BONUS_ACTION, REACTION }
enum Ability { STRENGTH, DEXTERITY, CRAFT, INTELLIGENCE, WILL, NATURE }

const ALLY_ABILITY_SIDES: Array[Array] = [[20, 8, 6, 4, 12, 6], [8, 20, 12, 6, 4, 6]]
static var ABILITY_NAMES: Array[String] = [TranslationServer.tr("힘"), TranslationServer.tr("민첩"),
	TranslationServer.tr("솜씨"), TranslationServer.tr("지능"), TranslationServer.tr("의지"), TranslationServer.tr("자연")]

const MOVEMENT_PER_TURN: int = 6
const FEEDBACK_RISE: float = 12.0
## 팝업이 먼저 찾는 범위: 기준 자리에서 팝업 왼쪽 위까지의 최대 논리px(#260). 기준 자리는 대상 상태 줄 기준점이다.
## 같은 대상의 이전 팝업이 그보다 높으면 그 팝업 바로 위다. 붐빌 때 옆 유닛 팝업 하나를 비켜 갈 만큼이다.
const FEEDBACK_NEAR: float = 40.0

const ALLY_COLOR: Color = Color("509be0")
const ENEMY_COLOR: Color = Color("df6256")
const OUTLINE_COLOR: Color = Color("202b35")
const WEAPON_COLOR: Color = Color("f4ead1")
const HEAL_COLOR: Color = Color("70c76d")
## 이어하기가 그대로 되돌리는 값. 저장 파일의 값은 이 변수와 같은 타입이어야 한다.
const SAVED_FIELDS: Array[String] = ["cell", "start_cell", "facing_left", "initiative_roll", "movement_left",
	"action_capacity", "bonus_action_capacity", "reaction_capacity", "action_left", "bonus_action_left",
	"reaction_left", "overloaded", "pull_cooldown", "disengaged", "second_wind_left", "parry_left",
	"surge_left", "mark_left", "shock_left", "disengage_left", "potion_left"]
## 저장 파일의 정수 상한. 고친 저장이 끝나지 않는 턴이나 큰 목록을 만들지 않게 한다.
const SAVED_INT_LIMIT: int = 99
const SAVED_HIT_POINT_LIMIT: int = 999

class StatusEffect extends RefCounted:
	var kind: String
	var source: CombatUnit
	var turns_left: int
	var strength: int

	func _init(effect_kind: String, caster: CombatUnit, duration: int, intensity: int = 0) -> void:
		kind = effect_kind
		source = caster
		turns_left = duration
		strength = intensity if kind == "poison" else 0


@export var kind: Kind = Kind.WARRIOR
@export var is_ally: bool = true
@export var start_cell: Vector2i = Vector2i.ZERO

var cell: Vector2i = Vector2i.ZERO
var is_moving: bool = false:
	set(value):
		is_moving = value
		_update_animation()
var facing_left: bool = false:
	set(value):
		facing_left = value
		_update_animation()
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
var _silhouette: Sprite2D
var _sprite: AnimatedSprite2D
var _attacking: bool = false
var _art_top_y: float = -28.0


## 능력치의 면은 1~n이다. 값은 능력치 점수나 d20 보정값이 아닌 면 수다 (#321).
func get_ability_sides(ability: Ability) -> int:
	if is_ally and kind in [Kind.WARRIOR, Kind.ARCHER]:
		return ALLY_ABILITY_SIDES[kind][ability]
	return int(CombatEnemyDefinitions.for_kind(kind)["abilities"][ability])


static func ability_name(ability: Ability) -> String:
	return ABILITY_NAMES[ability]


## 현재 일반 무기는 직업의 기본 대검·활을 강화하는 장비다. 실제 대상 거리로 유형을 바꾸지 않는다.
func get_attack_ability() -> Ability:
	return Ability.DEXTERITY if kind == Kind.ARCHER else Ability.STRENGTH


func is_ranged_attack() -> bool:
	return kind == Kind.ARCHER


func get_defense_bonus() -> int:
	if not is_ally:
		return int(CombatEnemyDefinitions.for_kind(kind)["defense_bonus"])
	return _equipment_stat("defense_bonus")


func get_max_hit_points() -> int:
	var base: int = 12 if kind == Kind.WARRIOR else 14
	if not is_ally:
		return int(CombatEnemyDefinitions.for_kind(kind)["max_hit_points"])
	return base + _equipment_stat("max_hit_points")


func get_attack_bonus() -> int:
	if not is_ally:
		return int(CombatEnemyDefinitions.for_kind(kind)["attack_bonus"])
	return _equipment_stat("attack_bonus")


func get_damage_bonus() -> int:
	if not is_ally:
		return int(CombatEnemyDefinitions.for_kind(kind)["damage_bonus"])
	return (3 if kind == Kind.WARRIOR else 1) + _equipment_stat("damage_bonus")


func get_damage_sides() -> int:
	if not is_ally:
		return int(CombatEnemyDefinitions.for_kind(kind)["damage_sides"])
	return 8 if kind == Kind.WARRIOR else 6


func _equipment_stat(stat: String) -> int:
	return int(weapon.get("stats", {}).get(stat, 0)) + int(armor.get("stats", {}).get(stat, 0))


func get_attack_range() -> int:
	if not is_ally:
		return int(CombatEnemyDefinitions.for_kind(kind)["attack_range"])
	return 1 if kind == Kind.WARRIOR else 6


func get_initiative() -> int:
	return initiative_roll


func get_display_name() -> String:
	if not is_ally:
		return CombatEnemyDefinitions.for_kind(kind)["name"]
	return tr("아군 전사") if kind == Kind.WARRIOR else tr("아군 궁수")


func get_art_id() -> String:
	if not is_ally and kind <= Kind.ARCHER:
		return "novice_barbarian" if kind == Kind.WARRIOR else "novice_archer"
	return ["warrior", "archer", "spiderling", "mother_spider",
		"scrap_robot_1000", "scrap_robot_2000", "scrap_robot_3000"][kind]


func get_status_label_y() -> float:
	return _art_top_y + body_offset_y - 9.0


## 유닛 위에 지금 보이는 상태 글자. 기절·화상·독·표식.
func get_status_text() -> String:
	var status: String = get_periodic_status_text()
	if is_stunned:
		status = tr("기절") + (" " + status if not status.is_empty() else "")
	if has_mark:
		status += " ◎"
	return status


## 상태 글자 text가 차지할 화면 영역을 padding만큼 넓힌다. 팝업 배치가 피한다.
func get_status_area(text: String, padding: float) -> Rect2:
	var font: Font = ThemeDB.fallback_font
	var width: float = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 10).x
	var area: Rect2 = Rect2(Vector2(-width / 2.0, floor_offset_y + get_status_label_y() - font.get_ascent(10)),
		Vector2(width, font.get_height(10)))
	return (get_global_transform_with_canvas() * area).grow(padding)


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
			states.append("%s%d" % [tr("화상") if kind_name == "burn" else tr("독"), count])
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


## 이어하기용 상태. 다른 유닛은 전투 유닛 목록의 번호로 적고, 없으면 -1이다.
func save_state(units: Array[CombatUnit]) -> Dictionary:
	var statuses: Array = []
	for effect: StatusEffect in status_effects:
		statuses.append([effect.kind, units.find(effect.source), effect.turns_left, effect.strength])
	var data: Dictionary = {"kind": kind, "ally": is_ally, "weapon": weapon, "armor": armor,
		"hit_points": hit_points, "lost_hit_points": _lost_hit_points, "stunned": is_stunned,
		"stun_source": units.find(stun_source), "marked_target": units.find(marked_target), "statuses": statuses}
	for field: String in SAVED_FIELDS:
		data[field] = get(field)
	return data


## save_state()의 값으로 되돌린다. 장비·HP setter가 바꾸는 HP·과부하·행동은 뒤에서 덮는다.
func load_state(data: Dictionary, units: Array[CombatUnit]) -> void:
	armor = data.armor
	weapon = data.weapon
	hit_points = data.hit_points
	for field: String in SAVED_FIELDS:
		set(field, data[field])
	_lost_hit_points = data.lost_hit_points
	is_stunned = data.stunned
	stun_source = units[data.stun_source] if data.stun_source >= 0 else null
	marked_target = units[data.marked_target] if data.marked_target >= 0 else null
	status_effects.clear()
	for saved: Array in data.statuses:
		var effect: StatusEffect = StatusEffect.new(saved[0], units[saved[1]], saved[2], saved[3])
		status_effects.append(effect)


## 저장 파일의 값을 load_state()에 넘겨도 되는지. 장비의 내용은 CombatLoot가 확인한다.
## 타입은 이 유닛의 변수와 비교하므로 어느 유닛에서 불러도 같다. count는 전투 유닛 수다.
func is_valid_state(data: Variant, count: int, map_size: Vector2i) -> bool:
	if not (data is Dictionary and data.get("kind") is int and data.kind in Kind.values() and data.get("ally") is bool
			and data.get("weapon") is Dictionary and data.get("armor") is Dictionary
			and data.get("hit_points") is int and data.hit_points >= 0 and data.hit_points <= SAVED_HIT_POINT_LIMIT
			and data.get("lost_hit_points") is int and data.lost_hit_points >= 0
			and data.lost_hit_points <= SAVED_HIT_POINT_LIMIT and data.get("stunned") is bool
			and _valid_index(data.get("stun_source"), count, true) and (not data.stunned or data.stun_source >= 0)
			and _valid_index(data.get("marked_target"), count, true)
			and data.get("statuses") is Array and data.statuses.size() <= 6):
		return false
	for field: String in SAVED_FIELDS:
		var value: Variant = data.get(field)
		if typeof(value) != typeof(get(field)) or value is int and (value < 0 or value > SAVED_INT_LIMIT):
			return false
	var area: Rect2i = Rect2i(Vector2i.ZERO, map_size)
	if not area.has_point(data.cell) or not area.has_point(data.start_cell):
		return false
	return (data.statuses as Array).all(func(saved: Variant) -> bool:
		return (saved is Array and saved.size() == 4 and saved[0] in ["burn", "poison"]
			and _valid_index(saved[1], count, false) and saved[2] is int and saved[2] >= 1 and saved[2] <= 4
			and saved[3] is int and saved[3] >= 0 and saved[3] <= SAVED_INT_LIMIT
			and (saved[3] == 0 if saved[0] == "burn" else saved[3] > 0)))


static func _valid_index(value: Variant, count: int, optional: bool) -> bool:
	return value is int and value >= (-1 if optional else 0) and value < count


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
	facing_left = not is_ally
	_sprite = AnimatedSprite2D.new()
	_sprite.name = "Sprite"
	_sprite.centered = false
	_sprite.offset = Vector2(-32, -56)
	_sprite.scale = Vector2.ONE * 0.5
	_sprite.material = preload("res://scenes/combat/art/pixel_art.tres")
	_sprite.sprite_frames = SpriteFrames.new()
	_sprite.sprite_frames.remove_animation("default")
	var unit_id: String = get_art_id()
	_art_top_y = 0.0
	for state: String in ["idle", "move", "attack"]:
		for direction: String in ["left", "right"]:
			var animation: StringName = state + "_" + direction
			_sprite.sprite_frames.add_animation(animation)
			var speed: float = 3.0 if state == "idle" else (24.0 if state == "move" else 12.0)
			_sprite.sprite_frames.set_animation_speed(animation, speed)
			_sprite.sprite_frames.set_animation_loop(animation, state != "attack")
			for frame: int in range(2):
				var texture: Texture2D = load("res://scenes/combat/art/units/%s/%s/%s/%03d.png" % [
					unit_id, state, direction, frame]) as Texture2D
				_sprite.sprite_frames.add_frame(animation, texture)
				_art_top_y = minf(_art_top_y, (texture.get_image().get_used_rect().position.y - 56.0) * 0.5)
	add_child(_sprite)
	_silhouette = Sprite2D.new()
	_silhouette.centered = false
	_silhouette.offset = _sprite.offset
	_silhouette.scale = _sprite.scale
	_silhouette.z_index = 1
	_silhouette.visible = false
	var outline: ShaderMaterial = ShaderMaterial.new()
	outline.shader = preload("res://scenes/combat/art/unit_outline.gdshader")
	_silhouette.material = outline
	add_child(_silhouette)
	_sprite.frame_changed.connect(_sync_sprite)
	_sprite.animation_changed.connect(_sync_sprite)
	_sprite.animation_finished.connect(func() -> void:
		_attacking = false
		_update_animation())
	_update_animation()
	cell = start_cell
	hit_points = get_max_hit_points()
	begin_turn()
	queue_redraw()


func _update_animation() -> void:
	if _sprite == null:
		return
	var state: String = "attack" if _attacking else ("move" if is_moving else "idle")
	_sprite.play(state + ("_left" if facing_left else "_right"))
	_sync_sprite()


func _sync_sprite() -> void:
	if _silhouette != null and _sprite.sprite_frames.has_animation(_sprite.animation):
		_silhouette.texture = _sprite.sprite_frames.get_frame_texture(_sprite.animation, _sprite.frame)


func play_attack() -> void:
	_attacking = true
	_sprite.stop()
	_update_animation()


func contains_body_point(point: Vector2) -> bool:
	var pixel: Vector2i = Vector2i(((point - Vector2(0, floor_offset_y + body_offset_y))
		/ _sprite.scale - _sprite.offset).floor())
	if not Rect2i(Vector2i.ZERO, Vector2i(64, 64)).has_point(pixel):
		return false
	var texture: Texture2D = _sprite.sprite_frames.get_frame_texture(_sprite.animation, _sprite.frame)
	return texture.get_image().get_pixelv(pixel).a > 0.0


func face_toward(destination: Vector2) -> void:
	if absf(destination.x - position.x) > 0.5:
		facing_left = destination.x < position.x
		queue_redraw()


func _draw() -> void:
	_silhouette.visible = is_occluded or is_selected or is_previewed
	var edge: Color = Color("f4cf69") if is_selected else (
		Color("f4ead1") if is_previewed else (ALLY_COLOR if is_ally else ENEMY_COLOR))
	(_silhouette.material as ShaderMaterial).set_shader_parameter("outline_color", edge)
	(_silhouette.material as ShaderMaterial).set_shader_parameter("fill_alpha", 0.22 if is_occluded else 0.0)
	_silhouette.position = Vector2(0, floor_offset_y + body_offset_y)
	_sprite.position = _silhouette.position
	draw_set_transform(Vector2(0, floor_offset_y))
	var status_y: float = get_status_label_y()
	draw_rect(Rect2(-9, status_y + 4, 18, 4), OUTLINE_COLOR)
	draw_rect(Rect2(-8, status_y + 5, 16.0 * hit_points / get_max_hit_points(), 2), HEAL_COLOR)
	var status: String = get_status_text()
	if not status.is_empty():
		var font: Font = ThemeDB.fallback_font
		var width: float = font.get_string_size(status, HORIZONTAL_ALIGNMENT_LEFT, -1, 10).x
		draw_string(font, Vector2(-width / 2.0, status_y), status, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, WEAPON_COLOR)
	draw_polyline(PackedVector2Array([Vector2(-9, 0), Vector2(0, 4), Vector2(9, 0)]),
		ALLY_COLOR if is_ally else ENEMY_COLOR)
	draw_set_transform(Vector2.ZERO)


func show_feedback(text: String, obstacles: Array[Rect2] = [], color: Color = WEAPON_COLOR) -> void:
	var popup: Label = Label.new()
	popup.z_index = 10
	popup.text = text
	popup.mouse_filter = Control.MOUSE_FILTER_IGNORE
	popup.add_theme_font_size_override("font_size", 10)
	popup.add_theme_color_override("font_color", color)
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
	var canvas_scale: float = maxf(absf(canvas.get_scale().x), absf(canvas.get_scale().y))
	var padding: float = 2.0 * canvas_scale
	var viewport: Rect2 = get_viewport().get_visible_rect()
	var origin: Vector2 = canvas * (position + Vector2(-16, floor_offset_y + get_status_label_y() - 5))
	var first: Vector2 = viewport.position + Vector2(padding, rise + padding)
	var center: Vector2 = origin.clamp(first, viewport.end - popup_size - Vector2.ONE * padding)
	# 화면 패널, 다른 대상 팝업의 상승 경로, 지금 보이는 상태 글자와 대상 자신의 상태 자리는 언제나 피한다.
	var blocked: Array[Rect2] = obstacles.duplicate()
	# 다른 유닛의 새 기절·표식과 현재 화상·독을 읽을 자리는 근처에 빈 자리가 있을 때만 비워 둔다.
	var reserved: Array[Rect2] = []
	# 같은 대상의 팝업은 이전 팝업 위에 순서대로 쌓는다(#260).
	var ceiling: float = INF
	for child: Node in get_parent().get_children():
		if child is CombatUnit:
			var periodic: String = child.get_periodic_status_text()
			var area: Rect2 = child.get_status_area(
				tr("기절") + (" " + periodic if not periodic.is_empty() else "") + " ◎", padding)
			if child == self:
				blocked.append(area)
			else:
				reserved.append(area)
			var shown: String = child.get_status_text()
			if not shown.is_empty():
				blocked.append(child.get_status_area(shown, padding))
		elif child is Label and child != popup and child.has_meta("feedback_unit"):
			var area: Rect2 = canvas * child.get_rect()
			if child.get_meta("feedback_unit") == get_instance_id():
				# 같은 대상의 팝업은 같은 속도로 떠오르므로 상승 경로를 비우지 않고 바로 위에 쌓는다.
				ceiling = minf(ceiling, area.position.y - 2.0 * padding)
				blocked.append(area.grow(padding))
				continue
			area.position.y -= rise
			area.size.y += rise
			blocked.append(area.grow(padding))
	var anchor: Vector2 = Vector2(center.x, minf(center.y, ceiling - popup_size.y - padding))
	var near: float = FEEDBACK_NEAR * canvas_scale
	var quantum: float = 2.0 * padding
	var steps: int = floori(near / quantum)
	var nearby: Array[Vector2] = _spot_grid(anchor, quantum, steps, steps, steps, near)
	var screen: Array[Vector2] = []
	var step: Vector2 = popup_size + Vector2(padding * 2, rise + padding * 2)
	for row: int in range(ceili(viewport.size.y / step.y)):
		for column: int in range(ceili(viewport.size.x / step.x)):
			screen.append(first + Vector2(column, row) * step)
	var all_blocked: Array[Rect2] = blocked + reserved
	# 1~2: 기준 자리 40px 안. 근처가 차면 다른 유닛의 상태 자리 예약을 풀고 다시 찾는다.
	# 3: 기준 자리 위쪽 띠(가로 ±40px)로 쌓는다. 4: 위가 막히면 순서를 포기하고 대상 기준점 40px 안에서 찾는다.
	# 5~6: 그래도 없으면 전처럼 화면 전체에서 대상에 가장 가까운 빈 자리를 쓴다.
	for search: Array in [[nearby, all_blocked, ceiling, anchor], [nearby, blocked, ceiling, anchor],
			[_spot_grid(anchor, quantum, steps, 0, ceili((anchor.y - first.y) / quantum)), blocked, ceiling, anchor],
			[_spot_grid(center, quantum, steps, steps, steps, near), blocked, INF, center],
			[screen, all_blocked, INF, center], [screen, blocked, INF, center]]:
		var found: Variant = _closest_free_spot(search[0], search[3], popup_size, rise, padding, search[1], search[2])
		if found != null:
			return canvas.affine_inverse() * (found as Vector2)
	return canvas.affine_inverse() * center


## base에서 quantum 간격의 후보 격자. 가로 ±columns칸, 아래 down칸에서 위 up칸까지. radius 밖은 뺀다.
func _spot_grid(base: Vector2, quantum: float, columns: int, down: int, up: int, radius: float = INF) -> Array[Vector2]:
	var spots: Array[Vector2] = []
	for row: int in range(-down, up + 1):
		for column: int in range(-columns, columns + 1):
			var offset: Vector2 = Vector2(column, -row) * quantum
			if offset.length() <= radius:
				spots.append(base + offset)
	return spots


## 후보 중 기준점에 가장 가까운 빈 자리. 없으면 null. 팝업 아래쪽은 ceiling을 넘지 않는다.
func _closest_free_spot(candidates: Array[Vector2], target: Vector2, popup_size: Vector2, rise: float,
		padding: float, blocked: Array[Rect2], ceiling: float) -> Variant:
	var viewport: Rect2 = get_viewport().get_visible_rect()
	var best: Variant = null
	var distance: float = INF
	for candidate: Vector2 in candidates:
		var candidate_distance: float = candidate.distance_squared_to(target)
		if candidate_distance >= distance:
			continue
		# 위로 뜨는 전체 경로를 예약해 연출 중에도 팝업과 HUD를 피한다.
		var area: Rect2 = Rect2(candidate - Vector2(0, rise), popup_size + Vector2(0, rise)).grow(padding)
		if not viewport.encloses(area) or area.end.y > ceiling:
			continue
		var available: bool = true
		for rect: Rect2 in blocked:
			if area.intersects(rect):
				available = false
				break
		if available:
			best = candidate
			distance = candidate_distance
	return best
