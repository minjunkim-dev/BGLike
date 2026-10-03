extends SceneTree
## M1 3단계의 판정 수학, 상태 조건과 실제 클릭 경로를 검사한다.

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
	_test_modes()
	_test_attacks()
	_test_saves_and_contests()
	_test_probabilities()
	_test_preview_conditions()
	await _test_scene_input()
	for unit: CombatUnit in _created_units:
		unit.free()
	print("Combat checks: %d checks, %d failures" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error(message)


func _dice_for(expected: Array[int]) -> RandomNumberGenerator:
	var dice: RandomNumberGenerator = RandomNumberGenerator.new()
	for seed_value: int in range(100000):
		dice.seed = seed_value
		var matches: bool = true
		for value: int in expected:
			if dice.randi_range(1, 20) != value:
				matches = false
				break
		if matches:
			dice.seed = seed_value
			return dice
	_check(false, "주사위 fixture를 찾지 못함")
	return dice


func _unit(kind: CombatUnit.Kind, ally: bool, cell: Vector2i) -> CombatUnit:
	var unit: CombatUnit = CombatUnit.new()
	unit.kind = kind
	unit.is_ally = ally
	unit.cell = cell
	unit.hit_points = unit.get_max_hit_points()
	_created_units.append(unit)
	return unit


func _test_modes() -> void:
	_check(CombatChecks.roll_mode(0, 0) == CombatChecks.RollMode.NORMAL, "조건 없으면 일반")
	_check(CombatChecks.roll_mode(3, 0) == CombatChecks.RollMode.ADVANTAGE, "유리 여러 개는 한 번의 유리")
	_check(CombatChecks.roll_mode(0, 3) == CombatChecks.RollMode.DISADVANTAGE, "불리 여러 개는 한 번의 불리")
	_check(CombatChecks.roll_mode(3, 1) == CombatChecks.RollMode.NORMAL, "유리 수가 많아도 불리와 서로 취소")
	_check(CombatChecks.roll_mode(1, 3) == CombatChecks.RollMode.NORMAL, "불리 수가 많아도 유리와 서로 취소")


func _test_attacks() -> void:
	var normal: CombatChecks.RollMode = CombatChecks.RollMode.NORMAL
	var result: CombatChecks.RollResult = CombatChecks.attack(100, 1, normal, _dice_for([1]))
	_check(not result.success and not result.critical, "공격 보너스가 커도 자연1 자동 실패")
	result = CombatChecks.attack(-100, 999, normal, _dice_for([20]))
	_check(result.success and result.critical, "AC가 커도 자연20 명중과 치명타")
	result = CombatChecks.attack(5, 16, normal, _dice_for([11]))
	_check(result.success and not result.critical and result.total == 16, "AC와 합계가 같으면 명중")
	_check(result.rolls == [11], "일반은 주사위 하나를 보존")
	result = CombatChecks.attack(5, 16, normal, _dice_for([10]))
	_check(not result.success, "AC 바로 아래는 실패")
	result = CombatChecks.attack(5, 16, CombatChecks.RollMode.ADVANTAGE, _dice_for([1, 20]))
	_check(result.success and result.critical and result.selected_roll == 20, "유리는 선택된20으로 치명타")
	_check(result.rolls == [1, 20] and result.total == 25, "주사위 두 개와 선택값 합계 보존")
	result = CombatChecks.attack(100, 1, CombatChecks.RollMode.DISADVANTAGE, _dice_for([20, 1]))
	_check(not result.success and not result.critical and result.selected_roll == 1, "불리는 선택된1으로 실패")
	result = CombatChecks.attack(5, 16, CombatChecks.roll_mode(2, 1), _dice_for([11, 1]))
	_check(result.rolls == [11], "상쇄되면 주사위를 하나만 굴림")


func _test_saves_and_contests() -> void:
	var save: CombatChecks.RollResult = CombatChecks.saving_throw(20, 10, _dice_for([1]))
	_check(save.success and save.total == 21, "내성 자연1도 합계가 높으면 성공")
	save = CombatChecks.saving_throw(-20, 10, _dice_for([20]))
	_check(not save.success and not save.critical, "내성 자연20도 합계가 낮으면 실패")
	save = CombatChecks.saving_throw(1, 10, _dice_for([9]))
	_check(save.success, "내성 합계가 DC와 같으면 성공")
	save = CombatChecks.saving_throw(1, 13, _dice_for([9]))
	_check(not save.success, "호출자가 준 DC에 따라 판정하고 고정값을 선택하지 않음")
	var opposed: CombatChecks.ContestResult = CombatChecks.contest(3, 1, _dice_for([10, 12]))
	_check(not opposed.attacker_wins and opposed.attacker_total == 13 and opposed.defender_total == 13,
		"대결 보정값 포함 동점은 방어 승")
	opposed = CombatChecks.contest(3, 1, _dice_for([11, 12]))
	_check(opposed.attacker_wins and opposed.attacker_roll == 11 and opposed.defender_roll == 12,
		"대결 높은 합계 승리와 양쪽 주사위 보존")
	opposed = CombatChecks.contest(30, 0, _dice_for([1, 20]))
	_check(opposed.attacker_wins, "대결은 공격의 자연1/20 특례를 적용하지 않음")


func _test_probabilities() -> void:
	_check(is_equal_approx(CombatChecks.hit_chance(5, 16, CombatChecks.RollMode.NORMAL), 0.5), "전사 AC16에 일반50%")
	_check(is_equal_approx(CombatChecks.hit_chance(5, 14, CombatChecks.RollMode.NORMAL), 0.6), "궁수 AC14에 일반60%")
	_check(is_equal_approx(CombatChecks.hit_chance(5, 14, CombatChecks.RollMode.ADVANTAGE), 0.84), "유리84%")
	_check(is_equal_approx(CombatChecks.hit_chance(5, 14, CombatChecks.RollMode.DISADVANTAGE), 0.36), "불리36%")
	_check(is_equal_approx(CombatChecks.hit_chance(-100, 999, CombatChecks.RollMode.NORMAL), 0.05), "자연20의 최소5%")
	_check(is_equal_approx(CombatChecks.hit_chance(100, 1, CombatChecks.RollMode.NORMAL), 0.95), "자연1로 최대95%")
	_check(is_equal_approx(CombatChecks.hit_chance(-100, 999, CombatChecks.RollMode.DISADVANTAGE), 0.0025), "불리 최소0.25%")
	_check(is_equal_approx(CombatChecks.hit_chance(100, 1, CombatChecks.RollMode.ADVANTAGE), 0.9975), "유리 최대99.75%")


func _test_preview_conditions() -> void:
	var archer: CombatUnit = _unit(CombatUnit.Kind.ARCHER, true, Vector2i(4, 4))
	var target: CombatUnit = _unit(CombatUnit.Kind.ARCHER, false, Vector2i(7, 4))
	var nearby: CombatUnit = _unit(CombatUnit.Kind.WARRIOR, false, Vector2i(5, 5))
	var units: Array[CombatUnit] = [archer, target, nearby]
	var preview: CombatChecks.AttackPreview = CombatChecks.attack_preview(archer, target, units)
	_check(preview.in_range and preview.mode == CombatChecks.RollMode.DISADVANTAGE
		and is_equal_approx(preview.chance, 0.36) and "옆에 적" in preview.reasons, "대각선 인접 적도 원거리 불리")
	nearby.is_stunned = true
	preview = CombatChecks.attack_preview(archer, target, units)
	_check(preview.mode == CombatChecks.RollMode.NORMAL, "기절한 인접 적은 불리를 주지 않음")
	nearby.is_stunned = false
	nearby.hit_points = 0
	preview = CombatChecks.attack_preview(archer, target, units)
	_check(preview.mode == CombatChecks.RollMode.NORMAL, "전투 불능인 인접 적도 제외")
	nearby.hit_points = 12
	nearby.is_ally = true
	preview = CombatChecks.attack_preview(archer, target, units)
	_check(preview.mode == CombatChecks.RollMode.NORMAL, "인접한 아군은 불리 아님")
	target.is_stunned = true
	preview = CombatChecks.attack_preview(archer, target, units)
	_check(preview.mode == CombatChecks.RollMode.ADVANTAGE and is_equal_approx(preview.chance, 0.84), "기절 대상은 유리")
	nearby.is_ally = false
	preview = CombatChecks.attack_preview(archer, target, units)
	_check(preview.mode == CombatChecks.RollMode.NORMAL and is_equal_approx(preview.chance, 0.6)
		and preview.reasons.size() == 2, "기절 대상과 인접 적이 함께 있으면 상쇄")
	archer.is_stunned = true
	preview = CombatChecks.attack_preview(archer, target, units)
	_check(preview.chance == 0.0 and not preview.blocked_reason.is_empty(), "기절한 공격자는 공격 불가")
	archer.is_stunned = false
	target.is_stunned = false
	nearby.cell = Vector2i(0, 0)
	target.cell = Vector2i(4, 10)
	preview = CombatChecks.attack_preview(archer, target, units)
	_check(preview.in_range, "궁수 사거리6 경계 포함")
	target.cell = Vector2i(4, 11)
	preview = CombatChecks.attack_preview(archer, target, units)
	_check(not preview.in_range and preview.chance == 0.0, "궁수 사거리7 밖이면0%")
	archer.kind = CombatUnit.Kind.WARRIOR
	target.cell = Vector2i(5, 5)
	preview = CombatChecks.attack_preview(archer, target, units)
	_check(preview.in_range and preview.mode == CombatChecks.RollMode.NORMAL, "근접은 대각선1 가능, 옆 적 때문에 불리 없음")
	target.cell = archer.cell
	_check(not CombatChecks.attack_preview(archer, target, units).in_range, "같은 칸은 공격 사거리가 아님")
	target.is_ally = true
	_check(not CombatChecks.attack_preview(archer, target, units).valid_target, "아군 공격 대상 거부")
	target.is_ally = false
	target.hit_points = 0
	_check(not CombatChecks.attack_preview(archer, target, units).valid_target, "전투 불능 대상 거부")
	_check(archer.get_attribute(CombatUnit.Attribute.MENTAL) == -1, "전사 정신 -1")
	_check(target.get_attribute(CombatUnit.Attribute.MENTAL) == 1, "궁수 정신 +1")


func _test_scene_input() -> void:
	var scene: PackedScene = load("res://scenes/combat/battle.tscn") as PackedScene
	var battle: Node2D = scene.instantiate() as Node2D
	root.add_child(battle)
	await process_frame
	var turns: CombatTurns = battle.get("turns") as CombatTurns
	var units: Array[CombatUnit] = battle.get("units")
	var hud: CombatTurnHud = battle.get_node("UI/TurnHud") as CombatTurnHud
	var dice: RandomNumberGenerator = RandomNumberGenerator.new()
	dice.seed = 33
	turns.start(units, dice)
	var hp_before: int = units[2].hit_points
	var movement_before: int = units[0].movement_left
	var action_before: int = units[0].action_left
	await _click_unit(units[2])
	_check(battle.get("preview_target") == units[2], "실제 입력 경로로 적 도형 선택")
	_check(hud.unit_label.text == "적 전사" and "AC 16" in hud.resource_label.text, "클릭하면 적 HP/AC/상태 표시")
	_check("사거리 밖" in hud.preview_label.text and "0.0%" in hud.preview_label.text, "기본 배치의 사거리 밖 안내")
	await _click_unit(units[2])
	_check(units[2].hit_points == hp_before and units[0].movement_left == movement_before
		and units[0].action_left == action_before, "사거리 밖이면 두 번 눌러도 공격하거나 자원을 쓰지 않음")
	_check(units[0].is_selected and units[2].is_previewed, "조작 유닛과 미리보기 대상 표시 구분")
	await _click_point(Vector2(8, 120))
	_check(battle.get("preview_target") == null and hud.unit_label.text == "아군 전사",
		"빈 곳 클릭은 미리보기를 해제하고 현재 유닛을 표시")
	await _click_unit(units[2])
	turns.select_unit(units[1])
	_check(battle.get("preview_target") == null and hud.preview_label.text.is_empty()
		and hud.unit_label.text == "아군 궁수", "초상 전환 후 미리보기 해제")
	_check(battle.call("preview_enemy", units[3]), "새 조작 유닛으로 미리보기")
	var map: TileMapLayer = battle.get_node("Map") as TileMapLayer
	units[3].cell = Vector2i(5, 5)
	units[3].position = map.map_to_local(units[3].cell)
	battle.call("_clear_preview")
	await _click_unit(units[3])
	_check("60.0%" in hud.preview_label.text and "AC 14" in hud.resource_label.text
		and "HP 11 / 11" in hud.resource_label.text, "사거리 안 대상의 명중률과 능력치 표시")
	units[3].is_stunned = true
	battle.call("_clear_preview")
	await _click_unit(units[3])
	_check("84.0% · 유리" in hud.preview_label.text and "기절한 대상" in hud.preview_label.text,
		"기절 대상의 유리 확률과 이유 표시")
	units[2].cell = Vector2i(6, 9)
	units[2].position = map.map_to_local(units[2].cell)
	battle.call("_clear_preview")
	await _click_unit(units[3])
	_check("60.0% · 유리/불리 상쇄" in hud.preview_label.text
		and "기절한 대상, 옆에 적" in hud.preview_label.text, "상쇄 확률과 양쪽 이유 표시")
	units[3].is_stunned = false
	battle.call("_clear_preview")
	await _click_unit(units[3])
	_check("36.0% · 불리" in hud.preview_label.text and "옆에 적" in hud.preview_label.text,
		"인접 적에 따른 불리 확률과 이유 표시")
	hud.end_button.pressed.emit()
	_check(battle.get("preview_target") == null and hud.unit_label.text == "아군 전사", "턴 종료 후 미리보기 해제")
	await _click_unit(units[0])
	_check(battle.get("preview_target") == null, "아군 도형 클릭은 공격 미리보기 대상 아님")
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
