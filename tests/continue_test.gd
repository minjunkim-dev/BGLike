extends SceneTree
## 새 게임·이어하기·졸업 흐름 (#284). 실제 타이틀에서 새 게임으로 시작해 행동하고, 게임을 다시 켠 것처럼 타이틀을
## 새로 열어 이어하면 마지막으로 끝난 행동 직후의 전투·보상·정비 화면으로 돌아오는지 본다. 덮어쓰기 확인,
## 읽을 수 없는 저장, 졸업 때의 저장 삭제와 `타이틀로`도 본다.

const WINDOWS: Array[Vector2i] = [Vector2i(1280, 720), Vector2i(1920, 1080), Vector2i(1440, 900)]
## 창별 논리 화면. headless 기본 창이 아니라 이 크기의 실제 창에서 배치를 본다 (#272).
const LOGICAL: Dictionary[Vector2i, Vector2] = {Vector2i(1280, 720): Vector2(640, 360),
	Vector2i(1920, 1080): Vector2(640, 360), Vector2i(1440, 900): Vector2(640, 400)}
## ADR 0002의 레이아웃 자동 검사 창: 16:10 4배, 넓은 비율, 비정수 배율.
const EXTRA_WINDOWS: Array[Vector2i] = [Vector2i(2560, 1600), Vector2i(2560, 1080), Vector2i(1366, 768)]
const UNREADABLE: String = "저장을 읽을 수 없어\n이어할 수 없습니다."
const ScriptedDice = preload("res://tests/scripted_dice.gd")
## 여러 worktree가 같은 user://를 쓰므로 실행마다 폴더를 나눈다. 사용자의 저장을 건드리지 않는다 (docs/adr/0003).
var directory: String = "user://tests/continue/%d" % OS.get_process_id()
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
	root.size = WINDOWS[0]
	await _test_new_game_and_continue()
	await _test_preparation_screens()
	await _test_overwrite()
	await _test_unreadable()
	await _test_graduation()
	_finish()


## 새 게임 → 아군 행동 셋 → 게임을 끄고 다시 켬 → 이어하기. 마지막 행동 직후의 전투로 돌아오고 저장을 덮지 않는다.
func _test_new_game_and_continue() -> void:
	var title: TitleScreen = await _open_title()
	_check(not title.continue_button.visible and not title.notice.visible, "저장이 없으면 이어하기와 안내를 숨김")
	title.new_game_button.pressed.emit()
	_check(not title.overwrite.visible, "저장이 없으면 확인 없이 새 게임")
	var battle: Node2D = await _new_battle()
	var saves: Array[int] = [0]
	battle.connect("autosaved", func() -> void: saves[0] += 1)
	await process_frame
	var save: Dictionary = GameSave.read()
	_check(GameSave.autosave and saves[0] == 1 and save.get("act") == 1 and save.get("stage") == 1
		and GameSave.summary_text(save) == "1막 1스테이지 진행 중", "새 게임은 1-1 시작 상태를 저장")
	var actions: CombatActions = battle.get("actions")
	var turns: CombatTurns = battle.get("turns")
	var first: CombatUnit = turns.current_unit
	_check(await _approach(battle, first), "첫 아군 이동")
	battle.call("_end_turn")
	await _settle()
	var second: CombatUnit = turns.current_unit
	_check(second != first and second.is_ally and await _approach(battle, second), "둘째 아군 이동")
	_check(saves[0] >= 4 and not battle.get("_save_pending"), "행동마다 저장: %d" % saves[0])
	var second_index: int = actions.units.find(second)
	var state: Dictionary = battle.call("combat_state")
	_check(GameSave.read().sections.combat == state and not GameSave.read().sections.has("preparation"),
		"마지막으로 끝난 행동 직후의 전투를 저장")
	var bytes: PackedByteArray = FileAccess.get_file_as_bytes(GameSave.path)
	title = await _open_title()
	_check(title.continue_button.visible and not title.notice.visible
		and title.continue_button.get_index() == title.new_game_button.get_index() + 1, "다시 켜면 이어하기를 보임")
	battle = await _continue(title)
	_check(battle != null and battle.call("combat_state") == state, "이어하면 마지막 행동 직후의 전투")
	if battle == null:
		return
	_check((battle.get("turns") as CombatTurns).current_unit == (battle.get("units") as Array)[second_index]
		and (battle.get_node("UI/TurnHud/Progress") as Label).text == "1막 · 1스테이지", "같은 아군의 차례, 같은 스테이지")
	await process_frame
	await process_frame
	_check(GameSave.autosave and FileAccess.get_file_as_bytes(GameSave.path) == bytes,
		"이어한 뒤에도 자동 저장을 켜고, 1-1 시작 상태로 저장을 덮지 않음")
	# 일시정지 메뉴의 `타이틀로`(#286)로 나가도 같은 자리에서 이어한다.
	var menu: PauseMenu = battle.get("pause_menu")
	await _tap(_action("pause"))
	menu.title_button.pressed.emit()
	menu.confirm.get_ok_button().pressed.emit()
	await _settle()
	_check(current_scene is TitleScreen and (current_scene as TitleScreen).continue_button.visible and not paused,
		"일시정지 메뉴의 타이틀로 뒤 타이틀에 이어하기")
	if current_scene is TitleScreen:
		battle = await _continue(current_scene as TitleScreen)
		_check(battle != null and battle.call("combat_state") == state, "일시정지 메뉴의 타이틀로 뒤 이어하면 같은 자리")


## 이어한 전투를 이겨 보상 확인·정비 화면에서 끄고 다시 켜면 그 화면 단계, 가방, 물약으로 돌아온다.
func _test_preparation_screens() -> void:
	var battle: Node2D = current_scene.get_node("Battle") as Node2D
	var loot: CombatLoot = battle.get("loot")
	var party: Array[CombatUnit] = battle.get("party")
	var actions: CombatActions = battle.get("actions")
	loot.bag.append_array([_item("weapon", {"attack_bonus": 1, "damage_bonus": 2}), _item("potion", {})])
	party[0].potion_left = 2
	for unit: CombatUnit in actions.units:
		if not unit.is_ally:
			actions.incapacitate(unit)
	actions.changed.emit()
	await process_frame
	var hud: CombatTurnHud = battle.get_node("UI/TurnHud") as CombatTurnHud
	hud.restart_button.pressed.emit()
	await process_frame
	var preparation: CombatPreparation = battle.get("preparation")
	_check(preparation.visible and GameSave.read().sections.get("preparation") == {"maintaining": false},
		"보상 확인 화면을 저장")
	var state: Dictionary = battle.call("combat_state")
	var rewards: Array[Dictionary] = preparation.rewards.duplicate(true)
	battle = await _continue(await _open_title())
	preparation = battle.get("preparation")
	loot = battle.get("loot")
	_check(preparation.visible and not preparation.maintaining and preparation.rewards == rewards
		and battle.call("combat_state") == state and loot.bag.size() == 2
		and (battle.get("party") as Array)[0].potion_left == 2, "보상 확인 화면에서 같은 가방·물약·보상으로 이어함")
	preparation.continue_button.pressed.emit()
	await process_frame
	_check(preparation.maintaining and GameSave.read().sections.get("preparation") == {"maintaining": true},
		"정비 화면을 저장")
	state = battle.call("combat_state")
	battle = await _continue(await _open_title())
	preparation = battle.get("preparation")
	_check(preparation.visible and preparation.maintaining and battle.call("combat_state") == state,
		"정비 화면에서 이어함")


## 저장이 있으면 새 게임은 그 저장의 막·스테이지를 보이는 덮어쓰기 확인을 거친다. 확인하면 처음 상태로 시작한다.
func _test_overwrite() -> void:
	var save: Dictionary = GameSave.read()
	GameSave.write(3, 2, save.sections)
	var bytes: PackedByteArray = FileAccess.get_file_as_bytes(GameSave.path)
	var title: TitleScreen = await _open_title()
	await _tap(_action("ui_accept"))
	var dialog: ConfirmationDialog = title.overwrite
	_check(dialog.visible and "3막 2스테이지 진행 중" in dialog.dialog_text and dialog.get_cancel_button().has_focus()
		and dialog.ok_button_text == "새 게임", "덮어쓰기 확인에 저장 내용, 기본 선택은 취소: %s" % dialog.dialog_text)
	await _check_dialog_layout(dialog)
	await _tap(_key(KEY_ESCAPE))
	_check(not dialog.visible and current_scene == title and title.new_game_button.has_focus()
		and FileAccess.get_file_as_bytes(GameSave.path) == bytes, "Esc로 취소하면 저장을 그대로 두고 타이틀에 남음")
	await _tap(_action("ui_accept"))
	dialog.get_cancel_button().pressed.emit()
	await process_frame
	_check(not dialog.visible and current_scene == title and FileAccess.get_file_as_bytes(GameSave.path) == bytes,
		"취소 버튼도 저장을 그대로 둠")
	await _tap(_action("ui_accept"))
	dialog.get_ok_button().pressed.emit()
	_check(not GameSave.has_save(), "확인하면 저장을 지움")
	var battle: Node2D = await _new_battle()
	await process_frame
	var party: Array[CombatUnit] = battle.get("party")
	_check((battle.get("loot") as CombatLoot).bag.is_empty() and (battle.get("progress") as CombatActProgress).stage_index == 0
		and party.all(func(unit: CombatUnit) -> bool:
			return unit.potion_left == 0 and unit.weapon.is_empty() and unit.armor.is_empty()),
		"새 게임은 1-1, 빈 가방, 물약 0개, 장비 없음")
	save = GameSave.read()
	_check(save.get("act") == 1 and save.get("stage") == 1 and save.sections.combat.bag.is_empty()
		and not save.sections.has("preparation"), "새 게임의 시작 상태로 저장")


## 읽을 수 없는 저장은 없는 것처럼 이어하기를 숨기고 이유를 보인다. 새 게임은 그래도 덮어쓰기를 묻는다.
func _test_unreadable() -> void:
	var title: TitleScreen
	for version: int in [1, GameSave.FORMAT_VERSION + 1]:
		var data: PackedByteArray = "BGLS".to_ascii_buffer()
		data.resize(GameSave.HEADER_SIZE)
		data.encode_u32(4, version)
		data.append_array(var_to_bytes({"act": 1, "stage": 1, "sections": {}}))
		GameSave.write_atomic(GameSave.path, data)
		title = await _open_title()
		_check(not title.continue_button.visible and title.notice.visible and title.notice.text == UNREADABLE,
			"형식 버전 %d의 저장: 이어하기 대신 안내" % version)
		_check(not GameSave.autosave and FileAccess.get_file_as_bytes(GameSave.path) == data,
			"형식 버전 %d의 저장은 안내 뒤에도 그대로 보존" % version)
		title.new_game_button.pressed.emit()
		_check(title.overwrite.visible and "저장을 읽을 수 없음" in title.overwrite.dialog_text,
			"읽을 수 없는 형식 버전 %d도 덮어쓰기를 물음" % version)
		title.overwrite.get_cancel_button().pressed.emit()
		_check(FileAccess.get_file_as_bytes(GameSave.path) == data, "새 게임 취소 뒤 형식 버전 %d도 보존" % version)
	await _check_menu_layout(title)
	# 머리는 맞지만 전투 칸이 맞지 않는 저장은 이어하기를 누른 순간 거르고 타이틀에 남는다.
	GameSave.write(2, 1, {"combat": {"stage": 99}})
	var bytes: PackedByteArray = FileAccess.get_file_as_bytes(GameSave.path)
	title = await _open_title()
	_check(title.continue_button.visible, "머리를 읽을 수 있으면 이어하기를 보임")
	title.continue_button.grab_focus()
	await _tap(_action("ui_accept"))
	await process_frame
	_check(current_scene == title and not title.continue_button.visible and title.notice.visible
		and title.new_game_button.has_focus() and root.find_child("Battle", true, false) == null,
		"맞지 않는 저장은 전투를 열지 않고 안내")
	_check(not GameSave.autosave and FileAccess.get_file_as_bytes(GameSave.path) == bytes, "맞지 않는 저장을 덮지 않음")


## 3-3 정비를 마쳐 졸업 화면이 뜨는 순간 저장을 지운다. 졸업 화면의 버튼은 `타이틀로` 하나다.
func _test_graduation() -> void:
	var title: TitleScreen = await _open_title()
	title.start_new_game()
	var battle: Node2D = await _new_battle()
	battle.set_process(false)
	var progress: CombatActProgress = battle.get("progress")
	progress.stage_index = 8
	battle.call("_start_stage", false)
	var actions: CombatActions = battle.get("actions")
	for unit: CombatUnit in actions.units:
		if not unit.is_ally:
			actions.incapacitate(unit)
	actions.changed.emit()
	var hud: CombatTurnHud = battle.get_node("UI/TurnHud") as CombatTurnHud
	hud.restart_button.pressed.emit()
	battle.call("_process", 0.0)
	var preparation: CombatPreparation = battle.get("preparation")
	_check(GameSave.read().get("act") == 3 and GameSave.read().get("stage") == 3
		and GameSave.read().sections.has("preparation"), "3-3 보상 화면까지 저장")
	preparation.continue_button.pressed.emit()
	preparation.continue_button.pressed.emit()
	if preparation.discard_dialog.visible:
		preparation.discard_dialog.confirmed.emit()
	_check(progress.graduated and hud.result_label.text == "3막 졸업" and not GameSave.has_save()
		and not FileAccess.file_exists(GameSave.path + ".tmp"), "졸업 화면이 뜨는 순간 저장을 지움")
	var buttons: Array = hud.get_node("Result").find_children("*", "Button", true, false).filter(
		func(button: Button) -> bool: return button.is_visible_in_tree()).map(
		func(button: Button) -> String: return button.text)
	_check(buttons == ["타이틀로"] and hud.restart_button.has_focus(), "졸업 화면의 버튼은 타이틀로 하나: %s" % [buttons])
	battle.set_process(true)
	await process_frame
	await process_frame
	_check(not GameSave.has_save(), "졸업 뒤 다시 저장하지 않음")
	await _tap(_action("pause"))
	_check(not (battle.get("pause_menu") as PauseMenu).visible and not paused, "졸업 화면에서는 일시정지 메뉴를 열지 않음")
	for size: Vector2i in WINDOWS + EXTRA_WINDOWS:
		root.size = size
		await process_frame
		await process_frame
		var screen: Rect2 = Rect2(Vector2.ZERO, hud.get_viewport_rect().size)
		_check(screen.encloses((hud.get_node("Result/Panel") as Control).get_global_rect()),
			"%s: 졸업 화면이 화면 안" % size)
	root.size = WINDOWS[0]
	await process_frame
	await _tap(_action("ui_accept"))
	await process_frame
	_check(current_scene is TitleScreen and not (current_scene as TitleScreen).continue_button.visible
		and not (current_scene as TitleScreen).notice.visible, "타이틀로 가면 이어할 저장이 없음")


## 게임을 다시 켠 것처럼 지금 장면을 닫고 타이틀을 새로 연다.
func _open_title() -> TitleScreen:
	if current_scene != null:
		current_scene.queue_free()
		await process_frame
	GameSave.autosave = false
	var title: TitleScreen = (load("res://scenes/main.tscn") as PackedScene).instantiate() as TitleScreen
	root.add_child(title)
	current_scene = title
	await process_frame
	return title


## 새 게임이 바꾼 장면이 첫 프레임을 돌기 전에 입력 fixture의 아군 둘 순서만 고정한다.
func _new_battle() -> Node2D:
	await process_frame
	var battle: Node2D = current_scene.get_node("Battle") as Node2D
	_check(not battle.get("_enemy_turn_running"), "새 게임 장면의 첫 프레임 전")
	var turns: CombatTurns = battle.get("turns")
	ScriptedDice.arrange_turns(turns, battle.get("units"), battle.get("party"))
	return battle


## 타이틀의 이어하기를 누른다. 장면은 바로 바뀐다.
func _continue(title: TitleScreen) -> Node2D:
	title.continue_button.pressed.emit()
	_check(current_scene != title and current_scene.has_node("Battle"), "이어하기는 게임 장면으로 바꿈")
	return current_scene.get_node_or_null("Battle") as Node2D


## 적에게 다가가는 이동 하나. 실제 연출을 기다리고 저장할 프레임을 지난다.
func _approach(battle: Node2D, actor: CombatUnit) -> bool:
	var actions: CombatActions = battle.get("actions")
	var cell: Vector2i = CombatEnemyAi.new().approach_cell(actor, actions)
	if cell == actor.cell or not actions.can_move(actor, cell) or not await actions.move_to(actor, cell):
		return false
	await _settle()
	return actions.pending_reactor == null


func _item(kind: String, stats: Dictionary) -> Dictionary:
	var items: Array = CombatLoot.new().data["items"]
	var item: Dictionary = items[items.find_custom(func(entry: Dictionary) -> bool: return entry.kind == kind)]
	item = item.duplicate(true)
	item["stats"] = stats
	return item


## ADR 0002의 여섯 창에서 덮어쓰기 확인 창이 화면 안에 들어가고 글이 잘리지 않는다.
func _check_dialog_layout(dialog: ConfirmationDialog) -> void:
	for size: Vector2i in WINDOWS + EXTRA_WINDOWS:
		root.size = size
		await process_frame
		dialog.popup_centered(Vector2i(360, 110))
		await process_frame
		var screen: Rect2 = Rect2(Vector2.ZERO, dialog.get_parent().get_viewport().get_visible_rect().size)
		_check(screen.encloses(Rect2(dialog.position, dialog.size)) and dialog.get_label().get_line_count() <= 3,
			"%s: 확인 창이 화면 안: %s / %s" % [size, Rect2(dialog.position, dialog.size), screen])
	root.size = WINDOWS[0]
	await process_frame
	dialog.get_cancel_button().grab_focus()


## ADR 0002의 여섯 창에서 안내를 포함한 타이틀 메뉴가 논리 화면 안에 겹치지 않고 들어간다.
func _check_menu_layout(title: TitleScreen) -> void:
	for size: Vector2i in WINDOWS + EXTRA_WINDOWS:
		root.size = size
		await process_frame
		await process_frame
		var screen: Rect2 = Rect2(Vector2.ZERO, title.get_viewport_rect().size)
		_check(screen.size == LOGICAL.get(size, screen.size), "%s: 논리 화면 %s" % [size, screen.size])
		var areas: Array = title.menu.get_children().filter(func(node: Control) -> bool: return node.visible)
		for index: int in range(areas.size()):
			var rect: Rect2 = (areas[index] as Control).get_global_rect()
			_check(screen.encloses(rect), "%s: 화면 안: %s" % [size, areas[index].name])
			for other: Control in areas.slice(index + 1):
				_check(not rect.intersects(other.get_global_rect()),
					"%s: 겹치지 않음: %s, %s" % [size, areas[index].name, other.name])
	root.size = WINDOWS[0]
	await process_frame
	await process_frame


## 기다리기 시작한 프레임은 전투의 _process 전에 깨어나므로 저장할 프레임을 하나 더 지난다.
func _settle() -> void:
	await process_frame
	await process_frame


func _key(keycode: Key) -> InputEventKey:
	var event: InputEventKey = InputEventKey.new()
	event.keycode = keycode
	return event


func _action(action: String) -> InputEventAction:
	var event: InputEventAction = InputEventAction.new()
	event.action = action
	return event


## 누름과 뗌을 한 프레임씩 보낸다.
func _tap(event: InputEvent) -> void:
	event.set("pressed", true)
	Input.parse_input_event(event)
	await process_frame
	event.set("pressed", false)
	Input.parse_input_event(event)
	await process_frame


func _finish() -> void:
	print("Continue: %d checks, %d failures;" % [checks, failures])
	GameSave.autosave = false
	if current_scene:
		current_scene.queue_free()
	await process_frame
	GameSave.delete()
	for file: String in [GameSettings.path, GameSettings.path + ".tmp"]:
		DirAccess.remove_absolute(file)
	DirAccess.remove_absolute(directory)
	quit(0 if failures == 0 else 1)
