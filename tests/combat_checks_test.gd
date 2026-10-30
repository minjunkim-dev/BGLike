extends SceneTree
## M1 3단계의 판정 수학, 상태 조건과 실제 클릭 경로를 검사한다.

const ScriptedDice = preload("res://tests/scripted_dice.gd")

var _checks: int = 0
var _failures: int = 0
var _created_units: Array[CombatUnit] = []


func _initialize() -> void:
	create_timer(30.0).timeout.connect(func() -> void:
		push_error("Combat checks: test timeout")
		quit(1)
	)
	_run.call_deferred()


func _run() -> void:
	_test_scripted_dice_leftovers()
	_test_scripted_dice_shortfall()
	_test_modes()
	_test_ability_dice()
	_test_opposed_rolls()
	_test_standard_values()
	_test_hit_chances()
	_test_hit_rolls()
	await _test_battle_rolls()
	await _test_spin_shared_modes()
	_test_spin_disadvantage()
	_test_strength_validation()
	_test_preview_conditions()
	_test_monster_hit_table()
	await _test_scene_input()
	await _test_scene_mixed_spin()
	for unit: CombatUnit in _created_units:
		unit.free()
	var dice_problems: Array[String] = ScriptedDice.finish()
	_check(dice_problems.is_empty(), "준비한 주사위 값을 요청대로 모두 굴림 " + str(dice_problems))
	print("Combat checks: %d checks, %d failures" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error(message)


## 다른 ScriptedDice보다 먼저 실행해야 finish()가 이 검사의 인스턴스만 본다.
func _test_scripted_dice_leftovers() -> void:
	var dice: ScriptedDice = ScriptedDice.new([3, 4], [6, 6], [0.5])
	dice.roll(6)
	_check(dice.unused() == [4, 0.5], "굴리지 않은 정수·확률 준비값을 남은 값으로 보고")
	ScriptedDice.new([7], [6]).roll(6)
	ScriptedDice.new([], [], [1.0]).chance()
	var problems: Array[String] = ScriptedDice.finish()
	_check(problems == ["7는 1~6 밖", "확률 1.0은 0 이상 1 미만 밖", "굴리지 않은 준비값 [4, 0.5]"],
		"finish()가 범위 밖 정수·확률과 남은 준비값을 보고 " + str(problems))
	_check(ScriptedDice.finish().is_empty(), "finish()는 보고한 문제와 인스턴스를 비움")


func _test_scripted_dice_shortfall() -> void:
	var dice: ScriptedDice = ScriptedDice.new([3], [6])
	dice.roll(6)
	dice.roll(8)
	dice.chance()
	var seeded: CombatDice = ScriptedDice.new([3], [6]).then_seeded()
	seeded.roll(6)
	seeded.roll(8)
	seeded.chance()
	var problems: Array[String] = ScriptedDice.finish()
	_check(problems == ["준비값 부족 d8", "확률 준비값 부족"],
		"준비값보다 더 굴리면 보고하고 then_seeded()는 seed 굴림을 허용 " + str(problems))


func _unit(kind: CombatUnit.Kind, ally: bool, cell: Vector2i) -> CombatUnit:
	var unit: CombatUnit = CombatUnit.new()
	unit.kind = kind
	unit.is_ally = ally
	unit.cell = cell
	unit.hit_points = unit.get_max_hit_points()
	_created_units.append(unit)
	return unit


func _test_ability_dice() -> void:
	for profile: Array in [
		[CombatUnit.Kind.WARRIOR, true, [20, 8, 6, 4, 6, 12]],
		[CombatUnit.Kind.ARCHER, true, [6, 12, 20, 6, 4, 8]],
		[CombatUnit.Kind.WARRIOR, false, [10, 6, 4, 4, 4, 4]],
		[CombatUnit.Kind.ARCHER, false, [4, 10, 4, 4, 4, 4]],
		[CombatUnit.Kind.SPIDERLING, false, [4, 8, 4, 4, 4, 4]],
		[CombatUnit.Kind.MOTHER_SPIDER, false, [8, 6, 4, 4, 6, 8]],
		[CombatUnit.Kind.SCRAP_ROBOT_1000, false, [12, 4, 8, 4, 12, 4]],
		[CombatUnit.Kind.SCRAP_ROBOT_2000, false, [12, 4, 8, 4, 12, 4]],
		[CombatUnit.Kind.SCRAP_ROBOT_3000, false, [12, 4, 8, 4, 12, 4]],
	]:
		var unit: CombatUnit = _unit(profile[0], profile[1], Vector2i.ZERO)
		for ability: CombatUnit.Ability in CombatUnit.Ability.values():
			_check(unit.get_ability_sides(ability) == profile[2][ability],
				"기획서의 여섯 능력치 주사위: %s %d" % [unit.get_display_name(), ability])


func _test_modes() -> void:
	_check(CombatChecks.roll_mode(0, 0) == CombatChecks.RollMode.NORMAL, "조건 없으면 일반")
	_check(CombatChecks.roll_mode(3, 0) == CombatChecks.RollMode.ADVANTAGE, "유리 여러 개는 한 번의 유리")
	_check(CombatChecks.roll_mode(0, 3) == CombatChecks.RollMode.DISADVANTAGE, "불리 여러 개는 한 번의 불리")
	_check(CombatChecks.roll_mode(2, 1) == CombatChecks.RollMode.ADVANTAGE, "유리 요인이 더 많으면 유리")
	_check(CombatChecks.roll_mode(1, 2) == CombatChecks.RollMode.DISADVANTAGE, "불리 요인이 더 많으면 불리")
	_check(CombatChecks.roll_mode(2, 2) == CombatChecks.RollMode.NORMAL, "유리와 불리 요인 수가 같으면 일반")


func _test_opposed_rolls() -> void:
	var normal: CombatChecks.RollMode = CombatChecks.RollMode.NORMAL
	var result: CombatChecks.RollResult = CombatChecks.opposed_attack(
		20, 10, 1, 2, normal, ScriptedDice.new([7, 6], [20, 10]))
	_check(result.rolls == [7] and result.total == 8
		and result.defender_roll == 6 and result.defender_total == 8
		and not result.success, "대결의 원본 굴림과 장비 가산을 보존, 동점 방어자 승")
	result = CombatChecks.opposed_attack(
		4, 20, 30, 0, normal, ScriptedDice.new([1, 20], [4, 20]))
	_check(result.success, "대결은 최솟값도 합계가 높으면 성공")
	result = CombatChecks.opposed_attack(
		20, 4, 0, 30, normal, ScriptedDice.new([20, 1], [20, 4]))
	_check(not result.success, "대결은 최댓값도 합계가 낮으면 실패")
	for mode: CombatChecks.RollMode in [CombatChecks.RollMode.ADVANTAGE, CombatChecks.RollMode.DISADVANTAGE]:
		result = CombatChecks.opposed_attack(
			20, 10, 0, 0, mode, ScriptedDice.new([3, 17, 9], [20, 20, 10]))
		_check(result.rolls == [3, 17] and result.defender_roll == 9
			and result.mode == mode and result.success == (mode == CombatChecks.RollMode.ADVANTAGE),
			"유리/불리는 공격 주사위만 두 번, 방어 주사위는 한 번")
	var dice: CombatDice = CombatDice.new()
	dice.seed = 321
	var saved_state: int = dice.state
	result = CombatChecks.opposed_attack(8, 12, 1, 2, CombatChecks.RollMode.ADVANTAGE, dice)
	dice.state = saved_state
	var replay: CombatChecks.RollResult = CombatChecks.opposed_attack(
		8, 12, 1, 2, CombatChecks.RollMode.ADVANTAGE, dice)
	_check(result.rolls == replay.rolls and result.defender_roll == replay.defender_roll,
		"난수 상태 복원 뒤 공격과 방어 굴림을 함께 재현")
	result = CombatChecks.threshold(8, 3, 7, ScriptedDice.new([4], [8]))
	_check(result.success and result.total == 7, "흘려내기 민첩 +3은 같은 공격값에도 성공")
	result = CombatChecks.threshold(6, 0, 4, ScriptedDice.new([4], [6]))
	_check(result.success, "건강 d6 대 독 강도4는 동점 제거 성공")
	_check(is_equal_approx(CombatChecks.threshold_chance(6, 0, 4), 0.5), "독 제거 확률 50%")
	_check(CombatChecks.threshold_chance(8, 3, 30) == 0.0
		and CombatChecks.threshold_chance(8, 3, 1) == 1.0, "흘려내기 확률은 0~100%")
	var shared: CombatChecks.RollResult = CombatChecks.attack_roll(12, 3, normal, ScriptedDice.new([8], [12]))
	var first: CombatChecks.RollResult = CombatChecks.defend_against(shared, 20, 0, ScriptedDice.new([10], [20]))
	var second: CombatChecks.RollResult = CombatChecks.defend_against(shared, 8, 4, ScriptedDice.new([8], [8]))
	_check(first.total == 11 and second.total == 11 and first.success and not second.success,
		"광역은 같은 공격 굴림과 대상별 방어를 비교")
	_check(first.defender_roll == 10 and shared.defender_roll == 0, "다음 대상의 방어는 이전 대상·공통 공격을 변경하지 않음")


func _test_standard_values() -> void:
	for expected: Array in [[4, 3], [6, 4], [8, 5], [10, 6], [12, 7], [20, 11]]:
		_check(CombatChecks.standard_value(expected[0]) == expected[1],
			"기획서 4-3 표준값 d%d = %d" % expected)


func _test_hit_chances() -> void:
	var normal: CombatChecks.RollMode = CombatChecks.RollMode.NORMAL
	# 기획서 4-13 확률 감각 표: 시작 상태 주사위, 가산 0으로 N 이상.
	var thresholds: Array[int] = [2, 3, 4, 5, 6, 8, 10, 12, 16, 20]
	var table: Dictionary = {
		4: [75.0, 50.0, 25.0, 0, 0, 0, 0, 0, 0, 0],
		6: [83.3, 66.7, 50.0, 33.3, 16.7, 0, 0, 0, 0, 0],
		8: [87.5, 75.0, 62.5, 50.0, 37.5, 12.5, 0, 0, 0, 0],
		10: [90.0, 80.0, 70.0, 60.0, 50.0, 30.0, 10.0, 0, 0, 0],
		12: [91.7, 83.3, 75.0, 66.7, 58.3, 41.7, 25.0, 8.3, 8.3, 8.3],
		20: [95.0, 90.0, 85.0, 80.0, 75.0, 65.0, 55.0, 45.0, 25.0, 15.0],
	}
	for sides: int in table:
		for index: int in thresholds.size():
			var percent: float = CombatChecks.hit_chance(sides, 0, thresholds[index], normal) * 100.0
			_check(absf(percent - table[sides][index]) < 0.05,
				"4-13 표 d%d ≥%d = %.1f%% (실제 %.2f%%)" % [sides, thresholds[index], table[sides][index], percent])
	for sides: int in table:
		_check(is_equal_approx(CombatChecks.hit_chance(sides, 0, CombatChecks.standard_value(sides), normal), 0.5),
			"같은 모양 d%d와 가산 0이면 명중률 50%%" % sides)
	_check(is_equal_approx(CombatChecks.hit_chance(10, 3, 5, normal), 0.9)
		and is_equal_approx(CombatChecks.hit_chance(10, 3, 7, normal), 0.7),
		"풋내기 야만인 힘 d10+3은 전사 AC5에 90%, 궁수 AC7에 70%")
	_check(is_equal_approx(CombatChecks.hit_chance(10, 30, 1, normal), 0.9),
		"가산이 아무리 커도 절대실패면은 빗나감")
	_check(is_equal_approx(CombatChecks.hit_chance(20, 0, 99, normal), 0.15)
		and is_equal_approx(CombatChecks.hit_chance(12, -30, 99, normal), 1.0 / 12.0)
		and CombatChecks.hit_chance(10, 0, 99, normal) == 0.0,
		"절대성공면(d20 3개, d12 1개)은 AC와 무관하게 명중, d10은 없음")
	# 단일 성공률 p에서 유리는 1-(1-p)², 불리는 p²이다.
	_check(is_equal_approx(CombatChecks.hit_chance(20, 0, 4, CombatChecks.RollMode.ADVANTAGE), 0.9775)
		and is_equal_approx(CombatChecks.hit_chance(20, 0, 4, CombatChecks.RollMode.DISADVANTAGE), 0.7225),
		"유리/불리 명중률은 두 번 굴린 면의 열거 (85% → 97.75% / 72.25%)")
	_check(is_equal_approx(CombatChecks.hit_chance(20, 0, 99, CombatChecks.RollMode.DISADVANTAGE), 0.0225),
		"불리에서도 두 면이 모두 절대성공이면 명중")


func _test_hit_rolls() -> void:
	var normal: CombatChecks.RollMode = CombatChecks.RollMode.NORMAL
	var result: CombatChecks.RollResult = CombatChecks.hit_roll(20, 1, 8, normal, ScriptedDice.new([7], [20]))
	_check(result.rolls == [7] and result.selected_roll == 7 and result.total == 8 and result.success
		and result.face == CombatChecks.Face.NORMAL, "공격 굴림이 AC와 같으면 명중")
	result = CombatChecks.hit_roll(20, 1, 9, normal, ScriptedDice.new([7], [20]))
	_check(not result.success, "공격 굴림이 AC보다 1 낮으면 빗나감")
	result = CombatChecks.hit_roll(20, 0, 99, normal, ScriptedDice.new([18], [20]))
	_check(result.success and result.rolls == [20] and result.total == 20
		and result.face == CombatChecks.Face.ABSOLUTE_SUCCESS, "d20 절대성공면은 숫자 20이며 AC와 무관하게 명중")
	result = CombatChecks.hit_roll(10, 30, 2, normal, ScriptedDice.new([1], [10]))
	_check(not result.success and result.total == 31 and result.face == CombatChecks.Face.ABSOLUTE_FAILURE,
		"절대실패면은 가산이 있어도 빗나감")
	result = CombatChecks.hit_roll(10, 0, 1, normal, ScriptedDice.new([10], [10]))
	_check(result.success and result.face == CombatChecks.Face.NORMAL, "d10의 최댓값은 일반면")
	for mode: CombatChecks.RollMode in [CombatChecks.RollMode.ADVANTAGE, CombatChecks.RollMode.DISADVANTAGE]:
		var advantage: bool = mode == CombatChecks.RollMode.ADVANTAGE
		result = CombatChecks.hit_roll(20, 0, 10, mode, ScriptedDice.new([3, 17], [20, 20]))
		_check(result.rolls == [3, 17] and result.selected_roll == (17 if advantage else 3)
			and result.success == advantage and result.mode == mode, "유리는 높은 값, 불리는 낮은 값을 고름")
		result = CombatChecks.hit_roll(20, 30, 2, mode, ScriptedDice.new([1, 19], [20, 20]))
		_check(result.rolls == [1, 20] and result.success == advantage
			and result.face == (CombatChecks.Face.ABSOLUTE_SUCCESS if advantage else CombatChecks.Face.ABSOLUTE_FAILURE),
			"고른 굴림이 절대면이면 절대면 효과 적용")


func _test_battle_rolls() -> void:
	var warrior: CombatUnit = _unit(CombatUnit.Kind.WARRIOR, true, Vector2i(4, 4))
	var archer: CombatUnit = _unit(CombatUnit.Kind.ARCHER, true, Vector2i(3, 4))
	var barbarian: CombatUnit = _unit(CombatUnit.Kind.WARRIOR, false, Vector2i(5, 4))
	var units: Array[CombatUnit] = [warrior, archer, barbarian]
	var turns: CombatTurns = CombatTurns.new()
	var actions: CombatActions = CombatActions.new()
	actions.initialize(units, turns)
	ScriptedDice.arrange_turns(turns, units, [warrior, archer, barbarian])
	var logs: Array[String] = []
	var observe: Callable = func(message: String) -> void: logs.append(message)
	actions.logged.connect(observe)
	var strength: CombatUnit.Ability = CombatUnit.Ability.STRENGTH
	actions.dice = ScriptedDice.new([4, 2], [warrior.get_ability_sides(warrior.get_attack_ability()), warrior.get_damage_sides()])
	var before: int = barbarian.hit_points
	_check(barbarian.get_armor_class() == 4 and warrior.get_ability_sides(strength) == 20, "풋내기 야만인 AC 4, 전사 힘 d20")
	_check(await actions.attack(warrior, barbarian) and barbarian.hit_points == before - 2 - warrior.get_damage_bonus()
		and actions.last_attack.rolls == [4] and actions.last_attack.total == 4 and actions.last_attack.defender_roll == 0
		and actions.last_damage_rolls == [2], "전사 힘 4가 야만인 AC 4와 같으면 명중, 야만인은 굴리지 않음")
	_check(logs.any(func(message: String) -> bool: return "힘 d20 [4] +0 = 4 / AC 4 · 명중" in message),
		"로그에 전사의 힘 d20 굴림 하나와 AC " + str(logs))
	barbarian.cell = Vector2i(3, 7)
	turns.select_unit(archer)
	actions.dice = ScriptedDice.new([4, 1], [archer.get_ability_sides(archer.get_attack_ability()), archer.get_damage_sides()])
	_check(archer.get_attack_ability() == CombatUnit.Ability.FINESSE, "아군 궁수는 솜씨로 공격")
	_check(await actions.attack(archer, barbarian, true) and barbarian.is_stunned
		and actions.last_attack.rolls == [4] and actions.last_damage == 1 + archer.get_damage_bonus(),
		"충격 화살은 솜씨 4가 AC 4와 같으면 명중하고 추가 굴림 없이 기절")
	barbarian.is_stunned = false
	barbarian.cell = Vector2i(5, 4)
	ScriptedDice.arrange_turns(turns, units, [barbarian, warrior, archer])
	actions.replay_answers = [true]
	actions.dice = ScriptedDice.new([7, 7], [barbarian.get_ability_sides(strength), warrior.get_ability_sides(CombatUnit.Ability.AGILITY)])
	before = warrior.hit_points
	_check(await actions.attack(barbarian, warrior) and warrior.hit_points == before
		and actions.last_attack.total == 10 and warrior.parry_left == 1,
		"야만인 힘7+3이 전사 AC5에 명중, 흘려내기 민첩7+3이 공격10과 같으면 방어, 피해 주사위 없음")
	actions.logged.disconnect(observe)
	_check(actions.apply_status(barbarian, warrior, "poison"), "강도4 독 부여")
	actions.dice = ScriptedDice.new([4], [warrior.get_ability_sides(CombatUnit.Ability.HEALTH)])
	turns.end_turn()
	_check(warrior.get_status_count("poison") == 0 and warrior.hit_points == before,
		"턴 시작 건강d12의4로 독 강도4 제거 후 독 피해 없음")
	var boss: CombatUnit = _unit(CombatUnit.Kind.SCRAP_ROBOT_3000, false, Vector2i(4, 4))
	warrior.cell = Vector2i(4, 3)
	archer.cell = Vector2i(4, 5)
	units = [boss, warrior, archer]
	actions.initialize(units, turns)
	ScriptedDice.arrange_turns(turns, units, [boss, warrior, archer])
	actions.replay_answers = [false]
	actions.dice = ScriptedDice.new([8, 1, 2, 1, 3], [12, 20, 8, 6, 8])
	var warrior_before: int = warrior.hit_points
	var archer_before: int = archer.hit_points
	_check(await actions.spin(boss) and warrior.hit_points == warrior_before - 4
		and archer.hit_points == archer_before - 5 and actions.last_attack.total == 11,
		"실제 회전 베기는 공통 공격8+3과 두 대상의 방어를 비교하고 각각 피해")
	# 신호가 actions와 turns를 함께 붙잡지 않게 연결을 해제한다.
	turns.turn_started.disconnect(actions._on_turn_started)


func _test_spin_shared_modes() -> void:
	for reversed: bool in [false, true]:
		for stunned: int in [1, 2, 3]:
			var boss: CombatUnit = _unit(CombatUnit.Kind.SCRAP_ROBOT_3000, false, Vector2i(4, 4))
			var warrior: CombatUnit = _unit(CombatUnit.Kind.WARRIOR, true, Vector2i(4, 3))
			var archer: CombatUnit = _unit(CombatUnit.Kind.ARCHER, true, Vector2i(4, 5))
			var units: Array[CombatUnit] = [boss, warrior, archer]
			if reversed:
				units = [boss, archer, warrior]
			var turns: CombatTurns = CombatTurns.new()
			var actions: CombatActions = CombatActions.new()
			actions.initialize(units, turns)
			ScriptedDice.arrange_turns(turns, units, [boss])
			warrior.is_stunned = (stunned & 1) != 0
			archer.is_stunned = (stunned & 2) != 0
			warrior.parry_left = 0
			var advantaged: bool = stunned == 3
			var attack_sides: int = boss.get_ability_sides(CombatUnit.Ability.STRENGTH)
			var damage_sides: int = boss.get_damage_sides()
			var total: int = 8 + boss.get_attack_bonus()
			var damage: int = 1 + boss.get_damage_bonus()
			var ready: bool = (attack_sides >= 8 and damage_sides >= 1 and damage > 0
				and total > 1 + warrior.get_defense_bonus() and total > 1 + archer.get_defense_bonus()
				and warrior.hit_points > damage and archer.hit_points > damage)
			_check(ready, "실제 능력치·가산값에서 공통 공격8이 명중하고 피해1은 전투를 끝내지 않음")
			if not ready:
				turns.turn_started.disconnect(actions._on_turn_started)
				return
			var rolls: Array[int] = [8]
			var sides: Array[int] = [attack_sides]
			if advantaged:
				rolls.push_front(2)
				sides.push_front(attack_sides)
			var values: Array[int] = rolls.duplicate()
			values.append_array([1, 1, 1, 1])
			var defenders: Array[CombatUnit] = [warrior, archer]
			if reversed:
				defenders.reverse()
			# 소비 순서: 공통 힘(유리면2회) → 대상별 방어 힘 → 명중 피해.
			for defender: CombatUnit in defenders:
				sides.append_array([defender.get_ability_sides(CombatUnit.Ability.STRENGTH), damage_sides])
			actions.dice = ScriptedDice.new(values, sides)
			var attacks: Array[Dictionary] = []
			var observe: Callable = func(message: String) -> void:
				if " 방어:" in message:
					attacks.append({"rolls": actions.last_attack.rolls.duplicate(),
						"total": actions.last_attack.total, "mode": actions.last_attack.mode})
			actions.logged.connect(observe)
			_check(actions.can_use(boss, "spin") and (actions.dice as ScriptedDice).unused() == values,
				"혼합 조건도 사용 가능하며 사용 가능 확인은 난수를 쓰지 않음")
			_check(await actions.spin(boss), "확정된 혼합/전원 유리 광역 실행")
			var mode: CombatChecks.RollMode = CombatChecks.RollMode.ADVANTAGE if advantaged else CombatChecks.RollMode.NORMAL
			_check(attacks.size() == 2 and attacks.all(func(record: Dictionary) -> bool:
				return record.rolls == rolls and record.total == total and record.mode == mode),
				"정순·역순 모두 공통 값 하나: 혼합은 일반, 전원이 기절하면 유리")
			_check(warrior.hit_points == warrior.get_max_hit_points() - damage
				and archer.hit_points == archer.get_max_hit_points() - damage,
				"각 대상 방어·피해는 독립적으로 한 번씩 처리")
			_check(boss.action_left == 0 and boss.bonus_action_left == 1 and boss.reaction_left == 1
				and boss.movement_left == 4 and not actions.busy and actions.pending_reactor == null,
				"공통 광역은 행동 하나만 쓰고 반응·연출 잠금을 해제")
			_check((actions.dice as ScriptedDice).unused().is_empty(), "준비한 공통 공격·대상별 방어·피해를 정확히 소비")
			actions.logged.disconnect(observe)
			turns.turn_started.disconnect(actions._on_turn_started)


func _test_spin_disadvantage() -> void:
	var archer: CombatUnit = _unit(CombatUnit.Kind.ARCHER, true, Vector2i(4, 4))
	var first: CombatUnit = _unit(CombatUnit.Kind.WARRIOR, false, Vector2i(6, 4))
	var second: CombatUnit = _unit(CombatUnit.Kind.WARRIOR, false, Vector2i(7, 4))
	var nearby: CombatUnit = _unit(CombatUnit.Kind.WARRIOR, false, Vector2i(4, 5))
	var actions: CombatActions = CombatActions.new()
	actions.grid.units = [archer, first, second, nearby]
	for disadvantage: bool in [false, true]:
		nearby.is_stunned = not disadvantage
		for stunned: int in [0, 1, 3]:
			first.is_stunned = (stunned & 1) != 0
			second.is_stunned = (stunned & 2) != 0
			var mode: CombatChecks.RollMode = CombatChecks.RollMode.NORMAL
			if stunned == 3 and not disadvantage:
				mode = CombatChecks.RollMode.ADVANTAGE
			elif stunned != 3 and disadvantage:
				mode = CombatChecks.RollMode.DISADVANTAGE
			var targets: Array[CombatUnit] = [first, second]
			_check(actions._spin_mode(archer, targets) == mode,
				"공격자 공통 불리는 혼합 대상에서도 유지하고 전원 유리와는 상쇄")
			targets.reverse()
			_check(actions._spin_mode(archer, targets) == mode, "불리·상쇄도 대상 순서와 무관")
	var empty: Array[CombatUnit] = []
	_check(actions._spin_mode(archer, empty) == -1, "공통 공격 대상이 없으면 기존대로 사용 불가")


func _test_strength_validation() -> void:
	var source: CombatUnit = _unit(CombatUnit.Kind.WARRIOR, false, Vector2i(4, 4))
	var target: CombatUnit = _unit(CombatUnit.Kind.WARRIOR, true, Vector2i(4, 5))
	var units: Array[CombatUnit] = [source, target]
	target.status_effects.append(CombatUnit.StatusEffect.new("burn", source, 2, 0))
	var saved: Dictionary = target.save_state(units)
	_check(target.is_valid_state(saved, 2, Vector2i(10, 10)), "화상 강도0 저장 허용")
	saved.statuses[0][3] = 5
	_check(not target.is_valid_state(saved, 2, Vector2i(10, 10)), "복원 때 사라질 잘못된 화상 강도 거부")
	var actions: CombatActions = CombatActions.new()
	var turns: CombatTurns = CombatTurns.new()
	actions.initialize(units, turns)
	actions.create_ground(source, Vector2i(5, 4), "burn")
	saved = actions.save_state()
	_check(CombatActions.is_valid_state(saved, 2, Vector2i(10, 10)), "불 장판 강도0 저장 허용")
	saved.grounds[0][5] = 5
	_check(not CombatActions.is_valid_state(saved, 2, Vector2i(10, 10)), "불 장판의 잘못된 강도 거부")
	turns.turn_started.disconnect(actions._on_turn_started)


func _test_preview_conditions() -> void:
	var archer: CombatUnit = _unit(CombatUnit.Kind.ARCHER, true, Vector2i(4, 4))
	var target: CombatUnit = _unit(CombatUnit.Kind.ARCHER, false, Vector2i(7, 4))
	var nearby: CombatUnit = _unit(CombatUnit.Kind.WARRIOR, false, Vector2i(4, 5))
	var units: Array[CombatUnit] = [archer, target, nearby]
	var grid: CombatGrid = CombatGrid.new()
	grid.units = units
	var preview: CombatChecks.AttackPreview = grid.attack_preview(archer, target)
	_check(preview.in_range and preview.mode == CombatChecks.RollMode.DISADVANTAGE
		and is_equal_approx(preview.chance, 0.5625) and "옆에 적" in preview.reasons, "헥사 인접 적도 원거리 불리 (75% → 56.25%)")
	nearby.cell = Vector2i(5, 5)
	preview = grid.attack_preview(archer, target)
	_check(preview.mode == CombatChecks.RollMode.NORMAL, "사각 대각선의 헥사 거리2는 불리를 주지 않음")
	nearby.cell = Vector2i(4, 5)
	nearby.is_stunned = true
	preview = grid.attack_preview(archer, target)
	_check(preview.mode == CombatChecks.RollMode.NORMAL, "기절한 인접 적은 불리를 주지 않음")
	nearby.is_stunned = false
	nearby.hit_points = 0
	preview = grid.attack_preview(archer, target)
	_check(preview.mode == CombatChecks.RollMode.NORMAL, "전투 불능인 인접 적도 제외")
	nearby.hit_points = 12
	nearby.is_ally = true
	preview = grid.attack_preview(archer, target)
	_check(preview.mode == CombatChecks.RollMode.NORMAL, "인접한 아군은 불리 아님")
	target.is_stunned = true
	preview = grid.attack_preview(archer, target)
	_check(preview.mode == CombatChecks.RollMode.ADVANTAGE and is_equal_approx(preview.chance, 0.9375), "기절 대상은 유리 (75% → 93.75%)")
	nearby.is_ally = false
	preview = grid.attack_preview(archer, target)
	_check(preview.mode == CombatChecks.RollMode.NORMAL and is_equal_approx(preview.chance, 0.75)
		and preview.reasons.size() == 2, "솜씨 d20 대 풋내기 궁수 AC6은 75%, 기절 대상과 인접 적 하나씩이면 상쇄")
	archer.is_stunned = true
	preview = grid.attack_preview(archer, target)
	_check(preview.chance == 0.0 and not preview.blocked_reason.is_empty(), "기절한 공격자는 공격 불가")
	archer.is_stunned = false
	target.is_stunned = false
	nearby.cell = Vector2i(0, 0)
	target.cell = Vector2i(4, 10)
	preview = grid.attack_preview(archer, target)
	_check(preview.in_range, "궁수 사거리6 경계 포함")
	target.cell = Vector2i(4, 11)
	preview = grid.attack_preview(archer, target)
	_check(not preview.in_range and preview.chance == 0.0, "궁수 사거리7 밖이면0%")
	archer.kind = CombatUnit.Kind.WARRIOR
	target.cell = Vector2i(4, 5)
	preview = grid.attack_preview(archer, target)
	_check(preview.in_range and preview.mode == CombatChecks.RollMode.NORMAL, "근접은 헥사 인접1 가능, 옆 적 때문에 불리 없음")
	target.cell = Vector2i(5, 5)
	_check(not grid.attack_preview(archer, target).in_range, "근접은 헥사 거리2 공격 불가")
	target.cell = archer.cell
	_check(not grid.attack_preview(archer, target).in_range, "같은 칸은 공격 사거리가 아님")
	target.is_ally = true
	_check(not grid.attack_preview(archer, target).valid_target, "아군 공격 대상 거부")
	target.is_ally = false
	target.hit_points = 0
	_check(not grid.attack_preview(archer, target).valid_target, "전투 불능 대상 거부")
	_check(archer.get_ability_sides(CombatUnit.Ability.WILL) == 6, "전사 의지 d6")
	_check(target.get_ability_sides(CombatUnit.Ability.WILL) == 4, "풋내기 궁수 의지 d4")


## 기획서 7장: 몬스터 AC와 장비 없는 전사·궁수와의 명중률을 실제 미리보기로 확인한다.
func _test_monster_hit_table() -> void:
	var warrior: CombatUnit = _unit(CombatUnit.Kind.WARRIOR, true, Vector2i.ZERO)
	var archer: CombatUnit = _unit(CombatUnit.Kind.ARCHER, true, Vector2i.ZERO)
	_check(warrior.get_armor_class() == 5 and archer.get_armor_class() == 7, "장비 없는 전사 AC 5, 궁수 AC 7")
	for row: Array in [
		[CombatUnit.Kind.WARRIOR, 4, 85.0, 90.0, 70.0],
		[CombatUnit.Kind.ARCHER, 6, 75.0, 60.0, 40.0],
		[CombatUnit.Kind.SCRAP_ROBOT_1000, 5, 80.0, 91.7, 75.0],
		[CombatUnit.Kind.SCRAP_ROBOT_2000, 6, 75.0, 91.7, 75.0],
		[CombatUnit.Kind.SCRAP_ROBOT_3000, 7, 70.0, 91.7, 75.0],
		[CombatUnit.Kind.SPIDERLING, 5, 80.0, 75.0, 25.0],
		[CombatUnit.Kind.MOTHER_SPIDER, 5, 80.0, 87.5, 62.5],
	]:
		var monster: CombatUnit = _unit(row[0], false, Vector2i.ZERO)
		_check(monster.get_armor_class() == row[1], "%s AC %d" % [monster.get_display_name(), row[1]])
		for pair: Array in [[warrior, monster, row[2]], [archer, monster, row[2]],
				[monster, warrior, row[3]], [monster, archer, row[4]]]:
			var percent: float = _preview_percent(pair[0], pair[1])
			_check(absf(percent - pair[2]) < 0.05, "7장 명중률 %s → %s %.1f%% (실제 %.2f%%)" % [
				pair[0].get_display_name(), pair[1].get_display_name(), pair[2], percent])
	var barbarian: CombatUnit = _unit(CombatUnit.Kind.WARRIOR, false, Vector2i.ZERO)
	warrior.weapon = {"kind": "weapon", "stats": {"attack_bonus": 1}}
	warrior.armor = {"kind": "armor", "stats": {"defense_bonus": 1}}
	_check(warrior.get_armor_class() == 6 and is_equal_approx(_preview_percent(warrior, barbarian), 90.0)
		and is_equal_approx(_preview_percent(barbarian, warrior), 80.0),
		"장비 공격 가산 +1은 공격 굴림(85% → 90%), 방어 가산 +1은 AC(5 → 6, 90% → 80%)에 더함")
	warrior.weapon = {}
	warrior.armor = {}
	CombatEnemyDefinitions.NOVICE_BARBARIAN["armor_class"] = 9
	var overridden: CombatUnit = _unit(CombatUnit.Kind.WARRIOR, false, Vector2i.ZERO)
	_check(overridden.get_armor_class() == 9 and is_equal_approx(_preview_percent(warrior, overridden), 60.0),
		"몬스터 정의에 직접 지정한 AC가 민첩 표준값 + 방어 가산을 덮어씀")
	CombatEnemyDefinitions.NOVICE_BARBARIAN.erase("armor_class")


## 원거리 공격자는 인접 불리가 없게 세 칸 떨어뜨린다.
func _preview_percent(attacker: CombatUnit, target: CombatUnit) -> float:
	var grid: CombatGrid = CombatGrid.new()
	grid.units = [attacker, target]
	attacker.cell = Vector2i(4, 4)
	target.cell = Vector2i(4, 7 if attacker.is_ranged_attack() else 5)
	var preview: CombatChecks.AttackPreview = grid.attack_preview(attacker, target)
	return preview.chance * 100.0 if preview.in_range else -1.0


func _test_scene_input() -> void:
	var scene: PackedScene = load("res://scenes/combat/battle.tscn") as PackedScene
	var battle: Node2D = scene.instantiate() as Node2D
	battle.stages[0] = load("res://scenes/combat/stage.tres") as CombatStage
	root.add_child(battle)
	battle.set_process(false)
	battle.call("start_battle")
	await process_frame
	var turns: CombatTurns = battle.get("turns") as CombatTurns
	var units: Array[CombatUnit] = battle.get("units")
	# 확률·입력 fixture는 이전과 같은 거리에서 비교한다.
	units[0].cell = Vector2i(4, 9)
	units[1].cell = Vector2i(5, 9)
	var hud: CombatTurnHud = battle.get_node("UI/TurnHud") as CombatTurnHud
	ScriptedDice.arrange_turns(turns, units, [units[0], units[1], units[2], units[3]])
	var hp_before: int = units[2].hit_points
	var movement_before: int = units[0].movement_left
	var action_before: int = units[0].action_left
	await _click_unit(units[2])
	_check((battle.get("selection") as CombatSelection).preview_target == units[2], "실제 입력 경로로 적 도형 선택")
	_check(hud.unit_label.text == "풋내기 야만인" and "AC 4" in hud.resource_label.text, "클릭하면 적 HP/AC/상태 표시")
	_check("사거리 밖" in hud.preview_label.text and "0.0%" in hud.preview_label.text, "기본 배치의 사거리 밖 안내")
	await _click_unit(units[2])
	_check(units[2].hit_points == hp_before and units[0].movement_left == movement_before
		and units[0].action_left == action_before, "사거리 밖이면 두 번 눌러도 공격하거나 자원을 쓰지 않음")
	_check(units[0].is_selected and units[2].is_previewed, "조작 유닛과 미리보기 대상 표시 구분")
	# 왼쪽 설명 패널 밖의 실제 빈 영역을 누른다.
	await _click_point(Vector2(4, 120))
	_check((battle.get("selection") as CombatSelection).preview_target == null and hud.unit_label.text == "아군 전사",
		"빈 곳 클릭은 미리보기를 해제하고 현재 유닛을 표시")
	await _click_unit(units[2])
	turns.select_unit(units[1])
	_check((battle.get("selection") as CombatSelection).preview_target == null and hud.preview_label.text.is_empty()
		and hud.unit_label.text == "아군 궁수", "초상 전환 후 미리보기 해제")
	_check(battle.call("preview_enemy", units[3]), "새 조작 유닛으로 미리보기")
	var map: TileMapLayer = battle.get_node("Map") as TileMapLayer
	units[3].cell = Vector2i(5, 5)
	units[3].position = map.map_to_local(units[3].cell)
	(battle.get("selection") as CombatSelection).clear_preview()
	await _click_unit(units[3])
	_check("75.0%" in hud.preview_label.text and "AC 6" in hud.resource_label.text
		and "HP 14 / 14" in hud.resource_label.text, "사거리 안 대상의 명중률과 능력치 표시")
	units[3].is_stunned = true
	(battle.get("selection") as CombatSelection).clear_preview()
	await _click_unit(units[3])
	_check("93.8% · 유리" in hud.preview_label.text and "기절한 대상" in hud.preview_label.text,
		"기절 대상의 유리 확률과 이유 표시")
	units[2].cell = Vector2i(6, 9)
	units[2].position = map.map_to_local(units[2].cell)
	(battle.get("selection") as CombatSelection).clear_preview()
	await _click_unit(units[3])
	_check("75.0% · 유리/불리 상쇄" in hud.preview_label.text
		and "기절한 대상, 옆에 적" in hud.preview_label.text, "상쇄 확률과 양쪽 이유 표시")
	units[3].is_stunned = false
	(battle.get("selection") as CombatSelection).clear_preview()
	await _click_unit(units[3])
	_check("56.2% · 불리" in hud.preview_label.text and "옆에 적" in hud.preview_label.text,
		"인접 적에 따른 불리 확률과 이유 표시")
	hud.end_button.pressed.emit()
	_check((battle.get("selection") as CombatSelection).preview_target == null and hud.unit_label.text == "아군 전사", "턴 종료 후 미리보기 해제")
	await _click_unit(units[0])
	_check((battle.get("selection") as CombatSelection).preview_target == null, "아군 도형 클릭은 공격 미리보기 대상 아님")
	turns.end_turn()
	_check(not battle.call("preview_enemy", units[0]), "적 턴에는 아군 조작 미리보기 불가")
	battle.queue_free()
	await process_frame


func _test_scene_mixed_spin() -> void:
	var battle: Node2D = (load("res://scenes/combat/battle.tscn") as PackedScene).instantiate()
	battle.stages[0] = load("res://scenes/combat/stage.tres")
	root.add_child(battle)
	battle.set_process(false)
	battle.call("start_battle")
	await process_frame
	var units: Array[CombatUnit] = battle.get("units")
	var actions: CombatActions = battle.get("actions")
	var turns: CombatTurns = battle.get("turns")
	_check(units.size() == 4, "장면 fixture의 아군2·적2 구성")
	if units.size() != 4:
		battle.queue_free()
		await process_frame
		return
	var boss: CombatUnit = units[2]
	boss.kind = CombatUnit.Kind.SCRAP_ROBOT_3000
	boss.hit_points = boss.get_max_hit_points()
	boss.cell = Vector2i(4, 4)
	units[0].cell = Vector2i(4, 3)
	units[1].cell = Vector2i(4, 5)
	units[3].cell = Vector2i(9, 9)
	ScriptedDice.arrange_turns(turns, units, [boss])
	units[0].is_stunned = true
	units[0].parry_left = 0
	units[0].reaction_left = 0
	units[1].reaction_left = 0
	var attack_sides: int = boss.get_ability_sides(CombatUnit.Ability.STRENGTH)
	var damage_sides: int = boss.get_damage_sides()
	var damage: int = 1 + boss.get_damage_bonus()
	var ready: bool = (boss.action_left == 1 and actions.grid.opponents_in_area(boss, 1).size() == 2
		and attack_sides >= 8 and damage_sides >= 1 and damage > 0
		and 8 + boss.get_attack_bonus() > 1 + units[0].get_defense_bonus()
		and 8 + boss.get_attack_bonus() > 1 + units[1].get_defense_bonus()
		and units[0].hit_points > damage and units[1].hit_points > damage)
	_check(ready, "행동1개·인접 아군2명, 실제 능력치·가산값에서 명중·생존하는 통제 장면")
	if not ready:
		battle.queue_free()
		await process_frame
		return
	# 소비 순서: 공통 힘 → 전사 방어 힘·피해 → 궁수 방어 힘·피해.
	actions.dice = ScriptedDice.new([8, 1, 1, 1, 1], [attack_sides,
		units[0].get_ability_sides(CombatUnit.Ability.STRENGTH), damage_sides,
		units[1].get_ability_sides(CombatUnit.Ability.STRENGTH), damage_sides])
	var logs: Array[String] = []
	var observe: Callable = func(message: String) -> void: logs.append(message)
	actions.logged.connect(observe)
	await CombatEnemyAi.new().play_turn(boss, actions)
	_check(logs.filter(func(message: String) -> bool: return "회전회오리:" in message).size() == 1
		and logs.filter(func(message: String) -> bool: return message.begins_with("공통 공격:")).size() == 1,
		"실제 장면의 직접 AI 호출이 혼합 대상 회전회오리와 공통 공격을 한 번 실행")
	_check(units[0].hit_points == units[0].get_max_hit_points() - damage
		and units[1].hit_points == units[1].get_max_hit_points() - damage
		and actions.last_attack.rolls == [8] and actions.last_attack.mode == CombatChecks.RollMode.NORMAL,
		"실제 장면·연출에서도 혼합 대상은 같은 일반 공격으로 각각 피해")
	var hud: CombatTurnHud = battle.get_node("UI/TurnHud")
	_check(boss.action_left == 0 and not actions.busy and not hud.reaction_dialog.visible
		and actions.pending_reactor == null and not battle.has_node("Arrow"), "AI 실행 후 행동 소비·입력 잠금 해제")
	_check((actions.dice as ScriptedDice).unused().is_empty(), "실제 장면에서도 준비 난수를 정확히 소비")
	actions.logged.disconnect(observe)
	(battle.get_node("HitSound") as AudioStreamPlayer).stop()
	await create_timer(0.15).timeout
	battle.queue_free()
	await process_frame


func _click_unit(unit: CombatUnit) -> void:
	await _click_point(unit.get_global_transform_with_canvas() * Vector2(0, -10))


func _click_point(point: Vector2) -> void:
	var event: InputEventMouseButton = InputEventMouseButton.new()
	event.position = point
	event.global_position = event.position
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	Input.parse_input_event(event)
	await process_frame
	event.pressed = false
	Input.parse_input_event(event)
	await process_frame
