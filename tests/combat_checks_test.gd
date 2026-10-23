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
	_test_opposed_chances()
	await _test_battle_rolls()
	_test_preview_conditions()
	await _test_scene_input()
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
		[CombatUnit.Kind.WARRIOR, true, [20, 8, 6, 4, 12, 6]],
		[CombatUnit.Kind.ARCHER, true, [8, 20, 12, 6, 4, 6]],
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
	_check(CombatChecks.roll_mode(3, 1) == CombatChecks.RollMode.NORMAL, "유리 수가 많아도 불리와 서로 취소")
	_check(CombatChecks.roll_mode(1, 3) == CombatChecks.RollMode.NORMAL, "불리 수가 많아도 유리와 서로 취소")


func _test_opposed_rolls() -> void:
	var normal: CombatChecks.RollMode = CombatChecks.RollMode.NORMAL
	var result: CombatChecks.RollResult = CombatChecks.opposed_attack(
		20, 10, 1, 2, normal, ScriptedDice.new([7, 6], [20, 10]))
	_check(result.rolls == [7] and result.total == 8
		and result.defender_roll == 6 and result.defender_total == 8
		and not result.success and not result.critical, "대결의 원본 굴림과 장비 가산을 보존, 동점 방어자 승")
	result = CombatChecks.opposed_attack(
		4, 20, 30, 0, normal, ScriptedDice.new([1, 20], [4, 20]))
	_check(result.success and not result.critical, "최솟값도 합계가 높으면 성공, 자동 실패 없음")
	result = CombatChecks.opposed_attack(
		20, 4, 0, 30, normal, ScriptedDice.new([20, 1], [20, 4]))
	_check(not result.success and not result.critical, "최댓값도 합계가 낮으면 실패, 치명타 없음")
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
	_check(result.success, "자연 d6 대 독 강도4는 동점 제거 성공")
	_check(is_equal_approx(CombatChecks.threshold_chance(6, 0, 4), 0.5), "독 제거 확률 50%")
	_check(CombatChecks.threshold_chance(8, 3, 30) == 0.0
		and CombatChecks.threshold_chance(8, 3, 1) == 1.0, "흘려내기 확률은 0~100%")
	var shared: CombatChecks.RollResult = CombatChecks.attack_roll(12, 3, normal, ScriptedDice.new([8], [12]))
	var first: CombatChecks.RollResult = CombatChecks.defend_against(shared, 20, 0, ScriptedDice.new([10], [20]))
	var second: CombatChecks.RollResult = CombatChecks.defend_against(shared, 8, 4, ScriptedDice.new([8], [8]))
	_check(first.total == 11 and second.total == 11 and first.success and not second.success,
		"광역은 같은 공격 굴림과 대상별 방어를 비교")
	_check(first.defender_roll == 10 and shared.defender_roll == 0, "다음 대상의 방어는 이전 대상·공통 공격을 변경하지 않음")


func _test_opposed_chances() -> void:
	var normal: CombatChecks.RollMode = CombatChecks.RollMode.NORMAL
	_check(is_equal_approx(CombatChecks.opposed_chance(20, 10, 0, 0, normal), 0.725),
		"전사 힘 d20 대 야만인 힘 d10의 명중률 72.5%")
	for sides: Array in [[4, 4], [20, 10], [4, 20], [8, 12], [12, 6], [20, 20]]:
		for bonuses: Array in [[0, 0], [1, 0], [0, 1], [-3, 4], [30, 0], [0, 30]]:
			for mode: CombatChecks.RollMode in [normal, CombatChecks.RollMode.ADVANTAGE, CombatChecks.RollMode.DISADVANTAGE]:
				var expected: float = _enumerated_opposed_chance(sides[0], sides[1], bonuses[0], bonuses[1], mode)
				var actual: float = CombatChecks.opposed_chance(sides[0], sides[1], bonuses[0], bonuses[1], mode)
				_check(is_equal_approx(actual, expected), "모든 실제 굴림 조합과 명중률 일치 %s %s %s" % [sides, bonuses, mode])


func _enumerated_opposed_chance(attack_sides: int, defense_sides: int,
	attack_bonus: int, defense_bonus: int, mode: CombatChecks.RollMode) -> float:
	var hits: int = 0
	var count: int = 0
	for first: int in range(1, attack_sides + 1):
		for second: int in range(1, (1 if mode == CombatChecks.RollMode.NORMAL else attack_sides) + 1):
			var attack: int = first
			if mode == CombatChecks.RollMode.ADVANTAGE:
				attack = maxi(first, second)
			elif mode == CombatChecks.RollMode.DISADVANTAGE:
				attack = mini(first, second)
			for defense: int in range(1, defense_sides + 1):
				count += 1
				if attack + attack_bonus > defense + defense_bonus:
					hits += 1
	return hits / float(count)


func _test_battle_rolls() -> void:
	var warrior: CombatUnit = _unit(CombatUnit.Kind.WARRIOR, true, Vector2i(4, 4))
	var archer: CombatUnit = _unit(CombatUnit.Kind.ARCHER, true, Vector2i(3, 4))
	var barbarian: CombatUnit = _unit(CombatUnit.Kind.WARRIOR, false, Vector2i(5, 4))
	var units: Array[CombatUnit] = [warrior, archer, barbarian]
	var turns: CombatTurns = CombatTurns.new()
	var actions: CombatActions = CombatActions.new()
	actions.initialize(units, turns)
	ScriptedDice.arrange_turns(turns, units, [warrior, archer, barbarian])
	actions.dice = ScriptedDice.new([11, 10, 2], [20, 10, 8])
	var before: int = barbarian.hit_points
	_check(await actions.attack(warrior, barbarian) and barbarian.hit_points == before - 5
		and actions.last_attack.total == 11 and actions.last_attack.defender_total == 10
		and not actions.last_attack.critical and actions.last_damage_rolls == [2],
		"실제 기본 공격이 양쪽 능력치 주사위를 비교하고 피해를 한 번 굴림")
	barbarian.cell = Vector2i(3, 7)
	turns.select_unit(archer)
	actions.dice = ScriptedDice.new([10, 6, 1], [20, 6, 6])
	_check(await actions.attack(archer, barbarian, true) and barbarian.is_stunned
		and actions.last_attack.defender_roll == 6 and actions.last_damage == 2,
		"충격 화살은 원거리 민첩 대결 명중 후 추가 굴림 없이 기절")
	barbarian.is_stunned = false
	barbarian.cell = Vector2i(5, 4)
	ScriptedDice.arrange_turns(turns, units, [barbarian, warrior, archer])
	actions.replay_answers = [true]
	actions.dice = ScriptedDice.new([7, 3, 7], [10, 20, 8])
	before = warrior.hit_points
	_check(await actions.attack(barbarian, warrior) and warrior.hit_points == before
		and actions.last_attack.total == 10 and warrior.parry_left == 1,
		"흘려내기 민첩7+3이 이미 굴린 공격10과 같으면 방어, 피해 주사위 없음")
	_check(actions.apply_status(barbarian, warrior, "poison"), "강도4 독 부여")
	actions.dice = ScriptedDice.new([4], [6])
	turns.end_turn()
	_check(warrior.get_status_count("poison") == 0 and warrior.hit_points == before,
		"턴 시작 자연d6의4로 독 강도4 제거 후 독 피해 없음")
	var boss: CombatUnit = _unit(CombatUnit.Kind.SCRAP_ROBOT_3000, false, Vector2i(4, 4))
	warrior.cell = Vector2i(4, 3)
	archer.cell = Vector2i(4, 5)
	units = [boss, warrior, archer]
	actions.initialize(units, turns)
	ScriptedDice.arrange_turns(turns, units, [boss, warrior, archer])
	actions.replay_answers = [false]
	actions.dice = ScriptedDice.new([8, 1, 2, 1, 3], [12, 20, 8, 8, 8])
	var warrior_before: int = warrior.hit_points
	var archer_before: int = archer.hit_points
	_check(await actions.spin(boss) and warrior.hit_points == warrior_before - 4
		and archer.hit_points == archer_before - 5 and actions.last_attack.total == 11,
		"실제 회전 베기는 공통 공격8+3과 두 대상의 방어를 비교하고 각각 피해")
	# 신호가 actions와 turns를 함께 붙잡지 않게 연결을 해제한다.
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
		and is_equal_approx(preview.chance, 0.54625) and "옆에 적" in preview.reasons, "헥사 인접 적도 원거리 불리")
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
	_check(preview.mode == CombatChecks.RollMode.ADVANTAGE and is_equal_approx(preview.chance, 0.90375), "기절 대상은 유리")
	nearby.is_ally = false
	preview = grid.attack_preview(archer, target)
	_check(preview.mode == CombatChecks.RollMode.NORMAL and is_equal_approx(preview.chance, 0.725)
		and preview.reasons.size() == 2, "기절 대상과 인접 적이 함께 있으면 상쇄")
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
	_check(archer.get_ability_sides(CombatUnit.Ability.WILL) == 12, "전사 의지 d12")
	_check(target.get_ability_sides(CombatUnit.Ability.WILL) == 4, "풋내기 궁수 의지 d4")


func _test_scene_input() -> void:
	var scene: PackedScene = load("res://scenes/combat/battle.tscn") as PackedScene
	var battle: Node2D = scene.instantiate() as Node2D
	battle.stages[0] = load("res://scenes/combat/stage.tres") as CombatStage
	root.add_child(battle)
	battle.set_process(false)
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
	_check(hud.unit_label.text == "풋내기 야만인" and "방어 +0" in hud.resource_label.text, "클릭하면 적 HP/방어/상태 표시")
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
	_check("72.5%" in hud.preview_label.text and "방어 +0" in hud.resource_label.text
		and "HP 14 / 14" in hud.resource_label.text, "사거리 안 대상의 명중률과 능력치 표시")
	units[3].is_stunned = true
	(battle.get("selection") as CombatSelection).clear_preview()
	await _click_unit(units[3])
	_check("90.4% · 유리" in hud.preview_label.text and "기절한 대상" in hud.preview_label.text,
		"기절 대상의 유리 확률과 이유 표시")
	units[2].cell = Vector2i(6, 9)
	units[2].position = map.map_to_local(units[2].cell)
	(battle.get("selection") as CombatSelection).clear_preview()
	await _click_unit(units[3])
	_check("72.5% · 유리/불리 상쇄" in hud.preview_label.text
		and "기절한 대상, 옆에 적" in hud.preview_label.text, "상쇄 확률과 양쪽 이유 표시")
	units[3].is_stunned = false
	(battle.get("selection") as CombatSelection).clear_preview()
	await _click_unit(units[3])
	_check("54.6% · 불리" in hud.preview_label.text and "옆에 적" in hud.preview_label.text,
		"인접 적에 따른 불리 확률과 이유 표시")
	hud.end_button.pressed.emit()
	_check((battle.get("selection") as CombatSelection).preview_target == null and hud.unit_label.text == "아군 전사", "턴 종료 후 미리보기 해제")
	await _click_unit(units[0])
	_check((battle.get("selection") as CombatSelection).preview_target == null, "아군 도형 클릭은 공격 미리보기 대상 아님")
	turns.end_turn()
	_check(not battle.call("preview_enemy", units[0]), "적 턴에는 아군 조작 미리보기 불가")
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
