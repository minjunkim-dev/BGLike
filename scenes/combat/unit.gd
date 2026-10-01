class_name Unit
extends Node2D
## 전투 캐릭터. 능력치는 보정값으로만 저장한다(CONTEXT.md 참고).

enum Kind { WARRIOR, ARCHER }

@export var display_name := "전사"
@export var kind := Kind.WARRIOR
@export var is_ally := true
@export var start_cell := Vector2i.ZERO
@export_group("능력치 보정값")
@export var str_mod := 3
@export var dex_mod := 1
@export var con_mod := 2
@export_group("전투")
@export var max_hp := 12
@export var armor_class := 16
@export var damage_die := 8
## 1이면 근접(인접한 칸만).
@export var attack_range := 1
@export var attacks_with_dex := false

var hp: int
var cell: Vector2i

@onready var sprite: Sprite2D = $Sprite


func _ready() -> void:
	hp = max_hp
	cell = start_cell
	sprite.frame = sprite_frame()


func sprite_frame() -> int:
	return kind + (0 if is_ally else 2)


func label() -> String:
	return ("아군 " if is_ally else "적 ") + display_name


func attack_mod() -> int:
	return dex_mod if attacks_with_dex else str_mod


func is_down() -> bool:
	return hp <= 0


func face_toward(world_position: Vector2) -> void:
	if absf(world_position.x - position.x) > 0.5:
		sprite.flip_h = world_position.x < position.x


func take_damage(amount: int) -> void:
	hp = maxi(0, hp - amount)
	queue_redraw()
	if amount > 0:
		var tween := create_tween()
		tween.tween_property(sprite.material, "shader_parameter/flash", 0.0, 0.2).from(1.0)


## 쓰러지는 연출. 끝나면 보이지 않는다.
func play_down() -> void:
	var tween := create_tween().set_parallel()
	tween.tween_property(sprite, "rotation_degrees", -90.0 if sprite.flip_h else 90.0, 0.25)
	tween.tween_property(self, "modulate:a", 0.0, 0.5).set_delay(0.2)
	await tween.finished
	visible = false


# 발밑 그림자와 머리 위 HP 바.
func _draw() -> void:
	draw_set_transform(Vector2.ZERO, 0.0, Vector2(1.0, 0.45))
	draw_circle(Vector2(0, 2), 7.0, Color(0, 0, 0, 0.3))
	draw_set_transform(Vector2.ZERO)
	if not is_down():
		draw_rect(Rect2(-8, -29, 16, 3), Color("1a1620"))
		var ratio := float(hp) / max_hp
		var bar_color := Color("5cc15c") if ratio > 0.5 else Color("e0b040") if ratio > 0.25 else Color("d94a4a")
		draw_rect(Rect2(-7, -28, 14.0 * ratio, 1), bar_color)
