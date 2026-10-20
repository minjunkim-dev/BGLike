extends SceneTree
## AI 선택과 실제 장면 자동 진행·반응 대기·결과까지의 회귀 검사.

class Fixture extends RefCounted:
	var units: Array[CombatUnit] = []
	var turns: CombatTurns = CombatTurns.new()
	var actions: CombatActions = CombatActions.new()
	var logs: Array[String] = []

var checks: int = 0
var failures: int = 0
var fixtures: Array[Fixture] = []
var ai: CombatEnemyAi = CombatEnemyAi.new()
const ScriptedDice = preload("res://tests/scripted_dice.gd")


func _initialize() -> void:
	create_timer(90.0).timeout.connect(func() -> void:
		push_error("Combat AI: test timeout")
		quit(1)
	)
	_run.call_deferred()


func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)


func _fixture(archer: bool = false) -> Fixture:
	var f: Fixture = Fixture.new()
	fixtures.append(f)
	for index: int in range(4):
		var unit: CombatUnit = CombatUnit.new()
		unit.kind = CombatUnit.Kind.WARRIOR if index % 2 == 0 else CombatUnit.Kind.ARCHER
		unit.is_ally = index < 2
		unit.cell = [Vector2i(5, 4), Vector2i(8, 8), Vector2i(4, 4), Vector2i(0, 0)][index]
		unit.hit_points = unit.get_max_hit_points()
		f.units.append(unit)
	var dice: CombatDice = CombatDice.new()
	dice.seed = 33
	f.turns.start(f.units, dice)
	f.actions.initialize(f.units, f.turns)
	f.actions.logged.connect(func(message: String) -> void: f.logs.append(message))
	f.turns.end_turn()
	f.turns.end_turn()
	if archer:
		f.turns.end_turn()
	for index: int in range(2):
		f.units[index].reaction_left = 0
	f.actions.dice.seed = 8
	_check(f.turns.current_unit == f.units[3 if archer else 2], "AI fixture 현재 적")
	return f


func _run() -> void:
	await _test_scrap_robot()
	await _test_scrap_robot_pull_priority()
	await _test_scrap_robot_pull_movement_and_combo()
	await _test_scrap_robot_spin_combos()
	await _test_scrap_robot_spin_reevaluation()
	await _test_mother()
	await _test_spiderling()
	await _test_warrior()
	await _test_archer()
	await _test_reaction_pause()
	await _test_enemy_reactions()
	await _test_guards()
	await _test_scene()
	await _test_default_scene()
	for f: Fixture in fixtures:
		for connection: Dictionary in f.actions.logged.get_connections():
			f.actions.logged.disconnect(connection["callable"] as Callable)
		for connection: Dictionary in f.actions.reaction_requested.get_connections():
			f.actions.reaction_requested.disconnect(connection["callable"] as Callable)
		for unit: CombatUnit in f.units:
			unit.free()
	fixtures.clear()
	var dice_problems: Array[String] = ScriptedDice.finish()
	_check(dice_problems.is_empty(), "준비한 주사위 값을 요청대로 모두 굴림 " + str(dice_problems))
	print("Combat AI: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)


func _test_scrap_robot() -> void:
	var normal: Fixture = _fixture()
	var boss: CombatUnit = normal.units[2]
	boss.kind = CombatUnit.Kind.SCRAP_ROBOT_1000
	boss.hit_points = 40
	boss.begin_turn()
	normal.actions.dice = ScriptedDice.new([11, 8], [20, 8])
	await ai.play_turn(boss, normal.actions)
	_check(normal.units[0].hit_points == 2 and boss.action_left == 0
		and boss.bonus_action_left == 1 and boss.movement_left == 4,
		"일반 보스는 인접 아군에게 1d8+2 기본 공격 한 번")
	var overloaded: Fixture = _fixture()
	boss = overloaded.units[2]
	boss.kind = CombatUnit.Kind.SCRAP_ROBOT_1000
	boss.hit_points = 20
	boss.begin_turn()
	overloaded.units[0].hit_points = 3
	overloaded.units[1].cell = Vector2i(6, 4)
	overloaded.actions.dice = ScriptedDice.new([11, 1, 10, 8], [20, 8, 20, 8])
	await ai.play_turn(boss, overloaded.actions)
	_check(overloaded.units[0].hit_points == 0 and overloaded.units[1].hit_points == 4,
		"과부하 첫 행동으로 전투 불능 뒤 두 번째 행동 대상을 다시 선택")
	_check(boss.cell == Vector2i(5, 4) and boss.movement_left == 3
		and boss.action_left == 0 and boss.bonus_action_left == 1,
		"두 번째 행동에 인접 대상이 없으면 남은 이동으로 접근 후 공격")
	var distant: Fixture = _fixture()
	boss = distant.units[2]
	boss.kind = CombatUnit.Kind.SCRAP_ROBOT_1000
	boss.hit_points = 40
	boss.cell = Vector2i(8, 4)
	distant.units[0].cell = Vector2i(1, 4)
	distant.units[1].cell = Vector2i(0, 5)
	boss.begin_turn()
	distant.actions.dice = ScriptedDice.new([], [])
	await ai.play_turn(boss, distant.actions)
	_check(boss.movement_left == 0 and boss.action_left == 1
		and CombatGrid.distance(boss.cell, distant.units[0].cell) == 3,
		"사거리 밖의 보스는 가장 가까운 아군에게 4칸만 접근")


func _test_scrap_robot_pull_priority() -> void:
	for nearby: Vector2i in [Vector2i(3, 4), Vector2i(6, 4)]:
		var f: Fixture = _fixture()
		var boss: CombatUnit = f.units[2]
		boss.kind = CombatUnit.Kind.SCRAP_ROBOT_2000
		boss.hit_points = 45
		boss.begin_turn()
		f.units[0].cell = nearby
		f.units[1].cell = Vector2i(7, 4)
		f.actions.dice = ScriptedDice.new([12, 10], [20, 20])
		await ai.play_turn(boss, f.actions)
		_check(f.units[1].cell == Vector2i(5, 4) and f.units[0].cell == nearby
			and f.units[0].hit_points == 12 and f.units[1].hit_points == 14,
			"2000은 인접 아군 공격과 거리2 대상보다 거리3 대상 만능팔을 우선")
		_check(boss.action_left == 0 and boss.movement_left == 4,
			"사거리 안 만능팔에 이동과 추가 공격을 쓰지 않음")


func _test_scrap_robot_pull_movement_and_combo() -> void:
	var moving: Fixture = _fixture()
	var boss: CombatUnit = moving.units[2]
	boss.kind = CombatUnit.Kind.SCRAP_ROBOT_2000
	boss.hit_points = 45
	boss.begin_turn()
	moving.units[0].cell = Vector2i(3, 4)
	moving.units[0].reaction_left = 1
	moving.units[1].cell = Vector2i(9, 4)
	moving.actions.reaction_requested.connect(func(_kind: String, _prompt: String) -> void:
		moving.actions.resolve_reaction(true)
	)
	moving.actions.dice = ScriptedDice.new([12, 1, 12, 10], [20, 8, 20, 20])
	await ai.play_turn(boss, moving.actions)
	_check(boss.cell == Vector2i(6, 4) and boss.movement_left == 2
		and moving.units[1].cell == Vector2i(7, 4), "인접 아군이 있어도 이동해서 사거리3의 만능팔 실행")
	_check(boss.hit_points == 41 and moving.units[0].reaction_left == 0
		and moving.units[0].hit_points == 12, "만능팔을 위한 로봇 일반 이동은 아군 기회 공격을 받음")
	var combo: Fixture = _fixture()
	boss = combo.units[2]
	boss.kind = CombatUnit.Kind.SCRAP_ROBOT_2000
	boss.hit_points = 22
	boss.begin_turn()
	combo.units[0].cell = Vector2i(1, 1)
	combo.units[1].cell = Vector2i(7, 4)
	combo.actions.dice = ScriptedDice.new([12, 10, 10, 8], [20, 20, 20, 8])
	await ai.play_turn(boss, combo.actions)
	_check(combo.units[1].cell == Vector2i(5, 4) and combo.units[1].hit_points == 4
		and boss.action_left == 0, "과부하 첫 행동 만능팔 뒤 두 번째 행동으로 끌려온 아군 기본 공격")
	boss.begin_turn()
	combo.units[0].cell = Vector2i(9, 9)
	combo.actions.dice = ScriptedDice.new([10, 2], [20, 8])
	await ai.play_turn(boss, combo.actions)
	_check(combo.units[1].hit_points == 0 and combo.units[0].hit_points == 12
		and boss.pull_cooldown == 1, "만능팔 쉬는 턴에는 기본 공격과 접근을 수행")
	var unreachable: Fixture = _fixture()
	boss = unreachable.units[2]
	boss.kind = CombatUnit.Kind.SCRAP_ROBOT_2000
	boss.hit_points = 45
	boss.begin_turn()
	unreachable.units[0].cell = Vector2i(3, 4)
	unreachable.units[1].cell = Vector2i(9, 9)
	unreachable.actions.dice = ScriptedDice.new([12, 1], [20, 8])
	await ai.play_turn(boss, unreachable.actions)
	_check(boss.cell == Vector2i(4, 4) and boss.movement_left == 4
		and unreachable.units[0].hit_points == 9,
		"이번 턴 이동으로 만능팔 사거리에 못 들면 인접 아군을 기본 공격")


func _test_scrap_robot_spin_combos() -> void:
	var pull_basic: Fixture = _fixture()
	var boss: CombatUnit = pull_basic.units[2]
	boss.kind = CombatUnit.Kind.SCRAP_ROBOT_3000
	boss.hit_points = 25
	boss.begin_turn()
	pull_basic.units[0].cell = Vector2i(1, 1)
	pull_basic.units[1].cell = Vector2i(7, 4)
	pull_basic.actions.dice = ScriptedDice.new([12, 10, 10, 8], [20, 20, 20, 8])
	await ai.play_turn(boss, pull_basic.actions)
	_check(pull_basic.units[1].cell == Vector2i(5, 4) and pull_basic.units[1].hit_points == 4
		and boss.action_left == 0, "3000 비인접 과부하는 만능팔 뒤 끌려온 대상 기본 공격")
	var pull_spin: Fixture = _fixture()
	boss = pull_spin.units[2]
	boss.kind = CombatUnit.Kind.SCRAP_ROBOT_3000
	boss.hit_points = 25
	boss.begin_turn()
	pull_spin.units[0].cell = Vector2i(3, 4)
	pull_spin.units[1].cell = Vector2i(7, 4)
	pull_spin.actions.dice = ScriptedDice.new([12, 10, 11, 1, 10, 2], [20, 20, 20, 8, 20, 8])
	await ai.play_turn(boss, pull_spin.actions)
	_check(pull_spin.units[0].hit_points == 9 and pull_spin.units[1].hit_points == 10
		and pull_spin.units[1].cell == Vector2i(5, 4) and boss.action_left == 0,
		"3000 한 명 인접 과부하는 만능팔 뒤 두 명에게 회전회오리")
	var spin_twice: Fixture = _fixture()
	boss = spin_twice.units[2]
	boss.kind = CombatUnit.Kind.SCRAP_ROBOT_3000
	boss.hit_points = 25
	boss.begin_turn()
	spin_twice.units[0].cell = Vector2i(3, 4)
	spin_twice.units[1].cell = Vector2i(5, 4)
	spin_twice.actions.dice = ScriptedDice.new([11, 1, 10, 1, 11, 1, 10, 1], [20, 8, 20, 8, 20, 8, 20, 8])
	await ai.play_turn(boss, spin_twice.actions)
	_check(spin_twice.units[0].hit_points == 6 and spin_twice.units[1].hit_points == 8
		and boss.action_left == 0 and boss.pull_cooldown == 0,
		"3000 두 명 인접 과부하는 만능팔 대신 회전회오리 두 번")
	_check(spin_twice.logs.filter(func(line: String) -> bool: return "회전회오리:" in line).size() == 2
		and boss.cell == Vector2i(4, 4) and boss.movement_left == 4,
		"회전회오리 두 번에 이동과 만능팔 쉬는 턴을 쓰지 않음")


func _test_scrap_robot_spin_reevaluation() -> void:
	for survivors: int in [1, 0]:
		var f: Fixture = _fixture()
		var boss: CombatUnit = f.units[2]
		boss.kind = CombatUnit.Kind.SCRAP_ROBOT_3000
		boss.hit_points = 25
		boss.begin_turn()
		f.units[0].cell = Vector2i(3, 4)
		f.units[0].hit_points = 3
		f.units[1].cell = Vector2i(5, 4)
		f.units[1].hit_points = 14 if survivors == 1 else 3
		if survivors == 1:
			f.actions.dice = ScriptedDice.new([11, 1, 10, 1, 10, 1], [20, 8, 20, 8, 20, 8])
		else:
			f.actions.dice = ScriptedDice.new([11, 1, 10, 1], [20, 8, 20, 8])
		await ai.play_turn(boss, f.actions)
		_check(f.units[0].hit_points == 0 and f.units[1].hit_points == (8 if survivors == 1 else 0),
			"첫 회전회오리 전투 불능 후 살아 있는 대상을 기준으로 다음 행동 선택")
		_check(f.logs.filter(func(line: String) -> bool: return "회전회오리:" in line).size() == 1
			and boss.action_left == (0 if survivors == 1 else 1),
			"인접 한 명이면 기본 공격, 아군이 없으면 두 번째 행동을 중단")
		_check(f.actions.is_over() == (survivors == 0) and not f.actions.busy,
			"다중 대상 처리 후 전투 종료와 대기 상태를 갱신")


func _test_mother() -> void:
	var spawning: Fixture = _fixture()
	var mother: CombatUnit = spawning.units[2]
	mother.kind = CombatUnit.Kind.MOTHER_SPIDER
	mother.hit_points = 20
	mother.begin_turn()
	spawning.actions.dice = ScriptedDice.new([1], [3])
	await ai.play_turn(mother, spawning.actions)
	_check(spawning.units.size() == 5 and mother.cell == Vector2i(4, 4)
		and mother.movement_left == 4 and mother.action_left == 0
		and mother.bonus_action_left == 1 and spawning.units[0].hit_points == 12,
		"아군이 인접해도 빈 칸이 있는 엄마는 이동·공격 없이 새끼 낳기 우선")
	_check(spawning.turns.current_unit == mother
		and spawning.turns.is_turn_finished(spawning.units.back()), "새끼를 낳은 엄마 턴에 새끼가 끼어들지 않음")
	var blocked: Fixture = _fixture()
	mother = blocked.units[2]
	mother.kind = CombatUnit.Kind.MOTHER_SPIDER
	mother.hit_points = 20
	mother.cell = Vector2i.ZERO
	mother.begin_turn()
	blocked.actions.grid.map_size = Vector2i(2, 2)
	blocked.units[0].cell = Vector2i(1, 0)
	blocked.units[1].cell = Vector2i(0, 1)
	blocked.units[1].hit_points = 5
	blocked.units[3].cell = Vector2i(9, 9)
	blocked.actions.dice = ScriptedDice.new([10, 1], [20, 6])
	await ai.play_turn(mother, blocked.actions)
	_check(blocked.units.size() == 4 and blocked.units[1].hit_points == 2
		and blocked.units[0].hit_points == 12 and mother.action_left == 0,
		"빈 칸이 없는 엄마는 가장 가까운 대상 중 HP가 낮은 아군을 기본 공격")
	blocked.turns.end_turn()
	while blocked.turns.current_unit != mother:
		blocked.turns.end_turn()
	blocked.units[1].cell = Vector2i(1, 1)
	blocked.actions.dice = ScriptedDice.new([1], [1])
	await ai.play_turn(mother, blocked.actions)
	_check(blocked.units.size() == 5 and mother.movement_left == 4
		and blocked.units[0].hit_points == 12 and blocked.units[1].hit_points == 2,
		"다음 턴에 빈 칸이 생긴 엄마는 공격 대신 새끼 낳기로 복귀")
	var stunned: Fixture = _fixture()
	mother = stunned.units[2]
	mother.kind = CombatUnit.Kind.MOTHER_SPIDER
	mother.begin_turn()
	mother.is_stunned = true
	stunned.actions.dice = ScriptedDice.new([])
	await ai.play_turn(mother, stunned.actions)
	_check(stunned.units.size() == 4 and mother.action_left == 1 and stunned.logs.is_empty(),
		"기절한 엄마의 AI는 새끼 낳기·이동·공격을 실행하지 않음")


func _test_spiderling() -> void:
	var close: Fixture = _fixture()
	var spiderling: CombatUnit = close.units[2]
	spiderling.kind = CombatUnit.Kind.SPIDERLING
	spiderling.hit_points = 1
	close.actions.dice = ScriptedDice.new([12], [20])
	await ai.play_turn(spiderling, close.actions)
	_check(spiderling.cell == Vector2i(4, 4) and spiderling.movement_left == 6
		and spiderling.action_left == 0 and close.units[0].hit_points == 11,
		"인접한 새끼 거미는 후퇴 없이 기본 공격만 실행")
	var approach: Fixture = _fixture()
	spiderling = approach.units[2]
	spiderling.kind = CombatUnit.Kind.SPIDERLING
	spiderling.hit_points = 1
	spiderling.cell = Vector2i(0, 0)
	approach.units[0].cell = Vector2i(3, 3)
	approach.units[1].cell = Vector2i(9, 9)
	approach.units[1].hit_points = 1
	approach.actions.dice = ScriptedDice.new([12], [20])
	await ai.play_turn(spiderling, approach.actions)
	_check(CombatGrid.distance(spiderling.cell, approach.units[0].cell) == 1
		and spiderling.movement_left == 1 and approach.units[0].hit_points == 11,
		"새끼 거미는 낮은 HP의 먼 아군보다 가장 가까운 아군에 접근해 공격")
	var opportunity: Fixture = _fixture()
	spiderling = opportunity.units[2]
	spiderling.kind = CombatUnit.Kind.SPIDERLING
	spiderling.hit_points = 1
	opportunity.units[0].reaction_left = 1
	opportunity.actions.reaction_requested.connect(func(_kind: String, _prompt: String) -> void:
		opportunity.actions.resolve_reaction(true)
	)
	opportunity.actions.dice = ScriptedDice.new([20, 1, 1], [20, 8, 8])
	_check(await opportunity.actions.move_to(spiderling, Vector2i(3, 4))
		and spiderling.hit_points == 0 and spiderling.cell == Vector2i(4, 4)
		and spiderling.movement_left == 6 and opportunity.units[0].reaction_left == 0,
		"이동하는 새끼 거미는 아군 기회 공격을 받고 벗어나기 전에 전투 불능")
	var no_opportunity: Fixture = _fixture()
	no_opportunity.units[2].kind = CombatUnit.Kind.SPIDERLING
	no_opportunity.turns.end_turn()
	no_opportunity.turns.end_turn()
	no_opportunity.actions.dice = ScriptedDice.new([])
	_check(await no_opportunity.actions.move_to(no_opportunity.units[0], Vector2i(6, 4))
		and no_opportunity.units[0].hit_points == 12
		and no_opportunity.units[2].reaction_left == 1, "새끼 거미는 아군 이동에 기회 공격을 하지 않음")


func _test_warrior() -> void:
	var hurt: Fixture = _fixture()
	hurt.units[2].hit_points = 6
	await ai.play_turn(hurt.units[2], hurt.actions)
	_check(hurt.units[2].hit_points > 6 and hurt.units[2].second_wind_left == 0,
		"HP 절반에서 숨 고르기를 먼저 사용")
	_check("숨 고르기" in hurt.logs[0] and hurt.units[2].surge_left == 1,
		"회복은 공격보다 먼저이며 같은 턴 몰아치기 금지")
	_check(hurt.units[2].action_left == 0 and hurt.units[2].bonus_action_left == 0,
		"회복과 공격은 각 자원 하나씩 소비")
	var healthy: Fixture = _fixture()
	healthy.units[2].hit_points = 7
	healthy.units[0].hit_points = 100
	await ai.play_turn(healthy.units[2], healthy.actions)
	_check(healthy.units[2].second_wind_left == 1 and healthy.units[2].surge_left == 1,
		"절반 초과는 회복하지 않고 몰아치기도 사용하지 않음")
	_check(healthy.units[2].action_left == 0 and healthy.units[2].bonus_action_left == 1,
		"기본 공격 한 번은 행동만 소비")
	var approach: Fixture = _fixture()
	approach.units[2].cell = Vector2i(0, 0)
	approach.units[3].cell = Vector2i(9, 0)
	approach.units[0].cell = Vector2i(3, 3)
	approach.units[1].cell = Vector2i(9, 9)
	approach.units[1].hit_points = 1
	await ai.play_turn(approach.units[2], approach.actions)
	_check(CombatGrid.distance(approach.units[2].cell, approach.units[0].cell) == 1,
		"사거리 밖에서는 낮은 HP의 먼 대상보다 가장 가까운 대상에게 접근")
	_check(approach.units[2].movement_left == 1 and approach.units[2].action_left == 0,
		"평면 거리6에서5칸 접근 후 공격, 이동과 행동 별도 소비")
	var retarget: Fixture = _fixture()
	retarget.units[1].cell = Vector2i(4, 5)
	retarget.units[1].hit_points = 1
	retarget.actions.dice.seed = 2
	await ai.play_turn(retarget.units[2], retarget.actions)
	_check(retarget.units[1].hit_points == 0, "인접한 대상 중 낮은 HP부터 공격")
	_check(retarget.units[2].surge_left == 1 and retarget.units[2].action_left == 0
		and retarget.units[0].hit_points == 12,
		"첫 대상 탈락 뒤 두 번째 대상을 추가 공격하지 않음")
	var last: Fixture = _fixture()
	last.units[0].hit_points = 1
	last.actions.incapacitate(last.units[1])
	last.actions.dice.seed = 2
	await ai.play_turn(last.units[2], last.actions)
	_check(last.actions.is_over() and last.units[2].surge_left == 1,
		"마지막 아군 탈락 후 추가 스킬과 공격 중단")


func _test_archer() -> void:
	var ranged: Fixture = _fixture(true)
	ranged.units[3].cell = Vector2i(2, 2)
	ranged.units[0].cell = Vector2i(6, 2)
	ranged.units[1].cell = Vector2i(7, 2)
	ranged.units[1].hit_points = 5
	await ai.play_turn(ranged.units[3], ranged.actions)
	_check(ranged.units[3].mark_left == 1 and ranged.units[3].marked_target == null,
		"풋내기 궁수는 표식을 사용하지 않음")
	_check("공격" in ranged.logs[0] and ranged.units[3].shock_left == 1
		and not ranged.units[1].is_stunned, "풋내기 궁수는 충격 화살 없이 기본 공격")
	_check(ranged.units[3].movement_left == 6 and ranged.units[3].disengage_left == 2,
		"인접 위협이 없으면 불필요한 후퇴 없음")
	var retreat: Fixture = _fixture(true)
	retreat.units[3].cell = Vector2i(4, 4)
	retreat.units[2].cell = Vector2i(9, 0)
	retreat.units[0].reaction_left = 1
	var prompts: Array[int] = [0]
	retreat.actions.reaction_requested.connect(func(_kind: String, _prompt: String) -> void:
		prompts[0] += 1
		retreat.actions.resolve_reaction(false)
	)
	await ai.play_turn(retreat.units[3], retreat.actions)
	_check(retreat.units[3].disengage_left == 1 and retreat.units[3].disengaged,
		"인접 적이 있으면 물러서며 쏘기를 먼저 사용")
	_check(CombatGrid.distance(retreat.units[3].cell, retreat.units[0].cell) > 1
		and retreat.units[3].movement_left == 5, "인접 위협에서 벗어나는 최단 후퇴")
	_check(prompts[0] == 0 and retreat.units[0].reaction_left == 1,
		"물러서며 쏘기 이동은 아군 기회 공격을 일으키지 않음")
	_check(retreat.units[3].mark_left == 1 and retreat.units[3].shock_left == 1
		and retreat.units[3].action_left == 0,
		"후퇴 뒤 표식·충격 화살 없이 기본 공격")
	_check(retreat.actions.last_attack.mode == CombatChecks.RollMode.NORMAL,
		"후퇴 후 공격의 인접 불리 제거")
	var approach: Fixture = _fixture(true)
	approach.units[3].cell = Vector2i(0, 0)
	approach.units[0].cell = Vector2i(6, 6)
	approach.units[1].cell = Vector2i(9, 9)
	await ai.play_turn(approach.units[3], approach.actions)
	_check(approach.units[3].movement_left == 0 and approach.units[3].action_left == 0,
		"평면 거리12에서 사거리6까지6칸 이동 후 공격")
	var exhausted: Fixture = _fixture(true)
	exhausted.units[3].cell = Vector2i(2, 2)
	exhausted.units[3].mark_left = 0
	exhausted.units[3].shock_left = 0
	await ai.play_turn(exhausted.units[3], exhausted.actions)
	_check(exhausted.units[3].action_left == 0 and exhausted.units[3].bonus_action_left == 1,
		"횟수 소진 후 기본 공격만 실행하며 횟수 회복 없음")
	var edge: Fixture = _fixture(true)
	edge.actions.grid.map_size = Vector2i(2, 1)
	edge.units[3].cell = Vector2i(0, 0)
	edge.units[0].cell = Vector2i(1, 0)
	await ai.play_turn(edge.units[3], edge.actions)
	_check(edge.units[3].movement_left == 6 and edge.units[3].disengage_left == 2
		and edge.units[3].action_left == 0, "후퇴 칸이 없으면 헛이동·후퇴 스킬 없이 공격")
	_check(edge.actions.last_attack.mode == CombatChecks.RollMode.DISADVANTAGE,
		"후퇴할 수 없는 풋내기 궁수는 인접 위협의 불리 유지")


func _test_reaction_pause() -> void:
	var f: Fixture = _fixture(true)
	f.units[3].cell = Vector2i(4, 4)
	f.units[2].cell = Vector2i(9, 0)
	f.units[3].disengage_left = 0
	f.units[0].reaction_left = 1
	var prompts: Array[int] = [0]
	f.actions.reaction_requested.connect(func(kind: String, _prompt: String) -> void:
		prompts[0] += 1
		_check(kind == "opportunity" and f.actions.busy and f.units[3].action_left == 1,
			"후퇴 스킬 소진 시 아군 기회 공격 창에서 공격 전 대기")
		_resolve_later.call_deferred(f.actions)
	)
	await ai.play_turn(f.units[3], f.actions)
	_check(prompts[0] >= 1 and not f.actions.busy and f.units[3].action_left == 0,
		"반응 결정 후 AI 이동과 공격 재개")
	_check(f.units[0].reaction_left == 1, "기회 공격 넘기기는 반응 유지")
	var lethal: Fixture = _fixture(true)
	lethal.units[3].cell = Vector2i(4, 4)
	lethal.units[2].cell = Vector2i(9, 0)
	lethal.units[3].disengage_left = 0
	lethal.units[3].hit_points = 1
	lethal.units[0].reaction_left = 1
	lethal.actions.dice.seed = 2
	lethal.actions.reaction_requested.connect(func(_kind: String, _prompt: String) -> void:
		lethal.actions.resolve_reaction(true)
	)
	await ai.play_turn(lethal.units[3], lethal.actions)
	_check(lethal.units[3].hit_points == 0 and lethal.units[3].action_left == 1
		and lethal.units[3].shock_left == 1, "기회 공격으로 탈락한 AI는 후속 공격을 실행하지 않음")


func _resolve_later(actions: CombatActions) -> void:
	actions.resolve_reaction(false)


func _test_enemy_reactions() -> void:
	var f: Fixture = _fixture()
	f.turns.end_turn()
	f.turns.end_turn()
	var actor: CombatUnit = f.units[0]
	var reactor: CombatUnit = f.units[2]
	actor.parry_left = 0
	var prompts: Array[int] = [0]
	f.actions.reaction_requested.connect(func(_kind: String, _prompt: String) -> void:
		prompts[0] += 1
		f.actions.resolve_reaction(false)
	)
	f.actions.dice.seed = 2
	_check(await f.actions.move_to(actor, Vector2i(6, 4)), "적 전사 옆에서 아군 이동 실행")
	_check(reactor.reaction_left == 0 and prompts[0] == 0,
		"적 기회 공격은 확인 창 없이 반응을 자동 소비")
	actor.cell = Vector2i(5, 4)
	reactor.reaction_left = 1
	f.actions.dice.seed = 2
	_check(await f.actions.attack(actor, reactor), "적 전사에게 아군 공격 실행")
	_check(reactor.parry_left == 2 and reactor.reaction_left == 1 and prompts[0] == 0,
		"야만인은 흘려내기 반응을 하지 않음")


func _test_guards() -> void:
	var f: Fixture = _fixture()
	f.units[2].is_stunned = true
	await ai.play_turn(f.units[2], f.actions)
	_check(f.logs.is_empty() and f.units[2].action_left == 1, "기절 AI 실행 거부")
	f.units[2].is_stunned = false
	f.actions.busy = true
	await ai.play_turn(f.units[2], f.actions)
	_check(f.logs.is_empty(), "진행 중 동작이 있으면 중복 AI 실행 거부")
	f.actions.busy = false
	await ai.play_turn(f.units[0], f.actions)
	_check(f.logs.is_empty(), "아군은 AI가 조작하지 않음")
	f.turns.end_turn()
	await ai.play_turn(f.units[2], f.actions)
	_check(f.logs.is_empty(), "이전 현재 유닛은 다시 실행하지 않음")


func _test_scene() -> void:
	var main: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	(main.get_node("Battle") as Node2D).stages[0] = load("res://scenes/combat/stage.tres") as CombatStage
	var battle: Node2D = main.get_node("Battle") as Node2D
	root.add_child(main)
	battle.set_process(false)
	current_scene = main
	var units: Array[CombatUnit] = battle.get("units")
	var turns: CombatTurns = battle.get("turns") as CombatTurns
	var actions: CombatActions = battle.get("actions") as CombatActions
	var hud: CombatTurnHud = battle.get_node("UI/TurnHud") as CombatTurnHud
	var dice: CombatDice = CombatDice.new()
	dice.seed = 33
	turns.start(units, dice)
	var prompts: Array[int] = [0]
	actions.reaction_requested.connect(func(_kind: String, _prompt: String) -> void:
		prompts[0] += 1
		_check(hud.reaction_dialog.visible and hud.end_button.disabled, "실제 AI 반응 창과 종료 잠금")
		hud.reaction_dialog.get_cancel_button().pressed.emit()
	)
	units[0].cell = Vector2i(4, 4)
	units[1].cell = Vector2i(7, 4)
	units[2].cell = Vector2i(5, 4)
	units[3].cell = Vector2i(6, 4)
	units[3].disengage_left = 0
	actions.dice.seed = 2
	hud.end_button.pressed.emit()
	hud.end_button.pressed.emit()
	var first_enemy: CombatUnit = turns.current_unit
	_check(not first_enemy.is_ally and hud.end_button.disabled, "실제 적 묶음 자동 진입과 입력 잠금")
	hud.end_button.pressed.emit()
	_check(turns.current_unit == first_enemy, "신호를 직접 보내도 적 턴 종료 우회 불가")
	battle.set_process(true)
	var started: Array[CombatUnit] = []
	turns.changed.connect(func() -> void:
		if turns.current_unit != null and not turns.current_unit.is_ally and turns.current_unit not in started:
			started.append(turns.current_unit)
	)
	started.append(first_enemy)
	for frame: int in range(2400):
		if actions.is_over() or (turns.current_unit != null and turns.current_unit.is_ally):
			break
		await create_timer(0.01).timeout
	_check(started.size() == 2 and started[0] == units[2] and started[1] == units[3],
		"적 묶음은 이니셔티브 전사→궁수 순서로 실행")
	_check(actions.is_over() or turns.current_unit.is_ally, "AI 완료 후 사용자 턴으로 복귀")
	_check(prompts[0] > 0, "실제 AI 공격에서 아군 반응 확인 창 연결")
	# 아군 입력은 합법 동작 API로 자동화하고 적은 실제 프레임 루프로 진행한다.
	for step: int in range(10000):
		if actions.is_over():
			break
		var actor: CombatUnit = turns.current_unit
		if actor != null and actor.is_ally and not actions.busy:
			var target: CombatUnit = null
			for unit: CombatUnit in units:
				if actions.can_target(actor, unit, "attack"):
					target = unit
					break
			if target == null:
				var destination: Vector2i = ai.approach_cell(actor, actions)
				if destination != actor.cell:
					await actions.move_to(actor, destination)
				for unit: CombatUnit in units:
					if actions.can_target(actor, unit, "attack"):
						target = unit
						break
			if target != null:
				await actions.attack(actor, target)
			if not actions.is_over():
				hud.end_button.pressed.emit()
		await create_timer(0.01).timeout
	_check(actions.is_over() and hud.get_node("Result").visible, "실제 장면 처음부터 결과 화면까지 완료")
	_check(not battle.get("_enemy_turn_running") and not hud.restart_button.disabled,
		"전투 종료 후 추가 대기 없이 재시작 버튼 활성")
	_check(turns.round_number < 50, "유한 라운드 안에 전투 종료")
	while battle.get("_enemy_turn_running"):
		await create_timer(0.01).timeout
	var hp: Array[int] = []
	for unit: CombatUnit in units:
		hp.append(unit.hit_points)
	await create_timer(0.4).timeout
	for index: int in range(units.size()):
		_check(units[index].hit_points == hp[index], "결과 이후 AI 추가 동작 없음")
	# signal에 자신을 캡처한 fixture 람다가 남지 않게 해제한다.
	for connection: Dictionary in turns.changed.get_connections():
		turns.changed.disconnect(connection["callable"] as Callable)
	main.queue_free()
	await process_frame


func _test_default_scene() -> void:
	var main: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	var battle: Node2D = main.get_node("Battle") as Node2D
	root.add_child(main)
	battle.set_process(false)
	current_scene = main
	var units: Array[CombatUnit] = battle.get("units")
	var turns: CombatTurns = battle.get("turns") as CombatTurns
	var actions: CombatActions = battle.get("actions") as CombatActions
	var hud: CombatTurnHud = battle.get_node("UI/TurnHud") as CombatTurnHud
	for unit: CombatUnit in units:
		_check(unit.cell == unit.start_cell and unit.hit_points == unit.get_max_hit_points(),
			"기본 배치와 최대 HP에서 전투 시작")
	var dice: CombatDice = CombatDice.new()
	dice.seed = 33
	turns.start(units, dice)
	actions.dice.seed = 33
	actions.reaction_requested.connect(func(_kind: String, _prompt: String) -> void:
		hud.reaction_dialog.get_cancel_button().pressed.emit()
	)
	battle.set_process(true)
	for step: int in range(10000):
		if actions.is_over():
			break
		var actor: CombatUnit = turns.current_unit
		if actor != null and actor.is_ally and not actions.busy:
			var target: CombatUnit = null
			for unit: CombatUnit in units:
				if actions.can_target(actor, unit, "attack"):
					target = unit
					break
			if target == null:
				var destination: Vector2i = ai.approach_cell(actor, actions)
				if destination != actor.cell:
					await actions.move_to(actor, destination)
				for unit: CombatUnit in units:
					if actions.can_target(actor, unit, "attack"):
						target = unit
						break
			if target != null:
				await actions.attack(actor, target)
			if not actions.is_over():
				hud.end_button.pressed.emit()
		await create_timer(0.01).timeout
	_check(actions.is_over() and hud.get_node("Result").visible,
		"기본 10×10 배치에서 결과 화면까지 실제 자동 적 턴 진행")
	_check(not battle.get("_enemy_turn_running") and not hud.restart_button.disabled,
		"기본 배치 전투 종료 후 AI 대기와 재시작 잠금 해제")
	while battle.get("_enemy_turn_running"):
		await create_timer(0.01).timeout
	var sound: AudioStreamPlayer = battle.get_node("HitSound") as AudioStreamPlayer
	while sound.playing:
		await process_frame
	main.queue_free()
	await process_frame
