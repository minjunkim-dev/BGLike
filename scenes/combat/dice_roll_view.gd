class_name CombatDiceRollView
extends Control
## 굴림 하나를 굴리는 유닛 머리 위의 주사위 그림으로 보인다. 기준값 가로선은 굴리기 전부터 보이고,
## 멈추면 액체 높이·합계 식(17 = 14+3)·판정 단어와 여유가 나온다. 유닛이 화면 밖이면 정해진 자리에 이름과 함께 보인다.
## 결과는 CombatChecks가 이미 확정했다.

## 보이던 굴림이 닫혀 다음 차례로 넘어갔다.
signal _turn_passed

const UI_THEME: Theme = preload("res://scenes/ui_theme.tres")
## 굴림 소리는 갈래 3개와 높낮이 1/1.06~1.06배(#630). 결과음 둘은 성공·실패를 음정으로 알리므로 그대로다.
const ROLL_SOUND_VARIANTS: int = 3
const ROLL_SOUND_PITCH: float = 1.06
const SUCCESS_SOUND: AudioStream = preload("res://scenes/combat/audio/roll_success.ogg")
const FAILURE_SOUND: AudioStream = preload("res://scenes/combat/audio/roll_fail.ogg")

## 굴림 하나의 시간. 매우 빠르게 끝나야 하며 정확한 값은 직접 플레이로 정한다.
const TUMBLE_TIME: float = 0.45
const HOLD_TIME: float = 0.8
## 명중굴림에서 절대성공·절대실패면이 나왔을 때 결과를 보이는 시간(#488, #727). 임시값이며 플레이 후 정한다.
## 내성굴림의 절대면은 강조만 두고 시간은 늘리지 않는다.
const ABSOLUTE_HIT_HOLD_TIME: float = 1.1
## 결과 표시가 끝난 뒤 사라지는 시간(#514). 임시값이며 플레이 후 정한다.
## 차례는 페이드를 기다리지 않고 넘기며, 다음 굴림이 오면 페이드를 끊는다.
const FADE_TIME: float = 0.3
const FACE_CHANGES: int = 8
## 굴림 그림 프레임 수(rolling, rolling_1~3). 눈 바꾸기 단계와 같이 넘긴다(#626).
const ROLLING_FRAMES: int = 4
## 결과 효과 전체 시간. HOLD_TIME보다 짧아 표시 시간·차례·페이드 시점을 바꾸지 않는다. 임시값이며 플레이 후 정한다(#626).
const EFFECT_TIME: float = 0.25
## 액체가 바닥에서 결과 표면까지 차오르는 시간.
const RISE_TIME: float = 0.12
## 실패 흔들림 한 칸의 시간. +1, -1, +1, 0 논리px로 RISE_TIME 동안 이어진다.
const SHAKE_STEP_TIME: float = 0.03
## 절대실패 내려앉음 시간.
const SINK_TIME: float = 0.06
const SHAKE_PATTERN: Array[int] = [1, -1, 1, 0]
## 절대성공 불티가 나가는 반지름(논리px)과 방향(도, 위쪽 다섯 방향).
const SPARK_RADIUS_FROM: float = 14.0
const SPARK_RADIUS_TO: float = 20.0
const SPARK_DEGREES: Array[int] = [-150, -120, -90, -60, -30]
## 절대실패 파편의 출발점(주사위 가운데 기준 논리px)과 떨어지는 거리.
const SHARD_START: Array[Vector2i] = [Vector2i(-5, 10), Vector2i(0, 10), Vector2i(5, 10)]
const SHARD_FALL: float = 4.0
const SHARD_COLOR: Color = Color("7a4a94")
## 사라지는 동안 위로 떠오르는 거리(논리px)와 한 칸 시간. 페이드(FADE_TIME)와 같은 Tween 안에서 돈다.
const LIFT_MAX: int = 2
const LIFT_STEP_TIME: float = 0.1
const PIXEL_ART: Material = preload("res://scenes/combat/art/pixel_art.tres")
const DICE_DIR: String = "res://scenes/combat/art/dice/"
## 그림이 있는 면 수. 이 밖의 면 수는 벡터 윤곽으로 같은 칸에 그린다.
const ART_SIDES: Array[int] = [4, 6, 8, 10, 12, 20]
const ART_STATES: Array[String] = ["rolling", "success", "failure", "absolute_success", "absolute_failure"]
## 48 원본 px을 0.5배로 쓴다(24 논리px, docs/design/pixel-art.md 표시 크기). 배율 2·4에서 정수다.
const TEXTURE_SCALE: float = 0.5
const DIE_SIZE: float = 24.0
const DIE_SPACING: float = 4.0
## 주사위 줄(24) 아래에 판정 단어 줄(12)을 둔 패널. 머리 위에서는 아랫변이 머리 점이다.
const WORD_ROW_Y: float = 24.0
const WORD_ROW_HEIGHT: float = 12.0
const PANEL_SIZE: Vector2 = Vector2(140.0, 36.0)
## 화면 밖 주사위 자리의 윗변. 턴 순서 막대(y 86) 아래이고 맵 중앙 영역 C(y 128~)와 겹치지 않는다.
const OFFSCREEN_TOP: float = 90.0
## 머리 위 점: 상태 글자 자리(get_status_label_y) 윗변에서 2 논리px 위.
const HEAD_RISE: float = 14.0
const SIDE_LABEL_GAP: float = 3.0
const SIDE_LABEL_WIDTH: float = 60.0
const POINTER_SIZE: float = 5.0
const OUTLINE_SIZE: int = 2
## 주사위·글자 묶음을 감싸는 반투명 배경 패널 여백과 색(#727).
const BACKDROP_PAD: Vector2 = Vector2(5.0, 3.0)
const BACKDROP_FILL: Color = Color(0.07058824, 0.10196079, 0.13333334, 0.84)
const BACKDROP_BORDER: Color = Color(0.38039216, 0.44313726, 0.49411765, 0.9)
const DIE_FILL: Color = Color("202b35")
const NEUTRAL_COLOR: Color = Color("f4ead1")
const SUCCESS_COLOR: Color = CombatUnit.HEAL_COLOR
const FAILURE_COLOR: Color = CombatUnit.ENEMY_COLOR
const ABSOLUTE_COLOR: Color = Color("f4cf69")
const DISCARDED_ALPHA: float = 0.35
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
## 액체 높이가 보이는 여유의 범위. 기준값 양쪽으로 이만큼이고 넘으면 끝에 붙는다.
const GAUGE_RANGE: int = 6
const WORD_FONT_SIZE: int = 13
const ABSOLUTE_WORD_FONT_SIZE: int = 16


class Die extends RefCounted:
	var shown: int = 1
	var alpha: float = 1.0
	## 그림 상태: rolling 또는 success·failure·absolute_success·absolute_failure.
	var state: String = "rolling"
	## 판정에 쓰인 주사위. 유리·불리에서 버린 쪽은 액체와 기준선을 그리지 않는다.
	var applied: bool = true


static var _textures: Dictionary[String, Texture2D] = {}
static var _liquid_rows: Dictionary[int, Vector2i] = {}

var _roll: CombatDiceRoll
var _dice: Array[Die] = []
var _elapsed: float = 0.0
var _last_step: int = -1
## 지금 굴림 프레임(0~3)과 멈춘 뒤 지난 시간, 사라지는 동안 떠오른 논리px. 화면에만 있다.
var _frame: int = 0
var _settled_elapsed: float = 0.0
var _lift: int = 0
var _tumbling: bool = false
var _selected: int = 0
var _final_margin: float = 0.0
## 멈춘 뒤에만 액체와 합계 식을 보인다.
var _settled: bool = false
## 패널 왼쪽 위(화면 논리 좌표)와 화면 밖 자리에 있는지. 굴리는 유닛을 따라 매 프레임 다시 정한다.
var _origin: Vector2 = Vector2.ZERO
var _offscreen: bool = false
var _head: Vector2 = Vector2.INF
var _summary_text: String = ""
## 먼저 온 굴림부터 하나씩 보인다. _tickets는 받은 굴림 수, _serving은 지금 보이는 차례다.
var _tickets: int = 0
var _serving: int = 0
## 화면용 난수. 게임의 주사위 순서와 저장 상태에 영향을 주지 않는다.
var _visual_rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _summary: Label
var _target: Label
var _total: Label
var _backdrop: Control
var _backdrop_rect: Rect2 = Rect2()
var _art: Control
var _pointer: Control
var _roll_player: AudioStreamPlayer
var _success_player: AudioStreamPlayer
var _failure_player: AudioStreamPlayer
var _fade: Tween


func _ready() -> void:
	theme = UI_THEME
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	set_process(false)
	hidden.connect(set_process.bind(false))
	_visual_rng.randomize()
	_backdrop = _make_layer("Backdrop")
	_backdrop.draw.connect(_draw_backdrop)
	_art = _make_layer("Art")
	_art.material = PIXEL_ART
	_art.draw.connect(_draw_art)
	_pointer = _make_layer("Pointer")
	_pointer.draw.connect(_draw_pointer)
	_target = _make_label("Target", HORIZONTAL_ALIGNMENT_RIGHT)
	_total = _make_label("Total", HORIZONTAL_ALIGNMENT_LEFT)
	_summary = _make_label("Summary", HORIZONTAL_ALIGNMENT_CENTER)
	_summary.size = Vector2(PANEL_SIZE.x, WORD_ROW_HEIGHT)
	_roll_player = _make_player("RollSound", SoundVariants.build(
		SoundVariants.variant_paths("res://scenes/combat/audio/", "dice_roll", ROLL_SOUND_VARIANTS), ROLL_SOUND_PITCH))
	_success_player = _make_player("SuccessSound", SUCCESS_SOUND)
	_failure_player = _make_player("FailureSound", FAILURE_SOUND)


## 굴리고 결과를 잠시 보인 뒤 페이드아웃한다. 앞 굴림이 보이는 중이면 그 결과가 닫힐 때까지 차례를 기다린다.
## 기다리지 않는 굴림(독 제거·만능팔)과 기다리는 굴림(명중·회전회오리)이 같은 차례 줄에 선다.
func play(roll: CombatDiceRoll) -> void:
	var ticket: int = _tickets
	_tickets += 1
	while ticket != _serving:
		await _turn_passed
	_begin(roll)
	await get_tree().create_timer(TUMBLE_TIME, false).timeout
	_settle()
	await get_tree().create_timer(hold_time(roll), false).timeout
	_fade = create_tween()
	_fade.set_parallel(true)
	_fade.tween_property(self, "modulate:a", 0.0, FADE_TIME)
	_fade.tween_method(_set_lift, 0.0, FADE_TIME, FADE_TIME)
	_fade.chain().tween_callback(hide)
	_serving += 1
	_turn_passed.emit()


## 명중굴림의 절대성공·절대실패인가. 결과를 오래 보이고 배경음을 낮추는 굴림이다.
static func is_absolute_hit(roll: CombatDiceRoll) -> bool:
	return roll.category == CombatDiceRoll.Category.HIT and roll.result.face != CombatChecks.Face.NORMAL


## 결과가 멈출 때 배경음을 낮추는 굴림(#632). 내성굴림의 절대면은 낮추지 않는다.
static func ducks_music(roll: CombatDiceRoll) -> bool:
	return is_absolute_hit(roll)


## 결과를 보이는 시간. 명중굴림의 절대면만 늘린다.
static func hold_time(roll: CombatDiceRoll) -> float:
	if is_absolute_hit(roll):
		return ABSOLUTE_HIT_HOLD_TIME
	return HOLD_TIME


## 합계와 기준값의 차이. 양수면 기준을 넘긴 만큼이다.
static func margin(result: CombatChecks.RollResult, target_value: int) -> int:
	return result.total - target_value


## 굴린 지 elapsed초일 때의 굴림 프레임. 눈 바꾸기 단계(FACE_CHANGES)와 같이 넘어간다.
static func rolling_frame(elapsed: float) -> int:
	return rolling_step(elapsed) % ROLLING_FRAMES


## 굴린 지 elapsed초일 때의 눈 바꾸기 단계(0~FACE_CHANGES).
static func rolling_step(elapsed: float) -> int:
	return int(clampf(elapsed / TUMBLE_TIME, 0.0, 1.0) * FACE_CHANGES)


## 주사위 칸의 움직임(논리px). 굴리는 동안은 홀수 단계에 위로 튀고,
## 멈춘 뒤에는 실패가 가로로 흔들리고 절대실패가 한 번 내려앉으며 EFFECT_TIME 뒤에는 0이다.
static func die_offset(result: CombatChecks.RollResult, tumbling: bool, step: int, settled_elapsed: float) -> Vector2i:
	if tumbling:
		return Vector2i(0, -1 if step % 2 == 1 else 0)
	if settled_elapsed < 0.0 or settled_elapsed >= EFFECT_TIME:
		return Vector2i.ZERO
	if result.face == CombatChecks.Face.ABSOLUTE_FAILURE:
		return Vector2i(0, 1 if settled_elapsed < SINK_TIME else 0)
	if result.face == CombatChecks.Face.ABSOLUTE_SUCCESS or result.success:
		return Vector2i.ZERO
	var index: int = int(settled_elapsed / SHAKE_STEP_TIME)
	return Vector2i(SHAKE_PATTERN[index] if index < SHAKE_PATTERN.size() else 0, 0)


## 차오르는 액체 표면 행(48 원본 px). 바닥 아래(bottom + 1)에서 시작해 RISE_TIME 동안 target 행에 닿는다.
static func rising_surface(_top: int, bottom: int, target: int, settled_elapsed: float) -> int:
	if settled_elapsed >= RISE_TIME:
		return target
	return bottom + 1 - roundi((bottom + 1 - target) * clampf(settled_elapsed, 0.0, RISE_TIME) / RISE_TIME)


## 절대면의 불티(절대성공)·파편(절대실패) 위치. 주사위 가운데 기준 정수 논리px이고 EFFECT_TIME 뒤에는 비어 있다.
static func effect_pixels(face: CombatChecks.Face, settled_elapsed: float) -> PackedVector2Array:
	var points: PackedVector2Array = PackedVector2Array()
	if settled_elapsed < 0.0 or settled_elapsed >= EFFECT_TIME:
		return points
	var progress: float = settled_elapsed / EFFECT_TIME
	match face:
		CombatChecks.Face.ABSOLUTE_SUCCESS:
			var radius: float = lerpf(SPARK_RADIUS_FROM, SPARK_RADIUS_TO, progress)
			for degrees: int in SPARK_DEGREES:
				points.append((Vector2.from_angle(deg_to_rad(degrees)) * radius).round())
		CombatChecks.Face.ABSOLUTE_FAILURE:
			for start: Vector2i in SHARD_START:
				points.append(Vector2(start.x, start.y + roundf(SHARD_FALL * progress)))
	return points


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


## 여유를 액체 표면 행(48 원본 px)으로 옮긴다. top·bottom은 액체 마스크의 첫·마지막 행이다.
## 여유 -6이면 바닥(bottom + 1), +6이면 꼭대기(top)이고 넘으면 끝에 붙는다. draw_dice.py의 sheet_cell과 같은 식이다.
static func liquid_surface(top: int, bottom: int, gap: int) -> int:
	var clamped: int = clampi(gap, -GAUGE_RANGE, GAUGE_RANGE)
	return bottom + 1 - roundi((bottom + 1 - top) * (clamped + GAUGE_RANGE) / float(2 * GAUGE_RANGE))


## 멈춘 뒤 합계 옆에 보이는 식. 보정이 음수여도 0이어도 늘 같은 꼴이다. 절대면은 굴린 눈만 보인다.
static func total_text(result: CombatChecks.RollResult) -> String:
	if result.face != CombatChecks.Face.NORMAL:
		return str(result.selected_roll)
	var added: int = result.added()
	return "%d = %d%s%d" % [result.total, result.selected_roll, "-" if added < 0 else "+", absi(added)]


## 면 수와 상태의 주사위 그림. 그림이 없으면 null이다.
static func die_texture(sides: int, state: String, frame: int = 0) -> Texture2D:
	if not ART_SIDES.has(sides) or not ART_STATES.has(state):
		return null
	if state == "rolling" and frame > 0:
		if frame >= ROLLING_FRAMES:
			return null
		return _load_texture("%sd%d_rolling_%d.png" % [DICE_DIR, sides, frame])
	return _load_texture("%sd%d_%s.png" % [DICE_DIR, sides, state])


## 몸체 안쪽 유리의 흰 실루엣. 런타임이 높이로 자르고 색을 곱한다.
static func liquid_texture(sides: int) -> Texture2D:
	if not ART_SIDES.has(sides):
		return null
	return _load_texture("%sd%d_liquid.png" % [DICE_DIR, sides])


## 액체 마스크의 첫·마지막 행. 그림이 없는 면 수는 가운데 24행을 쓴다.
static func liquid_rows(sides: int) -> Vector2i:
	if _liquid_rows.has(sides):
		return _liquid_rows[sides]
	var rows: Vector2i = Vector2i(12, 35)
	var mask: Texture2D = liquid_texture(sides)
	if mask != null:
		var image: Image = mask.get_image()
		rows = Vector2i(image.get_height(), -1)
		for y: int in range(image.get_height()):
			for x: int in range(image.get_width()):
				if image.get_pixel(x, y).a > 0.0:
					rows = Vector2i(mini(rows.x, y), maxi(rows.y, y))
					break
	_liquid_rows[sides] = rows
	return rows


## 패널 왼쪽 위. head는 굴리는 유닛 머리 위 점(화면 논리 좌표)이고 패널 아랫변 가운데가 된다.
## 패널이 화면을 벗어나면 화면 밖 자리(가운데 위, 턴 순서 막대 아래)다. 모두 정수 논리 px이다.
static func panel_origin(head: Vector2, panel: Vector2, screen: Rect2) -> Vector2:
	if is_offscreen(head, panel, screen):
		return Vector2(roundf(screen.position.x + (screen.size.x - panel.x) * 0.5), OFFSCREEN_TOP)
	return (head - Vector2(panel.x * 0.5, panel.y)).round()


## 화면 안에 있어야 하는 폭. 기준값·합계 글자와 배경 패널 여백(#727)은 주사위 묶음 양옆으로 패널 밖까지 나가므로 그 폭을 더한다.
static func footprint(dice_count: int) -> Vector2:
	var group: float = dice_count * DIE_SIZE + maxi(0, dice_count - 1) * DIE_SPACING
	return Vector2(maxf(PANEL_SIZE.x, group + 2.0 * (SIDE_LABEL_GAP + SIDE_LABEL_WIDTH)) + 2.0 * BACKDROP_PAD.x,
		PANEL_SIZE.y + 2.0 * BACKDROP_PAD.y)


static func is_offscreen(head: Vector2, panel: Vector2, screen: Rect2) -> bool:
	if not head.is_finite():
		return true
	return not screen.encloses(Rect2((head - Vector2(panel.x * 0.5, panel.y)).round(), panel))


static func _load_texture(path: String) -> Texture2D:
	if not _textures.has(path):
		_textures[path] = load(path) as Texture2D
	return _textures[path]


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
	player.bus = GameSettings.BUS_SFX
	player.max_polyphony = SOUND_POLYPHONY
	add_child(player)
	return player


func _make_layer(layer_name: String) -> Control:
	var layer: Control = Control.new()
	layer.name = layer_name
	layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(layer)
	return layer


func _make_label(label_name: String, alignment: HorizontalAlignment) -> Label:
	var label: Label = Label.new()
	label.name = label_name
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.horizontal_alignment = alignment
	label.add_theme_color_override("font_outline_color", CombatUnit.OUTLINE_COLOR)
	label.add_theme_constant_override("outline_size", OUTLINE_SIZE)
	add_child(label)
	return label


func _begin(roll: CombatDiceRoll) -> void:
	if _fade != null:
		_fade.kill()
	modulate.a = 1.0
	_roll = roll
	_dice.clear()
	for index: int in range(roll.result.rolls.size()):
		_dice.append(Die.new())
	_selected = maxi(0, roll.result.rolls.find(roll.result.selected_roll))
	_elapsed = 0.0
	_last_step = -1
	_frame = 0
	_settled_elapsed = 0.0
	_lift = 0
	_tumbling = true
	_settled = false
	_final_margin = clampf(margin(roll.result, roll.target_value), -GAUGE_RANGE, GAUGE_RANGE)
	_target.text = "%s %d" % [roll.target_label, roll.target_value]
	_target.add_theme_color_override("font_color", NEUTRAL_COLOR)
	_total.text = str(_dice[_selected].shown)
	_total.add_theme_color_override("font_color", NEUTRAL_COLOR)
	_summary_text = ""
	_summary.text = ""
	visible = true
	set_process(true)
	_update_layout()
	_roll_player.play()
	_art.queue_redraw()


func _process(delta: float) -> void:
	if _roll == null:
		return
	if _tumbling:
		_elapsed += delta
		var step: int = rolling_step(_elapsed)
		if step != _last_step:
			_last_step = step
			_frame = rolling_frame(_elapsed)
			for die: Die in _dice:
				die.shown = _visual_rng.randi_range(1, _roll.sides)
			_total.text = str(_dice[_selected].shown)
	else:
		_settled_elapsed += delta
	_update_layout()


## 사라지는 동안 위로 떠오른 논리px. 정수 단계로만 움직여 텍셀이 정수 화면 px에 놓인다.
func _set_lift(elapsed: float) -> void:
	_lift = mini(LIFT_MAX, int(elapsed / LIFT_STEP_TIME))


func _settle() -> void:
	_tumbling = false
	_settled_elapsed = 0.0
	var result: CombatChecks.RollResult = _roll.result
	var color: Color = SUCCESS_COLOR if result.success else FAILURE_COLOR
	var absolute: bool = result.face != CombatChecks.Face.NORMAL
	var state: String = "success" if result.success else "failure"
	if absolute:
		state = "absolute_" + state
	for index: int in range(_dice.size()):
		_dice[index].shown = result.rolls[index]
		_dice[index].state = state
		_dice[index].applied = index == _selected
		if _dice.size() > 1 and index != _selected:
			_dice[index].alpha = DISCARDED_ALPHA
	_settled = true
	_total.text = total_text(result)
	_total.add_theme_color_override("font_color", color)
	_summary_text = _result_text(absolute)
	_summary.add_theme_color_override("font_color", color)
	_summary.add_theme_font_size_override("font_size", ABSOLUTE_WORD_FONT_SIZE if absolute else WORD_FONT_SIZE)
	(_success_player if result.success else _failure_player).play()
	if ducks_music(_roll):
		GameMusic.duck(get_tree())
	_update_layout()
	_art.queue_redraw()


## 판정 단어와 여유. 식은 보이지 않는다. 절대면은 여유가 의미 없어 단어만 보인다.
func _result_text(absolute: bool) -> String:
	var word: String = grade_word(grade(_roll.result, _roll.target_value))
	if absolute:
		return word
	var gap: int = margin(_roll.result, _roll.target_value)
	return "%s  %s" % [word, "±0" if gap == 0 else "%+d" % gap]


## 굴리는 유닛 머리 위 점(화면 논리 좌표). 유닛이 없거나 장면 밖이면 INF다.
func _head_point() -> Vector2:
	var roller: CombatUnit = _roll.roller
	if roller == null or not is_instance_valid(roller) or not roller.is_inside_tree():
		return Vector2.INF
	var local: Vector2 = Vector2(0.0, roller.floor_offset_y + roller.get_status_label_y() - HEAD_RISE)
	return roller.get_global_transform_with_canvas() * local


## 굴리는 유닛을 따라 패널을 옮긴다. 화면 밖이면 정해진 자리에 두고 유닛 이름과 방향을 더한다.
func _update_layout() -> void:
	if _roll == null:
		return
	_head = _head_point()
	var screen: Rect2 = get_viewport_rect()
	_offscreen = is_offscreen(_head, footprint(_dice.size()), screen)
	_origin = panel_origin(Vector2.INF if _offscreen else _head, PANEL_SIZE, screen)
	var group: float = _group_width()
	var base: Vector2 = _origin - Vector2(0.0, _lift)
	var left: float = base.x + PANEL_SIZE.x * 0.5 - group * 0.5
	var rows: Vector2i = liquid_rows(_roll.sides)
	var line_y: float = base.y + ((rows.x + rows.y + 1) >> 1) * TEXTURE_SCALE
	var total_row: int = (rows.x + rows.y + 1) >> 1
	if _settled:
		total_row = _surface_row(rows)
	var total_y: float = base.y + total_row * TEXTURE_SCALE
	_target.size.x = SIDE_LABEL_WIDTH
	_target.position = Vector2(roundf(left - SIDE_LABEL_GAP - SIDE_LABEL_WIDTH),
		roundf(line_y - _target.size.y * 0.5))
	_total.position = Vector2(roundf(left + group + SIDE_LABEL_GAP), roundf(total_y - _total.size.y * 0.5))
	var word: String = _summary_text
	if _offscreen and _roll.roller != null and is_instance_valid(_roll.roller):
		var owner_name: String = _roll.roller.get_display_name()
		word = owner_name if word.is_empty() else "%s · %s" % [owner_name, word]
	_summary.text = word
	_summary.position = Vector2(base.x, roundf(base.y + WORD_ROW_Y + (WORD_ROW_HEIGHT - _summary.size.y) * 0.5))
	_backdrop_rect = _compute_backdrop_rect(base, left, group)
	_backdrop.queue_redraw()
	_art.queue_redraw()
	_pointer.queue_redraw()


## 주사위·기준값·합계·판정 단어 줄을 모두 감싸는 배경 패널 사각형(정수 논리 px, #727).
func _compute_backdrop_rect(base: Vector2, left: float, group: float) -> Rect2:
	var font: Font = get_theme_default_font()
	var target_width: float = _target.get_minimum_size().x
	if font != null and not _target.text.is_empty():
		target_width = maxf(target_width, font.get_string_size(_target.text, HORIZONTAL_ALIGNMENT_LEFT, -1,
			get_theme_default_font_size()).x)
	var total_width: float = _total.get_minimum_size().x
	if font != null and not _total.text.is_empty():
		total_width = maxf(total_width, font.get_string_size(_total.text, HORIZONTAL_ALIGNMENT_LEFT, -1,
			get_theme_default_font_size()).x)
	var min_x: float = left - SIDE_LABEL_GAP - target_width
	var max_x: float = left + group + SIDE_LABEL_GAP + total_width
	var min_y: float = minf(base.y, minf(_target.position.y, _total.position.y))
	var max_y: float = maxf(base.y + DIE_SIZE, maxf(_target.position.y + _target.size.y, _total.position.y + _total.size.y))
	if not _summary.text.is_empty():
		var summary_size: int = _summary.get_theme_font_size("font_size")
		var summary_width: float = _summary.get_minimum_size().x
		if font != null:
			summary_width = maxf(summary_width, font.get_string_size(_summary.text, HORIZONTAL_ALIGNMENT_LEFT, -1, summary_size).x)
		var center_x: float = base.x + PANEL_SIZE.x * 0.5
		min_x = minf(min_x, center_x - summary_width * 0.5)
		max_x = maxf(max_x, center_x + summary_width * 0.5)
		max_y = maxf(max_y, maxf(base.y + PANEL_SIZE.y, _summary.position.y + _summary.size.y))
	var top_left: Vector2 = Vector2(floorf(min_x - BACKDROP_PAD.x), floorf(min_y - BACKDROP_PAD.y))
	var bottom_right: Vector2 = Vector2(ceilf(max_x + BACKDROP_PAD.x), ceilf(max_y + BACKDROP_PAD.y))
	return Rect2(top_left, bottom_right - top_left)


func _draw_backdrop() -> void:
	if _roll == null or _dice.is_empty() or _backdrop_rect.size == Vector2.ZERO:
		return
	_backdrop.draw_rect(_backdrop_rect, BACKDROP_FILL, true)
	_backdrop.draw_rect(_backdrop_rect, BACKDROP_BORDER, false, 1.0)


func _group_width() -> float:
	return _dice.size() * DIE_SIZE + maxi(0, _dice.size() - 1) * DIE_SPACING


## 멈춘 뒤 액체 표면 행. 절대성공은 가득, 절대실패는 바닥 한 줄이다.
func _surface_row(rows: Vector2i) -> int:
	match _roll.result.face:
		CombatChecks.Face.ABSOLUTE_SUCCESS:
			return rows.x
		CombatChecks.Face.ABSOLUTE_FAILURE:
			return rows.y
	return liquid_surface(rows.x, rows.y, margin(_roll.result, _roll.target_value))


func _draw_art() -> void:
	if _roll == null or _dice.is_empty():
		return
	var rows: Vector2i = liquid_rows(_roll.sides)
	var mask: Texture2D = liquid_texture(_roll.sides)
	var base: Vector2 = _origin - Vector2(0.0, _lift)
	var left: float = base.x + PANEL_SIZE.x * 0.5 - _group_width() * 0.5
	var offset: Vector2 = Vector2(die_offset(_roll.result, _tumbling, _last_step, _settled_elapsed))
	for index: int in range(_dice.size()):
		var die: Die = _dice[index]
		var slot: Rect2 = Rect2(Vector2(left + index * (DIE_SIZE + DIE_SPACING), base.y), Vector2.ONE * DIE_SIZE)
		# 굴리는 동안은 모든 주사위가 튀고, 멈춘 뒤 흔들림·내려앉음은 적용한 주사위만 받는다.
		var rect: Rect2 = Rect2(slot.position + (offset if _tumbling or die.applied else Vector2.ZERO), slot.size)
		var tint: Color = Color(1.0, 1.0, 1.0, die.alpha)
		var texture: Texture2D = die_texture(_roll.sides, die.state, _frame)
		if texture != null:
			_art.draw_texture_rect(texture, rect, false, tint)
		else:
			_draw_vector_die(rect, die)
		if mask == null or not die.applied:
			continue
		if _settled:
			var target: int = _surface_row(rows)
			var surface: int = target
			if _roll.result.face != CombatChecks.Face.ABSOLUTE_FAILURE:
				surface = rising_surface(rows.x, rows.y, target, _settled_elapsed)
			var liquid: Color = SUCCESS_COLOR if _roll.result.success else FAILURE_COLOR
			_art.draw_texture_rect_region(mask, Rect2(rect.position + Vector2(0.0, surface * TEXTURE_SCALE),
				Vector2(DIE_SIZE, (rows.y + 1 - surface) * TEXTURE_SCALE)),
				Rect2(0, surface, 48, rows.y + 1 - surface), liquid)
			_draw_effect(rect)
		# 기준값 가로선은 굴리는 동안 튀지 않고, 멈춘 뒤에는 주사위와 함께 움직인다.
		var line_rect: Rect2 = slot if _tumbling else rect
		var line_row: int = (rows.x + rows.y + 1) >> 1
		_art.draw_texture_rect_region(mask, Rect2(line_rect.position + Vector2(0.0, line_row * TEXTURE_SCALE),
			Vector2(DIE_SIZE, TEXTURE_SCALE)), Rect2(0, line_row, 48, 1), NEUTRAL_COLOR)


## 절대면의 불티(금색)·파편(보라)을 주사위 둘레에 1 논리px로 찍고 효과가 끝나갈수록 흐리게 한다.
func _draw_effect(rect: Rect2) -> void:
	var face: CombatChecks.Face = _roll.result.face
	var color: Color = ABSOLUTE_COLOR if face == CombatChecks.Face.ABSOLUTE_SUCCESS else SHARD_COLOR
	color.a = 1.0 - _settled_elapsed / EFFECT_TIME
	for point: Vector2 in effect_pixels(face, _settled_elapsed):
		_art.draw_rect(Rect2(rect.get_center() + point, Vector2.ONE), color)


## 그림이 없는 면 수는 같은 24 논리px 칸에 벡터 윤곽으로 그린다.
func _draw_vector_die(rect: Rect2, die: Die) -> void:
	var points: PackedVector2Array = shape_points(_roll.sides)
	var scaled: PackedVector2Array = PackedVector2Array()
	for point: Vector2 in points:
		scaled.append(rect.get_center() + point * DIE_SIZE * 0.5)
	var edge: Color = NEUTRAL_COLOR
	if _settled:
		edge = SUCCESS_COLOR if _roll.result.success else FAILURE_COLOR
	_art.draw_colored_polygon(scaled, Color(DIE_FILL, die.alpha))
	scaled.append(scaled[0])
	_art.draw_polyline(scaled, Color(edge, die.alpha), 1.0)


## 화면 밖 패널에서 굴리는 유닛 쪽을 가리키는 작은 삼각형.
func _draw_pointer() -> void:
	if _roll == null or not _offscreen or not _head.is_finite():
		return
	var box: Rect2 = _backdrop_rect if _backdrop_rect.size != Vector2.ZERO else Rect2(_origin, PANEL_SIZE)
	var center: Vector2 = box.get_center()
	var direction: Vector2 = (_head - center).normalized()
	if direction == Vector2.ZERO:
		return
	var half: Vector2 = box.size * 0.5
	var reach: float = minf(half.x / maxf(absf(direction.x), 0.001), half.y / maxf(absf(direction.y), 0.001))
	var base: Vector2 = center + direction * (reach + 1.0)
	var side: Vector2 = direction.orthogonal() * POINTER_SIZE * 0.6
	_pointer.draw_colored_polygon(PackedVector2Array([base + direction * POINTER_SIZE, base + side, base - side]),
		NEUTRAL_COLOR)
