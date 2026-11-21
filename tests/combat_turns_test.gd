extends SceneTree
## 턴 계약과 실제 전투 장면의 버튼 연결을 Godot에서 검사한다.

const ScriptedDice = preload("res://tests/scripted_dice.gd")

var _failures: int = 0
var _checks: int = 0
var _created_units: Array[CombatUnit] = []


func _initialize() -> void:
	# GDScript 런타임 오류로 _run이 중단돼도 CI는 기다리다 성공하지 않는다.
	create_timer(30.0).timeout.connect(_on_timeout)
	_run.call_deferred()


func _on_timeout() -> void:
	push_error("Combat turns: test did not finish within 30 seconds")
	quit(1)


func _run() -> void:
	_test_initiative()
	_test_spawned_turn_insertion()
	_test_resources_and_groups()
	_test_refill_split()
	_test_reaction_across_sides()
	_test_movement_zero_restored_on_confirm()
	_test_overload_extra_action_boundary()
	_test_start_is_full()
	_test_available_actions()
	_test_removal()
	_test_deferred_stun()
	_test_deferred_start_removal()
	_test_boundary_prefix()
	_test_rounds()
	await _test_scene()
	for unit: CombatUnit in _created_units:
		unit.free()
	var dice_problems: Array[String] = ScriptedDice.finish()
	_check(dice_problems.is_empty(), "준비한 주사위 값을 요청대로 모두 굴림 " + str(dice_problems))
	print("Combat turns: %d checks, %d failures" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error(message)


func _make_units() -> Array[CombatUnit]:
	var units: Array[CombatUnit] = []
	for index: int in range(4):
		var unit: CombatUnit = CombatUnit.new()
		unit.kind = CombatUnit.Kind.WARRIOR if index % 2 == 0 else CombatUnit.Kind.ARCHER
		unit.is_ally = index < 2
		# 장면에 넣지 않은 유닛은 _ready()가 없으므로 전투 시작처럼 가득 채운다.
		unit.refill_turn_resources()
		units.append(unit)
		_created_units.append(unit)
	return units


func _ordered_fixture(units: Array[CombatUnit], order: Array[int]) -> CombatTurns:
	var desired: Array[CombatUnit] = []
	for index: int in order:
		desired.append(units[index])
	var turns: CombatTurns = CombatTurns.new()
	ScriptedDice.arrange_turns(turns, units, desired)
	_check(turns.ordered_units == desired, "정해진 이니셔티브 순서 fixture")
	return turns


func _test_initiative() -> void:
	var units: Array[CombatUnit] = _make_units()
	var turns: CombatTurns = CombatTurns.new()
	var dice: CombatDice = CombatDice.new()
	var saw_agility_tie: bool = false
	for seed_value: int in range(200):
		dice.seed = seed_value
		var expected_dice: CombatDice = CombatDice.new()
		expected_dice.seed = seed_value
		turns.start(units, dice)
		for unit: CombatUnit in units:
			var sides: int = unit.get_ability_sides(CombatUnit.Ability.AGILITY)
			_check(unit.initiative_roll == expected_dice.roll(sides)
				and unit.get_initiative() == unit.initiative_roll, "유닛마다 민첩 주사위 한 번, 가산 없는 원본 값")
			_check(unit.initiative_roll >= 1 and unit.initiative_roll <= sides, "민첩 주사위 면 범위")
		for index: int in range(3):
			var first: CombatUnit = turns.ordered_units[index]
			var next: CombatUnit = turns.ordered_units[index + 1]
			_check(first.get_initiative() >= next.get_initiative(), "이니셔티브 내림차순")
			if first.get_initiative() == next.get_initiative():
				_check(first.get_ability_sides(CombatUnit.Ability.AGILITY)
					>= next.get_ability_sides(CombatUnit.Ability.AGILITY), "동점: 민첩 주사위 면 수가 큰 쪽 우선")
				saw_agility_tie = true
	_check(saw_agility_tie, "동점의 면 수 규칙을 실제 주사위로 검증")
	units[2].kind = CombatUnit.Kind.SPIDERLING
	var another_ally: CombatUnit = CombatUnit.new()
	units.append(another_ally)
	_created_units.append(another_ally)
	turns.start(units, ScriptedDice.new([4, 4, 4, 4, 4], [8, 12, 8, 10, 8]))
	_check(turns.ordered_units == [units[1], units[3], units[0], another_ally, units[2]],
		"같은 굴림은 민첩 면 수, 아군, 같은 편의 배치 순으로 정렬")
	var empty: CombatTurns = CombatTurns.new()
	empty.start([], dice)
	_check(empty.current_unit == null and not empty.end_turn(), "빈 전투에서 턴 종료 불가")


func _test_spawned_turn_insertion() -> void:
	var units: Array[CombatUnit] = _make_units()
	units[2].kind = CombatUnit.Kind.MOTHER_SPIDER
	var turns: CombatTurns = _ordered_fixture(units, [0, 1, 2, 3])
	turns.end_turn()
	turns.end_turn()
	var first: CombatUnit = CombatUnit.new()
	first.kind = CombatUnit.Kind.SPIDERLING
	first.is_ally = false
	first.action_left = 0
	first.movement_left = 0
	_created_units.append(first)
	_check(turns.insert_before(first, units[2])
		and turns.ordered_units == [units[0], units[1], first, units[2], units[3]],
		"새로 생성한 새끼는 엄마 바로 앞에 삽입")
	_check(turns.current_unit == units[2] and turns.is_turn_finished(first)
		and turns.get_current_group() == [first, units[2], units[3]]
		and first.action_left == 0 and first.movement_left == 0,
		"삽입은 현재 엄마 턴을 보존하고 생성 라운드의 새끼를 대기시킴")
	_check(not turns.insert_before(first, units[2])
		and turns.ordered_units.size() == 5, "같은 새끼를 중복 삽입하지 않음")
	turns.end_turn()
	_check(turns.current_unit == units[3] and turns.round_number == 1,
		"생성 라운드에는 새끼를 건너뛰고 다음 적으로 진행")
	for step: int in range(3):
		turns.end_turn()
	_check(turns.round_number == 2 and turns.current_unit == first
		and first.action_left == 1 and first.movement_left == 8,
		"다음 라운드부터 새끼는 엄마 직전에 자기 자원으로 행동")
	turns.end_turn()
	var second: CombatUnit = CombatUnit.new()
	second.kind = CombatUnit.Kind.SPIDERLING
	second.is_ally = false
	_created_units.append(second)
	_check(turns.insert_before(second, units[2])
		and turns.ordered_units == [units[0], units[1], first, second, units[2], units[3]]
		and turns.is_turn_finished(first) and turns.is_turn_finished(second),
		"여러 새끼는 먼저 생성한 순서이며 새로 생성한 새끼는 그 라운드 대기")
	turns.remove_unit(units[2])
	_check(first in turns.ordered_units and second in turns.ordered_units
		and turns.current_unit == units[3], "엄마가 탈락해도 새끼의 순서와 생성 라운드 대기 유지")
	for step: int in range(3):
		turns.end_turn()
	_check(turns.current_unit == first and turns.round_number == 3, "엄마 탈락 뒤에도 오래된 새끼가 먼저 행동")
	turns.end_turn()
	_check(turns.current_unit == second, "엄마 탈락 뒤에도 새 새끼가 이어서 행동")


func _test_resources_and_groups() -> void:
	var units: Array[CombatUnit] = _make_units()
	var turns: CombatTurns = _ordered_fixture(units, [0, 1, 2, 3])
	_check(turns.get_turn_groups().size() == 2, "아군 둘과 적 둘은 두 묶음")
	_check(turns.get_current_group() == [units[0], units[1]], "아군 턴 묶음")
	_check(turns.current_unit == units[0], "가장 높은 이니셔티브부터 선택")
	_check(units[0].spend_movement(1) and units[0].spend_movement(1), "이동을 나누어 소비")
	_check(units[0].movement_left == 2, "나눈 이동 비용 합계")
	_check(not units[0].spend_movement(3), "남은 이동보다 큰 비용 거부")
	_check(not units[0].spend_movement(0) and not units[0].spend_movement(-1), "0과 음수 이동 거부")
	for resource: CombatUnit.TurnResource in CombatUnit.TurnResource.values():
		_check(units[0].spend_resource(resource), "각 자원을 한 번 소비")
		_check(not units[0].spend_resource(resource), "각 자원을 중복 소비할 수 없음")
	_check(turns.current_unit == units[0], "자원을 써도 자동 종료하지 않음")
	_check(turns.select_unit(units[1]), "같은 묶음의 아군으로 전환")
	_check(units[1].movement_left == 8 and units[1].action_left == 1, "다른 유닛 자원은 독립")
	_check(turns.select_unit(units[0]), "원래 유닛으로 복귀")
	_check(units[0].movement_left == 2 and units[0].action_left == 0
		and units[0].bonus_action_left == 0 and units[0].reaction_left == 0, "선택 전환으로 자원 회복 없음")
	_check(not turns.select_unit(units[2]), "다른 묶음 선택 거부")
	turns.select_unit(units[1])
	units[1].spend_movement(2)
	units[1].spend_resource(CombatUnit.TurnResource.ACTION)
	turns.end_turn()
	_check(turns.current_unit == units[0], "현재 유닛만 종료하고 남은 아군으로 전환")
	_check(turns.select_unit(units[1]) and not turns.is_turn_finished(units[1]),
		"묶음 확정 전에는 종료한 아군을 다시 골라 종료 해제")
	_check(units[1].movement_left == 6 and units[1].action_left == 0
		and units[1].bonus_action_left == 1 and units[1].reaction_left == 1,
		"턴 종료 취소로 이미 쓴 자원을 회복하지 않음")
	turns.end_turn()
	units[2].spend_resource(CombatUnit.TurnResource.REACTION)
	turns.end_turn()
	_check(turns.current_unit == units[2], "묶음 전원이 종료한 뒤 적으로 진행")
	_check(units[2].reaction_left == 0, "아군 턴에 쓴 적 반응은 적 묶음 시작에 회복하지 않음")
	for ally: CombatUnit in [units[0], units[1]]:
		_check(ally.movement_left == ally.get_movement() and ally.action_left == 1
			and ally.bonus_action_left == 1 and ally.reaction_left == 1,
			"묶음 확정 때 아군 전원이 자원 4종을 한꺼번에 회복")
	_check(not turns.select_unit(units[3]), "적 묶음은 임의 전환 없이 이니셔티브 순서")
	units[3].spend_movement(2)
	turns.end_turn()
	_check(turns.current_unit == units[3] and units[3].movement_left == 6, "적 내부 전환도 자원 회복 없음")
	_check(units[2].reaction_left == 0, "적 묶음 확정 전에는 적 반응을 회복하지 않음")
	turns.end_turn()
	_check(units[2].reaction_left == 1 and units[3].movement_left == units[3].get_movement(),
		"적 묶음 확정 때 적 전원이 회복")
	_check(turns.round_number == 2 and turns.current_unit == units[0], "한 라운드 후 원래 순서로 반복")
	_check(units[0].movement_left == CombatUnit.WARRIOR_MOVEMENT and units[0].action_left == 1
		and units[0].bonus_action_left == 1 and units[0].reaction_left == 1, "다음 자기 턴에 자원 4종 회복")


func _test_refill_split() -> void:
	var unit: CombatUnit = _make_units()[0]
	unit.spend_movement(2)
	for resource: CombatUnit.TurnResource in CombatUnit.TurnResource.values():
		unit.spend_resource(resource)
	unit.begin_turn()
	_check(unit.movement_left == 2 and unit.action_left == 0 and unit.bonus_action_left == 0
		and unit.reaction_left == 0, "턴 시작 처리는 자원을 채우지 않음")
	unit.refill_turn_resources()
	_check(unit.movement_left == unit.get_movement() and unit.action_left == unit.action_capacity
		and unit.bonus_action_left == unit.bonus_action_capacity
		and unit.reaction_left == unit.reaction_capacity, "묶음 확정 회복은 자원 4종을 채움")
	unit.moving_shot_spent = true
	unit.pull_cooldown = 2
	unit.refill_turn_resources()
	_check(unit.moving_shot_spent and unit.pull_cooldown == 2, "회복은 턴 시작 상태를 건드리지 않음")
	unit.begin_turn()
	_check(not unit.moving_shot_spent and unit.pull_cooldown == 1, "턴 시작 처리는 턴 시작 상태를 초기화")


func _test_reaction_across_sides() -> void:
	var units: Array[CombatUnit] = _make_units()
	var turns: CombatTurns = _ordered_fixture(units, [0, 1, 2, 3])
	units[0].spend_resource(CombatUnit.TurnResource.REACTION)
	turns.end_turn()
	_check(units[0].reaction_left == 0 and units[1].reaction_left == 1, "한 명의 턴 종료는 자원을 채우지 않음")
	turns.end_turn()
	_check(turns.current_unit == units[2] and units[0].reaction_left == 1,
		"자기 턴에 쓴 반응은 묶음 확정 때 회복해 적 턴에 다시 씀")
	_check(units[0].spend_resource(CombatUnit.TurnResource.REACTION), "적 턴에 회복한 반응 사용")
	turns.end_turn()
	turns.end_turn()
	_check(turns.round_number == 2 and turns.current_unit == units[0] and units[0].reaction_left == 0,
		"적 턴에 쓴 반응은 다음 자기 묶음 확정까지 회복하지 않음")
	_check(units[1].reaction_left == 1, "적 턴에 쓰지 않은 반응은 그대로")
	turns.end_turn()
	turns.end_turn()
	_check(turns.current_unit == units[2] and units[0].reaction_left == 1,
		"다음 자기 묶음 확정 뒤 반응 회복")


func _test_movement_zero_restored_on_confirm() -> void:
	var units: Array[CombatUnit] = _make_units()
	var turns: CombatTurns = _ordered_fixture(units, [0, 1, 2, 3])
	turns.end_turn()
	turns.end_turn()
	units[0].movement_left = 0
	turns.end_turn()
	turns.end_turn()
	_check(turns.current_unit == units[0] and units[0].movement_left == 0,
		"적 턴에 0이 된 이동력은 자기 묶음 시작에도 0")
	turns.end_turn()
	turns.end_turn()
	_check(units[0].movement_left == units[0].get_movement(), "0이 된 이동력은 자기 묶음 확정 때 복구")


func _test_overload_extra_action_boundary() -> void:
	var units: Array[CombatUnit] = _make_units()
	var boss: CombatUnit = units[2]
	boss.kind = CombatUnit.Kind.SCRAP_ROBOT_3000
	boss.refill_turn_resources()
	var turns: CombatTurns = _ordered_fixture(units, [0, 1, 2, 3])
	boss.overloaded = true
	_check(boss.action_left == 1, "켜지는 순간에는 행동을 더하지 않음")
	turns.end_turn()
	turns.end_turn()
	_check(turns.current_unit == boss and boss.action_left == 2, "아군 턴에 켜지면 바로 다음 보스 턴에 행동 2개")
	turns.end_turn()
	turns.end_turn()
	_check(turns.round_number == 2 and turns.current_unit == units[0] and boss.action_left == 1,
		"묶음 확정은 추가 행동을 없애고 기본 개수로 채움")
	turns.end_turn()
	turns.end_turn()
	_check(turns.current_unit == boss and boss.action_left == 2, "다음 보스 턴에도 시작에 행동 2개")
	units = _make_units()
	boss = units[2]
	boss.kind = CombatUnit.Kind.SCRAP_ROBOT_3000
	boss.refill_turn_resources()
	turns = _ordered_fixture(units, [0, 1, 2, 3])
	turns.end_turn()
	turns.end_turn()
	boss.overloaded = true
	_check(boss.action_left == 1, "보스 자기 턴 중에 켜져도 그 턴의 행동 수는 그대로")
	turns.end_turn()
	turns.end_turn()
	_check(turns.round_number == 2 and turns.current_unit == units[0] and boss.action_left == 1,
		"자기 턴 중에 켜지면 확정 때 기본 개수")
	turns.end_turn()
	turns.end_turn()
	_check(turns.current_unit == boss and boss.action_left == 2, "자기 턴 중에 켜지면 다음 자기 턴부터 행동 2개")


func _test_start_is_full() -> void:
	var units: Array[CombatUnit] = _make_units()
	var turns: CombatTurns = _ordered_fixture(units, [0, 1, 2, 3])
	for unit: CombatUnit in units:
		_check(unit.movement_left == unit.get_movement() and unit.action_left == 1
			and unit.bonus_action_left == 1 and unit.reaction_left == 1, "전투 시작 때 모든 유닛은 자원이 가득 참")
	for unit: CombatUnit in units:
		unit.spend_movement(1)
		unit.spend_resource(CombatUnit.TurnResource.ACTION)
		unit.spend_resource(CombatUnit.TurnResource.REACTION)
	for unit: CombatUnit in units:
		unit.begin_stage(false)
		_check(unit.movement_left == unit.get_movement() and unit.action_left == 1
			and unit.bonus_action_left == 1 and unit.reaction_left == 1, "스테이지 시작·재시작 때 자원이 가득 참")
	turns = _ordered_fixture(units, [0, 1, 2, 3])
	for unit: CombatUnit in units:
		_check(unit.movement_left == unit.get_movement() and unit.action_left == 1
			and unit.reaction_left == 1, "첫 묶음 시작은 가득 찬 자원을 바꾸지 않음")


func _test_available_actions() -> void:
	var unit: CombatUnit = _make_units()[1]
	_check(not unit.has_available_turn_action(false, false, false), "자원이 있어도 유효한 동작 대상 없으면 종료 강조")
	_check(unit.has_available_turn_action(true, false, false), "이동 목적지가 있으면 동작 가능")
	unit.spend_movement(8)
	_check(not unit.has_available_turn_action(true, false, false), "이동력 없으면 이동 동작 불가")
	_check(unit.has_available_turn_action(false, true, false), "행동 대상이 있으면 동작 가능")
	unit.spend_resource(CombatUnit.TurnResource.ACTION)
	_check(not unit.has_available_turn_action(false, true, false), "행동 자원 없으면 동작 불가")
	_check(unit.has_available_turn_action(false, false, true), "보조 행동도 종료 가능 여부에 포함")
	unit.spend_resource(CombatUnit.TurnResource.BONUS_ACTION)
	_check(not unit.has_available_turn_action(true, true, true) and unit.reaction_left == 1,
		"반응만 남으면 종료 강조")


func _test_removal() -> void:
	var units: Array[CombatUnit] = _make_units()
	var turns: CombatTurns = _ordered_fixture(units, [0, 1, 2, 3])
	units[1].spend_movement(2)
	turns.remove_unit(units[0])
	_check(turns.current_unit == units[1] and units[1].movement_left == 6, "현재 유닛 탈락: 자원을 유지하고 남은 아군 선택")
	turns.remove_unit(units[1])
	_check(turns.current_unit == units[2], "현재 묶음이 비면 다음 묶음")
	turns.remove_unit(units[3])
	_check(turns.current_unit == units[2], "앞으로 올 유닛 탈락은 현재 선택 유지")
	turns.remove_unit(units[2])
	_check(turns.current_unit == null and not turns.end_turn(), "전원 탈락 후 잘못된 인덱스 없이 종료")
	units = _make_units()
	turns = _ordered_fixture(units, [0, 2, 1, 3])
	_check(turns.get_turn_groups().size() == 4, "편이 번갈아 있으면 네 묶음")
	units[0].spend_movement(2)
	units[1].movement_left = 2
	units[1].action_left = 0
	turns.remove_unit(units[2])
	_check(turns.get_current_group() == [units[0], units[1]], "중간 적 탈락 후 연속한 아군 묶음 결합")
	_check(units[0].movement_left == 2 and units[1].movement_left == 2
		and units[1].action_left == 0, "결합만으로 새 유닛의 턴을 시작하지 않음")
	_check(turns.select_unit(units[1]) and turns.is_turn_started(units[1]) and units[1].movement_left == 2
		and units[1].action_left == 0, "새로 합류한 아군은 처음 조작해도 자원을 다시 채우지 않음")
	turns.select_unit(units[0])
	turns.end_turn()
	turns.end_turn()
	units[3].spend_movement(2)
	turns.remove_unit(units[0])
	_check(turns.current_unit == units[3] and units[3].movement_left == 6, "지나간 유닛 탈락은 현재 적 자원 유지")
	turns.remove_unit(units[3])
	_check(turns.round_number == 2 and turns.current_unit == units[1], "마지막 묶음 탈락 후 다음 라운드")
	units = _make_units()
	turns = _ordered_fixture(units, [0, 2, 1, 3])
	units[0].spend_resource(CombatUnit.TurnResource.ACTION)
	turns.end_turn()
	turns.end_turn()
	turns.remove_unit(units[2])
	_check(not turns.select_unit(units[0]) and turns.is_turn_finished(units[0])
		and turns.current_unit == units[1] and units[0].action_left == 1,
		"적 탈락으로 같은 묶음에 붙어도 이전에 확정한 턴 종료는 해제하지 않고 그때 채운 자원을 유지")


func _test_deferred_stun() -> void:
	var units: Array[CombatUnit] = _make_units()
	var third: CombatUnit = CombatUnit.new()
	third.is_ally = true
	units.append(third)
	_created_units.append(third)
	var turns: CombatTurns = _ordered_fixture(units, [0, 2, 1, 4, 3])
	var starts: Array[CombatUnit] = []
	turns.turn_started.connect(func(unit: CombatUnit) -> void: starts.append(unit))
	units[1].is_stunned = true
	units[1].action_left = 0
	turns.remove_unit(units[2])
	turns.end_turn()
	_check(turns.current_unit == third and units[1].is_stunned
		and units[1].action_left == 0 and units[1] not in starts,
		"새로 결합한 기절 유닛은 다른 조작 가능한 유닛보다 먼저 시작하지 않음")
	turns.end_turn()
	_check(turns.current_unit == units[3] and units[1].is_stunned
		and turns.is_turn_finished(units[1]) and units[1].action_left == 1
		and starts.count(units[1]) == 1,
		"다른 유닛 종료 뒤 기절 유닛의 턴 시작 효과를 한 번 처리하고 자동 진행")


func _test_deferred_start_removal() -> void:
	for stunned: bool in [false, true]:
		var units: Array[CombatUnit] = _make_units()
		var turns: CombatTurns = _ordered_fixture(units, [0, 2, 1, 3])
		units[1].is_stunned = stunned
		var knockout: Callable = func(unit: CombatUnit) -> void:
			if unit == units[1]:
				turns.remove_unit(unit)
		turns.turn_started.connect(knockout)
		turns.remove_unit(units[2])
		turns.end_turn()
		_check(turns.current_unit == units[3] and turns.round_number == 1
			and units[1] not in turns.ordered_units,
			"지연된 시작 효과에서 탈락해도 다음 적의 턴을 건너뛰지 않음: " + str(stunned))
		turns.turn_started.disconnect(knockout)


func _test_boundary_prefix() -> void:
	var units: Array[CombatUnit] = _make_units()
	var third: CombatUnit = CombatUnit.new()
	third.is_ally = true
	units.append(third)
	_created_units.append(third)
	var turns: CombatTurns = _ordered_fixture(units, [0, 1, 2, 3, 4])
	units[0].spend_movement(2)
	units[1].spend_movement(3)
	for i: int in range(4):
		turns.end_turn()
	_check(turns.get_current_group() == [third, units[0], units[1]]
		and turns.ordered_units == [units[2], units[3], third, units[0], units[1]],
		"앞 유닛이 여럿이면 묶음 단위로 뒤에 옮기고 기존 내부 순서 유지")
	_check(units[0].movement_left == CombatUnit.WARRIOR_MOVEMENT and units[1].movement_left == 8,
		"경계에 합류한 여러 유닛도 직전 확정 때 채운 자원 유지")
	var allies: Array[CombatUnit] = [units[0], units[1]]
	turns = _ordered_fixture(allies, [0, 1])
	turns.end_turn()
	turns.end_turn()
	_check(turns.round_number == 2 and turns.get_current_group() == [units[0], units[1]],
		"한 편만 남은 일반 묶음은 순서를 중복 연결하지 않고 라운드 반복")


func _test_rounds() -> void:
	var units: Array[CombatUnit] = _make_units()
	var turns: CombatTurns = _ordered_fixture(units, [0, 2, 1, 3])
	var initial_order: Array[CombatUnit] = turns.ordered_units.duplicate()
	for round_index: int in range(1, 11):
		for unit: CombatUnit in initial_order:
			_check(turns.current_unit == unit and turns.round_number == round_index, "매 라운드 각 유닛은 한 번씩 원래 순서")
			unit.spend_resource(CombatUnit.TurnResource.ACTION)
			turns.end_turn()
	_check(turns.ordered_units == initial_order, "라운드마다 이니셔티브를 다시 굴리지 않음")
	turns = _ordered_fixture(units, [0, 2, 3, 1])
	_check(turns.get_turn_groups().size() == 3 and turns.get_current_group() == [units[0]],
		"처음 차례는 기존 이니셔티브 순서로 시작")
	units[0].spend_movement(2)
	units[0].spend_resource(CombatUnit.TurnResource.ACTION)
	turns.end_turn()
	turns.end_turn()
	turns.end_turn()
	_check(turns.get_current_group() == [units[1], units[0]]
		and turns.ordered_units == [units[2], units[3], units[1], units[0]],
		"라운드 경계의 아군을 중복 없이 묶고 앞 초상을 묶음 뒤로 이동")
	_check(units[0].movement_left == CombatUnit.WARRIOR_MOVEMENT and units[0].action_left == 1,
		"경계에서 합류한 다음 턴 유닛은 직전 확정 때 채운 자원 유지")
	_check(not turns.is_turn_started(units[0]) and turns.select_unit(units[0])
		and turns.is_turn_started(units[0]) and units[0].action_left == 1,
		"경계 묶음의 새 턴은 첫 조작에 시작하되 자원은 다시 채우지 않음")
	units[0].spend_resource(CombatUnit.TurnResource.ACTION)
	turns.end_turn()
	turns.select_unit(units[0])
	_check(units[0].action_left == 0, "경계 유닛의 종료 취소도 턴을 중복 시작하지 않음")
	turns.end_turn()
	turns.end_turn()
	_check(turns.round_number == 2 and turns.current_unit == units[2], "새 순서의 시작에서 다음 라운드")
	turns.end_turn()
	turns.end_turn()
	_check(turns.get_current_group() == [units[1], units[0]]
		and units[0].action_left == 1 and units[1].action_left == 1,
		"다음 라운드에도 옮긴 순서와 일반 묶음의 동시 자원 회복 유지")


func _test_scene() -> void:
	var scene: PackedScene = load("res://scenes/combat/battle.tscn") as PackedScene
	var battle: Node2D = scene.instantiate() as Node2D
	battle.stages[0] = load("res://scenes/combat/stage.tres") as CombatStage
	root.add_child(battle)
	battle.set_process(false)
	var first: CombatUnit = (battle.get("party") as Array)[0]
	first.armor = {"kind": "armor", "stats": {"max_movement": 1}}  # 시작 전 정비 화면에서 바꾼 장비
	battle.call("start_battle")
	_check(first.movement_left == first.get_movement(), "전투 시작 때 바뀐 장비의 최대 이동으로 이동력을 채움")
	await process_frame
	var turns: CombatTurns = battle.get("turns") as CombatTurns
	var hud: CombatTurnHud = battle.get_node("UI/TurnHud") as CombatTurnHud
	var scene_units: Array[CombatUnit] = battle.get("units")
	ScriptedDice.arrange_turns(turns, scene_units, scene_units)
	_check(turns.get_current_group().size() == 2, "장면 확인용 아군 묶음")
	var panel: Node = hud.order_bar.get_child(0)
	var portraits: Node = panel.get_child(0)
	var archer_button: Button = portraits.get_child(1) as Button
	# 순서가 같은 채 데이터가 바뀌어도 계산식 툴팁을 갱신한다.
	scene_units[1].initiative_roll += 1
	hud.refresh(turns, false)
	_check(archer_button.text == "아군\n궁수", "같은 순서에서도 초상에 이니셔티브 숫자 없음")
	_check(archer_button.tooltip_text.ends_with(str(scene_units[1].get_initiative())), "같은 순서의 이니셔티브 툴팁 갱신")
	_check(not archer_button.disabled, "같은 묶음의 아군 초상 활성")
	archer_button.pressed.emit()
	_check(turns.current_unit == scene_units[1] and hud.unit_label.text == "아군 궁수",
		"초상 클릭 신호의 대상과 정보 표시가 일치")
	hud.end_button.pressed.emit()
	var current: CombatUnit = turns.current_unit
	archer_button.pressed.emit()
	_check(not archer_button.disabled and turns.current_unit == scene_units[1]
		and not turns.is_turn_finished(scene_units[1]) and hud.unit_label.text == "아군 궁수",
		"턴을 끝낸 초상을 누르면 조작을 전환하고 턴 종료 해제")
	hud.unit_selected.emit(current)
	var old_round: int = turns.round_number
	_check(hud.unit_label.text == current.get_display_name(), "장면 연결: 현재 유닛 표시")
	_check(current.is_selected, "장면 연결: 현재 유닛 선택 테두리")
	var style: StyleBoxTexture = hud.end_button.get_theme_stylebox("normal") as StyleBoxTexture
	_check(style.modulate_color == CombatTurnHud.DEFAULT_BUTTON_COLOR, "이동할 수 있으면 종료 강조 없음")
	# 전사의 성스러운 장막·전투의 함성과 빈 반달 휩쓸기(#436)는 대상 없이 쓰므로 행동·보조 행동과 함성 횟수도 비운다.
	current.movement_left = 0
	current.action_left = 0
	current.bonus_action_left = 0
	current.battle_cry_left = 0
	battle.call("_update_turn_ui")
	style = hud.end_button.get_theme_stylebox("normal") as StyleBoxTexture
	_check(style.modulate_color == CombatTurnHud.END_BUTTON_COLOR, "유효한 동작 없으면 버튼 색만 강조")
	await process_frame
	_check(turns.current_unit == current, "실행 가능한 동작이 없어도 자동 종료 없음")
	hud.end_button.pressed.emit()
	_check(turns.current_unit != current or turns.round_number != old_round, "턴 종료 버튼의 신호가 실제 모델에 연결됨")
	battle.queue_free()
	await process_frame
