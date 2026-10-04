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
	_check((titles[0] as Label).text == "행동 ●" and (titles[1] as Label).text == "보조 행동 ▲"
		and (titles[2] as Label).text == "반응 ◆", "컨테이너 제목이 자원 표시")
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
	_check((titles[0] as Label).text == "행동 ○" and (titles[2] as Label).text == "반응 ◇",
		"소비 자원은 빈 기호")
	_check(not (buttons["surge"] as Button).disabled, "공격을 쓴 뒤 몰아치기 활성화")
	_check(not (buttons["parry"] as Button).disabled, "자기 턴 반응 항목은 자원·횟수0도 켜진 표시")
	(buttons["surge"] as Button).pressed.emit()
	_check(units[0].action_left == 0 and units[0].surge_left == 1, "자기 대상 첫 클릭은 미리보기")
	(buttons["surge"] as Button).pressed.emit()
	_check((titles[0] as Label).text == "행동 ●" and (titles[1] as Label).text == "보조 행동 △",
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
	_check("공격(불리): d20 [" in hud.message_label.text, "불리 판정의 두 주사위 로그")
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
	_check("표식 추가" in hud.message_label.text, "표식 추가 피해를 로그에 명시")


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
				hud.end_button, hud.move_button, hud.resource_label]:
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
