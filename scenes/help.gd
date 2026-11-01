class_name HelpScreen
extends ColorRect
## 조작과 능력치 판정·유리/불리·반응을 적은 정적 도움말 화면 (#287). 처음 실행할 때 저절로 열지 않는다.
## 타이틀은 이 장면을 넣어 두고 `open()`을 부른다. 일시정지 메뉴(#286)도 같은 방법으로 연다.

## 닫혔을 때. 연 화면이 자기 버튼으로 포커스를 되돌린다.
signal closed

## 위아래 입력 한 번에 스크롤하는 거리(논리 px). 출처 화면과 같다.
const SCROLL_STEP: int = 24

@onready var scroll: ScrollContainer = %HelpScroll
@onready var back_button: Button = %HelpBack


func _ready() -> void:
	back_button.pressed.connect(close)


func open() -> void:
	show()
	scroll.scroll_vertical = 0
	back_button.grab_focus()


func close() -> void:
	hide()
	closed.emit()


## 포커스는 `뒤로` 하나라 키보드·컨트롤러의 위아래 입력은 글을 스크롤한다.
func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("ui_cancel"):
		close()
	elif event.is_action_pressed("ui_down", true):
		scroll.scroll_vertical += SCROLL_STEP
	elif event.is_action_pressed("ui_up", true):
		scroll.scroll_vertical -= SCROLL_STEP
	else:
		return
	get_viewport().set_input_as_handled()
