extends SceneTree

## 실제 전투 피드백의 이동 경로와 상태 표시 겹침을 매 프레임 검사한다.

const ScriptedDice = preload("res://tests/scripted_dice.gd")
const CaptureObserver = preload("res://tests/capture_observer.gd")

var checks: int = 0
var failures: int = 0
var battle: Node2D
var turns: CombatTurns
var observer: CaptureObserver
var collisions: Array[String] = []
var messages: Array[String] = []
var monitoring: bool = true
var popup_samples: int = 0
var popup_styles: Dictionary[String, Array] = {}
var manual: bool = "--manual" in OS.get_cmdline_user_args()
var finished: bool = false


func _initialize() -> void:
	_run.call_deferred()


func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)


func _run() -> void:
	create_timer(180.0 if manual else 20.0).timeout.connect(func() -> void:
		if not finished:
			push_error("Combat feedback watchdog expired")
			quit(1))
	root.size = Vector2i(640, 360)
	var main: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	current_scene = main
	battle = main.get_node("Battle") as Node2D
	(battle.get("progress") as CombatActProgress).stage_index = 8
	battle.call("_start_stage", true)
	var units: Array[CombatUnit] = battle.get("units")
	_check(units.size() == 3, "반복 공격 전제조건: 3-3 유닛 3개")
	if units.size() != 3:
		await _abort_fixture()
		return
	var boss: CombatUnit = units[2]
	units[0].cell = Vector2i(3, 4)
	units[1].cell = Vector2i(5, 4)
	boss.cell = Vector2i(4, 4)
	boss.hit_points = 25
	turns = battle.get("turns") as CombatTurns
	turns.start(units, ScriptedDice.new([20, 20, 1]))
	var actions: CombatActions = battle.get("actions") as CombatActions
	# 판정·피해·빗나감이 같은 반복 공격에서 발생하는 통제된 재현이다.
	actions.dice = ScriptedDice.new([15, 1, 1, 20, 1, 1, 15, 2], [20, 8, 20, 20, 8, 8, 20, 8])
	for unit: CombatUnit in units:
		if unit.is_ally:
			unit.reaction_left = 0
	actions.logged.connect(func(message: String) -> void: messages.append(message))
	battle.call("_update_turn_ui")
	if not _fixture_ready(units):
		await _abort_fixture()
		return
	print("[FEEDBACK_FIXTURE] 통제된 재현: HP25·배치·주사위 고정, 아군 반응0")
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--capture-dir="):
			observer = CaptureObserver.new()
			battle.add_child(observer)
			_check(observer.start(battle, argument.trim_prefix("--capture-dir=")) == OK,
				"독립 캡처 관찰 Node 시작")
	_monitor()
	await create_timer(0.2).timeout
	if manual:
		print("[FEEDBACK_CHECK] READY: 통제된 반복 공격 재현. 아군 두 명의 턴 종료를 누르세요.")
		_check(await _wait_for(func() -> bool:
			return turns.current_unit != null and not turns.current_unit.is_ally, 120.0),
			"직접 입력으로 적 차례 진입")
	else:
		var hud: CombatTurnHud = battle.get_node("UI/TurnHud") as CombatTurnHud
		hud.end_turn_requested.emit()
		hud.end_turn_requested.emit()
	_check(await _wait_for(func() -> bool:
		return (turns.round_number == 2 and turns.current_unit.is_ally
			and not battle.get("_enemy_turn_running")), 10.0), "실제 적 AI 종료와 아군 차례 복귀")
	# 마지막 팝업이 사라지는 구간까지 검사한다.
	await create_timer(1.0).timeout
	_check(popup_samples > 0, "반복 공격에서 실제 팝업을 관찰함")
	_check(collisions.is_empty(), "반복 공격 팝업 겹침 없음: %s" % str(collisions))
	_check(popup_styles.get("치명타!", []) == [CombatUnit.CRITICAL_COLOR, 14], "치명타는 금색 큰 글씨 팝업")
	_check(popup_styles.get("자동 실패", []) == [CombatUnit.FUMBLE_COLOR, 10], "자동 실패는 회색 팝업")
	_check(messages.filter(func(line: String) -> bool: return "회전회오리:" in line).size() == 2,
		"과부하 중 회전 공격 두 번 유지")
	_check(units[0].hit_points == 5 and units[1].hit_points == 10 and boss.hit_points == 23,
		"명중·빗나감·치명타 피해와 과부하 자해 유지")
	_check(_popups().is_empty(), "마지막 피드백 이후 팝업 제거")
	await _test_shock_feedback()
	monitoring = false
	if observer != null:
		_check(observer.last_error == OK and observer.frame_count > 0, "Forward+ 원본 프레임 저장")
		observer.stop()
	var problems: Array[String] = ScriptedDice.finish()
	_check(problems.is_empty(), "준비한 주사위 모두 소비: %s" % str(problems))
	finished = true
	print("Combat feedback: %d checks, %d failures; samples=%d; collisions=%s" % [
		checks, failures, popup_samples, str(collisions)])
	if manual and failures == 0:
		print("[FEEDBACK_CHECK] PASS")
		return
	main.queue_free()
	await process_frame
	quit(0 if failures == 0 else 1)


func _fixture_ready(units: Array[CombatUnit]) -> bool:
	var previous_failures: int = failures
	var boss: CombatUnit = units[2]
	_check(units[0].is_ally and units[0].kind == CombatUnit.Kind.WARRIOR
		and units[1].is_ally and units[1].kind == CombatUnit.Kind.ARCHER
		and not boss.is_ally and boss.kind == CombatUnit.Kind.SCRAP_ROBOT_3000,
		"반복 공격 전제조건: 전사·궁수·고철로봇 3000")
	var portraits: Dictionary = battle.get_node("UI/TurnHud").get("_portraits")
	_check(portraits.size() == 3 and portraits.has(units[0]) and portraits.has(units[1])
		and portraits.has(boss), "반복 공격 전제조건: 실제 유닛의 초상 3개")
	_check(boss.hit_points == 25 and boss.overloaded and boss.action_left == 2,
		"반복 공격 전제조건: HP25 과부하와 행동2")
	for ally: CombatUnit in [units[0], units[1]]:
		_check(CombatGrid.distance(ally.cell, boss.cell) == 1
			and ally.hit_points == ally.get_max_hit_points()
			and ally.movement_left == CombatUnit.MOVEMENT_PER_TURN
			and ally.action_left == 1 and ally.bonus_action_left == 1 and ally.reaction_left == 0,
			"반복 공격 전제조건: 인접 아군의 정상 HP·턴 자원과 반응0")
	return failures == previous_failures


func _abort_fixture() -> void:
	finished = true
	monitoring = false
	current_scene.queue_free()
	await process_frame
	quit(1)


func _test_shock_feedback() -> void:
	for marked: bool in [false, true]:
		(battle.get("progress") as CombatActProgress).stage_index = 1
		battle.call("_start_stage", true)
		var units: Array[CombatUnit] = battle.get("units")
		var archer: CombatUnit = units[1]
		var target: CombatUnit = units[2]
		units[0].cell = Vector2i(0, 9)
		archer.cell = Vector2i(2, 4)
		target.cell = Vector2i(5, 4)
		target.reaction_left = 0
		turns.start(units, ScriptedDice.new([1, 20, 1]))
		var actions: CombatActions = battle.get("actions") as CombatActions
		if marked:
			_check(actions.mark(archer, target), "충격 화살 전 표식 적용")
		actions.dice = (ScriptedDice.new([15, 2, 1, 1], [20, 6, 6, 20]) if marked
			else ScriptedDice.new([15, 2, 1], [20, 6, 20]))
		battle.call("_update_turn_ui")
		_check(await actions.attack(archer, target, true), "실제 충격 화살 실행")
		_check(target.is_stunned and target.has_mark == marked, "기절·표식 상태 유지")
		_check(target.hit_points == (8 if marked else 9), "충격 화살 피해 유지")
		await create_timer(1.0).timeout
		_check(collisions.is_empty(), "충격 화살 팝업·상태 표시 겹침 없음: %s" % str(collisions))
		_check(_popups().is_empty(), "충격 화살 팝업 제거")


func _wait_for(predicate: Callable, seconds: float) -> bool:
	var deadline: int = Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < deadline:
		if predicate.call():
			return true
		await create_timer(0.02).timeout
	return false


func _popups() -> Array[Label]:
	var result: Array[Label] = []
	for child: Node in battle.get_node("Units").get_children():
		if child is Label and child.has_meta("feedback_unit"):
			result.append(child)
	return result


func _monitor() -> void:
	while monitoring:
		await process_frame
		if not monitoring:
			return
		var popups: Array[Label] = _popups()
		popup_samples += popups.size()
		for index: int in range(popups.size()):
			var popup: Label = popups[index]
			popup_styles[popup.text] = [popup.get_theme_color("font_color"), popup.get_theme_font_size("font_size")]
			if popup.modulate.a < 0.1:
				continue
			var rect: Rect2 = popup.get_global_transform_with_canvas() * Rect2(Vector2.ZERO, popup.size)
			var outside: String = "화면 밖: %s" % popup.text
			if not root.get_visible_rect().encloses(rect.grow(2)) and outside not in collisions:
				collisions.append(outside)
			var hud: CombatTurnHud = battle.get_node("UI/TurnHud") as CombatTurnHud
			for unit: CombatUnit in battle.get("units"):
				var status: String = ("기절" if unit.is_stunned else "") + (" ◎" if unit.has_mark else "")
				if status.is_empty():
					continue
				var font: Font = ThemeDB.fallback_font
				var width: float = font.get_string_size(status, HORIZONTAL_ALIGNMENT_LEFT, -1, 10).x
				var status_rect: Rect2 = unit.get_global_transform_with_canvas() * Rect2(
					Vector2(-width / 2.0, unit.floor_offset_y + unit.get_status_label_y() - font.get_ascent(10)),
					Vector2(width, font.get_height(10)))
				var status_pair: String = "%s / %s %s" % [popup.text, unit.get_display_name(), status]
				if rect.grow(2).intersects(status_rect) and status_pair not in collisions:
					collisions.append(status_pair)
			for panel: String in ["Round", "Progress", "OrderScroll", "UnitDetails", "Skills", "CombatLog", "EndTurn"]:
				var control: Control = hud.get_node(panel) as Control
				var blocked: String = "%s / HUD %s" % [popup.text, panel]
				if rect.grow(2).intersects(control.get_global_rect()) and blocked not in collisions:
					collisions.append(blocked)
			for other_index: int in range(index):
				var other: Label = popups[other_index]
				var other_rect: Rect2 = other.get_global_transform_with_canvas() * Rect2(Vector2.ZERO, other.size)
				var pair: String = "%s / %s" % [other.text, popup.text]
				if (other.modulate.a >= 0.1 and rect.grow(2).intersects(other_rect.grow(2))
					and pair not in collisions):
					collisions.append(pair)
