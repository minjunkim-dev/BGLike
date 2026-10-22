class_name HoverTooltip
extends PanelContainer
## 마우스 호버와 키보드·컨트롤러 포커스에 대상의 tooltip_text를 0.5초 뒤 띄운다(#226, #248, #274).
## 스킬 바와 정비 화면이 같은 모양·시점을 쓴다. 화면을 채우는 부모 Control 안에 두고, 설명은 부모 밖으로 나가지 않는다.

## 기본 툴팁 창 대신 이 설명을 쓰는 버튼.
class HoverButton extends Button:
	func _get_tooltip(_at_position: Vector2) -> String:
		return ""

## 참이면 설명을 숨긴다. 앞을 가리는 창이 열렸을 때 쓴다.
var hidden_when: Callable = func() -> bool: return false
## 설명 아래 끝을 둘 global y. 기본은 대상의 위 끝이다. 위 자리가 모자라면 대상 아래에 둔다.
var top_of: Callable = func(target: Control) -> float: return target.get_global_rect().position.y

var _owner: Control
var _label: Label = Label.new()
var _timer: Timer = Timer.new()


func _init() -> void:
	z_index = 10
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = Color("202b35")
	style.border_color = Color("61717e")
	style.set_border_width_all(1)
	style.content_margin_left = 4
	style.content_margin_right = 4
	style.content_margin_top = 3
	style.content_margin_bottom = 3
	add_theme_stylebox_override("panel", style)
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label.add_theme_font_size_override("font_size", 10)
	add_child(_label)
	hide()
	_timer.one_shot = true
	_timer.wait_time = 0.5
	_timer.timeout.connect(_update)
	add_child(_timer)


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
	_label.text = _owner.tooltip_text
	size = get_combined_minimum_size()
	var rect: Rect2 = _owner.get_global_rect()
	var bounds: Rect2 = get_parent_control().get_global_rect().grow(-4)
	var y: float = top_of.call(_owner) - size.y - 4
	if y < bounds.position.y:
		y = rect.end.y + 4
	global_position = Vector2(
		clampf(rect.position.x, bounds.position.x, bounds.end.x - size.x),
		clampf(y, bounds.position.y, bounds.end.y - size.y))
	show()
