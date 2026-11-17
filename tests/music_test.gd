extends SceneTree
## 배경음 재생기(GameMusic)의 공개 인터페이스를 검사한다: 버스·곡표·같은 곡 이어 받기·화면 전환 뒤 유지 (#629).

var checks: int = 0
var failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)


func _run() -> void:
	await _check_first_play()
	_check_track_table()
	_check_same_track_continues()
	_check_switching()
	await _check_survives_scene_change()
	_finish()


func _check_first_play() -> void:
	GameMusic.play(self, GameMusic.CALM)
	var player: AudioStreamPlayer = GameMusic.player(self)
	_check(GameMusic.current(self) == GameMusic.CALM, "처음 고른 곡이 현재 곡")
	# 재생 노드는 다음 프레임에 root에 붙고 그때 재생을 시작한다.
	await process_frame
	_check(player.bus == GameSettings.BUS_BGM, "재생기는 BGM 버스로 나감")
	_check(player.playing, "고른 곡이 재생 중")


## 곡표: 긴 두 곡은 1~2분 반복, 짧은 두 곡은 반복하지 않는 10초 미만이다.
func _check_track_table() -> void:
	var player: AudioStreamPlayer = GameMusic.player(self)
	paused = true
	_check(player.can_process(), "일시정지 중에도 재생")
	paused = false
	for track: StringName in [GameMusic.CALM, GameMusic.BATTLE]:
		GameMusic.play(self, track)
		var stream: AudioStreamOggVorbis = player.stream as AudioStreamOggVorbis
		_check(stream != null and stream.loop and stream.get_length() >= 60.0 and stream.get_length() <= 120.0,
			"%s는 1~2분 반복 곡" % track)
	for track: StringName in [GameMusic.VICTORY, GameMusic.DEFEAT]:
		GameMusic.play(self, track)
		var stream: AudioStreamOggVorbis = player.stream as AudioStreamOggVorbis
		_check(stream != null and not stream.loop and stream.get_length() < 10.0, "%s는 반복하지 않는 짧은 곡" % track)
	GameMusic.play(self, GameMusic.CALM)
	var calm_db: float = player.volume_db
	GameMusic.play(self, GameMusic.BATTLE)
	_check(player.volume_db != calm_db, "곡마다 음량을 따로 맞춤")


## 같은 곡을 다시 고르면 재생 객체가 그대로다(다시 시작하면 새 playback이 생긴다).
func _check_same_track_continues() -> void:
	GameMusic.play(self, GameMusic.CALM)
	var player: AudioStreamPlayer = GameMusic.player(self)
	var playback: AudioStreamPlayback = player.get_stream_playback()
	_check(playback != null, "재생 객체가 있음")
	GameMusic.play(self, GameMusic.CALM)
	_check(player.get_stream_playback() == playback and player.playing, "같은 곡을 다시 골라도 다시 시작하지 않음")


func _check_switching() -> void:
	var player: AudioStreamPlayer = GameMusic.player(self)
	GameMusic.play(self, GameMusic.CALM)
	var calm: AudioStream = player.stream
	GameMusic.play(self, GameMusic.BATTLE)
	_check(GameMusic.current(self) == GameMusic.BATTLE and player.stream != calm and player.playing, "다른 곡으로 바꿈")
	GameMusic.play(self, GameMusic.VICTORY)
	var first: AudioStreamPlayback = player.get_stream_playback()
	player.stop()
	GameMusic.play(self, GameMusic.VICTORY)
	_check(not player.playing, "끝난 짧은 곡은 같은 곡을 다시 불러도 다시 울리지 않음")
	GameMusic.play(self, GameMusic.BATTLE)
	GameMusic.play(self, GameMusic.VICTORY)
	_check(player.playing and player.get_stream_playback() != first, "다른 곡을 고른 뒤에는 짧은 곡이 다시 울림")


## change_scene_to_file 뒤에도 같은 노드·같은 재생 객체다.
func _check_survives_scene_change() -> void:
	GameMusic.play(self, GameMusic.CALM)
	var player: AudioStreamPlayer = GameMusic.player(self)
	var playback: AudioStreamPlayback = player.get_stream_playback()
	var first: Node = Node.new()
	root.add_child(first)
	current_scene = first
	change_scene_to_file("res://scenes/main.tscn")
	await process_frame
	await process_frame
	GameMusic.play(self, GameMusic.CALM)
	_check(GameMusic.player(self) == player and player.is_inside_tree() and player.get_stream_playback() == playback
		and player.playing, "장면을 바꿔도 같은 곡이 이어짐")


func _finish() -> void:
	print("Music: %d checks, %d failures;" % [checks, failures])
	quit(0 if failures == 0 else 1)
