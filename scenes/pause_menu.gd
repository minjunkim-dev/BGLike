class_name PauseMenu
extends ColorRect
## 전투·정비 중 Esc·컨트롤러 Start로 여는 일시정지 메뉴 (#286). 열려 있는 동안 게임 트리를 멈춰
## 전투 입력과 적 행동(연출·타이머)이 서고, 이 메뉴와 설정·도움말·확인 창만 움직인다.

## `전투 포기`를 확정했을 때. 전투 화면이 전멸과 같은 패배로 처리한다.
signal give_up_confirmed

const TITLE_SCENE: String = "res://scenes/main.tscn"

## 확인 창의 `확인`이 할 일과 창을 연 버튼.
var _on_confirm: Callable
var _asked_from: Button
var _focus_before: Control

@onready var menu: VBoxContainer = %Menu
@onready var resume_button: Button = %Resume
@onready var settings_button: Button = %SettingsButton
@onready var settings: SettingsScreen = %SettingsScreen
@onready var help_button: Button = %HelpButton
@onready var help: HelpScreen = %Help
@onready var give_up_button: Button = %GiveUp
@onready var title_button: Button = %ToTitle
@onready var quit_button: Button = %Quit
@onready var confirm: ConfirmationDialog = %Confirm


func _ready() -> void:
	resume_button.pressed.connect(close)
	settings_button.pressed.connect(_open_screen.bind(settings.open))
	settings.closed.connect(_back_to_menu.bind(settings_button))
	help_button.pressed.connect(_open_screen.bind(help.open))
	help.closed.connect(_back_to_menu.bind(help_button))
	give_up_button.pressed.connect(_ask.bind(give_up_button, tr("전투 포기"),
		tr("전투를 포기하면 패배로 처리되고, 이 막을 처음부터 다시 합니다."), tr("포기"), _give_up))
	# 자동 저장이 있으므로 "진행이 저장되지 않습니다" 안내는 하지 않는다 (#209 7번).
	title_button.pressed.connect(_ask.bind(title_button, tr("타이틀로"),
		tr("타이틀 화면으로 돌아가시겠습니까?"), tr("타이틀로"), _to_title))
	quit_button.pressed.connect(_ask.bind(quit_button, tr("종료"),
		tr("게임을 종료하시겠습니까?"), tr("종료"), get_tree().quit))
	confirm.cancel_button_text = tr("취소")
	confirm.confirmed.connect(_confirm)
	confirm.canceled.connect(_cancel)


## 전투가 끝났거나 정비·보상 화면이면 `전투 포기`를 숨긴다.
func open(can_give_up: bool) -> void:
	give_up_button.visible = can_give_up
	_link_focus()
	_focus_before = get_viewport().gui_get_focus_owner()
	show()
	menu.show()
	get_tree().paused = true
	resume_button.grab_focus()


## `계속`. 메뉴를 열기 전의 포커스로 돌아간다.
func close() -> void:
	hide()
	get_tree().paused = false
	if is_instance_valid(_focus_before) and _focus_before.is_visible_in_tree():
		_focus_before.grab_focus()


func _open_screen(open_screen: Callable) -> void:
	menu.hide()
	open_screen.call()


func _back_to_menu(button: Button) -> void:
	menu.show()
	button.grab_focus()


## 파괴적인 결정이라 연속 Enter로 확정하지 않게 `취소`를 기본 선택한다(정비 확인 창과 같다).
func _ask(button: Button, title: String, text: String, ok: String, action: Callable) -> void:
	_asked_from = button
	_on_confirm = action
	confirm.title = title
	confirm.dialog_text = text
	confirm.ok_button_text = ok
	confirm.exclusive = true
	confirm.popup_centered(Vector2i(360, 110))
	confirm.get_cancel_button().grab_focus()


func _hide_confirm() -> void:
	# Godot 4.7.2 접근성이 제거 중인 exclusive child에 포커스를 보내지 않게 한다.
	confirm.exclusive = false
	confirm.hide()


func _confirm() -> void:
	_hide_confirm()
	_on_confirm.call()


func _cancel() -> void:
	_hide_confirm()
	_asked_from.grab_focus()


func _give_up() -> void:
	close()
	give_up_confirmed.emit()


func _to_title() -> void:
	get_tree().paused = false
	get_tree().change_scene_to_file(TITLE_SCENE)


## 위아래·Tab은 보이는 버튼 사이만 옮기고 끝에서 멈춘다. 멈춘 HUD 버튼으로 포커스가 나가지 않는다.
func _link_focus() -> void:
	var shown: Array[Button] = []
	for node: Node in menu.get_children():
		if node is Button and (node as Button).visible:
			shown.append(node as Button)
	for index: int in range(shown.size()):
		var button: Button = shown[index]
		var up: NodePath = button.get_path_to(shown[maxi(index - 1, 0)])
		var down: NodePath = button.get_path_to(shown[mini(index + 1, shown.size() - 1)])
		button.focus_neighbor_top = up
		button.focus_previous = up
		button.focus_neighbor_bottom = down
		button.focus_next = down
		button.focus_neighbor_left = NodePath(".")
		button.focus_neighbor_right = NodePath(".")


## Esc·Start는 메뉴를 닫는다. 설정·도움말·확인 창이 열려 있으면 그 화면이 먼저 받는다.
func _input(event: InputEvent) -> void:
	if not visible or not menu.visible or confirm.visible:
		return
	if event.is_action_pressed("ui_cancel") or event.is_action_pressed("pause"):
		close()
		get_viewport().set_input_as_handled()
