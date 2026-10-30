class_name TitleScreen
extends Control
## 타이틀 화면. 게임은 여기서 시작한다. `새 게임`은 1-1 전투, `이어하기`는 자동 저장한 자리로 간다 (#283, #284).

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
@onready var notice: Label = %Notice
@onready var overwrite: ConfirmationDialog = %Overwrite


func _ready() -> void:
	var version: Dictionary = Engine.get_version_info()
	(%Engine as Label).text = tr("이 게임은 Godot Engine %d.%d.%d를 사용합니다. Godot Engine은 다음 MIT 라이선스를 따릅니다.") % [
		version.major, version.minor, version.patch]
	(%EngineLicense as Label).text = Engine.get_license_text()
	_show_continue(has_save())
	# 설정은 게임 저장과 따로 보관하며 시작할 때 적용한다 (docs/adr/0003).
	GameSettings.apply()
	new_game_button.pressed.connect(_ask_new_game)
	continue_button.pressed.connect(continue_game)
	overwrite.ok_button_text = tr("새 게임")
	overwrite.cancel_button_text = tr("취소")
	overwrite.confirmed.connect(func() -> void:
		_hide_overwrite()
		start_new_game())
	overwrite.canceled.connect(func() -> void:
		_hide_overwrite()
		new_game_button.grab_focus())
	settings_button.pressed.connect(show_settings.bind(true))
	settings.closed.connect(show_settings.bind(false))
	help_button.pressed.connect(show_help.bind(true))
	help.closed.connect(show_help.bind(false))
	credits_button.pressed.connect(show_credits.bind(true))
	back_button.pressed.connect(show_credits.bind(false))
	quit_button.pressed.connect(get_tree().quit)
	new_game_button.grab_focus()


## 이어할 저장이 있는지. 파일이 있어도 읽을 수 없으면(깨짐, 다른 형식 버전) 없는 것으로 본다 (docs/adr/0003).
func has_save() -> bool:
	return GameSave.has_save() and not GameSave.read().is_empty()


## 저장이 있으면 덮어쓰기를 먼저 묻는다. 창에 그 저장의 막·스테이지를 보인다 (#209 9번).
func _ask_new_game() -> void:
	if not GameSave.has_save():
		start_new_game()
		return
	overwrite.dialog_text = tr("%s\n이 저장을 지우고 새 게임을 시작하시겠습니까?") % GameSave.summary_text(GameSave.read())
	overwrite.exclusive = true
	overwrite.popup_centered(Vector2i(360, 110))
	# 저장을 지우는 결정이라 연속 Enter로 확정하지 않게 `취소`를 기본 선택한다.
	overwrite.get_cancel_button().grab_focus()


func _hide_overwrite() -> void:
	# Godot 4.7.2 접근성이 제거 중인 exclusive child에 포커스를 보내지 않게 한다(일시정지 메뉴와 같다).
	overwrite.exclusive = false
	overwrite.hide()


## 저장을 지우고 처음 상태(빈 가방, 물약 0개)의 1-1 전투를 연다. 그때부터 행동마다 자동 저장한다.
func start_new_game() -> void:
	GameSave.delete()
	GameSave.autosave = true
	get_tree().change_scene_to_file(GAME_SCENE)


## 저장한 자리의 전투·보상·정비 화면을 연다. 저장이 맞지 않으면 타이틀에 남고 이어하기를 숨긴다.
## 첫 프레임 전에 복원해야 1-1 시작 상태가 저장을 덮지 않는다 (docs/adr/0003).
func continue_game() -> void:
	# 복원 전에는 쓰지 않고, 실패하면 스위치를 끈 채 둔다.
	GameSave.autosave = false
	var game: Node = (load(GAME_SCENE) as PackedScene).instantiate()
	get_tree().root.add_child(game)
	if not game.get_node("Battle").call("restore_save", GameSave.read().get("sections")):
		game.free()
		_show_continue(false)
		new_game_button.grab_focus()
		return
	GameSave.autosave = true
	get_tree().current_scene = game
	# 지워지는 프레임에 한 번 더 눌러 게임 장면을 둘 열지 않게 바로 숨긴다.
	hide()
	queue_free()


## 파일은 있는데 이어할 수 없으면 그 이유를 한 줄로 보인다. 새 게임은 덮어쓰기를 묻는다.
func _show_continue(can_continue: bool) -> void:
	continue_button.visible = can_continue
	notice.visible = GameSave.has_save() and not can_continue


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
