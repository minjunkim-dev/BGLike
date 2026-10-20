extends SceneTree
## 실제 장면의 화면 상태, 입력 연결, 전투 종료와 재시작을 검사한다.

const ScriptedDice = preload("res://tests/scripted_dice.gd")

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
	_test_selection()
	var scene: PackedScene = load("res://scenes/main.tscn") as PackedScene
	var main: Node = scene.instantiate()
	# 전사·궁수 UI 회귀는 기존 풋내기 배치를 fixture로 유지한다.
	(main.get_node("Battle") as Node2D).stages[0] = load("res://scenes/combat/stage.tres") as CombatStage
	# 화면 fixture는 턴을 직접 고정한다. 자동 실행은 AI 장면 검사에서 확인한다.
	root.add_child(main)
	main.get_node("Battle").set_process(false)
	current_scene = main
	await process_frame
	battle = current_scene.get_node("Battle") as Node2D
	units = battle.get("units")
	turns = battle.get("turns") as CombatTurns
	actions = battle.get("actions") as CombatActions
	hud = battle.get_node("UI/TurnHud") as CombatTurnHud
	# HUD fixture의 사거리와 입력 조건을 고정한다.
	units[0].cell = Vector2i(4, 9)
	units[1].cell = Vector2i(5, 9)
	var dice: CombatDice = CombatDice.new()
	dice.seed = 33
	turns.start(units, dice)
	units[2].cell = Vector2i(4, 8)
	units[3].cell = Vector2i(7, 9)
	battle.call("_update_turn_ui")
	await process_frame
	await process_frame
	_check("이니셔티브" not in hud.message_label.text, "전투 시작 로그에 이니셔티브 계산식 없음")
	_test_square_map()
	_test_warrior()
	await _test_resources()
	_test_archer_and_enemy()
	await _test_log_and_status()
	await _test_hit_sound_mix()
	await _test_layout()
	await _test_guidance()
	_test_high_ground_guidance()
	await _test_mouse_controls_and_inspection()
	await _test_group_keyboard()
	await _test_joined_group_hud()
	await _test_incapacitated_portrait_join()
	await _test_portrait_stage_reset()
	await _test_portrait_join_interrupted_by_order_change(true)
	await _test_portrait_join_interrupted_by_order_change(false)
	await _test_portrait_join_interrupted_by_order_change(false, true)
	await _test_order_bar_input()
	await _test_transparent_order_input()
	await _test_reaction_flow()
	await _test_reaction_focus()
	await _test_action_animations()
	await _test_results_and_restart()
	(battle.get_node("HitSound") as AudioStreamPlayer).stop()
	await create_timer(0.08).timeout
	current_scene.queue_free()
	await process_frame
	await _test_spawned_portrait_input()
	var dice_problems: Array[String] = ScriptedDice.finish()
	_check(dice_problems.is_empty(), "준비한 주사위 값을 요청대로 모두 굴림 " + str(dice_problems))
	print("Combat HUD: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)


func _test_selection() -> void:
	var selected: CombatSelection = CombatSelection.new()
	var target: CombatUnit = CombatUnit.new()
	var inspected: CombatUnit = CombatUnit.new()
	var path: Array[Vector2i] = [Vector2i(1, 0), Vector2i(1, 1)]
	_check(not selected.select_move(Vector2i(1, 1), path)
		and selected.selected_action == "move" and selected.preview_path == path,
		"선택 module: 첫 목적지 선택은 이동 미리보기")
	_check(selected.select_move(Vector2i(1, 1), path)
		and selected.preview_path.is_empty() and selected.preview_cell == Vector2i(-1, -1)
		and not path.is_empty(), "선택 module: 같은 목적지는 한 번 확정하고 호출자의 경로는 보존")
	selected.select_move(Vector2i(1, 1), path)
	selected.select_move(Vector2i(2, 2), [])
	_check(selected.selected_action == "move" and selected.preview_path.is_empty(),
		"선택 module: 유효하지 않은 목적지는 경로만 취소")
	selected.begin_field_input(true)
	_check(selected.selected_action == "attack", "선택 module: 좌클릭은 이동 확정 대신 공격 선택으로 복귀")
	selected.inspect(inspected)
	_check(not selected.select_action("second_wind") and selected.inspected_unit == null,
		"선택 module: 첫 보조 행동 선택은 조회만 해제")
	_check(selected.select_action("second_wind") and selected.begin_execution() == "second_wind",
		"선택 module: 같은 보조 행동의 두 번째 선택만 실행")
	selected.finish_execution()
	_check(selected.selected_action == "attack", "선택 module: 실행 뒤 기본 공격으로 복귀")
	_check(not selected.select_target(target, true) and selected.preview_target == target
		and not selected.select_target(target, false) and selected.select_target(target, true),
		"선택 module: 대상 재선택은 실행 가능할 때만 확정")
	selected.select_move(Vector2i(1, 1), path)
	selected.inspect(inspected)
	_check(selected.selected_action == "attack" and selected.preview_target == null
		and selected.preview_path.is_empty() and selected.inspected_unit == inspected,
		"선택 module: 초상 조회는 이동·대상 미리보기를 함께 취소")
	inspected.hit_points = 0
	selected.discard_incapacitated_inspection()
	_check(selected.inspected_unit == null, "선택 module: 전투 불능 조회 해제")
	selected.select_action("shock")
	selected.preview_unit(target)
	selected.reset()
	_check(selected.selected_action == "attack" and selected.preview_target == null
		and selected.preview_path.is_empty() and selected.inspected_unit == null,
		"선택 module: 턴·스테이지 전환은 선택 전체 초기화")
	target.free()
	inspected.free()


func _test_square_map() -> void:
	var map: TileMapLayer = battle.get_node("Map") as TileMapLayer
	_check(map.get_used_cells().size() == 100, "사각 맵은100칸")
	_check(map.tile_set.tile_shape == TileSet.TILE_SHAPE_ISOMETRIC
		and map.tile_set.tile_size == Vector2i(32, 16), "사각 논리 칸을32×16 마름모로 표시")
	for cell: Vector2i in map.get_used_cells():
		_check(map.local_to_map(map.map_to_local(cell)) == cell, "사각 중심 클릭의 좌표 왕복")
		var visual_neighbors: Array[Vector2i] = map.get_surrounding_cells(cell)
		var neighbors: Array[Vector2i] = CombatGrid.neighbors(cell)
		_check(visual_neighbors.size() == 4 and neighbors.size() == 4,
			"표시와 전투 판정 모두 인접4칸")
		for neighbor: Vector2i in visual_neighbors:
			_check(neighbors.has(neighbor) and CombatGrid.distance(cell, neighbor) == 1,
				"Godot 타일 이웃과 전투 인접 판정 일치")


func _test_warrior() -> void:
	var buttons: Dictionary = hud.get("_actions")
	var badges: Dictionary = hud.get("_badges")
	var costs: Dictionary = hud.get("_costs")
	var titles: Array = hud.get("_titles")
	_check(hud.unit_label.text == "아군 전사" and "HP 12 / 12" in hud.resource_label.text
		and "AC 16" in hud.resource_label.text and "이동" not in hud.resource_label.text,
		"현재 유닛 정보: HP·AC 유지, 남은 이동 제거")
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
	_check((badges["second_wind"] as Label).text == "1" and (badges["potion"] as Label).text == "0"
		and (costs["second_wind"] as Label).text == "▲" and (costs["potion"] as Label).text == "▲",
		"호버에서 제거한 스킬 횟수·물약 개수와 비용은 배지·마크에 유지")
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
	_check(units[0].reaction_left == before and (battle.get("selection") as CombatSelection).selected_action == "attack",
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
	_check(hud.unit_label.text == "풋내기 야만인" and "AC 12" in hud.resource_label.text,
		"미리보기는 유닛 정보 자리를 사용")
	_check((buttons["shock"] as Button).visible, "미리보기에도 현재 아군의 스킬 유지")
	hud.unit_selected.emit(units[0])
	hud.end_button.pressed.emit()
	hud.end_button.pressed.emit()
	_check(not turns.current_unit.is_ally and hud.unit_label.text == turns.current_unit.get_display_name(),
		"적 턴에는 행동 중인 적 정보")
	_check(not hud.has_node("Move") and not hud.has_node("InputHint"), "이동 버튼과 상시 입력 안내 없음")
	_check(hud.end_button.disabled, "적 턴 종료는 AI가 처리하며 버튼은 잠김")
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
	actions.apply_status(units[1], units[2], "burn")
	actions.apply_status(units[1], units[2], "burn")
	actions.apply_status(units[0], units[2], "poison")
	hud.show_unit(units[2])
	_check("화상2" in hud.resource_label.text and "독1" in hud.resource_label.text
		and "기절" in hud.resource_label.text and "◎ 표식" in hud.resource_label.text,
		"기존 상태 정보에 화상/독 중첩 수를 함께 표시")
	await process_frame
	_check(hud.get_viewport_rect().encloses(hud.resource_label.get_global_rect()),
		"기절/표식/화상/독의 상태 정보를 함께 표시해도 화면 안에 배치")
	units[2].begin_stage(false)
	units[1].marked_target = null
	battle.call("_update_turn_ui")
	_check(not units[2].has_mark, "표식 해제 표시")
	# 실제 동작의 판정 로그와 숫자 팝업 연결. 마지막 적이 아닌 대상에 확정 명중.
	var hit_sound: AudioStreamPlayer = battle.get_node("HitSound") as AudioStreamPlayer
	var hit_stream: AudioStreamOggVorbis = hit_sound.stream as AudioStreamOggVorbis
	_check(hit_stream != null and hit_stream.get_length() > 0.0
		and hit_stream.get_length() < 0.5 and not hit_stream.loop,
		"타격음은0.5초 미만의 반복 없는 OGG")
	_check(not hit_sound.autoplay and hit_sound.volume_db == -12.0
		and hit_sound.max_polyphony == 4, "타격음 자동 재생 없음·음량-12dB·동시4개 제한")
	hit_sound.stop()
	# 짧은 타격음이 다음 프레임 전에 끝날 수 있어 피해 신호 시점의 재생을 관찰한다.
	var hit_played: Array[bool] = []
	var record_hit: Callable = func() -> void: hit_played.append(hit_sound.playing)
	actions.hit_landed.connect(record_hit)
	units[2].is_stunned = false
	units[2].reaction_left = 0
	units[2].hit_points = 12
	var dice: CombatDice = CombatDice.new()
	dice.seed = 33
	turns.start(units, dice)
	turns.select_unit(units[1])
	units[1].marked_target = units[2]
	units[2].cell = Vector2i(5, 8)
	actions.dice = ScriptedDice.new([6, 6], [20, 20])
	await actions.attack(units[1], units[2])
	_check(not hit_sound.playing and hit_played.is_empty(), "실제 장면의 빗나감은 타격음 무음")
	_check(_has_two_dice_log("불리"),
		"불리 판정은 로그에 주사위 두 값을 모두 표시")
	var parent: Node = units[2].get_parent()
	var has_popup: bool = false
	for child: Node in parent.get_children():
		if child is Label and child.text == "빗나감":
			has_popup = true
	_check(has_popup, "실제 빗나감 결과 팝업 연결")
	_check(_has_feedback(units[1], "공격 %d" % actions.last_attack.total),
		"불리 공격의 실제 판정 합계를 숫자 팝업으로 표시")
	units[1].action_left = 1
	units[2].is_stunned = true
	actions.dice = CombatDice.new()
	actions.dice.seed = 100
	await actions.attack(units[1], units[2])
	_check(hit_played == [true], "실제 피해 신호가 장면의 타격음 재생으로 연결됨")
	actions.hit_landed.disconnect(record_hit)
	_check(_has_two_dice_log("유리"),
		"유리 판정은 로그에 주사위 두 값을 모두 표시")
	_check("표식 추가" in hud.message_label.text, "표식 추가 피해를 로그에 명시")
	_check(_has_feedback(units[1], "공격 %d" % actions.last_attack.total),
		"유리 공격의 실제 판정 합계를 숫자 팝업으로 표시")
	await _test_roll_popups()


func _test_hit_sound_mix() -> void:
	var sound: AudioStreamPlayer = battle.get_node("HitSound") as AudioStreamPlayer
	sound.stop()
	var capture: AudioEffectCapture = AudioEffectCapture.new()
	capture.buffer_length = 2.0
	var effect_index: int = AudioServer.get_bus_effect_count(0)
	AudioServer.add_bus_effect(0, capture)
	await create_timer(0.08).timeout
	capture.clear_buffer()
	for index: int in range(6):
		actions.hit_landed.emit()
	await create_timer(sound.stream.get_length() + 0.2).timeout
	var samples: PackedVector2Array = capture.get_buffer(capture.get_frames_available())
	var peak: float = 0.0
	for sample: Vector2 in samples:
		peak = maxf(peak, maxf(absf(sample.x), absf(sample.y)))
	_check(samples.size() > 1000 and peak > 0.001 and peak < 1.0,
		"연속 타격의 실제 믹서 출력은 무음·클리핑이 없음")
	_check(not sound.playing, "연속 타격음은 반복 없이 종료")
	AudioServer.remove_bus_effect(0, effect_index)


func _has_feedback(unit: CombatUnit, text: String) -> bool:
	for child: Node in unit.get_parent().get_children():
		if child is Label and child.text == text and child.get_meta("feedback_unit", 0) == unit.get_instance_id():
			return true
	return false


func _test_roll_popups() -> void:
	var warrior: CombatUnit = units[0]
	var target: CombatUnit = units[2]
	turns.select_unit(warrior)
	warrior.cell = Vector2i(4, 4)
	target.cell = Vector2i(5, 4)
	target.hit_points = target.get_max_hit_points()
	target.is_stunned = false
	warrior.bonus_action_left = 1
	var expected_dice: CombatDice = CombatDice.new()
	expected_dice.seed = 100
	var contest: CombatChecks.ContestResult = CombatChecks.contest(
		warrior.get_attribute(CombatUnit.Attribute.STRENGTH),
		maxi(target.get_attribute(CombatUnit.Attribute.STRENGTH), target.get_dexterity()), expected_dice)
	actions.dice.seed = 100
	actions.shove(warrior, target)
	_check(_has_feedback(warrior, "밀치기 %d" % contest.attacker_total)
		and _has_feedback(target, "저항 %d" % contest.defender_total), "밀치기 양쪽 대결 합계를 표시")
	# 기절 자동 성공에는 굴림이 없으므로 숫자를 새로 만들지 않는다.
	warrior.bonus_action_left = 1
	target.cell = Vector2i(5, 4)
	target.is_stunned = true
	var emitted: Array[String] = []
	var capture: Callable = func(_unit: CombatUnit, text: String) -> void: emitted.append(text)
	actions.feedback.connect(capture)
	actions.shove(warrior, target)
	_check(emitted.is_empty(), "기절 대상의 자동 밀치기는 가짜 대결 숫자를 표시하지 않음")
	# 명중(비치명타) 굴림을 정해 정신 내성까지 진행하고 실제 로그 합계와 비교한다.
	turns.select_unit(units[1])
	units[1].cell = Vector2i(1, 4)
	target.cell = Vector2i(5, 4)
	target.is_stunned = false
	target.reaction_left = 0
	units[1].action_left = 1
	units[1].shock_left = 1
	units[1].marked_target = null
	actions.dice = ScriptedDice.new([15], [20]).then_seeded()
	await actions.attack(units[1], target, true)
	var save_total: String = hud.message_label.text.get_slice("정신 내성: ", 1).get_slice(" = ", 1).get_slice(" /", 0)
	_check(save_total.is_valid_int() and _has_feedback(target, "정신 내성 %s" % save_total),
		"정신 내성 팝업은 실제 로그의 합계와 일치")
	# 아군 전사의 흘려내기는 실제 내성 합계를 표시한다.
	target = warrior
	target.cell = Vector2i(4, 4)
	units[3].cell = Vector2i(1, 4)
	units[2].cell = Vector2i(9, 9)
	while turns.current_unit != units[3]:
		turns.end_turn()
	target.is_stunned = false
	target.hit_points = target.get_max_hit_points()
	target.reaction_left = 1
	target.parry_left = 2
	var respond: Callable = func(_kind: String, _prompt: String) -> void:
		hud.reaction_dialog.get_ok_button().pressed.emit()
	actions.reaction_requested.connect(respond)
	actions.dice = ScriptedDice.new([11, 10], [20, 20])
	await actions.attack(units[3], target)
	actions.reaction_requested.disconnect(respond)
	var parry_text: String = ""
	for text: String in emitted:
		if text.begins_with("흘려내기 ") and text.get_slice(" ", 1).is_valid_int():
			parry_text = text
	_check(not parry_text.is_empty() and _has_feedback(target, parry_text), "흘려내기 실제 내성 합계 표시")
	var popup_rects: Array[Rect2] = []
	await process_frame
	for child: Node in target.get_parent().get_children():
		if child is Label and child.get_meta("feedback_unit", 0) == target.get_instance_id():
			for rect: Rect2 in popup_rects:
				_check(not rect.intersects(child.get_rect()), "같은 유닛의 숫자 팝업은 겹치지 않음")
			popup_rects.append(child.get_rect())
	actions.feedback.disconnect(capture)


func _has_two_dice_log(mode: String) -> bool:
	var marker: String = "공격(%s): d20 [" % mode
	for line: String in hud.message_label.text.split("\n"):
		if marker not in line:
			continue
		var values: PackedStringArray = line.get_slice(marker, 1).get_slice("]", 0).split(", ")
		return values.size() == 2 and values[0].is_valid_int() and values[1].is_valid_int()
	return false


func _dice_for_miss() -> CombatDice:
	return ScriptedDice.new([1], [20])


func _test_layout() -> void:
	for size: Vector2i in [Vector2i(640, 360), Vector2i(1280, 720), Vector2i(1920, 1080),
		Vector2i(800, 360), Vector2i(683, 384)]:
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
				hud.end_button, hud.resource_label, hud.actor_label,
				hud.preview_label, hud.round_label, hud.progress_label]:
				_check(area.encloses(control.get_global_rect()), "%s: 화면 안 %s" % [size, control.name])
			_check(not hud.round_label.get_global_rect().intersects(hud.progress_label.get_global_rect()),
				"라운드와 막 진행 표시 영역은 겹치지 않음")
			_check(not (hud.get_node("UnitDetails/UnitPanel") as Control).get_global_rect().intersects(
				hud.preview_label.get_global_rect()), "확장한 유닛 정보와 공격 예측은 겹치지 않음")
			var skills: Rect2 = (hud.get_node("Skills") as Control).get_global_rect()
			_check(not skills.intersects(hud.end_button.get_global_rect()), "스킬과 턴 종료가 겹치지 않음")
			var badges: Dictionary = hud.get("_badges")
			var costs: Dictionary = hud.get("_costs")
			for action: String in badges:
				var badge: Label = badges[action] as Label
				if badge.is_visible_in_tree():
					_check(badge.size.y <= 15 and not badge.get_global_rect().intersects(
						(costs[action] as Label).get_global_rect()), "크기 변경 후 배지 분리: " + action)
	# 다른 플랫폼의 글꼴이 줄 높이를 늘려도 정보 아래에 공격 예측을 배치한다.
	hud.resource_label.add_theme_constant_override("line_spacing", 6)
	battle.call("preview_enemy", units[2])
	await process_frame
	await process_frame
	_check(not (hud.get_node("UnitDetails/UnitPanel") as Control).get_global_rect().intersects(
		hud.preview_label.get_global_rect()), "줄 높이가 커져도 정보·공격 예측은 겹치지 않음")
	hud.resource_label.remove_theme_constant_override("line_spacing")
	root.size = Vector2i(640, 360)
	await process_frame


func _test_high_ground_guidance() -> void:
	_reset_units()
	turns.select_unit(units[1])
	units[1].cell = Vector2i(4, 4)
	units[2].cell = Vector2i(7, 4)
	units[2].is_stunned = true
	units[3].cell = Vector2i(4, 5)
	actions.grid.heights = {units[1].cell: 2, units[3].cell: 1}
	battle.call("preview_enemy", units[2])
	_check("유리/불리 상쇄" in hud.preview_label.text and "기절한 대상" in hud.preview_label.text
		and "고지대" in hud.preview_label.text and "옆에 적" in hud.preview_label.text,
		"고지대·기절 유리와 인접 불리의 세 원인을 실제 HUD에서 상쇄로 표시")
	units[3].is_stunned = true
	battle.call("preview_enemy", units[2])
	_check(" · 유리\n" in hud.preview_label.text and "상쇄" not in hud.preview_label.text,
		"고지대·기절 두 유리만 있을 때는 상쇄로 잘못 표시하지 않음")
	actions.grid.heights.clear()


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
	_check(not hud.has_node("ActionHelp") and not hud.has_node("InputHint"),
		"좌측 고정 설명과 우측 조작 안내 제거")
	_check("인접한 적을 기본 공격합니다." in (buttons["attack"] as Button).tooltip_text
		and "지금 사용 불가" in (buttons["attack"] as Button).tooltip_text,
		"공격 버튼 호버에 효과와 사용 불가 이유 유지")
	await _hover((buttons["second_wind"] as Button))
	_check((buttons["second_wind"] as Button).tooltip_text ==
		"숨 고르기\nHP 1d10+1 회복.\n최대 HP를 넘지 않습니다.\n지금 사용 불가: HP가 이미 최대",
		"비활성 숨 고르기는 기획 예시의 이름·효과·이유만 표시")
	for title: Label in hud.get("_titles"):
		await _hover(title)
		_check(title.tooltip_text.is_empty() and not (hud.get("_tooltip_panel") as Control).visible,
			"자원 제목에 실제 호버 설명 없음: " + title.text)
	units[0].action_capacity = 3
	units[0].bonus_action_capacity = 2
	units[0].reaction_capacity = 2
	units[0].action_left = 3
	units[0].bonus_action_left = 2
	units[0].reaction_left = 2
	battle.call("_update_turn_ui")
	var titles: Array = hud.get("_titles")
	_check(titles[0].text == "행동 ●●●" and titles[1].text == "보조 행동 ▲▲"
		and titles[2].text == "반응 ◆◆", "여러 자원은 개수만큼 마크 표시")
	for resource: CombatUnit.TurnResource in CombatUnit.TurnResource.values():
		units[0].spend_resource(resource)
	battle.call("_update_turn_ui")
	_check(titles[0].text == "행동 ●●○" and titles[1].text == "보조 행동 ▲△"
		and titles[2].text == "반응 ◆◇", "일부 자원을 써도 전체 마크 수 유지")
	units[0].action_left = 0
	units[0].bonus_action_left = 0
	units[0].reaction_left = 0
	battle.call("_update_turn_ui")
	_check(titles[0].text == "행동 ○○○" and titles[1].text == "보조 행동 △△"
		and titles[2].text == "반응 ◇◇", "전부 소비하면 가진 개수만큼 빈 마크 유지")
	units[0].begin_turn()
	battle.call("_update_turn_ui")
	_check(titles[0].text == "행동 ●●●" and titles[0].tooltip_text.is_empty(),
		"자기 턴 시작은 같은 개수의 마크를 다시 채움")
	units[0].action_capacity = 1
	units[0].bonus_action_capacity = 1
	units[0].reaction_capacity = 1
	units[0].begin_turn()
	units[0].movement_left = 2
	battle.call("_update_turn_ui")
	var portraits: Dictionary = hud.get("_portraits")
	for unit: CombatUnit in portraits:
		var portrait: Button = portraits[unit] as Button
		_check(portrait.text.split("\n").size() == 2 and "d20" in portrait.tooltip_text
			and str(unit.get_initiative()) == portrait.tooltip_text.get_slice(" = ", 1),
			"초상 숫자 제거, 호버 계산식 유지")
	await battle.call("_select_move_cell", Vector2i(2, 1))
	var cells: Array[Vector2i] = battle.get("movement_cells")
	_check(cells.has(Vector2i(2, 1)) and not cells.has(units[2].cell)
		and not cells.has(Vector2i(5, 1)) and not cells.has(units[0].cell),
		"이동 가능 범위는 남은 이동·점유 칸·현재 칸을 반영")
	_check(hud.preview_label.text.is_empty() and not hud.preview_label.visible
		and "이동" not in hud.resource_label.text and units[2].is_previewed,
		"이동 설명·남은 이동은 제거하고 도착 시 공격 대상 테두리 유지")
	_check(units[0].cell == Vector2i(1, 1) and units[0].movement_left == 2 and units[0].action_left == 1
		and not actions.can_target(units[0], units[2], "attack")
		and actions.can_target(units[0], units[2], "attack", Vector2i(2, 1)),
		"미리보기는 유닛·자원을 바꾸지 않고 이동 위치에서 같은 공격 판정을 사용")
	units[0].action_left = 0
	battle.call("_update_turn_ui")
	_check(hud.preview_label.text.is_empty() and not units[2].is_previewed
		and not (battle.get("movement_cells") as Array).is_empty(),
		"행동을 써도 이동 범위는 유지, 도착 시 공격 대상은 제거")
	units[0].action_left = 1
	var map: TileMapLayer = battle.get_node("Map") as TileMapLayer
	var move_point: Vector2 = map.get_global_transform_with_canvas() * map.map_to_local(Vector2i(2, 1))
	await _click(move_point)
	await _click(move_point, MOUSE_BUTTON_RIGHT)
	_check((battle.get("selection") as CombatSelection).preview_cell == Vector2i(2, 1) and units[0].cell == Vector2i(1, 1),
		"실제 첫 우클릭은 이동 모드와 경로 확인만 실행")
	await _click(move_point, MOUSE_BUTTON_RIGHT)
	_check(units[0].cell == Vector2i(2, 1) and units[0].movement_left == 1
		and units[0].action_left == 1 and not (buttons["attack"] as Button).disabled
		and (battle.get("selection") as CombatSelection).selected_action == "attack",
		"실제 이동 후 행동과 공격 버튼 유지")
	_check((battle.get("movement_cells") as Array).is_empty(), "이동 선택을 해제하면 범위 표시 제거")
	var point: Vector2 = units[2].get_global_transform_with_canvas() * Vector2(0, -10)
	await _click(point)
	_check((battle.get("selection") as CombatSelection).preview_target == units[2] and units[0].action_left == 1,
		"이동 후 적 클릭으로 공격 미리보기")
	actions.dice = ScriptedDice.new([1], [20])
	await _click(point)
	_check(units[0].action_left == 0 and units[0].movement_left == 1 and units[2].hit_points == 12,
		"같은 적 재클릭은 공격만 소비하고 남은 이동 유지")
	units[0].surge_left = 1
	battle.call("_update_turn_ui")
	(buttons["surge"] as Button).pressed.emit()
	var details: String = (buttons["surge"] as Button).tooltip_text
	_check("몰아치기" in details and "이미 쓴 행동" in details
		and units[0].surge_left == 1,
		"자기 대상 스킬 첫 클릭은 실행하지 않고 이름·효과 유지")
	for unit: CombatUnit in [units[0], units[1]]:
		turns.select_unit(unit)
		battle.call("_update_turn_ui")
		for action: String in CombatActionRules.NAMES:
			var button: Button = buttons[action] as Button
			if not button.visible:
				continue
			var hp: int = unit.hit_points
			var uses: int = unit.surge_left
			await _hover(button)
			_check(_has_tooltip(root, button.tooltip_text),
				"활성·비활성 버튼의 실제 호버 설명: " + action)
			var tooltip: PanelContainer = hud.get("_tooltip_panel") as PanelContainer
			_check(hud.get_global_rect().encloses(tooltip.get_global_rect())
				and not tooltip.get_global_rect().intersects((hud.get_node("Skills") as Control).get_global_rect())
				and tooltip.z_index > (hud.get_node("Skills") as Control).z_index,
				"호버 전체 설명은 화면 안에서 스킬 패널 위에 표시: " + action)
			_check(button.tooltip_text.begins_with(CombatActionRules.NAMES[action] + "\n"),
				"호버에 동작 이름 유지: " + action)
			for removed: String in ["비용", "막당 ", "횟수 제한", "\n보유 물약", "오른쪽 기호",
				"위 숫자", "좌클릭", "같은 버튼", "버튼으로 실행", "확인 창", "묻습니다"]:
				_check(removed not in button.tooltip_text, "호버에서 안내 제거: %s / %s" % [action, removed])
			_check(unit.hit_points == hp and unit.surge_left == uses,
				"호버는 동작 실행·자원 소비 없음: " + action)
	# 비활성 버튼은 비용 소진·횟수 소진·효과 없음의 이유를 호버에 유지한다.
	turns.select_unit(units[0])
	units[0].action_left = 0
	units[0].surge_left = 0
	battle.call("_update_turn_ui")
	_check("자원을 이미 씀" in (buttons["attack"] as Button).tooltip_text
		and "이번 막의 횟수를 모두 씀" in (buttons["surge"] as Button).tooltip_text
		and "HP가 이미 최대" in (buttons["second_wind"] as Button).tooltip_text,
		"사용 불가 이유는 비활성 버튼 호버에 유지")
	units[0].parry_left = 0
	battle.call("_update_turn_ui")
	_check("이번 막의 횟수를 모두 씀" in (buttons["parry"] as Button).tooltip_text,
		"반응 스킬 횟수가 없으면 이유 표시")
	units[0].parry_left = 2
	units[0].reaction_left = 0
	battle.call("_update_turn_ui")
	_check("자원을 이미 씀" in (buttons["opportunity"] as Button).tooltip_text,
		"반응을 이미 썼으면 이유 표시")
	units[0].reaction_left = 1
	turns.select_unit(units[1])
	turns.end_turn()
	turns.end_turn()
	battle.call("_update_turn_ui")
	_check(not turns.current_unit.is_ally and (buttons["parry"] as Button).is_visible_in_tree()
		and "지금 사용 불가" not in (buttons["parry"] as Button).tooltip_text,
		"적 턴에도 남은 반응에 아군 자기 턴 제한을 안내하지 않음")
	actions.busy = true
	battle.call("_update_turn_ui")
	_check("지금 사용 불가" not in (buttons["parry"] as Button).tooltip_text
		and "지금 사용 불가" not in (buttons["opportunity"] as Button).tooltip_text,
		"적 행동 중의 입력 잠금은 반응 사용을 막지 않음")
	units[0].is_stunned = true
	battle.call("_update_turn_ui")
	_check("기절 상태" in (buttons["parry"] as Button).tooltip_text
		and "기절 상태" in (buttons["opportunity"] as Button).tooltip_text,
		"기절한 전사는 반응을 사용할 수 없는 이유 표시")
	units[0].is_stunned = false
	units[0].hit_points = 0
	battle.call("_update_turn_ui")
	_check("전투 불능" in (buttons["parry"] as Button).tooltip_text
		and "전투 불능" in (buttons["opportunity"] as Button).tooltip_text,
		"전투 불능 전사의 반응에는 사용 불가 이유 표시")
	units[0].hit_points = 12
	actions.busy = false
	await _hover(hud.end_button)


func _hover(control: Control) -> void:
	await process_frame
	await process_frame
	var motion: InputEventMouseMotion = InputEventMouseMotion.new()
	motion.position = root.get_final_transform() * control.get_global_rect().get_center()
	motion.global_position = motion.position
	Input.parse_input_event(motion)
	await create_timer(0.8).timeout


func _has_tooltip(node: Node, text: String) -> bool:
	if node is Label and node.text == text and node.is_visible_in_tree():
		return true
	for child: Node in node.get_children(true):
		if _has_tooltip(child, text):
			return true
	return false


func _test_results_and_restart() -> void:
	for unit: CombatUnit in units:
		if not unit.is_ally:
			actions.incapacitate(unit)
	actions.changed.emit()
	_check(hud.get_node("Result").visible and hud.result_label.text == "승리", "전멸시 승리 창")
	_check(not battle.progress.rewards.is_empty(), "실제 승리 신호에서 드랍 생성")
	var before: int = turns.round_number
	var ally_hp: Array[int] = [units[0].hit_points, units[1].hit_points]
	hud.end_button.pressed.emit()
	hud.unit_selected.emit(units[1])
	_check(turns.round_number == before and hud.end_button.disabled, "전투 종료 입력 잠금")
	hud.restart_button.pressed.emit()
	var preparation: CombatPreparation = battle.get_node("UI/Preparation") as CombatPreparation
	preparation.continue_button.pressed.emit()
	preparation.continue_button.pressed.emit()
	preparation.discard_dialog.confirmed.emit()
	await process_frame
	await process_frame
	battle = current_scene.get_node("Battle") as Node2D
	units = battle.get("units")
	turns = battle.get("turns") as CombatTurns
	hud = battle.get_node("UI/TurnHud") as CombatTurnHud
	_check(units.size() == 3 and turns.ordered_units.size() == 3
		and not hud.get_node("Result").visible and hud.progress_label.text == "1막 · 2스테이지",
		"승리 뒤 보상·정비 종료로 다음 스테이지 진입")
	for index: int in range(2):
		_check(units[index].hit_points == ally_hp[index] and units[index].potion_left == 0,
			"같은 막은 HP를 유지하고 물약을 지급하지 않음")
	for unit: CombatUnit in units:
		if unit.is_ally:
			actions.incapacitate(unit)
	battle.call("_update_turn_ui")
	_check(hud.get_node("Result").visible and hud.result_label.text == "패배", "아군 전멸시 패배 창")


func _reset_units() -> void:
	for unit: CombatUnit in units:
		unit.hit_points = unit.get_max_hit_points()
		unit.is_stunned = false
		unit.marked_target = null
		unit.parry_left = 2
	var dice: CombatDice = CombatDice.new()
	dice.seed = 33
	turns.start(units, dice)


func _test_mouse_controls_and_inspection() -> void:
	_reset_units()
	units[0].cell = Vector2i(4, 4)
	units[1].cell = Vector2i(0, 0)
	units[2].cell = Vector2i(5, 4)
	units[3].cell = Vector2i(9, 9)
	units[2].reaction_left = 0
	battle.call("_update_turn_ui")
	var map: TileMapLayer = battle.get_node("Map") as TileMapLayer
	var destination: Vector2i = Vector2i(3, 4)
	var point: Vector2 = map.get_global_transform_with_canvas() * map.map_to_local(destination)
	await _click(point)
	await _click(point)
	_check(units[0].cell == Vector2i(4, 4) and ((battle.get("selection") as CombatSelection).preview_path as Array).is_empty(),
		"빈 칸 좌클릭은 이동을 준비하거나 실행하지 않음")
	await _click(point, MOUSE_BUTTON_RIGHT)
	_check((battle.get("selection") as CombatSelection).preview_cell == destination and units[0].movement_left == 6
		and not (battle.get("movement_cells") as Array).is_empty(), "첫 우클릭만으로 이동 범위·경로 표시")
	var other: Vector2i = Vector2i(4, 3)
	var other_point: Vector2 = map.get_global_transform_with_canvas() * map.map_to_local(other)
	await _click(other_point, MOUSE_BUTTON_RIGHT)
	_check((battle.get("selection") as CombatSelection).preview_cell == other and units[0].cell == Vector2i(4, 4),
		"다른 칸 우클릭은 이동하지 않고 목적지 변경")
	await _click(other_point)
	_check(units[0].movement_left == 6 and ((battle.get("selection") as CombatSelection).preview_path as Array).is_empty(),
		"이동 미리보기의 좌클릭은 이동 확정으로 처리하지 않음")
	await _click(point, MOUSE_BUTTON_RIGHT)
	await _click(point, MOUSE_BUTTON_RIGHT)
	_check(units[0].cell == destination and units[0].movement_left == 5 and units[0].action_left == 1,
		"같은 칸 두 번째 우클릭은 이동력만 소비")
	units[0].cell = Vector2i(4, 4)
	battle.call("_update_turn_ui")
	var enemy_point: Vector2 = units[2].get_global_transform_with_canvas() * Vector2(0, -10)
	await _click(enemy_point)
	_check((battle.get("selection") as CombatSelection).preview_target == units[2] and units[0].action_left == 1
		and hud.unit_label.text == units[2].get_display_name(), "필드 적 첫 좌클릭은 공격 미리보기와 적 정보")
	await _click(map.get_global_transform_with_canvas() * map.map_to_local(units[2].cell), MOUSE_BUTTON_RIGHT)
	_check((battle.get("selection") as CombatSelection).preview_target == null and units[0].action_left == 1
		and units[2].hit_points == 12, "적 점유 칸 우클릭은 공격하지 않음")
	await _click(enemy_point)
	var portraits: Dictionary = hud.get("_portraits")
	await _click((portraits[units[2]] as Button).get_global_rect().get_center())
	await _click((portraits[units[2]] as Button).get_global_rect().get_center())
	_check(turns.current_unit == units[0] and units[0].action_left == 1
		and units[2].hit_points == 12 and (battle.get("selection") as CombatSelection).preview_target == null,
		"적 초상을 반복 클릭해도 공격 준비·실행·조작 전환 없음")
	_check(hud.unit_label.text == "풋내기 야만인" and hud.actor_label.text == "조작: 아군 전사"
		and "힘 +3" in hud.resource_label.text and "민첩 +1" in hud.resource_label.text
		and "체력 +2" in hud.resource_label.text and "정신 -2" in hud.resource_label.text
		and "명중 +5" in hud.resource_label.text and "사거리 1칸" in hud.resource_label.text,
		"정보 대상·조작 유닛을 구분하고 실제 능력치·공격 수치 표시")
	_check("행동" not in hud.resource_label.text and "반응" not in hud.resource_label.text
		and (hud.get("_titles") as Array)[0].text == "행동 ●"
		and (hud.get("_actions") as Dictionary).has("surge"), "적 정보에도 현재 아군 자원 마크 유지")
	battle.call("_update_turn_ui")
	_check(hud.unit_label.text == "풋내기 야만인", "UI 갱신은 초상 정보 조회 유지")
	await _click(enemy_point)
	_check(units[0].action_left == 1 and (battle.get("selection") as CombatSelection).preview_target == units[2],
		"초상 조회 뒤 필드 적 클릭은 새 공격의 첫 미리보기")
	actions.dice = _dice_for_miss()
	await _click(enemy_point)
	_check(units[0].action_left == 0, "필드 적 두 번째 좌클릭은 공격 확정")
	await _click((portraits[units[1]] as Button).get_global_rect().get_center())
	_check(turns.current_unit == units[1] and units[0].action_left == 0
		and "힘 +0" in hud.resource_label.text and "사거리 6칸" in hud.resource_label.text,
		"조작 가능한 아군 초상은 정보와 조작 전환, 기존 자원 유지")
	turns.select_unit(units[0])
	turns.end_turn()
	await _click((portraits[units[0]] as Button).get_global_rect().get_center())
	_check(turns.current_unit == units[0] and not turns.is_turn_finished(units[0])
		and units[0].action_left == 0 and hud.unit_label.text == "아군 전사",
		"턴을 마친 아군 초상은 종료를 해제하고 남은 자원으로 조작 전환")
	turns.end_turn()
	turns.end_turn()
	var enemy_actor: CombatUnit = turns.current_unit
	await _click((portraits[units[1]] as Button).get_global_rect().get_center())
	_check(turns.current_unit == enemy_actor and hud.unit_label.text == "아군 궁수"
		and hud.actor_label.text == "진행: " + enemy_actor.get_display_name(), "적 턴에도 아군 정보만 조회")
	await _click(point, MOUSE_BUTTON_RIGHT)
	await _click(enemy_point)
	_check(turns.current_unit == enemy_actor and units[0].cell == Vector2i(4, 4),
		"적 턴의 필드 좌·우클릭은 아군 조작으로 통과하지 않음")
	_reset_units()
	units[1].is_stunned = true
	battle.call("_update_turn_ui")
	await _click((portraits[units[1]] as Button).get_global_rect().get_center())
	_check(turns.current_unit == units[0] and "기절" in hud.resource_label.text,
		"기절한 아군은 정보만 표시하고 조작 전환 거부")
	units[1].is_stunned = false
	actions.busy = true
	battle.call("_update_turn_ui")
	await _click((portraits[units[2]] as Button).get_global_rect().get_center())
	await _click(point, MOUSE_BUTTON_RIGHT)
	_check(hud.unit_label.text == "아군 궁수" and ((battle.get("selection") as CombatSelection).preview_path as Array).is_empty(),
		"반응 대기 중 초상·우클릭은 기존 잠금을 유지")
	actions.busy = false
	_reset_units()


func _test_group_keyboard() -> void:
	_reset_units()
	var portraits: Dictionary = hud.get("_portraits")
	hud.end_button.grab_focus()
	await _tab()
	_check(turns.current_unit == units[1] and hud.end_button.has_focus(),
		"Tab은 묶음의 다음 아군을 고르고 UI 포커스를 옮기지 않음")
	await _tab(true)
	_check(turns.current_unit == units[0], "Shift+Tab은 묶음의 이전 아군으로 순환")
	units[0].spend_movement(2)
	units[0].spend_resource(CombatUnit.TurnResource.ACTION)
	hud.end_button.pressed.emit()
	var ended: StyleBoxFlat = (portraits[units[0]] as Button).get_theme_stylebox("normal")
	_check(is_equal_approx(ended.bg_color.r, ended.bg_color.g)
		and is_equal_approx(ended.bg_color.g, ended.bg_color.b), "턴 종료한 초상은 회색")
	await _tab()
	_check(turns.current_unit == units[0] and not turns.is_turn_finished(units[0])
		and units[0].movement_left == 4 and units[0].action_left == 0,
		"Tab은 종료한 아군도 포함하며 자원 회복 없이 종료를 해제")
	var selected: StyleBoxFlat = (portraits[units[0]] as Button).get_theme_stylebox("normal")
	var grouped: StyleBoxFlat = (portraits[units[1]] as Button).get_theme_stylebox("normal")
	var outside: StyleBoxFlat = (portraits[units[2]] as Button).get_theme_stylebox("normal")
	_check(selected.border_color == Color("f4cf69") and grouped.border_color == Color.WHITE,
		"조작 중 초상은 금색, 현재 묶음의 다른 초상은 흰색 테두리")
	_check(outside.bg_color == CombatUnit.ENEMY_COLOR.darkened(0.3), "묶음 밖 초상도 원래 색 유지")
	units[1].is_stunned = true
	await _tab()
	_check(turns.current_unit == units[0], "Tab은 기절한 아군을 건너뜀")
	units[1].is_stunned = false
	actions.busy = true
	await _tab()
	_check(turns.current_unit == units[0], "이동·행동 연출 중 Tab 전환 잠금")
	actions.busy = false
	hud.reaction_dialog.popup_centered()
	await _tab()
	_check(turns.current_unit == units[0], "반응 확인 창 중 Tab 전환 잠금")
	hud.reaction_dialog.hide()
	hud.get_node("Result").show()
	await _tab()
	_check(turns.current_unit == units[0], "결과 창 중 Tab 전환 잠금")
	hud.get_node("Result").hide()
	turns.end_turn()
	turns.end_turn()
	var enemy: CombatUnit = turns.current_unit
	await _tab()
	_check(turns.current_unit == enemy and not enemy.is_ally, "적 턴 중 Tab 전환 잠금")
	_reset_units()


func _test_joined_group_hud() -> void:
	_reset_units()
	var desired: Array[CombatUnit] = [units[0], units[2], units[3], units[1]]
	var rolls: Array[int] = []
	for unit: CombatUnit in units:
		rolls.append(20 - 3 * desired.find(unit) - unit.get_dexterity())
	turns.start(units, ScriptedDice.new(rolls))
	units[0].spend_movement(2)
	units[0].spend_resource(CombatUnit.TurnResource.ACTION)
	turns.end_turn()
	turns.end_turn()
	turns.end_turn()
	var portraits: Dictionary = hud.get("_portraits")
	var warrior: Button = portraits[units[0]]
	var archer: Button = portraits[units[1]]
	var pending: Control = warrior.get_node_or_null("PendingTurn") as Control
	_check(pending != null and pending.is_visible_in_tree()
		and turns.current_unit == units[1] and units[0].action_left == 0,
		"경계 묶음의 미시작 유닛은 자원을 유지하고 모래시계 표시")
	await process_frame
	_check(warrior.global_position.x < archer.global_position.x,
		"경계의 앞 초상은 기존 위치에서 합쳐지는 중간 위치를 표시")
	await create_timer(0.4).timeout
	_check(warrior.global_position.x > archer.global_position.x
		and not warrior.get_global_rect().intersects(archer.get_global_rect()),
		"1초 미만에 경계 초상이 묶음 뒤로 이동하고 겹침 없이 종료")
	await _tab()
	_check(turns.current_unit == units[0] and units[0].movement_left == 6
		and units[0].action_left == 1 and pending != null and not pending.visible,
		"Tab 첫 조작에서 턴을 시작하고 모래시계 제거")
	units[0].spend_resource(CombatUnit.TurnResource.ACTION)
	turns.end_turn()
	await _tab()
	_check(turns.current_unit == units[0] and units[0].action_left == 0
		and pending != null and not pending.visible, "결합 묶음의 종료 취소는 턴을 다시 시작하지 않음")
	_reset_units()


func _test_incapacitated_portrait_join() -> void:
	_reset_units()
	var desired: Array[CombatUnit] = [units[0], units[2], units[1], units[3]]
	var rolls: Array[int] = []
	for unit: CombatUnit in units:
		rolls.append(20 - 3 * desired.find(unit) - unit.get_dexterity())
	turns.start(units, ScriptedDice.new(rolls, [20, 20, 20, 20]))
	await process_frame
	await process_frame
	var before: float = ((hud.get("_portraits") as Dictionary)[units[1]] as Button).global_position.x
	units[0].spend_movement(2)
	units[0].spend_resource(CombatUnit.TurnResource.ACTION)
	actions.incapacitate(units[2])
	var portraits: Dictionary = hud.get("_portraits")
	_check(portraits.size() == 3 and not portraits.has(units[2])
		and turns.get_current_group() == [units[0], units[1]]
		and not turns.is_turn_started(units[1]), "전투 불능 초상은 즉시 빠지고 동료는 미시작 묶음에 합류")
	await process_frame
	await process_frame
	var archer: Button = portraits[units[1]]
	var start: float = archer.global_position.x
	await create_timer(0.1).timeout
	var middle: float = archer.global_position.x
	var first_panel: Control = hud.order_bar.get_child(0) as Control
	var next_panel: Control = hud.order_bar.get_child(1) as Control
	var point: Vector2 = Vector2((first_panel.get_global_rect().end.x
		+ next_panel.global_position.x) / 2.0, archer.get_global_rect().get_center().y)
	_check(archer.get_global_rect().has_point(point)
		and not first_panel.get_global_rect().has_point(point)
		and not next_panel.get_global_rect().has_point(point), "이동 중 초상은 묶음 사이의 빈틈을 지나감")
	var motion: InputEventMouseMotion = InputEventMouseMotion.new()
	motion.position = root.get_final_transform() * point
	motion.global_position = motion.position
	Input.parse_input_event(motion)
	await process_frame
	_check(root.gui_get_hovered_control() == archer, "묶음 사이를 지나는 초상의 표시 영역이 포인터 입력을 받음")
	await _click(point)
	_check(turns.current_unit == units[1] and turns.is_turn_started(units[1])
		and units[0].movement_left == 4 and units[0].action_left == 0,
		"합류 이동 중 초상을 선택해도 첫 턴만 시작하고 동료 자원을 회복하지 않음")
	await create_timer(0.2).timeout
	_check(start <= before + 1.0 and start > middle and middle > archer.global_position.x
		and archer.get_parent() == (portraits[units[0]] as Button).get_parent()
		and not archer.get_global_rect().intersects((portraits[units[0]] as Button).get_global_rect()),
		"남은 초상은 즉시 새 위치로 뛰지 않고 0.25초 동안 합쳐져 겹침 없이 종료")
	units[2].show()
	_reset_units()


func _test_portrait_stage_reset() -> void:
	_reset_units()
	await process_frame
	await process_frame
	actions.incapacitate(units[2])
	hud.begin_stage(2, 1)
	hud.refresh(turns, actions.has_available_action(turns.current_unit))
	await process_frame
	await process_frame
	var survivor: Button = (hud.get("_portraits") as Dictionary)[units[3]]
	var initial: Vector2 = survivor.global_position
	await create_timer(0.35).timeout
	_check(initial.is_equal_approx(survivor.global_position),
		"스테이지 초기화는 같은 유닛 순서여도 이전 장면에서 예약한 초상 이동을 재생하지 않음")
	units[2].show()
	hud.begin_stage(1, 1)
	_reset_units()


func _test_portrait_join_interrupted_by_order_change(wait_for_start: bool, remove_another: bool = false) -> void:
	_reset_units()
	var desired: Array[CombatUnit] = [units[0], units[2], units[1], units[3]]
	var rolls: Array[int] = []
	for unit: CombatUnit in units:
		rolls.append(20 - 3 * desired.find(unit) - unit.get_dexterity())
	turns.start(units, ScriptedDice.new(rolls, [20, 20, 20, 20]))
	await process_frame
	await process_frame
	var previous: Vector2 = ((hud.get("_portraits") as Dictionary)[units[1]] as Button).global_position
	actions.incapacitate(units[2])
	if wait_for_start:
		await create_timer(0.1).timeout
		previous = ((hud.get("_portraits") as Dictionary)[units[1]] as Button).global_position
	var inserted: CombatUnit
	if remove_another:
		actions.incapacitate(units[3])
	else:
		inserted = CombatUnit.new()
		inserted.is_ally = true
		inserted.hit_points = inserted.get_max_hit_points()
		battle.get_node("Units").add_child(inserted)
		units.append(inserted)
		_check(turns.insert_before(inserted, units[0]), "초상 이동 중 새 유닛의 순서 삽입을 즉시 반영")
	await process_frame
	await process_frame
	var archer: Button = (hud.get("_portraits") as Dictionary)[units[1]]
	var start: Vector2 = archer.global_position
	await create_timer(0.1).timeout
	var middle: Vector2 = archer.global_position
	await create_timer(0.2).timeout
	var destination: Vector2 = archer.global_position
	_check(start.distance_to(destination) > middle.distance_to(destination)
		and middle.distance_to(destination) > 0.0
		and start.distance_to(previous) <= destination.distance_to(previous),
		"실행 중이거나 예약된 이동은 순서가 바뀌어도 마지막 표시 위치에서 이어 감: %s/%s" % [wait_for_start, remove_another])
	if inserted != null:
		turns.remove_unit(inserted)
		units.erase(inserted)
	hud.begin_stage(1, 1)
	if inserted != null:
		inserted.free()
	units[2].show()
	units[3].show()
	_reset_units()


func _tab(backwards: bool = false) -> void:
	var event: InputEventKey = InputEventKey.new()
	event.keycode = KEY_TAB
	event.shift_pressed = backwards
	event.pressed = true
	Input.parse_input_event(event)
	await process_frame
	event = event.duplicate() as InputEventKey
	event.pressed = false
	Input.parse_input_event(event)
	await process_frame


func _test_order_bar_input() -> void:
	_reset_units()
	units[0].cell = Vector2i(4, 4)
	units[1].cell = Vector2i(0, 0)
	units[2].cell = Vector2i(8, 8)
	units[3].cell = Vector2i(9, 9)
	battle.call("_update_turn_ui")
	await process_frame
	await process_frame
	var scroll: ScrollContainer = hud.get_node("OrderScroll") as ScrollContainer
	var last_panel: Control = hud.order_bar.get_child(-1) as Control
	var panel_end: float = last_panel.get_global_rect().end.x
	var camera: Camera2D = battle.get_node("Camera") as Camera2D
	var map: TileMapLayer = battle.get_node("Map") as TileMapLayer
	var original: Vector2 = camera.position
	var destination: Vector2i = Vector2i(4, 3)
	# 플랫폼 글꼴에 따라 초상 너비가 달라지므로 실제 빈 영역을 사용한다.
	var point: Vector2 = Vector2((panel_end + scroll.get_global_rect().end.x) / 2.0,
		hud.order_bar.get_global_rect().get_center().y)
	camera.position = map.map_to_local(destination) + root.get_visible_rect().size / 2.0 - point - camera.offset
	camera.force_update_scroll()
	point = map.get_global_transform_with_canvas() * map.map_to_local(destination)
	_check(hud.order_bar.get_global_rect().has_point(point) and point.x > panel_end,
		"클릭 통과 재현 조건: 실제 초상 영역 밖의 턴 순서 바 아래 빈 칸")
	await _click(point, MOUSE_BUTTON_RIGHT)
	await _click(point, MOUSE_BUTTON_RIGHT)
	_check((battle.get("selection") as CombatSelection).preview_cell == Vector2i(-1, -1) and units[0].cell == destination,
		"턴 순서 바의 빈 영역 우클릭은 이동 미리보기·확정으로 통과")
	var portraits: Dictionary = hud.get("_portraits")
	await _click((portraits[units[1]] as Button).get_global_rect().get_center())
	_check(turns.current_unit == units[1] and units[0].movement_left == 5,
		"빈 영역을 통과시켜도 자식 초상 클릭은 조작 전환만 수행")
	destination = Vector2i(1, 0)
	point = Vector2(80, 140)
	camera.position = map.map_to_local(destination) + root.get_visible_rect().size / 2.0 - point - camera.offset
	camera.force_update_scroll()
	point = map.get_global_transform_with_canvas() * map.map_to_local(destination)
	_check(not hud.has_node("ActionHelp") and Rect2(8, 88, 152, 158).has_point(point)
		and actions.can_move(units[1], destination), "설명 패널 입력 검사: 아래에 이동 가능한 칸을 배치")
	await _click(point, MOUSE_BUTTON_RIGHT)
	await _click(point, MOUSE_BUTTON_RIGHT)
	_check((battle.get("selection") as CombatSelection).preview_cell == Vector2i(-1, -1) and units[1].cell == destination,
		"제거한 설명 패널 자리는 월드 입력을 가로막지 않음")
	camera.position = original
	camera.force_update_scroll()


func _test_transparent_order_input() -> void:
	for window_size: Vector2i in [Vector2i(640, 360), Vector2i(1280, 800), Vector2i(1920, 1080)]:
		root.size = window_size
		_reset_units()
		units[0].cell = Vector2i(0, 0)
		units[1].cell = Vector2i(8, 9)
		units[2].cell = Vector2i(1, 0)
		units[3].cell = Vector2i(9, 9)
		units[2].reaction_left = 0
		battle.call("_update_turn_ui")
		await process_frame
		await process_frame
		var enemy_point: Vector2 = units[2].get_global_transform_with_canvas() * Vector2(0, -10)
		await _click(enemy_point)
		_check((battle.get("selection") as CombatSelection).preview_target == units[2]
			and units[0].action_left == 1, "상단 유닛 몸통 클릭은 공격 미리보기: %s" % window_size)
		await _click(enemy_point + Vector2(30, 0))
		_check((battle.get("selection") as CombatSelection).preview_target == null,
			"빈 영역 좌클릭은 공격 선택 취소: %s" % window_size)
		await _click(enemy_point)
		actions.dice = ScriptedDice.new([15, 2], [20, 8])
		await _click(enemy_point)
		_check(units[0].action_left == 0 and units[2].hit_points == 7,
			"상단 유닛 몸통 두 번째 클릭은 공격 확정: %s" % window_size)
	root.size = Vector2i(640, 360)
	_reset_units()
	battle.call("_update_turn_ui")
	await process_frame
	await process_frame


func _test_spawned_portrait_input() -> void:
	root.size = Vector2i(640, 360)
	var main: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	current_scene = main
	battle = main.get_node("Battle") as Node2D
	battle.set_process(false)
	(battle.get("progress") as CombatActProgress).stage_index = 6
	battle.call("_start_stage", true)
	units = battle.get("units")
	turns = battle.get("turns") as CombatTurns
	actions = battle.get("actions") as CombatActions
	hud = battle.get_node("UI/TurnHud") as CombatTurnHud
	var initial_units: Array[CombatUnit] = units.duplicate()
	var initial_allies: int = units.filter(func(unit: CombatUnit) -> bool: return unit.is_ally).size()
	var initial_spiderlings: int = units.filter(func(unit: CombatUnit) -> bool:
		return not unit.is_ally and unit.kind == CombatUnit.Kind.SPIDERLING).size()
	var initial_mothers: int = units.filter(func(unit: CombatUnit) -> bool:
		return not unit.is_ally and unit.kind == CombatUnit.Kind.MOTHER_SPIDER).size()
	var initial_ready: bool = (units.size() == 7 and initial_allies == 2
		and initial_spiderlings == 3 and initial_mothers == 2
		and units[0].is_ally and units[0].kind == CombatUnit.Kind.WARRIOR
		and units[1].is_ally and units[1].kind == CombatUnit.Kind.ARCHER)
	_check(initial_ready,
		"소환 전제조건: 3-1 아군2·새끼3·엄마거미2")
	if not initial_ready:
		main.queue_free()
		await process_frame
		return
	var spawn_events: Array[int] = [0]
	actions.logged.connect(func(message: String) -> void:
		if " 새끼 낳기:" in message:
			spawn_events[0] += 1)
	actions.movement_animation = Callable()
	actions.attack_animation = Callable()
	actions.dice.seed = 109
	units[0].hit_points = 1000
	units[1].hit_points = 1000
	print("[HUD_FIXTURE] 통제된 소환 검사: 아군HP1000·직접AI호출, native 입력·전투_process 검증 제외")
	turns.start(units, ScriptedDice.new([1, 1, 20, 20, 20, 20, 20]))
	var ai: CombatEnemyAi = battle.get("enemy_ai") as CombatEnemyAi
	for step: int in range(200):
		var actor: CombatUnit = turns.current_unit
		if actor.is_ally and units.size() >= 13:
			break
		if not actor.is_ally:
			units[0].reaction_left = 0
			units[1].reaction_left = 0
			await ai.play_turn(actor, actions)
		if turns.current_unit == actor:
			turns.end_turn()
	for frame: int in range(4):
		await process_frame
	var fixture_failures: int = failures
	_check(units.size() == 13 and turns.round_number == 3 and turns.current_unit == units[1],
		"실제3-1 AI가 새끼6마리를 생성한 뒤 궁수 턴에서 누적 초상 입력 검사")
	var portraits: Dictionary = hud.get("_portraits")
	var spawned: Array[CombatUnit] = []
	for unit: CombatUnit in units:
		if unit not in initial_units:
			spawned.append(unit)
	_check(spawn_events[0] == 6 and spawned.size() == 6
		and spawned.all(func(unit: CombatUnit) -> bool:
			return not unit.is_ally and unit.kind == CombatUnit.Kind.SPIDERLING),
		"소환 전제조건: 소환 로그6건과 실제 새 개체6개 일치")
	_check(portraits.size() == 13 and units.all(func(unit: CombatUnit) -> bool: return portraits.has(unit)),
		"소환 전제조건: 살아 있는 각 유닛과 초상13개 일치")
	if failures != fixture_failures:
		main.queue_free()
		await process_frame
		return
	var resources: Array[int] = [units[0].movement_left, units[0].action_left,
		units[0].bonus_action_left, units[0].reaction_left, units[1].movement_left,
		units[1].action_left, units[1].bonus_action_left, units[1].reaction_left]
	_check(resources == [CombatUnit.MOVEMENT_PER_TURN, 1, 1, 1,
		CombatUnit.MOVEMENT_PER_TURN, 1, 1, 1], "소환 전제조건: 새 라운드의 두 아군 턴 자원 회복")
	if failures != fixture_failures:
		main.queue_free()
		await process_frame
		return
	# 포인터로 오른쪽 끝까지 이동한 뒤 가려졌던 아군 초상을 선택한다.
	for step: int in range(16):
		await _click(Vector2(80, 50), MOUSE_BUTTON_WHEEL_RIGHT)
	await _click((portraits[units[0]] as Button).get_global_rect().get_center())
	_check(turns.current_unit == units[0] and hud.unit_label.text == "아군 전사",
		"새끼가 누적되어도 오른쪽 아군 초상을 스크롤하고 실제 클릭으로 조작 전환")
	_check(resources == [units[0].movement_left, units[0].action_left, units[0].bonus_action_left,
		units[0].reaction_left, units[1].movement_left, units[1].action_left,
		units[1].bonus_action_left, units[1].reaction_left], "소환 후 아군 초상 전환은 두 아군 턴 자원 보존")
	for step: int in range(16):
		await _click(Vector2(80, 50), MOUSE_BUTTON_WHEEL_LEFT)
	var enemy: CombatUnit = turns.ordered_units.front()
	await _click((portraits[enemy] as Button).get_global_rect().get_center())
	_check(turns.current_unit == units[0] and hud.unit_label.text == enemy.get_display_name(),
		"반대쪽 끝의 적 초상도 스크롤하고 조회하며 아군 조작 유지")
	_check(resources == [units[0].movement_left, units[0].action_left, units[0].bonus_action_left,
		units[0].reaction_left, units[1].movement_left, units[1].action_left,
		units[1].bonus_action_left, units[1].reaction_left], "소환 후 스크롤·적 조회는 두 아군 턴 자원 보존")
	(battle.get_node("HitSound") as AudioStreamPlayer).stop()
	await create_timer(0.08).timeout
	main.queue_free()
	await process_frame


func _click(point: Vector2, button_index: MouseButton = MOUSE_BUTTON_LEFT) -> void:
	var event: InputEventMouseButton = InputEventMouseButton.new()
	event.position = root.get_final_transform() * point
	event.global_position = event.position
	event.button_index = button_index
	event.pressed = true
	Input.parse_input_event(event)
	await process_frame
	event.pressed = false
	Input.parse_input_event(event)
	await process_frame
	for frame: int in range(600):
		var moving: bool = false
		for unit: CombatUnit in units:
			moving = moving or unit.is_moving
		if not moving and not battle.has_node("Arrow"):
			return
		await process_frame
	_check(false, "포인터 입력 후 연출이 제한 시간 안에 끝나지 않음")


func _test_action_animations() -> void:
	_reset_units()
	units[0].cell = Vector2i(4, 4)
	units[1].cell = Vector2i(0, 0)
	units[2].cell = Vector2i(8, 8)
	units[3].cell = Vector2i(9, 9)
	battle.call("_update_turn_ui")
	var origin: Vector2 = units[0].position
	var finished: Array[bool] = [false]
	_animated_move(units[0], Vector2i(4, 2), finished)
	_check(actions.busy and units[0].is_moving and units[0].cell == Vector2i(4, 4)
		and units[0].movement_left == 6, "이동 연출 시작은 입력 잠금, 논리 칸·이동력 유지")
	hud.end_button.pressed.emit()
	hud.unit_selected.emit(units[1])
	hud.restart_button.pressed.emit()
	_check(turns.current_unit == units[0] and battle.progress.stage_index == 0,
		"이동 중 턴 종료·유닛 전환·스테이지 전환 거부")
	await process_frame
	await process_frame
	await process_frame
	var intermediate: Vector2 = units[0].position
	battle.call("_update_turn_ui")
	_check(units[0].position == intermediate and units[0].position != origin,
		"이동 중 UI 갱신은 실제 중간 위치를 되돌리지 않음")
	while not finished[0]:
		await process_frame
	_check(units[0].cell == Vector2i(4, 2) and units[0].movement_left == 4
		and units[0].position == (battle.get_node("Map") as TileMapLayer).map_to_local(units[0].cell)
		and not units[0].is_moving and units[0].body_offset_y == 0.0 and not actions.busy,
		"두 사각 칸 이동은 도착 후 자원 갱신과 몸통·입력 복구")
	for side: bool in [true, false]:
		for shock: bool in [false, true]:
			if not side and shock:
				continue
			_reset_units()
			var actor: CombatUnit = units[1] if side else units[3]
			var target: CombatUnit = units[2] if side else units[0]
			actor.shock_left = 1
			actor.cell = Vector2i(1, 4)
			target.cell = Vector2i(4, 4)
			(units[0] if side else units[2]).cell = Vector2i(9, 9)
			(units[3] if side else units[1]).cell = Vector2i(0, 0)
			target.reaction_left = 0
			if side:
				turns.select_unit(actor)
			else:
				while turns.current_unit != actor:
					turns.end_turn()
			battle.call("_update_turn_ui")
			actions.dice = ScriptedDice.new([20], [20]).then_seeded()
			var hp: int = target.hit_points
			finished[0] = false
			_animated_attack(actor, target, shock, finished)
			_check(actions.busy and battle.has_node("Arrow") and target.hit_points == hp,
				"아군·적 궁수 기본/충격 화살은 비행 중 피해 적용 전: %s/%s" % [side, shock])
			_check(not actions.can_move(actor, Vector2i(2, 4)) and not actions.can_use(actor, "attack")
				and not await actions.attack(actor, target, shock), "화살 비행 중 중복 입력 거부")
			while not finished[0]:
				await process_frame
			await process_frame
			_check(target.hit_points < hp and actor.action_left == 0 and (not shock or actor.shock_left == 0)
				and not battle.has_node("Arrow")
				and not actions.busy, "화살 도착 후 피해·비용 처리와 투사체 정리")
	_reset_units()
	units[1].cell = Vector2i(1, 4)
	units[2].cell = Vector2i(4, 4)
	turns.select_unit(units[1])
	battle.call("_update_turn_ui")
	actions.dice = _dice_for_miss()
	finished[0] = false
	_animated_attack(units[1], units[2], false, finished)
	_check(battle.has_node("Arrow"), "확정 빗나감에도 화살 비행 표시")
	while not finished[0]:
		await process_frame
	_check(units[2].hit_points == units[2].get_max_hit_points() and units[1].action_left == 0,
		"빗나감은 비행 후 행동만 소비하고 피해 없음")
	_reset_units()
	units[0].cell = Vector2i(4, 4)
	units[1].cell = Vector2i(0, 0)
	units[2].cell = Vector2i(9, 9)
	units[3].cell = Vector2i(1, 4)
	while turns.current_unit != units[3]:
		turns.end_turn()
	battle.call("_update_turn_ui")
	actions.dice = ScriptedDice.new([20], [20]).then_seeded()
	var reactions: Array[int] = [0]
	var on_reaction: Callable = func(kind: String, _prompt: String) -> void:
		var arrow: Node = battle.get_node_or_null("Arrow")
		_check(kind == "parry" and (arrow == null or arrow.is_queued_for_deletion())
			and units[0].hit_points == units[0].get_max_hit_points() and actions.busy,
			"적 화살이 도착한 뒤 피해 전에 흘려내기 확인")
		reactions[0] += 1
		hud.reaction_dialog.get_cancel_button().pressed.emit()
	actions.reaction_requested.connect(on_reaction)
	await actions.attack(units[3], units[0])
	await process_frame
	_check(reactions[0] == 1 and not actions.busy and not hud.reaction_dialog.visible,
		"화살 도착 뒤 반응 넘기기는 전투를 정상 재개")
	actions.reaction_requested.disconnect(on_reaction)
	_reset_units()


func _animated_move(actor: CombatUnit, cell: Vector2i, finished: Array[bool]) -> void:
	await actions.move_to(actor, cell)
	finished[0] = true


func _animated_attack(actor: CombatUnit, target: CombatUnit, shock: bool, finished: Array[bool]) -> void:
	await actions.attack(actor, target, shock)
	finished[0] = true


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
		_check(not units[3].is_moving and units[3].cell == Vector2i(5, 4)
			and units[3].position == (battle.get_node("Map") as TileMapLayer).map_to_local(Vector2i(5, 4)),
			"기회 공격을 기다리는 동안 이동 연출 전의 칸·위치 유지")
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
	actions.dice = ScriptedDice.new([1], [20])
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


func _test_reaction_focus() -> void:
	var choices: Array[bool] = []
	var stale_focus_requests: Array[int] = [0]
	var on_choice: Callable = func(use_reaction: bool) -> void: choices.append(use_reaction)
	# Headless는 접근성을 지원하지 않는다. 엔진의 부모→exclusive child 포커스 전달을 모형화한다.
	var on_parent_focus: Callable = func() -> void:
		if hud.reaction_dialog.exclusive:
			stale_focus_requests[0] += 1
			hud.reaction_dialog.grab_focus()
	root.focus_entered.connect(on_parent_focus)
	hud.reaction_selected.connect(on_choice)
	for choice: String in ["cancel", "ok", "close", "escape", "stage", "result"]:
		hud.show_reaction("parry", "접근성 포커스 회귀")
		await process_frame
		_check(hud.reaction_dialog.visible and hud.reaction_dialog.exclusive,
			"반응 선택 중 모달 입력 유지: " + choice)
		var before: int = choices.size()
		match choice:
			"cancel":
				hud.reaction_dialog.get_cancel_button().pressed.emit()
			"ok":
				hud.reaction_dialog.get_ok_button().pressed.emit()
			"close":
				hud.reaction_dialog.notification(Window.NOTIFICATION_WM_CLOSE_REQUEST)
			"escape":
				var key: InputEventKey = InputEventKey.new()
				key.keycode = KEY_ESCAPE
				key.pressed = true
				Input.parse_input_event(key)
			"stage":
				hud.begin_stage(1, 1)
			"result":
				hud.show_result(true)
		await process_frame
		await process_frame
		_check(not hud.reaction_dialog.visible, "반응 창 닫힘: " + choice)
		var is_choice: bool = choice in ["cancel", "ok", "close", "escape"]
		_check(choices.size() == before + int(is_choice), "반응 결정 정확히 한 번 또는 화면 전환 시 미결정: " + choice)
		if is_choice:
			_check(choices.back() == (choice == "ok"), "확인만 반응 사용: " + choice)
	_check(stale_focus_requests[0] == 0, "제거된 반응 창에 접근성 포커스를 전달하지 않음")
	hud.reaction_selected.disconnect(on_choice)
	root.focus_entered.disconnect(on_parent_focus)
	hud.begin_stage(1, 1)
