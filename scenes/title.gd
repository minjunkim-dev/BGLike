class_name TitleScreen
extends Control
## 타이틀 화면. 게임은 여기서 시작한다. `새 게임`은 1-1 전투, `이어하기`는 자동 저장한 자리로 간다 (#283, #284).

## 전투·정비가 든 게임 장면. 검사도 이 장면을 직접 불러 전투부터 시작한다.
const GAME_SCENE: String = "res://scenes/game.tscn"
## 출처 화면에서 위아래 입력 한 번에 스크롤하는 거리(논리 px).
const SCROLL_STEP: int = 24
## 디버그 테스트 진입(#512)이 고르는 스테이지 수: 3막 × 3스테이지.
const DEBUG_STAGE_COUNT: int = 9

## 디버그 테스트 진입을 여는지. 출시(release) 빌드는 false라 메뉴를 만들지 않는다. 검사가 출시 빌드 차단을 확인하려고 바꾼다.
static var debug_entry: bool = OS.is_debug_build()

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
## 디버그 빌드에서만 메뉴 끝에 만든다. 출시 빌드에서는 null이다.
var debug_stage: OptionButton


func _ready() -> void:
	var version: Dictionary = Engine.get_version_info()
	(%Engine as Label).text = tr("이 게임은 Godot Engine %d.%d.%d를 사용합니다. Godot Engine은 다음 MIT 라이선스를 따릅니다.") % [
		version.major, version.minor, version.patch]
	(%EngineLicense as Label).text = Engine.get_license_text()
	_show_continue(has_save())
	# 설정은 게임 저장과 따로 보관하며 시작할 때 적용한다 (docs/adr/0003).
	GameSettings.apply(get_window())
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
	if debug_entry:
		_add_debug_stage()
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


## 개발자용 메뉴라 번역하지 않는다. 첫 항목은 안내문이고 고를 수 없다.
func _add_debug_stage() -> void:
	debug_stage = OptionButton.new()
	debug_stage.name = "DebugStage"
	debug_stage.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	debug_stage.custom_minimum_size = Vector2(0, 20)
	debug_stage.add_item("테스트 진입 (디버그)")  # NO_TRANSLATE
	debug_stage.set_item_disabled(0, true)
	for index: int in range(DEBUG_STAGE_COUNT):
		var act: int = index / CombatActProgress.STAGES_PER_ACT + 1
		debug_stage.add_item("%d-%d" % [act, index % CombatActProgress.STAGES_PER_ACT + 1])
	debug_stage.select(0)
	# 항목 번호에서 안내문 한 칸을 빼면 스테이지 번호다.
	debug_stage.item_selected.connect(func(item: int) -> void: start_debug_stage(item - 1))
	menu.add_child(debug_stage)


## 고른 스테이지의 전투를 바로 연다. 자동 저장을 꺼서 사용자의 저장 파일을 읽지도 쓰지도 않는다.
## 파티는 새 게임 상태(빈 가방, 첫 레벨)다. 출시 빌드에서는 아무것도 하지 않는다.
func start_debug_stage(index: int) -> void:
	if not debug_entry or index < 0 or index >= DEBUG_STAGE_COUNT:
		return
	GameSave.autosave = false
	var game: Node = (load(GAME_SCENE) as PackedScene).instantiate()
	game.get_node("Battle").set("start_stage", index)
	get_tree().root.add_child(game)
	get_tree().current_scene = game
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
