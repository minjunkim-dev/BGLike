class_name HelpScreen
extends ColorRect
## 조작과 능력치 판정·유리/불리·반응을 적은 정적 도움말 화면 (#287). 처음 실행할 때 저절로 열지 않는다.
## 본문은 주제별 섹션 탭 8개로 나뉘고 한 번에 한 섹션만 보인다 (#557). 좌우 입력으로 탭을 옮긴다.
## 타이틀은 이 장면을 넣어 두고 `open()`을 부른다. 일시정지 메뉴(#286)도 같은 방법으로 연다.

## 닫혔을 때. 연 화면이 자기 버튼으로 포커스를 되돌린다.
signal closed

## 위아래 입력 한 번에 스크롤하는 거리(논리 px). 출처 화면과 같다.
const SCROLL_STEP: int = 24

@onready var scroll: ScrollContainer = %HelpScroll
@onready var back_button: Button = %HelpBack
@onready var tabs: TabBar = %HelpTabs
## 탭과 같은 순서의 섹션. 각 섹션의 첫 자식이 탭 제목이 되는 숨은 소제목이다.
var sections: Array[Control] = []


func _ready() -> void:
	back_button.pressed.connect(close)
	for section: Node in scroll.get_child(0).get_children():
		sections.append(section as Control)
		tabs.add_tab(tr((section.get_child(0) as Label).text))
	tabs.tab_changed.connect(show_section)
	show_section(0)


func open() -> void:
	show()
	show_section(0)
	back_button.grab_focus()


func section_count() -> int:
	return sections.size()


## index번째 섹션만 보이고 맨 위부터 읽는다. 범위를 벗어나면 끝에서 멈춘다.
func show_section(index: int) -> void:
	index = clampi(index, 0, sections.size() - 1)
	if tabs.current_tab != index:
		tabs.current_tab = index
		return  # tab_changed가 다시 이 함수를 부른다.
	for position: int in range(sections.size()):
		sections[position].visible = position == index
	scroll.scroll_vertical = 0


func close() -> void:
	hide()
	closed.emit()


## 포커스는 `뒤로` 하나라 키보드·컨트롤러의 위아래 입력은 글을 스크롤하고, 좌우 입력은 탭을 옮긴다.
func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("ui_cancel"):
		close()
	elif event.is_action_pressed("ui_left", true):
		show_section(tabs.current_tab - 1)
	elif event.is_action_pressed("ui_right", true):
		show_section(tabs.current_tab + 1)
	elif event.is_action_pressed("ui_down", true):
		scroll.scroll_vertical += SCROLL_STEP
	elif event.is_action_pressed("ui_up", true):
		scroll.scroll_vertical -= SCROLL_STEP
	else:
		return
	get_viewport().set_input_as_handled()
