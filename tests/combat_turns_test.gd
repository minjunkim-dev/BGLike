extends SceneTree
## 턴 계약과 실제 전투 장면의 버튼 연결을 Godot에서 검사한다.

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
	_test_resources_and_groups()
	_test_available_actions()
	_test_removal()
	_test_rounds()
	await _test_scene()
	for unit: CombatUnit in _created_units:
		unit.free()
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
		units.append(unit)
		_created_units.append(unit)
	return units


func _ordered_fixture(units: Array[CombatUnit], order: Array[int]) -> CombatTurns:
	var desired: Array[CombatUnit] = []
	for index: int in order:
		desired.append(units[index])
	var turns: CombatTurns = CombatTurns.new()
	var dice: RandomNumberGenerator = RandomNumberGenerator.new()
	for seed_value: int in range(10000):
		dice.seed = seed_value
		turns.start(units, dice)
		if turns.ordered_units == desired:
			return turns
	_check(false, "이니셔티브 fixture를 찾지 못함")
	return turns


func _test_initiative() -> void:
	var units: Array[CombatUnit] = _make_units()
	var turns: CombatTurns = CombatTurns.new()
	var dice: RandomNumberGenerator = RandomNumberGenerator.new()
	var saw_dexterity_tie: bool = false
	var saw_team_tie: bool = false
	for seed_value: int in range(200):
		dice.seed = seed_value
		var expected_dice: RandomNumberGenerator = RandomNumberGenerator.new()
		expected_dice.seed = seed_value
		turns.start(units, dice)
		for unit: CombatUnit in units:
			_check(unit.initiative_roll == expected_dice.randi_range(1, 20), "유닛마다 d20 한 번")
			_check(unit.initiative_roll >= 1 and unit.initiative_roll <= 20, "d20 범위")
		for index: int in range(3):
			var first: CombatUnit = turns.ordered_units[index]
			var next: CombatUnit = turns.ordered_units[index + 1]
			_check(first.get_initiative() >= next.get_initiative(), "이니셔티브 내림차순")
			if first.get_initiative() == next.get_initiative():
				_check(first.get_dexterity() >= next.get_dexterity(), "동점: 민첩 높은 쪽 우선")
				if first.get_dexterity() != next.get_dexterity():
					saw_dexterity_tie = true
				elif first.is_ally != next.is_ally:
					saw_team_tie = true
					_check(first.is_ally, "민첩도 동점: 아군 우선")
	_check(saw_dexterity_tie and saw_team_tie, "동점 규칙 두 종류를 실제 주사위로 검증")
	var empty: CombatTurns = CombatTurns.new()
	empty.start([], dice)
	_check(empty.current_unit == null and not empty.end_turn(), "빈 전투에서 턴 종료 불가")


func _test_resources_and_groups() -> void:
	var units: Array[CombatUnit] = _make_units()
	var turns: CombatTurns = _ordered_fixture(units, [0, 1, 2, 3])
	_check(turns.get_turn_groups().size() == 2, "아군 둘과 적 둘은 두 묶음")
	_check(turns.get_current_group() == [units[0], units[1]], "아군 턴 묶음")
	_check(turns.current_unit == units[0], "가장 높은 이니셔티브부터 선택")
	_check(units[0].spend_movement(2) and units[0].spend_movement(3), "이동을 나누어 소비")
	_check(units[0].movement_left == 1, "나눈 이동 비용 합계")
	_check(not units[0].spend_movement(2), "남은 이동보다 큰 비용 거부")
	_check(not units[0].spend_movement(0) and not units[0].spend_movement(-1), "0과 음수 이동 거부")
	for resource: CombatUnit.TurnResource in CombatUnit.TurnResource.values():
		_check(units[0].spend_resource(resource), "각 자원을 한 번 소비")
		_check(not units[0].spend_resource(resource), "각 자원을 중복 소비할 수 없음")
	_check(turns.current_unit == units[0], "자원을 써도 자동 종료하지 않음")
	_check(turns.select_unit(units[1]), "같은 묶음의 아군으로 전환")
	_check(units[1].movement_left == 6 and units[1].action_left == 1, "다른 유닛 자원은 독립")
	_check(turns.select_unit(units[0]), "원래 유닛으로 복귀")
	_check(units[0].movement_left == 1 and units[0].action_left == 0
		and units[0].bonus_action_left == 0 and units[0].reaction_left == 0, "선택 전환으로 자원 회복 없음")
	_check(not turns.select_unit(units[2]), "다른 묶음 선택 거부")
	turns.select_unit(units[1])
	turns.end_turn()
	_check(turns.current_unit == units[0], "현재 유닛만 종료하고 남은 아군으로 전환")
	_check(not turns.select_unit(units[1]), "이미 끝낸 유닛은 다시 조작하지 못함")
	units[2].spend_resource(CombatUnit.TurnResource.REACTION)
	turns.end_turn()
	_check(turns.current_unit == units[2], "묶음 전원이 종료한 뒤 적으로 진행")
	_check(units[2].reaction_left == 1, "반응은 자기 묶음 진입 시 회복")
	_check(units[0].reaction_left == 0, "다른 편 턴에 아군 반응을 회복하지 않음")
	_check(not turns.select_unit(units[3]), "적 묶음은 임의 전환 없이 이니셔티브 순서")
	units[3].spend_movement(2)
	turns.end_turn()
	_check(turns.current_unit == units[3] and units[3].movement_left == 4, "적 내부 전환도 자원 회복 없음")
	turns.end_turn()
	_check(turns.round_number == 2 and turns.current_unit == units[0], "한 라운드 후 원래 순서로 반복")
	_check(units[0].movement_left == 6 and units[0].action_left == 1
		and units[0].bonus_action_left == 1 and units[0].reaction_left == 1, "다음 자기 턴에 자원 4종 회복")


func _test_available_actions() -> void:
	var unit: CombatUnit = _make_units()[0]
	_check(not unit.has_available_turn_action(false, false, false), "자원이 있어도 유효한 동작 대상 없으면 종료 강조")
	_check(unit.has_available_turn_action(true, false, false), "이동 목적지가 있으면 동작 가능")
	unit.spend_movement(6)
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
	_check(turns.current_unit == units[1] and units[1].movement_left == 4, "현재 유닛 탈락: 자원을 유지하고 남은 아군 선택")
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
	turns.remove_unit(units[2])
	_check(turns.get_current_group() == [units[0], units[1]], "중간 적 탈락 후 연속한 아군 묶음 결합")
	_check(units[0].movement_left == 4 and units[1].movement_left == 6, "결합 시 진행 중 자원 유지와 새 유닛 턴 시작")
	turns.end_turn()
	turns.end_turn()
	units[3].spend_movement(2)
	turns.remove_unit(units[0])
	_check(turns.current_unit == units[3] and units[3].movement_left == 4, "지나간 유닛 탈락은 현재 적 자원 유지")
	turns.remove_unit(units[3])
	_check(turns.round_number == 2 and turns.current_unit == units[1], "마지막 묶음 탈락 후 다음 라운드")


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
		"라운드 끝과 처음의 아군을 순서를 넘어서 묶지 않음")


func _test_scene() -> void:
	var scene: PackedScene = load("res://scenes/combat/battle.tscn") as PackedScene
	var battle: Node2D = scene.instantiate() as Node2D
	root.add_child(battle)
	battle.set_process(false)
	await process_frame
	var turns: CombatTurns = battle.get("turns") as CombatTurns
	var hud: CombatTurnHud = battle.get_node("UI/TurnHud") as CombatTurnHud
	var scene_units: Array[CombatUnit] = battle.get("units")
	var dice: RandomNumberGenerator = RandomNumberGenerator.new()
	for seed_value: int in range(10000):
		dice.seed = seed_value
		turns.start(scene_units, dice)
		if turns.ordered_units == scene_units:
			break
	_check(turns.get_current_group().size() == 2, "장면 확인용 아군 묶음")
	var panel: Node = hud.order_bar.get_child(0)
	var portraits: Node = panel.get_child(0)
	var archer_button: Button = portraits.get_child(1) as Button
	# 순서가 같은 채 데이터가 바뀌어도 기존 초상의 숫자와 툴팁을 갱신한다.
	scene_units[1].initiative_roll += 1
	hud.refresh(turns, false)
	_check(archer_button.text.ends_with(str(scene_units[1].get_initiative())), "같은 순서의 이니셔티브 숫자 갱신")
	_check(archer_button.tooltip_text.ends_with(str(scene_units[1].get_initiative())), "같은 순서의 이니셔티브 툴팁 갱신")
	_check(not archer_button.disabled, "같은 묶음의 아군 초상 활성")
	archer_button.pressed.emit()
	_check(turns.current_unit == scene_units[1] and hud.unit_label.text == "아군 궁수",
		"초상 클릭 신호의 대상과 정보 표시가 일치")
	hud.end_button.pressed.emit()
	var current: CombatUnit = turns.current_unit
	archer_button.pressed.emit()
	_check(not archer_button.disabled and turns.current_unit == current
		and hud.unit_label.text == "아군 궁수", "턴을 끝낸 초상은 정보만 조회하며 조작 전환 없음")
	hud.unit_selected.emit(current)
	var old_round: int = turns.round_number
	_check(hud.unit_label.text == current.get_display_name(), "장면 연결: 현재 유닛 표시")
	_check(current.is_selected, "장면 연결: 현재 유닛 선택 테두리")
	var style: StyleBoxFlat = hud.end_button.get_theme_stylebox("normal") as StyleBoxFlat
	_check(style.bg_color == CombatTurnHud.DEFAULT_BUTTON_COLOR, "이동할 수 있으면 종료 강조 없음")
	current.movement_left = 0
	battle.call("_update_turn_ui")
	style = hud.end_button.get_theme_stylebox("normal") as StyleBoxFlat
	_check(style.bg_color == CombatTurnHud.END_BUTTON_COLOR, "유효한 동작 없으면 버튼 색만 강조")
	await process_frame
	_check(turns.current_unit == current, "실행 가능한 동작이 없어도 자동 종료 없음")
	hud.end_button.pressed.emit()
	_check(turns.current_unit != current or turns.round_number != old_round, "턴 종료 버튼의 신호가 실제 모델에 연결됨")
	battle.queue_free()
	await process_frame
