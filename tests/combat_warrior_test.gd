extends SceneTree
## 전사 재디자인 1단계(#423): 수치, 전투마다 횟수, 복합 비용, 방어막, 시전자 시계와 시계 슬롯, 새 스킬.

class Fixture extends RefCounted:
	var units: Array[CombatUnit] = []
	var turns: CombatTurns = CombatTurns.new()
	var actions: CombatActions = CombatActions.new()
	var logs: Array[String] = []


const ScriptedDice = preload("res://tests/scripted_dice.gd")

var _checks: int = 0
var _failures: int = 0
var _created: Array[CombatUnit] = []


func _initialize() -> void:
	create_timer(30.0).timeout.connect(func() -> void:
		push_error("Combat warrior: test timeout")
		quit(1)
	)
	_run.call_deferred()


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error(message)


## 아군 전사(4,4)·궁수(3,4), 적 야만인(5,4)·궁수(7,4). extra_archer면 아군 궁수(3,5)를 더한다. 순서는 order다.
func _fixture(order: Array[int] = [0, 1, 2, 3], extra_archer: bool = false) -> Fixture:
	var f: Fixture = Fixture.new()
	var cells: Array[Vector2i] = [Vector2i(4, 4), Vector2i(3, 4), Vector2i(5, 4), Vector2i(7, 4), Vector2i(3, 5)]
	for index: int in range(5 if extra_archer else 4):
		var unit: CombatUnit = CombatUnit.new()
		unit.kind = CombatUnit.Kind.WARRIOR if index % 2 == 0 and index < 4 else CombatUnit.Kind.ARCHER
		unit.is_ally = index < 2 or index == 4
		unit.cell = cells[index]
		unit.hit_points = unit.get_max_hit_points()
		f.units.append(unit)
		_created.append(unit)
	var desired: Array[CombatUnit] = []
	for index: int in order:
		desired.append(f.units[index])
	ScriptedDice.arrange_turns(f.turns, f.units, desired)
	f.actions.initialize(f.units, f.turns)
	f.actions.logged.connect(f.logs.append)
	return f


func _dice(values: Array[int], sides: Array[int]) -> ScriptedDice:
	return ScriptedDice.new(values, sides)


func _run() -> void:
	_test_stats()
	_test_skill_ownership()
	_test_combat_uses()
	_test_compound_costs()
	await _test_cross_slash()
	await _test_steel_charge()
	_test_sweep_shape()
	await _test_sweep()
	_test_holy_veil()
	await _test_battle_cry()
	_test_battle_cry_clock_slot()
	_test_phalanx()
	_test_save_state()
	for unit: CombatUnit in _created:
		unit.free()
	var dice_problems: Array[String] = ScriptedDice.finish()
	_check(dice_problems.is_empty(), "준비한 주사위 값을 요청대로 모두 굴림 " + str(dice_problems))
	print("Combat warrior: %d checks, %d failures" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)


func _test_stats() -> void:
	var f: Fixture = _fixture()
	var warrior: CombatUnit = f.units[0]
	var archer: CombatUnit = f.units[1]
	var barbarian: CombatUnit = f.units[2]
	_check(warrior.get_ability_sides(CombatUnit.Ability.WILL) == 8, "전사 의지 d8")
	_check(warrior.get_max_hit_points() == 11 and archer.get_max_hit_points() == 9,
		"아군 최대 HP = 건강 면 수 ÷ 2 × (레벨 0 + 1) + 5: 전사 11, 궁수 9")
	_check(barbarian.get_max_hit_points() == 12, "몬스터 HP는 그대로")
	warrior.begin_turn()
	archer.begin_turn()
	barbarian.begin_turn()
	_check(warrior.movement_left == 3 and archer.movement_left == 6 and barbarian.movement_left == 6,
		"이동력: 전사 3, 궁수와 풋내기 야만인 6")
	_check(warrior.get_damage_bonus() == 0 and archer.get_damage_bonus() == 1,
		"전사의 기본 피해 보정 0, 궁수 +1은 질문 3까지 유지")
	warrior.armor = {"stats": {"max_hit_points": 2}}
	_check(warrior.get_max_hit_points() == 13, "장비 HP는 식에 더함")


func _test_skill_ownership() -> void:
	var f: Fixture = _fixture()
	var warrior: CombatUnit = f.units[0]
	for action: String in ["cross_slash", "steel_charge", "holy_veil", "battle_cry", "phalanx", "opportunity"]:
		_check(CombatActionRules.belongs_to(warrior, action), "아군 전사의 스킬: " + action)
		_check(not CombatActionRules.belongs_to(f.units[1], action), "아군 궁수는 전사 스킬 없음: " + action)
		_check(not CombatActionRules.belongs_to(f.units[2], action) or action == "opportunity",
			"풋내기 야만인은 전사 스킬 없음: " + action)
	_check(not CombatActionRules.belongs_to(warrior, "second_wind"), "아군 전사의 숨 고르기 삭제")
	_check(CombatActionRules.belongs_to(f.units[2], "second_wind"), "풋내기 야만인의 숨 고르기 유지")
	for action: String in ["parry", "surge"]:
		_check(action not in CombatActionRules.NAMES and action not in CombatActionRules.USE_COUNTERS
			and not CombatActionRules.GROUPS.any(func(group: Array) -> bool: return action in group), "옛 스킬 삭제: " + action)
	_check(CombatActionRules.GROUPS[2] == ["opportunity"], "반응 묶음은 기회 공격만")


func _test_combat_uses() -> void:
	var f: Fixture = _fixture()
	var warrior: CombatUnit = f.units[0]
	var archer: CombatUnit = f.units[1]
	_check("전투마다 1회 · 1회 남음" in CombatActionRules.details(warrior, "battle_cry"), "설명에 전투마다 횟수와 남은 횟수")
	warrior.battle_cry_left = 0
	warrior.cross_slash_left = 0
	warrior.steel_charge_left = 0
	archer.mark_left = 0
	_check("전투마다 1회 · 0회 남음" in CombatActionRules.details(warrior, "battle_cry"), "다 쓰면 0회 남음")
	_check(f.actions.unavailable_reason(warrior, "battle_cry") == "이번 전투의 횟수를 모두 씀", "전투마다 횟수 소진 이유")
	_check(not f.actions.can_use(warrior, "battle_cry"), "횟수를 다 쓰면 비활성")
	warrior.shield_points = 4
	warrior.shield_turns = 2
	warrior.begin_stage(false)
	archer.begin_stage(false)
	_check(warrior.battle_cry_left == 1 and warrior.cross_slash_left == 1 and warrior.steel_charge_left == 1,
		"새 전투(같은 막의 다음 스테이지·재시작)에서 전투마다 횟수 회복")
	_check(archer.mark_left == 0, "막당 횟수는 같은 막의 다음 전투에서 회복하지 않음")
	_check(warrior.shield_points == 0 and warrior.shield_turns == 0, "방어막은 전투 종료에 소멸")
	archer.begin_stage(true)
	_check(archer.mark_left == 1, "막당 횟수는 막 시작에 회복")


func _test_compound_costs() -> void:
	var f: Fixture = _fixture()
	var warrior: CombatUnit = f.units[0]
	_check("비용: 행동 1 + 보조 행동 1" in CombatActionRules.details(warrior, "cross_slash"), "십자 베기 호버의 비용 문구")
	_check("비용: 보조 행동 1 + 이동력 1" in CombatActionRules.details(warrior, "steel_charge"), "강철 돌진 호버의 비용 문구")
	_check("비용: 보조 행동 1 + 이동력" in CombatActionRules.details(warrior, "jump"), "점프 호버의 비용 문구")
	_check(CombatActionRules.cost_text("attack").is_empty(), "자원 하나만 쓰는 동작은 비용 문구 없음")
	_check(f.actions.can_use(warrior, "cross_slash") and f.actions.can_use(warrior, "steel_charge"),
		"자원이 모두 있으면 복합 비용 스킬 활성")
	warrior.bonus_action_left = 0
	_check(not f.actions.can_use(warrior, "cross_slash")
		and f.actions.unavailable_reason(warrior, "cross_slash") == "자원을 이미 씀", "보조 행동이 없으면 십자 베기 비활성")
	warrior.bonus_action_left = 1
	warrior.action_left = 0
	_check(not f.actions.can_use(warrior, "cross_slash"), "행동이 없으면 십자 베기 비활성")
	warrior.action_left = 1
	warrior.movement_left = 0
	_check(not f.actions.can_use(warrior, "steel_charge")
		and f.actions.unavailable_reason(warrior, "steel_charge") == "이동력을 이미 씀", "이동력이 없으면 강철 돌진 비활성")


func _test_cross_slash() -> void:
	var f: Fixture = _fixture()
	var warrior: CombatUnit = f.units[0]
	var barbarian: CombatUnit = f.units[2]
	f.actions.dice = _dice([15, 5, 15, 4], [20, 20, 20, 20])
	_check(await f.actions.cross_slash(warrior, barbarian), "인접한 적에게 십자 베기")
	_check(barbarian.hit_points == 12 - 5 - 4, "기본 공격 2회가 각각 명중굴림과 피해(힘 d20 + 0)를 굴림")
	_check(warrior.action_left == 0 and warrior.bonus_action_left == 0 and warrior.cross_slash_left == 0,
		"행동과 보조 행동, 전투마다 횟수를 모두 소비")
	var killed: Fixture = _fixture()
	killed.units[2].hit_points = 3
	killed.actions.dice = _dice([15, 5], [20, 20])
	await killed.actions.cross_slash(killed.units[0], killed.units[2])
	_check(killed.units[2].hit_points == 0 and killed.logs.any(func(line: String) -> bool: return "둘째 타격 취소" in line),
		"첫 타격으로 쓰러지면 둘째 타격 취소")
	_check(killed.units[0].cross_slash_left == 0 and killed.units[0].bonus_action_left == 0, "취소돼도 자원과 횟수는 소비")
	var far: Fixture = _fixture()
	_check(not far.actions.can_target(far.units[0], far.units[3], "cross_slash"), "인접하지 않은 적은 대상 아님")


func _test_steel_charge() -> void:
	var f: Fixture = _fixture()
	var warrior: CombatUnit = f.units[0]
	var barbarian: CombatUnit = f.units[2]
	warrior.weapon = {"stats": {"damage_bonus": 2}}
	f.actions.dice = _dice([15, 6], [20, 20])
	_check(await f.actions.steel_charge(warrior, barbarian), "인접한 적에게 강철 돌진")
	_check(barbarian.hit_points == 6, "피해는 힘 d20 + 레벨이고 기타 가산치(장비 +2)를 더하지 않음")
	_check(barbarian.cell == Vector2i(6, 4) and warrior.cell == Vector2i(5, 4), "대상을 1칸 밀고 비워진 칸으로 1칸 전진")
	_check(warrior.movement_left == 2 and warrior.bonus_action_left == 0 and warrior.steel_charge_left == 0
		and warrior.action_left == 1, "보조 행동과 이동력 1만 소비하고 전진에는 이동력을 더 쓰지 않음")
	for blocker: String in ["crate", "unit", "higher", "edge"]:
		var blocked: Fixture = _fixture()
		var target: CombatUnit = blocked.units[2]
		match blocker:
			"crate":
				blocked.actions.create_prop(Vector2i(6, 4), "crate")
			"unit":
				blocked.units[3].cell = Vector2i(6, 4)
			"higher":
				blocked.actions.grid.heights[Vector2i(6, 4)] = 1
			"edge":
				blocked.units[0].cell = Vector2i(8, 4)
				target.cell = Vector2i(9, 4)
				blocked.units[3].cell = Vector2i(7, 7)
		var origin: Vector2i = blocked.units[0].cell
		blocked.actions.dice = _dice([15, 6], [20, 20])
		await blocked.actions.steel_charge(blocked.units[0], target)
		_check(target.hit_points == 6 and blocked.units[0].cell == origin and target.cell == origin + Vector2i(1, 0),
			"밀려날 칸이 막히면 피해만: " + blocker)
	# #407 1단계 답 1: 피해로 쓰러지면 밀침 없이 대상 칸으로 전진하고, 떠나는 칸의 인접 적에게 기회 공격을 받지 않는다.
	var downed: Fixture = _fixture()
	var charger: CombatUnit = downed.units[0]
	var watcher: CombatUnit = downed.units[3]
	watcher.kind = CombatUnit.Kind.WARRIOR
	watcher.cell = Vector2i(4, 3)
	downed.units[2].hit_points = 6
	downed.actions.dice = _dice([15, 6], [20, 20])
	_check(await downed.actions.steel_charge(charger, downed.units[2]), "쓰러뜨리는 강철 돌진")
	_check(downed.units[2].hit_points == 0 and charger.cell == Vector2i(5, 4), "대상이 쓰러지면 대상이 있던 칸으로 1칸 전진")
	_check(charger.hit_points == charger.get_max_hit_points() and watcher.reaction_left == 1
		and downed.actions.pending_reactor == null, "전진은 기회 공격을 받지 않음")
	_check(charger.movement_left == 2 and charger.bonus_action_left == 0, "전진에 이동력을 더 쓰지 않음")
	var walled: Fixture = _fixture()
	walled.actions.create_prop(Vector2i(6, 4), "crate")
	walled.units[2].hit_points = 6
	walled.actions.dice = _dice([15, 6], [20, 20])
	await walled.actions.steel_charge(walled.units[0], walled.units[2])
	_check(walled.units[0].cell == Vector2i(5, 4), "밀려날 칸이 막혀도 대상이 쓰러지면 그 칸으로 전진")
	var missed: Fixture = _fixture()
	missed.actions.dice = _dice([1], [20])
	await missed.actions.steel_charge(missed.units[0], missed.units[2])
	_check(missed.units[2].cell == Vector2i(5, 4) and missed.units[0].cell == Vector2i(4, 4)
		and missed.units[0].steel_charge_left == 0 and missed.units[0].movement_left == 2,
		"빗나가면 밀치거나 전진하지 않고 비용은 소비")


func _test_sweep_shape() -> void:
	var f: Fixture = _fixture()
	var grid: CombatGrid = f.actions.grid
	var origin: Vector2i = Vector2i(4, 4)
	# 정면 +x(화면 오른쪽 아래)의 오른쪽 옆은 +y(왼쪽 아래)다. 순서는 왼쪽 옆부터 시계방향이다.
	_check(grid.sweep_cells(origin, Vector2i(5, 4)) == [Vector2i(4, 3), Vector2i(5, 3), Vector2i(5, 4), Vector2i(5, 5), Vector2i(4, 5)],
		"정면 반달 5칸: 왼쪽 옆 → 앞왼쪽 → 앞 → 앞오른쪽 → 오른쪽 옆")
	_check(grid.sweep_cells(origin, Vector2i(4, 3)) == [Vector2i(3, 4), Vector2i(3, 3), Vector2i(4, 3), Vector2i(5, 3), Vector2i(5, 4)],
		"다른 방향을 조준하면 모양과 순서가 함께 돎")
	_check(grid.sweep_cells(origin, Vector2i(6, 4)).is_empty() and grid.sweep_cells(origin, origin).is_empty(),
		"인접하지 않은 칸은 정면이 될 수 없음")
	grid.heights[Vector2i(5, 3)] = 2
	grid.heights[Vector2i(5, 5)] = 1
	grid.pits = [Vector2i(4, 3)]
	grid.blocked_cells = [Vector2i(5, 4)]
	f.actions.create_prop(Vector2i(4, 5), "crate")
	_check(grid.sweep_cells(origin, Vector2i(5, 4)) == [Vector2i(5, 5)],
		"높이 차 2 이상·낭떠러지·막힌 칸·나무 상자는 빼고, 막힌 정면 너머의 칸도 시야 없이 셈")
	_check(grid.sweep_cells(Vector2i(0, 0), Vector2i(0, 1)) == [Vector2i(1, 0), Vector2i(1, 1), Vector2i(0, 1)], "맵 밖 칸은 뺌")
	_check(grid.sweep_cells(Vector2i(0, 4), Vector2i(-1, 4)).is_empty(), "맵 밖 칸은 정면이 될 수 없음")


func _test_sweep() -> void:
	var f: Fixture = _fixture()
	var warrior: CombatUnit = f.units[0]
	var archer: CombatUnit = f.units[1]
	var barbarian: CombatUnit = f.units[2]
	var enemy_archer: CombatUnit = f.units[3]
	enemy_archer.cell = Vector2i(4, 3)
	archer.cell = Vector2i(5, 5)
	_check(CombatActionRules.belongs_to(warrior, "sweep") and not CombatActionRules.belongs_to(archer, "sweep")
		and not CombatActionRules.belongs_to(barbarian, "sweep"), "휩쓸기는 아군 전사만")
	_check(CombatActionRules.resource_of("sweep") == CombatUnit.TurnResource.ACTION
		and CombatActionRules.uses_left(warrior, "sweep") == -1, "행동 자원, 무제한")
	var details: String = CombatActionRules.details(warrior, "sweep")
	_check("사거리: 정면 반달 5칸" in details and "피해: 힘 d20 ÷2 올림" in details and "판정: 대상마다 힘 d20" in details,
		"호버에 범위·피해식·판정 " + details)
	_check(f.actions.sweep_targets(warrior, Vector2i(5, 4)) == [enemy_archer, barbarian], "영향 칸의 적만 시계방향 순서로, 아군은 제외")
	_check(f.actions.can_sweep(warrior, Vector2i(4, 5)), "빈 칸을 정면으로 골라도 반달 안에 적이 있으면 쓸 수 있음")
	var diagonal: float = f.actions.sweep_chance(warrior, enemy_archer)
	var preview: CombatChecks.AttackPreview = f.actions.grid.attack_preview(warrior, enemy_archer)
	_check(diagonal > 0.0 and is_equal_approx(diagonal, CombatChecks.hit_chance(20, warrior.get_hit_bonus(),
		f.actions.grid.armor_class(enemy_archer), preview.mode)), "기본 공격 사거리 밖의 반달 칸도 명중률을 보임")
	var archer_hp: int = enemy_archer.hit_points
	f.actions.dice = _dice([15, 7, 15, 10], [20, 20, 20, 20])
	_check(await f.actions.sweep(warrior, Vector2i(5, 4)), "휩쓸기 실행")
	_check(archer_hp - enemy_archer.hit_points == 4 and barbarian.hit_points == 12 - 5,
		"대상마다 명중굴림 뒤 피해 ⌈힘 d20 ÷ 2⌉ + 0을 왼쪽 옆부터 차례로 굴림")
	_check(archer.hit_points == archer.get_max_hit_points(), "반달 안의 아군은 맞지 않음")
	_check(warrior.action_left == 0 and warrior.bonus_action_left == 1 and warrior.movement_left == 3, "행동만 소비")
	_check(f.logs.any(func(line: String) -> bool: return "휩쓸기: 대상 2명" in line)
		and f.logs.any(func(line: String) -> bool: return "(휩쓸기 ÷2 올림): 힘 d20 [7] → 4 +0 = 4" in line), "대상 수와 피해식을 로그에 기록")
	_check(not f.actions.can_use(warrior, "sweep") and f.actions.unavailable_reason(warrior, "sweep") == "자원을 이미 씀",
		"행동을 쓰면 비활성")
	var bonus: Fixture = _fixture()
	bonus.units[0].weapon = {"stats": {"damage_bonus": 2}}
	_check("피해: 힘 d20 ÷2 올림 +2" in CombatActionRules.details(bonus.units[0], "sweep"), "가산치는 ÷2 올림 뒤에 띄워 더함")
	bonus.actions.dice = _dice([1], [20])
	await bonus.actions.sweep(bonus.units[0], Vector2i(5, 4))
	_check(bonus.units[2].hit_points == 12 and bonus.units[0].action_left == 0, "빗나가도 행동은 소비")
	bonus.units[0].action_left = 1
	bonus.actions.dice = _dice([15, 1], [20, 20])
	await bonus.actions.sweep(bonus.units[0], Vector2i(5, 4))
	_check(bonus.units[2].hit_points == 12 - 3, "피해는 ⌈1 ÷ 2⌉ + 기타 가산치(장비 +2)")
	# #407 답 5a: 반달 안에 적이 없어도 실행하고 행동을 소비한다.
	var lone: Fixture = _fixture()
	var alone: CombatUnit = lone.units[0]
	lone.units[2].cell = Vector2i(7, 7)
	lone.actions.grid.blocked_cells = [Vector2i(4, 3)]
	_check(lone.actions.can_use(alone, "sweep") and lone.actions.can_sweep(alone, Vector2i(5, 4))
		and lone.actions.can_sweep(alone, Vector2i(4, 3)), "적이 없는 방향과 막힌 칸도 정면으로 고를 수 있어 버튼이 켜져 있음")
	_check(not lone.actions.can_sweep(alone, Vector2i(6, 4)) and not lone.actions.can_sweep(alone, alone.cell),
		"인접하지 않은 칸은 정면이 될 수 없음")
	var edge: Fixture = _fixture()
	edge.units[0].cell = Vector2i(0, 4)
	_check(not edge.actions.can_sweep(edge.units[0], Vector2i(-1, 4)), "맵 밖 칸은 정면이 될 수 없음")
	_check(await lone.actions.sweep(alone, Vector2i(5, 4)) and alone.action_left == 0
		and lone.logs.any(func(line: String) -> bool: return "휩쓸기: 대상 0명" in line), "빈 반달도 실행하고 행동을 소비")
	_check(not lone.actions.can_use(alone, "sweep") and lone.actions.unavailable_reason(alone, "sweep") == "자원을 이미 씀",
		"빈 반달에 쓴 뒤에는 행동이 없어 비활성")
	# 휩쓸기가 없는 유닛은 행동이 남아도 쓸 대상이 없으면 할 동작이 없다.
	var idle: Fixture = _fixture([1, 0, 2, 3])
	var idle_archer: CombatUnit = idle.units[1]
	idle.units[2].cell = Vector2i(9, 9)
	idle.units[3].cell = Vector2i(9, 8)
	idle_archer.movement_left = 0
	idle_archer.bonus_action_left = 0
	_check(idle.turns.current_unit == idle_archer and idle_archer.action_left > 0
		and not idle.actions.has_available_action(idle_archer),
		"행동이 남아도 대상이 없는 궁수는 할 동작 없음")


func _test_holy_veil() -> void:
	var f: Fixture = _fixture()
	var warrior: CombatUnit = f.units[0]
	f.actions.dice = _dice([8], [12])
	_check(f.actions.use_self(warrior, "holy_veil"), "성스러운 장막 사용")
	_check(warrior.shield_points == 8 and warrior.shield_turns == 3 and warrior.bonus_action_left == 0,
		"건강 d12 굴림값만큼 방어막, 3턴, 보조 행동 소비")
	f.actions.call("_damage", warrior, 5)
	_check(warrior.shield_points == 3 and warrior.hit_points == 11, "방어막이 HP보다 먼저 피해를 받음")
	_check(f.logs.any(func(line: String) -> bool: return "방어막: 5 흡수" in line), "흡수한 피해를 로그에 기록")
	warrior.bonus_action_left = 1
	f.actions.dice = _dice([2], [12])
	f.actions.use_self(warrior, "holy_veil")
	_check(warrior.shield_points == 3 and warrior.shield_turns == 3, "재시전은 남은 방어막과 새 굴림 중 큰 값, 기간은 3으로 갱신")
	warrior.status_effects.append(CombatUnit.StatusEffect.new("burn", f.units[2], 2))
	f.actions.dice = _dice([4], [4])
	f.turns.turn_started.emit(warrior)
	_check(warrior.shield_turns == 0 and warrior.shield_points == 0 and warrior.hit_points == 10,
		"화상 틱도 방어막이 먼저 받고, 다 흡수하면 방어막이 사라짐")
	warrior.status_effects.clear()
	warrior.bonus_action_left = 1
	f.actions.dice = _dice([9], [12])
	f.actions.use_self(warrior, "holy_veil")
	f.turns.turn_started.emit(warrior)
	_check(warrior.shield_turns == 2 and warrior.shield_points == 9, "시전자 턴 시작마다 기간이 1 줄어듦")
	for count: int in range(2):
		f.turns.turn_started.emit(warrior)
	_check(warrior.shield_points == 0 and warrior.shield_turns == 0, "3턴이 지나면 방어막 소멸")
	warrior.bonus_action_left = 1
	f.actions.dice = _dice([6], [12])
	f.actions.use_self(warrior, "holy_veil")
	f.actions.grid.pits = [Vector2i(4, 5)]
	f.actions.call("_land", warrior, Vector2i(4, 5))
	_check(warrior.hit_points == 0, "낙사는 피해가 아니라 방어막이 받지 않음")
	# 바위 미리보기도 방어막을 셈해 실행과 같은 생존·밀림을 보인다.
	var rocky: Fixture = _fixture()
	var target: CombatUnit = rocky.units[3]
	target.cell = Vector2i(4, 6)
	target.hit_points = 3
	target.shield_points = 5
	target.shield_turns = 3
	var rock: CombatGrid.Prop = rocky.actions.create_prop(Vector2i(4, 5), "rock")
	var preview: CombatActions.RockRoll = rocky.actions.preview_rock(rocky.units[0], rock)
	var pushed: bool = preview.steps.any(func(step: CombatActions.RockStep) -> bool: return step.target == target and step.push)
	rocky.actions.dice = _dice([], [])
	rocky.actions.attack_prop(rocky.units[0], rock)
	_check(pushed and target.hit_points == 3 and target.shield_points == 1 and target.cell != Vector2i(4, 6),
		"바위 충돌 피해 4를 방어막이 받고, 미리보기도 살아남아 밀리는 것으로 보임")


func _test_battle_cry() -> void:
	var f: Fixture = _fixture()
	var warrior: CombatUnit = f.units[0]
	var archer: CombatUnit = f.units[1]
	f.actions.dice = _dice([5], [8])
	_check(f.actions.use_self(warrior, "battle_cry"), "전투의 함성 사용")
	_check(warrior.action_left == 0 and warrior.battle_cry_left == 0, "행동과 전투마다 횟수 소비")
	_check(warrior.battle_cry_bonus == 5 and archer.battle_cry_bonus == 5 and archer.battle_cry_turns == 2
		and archer.battle_cry_source == warrior and f.units[2].battle_cry_bonus == 0,
		"의지 d8을 한 번 굴려 살아 있는 모든 아군(자신 포함)에게 같은 값, 2턴")
	_check(archer.get_hit_bonus() == 5 and archer.get_attack_bonus() == 0, "명중 가산에만 더하고 DC용 공격 가산은 그대로")
	var preview: CombatChecks.AttackPreview = f.actions.grid.attack_preview(archer, f.units[3])
	_check(is_equal_approx(preview.chance, CombatChecks.hit_chance(20, 5, f.units[3].get_armor_class(), preview.mode)),
		"명중률 미리보기에 전투의 함성 반영")
	f.turns.select_unit(archer)
	f.actions.dice = _dice([4, 3], [20, 20])
	await f.actions.attack(archer, f.units[3])
	_check(f.actions.last_attack.total == 9, "명중굴림 합계에 전투의 함성 더함")
	f.turns.turn_started.emit(warrior)
	_check(archer.battle_cry_turns == 1 and archer.battle_cry_bonus == 5, "시전자 턴 시작마다 1턴 줄어듦")
	f.turns.turn_started.emit(archer)
	_check(archer.battle_cry_turns == 1, "대상의 턴 시작에는 줄지 않음")
	f.turns.turn_started.emit(warrior)
	_check(archer.battle_cry_turns == 0 and archer.get_hit_bonus() == 0 and archer.battle_cry_source == null,
		"2턴 뒤 소멸")


func _test_battle_cry_clock_slot() -> void:
	# 전사가 자기 턴에 쓰러지면 그 자리는 이번 순환에서 이미 지나갔다.
	var own: Fixture = _fixture([0, 1, 4, 2, 3], true)
	var warrior: CombatUnit = own.units[0]
	var archer: CombatUnit = own.units[1]
	var second: CombatUnit = own.units[4]
	own.actions.dice = _dice([6], [8])
	own.actions.use_self(warrior, "battle_cry")
	own.actions.incapacitate(warrior)
	_check(archer.battle_cry_turns == 2 and archer.battle_cry_bonus == 6, "시전자가 쓰러져도 전투의 함성 유지")
	# 다음 궁수가 바로 턴을 시작하지만 이번 순환의 전사 자리는 이미 지났으므로 줄이지 않는다.
	_check(own.turns.current_unit == archer and archer.battle_cry_turns == 2
		and own.actions.save_state().clock_slots == [[0, 1, false]],
		"쓰러진 전사의 턴 자리를 다음 유닛 앞의 시계 슬롯으로 보관하고 이미 지난 자리는 줄이지 않음")
	own.actions.incapacitate(archer)
	_check(own.turns.current_unit == second and second.battle_cry_turns == 2
		and own.actions.save_state().clock_slots == [[0, 4, false]], "슬롯 뒤 유닛이 쓰러지면 그다음 유닛으로 옮김")
	own.turns.turn_started.emit(second)
	_check(second.battle_cry_turns == 1, "다음 순환부터 슬롯 자리마다 1턴 줄어듦")
	own.turns.turn_started.emit(second)
	_check(second.battle_cry_turns == 0 and own.actions.save_state().clock_slots.is_empty(), "효과가 끝나면 슬롯 제거")
	# 적 턴에 쓰러지면 이번 순환의 자기 자리가 아직 오지 않았다.
	var enemy: Fixture = _fixture([2, 3, 0, 1])
	enemy.units[0].battle_cry_bonus = 3
	enemy.units[0].battle_cry_turns = 2
	enemy.units[0].battle_cry_source = enemy.units[0]
	enemy.units[1].battle_cry_bonus = 3
	enemy.units[1].battle_cry_turns = 2
	enemy.units[1].battle_cry_source = enemy.units[0]
	enemy.actions.incapacitate(enemy.units[0])
	_check(enemy.actions.save_state().clock_slots == [[0, 1, false]], "적 턴에 쓰러진 시전자의 자리는 아직 지나지 않음")
	enemy.turns.turn_started.emit(enemy.units[1])
	_check(enemy.units[1].battle_cry_turns == 1, "다음 유닛 턴 시작 직전에 쓰러진 시전자의 자리가 줄임")
	# 순서의 마지막인 전사가 자기 턴에 쓰러지면 다음 유닛은 처음으로 돈다. 그 유닛의 다음 시작이 이미 지난 자리다.
	var last: Fixture = _fixture([2, 3, 1, 0])
	last.turns.end_turn()
	last.turns.end_turn()
	last.turns.select_unit(last.units[0])
	last.actions.dice = _dice([5], [8])
	last.actions.use_self(last.units[0], "battle_cry")
	last.actions.incapacitate(last.units[0])
	_check(last.actions.save_state().clock_slots == [[0, 2, true]], "순서 끝의 시전자는 처음 유닛 앞 슬롯에 이미 지난 자리로 보관")
	last.turns.end_turn()
	_check(last.turns.current_unit == last.units[2] and last.turns.round_number == 2 and last.units[1].battle_cry_turns == 2,
		"다음 라운드 첫 유닛의 시작은 이미 줄인 자리라 건너뜀")
	last.turns.turn_started.emit(last.units[2])
	_check(last.units[1].battle_cry_turns == 1, "그다음 순환부터 줄어듦")
	# 그 슬롯의 기준 유닛도 같은 라운드에 쓰러지면, 옮긴 유닛의 다음 라운드 시작도 이미 줄인 자리 바로 뒤다.
	var wrap: Fixture = _fixture([2, 3, 1, 0])
	wrap.turns.end_turn()
	wrap.turns.end_turn()
	wrap.turns.select_unit(wrap.units[0])
	wrap.actions.dice = _dice([5], [8])
	wrap.actions.use_self(wrap.units[0], "battle_cry")
	wrap.actions.incapacitate(wrap.units[0])
	wrap.actions.incapacitate(wrap.units[2])
	_check(wrap.actions.save_state().clock_slots == [[0, 3, true]], "이미 시작한 기준 유닛이 쓰러져도 건너뛸 자리를 유지")
	wrap.turns.end_turn()
	_check(wrap.turns.current_unit == wrap.units[3] and wrap.turns.round_number == 2
		and wrap.units[1].battle_cry_turns == 2, "옮긴 유닛의 다음 라운드 시작은 이미 줄인 자리라 건너뜀")
	# 기존 상태 이상은 시전자 전투 불능에서 해제한다.
	var burn: Fixture = _fixture()
	burn.units[0].status_effects.append(CombatUnit.StatusEffect.new("burn", burn.units[2], 2))
	burn.actions.incapacitate(burn.units[2])
	_check(burn.units[0].status_effects.is_empty() and burn.actions.save_state().clock_slots.is_empty(),
		"기존 화상은 시전자 전투 불능에 해제하고 시계 슬롯을 쓰지 않음")
	_test_clock_slot_with_spawn()
	_test_clock_slot_in_group()


## archer에게 caster의 전투의 함성 2턴을 건다.
func _give_battle_cry(caster: CombatUnit, archer: CombatUnit) -> void:
	archer.battle_cry_bonus = 3
	archer.battle_cry_turns = 2
	archer.battle_cry_source = caster


## 엄마 거미가 자기 턴에 새끼를 낳는다. 새끼는 units의 끝에 붙는다.
func _spawn(f: Fixture, mother: CombatUnit) -> CombatUnit:
	f.actions.dice = _dice([1], [f.actions.grid.empty_neighbors(mother.cell).size()])
	_check(f.actions.spawn_spiderling(mother), "엄마 거미가 새끼를 낳음")
	_created.append(f.units.back())
	return f.units.back()


## 소환 유닛이 쓰러진 시전자의 자리 바로 뒤에 끼어도 순환마다 그 자리에서 한 번 줄인다 (#427 1·2번).
func _test_clock_slot_with_spawn() -> void:
	# 슬롯 (전사, 엄마)에서 엄마가 새끼를 낳으면 쓰러진 자리 바로 뒤는 새끼다.
	var moved: Fixture = _fixture([1, 0, 2, 3])
	moved.units[2].kind = CombatUnit.Kind.MOTHER_SPIDER
	moved.turns.end_turn()
	moved.turns.end_turn()
	_give_battle_cry(moved.units[0], moved.units[1])
	moved.actions.incapacitate(moved.units[0])
	var child: CombatUnit = _spawn(moved, moved.units[2])
	_check(moved.actions.save_state().clock_slots == [[0, 4, false]], "새끼를 낳으면 엄마에 걸린 슬롯을 새끼로 옮김")
	moved.turns.end_turn()
	moved.turns.end_turn()
	moved.turns.end_turn()
	_check(moved.turns.current_unit == child and moved.units[1].battle_cry_turns == 1,
		"다음 라운드에 새끼의 턴 시작 직전에 쓰러진 자리가 줄임")
	# 생성 라운드의 새끼는 이번 순환에 시작하지 않으므로 그 앞의 시전자가 쓰러져도 건너뛸 자리가 아니다.
	var own: Fixture = _fixture([1, 0, 2, 3])
	own.units[2].kind = CombatUnit.Kind.MOTHER_SPIDER
	own.turns.end_turn()
	own.turns.end_turn()
	_give_battle_cry(own.units[0], own.units[1])
	child = _spawn(own, own.units[2])
	own.actions.incapacitate(own.units[0])
	_check(own.actions.save_state().clock_slots == [[0, 4, false]], "생성 라운드 새끼 앞의 쓰러진 자리는 지난 자리가 아님")
	own.turns.end_turn()
	own.turns.end_turn()
	own.turns.end_turn()
	_check(own.turns.current_unit == child and own.units[1].battle_cry_turns == 1, "다음 라운드 새끼의 턴 시작에 줄임")
	# 기준 유닛이 쓰러져 생성 라운드 새끼로 옮겨질 때도 같다.
	var anchor: Fixture = _fixture([1, 0, 4, 2, 3], true)
	anchor.units[2].kind = CombatUnit.Kind.MOTHER_SPIDER
	anchor.turns.end_turn()
	anchor.turns.end_turn()
	anchor.turns.end_turn()
	_give_battle_cry(anchor.units[0], anchor.units[1])
	anchor.actions.incapacitate(anchor.units[0])
	child = _spawn(anchor, anchor.units[2])
	anchor.actions.incapacitate(anchor.units[4])
	_check(anchor.actions.save_state().clock_slots == [[0, 5, false]], "생성 라운드 새끼로 옮긴 슬롯은 건너뛰지 않음")
	anchor.turns.end_turn()
	anchor.turns.end_turn()
	anchor.turns.end_turn()
	_check(anchor.turns.current_unit == child and anchor.units[1].battle_cry_turns == 1, "옮긴 새끼의 다음 라운드 턴 시작에 줄임")


## 같은 묶음에서 뒤 유닛을 먼저 조작한 뒤 시전자가 자기 턴 전에 쓰러져도 이번 순환 몫을 줄인다 (#427 3번).
func _test_clock_slot_in_group() -> void:
	var f: Fixture = _fixture([4, 0, 1, 2, 3], true)
	_give_battle_cry(f.units[0], f.units[1])
	f.turns.select_unit(f.units[1])
	f.actions.incapacitate(f.units[0])
	_check(f.units[1].battle_cry_turns == 1 and f.actions.save_state().clock_slots == [[0, 1, false]],
		"기준 유닛이 이미 시작했으면 시전자의 이번 순환 몫을 바로 줄임")
	f.turns.turn_started.emit(f.units[1])
	_check(f.units[1].battle_cry_turns == 0, "다음 순환의 기준 유닛 턴 시작에 다시 줄임")


func _test_phalanx() -> void:
	var f: Fixture = _fixture()
	var grid: CombatGrid = f.actions.grid
	var warrior: CombatUnit = f.units[0]
	var archer: CombatUnit = f.units[1]
	_check(grid.phalanx_bonus(archer) == 1 and grid.armor_class(archer) == archer.get_armor_class() + 1,
		"전사와 인접한 아군 AC +1")
	_check(grid.phalanx_bonus(warrior) == 1, "인접 아군이 있으면 전사도 AC +1")
	_check(grid.phalanx_bonus(f.units[2]) == 0, "적에게는 없음")
	var preview: CombatChecks.AttackPreview = grid.attack_preview(f.units[2], warrior)
	_check(is_equal_approx(preview.chance, CombatChecks.hit_chance(10, 3, warrior.get_armor_class() + 1, preview.mode)),
		"적의 명중률에 팔랑크스 AC 반영")
	var second: CombatUnit = CombatUnit.new()
	second.kind = CombatUnit.Kind.ARCHER
	second.cell = Vector2i(4, 3)
	second.hit_points = second.get_max_hit_points()
	_created.append(second)
	f.units.append(second)
	_check(grid.phalanx_bonus(warrior) == 1 and grid.phalanx_bonus(second) == 1, "인접 아군이 여럿이어도 +1, 중첩 없음")
	f.units.erase(second)
	grid.heights[archer.cell] = 2
	_check(grid.phalanx_bonus(archer) == 0 and grid.phalanx_bonus(warrior) == 0, "높이 차가 2 이상이면 인접 아님")
	grid.heights.erase(archer.cell)
	_check(f.actions.apply_status(f.units[3], warrior, "stun"), "적이 전사를 기절시킴")
	_check(grid.phalanx_bonus(archer) == 0 and grid.phalanx_bonus(warrior) == 0, "전사가 기절하면 해제")
	f.actions.call("_on_turn_started", f.units[3])
	_check(not warrior.is_stunned and grid.phalanx_bonus(archer) == 1 and grid.phalanx_bonus(warrior) == 1,
		"기절을 건 적의 턴 시작에 기절이 풀리면 인접 아군이 있는 동안 다시 켜짐 (#407 답 5b)")
	archer.cell = Vector2i(2, 4)
	_check(grid.phalanx_bonus(archer) == 0 and grid.phalanx_bonus(warrior) == 0, "떨어지면 바로 꺼지는 상시 효과")
	archer.cell = Vector2i(3, 4)
	f.actions.incapacitate(warrior)
	_check(grid.phalanx_bonus(archer) == 0, "전사가 전투 불능이면 사라짐")


func _test_save_state() -> void:
	var f: Fixture = _fixture([0, 1, 2, 3], true)
	f.actions.dice = _dice([7], [12])
	f.actions.use_self(f.units[0], "holy_veil")
	f.units[0].action_left = 1
	f.actions.dice = _dice([4], [8])
	f.actions.use_self(f.units[0], "battle_cry")
	var saved: Array = f.units.map(func(unit: CombatUnit) -> Dictionary: return unit.save_state(f.units))
	_check(saved.all(func(data: Dictionary) -> bool: return f.units[0].is_valid_state(data, 5, Vector2i(10, 10))),
		"방어막과 전투의 함성을 담은 유닛 저장은 유효")
	var restored: CombatUnit = CombatUnit.new()
	_created.append(restored)
	restored.load_state(saved[1], f.units)
	_check(restored.battle_cry_bonus == 4 and restored.battle_cry_turns == 2 and restored.battle_cry_source == f.units[0],
		"전투의 함성과 시전자를 되돌림")
	var warrior_copy: CombatUnit = CombatUnit.new()
	_created.append(warrior_copy)
	warrior_copy.load_state(saved[0], f.units)
	_check(warrior_copy.shield_points == 7 and warrior_copy.shield_turns == 3, "방어막을 되돌림")
	for broken: Dictionary in [{"shield_turns": 4}, {"shield_points": 0}, {"battle_cry_source": -1},
			{"battle_cry_turns": 3}, {"battle_cry_bonus": 0}]:
		var data: Dictionary = (saved[0] as Dictionary).duplicate()
		data.merge(broken, true)
		_check(not f.units[0].is_valid_state(data, 5, Vector2i(10, 10)), "깨진 유닛 효과 저장 거부: " + str(broken))
	f.actions.incapacitate(f.units[0])
	var state: Dictionary = f.actions.save_state()
	_check(CombatActions.is_valid_state(state, 5, Vector2i(10, 10)), "시계 슬롯을 담은 전투 저장은 유효")
	var loaded: Fixture = _fixture([0, 1, 2, 3], true)
	loaded.actions.load_state(state)
	_check(loaded.actions.save_state().clock_slots == [[0, 1, false]], "시계 슬롯을 되돌림")
	for slots: Array in [[[0, 0, true]], [[0, 9, true]], [[0, 1, 1]], [[0, 1]], [[0, 1, false], [0, 2, false]]]:
		var broken: Dictionary = state.duplicate()
		broken.clock_slots = slots
		_check(not CombatActions.is_valid_state(broken, 5, Vector2i(10, 10)), "깨진 시계 슬롯 거부: " + str(slots))
