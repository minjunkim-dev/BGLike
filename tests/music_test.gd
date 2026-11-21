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
	_check_duck_curve()
	await _check_duck_on_bus()
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


## 낮추기 곡선(#632): 0.05초에 −8dB로 내려가 1.5초 머물고 0.5초에 0dB로 돌아온다. 기대값은 설계의 숫자다.
func _check_duck_curve() -> void:
	for case: Array in [
		[-1.0, 0.0], [0.0, 0.0], [0.025, -4.0], [0.05, -8.0], [0.8, -8.0], [1.55, -8.0],
		[1.8, -4.0], [2.05, 0.0], [3.0, 0.0],
	]:
		var got: float = GameMusic.duck_db(case[0])
		_check(is_equal_approx(got, case[1]), "낮추기 곡선 %s초 → %s dB: %s" % [case[0], case[1], got])


## 실제 BGM 버스 효과(#632): 실제 시간으로 내려가 머물고 돌아온다. 다른 음량은 그대로이고 4배속에서도 같다.
func _check_duck_on_bus() -> void:
	var bgm: int = AudioServer.get_bus_index(GameSettings.BUS_BGM)
	var sfx: int = AudioServer.get_bus_index(GameSettings.BUS_SFX)
	var player: AudioStreamPlayer = GameMusic.player(self)
	GameMusic.play(self, GameMusic.BATTLE)
	var player_db: float = player.volume_db
	var bgm_bus_db: float = AudioServer.get_bus_volume_db(bgm)
	var sfx_bus_db: float = AudioServer.get_bus_volume_db(sfx)
	_check(GameMusic.duck_level(self) == 0.0, "낮추기 전에는 0dB")
	Engine.time_scale = 4.0
	GameMusic.duck(self)
	await create_timer(0.3, true, false, true).timeout
	_check(is_equal_approx(GameMusic.duck_level(self), GameMusic.DUCK_DB), "머무는 동안 −8dB(4배속에서도 실제 시간): %s" % GameMusic.duck_level(self))
	_check(player.volume_db == player_db and AudioServer.get_bus_volume_db(bgm) == bgm_bus_db
		and AudioServer.get_bus_volume_db(sfx) == sfx_bus_db, "낮춰도 재생기·BGM 버스·SFX 버스 음량은 그대로")
	GameMusic.play(self, GameMusic.CALM)
	_check(is_equal_approx(GameMusic.duck_level(self), GameMusic.DUCK_DB), "낮춘 동안 곡을 바꿔도 낮춘 값이 유지됨")
	await create_timer(1.2, true, false, true).timeout
	GameMusic.duck(self)
	_check(is_equal_approx(GameMusic.duck_level(self), GameMusic.DUCK_DB), "머무는 동안 다시 불러도 더 깊어지지 않음")
	await create_timer(1.0, true, false, true).timeout
	_check(is_equal_approx(GameMusic.duck_level(self), GameMusic.DUCK_DB), "다시 부르면 머물기를 새로 시작해 처음 끝 시각 뒤에도 낮춤")
	await create_timer(GameMusic.DUCK_HOLD + GameMusic.DUCK_RELEASE, true, false, true).timeout
	Engine.time_scale = 1.0
	_check(GameMusic.duck_level(self) == 0.0, "끝나면 0dB로 돌아옴: %s" % GameMusic.duck_level(self))


func _finish() -> void:
	print("Music: %d checks, %d failures;" % [checks, failures])
	quit(0 if failures == 0 else 1)
