extends SceneTree

## 실제 전투의 AI, 연출, 차례 복귀와 캡처 관찰 Node를 함께 검사한다.

const CaptureObserver = preload("res://tests/capture_observer.gd")
const ScriptedDice = preload("res://tests/scripted_dice.gd")

var checks: int = 0
var failures: int = 0
var battle: Node2D
var turns: CombatTurns
var actions: CombatActions
var observer: CaptureObserver
var directory: String
var manual: bool = "--manual" in OS.get_cmdline_user_args()
var saw_enemy: bool = false
var _finished: bool = false


func _initialize() -> void:
	_run.call_deferred()


func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)


func _run() -> void:
	# Parse/runtime errors must not leave a test process waiting forever.
	create_timer(180.0 if manual else 20.0).timeout.connect(func() -> void:
		if _finished:
			return
		push_error("Combat capture watchdog expired")
		quit(1))
	directory = "user://capture_checks/%s" % str(Time.get_ticks_usec())
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--capture-dir="):
			directory = argument.trim_prefix("--capture-dir=")
	root.size = Vector2i(1280, 720)
	var main: Node = (load("res://scenes/game.tscn") as PackedScene).instantiate()
	root.add_child(main)
	current_scene = main
	battle = main.get_node("Battle") as Node2D
	# 3-3 진입만 고정한다. 전투 스크립트와 AI·연출 콜백은 원본을 유지한다.
	(battle.get("progress") as CombatActProgress).stage_index = 8
	battle.call("_start_stage", true)
	turns = battle.get("turns") as CombatTurns
	actions = battle.get("actions") as CombatActions
	var units: Array[CombatUnit] = battle.get("units")
	var initiative: Array[int] = []
	for unit: CombatUnit in units:
		initiative.append(20 if unit.is_ally else 1)
	turns.start(units, ScriptedDice.new(initiative))
	# 자동 검사는 반응 선택을 기다리지 않는다. 직접 플레이는 반응 UI도 유지한다.
	if not manual:
		actions.dice.seed = 41
		for unit: CombatUnit in units:
			if unit.is_ally:
				unit.reaction_left = 0
	if not _fixture_ready(units):
		await _finish()
		return
	observer = CaptureObserver.new()
	battle.add_child(observer)
	var result: Error = observer.start(battle, directory)
	_check(result == OK, "캡처 관찰 Node 시작: %s" % error_string(result))
	if result != OK:
		_finish()
		return
	turns.changed.connect(func() -> void:
		if turns.current_unit != null and not turns.current_unit.is_ally:
			saw_enemy = true)
	_check(battle.is_processing(), "실제 battle의 전투 진행 콜백 활성")
	_check(turns.current_unit != null and turns.current_unit.is_ally, "아군 차례에서 검사 시작")
	observer.record("BEFORE_ENEMY_TURN")
	if observer.renders_frames:
		_check(await _wait_for(func() -> bool: return observer.frame_count > 0, 3.0),
			"적 차례 전 원본 프레임 저장")
	if manual:
		print("[CAPTURE_CHECK] READY: native UI에서 아군 두 명의 차례를 끝내세요. dir=", directory)
		_check(await _wait_for(func() -> bool: return saw_enemy, 120.0), "직접 입력으로 적 차례 진입")
	else:
		var hud: CombatTurnHud = battle.get_node("UI/TurnHud") as CombatTurnHud
		for unit: CombatUnit in units:
			if unit.is_ally:
				hud.end_turn_requested.emit()
	_check(saw_enemy, "적 차례가 실제로 시작됨")
	var returned: bool = await _wait_for(_returned_to_ally, 15.0)
	_check(returned, "적 AI 종료 후 아군 차례 복귀")
	if not returned:
		observer.record("ALLY_TURN_TIMEOUT")
		_finish()
		return
	_check(not actions.busy, "차례 복귀 후 행동 잠금 해제")
	_check(battle.is_processing(), "캡처 중 전투 진행 콜백 유지")
	var previous_frames: int = observer.frame_count
	observer.record("ALLY_TURN_RETURNED")
	if observer.renders_frames:
		_check(await _wait_for(func() -> bool: return observer.frame_count > previous_frames, 3.0),
			"아군 차례 복귀 후 원본 프레임 저장")
	else:
		print("[CAPTURE_CHECK] headless: PNG 검증 제외, AI·차례 복귀·이벤트 기록만 검사")
	_check(observer.last_error == OK, "캡처 파일 쓰기 오류 없음")
	observer.stop()
	_validate_manifest()
	var collision: CaptureObserver = CaptureObserver.new()
	battle.add_child(collision)
	_check(collision.start(battle, directory) == ERR_ALREADY_EXISTS, "기존 캡처 기록 덮어쓰기 거부")
	collision.queue_free()
	var problems: Array[String] = ScriptedDice.finish()
	_check(problems.is_empty(), "이니셔티브 준비값 모두 소비: %s" % str(problems))
	_finish()


func _fixture_ready(units: Array[CombatUnit]) -> bool:
	var previous_failures: int = failures
	_check(units.size() == 3, "캡처 전제조건: 3-3 유닛 3개")
	if units.size() != 3:
		return false
	_check(units[0].is_ally and units[0].kind == CombatUnit.Kind.WARRIOR
		and units[1].is_ally and units[1].kind == CombatUnit.Kind.ARCHER
		and not units[2].is_ally and units[2].kind == CombatUnit.Kind.SCRAP_ROBOT_3000,
		"캡처 전제조건: 전사·궁수·고철로봇 3000")
	var portraits: Dictionary = battle.get_node("UI/TurnHud").get("_portraits")
	_check(portraits.size() == units.size(), "캡처 전제조건: 초상 3개")
	for unit: CombatUnit in units:
		_check(portraits.has(unit) and unit.hit_points == unit.get_max_hit_points(),
			"캡처 전제조건: 각 유닛의 초상과 정상 HP")
		if unit.is_ally:
			_check(unit.movement_left == CombatUnit.MOVEMENT_PER_TURN and unit.action_left == 1
				and unit.bonus_action_left == 1 and unit.reaction_left == (1 if manual else 0),
				"캡처 전제조건: 아군 턴 자원과 모드별 반응 횟수")
	return failures == previous_failures


func _returned_to_ally() -> bool:
	return (saw_enemy and turns.round_number >= 2 and turns.current_unit != null
		and turns.current_unit.is_ally and not battle.get("_enemy_turn_running")
		and not actions.busy)


func _wait_for(predicate: Callable, seconds: float) -> bool:
	var deadline: int = Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < deadline:
		if predicate.call():
			return true
		await create_timer(0.02).timeout
	return false


func _validate_manifest() -> void:
	var manifest: FileAccess = FileAccess.open(directory.path_join("frames.jsonl"), FileAccess.READ)
	_check(manifest != null, "이벤트 manifest 저장")
	if manifest == null:
		return
	var events: Dictionary = {}
	var frames: int = 0
	var ally_frame: bool = false
	var enemy_event: bool = false
	while not manifest.eof_reached():
		var line: String = manifest.get_line()
		if line.is_empty():
			continue
		var entry: Dictionary = JSON.parse_string(line)
		if not entry.has("png"):
			events[int(entry["event"])] = true
			enemy_event = enemy_event or not entry["ally"]
			continue
		frames += 1
		_check(events.has(int(entry["event"])), "프레임을 앞서 기록한 이벤트에 연결")
		var image: Image = Image.load_from_file(directory.path_join(entry["png"]))
		_check(image != null and not image.is_empty() and image.get_size() == Vector2i(1280, 720),
			"원본 PNG를 다시 읽고 Viewport 크기 확인")
		ally_frame = ally_frame or (entry["ally"] and int(entry["round"]) >= 2)
	_check(enemy_event, "manifest에 실제 적 차례 기록")
	_check(frames == observer.frame_count, "저장한 프레임과 manifest 개수 일치")
	if observer.renders_frames:
		_check(frames > 0 and ally_frame, "manifest에 아군 차례 복귀 프레임 연결")


func _finish() -> void:
	_finished = true
	if observer != null:
		observer.stop()
	print("Combat capture: %d checks, %d failures; frames=%d; artifacts=%s" % [
		checks, failures, observer.frame_count if observer != null else 0,
		ProjectSettings.globalize_path(directory)])
	if manual and failures == 0:
		print("[CAPTURE_CHECK] PASS: 화면 확인 후 이 검증 인스턴스만 종료하세요.")
		return
	current_scene.queue_free()
	await process_frame
	quit(0 if failures == 0 else 1)
