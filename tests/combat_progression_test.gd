extends SceneTree
## 실제 메인 장면과 결과 버튼에서 막 진행과 자원 유지 규칙을 검사한다.

var checks: int = 0
var failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)


func _run() -> void:
	var main: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	current_scene = main
	var battle: Node2D = main.get_node("Battle") as Node2D
	battle.set_process(false)
	await process_frame
	var hud: CombatTurnHud = battle.get_node("UI/TurnHud") as CombatTurnHud
	_check(hud.has_node("Progress"), "현재 막과 스테이지를 화면에 표시")
	if hud.has_node("Progress"):
		_check((hud.get_node("Progress") as Label).text == "1막 · 1스테이지", "첫 전투는1-1")
	for unit: CombatUnit in battle.get("units"):
		_check(unit.potion_left == 0, "드랍 전 시작 물약은0개")
	await _test_stage_transition(battle)
	await _test_act_and_defeat(battle)
	await _test_graduation(battle)
	_test_usage_text(battle)
	main.queue_free()
	await process_frame
	await _test_async_transition()
	print("Combat progression: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)


func _test_async_transition() -> void:
	var main: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	current_scene = main
	var battle: Node2D = main.get_node("Battle") as Node2D
	battle.set_process(false)
	var hud: CombatTurnHud = battle.get_node("UI/TurnHud") as CombatTurnHud
	var turns: CombatTurns = battle.get("turns") as CombatTurns
	var dice: RandomNumberGenerator = RandomNumberGenerator.new()
	dice.seed = 33
	turns.start(battle.get("units"), dice)
	hud.end_button.pressed.emit()
	hud.end_button.pressed.emit()
	battle.set_process(true)
	await process_frame
	await process_frame
	_check(battle.get("_enemy_turn_running"), "실제 적 턴 타이머가 실행 중")
	_win(battle)
	_check(hud.restart_button.disabled, "적 턴 타이머 처리 중 결과 버튼 잠금")
	hud.restart_button.pressed.emit()
	_check(hud.progress_label.text == "1막 · 1스테이지", "실제 AI await 중 전환 신호 거부")
	await create_timer(0.6).timeout
	battle.set_process(false)
	_check(not battle.get("_enemy_turn_running") and not hud.restart_button.disabled,
		"적 턴 await 완료 뒤 결과 버튼 잠금 해제")
	hud.restart_button.pressed.emit()
	_finish_rewards(battle)
	await process_frame
	_check(hud.progress_label.text == "1막 · 2스테이지"
		and not hud.get_node("Result").visible, "이전 적 턴 처리 종료 뒤 다음 전투로 진입")
	main.queue_free()
	await process_frame


func _win(battle: Node2D) -> void:
	var turns: CombatTurns = battle.get("turns") as CombatTurns
	for unit: CombatUnit in battle.get("units"):
		if not unit.is_ally:
			unit.hit_points = 0
			turns.remove_unit(unit)
	(battle.get("actions") as CombatActions).changed.emit()


func _test_stage_transition(battle: Node2D) -> void:
	var party: Array[CombatUnit] = []
	for unit: CombatUnit in battle.get("units"):
		if unit.is_ally:
			party.append(unit)
	var warrior: CombatUnit = party[0]
	var archer: CombatUnit = party[1]
	warrior.hit_points = 5
	warrior.second_wind_left = 0
	warrior.parry_left = 0
	warrior.surge_left = 0
	warrior.potion_left = 3
	warrior.is_stunned = true
	warrior.disengaged = true
	warrior.marked_target = (battle.get("units") as Array)[2] as CombatUnit
	archer.hit_points = 0
	(battle.get("turns") as CombatTurns).remove_unit(archer)
	var hud: CombatTurnHud = battle.get_node("UI/TurnHud") as CombatTurnHud
	var stages: Array[CombatStage] = battle.get("stages")
	var second: CombatStage = stages[1].duplicate() as CombatStage
	second.map_size = Vector2i(8, 9)
	second.ally_cells = [Vector2i(1, 8), Vector2i(2, 8)]
	stages[1] = second
	_win(battle)
	_check(hud.result_label.text == "승리" and hud.restart_button.text == "보상 확인",
		"스테이지 승리 결과에서 보상 확인 안내")
	hud.restart_button.pressed.emit()
	_finish_rewards(battle)
	await process_frame
	await process_frame
	_check((hud.get_node("Progress") as Label).text == "1막 · 2스테이지", "승리 뒤1-2 진행")
	_check((battle.get_node("Map") as TileMapLayer).get_used_cells().size() == 72
		and (battle.get("actions") as CombatActions).map_size == Vector2i(8, 9)
		and warrior.cell == Vector2i(1, 8), "다음 스테이지 맵과 배치 데이터를 실제 전투에 적용")
	_check(warrior.hit_points == 5 and warrior.second_wind_left == 0
		and warrior.parry_left == 0 and warrior.surge_left == 0, "같은 막의 HP와 전사 스킬 횟수 유지")
	_check(archer.hit_points == 0 and not archer.visible
		and archer not in (battle.get("turns") as CombatTurns).ordered_units,
		"전투 불능 아군은 같은 막 다음 전투에 나오지 않음")
	_check(warrior.potion_left == 3, "스테이지 전환에서 가진 물약 유지")
	_check(not warrior.is_stunned and not warrior.disengaged
		and warrior.marked_target == null and not warrior.has_mark,
		"기절·표식·이번 턴 효과는 전투 전환에서 해제")
	_check(not hud.get_node("Result").visible, "다음 전투에서 이전 승리 창 숨김")


func _next(battle: Node2D) -> void:
	var hud: CombatTurnHud = battle.get_node("UI/TurnHud") as CombatTurnHud
	_win(battle)
	await process_frame
	# 결과 버튼의 실제 포인터 입력을 사용한다.
	var point: Vector2 = root.get_final_transform() * hud.restart_button.get_global_rect().get_center()
	var click: InputEventMouseButton = InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.position = point
	click.global_position = point
	click.pressed = true
	Input.parse_input_event(click)
	await process_frame
	click.pressed = false
	Input.parse_input_event(click)
	await process_frame
	await process_frame
	_finish_rewards(battle)
	await process_frame


func _finish_rewards(battle: Node2D) -> void:
	var preparation: CombatPreparation = battle.get_node("UI/Preparation") as CombatPreparation
	preparation.continue_button.pressed.emit()
	preparation.continue_button.pressed.emit()
	preparation.discard_dialog.confirmed.emit()


func _test_act_and_defeat(battle: Node2D) -> void:
	var hud: CombatTurnHud = battle.get_node("UI/TurnHud") as CombatTurnHud
	await _next(battle)
	_check(hud.progress_label.text == "1막 · 3스테이지", "1-2에서1-3 진행")
	_check((battle.get_node("Map") as TileMapLayer).get_used_cells().size() == 100,
		"다음 스테이지 데이터가 이전 맵 크기를 덮어씀")
	_win(battle)
	_check(hud.restart_button.text == "보상 확인", "막 마지막 전투도 보상 확인 안내")
	hud.restart_button.pressed.emit()
	var preparation: CombatPreparation = battle.get_node("UI/Preparation") as CombatPreparation
	preparation.continue_button.pressed.emit()
	_check(preparation.continue_button.text == "다음 막 시작", "정비 뒤 다음 막 안내")
	preparation.continue_button.pressed.emit()
	await process_frame
	preparation.discard_dialog.confirmed.emit()
	await process_frame
	_check(hud.progress_label.text == "2막 · 1스테이지", "1-3 승리 뒤2-1 진행")
	_check((battle.get("turns") as CombatTurns).ordered_units.size() == 4,
		"새 막에서 전투 불능 아군 부활과 적 재배치")
	var party: Array[CombatUnit] = battle.get("party")
	for unit: CombatUnit in party:
		_check(unit.hit_points == unit.get_max_hit_points() and unit.second_wind_left == 1
			and unit.parry_left == 2 and unit.surge_left == 1 and unit.mark_left == 1
			and unit.shock_left == 1 and unit.disengage_left == 2,
			"막 시작에 전원 HP와 기존 스킬 횟수 회복")
	_check(party[0].potion_left == 3 and party[1].potion_left == 0,
		"막 시작은 물약을 지급하거나 제거하지 않음")
	party[1].hit_points = 8
	party[1].mark_left = 0
	party[1].shock_left = 0
	party[1].disengage_left = 0
	await _next(battle)
	_check(hud.progress_label.text == "2막 · 2스테이지" and party[1].hit_points == 8
		and party[1].mark_left == 0 and party[1].shock_left == 0 and party[1].disengage_left == 0,
		"같은 막에서 궁수 HP와 세 스킬 횟수 유지")
	# 전투 중 결과 버튼 신호를 보내도 스테이지가 바뀌지 않는다.
	hud.restart_button.pressed.emit()
	_check(hud.progress_label.text == "2막 · 2스테이지", "전투 중 임의 진행 거부")
	var actions: CombatActions = battle.get("actions") as CombatActions
	for unit: CombatUnit in party:
		unit.hit_points = 0
		(battle.get("turns") as CombatTurns).remove_unit(unit)
	party[0].potion_left = 2
	actions.changed.emit()
	_check(hud.result_label.text == "패배" and hud.restart_button.text == "이 막 다시 시작",
		"아군 전멸은 막 재시작 안내")
	actions.busy = true
	hud.restart_button.pressed.emit()
	_check(hud.progress_label.text == "2막 · 2스테이지", "동작 처리 중 막 재시작 거부")
	actions.busy = false
	battle.set("_enemy_turn_running", true)
	hud.restart_button.pressed.emit()
	_check(hud.progress_label.text == "2막 · 2스테이지", "적 턴 처리 중 막 재시작 거부")
	battle.set("_enemy_turn_running", false)
	hud.restart_button.pressed.emit()
	await process_frame
	_check(hud.progress_label.text == "2막 · 1스테이지", "패배한 막의1스테이지로 복귀")
	for unit: CombatUnit in party:
		_check(unit.hit_points == unit.get_max_hit_points() and unit.mark_left == 1
			and unit.shock_left == 1 and unit.disengage_left == 2, "전멸 뒤 부활과 스킬 회복")
	_check(party[0].potion_left == 2, "사용한 물약은 막 재시작으로 돌아오지 않음")


func _test_graduation(battle: Node2D) -> void:
	var hud: CombatTurnHud = battle.get_node("UI/TurnHud") as CombatTurnHud
	for label: String in ["2막 · 2스테이지", "2막 · 3스테이지", "3막 · 1스테이지",
			"3막 · 2스테이지", "3막 · 3스테이지"]:
		await _next(battle)
		_check(hud.progress_label.text == label, "정해진 순서: " + label)
	for unit: CombatUnit in battle.get("party"):
		unit.hit_points = 0
		(battle.get("turns") as CombatTurns).remove_unit(unit)
	(battle.get("actions") as CombatActions).changed.emit()
	hud.restart_button.pressed.emit()
	await process_frame
	_check(hud.progress_label.text == "3막 · 1스테이지" and not hud.get_node("Result").visible,
		"최종 스테이지 패배도 현재 막의 첫 전투로 복귀")
	await _next(battle)
	await _next(battle)
	_win(battle)
	_check(hud.result_label.text == "승리" and hud.restart_button.visible,
		"3-3도 졸업 전에 보상과 정비 제공")
	hud.restart_button.pressed.emit()
	_finish_rewards(battle)
	_check(hud.result_label.text == "3막 졸업" and not hud.restart_button.visible,
		"3-3 승리 뒤 졸업 화면과 추가 스테이지 없음")
	hud.restart_button.pressed.emit()
	_check(hud.progress_label.text == "3막 · 3스테이지"
		and hud.result_label.text == "3막 졸업", "졸업 뒤 진행 신호 무시")


func _test_usage_text(battle: Node2D) -> void:
	var hud: CombatTurnHud = battle.get_node("UI/TurnHud") as CombatTurnHud
	var actions: CombatActions = battle.get("actions") as CombatActions
	var party: Array[CombatUnit] = battle.get("party")
	_check("막당" in hud.action_details(actions, party[0], "second_wind"),
		"스킬 횟수 안내는 막당")
	_check("보유" in hud.action_details(actions, party[0], "potion")
		and "막당" not in hud.action_details(actions, party[0], "potion"),
		"물약은 막당 횟수가 아니라 현재 보유 개수")
