class_name CombatDiceRollView
extends Control
## 굴림 하나를 면 수에 맞는 다면체로 굴려 보인다. 기준값은 굴리기 전부터 보이고,
## 멈추면 판정 단어·여유 숫자·게이지 위 합계가 나온다. 결과는 CombatChecks가 이미 확정했다.

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

## 판정 단어의 등급. 합계와 기준값의 차이(여유)로 가르며 규칙 결과(성공/실패)는 바꾸지 않는다.
enum Grade {
	ABSOLUTE_SUCCESS,
	BIG_SUCCESS,
	SUCCESS,
	NARROW_SUCCESS,
	NARROW_FAILURE,
	FAILURE,
	BIG_FAILURE,
	ABSOLUTE_FAILURE,
}

## 여유가 이 값 이상이면 큰 성공, 이 값 이하(음수)면 큰 실패다.
const BIG_MARGIN: int = 5
## 성공의 여유가 이 값 이하면 아슬아슬한 성공, 실패의 여유가 이 값 이상(음수)이면 아슬아슬한 실패다.
const NARROW_SUCCESS_MARGIN: int = 1
const NARROW_FAILURE_MARGIN: int = -1
## 게이지가 보이는 여유의 범위. 기준값 양쪽으로 이만큼이고 넘으면 끝에 붙는다.
const GAUGE_RANGE: int = 6
const GAUGE_WIDTH: float = 136.0
const GAUGE_TRACK_Y: float = 80.0
const GAUGE_TRACK_HEIGHT: float = 6.0
const GAUGE_TICK_OVERHANG: float = 3.0
const GAUGE_ZONE_ALPHA: float = 0.4
const GAUGE_PILL_HEIGHT: float = 16.0
const GAUGE_PILL_GAP: float = 5.0
const GAUGE_PILL_MIN_WIDTH: float = 28.0
const TARGET_LABEL_Y: float = 90.0
const WORD_FONT_SIZE: int = 13
const ABSOLUTE_WORD_FONT_SIZE: int = 16
const WORD_HEIGHT: float = 24.0


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
## 게이지 마커의 여유(굴리는 동안 한쪽 끝에서 결과로 움직인다)와 멈춘 뒤 보이는 합계.
var _marker_margin: float = 0.0
var _final_margin: float = 0.0
var _total_shown: bool = false
## 절대성공·절대실패는 기준값과 상관없으므로 게이지 전체를 결과 색으로 채운다.
var _gauge_filled: bool = false
## 먼저 온 굴림부터 하나씩 보인다. _tickets는 받은 굴림 수, _serving은 지금 보이는 차례다.
var _tickets: int = 0
var _serving: int = 0
## 화면용 난수. 게임의 주사위 순서와 저장 상태에 영향을 주지 않는다.
var _visual_rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _summary: Label
var _target: Label
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
	_summary.custom_minimum_size.y = WORD_HEIGHT
	_summary.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	add_child(_summary)
	_target = Label.new()
	_target.name = "Target"
	_target.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_target.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_target.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	_target.position.y = TARGET_LABEL_Y
	add_child(_target)
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


## 합계와 기준값의 차이. 양수면 기준을 넘긴 만큼이다.
static func margin(result: CombatChecks.RollResult, target_value: int) -> int:
	return result.total - target_value


## 판정 단어의 등급. 절대면은 기준값과 상관없고, 나머지는 규칙의 성공/실패를 따라 여유로 세분한다.
## 여유의 부호가 규칙 결과와 어긋나도(성공인데 여유가 음수 등) 규칙을 따르고 여유는 있는 그대로 보인다.
static func grade(result: CombatChecks.RollResult, target_value: int) -> Grade:
	match result.face:
		CombatChecks.Face.ABSOLUTE_SUCCESS:
			return Grade.ABSOLUTE_SUCCESS
		CombatChecks.Face.ABSOLUTE_FAILURE:
			return Grade.ABSOLUTE_FAILURE
	var gap: int = margin(result, target_value)
	if result.success:
		if gap >= BIG_MARGIN:
			return Grade.BIG_SUCCESS
		return Grade.NARROW_SUCCESS if gap <= NARROW_SUCCESS_MARGIN else Grade.SUCCESS
	if gap <= -BIG_MARGIN:
		return Grade.BIG_FAILURE
	return Grade.NARROW_FAILURE if gap >= NARROW_FAILURE_MARGIN else Grade.FAILURE


## 판정 단어. 명중이든 내성이든 같은 말을 쓴다.
static func grade_word(value: Grade) -> String:
	match value:
		Grade.ABSOLUTE_SUCCESS:
			return TranslationServer.tr("절대성공")
		Grade.BIG_SUCCESS:
			return TranslationServer.tr("큰 성공")
		Grade.SUCCESS:
			return TranslationServer.tr("성공")
		Grade.NARROW_SUCCESS:
			return TranslationServer.tr("간신히 성공")
		Grade.NARROW_FAILURE:
			return TranslationServer.tr("아깝게 실패")
		Grade.FAILURE:
			return TranslationServer.tr("실패")
		Grade.BIG_FAILURE:
			return TranslationServer.tr("큰 실패")
		_:
			return TranslationServer.tr("절대실패")


## 게이지 위 x 위치(중앙이 기준값). 범위를 넘는 여유는 끝에 붙는다.
static func gauge_offset(gap: float) -> float:
	return clampf(gap / GAUGE_RANGE, -1.0, 1.0) * GAUGE_WIDTH * 0.5


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
	_total_shown = false
	_gauge_filled = false
	_final_margin = clampf(margin(roll.result, roll.target_value), -GAUGE_RANGE, GAUGE_RANGE)
	_marker_margin = -GAUGE_RANGE
	_target.text = "%s %d" % [roll.target_label, roll.target_value]
	_summary.text = ""
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
	var eased: float = 1.0 - pow(1.0 - progress, 2.0)
	_angle = eased * TAU * 1.5
	_marker_margin = lerpf(-GAUGE_RANGE, _final_margin, eased)
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
	_marker_margin = _final_margin
	_total_shown = not absolute
	_gauge_filled = absolute
	_summary.text = _result_text(absolute)
	_summary.add_theme_color_override("font_color", color)
	_summary.add_theme_font_size_override("font_size", ABSOLUTE_WORD_FONT_SIZE if absolute else WORD_FONT_SIZE)
	(_success_player if result.success else _failure_player).play()
	queue_redraw()


## 판정 단어와 여유. 식은 보이지 않는다. 절대면은 여유가 의미 없어 단어만 보인다.
func _result_text(absolute: bool) -> String:
	var word: String = grade_word(grade(_roll.result, _roll.target_value))
	if absolute:
		return word
	var gap: int = margin(_roll.result, _roll.target_value)
	return "%s  %s" % [word, "±0" if gap == 0 else "%+d" % gap]


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
	_draw_gauge(font, font_size)


## 기준값(중앙 눈금)을 사이에 두고 실패 구간과 성공 구간을 깔고, 합계 마커를 그 위에 둔다.
func _draw_gauge(font: Font, font_size: int) -> void:
	var color: Color = SUCCESS_COLOR if _roll.result.success else FAILURE_COLOR
	var center_x: float = size.x * 0.5
	var half: float = GAUGE_WIDTH * 0.5
	var fail_zone: Rect2 = Rect2(center_x - half, GAUGE_TRACK_Y, half, GAUGE_TRACK_HEIGHT)
	var success_zone: Rect2 = Rect2(center_x, GAUGE_TRACK_Y, half, GAUGE_TRACK_HEIGHT)
	if _gauge_filled:
		draw_rect(Rect2(fail_zone.position, Vector2(GAUGE_WIDTH, GAUGE_TRACK_HEIGHT)), color)
	else:
		draw_rect(fail_zone, Color(FAILURE_COLOR, GAUGE_ZONE_ALPHA))
		draw_rect(success_zone, Color(SUCCESS_COLOR, GAUGE_ZONE_ALPHA))
	draw_line(Vector2(center_x, GAUGE_TRACK_Y - GAUGE_TICK_OVERHANG),
		Vector2(center_x, GAUGE_TRACK_Y + GAUGE_TRACK_HEIGHT + GAUGE_TICK_OVERHANG), NEUTRAL_COLOR, 2.0)
	if _gauge_filled:
		return
	var marker_x: float = center_x + gauge_offset(_marker_margin)
	var tip: Vector2 = Vector2(marker_x, GAUGE_TRACK_Y - 1.0)
	if not _total_shown:
		# 절대면은 기준값과 상관없으므로 굴리는 동안에도 결과 위치로 향하는 마커를 보이지 않는다.
		if _roll.result.face != CombatChecks.Face.NORMAL:
			return
		draw_colored_polygon(PackedVector2Array([tip, tip + Vector2(-4.0, -6.0), tip + Vector2(4.0, -6.0)]),
			NEUTRAL_COLOR)
		return
	var text: String = str(_roll.result.total)
	var width: float = maxf(GAUGE_PILL_MIN_WIDTH, font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT,
		-1, font_size).x + 10.0)
	var pill_x: float = clampf(marker_x - width * 0.5, center_x - half - 4.0, center_x + half + 4.0 - width)
	var pill: Rect2 = Rect2(pill_x, tip.y - GAUGE_PILL_GAP - GAUGE_PILL_HEIGHT, width, GAUGE_PILL_HEIGHT)
	draw_rect(pill, DIE_FILL)
	draw_rect(pill, color, false, 1.0)
	draw_colored_polygon(PackedVector2Array([tip, tip + Vector2(-4.0, -GAUGE_PILL_GAP), tip + Vector2(4.0, -GAUGE_PILL_GAP)]),
		color)
	draw_string(font, pill.position + Vector2(0.0, GAUGE_PILL_HEIGHT * 0.5 + font_size * 0.35), text,
		HORIZONTAL_ALIGNMENT_CENTER, width, font_size, NEUTRAL_COLOR)
