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
	await _test_parry_roll()
	_test_poison_roll_does_not_block_the_turn()
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


func _test_parry_roll() -> void:
	var f: Fixture = _fixture()
	f.units[0].cell = Vector2i(4, 4)
	f.units[2].cell = Vector2i(5, 4)
	f.turns.end_turn()
	f.turns.end_turn()
	f.actions.reaction_requested.connect(func(_kind: String, _prompt: String) -> void:
		f.actions.resolve_reaction(true))
	f.actions.dice = _dice_for([5, 5],
		ScriptedDice.attack_sides(f.units[2]) + [f.units[0].get_ability_sides(CombatUnit.Ability.AGILITY)])
	await f.actions.attack(f.units[2], f.units[0])
	_check(f.rolls.size() == 2 and f.rolls[0].category == CombatDiceRoll.Category.HIT
		and f.rolls[1].category == CombatDiceRoll.Category.SAVE, "공격을 맞은 쪽의 흘려내기가 이어서 전달된다")
	if f.rolls.size() < 2:
		return
	var parry: CombatDiceRoll = f.rolls[1]
	_check(parry.roller == f.units[0] and parry.bonus == 3 and parry.target_value == f.actions.last_attack.total
		and parry.target_label == tr("공격"), "흘려내기는 굴리는 아군, 보정+3, 맞은 공격 합계를 기준으로 전달한다")
	_check(parry.result.success, "흘려내기의 확정 결과를 그대로 전달한다")


func _test_poison_roll_does_not_block_the_turn() -> void:
	var f: Fixture = _fixture()
	var target: CombatUnit = f.units[2]
	f.turns.select_unit(f.units[1])
	f.actions.apply_status(f.units[1], target, "poison")
	var strength: int = target.status_effects[0].strength
	f.actions.dice = _dice_for([3], [4])
	f.turns.end_turn()
	f.turns.end_turn()
	_check(target.hit_points == 11, "연출 훅이 기다려도 독 처리는 같은 시점에 끝난다")
	_check(f.rolls.size() == 1 and f.rolls[0].category == CombatDiceRoll.Category.SAVE
		and f.rolls[0].roller == target and f.rolls[0].target_value == strength
		and f.rolls[0].target_label == tr("강도") and f.rolls[0].sides == 4,
		"독 제거는 건강 주사위와 독 강도를 기준으로 전달한다")
	_check(f.events.find("roll end") == -1 or f.events.find("roll end") > f.events.find("roll start"),
		"독 제거 연출은 턴 시작 처리를 멈추지 않고 이어서 재생한다")


func _test_values_without_presentation() -> void:
	var f: Fixture = _fixture()
	f.units[0].hit_points = 5
	f.actions.dice = _dice_for([5], [10])
	f.actions.use_self(f.units[0], "second_wind")
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
	_check(view != null and not view.visible and actions.roll_animation.is_valid(),
		"전투 장면은 숨겨진 주사위 뷰를 가지고 훅을 연결한다")
	var ally: CombatUnit = units.filter(func(unit: CombatUnit) -> bool: return unit.is_ally)[0]
	var enemy: CombatUnit = units.filter(func(unit: CombatUnit) -> bool: return not unit.is_ally)[0]
	var dice_state: int = actions.dice.state

	# 몬스터의 굴림은 보이지 않는다.
	var monster_roll: CombatDiceRoll = CombatDiceRoll.hit(enemy, 20, _result([9], 9, 12, true), 3, 12)
	await actions.roll_animation.call(monster_roll)
	_check(not view.visible, "몬스터의 명중굴림은 연출하지 않는다")
	monster_roll = CombatDiceRoll.save(enemy, 4, _result([3], 3, 3, false), 0, tr("강도"), 4)
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
	var play: Callable = func(roll: CombatDiceRoll) -> void:
		finished[0] = false
		await actions.roll_animation.call(roll)
		finished[0] = true
	play.call(hit)
	await process_frame
	_check(view.visible and summary.text == "AC 12" and not finished[0],
		"굴리는 동안 기준값 AC 12가 먼저 보인다: " + summary.text)
	await create_timer(CombatDiceRollView.TUMBLE_TIME + 0.1).timeout
	_check(summary.text == "9 +3 = 12  ≥  AC 12" and summary.get_theme_color("font_color") == CombatDiceRollView.SUCCESS_COLOR,
		"멈추면 합계와 기준을 비교해 성공 색으로 보인다: " + summary.text)
	_check((view.get_node("ResultSound") as AudioStreamPlayer).stream == CombatDiceRollView.SUCCESS_SOUND,
		"성공 결과음을 쓴다")
	await create_timer(CombatDiceRollView.HOLD_TIME + 0.1).timeout
	_check(not view.visible and finished[0], "결과를 잠시 보인 뒤 닫고 대기하던 쪽에 돌려준다")

	# 실패.
	play.call(CombatDiceRoll.save(ally, 8, _result([3], 3, 6, false), 3, tr("공격"), 8))
	await create_timer(CombatDiceRollView.TUMBLE_TIME + 0.1).timeout
	_check(summary.text == "3 +3 = 6  <  공격 8" and summary.get_theme_color("font_color") == CombatDiceRollView.FAILURE_COLOR
		and (view.get_node("ResultSound") as AudioStreamPlayer).stream == CombatDiceRollView.FAILURE_SOUND,
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
	_check(summary.text.begins_with(tr("절대성공")) and dice[0].scale == CombatDiceRollView.ABSOLUTE_SCALE
		and dice[0].edge == CombatDiceRollView.ABSOLUTE_COLOR, "절대성공은 같은 성공 색에 강조를 더한다: " + summary.text)
	await create_timer(CombatDiceRollView.HOLD_TIME + 0.1).timeout

	_check(actions.dice.state == dice_state, "화면 연출은 게임의 주사위 순서와 저장 상태를 바꾸지 않는다")
	current_scene.queue_free()
	await process_frame
