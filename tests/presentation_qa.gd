extends SceneTree
## #349 실제 Mac 입력용 통제 fixture. 입력을 대신 실행하지 않고 상태·원본 화면을 관찰한다.
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
	assert(not directory.is_empty() and kind in ["prep", "crate", "rock"])
	DirAccess.make_dir_recursive_absolute(directory)
	GameSave.autosave = false
	GameSave.path = directory.path_join("qa-only-save.bin")
	GameSettings.path = directory.path_join("qa-only-settings.cfg")
	game = load("res://scenes/game.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	battle = game.get_node("Battle")
	battle.set_process(false)
	if kind == "rock":
		(battle.get("progress") as CombatActProgress).stage_index = 3
		battle.call("_start_stage", true)
	var units: Array[CombatUnit] = battle.get("units")
	var party: Array[CombatUnit] = battle.get("party")
	var actions: CombatActions = battle.get("actions")
	ScriptedDice.arrange_turns(battle.get("turns"), units, party)
	battle.call("_update_turn_ui")
	assert(units.size() >= 3 and party.size() == 2 and battle.get("waiting_for_start"))
	assert(actions.grid.props.size() == 2 and party[0].cell == Vector2i(1, 4))
	assert(party[0].movement_left == 6 and party[0].action_left == 1)
	if kind == "prep":
		var loot: CombatLoot = battle.get("loot")
		for item_kind: String in ["weapon", "armor", "potion"]:
			var item: Dictionary = loot.data.items.filter(func(i: Dictionary) -> bool: return i.kind == item_kind)[0].duplicate(true)
			for stat: String in item.stats: item.stats[stat] = int(item.stats[stat][0][0])
			loot.bag.append(item)
		assert(loot.bag.size() == 3 and party[0].weapon.is_empty() and party[0].armor.is_empty())
		loot.bag.append(loot.bag[0].duplicate(true))
	elif kind == "crate":
		assert(not actions.grid.path_to(party[0], Vector2i(2, 4)).is_empty())
		var sides: int = party[0].get_damage_sides()
		assert(sides + party[0].get_damage_bonus() >= actions.grid.props[0].hit_points)
		# 상자 공격은 명중 굴림 없이 현재 피해 주사위 한 번만 소비한다.
		actions.dice = ScriptedDice.new([sides], [sides]) if not preflight else CombatDice.new()
		print("[FIXTURE] crate current damage d%d +%d; native attack uses legal maximum roll" % [sides, party[0].get_damage_bonus()])
	else:
		assert(not actions.grid.path_to(party[0], Vector2i(5, 4)).is_empty())
		assert(actions.grid.props[1].cell == Vector2i(6, 4))
		actions.dice = ScriptedDice.new([])
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
		await create_timer(0.08).timeout
		if (battle.get("actions") as CombatActions).busy:
			await capture("animation")
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
		"preparation": preparation.visible, "hint": preparation.hint_label.text, "busy": actions.busy, "controls": [], "waiting": battle.get("waiting_for_start"), "dragging": root.gui_is_dragging(),
		"bag": (battle.get("loot") as CombatLoot).bag, "party": [], "props": [], "units": [], "selected_action": selection.selected_action,
		"preview_path": str(selection.preview_path), "preview_prop": selection.preview_prop.kind if selection.preview_prop != null else "", "log": hud.message_label.text,
		"actor": actor.get_display_name(), "actor_cell": str(actor.cell), "action": actor.action_left, "movement": actor.movement_left}
	for control: Node in preparation.find_children("*", "Control", true, false) + (battle.get("staging") as Control).find_children("*", "Control", true, false):
		if control is Button and control.is_visible_in_tree():
			var rect: Rect2 = control.get_global_rect()
			row.controls.append({"name": str(control.name), "text": control.text, "rect": [rect.position.x, rect.position.y, rect.size.x, rect.size.y]})
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
