class_name TitleScreen
extends Control
## 타이틀 화면. 게임은 여기서 시작하고 `새 게임`으로 1-1 전투에 간다 (#283).

## 전투·정비가 든 게임 장면. 검사도 이 장면을 직접 불러 전투부터 시작한다.
const GAME_SCENE: String = "res://scenes/game.tscn"
## 출처 화면에서 위아래 입력 한 번에 스크롤하는 거리(논리 px).
const SCROLL_STEP: int = 24

@onready var menu: VBoxContainer = %Menu
@onready var new_game_button: Button = %NewGame
@onready var continue_button: Button = %Continue
@onready var settings_button: Button = %Settings
@onready var credits_button: Button = %CreditsButton
@onready var quit_button: Button = %Quit
@onready var credits: Control = %Credits
@onready var credits_scroll: ScrollContainer = %CreditsScroll
@onready var back_button: Button = %Back


func _ready() -> void:
	var version: Dictionary = Engine.get_version_info()
	(%Engine as Label).text = tr("이 게임은 Godot Engine %d.%d.%d를 사용합니다. Godot Engine은 다음 MIT 라이선스를 따릅니다.") % [
		version.major, version.minor, version.patch]
	(%EngineLicense as Label).text = Engine.get_license_text()
	continue_button.visible = has_save()
	# 설정 화면은 #285가 이 버튼에 연결할 때까지 꺼 둔다.
	settings_button.disabled = true
	new_game_button.pressed.connect(func() -> void: get_tree().change_scene_to_file(GAME_SCENE))
	credits_button.pressed.connect(show_credits.bind(true))
	back_button.pressed.connect(show_credits.bind(false))
	quit_button.pressed.connect(get_tree().quit)
	new_game_button.grab_focus()


## 이어할 저장이 있는지. shortcut: #280 저장 모듈 전까지 항상 없음. #284가 저장 조회와 이어하기 동작으로 바꾼다.
func has_save() -> bool:
	return false


func show_credits(open: bool) -> void:
	credits.visible = open
	menu.visible = not open
	if open:
		credits_scroll.scroll_vertical = 0
		back_button.grab_focus()
	else:
		credits_button.grab_focus()


## 출처 화면의 포커스는 `뒤로` 하나라 키보드·컨트롤러의 위아래 입력은 글을 스크롤한다.
func _input(event: InputEvent) -> void:
	if not credits.visible:
		return
	if event.is_action_pressed("ui_cancel"):
		show_credits(false)
	elif event.is_action_pressed("ui_down", true):
		credits_scroll.scroll_vertical += SCROLL_STEP
	elif event.is_action_pressed("ui_up", true):
		credits_scroll.scroll_vertical -= SCROLL_STEP
	else:
		return
	get_viewport().set_input_as_handled()
