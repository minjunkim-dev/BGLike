extends SceneTree
## 동작의 정상 흐름, 자원·횟수, 반응 중단과 실제 두 번 클릭 경로.

class Fixture extends RefCounted:
	var units: Array[CombatUnit] = []
	var turns: CombatTurns = CombatTurns.new()
	var actions: CombatActions = CombatActions.new()
	var hits: Array[bool] = []


const ScriptedDice = preload("res://tests/scripted_dice.gd")

var _checks: int = 0
var _failures: int = 0
var _created: Array[CombatUnit] = []
var _fixtures: Array[Fixture] = []


func _initialize() -> void:
	create_timer(30.0).timeout.connect(func() -> void:
		push_error("Combat actions: test timeout")
		quit(1)
	)
	_run.call_deferred()


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error(message)


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
	var dice: CombatDice = CombatDice.new()
	dice.seed = 33
	f.turns.start(f.units, dice)
	f.actions.initialize(f.units, f.turns)
	f.actions.hit_landed.connect(f.hits.append.bind(true))
	return f


func _dice_for(expected: Array[int], sides: Array[int]) -> ScriptedDice:
	return ScriptedDice.new(expected, sides)


func _run() -> void:
	_test_novice_stats()
	_test_scrap_robot_stats()
	_test_scrap_robot_overload()
	_test_scrap_robot_turn_damage()
	await _test_spiderling_stats_and_damage()
	_test_novice_uses()
	await _test_novice_damage()
	await _test_scrap_robot_stun_immunity()
	await _test_scrap_robot_opportunity()
	await _test_movement()
	await _test_hex_rules()
	await _test_attacks()
	await _test_archer_balance()
	_test_self_actions()
	_test_shove()
	await _test_mark_and_stun()
	await _test_reactions()
	await _test_own_turn_parry()
	await _test_scene_input()
	await _test_scene_shock()
	for f: Fixture in _fixtures:
		for connection: Dictionary in f.actions.reaction_requested.get_connections():
			f.actions.reaction_requested.disconnect(connection["callable"] as Callable)
	_fixtures.clear()
	for unit: CombatUnit in _created:
		unit.free()
	var dice_problems: Array[String] = ScriptedDice.finish()
	_check(dice_problems.is_empty(), "준비한 주사위 값을 요청대로 모두 굴림 " + str(dice_problems))
	print("Combat actions: %d checks, %d failures" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)


func _test_scrap_robot_stats() -> void:
	var boss: CombatUnit = _fixture().units[2]
	boss.kind = CombatUnit.Kind.SCRAP_ROBOT_1000
	for act: int in range(1, 4):
		boss.act_number = act
		boss.hit_points = boss.get_max_hit_points()
		boss.begin_turn()
		_check(boss.get_max_hit_points() == 40 and boss.get_armor_class() == 14
			and boss.get_attack_bonus() == 5 and boss.get_damage_bonus() == 2
			and boss.get_damage_sides() == 8 and boss.get_attack_range() == 1
			and boss.get_save_dc() == 13 and boss.movement_left == 4,
			"고철로봇-1000 전투 수치는 모든 막에서 고정")
		_check(boss.get_attribute(CombatUnit.Attribute.STRENGTH) == 3
			and boss.get_dexterity() == -1
			and boss.get_attribute(CombatUnit.Attribute.CONSTITUTION) == 3
			and boss.get_attribute(CombatUnit.Attribute.MENTAL) == 0,
			"고철로봇-1000 능력치")
	_check(boss.is_boss() and boss.get_display_name() == "고철로봇-1000"
		and CombatActionRules.belongs_to(boss, "opportunity")
		and not CombatActionRules.belongs_to(boss, "second_wind")
		and not CombatActionRules.belongs_to(boss, "surge"), "보스는 기본 공격과 기회 공격만 사용")


func _test_scrap_robot_overload() -> void:
	var boss: CombatUnit = _fixture().units[2]
	boss.kind = CombatUnit.Kind.SCRAP_ROBOT_1000
	boss.hit_points = 21
	boss.begin_turn()
	_check(boss.action_left == 1, "HP 21에서 과부하가 켜지지 않음")
	boss.hit_points = 20
	boss.begin_turn()
	_check(boss.action_left == 2, "HP 20에서 턴 행동 2개")
	boss.spend_resource(CombatUnit.TurnResource.ACTION)
	boss.hit_points = 19
	_check(boss.action_left == 1, "추가 피해로 과부하 행동을 중복 지급하지 않음")
	boss.hit_points = 40
	boss.begin_turn()
	_check(boss.action_left == 2, "회복해도 과부하가 전투 중 유지됨")


func _test_scrap_robot_turn_damage() -> void:
	var f: Fixture = _fixture()
	var boss: CombatUnit = f.units[2]
	boss.kind = CombatUnit.Kind.SCRAP_ROBOT_1000
	boss.hit_points = 20
	f.turns.start(f.units, _dice_for([19, 14, 2, 7], [20, 20, 20, 20]))
	f.turns.end_turn()
	f.turns.end_turn()
	_check(f.turns.current_unit == f.units[3] and boss.hit_points == 20,
		"같은 적 묶음에 들어가도 실제 보스 순서 전에는 자기 피해 없음")
	f.turns.end_turn()
	_check(f.turns.current_unit == boss and boss.hit_points == 18 and boss.action_left == 2,
		"보스 실제 턴 시작에 자기 피해 2와 행동 2개")
	f.turns.remove_unit(f.units[3])
	_check(boss.hit_points == 18, "묶음 재계산으로 자기 피해를 중복 적용하지 않음")
	f.turns.end_turn()
	f.turns.end_turn()
	f.turns.end_turn()
	_check(f.turns.current_unit == boss and boss.hit_points == 16,
		"다음 라운드 자기 턴에 다시 자기 피해 2")
	for remaining_enemy: bool in [false, true]:
		var dying: Fixture = _fixture()
		var doomed: CombatUnit = dying.units[2]
		doomed.kind = CombatUnit.Kind.SCRAP_ROBOT_1000
		doomed.hit_points = 2 if remaining_enemy else 1
		dying.units[1].marked_target = doomed
		if not remaining_enemy:
			dying.actions.incapacitate(dying.units[3])
		var living: Array[CombatUnit] = dying.units.duplicate()
		var rolls: Array[int] = [19, 14, 2, 7]
		var sides: Array[int] = [20, 20, 20, 20]
		if not remaining_enemy:
			living.erase(dying.units[3])
			rolls.pop_back()
			sides.pop_back()
		dying.turns.start(living, _dice_for(rolls, sides))
		dying.turns.end_turn()
		dying.turns.end_turn()
		if remaining_enemy:
			dying.turns.end_turn()
		_check(doomed.hit_points == 0 and doomed not in dying.turns.ordered_units
			and not doomed.visible and dying.units[1].marked_target == null,
			"자기 피해 HP 0은 즉시 전투 불능·턴 제거·표식 해제")
		_check(dying.actions.is_victory() == not remaining_enemy
			and dying.actions.is_over() == not remaining_enemy,
			"다른 살아 있는 적이 없을 때만 승리")
		_check(not dying.actions.can_use(doomed, "attack")
			and dying.turns.current_unit != doomed, "전투 불능 보스는 그 턴과 이후 턴에 행동 불가")


func _test_scrap_robot_stun_immunity() -> void:
	var f: Fixture = _fixture()
	var boss: CombatUnit = f.units[2]
	boss.kind = CombatUnit.Kind.SCRAP_ROBOT_1000
	boss.hit_points = 40
	boss.cell = Vector2i(6, 4)
	var archer: CombatUnit = f.units[1]
	f.turns.select_unit(archer)
	f.actions.dice = _dice_for([10, 3], [20, 6])
	_check(await f.actions.attack(archer, boss, true), "보스에게 충격 화살 공격 가능")
	_check(boss.hit_points == 36 and not boss.is_stunned and archer.shock_left == 0,
		"보스는 충격 화살 피해를 받지만 내성 굴림 없이 기절에 면역")


func _test_scrap_robot_opportunity() -> void:
	var f: Fixture = _fixture()
	var boss: CombatUnit = f.units[2]
	boss.kind = CombatUnit.Kind.SCRAP_ROBOT_1000
	boss.hit_points = 40
	f.units[0].parry_left = 0
	f.actions.dice = _dice_for([11, 8], [20, 8])
	_check(await f.actions.move_to(f.units[0], Vector2i(3, 5)), "보스 인접 칸에서 이동")
	_check(f.units[0].hit_points == 2 and boss.reaction_left == 0,
		"보스 기회 공격은 명중 +5·피해 1d8+2로 반응을 소비")


func _test_novice_stats() -> void:
	var f: Fixture = _fixture()
	for act: int in range(1, 4):
		for index: int in [2, 3]:
			var enemy: CombatUnit = f.units[index]
			enemy.act_number = act
			_check(enemy.get_max_hit_points() == (12 if index == 2 else 14)
				and enemy.get_armor_class() == (12 if index == 2 else 11)
				and enemy.get_attack_bonus() == 5 and enemy.get_damage_bonus() == 1,
				"풋내기 HP·AC·명중·피해는 모든 막에서 고정")
			_check(enemy.get_attribute(CombatUnit.Attribute.STRENGTH) == (3 if index == 2 else 0)
				and enemy.get_dexterity() == (1 if index == 2 else 3)
				and enemy.get_attribute(CombatUnit.Attribute.CONSTITUTION) == (2 if index == 2 else 1)
				and enemy.get_attribute(CombatUnit.Attribute.MENTAL) == (-2 if index == 2 else 0)
				and enemy.get_attack_range() == (1 if index == 2 else 6)
				and enemy.movement_left == 6, "풋내기 능력치·이동력·사거리")
	_check(CombatActionRules.belongs_to(f.units[2], "second_wind")
		and CombatActionRules.belongs_to(f.units[2], "opportunity")
		and not CombatActionRules.belongs_to(f.units[2], "parry")
		and not CombatActionRules.belongs_to(f.units[2], "surge"), "야만인은 숨 고르기와 기회 공격만 사용")
	_check(CombatActionRules.belongs_to(f.units[3], "disengage")
		and not CombatActionRules.belongs_to(f.units[3], "opportunity")
		and not CombatActionRules.belongs_to(f.units[3], "mark")
		and not CombatActionRules.belongs_to(f.units[3], "shock"), "풋내기 궁수는 물러서며 쏘기만 사용")
	_check(f.units[0].get_armor_class() == 16 and f.units[0].get_damage_bonus() == 3
		and f.units[0].get_attribute(CombatUnit.Attribute.MENTAL) == -1
		and f.units[1].get_armor_class() == 14 and f.units[1].get_damage_bonus() == 1
		and f.units[1].get_attribute(CombatUnit.Attribute.MENTAL) == 1,
		"아군 전사·궁수의 기존 수치 보존")


func _test_novice_damage() -> void:
	for index: int in [2, 3]:
		for critical: bool in [false, true]:
			var f: Fixture = _fixture()
			var actor: CombatUnit = f.units[index]
			var target: CombatUnit = f.units[0]
			f.turns.end_turn()
			f.turns.end_turn()
			if index == 3:
				f.turns.end_turn()
			target.reaction_left = 0
			f.actions.dice = (_dice_for([20, 4, 2], [20, 4, 4]) if critical
				else _dice_for([11, 4], [20, 4]))
			_check(await f.actions.attack(actor, target), "풋내기 기본 공격 실행")
			_check(f.actions.last_damage == (7 if critical else 5)
				and target.hit_points == (5 if critical else 7),
				"풋내기 피해는 일반1d4+1·치명타2d4+1")


func _test_spiderling_stats_and_damage() -> void:
	for critical: bool in [false, true]:
		var f: Fixture = _fixture()
		var spiderling: CombatUnit = f.units[2]
		spiderling.kind = CombatUnit.Kind.SPIDERLING
		for act: int in range(1, 4):
			spiderling.act_number = act
			_check(spiderling.get_max_hit_points() == 1 and spiderling.get_armor_class() == 6
				and spiderling.get_attack_bonus() == 4 and spiderling.get_damage_bonus() == 1
				and spiderling.get_damage_sides() == 0 and spiderling.get_attack_range() == 1
				and spiderling.get_save_dc() == 10, "새끼 거미의 HP·방어·공격은 모든 막에서 고정")
			_check(spiderling.get_attribute(CombatUnit.Attribute.STRENGTH) == 0
				and spiderling.get_dexterity() == 2
				and spiderling.get_attribute(CombatUnit.Attribute.CONSTITUTION) == -2
				and spiderling.get_attribute(CombatUnit.Attribute.MENTAL) == -2
				and spiderling.movement_left == 6, "새끼 거미의 능력치·이동력")
		for action: String in CombatActionRules.NAMES:
			_check(CombatActionRules.belongs_to(spiderling, action) == (action == "attack"),
				"새끼 거미는 스킬·기회 공격 없이 기본 공격만 사용: " + action)
		f.turns.end_turn()
		f.turns.end_turn()
		f.units[0].reaction_left = 0
		f.actions.dice = _dice_for([20 if critical else 12], [20])
		_check(await f.actions.attack(spiderling, f.units[0]), "새끼 거미 기본 공격 실행")
		_check(f.actions.last_damage == 1 and f.units[0].hit_points == 11
			and f.actions.last_damage_rolls.is_empty(), "새끼 거미는 치명타도 피해1이며 피해 주사위를 굴리지 않음")


func _test_novice_uses() -> void:
	var f: Fixture = _fixture()
	f.turns.end_turn()
	f.turns.end_turn()
	var barbarian: CombatUnit = f.units[2]
	barbarian.hit_points = 6
	f.actions.dice = _dice_for([10], [10])
	_check(f.actions.use_self(barbarian, "second_wind") and barbarian.hit_points == 12
		and barbarian.bonus_action_left == 0 and barbarian.second_wind_left == 0,
		"야만인 숨 고르기는1d10+1 회복을 최대 HP에 제한하고 보조 행동·횟수 소비")
	barbarian.begin_turn()
	barbarian.hit_points = 6
	_check(not f.actions.can_use(barbarian, "second_wind"), "야만인은 다음 턴에도 숨 고르기 재사용 불가")
	f.turns.end_turn()
	var archer: CombatUnit = f.units[3]
	for use: int in range(2):
		archer.begin_turn()
		_check(f.actions.use_self(archer, "disengage") and archer.disengage_left == 1 - use
			and archer.bonus_action_left == 0 and archer.action_left == 1
			and archer.movement_left == 6 and f.actions.last_attack == null,
			"풋내기 궁수 물러서며 쏘기는2회이며 공격·이동을 실행하지 않음")
	archer.begin_turn()
	_check(not archer.disengaged and not f.actions.can_use(archer, "disengage"),
		"궁수는 다음 턴에 면제를 해제하고 소진한2회를 회복하지 않음")


func _test_movement() -> void:
	var f: Fixture = _fixture()
	for action: String in CombatActionRules.USE_COUNTERS:
		_check(CombatActionRules.USE_COUNTERS[action] in f.units[0],
			"동작 횟수 필드가 유닛에 있음: " + action)
	f.units[2].cell = Vector2i(9, 0)
	var actor: CombatUnit = f.units[0]
	_check(not f.actions.can_move(actor, actor.cell), "같은 칸 이동 거부")
	_check(not f.actions.can_move(actor, Vector2i(-1, 4)), "맵 밖 이동 거부")
	_check(not f.actions.can_move(actor, f.units[2].cell), "점유 칸 이동 거부")
	var reachable: Dictionary[Vector2i, int] = f.actions.reachable_cells(actor)
	var costs_match: bool = not reachable.is_empty()
	for cell: Vector2i in reachable:
		costs_match = costs_match and reachable[cell] == f.actions.path_to(actor, cell).size() \
			and reachable[cell] <= actor.movement_left
	_check(costs_match and not reachable.has(actor.cell) and not reachable.has(f.units[2].cell),
		"도달 칸 비용은 최단 경로 길이이고 남은 이동 안")
	var all_listed: bool = true
	for x: int in range(f.actions.map_size.x):
		for y: int in range(f.actions.map_size.y):
			var path: Array[Vector2i] = f.actions.path_to(actor, Vector2i(x, y))
			if not path.is_empty() and path.size() <= actor.movement_left:
				all_listed = all_listed and reachable.has(Vector2i(x, y))
	_check(all_listed, "남은 이동 안의 경로가 있는 칸은 모두 도달 칸")
	_check(CombatHexGrid.distance(Vector2i(4, 4), Vector2i(5, 5)) == 2,
		"짝수 행 오른쪽 아래 대각선은 헥사 거리2")
	_check(CombatHexGrid.distance(Vector2i(4, 5), Vector2i(5, 6)) == 1,
		"홀수 행 오른쪽 아래 대각선은 헥사 인접")
	_check(f.actions.path_to(actor, Vector2i(5, 5)).size() == 2,
		"사각 격자 대각선으로 헥사 경로를 단축하지 않음")
	_check(f.actions.path_to(actor, Vector2i(4, 6)).size() == 2, "6방향 이동 경로와 비용")
	_check(await f.actions.move_to(actor, Vector2i(4, 6)), "첫 이동 실행")
	_check(actor.cell == Vector2i(4, 6) and actor.movement_left == 4, "이동2 소비와 위치 갱신")
	_check(await f.actions.move_to(actor, Vector2i(4, 7)), "이동을 나눠서 실행")
	_check(actor.movement_left == 3 and actor.action_left == 1 and actor.bonus_action_left == 1,
		"나눈 이동은 누적 비용만 쓰며 행동 자원은 유지")
	_check(not f.actions.can_move(actor, Vector2i(0, 0)), "남은 이동을 넘는 경로 거부")
	f.units[1].cell = Vector2i(2, 2)
	_check(f.actions.path_to(actor, Vector2i(2, 2)).is_empty(), "아군 점유 칸도 거부")
	actor.is_stunned = true
	_check(not f.actions.can_move(actor, Vector2i(4, 8)), "기절한 유닛 이동 거부")
	actor.is_stunned = false
	f.turns.select_unit(f.units[1])
	_check(not f.actions.can_move(actor, Vector2i(4, 8)), "현재 유닛이 아닌 이동 거부")


func _test_hex_rules() -> void:
	# 좌표 기대값은 pointy-top 홀수 행 오프셋의 두 행에서 직접 정한다.
	var adjacent_rows: Array[Array] = [
		[Vector2i(5, 4), Vector2i(4, 5), Vector2i(3, 5), Vector2i(3, 4), Vector2i(3, 3), Vector2i(4, 3)],
		[Vector2i(5, 5), Vector2i(5, 6), Vector2i(4, 6), Vector2i(3, 5), Vector2i(4, 4), Vector2i(5, 4)]
	]
	var pushed_rows: Array[Array] = [
		[Vector2i(6, 4), Vector2i(5, 6), Vector2i(3, 6), Vector2i(2, 4), Vector2i(3, 2), Vector2i(5, 2)],
		[Vector2i(6, 5), Vector2i(5, 7), Vector2i(3, 7), Vector2i(2, 5), Vector2i(3, 3), Vector2i(5, 3)]
	]
	for row: int in range(2):
		var f: Fixture = _fixture()
		var actor: CombatUnit = f.units[0]
		var target: CombatUnit = f.units[2]
		actor.cell = Vector2i(4, 4 + row)
		f.units[1].cell = Vector2i(0, 9)
		f.units[3].cell = Vector2i(9, 9)
		for index: int in range(6):
			var neighbor: Vector2i = adjacent_rows[row][index]
			var pushed: Vector2i = pushed_rows[row][index]
			target.cell = Vector2i(9, 0)
			_check(f.actions.path_to(actor, neighbor).size() == 1,
				"두 행의6방향 이웃은 이동 비용1")
			target.cell = neighbor
			_check(f.actions.can_target(actor, target, "attack"), "6방향 근접 공격 가능")
			actor.kind = CombatUnit.Kind.ARCHER
			_check(CombatChecks.attack_preview(actor, target, f.units).mode == CombatChecks.RollMode.DISADVANTAGE,
				"6방향 적은 원거리 불리")
			actor.kind = CombatUnit.Kind.WARRIOR
			_check(f.actions.shove_destination(actor, target) == pushed, "행이 바뀌어도 같은 헥사 방향으로 밀치기")
			f.units[3].cell = pushed
			_check(not f.actions.can_target(actor, target, "shove"), "밀려날 칸 점유 시 선택 불가")
			f.units[3].cell = Vector2i(9, 9)
			target.is_stunned = true
			actor.bonus_action_left = 1
			_check(f.actions.shove(actor, target) and target.cell == pushed, "6방향 밀치기 실제 위치 일치")
			actor.bonus_action_left = 1
			target.is_stunned = false
			var opportunity: Fixture = _fixture()
			_enemy_archer(opportunity)
			opportunity.units[0].cell = actor.cell
			opportunity.units[1].cell = Vector2i(0, 9)
			opportunity.units[2].cell = Vector2i(9, 0)
			opportunity.units[3].cell = neighbor
			var prompts: Array[int] = [0]
			opportunity.actions.reaction_requested.connect(func(kind: String, _prompt: String) -> void:
				if kind == "opportunity":
					prompts[0] += 1
				opportunity.actions.resolve_reaction(false)
			)
			await opportunity.actions.move_to(opportunity.units[3], pushed)
			_check(prompts[0] == 1, "6방향 인접을 벗어나면 기회 공격")
	var edge: Fixture = _fixture()
	edge.units[0].cell = Vector2i(0, 1)
	edge.units[2].cell = Vector2i(0, 0)
	_check(not edge.actions.can_target(edge.units[0], edge.units[2], "shove"), "밀려날 칸이 맵 밖이면 선택 불가")
	var ranged: Fixture = _fixture()
	ranged.units[0].kind = CombatUnit.Kind.ARCHER
	ranged.units[0].cell = Vector2i(0, 0)
	ranged.units[2].cell = Vector2i(4, 4)
	_check(ranged.actions.can_target(ranged.units[0], ranged.units[2], "attack"), "헥사 거리6 공격 가능")
	ranged.units[2].cell = Vector2i(5, 4)
	_check(not ranged.actions.can_target(ranged.units[0], ranged.units[2], "attack"), "헥사 거리7 공격 불가")
	_check(ranged.actions.path_to(ranged.units[0], Vector2i(4, 4)).size() == 6
		and ranged.actions.can_move(ranged.units[0], Vector2i(4, 4))
		and not ranged.actions.can_move(ranged.units[0], Vector2i(5, 4)), "이동력6 경계도 헥사 최단 경로 기준")


func _test_attacks() -> void:
	var f: Fixture = _fixture()
	var actor: CombatUnit = f.units[0]
	var target: CombatUnit = f.units[2]
	target.parry_left = 0
	f.actions.dice = _dice_for([1], [20])
	_check(await f.actions.attack(actor, target), "빗나간 공격도 실행 성공")
	_check(actor.action_left == 0 and target.hit_points == 12 and f.actions.last_damage == 0,
		"자연1 공격은 행동을 소비하고 피해 없음")
	_check(f.hits.is_empty(), "빗나감은 타격음을 요청하지 않음")
	_check(not await f.actions.attack(actor, target), "행동 없는 재공격 거부")
	actor.action_left = 1
	f.actions.dice = _dice_for([20], [20]).then_seeded()
	_check(await f.actions.attack(actor, target), "치명타 공격")
	_check(f.actions.last_attack.critical and f.actions.last_damage_rolls.size() == 2,
		"치명타는 무기 주사위 두 개")
	var total: int = 3
	for rolled: int in f.actions.last_damage_rolls:
		total += rolled
	_check(f.actions.last_damage == total, "능력치3은 치명타에서도 한 번만 더함")
	_check(target.hit_points == maxi(0, 12 - total), "피해와 HP0 하한")
	_check(f.hits.size() == 1, "치명타 주사위가 여러 개여도 타격음은 한 번")
	var killed: Fixture = _fixture()
	killed.units[2].hit_points = 1
	killed.units[2].parry_left = 0
	killed.units[1].marked_target = killed.units[2]
	killed.actions.dice = _dice_for([11], [20]).then_seeded()
	await killed.actions.attack(killed.units[0], killed.units[2])
	_check(killed.units[2].hit_points == 0 and killed.units[2] not in killed.turns.ordered_units,
		"HP0은 즉시 전투 불능과 턴 순서 제거")
	_check(killed.units[1].marked_target == null, "전투 불능 대상의 표식 제거")
	_check(not killed.units[2].visible and not killed.actions.is_marked(killed.units[2]),
		"전투 불능 대상은 숨기고 표식 표시도 해제")
	_check(not await killed.actions.attack(killed.units[0], killed.units[2]), "전투 불능 대상 재공격 거부")
	_check(killed.hits.size() == 1, "전투 불능 타격도 한 번 재생하고 거부한 공격은 무음")
	f.actions._damage(target, 0)
	_check(f.hits.size() == 1, "HP가 줄지 않으면 타격음을 요청하지 않음")
	f.actions._heal(actor, 1, "회복 검사")
	_check(f.hits.size() == 1, "회복은 타격음을 요청하지 않음")


func _test_archer_balance() -> void:
	for actor_index: int in [1, 3]:
		for marked: bool in [false, true]:
			if actor_index == 3 and marked:
				continue
			for attack_roll: int in [11, 20]:
				var f: Fixture = _fixture()
				var actor: CombatUnit = f.units[actor_index]
				var target: CombatUnit = f.units[3 if actor_index == 1 else 1]
				if actor_index == 1:
					f.turns.select_unit(actor)
				else:
					_enemy_archer(f)
					actor.cell = Vector2i(7, 4)
					f.units[0].cell = Vector2i(9, 9)
					target.cell = Vector2i(3, 4)
				if not marked and attack_roll == 11:
					_check(actor.hit_points == 14 and actor.get_max_hit_points() == 14,
						"아군과 적 궁수의 시작·최대 HP는14")
					_check(actor.get_dexterity() == 3 and actor.get_attack_bonus() == 5
						and actor.get_save_dc() == (13 if actor.is_ally else 11),
						"아군 DC13·풋내기 DC11은 피해 고정값과 별개")
				if marked:
					_check(f.actions.mark(actor, target), "궁수 피해 검사에서 표식 사용")
				var logs: Array[String] = []
				f.actions.logged.connect(func(line: String) -> void: logs.append(line))
				f.actions.dice = _dice_for([attack_roll], [20]).then_seeded()
				_check(await f.actions.attack(actor, target), "양쪽 궁수 기본 공격 실행")
				_check(f.hits.size() == 1, "아군·적 궁수와 표식 공격도 타격음 한 번")
				var count: int = (2 if attack_roll == 20 else 1) * (2 if marked else 1)
				var total: int = 1
				for rolled: int in f.actions.last_damage_rolls:
					total += rolled
				_check(f.actions.last_damage_rolls.size() == count and f.actions.last_damage == total
					and target.hit_points == maxi(0, 14 - total),
					"궁수 피해는 무기·표식 주사위에 고정값1을 한 번만 더함")
				_check(" + 1 = %d · HP %d" % [total, target.hit_points] in "\n".join(logs),
					"궁수 피해 로그도 고정값1과 실제 HP를 표시")


func _test_self_actions() -> void:
	var f: Fixture = _fixture()
	var warrior: CombatUnit = f.units[0]
	_check(not f.actions.can_use(warrior, "second_wind"), "만HP 숨 고르기는 효과 없음")
	_check(not f.actions.can_use(warrior, "surge"), "행동이 남으면 몰아치기 불가")
	warrior.hit_points = 1
	f.actions.dice = _dice_for([10], [10])
	_check(f.actions.use_self(warrior, "second_wind"), "숨 고르기 사용")
	_check(warrior.hit_points == 12 and warrior.second_wind_left == 0 and warrior.bonus_action_left == 0,
		"1d10+1 회복과 횟수·보조 행동 소비")
	warrior.begin_turn()
	_check(warrior.second_wind_left == 0, "자기 턴은 막당 횟수를 회복하지 않음")
	warrior.action_left = 0
	_check(f.actions.use_self(warrior, "surge"), "몰아치기 사용")
	_check(warrior.action_left == 1 and warrior.bonus_action_left == 0 and warrior.surge_left == 0,
		"몰아치기는 행동을 최대1로 채움")
	warrior.begin_turn()
	warrior.hit_points = 1
	warrior.potion_left = 1
	f.actions.dice = _dice_for([4, 4], [4, 4])
	_check(f.actions.use_self(warrior, "potion"), "물약 사용")
	_check(warrior.hit_points == 11 and warrior.potion_left == 0, "보유 물약 소비와2d4+2 회복")
	warrior.begin_turn()
	_check(not f.actions.use_self(warrior, "potion"), "물약 횟수 회복 없음")
	f.turns.select_unit(f.units[1])
	var archer: CombatUnit = f.units[1]
	_check(f.actions.use_self(archer, "disengage"), "물러서며 쏘기 사용")
	_check(archer.disengaged and archer.disengage_left == 1 and archer.bonus_action_left == 0,
		"이번 턴 기회 공격 제외와 횟수 소비")
	archer.begin_turn()
	_check(not archer.disengaged and archer.disengage_left == 1, "다음 턴 면제만 해제")
	archer.is_stunned = true
	archer.hit_points = 1
	_check(not f.actions.use_self(archer, "potion"), "기절 중 보조 행동 거부")


func _test_shove() -> void:
	var f: Fixture = _fixture()
	var actor: CombatUnit = f.units[0]
	var target: CombatUnit = f.units[2]
	f.actions.dice = _dice_for([20, 1], [20, 20])
	_check(f.actions.shove(actor, target), "밀치기 실행")
	_check(target.cell == Vector2i(6, 4) and actor.bonus_action_left == 0, "대결 승리 시1칸 이동과 자원 소비")
	_check(target.reaction_left == 1, "강제 이동은 기회 공격 없음")
	actor.bonus_action_left = 1
	target.cell = Vector2i(5, 4)
	f.units[3].cell = Vector2i(6, 4)
	_check(not f.actions.shove(actor, target) and actor.bonus_action_left == 1, "막힌 밀림 칸은 선택·소비 거부")
	f.units[3].cell = Vector2i(7, 4)
	f.actions.dice = _dice_for([10, 10], [20, 20])
	f.actions.shove(actor, target)
	_check(target.cell == Vector2i(5, 4), "대결 동점은 방어 승")
	actor.bonus_action_left = 1
	target.is_stunned = true
	f.actions.shove(actor, target)
	_check(target.cell == Vector2i(6, 4), "기절 대상은 대결 자동 패배")
	actor.cell = Vector2i(8, 4)
	target.cell = Vector2i(9, 4)
	actor.bonus_action_left = 1
	_check(not f.actions.can_target(actor, target, "shove"), "맵 밖으로 밀어내기 거부")


func _test_mark_and_stun() -> void:
	var f: Fixture = _fixture()
	f.turns.select_unit(f.units[1])
	var actor: CombatUnit = f.units[1]
	var target: CombatUnit = f.units[3]
	_check(f.actions.mark(actor, target), "표식 부여")
	_check(actor.marked_target == target and actor.mark_left == 0 and actor.bonus_action_left == 0,
		"표식은 유닛별 대상·횟수·자원 기록")
	actor.bonus_action_left = 1
	_check(not f.actions.mark(actor, f.units[2]), "사용한 표식 대상 변경 거부")
	f.actions.dice = _dice_for([20], [20]).then_seeded()
	await f.actions.attack(actor, target)
	_check(f.actions.last_damage_rolls.size() == 4, "표식 치명타는 무기와 표식 각각2개")
	var shock: Fixture = _fixture()
	_check(shock.units[1].get_save_dc() == 13, "아군 궁수 내성 DC는13")
	shock.turns.select_unit(shock.units[1])
	shock.units[2].reaction_left = 0
	shock.actions.dice = _dice_for([11, 0, 1], [20, 6, 20])
	_check(await shock.actions.attack(shock.units[1], shock.units[2], true), "충격 화살 실행")
	_check(shock.units[1].shock_left == 0 and shock.units[1].action_left == 0, "충격 화살 횟수와 행동 소비")
	_check(shock.units[2].is_stunned and shock.units[2].hit_points > 0, "명중·피해 후 정신 내성 실패 기절")
	_check(shock.hits.size() == 1, "충격 화살 피해와 기절은 타격음 한 번")
	shock.turns.end_turn()
	shock.turns.end_turn()
	_check(shock.turns.current_unit == shock.units[3] and shock.turns.is_turn_finished(shock.units[2]),
		"기절한 다음 턴은 자동으로 건너뜀")
	_check(not shock.units[2].is_stunned, "건너뛴 턴 끝에서 기절 해제")
	for roll: int in [14, 15]:
		var boundary: Fixture = _fixture()
		boundary.turns.select_unit(boundary.units[1])
		boundary.units[2].reaction_left = 0
		boundary.actions.dice = _dice_for([11, 4, roll], [20, 6, 20])
		await boundary.actions.attack(boundary.units[1], boundary.units[2], true)
		_check(boundary.units[2].hit_points == 7, "내성 성공 여부와 관계없이 충격 화살 피해 적용")
		_check(boundary.units[2].is_stunned == (roll == 14),
			"풋내기 정신-2의 DC13 경계: d20의14는 기절,15는 버팀")
	var waiting: Fixture = _fixture()
	waiting.units[1].is_stunned = true
	var start_dice: CombatDice = CombatDice.new()
	start_dice.seed = 33
	waiting.turns.start(waiting.units, start_dice)
	_check(waiting.turns.current_unit == waiting.units[0] and waiting.units[1].is_stunned,
		"두 번째 기절 유닛은 앞 유닛이 동작하는 동안 기절 유지")
	_check(not waiting.turns.select_unit(waiting.units[1]), "아직 건너뛰지 않은 기절 유닛 선택 거부")
	waiting.turns.remove_unit(waiting.units[3])
	_check(waiting.units[1].is_stunned, "다른 유닛 탈락의 묶음 재계산은 기절을 풀지 않음")
	waiting.turns.end_turn()
	_check(not waiting.units[1].is_stunned and waiting.turns.is_turn_finished(waiting.units[1]),
		"실제로 두 번째 유닛 순서를 건너뛴 끝에 기절 해제")
	var missed: Fixture = _fixture()
	missed.turns.select_unit(missed.units[1])
	var before_miss: int = missed.units[3].hit_points
	missed.actions.dice = _dice_for([1], [20])
	await missed.actions.attack(missed.units[1], missed.units[3], true)
	_check(missed.units[1].action_left == 0 and missed.units[1].shock_left == 0
		and missed.units[3].hit_points == before_miss and not missed.units[3].is_stunned,
		"빗나가도 충격 화살 행동·횟수 모두 소비, 피해·기절 없음")
	_check(not missed.actions.can_use(missed.units[1], "shock"), "빗나간 충격 화살 재사용 거부")
	missed.units[1].action_left = 1
	_check(not missed.actions.can_use(missed.units[1], "shock"), "행동만 회복해도 사용 횟수는 돌아오지 않음")
	_check(not missed.actions.can_target(missed.units[3], missed.units[0], "shock"),
		"풋내기 궁수의 충격 화살 실행 거부")


func _enemy_archer(f: Fixture) -> void:
	f.units[0].cell = Vector2i(4, 4)
	f.units[1].cell = Vector2i(0, 0)
	f.units[2].cell = Vector2i(0, 9)
	f.units[3].cell = Vector2i(5, 4)
	f.turns.end_turn()
	f.turns.end_turn()
	f.turns.end_turn()


func _test_reactions() -> void:
	var f: Fixture = _fixture()
	_enemy_archer(f)
	var asked: Array[String] = []
	f.actions.reaction_requested.connect(func(kind: String, _prompt: String) -> void:
		asked.append(kind)
		_check(f.actions.busy and not f.actions.can_move(f.units[3], Vector2i(6, 4)), "반응 대기 중 새 동작 잠금")
		f.actions.resolve_reaction(true)
	)
	f.actions.dice = _dice_for([1], [20])
	await f.actions.move_to(f.units[3], Vector2i(6, 4))
	_check(asked == ["opportunity"] and f.units[0].reaction_left == 0, "아군 기회 공격은 물어보고 반응 소비")
	_check(f.units[3].cell == Vector2i(6, 4) and f.units[3].movement_left == 5, "빗나가면 이동 계속")
	_check(not f.actions.busy and f.actions.pending_reactor == null, "반응 종료 후 대기 해제")
	f.actions.dice = _dice_for([11], [20]).then_seeded()
	await f.actions.attack(f.units[3], f.units[0])
	_check(asked.size() == 1 and f.units[0].parry_left == 2 and f.units[0].hit_points < 12,
		"기회 공격에 쓴 반응으로 흘려내기를 다시 쓸 수 없음")
	var skip: Fixture = _fixture()
	_enemy_archer(skip)
	skip.actions.reaction_requested.connect(func(_kind: String, _prompt: String) -> void: skip.actions.resolve_reaction(false))
	await skip.actions.move_to(skip.units[3], Vector2i(6, 4))
	_check(skip.units[0].reaction_left == 1 and skip.units[3].cell == Vector2i(6, 4), "넘기기는 반응을 쓰지 않음")
	var ranged: Fixture = _fixture()
	_enemy_archer(ranged)
	ranged.units[0].kind = CombatUnit.Kind.ARCHER
	await ranged.actions.move_to(ranged.units[3], Vector2i(6, 4))
	_check(ranged.units[0].reaction_left == 1, "궁수는 기회 공격 불가")
	var retreat: Fixture = _fixture()
	_enemy_archer(retreat)
	retreat.actions.use_self(retreat.units[3], "disengage")
	await retreat.actions.move_to(retreat.units[3], Vector2i(6, 4))
	_check(retreat.units[0].reaction_left == 1, "물러서며 쏘기 이동은 반응 안 함")
	var dead: Fixture = _fixture()
	_enemy_archer(dead)
	dead.units[3].hit_points = 1
	dead.actions.reaction_requested.connect(func(_kind: String, _prompt: String) -> void: dead.actions.resolve_reaction(true))
	dead.actions.dice = _dice_for([20], [20]).then_seeded()
	await dead.actions.move_to(dead.units[3], Vector2i(6, 4))
	_check(dead.units[3].hit_points == 0 and dead.units[3].cell == Vector2i(5, 4)
		and dead.units[3].movement_left == 6, "기회 공격으로 탈락하면 벗어나기 전 칸에서 이동 중단")
	_check(dead.hits.size() == 1, "기회 공격 피해도 타격음 한 번")
	var parry: Fixture = _fixture()
	parry.units[0].cell = Vector2i(4, 4)
	parry.units[2].cell = Vector2i(5, 4)
	parry.turns.end_turn()
	parry.turns.end_turn()
	parry.actions.reaction_requested.connect(func(kind: String, prompt: String) -> void:
		_check(kind == "parry" and parry.actions.last_damage_rolls.is_empty(), "피해 굴림 전에 흘려내기 확인")
		_check("55.0%" in prompt, "풋내기 DC11 흘려내기 확인은 성공률55%")
		parry.actions.resolve_reaction(true)
	)
	parry.actions.dice = _dice_for([20, 10], [20, 20])
	await parry.actions.attack(parry.units[2], parry.units[0])
	_check(parry.units[0].hit_points == 12 and parry.actions.last_damage == 0, "흘려내기 성공은 치명타도 무효")
	_check(parry.hits.is_empty(), "성공한 흘려내기는 타격음을 요청하지 않음")
	_check(parry.units[0].reaction_left == 0 and parry.units[0].parry_left == 1, "흘려내기 반응과 막당 횟수 소비")
	_check(parry.units[2].action_left == 0, "흘려내기 성공해도 공격자 행동 소비")
	parry.units[2].action_left = 1
	parry.units[0].reaction_left = 1
	parry.actions.dice = _dice_for([20, 9], [20, 20]).then_seeded()
	await parry.actions.attack(parry.units[2], parry.units[0])
	_check(parry.actions.last_damage > 0 and parry.actions.last_damage_rolls.size() == 2,
		"민첩+1의 d20의9는 DC11 미달로 치명타 피해 적용")
	_check(parry.hits.size() == 1, "실패한 흘려내기는 실제 피해 타격음 한 번")
	_check(parry.units[0].reaction_left == 0 and parry.units[0].parry_left == 0,
		"흘려내기 내성 실패도 반응과 횟수 소비")
	var automatic: Fixture = _fixture()
	automatic.actions.dice = _dice_for([11, 4], [20, 8])
	await automatic.actions.attack(automatic.units[0], automatic.units[2])
	_check(automatic.units[2].parry_left == 2 and automatic.units[2].reaction_left == 1
		and automatic.units[2].hit_points == 5, "야만인은 흘려내기 없이 아군 피해를 받음")
	var parried_shock: Fixture = _fixture()
	_enemy_archer(parried_shock)
	parried_shock.actions.reaction_requested.connect(func(_kind: String, _prompt: String) -> void:
		parried_shock.actions.resolve_reaction(true)
	)
	_check(not await parried_shock.actions.attack(parried_shock.units[3], parried_shock.units[0], true),
		"풋내기 궁수는 충격 화살로 공격하지 못함")
	_check(parried_shock.units[0].hit_points == 12 and not parried_shock.units[0].is_stunned
		and parried_shock.units[3].shock_left == 1, "불가능한 스킬은 피해·기절·횟수를 바꾸지 않음")


func _test_own_turn_parry() -> void:
	var scene: PackedScene = load("res://scenes/combat/battle.tscn") as PackedScene
	for choice: int in range(3):
		var battle: Node2D = scene.instantiate() as Node2D
		battle.stages[0] = load("res://scenes/combat/stage.tres") as CombatStage
		root.add_child(battle)
		battle.set_process(false)
		await process_frame
		var units: Array[CombatUnit] = battle.get("units")
		var turns: CombatTurns = battle.get("turns") as CombatTurns
		var actions: CombatActions = battle.get("actions") as CombatActions
		var hud: CombatTurnHud = battle.get_node("UI/TurnHud") as CombatTurnHud
		var dice: CombatDice = CombatDice.new()
		dice.seed = 33
		turns.start(units, dice)
		units[0].cell = Vector2i(4, 4)
		units[1].cell = Vector2i(0, 0)
		units[2].cell = Vector2i(5, 4)
		units[3].cell = Vector2i(0, 9)
		battle.call("_update_turn_ui")
		_check(units[1].hit_points == 14 and units[3].hit_points == 14,
			"실제 장면의 아군과 적 궁수 HP는14")
		var asked: Array[String] = []
		var respond: Callable = func(kind: String, prompt: String) -> void:
			asked.append(kind)
			_check(kind == "parry" and turns.current_unit == units[0]
				and actions.pending_reactor == units[0], "자기 턴 기회 공격 명중에도 흘려내기 요청")
			_check(hud.reaction_dialog.visible and hud.end_button.disabled
				and actions.busy, "자기 턴 흘려내기 창과 입력 잠금")
			_check("55.0%" in prompt and actions.last_damage_rolls.is_empty(),
				"자기 턴에도 피해 굴림 전에 풋내기 DC11·55% 표시")
			if choice == 2:
				hud.reaction_dialog.get_cancel_button().pressed.emit()
			else:
				hud.reaction_dialog.get_ok_button().pressed.emit()
		actions.reaction_requested.connect(respond)
		if choice == 0:
			actions.dice = _dice_for([11, 10], [20, 20])
		elif choice == 1:
			actions.dice = _dice_for([11, 9, 4], [20, 20, 4])
		else:
			actions.dice = _dice_for([11, 4], [20, 4])
		_check(await actions.move_to(units[0], Vector2i(3, 4)), "자기 턴 기회 공격 후 이동 완료")
		await process_frame
		_check(asked == ["parry"] and units[2].reaction_left == 0, "적 기회 공격은 자동이며 반응 소비")
		_check(units[0].hit_points == (12 if choice == 0 else 7),
			"흘려내기 성공은 피해 무효, 실패·넘기기는 피해 적용")
		var reaction: int = 1 if choice == 2 else 0
		var uses: int = 2 if choice == 2 else 1
		_check(units[0].reaction_left == reaction and units[0].parry_left == uses,
			"성공·실패는 반응과 횟수 소비, 넘기기는 유지")
		_check(units[0].cell == Vector2i(3, 4) and units[0].movement_left == 5
			and units[0].action_left == 1 and units[0].bonus_action_left == 1,
			"흘려내기 뒤 이동1만 소비하고 행동·보조 행동 유지")
		_check(not hud.reaction_dialog.visible and not actions.busy
			and actions.pending_reactor == null and not hud.end_button.disabled,
			"자기 턴 반응 선택 후 창과 입력 잠금 해제")
		turns.select_unit(units[1])
		turns.select_unit(units[0])
		_check(units[0].reaction_left == reaction, "아군 선택 전환은 쓴 반응을 회복하지 않음")
		turns.end_turn()
		turns.end_turn()
		_check(not turns.current_unit.is_ally and units[0].reaction_left == reaction,
			"적 턴 시작에도 아군 반응 회복 없음")
		turns.end_turn()
		turns.end_turn()
		_check(turns.current_unit == units[0] and units[0].reaction_left == 1
			and units[0].parry_left == uses, "다음 자기 턴 시작에는 반응만 회복")
		actions.reaction_requested.disconnect(respond)
		battle.queue_free()
		await process_frame


func _test_scene_input() -> void:
	var scene: PackedScene = load("res://scenes/combat/battle.tscn") as PackedScene
	var battle: Node2D = scene.instantiate() as Node2D
	battle.stages[0] = load("res://scenes/combat/stage.tres") as CombatStage
	root.add_child(battle)
	battle.set_process(false)
	await process_frame
	var turns: CombatTurns = battle.get("turns") as CombatTurns
	var actions: CombatActions = battle.get("actions") as CombatActions
	var units: Array[CombatUnit] = battle.get("units")
	var map: TileMapLayer = battle.get_node("Map") as TileMapLayer
	var hud: CombatTurnHud = battle.get_node("UI/TurnHud") as CombatTurnHud
	var dice: CombatDice = CombatDice.new()
	dice.seed = 33
	turns.start(units, dice)
	var destination: Vector2i = Vector2i(1, 6)
	var screen: Vector2 = map.get_global_transform_with_canvas() * map.map_to_local(destination)
	await _click(screen, MOUSE_BUTTON_RIGHT)
	_check(units[0].cell == Vector2i(1, 4) and not (battle.get("preview_path") as Array).is_empty(), "이동 첫 클릭은 미리보기")
	await _click(screen, MOUSE_BUTTON_RIGHT)
	_check(units[0].cell == destination and units[0].movement_left == 4, "이동 두 번째 클릭 실행")
	units[2].cell = Vector2i(2, 6)
	units[2].parry_left = 0
	battle.call("_update_turn_ui")
	actions.dice = _dice_for([1], [20])
	var point: Vector2 = units[2].get_global_transform_with_canvas() * Vector2(0, -10)
	await _click(point)
	_check(units[0].action_left == 1 and battle.get("preview_target") == units[2], "공격 첫 클릭은 피해·자원 소비 없음")
	await _click(point)
	_check(units[0].action_left == 0 and units[2].hit_points == 12, "공격 두 번째 클릭과 빗나감 처리")
	hud.action_selected.emit("surge")
	_check(units[0].surge_left == 1, "자기 대상 동작 첫 클릭은 선택만")
	hud.action_selected.emit("surge")
	_check(units[0].surge_left == 0 and units[0].action_left == 1, "자기 대상 동작 두 번째 클릭 실행")
	_check("몰아치기" in hud.message_label.text, "실행 결과 화면 피드백")
	actions.dice = _dice_for([11], [20]).then_seeded()
	await _click(point)
	_check(units[0].action_left == 1 and units[2].hit_points == 12
		and battle.get("preview_target") == units[2], "몰아치기 뒤 추가 공격 첫 클릭은 미리보기")
	await _click(point)
	_check(turns.current_unit == units[0] and units[0].action_left == 0
		and units[0].bonus_action_left == 0 and units[2].hit_points < 12,
		"아군은 같은 턴에 몰아치기 뒤 두 번째 클릭으로 추가 공격")
	turns.end_turn()
	turns.end_turn()
	_check(units[0].get_save_dc() == 13 and units[2].get_save_dc() == 11,
		"실제 장면도 아군 DC13과 풋내기 DC11을 분리")
	actions.dice = _dice_for([20, 12], [20, 20])
	actions.reaction_requested.connect(func(kind: String, _prompt: String) -> void:
		_check(kind == "parry" and hud.reaction_dialog.visible and hud.end_button.disabled,
			"실제 확인 창이 뜨고 턴 종료가 잠김")
		hud.reaction_dialog.get_ok_button().pressed.emit()
	)
	await actions.attack(units[2], units[0])
	_check(units[0].parry_left == 1 and units[0].hit_points == 12,
		"실제 확인 창의 확인 버튼이 반응 모델에 연결됨")
	_check(not hud.reaction_dialog.visible and not actions.busy, "확인 후 창과 입력 잠금 해제")
	battle.queue_free()
	await process_frame
	# 몸통에 가린 빈 칸과 겹친 유닛은 실제 입력으로 별도 확인한다.
	var overlap: Node2D = scene.instantiate() as Node2D
	overlap.stages[0] = load("res://scenes/combat/stage.tres") as CombatStage
	root.add_child(overlap)
	overlap.set_process(false)
	await process_frame
	var overlap_units: Array[CombatUnit] = overlap.get("units")
	var overlap_turns: CombatTurns = overlap.get("turns") as CombatTurns
	var overlap_hud: CombatTurnHud = overlap.get_node("UI/TurnHud") as CombatTurnHud
	var overlap_map: TileMapLayer = overlap.get_node("Map") as TileMapLayer
	dice.seed = 33
	overlap_turns.start(overlap_units, dice)
	var hidden_cell: Vector2i = overlap_units[0].cell - Vector2i(0, 1)
	var hidden_screen: Vector2 = overlap_map.get_global_transform_with_canvas() * (
		overlap_map.map_to_local(hidden_cell) + Vector2(5, 0))
	await _click(hidden_screen, MOUSE_BUTTON_RIGHT)
	_check(overlap.get("preview_cell") == hidden_cell, "이동 모드에서 몸통 뒤 빈 헥사 칸 선택")
	await _click(hidden_screen, MOUSE_BUTTON_RIGHT)
	_check(overlap_units[0].cell == hidden_cell, "몸통에 가린 빈 칸 이동 실행")
	overlap_hud.action_selected.emit("attack")
	overlap_units[2].cell = Vector2i(5, 4)
	overlap_units[3].cell = Vector2i(4, 5)
	overlap.call("_update_turn_ui")
	var overlap_point: Vector2 = overlap_units[2].get_global_transform_with_canvas() * Vector2(-5, -1)
	await _click(overlap_point)
	_check(overlap.get("preview_target") == overlap_units[3], "겹친 몸통은 y-sort 앞쪽 유닛 선택")
	overlap.queue_free()
	await process_frame


func _test_scene_shock() -> void:
	var scene: PackedScene = load("res://scenes/combat/battle.tscn") as PackedScene
	var battle: Node2D = scene.instantiate() as Node2D
	battle.stages[0] = load("res://scenes/combat/stage.tres") as CombatStage
	root.add_child(battle)
	battle.set_process(false)
	await process_frame
	var units: Array[CombatUnit] = battle.get("units")
	var turns: CombatTurns = battle.get("turns") as CombatTurns
	var actions: CombatActions = battle.get("actions") as CombatActions
	var hud: CombatTurnHud = battle.get_node("UI/TurnHud") as CombatTurnHud
	var dice: CombatDice = CombatDice.new()
	dice.seed = 33
	turns.start(units, dice)
	units[3].cell = Vector2i(3, 5)
	turns.select_unit(units[1])
	var buttons: Dictionary = hud.get("_actions")
	var shock_button: Button = buttons["shock"] as Button
	_check(shock_button.visible and not shock_button.disabled, "실제 장면의 충격 화살 버튼 활성화")
	shock_button.pressed.emit()
	var before_miss: int = units[3].hit_points
	actions.dice = _dice_for([1], [20])
	var point: Vector2 = units[3].get_global_transform_with_canvas() * Vector2(0, -10)
	await _click(point)
	_check(units[1].action_left == 1 and units[1].shock_left == 1, "충격 화살 미리보기는 행동·횟수 유지")
	await _click(point)
	_check(units[1].action_left == 0 and units[1].shock_left == 0
		and units[3].hit_points == before_miss and not units[3].is_stunned,
		"실제 두 번째 클릭의 충격 화살 빗나감은 행동·횟수만 소비")
	var badges: Dictionary = hud.get("_badges")
	_check(shock_button.disabled and (badges["shock"] as Label).text == "0",
		"실행 후 충격 화살 비활성화와 모서리 횟수 배지 갱신")
	battle.queue_free()
	await process_frame


func _click(point: Vector2, button_index: MouseButton = MOUSE_BUTTON_LEFT) -> void:
	var event: InputEventMouseButton = InputEventMouseButton.new()
	event.position = root.get_final_transform() * point
	event.global_position = event.position
	event.button_index = button_index
	event.pressed = true
	Input.parse_input_event(event)
	await process_frame
	event.pressed = false
	Input.parse_input_event(event)
	await process_frame
	var battle: Node2D = root.get_node_or_null("Battle") as Node2D
	if battle == null:
		return
	for frame: int in range(600):
		var moving: bool = false
		for unit: CombatUnit in battle.get("units"):
			moving = moving or unit.is_moving
		if not moving and not battle.has_node("Arrow"):
			return
		await process_frame
	_check(false, "포인터 입력 후 연출이 제한 시간 안에 끝나지 않음")
