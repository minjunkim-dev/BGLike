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
	first.queue_free()
	second.queue_free()
	await process_frame
