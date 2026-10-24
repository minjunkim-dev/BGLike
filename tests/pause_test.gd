extends SceneTree
## 실제 게임 장면에서 일시정지 메뉴, 메뉴 중 전투 정지, 전투 포기, 타이틀로·종료 확인 창을 검사한다 (#286).

const WINDOWS: Array[Vector2i] = [Vector2i(1280, 720), Vector2i(1920, 1080), Vector2i(1440, 900)]
## 창별 논리 화면. headless 기본 창이 아니라 이 크기의 실제 창에서 배치를 본다 (#272).
const LOGICAL: Dictionary[Vector2i, Vector2] = {Vector2i(1280, 720): Vector2(640, 360),
	Vector2i(1920, 1080): Vector2(640, 360), Vector2i(1440, 900): Vector2(640, 400)}
## ADR 0002의 레이아웃 자동 검사 창: 16:10 4배, 넓은 비율, 비정수 배율.
const EXTRA_WINDOWS: Array[Vector2i] = [Vector2i(2560, 1600), Vector2i(2560, 1080), Vector2i(1366, 768)]
const GIVE_UP_TEXT: String = "전투를 포기하면 패배로 처리되고, 이 막을 처음부터 다시 합니다."
## 여러 worktree가 같은 user://를 쓰므로 실행마다 폴더를 나눈다 (docs/adr/0003).
var directory: String = "user://tests/pause/%d" % OS.get_process_id()

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
	DirAccess.make_dir_recursive_absolute(directory)
	GameSave.path = directory + "/save.bin"
	GameSettings.path = directory + "/settings.cfg"
	GameSave.autosave = true
	root.size = WINDOWS[0]
	var battle: Node2D = await _open_game()
	var menu: PauseMenu = battle.get("pause_menu") as PauseMenu
	await _check_menu(battle, menu)
	await _check_layout(menu)
	await _check_screens(menu)
	await _check_confirms(menu)
	await _check_dialog_keys(battle, menu)
	await _check_give_up(battle, menu)
	await _check_after_combat(battle, menu)
	await _check_to_title(menu)
	await _check_split_groups(await _open_game())
	battle = await _open_game()
	await _check_enemy_turn(battle, battle.get("pause_menu") as PauseMenu)
	_finish()


func _open_game() -> Node2D:
	if current_scene != null:
		current_scene.queue_free()
		await process_frame
	var game: Node = (load(TitleScreen.GAME_SCENE) as PackedScene).instantiate()
	root.add_child(game)
	current_scene = game
	var battle: Node2D = game.get_node("Battle") as Node2D
	# 적 턴은 검사가 직접 시작한다. 아군이 먼저인 시드로 턴 순서를 다시 굴린다.
	battle.set_process(false)
	battle.call("start_battle")
	var turns: CombatTurns = battle.get("turns") as CombatTurns
	var dice: CombatDice = CombatDice.new()
	while turns.current_unit == null or not turns.current_unit.is_ally:
		dice.seed += 1
		turns.start(battle.get("units"), dice)
	await process_frame
	return battle


## 아군 턴에 Esc로 열면 트리가 멈추고 여섯 버튼이 보인다. 방향키·D-pad는 메뉴 안에서만 옮긴다.
func _check_menu(battle: Node2D, menu: PauseMenu) -> void:
	var turns: CombatTurns = battle.get("turns") as CombatTurns
	var hud: CombatTurnHud = battle.get_node("UI/TurnHud") as CombatTurnHud
	_check(not menu.visible and turns.current_unit.is_ally, "처음에는 메뉴가 닫힌 아군 턴")
	hud.end_button.grab_focus()
	await _tap(_key(KEY_ESCAPE))
	_check(menu.visible and paused and menu.resume_button.has_focus(), "Esc로 메뉴를 열고 게임을 멈춤, 계속에 포커스")
	_check(_shown(menu) == ["계속", "설정", "도움말", "전투 포기", "타이틀로", "종료"], "전투 중 메뉴 버튼: %s" % [_shown(menu)])
	_check(not battle.can_process() and menu.can_process() and menu.settings.can_process() and menu.help.can_process(),
		"메뉴·설정·도움말만 멈춘 동안 동작")
	# 숫자 키·Tab·턴 종료 클릭이 전투에 닿지 않는다.
	var actor: CombatUnit = turns.current_unit
	await _tap(_key(KEY_1, KEY_1))
	await _tap(_key(KEY_TAB))
	await _click(hud.end_button.get_global_rect().get_center())
	_check(menu.visible and turns.current_unit == actor and not hud.get_node("Result").visible
		and not hud.end_button.has_focus(), "메뉴가 열린 동안 전투 입력을 받지 않음")
	var path: PackedStringArray = []
	for step: int in range(7):
		await _tap(_action("ui_down") if step % 2 == 0 else _joypad(JOY_BUTTON_DPAD_DOWN))
		path.append(_focus_name())
	_check(menu.quit_button.has_focus(), "아래로 끝까지 가서 종료에서 멈춤: %s" % [path])
	await _tap(_action("ui_left"))
	await _tap(_action("ui_right"))
	_check(menu.quit_button.has_focus(), "좌우 방향키는 메뉴 밖으로 나가지 않음")
	for step: int in range(7):
		await _tap(_action("ui_up"))
	_check(menu.resume_button.has_focus(), "위로 끝까지 가서 계속에서 멈춤")
	await _tap(_action("ui_accept"))
	_check(not menu.visible and not paused and hud.end_button.has_focus(), "계속은 메뉴를 닫고 전의 포커스로 돌아감")
	await _tap(_joypad(JOY_BUTTON_START))
	_check(menu.visible and paused, "컨트롤러 Start로 메뉴를 엶")
	await _tap(_joypad(JOY_BUTTON_START))
	_check(not menu.visible and not paused, "컨트롤러 Start로 메뉴를 닫음")
	await _tap(_key(KEY_ESCAPE))
	await _tap(_key(KEY_ESCAPE))
	_check(not menu.visible and not paused, "Esc로 열고 Esc로 닫음")
	# 끝난 행동의 저장이 다음 프레임을 기다리는 중에 메뉴를 열면 멈추기 전에 쓴다(메뉴에서 바로 종료해도 남는다).
	GameSave.delete()
	(battle.get("actions") as CombatActions).changed.emit()
	await _tap(_key(KEY_ESCAPE))
	_check(GameSave.has_save() and not battle.get("_save_pending"), "메뉴를 열 때 미뤄 둔 자동 저장을 씀")
	await _tap(_key(KEY_ESCAPE))


## 설정과 도움말은 타이틀과 같은 장면이다. 닫으면 메뉴의 자기 버튼으로 돌아오고 게임은 계속 멈춰 있다.
func _check_screens(menu: PauseMenu) -> void:
	await _tap(_key(KEY_ESCAPE))
	await _tap(_action("ui_down"))
	await _tap(_action("ui_accept"))
	_check(menu.settings.visible and not menu.menu.visible and menu.settings.volume_slider.has_focus() and paused,
		"설정을 열고 음량 슬라이더에 포커스, 게임은 멈춘 채")
	await _check_layout(menu)
	await _tap(_action("ui_left"))
	_check(menu.settings.volume_slider.value == 70 and GameSettings.volume() == 70, "메뉴의 설정에서 음량을 바꾸고 파일에 씀")
	await _tap(_key(KEY_ESCAPE))
	_check(not menu.settings.visible and menu.menu.visible and menu.settings_button.has_focus() and paused,
		"Esc로 설정을 닫고 설정 버튼으로, 메뉴는 열린 채")
	await _tap(_joypad(JOY_BUTTON_DPAD_DOWN))
	await _tap(_joypad(JOY_BUTTON_A))
	_check(menu.help.visible and not menu.menu.visible and menu.help.back_button.has_focus(), "컨트롤러 A로 도움말을 엶")
	var text: String = "\n".join(menu.help.scroll.find_children("*", "Label", true, false).map(
		func(label: Label) -> String: return label.text))
	_check("일시정지 메뉴" in text and "Start" in text, "도움말에 일시정지 메뉴를 여는 키")
	await _check_layout(menu)
	await _tap(_joypad(JOY_BUTTON_DPAD_DOWN))
	_check(menu.help.scroll.scroll_vertical > 0, "멈춘 동안 D-pad로 도움말 스크롤")
	await _tap(_joypad(JOY_BUTTON_A))
	_check(not menu.help.visible and menu.menu.visible and menu.help_button.has_focus() and paused,
		"뒤로로 도움말을 닫고 도움말 버튼으로")
	await _tap(_key(KEY_ESCAPE))
	_check(not menu.visible and not paused, "Esc로 메뉴를 닫고 게임을 이어 감")


## 타이틀로·종료는 확인 창을 거친다. 자동 저장이 있으므로 저장 안내는 없다. 취소가 기본 선택이다.
func _check_confirms(menu: PauseMenu) -> void:
	await _tap(_key(KEY_ESCAPE))
	for button: Button in [menu.title_button, menu.quit_button]:
		button.grab_focus()
		await _tap(_action("ui_accept"))
		var dialog: ConfirmationDialog = menu.confirm
		_check(dialog.visible and dialog.get_cancel_button().has_focus() and dialog.theme == preload("res://scenes/ui_theme.tres"),
			"%s: 확인 창, 취소에 포커스, 공용 테마" % button.text)
		_check(dialog.dialog_text == ("타이틀 화면으로 돌아가시겠습니까?" if button == menu.title_button else "게임을 종료하시겠습니까?")
			and "저장" not in dialog.dialog_text, "%s: 확인 문구에 저장 안내 없음: %s" % [button.text, dialog.dialog_text])
		_check(dialog.get_ok_button().text == button.text and dialog.get_cancel_button().text == "취소",
			"%s: 확인 버튼 이름" % button.text)
		await _check_dialog_layout(dialog)
		await _tap(_key(KEY_ESCAPE))
		_check(not dialog.visible and menu.visible and menu.menu.visible and button.has_focus() and paused,
			"%s: Esc로 확인 창만 닫고 버튼으로 포커스" % button.text)
	_check(menu.get("_on_confirm") == quit, "종료 확인은 SceneTree.quit")
	await _tap(_key(KEY_ESCAPE))


## 반응 확인 창과 정비 확인 창에서 Esc는 지금처럼 그 창을 닫고 메뉴를 열지 않는다.
func _check_dialog_keys(battle: Node2D, menu: PauseMenu) -> void:
	var actions: CombatActions = battle.get("actions") as CombatActions
	var hud: CombatTurnHud = battle.get_node("UI/TurnHud") as CombatTurnHud
	var answers: Array[bool] = []
	var record: Callable = func(answer: bool) -> void: answers.append(answer)
	actions.reaction_decided.connect(record)
	actions.pending_reactor = battle.get("party")[0]
	hud.show_reaction("opportunity", "검사용 기회 공격")
	await process_frame
	await _tap(_joypad(JOY_BUTTON_START))
	_check(hud.reaction_dialog.visible and not menu.visible, "반응 확인 창에서 Start는 메뉴를 열지 않음")
	await _tap(_key(KEY_ESCAPE))
	_check(not hud.reaction_dialog.visible and answers == [false] and not menu.visible and not paused,
		"반응 확인 창에서 Esc는 넘기기, 메뉴를 열지 않음")
	actions.reaction_decided.disconnect(record)
	var preparation: CombatPreparation = battle.get("preparation") as CombatPreparation
	preparation.discard_dialog.popup_centered()
	await process_frame
	await _tap(_joypad(JOY_BUTTON_START))
	_check(preparation.discard_dialog.visible and not menu.visible, "정비 확인 창에서 Start는 메뉴를 열지 않음")
	await _tap(_key(KEY_ESCAPE))
	_check(not preparation.discard_dialog.visible and not menu.visible and not paused, "정비 확인 창에서 Esc는 창만 닫음")


## 2-2에서 포기하면 전멸과 같다: 패배 결과 → 2-1부터, HP·전투 불능·스킬 횟수 초기화, 장비·가방·물약 유지.
func _check_give_up(battle: Node2D, menu: PauseMenu) -> void:
	var progress: CombatActProgress = battle.get("progress") as CombatActProgress
	var hud: CombatTurnHud = battle.get_node("UI/TurnHud") as CombatTurnHud
	var actions: CombatActions = battle.get("actions") as CombatActions
	progress.stage_index = 4
	battle.call("_start_stage", false)
	battle.call("start_battle")
	await process_frame
	_check(hud.progress_label.text == "2막 · 2스테이지", "검사 시작은 2-2")
	var party: Array[CombatUnit] = battle.get("party")
	var item: Dictionary = {}
	for definition: Dictionary in battle.loot.data["items"]:
		if definition["kind"] == "weapon" and battle.loot.can_receive(party[0], definition):
			item = definition.duplicate(true)
			for stat: String in definition["stats"]:
				item["stats"][stat] = int(definition["stats"][stat][1][0])
			break
	_check(battle.loot.receive(party[0], item), "검사용 무기 장착")
	var weapon: Dictionary = party[0].weapon.duplicate(true)
	battle.loot.bag.append({"kind": "potion", "name": "가방의 물약", "stats": {}})
	var bag: Array[Dictionary] = battle.loot.bag.duplicate(true)
	party[0].potion_left = 2
	party[0].hit_points = 3
	party[0].second_wind_left = 0
	party[1].shock_left = 0
	actions.incapacitate(party[1])
	actions.changed.emit()
	await _tap(_key(KEY_ESCAPE))
	menu.give_up_button.grab_focus()
	await _tap(_action("ui_accept"))
	var dialog: ConfirmationDialog = menu.confirm
	_check(dialog.visible and dialog.title == "전투 포기" and dialog.dialog_text == GIVE_UP_TEXT
		and dialog.get_ok_button().text == "포기" and dialog.get_cancel_button().has_focus(), "전투 포기 확인 창과 문구")
	await _tap(_action("ui_accept"))
	_check(not dialog.visible and menu.visible and menu.give_up_button.has_focus() and not actions.is_over(),
		"기본 선택(취소)으로 Enter를 눌러도 포기하지 않음")
	await _tap(_action("ui_accept"))
	dialog.get_ok_button().grab_focus()
	await _tap(_action("ui_accept"))
	await process_frame
	_check(not menu.visible and not paused, "포기를 확정하면 메뉴를 닫음")
	_check(actions.is_over() and not actions.is_victory() and party.all(func(unit: CombatUnit) -> bool:
		return unit.hit_points == 0), "포기는 아군 전멸과 같은 패배")
	_check(hud.get_node("Result").visible and hud.result_label.text == "패배"
		and hud.restart_button.text == "이 막 다시 시작" and not hud.restart_button.disabled
		and hud.restart_button.has_focus(), "패배 결과 화면")
	_check("전투 포기" in hud.message_label.text, "전투 기록에 전투 포기")
	_check(_saved_defeat(), "포기를 확정한 순간의 전멸 상태를 저장")
	await _tap(_action("ui_accept"))
	await process_frame
	_check(hud.progress_label.text == "2막 · 1스테이지" and not hud.get_node("Result").visible, "포기한 막의 1스테이지부터")
	for unit: CombatUnit in party:
		_check(unit.hit_points == unit.get_max_hit_points() and unit.visible and unit.second_wind_left == 1
			and unit.shock_left == 1, "%s: HP·전투 불능·스킬 횟수 초기화" % unit.get_display_name())
	_check(party[0].weapon == weapon and not weapon.is_empty() and battle.loot.bag == bag and party[0].potion_left == 2,
		"장비·가방·물약 유지")


## 전투가 끝난 결과 화면과 보상·정비 화면에서는 `전투 포기`가 없다.
func _check_after_combat(battle: Node2D, menu: PauseMenu) -> void:
	var actions: CombatActions = battle.get("actions") as CombatActions
	var hud: CombatTurnHud = battle.get_node("UI/TurnHud") as CombatTurnHud
	for unit: CombatUnit in battle.get("units"):
		if not unit.is_ally:
			actions.incapacitate(unit)
	actions.changed.emit()
	await _tap(_key(KEY_ESCAPE))
	_check(menu.visible and _shown(menu) == ["계속", "설정", "도움말", "타이틀로", "종료"], "결과 화면 메뉴: %s" % [_shown(menu)])
	await _tap(_key(KEY_ESCAPE))
	_check(hud.restart_button.has_focus(), "메뉴를 닫으면 결과 버튼으로 포커스 복귀")
	await _tap(_action("ui_accept"))
	var preparation: CombatPreparation = battle.get("preparation") as CombatPreparation
	_check(preparation.visible, "보상 확인 화면")
	await _tap(_key(KEY_ESCAPE))
	_check(menu.visible and "전투 포기" not in _shown(menu) and paused, "정비·보상 화면 메뉴에 전투 포기 없음")
	await _check_layout(menu)


## 타이틀로를 확정하면 멈춤을 풀고 타이틀 화면으로 간다.
func _check_to_title(menu: PauseMenu) -> void:
	menu.title_button.grab_focus()
	await _tap(_action("ui_accept"))
	menu.confirm.get_ok_button().grab_focus()
	await _tap(_action("ui_accept"))
	await process_frame
	await process_frame
	_check(current_scene is TitleScreen and not paused, "타이틀로는 멈춤을 풀고 타이틀 화면으로")


## 아군이 두 묶음으로 나뉜 순서([아군][적][아군])에서 포기해도 사이의 적 턴 시작 효과가 들지 않는다.
## 과부하로 죽을 마지막 적이 있어도 승리로 바뀌지 않는다.
func _check_split_groups(battle: Node2D) -> void:
	var actions: CombatActions = battle.get("actions") as CombatActions
	var turns: CombatTurns = battle.get("turns") as CombatTurns
	var hud: CombatTurnHud = battle.get_node("UI/TurnHud") as CombatTurnHud
	var party: Array[CombatUnit] = battle.get("party")
	var enemy: CombatUnit = null
	for unit: CombatUnit in battle.get("units"):
		if not unit.is_ally:
			if enemy == null:
				enemy = unit
			else:
				actions.incapacitate(unit)
	var living: Array[CombatUnit] = [party[0], party[1], enemy]
	var dice: CombatDice = CombatDice.new()
	while turns.ordered_units != [turns.current_unit, enemy, turns.ordered_units[2]] or not turns.current_unit.is_ally:
		dice.seed += 1
		turns.start(living, dice)
	enemy.overloaded = true
	enemy.hit_points = 2
	battle.call("_give_up")
	await process_frame
	_check(actions.is_over() and not actions.is_victory() and enemy.hit_points == 2 and hud.result_label.text == "패배",
		"아군 묶음 사이의 적 턴 시작 효과 없이 패배: HP %d, %s" % [enemy.hit_points, hud.result_label.text])
	_check(hud.message_label.text.ends_with("전투 포기"), "전투 포기가 전투 기록의 마지막 줄")


## 적 턴 중에도 메뉴를 연다. 열린 동안 적 연출·타이머가 멈추고, 포기하면 적 턴이 끝난 뒤 결과 버튼이 풀린다.
func _check_enemy_turn(battle: Node2D, menu: PauseMenu) -> void:
	var hud: CombatTurnHud = battle.get_node("UI/TurnHud") as CombatTurnHud
	var actions: CombatActions = battle.get("actions") as CombatActions
	var turns: CombatTurns = battle.get("turns") as CombatTurns
	for ally: int in range(4):
		if turns.current_unit.is_ally:
			hud.end_button.pressed.emit()
	_check(not turns.current_unit.is_ally, "아군 턴을 모두 마침")
	battle.set_process(true)
	await process_frame
	await process_frame
	_check(battle.get("_enemy_turn_running"), "적 턴 진행 중")
	await create_timer(0.1).timeout
	await _tap(_key(KEY_ESCAPE))
	var before: Array = _snapshot(battle)
	await create_timer(1.0).timeout
	_check(menu.visible and battle.get("_enemy_turn_running") and _snapshot(battle) == before,
		"메뉴가 열린 동안 적 행동이 멈춤")
	menu.give_up_button.grab_focus()
	await _tap(_action("ui_accept"))
	# 확정과 같은 호출 안에서 본다. 다음 프레임이면 멈췄던 적 행동이 끝났을 수 있다.
	menu.confirm.get_ok_button().pressed.emit()
	_check(actions.is_over() and not actions.is_victory() and hud.result_label.text == "패배", "적 턴 중 포기도 패배")
	_check(_saved_defeat(), "적 턴 중에도 포기한 순간을 바로 저장")
	_check(battle.get("_enemy_turn_running") and hud.restart_button.disabled, "진행 중인 적 행동이 끝날 때까지 결과 버튼 잠금")
	var waited: float = 0.0
	while battle.get("_enemy_turn_running") and waited < 5.0:
		await create_timer(0.05).timeout
		waited += 0.05
	_check(not battle.get("_enemy_turn_running") and not hud.restart_button.disabled
		and hud.get_node("Result").visible, "적 턴이 끝난 뒤 결과 버튼이 풀림")
	_check(_saved_defeat(), "남은 적 행동이 끝나도 포기 저장을 적 턴 시작 상태로 덮지 않음")
	# 강제 종료 뒤 이어하기: 저장을 새 게임 장면에 되돌리면 포기한 패배 결과다.
	var state: Variant = GameSave.read().sections.combat
	battle = await _open_game()
	hud = battle.get_node("UI/TurnHud") as CombatTurnHud
	_check(battle.call("restore_combat", state) and (battle.get("actions") as CombatActions).is_over()
		and hud.get_node("Result").visible and hud.result_label.text == "패배"
		and hud.restart_button.text == "이 막 다시 시작", "포기 저장을 이어하면 패배 결과 화면")


## 마지막 저장이 아군 전원 전투 불능인 전투 상태인지.
func _saved_defeat() -> bool:
	var save: Dictionary = GameSave.read()
	if save.is_empty():
		return false
	var allies: Array = save.sections.combat.units.filter(func(unit: Dictionary) -> bool: return unit.ally)
	return not allies.is_empty() and allies.all(func(unit: Dictionary) -> bool: return unit.hit_points == 0)


func _snapshot(battle: Node2D) -> Array:
	var turns: CombatTurns = battle.get("turns") as CombatTurns
	var state: Array = [turns.current_unit, (battle.get_node("UI/TurnHud") as CombatTurnHud).message_label.text]
	for unit: CombatUnit in battle.get("units"):
		state.append([unit.cell, unit.position, unit.is_moving, unit.facing_left, unit.hit_points,
			unit.movement_left, unit.action_left])
	return state


func _shown(menu: PauseMenu) -> Array:
	return menu.menu.get_children().filter(func(node: Node) -> bool:
		return node is Button and (node as Button).visible).map(func(button: Button) -> String:
			return button.text)


## ADR 0002의 여섯 창에서 메뉴와 열린 화면이 논리 화면 안에 겹치지 않고 들어간다.
func _check_layout(menu: PauseMenu) -> void:
	for size: Vector2i in WINDOWS + EXTRA_WINDOWS:
		root.size = size
		await process_frame
		await process_frame
		var screen: Rect2 = Rect2(Vector2.ZERO, menu.get_viewport_rect().size)
		_check(screen.size == LOGICAL.get(size, screen.size), "%s: 논리 화면 %s" % [size, screen.size])
		_check(menu.get_global_rect() == screen, "%s: 메뉴가 논리 화면 전체를 덮음" % size)
		var areas: Array[Control] = []
		if menu.settings.visible:
			_check(menu.settings.get_global_rect() == screen, "%s: 설정이 화면 전체" % size)
			areas = [menu.settings.find_child("Heading") as Control, menu.settings.back_button]
			areas.append_array(menu.settings.find_child("Grid").get_children())
		elif menu.help.visible:
			_check(menu.help.get_global_rect() == screen, "%s: 도움말이 화면 전체" % size)
			areas = [menu.help.find_child("Heading") as Control, menu.help.scroll, menu.help.back_button]
		else:
			for node: Node in menu.menu.get_children():
				if (node as Control).visible:
					areas.append(node as Control)
		for index: int in range(areas.size()):
			var rect: Rect2 = areas[index].get_global_rect()
			_check(screen.encloses(rect), "%s: 화면 안: %s" % [size, areas[index].name])
			for other: Control in areas.slice(index + 1):
				_check(not rect.intersects(other.get_global_rect()),
					"%s: 겹치지 않음: %s, %s" % [size, areas[index].name, other.name])
	root.size = WINDOWS[0]
	await process_frame
	await process_frame


func _check_dialog_layout(dialog: ConfirmationDialog) -> void:
	for size: Vector2i in WINDOWS + EXTRA_WINDOWS:
		root.size = size
		await process_frame
		dialog.popup_centered(Vector2i(360, 110))
		await process_frame
		var screen: Rect2 = Rect2(Vector2.ZERO, dialog.get_parent().get_viewport().get_visible_rect().size)
		_check(screen.encloses(Rect2(dialog.position, dialog.size)) and dialog.get_label().get_line_count() <= 2,
			"%s: 확인 창이 화면 안: %s / %s" % [size, Rect2(dialog.position, dialog.size), screen])
	root.size = WINDOWS[0]
	await process_frame
	dialog.get_cancel_button().grab_focus()


func _focus_name() -> String:
	var owner: Control = root.gui_get_focus_owner()
	return owner.name if owner else "-"


func _key(keycode: Key, physical: Key = KEY_NONE) -> InputEventKey:
	var event: InputEventKey = InputEventKey.new()
	event.keycode = keycode
	event.physical_keycode = physical
	return event


func _action(action: String) -> InputEventAction:
	var event: InputEventAction = InputEventAction.new()
	event.action = action
	return event


func _joypad(button: JoyButton) -> InputEventJoypadButton:
	var event: InputEventJoypadButton = InputEventJoypadButton.new()
	event.button_index = button
	return event


func _click(position: Vector2) -> void:
	var point: Vector2 = root.get_final_transform() * position
	var click: InputEventMouseButton = InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.position = point
	click.global_position = point
	await _tap(click)


## 누름과 뗌을 한 프레임씩 보낸다.
func _tap(event: InputEvent) -> void:
	event.set("pressed", true)
	Input.parse_input_event(event)
	await process_frame
	event.set("pressed", false)
	Input.parse_input_event(event)
	await process_frame


func _finish() -> void:
	print("Pause: %d checks, %d failures;" % [checks, failures])
	paused = false
	GameSave.autosave = false
	if current_scene:
		current_scene.queue_free()
	await process_frame
	GameSave.delete()
	for file: String in [GameSettings.path, GameSettings.path + ".tmp"]:
		DirAccess.remove_absolute(file)
	DirAccess.remove_absolute(directory)
	quit(0 if failures == 0 else 1)
