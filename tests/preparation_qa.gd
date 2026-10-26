extends SceneTree
## #366: 실제 아이템의 보상·정비·가방 부족 화면. 스크립트 입력이며 OS 입력 검증은 아니다.
var output: String
var preflight: bool = "--fixture-precheck" in OS.get_cmdline_user_args()
var records: Array[Dictionary] = []

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	create_timer(25).timeout.connect(func() -> void: push_error("preparation QA watchdog"); quit(1))
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--capture-dir="):
			output = arg.trim_prefix("--capture-dir=")
	assert(preflight or not output.is_empty())
	if not preflight:
		assert(DirAccess.make_dir_recursive_absolute(output) == OK)
	GameSave.autosave = false
	var directory: String = "user://tests/preparation-qa/%d" % OS.get_process_id()
	GameSave.path = directory.path_join("unused-save.bin")
	GameSettings.path = directory.path_join("unused-settings.cfg")
	var game: Node = load("res://scenes/game.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	var battle: Node = game.get_node("Battle")
	battle.set_process(false)
	var prep: CombatPreparation = battle.get("preparation")
	var loot: CombatLoot = battle.get("loot")
	var party: Array[CombatUnit] = battle.get("party")
	assert(party.size() == 2 and not prep.visible and battle.get("waiting_for_start"))
	loot.bag.clear()
	var weapon: Dictionary = loot.data.items.filter(func(item: Dictionary) -> bool: return item.kind == "weapon")[0].duplicate(true)
	weapon.stats = {"attack_bonus": 1, "damage_bonus": 1}
	var potion: Dictionary = loot.data.items.filter(func(item: Dictionary) -> bool: return item.kind == "potion")[0].duplicate(true)
	assert(loot.is_valid_item(weapon) and loot.is_valid_item(potion))
	var rewards: Array[Dictionary] = [weapon, potion]
	prep.open_rewards(loot, party, rewards, false, false)
	assert(prep.visible and not prep.maintaining and prep.rewards.size() == 2)
	await _capture("reward-overview")
	await _button(prep.continue_button)
	assert(prep.maintaining)
	await _button(prep.find_child("Item0", true, false) as Button)
	await _capture("maintenance-selected")
	prep.hide()
	var bag_limit: int = int(loot.data["bag_limit"])
	assert(bag_limit > 0)
	for index: int in range(bag_limit):
		loot.bag.append(potion.duplicate(true))
	prep.open_rewards(loot, party, rewards, false, false, true)
	await _button(prep.continue_button)
	assert(prep.discard_dialog.visible and prep.discard_dialog.get_cancel_button().has_focus())
	await _capture("finish-confirmation")
	prep.discard_dialog.confirmed.emit()
	await _settle()
	assert(prep.bag_notice.visible and prep.visible and not prep.discard_dialog.visible
		and loot.bag.size() == bag_limit and rewards.size() == 2)
	await _capture("bag-full-notice")
	await _button(prep.find_child("BagItem0", true, false) as Button)
	await _capture("bag-discard-button")
	await _button(prep.find_child("DiscardItem", true, false) as Button)
	assert(prep.discard_dialog.visible and prep.discard_dialog.get_cancel_button().has_focus())
	await _capture("discard-confirmation")
	prep.discard_dialog.canceled.emit()
	await _settle()
	assert(not prep.discard_dialog.visible and loot.bag.size() == bag_limit and rewards.size() == 2)
	assert(not FileAccess.file_exists(GameSave.path) and not FileAccess.file_exists(GameSettings.path))
	if not preflight:
		var file: FileAccess = FileAccess.open(output.path_join("frames.json"), FileAccess.WRITE)
		assert(file != null)
		file.store_string(JSON.stringify(records, "\t"))
	print("[PREPARATION_PREFLIGHT_PASS]" if preflight else "[PREPARATION_QA_PASS]")
	quit()

func _settle() -> void:
	for frame: int in range(4):
		await process_frame

func _button(button: Button) -> void:
	assert(button != null and button.is_visible_in_tree() and not button.disabled)
	await _settle()
	var event: InputEventMouseButton = InputEventMouseButton.new()
	event.position = root.get_final_transform() * button.get_global_rect().get_center()
	event.global_position = event.position
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	Input.parse_input_event(event)
	await _settle()
	event.pressed = false
	Input.parse_input_event(event)
	await _settle()

func _capture(label: String) -> void:
	await _settle()
	var labels: Array[Dictionary] = []
	for node: Node in root.find_children("*", "Label", true, false):
		if (node as Label).is_visible_in_tree():
			labels.append({"path": str(node.get_path()), "text": node.text,
				"rect": str(node.get_global_rect()), "lines": node.get_line_count()})
	records.append({"id": label, "window": str(root.size), "viewport": str(root.get_visible_rect()), "labels": labels})
	if preflight:
		return
	await RenderingServer.frame_post_draw
	assert(root.get_texture().get_image().save_png(output.path_join(label + ".png")) == OK)
