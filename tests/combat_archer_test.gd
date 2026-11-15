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
	await _test_aegisal()
	await _test_bow_bash()
	await _test_moving_shot()
	_test_reflex_rules()
	await _test_reflex_dodge()
	await _test_reflex_conditions()
	await _test_reflex_movement()
	await _test_reflex_oil()
	await _test_reflex_next_turn()
	await _test_reflex_replay()
	_test_trick_attribute()
	await _test_trick_arrow()
	await _test_firework_arrow()
	_test_arrow_usability()
	_test_firework_uses_and_save()
	_test_stage_reset()
	_test_save_state()
	await _test_battle_save()
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


## 애기살 급조: 보조 행동으로 +2(누적), 기본 공격마다 1발을 쓰고 피해 굴림 2번 중 높은 값.
func _test_aegisal() -> void:
	var f: Fixture = _fixture()
	var archer: CombatUnit = f.units[0]
	var target: CombatUnit = f.units[3]
	_check(f.actions.can_use(archer, "aegisal") and "애기살 0발 남음" in CombatActionRules.details(archer, "aegisal"),
		"보조 행동이 있으면 애기살 급조 사용 가능")
	_check(f.actions.use_self(archer, "aegisal") and archer.aegisal_left == 2 and archer.bonus_action_left == 0
		and archer.action_left == 1, "애기살 급조는 보조 행동을 쓰고 2발")
	_check(not f.actions.can_use(archer, "aegisal"), "보조 행동을 쓰면 비활성")
	archer.bonus_action_left = 1
	f.actions.use_self(archer, "aegisal")
	_check(archer.aegisal_left == 4, "다시 쓰면 누적해 4발, 상한 없음")
	_check("애기살 4발" in CombatActionRules.details(archer, "attack"), "기본 공격 호버에 남은 애기살")
	# 명중 15, 피해 굴림 3과 9 중 높은 9.
	f.actions.dice = _dice([15, 3, 9], [20, 20, 20])
	await f.actions.attack(archer, target)
	_check(target.hit_points == 14 - 9 and archer.aegisal_left == 3 and f.actions.last_damage_rolls == [3, 9],
		"애기살 기본 공격은 피해 굴림 두 번 중 높은 값이고 1발을 씀")
	_check(f.logs.any(func(line: String) -> bool: return "애기살" in line and "[3, 9]" in line), "로그에 두 굴림 " + str(f.logs))
	archer.action_left = 1
	f.actions.dice = _dice([1], [20])
	await f.actions.attack(archer, target)
	_check(archer.aegisal_left == 2 and target.hit_points == 5, "빗나가도 1발을 씀")
	var crate: CombatGrid.Prop = f.actions.create_prop(Vector2i(3, 3), "crate")
	archer.action_left = 1
	f.actions.dice = _dice([2, 4], [20, 20])
	_check(f.actions.attack_prop(archer, crate) and crate.hit_points == 6 - 4 and archer.aegisal_left == 1,
		"나무 상자 공격도 1발을 쓰고 피해 굴림 두 번 중 높은 값")
	var rock: CombatGrid.Prop = f.actions.create_prop(Vector2i(2, 4), "rock")
	archer.action_left = 1
	f.actions.dice = _dice([], [])
	_check(f.actions.attack_prop(archer, rock) and archer.aegisal_left == 0, "바위 공격은 굴림 없이 1발을 씀")
	var plain: Fixture = _fixture()
	plain.actions.dice = _dice([15, 7], [20, 20])
	await plain.actions.attack(plain.units[0], plain.units[3])
	_check(plain.actions.last_damage_rolls == [7] and plain.units[0].aegisal_left == 0, "애기살이 없으면 한 번 굴림")


## 활 후려치기: 보조 행동, 인접한 적에게 힘 d6 명중·피해, 명중하면 1칸 밀침(내성 없음).
func _test_bow_bash() -> void:
	var f: Fixture = _fixture()
	var archer: CombatUnit = f.units[0]
	var barbarian: CombatUnit = f.units[2]
	barbarian.cell = Vector2i(4, 4)
	archer.aegisal_left = 2
	_check(f.actions.can_target(archer, barbarian, "bow_bash") and not f.actions.can_target(archer, f.units[3], "bow_bash"),
		"인접한 적만 대상")
	var preview: CombatChecks.AttackPreview = f.actions.grid.attack_preview(archer, barbarian, "bow_bash")
	_check(preview.mode == CombatChecks.RollMode.NORMAL and is_equal_approx(preview.chance, 0.5)
		and f.actions.grid.attack_preview(archer, barbarian).mode == CombatChecks.RollMode.DISADVANTAGE,
		"근접 동작이라 옆에 적 불리가 없고 명중률은 힘 d6 대 AC 4 = 50%")
	var details: String = CombatActionRules.details(archer, "bow_bash")
	_check("힘 d6" in details and "사거리: 인접1칸" in details, "호버의 힘 d6 판정 " + details)
	f.actions.dice = _dice([4, 3], [6, 6])
	_check(await f.actions.bow_bash(archer, barbarian), "활 후려치기 실행")
	_check(barbarian.hit_points == 12 - 3 and barbarian.cell == Vector2i(5, 4), "명중하면 힘 d6 3 + 0 피해 뒤 1칸 밀침")
	_check(archer.bonus_action_left == 0 and archer.action_left == 1 and archer.aegisal_left == 2,
		"보조 행동만 쓰고 애기살은 쓰지 않음")
	var blocked: Fixture = _fixture()
	blocked.units[2].cell = Vector2i(4, 4)
	blocked.actions.create_prop(Vector2i(5, 4), "crate")
	blocked.actions.dice = _dice([4, 3], [6, 6])
	await blocked.actions.bow_bash(blocked.units[0], blocked.units[2])
	_check(blocked.units[2].hit_points == 9 and blocked.units[2].cell == Vector2i(4, 4), "밀려날 칸이 막히면 피해만")
	var killed: Fixture = _fixture()
	killed.units[2].cell = Vector2i(4, 4)
	killed.units[2].hit_points = 2
	killed.actions.dice = _dice([4, 3], [6, 6])
	await killed.actions.bow_bash(killed.units[0], killed.units[2])
	_check(killed.units[2].hit_points == 0 and killed.units[2].cell == Vector2i(4, 4), "쓰러지면 밀지 않음")
	var missed: Fixture = _fixture()
	missed.units[2].cell = Vector2i(4, 4)
	missed.actions.dice = _dice([1], [6])
	await missed.actions.bow_bash(missed.units[0], missed.units[2])
	_check(missed.units[2].hit_points == 12 and missed.units[2].cell == Vector2i(4, 4)
		and missed.units[0].bonus_action_left == 0, "빗나가면 피해·밀침 없이 보조 행동만 씀")
	var fall: Fixture = _fixture()
	fall.units[2].cell = Vector2i(4, 4)
	fall.actions.grid.heights[Vector2i(3, 4)] = 3
	fall.actions.grid.heights[Vector2i(4, 4)] = 3
	fall.actions.dice = _dice([4, 3], [6, 6])
	await fall.actions.bow_bash(fall.units[0], fall.units[2])
	_check(fall.units[2].cell == Vector2i(5, 4) and fall.units[2].hit_points == 12 - 3 - 2,
		"높이 차 3 아래로 밀리면 낙하 피해 2")


## 무빙샷: 이번 턴 첫 행동 원거리 공격 뒤 인접 빈 칸으로 1칸 도약. 이동력·기회 공격 없음.
func _test_moving_shot() -> void:
	var f: Fixture = _fixture()
	var archer: CombatUnit = f.units[0]
	var barbarian: CombatUnit = f.units[2]
	barbarian.cell = Vector2i(3, 3)
	barbarian.reaction_left = 1
	_check(f.actions.moving_shot_cells(archer).is_empty(), "공격 전에는 도약할 칸이 없음")
	# 인접한 야만인 때문에 불리라 명중굴림을 두 번 굴린다.
	f.actions.dice = _dice([15, 15, 2], [20, 20, 20])
	await f.actions.attack(archer, f.units[3])
	var cells: Array[Vector2i] = f.actions.moving_shot_cells(archer)
	_check(archer.moving_shot_ready and cells.size() == 3 and Vector2i(2, 4) in cells and Vector2i(4, 4) in cells
		and Vector2i(3, 5) in cells and Vector2i(3, 3) not in cells, "첫 기본 공격 뒤 인접 빈 칸만 " + str(cells))
	_check(not await f.actions.moving_shot(archer, Vector2i(5, 4)), "인접하지 않은 칸은 거부")
	_check(await f.actions.moving_shot(archer, Vector2i(2, 4)), "무빙샷 도약")
	_check(archer.cell == Vector2i(2, 4) and archer.movement_left == 6 and archer.bonus_action_left == 1,
		"이동력과 보조 행동을 쓰지 않음")
	_check(barbarian.reaction_left == 1 and archer.hit_points == archer.get_max_hit_points()
		and f.actions.pending_reactor == null, "인접 적을 벗어나도 기회 공격 없음")
	_check(not archer.moving_shot_ready and f.actions.moving_shot_cells(archer).is_empty()
		and not await f.actions.moving_shot(archer, Vector2i(1, 4)), "한 번 쓰면 끝")
	archer.action_left = 1
	f.units[3].cell = Vector2i(6, 4)
	f.actions.dice = _dice([15, 2], [20, 20])
	_check(await f.actions.attack(archer, f.units[3]) and not archer.moving_shot_ready,
		"이번 턴 첫 공격이 아니면 켜지지 않음")
	archer.begin_turn()
	_check(not archer.moving_shot_ready and not archer.moving_shot_spent, "자기 턴 시작에 해제")
	var other: Fixture = _fixture()
	other.actions.dice = _dice([15, 2], [20, 20])
	await other.actions.attack(other.units[0], other.units[3])
	_check(other.units[0].moving_shot_ready, "다른 동작 전에는 남음")
	other.actions.use_self(other.units[0], "aegisal")
	_check(not other.units[0].moving_shot_ready, "다른 동작을 실행하면 사라짐")
	var crate: Fixture = _fixture()
	var prop: CombatGrid.Prop = crate.actions.create_prop(Vector2i(3, 2), "crate")
	crate.actions.dice = _dice([2], [20])
	crate.actions.attack_prop(crate.units[0], prop)
	_check(crate.units[0].moving_shot_ready, "나무 상자 기본 공격 뒤에도 도약 가능")
	var last: Fixture = _fixture()
	last.actions.incapacitate(last.units[2])
	last.units[3].hit_points = 1
	last.actions.dice = _dice([15, 2], [20, 20])
	await last.actions.attack(last.units[0], last.units[3])
	_check(last.actions.is_over() and not last.units[0].moving_shot_ready, "전투를 끝낸 공격 뒤에는 켜지지 않음")
	var enemy: Fixture = _fixture([3, 0, 1, 2])
	enemy.actions.dice = _dice([1], [10])
	await enemy.actions.attack(enemy.units[3], enemy.units[0])
	_check(not enemy.units[3].moving_shot_ready, "풋내기 궁수에게는 무빙샷이 없음")

## 지능 d6 눈 → 속성 구간 (궁수 문서 장난스러운 화살).
func _test_trick_attribute() -> void:
	var got: Array[String] = []
	for face: int in range(1, 7):
		got.append(CombatOil.trick_attribute(face))
	_check(got == ["", "water", "water", "fire", "fire", "fire"], "지능 눈 1 삐끗, 2~3 물, 4~6 화염: " + str(got))


func _burns(unit: CombatUnit) -> int:
	return unit.get_status_count("burn")


## 장난스러운 화살: 행동 1, 칸 조준, 지능 d6 눈이 속성과 피해, 속성은 명중과 무관하게 칸에, 유닛 효과는 명중해야.
func _test_trick_arrow() -> void:
	var f: Fixture = _fixture()
	var archer: CombatUnit = f.units[0]
	var target: CombatUnit = f.units[3]
	archer.weapon = {"stats": {"damage_bonus": 4}}
	# 화염(눈 5): 마법 굴림 d6, 명중 d20 15. 피해는 눈 5 그대로(장비 피해 가산 없음), 화상 1중첩.
	f.actions.dice = _dice([5, 15], [6, 20])
	_check(await f.actions.trick_arrow(archer, Vector2i(7, 4)), "장난스러운 화살을 적 칸에 쏨")
	_check(target.hit_points == 14 - 5 and _burns(target) == 1 and f.actions.last_damage == 5,
		"화염 명중: 피해는 굴림 눈 5, 화상 1중첩")
	_check(archer.action_left == 0 and archer.bonus_action_left == 1 and archer.moving_shot_ready,
		"행동 1을 쓰고 무빙샷이 켜짐")
	_check(not f.actions.can_use(archer, "trick_arrow"), "행동이 없으면 쓸 수 없음")
	# 물(눈 3): 피해 3, 화상 모두 제거.
	archer.action_left = 1
	f.actions.apply_status(archer, target, "burn")
	f.actions.dice = _dice([3, 15], [6, 20])
	await f.actions.trick_arrow(archer, Vector2i(7, 4))
	_check(target.hit_points == 9 - 3 and _burns(target) == 0, "물 명중: 피해 3, 화상 모두 제거")
	# 삐끗(눈 1): 피해 1, 속성 없음. 기름은 그대로.
	archer.action_left = 1
	f.actions.create_oil(archer, Vector2i(7, 4))
	f.actions.dice = _dice([1, 15], [6, 20])
	await f.actions.trick_arrow(archer, Vector2i(7, 4))
	_check(target.hit_points == 6 - 1 and _burns(target) == 0 and _oil_count(f) == 5, "삐끗: 피해 1, 장판 변화 없음")
	# 빗나가도 속성은 칸에 닿는다: 화염이 기름을 점화하고 칸 위 유닛에 화상 2중첩. 유닛 효과(피해)는 없음.
	archer.action_left = 1
	f.actions.dice = _dice([5, 2], [6, 20])
	await f.actions.trick_arrow(archer, Vector2i(7, 4))
	_check(target.hit_points == 5 and _oil_count(f) == 0 and _burns(target) == 2, "빗나가도 점화: 기름 사라지고 화상 2중첩, 피해 없음")
	# 물은 기름 칸 하나만 지운다(빈 칸이라 d6 하나만 굴림).
	archer.action_left = 1
	f.actions.create_oil(archer, Vector2i(4, 2))
	f.actions.dice = _dice([2], [6])
	await f.actions.trick_arrow(archer, Vector2i(4, 3))
	_check(_oil_count(f) == 4, "물은 닿은 칸의 기름 하나를 지움")
	# 빈 칸은 판정 없이 닿는다(d6 하나만 굴림).
	var g: Fixture = _fixture()
	var shooter: CombatUnit = g.units[0]
	g.actions.create_oil(shooter, Vector2i(5, 2))
	g.actions.dice = _dice([6], [6])
	_check(await g.actions.trick_arrow(shooter, Vector2i(5, 2)) and _oil_count(g) == 0 and g.units[3].hit_points == 14,
		"빈 칸에는 명중굴림 없이 속성만 닿음")
	# 아군도 조준할 수 있다. 화염이 나오면 아군이 화상을 입는다.
	var h: Fixture = _fixture()
	var ally: CombatUnit = h.units[1]
	_check(h.actions.can_aim(h.units[0], "trick_arrow", ally.cell) and not h.actions.can_aim(h.units[0], "trick_arrow", h.units[0].cell),
		"아군 칸은 고를 수 있고 자기 칸은 못 고름")
	h.actions.dice = _dice([4, 15], [6, 20])
	await h.actions.trick_arrow(h.units[0], ally.cell)
	_check(ally.hit_points == ally.get_max_hit_points() - 4 and _burns(ally) == 1, "아군 조준: 화염이 나오면 아군이 피해와 화상")
	_check(h.units[0].aegisal_left == 0, "장난스러운 화살은 애기살과 무관")
	var armed: Fixture = _fixture()
	armed.units[0].aegisal_left = 2
	armed.actions.dice = _dice([5, 15], [6, 20])
	await armed.actions.trick_arrow(armed.units[0], Vector2i(7, 4))
	_check(armed.units[0].aegisal_left == 2 and armed.actions.last_damage == 5, "애기살을 쓰지도 소모하지도 않음")


func _oil_count(f: Fixture) -> int:
	return f.actions.get_grounds().filter(func(ground: CombatActions.Ground) -> bool: return ground.kind == "oil").size()


## 폭죽 화살: 막당 1, 반경 1 안의 모두에게 민첩 내성 DC 4, 솜씨 d20 두 번 합(레벨은 한 번), 성공 시 절반, 점화.
func _test_firework_arrow() -> void:
	var f: Fixture = _fixture()
	var archer: CombatUnit = f.units[0]
	var ally: CombatUnit = f.units[1]
	var barbarian: CombatUnit = f.units[2]
	ally.cell = Vector2i(4, 5)
	for unit: CombatUnit in f.units:
		unit.hit_points = 40
	_check(f.actions.can_aim(archer, "firework_arrow", archer.cell) and f.actions.can_aim(archer, "firework_arrow", Vector2i(7, 4))
		and not f.actions.can_aim(archer, "firework_arrow", Vector2i(8, 4)), "사거리 0~4, 자기 발밑도 고름")
	_check(f.actions.aim_area(archer, "firework_arrow", Vector2i(4, 4)).size() == 5, "반경 1은 십자 5칸")
	# 중심 (4,4): 궁수 자신, 아군 전사 (4,5), 적 (5,4)가 모두 맞는다. 유닛 순서대로 내성(민첩 d12, d8, d6)과 d20 두 번.
	# 궁수 내성 12(성공) 뒤 피해 8,6 → 14 절반 7 / 전사 내성 5(성공) 피해 4,4 → 8 절반 4 / 적 내성 1(절대실패) 피해 3,2 → 5.
	f.actions.dice = _dice([12, 8, 6, 5, 4, 4, 1, 3, 2], [12, 20, 20, 8, 20, 20, 6, 20, 20])
	_check(await f.actions.firework_arrow(archer, Vector2i(4, 4)), "폭죽 화살을 쏨")
	_check(archer.hit_points == 40 - 7 and ally.hit_points == 40 - 4 and barbarian.hit_points == 40 - 5,
		"대상마다 내성: 성공은 절반(내림), 실패는 전부. 궁수와 아군도 맞음 %d %d %d" % [archer.hit_points, ally.hit_points, barbarian.hit_points])
	_check(_burns(archer) == 0 and _burns(ally) == 0 and _burns(barbarian) == 0, "화상은 주지 않음")
	_check(archer.action_left == 0 and archer.firework_arrow_left == 0 and archer.moving_shot_ready, "행동과 막당 횟수를 쓰고 무빙샷이 켜짐")
	archer.action_left = 1
	_check(not f.actions.can_use(archer, "firework_arrow") and f.actions.unavailable_reason(archer, "firework_arrow") != "",
		"막당 횟수가 없으면 쓸 수 없음")
	# 레벨 항(장비 능력치 가감으로 모사)은 두 굴림의 합에 한 번만 더한다. 장비 피해 가산은 더하지 않는다.
	var g: Fixture = _fixture()
	var shooter: CombatUnit = g.units[0]
	shooter.weapon = {"stats": {"finesse_modifier": 3, "damage_bonus": 5}}
	var foe: CombatUnit = g.units[3]
	foe.hit_points = 40
	g.actions.dice = _dice([1, 8, 6], [10, 20, 20])
	await g.actions.firework_arrow(shooter, foe.cell)
	_check(foe.hit_points == 40 - (8 + 6 + 3) and g.actions.last_damage_rolls == [8, 6],
		"피해 = 두 굴림의 합 + 레벨 한 번(굴림마다 더하지 않음), 피해 가산 없음: " + str(40 - foe.hit_points))
	# 최소 피해 1: 내성 성공 절반 내림 최소 1.
	var m: Fixture = _fixture()
	m.units[3].hit_points = 40
	m.actions.dice = _dice([10, 2, 2], [10, 20, 20])
	await m.actions.firework_arrow(m.units[0], m.units[3].cell)
	_check(m.units[3].hit_points == 40 - 2, "성공 절반은 내림 최소 1: 합 4 → 2")
	# 기름 점화: 영역의 기름이 타고 그 위 유닛은 화상 2중첩. 화염은 피해와 별개다.
	var h: Fixture = _fixture()
	var igniter: CombatUnit = h.units[0]
	var enemy: CombatUnit = h.units[2]
	enemy.hit_points = 40
	h.actions.create_oil(igniter, Vector2i(5, 4))
	h.actions.dice = _dice([1, 3, 3], [6, 20, 20])
	await h.actions.firework_arrow(igniter, Vector2i(5, 4))
	_check(_oil_count(h) == 0 and _burns(enemy) == 2 and enemy.hit_points == 40 - 6, "기름 점화: 기름이 사라지고 화상 2중첩, 피해는 별개")
	# 궁수가 쓰러져도 남은 대상은 처리한다.
	var k: Fixture = _fixture()
	k.units[0].hit_points = 1
	k.units[1].cell = Vector2i(3, 5)
	k.units[1].hit_points = 40
	k.actions.dice = _dice([1, 5, 5, 1, 5, 5], [12, 20, 20, 8, 20, 20])
	await k.actions.firework_arrow(k.units[0], Vector2i(3, 4))
	_check(k.units[0].hit_points <= 0 and k.units[1].hit_points == 40 - 10, "시전자가 쓰러져도 남은 대상은 내성과 피해를 받음")


func _test_arrow_usability() -> void:
	var f: Fixture = _fixture()
	var archer: CombatUnit = f.units[0]
	_check(CombatActionRules.belongs_to(archer, "trick_arrow") and CombatActionRules.belongs_to(archer, "firework_arrow")
		and not CombatActionRules.belongs_to(f.units[1], "trick_arrow") and not CombatActionRules.belongs_to(f.units[1], "firework_arrow")
		and not CombatActionRules.belongs_to(f.units[3], "firework_arrow"), "두 화살은 아군 궁수만의 동작")
	_check(f.actions.can_aim(archer, "trick_arrow", Vector2i(7, 4)) and not f.actions.can_aim(archer, "trick_arrow", Vector2i(8, 4))
		and not f.actions.can_aim(archer, "trick_arrow", archer.cell) and f.actions.can_aim(archer, "trick_arrow", f.units[1].cell),
		"장난스러운 화살 사거리 1~4")
	_check(f.actions.can_use(archer, "trick_arrow") and f.actions.can_use(archer, "firework_arrow"), "행동이 있으면 사용 가능")
	archer.fallen = true
	_check(not f.actions.can_use(archer, "trick_arrow") and not f.actions.can_use(archer, "firework_arrow")
		and f.actions.unavailable_reason(archer, "trick_arrow") != "", "넘어지면 쓸 수 없음")
	archer.fallen = false
	archer.action_left = 0
	_check(not f.actions.can_use(archer, "trick_arrow") and f.actions.unavailable_reason(archer, "trick_arrow") != "", "행동이 없으면 쓸 수 없음")
	var preview: CombatChecks.AttackPreview = f.actions.grid.attack_preview(archer, f.units[1], "trick_arrow")
	_check(preview.valid_target and preview.in_range, "아군도 장난스러운 화살의 명중 미리보기 대상")
	var water: Fixture = _fixture()
	water.actions.grid.water_cells.append(water.units[0].cell)
	var wet: CombatChecks.AttackPreview = water.actions.grid.attack_preview(water.units[0], water.units[1], "trick_arrow")
	_check(wet.valid_target and wet.mode == CombatChecks.RollMode.DISADVANTAGE, "물 위에서 아군을 쏘면 불리")
	var near: Fixture = _fixture()
	near.units[2].cell = Vector2i(3, 3)
	var close: CombatChecks.AttackPreview = near.actions.grid.attack_preview(near.units[0], near.units[1], "trick_arrow")
	_check(close.valid_target and close.mode == CombatChecks.RollMode.DISADVANTAGE, "인접한 적이 있으면 불리")


func _test_firework_uses_and_save() -> void:
	var archer: CombatUnit = CombatUnit.new()
	_created.append(archer)
	archer.kind = CombatUnit.Kind.ARCHER
	_check(archer.firework_arrow_left == 1 and CombatActionRules.uses_left(archer, "firework_arrow") == 1, "새 막에는 1회")
	archer.firework_arrow_left = 0
	archer.begin_stage(false)
	_check(archer.firework_arrow_left == 0, "같은 막의 다음 전투에서는 회복하지 않음")
	archer.begin_stage(true)
	_check(archer.firework_arrow_left == 1, "새 막이 시작되면 회복")
	_check("막당 1회" in CombatActionRules.details(archer, "firework_arrow"), "호버에 막당 횟수: " + CombatActionRules.details(archer, "firework_arrow"))
	archer.firework_arrow_left = 0
	var data: Dictionary = archer.save_state([archer])
	_check(archer.is_valid_state(data, 1, Vector2i(10, 10)) and "firework_arrow_left" not in CombatUnit.SAVED_FIELDS, "선택 필드로 저장")
	var restored: CombatUnit = CombatUnit.new()
	_created.append(restored)
	restored.load_state(data, [restored])
	_check(restored.firework_arrow_left == 0, "남은 횟수를 되돌림")
	var old: Dictionary = data.duplicate()
	old.erase("firework_arrow_left")
	_check(archer.is_valid_state(old, 1, Vector2i(10, 10)), "필드가 없는 저장도 유효")
	restored.load_state(old, [restored])
	_check(restored.firework_arrow_left == 1, "없는 필드는 1로 읽음")
	for broken: Dictionary in [{"firework_arrow_left": -1}, {"firework_arrow_left": "1"}, {"firework_arrow_left": CombatUnit.SAVED_INT_LIMIT + 1}]:
		var bad: Dictionary = data.duplicate()
		bad.merge(broken, true)
		_check(not archer.is_valid_state(bad, 1, Vector2i(10, 10)), "깨진 값 거부: " + str(broken))


## 반사신경(#500): 반응 + 이동력 1. 정의는 궁수만 갖고 반응 묶음에 있다.
func _test_reflex_rules() -> void:
	var f: Fixture = _fixture()
	_check(CombatActionRules.belongs_to(f.units[0], "reflex") and not CombatActionRules.belongs_to(f.units[1], "reflex")
		and not CombatActionRules.belongs_to(f.units[3], "reflex"), "반사신경은 아군 궁수만")
	_check(CombatActionRules.resource_of("reflex") == CombatUnit.TurnResource.REACTION, "반사신경은 반응 묶음")
	_check(CombatActionRules.cost_text("reflex") == "비용: 반응 1 + 이동력 1", "호버 비용: " + CombatActionRules.cost_text("reflex"))


## 야만인(3,3)이 궁수(3,4)를 노린다. 야만인 차례. 확인 창은 answer로 답한다(Vector2i는 칸, bool은 넘기기/첫 칸).
func _reflex_fixture(answer: Variant, prompts: Array[Array], order: Array[int] = [2, 0, 1, 3]) -> Fixture:
	var f: Fixture = _fixture(order)
	f.units[2].cell = Vector2i(3, 3)
	f.actions.reaction_requested.connect(func(kind: String, prompt: String) -> void:
		prompts.append([kind, prompt])
		if answer is Vector2i:
			f.actions.resolve_reflex(answer)
		else:
			f.actions.resolve_reaction(answer))
	return f


func _hit_dice(f: Fixture) -> ScriptedDice:
	var sides: Array[int] = ScriptedDice.attack_sides(f.units[2]) + ScriptedDice.damage_sides(f.units[2])
	return _dice([sides[0], 1], sides)


func _test_reflex_dodge() -> void:
	var prompts: Array[Array] = []
	var f: Fixture = _reflex_fixture(Vector2i(2, 4), prompts)
	var archer: CombatUnit = f.units[0]
	f.actions.dice = _dice([ScriptedDice.attack_sides(f.units[2])[0]], ScriptedDice.attack_sides(f.units[2]))
	_check(await f.actions.attack(f.units[2], archer), "야만인이 궁수를 공격")
	_check(f.actions.last_attack.success and prompts.size() == 1 and prompts[0][0] == "reflex"
		and "명중했습니다" in prompts[0][1] and "이동력 1" in prompts[0][1], "명중 확정 뒤 반사신경 창: " + str(prompts))
	_check(archer.cell == Vector2i(2, 4) and archer.hit_points == archer.get_max_hit_points()
		and archer.reaction_left == 0 and archer.movement_left == 5 and f.actions.last_damage == 0,
		"고른 칸으로 회피하고 피해 없음, 반응·이동력 1 소비")
	_check(f.logs.any(func(line: String) -> bool: return "반사신경" in line and "회피" in line), "회피 로그: " + str(f.logs))
	_check(not f.actions.busy and f.actions.pending_reactor == null, "회피 뒤 잠금·대기 해제")
	# 넘기면 피해를 받고 반응·이동력은 그대로다.
	prompts.clear()
	var declined: Fixture = _reflex_fixture(false, prompts)
	declined.actions.dice = _hit_dice(declined)
	await declined.actions.attack(declined.units[2], declined.units[0])
	_check(prompts.size() == 1 and declined.units[0].cell == Vector2i(3, 4) and declined.units[0].hit_points < 9
		and declined.units[0].reaction_left == 1 and declined.units[0].movement_left == 6, "넘기면 피해, 반응·이동력 그대로")
	# 참으로만 답하면 첫 후보 칸으로 회피한다.
	prompts.clear()
	var first: Fixture = _reflex_fixture(true, prompts)
	first.actions.dice = _dice([ScriptedDice.attack_sides(first.units[2])[0]], ScriptedDice.attack_sides(first.units[2]))
	var expected: Vector2i = first.actions.reflex_cells(first.units[0])[0]
	await first.actions.attack(first.units[2], first.units[0])
	_check(first.units[0].cell == expected and first.units[0].reaction_left == 0, "resolve_reaction(true)는 첫 후보 칸")


## 창이 뜨지 않는 경우: 빗나감, 넘어짐, 기절, 반응·이동력 0, 빈 칸 없음, 내성굴림 동작, 반사신경이 없는 유닛.
func _test_reflex_conditions() -> void:
	var rolled: int = ScriptedDice.attack_sides(_fixture().units[2])[0]
	for case: String in ["miss", "fallen", "stunned", "no_reaction", "no_movement", "surrounded", "wall_height"]:
		var prompts: Array[Array] = []
		var f: Fixture = _reflex_fixture(true, prompts)
		var archer: CombatUnit = f.units[0]
		var count: int = 1
		var values: Array[int] = [rolled]
		match case:
			"miss":
				values = [1]
			"fallen":
				archer.fallen = true
			"stunned":
				archer.is_stunned = true
				# 기절한 대상은 유리(2개)라 둘 다 최대로 굴린다.
				count = 2
				values = [rolled, rolled]
			"no_reaction":
				archer.reaction_left = 0
			"no_movement":
				archer.movement_left = 0
			"surrounded":
				f.units[1].cell = Vector2i(2, 4)
				f.units[3].cell = Vector2i(4, 4)
				f.actions.grid.blocked_cells.append(Vector2i(3, 5))
			"wall_height":
				f.actions.grid.blocked_cells.append(Vector2i(2, 4))
				f.actions.grid.blocked_cells.append(Vector2i(4, 4))
				f.actions.grid.heights[Vector2i(3, 5)] = 2
		var sides: Array[int] = ScriptedDice.attack_sides(f.units[2], count)
		if case != "miss":
			sides += ScriptedDice.damage_sides(f.units[2])
			values.append(1)
		f.actions.dice = _dice(values, sides)
		await f.actions.attack(f.units[2], archer)
		_check(prompts.is_empty(), "반사신경 창 없음: " + case + " " + str(prompts))
	# 내성굴림 범위 효과(회전회오리)에는 묻지 않는다.
	var spin_prompts: Array[Array] = []
	var spin: Fixture = _reflex_fixture(true, spin_prompts)
	spin.units[2].kind = CombatUnit.Kind.SCRAP_ROBOT_3000
	spin.units[2].hit_points = spin.units[2].get_max_hit_points()
	spin.actions.dice = _dice([1, 1], [12, 12])
	await spin.actions.spin(spin.units[2])
	_check(spin_prompts.is_empty() and spin.units[0].reaction_left == 1, "내성굴림 동작에는 반사신경 창 없음")
	var warrior_side: Fixture = _fixture()
	_check(warrior_side.actions.reflex_cells(warrior_side.units[1]).is_empty(), "전사는 반사신경 없음")
	_check(warrior_side.actions.reflex_cells(warrior_side.units[0]).size() == 4, "궁수는 후보 칸 4개")


## 자기 턴 걷기·점프 중 적의 기회 공격을 회피하면 걷기는 회피 칸에서 멈추고, 점프는 취소된다.
func _test_reflex_movement() -> void:
	var rolled: int = ScriptedDice.attack_sides(_fixture().units[2])[0]
	var prompts: Array[Array] = []
	var walk: Fixture = _reflex_fixture(Vector2i(3, 5), prompts, [0, 1, 2, 3])
	var archer: CombatUnit = walk.units[0]
	archer.cell = Vector2i(4, 4)
	walk.units[2].cell = Vector2i(4, 6)
	walk.actions.grid.blocked_cells.append(Vector2i(5, 4))
	walk.actions.dice = _dice([rolled], ScriptedDice.attack_sides(walk.units[2]))
	_check(await walk.actions.move_to(archer, Vector2i(5, 5)), "기회 공격을 받는 걷기")
	_check(prompts.size() == 1 and prompts[0][0] == "reflex" and archer.cell == Vector2i(3, 5)
		and archer.hit_points == archer.get_max_hit_points() and archer.reaction_left == 0
		and archer.movement_left == 6 - 1 - 1 and walk.units[2].reaction_left == 0,
		"한 칸 걷고 회피하면 회피 칸에서 멈춤, 이동력은 걸은 1 + 회피 1: " + str(archer.cell) + " " + str(archer.movement_left))
	# 넘기면 피해를 받고 걷기를 이어 간다.
	prompts.clear()
	var declined: Fixture = _reflex_fixture(false, prompts, [0, 1, 2, 3])
	declined.units[0].cell = Vector2i(4, 4)
	declined.units[2].cell = Vector2i(4, 6)
	declined.actions.grid.blocked_cells.append(Vector2i(5, 4))
	declined.actions.dice = _hit_dice(declined)
	_check(await declined.actions.move_to(declined.units[0], Vector2i(5, 5)) and declined.units[0].cell == Vector2i(5, 5)
		and declined.units[0].hit_points < 9 and declined.units[0].reaction_left == 1, "넘기면 피해를 받고 계속 걸음")
	# 점프: 이륙 전 회피하면 점프가 취소된다. 보조 행동은 쓰고 점프의 이동력은 쓰지 않는다.
	prompts.clear()
	var jump: Fixture = _reflex_fixture(Vector2i(3, 5), prompts, [0, 1, 2, 3])
	jump.actions.dice = _dice([rolled], ScriptedDice.attack_sides(jump.units[2]))
	_check(await jump.actions.jump_to(jump.units[0], Vector2i(1, 4)), "기회 공격을 받는 점프")
	_check(jump.units[0].cell == Vector2i(3, 5) and jump.units[0].bonus_action_left == 0
		and jump.units[0].movement_left == 5 and jump.units[0].hit_points == 9 and not jump.actions.busy,
		"회피하면 점프 취소, 보조 행동 소비, 이동력은 회피 1만: " + str(jump.units[0].cell) + " " + str(jump.units[0].movement_left))


func _with_save(attacker: CombatUnit, save_sides: int) -> Array[int]:
	var sides: Array[int] = ScriptedDice.attack_sides(attacker)
	sides.append(save_sides)
	return sides


## 기름: 떠나는 회피는 이탈 미끌거림, 들어가는 회피는 진입 미끌거림을 굴린다. 실패해도 회피는 성립한다.
func _test_reflex_oil() -> void:
	var rolled: int = ScriptedDice.attack_sides(_fixture().units[2])[0]
	var finesse: int = _fixture().units[0].get_ability_sides(CombatUnit.Ability.FINESSE)
	# 서 있는 칸이 기름: 이탈 굴림에 실패하면 제자리에서 넘어지고 공격은 무효, 반응·이동력 1은 소비한다.
	var prompts: Array[Array] = []
	var leave: Fixture = _reflex_fixture(Vector2i(3, 5), prompts)
	leave.actions.create_oil(leave.units[2], Vector2i(3, 4))
	leave.actions.dice = _dice([rolled, 1], _with_save(leave.units[2], finesse))
	await leave.actions.attack(leave.units[2], leave.units[0])
	var archer: CombatUnit = leave.units[0]
	_check(archer.cell == Vector2i(3, 4) and archer.fallen and archer.hit_points == archer.get_max_hit_points()
		and archer.reaction_left == 0 and archer.movement_left == 5, "이탈 실패: 제자리에서 넘어지고 피해 없음, 반응·이동력 소비")
	# 이탈에 성공하면 회피 칸으로 간다.
	prompts.clear()
	var pass_leave: Fixture = _reflex_fixture(Vector2i(3, 5), prompts)
	pass_leave.actions.create_oil(pass_leave.units[2], Vector2i(3, 4))
	pass_leave.actions.dice = _dice([rolled, finesse], _with_save(pass_leave.units[2], finesse))
	await pass_leave.actions.attack(pass_leave.units[2], pass_leave.units[0])
	_check(pass_leave.units[0].cell == Vector2i(3, 5) and not pass_leave.units[0].fallen, "이탈 성공: 회피 칸으로 이동")
	# 기름 칸으로 회피하면 진입 굴림을 하고, 실패하면 그 칸에서 넘어진다.
	prompts.clear()
	var enter: Fixture = _reflex_fixture(Vector2i(2, 4), prompts)
	enter.actions.create_oil(enter.units[2], Vector2i(1, 4))
	enter.actions.dice = _dice([rolled, 1], _with_save(enter.units[2], finesse))
	await enter.actions.attack(enter.units[2], enter.units[0])
	_check(enter.units[0].cell == Vector2i(2, 4) and enter.units[0].fallen
		and enter.units[0].hit_points == enter.units[0].get_max_hit_points(), "진입 실패: 회피 칸에서 넘어짐")


## 적 턴에 쓴 반응과 이동력 1은 다음 자기 묶음이 확정될 때까지 회복되지 않는다(3-3, #551).
func _test_reflex_next_turn() -> void:
	var rolled: int = ScriptedDice.attack_sides(_fixture().units[2])[0]
	var prompts: Array[Array] = []
	var f: Fixture = _reflex_fixture(Vector2i(2, 4), prompts)
	var archer: CombatUnit = f.units[0]
	f.actions.dice = _dice([rolled], ScriptedDice.attack_sides(f.units[2]))
	await f.actions.attack(f.units[2], archer)
	f.turns.end_turn()
	_check(f.turns.current_unit == archer and archer.reaction_left == 0 and archer.movement_left == archer.get_movement() - 1,
		"다음 자기 턴: 이동력 1 적고 반응 없음")
	f.turns.end_turn()
	f.turns.end_turn()
	_check(f.turns.current_unit == f.units[3] and archer.reaction_left == 1 and archer.movement_left == archer.get_movement(),
		"자기 묶음 확정 뒤 반응과 이동력 회복")


## 이어하기가 다시 실행하는 적 턴: 저장한 반사신경 답(칸 또는 false)을 묻지 않고 쓴다. 후보 밖 칸과 bool은 넘기기다.
func _test_reflex_replay() -> void:
	var rolled: int = ScriptedDice.attack_sides(_fixture().units[2])[0]
	var asked: Array[Array] = []
	var f: Fixture = _reflex_fixture(true, asked)
	f.actions.replay_answers = [Vector2i(2, 4)]
	f.actions.dice = _dice([rolled], ScriptedDice.attack_sides(f.units[2]))
	await f.actions.attack(f.units[2], f.units[0])
	_check(asked.is_empty() and f.units[0].cell == Vector2i(2, 4) and f.units[0].reaction_left == 0
		and f.actions.reaction_answers == [Vector2i(2, 4)] and f.actions.replay_answers.is_empty(),
		"저장한 칸으로 묻지 않고 회피하고 답을 다시 기록: " + str(f.actions.reaction_answers))
	for answer: Variant in [Vector2i(9, 9), true, false]:
		var other: Fixture = _reflex_fixture(true, asked)
		other.actions.replay_answers = [answer]
		other.actions.dice = _hit_dice(other)
		await other.actions.attack(other.units[2], other.units[0])
		_check(asked.is_empty() and other.units[0].cell == Vector2i(3, 4) and other.units[0].hit_points < 9
			and other.actions.reaction_answers == [false], "후보 밖 칸·bool은 넘기기: " + str(answer))
	# 반사신경이 아닌 반응(기회 공격)은 칸 답을 쓰지 않는다.
	var opp: Fixture = _fixture([2, 0, 1, 3])
	opp.units[2].cell = Vector2i(3, 5)
	opp.units[1].reaction_left = 1
	opp.actions.replay_answers = [Vector2i(1, 1)]
	_check(await opp.actions.move_to(opp.units[2], Vector2i(4, 5)) and opp.actions.reaction_answers == [false]
		and opp.units[1].reaction_left == 1, "기회 공격은 칸 답을 넘기기로 봄")


## 새 전투(스테이지) 시작에는 애기살과 무빙샷 상태가 없다.
func _test_stage_reset() -> void:
	var f: Fixture = _fixture()
	var archer: CombatUnit = f.units[0]
	archer.aegisal_left = 5
	archer.moving_shot_ready = true
	archer.moving_shot_spent = true
	archer.begin_stage(false)
	_check(archer.aegisal_left == 0 and not archer.moving_shot_ready and not archer.moving_shot_spent,
		"전투 전환에서 애기살 0, 무빙샷 해제")


## 애기살·무빙샷 상태는 SAVED_FIELDS 밖의 선택 필드다. 없으면 0·false, 옛 표식·충격 화살 필드는 무시한다.
func _test_save_state() -> void:
	var f: Fixture = _fixture()
	var archer: CombatUnit = f.units[0]
	archer.aegisal_left = 3
	archer.moving_shot_ready = true
	archer.moving_shot_spent = true
	f.units[3].disengage_left = 1
	var saved: Array = f.units.map(func(unit: CombatUnit) -> Dictionary: return unit.save_state(f.units))
	_check(saved.all(func(data: Dictionary) -> bool: return archer.is_valid_state(data, 4, Vector2i(10, 10))),
		"애기살·무빙샷을 담은 유닛 저장은 유효")
	_check("aegisal_left" not in CombatUnit.SAVED_FIELDS and "mark_left" not in CombatUnit.SAVED_FIELDS
		and "shock_left" not in CombatUnit.SAVED_FIELDS and "disengage_left" in CombatUnit.SAVED_FIELDS,
		"새 필드는 선택 필드, 표식·충격 화살 필드 삭제, 물러서며 쏘기 횟수 유지")
	var restored: CombatUnit = CombatUnit.new()
	_created.append(restored)
	restored.load_state(saved[0], f.units)
	_check(restored.aegisal_left == 3 and restored.moving_shot_ready and restored.moving_shot_spent,
		"애기살 발수와 무빙샷 상태를 되돌림")
	var novice: CombatUnit = CombatUnit.new()
	_created.append(novice)
	novice.load_state(saved[3], f.units)
	_check(novice.disengage_left == 1, "풋내기 궁수의 물러서며 쏘기 남은 횟수를 되돌림")
	var old: Dictionary = (saved[0] as Dictionary).duplicate()
	for field: String in ["aegisal_left", "moving_shot_ready", "moving_shot_spent"]:
		old.erase(field)
	old.merge({"mark_left": 1, "shock_left": 0, "marked_target": 2}, true)
	_check(archer.is_valid_state(old, 4, Vector2i(10, 10)), "새 필드가 없고 옛 필드가 남은 저장도 유효")
	var legacy: CombatUnit = CombatUnit.new()
	_created.append(legacy)
	legacy.aegisal_left = 5
	legacy.moving_shot_ready = true
	legacy.load_state(old, f.units)
	_check(legacy.aegisal_left == 0 and not legacy.moving_shot_ready and not legacy.moving_shot_spent,
		"없는 선택 필드는 0·false로 읽음")
	for broken: Dictionary in [{"aegisal_left": -1}, {"aegisal_left": CombatUnit.SAVED_INT_LIMIT + 1},
			{"aegisal_left": "3"}, {"moving_shot_ready": 1}, {"moving_shot_spent": "true"}]:
		var data: Dictionary = (saved[0] as Dictionary).duplicate()
		data.merge(broken, true)
		_check(not archer.is_valid_state(data, 4, Vector2i(10, 10)), "깨진 선택 필드 거부: " + str(broken))


## 실제 전투 장면의 combat_state()·restore_combat()으로 애기살과 무빙샷 상태가 이어진다.
func _test_battle_save() -> void:
	var scene: PackedScene = load("res://scenes/combat/battle.tscn") as PackedScene
	var first: Node2D = scene.instantiate() as Node2D
	first.stages[0] = load("res://scenes/combat/stage.tres") as CombatStage
	root.add_child(first)
	first.set_process(false)
	first.call("start_battle")
	await process_frame
	var archer: CombatUnit = (first.get("units") as Array[CombatUnit])[1]
	archer.aegisal_left = 4
	archer.moving_shot_ready = true
	archer.moving_shot_spent = true
	var state: Dictionary = first.call("combat_state")
	var second: Node2D = scene.instantiate() as Node2D
	second.stages[0] = load("res://scenes/combat/stage.tres") as CombatStage
	root.add_child(second)
	second.set_process(false)
	await process_frame
	_check(second.call("restore_combat", state), "애기살·무빙샷을 담은 전투 저장 복원")
	var copy: CombatUnit = (second.get("units") as Array[CombatUnit])[1]
	_check(copy.aegisal_left == 4 and copy.moving_shot_ready and copy.moving_shot_spent, "복원한 궁수의 애기살·무빙샷 상태")
	var old: Dictionary = state.duplicate(true)
	for field: String in ["aegisal_left", "moving_shot_ready", "moving_shot_spent"]:
		(old.units[1] as Dictionary).erase(field)
	(old.units[1] as Dictionary).merge({"mark_left": 1, "shock_left": 1, "marked_target": -1}, true)
	_check(second.call("restore_combat", old), "새 필드가 없는 옛 형식 5 전투 저장도 복원")
	copy = (second.get("units") as Array[CombatUnit])[1]
	_check(copy.aegisal_left == 0 and not copy.moving_shot_ready, "옛 저장의 애기살 0, 무빙샷 해제")
	# 적 턴 중간 저장의 반응 답: bool 또는 지도 안의 칸만 받는다(형식 7 유지).
	var combat_turns: CombatTurns = first.get("turns")
	var guard: int = 0
	while combat_turns.current_unit.is_ally and guard < 8:
		combat_turns.end_turn()
		guard += 1
	var mid: Dictionary = first.call("combat_state")
	var accepted: bool = true
	for answers: Array in [[true], [false, Vector2i(0, 0)], [Vector2i(1, 1)]]:
		var good: Dictionary = mid.duplicate(true)
		good["replay"] = {"actions": 1, "reactions": answers}
		accepted = accepted and second.call("restore_combat", good)
	_check(accepted, "적 턴 저장의 반응 답에 bool과 지도 안 칸을 받음")
	for bad_answer: Variant in [Vector2i(-1, 0), Vector2i(99, 99), "x", 3, Vector2(1, 1)]:
		var bad: Dictionary = mid.duplicate(true)
		bad["replay"] = {"actions": 1, "reactions": [bad_answer]}
		_check(not second.call("restore_combat", bad), "반응 답으로 받지 않는 값: " + str(bad_answer))
	first.queue_free()
	second.queue_free()
	await process_frame
