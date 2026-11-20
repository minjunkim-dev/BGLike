extends SceneTree
## 전투·UI 효과음(#628): cue 표, 재질·지형 판정, 사건 연결, 치명타 끄기, 재실행 무음, UI 소리를 검사한다.
## headless는 Dummy 오디오라 들리는 것은 확인하지 못한다. 무엇이 났는지는 played 신호로 본다.

const MAX_SHORT_SECONDS: float = 1.2
## 갈래를 두는 전투 cue(#630). 실제 소리를 가공한 것과 잡음 합성은 1.08, 칩튠 음은 1.06.
const VARIANT_CUES: Array[StringName] = [
	&"hit_flesh", &"hit_metal", &"hit_wood", &"hit_stone", &"miss",
	&"step_dirt", &"step_stone", &"step_water", &"jump", &"land",
]
const VARIANT_UI_CUES: Array[StringName] = [&"ui_hover", &"ui_click"]

var checks: int = 0
var failures: int = 0
var battle: Node2D
var sounds: CombatSounds
var actions: CombatActions
var turns: CombatTurns
var units: Array[CombatUnit]
var heard: Array[StringName] = []
## 자동 로드는 --script 실행에서 식별자로 컴파일되지 않아 경로로 찾는다.
var ui_sounds: Node


func _initialize() -> void:
	_run.call_deferred()


func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)


func _run() -> void:
	create_timer(60.0).timeout.connect(func() -> void:
		push_error("Combat sound watchdog expired")
		quit(1))
	var main: Node = (load("res://scenes/game.tscn") as PackedScene).instantiate()
	battle = main.get_node("Battle") as Node2D
	battle.stages[0] = load("res://scenes/combat/stage.tres") as CombatStage
	root.add_child(main)
	current_scene = main
	battle.set_process(false)
	await process_frame
	ui_sounds = root.get_node_or_null("UiSounds")
	_check(ui_sounds != null, "UiSounds 자동 로드가 있음")
	if ui_sounds == null:
		quit(1)
		return
	sounds = battle.get("sounds") as CombatSounds
	actions = battle.get("actions") as CombatActions
	turns = battle.get("turns") as CombatTurns
	units = battle.get("units")
	sounds.played.connect(func(cue: StringName) -> void: heard.append(cue))
	_test_sound_variants()
	_test_cue_table()
	_test_material_cues()
	_test_ground_cues()
	await _test_battle_events()
	_test_ui_cue_table()
	await _test_ui_sounds()
	sounds.stop_all()
	await create_timer(0.3).timeout
	main.queue_free()
	await process_frame
	print("combat sound checks: %d, failures: %d" % [checks, failures])
	quit(0 if failures == 0 else 1)


func _expect(label: String, cues: Array[StringName]) -> void:
	_check(heard == cues, "%s: 기대 %s, 실제 %s" % [label, cues, heard])
	heard.clear()


## seam 1: 갈래 스트림을 만드는 SoundVariants.
func _test_sound_variants() -> void:
	var dir: String = "res://scenes/combat/audio/"
	_check(SoundVariants.variant_paths(dir, "hit_flesh", 3) == PackedStringArray([
		dir + "hit_flesh.ogg", dir + "hit_flesh_2.ogg", dir + "hit_flesh_3.ogg"]), "갈래 경로 이름 규칙")
	_check(SoundVariants.variant_paths(dir, "heal", 1) == PackedStringArray([dir + "heal.ogg"]), "갈래 하나면 원본 경로만")
	var single: AudioStream = SoundVariants.build(PackedStringArray([dir + "heal.ogg"]), 1.08)
	_check(single is AudioStreamOggVorbis, "갈래가 하나면 OGG 그대로")
	var multi: AudioStream = SoundVariants.build(SoundVariants.variant_paths(dir, "hit_flesh", 3), 1.08)
	var randomizer: AudioStreamRandomizer = multi as AudioStreamRandomizer
	_check(randomizer != null, "갈래가 둘 이상이면 AudioStreamRandomizer")
	if randomizer != null:
		_check(randomizer.streams_count == 3, "갈래 수 3: %d" % randomizer.streams_count)
		_check(randomizer.playback_mode == AudioStreamRandomizer.PLAYBACK_RANDOM_NO_REPEATS, "같은 갈래를 연달아 고르지 않음")
		_check(is_equal_approx(randomizer.random_pitch, 1.08), "높낮이 폭 1.08")
		_check(is_zero_approx(randomizer.random_volume_offset_db), "음량 오프셋 0")
		var longest: float = SoundVariants.longest(multi)
		_check(longest > 0.0, "longest는 0보다 큼: %f" % longest)
		var expected: float = 0.0
		for index: int in range(randomizer.streams_count):
			expected = maxf(expected, randomizer.get_stream(index).get_length())
		_check(is_equal_approx(longest, expected), "longest는 갈래 중 가장 긴 길이")
	_check(is_equal_approx(SoundVariants.longest(single), single.get_length()), "OGG의 longest는 그 길이")


## seam 2: 모든 cue의 파일, 길이, 반복, 버스, 갈래.
func _test_cue_table() -> void:
	for cue: StringName in CombatSounds.CUES:
		var player: AudioStreamPlayer = sounds.player(cue)
		_check(player != null, "cue 플레이어 있음: %s" % cue)
		if player == null:
			continue
		var varied: bool = cue in VARIANT_CUES
		_check(varied == (int(CombatSounds.CUES[cue].get("variants", 1)) > 1), "갈래 cue 목록: %s" % cue)
		var stream: AudioStreamOggVorbis = player.stream as AudioStreamOggVorbis
		if varied:
			_check(stream == null and player.stream is AudioStreamRandomizer, "갈래 cue는 Randomizer: %s" % cue)
			_test_variant_stream(cue, player.stream as AudioStreamRandomizer, 1.08)
		_check(player.bus == GameSettings.BUS_SFX, "SFX 버스: %s" % cue)
		_check(not player.autoplay, "자동 재생 없음: %s" % cue)
		if varied:
			_check(SoundVariants.longest(player.stream) < MAX_SHORT_SECONDS, "짧음: %s" % cue)
			continue
		_check(stream != null and stream.get_length() > 0.0, "OGG로 열림: %s" % cue)
		if String(cue).begins_with("ambient_"):
			_check(stream.loop and stream.get_length() >= 4.0, "환경음은 4초 이상 반복: %s" % cue)
		elif stream != null:
			_check(not stream.loop and stream.get_length() < MAX_SHORT_SECONDS, "짧고 반복 없음: %s" % cue)
	_check(sounds.player(&"hit_flesh").volume_db == -12.0 and sounds.player(&"hit_flesh").max_polyphony == 4,
		"타격음 음량 -12dB·동시 4개")
	_check(not sounds.critical_enabled, "치명타 소리는 처음에 꺼져 있음")
	_check(AudioServer.get_bus_index(GameSettings.BUS_SFX) >= 0, "SFX 버스가 있음")
	_check(AudioServer.get_bus_send(AudioServer.get_bus_index(GameSettings.BUS_UI)) == GameSettings.BUS_SFX,
		"UI 버스는 SFX로 나감")


## seam 3: UI cue(호버·클릭만 갈래, 칩튠이라 1.06).
func _test_ui_cue_table() -> void:
	# UiSounds.MAX_POLYPHONY는 스크립트 상수라 상수 표로 읽는다(없으면 null이라 검사가 실패한다).
	var ui_polyphony: Variant = ui_sounds.get_script().get_script_constant_map().get("MAX_POLYPHONY")
	_check(ui_polyphony is int and ui_polyphony >= 1 and ui_polyphony <= 4,
		"UI 동시 재생 상한은 1~4: %s" % [ui_polyphony])
	for cue: StringName in ui_sounds.CUES:
		var player: AudioStreamPlayer = ui_sounds.player(cue)
		var varied: bool = cue in VARIANT_UI_CUES
		_check(player != null and player.bus == GameSettings.BUS_UI and not player.autoplay
			and SoundVariants.longest(player.stream) < MAX_SHORT_SECONDS,
			"UI cue는 UI 버스의 짧은 소리: %s" % cue)
		_check(player != null and player.max_polyphony == ui_polyphony,
			"UI cue는 같은 소리 동시 재생 상한을 가짐: %s" % cue)
		if varied:
			_check(player.stream is AudioStreamRandomizer, "UI 갈래 cue는 Randomizer: %s" % cue)
			_test_variant_stream(cue, player.stream as AudioStreamRandomizer, 1.06)
		else:
			_check(player.stream is AudioStreamOggVorbis, "UI 신호음은 OGG 그대로: %s" % cue)


## 갈래 스트림 하나: 갈래 2~4개, 모두 반복 없는 OGG, 높낮이 폭 pitch(±5~10% 안), 첫 갈래는 원본 파일.
func _test_variant_stream(cue: StringName, randomizer: AudioStreamRandomizer, pitch: float) -> void:
	if randomizer == null:
		return
	_check(randomizer.streams_count >= 2 and randomizer.streams_count <= 4, "갈래 2~4개: %s" % cue)
	_check(is_equal_approx(randomizer.random_pitch, pitch), "높낮이 폭 %.2f: %s" % [pitch, cue])
	_check(randomizer.random_pitch >= 1.0526 and randomizer.random_pitch <= 1.10, "높낮이 ±5~10%%: %s" % cue)
	_check(randomizer.playback_mode == AudioStreamRandomizer.PLAYBACK_RANDOM_NO_REPEATS, "반복 없이 고름: %s" % cue)
	for index: int in range(randomizer.streams_count):
		var variant: AudioStreamOggVorbis = randomizer.get_stream(index) as AudioStreamOggVorbis
		_check(variant != null and variant.get_length() > 0.0 and not variant.loop, "갈래 %d는 반복 없는 OGG: %s" % [index, cue])
	var first: AudioStreamOggVorbis = randomizer.get_stream(0) as AudioStreamOggVorbis
	var file: String = "%s.ogg" % cue
	_check(first != null and first.resource_path.get_file() == file, "첫 갈래는 원본 %s" % file)


## 재질 분류.
func _test_material_cues() -> void:
	_check(CombatSounds.hit_cue(units[2]) == &"hit_flesh", "야만인은 살")
	var robot: CombatUnit = (load("res://scenes/combat/unit.tscn") as PackedScene).instantiate() as CombatUnit
	for kind: CombatUnit.Kind in [CombatUnit.Kind.SCRAP_ROBOT_1000, CombatUnit.Kind.SCRAP_ROBOT_2000,
			CombatUnit.Kind.SCRAP_ROBOT_3000]:
		robot.kind = kind
		_check(CombatSounds.hit_cue(robot) == &"hit_metal", "고철로봇은 금속: %d" % kind)
	robot.kind = CombatUnit.Kind.SPIDERLING
	_check(CombatSounds.hit_cue(robot) == &"hit_flesh", "거미는 살")
	robot.free()
	_check(CombatSounds.hit_cue(CombatGrid.Prop.new(Vector2i.ZERO, "crate")) == &"hit_wood", "상자는 나무")
	_check(CombatSounds.hit_cue(CombatGrid.Prop.new(Vector2i.ZERO, "rock")) == &"hit_stone", "바위는 돌")


## 지형 판정.
func _test_ground_cues() -> void:
	var grid: CombatGrid = CombatGrid.new()
	var stage: CombatStage = CombatStage.new()
	stage.stone_cells = [Vector2i(2, 2)]
	grid.water_cells = [Vector2i(1, 1)]
	_check(CombatSounds.step_cue(grid, stage, Vector2i(1, 1)) == &"step_water", "물 칸은 물 발소리")
	_check(CombatSounds.step_cue(grid, stage, Vector2i(2, 2)) == &"step_stone", "돌 칸은 돌 발소리")
	_check(CombatSounds.step_cue(grid, stage, Vector2i(3, 3)) == &"step_dirt", "그 밖은 흙 발소리")
	_check(CombatSounds.step_cue(grid, null, Vector2i(2, 2)) == &"step_dirt", "스테이지가 없으면 흙")
	_check(CombatSounds.ambient_cue(grid) == &"ambient_water", "물 칸이 있으면 물 환경음")
	grid.water_cells = []
	_check(CombatSounds.ambient_cue(grid) == &"ambient_wind", "물 칸이 없으면 바람 환경음")


## seam 4(기존): 실제 전투 장면의 사건 연결.
func _test_battle_events() -> void:
	_check(not sounds.is_ambient_playing(), "전투를 시작하기 전에는 환경음이 없음")
	battle.call("start_battle")
	_check(sounds.is_ambient_playing(), "전투를 시작하면 환경음이 재생됨")
	_check(heard.size() == 2 and String(heard[0]).begins_with("ambient_")
		and heard[1] == (&"turn_ally" if turns.current_unit.is_ally else &"turn_enemy"),
		"전투 시작: 환경음과 첫 턴 신호 (%s)" % [heard])
	heard.clear()
	# 진영이 바뀔 때만 턴 신호를 낸다.
	var ally: CombatUnit = units[0]
	var enemy: CombatUnit = units[2]
	sounds.start_ambient(actions.grid)
	heard.clear()
	turns.turn_started.emit(ally)
	turns.turn_started.emit(units[1])
	turns.turn_started.emit(enemy)
	turns.turn_started.emit(units[3])
	turns.turn_started.emit(ally)
	_expect("턴 신호는 진영이 바뀔 때만", [&"turn_ally", &"turn_enemy", &"turn_ally"])
	# 피해와 재질.
	actions.damaged.emit(enemy)
	actions.damaged.emit(actions.create_prop(Vector2i(0, 0), "crate"))
	actions.damaged.emit(CombatGrid.Prop.new(Vector2i(1, 1), "rock"))
	_expect("피해 재질", [&"hit_flesh", &"hit_wood", &"hit_stone"])
	# 빗나감과 치명타.
	actions.struck.emit(ally, enemy, enemy.cell, false)
	_expect("빗나감", [&"miss"])
	actions.struck.emit(ally, enemy, enemy.cell, true)
	_expect("명중 섬광만으로는 소리가 나지 않음", [])
	actions.critical_hit.emit(enemy)
	_expect("치명타 소리는 꺼져 있으면 없음", [])
	sounds.critical_enabled = true
	actions.critical_hit.emit(enemy)
	_expect("치명타 소리를 켜면 남", [&"critical"])
	sounds.critical_enabled = false
	# 회복, 방어막, 함성, 전투 불능.
	actions.healed.emit(ally, 3)
	actions.self_used.emit(ally, "holy_veil")
	actions.self_used.emit(ally, "battle_cry")
	actions.self_used.emit(ally, "stealth")
	_expect("회복·방어막·함성(은신은 없음)", [&"heal", &"shield", &"shout"])
	# 이동·점프.
	var cell: Vector2i = ally.cell
	await battle.call("_animate_movement", ally, cell)
	_expect("이동 한 칸의 발소리", [CombatSounds.step_cue(actions.grid, battle.stages[0], cell)])
	await battle.call("_animate_jump", ally, cell)
	_expect("점프와 착지", [&"jump", &"land"])
	# 이어하기 재실행에서는 아무 소리도 나지 않는다.
	battle.set("_replay_actions", 5)
	actions.damaged.emit(enemy)
	actions.struck.emit(ally, enemy, enemy.cell, false)
	actions.healed.emit(ally, 1)
	actions.self_used.emit(ally, "holy_veil")
	actions.critical_hit.emit(enemy)
	await battle.call("_animate_movement", ally, cell)
	_expect("재실행은 무음", [])
	battle.set("_replay_actions", 0)
	# 전투 불능, 전투 종료.
	var living: Array[CombatUnit] = []
	for unit: CombatUnit in units:
		if not unit.is_ally and unit.hit_points > 0:
			living.append(unit)
	for unit: CombatUnit in living:
		actions.incapacitate(unit)
	_check(heard.count(&"downed") == living.size() and not living.is_empty(),
		"전투 불능마다 소리: %s" % [heard])
	heard.clear()
	# 행동이 끝나면 changed가 나가 환경음을 멈춘다(_finish).
	actions.changed.emit()
	await process_frame
	_check(actions.is_over() and not sounds.is_ambient_playing(), "전투가 끝나면 환경음이 멈춤")


## UI 소리 연결.
func _test_ui_sounds() -> void:
	var uiheard: Array[StringName] = []
	ui_sounds.played.connect(func(cue: StringName) -> void: uiheard.append(cue))
	var button: Button = Button.new()
	root.add_child(button)
	button.mouse_entered.emit()
	_check(uiheard == [&"ui_hover"], "사용 가능한 버튼의 호버: %s" % [uiheard])
	uiheard.clear()
	button.pressed.emit()
	_check(uiheard == [&"ui_click"], "버튼 클릭: %s" % [uiheard])
	uiheard.clear()
	button.disabled = true
	button.mouse_entered.emit()
	_check(uiheard.is_empty(), "사용 불가 버튼은 호버 소리 없음: %s" % [uiheard])
	var click: InputEventMouseButton = InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	button.gui_input.emit(click)
	_check(uiheard == [&"ui_disabled"], "사용 불가 버튼 클릭: %s" % [uiheard])
	uiheard.clear()
	button.disabled = false
	button.grab_focus()
	_check(uiheard.is_empty(), "포커스 이동은 소리 없음: %s" % [uiheard])
	var cancel: InputEventAction = InputEventAction.new()
	cancel.action = &"ui_cancel"
	cancel.pressed = true
	Input.parse_input_event(cancel)
	await process_frame
	_check(uiheard == [&"ui_cancel"], "ui_cancel 입력: %s" % [uiheard])
	# 설정 화면처럼 앞선 노드가 _input에서 Esc를 소비해도 취소음이 난다(PR #644 리뷰).
	uiheard.clear()
	var consumer_script: GDScript = GDScript.new()
	consumer_script.source_code = "extends Node\nvar consumed: int = 0\nfunc _input(event: InputEvent) -> void:\n\tif event.is_action_pressed(\"ui_cancel\"):\n\t\tconsumed += 1\n\t\tget_viewport().set_input_as_handled()\n"
	consumer_script.reload()
	var consumer: Node = consumer_script.new()
	root.add_child(consumer)
	Input.parse_input_event(cancel)
	await process_frame
	_check(consumer.get("consumed") == 1 and uiheard == [&"ui_cancel"],
		"Esc를 소비하는 화면이 있어도 ui_cancel 소리: %s" % [uiheard])
	consumer.queue_free()
	# 일시정지 메뉴가 get_tree().paused를 쓰므로 UiSounds는 멈추지 않아야 한다(상수 확인, 청취는 사람이 한다).
	_check(ui_sounds.process_mode == Node.PROCESS_MODE_ALWAYS, "UiSounds는 일시정지 중에도 돈다: %s" % [ui_sounds.process_mode])
	button.queue_free()
