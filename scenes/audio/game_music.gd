class_name GameMusic
extends Node
## 화면별 배경음 재생기 (#629). 장면이 바뀌어도 이어지도록 root 아래에 노드 하나를 만들어 둔다.
## 같은 곡을 다시 고르면 다시 시작하지 않는다. 승리·패배 곡은 반복하지 않고 한 번만 울린다.

const CALM: StringName = &"calm"
const BATTLE: StringName = &"battle"
const VICTORY: StringName = &"victory"
const DEFEAT: StringName = &"defeat"

## 곡 → 음원과 음량(dB). 음량은 곡마다 크게 들리는 정도(LUFS)를 -20 근처로 맞춘 값이다.
const TRACKS: Dictionary[StringName, Dictionary] = {
	CALM: {"stream": preload("res://scenes/audio/music/calm.ogg"), "volume_db": -3.0},
	BATTLE: {"stream": preload("res://scenes/audio/music/battle.ogg"), "volume_db": -7.0},
	VICTORY: {"stream": preload("res://scenes/audio/music/victory.ogg"), "volume_db": 0.0},
	DEFEAT: {"stream": preload("res://scenes/audio/music/defeat.ogg"), "volume_db": -3.0},
}
const NODE_NAME: String = "GameMusic"

var _player: AudioStreamPlayer
var _current: StringName = &""


## 이 곡을 튼다. 이미 이 곡을 골랐으면 아무것도 하지 않는다.
static func play(tree: SceneTree, track: StringName) -> void:
	var music: GameMusic = _instance(tree)
	if music._current == track:
		return
	music._current = track
	var entry: Dictionary = TRACKS[track]
	music._player.stop()
	music._player.stream = entry.stream
	music._player.volume_db = entry.volume_db
	music._player.play()


## 지금 고른 곡. 아직 없으면 &"".
static func current(tree: SceneTree) -> StringName:
	return _instance(tree)._current


## root 아래의 재생 노드. 없으면 만든다.
static func player(tree: SceneTree) -> AudioStreamPlayer:
	return _instance(tree)._player


static func _instance(tree: SceneTree) -> GameMusic:
	var root: Window = tree.root
	var music: GameMusic = root.get_node_or_null(NODE_NAME) as GameMusic
	if music == null:
		music = GameMusic.new()
		music.name = NODE_NAME
		music.process_mode = Node.PROCESS_MODE_ALWAYS
		music._player = AudioStreamPlayer.new()
		music._player.name = "Player"
		music._player.bus = GameSettings.BUS_BGM
		music.add_child(music._player)
		root.add_child(music)
	return music
