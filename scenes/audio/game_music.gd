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

## 중요한 순간의 배경음 낮추기(#632). BGM 버스의 Amplify 효과(0번)만 움직여 배경음 음량 설정과 곡별 음량을 건드리지 않는다.
## 깊이(dB)와 내려가기·머물기·돌아오기 시간(실제 초)이다. 처음 값은 임시이며 사람이 듣고 조정한다.
const DUCK_DB: float = -8.0
const DUCK_ATTACK: float = 0.05
const DUCK_HOLD: float = 1.5
const DUCK_RELEASE: float = 0.5

## 아직 root에 붙지 않은(다음 프레임에 붙을) 노드. 그 사이 다시 불러도 하나만 만든다.
static var _pending: GameMusic = null

var _player: AudioStreamPlayer
var _current: StringName = &""
## 낮추기가 시작된 실제 시각(마이크로초)을 곡선의 경과 시간으로 맞춘 값. 낮추는 중이 아니면 -1이다.
var _duck_start_usec: int = -1


func _ready() -> void:
	set_process(_duck_start_usec >= 0)


func _process(_delta: float) -> void:
	_apply_duck()


## 곡선의 지금 값을 효과에 쓴다. 끝났으면 0dB로 두고 갱신을 멈춘다.
func _apply_duck() -> void:
	var effect: AudioEffectAmplify = _duck_effect()
	var elapsed: float = float(Time.get_ticks_usec() - _duck_start_usec) / 1000000.0
	var finished: bool = _duck_start_usec < 0 or elapsed >= DUCK_ATTACK + DUCK_HOLD + DUCK_RELEASE
	if effect != null:
		effect.volume_db = 0.0 if finished else duck_db(elapsed)
	if finished:
		_duck_start_usec = -1
		set_process(false)


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
	if music.is_inside_tree():
		music._player.play()
	else:
		# 처음 만든 노드는 다음 프레임에 붙는다. 붙는 순간 고른 곡이 재생된다.
		music._player.autoplay = true


## 지금 고른 곡. 아직 없으면 &"".
static func current(tree: SceneTree) -> StringName:
	return _instance(tree)._current


## root 아래의 재생 노드. 없으면 만든다.
static func player(tree: SceneTree) -> AudioStreamPlayer:
	return _instance(tree)._player


## 경과 실제 초 → 낮추기 효과의 dB. 0이하와 끝난 뒤는 0dB다.
static func duck_db(elapsed: float) -> float:
	if elapsed <= 0.0:
		return 0.0
	if elapsed < DUCK_ATTACK:
		return DUCK_DB * elapsed / DUCK_ATTACK
	if elapsed < DUCK_ATTACK + DUCK_HOLD:
		return DUCK_DB
	var released: float = elapsed - DUCK_ATTACK - DUCK_HOLD
	if released < DUCK_RELEASE:
		return DUCK_DB * (1.0 - released / DUCK_RELEASE)
	return 0.0


## 배경음을 낮춘다. 낮추는 중에 다시 부르면 −8dB보다 깊어지지 않고 머물기를 새로 시작한다. 내려가는 중이나 돌아오는 중이면 지금 깊이에서 −8dB까지 이어 내려간다.
static func duck(tree: SceneTree) -> void:
	var music: GameMusic = _instance(tree)
	var elapsed: float = 0.0
	if music._duck_start_usec >= 0:
		var level: float = duck_db(float(Time.get_ticks_usec() - music._duck_start_usec) / 1000000.0)
		elapsed = DUCK_ATTACK * level / DUCK_DB
	music._duck_start_usec = Time.get_ticks_usec() - int(elapsed * 1000000.0)
	music._apply_duck()
	music.set_process(true)


## 지금 BGM 버스 낮추기 효과의 dB. 효과가 없으면 0.
static func duck_level(_tree: SceneTree) -> float:
	var effect: AudioEffectAmplify = _duck_effect()
	return effect.volume_db if effect != null else 0.0


static func _duck_effect() -> AudioEffectAmplify:
	var bus: int = AudioServer.get_bus_index(GameSettings.BUS_BGM)
	if bus == -1 or AudioServer.get_bus_effect_count(bus) == 0:
		return null
	return AudioServer.get_bus_effect(bus, 0) as AudioEffectAmplify


static func _instance(tree: SceneTree) -> GameMusic:
	var root: Window = tree.root
	var music: GameMusic = root.get_node_or_null(NODE_NAME) as GameMusic
	if music == null and is_instance_valid(_pending) and not _pending.is_queued_for_deletion():
		music = _pending
	if music == null:
		music = GameMusic.new()
		music.name = NODE_NAME
		music.process_mode = Node.PROCESS_MODE_ALWAYS
		music._player = AudioStreamPlayer.new()
		music._player.name = "Player"
		music._player.bus = GameSettings.BUS_BGM
		music.add_child(music._player)
		# 장면의 _ready 안(예: 시작할 때의 타이틀)에서는 root가 자식을 붙이는 중이라 바로 붙일 수 없다.
		root.add_child.call_deferred(music)
		_pending = music
	return music
