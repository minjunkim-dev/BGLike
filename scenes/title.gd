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
@onready var settings: SettingsScreen = %SettingsScreen
@onready var help_button: Button = %HelpButton
@onready var help: HelpScreen = %Help
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
	# 설정은 게임 저장과 따로 보관하며 시작할 때 적용한다 (docs/adr/0003).
	GameSettings.apply()
	new_game_button.pressed.connect(func() -> void: get_tree().change_scene_to_file(GAME_SCENE))
	settings_button.pressed.connect(show_settings.bind(true))
	settings.closed.connect(show_settings.bind(false))
	help_button.pressed.connect(show_help.bind(true))
	help.closed.connect(show_help.bind(false))
	credits_button.pressed.connect(show_credits.bind(true))
	back_button.pressed.connect(show_credits.bind(false))
	quit_button.pressed.connect(get_tree().quit)
	new_game_button.grab_focus()


## 이어할 저장이 있는지. `이어하기`를 눌렀을 때 저장한 자리로 가는 동작은 #284가 연결한다.
func has_save() -> bool:
	return GameSave.has_save()


func show_settings(open: bool) -> void:
	menu.visible = not open
	if open:
		settings.open()
	else:
		settings_button.grab_focus()


func show_help(open: bool) -> void:
	menu.visible = not open
	if open:
		help.open()
	else:
		help_button.grab_focus()


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
