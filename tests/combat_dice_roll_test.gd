extends SceneTree
## 주사위 굴림 연출: 어떤 굴림이 언제 훅에 전달되는지, 아군만 보이는지, 뷰가 결과를 정확히 보이는지.

class Fixture extends RefCounted:
	var units: Array[CombatUnit] = []
	var turns: CombatTurns = CombatTurns.new()
	var actions: CombatActions = CombatActions.new()
	var events: Array[String] = []
	var rolls: Array[CombatDiceRoll] = []


const ScriptedDice = preload("res://tests/scripted_dice.gd")

var _checks: int = 0
var _failures: int = 0
var _created: Array[CombatUnit] = []
var _fixtures: Array[Fixture] = []


func _initialize() -> void:
	create_timer(60.0).timeout.connect(func() -> void:
		push_error("Combat dice roll: test timeout")
		quit(1)
	)
	_run.call_deferred()


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error(message)


func _run() -> void:
	_test_shapes()
	await _test_hit_roll_is_awaited_before_the_log()
	_test_poison_roll_does_not_block_the_turn()
	await _test_spin_save_is_awaited_before_damage()
	await _test_give_up_during_roll()
	await _test_give_up_during_spin_roll()
	_test_pull_save_does_not_block_the_action()
	_test_values_without_presentation()
	await _test_scene()
	for f: Fixture in _fixtures:
		# 훅 람다가 픽스처를 붙잡고 있어 순환을 끊는다.
		f.actions.roll_animation = Callable()
		for connection: Dictionary in f.actions.logged.get_connections():
			f.actions.logged.disconnect(connection["callable"] as Callable)
		for connection: Dictionary in f.actions.reaction_requested.get_connections():
			f.actions.reaction_requested.disconnect(connection["callable"] as Callable)
	_fixtures.clear()
	for unit: CombatUnit in _created:
		unit.free()
	var dice_problems: Array[String] = ScriptedDice.finish()
	_check(dice_problems.is_empty(), "준비한 주사위 값을 요청대로 모두 굴림 " + str(dice_problems))
	print("Combat dice roll: %d checks, %d failures" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)


## 아군 둘(0·1)과 적 둘(2·3). 연출 훅은 사건 순서를 기록하고 한 프레임을 기다린다.
func _fixture() -> Fixture:
	var f: Fixture = Fixture.new()
	_fixtures.append(f)
	for index: int in range(4):
		var unit: CombatUnit = CombatUnit.new()
		unit.kind = CombatUnit.Kind.WARRIOR if index % 2 == 0 else CombatUnit.Kind.ARCHER
		unit.is_ally = index < 2
		unit.cell = [Vector2i(4, 4), Vector2i(3, 4), Vector2i(5, 4), Vector2i(7, 4)][index]
		unit.hit_points = unit.get_max_hit_points()
		f.units.append(unit)
		_created.append(unit)
	ScriptedDice.arrange_turns(f.turns, f.units, f.units)
	f.actions.initialize(f.units, f.turns)
	f.actions.logged.connect(func(message: String) -> void: f.events.append("log: " + message))
	f.actions.roll_animation = func(roll: CombatDiceRoll) -> void:
		f.rolls.append(roll)
		f.events.append("roll start")
		await process_frame
		f.events.append("roll end")
	return f


func _dice_for(expected: Array[int], sides: Array) -> ScriptedDice:
	var typed: Array[int] = []
	typed.assign(sides)
	return ScriptedDice.new(expected, typed)


func _result(rolls: Array[int], selected: int, total: int, success: bool,
		face: CombatChecks.Face = CombatChecks.Face.NORMAL) -> CombatChecks.RollResult:
	var result: CombatChecks.RollResult = CombatChecks.RollResult.new()
	result.rolls = rolls
	result.selected_roll = selected
	result.total = total
	result.success = success
	result.face = face
	if rolls.size() > 1:
		result.mode = CombatChecks.RollMode.ADVANTAGE
	return result


func _test_shapes() -> void:
	var corners: Dictionary[int, int] = {4: 3, 6: 4, 8: 4, 10: 4, 12: 5, 20: 6, 7: 16}
	for sides: int in corners:
		_check(CombatDiceRollView.shape_points(sides).size() == corners[sides],
			"d%d는 %d각 윤곽으로 굴린다" % [sides, corners[sides]])
	_check(CombatDiceRollView.shape_points(6) != CombatDiceRollView.shape_points(8),
		"d6와 d8은 모양이 다르다")


func _test_hit_roll_is_awaited_before_the_log() -> void:
	var f: Fixture = _fixture()
	var attacker: CombatUnit = f.units[0]
	var target: CombatUnit = f.units[2]
	f.actions.dice = _dice_for([11, 4], ScriptedDice.attack_sides(attacker) + ScriptedDice.damage_sides(attacker))
	await f.actions.attack(attacker, target)
	_check(f.rolls.size() == 1, "명중과 피해를 굴려도 연출은 명중굴림 하나만 받는다: %d" % f.rolls.size())
	var roll: CombatDiceRoll = f.rolls[0]
	_check(roll.category == CombatDiceRoll.Category.HIT and roll.roller == attacker
		and roll.sides == attacker.get_ability_sides(attacker.get_attack_ability())
		and roll.bonus == attacker.get_attack_bonus() and roll.target_value == target.get_armor_class()
		and roll.result == f.actions.last_attack, "명중굴림은 확정된 결과와 AC·보정을 그대로 전달한다")
	var first_log: int = f.events.find_custom(func(event: String) -> bool: return event.begins_with("log: "))
	_check(f.events.find("roll end") != -1 and f.events.find("roll end") < first_log,
		"연출이 끝난 뒤에 공격 로그와 피해를 낸다: %s" % str(f.events))
	_check(target.hit_points < target.get_max_hit_points(), "연출을 기다려도 피해는 그대로 적용한다")


func _test_poison_roll_does_not_block_the_turn() -> void:
	var f: Fixture = _fixture()
	var target: CombatUnit = f.units[2]
	f.turns.select_unit(f.units[1])
	f.actions.apply_status(f.units[1], target, "poison")
	var dc: int = target.status_effects[0].dc
	f.actions.dice = _dice_for([3], [4])
	f.turns.end_turn()
	f.turns.end_turn()
	_check(target.hit_points == 11, "연출 훅이 기다려도 독 처리는 같은 시점에 끝난다")
	_check(f.rolls.size() == 1 and f.rolls[0].category == CombatDiceRoll.Category.SAVE
		and f.rolls[0].roller == target and f.rolls[0].target_value == dc
		and f.rolls[0].target_label == tr("DC") and f.rolls[0].sides == 4,
		"독 제거는 건강 내성굴림과 독 DC를 기준으로 전달한다")


## 회전회오리는 대상마다 내성굴림을 연출이 끝난 뒤 피해로 이어 간다 (#389 이관, DICE_PRESENTATION 내성).
func _test_spin_save_is_awaited_before_damage() -> void:
	var f: Fixture = _fixture()
	var boss: CombatUnit = f.units[2]
	boss.kind = CombatUnit.Kind.SCRAP_ROBOT_3000
	boss.hit_points = 50
	boss.begin_turn()
	f.turns.current_unit = boss
	f.units[1].cell = Vector2i(5, 3)
	# 전사 민첩 d8 8은 DC 10에 실패하고 궁수 민첩 d12 10은 성공한다 (#528).
	f.actions.dice = _dice_for([8, 6, 10, 6], [8, 12, 12, 12])
	_check(await f.actions.spin(boss), "회전회오리 실행")
	_check(f.rolls.size() == 2 and f.rolls.all(func(roll: CombatDiceRoll) -> bool:
			return roll.category == CombatDiceRoll.Category.SAVE and roll.target_label == tr("DC") and roll.target_value == 10)
		and f.rolls[0].roller == f.units[0] and f.rolls[0].sides == 8 and not f.rolls[0].result.success
		and f.rolls[1].roller == f.units[1] and f.rolls[1].sides == 12 and f.rolls[1].result.success,
		"회전회오리는 대상마다 민첩 내성굴림을 DC 기준으로 전달한다")
	var first_damage: int = -1
	for index: int in range(f.events.size()):
		if f.events[index].begins_with("log: ") and "피해" in f.events[index]:
			first_damage = index
			break
	_check(first_damage > f.events.find("roll end"), "회전회오리 피해는 첫 내성굴림 연출이 끝난 뒤 나온다")


## 연출 중 일시정지 메뉴에서 전투를 포기하면 남은 굴림 결과를 적용하지 않는다.
func _test_give_up_during_roll() -> void:
	var f: Fixture = _fixture()
	var target: CombatUnit = f.units[2]
	target.hit_points = 1
	f.units[3].hit_points = 0
	f.actions.roll_animation = func(roll: CombatDiceRoll) -> void:
		f.rolls.append(roll)
		f.actions.give_up()
		await process_frame
	f.actions.dice = _dice_for([15], ScriptedDice.attack_sides(f.units[0]))
	await f.actions.attack(f.units[0], target)
	_check(f.rolls.size() == 1 and target.hit_points == 1 and f.actions.last_damage == 0
		and f.actions.is_over() and not f.actions.is_victory(), "연출 중 전투를 포기하면 명중해도 피해와 승리를 적용하지 않는다")
	_check(not f.actions.busy, "명중 연출 중 포기한 뒤 동작 잠금을 푼다")


## 회전회오리 첫 내성굴림 연출 중 포기하면 그 대상의 피해도, 남은 대상의 굴림도 없고 동작 잠금이 풀린다.
func _test_give_up_during_spin_roll() -> void:
	var f: Fixture = _fixture()
	var boss: CombatUnit = f.units[2]
	boss.kind = CombatUnit.Kind.SCRAP_ROBOT_3000
	boss.hit_points = 50
	boss.begin_turn()
	f.turns.current_unit = boss
	f.units[1].cell = Vector2i(5, 3)
	f.actions.roll_animation = func(roll: CombatDiceRoll) -> void:
		f.rolls.append(roll)
		f.actions.give_up()
		await process_frame
	# 첫 대상(전사)은 민첩 d8로 내성굴림한다(#528).
	f.actions.dice = _dice_for([1], [8])
	_check(await f.actions.spin(boss), "회전회오리 실행")
	_check(f.rolls.size() == 1 and f.actions.last_damage == 0
		and not f.events.any(func(event: String) -> bool: return "피해" in event),
		"연출 중 포기하면 회전회오리 피해와 다음 대상의 굴림을 적용하지 않는다: %s" % str(f.events))
	_check(f.actions.is_over() and not f.actions.is_victory() and boss.hit_points == 50, "포기는 패배로 끝난다")
	_check(not f.actions.busy, "회전회오리 연출 중 포기한 뒤 동작 잠금을 푼다")


## 만능팔은 동작이 바로 끝나는 동기 처리라 내성굴림을 기다리지 않는다.
func _test_pull_save_does_not_block_the_action() -> void:
	var f: Fixture = _fixture()
	var boss: CombatUnit = f.units[2]
	boss.kind = CombatUnit.Kind.SCRAP_ROBOT_2000
	boss.hit_points = 45
	boss.cell = Vector2i(4, 4)
	boss.begin_turn()
	f.turns.current_unit = boss
	f.units[0].cell = Vector2i(1, 1)
	f.units[3].cell = Vector2i(0, 9)
	var target: CombatUnit = f.units[1]
	target.cell = Vector2i(7, 4)
	f.actions.dice = _dice_for([1], [6])
	_check(f.actions.pull(boss, target) and target.cell == Vector2i(5, 4), "만능팔 실행과 끌어오기")
	_check(f.rolls.size() == 1 and f.rolls[0].category == CombatDiceRoll.Category.SAVE
		and f.rolls[0].roller == target and f.rolls[0].target_label == tr("DC") and not f.rolls[0].result.success,
		"만능팔은 대상의 힘 내성굴림을 DC 기준으로 전달한다")
	_check(f.events.find("roll end") == -1, "만능팔 연출은 동작 처리를 멈추지 않는다")


func _test_values_without_presentation() -> void:
	var f: Fixture = _fixture()
	f.units[0].hit_points = 5
	f.units[0].potion_left = 1
	f.actions.dice = _dice_for([1, 1], [4, 4])
	_check(f.actions.use_self(f.units[0], "potion") and f.units[0].hit_points == 5 + 1 + 1 + 2, "물약 회복 실행")
	_check(f.rolls.is_empty(), "회복 굴림은 연출하지 않는다")
	var bare: CombatActions = CombatActions.new()
	_check(not bare.roll_animation.is_valid(), "훅이 없으면 연출 없이 넘어간다")


func _test_scene() -> void:
	var main: Node = (load("res://scenes/game.tscn") as PackedScene).instantiate()
	(main.get_node("Battle") as Node2D).stages[0] = load("res://scenes/combat/stage.tres") as CombatStage
	root.add_child(main)
	main.get_node("Battle").set_process(false)
	main.get_node("Battle").call("start_battle")
	current_scene = main
	await process_frame
	var battle: Node2D = current_scene.get_node("Battle") as Node2D
	var units: Array[CombatUnit] = battle.get("units")
	var actions: CombatActions = battle.get("actions") as CombatActions
	var view: CombatDiceRollView = battle.get("dice_view") as CombatDiceRollView
	var summary: Label = view.get_node("Summary") as Label
	var target: Label = view.get_node("Target") as Label
	_check(view != null and not view.visible and actions.roll_animation.is_valid(),
		"전투 장면은 숨겨진 주사위 뷰를 가지고 훅을 연결한다")
	var ally: CombatUnit = units.filter(func(unit: CombatUnit) -> bool: return unit.is_ally)[0]
	var enemy: CombatUnit = units.filter(func(unit: CombatUnit) -> bool: return not unit.is_ally)[0]
	var dice_state: int = actions.dice.state

	# 몬스터의 굴림은 보이지 않는다.
	var monster_roll: CombatDiceRoll = CombatDiceRoll.hit(enemy, 20, _result([9], 9, 12, true), 3, 12)
	await actions.roll_animation.call(monster_roll)
	_check(not view.visible, "몬스터의 명중굴림은 연출하지 않는다")
	monster_roll = CombatDiceRoll.save(enemy, 4, _result([3], 3, 3, false), 0, tr("DC"), 4)
	await actions.roll_animation.call(monster_roll)
	_check(not view.visible, "몬스터의 독 제거는 연출하지 않는다")

	# 이어하기로 다시 실행하는 중에는 아군이어도 보이지 않는다.
	battle.set("_replay_actions", 1)
	await actions.roll_animation.call(CombatDiceRoll.hit(ally, 20, _result([9], 9, 12, true), 3, 12))
	_check(not view.visible, "이어하기로 다시 실행하는 굴림은 연출하지 않는다")
	battle.set("_replay_actions", 0)

	# 아군의 명중굴림: 기준값을 먼저 보이고, 멈추면 합계와 색을 보인다.
	var hit: CombatDiceRoll = CombatDiceRoll.hit(ally, 20, _result([9], 9, 12, true), 3, 12)
	var finished: Array[bool] = [false]
	# 돌아온 그 순간의 상태. 프레임 길이와 상관없이 바로 숨기지 않고 페이드 중인지 본다.
	var fading_on_return: Array[bool] = [false]
	var play: Callable = func(roll: CombatDiceRoll) -> void:
		finished[0] = false
		await actions.roll_animation.call(roll)
		var tween: Tween = view.get("_fade") as Tween
		fading_on_return[0] = view.visible and tween != null and tween.is_running()
		finished[0] = true
	play.call(hit)
	await process_frame
	_check(view.visible and target.text == "AC 12" and summary.text == "" and not finished[0],
		"굴리는 동안 기준값 AC 12가 먼저 보이고 판정 단어는 아직 없다: " + target.text)
	await create_timer(CombatDiceRollView.TUMBLE_TIME + 0.1).timeout
	_check(summary.text == tr("간신히 성공") + "  ±0" and target.text == "AC 12"
		and summary.get_theme_color("font_color") == CombatDiceRollView.SUCCESS_COLOR,
		"멈추면 식 없이 판정 단어와 여유를 성공 색으로 보인다: " + summary.text)
	_check(view.get("_total_shown") == true and view.get("_marker_margin") == 0.0,
		"게이지 마커는 합계와 기준의 차이 위치에서 멈추고 합계를 보인다")
	_check((view.get_node("SuccessSound") as AudioStreamPlayer).playing
		and not (view.get_node("FailureSound") as AudioStreamPlayer).playing, "성공 결과음을 쓴다")
	for _frame: int in range(120):
		if finished[0]:
			break
		await process_frame
	var fade: Tween = view.get("_fade") as Tween
	_check(finished[0] and fading_on_return[0],
		"결과를 잠시 보인 뒤 바로 숨기지 않고 페이드아웃하며, 페이드를 기다리지 않고 대기하던 쪽에 돌려준다")

	# 실패. 앞 결과가 페이드아웃하는 중에 시작해 페이드를 끊는다. 이미 다 흐려졌어도 새 굴림은 불투명해야 한다.
	await create_timer(CombatDiceRollView.FADE_TIME * 0.5).timeout
	play.call(CombatDiceRoll.save(ally, 8, _result([3], 3, 6, false), 3, tr("DC"), 8))
	await process_frame
	_check(view.visible and view.modulate.a == 1.0 and not fade.is_valid() and target.text == "DC 8",
		"페이드아웃 중에 다음 굴림이 오면 페이드를 끊고 바로 새 굴림을 보인다: %.2f" % view.modulate.a)
	await create_timer(CombatDiceRollView.TUMBLE_TIME + 0.1).timeout
	_check(view.visible and view.modulate.a == 1.0, "끊긴 페이드는 끝난 뒤에도 새 굴림을 숨기지 않는다")
	_check(summary.text == tr("실패") + "  -2" and target.text == "DC 8"
		and summary.get_theme_color("font_color") == CombatDiceRollView.FAILURE_COLOR
		and (view.get_node("FailureSound") as AudioStreamPlayer).playing,
		"기준에 못 미치면 실패 색과 실패 결과음을 쓴다: " + summary.text)
	await create_timer(CombatDiceRollView.HOLD_TIME + 0.1).timeout

	# 유리: 두 주사위를 함께 보이고 버려지는 쪽을 흐리게 한다.
	var advantage: CombatChecks.RollResult = _result([4, 15], 15, 18, true)
	play.call(CombatDiceRoll.hit(ally, 20, advantage, 3, 12))
	await process_frame
	_check((view.get("_dice") as Array).size() == 2, "유리·불리는 주사위 두 개를 함께 굴린다")
	await create_timer(CombatDiceRollView.TUMBLE_TIME + 0.1).timeout
	var dice: Array = view.get("_dice")
	_check(dice[0].alpha < dice[1].alpha and dice[1].scale > dice[0].scale and dice[0].shown == 4 and dice[1].shown == 15,
		"적용되는 쪽을 키우고 버려지는 쪽을 흐리게 한다")
	await create_timer(CombatDiceRollView.HOLD_TIME + 0.1).timeout

	# 절대성공: 비교 대신 이름을 보이고 강조한다.
	play.call(CombatDiceRoll.hit(ally, 20, _result([20], 20, 23, true, CombatChecks.Face.ABSOLUTE_SUCCESS), 3, 30))
	await create_timer(CombatDiceRollView.TUMBLE_TIME + 0.1).timeout
	dice = view.get("_dice")
	_check(summary.text == tr("절대성공") and view.get("_gauge_filled") == true and view.get("_total_shown") == false
		and dice[0].scale == CombatDiceRollView.ABSOLUTE_SCALE
		and dice[0].edge == CombatDiceRollView.SUCCESS_COLOR and dice[0].emphasized,
		"절대성공은 같은 성공 색에 강조를 더한다: " + summary.text)
	await create_timer(CombatDiceRollView.HOLD_TIME + 0.1).timeout
	_check(view.visible and view.modulate.a == 1.0, "명중굴림의 절대성공은 일반 표시 시간이 지나도 흐려지지 않고 보인다")
	await create_timer(CombatDiceRollView.ABSOLUTE_HIT_HOLD_TIME - CombatDiceRollView.HOLD_TIME).timeout
	_check(view.modulate.a < 1.0, "명중굴림의 절대성공은 늘어난 표시 시간 뒤에 페이드아웃한다")

	play.call(CombatDiceRoll.hit(ally, 20, _result([1], 1, 4, false, CombatChecks.Face.ABSOLUTE_FAILURE), 3, 2))
	# 절대면 바로 뒤에 일반 굴림을 이어 붙여, 뒤 굴림이 늘어난 표시 시간만큼 기다리는지 본다.
	play.call(CombatDiceRoll.hit(ally, 20, _result([9], 9, 12, true), 3, 12))
	await create_timer(CombatDiceRollView.TUMBLE_TIME + 0.1).timeout
	dice = view.get("_dice")
	_check(summary.text == tr("절대실패") and view.get("_gauge_filled") == true and dice[0].scale == CombatDiceRollView.ABSOLUTE_SCALE
		and dice[0].edge == CombatDiceRollView.FAILURE_COLOR and dice[0].emphasized,
		"절대실패는 같은 실패 색에 강조를 더한다: " + summary.text)
	_check(summary.get_combined_minimum_size().y <= CombatDiceRollView.WORD_HEIGHT,
		"절대면의 큰 글자도 판정 단어 영역(%.0f)에 들어간다: %.1f" % [
			CombatDiceRollView.WORD_HEIGHT, summary.get_combined_minimum_size().y])
	await create_timer(CombatDiceRollView.HOLD_TIME + 0.1).timeout
	_check(summary.text == tr("절대실패"), "뒤 굴림은 절대면의 일반 표시 시간이 지나도 시작하지 않는다: " + summary.text)
	await create_timer(CombatDiceRollView.ABSOLUTE_HIT_HOLD_TIME - CombatDiceRollView.HOLD_TIME).timeout
	_check(summary.text == "" and (view.get_node("Target") as Label).text == "AC 12" and view.modulate.a == 1.0,
		"뒤 굴림은 늘어난 표시 시간이 끝난 뒤 페이드를 기다리지 않고 굴린다: " + summary.text)
	await create_timer(CombatDiceRollView.TUMBLE_TIME).timeout

	# 절대면 다음 일반 굴림은 채움·글자 크기·마커 상태를 이어받지 않는다.
	_check(view.get("_gauge_filled") == false and view.get("_total_shown") == true
		and summary.get_theme_font_size("font_size") == CombatDiceRollView.WORD_FONT_SIZE
		and summary.text == tr("간신히 성공") + "  ±0",
		"절대면 다음 일반 굴림은 게이지 채움과 글자 크기를 이어받지 않는다: " + summary.text)
	await create_timer(CombatDiceRollView.HOLD_TIME + 0.1).timeout
	var halo: float = CombatDiceRollView.DIE_RADIUS * CombatDiceRollView.ABSOLUTE_SCALE * (
		CombatDiceRollView.HALO_SCALE + CombatDiceRollView.HALO_WIDTH * 0.5)
	_check(CombatDiceRollView.DIE_CENTER_Y - halo >= 0.0
		and CombatDiceRollView.DIE_CENTER_Y + halo <= view.size.y,
		"d20·d4의 절대면 강조선은 주사위 배경 위로 나가지 않는다: %.1f, %.1f / %.1f" % [
			CombatDiceRollView.DIE_CENTER_Y - halo, CombatDiceRollView.DIE_CENTER_Y + halo, view.size.y])

	_test_grades()
	await _test_overlapping_rolls(actions, view, ally, play, finished)

	_check(actions.dice.state == dice_state, "화면 연출은 게임의 주사위 순서와 저장 상태를 바꾸지 않는다")
	current_scene.queue_free()
	await process_frame


## 판정 단어의 등급은 규칙의 성공/실패 방향을 바꾸지 않고 여유로만 세분한다.
func _test_grades() -> void:
	var cases: Array = [
		# [총합, 성공, 절대면, 기대 등급, 이름]
		[17, true, CombatChecks.Face.NORMAL, CombatDiceRollView.Grade.BIG_SUCCESS, "여유 +5"],
		[16, true, CombatChecks.Face.NORMAL, CombatDiceRollView.Grade.SUCCESS, "여유 +4"],
		[14, true, CombatChecks.Face.NORMAL, CombatDiceRollView.Grade.SUCCESS, "여유 +2"],
		[13, true, CombatChecks.Face.NORMAL, CombatDiceRollView.Grade.NARROW_SUCCESS, "여유 +1"],
		[12, true, CombatChecks.Face.NORMAL, CombatDiceRollView.Grade.NARROW_SUCCESS, "여유 0"],
		[11, false, CombatChecks.Face.NORMAL, CombatDiceRollView.Grade.NARROW_FAILURE, "여유 -1"],
		[10, false, CombatChecks.Face.NORMAL, CombatDiceRollView.Grade.FAILURE, "여유 -2"],
		[8, false, CombatChecks.Face.NORMAL, CombatDiceRollView.Grade.FAILURE, "여유 -4"],
		[7, false, CombatChecks.Face.NORMAL, CombatDiceRollView.Grade.BIG_FAILURE, "여유 -5"],
		[3, true, CombatChecks.Face.ABSOLUTE_SUCCESS, CombatDiceRollView.Grade.ABSOLUTE_SUCCESS, "절대성공은 여유와 무관"],
		[40, false, CombatChecks.Face.ABSOLUTE_FAILURE, CombatDiceRollView.Grade.ABSOLUTE_FAILURE, "절대실패는 여유와 무관"],
	]
	for entry: Array in cases:
		var result: CombatChecks.RollResult = _result([entry[0] - 3], entry[0] - 3, entry[0], entry[1], entry[2])
		_check(CombatDiceRollView.grade(result, 12) == entry[3], "등급: " + str(entry[4]))
	var absolute_result: CombatChecks.RollResult = _result([20], 20, 23, true, CombatChecks.Face.ABSOLUTE_SUCCESS)
	var normal_result: CombatChecks.RollResult = _result([9], 9, 12, true)
	var hit_absolute: CombatDiceRoll = CombatDiceRoll.hit(null, 20, absolute_result, 3, 30)
	var save_absolute: CombatDiceRoll = CombatDiceRoll.save(null, 20, absolute_result, 3, tr("DC"), 10)
	_check(CombatDiceRollView.hold_time(hit_absolute) == CombatDiceRollView.ABSOLUTE_HIT_HOLD_TIME
		and CombatDiceRollView.hold_time(CombatDiceRoll.hit(null, 20, normal_result, 3, 12)) == CombatDiceRollView.HOLD_TIME
		and CombatDiceRollView.hold_time(save_absolute) == CombatDiceRollView.HOLD_TIME
		and CombatDiceRollView.ABSOLUTE_HIT_HOLD_TIME > CombatDiceRollView.HOLD_TIME,
		"표시 시간은 명중굴림의 절대면만 늘어난다")
	_check(CombatDiceRollView.gauge_offset(0.0) == 0.0
		and CombatDiceRollView.gauge_offset(100.0) == CombatDiceRollView.GAUGE_WIDTH * 0.5
		and CombatDiceRollView.gauge_offset(-100.0) == -CombatDiceRollView.GAUGE_WIDTH * 0.5
		and CombatDiceRollView.gauge_offset(3.0) > 0.0 and CombatDiceRollView.gauge_offset(-3.0) < 0.0,
		"게이지 마커는 기준값이 중앙이고 범위를 넘으면 끝에 붙는다")


## 기다리지 않는 독 제거 둘이 연달아 오고 기다리는 명중굴림이 뒤따라도, 먼저 온 굴림부터 결과를 끝까지 보인다.
## 기다리지 않는 쪽은 바로 돌아오고, 기다리는 쪽은 앞 굴림이 닫힌 뒤 자기 연출까지 마치고 돌아온다.
func _test_overlapping_rolls(actions: CombatActions, view: CombatDiceRollView, ally: CombatUnit,
		play: Callable, finished: Array[bool]) -> void:
	var summary: Label = view.get_node("Summary") as Label
	var target: Label = view.get_node("Target") as Label
	for player_name: String in ["RollSound", "SuccessSound", "FailureSound"]:
		_check((view.get_node(player_name) as AudioStreamPlayer).max_polyphony > 1,
			"%s는 겹쳐 재생해 앞 소리를 끊지 않는다" % player_name)
	actions.roll_animation.call(CombatDiceRoll.save(ally, 4, _result([4], 4, 4, true), 0, tr("DC"), 3))
	actions.roll_animation.call(CombatDiceRoll.save(ally, 4, _result([1], 1, 1, false), 0, tr("DC"), 3))
	play.call(CombatDiceRoll.hit(ally, 20, _result([9], 9, 12, true), 3, 12))
	await create_timer(CombatDiceRollView.TUMBLE_TIME + 0.1).timeout
	_check(summary.text == tr("간신히 성공") + "  +1" and summary.get_theme_color("font_color") == CombatDiceRollView.SUCCESS_COLOR
		and (view.get_node("SuccessSound") as AudioStreamPlayer).playing,
		"뒤 굴림이 와도 첫 굴림의 결과 숫자·색·결과음이 나온다: " + summary.text)
	await create_timer(CombatDiceRollView.HOLD_TIME).timeout
	_check(view.visible and view.modulate.a == 1.0 and target.text == "DC 3" and summary.text == "",
		"첫 결과가 닫힌 뒤 페이드를 기다리지 않고 두 번째 굴림을 굴린다: " + summary.text)
	await create_timer(CombatDiceRollView.TUMBLE_TIME).timeout
	_check(summary.text == tr("실패") + "  -2" and summary.get_theme_color("font_color") == CombatDiceRollView.FAILURE_COLOR
		and (view.get_node("FailureSound") as AudioStreamPlayer).playing,
		"두 번째 굴림도 결과 숫자·색·결과음이 나온다: " + summary.text)
	await create_timer(CombatDiceRollView.HOLD_TIME).timeout
	_check(view.visible and target.text == "AC 12" and not finished[0],
		"기다리는 명중굴림은 앞 굴림들이 닫힌 뒤 차례로 굴리고 아직 돌아오지 않는다: " + summary.text)
	# 뒤따르는 굴림이 없어 여유를 더 둔다. 뷰의 마지막 타이머가 이 타이머보다 늦게 만들어진다.
	await create_timer(CombatDiceRollView.TUMBLE_TIME + CombatDiceRollView.HOLD_TIME + 0.1).timeout
	_check(finished[0] and view.modulate.a < 1.0, "명중굴림은 자기 연출까지 마친 뒤 페이드를 기다리지 않고 돌아온다")
	await create_timer(CombatDiceRollView.FADE_TIME).timeout
	_check(not view.visible and view.modulate.a == 0.0, "페이드아웃이 끝나면 주사위 뷰를 숨긴다")
