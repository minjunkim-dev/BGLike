class_name HoverTooltip
extends PanelContainer
## 마우스 호버와 키보드·컨트롤러 포커스에 대상의 tooltip_text를 0.5초 뒤 띄운다(#226, #248, #274).
## 스킬 바와 정비 화면이 같은 모양·시점을 쓴다. 화면을 채우는 부모 Control 안에 두고, 설명은 부모 밖으로 나가지 않는다.

## 줄 역할별 글자 색(#620). 값은 도트 아트 기준 UI 팔레트다.
const TITLE_COLOR: Color = Color("ebba84")
const BODY_COLOR: Color = Color("f5ebdb")
const DETAIL_COLOR: Color = Color("c5b29f")

## 기본 툴팁 창 대신 이 설명을 쓰는 버튼.
class HoverButton extends Button:
	func _get_tooltip(_at_position: Vector2) -> String:
		return ""

## 참이면 설명을 숨긴다. 앞을 가리는 창이 열렸을 때 쓴다.
var hidden_when: Callable = func() -> bool: return false
## 0이면 자동 줄바꿈 없이 tooltip_text의 줄 그대로 그린다(정비 화면). 0보다 크면 설명 패널의 바깥 폭이 이 값을 넘지 않고,
## 줄바꿈 없이 이 폭에 들어가는 설명은 그 글 폭만큼만 차지한다(#619).
var max_width: float = 0.0
## 비어 있으면 설명을 대상 위(모자라면 아래)의 대상 x에 둔다. 있으면 (대상 Control, 설명 크기)를 받아 설명의 global 위치를 돌려준다.
## 어느 쪽이든 부모 영역 안으로 민다.
var place: Callable = Callable()
## 대상 Control을 받아 그 설명의 BBCode 글을 돌려준다. 전투 HUD만 쓴다(줄 역할별 색 #620, 수치 가감 색 #457).
## 비어 있으면 tooltip_text를 원문 그대로 보인다(정비 화면).
var format: Callable = Callable()

var _owner: Control
var _label: RichTextLabel = RichTextLabel.new()
var _timer: Timer = Timer.new()
var _shown_text: String = ""


func _init() -> void:
	z_index = 10
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	theme_type_variation = &"HudPanel"
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# 수치 가감은 색과 부호로 구분한다(#457). 줄바꿈은 기본으로 tooltip_text 그대로 쓰므로 자동 줄바꿈은 끈다(max_width로 켠다).
	_label.bbcode_enabled = true
	_label.fit_content = true
	_label.scroll_active = false
	_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	add_child(_label)
	hide()
	_timer.one_shot = true
	_timer.wait_time = 0.5
	_timer.timeout.connect(_update)
	add_child(_timer)


## 글을 color로 칠한 BBCode. 수치 가감 색(#457)은 그 안에서 그대로 남는다. 빈 글은 빈 글이다.
static func paint(text: String, color: Color) -> String:
	if text.is_empty():
		return ""
	return "[color=#%s]%s[/color]" % [color.to_html(false), CombatActionRules.colorize(text)]


## 첫 줄은 강조 글자, 나머지 줄은 본문 글자로 칠한 BBCode. 초상·패시브 설명이 쓴다.
static func headed(text: String) -> String:
	var lines: PackedStringArray = text.split("\n")
	var rest: String = "\n".join(lines.slice(1))
	var result: String = paint(lines[0], TITLE_COLOR)
	if not rest.is_empty():
		result += "\n" + paint(rest, BODY_COLOR)
	return result


func attach(control: Control) -> void:
	var start: Callable = func() -> void:
		# 호버 중 클릭으로 포커스를 받아도 떠 있는 설명을 다시 기다리게 하지 않는다.
		if _owner == control and (visible or not _timer.is_stopped()):
			return
		_owner = control
		hide()
		_timer.start()
	var stop: Callable = func() -> void:
		if _owner == control:
			_owner = null
			_timer.stop()
			hide()
	control.mouse_entered.connect(start)
	control.mouse_exited.connect(stop)
	# 키보드·컨트롤러 포커스도 같은 설명을 띄운다. 클릭으로 받은 포커스는 마우스가 떠나면 숨긴다.
	control.focus_entered.connect(start)
	control.focus_exited.connect(stop)


func _process(_delta: float) -> void:
	if visible:
		_update()


func _update() -> void:
	if not is_instance_valid(_owner) or not _owner.is_visible_in_tree() or _owner.tooltip_text.is_empty() \
		or hidden_when.call():
		hide()
		return
	# 글자는 BBCode다. 꺼진 경우도 [를 태그가 아닌 글자로 쓴다.
	var text: String = format.call(_owner) if format.is_valid() else _owner.tooltip_text.replace("[", "[lb]")
	if text != _shown_text:
		_shown_text = text
		_label.text = text
		_fit_width()
	size = get_combined_minimum_size()
	var rect: Rect2 = _owner.get_global_rect()
	var bounds: Rect2 = get_parent_control().get_global_rect().grow(-4)
	var at: Vector2
	if place.is_valid():
		at = place.call(_owner, size)
	else:
		var y: float = rect.position.y - size.y - 4
		if y < bounds.position.y:
			y = rect.end.y + 4
		at = Vector2(rect.position.x, y)
	global_position = Vector2(
		clampf(at.x, bounds.position.x, bounds.end.x - size.x),
		clampf(at.y, bounds.position.y, bounds.end.y - size.y))
	show()


# max_width가 있으면 줄바꿈 없는 글 폭이 남는 폭을 넘을 때만 그 폭에서 줄바꿈한다. 글이 바뀔 때만 다시 잰다.
func _fit_width() -> void:
	_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	_label.custom_minimum_size.x = 0.0
	if max_width <= 0.0:
		return
	var available: float = max_width - get_theme_stylebox("panel").get_minimum_size().x
	if float(_label.get_content_width()) > available:
		_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_label.custom_minimum_size.x = available
