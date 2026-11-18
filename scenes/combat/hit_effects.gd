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
## 스킬 효과(#634): 폴더별 프레임 수. 그림은 draw_skill_effects.py가 찍는다.
const SKILL_FRAME_COUNTS: Dictionary = {"shield": 4, "heal": 4, "buff": 4, "sweep_front": 3, "sweep_back": 3}
## 상태 이상 효과(#635): 폴더별 프레임 수. 그림은 draw_status_effects.py가 찍는다. 재생 규칙은 스킬 효과와 같다.
const STATUS_FRAME_COUNTS: Dictionary = {"stun": 4, "burn": 4, "poison": 4, "fallen": 3, "ignite": 4}
const SKILL_FRAME_PATH: String = "res://scenes/combat/art/effects/%s/%03d.png"
## 효과 그림 안에서 유닛 발 기준점과 캔버스 중심(그림 px). 유닛 프레임과 같은 기준이다.
const UNIT_EFFECT_ANCHOR: Vector2 = Vector2(32, 56)
const UNIT_EFFECT_CENTER: Vector2 = Vector2(32, 32)
const SWEEP_CENTER: Vector2 = Vector2(64, 32)
const SWEEP_FRONT_ANCHOR: Vector2 = Vector2(64, 26)
const SWEEP_BACK_ANCHOR: Vector2 = Vector2(64, 37)
const PIXEL_ART: Material = preload("res://scenes/combat/art/pixel_art.tres")

var _flash_frames: SpriteFrames
var _skill_frames: Dictionary = {}


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


## 성스러운 장막의 방어막. 표시만 하고 기다리지 않는다.
func play_shield(unit: CombatUnit) -> void:
	_play_on_unit("shield", unit)


## 숨 고르기·물약의 회복.
func play_heal(unit: CombatUnit) -> void:
	_play_on_unit("heal", unit)


## 전투의 함성을 받은 아군 하나.
func play_buff(unit: CombatUnit) -> void:
	_play_on_unit("buff", unit)


## 휩쓸기 궤적. direction은 시전자에서 고른 정면 칸으로 가는 화면 방향이다. 아래쪽이면 앞, 위쪽이면 뒤 그림이고 왼쪽이면 뒤집는다.
func play_sweep(actor: CombatUnit, direction: Vector2) -> void:
	var front: bool = direction.y >= 0.0
	var anchor: Vector2 = SWEEP_FRONT_ANCHOR if front else SWEEP_BACK_ANCHOR
	_spawn("sweep_front" if front else "sweep_back", _unit_anchor(actor) + (SWEEP_CENTER - anchor) * 0.5, direction.x < 0.0)


## 기절·화상·독·넘어짐이 걸렸거나 화상·독 틱이 났을 때. kind는 효과 폴더 이름과 같다.
func play_status(unit: CombatUnit, kind: String) -> void:
	if STATUS_FRAME_COUNTS.has(kind) and kind != "ignite":
		_play_on_unit(kind, unit)


## 기름이 탄 칸 하나의 불기둥. at은 칸 표면이다.
func play_ignite(at: Vector2) -> void:
	_spawn("ignite", at + (UNIT_EFFECT_CENTER - UNIT_EFFECT_ANCHOR) * 0.5, false)


func _play_on_unit(folder: String, unit: CombatUnit) -> void:
	_spawn(folder, _unit_anchor(unit) + (UNIT_EFFECT_CENTER - UNIT_EFFECT_ANCHOR) * 0.5, false)


func _unit_anchor(unit: CombatUnit) -> Vector2:
	return unit.position + Vector2(0, unit.floor_offset_y + unit.body_offset_y)


func _spawn(folder: String, at: Vector2, flip: bool) -> void:
	var sprite: AnimatedSprite2D = AnimatedSprite2D.new()
	sprite.sprite_frames = _skill_effect_frames(folder)
	sprite.material = PIXEL_ART
	sprite.scale = Vector2.ONE * 0.5
	sprite.position = at
	sprite.flip_h = flip
	add_child(sprite)
	sprite.animation_finished.connect(sprite.queue_free)
	sprite.play(&"play")


func _skill_effect_frames(folder: String) -> SpriteFrames:
	if not _skill_frames.has(folder):
		var frames: SpriteFrames = SpriteFrames.new()
		frames.remove_animation("default")
		frames.add_animation(&"play")
		frames.set_animation_speed(&"play", FLASH_FPS)
		frames.set_animation_loop(&"play", false)
		var count: int = SKILL_FRAME_COUNTS[folder] if SKILL_FRAME_COUNTS.has(folder) else STATUS_FRAME_COUNTS[folder]
		for index: int in range(count):
			frames.add_frame(&"play", load(SKILL_FRAME_PATH % [folder, index]) as Texture2D)
		_skill_frames[folder] = frames
	return _skill_frames[folder]


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
