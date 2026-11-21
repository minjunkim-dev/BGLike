class_name CombatSounds
extends Node
## 전투 사건의 효과음(#628). 사건 이름(cue)마다 플레이어 하나를 SFX 버스로 내보낸다.
## 적 턴 4배속(Engine.time_scale > 1)에서는 갈래가 있는 소리가 같은 소리끼리 FAST_MIN_INTERVAL 안에 다시 오면 건너뛴다(#633).
## 재생은 전투 진행을 기다리지 않는다. 무엇이 났는지는 played 신호로 알 수 있다(headless는 Dummy 오디오).

const AUDIO_DIR: String = "res://scenes/combat/audio/"
const HIT_VOLUME_DB: float = -12.0
const DEFAULT_VOLUME_DB: float = -9.0
const AMBIENT_VOLUME_DB: float = -20.0
const MAX_POLYPHONY: int = 4
## 갈래 3개(#630). 높낮이 폭은 배율 1/p~p. 실제 소리와 잡음 합성은 ±7~8%, 칩튠 음은 ±6%.
const VARIANTS: int = 3
const PITCH: float = 1.08
## 4배속에서 같은 갈래 소리 사이의 최소 간격(실제 초). 1배속 한 칸 이동 시간(약 0.129초)이다. 처음 값은 임시이며 사람이 듣고 조정한다.
const FAST_MIN_INTERVAL: float = 0.13
## cue → 파일과 음량. "variants"가 있으면 `<파일>_2.ogg`… 갈래를 더해 반복 없이 고르고 "pitch"만큼 높낮이를 흔든다.
## 처음 음량은 임시이며 사람이 듣고 조정한다.
const CUES: Dictionary = {
	&"hit_flesh": {"file": "hit_flesh.ogg", "db": HIT_VOLUME_DB, "variants": VARIANTS, "pitch": PITCH},
	&"hit_metal": {"file": "hit_metal.ogg", "db": HIT_VOLUME_DB, "variants": VARIANTS, "pitch": PITCH},
	&"hit_wood": {"file": "hit_wood.ogg", "db": HIT_VOLUME_DB, "variants": VARIANTS, "pitch": PITCH},
	&"hit_stone": {"file": "hit_stone.ogg", "db": HIT_VOLUME_DB, "variants": VARIANTS, "pitch": PITCH},
	&"critical": {"file": "critical.ogg", "db": HIT_VOLUME_DB},
	&"miss": {"file": "miss.ogg", "db": DEFAULT_VOLUME_DB, "variants": VARIANTS, "pitch": PITCH},
	&"downed": {"file": "downed.ogg", "db": DEFAULT_VOLUME_DB},
	&"shield": {"file": "shield.ogg", "db": DEFAULT_VOLUME_DB},
	&"heal": {"file": "heal.ogg", "db": DEFAULT_VOLUME_DB},
	&"shout": {"file": "shout.ogg", "db": DEFAULT_VOLUME_DB},
	&"step_dirt": {"file": "step_dirt.ogg", "db": -14.0, "variants": VARIANTS, "pitch": PITCH},
	&"step_stone": {"file": "step_stone.ogg", "db": -14.0, "variants": VARIANTS, "pitch": PITCH},
	&"step_water": {"file": "step_water.ogg", "db": -14.0, "variants": VARIANTS, "pitch": PITCH},
	&"jump": {"file": "jump.ogg", "db": DEFAULT_VOLUME_DB, "variants": VARIANTS, "pitch": PITCH},
	&"land": {"file": "land.ogg", "db": DEFAULT_VOLUME_DB, "variants": VARIANTS, "pitch": PITCH},
	&"turn_ally": {"file": "turn_ally.ogg", "db": DEFAULT_VOLUME_DB},
	&"turn_enemy": {"file": "turn_enemy.ogg", "db": DEFAULT_VOLUME_DB},
	&"ambient_water": {"file": "ambient_water.ogg", "db": AMBIENT_VOLUME_DB, "loop": true},
	&"ambient_wind": {"file": "ambient_wind.ogg", "db": AMBIENT_VOLUME_DB, "loop": true},
}
## 고철로봇 세 종류. 이 밖의 유닛은 살로 듣는다.
const ROBOT_KINDS: Array[CombatUnit.Kind] = [
	CombatUnit.Kind.SCRAP_ROBOT_1000, CombatUnit.Kind.SCRAP_ROBOT_2000, CombatUnit.Kind.SCRAP_ROBOT_3000,
]

signal played(cue: StringName)

## 치명타(명중 절대성공) 소리는 만들어 두되 꺼 둔다. 켜는 것은 사람이 듣고 정한다.
var critical_enabled: bool = false

var _players: Dictionary[StringName, AudioStreamPlayer] = {}
## 마지막에 신호를 낸 진영. -1 없음, 0 적, 1 아군.
var _last_side: int = -1
var _ambient: StringName = &""
## cue마다 마지막으로 실제 재생한 시각(마이크로초). 4배속에서 건너뛴 재생은 적지 않는다.
var _last_played_usec: Dictionary[StringName, int] = {}


func _ready() -> void:
	for cue: StringName in CUES:
		var info: Dictionary = CUES[cue]
		var player: AudioStreamPlayer = AudioStreamPlayer.new()
		player.name = String(cue).to_pascal_case()
		var file: String = String(info["file"])
		var variants: int = int(info.get("variants", 1))
		if variants > 1:
			player.stream = SoundVariants.build(
				SoundVariants.variant_paths(AUDIO_DIR, file.get_basename(), variants), float(info["pitch"]))
		else:
			var stream: AudioStreamOggVorbis = load(AUDIO_DIR + file) as AudioStreamOggVorbis
			if info.get("loop", false):
				stream = stream.duplicate() as AudioStreamOggVorbis
				stream.loop = true
			player.stream = stream
		player.volume_db = float(info["db"])
		player.max_polyphony = MAX_POLYPHONY
		player.bus = GameSettings.BUS_SFX
		add_child(player)
		_players[cue] = player


## cue의 플레이어. 없는 cue면 null.
func player(cue: StringName) -> AudioStreamPlayer:
	return _players.get(cue)


func play(cue: StringName) -> void:
	var sound: AudioStreamPlayer = _players.get(cue)
	if sound == null:
		return
	var now: int = Time.get_ticks_usec()
	var since_last: float = INF
	if _last_played_usec.has(cue):
		since_last = float(now - _last_played_usec[cue]) / 1000000.0
	if fast_skips(cue, since_last, Engine.time_scale):
		return
	_last_played_usec[cue] = now
	sound.play()
	played.emit(cue)


## 피해를 받은 쪽(유닛 또는 상자·바위)의 재질 소리.
func play_hit(target: Object) -> void:
	play(hit_cue(target))


## 명중 절대성공. 꺼져 있으면 아무것도 내지 않는다.
func play_critical() -> void:
	if critical_enabled:
		play(&"critical")


## 진영이 바뀔 때만 턴 신호를 낸다(유닛마다 내면 적 턴이 이어질 때 겹친다).
func turn_started(unit: CombatUnit) -> void:
	if unit == null:
		return
	var side: int = 1 if unit.is_ally else 0
	if side == _last_side:
		return
	_last_side = side
	play(&"turn_ally" if unit.is_ally else &"turn_enemy")


## 전투 동안 반복하는 환경음을 시작한다. 턴 신호의 진영 기억도 새로 시작한다.
func start_ambient(grid: CombatGrid) -> void:
	stop_ambient()
	_last_side = -1
	_ambient = ambient_cue(grid)
	var sound: AudioStreamPlayer = _players[_ambient]
	sound.play()
	played.emit(_ambient)


## 재생 중인 소리를 모두 멈춘다. 장면을 지우기 전에 쓴다.
func stop_all() -> void:
	_ambient = &""
	_last_played_usec.clear()
	for sound: AudioStreamPlayer in _players.values():
		sound.stop()


func stop_ambient() -> void:
	if _ambient != &"":
		_players[_ambient].stop()
	_ambient = &""


func is_ambient_playing() -> bool:
	return _ambient != &"" and _players[_ambient].playing


## 4배속(time_scale > 1)에서 갈래가 있는 cue가 마지막 재생 뒤 FAST_MIN_INTERVAL(실제 초)이 지나기 전에 오면 true.
## 신호음·환경음·없는 cue는 건너뛰지 않는다. since_last는 처음 나는 cue면 INF다.
static func fast_skips(cue: StringName, since_last: float, time_scale: float) -> bool:
	if time_scale <= 1.0 or not CUES.has(cue):
		return false
	return int(CUES[cue].get("variants", 1)) > 1 and since_last < FAST_MIN_INTERVAL


static func hit_cue(target: Object) -> StringName:
	if target is CombatGrid.Prop:
		return &"hit_stone" if (target as CombatGrid.Prop).kind == "rock" else &"hit_wood"
	if target is CombatUnit and (target as CombatUnit).kind in ROBOT_KINDS:
		return &"hit_metal"
	return &"hit_flesh"


static func step_cue(grid: CombatGrid, stage: CombatStage, cell: Vector2i) -> StringName:
	if grid != null and grid.water_cells.has(cell):
		return &"step_water"
	if stage != null and stage.stone_cells.has(cell):
		return &"step_stone"
	return &"step_dirt"


static func ambient_cue(grid: CombatGrid) -> StringName:
	return &"ambient_water" if grid != null and not grid.water_cells.is_empty() else &"ambient_wind"
