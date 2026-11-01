class_name CombatDiceRollView
extends Control
## 굴림 하나를 면 수에 맞는 다면체로 굴려 보인다. 기준값은 굴리기 전부터 보이고,
## 멈추면 합계와 성공/실패 색이 나온다. 결과는 CombatChecks가 이미 확정했다.

## 보이던 굴림이 닫혀 다음 차례로 넘어갔다.
signal _turn_passed

const UI_THEME: Theme = preload("res://scenes/ui_theme.tres")
const ROLL_SOUND: AudioStream = preload("res://scenes/combat/audio/dice_roll.ogg")
const SUCCESS_SOUND: AudioStream = preload("res://scenes/combat/audio/roll_success.ogg")
const FAILURE_SOUND: AudioStream = preload("res://scenes/combat/audio/roll_fail.ogg")

## 굴림 하나의 시간. 매우 빠르게 끝나야 하며 정확한 값은 직접 플레이로 정한다.
const TUMBLE_TIME: float = 0.45
const HOLD_TIME: float = 0.5
const FACE_CHANGES: int = 8
const DIE_RADIUS: float = 18.0
## 주사위 중심 높이. 절대면 강조선(가장 큰 윤곽)이 배경 위로 나가지 않게 둔다.
const DIE_CENTER_Y: float = 28.0
const HALO_SCALE: float = 1.15
const HALO_WIDTH: float = 0.08
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
## 4배속에서는 다음 굴림이 앞 소리가 끝나기 전에 와서, 같은 소리를 겹쳐 재생한다(누적 규칙).
const SOUND_POLYPHONY: int = 4


class Die extends RefCounted:
	var shown: int = 1
	var scale: float = 1.0
	var alpha: float = 1.0
	var edge: Color = NEUTRAL_COLOR
	## 절대성공·절대실패면. 테두리는 성공/실패 색 그대로 두고 바깥 강조선을 더한다.
	var emphasized: bool = false


var _roll: CombatDiceRoll
var _dice: Array[Die] = []
var _angle: float = 0.0
var _elapsed: float = 0.0
var _last_step: int = -1
var _tumbling: bool = false
## 먼저 온 굴림부터 하나씩 보인다. _tickets는 받은 굴림 수, _serving은 지금 보이는 차례다.
var _tickets: int = 0
var _serving: int = 0
## 화면용 난수. 게임의 주사위 순서와 저장 상태에 영향을 주지 않는다.
var _visual_rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _summary: Label
var _roll_player: AudioStreamPlayer
var _success_player: AudioStreamPlayer
var _failure_player: AudioStreamPlayer


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
	_success_player = _make_player("SuccessSound", SUCCESS_SOUND)
	_failure_player = _make_player("FailureSound", FAILURE_SOUND)


## 굴리고 결과를 잠시 보인 뒤 닫는다. 앞 굴림이 보이는 중이면 그 결과가 닫힐 때까지 차례를 기다린다.
## 기다리지 않는 굴림(독 제거·만능팔)과 기다리는 굴림(명중·회전회오리)이 같은 차례 줄에 선다.
func play(roll: CombatDiceRoll) -> void:
	var ticket: int = _tickets
	_tickets += 1
	while ticket != _serving:
		await _turn_passed
	_begin(roll)
	await get_tree().create_timer(TUMBLE_TIME, false).timeout
	_settle()
	await get_tree().create_timer(HOLD_TIME, false).timeout
	visible = false
	_serving += 1
	_turn_passed.emit()


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
	player.max_polyphony = SOUND_POLYPHONY
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
	_dice[selected].edge = color
	_dice[selected].emphasized = absolute
	_dice[selected].scale = ABSOLUTE_SCALE if absolute else SELECTED_SCALE
	_summary.text = _result_text(absolute)
	_summary.add_theme_color_override("font_color", color)
	(_success_player if result.success else _failure_player).play()
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
		var center: Vector2 = Vector2(size.x * 0.5 + (index - (_dice.size() - 1) * 0.5) * DIE_GAP, DIE_CENTER_Y)
		draw_set_transform(center, _angle, Vector2.ONE * DIE_RADIUS * die.scale)
		var outline: PackedVector2Array = points.duplicate()
		outline.append(points[0])
		draw_colored_polygon(points, Color(DIE_FILL, die.alpha))
		draw_polyline(outline, Color(die.edge, die.alpha), 0.12)
		if die.emphasized:
			var halo: PackedVector2Array = PackedVector2Array()
			for point: Vector2 in outline:
				halo.append(point * HALO_SCALE)
			draw_polyline(halo, Color(ABSOLUTE_COLOR, die.alpha), HALO_WIDTH)
		if _roll.sides == 20:
			draw_polyline(PackedVector2Array([points[0], points[2], points[4], points[0]]),
				Color(die.edge, die.alpha * 0.5), 0.08)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		draw_string(font, center + Vector2(-DIE_RADIUS, font_size * 0.35), str(die.shown),
			HORIZONTAL_ALIGNMENT_CENTER, DIE_RADIUS * 2.0, font_size, Color(NEUTRAL_COLOR, die.alpha))
