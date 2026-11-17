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
	_test_whistle_band()
	await _test_whistle()
	_test_whistle_unusable()
	await _test_distraction_clock()
	await _test_distraction_logs()
	await _test_help_dc_basis()
	_test_firework_uses_and_save()
	_test_firework_effect_dc()
	await _test_tree_burn()
	_test_stage_reset()
	_test_save_state()
	_test_whistle_save_state()
	_test_stealth_use()
	_test_stealth_targeting()
	await _test_stealth_breaks()
	await _test_stealth_keeps()
	_test_stealth_duration()
	await _test_stealth_opportunity()
	await _test_stealth_area()
	_test_stealth_save()
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


## 은신: 보조 행동·전투마다 1회, 궁수만 쓴다(궁수 문서 「은신」).
func _test_stealth_use() -> void:
	var f: Fixture = _fixture()
	var archer: CombatUnit = f.units[0]
	_check(CombatActionRules.belongs_to(archer, "stealth") and not CombatActionRules.belongs_to(f.units[1], "stealth")
		and not CombatActionRules.belongs_to(f.units[3], "stealth") and not CombatActionRules.belongs_to(f.units[2], "stealth"),
		"은신은 아군 궁수만")
	_check(CombatActionRules.resource_of("stealth") == CombatUnit.TurnResource.BONUS_ACTION
		and CombatActionRules.uses_left(archer, "stealth") == 1, "은신은 보조 행동, 전투마다 1회")
	_check(f.actions.can_use(archer, "stealth") and f.actions.use_self(archer, "stealth"), "은신 사용")
	_check(archer.stealthed and archer.bonus_action_left == 0 and archer.action_left == 1 and archer.stealth_left == 0,
		"은신은 보조 행동과 1회를 쓰고 행동은 남김")
	_check(not f.actions.can_use(archer, "stealth") and not f.actions.use_self(archer, "stealth"), "횟수를 쓰면 다시 못 씀")
	_check("전투마다 1회 · 0회 남음" in CombatActionRules.details(archer, "stealth"), "호버의 남은 횟수")
	_check(not f.actions.use_self(f.units[3], "stealth") and not f.units[3].stealthed, "풋내기 궁수는 못 씀")


## 적은 은신 유닛을 지정할 수 없고 아군은 지정할 수 있다.
func _test_stealth_targeting() -> void:
	var f: Fixture = _fixture()
	var archer: CombatUnit = f.units[0]
	var barbarian: CombatUnit = f.units[2]
	barbarian.cell = Vector2i(4, 4)
	f.units[1].cell = Vector2i(3, 5)
	_check(f.actions.can_target(barbarian, archer, "attack") and f.actions.can_target(f.units[3], archer, "attack"),
		"은신 전에는 적이 공격을 지정할 수 있음")
	var robot: Fixture = _fixture([2, 0, 1, 3])
	robot.units[2].kind = CombatUnit.Kind.SCRAP_ROBOT_3000
	robot.units[2].cell = Vector2i(6, 4)
	_check(robot.actions.can_target(robot.units[2], robot.units[0], "pull"), "은신 전에는 만능팔을 지정할 수 있음")
	robot.units[0].stealthed = true
	_check(not robot.actions.can_target(robot.units[2], robot.units[0], "pull"), "은신하면 만능팔도 지정 불가")
	archer.stealthed = true
	_check(not f.actions.can_target(barbarian, archer, "attack") and not f.actions.can_target(f.units[3], archer, "attack"),
		"은신하면 적의 공격 지정 불가")
	_check(f.actions.can_target(f.units[1], archer, "shove"), "아군이 은신 유닛을 대상으로 고르는 것은 막지 않음")
	_check(f.actions.can_target(archer, barbarian, "attack"), "은신 유닛 자신의 공격은 그대로")


## 피해를 주는 공격 동작을 쓰면 풀린다. 빗나가도, 빈 칸·상자를 쏘아도 풀린다.
func _test_stealth_breaks() -> void:
	var hit: Fixture = _fixture()
	hit.units[0].stealthed = true
	hit.actions.dice = _dice([15, 7], [20, 20])
	await hit.actions.attack(hit.units[0], hit.units[3])
	_check(not hit.units[0].stealthed, "기본 공격은 은신을 풂")
	var miss: Fixture = _fixture()
	miss.units[0].stealthed = true
	miss.actions.dice = _dice([1], [20])
	await miss.actions.attack(miss.units[0], miss.units[3])
	_check(not miss.units[0].stealthed and miss.units[3].hit_points == 14, "빗나가도 풀림")
	var crate: Fixture = _fixture()
	crate.units[0].stealthed = true
	var prop: CombatGrid.Prop = crate.actions.create_prop(Vector2i(4, 4), "crate")
	crate.actions.dice = _dice([3], [20])
	await crate.actions.attack_prop(crate.units[0], prop)
	_check(not crate.units[0].stealthed, "나무 상자 공격도 풂")
	var trick: Fixture = _fixture()
	trick.units[0].stealthed = true
	trick.actions.dice = _dice([6], [6])
	await trick.actions.trick_arrow(trick.units[0], Vector2i(5, 2))
	_check(not trick.units[0].stealthed, "장난스러운 화살은 빈 칸에 쏴도 풂")
	var firework: Fixture = _fixture()
	firework.units[0].stealthed = true
	await firework.actions.firework_arrow(firework.units[0], Vector2i(5, 2))
	_check(not firework.units[0].stealthed, "폭죽 화살은 풂")
	var bash: Fixture = _fixture()
	bash.units[0].stealthed = true
	bash.units[2].cell = Vector2i(4, 4)
	bash.actions.dice = _dice([1], [6])
	await bash.actions.bow_bash(bash.units[0], bash.units[2])
	_check(not bash.units[0].stealthed, "활 후려치기는 풂")


## 이동·기름병 던지기·애기살 급조는 풀지 않는다.
func _test_stealth_keeps() -> void:
	var f: Fixture = _fixture()
	var archer: CombatUnit = f.units[0]
	archer.stealthed = true
	_check(f.actions.use_self(archer, "aegisal") and archer.stealthed, "애기살 급조는 풀지 않음")
	var oil: Fixture = _fixture()
	oil.units[0].stealthed = true
	_check(oil.actions.throw_oil(oil.units[0], Vector2i(3, 2)) and oil.units[0].stealthed, "기름병 던지기는 풀지 않음")
	var walk: Fixture = _fixture()
	walk.units[0].stealthed = true
	_check(await walk.actions.move_to(walk.units[0], Vector2i(3, 3)) and walk.units[0].stealthed, "이동은 풀지 않음")
	var jump: Fixture = _fixture()
	jump.units[0].stealthed = true
	_check(await jump.actions.jump_to(jump.units[0], Vector2i(3, 2)) and jump.units[0].stealthed, "점프는 풀지 않음")


## 다음 자기 턴 시작까지 이어지고, 새 전투와 전투 불능에서 풀린다.
func _test_stealth_duration() -> void:
	var f: Fixture = _fixture()
	var archer: CombatUnit = f.units[0]
	archer.stealthed = true
	f.turns.turn_started.emit(f.units[2])
	_check(archer.stealthed, "적 턴이 시작되어도 유지")
	f.turns.turn_started.emit(archer)
	_check(not archer.stealthed, "자기 턴 시작에 풀림")
	archer.stealthed = true
	archer.stealth_left = 0
	archer.begin_stage(false)
	_check(not archer.stealthed and archer.stealth_left == 1, "새 전투에는 은신이 없고 횟수 1")
	archer.stealthed = true
	f.actions.incapacitate(archer)
	_check(not archer.stealthed, "전투 불능이면 풀림")


## 은신 유닛은 기회 공격을 받지 않는다.
func _test_stealth_opportunity() -> void:
	var f: Fixture = _fixture()
	var archer: CombatUnit = f.units[0]
	var barbarian: CombatUnit = f.units[2]
	barbarian.cell = Vector2i(4, 4)
	barbarian.reaction_left = 1
	_check(f.actions.jump_reactors(archer, Vector2i(2, 4)).size() == 1, "은신 전에는 점프 이탈에 기회 공격")
	archer.stealthed = true
	_check(f.actions.jump_reactors(archer, Vector2i(2, 4)).is_empty(), "은신하면 점프 이탈에 기회 공격 없음")
	_check(await f.actions.move_to(archer, Vector2i(2, 4)) and archer.cell == Vector2i(2, 4)
		and archer.hit_points == archer.get_max_hit_points() and barbarian.reaction_left == 1,
		"은신하면 걷기 이탈에 기회 공격 없음")


## 범위 효과는 은신 유닛도 맞고 은신은 유지된다.
func _test_stealth_area() -> void:
	var f: Fixture = _fixture([2, 0, 1, 3])
	var robot: CombatUnit = f.units[2]
	var archer: CombatUnit = f.units[0]
	robot.kind = CombatUnit.Kind.SCRAP_ROBOT_3000
	robot.hit_points = robot.get_max_hit_points()
	archer.cell = Vector2i(5, 3)
	f.units[1].cell = Vector2i(0, 0)
	archer.stealthed = true
	f.actions.dice = _dice([2, 6], [12, 12])
	_check(await f.actions.spin(robot) and archer.hit_points == 9 - 8 and archer.stealthed,
		"회전회오리는 은신 유닛도 맞히고 은신은 유지")


## 은신 상태와 남은 횟수는 선택 필드다. 없으면 false·1이다.
func _test_stealth_save() -> void:
	var f: Fixture = _fixture()
	var archer: CombatUnit = f.units[0]
	archer.stealthed = true
	archer.stealth_left = 0
	var saved: Array = f.units.map(func(unit: CombatUnit) -> Dictionary: return unit.save_state(f.units))
	_check(saved.all(func(data: Dictionary) -> bool: return archer.is_valid_state(data, 4, Vector2i(10, 10)))
		and "stealthed" not in CombatUnit.SAVED_FIELDS and "stealth_left" not in CombatUnit.SAVED_FIELDS
		and "stealthed" in CombatUnit.OPTIONAL_FIELDS and "stealth_left" in CombatUnit.OPTIONAL_FIELDS, "은신은 선택 필드")
	var restored: CombatUnit = CombatUnit.new()
	_created.append(restored)
	restored.load_state(saved[0], f.units)
	_check(restored.stealthed and restored.stealth_left == 0, "은신 상태와 횟수를 되돌림")
	var old: Dictionary = (saved[0] as Dictionary).duplicate()
	for field: String in ["stealthed", "stealth_left"]:
		old.erase(field)
	var legacy: CombatUnit = CombatUnit.new()
	_created.append(legacy)
	legacy.stealthed = true
	legacy.stealth_left = 0
	legacy.load_state(old, f.units)
	_check(archer.is_valid_state(old, 4, Vector2i(10, 10)) and not legacy.stealthed and legacy.stealth_left == 1,
		"필드가 없는 옛 저장은 false·1로 읽음")
	for broken: Dictionary in [{"stealthed": 1}, {"stealth_left": -1}, {"stealth_left": "1"},
			{"stealth_left": CombatUnit.SAVED_INT_LIMIT + 1}]:
		var data: Dictionary = (saved[0] as Dictionary).duplicate()
		data.merge(broken, true)
		_check(not archer.is_valid_state(data, 4, Vector2i(10, 10)), "깨진 선택 필드 거부: " + str(broken))


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


## 효시의 세 줄 띠: 고른 방향의 모든 칸과 그 양옆 칸. 궁수 줄의 양옆은 뺀다. 높이·벽은 보지 않는다.
func _test_whistle_band() -> void:
	var f: Fixture = _fixture()
	var grid: CombatGrid = f.actions.grid
	_check(grid.band_cells(Vector2i(8, 4), Vector2i(9, 4)) == [Vector2i(9, 3), Vector2i(9, 4), Vector2i(9, 5)],
		"맵 끝까지 한 줄 앞이면 앞 칸과 그 양옆 셋")
	var right: Array[Vector2i] = grid.band_cells(Vector2i(4, 4), Vector2i(5, 4))
	_check(right.size() == 15 and Vector2i(5, 3) in right and Vector2i(9, 5) in right and Vector2i(4, 3) not in right
		and Vector2i(4, 5) not in right and Vector2i(4, 4) not in right, "오른쪽 방향: 5줄×3칸, 궁수 줄의 양옆과 자신은 제외")
	var up: Array[Vector2i] = grid.band_cells(Vector2i(4, 4), Vector2i(4, 3))
	_check(up.size() == 12 and Vector2i(3, 0) in up and Vector2i(5, 3) in up and Vector2i(3, 4) not in up, "위쪽 방향은 맵 끝(y=0)까지")
	_check(grid.band_cells(Vector2i(4, 4), Vector2i(3, 4)).size() == 12 and grid.band_cells(Vector2i(4, 4), Vector2i(4, 5)).size() == 15,
		"왼쪽·아래쪽 방향도 같은 모양")
	_check(grid.band_cells(Vector2i(0, 0), Vector2i(1, 0)).size() == 18, "맵 밖 옆 칸은 잘림")
	grid.heights[Vector2i(6, 4)] = 3
	grid.pits = [Vector2i(7, 5)]
	grid.blocked_cells = [Vector2i(5, 4)]
	_check(grid.band_cells(Vector2i(4, 4), Vector2i(5, 4)).size() == 15, "높이·낭떠러지·막힌 칸도 범위에 포함")
	_check(grid.band_cells(Vector2i(4, 4), Vector2i(6, 4)).is_empty() and grid.band_cells(Vector2i(0, 4), Vector2i(-1, 4)).is_empty(),
		"인접하지 않거나 맵 밖인 방향은 빈 목록")


func _logged(f: Fixture, text: String) -> bool:
	return f.logs.any(func(message: String) -> bool: return text in message)


## 도움말(#600): 폭죽 화살·효시·일반 DC 문구는 고정 숫자 대신 계산 기준을 적고, 레벨 0·장비 없음의 값은 실제 DC와 같다.
func _test_help_dc_basis() -> void:
	var help: Control = (load("res://scenes/help.tscn") as PackedScene).instantiate() as Control
	root.add_child(help)
	await process_frame
	var text: String = "\n".join(help.find_children("*", "Label", true, false).map(
		func(label: Label) -> String: return label.text))
	var f: Fixture = _fixture()
	var archer: CombatUnit = f.units[0]
	var firework: int = CombatActionRules.save_dc(archer, "firework_arrow")
	var whistle: int = CombatActionRules.save_dc(archer, "whistle")
	_check("DC는 지능 표준값 + 지능 가감 + 공격 가산, 레벨업·장비 전 %d" % firework in text, "도움말 폭죽 화살: 기준과 시작 값 %d" % firework)
	_check("DC는 솜씨 표준값 + 솜씨 가감 + 공격 가산, 레벨업·장비 전 %d" % whistle in text, "도움말 효시: 기준과 시작 값 %d" % whistle)
	_check("민첩 내성(DC 4)" not in text and "의지 내성굴림(DC 11)" not in text, "도움말에 고정 DC 표기가 남지 않음")
	_check("DC(시전 능력치 표준값 + 능력치 가감 + 공격 가산)" in text, "도움말 일반 DC 공식에 가감 포함")
	help.free()


## 효시(궁수 문서): 띠 안의 적만 의지 내성(DC 11). 실패하면 산만함 2턴, 피해 없음, 행동과 전투마다 1회를 쓴다.
func _test_whistle() -> void:
	var f: Fixture = _fixture()
	var archer: CombatUnit = f.units[0]
	var ally: CombatUnit = f.units[1]
	var barbarian: CombatUnit = f.units[2]
	var foe: CombatUnit = f.units[3]
	ally.cell = Vector2i(5, 5)
	foe.cell = Vector2i(7, 6)
	for unit: CombatUnit in f.units:
		unit.hit_points = 40
	var facing: Vector2i = Vector2i(4, 4)
	_check(f.actions.whistle_targets(archer, facing) == [barbarian], "띠 안의 적만 대상: 아군과 띠 밖의 적은 제외")
	_check(f.actions.can_whistle(archer, facing) and f.actions.can_use(archer, "whistle"), "효시를 쓸 수 있음")
	_check(CombatActionRules.save_dc(archer, "whistle") == 11, "DC는 솜씨 표준값 11")
	archer.moving_shot_ready = true
	var will: int = barbarian.get_ability_sides(CombatUnit.Ability.WILL)
	f.actions.dice = _dice([2], [will])
	_check(await f.actions.whistle(archer, facing), "효시를 씀")
	_check(barbarian.distracted_turns == 2 and barbarian.distracted_source == archer and ally.distracted_turns == 0
		and foe.distracted_turns == 0, "내성에 실패한 대상만 산만함 2턴, 시전자는 궁수")
	_check(f.units.all(func(unit: CombatUnit) -> bool: return unit.hit_points == 40), "피해 없음")
	_check(archer.action_left == 0 and archer.whistle_left == 0 and not archer.moving_shot_ready and not archer.moving_shot_spent,
		"행동과 전투마다 횟수를 쓰고 무빙샷을 켜지 않음")
	_check(_logged(f, "효시") and _logged(f, "의지 내성") and _logged(f, "산만함 2턴"), "시전·내성·결과 로그 " + str(f.logs))
	archer.action_left = 1
	_check(not f.actions.can_use(archer, "whistle") and f.actions.unavailable_reason(archer, "whistle") != "", "전투마다 1회라 다시 쓸 수 없음")
	archer.begin_stage(false)
	_check(archer.whistle_left == 1, "새 전투에서 횟수 회복")
	# 성공하면 걸리지 않는다. 의지 가감으로 DC를 넘긴다.
	var g: Fixture = _fixture()
	var target: CombatUnit = g.units[2]
	target.weapon = {"stats": {"will_modifier": 20}}
	g.units[3].cell = Vector2i(7, 8)
	g.actions.dice = _dice([3], [target.get_ability_sides(CombatUnit.Ability.WILL)])
	await g.actions.whistle(g.units[0], Vector2i(4, 4))
	_check(target.distracted_turns == 0 and _logged(g, "버팀"), "내성에 성공하면 걸리지 않고 로그는 버팀")
	# 이미 산만함인 대상이 다시 실패하면 기간만 되돌린다.
	var h: Fixture = _fixture()
	h.units[2].distracted_turns = 1
	h.units[2].distracted_source = h.units[0]
	h.units[3].cell = Vector2i(7, 8)
	var h_will: int = h.units[2].get_ability_sides(CombatUnit.Ability.WILL)
	# 효시의 내성굴림 자체에는 산만함이 붙지 않아 이미 산만함이어도 한 번만 굴린다(궁수 문서 「효시」).
	h.actions.dice = _dice([2], [h_will])
	await h.actions.whistle(h.units[0], Vector2i(4, 4))
	_check(h.units[2].distracted_turns == 2, "다시 걸리면 기간을 2로 되돌림(중첩 없음)")
	_check(h.actions.last_save.mode == CombatChecks.RollMode.NORMAL and not _logged(h, "불리: 산만함"),
		"이미 산만함인 대상의 효시 내성굴림은 불리가 아님")
	# 산만함은 효시가 아닌 내성굴림에는 그대로 불리다.
	var k: Fixture = _fixture()
	k.units[2].distracted_turns = 1
	_check(CombatActionRules.save_mode(k.units[2], CombatUnit.Ability.WILL, "whistle") == CombatChecks.RollMode.NORMAL
		and CombatActionRules.save_mode(k.units[2], CombatUnit.Ability.WILL) == CombatChecks.RollMode.DISADVANTAGE,
		"산만함은 효시 내성만 면제하고 다른 내성은 불리")
	# 대상이 없는 맵 안 방향은 실행되어 횟수를 쓴다. 맵 밖 방향은 거부한다.
	var m: Fixture = _fixture()
	m.actions.dice = _dice([], [])
	_check(m.actions.can_whistle(m.units[0], Vector2i(3, 3)) and m.actions.whistle_targets(m.units[0], Vector2i(3, 3)).is_empty()
		and await m.actions.whistle(m.units[0], Vector2i(3, 3)) and m.units[0].whistle_left == 0,
		"적이 없는 방향도 실행되고 횟수를 씀")
	var n: Fixture = _fixture()
	n.units[0].cell = Vector2i(0, 4)
	_check(not n.actions.can_whistle(n.units[0], Vector2i(-1, 4)) and not await n.actions.whistle(n.units[0], Vector2i(-1, 4))
		and n.units[0].whistle_left == 1 and n.units[0].action_left == 1, "맵 밖 방향은 거부하고 아무것도 쓰지 않음")


func _test_whistle_unusable() -> void:
	var f: Fixture = _fixture()
	var archer: CombatUnit = f.units[0]
	var facing: Vector2i = Vector2i(4, 4)
	archer.fallen = true
	_check(not f.actions.can_whistle(archer, facing) and not f.actions.can_use(archer, "whistle"), "넘어진 궁수는 쓸 수 없음")
	archer.fallen = false
	archer.is_stunned = true
	_check(not f.actions.can_use(archer, "whistle"), "기절한 궁수는 쓸 수 없음")
	archer.is_stunned = false
	archer.action_left = 0
	_check(not f.actions.can_whistle(archer, facing), "행동을 쓴 뒤에는 쓸 수 없음")
	_check(not CombatActionRules.belongs_to(f.units[3], "whistle") and not CombatActionRules.belongs_to(f.units[1], "whistle"),
		"적 궁수와 전사는 효시를 갖지 않음")
	_check(CombatActionRules.belongs_to(archer, "whistle") and "whistle" in CombatActionRules.GROUPS[0], "아군 궁수의 행동 스킬")


## 산만함 기간: 시전자 턴 시작마다 1씩 줄고, 시전자가 쓰러져도 시계 슬롯이 줄이며, 대상이 쓰러지면 지워진다.
func _test_distraction_clock() -> void:
	var f: Fixture = _fixture()
	var archer: CombatUnit = f.units[0]
	var barbarian: CombatUnit = f.units[2]
	barbarian.distracted_turns = 2
	barbarian.distracted_source = archer
	f.turns.turn_started.emit(archer)
	_check(barbarian.distracted_turns == 1, "시전자 턴 시작마다 1턴 줄어듦")
	f.turns.turn_started.emit(barbarian)
	_check(barbarian.distracted_turns == 1, "대상의 턴 시작에는 줄지 않음")
	f.turns.turn_started.emit(archer)
	_check(barbarian.distracted_turns == 0 and barbarian.distracted_source == null and _logged(f, "산만함 만료"),
		"2턴 뒤 소멸하고 만료 로그")
	var g: Fixture = _fixture()
	var caster: CombatUnit = g.units[0]
	var victim: CombatUnit = g.units[2]
	victim.distracted_turns = 2
	victim.distracted_source = caster
	g.actions.incapacitate(caster)
	_check(victim.distracted_turns == 2 and victim.distracted_source == caster and g.actions.save_state().clock_slots == [[0, 1, false]],
		"시전자가 쓰러져도 산만함 유지, 턴 자리는 시계 슬롯으로 보관")
	g.turns.turn_started.emit(g.units[1])
	_check(victim.distracted_turns == 1, "시계 슬롯 자리마다 1턴 줄어듦")
	g.turns.turn_started.emit(g.units[1])
	_check(victim.distracted_turns == 0 and g.actions.save_state().clock_slots.is_empty(), "소멸하면 슬롯 제거")
	var h: Fixture = _fixture()
	h.units[2].distracted_turns = 2
	h.units[2].distracted_source = h.units[0]
	h.actions.incapacitate(h.units[2])
	_check(h.units[2].distracted_turns == 0 and h.units[2].distracted_source == null, "대상이 쓰러지면 지워짐")
	var k: Fixture = _fixture()
	k.units[2].distracted_turns = 2
	k.units[2].distracted_source = k.units[0]
	k.units[2].begin_stage(true)
	_check(k.units[2].distracted_turns == 0, "새 전투에서 사라짐")


## 로그에 불리의 이유를 적는다(개발 결정, #500): 요인이 없으면 지금 문구 그대로다.
func _test_distraction_logs() -> void:
	var f: Fixture = _fixture()
	var archer: CombatUnit = f.units[0]
	f.actions.dice = _dice([1], [20])
	await f.actions.attack(archer, f.units[2])
	_check(_logged(f, "공격(일반)") and not _logged(f, "산만함"), "요인이 없는 굴림은 기존 문구")
	var g: Fixture = _fixture()
	g.units[0].distracted_turns = 2
	g.units[0].distracted_source = g.units[3]
	g.actions.dice = _dice([1, 1], ScriptedDice.attack_sides(g.units[0], 2))
	await g.actions.attack(g.units[0], g.units[2])
	_check(_logged(g, "공격(불리: 산만함)"), "산만함 공격자의 공격 로그 " + str(g.logs))
	# 넘어짐과 산만함이 함께인 대상의 폭죽 화살 민첩 내성.
	var h: Fixture = _fixture()
	var target: CombatUnit = h.units[2]
	target.fallen = true
	target.distracted_turns = 2
	target.distracted_source = h.units[0]
	h.units[0].hit_points = 40
	target.hit_points = 40
	var agility: int = target.get_ability_sides(CombatUnit.Ability.AGILITY)
	h.actions.dice = _dice([1, 1, 3, 3], [agility, agility, 20, 20])
	await h.actions.firework_arrow(h.units[0], target.cell)
	_check(_logged(h, "민첩 내성(불리: 넘어짐, 산만함)"), "내성 로그에 요인 둘 " + str(h.logs))
	# 기름 미끌거림 로그.
	var k: Fixture = _fixture()
	var walker: CombatUnit = k.units[0]
	k.actions.create_oil(walker, Vector2i(3, 4))
	walker.distracted_turns = 2
	walker.distracted_source = k.units[3]
	k.actions.dice = _dice([1, 1], [20, 20])
	await k.actions.move_to(walker, Vector2i(3, 2))
	_check(_logged(k, "미끌거림(솜씨 내성 · 불리: 산만함)"), "미끌거림 로그에 이유 " + str(k.logs))
	var m: Fixture = _fixture()
	m.actions.create_oil(m.units[0], Vector2i(3, 4))
	m.actions.dice = _dice([10], [20])
	await m.actions.move_to(m.units[0], Vector2i(3, 2))
	_check(_logged(m, "미끌거림(솜씨 내성):"), "요인이 없는 미끌거림은 기존 문구")


## 나무 불타기(환경요소 5장, #529): 서 있는 나무는 벽 (4,3), 나무 (5,3)·(6,3)·(8,8)이다.
func _tree_fixture() -> Fixture:
	var f: Fixture = _fixture()
	f.actions.grid.blocked_cells = [Vector2i(4, 3), Vector2i(5, 3), Vector2i(6, 3), Vector2i(8, 8)]
	f.actions.grid.trees = [Vector2i(5, 3), Vector2i(6, 3), Vector2i(8, 8)]
	return f


func _test_tree_burn() -> void:
	var f: Fixture = _tree_fixture()
	var archer: CombatUnit = f.units[0]
	var tree: Vector2i = Vector2i(5, 3)
	# 고르기: 화염 동작만 사거리 안의 나무를 고른다. 벽·사거리 밖 나무는 못 고른다.
	_check(f.actions.can_aim(archer, "trick_arrow", tree) and f.actions.can_aim(archer, "firework_arrow", tree),
		"두 화살은 사거리 안의 나무 칸을 고름")
	_check(not f.actions.can_aim(archer, "trick_arrow", Vector2i(4, 3)) and not f.actions.can_aim(archer, "firework_arrow", Vector2i(4, 3)),
		"벽은 고르지 못함")
	_check(not f.actions.can_aim(archer, "trick_arrow", Vector2i(8, 8)) and not f.actions.can_aim(archer, "firework_arrow", Vector2i(8, 8)),
		"사거리 밖 나무는 고르지 못함")
	_check(not f.actions.can_aim(archer, "oil_throw", tree) and not f.actions.can_aim(archer, "fog", tree),
		"기름병·독안개는 나무 칸을 고르지 못함")
	# 영역: 폭죽은 나무 칸을 중심으로 계산하고 이웃 나무를 넣으며 벽은 뺀다. 독안개 영역은 나무를 뺀다.
	var area: Array[Vector2i] = f.actions.aim_area(archer, "firework_arrow", tree)
	_check(area.size() == 4 and tree in area and Vector2i(6, 3) in area and Vector2i(4, 3) not in area,
		"폭죽 영역은 나무 칸을 중심으로 이웃 나무를 넣고 벽을 뺌 " + str(area))
	_check(f.actions.aim_area(archer, "fog", Vector2i(5, 2)).has(tree) == false, "독안개 영역은 나무를 계속 뺌")
	# 장난스러운 화살: 화염 면이면 탄다. 불 장판·피해 없음.
	f.actions.dice = _dice([5], [6])
	_check(await f.actions.trick_arrow(archer, tree), "나무 칸에 장난스러운 화살을 쏨")
	_check(not f.actions.grid.is_tree(tree) and not f.actions.grid.is_blocked(tree) and f.actions.get_grounds().is_empty(),
		"화염 면: 나무가 사라지고 장판은 없음")
	_check("나무가 불탐: 5, 3" in f.logs, "불탐 로그 " + str(f.logs))
	_check(f.actions.grid.is_tree(Vector2i(6, 3)) and f.actions.grid.is_blocked(Vector2i(6, 3)), "이웃 나무는 번지지 않음")
	_check(not f.actions.touch_attribute(tree, "fire", archer) and f.logs.filter(func(line: String) -> bool: return "나무가 불탐" in line).size() == 1,
		"이미 탄 칸에 다시 닿아도 다시 타지 않음")
	# 열린 칸은 일반 바닥이다.
	_check(f.actions.grid.walk_costs(archer.cell).has(tree) and not f.actions.grid.path_to(archer, tree).is_empty(),
		"열린 칸으로 걸을 수 있음")
	_check(f.actions.grid.area_cells(Vector2i(5, 2), 1).has(tree), "열린 칸은 원형 범위에 들어감")
	_check(f.actions.create_prop(tree, "crate") != null, "열린 칸에 물체를 둘 수 있음")
	# 삐끗·물은 태우지 않는다(나무를 겨눌 수는 있다). 점프도 막히다 열린다.
	var g: Fixture = _tree_fixture()
	var shooter: CombatUnit = g.units[0]
	for face: int in [1, 3]:
		shooter.action_left = 1
		g.actions.dice = _dice([face], [6])
		await g.actions.trick_arrow(shooter, tree)
		_check(g.actions.grid.is_tree(tree) and g.actions.grid.is_blocked(tree), "삐끗·물은 나무를 태우지 않음: %d" % face)
	_check(not g.actions.touch_attribute(tree, "water", shooter) and g.actions.grid.is_tree(tree), "물이 닿아도 나무는 그대로")
	g.actions.create_ground(shooter, Vector2i(5, 4), "burn")
	_check(g.actions.grid.is_tree(tree) and g.actions.grid.is_tree(Vector2i(6, 3)), "인접 칸의 불 장판은 나무를 태우지 않음")
	shooter.cell = Vector2i(6, 5)
	_check(g.actions.grid.jump_path(shooter, Vector2i(6, 3)).is_empty(), "서 있는 나무 칸으로는 못 뜀")
	g.actions.touch_attribute(Vector2i(6, 3), "fire", shooter)
	_check(g.actions.grid.jump_path(shooter, Vector2i(6, 3)) == [Vector2i(6, 4), Vector2i(6, 3)], "열린 칸은 착지 칸이 됨")
	# 폭죽 화살: 영역 안 나무는 모두 타고(목표가 나무가 아니어도) 영역 밖 나무·벽은 그대로다.
	var h: Fixture = _tree_fixture()
	var bomber: CombatUnit = h.units[0]
	h.units[2].hit_points = 40
	h.actions.dice = _dice([1, 3, 2], [6, 20, 20])
	_check(await h.actions.firework_arrow(bomber, Vector2i(5, 3)), "나무 칸에 폭죽 화살을 쏨")
	_check(not h.actions.grid.is_tree(Vector2i(5, 3)) and not h.actions.grid.is_tree(Vector2i(6, 3))
		and h.actions.grid.is_tree(Vector2i(8, 8)) and h.actions.grid.is_blocked(Vector2i(4, 3)),
		"영역 안 나무만 타고 영역 밖 나무와 벽은 그대로")
	_check(h.units[2].hit_points == 40 - 5, "영역 안 유닛의 내성·피해는 지금과 같음")
	var k: Fixture = _tree_fixture()
	k.units[0].cell = Vector2i(5, 6)
	k.actions.dice = _dice([1, 3, 2], [6, 20, 20])
	await k.actions.firework_arrow(k.units[0], Vector2i(5, 4))
	_check(not k.actions.grid.is_tree(Vector2i(5, 3)) and k.actions.grid.is_tree(Vector2i(6, 3)),
		"목표가 나무가 아니어도 영역 안 나무가 탐")


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


## 설명 창 효과 줄의 DC는 레벨을 반영한 실제 DC(save_dc)다. 4로 고정하지 않는다.
func _test_firework_effect_dc() -> void:
	var archer: CombatUnit = CombatUnit.new()
	_created.append(archer)
	archer.kind = CombatUnit.Kind.ARCHER
	archer.is_ally = true
	for level: int in [0, 5]:
		archer.dice_level = level
		var dc: int = CombatActionRules.save_dc(archer, "firework_arrow")
		var effect: String = CombatActionRules.effect(archer, "firework_arrow")
		_check("민첩 내성(DC %d)" % dc in effect, "폭죽 화살 효과 줄이 실제 DC %d를 보임(레벨 %d): %s" % [dc, level, effect])
	_check(CombatActionRules.save_dc(archer, "firework_arrow") != 4 and "DC 4" not in CombatActionRules.effect(archer, "firework_arrow"),
		"레벨 5 궁수의 효과 줄에 DC 4가 고정으로 남지 않음: " + CombatActionRules.effect(archer, "firework_arrow"))


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


## 효시 횟수와 산만함(기간·시전자)은 선택 필드로 저장한다. 옛 형식 10 저장은 기본값으로 읽고 형식 번호는 그대로다.
func _test_whistle_save_state() -> void:
	var f: Fixture = _fixture()
	var archer: CombatUnit = f.units[0]
	var victim: CombatUnit = f.units[2]
	archer.whistle_left = 0
	victim.distracted_turns = 1
	victim.distracted_source = archer
	var saved: Array = f.units.map(func(unit: CombatUnit) -> Dictionary: return unit.save_state(f.units))
	_check(saved.all(func(data: Dictionary) -> bool: return archer.is_valid_state(data, 4, Vector2i(10, 10))), "산만함을 담은 유닛 저장은 유효")
	_check("whistle_left" not in CombatUnit.SAVED_FIELDS and "distracted_turns" not in CombatUnit.SAVED_FIELDS and GameSave.FORMAT_VERSION >= 11,
		"새 필드는 선택 필드이고 저장 형식 버전은 11 그대로(#575가 올린 번호)")
	var restored: CombatUnit = CombatUnit.new()
	_created.append(restored)
	restored.load_state(saved[2], f.units)
	_check(restored.distracted_turns == 1 and restored.distracted_source == archer, "산만함 기간과 시전자를 되돌림")
	var shooter: CombatUnit = CombatUnit.new()
	_created.append(shooter)
	shooter.load_state(saved[0], f.units)
	_check(shooter.whistle_left == 0 and shooter.distracted_turns == 0 and shooter.distracted_source == null, "효시 남은 횟수를 되돌리고 산만함은 없음")
	var old: Dictionary = (saved[2] as Dictionary).duplicate()
	for field: String in ["whistle_left", "distracted_turns", "distracted_source"]:
		old.erase(field)
	_check(archer.is_valid_state(old, 4, Vector2i(10, 10)), "새 필드가 없는 옛 저장도 유효")
	var legacy: CombatUnit = CombatUnit.new()
	_created.append(legacy)
	legacy.whistle_left = 0
	legacy.distracted_turns = 2
	legacy.distracted_source = archer
	legacy.load_state(old, f.units)
	_check(legacy.whistle_left == 1 and legacy.distracted_turns == 0 and legacy.distracted_source == null, "없는 필드는 효시 1회·산만함 없음으로 읽음")
	for broken: Dictionary in [{"distracted_turns": 3}, {"distracted_turns": -1}, {"distracted_turns": 2, "distracted_source": -1},
			{"distracted_turns": 0, "distracted_source": 0}, {"distracted_source": 4}, {"distracted_source": "0"}, {"whistle_left": -1}]:
		var data: Dictionary = (saved[2] as Dictionary).duplicate()
		data.merge(broken, true)
		_check(not archer.is_valid_state(data, 4, Vector2i(10, 10)), "깨진 산만함 필드 거부: " + str(broken))
	var keyless: Dictionary = (saved[2] as Dictionary).duplicate()
	keyless.erase("distracted_source")
	_check(not archer.is_valid_state(keyless, 4, Vector2i(10, 10)), "기간이 남았는데 시전자가 없는 저장 거부")


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
