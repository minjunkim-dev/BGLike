extends SceneTree

## #470: 과부하 고철로봇의 화상 방출을 실제 게임 장면(game.tscn)에서 에이전트가 조작해 확인한다.
## 적 AI를 끈 채 실제 턴 진행(end_turn)으로 보스 턴 시작을 일으키고, 마지막 사례만 실제 적 AI를 켠다.
## 주사위는 고정 seed다. 실제 입력 장치·자연 주사위 플레이의 증거가 아니다.

const ScriptedDice = preload("res://tests/scripted_dice.gd")
const CaptureObserver = preload("res://tests/capture_observer.gd")
const BOSS_STAGES: Dictionary[int, CombatUnit.Kind] = {
	2: CombatUnit.Kind.SCRAP_ROBOT_1000,
	5: CombatUnit.Kind.SCRAP_ROBOT_2000,
	8: CombatUnit.Kind.SCRAP_ROBOT_3000,
}

var checks: int = 0
var failures: int = 0
var battle: Node2D
var actions: CombatActions
var turns: CombatTurns
var units: Array[CombatUnit]
var log_lines: Array[String] = []
var popups: Array[String] = []
var observer: CaptureObserver
var finished: bool = false


func _initialize() -> void:
	_run.call_deferred()


func _check(condition: bool, message: String) -> void:
	checks += 1
	print("[OVERLOAD_BURN] %s: %s" % ["ok" if condition else "FAIL", message])
	if not condition:
		failures += 1
		push_error(message)


func _run() -> void:
	create_timer(150.0).timeout.connect(func() -> void:
		if not finished:
			push_error("overload burn watchdog expired")
			quit(1))
	root.size = Vector2i(1280, 720)
	for stage: int in BOSS_STAGES:
		await _open_stage(stage)
		await _core_flow(BOSS_STAGES[stage])
	await _open_stage(8)
	await _edge_cases()
	await _open_stage(8)
	await _save_resume()
	await _open_stage(8)
	await _real_ai_flow()
	var problems: Array[String] = ScriptedDice.finish()
	_check(problems.is_empty(), "준비한 주사위 모두 소비: %s" % str(problems))
	finished = true
	print("Overload burn QA: %d checks, %d failures;" % [checks, failures])
	if observer != null:
		observer.stop()
	quit(0 if failures == 0 else 1)


func _open_stage(stage: int) -> void:
	if current_scene != null:
		current_scene.queue_free()
		await process_frame
	var main: Node = (load("res://scenes/game.tscn") as PackedScene).instantiate()
	root.add_child(main)
	current_scene = main
	battle = main.get_node("Battle") as Node2D
	battle.set_process(false)
	(battle.get("progress") as CombatActProgress).stage_index = stage
	battle.call("_start_stage", true)
	battle.call("start_battle")
	units = battle.get("units")
	actions = battle.get("actions") as CombatActions
	turns = battle.get("turns") as CombatTurns
	actions.dice = ScriptedDice.new([], []).then_seeded()
	log_lines.clear()
	popups.clear()
	actions.logged.connect(func(line: String) -> void: log_lines.append(line))
	actions.feedback.connect(func(unit: CombatUnit, text: String) -> void:
		popups.append("%s|%s" % [unit.get_display_name(), text]))
	await create_timer(0.2).timeout


## 보스: units의 마지막 적. 전사(0)는 보스 오른쪽 옆, 궁수(1)는 대각선에 둔다.
func _place(boss: CombatUnit, boss_hp: int) -> void:
	boss.cell = Vector2i(4, 5)
	units[0].cell = Vector2i(3, 5)
	units[1].cell = Vector2i(5, 6)
	boss.hit_points = boss_hp
	for ally: CombatUnit in units.filter(func(u: CombatUnit) -> bool: return u.is_ally):
		ally.reaction_left = 0


## 아군 턴을 모두 끝내 보스의 실제 턴 시작을 일으킨다.
func _boss_turn(boss: CombatUnit) -> void:
	log_lines.clear()
	popups.clear()
	var order: Array[CombatUnit] = []
	for unit: CombatUnit in units:
		if unit.is_ally and unit.hit_points > 0:
			order.append(unit)
	order.append(boss)
	ScriptedDice.arrange_turns(turns, units, order)
	for _i: int in range(order.size() - 1):
		turns.end_turn()
	await create_timer(0.3).timeout


func _burns(unit: CombatUnit) -> Array[int]:
	var result: Array[int] = []
	for effect: CombatUnit.StatusEffect in unit.status_effects:
		if effect.kind == "burn":
			result.append(effect.turns_left)
	result.sort()
	return result


func _has_log(part: String) -> bool:
	return log_lines.any(func(line: String) -> bool: return part in line)


## 항목 1·2·3·4·6(일부)·8(1000/2000/3000 동일): 한 보스의 전체 흐름.
func _core_flow(kind: CombatUnit.Kind) -> void:
	var boss: CombatUnit = units[units.size() - 1]
	var tag: String = "보스%d" % kind
	_check(boss.kind == kind and not boss.is_ally and units.size() == 3, "%s 전제조건: 실제 스테이지의 보스와 아군 2명" % tag)
	var warrior: CombatUnit = units[0]
	var archer: CombatUnit = units[1]
	_place(boss, boss.get_max_hit_points())
	_check(not boss.overloaded and warrior.cell == Vector2i(3, 5) and archer.cell == Vector2i(5, 6),
		"%s 전제조건: 과부하 전, 전사 인접, 궁수 대각선" % tag)
	# 항목 1: 과부하 전에는 근접해도 화상이 붙지 않는다.
	await _boss_turn(boss)
	_check(turns.current_unit == boss and _burns(warrior).is_empty() and not _has_log("화상 부여"),
		"%s 과부하 전 보스 턴: 인접 전사에게 화상 없음" % tag)
	# 항목 3: 이 턴 도중 과부하가 켜져도 이 턴에는 방출이 없다.
	boss.hit_points = boss.get_max_hit_points() / 2
	_check(boss.overloaded, "%s 보스 턴 도중 과부하 켜짐" % tag)
	await create_timer(0.2).timeout
	_check(_burns(warrior).is_empty(), "%s 과부하가 켜진 그 턴에는 방출 없음" % tag)
	# 항목 2: 다음 보스 턴 시작에 판정 없이 인접 아군에게 화상 1중첩, 로그, "화상" 팝업.
	var hp_before: int = boss.hit_points
	await _boss_turn(boss)
	_check(_burns(warrior) == [2], "%s 다음 보스 턴: 전사 화상 1중첩, 기간 2: %s" % [tag, str(_burns(warrior))])
	_check(boss.hit_points == hp_before - 2, "%s 과부하 자기 피해 2" % tag)
	_check(_has_log("과부하: 자기 피해 2") and _has_log("과부하: ") and _has_log("화상 부여"),
		"%s 과부하 자해·화상 부여 로그: %s" % [tag, str(log_lines)])
	_check(popups.any(func(p: String) -> bool: return p.ends_with("|화상")) and popups.any(func(p: String) -> bool: return p.ends_with("|과부하 2")),
		"%s '화상' 팝업과 '과부하 2' 팝업 발생: %s" % [tag, str(popups)])
	var own: int = log_lines.find_custom(func(l: String) -> bool: return "자기 피해" in l)
	var burn: int = log_lines.find_custom(func(l: String) -> bool: return "화상 부여" in l)
	_check(own >= 0 and burn > own, "%s 로그 순서: 자기 피해 다음 화상 부여" % tag)
	# 항목 6: 대각선 아군(궁수)과 보스 자신에게는 걸리지 않는다.
	_check(_burns(archer).is_empty() and _burns(boss).is_empty(), "%s 대각선 궁수와 보스 자신은 화상 없음" % tag)
	# 항목 4: 대상 턴 시작에 1d4 틱, 보스 다음 턴에 기존 화상 기간이 줄어든다.
	var warrior_hp: int = warrior.hit_points
	log_lines.clear()
	turns.end_turn()  # 보스 턴 종료 → 라운드 2 아군 턴 시작(전사 틱)
	await create_timer(0.3).timeout
	var tick: int = warrior_hp - warrior.hit_points
	_check(tick >= 1 and tick <= 4 and _has_log("화상: %d" % tick), "%s 전사 턴 시작 화상 틱 1d4: %d" % [tag, tick])
	_check(_burns(warrior) == [2], "%s 틱 뒤에도 기간은 보스 턴이 줄임(아직 2)" % tag)
	await _boss_turn(boss)
	_check(_burns(warrior) == [1, 2], "%s 보스 다음 턴: 기존 화상 기간 감소, 새 화상 추가: %s" % [tag, str(_burns(warrior))])


func _edge_cases() -> void:
	var boss: CombatUnit = units[2]
	var warrior: CombatUnit = units[0]
	var archer: CombatUnit = units[1]
	# 항목 5: 중첩 3개면 더 걸리지 않는다.
	_place(boss, 20)
	for _i: int in range(3):
		actions.apply_status(boss, warrior, "burn")
	await _boss_turn(boss)
	_check(_burns(warrior).size() == 3 and not _has_log("화상 부여"), "화상 상한 3: 방출이 더 걸지 않음")
	# 항목 5: 물 위 유닛에게는 걸리지 않는다.
	await _open_stage(8)
	boss = units[2]
	warrior = units[0]
	_place(boss, 20)
	actions.grid.water_cells = [warrior.cell]
	await _boss_turn(boss)
	_check(_burns(warrior).is_empty() and not _has_log("화상 부여"), "물 위 전사에게는 화상 없음")
	# 항목 6: 2칸 이상 떨어진 아군, 높이 차 2인 아군.
	await _open_stage(8)
	boss = units[2]
	warrior = units[0]
	archer = units[1]
	_place(boss, 20)
	archer.cell = Vector2i(6, 5)  # 2칸
	await _boss_turn(boss)
	_check(_burns(warrior).size() == 1 and _burns(archer).is_empty(), "2칸 떨어진 궁수는 화상 없음")
	await _open_stage(8)
	boss = units[2]
	warrior = units[0]
	archer = units[1]
	_place(boss, 20)
	archer.cell = Vector2i(5, 5)  # 인접하지만 높이 차 2
	actions.grid.heights[boss.cell] = 0
	actions.grid.heights[warrior.cell] = 1
	actions.grid.heights[archer.cell] = 2
	await _boss_turn(boss)
	_check(_burns(warrior).size() == 1 and _burns(archer).is_empty(), "높이 차 1 전사는 화상, 높이 차 2 궁수는 화상 없음")
	# 항목 7: 자기 피해로 전투가 끝나면 방출 없이 승리 처리된다.
	await _open_stage(8)
	boss = units[2]
	warrior = units[0]
	_place(boss, 2)
	await _boss_turn(boss)
	_check(actions.is_over() and boss.hit_points <= 0 and _burns(warrior).is_empty() and not _has_log("화상 부여"),
		"자기 피해로 보스 쓰러짐: 방출 없이 전투 종료")
	# 항목 7: 보스 자신의 화상 틱으로 전투가 끝나도(자기 피해 2 뒤 HP 1) 방출 없이 승리 처리된다.
	await _open_stage(8)
	boss = units[2]
	warrior = units[0]
	_place(boss, 3)
	actions.apply_status(warrior, boss, "burn")
	await _boss_turn(boss)
	_check(actions.is_over() and boss.hit_points <= 0 and _burns(warrior).is_empty() and not _has_log("화상 부여"),
		"자기 피해 뒤 화상 틱으로 보스 쓰러짐: 방출 없이 전투 종료: %s" % str(log_lines))


func _save_resume() -> void:
	var boss: CombatUnit = units[2]
	var warrior: CombatUnit = units[0]
	_place(boss, 20)
	await _boss_turn(boss)
	_check(_burns(warrior) == [2], "저장 전제조건: 방출 화상 중첩1·기간2")
	turns.end_turn()
	await create_timer(0.3).timeout
	await _boss_turn(boss)
	var before: Array[int] = _burns(warrior)
	var state: Dictionary = battle.call("combat_state")
	_check(before == [1, 2], "저장 전제조건: 화상 2중첩 기간 [1, 2]")
	await _open_stage(8)
	_check(battle.call("restore_combat", state), "저장 상태 복원")
	var restored: CombatUnit = (battle.get("units") as Array[CombatUnit])[0]
	_check(_burns(restored) == before and battle.call("combat_state") == state,
		"이어하기 뒤 화상 중첩과 남은 기간 유지: %s" % str(_burns(restored)))


## 항목 8(일부): 실제 적 AI가 켜진 보스 턴에서 방출과 회전회오리의 로그·팝업 순서.
func _real_ai_flow() -> void:
	var boss: CombatUnit = units[2]
	var warrior: CombatUnit = units[0]
	var archer: CombatUnit = units[1]
	_place(boss, 20)
	archer.cell = Vector2i(5, 5)  # 두 아군 모두 인접 → 회전회오리
	warrior.hit_points = warrior.get_max_hit_points()
	archer.hit_points = archer.get_max_hit_points()
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--capture-dir="):
			observer = CaptureObserver.new()
			battle.add_child(observer)
			_check(observer.start(battle, argument.trim_prefix("--capture-dir=")) == OK, "독립 캡처 관찰 Node 시작")
	battle.set_process(true)
	log_lines.clear()
	popups.clear()
	ScriptedDice.arrange_turns(turns, units, [warrior, archer, boss])
	var hud: CombatTurnHud = battle.get_node("UI/TurnHud") as CombatTurnHud
	hud.end_turn_requested.emit()
	hud.end_turn_requested.emit()
	var deadline: int = Time.get_ticks_msec() + 20000
	while Time.get_ticks_msec() < deadline and not actions.is_over() and not (turns.round_number == 2
			and turns.current_unit.is_ally and not battle.get("_enemy_turn_running")):
		await create_timer(0.05).timeout
	await create_timer(1.0).timeout
	# 이 배치에서는 회전회오리·기본 공격·화상 틱이 겹쳐 아군이 모두 쓰러질 수 있다. 전투 종료도 정상 종료로 본다.
	_check(actions.is_over() or (turns.round_number == 2 and turns.current_unit.is_ally), "실제 적 AI 종료: 전투 종료 또는 아군 차례 복귀")
	print("[OVERLOAD_BURN] AI 로그: %s" % str(log_lines))
	print("[OVERLOAD_BURN] AI 팝업: %s" % str(popups))
	var own: int = log_lines.find_custom(func(l: String) -> bool: return "자기 피해" in l)
	var first_burn: int = log_lines.find_custom(func(l: String) -> bool: return "화상 부여" in l)
	var spin: int = log_lines.find_custom(func(l: String) -> bool: return "회전회오리" in l)
	_check(own == 0 and first_burn > own and spin > first_burn, "AI 턴 로그 순서: 자기 피해 → 화상 부여 → 회전회오리")
	_check(_has_log("과부하: 아군 전사 화상 부여") and _has_log("과부하: 아군 궁수 화상 부여"), "인접한 두 아군 모두 방출 로그")
	_check(popups.count("아군 전사|화상") == 1 and popups.count("아군 궁수|화상") == 1, "인접한 두 아군 모두 '화상' 팝업 1번씩")
	battle.set_process(false)
