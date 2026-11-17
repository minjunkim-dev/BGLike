extends Node
## UI 효과음(#628). 장면에 들어오는 모든 버튼에 호버·클릭·사용 불가 소리를 달고, ui_cancel 입력에 취소 소리를 낸다.
## UI 버스(SFX로 나간다)로 내보내므로 효과음 음량을 따른다. 입력을 소비하지 않는다.
## 키보드 포커스 이동에는 소리를 내지 않는다(화면을 열며 grab_focus가 소리를 내지 않게).

const AUDIO_DIR: String = "res://scenes/ui/audio/"
const CUES: Dictionary = {
	&"ui_hover": -14.0,
	&"ui_click": -10.0,
	&"ui_cancel": -10.0,
	&"ui_disabled": -10.0,
}

signal played(cue: StringName)

var _players: Dictionary[StringName, AudioStreamPlayer] = {}


func _ready() -> void:
	# 일시정지 메뉴(get_tree().paused)와 도움말도 이 소리를 내야 한다.
	process_mode = Node.PROCESS_MODE_ALWAYS
	for cue: StringName in CUES:
		var player: AudioStreamPlayer = AudioStreamPlayer.new()
		player.name = String(cue).to_pascal_case()
		player.stream = load(AUDIO_DIR + String(cue) + ".ogg") as AudioStream
		player.volume_db = float(CUES[cue])
		player.bus = GameSettings.BUS_UI
		add_child(player)
		_players[cue] = player
	get_tree().node_added.connect(_on_node_added)


func player(cue: StringName) -> AudioStreamPlayer:
	return _players.get(cue)


func play(cue: StringName) -> void:
	var sound: AudioStreamPlayer = _players.get(cue)
	if sound == null:
		return
	sound.play()
	played.emit(cue)


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		play(&"ui_cancel")


func _on_node_added(node: Node) -> void:
	if node is BaseButton:
		var button: BaseButton = node as BaseButton
		button.mouse_entered.connect(_on_hover.bind(button))
		button.pressed.connect(play.bind(&"ui_click"))
		button.gui_input.connect(_on_gui_input.bind(button))


func _on_hover(button: BaseButton) -> void:
	if not button.disabled:
		play(&"ui_hover")


func _on_gui_input(event: InputEvent, button: BaseButton) -> void:
	if (button.disabled and event is InputEventMouseButton and event.pressed
			and event.button_index == MOUSE_BUTTON_LEFT):
		play(&"ui_disabled")
