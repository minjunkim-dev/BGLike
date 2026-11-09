extends SceneTree

## #463: 3막 스테이지 1의 독안개 거미를 실제 게임 장면(game.tscn)에서 에이전트가 조작해 확인한다.
## 독안개 거미의 턴만 실제 AI(play_turn)로 돌리고, 나머지 적은 턴을 넘긴다. 아군은 가만히 둔다.
## 주사위는 무작위 seed다. 실제 입력 장치·자연 주사위 플레이의 증거가 아니다.

const CaptureObserver = preload("res://tests/capture_observer.gd")
const ScriptedDice = preload("res://tests/scripted_dice.gd")
const STAGE: int = 6

var checks: int = 0
var failures: int = 0
var battle: Node2D
var actions: CombatActions
var turns: CombatTurns
var units: Array[CombatUnit]
var spider: CombatUnit
var log_lines: Array[String] = []
var observer: CaptureObserver
var capture_dir: String = ""
var finished: bool = false
## 거미 순서마다 [라운드, 전 시전 수, 후 시전 수, 시전함, 칸 수] 기록.
var history: Array = []
var cast_rounds: Array[int] = []


func _initialize() -> void:
	_run.call_deferred()


func _check(condition: bool, message: String) -> void:
	checks += 1
	print("[FOG_SPIDER] %s: %s" % ["ok" if condition else "FAIL", message])
	if not condition:
		failures += 1
		push_error(message)


func _run() -> void:
	create_timer(150.0).timeout.connect(func() -> void:
		if not finished:
			push_error("fog spider watchdog expired")
			quit(1))
	root.size = Vector2i(1280, 720)
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--capture-dir="):
			capture_dir = argument.trim_prefix("--capture-dir=")
	await _open_stage()
	_attach_observer("")
	_check_layout()
	await _two_zones_flow()
	var expiry_live: Array = await _death_flow(false)
	var expiry_resumed: Array = await _death_flow(true)
	_check(expiry_resumed.size() == 2 and expiry_live.size() == 2,
		"두 흐름 모두 소멸 두 건: 처음부터 %s / 이어하기 %s" % [str(expiry_live), str(expiry_resumed)])
	var problems: Array[String] = ScriptedDice.finish()
	_check(problems.is_empty(), "준비한 주사위 모두 소비: %s" % str(problems))
	finished = true
	print("Fog spider QA: %d checks, %d failures;" % [checks, failures])
	if is_instance_valid(observer):
		observer.stop()
	quit(0 if failures == 0 else 1)


func _open_stage() -> void:
	if current_scene != null:
		current_scene.queue_free()
		await process_frame
	var main: Node = (load("res://scenes/game.tscn") as PackedScene).instantiate()
	root.add_child(main)
	current_scene = main
	battle = main.get_node("Battle") as Node2D
	battle.set_process(false)
	(battle.get("progress") as CombatActProgress).stage_index = STAGE
	battle.call("_start_stage", true)
	battle.call("start_battle")
	_bind()
	await create_timer(0.2).timeout


## 관찰 Node는 전투 장면의 자식이라 장면을 다시 열면 함께 사라진다. 흐름마다 새로 붙이고 폴더를 나눈다.
## 첫 흐름은 --capture-dir 바로 아래에, 나머지는 하위 폴더에 저장한다(start()는 기존 frames.jsonl을 거부한다).
func _attach_observer(sub: String) -> void:
	if capture_dir.is_empty():
		return
	observer = CaptureObserver.new()
	battle.add_child(observer)
	var directory: String = capture_dir if sub.is_empty() else capture_dir.path_join(sub)
	_check(observer.start(battle, directory) == OK, "독립 캡처 관찰 Node 시작: %s" % directory)


func _bind() -> void:
	units = battle.get("units")
	actions = battle.get("actions") as CombatActions
	turns = battle.get("turns") as CombatTurns
	actions.dice = ScriptedDice.new([], []).then_seeded()
	log_lines.clear()
	actions.logged.connect(func(line: String) -> void: log_lines.append(line))
	_find_spider()


func _find_spider() -> void:
	for unit: CombatUnit in units:
		if unit.kind == CombatUnit.Kind.FOG_SPIDER:
			spider = unit


func _check_layout() -> void:
	var counts: Dictionary = {}
	for unit: CombatUnit in units:
		if not unit.is_ally:
			counts[unit.kind] = int(counts.get(unit.kind, 0)) + 1
	_check(counts == {CombatUnit.Kind.SPIDERLING: 3, CombatUnit.Kind.MOTHER_SPIDER: 1, CombatUnit.Kind.FOG_SPIDER: 1},
		"3막 1스테이지 적 구성: 새끼 3·엄마 1·독안개 거미 1: %s" % str(counts))
	_check(spider != null and spider.cell == Vector2i(9, 2), "독안개 거미는 (9,2)에서 시작")
	for unit: CombatUnit in units:
		if unit.kind == CombatUnit.Kind.MOTHER_SPIDER:
			_check(unit.cell == Vector2i(9, 7), "엄마 거미는 (9,7)에 유지")


## 아군은 가만히 두고 거미 순서만 실제 AI로 돌린다. 다른 유닛의 순서는 그냥 넘긴다.
## stop_at_two가 true이면 시전이 두 건이 된 거미 순서까지만 돌리고 거미 순서 중간에 멈춘다.
func _play_until(target_round: int, stop_at_two: bool = false) -> void:
	var guard: int = 0
	while turns.round_number < target_round and guard < 200:
		guard += 1
		var unit: CombatUnit = turns.current_unit
		if unit == spider and spider.hit_points > 0:
			var before: int = actions.fog_cast_count(spider)
			var logs_before: int = _casts().size()
			await (battle.get("enemy_ai") as CombatEnemyAi).play_turn(spider, actions)
			var after: int = actions.fog_cast_count(spider)
			var cast: bool = _casts().size() > logs_before
			history.append([turns.round_number, before, after, cast, actions.fog_cells(spider).size()])
			if cast:
				cast_rounds.append(turns.round_number)
			if stop_at_two and after == 2:
				return
		turns.end_turn()
		await create_timer(0.05).timeout


func _casts() -> Array[String]:
	return log_lines.filter(func(l: String) -> bool: return "독안개 시전" in l)


## 항목 1·2: 독안개 두 곳 유지. 두 곳이 차 있는 거미 순서에는 시전하지 않고, 한 곳이 만료되면 다시 시전한다.
func _two_zones_flow() -> void:
	ScriptedDice.arrange_turns(turns, units, [units[0], units[1], spider])
	await create_timer(0.2).timeout
	history.clear()
	cast_rounds.clear()
	await _play_until(9)
	await create_timer(1.4).timeout
	print("[FOG_SPIDER] 거미 순서별 [라운드, 전 시전 수, 후 시전 수, 시전함, 칸 수]: %s" % str(history))
	print("[FOG_SPIDER] 시전 로그: %s" % str(_casts()))
	var max_count: int = 0
	var full_turn_casts: int = 0
	var full_turns: int = 0
	for entry: Array in history:
		max_count = maxi(max_count, entry[2])
		if entry[1] == 2:
			full_turns += 1
			if entry[3]:
				full_turn_casts += 1
	_check(max_count == 2, "독안개 시전 수는 최대 2건")
	_check(full_turns >= 2 and full_turn_casts == 0, "두 곳이 차 있는 거미 순서 %d번에는 시전하지 않음" % full_turns)
	_check(cast_rounds.size() >= 3, "한 곳이 만료되면 다시 시전해 두 곳을 유지: 시전 라운드 %s" % str(cast_rounds))
	# 두 건이 된 직후부터 다음 시전 전까지 모든 거미 순서가 끝날 때 2건이어야 한다. 만료 직후 같은 순서에 재시전하므로 끝 상태는 항상 2건이다.
	var after_two: bool = false
	var kept: bool = true
	for entry: Array in history:
		if after_two and entry[2] != 2:
			kept = false
		after_two = after_two or entry[2] == 2
	_check(kept, "두 건이 된 뒤 모든 거미 순서가 끝나면 독안개가 두 곳으로 유지됨")
	var expired: Array[String] = log_lines.filter(func(l: String) -> bool: return "독안개 만료" in l)
	_check(not expired.is_empty(), "시전한 장판은 거미의 순서가 돌며 만료됨: %s" % str(expired))
	await create_timer(1.4).timeout


## 항목 3: 거미를 쓰러뜨려도 장판은 남고, 각 시전은 시전한 라운드로부터 네 번째 거미 순서에 사라진다.
## resume이 true이면 거미가 쓰러진 직후 상태를 저장해 새 전투에 복원한 뒤 이어서 확인한다.
func _death_flow(resume: bool) -> Array:
	await _open_stage()
	_attach_observer("resume-before" if resume else "live-before")
	ScriptedDice.arrange_turns(turns, units, [units[0], units[1], spider])
	await create_timer(0.2).timeout
	history.clear()
	cast_rounds.clear()
	await _play_until(30, true)
	_check(actions.fog_cast_count(spider) == 2 and cast_rounds.size() == 2,
		"쓰러뜨리기 전제조건: 독안개 두 건 시전, 시전 라운드 %s" % str(cast_rounds))
	var cells_before: int = actions.fog_cells(spider).size()
	var tag: String = "이어하기" if resume else "처음부터"
	if is_instance_valid(observer):
		await create_timer(1.4).timeout
	actions.incapacitate(spider)
	_check(spider.hit_points == 0 and actions.fog_cast_count(spider) == 2
		and actions.fog_cells(spider).size() == cells_before, "거미가 쓰러져도 장판 두 건은 남음")
	var cast_copy: Array = cast_rounds.duplicate()
	if resume:
		var state: Dictionary = battle.call("combat_state")
		await _open_stage()
		_attach_observer("resume-after")
		_check(battle.call("restore_combat", state), "저장 상태 복원")
		units = battle.get("units")
		_find_spider()
		_check(battle.call("combat_state") == state, "복원 직후 전투 상태가 저장과 같음")
		_check(actions.fog_cast_count(spider) == 2 and actions.fog_cells(spider).size() == cells_before,
			"복원 뒤 독안개 두 건·같은 칸 수 유지")
	if is_instance_valid(observer):
		await create_timer(1.4).timeout
	var expiry_rounds: Array[int] = []
	var previous: int = actions.fog_cast_count(spider)
	var guard: int = 0
	while guard < 300 and actions.fog_cast_count(spider) > 0:
		guard += 1
		turns.end_turn()
		await create_timer(0.05).timeout
		var now: int = actions.fog_cast_count(spider)
		if now < previous:
			expiry_rounds.append(turns.round_number)
			previous = now
	print("[FOG_SPIDER] %s 시전 라운드 %s → 소멸 라운드 %s" % [tag, str(cast_copy), str(expiry_rounds)])
	print("[FOG_SPIDER] %s 만료 로그: %s" % [tag, str(log_lines.filter(func(l: String) -> bool: return "독안개 만료" in l))])
	_check(actions.fog_cast_count(spider) == 0 and actions.fog_cells(spider).is_empty(), "쓰러진 거미의 장판이 모두 사라짐")
	var expected: Array[int] = [int(cast_copy[0]) + 4, int(cast_copy[1]) + 4]
	_check(expiry_rounds == expected, "시전 라운드 %s로부터 네 번째 순서(라운드 %s)에 각각 소멸: %s"
		% [str(cast_copy), str(expected), str(expiry_rounds)])
	return expiry_rounds
