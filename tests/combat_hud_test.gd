extends SceneTree
## 실제 장면의 화면 상태, 입력 연결, 전투 종료와 재시작을 검사한다.

var checks: int = 0
var failures: int = 0
var battle: Node2D
var units: Array[CombatUnit]
var turns: CombatTurns
var actions: CombatActions
var hud: CombatTurnHud


func _initialize() -> void:
	_run.call_deferred()


func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)


func _run() -> void:
	var scene: PackedScene = load("res://scenes/main.tscn") as PackedScene
	var main: Node = scene.instantiate()
	root.add_child(main)
	current_scene = main
	await process_frame
	battle = current_scene.get_node("Battle") as Node2D
	units = battle.get("units")
	turns = battle.get("turns") as CombatTurns
	actions = battle.get("actions") as CombatActions
	hud = battle.get_node("UI/TurnHud") as CombatTurnHud
	var dice: RandomNumberGenerator = RandomNumberGenerator.new()
	dice.seed = 33
	turns.start(units, dice)
	units[2].cell = Vector2i(4, 8)
	units[3].cell = Vector2i(7, 9)
	battle.call("_update_turn_ui")
	await process_frame
	await process_frame
	_test_warrior()
	await _test_resources()
	_test_archer_and_enemy()
	await _test_log_and_status()
	await _test_layout()
	await _test_guidance()
	await _test_order_bar_input()
	await _test_reaction_flow()
	await _test_results_and_restart()
	current_scene.queue_free()
	await process_frame
	print("Combat HUD: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)


func _test_warrior() -> void:
	var buttons: Dictionary = hud.get("_actions")
	var badges: Dictionary = hud.get("_badges")
	var costs: Dictionary = hud.get("_costs")
	var titles: Array = hud.get("_titles")
	_check(hud.unit_label.text == "아군 전사" and "HP 12 / 12" in hud.resource_label.text
		and "AC 16" in hud.resource_label.text and "이동 6 / 6" in hud.resource_label.text,
		"현재 유닛 정보: HP·AC·남은 이동")
	_check(hud.health_bar.value == 12, "현재 유닛 HP 바")
	for action: String in ["attack", "second_wind", "surge", "shove", "potion", "opportunity", "parry"]:
		_check((buttons[action] as Button).is_visible_in_tree(), "전사 동작 표시: " + action)
	for action: String in ["mark", "shock", "disengage"]:
		_check(not (buttons[action] as Button).visible, "궁수 동작 숨김: " + action)
	_check((titles[0] as Label).text == "행동 ● · 남음" and (titles[1] as Label).text == "보조 행동 ▲ · 남음"
		and (titles[2] as Label).text == "반응 ◆ · 남음", "컨테이너 제목이 자원 표시")
	_check(not (badges["attack"] as Label).visible and not (badges["shove"] as Label).visible,
		"횟수 제한이 없는 동작은 배지 숨김")
	_check((badges["parry"] as Label).text == "2" and (costs["parry"] as Label).text == "◆",
		"비용 기호와 횟수 숫자 분리")
	var badge: Label = badges["parry"] as Label
	var cost: Label = costs["parry"] as Label
	_check(badge.size.y <= 15 and not badge.get_global_rect().intersects(cost.get_global_rect()),
		"횟수 배지는 작고 비용 기호와 겹치지 않음: badge=%s cost=%s min=%s font=%d fontheight=%f" % [
			badge.get_global_rect(), cost.get_global_rect(), badge.get_combined_minimum_size(),
			badge.get_theme_font_size("font_size"), badge.get_theme_font("font").get_height(9)])
	_check((buttons["surge"] as Button).disabled and (buttons["second_wind"] as Button).disabled
		and (buttons["potion"] as Button).disabled, "효과 없는 동작 비활성화")
	var before: int = units[0].reaction_left
	(buttons["opportunity"] as Button).pressed.emit()
	(buttons["parry"] as Button).pressed.emit()
	_check(units[0].reaction_left == before and battle.get("selected_action") == "attack",
		"자기 턴의 반응 항목은 아무 동작도 실행하지 않음")


func _test_resources() -> void:
	var buttons: Dictionary = hud.get("_actions")
	var titles: Array = hud.get("_titles")
	units[0].action_left = 0
	units[0].reaction_left = 0
	units[0].parry_left = 0
	battle.call("_update_turn_ui")
	_check((titles[0] as Label).text == "행동 ○ · 사용함" and (titles[2] as Label).text == "반응 ◇ · 사용함",
		"소비 자원은 빈 기호")
	_check(not (buttons["surge"] as Button).disabled, "공격을 쓴 뒤 몰아치기 활성화")
	_check(not (buttons["parry"] as Button).disabled, "자기 턴 반응 항목은 자원·횟수0도 켜진 표시")
	(buttons["surge"] as Button).pressed.emit()
	_check(units[0].action_left == 0 and units[0].surge_left == 1, "자기 대상 첫 클릭은 미리보기")
	(buttons["surge"] as Button).pressed.emit()
	_check((titles[0] as Label).text == "행동 ● · 남음" and (titles[1] as Label).text == "보조 행동 △ · 사용함",
		"몰아치기는 기호 한 개만 다시 채움")
	_check(units[0].surge_left == 0 and (buttons["surge"] as Button).disabled, "횟수 소진 비활성화")
	units[0].movement_left = 0
	units[0].action_left = 0
	battle.call("_update_turn_ui")
	var style: StyleBoxFlat = hud.end_button.get_theme_stylebox("normal") as StyleBoxFlat
	_check(style.bg_color == CombatTurnHud.END_BUTTON_COLOR and turns.current_unit == units[0],
		"할 일이 없으면 색만 변경하고 턴 유지")
	await process_frame


func _test_archer_and_enemy() -> void:
	var buttons: Dictionary = hud.get("_actions")
	var containers: Array = hud.get("_containers")
	var before: int = units[0].movement_left
	hud.unit_selected.emit(units[1])
	_check(turns.current_unit == units[1] and units[0].movement_left == before, "초상 전환 자원 유지")
	_check(not (containers[2] as PanelContainer).visible, "궁수 반응 컨테이너 숨김")
	_check((buttons["shock"] as Button).visible and not (buttons["surge"] as Button).visible,
		"궁수 스킬만 표시")
	_check(battle.call("preview_enemy", units[2]), "적 미리보기 연결")
	_check(hud.unit_label.text == "적 전사" and "AC 16" in hud.resource_label.text,
		"미리보기는 유닛 정보 자리를 사용")
	_check((buttons["shock"] as Button).visible, "미리보기에도 현재 아군의 스킬 유지")
	hud.unit_selected.emit(units[0])
	hud.end_button.pressed.emit()
	hud.end_button.pressed.emit()
	_check(not turns.current_unit.is_ally and hud.unit_label.text == turns.current_unit.get_display_name(),
		"적 턴에는 행동 중인 적 정보")
	_check(hud.move_button.text == "이동", "적 턴 이동 버튼은 아군의 이동력으로 혼동할 숫자를 표시하지 않음")
	_check((buttons["shock"] as Button).visible and (buttons["shock"] as Button).disabled
		and not (containers[2] as PanelContainer).visible, "적 턴에는 마지막 궁수 패널 회색 유지")
	for button: Button in buttons.values():
		if button.is_visible_in_tree():
			_check(button.disabled, "적 턴 입력 잠금: " + button.text)
	actions.busy = true
	battle.call("_update_turn_ui")
	_check(hud.end_button.disabled, "반응 대기 중 턴 종료 잠금")
	actions.busy = false


func _test_log_and_status() -> void:
	hud.add_log("첫째")
	hud.add_log("둘째")
	hud.add_log("셋째")
	hud.add_log("넷째")
	_check(hud.message_label.text == "둘째\n셋째\n넷째", "최근 로그는 정확히3줄")
	units[1].marked_target = units[2]
	units[2].is_stunned = true
	units[2].hit_points = 5
	battle.call("_update_turn_ui")
	hud.show_unit(units[2])
	_check(units[2].has_mark and "기절" in hud.resource_label.text and "◎ 표식" in hud.resource_label.text,
		"기절과 표식은 유닛 표시와 정보에 함께 반영")
	_check(hud.health_bar.value == 5, "대상 HP 갱신")
	units[1].marked_target = null
	battle.call("_update_turn_ui")
	_check(not units[2].has_mark, "표식 해제 표시")
	# 실제 동작의 판정 로그와 숫자 팝업 연결. 마지막 적이 아닌 대상에 확정 명중.
	units[2].is_stunned = false
	units[2].reaction_left = 0
	units[2].hit_points = 12
	var dice: RandomNumberGenerator = RandomNumberGenerator.new()
	dice.seed = 33
	turns.start(units, dice)
	turns.select_unit(units[1])
	units[1].marked_target = units[2]
	units[2].cell = Vector2i(5, 8)
	actions.dice = _dice_for_miss()
	await actions.attack(units[1], units[2])
	_check(_has_two_dice_log("불리"),
		"불리 판정은 로그에 주사위 두 값을 모두 표시")
	var parent: Node = units[2].get_parent()
	var has_popup: bool = false
	for child: Node in parent.get_children():
		if child is Label and child.text == "빗나감":
			has_popup = true
	_check(has_popup, "실제 판정의 숫자 팝업 연결")
	units[1].action_left = 1
	units[2].is_stunned = true
	actions.dice.seed = 100
	await actions.attack(units[1], units[2])
	_check(_has_two_dice_log("유리"),
		"유리 판정은 로그에 주사위 두 값을 모두 표시")
	_check("표식 추가" in hud.message_label.text, "표식 추가 피해를 로그에 명시")


func _has_two_dice_log(mode: String) -> bool:
	var marker: String = "공격(%s): d20 [" % mode
	for line: String in hud.message_label.text.split("\n"):
		if marker not in line:
			continue
		var values: PackedStringArray = line.get_slice(marker, 1).get_slice("]", 0).split(", ")
		return values.size() == 2 and values[0].is_valid_int() and values[1].is_valid_int()
	return false


func _dice_for_miss() -> RandomNumberGenerator:
	var dice: RandomNumberGenerator = RandomNumberGenerator.new()
	for value: int in range(1000):
		dice.seed = value
		var first: int = dice.randi_range(1, 20)
		var second: int = dice.randi_range(1, 20)
		if mini(first, second) < 11:
			dice.seed = value
			return dice
	return dice


func _test_layout() -> void:
	for size: Vector2i in [Vector2i(640, 360), Vector2i(800, 360), Vector2i(683, 384)]:
		root.size = size
		await process_frame
		await process_frame
		for kind: CombatUnit.Kind in [CombatUnit.Kind.WARRIOR, CombatUnit.Kind.ARCHER]:
			var actor: CombatUnit = units[0] if kind == CombatUnit.Kind.WARRIOR else units[1]
			actor.hit_points = actor.get_max_hit_points()
			hud.refresh_actions(actions, "attack", actor)
			# 적 턴에서도 마지막 아군 패널의 최소 크기를 검사한다.
			if turns.current_unit.is_ally:
				turns.select_unit(actor)
			await process_frame
			await process_frame
			var area: Rect2 = hud.get_global_rect()
			for control: Control in [hud.order_bar, hud.action_bar, hud.message_label,
				hud.end_button, hud.move_button, hud.resource_label, hud.help_label, hud.preview_label]:
				_check(area.encloses(control.get_global_rect()), "%s: 화면 안 %s" % [size, control.name])
			var skills: Rect2 = (hud.get_node("Skills") as Control).get_global_rect()
			_check(not skills.intersects(hud.end_button.get_global_rect()), "스킬과 턴 종료가 겹치지 않음")
			var badges: Dictionary = hud.get("_badges")
			var costs: Dictionary = hud.get("_costs")
			for action: String in badges:
				var badge: Label = badges[action] as Label
				if badge.is_visible_in_tree():
					_check(badge.size.y <= 15 and not badge.get_global_rect().intersects(
						(costs[action] as Label).get_global_rect()), "크기 변경 후 배지 분리: " + action)
	root.size = Vector2i(640, 360)
	await process_frame


func _test_guidance() -> void:
	_reset_units()
	units[0].cell = Vector2i(1, 1)
	units[1].cell = Vector2i(0, 0)
	units[2].cell = Vector2i(3, 1)
	units[3].cell = Vector2i(9, 9)
	units[2].reaction_left = 0
	units[0].movement_left = 2
	battle.call("_update_turn_ui")
	var buttons: Dictionary = hud.get("_actions")
	_check("비용: 행동 ●" in hud.help_label.text
		and "지금 사용 불가" in hud.help_label.text, "선택 동작의 비용과 사거리 조건 설명")
	_check("자기 턴 시작" in (hud.get("_titles") as Array)[0].tooltip_text
		and "6칸" in hud.move_button.tooltip_text, "자원 회복 시점과 별도 이동 자원 설명")
	var title: Label = (hud.get("_titles") as Array)[0] as Label
	var hovered: Array[bool] = [false]
	title.mouse_entered.connect(func() -> void: hovered[0] = true, CONNECT_ONE_SHOT)
	var motion: InputEventMouseMotion = InputEventMouseMotion.new()
	motion.position = root.get_final_transform() * title.get_global_rect().get_center()
	motion.global_position = motion.position
	Input.parse_input_event(motion)
	await process_frame
	_check(title.mouse_filter != Control.MOUSE_FILTER_IGNORE and hovered[0],
		"자원 제목의 툴팁은 문자열뿐 아니라 실제 포인터 입력을 받음")
	_check("이번 턴 비용" in (buttons["attack"] as Button).tooltip_text
		and "이번 전투의 남은 횟수" in (buttons["parry"] as Button).tooltip_text,
		"비용 기호와 횟수 숫자의 뜻 설명")
	hud.move_button.pressed.emit()
	var cells: Array[Vector2i] = battle.get("movement_cells")
	_check(cells.has(Vector2i(2, 1)) and not cells.has(units[2].cell)
		and not cells.has(Vector2i(5, 1)) and not cells.has(units[0].cell),
		"이동 가능 범위는 남은 이동·점유 칸·현재 칸을 반영")
	_check("이동은 행동을 쓰지 않습니다" in hud.help_label.text
		and "초록" in hud.help_label.text and "2칸" in hud.move_button.text, "이동 범위 범례와 현재 이동력")
	await battle.call("_select_move_cell", Vector2i(2, 1))
	_check("이동 1칸 → 1칸 남음" in hud.preview_label.text
		and "도착 시 공격 가능: 1명" in hud.preview_label.text and units[2].is_previewed,
		"선택한 목적지의 비용과 도착 시 공격 대상 표시")
	_check("도착 시 공격 가능: 1명" in hud.help_label.text and not hud.preview_label.visible,
		"이동 예측은 격자를 가리지 않는 설명 패널에 표시")
	_check(units[0].cell == Vector2i(1, 1) and units[0].movement_left == 2 and units[0].action_left == 1
		and not actions.can_target(units[0], units[2], "attack")
		and actions.can_target(units[0], units[2], "attack", Vector2i(2, 1)),
		"미리보기는 유닛·자원을 바꾸지 않고 이동 위치에서 같은 공격 판정을 사용")
	units[0].action_left = 0
	battle.call("_update_turn_ui")
	_check("공격 불가: 행동을 이미 씀" in hud.preview_label.text
		and not units[2].is_previewed and not (battle.get("movement_cells") as Array).is_empty(),
		"행동을 썼으면 이동은 가능하지만 도착 시 공격 불가")
	await process_frame
	await process_frame
	_check(not (hud.get_node("ActionHelp") as Control).get_global_rect().intersects(
		(hud.get_node("CombatLog") as Control).get_global_rect()), "행동 소진 이동 안내도 설명과 로그가 겹치지 않음")
	units[0].action_left = 1
	await battle.call("_select_move_cell", Vector2i(1, 3))
	_check("이동 2칸 → 0칸 남음" in hud.preview_label.text
		and "공격 불가: 사거리 안 적 없음" in hud.preview_label.text, "이동은 가능해도 공격 사거리가 닿지 않는 칸 설명")
	await process_frame
	await process_frame
	_check(not (hud.get_node("ActionHelp") as Control).get_global_rect().intersects(
		(hud.get_node("CombatLog") as Control).get_global_rect()), "사거리 밖 이동 안내도 설명과 로그가 겹치지 않음")
	(buttons["attack"] as Button).pressed.emit()
	units[0].disengaged = true
	await battle.call("_select_move_cell", Vector2i(2, 1))
	_check(hud.help_title.text == "이동 미리보기" and "이번 턴 기회 공격 없음" in hud.help_label.text
		and "반격 주의" not in hud.help_label.text and not hud.preview_label.visible,
		"기본 공격 모드의 빈 칸 클릭도 이동 안내와 적용 중인 기회 공격 면제를 표시")
	units[0].disengaged = false
	hud.move_button.pressed.emit()
	_check(battle.get("selected_action") == "move", "실제 이동 조작은 이동 모드에서 시작")
	var map: TileMapLayer = battle.get_node("Map") as TileMapLayer
	var move_point: Vector2 = map.get_global_transform_with_canvas() * map.map_to_local(Vector2i(2, 1))
	await _click(move_point)
	_check(battle.get("preview_cell") == Vector2i(2, 1) and units[0].cell == Vector2i(1, 1),
		"이동 모드의 실제 첫 클릭은 경로 확인만 실행")
	await _click(move_point)
	_check(units[0].cell == Vector2i(2, 1) and units[0].movement_left == 1
		and units[0].action_left == 1 and not (buttons["attack"] as Button).disabled
		and battle.get("selected_action") == "attack",
		"실제 이동 후 행동과 공격 버튼 유지")
	_check((battle.get("movement_cells") as Array).is_empty(), "이동 선택을 해제하면 범위 표시 제거")
	var point: Vector2 = units[2].get_global_transform_with_canvas() * Vector2(0, -10)
	await _click(point)
	_check(battle.get("preview_target") == units[2] and units[0].action_left == 1,
		"이동 후 공격 버튼을 따로 누르지 않아도 적 클릭으로 공격 미리보기")
	for seed_value: int in range(1000):
		actions.dice.seed = seed_value
		if actions.dice.randi_range(1, 20) == 1:
			actions.dice.seed = seed_value
			break
	await _click(point)
	_check(units[0].action_left == 0 and units[0].movement_left == 1 and units[2].hit_points == 12,
		"이동 후 같은 적 재클릭은 공격만 소비하고 남은 이동은 유지")
	units[0].action_left = 0
	units[0].surge_left = 1
	battle.call("_update_turn_ui")
	(buttons["surge"] as Button).pressed.emit()
	_check(hud.help_title.text == "몰아치기" and "이미 쓴 행동" in hud.help_label.text
		and "비용: 보조 행동 ▲" in hud.help_label.text and "전투 중 1회 남음" in hud.help_label.text
		and "같은 버튼을 다시" in hud.help_label.text and units[0].surge_left == 1,
		"스킬 첫 선택은 효과·비용·횟수·사용법만 보여 줌")
	for unit: CombatUnit in [units[0], units[1]]:
		turns.select_unit(unit)
		for action: String in CombatTurnHud.ACTION_NAMES:
			if not (buttons[action] as Button).visible:
				continue
			hud.refresh_actions(actions, action, unit)
			await process_frame
			await process_frame
			var panel: Control = hud.get_node("ActionHelp") as Control
			_check(not panel.get_global_rect().intersects((hud.get_node("CombatLog") as Control).get_global_rect()),
				"동작 설명과 로그가 겹치지 않음: " + action)
			_check(hud.help_label.text.begins_with("비용: "), "비용은 긴 효과 설명보다 먼저 표시: " + action)
			print("Guidance layout: %s content=%d visible=%.0f scroll=%s" % [action,
				hud.help_label.get_content_height(), hud.help_label.size.y,
				hud.help_label.get_content_height() > hud.help_label.size.y])
	# 플랫폼 글꼴이 더 크거나 안내가 길어도 패널은 로그 위에 머문다.
	hud.help_label.add_theme_font_size_override("normal_font_size", 18)
	hud.help_label.text = "글꼴 차이를 재현하는 긴 안내\n".repeat(30) + "마지막 안내"
	await process_frame
	await process_frame
	var help_panel: Control = hud.get_node("ActionHelp") as Control
	var scroll: VScrollBar = hud.help_label.get_v_scroll_bar()
	_check(not help_panel.get_global_rect().intersects((hud.get_node("CombatLog") as Control).get_global_rect())
		and scroll.max_value > scroll.page, "긴 안내는 패널을 늘리지 않고 스크롤 범위를 만든다")
	var wheel: InputEventMouseButton = InputEventMouseButton.new()
	wheel.button_index = MOUSE_BUTTON_WHEEL_DOWN
	wheel.pressed = true
	wheel.position = root.get_final_transform() * hud.help_label.get_global_rect().get_center()
	wheel.global_position = wheel.position
	Input.parse_input_event(wheel)
	await process_frame
	_check(scroll.value > 0, "설명 영역의 실제 휠 입력으로 아래 내용을 읽을 수 있음")
	wheel.pressed = false
	Input.parse_input_event(wheel)
	hud.help_label.remove_theme_font_size_override("normal_font_size")
	battle.call("_update_turn_ui")
	await process_frame
	await process_frame


func _test_results_and_restart() -> void:
	for unit: CombatUnit in units:
		if not unit.is_ally:
			unit.hit_points = 0
			turns.remove_unit(unit)
	battle.call("_update_turn_ui")
	_check(hud.get_node("Result").visible and hud.result_label.text == "승리", "전멸시 승리 창")
	var before: int = turns.round_number
	hud.end_button.pressed.emit()
	hud.unit_selected.emit(units[1])
	_check(turns.round_number == before and hud.end_button.disabled, "전투 종료 입력 잠금")
	hud.restart_button.pressed.emit()
	await process_frame
	await process_frame
	battle = current_scene.get_node("Battle") as Node2D
	units = battle.get("units")
	turns = battle.get("turns") as CombatTurns
	hud = battle.get_node("UI/TurnHud") as CombatTurnHud
	_check(units.size() == 4 and turns.ordered_units.size() == 4
		and not hud.get_node("Result").visible, "실제 재시작으로 새 전투 진입")
	for unit: CombatUnit in units:
		_check(unit.hit_points == unit.get_max_hit_points() and unit.potion_left == 1,
			"재시작 HP와 전투당 횟수 초기화")
	for unit: CombatUnit in units:
		if unit.is_ally:
			unit.hit_points = 0
			turns.remove_unit(unit)
	battle.call("_update_turn_ui")
	_check(hud.get_node("Result").visible and hud.result_label.text == "패배", "아군 전멸시 패배 창")


func _reset_units() -> void:
	for unit: CombatUnit in units:
		unit.hit_points = unit.get_max_hit_points()
		unit.is_stunned = false
		unit.marked_target = null
		unit.parry_left = 2
	var dice: RandomNumberGenerator = RandomNumberGenerator.new()
	dice.seed = 33
	turns.start(units, dice)


func _test_order_bar_input() -> void:
	_reset_units()
	units[0].cell = Vector2i(4, 4)
	units[1].cell = Vector2i(0, 0)
	units[2].cell = Vector2i(8, 8)
	units[3].cell = Vector2i(9, 9)
	battle.call("_update_turn_ui")
	var camera: Camera2D = battle.get_node("Camera") as Camera2D
	var map: TileMapLayer = battle.get_node("Map") as TileMapLayer
	var original: Vector2 = camera.position
	var destination: Vector2i = Vector2i(4, 3)
	var point: Vector2 = Vector2(260, 50)
	# HUD 빈 영역 아래에 이동 가능한 칸을 놓아 클릭 통과를 재현한다.
	camera.position = map.map_to_local(destination) + root.get_visible_rect().size / 2.0 - point - camera.offset
	camera.force_update_scroll()
	point = map.get_global_transform_with_canvas() * map.map_to_local(destination)
	_check(hud.order_bar.get_global_rect().has_point(point), "클릭 통과 재현 조건: 턴 순서 바 아래 빈 칸")
	await _click(point)
	await _click(point)
	_check(battle.get("preview_cell") == Vector2i(-1, -1) and units[0].cell == Vector2i(4, 4),
		"턴 순서 바의 빈 영역 클릭은 이동 미리보기·확정으로 통과하지 않음")
	var portraits: Dictionary = hud.get("_portraits")
	await _click((portraits[units[1]] as Button).get_global_rect().get_center())
	_check(turns.current_unit == units[1] and units[0].movement_left == 6,
		"턴 순서 바가 월드 입력을 막아도 자식 초상은 실제 클릭으로 전환")
	destination = Vector2i(1, 0)
	point = Vector2(80, 140)
	camera.position = map.map_to_local(destination) + root.get_visible_rect().size / 2.0 - point - camera.offset
	camera.force_update_scroll()
	point = map.get_global_transform_with_canvas() * map.map_to_local(destination)
	_check((hud.get_node("ActionHelp") as Control).get_global_rect().has_point(point)
		and actions.can_move(units[1], destination), "설명 패널 입력 검사: 아래에 이동 가능한 칸을 배치")
	await _click(point)
	await _click(point)
	_check(battle.get("preview_cell") == Vector2i(-1, -1) and units[1].cell == Vector2i(0, 0),
		"동작 설명 패널을 눌러도 아래의 월드 칸을 선택하거나 이동하지 않음")
	camera.position = original
	camera.force_update_scroll()


func _click(point: Vector2) -> void:
	var event: InputEventMouseButton = InputEventMouseButton.new()
	event.position = root.get_final_transform() * point
	event.global_position = event.position
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	Input.parse_input_event(event)
	await process_frame
	event.pressed = false
	Input.parse_input_event(event)
	await process_frame


func _test_reaction_flow() -> void:
	_reset_units()
	units[0].cell = Vector2i(4, 4)
	units[1].cell = Vector2i(0, 0)
	units[2].cell = Vector2i(8, 8)
	units[3].cell = Vector2i(5, 4)
	turns.end_turn()
	turns.end_turn()
	turns.end_turn()
	_check(turns.current_unit == units[3] and actions.can_move(units[3], Vector2i(6, 4)),
		"반응 재현 조건: 적 궁수의 이동. current=%s group=%s" % [
			turns.current_unit.get_display_name(), turns.get_current_group()])
	var messages: Array[String] = []
	var choices: Array[int] = [0]
	var on_log: Callable = func(message: String) -> void: messages.append(message)
	var on_reaction: Callable = func(kind: String, _prompt: String) -> void:
		_check(kind == "opportunity" and hud.reaction_dialog.visible, "실제 기회 공격 확인 창")
		_check(hud.reaction_dialog.get_ok_button().text == "공격"
			and hud.reaction_dialog.get_cancel_button().text == "넘기기", "기회 공격 선택 문구")
		var before: CombatUnit = turns.current_unit
		hud.end_button.pressed.emit()
		hud.unit_selected.emit(units[0])
		_check(hud.end_button.disabled and turns.current_unit == before, "확인 창 대기 중 턴·초상 잠금")
		var use_reaction: bool = choices[0] > 0
		choices[0] += 1
		if not use_reaction:
			hud.reaction_dialog.get_cancel_button().pressed.emit()
		else:
			hud.reaction_dialog.get_ok_button().pressed.emit()
		_check(not actions.resolve_reaction(true), "같은 반응의 중복 결정 거부")
	actions.logged.connect(on_log)
	actions.reaction_requested.connect(on_reaction)
	# 첫째 넘기기, 둘째 사용. 사용한 기회 공격은 확정 빗나감.
	await actions.move_to(units[3], Vector2i(6, 4))
	await process_frame
	_check(units[0].reaction_left == 1 and units[3].cell == Vector2i(6, 4)
		and not hud.reaction_dialog.visible and not actions.busy, "넘기기는 반응 유지와 이동 재개")
	units[3].cell = Vector2i(5, 4)
	for seed_value: int in range(1000):
		actions.dice.seed = seed_value
		if actions.dice.randi_range(1, 20) == 1:
			actions.dice.seed = seed_value
			break
	messages.clear()
	await actions.move_to(units[3], Vector2i(6, 4))
	await process_frame
	var use_count: int = 0
	for message: String in messages:
		if "기회 공격:" in message and "사용" in message:
			use_count += 1
	_check(use_count == 1 and units[0].reaction_left == 0, "아군 반응 사용 로그·비용은 정확히 한 번")
	_check("d20 [1]" in hud.message_label.text, "3줄 로그에 기회 공격 판정이 남음")
	_check(choices[0] == 2 and not hud.reaction_dialog.visible and not actions.busy, "두 선택의 연결과 입력 잠금 해제")
	hud.show_reaction("parry", "흘려내기 확인")
	_check(hud.reaction_dialog.get_ok_button().text == "흘려내기"
		and hud.reaction_dialog.get_cancel_button().text == "넘기기", "흘려내기 선택 문구")
	hud.reaction_dialog.hide()
	actions.logged.disconnect(on_log)
	actions.reaction_requested.disconnect(on_reaction)
