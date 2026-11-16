class_name CombatHitEffects
extends Node2D
## 타격 섬광·히트스톱·빗나감 잔상(#559). 표시만 하고 전투 진행은 기다리지 않는다.
## 모든 시간은 게임 시간이라 4배속(Engine.time_scale)에서 같은 비율로 줄어든다.

const HITSTOP_TIME: float = 0.05
const FLASH_FPS: float = 12.0
const RECOIL_DISTANCE: float = 2.0
const RECOIL_TIME: float = 0.04
const AFTERIMAGE_OFFSET: float = 3.0
const AFTERIMAGE_TIME: float = 0.25
const AFTERIMAGE_COLOR: Color = Color(0.6, 0.75, 1.0, 0.55)
const FLASH_FRAMES: Array[String] = [
	"res://scenes/combat/art/effects/hit_flash/000.png",
	"res://scenes/combat/art/effects/hit_flash/001.png",
	"res://scenes/combat/art/effects/hit_flash/002.png",
]
const PIXEL_ART: Material = preload("res://scenes/combat/art/pixel_art.tres")

var _flash_frames: SpriteFrames


## at 자리에 섬광을 한 번 재생한다. target이 유닛이면 히트스톱과 밀림도 한다(상자는 null).
func play_hit(attacker: CombatUnit, target: CombatUnit, at: Vector2) -> void:
	var flash: AnimatedSprite2D = AnimatedSprite2D.new()
	flash.sprite_frames = _frames()
	flash.material = PIXEL_ART
	flash.scale = Vector2.ONE * 0.5
	flash.position = at
	add_child(flash)
	flash.animation_finished.connect(flash.queue_free)
	flash.play(&"flash")
	if target != null:
		_hitstop(attacker, target)


func play_miss(attacker: CombatUnit, target: CombatUnit) -> void:
	var ghost: Sprite2D = Sprite2D.new()
	ghost.texture = target.current_frame_texture()
	ghost.material = PIXEL_ART
	ghost.centered = false
	ghost.offset = Vector2(-32, -56)
	ghost.scale = Vector2.ONE * 0.5
	ghost.modulate = AFTERIMAGE_COLOR
	ghost.position = (target.position + Vector2(0, target.floor_offset_y + target.body_offset_y)
		+ Vector2(_away(attacker, target) * AFTERIMAGE_OFFSET, 0))
	add_child(ghost)
	var tween: Tween = ghost.create_tween()
	tween.tween_property(ghost, "modulate:a", 0.0, AFTERIMAGE_TIME)
	tween.tween_callback(ghost.queue_free)


func _frames() -> SpriteFrames:
	if _flash_frames == null:
		_flash_frames = SpriteFrames.new()
		_flash_frames.remove_animation("default")
		_flash_frames.add_animation(&"flash")
		_flash_frames.set_animation_speed(&"flash", FLASH_FPS)
		_flash_frames.set_animation_loop(&"flash", false)
		for path: String in FLASH_FRAMES:
			_flash_frames.add_frame(&"flash", load(path) as Texture2D)
	return _flash_frames


## 공격자 반대쪽의 수평 방향(-1 또는 1).
func _away(attacker: CombatUnit, target: CombatUnit) -> float:
	if attacker == null or not is_instance_valid(attacker) or absf(target.position.x - attacker.position.x) < 0.5:
		return 1.0
	return signf(target.position.x - attacker.position.x)


func _hitstop(attacker: CombatUnit, target: CombatUnit) -> void:
	var direction: float = _away(attacker, target)
	target.set_hit_pause(true)
	await get_tree().create_timer(HITSTOP_TIME, false).timeout
	if not is_instance_valid(target):
		return
	target.set_hit_pause(false)
	var tween: Tween = create_tween()
	tween.tween_property(target, "recoil_offset", Vector2(direction * RECOIL_DISTANCE, 0), RECOIL_TIME)
	tween.tween_property(target, "recoil_offset", Vector2.ZERO, RECOIL_TIME)
	await tween.finished
	if is_instance_valid(target):
		target.recoil_offset = Vector2.ZERO
