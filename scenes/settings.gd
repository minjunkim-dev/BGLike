class_name SettingsScreen
extends ColorRect
## 설정 화면: 마스터 음량과 창 모드. 바꾸는 즉시 설정 파일에 쓰고 적용한다 (#285).
## 타이틀과 일시정지 메뉴가 같은 장면을 자식으로 두고 open()으로 연다. 닫히면 closed를 보낸다.

signal closed

@onready var volume_slider: HSlider = %Volume
@onready var volume_label: Label = %VolumeValue
@onready var fullscreen_box: CheckBox = %Fullscreen
@onready var back_button: Button = %Back


func _ready() -> void:
	volume_slider.step = GameSettings.VOLUME_STEP
	volume_slider.value_changed.connect(_on_volume_changed)
	fullscreen_box.toggled.connect(_on_fullscreen_toggled)
	back_button.pressed.connect(close)


func open() -> void:
	var volume: int = GameSettings.volume()
	volume_slider.set_value_no_signal(volume)
	_show_volume(volume)
	fullscreen_box.set_pressed_no_signal(GameSettings.fullscreen())
	show()
	volume_slider.grab_focus()


func close() -> void:
	hide()
	closed.emit()


## 음소거 버튼이 없으므로 0은 글자로 알린다.
func _show_volume(value: int) -> void:
	volume_label.text = tr("음소거") if value == 0 else "%d%%" % value


## 파일 쓰기에 실패해도(경고만 남김) 화면에 보인 값을 적용한다. 다음 실행에만 남지 않는다.
func _on_volume_changed(value: float) -> void:
	_show_volume(int(value))
	GameSettings.write("master_volume", int(value))
	GameSettings.apply_volume(int(value))


func _on_fullscreen_toggled(on: bool) -> void:
	GameSettings.write("fullscreen", on)
	GameSettings.apply_window_mode(on)


func _input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()
