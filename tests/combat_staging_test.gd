extends SceneTree
## #345: 전투 전 정비·저장과 실제 GUI 드래그 입력. 수치·회복·용량은 기존 CombatLoot 규칙을 쓴다.
const ScriptedDice = preload("res://tests/scripted_dice.gd")
var checks: int = 0
var failures: int = 0
var directory: String = "user://tests/staging/%d" % OS.get_process_id()
var capture_dir: String = ""
var fixture_precheck: bool = "--fixture-precheck" in OS.get_cmdline_user_args()
var battle: Node2D
var preparation: CombatPreparation
var loot: CombatLoot
var party: Array[CombatUnit]

func _initialize() -> void:
	_run.call_deferred()

func ck(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)

func _run() -> void:
	create_timer(35).timeout.connect(func() -> void: push_error("staging watchdog"); quit(1))
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--capture-dir="):
			capture_dir = arg.trim_prefix("--capture-dir=")
	if not capture_dir.is_empty():
		DirAccess.make_dir_recursive_absolute(capture_dir)
	GameSave.autosave = false
	DirAccess.make_dir_recursive_absolute(directory)
	GameSave.path = directory + "/save.bin"
	if capture_dir.is_empty():
		root.size = Vector2i(1280, 720)
	var main: Node = load("res://scenes/game.tscn").instantiate()
	root.add_child(main)
	current_scene = main
	battle = main.get_node("Battle")
	battle.set_process(false)
	preparation = battle.get("preparation")
	loot = battle.get("loot")
	party = battle.get("party")
	await process_frame
	ck(battle.get("waiting_for_start") and not preparation.visible, "정비를 강제로 열지 않고 지도에서 준비")
	await _capture("01-staging")
	var turns: CombatTurns = battle.get("turns")
	var units: Array[CombatUnit] = battle.get("units")
	ScriptedDice.arrange_turns(turns, units, [units[2], party[0], party[1], units[3], units[4], units[5]])
	var before: Dictionary = battle.call("combat_state")
	battle.call("_process", 0.0)
	await process_frame
	ck(not battle.get("_enemy_turn_running") and battle.call("combat_state") == before, "적 선공도 전투 시작 전에는 대기")
	battle.call("_end_turn")
	battle.call("_on_action_selected", "attack")
	ck(battle.call("combat_state") == before, "준비 중 행동·턴 종료 차단")
	var bar: Control = battle.get("staging")
	ck(bar.visible and not battle.get_node("UI/TurnHud/Skills").visible, "지도에 정비·전투 시작 버튼")
	(bar.get_child(1) as Button).grab_focus()
	await _key(KEY_TAB)
	ck((bar.get_child(2) as Button).has_focus(), "Tab으로 정비에서 전투 시작으로 이동")
	await _key(KEY_TAB, true)
	ck((bar.get_child(1) as Button).has_focus(), "Shift+Tab으로 정비로 돌아옴")
	GameSave.autosave = true
	battle.call("_autosave", before)
	await _restore_check(before, false)
	(bar.get_child(1) as Button).pressed.emit()
	await process_frame
	ck(preparation.visible and preparation.maintaining and preparation.before_battle, "전투 전 정비 열기")
	battle.call("_process", 0.0)
	await _restore_check(battle.call("combat_state"), true)
	preparation._continue()
	ck(not preparation.visible and battle.get("waiting_for_start") and (battle.get("progress") as CombatActProgress).stage_index == 0,
		"정비 종료는 같은 지도 준비 단계로 돌아옴")
	(bar.get_child(2) as Button).pressed.emit()
	ck(not battle.get("waiting_for_start") and not bar.visible and turns.current_unit == units[2], "전투 시작 뒤 원래 적 선공 순서 유지")
	GameSave.autosave = false
	# 아군 시작 위치와 자원을 그대로 두고 정비 UI의 입력을 검사한다.
	battle.call("_start_stage", true)
	battle.call("_open_staging_preparation")
	loot.bag.assign([_item("weapon"), _item("armor"), _item("potion")])
	preparation._render()
	await _settle()
	await _capture("02-preparation")
	var bag_before: Array[Dictionary] = loot.bag.duplicate(true)
	await _drag("BagItem0", "Armor0")
	ck(loot.bag == bag_before and party[0].weapon.is_empty(), "잘못된 장비 칸은 아이템 보존")
	await _drag("BagItem0", "Weapon0")
	ck(not party[0].weapon.is_empty() and loot.bag.size() == 2, "가방 무기를 드래그해 장착")
	GameSave.autosave = true
	battle.call("_process", 0.0)
	await _restore_check(battle.call("combat_state"), true)
	GameSave.autosave = false
	await _drag("BagItem0", "Armor0")
	ck(not party[0].armor.is_empty() and loot.bag.size() == 1, "가방 방어구 장착")
	var hp: int = party[0].hit_points
	await _drag("Armor0", "EmptyBag1")
	ck(party[0].armor.is_empty() and loot.bag.size() == 2 and party[0].hit_points <= hp, "방어구를 가방으로 해제하며 무료 회복 없음")
	await _drag("BagItem0", "Potions0")
	ck(party[0].potion_left == 1 and loot.bag.size() == 1, "가방 물약을 캐릭터 물약 칸에 분배")
	await _drag("Potions0", "Potions1")
	ck(party[0].potion_left == 0 and party[1].potion_left == 1, "캐릭터 물약을 다른 캐릭터에게 한 개 양도")
	bag_before = loot.bag.duplicate(true)
	await _begin_drag("BagItem0")
	var cancel: InputEventKey = InputEventKey.new()
	cancel.keycode = KEY_ESCAPE
	cancel.pressed = true
	Input.parse_input_event(cancel)
	await _settle()
	cancel.pressed = false
	Input.parse_input_event(cancel)
	ck(not root.gui_is_dragging() and not (battle.get("pause_menu") as Control).visible, "Esc는 드래그만 취소")
	await _mouse(Vector2(1200, 400), false)
	ck(loot.bag == bag_before and party[0].armor.is_empty(), "드래그 취소는 아이템 보존")
	party[1].potion_left = int(loot.data["potion_limit"])
	loot.bag.append(_item("potion"))
	preparation._render()
	await _settle()
	bag_before = loot.bag.duplicate(true)
	await _drag("BagItem1", "Potions1")
	ck(loot.bag == bag_before and party[1].potion_left == int(loot.data["potion_limit"]), "물약 한도면 드롭 거부")
	# 보상 직접 수령과 꽉 찬 가방의 장착/교환 경계.
	preparation.rewards.assign([_item("weapon")])
	preparation._render()
	await _settle()
	await _drag("Item0", "EmptyBag2")
	ck(preparation.rewards.is_empty() and loot.bag.size() == 3, "보상을 빈 가방에 직접 수령")
	var weapon: Dictionary = _item("weapon")
	while loot.bag.size() < int(loot.data["bag_limit"]):
		loot.bag.append(weapon.duplicate(true))
	preparation.rewards.assign([weapon.duplicate(true)])
	preparation._render()
	await _settle()
	bag_before = loot.bag.duplicate(true)
	var equipped: Dictionary = party[0].weapon.duplicate(true)
	await _drag("Item0", "Weapon0")
	ck(loot.bag == bag_before and preparation.rewards.size() == 1 and party[0].weapon == equipped,
		"가방이 가득 차면 보상 장비 교체 거부·원본 보존")
	await _drag("BagItem2", "Weapon0")
	ck(loot.bag.size() == int(loot.data["bag_limit"]) and loot.bag[2] == equipped,
		"가방이 가득 차도 가방 장비는 이전 장비와 같은 칸 교환")
	preparation._discard(0)
	var source: Control = preparation.find_child("Item0", true, false)
	ck(preparation._drag_item(source, "reward", 0) == null, "확인 창에서 드래그 시작 차단")
	ck(not preparation._can_drop_item({"owner": preparation.get_instance_id(), "kind": "reward", "index": 0,
		"item": weapon}, "weapon", 1), "확인 창 중에는 드롭도 거부")
	preparation.discard_dialog.canceled.emit()
	preparation.rewards.clear()
	preparation._continue()
	# 준비 flag와 승리 기록이 모순이면 복원 전에 거부한다.
	before = battle.call("combat_state")
	var invalid: Dictionary = before.duplicate(true)
	invalid.rewarded = true
	ck(not battle.call("restore_save", {"combat": invalid, "preparation": {"maintaining": true}})
		and battle.call("combat_state") == before, "모순된 준비·승리 저장 거부·현재 상태 보존")
	# 옛 전투 저장은 준비 상태 필드가 없어도 이미 진행 중인 전투로 복원한다.
	before = battle.call("combat_state")
	before.erase("waiting_for_start")
	ck(battle.call("restore_combat", before) and not battle.get("waiting_for_start"), "기존 전투 저장 호환")
	await _transitions()
	ck(ScriptedDice.finish().is_empty(), "이니셔티브 fixture 소비 일치")
	main.queue_free()
	await process_frame
	GameSave.delete()
	print("Combat staging: %d checks, %d failures" % [checks, failures])
	print("[STAGING_FIXTURE_READY]" if fixture_precheck else "[STAGING_DONE]")
	quit(0 if failures == 0 else 1)

func _restore_check(state: Dictionary, screen: bool) -> void:
	var game: Node = load("res://scenes/game.tscn").instantiate()
	root.add_child(game)
	var copy: Node2D = game.get_node("Battle")
	copy.set_process(false)
	ck(copy.call("restore_save", GameSave.read().sections), "준비/정비 저장 복원")
	ck(copy.call("combat_state") == state and (copy.get("preparation") as CombatPreparation).visible == screen,
		"준비 상태와 정비 화면을 같은 단계로 복원")
	game.queue_free()
	await process_frame

func _item(kind: String) -> Dictionary:
	var item: Dictionary = loot.data.items.filter(func(value: Dictionary) -> bool: return value.kind == kind)[0].duplicate(true)
	for stat: String in item.stats:
		item.stats[stat] = int(item.stats[stat][0][0])
	return item

func _settle() -> void:
	for step: int in range(3):
		await process_frame

func _point(node_name: String) -> Vector2:
	var control: Control = preparation.find_child(node_name, true, false)
	var point: Vector2 = control.get_global_rect().get_center()
	if node_name.begins_with("Potions"):
		point = control.global_position + Vector2(8, 8)
	return root.get_final_transform() * point

func _mouse(point: Vector2, pressed: bool) -> void:
	var event: InputEventMouseButton = InputEventMouseButton.new()
	event.position = point
	event.global_position = point
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = pressed
	Input.parse_input_event(event)
	await _settle()

func _motion(point: Vector2, relative: Vector2) -> void:
	var event: InputEventMouseMotion = InputEventMouseMotion.new()
	event.position = point
	event.global_position = point
	event.relative = relative
	event.button_mask = MOUSE_BUTTON_MASK_LEFT
	Input.parse_input_event(event)
	await _settle()

func _begin_drag(source: String) -> void:
	var point: Vector2 = _point(source)
	await _motion(point, Vector2.ZERO)
	await _mouse(point, true)
	await _motion(point + Vector2(24, 0), Vector2(24, 0))
	ck(root.gui_is_dragging(), "실제 GUI 드래그 시작: " + source)
	if source == "BagItem0" and party[0].weapon.is_empty():
		await _capture("03-drag-valid-targets-" + str(checks))

func _drag(source: String, target: String) -> void:
	await _begin_drag(source)
	var point: Vector2 = _point(target)
	await _motion(point, Vector2(30, 30))
	await _mouse(point, false)

func _key(code: Key, shift: bool = false) -> void:
	var event: InputEventKey = InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.shift_pressed = shift
	event.pressed = true
	Input.parse_input_event(event)
	await _settle()
	event.pressed = false
	Input.parse_input_event(event)
	await _settle()

func _capture(label: String) -> void:
	if capture_dir.is_empty() or fixture_precheck:
		return
	await RenderingServer.frame_post_draw
	ck(root.get_texture().get_image().save_png(capture_dir.path_join(label + ".png")) == OK, "원본 PNG 저장")

func _transitions() -> void:
	loot.bag.clear()
	var actions: CombatActions = battle.get("actions")
	for unit: CombatUnit in battle.get("units"):
		if not unit.is_ally:
			actions.incapacitate(unit)
	actions.changed.emit()
	battle.call("_restart")
	preparation._continue()
	preparation._continue()
	preparation.discard_dialog.confirmed.emit()
	ck((battle.get("progress") as CombatActProgress).stage_index == 1 and battle.get("waiting_for_start")
		and not preparation.visible, "승리 후 다음 스테이지도 지도 준비에서 대기")
	battle.call("start_battle")
	for unit: CombatUnit in party:
		actions.incapacitate(unit)
	actions.changed.emit()
	battle.call("_restart")
	ck((battle.get("progress") as CombatActProgress).stage_index == 0 and battle.get("waiting_for_start")
		and party.all(func(unit: CombatUnit) -> bool: return unit.hit_points > 0), "전멸 후 막 재시작도 부활한 지도 준비")
