extends SceneTree
## 궁수 재디자인 1·5단계(#528): 사거리·피해, 새 스킬(무빙샷·애기살 급조·활 후려치기), 옛 스킬 삭제, 저장, 회전회오리 내성.

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
		push_error("Combat archer: test timeout")
		quit(1)
	)
	_run.call_deferred()


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error(message)


## 아군 궁수(3,4)·전사(3,6), 적 야만인(5,4)·풋내기 궁수(7,4). 순서는 order다(기본은 궁수부터).
func _fixture(order: Array[int] = [0, 1, 2, 3]) -> Fixture:
	var f: Fixture = Fixture.new()
	var kinds: Array[CombatUnit.Kind] = [CombatUnit.Kind.ARCHER, CombatUnit.Kind.WARRIOR, CombatUnit.Kind.WARRIOR,
		CombatUnit.Kind.ARCHER]
	var cells: Array[Vector2i] = [Vector2i(3, 4), Vector2i(3, 6), Vector2i(5, 4), Vector2i(7, 4)]
	for index: int in range(4):
		var unit: CombatUnit = CombatUnit.new()
		unit.kind = kinds[index]
		unit.is_ally = index < 2
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
	await _test_range_and_damage()
	_test_skill_ownership()
	await _test_spin_save()
	for unit: CombatUnit in _created:
		unit.free()
	var dice_problems: Array[String] = ScriptedDice.finish()
	_check(dice_problems.is_empty(), "준비한 주사위 값을 요청대로 모두 굴림 " + str(dice_problems))
	print("Combat archer: %d checks, %d failures" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)


func _test_range_and_damage() -> void:
	var f: Fixture = _fixture()
	var archer: CombatUnit = f.units[0]
	var target: CombatUnit = f.units[3]
	_check(archer.get_attack_range() == 4 and target.get_attack_range() == 6, "아군 궁수 사거리 4, 풋내기 궁수는 6 유지")
	_check(f.actions.can_target(archer, target, "attack"), "거리 4의 적은 기본 공격 대상")
	target.cell = Vector2i(8, 4)
	_check(not f.actions.can_target(archer, target, "attack"), "거리 5의 적은 사거리 밖")
	target.cell = Vector2i(7, 4)
	_check(archer.get_damage_bonus() == 0 and target.get_damage_bonus() == 1, "아군 궁수 피해 보정 0, 풋내기 궁수 +1 유지")
	_check("1~4칸" in CombatActionRules.effect(archer, "attack") and "1~4칸" in CombatActionRules.details(archer, "attack"),
		"기본 공격 호버의 사거리 1~4칸")
	f.actions.dice = _dice([15, 7], [20, 20])
	_check(await f.actions.attack(archer, target), "거리 4의 적을 공격")
	_check(target.hit_points == 14 - 7, "피해 = 솜씨 d20 굴림 7 + 레벨 0 + 기타 가산치 0")
	var armed: Fixture = _fixture()
	armed.units[0].weapon = {"stats": {"damage_bonus": 2}}
	armed.actions.dice = _dice([15, 7], [20, 20])
	await armed.actions.attack(armed.units[0], armed.units[3])
	_check(armed.units[3].hit_points == 14 - 9, "장비 피해 가산은 더함")


func _test_skill_ownership() -> void:
	var f: Fixture = _fixture()
	var archer: CombatUnit = f.units[0]
	var warrior: CombatUnit = f.units[1]
	var novice: CombatUnit = f.units[3]
	for action: String in ["mark", "shock", "disengage"]:
		_check(not CombatActionRules.belongs_to(archer, action), "아군 궁수의 옛 스킬 삭제: " + action)
	for action: String in ["mark", "shock"]:
		_check(action not in CombatActionRules.NAMES and action not in CombatActionRules.USE_COUNTERS
			and not CombatActionRules.GROUPS.any(func(group: Array) -> bool: return action in group), "옛 스킬 정의 삭제: " + action)
	for action: String in ["aegisal", "bow_bash", "moving_shot"]:
		_check(CombatActionRules.belongs_to(archer, action), "아군 궁수의 새 스킬: " + action)
		_check(not CombatActionRules.belongs_to(warrior, action), "아군 전사에게는 없음: " + action)
		_check(not CombatActionRules.belongs_to(novice, action), "풋내기 궁수에게는 없음: " + action)
	_check(CombatActionRules.resource_of("aegisal") == CombatUnit.TurnResource.BONUS_ACTION
		and CombatActionRules.resource_of("bow_bash") == CombatUnit.TurnResource.BONUS_ACTION, "두 스킬은 보조 행동")
	_check(CombatActionRules.uses_left(archer, "aegisal") == -1 and CombatActionRules.uses_left(archer, "bow_bash") == -1,
		"두 스킬은 무제한")
	_check("moving_shot" in CombatActionRules.PASSIVES, "무빙샷은 패시브 칸")
	_check(CombatActionRules.belongs_to(novice, "disengage") and CombatActionRules.uses_left(novice, "disengage") == 2,
		"풋내기 궁수의 물러서며 쏘기 2회 유지")


## 고철로봇-3000(5,4)과 인접한 전사(4,4)가 민첩 d8로 내성굴림한다. DC는 힘 d12 표준값 7 + 공격 가산 3 = 10 그대로다.
func _test_spin_save() -> void:
	var f: Fixture = _fixture([2, 0, 1, 3])
	var robot: CombatUnit = f.units[2]
	var warrior: CombatUnit = f.units[1]
	robot.kind = CombatUnit.Kind.SCRAP_ROBOT_3000
	robot.hit_points = robot.get_max_hit_points()
	warrior.cell = Vector2i(4, 4)
	f.units[0].cell = Vector2i(0, 0)
	_check(CombatActionRules.SAVE_ABILITIES["spin"] == CombatUnit.Ability.AGILITY, "회전회오리 내성 능력치는 민첩")
	_check(CombatActionRules.save_dc(robot, "spin") == 10, "회전회오리 DC는 힘 기준 10 그대로")
	_check(CombatActionRules.SAVE_ABILITIES["pull"] == CombatUnit.Ability.STRENGTH
		and CombatActionRules.SAVE_ABILITIES["shove"] == CombatUnit.Ability.STRENGTH, "만능팔·밀치기는 힘 유지")
	_check(is_equal_approx(CombatActionRules.save_chance(robot, warrior, "spin"),
		CombatChecks.save_chance(8, 0, 10, CombatChecks.RollMode.NORMAL)), "내성 성공률은 대상의 민첩 d8")
	var details: String = CombatActionRules.details(robot, "spin", f.units)
	_check("대상의 민첩 내성 대 DC 10" in details and "각자 민첩 내성굴림" in CombatActionRules.effect(robot, "spin"),
		"회전회오리 호버 문구: " + details)
	_check("대상의 힘 내성" in CombatActionRules.details(robot, "pull"), "만능팔 호버는 힘 내성")
	# 민첩 d8 8은 DC 10에 실패해 피해 힘 d12 6 + 2를 모두 받는다.
	f.actions.dice = _dice([8, 6], [8, 12])
	_check(await f.actions.spin(robot), "회전회오리 사용")
	_check(warrior.hit_points == 11 - 8, "실패하면 피해 전부")
