class_name SettingsScreen
extends ColorRect
## 설정 화면: 마스터·배경음·효과음 음량, 창 모드, 화면 맞춤. 바꾸는 즉시 설정 파일에 쓰고 적용한다 (#285).
## 타이틀과 일시정지 메뉴가 같은 장면을 자식으로 두고 open()으로 연다. 닫히면 closed를 보낸다.

signal closed

@onready var volume_slider: HSlider = %Volume
@onready var volume_label: Label = %VolumeValue
@onready var bgm_slider: HSlider = %BgmVolume
@onready var bgm_label: Label = %BgmVolumeValue
@onready var sfx_slider: HSlider = %SfxVolume
@onready var sfx_label: Label = %SfxVolumeValue
@onready var fullscreen_box: CheckBox = %Fullscreen
@onready var fill_box: CheckBox = %FillScreen
@onready var back_button: Button = %Back


func _ready() -> void:
	volume_slider.step = GameSettings.VOLUME_STEP
	volume_slider.value_changed.connect(_on_volume_changed.bind(GameSettings.BUS_MASTER))
	for bus: StringName in [GameSettings.BUS_BGM, GameSettings.BUS_SFX]:
		_slider(bus).step = GameSettings.VOLUME_STEP
		_slider(bus).value_changed.connect(_on_volume_changed.bind(bus))
	fullscreen_box.toggled.connect(_on_fullscreen_toggled)
	fill_box.toggled.connect(_on_fill_toggled)
	back_button.pressed.connect(close)


func open() -> void:
	for bus: StringName in GameSettings.VOLUME_KEYS:
		var volume: int = GameSettings.volume(bus)
		_slider(bus).set_value_no_signal(volume)
		_show_volume(volume, bus)
	fullscreen_box.set_pressed_no_signal(GameSettings.fullscreen())
	# 쓰기에 실패했어도 적용된 값을 보인다.
	fill_box.set_pressed_no_signal(get_window().content_scale_stretch == Window.CONTENT_SCALE_STRETCH_FRACTIONAL)
	show()
	volume_slider.grab_focus()


func close() -> void:
	hide()
	closed.emit()


func _slider(bus: StringName) -> HSlider:
	match bus:
		GameSettings.BUS_BGM:
			return bgm_slider
		GameSettings.BUS_SFX:
			return sfx_slider
	return volume_slider


## 음소거 버튼이 없으므로 0은 글자로 알린다.
func _show_volume(value: int, bus: StringName) -> void:
	var label: Label = volume_label
	if bus == GameSettings.BUS_BGM:
		label = bgm_label
	elif bus == GameSettings.BUS_SFX:
		label = sfx_label
	label.text = tr("음소거") if value == 0 else "%d%%" % value


## 파일 쓰기에 실패해도(경고만 남김) 화면에 보인 값을 적용한다. 다음 실행에만 남지 않는다.
func _on_volume_changed(value: float, bus: StringName) -> void:
	_show_volume(int(value), bus)
	GameSettings.write(GameSettings.VOLUME_KEYS[bus], int(value))
	GameSettings.apply_volume(int(value), bus)


func _on_fullscreen_toggled(on: bool) -> void:
	GameSettings.write("fullscreen", on)
	GameSettings.apply_window_mode(on)


func _on_fill_toggled(on: bool) -> void:
	GameSettings.write("fill_screen", on)
	GameSettings.apply_screen_fit(get_window(), on)


func _input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()
