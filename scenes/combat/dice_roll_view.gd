class_name CombatDiceRollView
extends Control
## 굴림 하나를 면 수에 맞는 다면체로 굴려 보인다. 기준값은 굴리기 전부터 보이고,
## 멈추면 합계와 성공/실패 색이 나온다. 결과는 CombatChecks가 이미 확정했다.

const UI_THEME: Theme = preload("res://scenes/ui_theme.tres")
const ROLL_SOUND: AudioStream = preload("res://scenes/combat/audio/dice_roll.ogg")
const SUCCESS_SOUND: AudioStream = preload("res://scenes/combat/audio/roll_success.ogg")
const FAILURE_SOUND: AudioStream = preload("res://scenes/combat/audio/roll_fail.ogg")

## 굴림 하나의 시간. 매우 빠르게 끝나야 하며 정확한 값은 직접 플레이로 정한다.
const TUMBLE_TIME: float = 0.45
const HOLD_TIME: float = 0.5
const FACE_CHANGES: int = 8
const DIE_RADIUS: float = 18.0
const DIE_GAP: float = 48.0
const DIE_FILL: Color = Color("202b35")
## 지형 위에서도 글자가 읽히도록 깔아 두는 배경.
const BACKDROP_FILL: Color = Color(0.07, 0.1, 0.13, 0.88)
const BACKDROP_EDGE: Color = Color("61717e")
const BACKDROP_WIDTH: float = 168.0
const NEUTRAL_COLOR: Color = Color("f4ead1")
const SUCCESS_COLOR: Color = CombatUnit.HEAL_COLOR
const FAILURE_COLOR: Color = CombatUnit.ENEMY_COLOR
const ABSOLUTE_COLOR: Color = Color("f4cf69")
const DISCARDED_ALPHA: float = 0.35
const SELECTED_SCALE: float = 1.15
const ABSOLUTE_SCALE: float = 1.3
const SOUND_VOLUME_DB: float = -10.0


class Die extends RefCounted:
	var shown: int = 1
	var scale: float = 1.0
	var alpha: float = 1.0
	var edge: Color = NEUTRAL_COLOR


var _roll: CombatDiceRoll
var _dice: Array[Die] = []
var _angle: float = 0.0
var _elapsed: float = 0.0
var _last_step: int = -1
var _tumbling: bool = false
var _revision: int = 0
## 화면용 난수. 게임의 주사위 순서와 저장 상태에 영향을 주지 않는다.
var _visual_rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _summary: Label
var _roll_player: AudioStreamPlayer
var _result_player: AudioStreamPlayer


func _ready() -> void:
	theme = UI_THEME
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	set_process(false)
	_visual_rng.randomize()
	_summary = Label.new()
	_summary.name = "Summary"
	_summary.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_summary.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_summary.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	_summary.custom_minimum_size.y = 16.0
	add_child(_summary)
	_roll_player = _make_player("RollSound", ROLL_SOUND)
	_result_player = _make_player("ResultSound", SUCCESS_SOUND)


## 굴리고 결과를 잠시 보인 뒤 닫는다. 다른 굴림이 끼어들면 이 호출은 조용히 끝난다.
func play(roll: CombatDiceRoll) -> void:
	_revision += 1
	var revision: int = _revision
	_begin(roll)
	await get_tree().create_timer(TUMBLE_TIME, false).timeout
	if revision != _revision:
		return
	_settle()
	await get_tree().create_timer(HOLD_TIME, false).timeout
	if revision != _revision:
		return
	visible = false


## 면 수에 맞는 다면체의 윤곽. 반지름1 기준이다.
static func shape_points(sides: int) -> PackedVector2Array:
	match sides:
		4:
			return _regular_polygon(3)
		6:
			return PackedVector2Array([Vector2(-0.8, -0.8), Vector2(0.8, -0.8), Vector2(0.8, 0.8), Vector2(-0.8, 0.8)])
		8:
			return _regular_polygon(4)
		10:
			return PackedVector2Array([Vector2(0, -1), Vector2(0.8, -0.2), Vector2(0, 1), Vector2(-0.8, -0.2)])
		12:
			return _regular_polygon(5)
		20:
			return _regular_polygon(6)
		_:
			return _regular_polygon(16)


static func _regular_polygon(corners: int) -> PackedVector2Array:
	var points: PackedVector2Array = []
	for index: int in range(corners):
		points.append(Vector2.from_angle(-PI / 2.0 + TAU * index / corners))
	return points


func _make_player(player_name: String, stream: AudioStream) -> AudioStreamPlayer:
	var player: AudioStreamPlayer = AudioStreamPlayer.new()
	player.name = player_name
	player.stream = stream
	player.volume_db = SOUND_VOLUME_DB
	add_child(player)
	return player


func _begin(roll: CombatDiceRoll) -> void:
	_roll = roll
	_dice.clear()
	for index: int in range(roll.result.rolls.size()):
		_dice.append(Die.new())
	_angle = 0.0
	_elapsed = 0.0
	_last_step = -1
	_tumbling = true
	_summary.text = "%s %d" % [roll.target_label, roll.target_value]
	_summary.add_theme_color_override("font_color", NEUTRAL_COLOR)
	visible = true
	set_process(true)
	_roll_player.play()
	queue_redraw()


func _process(delta: float) -> void:
	if not _tumbling:
		return
	_elapsed += delta
	var progress: float = clampf(_elapsed / TUMBLE_TIME, 0.0, 1.0)
	# 처음엔 빠르게 구르고 멈출 때 느려진다.
	_angle = (1.0 - pow(1.0 - progress, 2.0)) * TAU * 1.5
	var step: int = int(progress * FACE_CHANGES)
	if step != _last_step:
		_last_step = step
		for die: Die in _dice:
			die.shown = _visual_rng.randi_range(1, _roll.sides)
	queue_redraw()


func _settle() -> void:
	_tumbling = false
	set_process(false)
	_angle = 0.0
	var result: CombatChecks.RollResult = _roll.result
	var selected: int = maxi(0, result.rolls.find(result.selected_roll))
	for index: int in range(_dice.size()):
		_dice[index].shown = result.rolls[index]
		if _dice.size() > 1 and index != selected:
			_dice[index].alpha = DISCARDED_ALPHA
	var color: Color = SUCCESS_COLOR if result.success else FAILURE_COLOR
	var absolute: bool = result.face != CombatChecks.Face.NORMAL
	_dice[selected].edge = ABSOLUTE_COLOR if absolute else color
	_dice[selected].scale = ABSOLUTE_SCALE if absolute else SELECTED_SCALE
	_summary.text = _result_text(absolute)
	_summary.add_theme_color_override("font_color", color)
	_result_player.stream = SUCCESS_SOUND if result.success else FAILURE_SOUND
	_result_player.play()
	queue_redraw()


func _result_text(absolute: bool) -> String:
	var result: CombatChecks.RollResult = _roll.result
	var target: String = "%s %d" % [_roll.target_label, _roll.target_value]
	if absolute:
		var face_name: String = (tr("절대성공") if result.face == CombatChecks.Face.ABSOLUTE_SUCCESS
			else tr("절대실패"))
		return "%s · %s" % [face_name, target]
	return "%d %+d = %d  %s  %s" % [result.selected_roll, _roll.bonus, result.total,
		"≥" if result.success else "<", target]


func _draw() -> void:
	if _roll == null or _dice.is_empty():
		return
	var backdrop: Rect2 = Rect2((size.x - BACKDROP_WIDTH) * 0.5, 0.0, BACKDROP_WIDTH, size.y)
	draw_rect(backdrop, BACKDROP_FILL)
	draw_rect(backdrop, BACKDROP_EDGE, false)
	var points: PackedVector2Array = shape_points(_roll.sides)
	var font: Font = get_theme_default_font()
	var font_size: int = get_theme_default_font_size()
	for index: int in range(_dice.size()):
		var die: Die = _dice[index]
		var center: Vector2 = Vector2(size.x * 0.5 + (index - (_dice.size() - 1) * 0.5) * DIE_GAP, DIE_RADIUS * 1.45)
		draw_set_transform(center, _angle, Vector2.ONE * DIE_RADIUS * die.scale)
		var outline: PackedVector2Array = points.duplicate()
		outline.append(points[0])
		draw_colored_polygon(points, Color(DIE_FILL, die.alpha))
		draw_polyline(outline, Color(die.edge, die.alpha), 0.12)
		if _roll.sides == 20:
			draw_polyline(PackedVector2Array([points[0], points[2], points[4], points[0]]),
				Color(die.edge, die.alpha * 0.5), 0.08)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		draw_string(font, center + Vector2(-DIE_RADIUS, font_size * 0.35), str(die.shown),
			HORIZONTAL_ALIGNMENT_CENTER, DIE_RADIUS * 2.0, font_size, Color(NEUTRAL_COLOR, die.alpha))
