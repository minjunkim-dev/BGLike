extends SceneTree
const ScriptedDice = preload("res://tests/scripted_dice.gd")
var directory: String
var kind: String = "prep"
var game: Node
var battle: Node
var shots: int = 0
var preflight: bool
class Inputs extends Node:
	var tree: SceneTree
	var dragging: bool = false
	func _process(_delta: float) -> void:
		if dragging != get_viewport().gui_is_dragging():
			dragging = get_viewport().gui_is_dragging()
			print("[GUI_DRAG] ", dragging)
	func _input(event: InputEvent) -> void:
		if event is InputEventMouseButton:
			print("[RAW_BUTTON] msec=%s pressed=%s button=%s pos=%s" % [Time.get_ticks_msec(), event.pressed, event.button_index, event.position])
		if event is InputEventMouseMotion and event.button_mask != 0:
			print("[RAW_DRAG_MOTION] msec=%s mask=%s pos=%s relative=%s" % [Time.get_ticks_msec(), event.button_mask, event.position, event.relative])
		if (event is InputEventKey and not event.echo) or event is InputEventMouseButton:
			tree.record(event.as_text())
func _initialize() -> void:
	_run.call_deferred()
func _run() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--capture-dir="): directory = arg.trim_prefix("--capture-dir=")
		if arg.begins_with("--case="): kind = arg.trim_prefix("--case=")
	preflight = "--fixture-precheck" in OS.get_cmdline_user_args()
	assert(not directory.is_empty() and kind in ["limits", "resume"])
	DirAccess.make_dir_recursive_absolute(directory)
	GameSave.autosave = false
	GameSave.path = "/Users/swifty/.codex/visualizations/2026/10/25/bglike-native-edges-7d533b6/shared-save.bin"
	GameSettings.path = "/Users/swifty/.codex/visualizations/2026/10/25/bglike-native-edges-7d533b6/shared-settings.cfg"
	if kind == "resume" and not preflight:
		assert(GameSave.has_save())
		game = load("res://scenes/title.tscn").instantiate()
		root.add_child(game)
		current_scene = game
		print("[NATIVE_READY] resume title")
		while current_scene == game:
			await process_frame
		game = current_scene
		battle = game.get_node("Battle")
		assert(battle.get("waiting_for_start") and (battle.get("preparation") as Control).visible)
	else:
		game = load("res://scenes/game.tscn").instantiate()
		root.add_child(game)
		current_scene = game
		battle = game.get_node("Battle")
		var party: Array[CombatUnit] = battle.get("party")
		var loot: CombatLoot = battle.get("loot")
		ScriptedDice.arrange_turns(battle.get("turns"), battle.get("units"), party)
		battle.call("_update_turn_ui")
		var weapon: Dictionary = item(loot, "weapon")
		assert(loot.receive(party[0], weapon))
		assert(loot.receive(party[0], item(loot, "armor")))
		party[0].potion_left = 1
		party[1].potion_left = int(loot.data.potion_limit)
		var better: Dictionary = item(loot, "weapon")
		for stat: String in better.stats:
			better.stats[stat] = int(loot.data.items.filter(func(i: Dictionary) -> bool: return i.kind == "weapon")[0].stats[stat][0][1])
		loot.bag.assign([item(loot, "potion"), better])
		while loot.bag.size() < int(loot.data.bag_limit): loot.bag.append(weapon.duplicate(true))
		assert(loot.bag.size() == 12 and party[1].potion_left == 3)
		assert(battle.get("waiting_for_start"))
		if not preflight: GameSave.autosave = true
	await process_frame
	await process_frame
	if preflight:
		assert(ScriptedDice.finish().is_empty())
		print("[NATIVE_FIXTURE_READY] ", kind)
		game.queue_free()
		await process_frame
		quit()
		return
	var listener: Inputs = Inputs.new()
	listener.tree = self
	root.add_child(listener)
	print("[NATIVE_READY] %s display=%s window=%s" % [kind, DisplayServer.get_name(), DisplayServer.window_get_size()])
	await capture("initial")
	while not FileAccess.file_exists(directory.path_join("finish")):
		await create_timer(0.2).timeout
		if FileAccess.file_exists(directory.path_join("capture")):
			DirAccess.remove_absolute(directory.path_join("capture"))
			await capture("checkpoint")
	await capture("final")
	assert(ScriptedDice.finish().is_empty())
	print("[NATIVE_CASE_DONE] ", kind)
	game.queue_free()
	await create_timer(0.3).timeout
	quit()
func record(event: String) -> void:
	print("[NATIVE_INPUT] msec=%d %s" % [Time.get_ticks_msec(), event])
	capture.call_deferred(event)
func capture(label: String) -> void:
	await RenderingServer.frame_post_draw
	shots += 1
	var path: String = directory.path_join("%04d.png" % shots)
	assert(root.get_texture().get_image().save_png(path) == OK)
	var preparation: CombatPreparation = battle.get("preparation")
	var selection: CombatSelection = battle.get("selection")
	var actions: CombatActions = battle.get("actions")
	var actor: CombatUnit = (battle.get("turns") as CombatTurns).current_unit
	var hud: CombatTurnHud = battle.get("hud")
	var row: Dictionary = {"image": path, "label": label, "msec": Time.get_ticks_msec(), "window": str(DisplayServer.window_get_size()), "viewport": str(root.get_visible_rect()), "case": kind,
		"pause": (battle.get("pause_menu") as Control).visible, "dialog": preparation.discard_dialog.visible, "save_exists": GameSave.has_save(), "preparation": preparation.visible, "waiting": battle.get("waiting_for_start"), "dragging": root.gui_is_dragging(),
		"bag": (battle.get("loot") as CombatLoot).bag, "party": [], "props": [], "units": [], "selected_action": selection.selected_action,
		"preview_path": str(selection.preview_path), "preview_prop": selection.preview_prop.kind if selection.preview_prop != null else "", "log": hud.message_label.text,
		"actor": actor.get_display_name(), "actor_cell": str(actor.cell), "action": actor.action_left, "movement": actor.movement_left}
	for unit: CombatUnit in battle.get("party"):
		row.party.append({"name": unit.get_display_name(), "weapon": unit.weapon, "armor": unit.armor, "potions": unit.potion_left, "hp": unit.hit_points})
	for unit: CombatUnit in battle.get("units"):
		row.units.append({"name": unit.get_display_name(), "cell": str(unit.cell), "hp": unit.hit_points})
	for prop: CombatGrid.Prop in actions.grid.props:
		row.props.append({"kind": prop.kind, "cell": str(prop.cell), "hp": prop.hit_points})
	var file: FileAccess = FileAccess.open(directory.path_join("frames.jsonl"), FileAccess.READ_WRITE if FileAccess.file_exists(directory.path_join("frames.jsonl")) else FileAccess.WRITE)
	file.seek_end()
	file.store_line(JSON.stringify(row))
	print("[NATIVE_FRAME] %s %s action=%s move=%s" % [shots, label, actor.action_left, actor.movement_left])

func item(loot: CombatLoot, item_kind: String) -> Dictionary:
	var value: Dictionary = loot.data.items.filter(func(i: Dictionary) -> bool: return i.kind == item_kind)[0].duplicate(true)
	for stat: String in value.stats: value.stats[stat] = int(value.stats[stat][0][0])
	return value
