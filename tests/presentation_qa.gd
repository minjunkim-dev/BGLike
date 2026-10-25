extends SceneTree
## #349 실제 Mac 입력용 통제 fixture. 입력을 대신 실행하지 않고 상태·원본 화면을 관찰한다.
const ScriptedDice = preload("res://tests/scripted_dice.gd")
var directory: String
var kind: String = "prep"
var game: Node
var battle: Node
var shots: int = 0
var preflight: bool
var transitions: bool = "--transitions" in OS.get_cmdline_user_args()
class Inputs extends Node:
	var tree: SceneTree
	var dragging: bool = false
	func _process(_delta: float) -> void:
		if tree.has_method("sample"):
			tree.sample(_delta)
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
	assert(not directory.is_empty() and kind in ["prep", "crate", "rock", "resume"])
	DirAccess.make_dir_recursive_absolute(directory)
	GameSave.autosave = false
	GameSave.path = directory.path_join("qa-only-save.bin")
	GameSettings.path = directory.path_join("qa-only-settings.cfg")
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--save-path="): GameSave.path = arg.trim_prefix("--save-path=")
	if kind == "resume" and not preflight:
		assert(GameSave.has_save())
		game = load("res://scenes/main.tscn").instantiate()
		root.add_child(game)
		current_scene = game
	else:
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
			actions.dice = ScriptedDice.new([sides], [sides]) if not preflight and not transitions else CombatDice.new()
			print("[FIXTURE] crate current damage d%d +%d; transitions=%s" % [sides, party[0].get_damage_bonus(), transitions])
		elif kind == "rock":
			assert(not actions.grid.path_to(party[0], Vector2i(5, 4)).is_empty())
			assert(actions.grid.props[1].cell == Vector2i(6, 4))
			actions.dice = ScriptedDice.new([])
		if transitions:
			actions.dice = CombatDice.new()
			actions.dice.seed = 351
			battle.set_process(true)
			GameSave.autosave = not preflight
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
	listener.process_mode = Node.PROCESS_MODE_ALWAYS
	root.add_child(listener)
	print("[NATIVE_READY] %s display=%s window=%s" % [kind, DisplayServer.get_name(), DisplayServer.window_get_size()])
	await capture("initial")
	while not FileAccess.file_exists(directory.path_join("finish")):
		await create_timer(0.08).timeout
		battle = current_scene.get_node_or_null("Battle")
		if battle != null and (battle.get("actions") as CombatActions).busy:
			await capture("animation")
		if FileAccess.file_exists(directory.path_join("capture")):
			DirAccess.remove_absolute(directory.path_join("capture"))
			await capture("checkpoint")
	await capture("final")
	assert(ScriptedDice.finish().is_empty())
	print("[NATIVE_CASE_DONE] ", kind)
	current_scene.queue_free()
	await create_timer(0.3).timeout
	quit()
func record(event: String) -> void:
	print("[NATIVE_INPUT] msec=%d %s" % [Time.get_ticks_msec(), event])
	capture.call_deferred(event)
func capture(label: String) -> void:
	await RenderingServer.frame_post_draw
	if current_scene == null: return
	battle = current_scene.get_node_or_null("Battle")
	shots += 1
	var path: String = directory.path_join("%04d.png" % shots)
	assert(root.get_texture().get_image().save_png(path) == OK)
	var row: Dictionary = {"image": path, "label": label, "msec": Time.get_ticks_msec(), "window": str(DisplayServer.window_get_size()), "viewport": str(root.get_visible_rect()), "case": kind,
		"scene": current_scene.scene_file_path, "paused": paused, "dragging": root.gui_is_dragging(), "controls": [], "save_exists": GameSave.has_save()}
	for control: Node in current_scene.find_children("*", "Control", true, false):
		if control is Button and control.is_visible_in_tree():
			var rect: Rect2 = control.get_global_rect()
			if control.get_window() != root: rect.position += Vector2(control.get_window().position)
			row.controls.append({"name": str(control.name), "text": control.text, "rect": [rect.position.x, rect.position.y, rect.size.x, rect.size.y]})
	if battle != null:
		var preparation: CombatPreparation = battle.get("preparation")
		var selection: CombatSelection = battle.get("selection")
		var actions: CombatActions = battle.get("actions")
		var actor: CombatUnit = (battle.get("turns") as CombatTurns).current_unit
		var map: CombatMap = battle.get("map")
		row.merge({"preparation": preparation.visible, "hint": preparation.hint_label.text, "busy": actions.busy, "waiting": battle.get("waiting_for_start"),
			"bag": (battle.get("loot") as CombatLoot).bag, "party": [], "props": [], "units": [], "cells": {}, "selected_action": selection.selected_action,
			"preview_path": str(selection.preview_path), "preview_prop": selection.preview_prop.kind if selection.preview_prop != null else "", "log": (battle.get("hud") as CombatTurnHud).message_label.text,
			"actor": actor.get_display_name() if actor != null else "", "actor_cell": str(actor.cell) if actor != null else "", "action": actor.action_left if actor != null else -1,
			"movement": actor.movement_left if actor != null else -1, "state": battle.call("combat_state"), "animations": map.find_children("PropAnimation", "Node2D", false, false).size(), "effects": (map.get("_prop_effects") as Array).size()})
		row["saved_matches"] = row.state == GameSave.read().get("sections", {}).get("combat", {}) if GameSave.has_save() else false
		for unit: CombatUnit in battle.get("party"):
			row.party.append({"name": unit.get_display_name(), "weapon": unit.weapon, "armor": unit.armor, "potions": unit.potion_left, "hp": unit.hit_points})
		for unit: CombatUnit in battle.get("units"):
			row.units.append({"name": unit.get_display_name(), "cell": str(unit.cell), "hp": unit.hit_points})
		for prop: CombatGrid.Prop in actions.grid.props:
			row.props.append({"kind": prop.kind, "cell": str(prop.cell), "hp": prop.hit_points})
		for cell: Vector2i in [Vector2i(2, 4), Vector2i(5, 4)]:
			var point: Vector2 = map.get_global_transform_with_canvas() * map.map_to_surface(cell)
			row.cells[str(cell)] = [point.x, point.y]
		# 물체 몸통은 주변 유닛 픽셀에 가리지 않은 점만 입력 후보로 제공한다.
		for prop: CombatGrid.Prop in actions.grid.props:
			for y: int in range(-24, 1):
				var found: bool = false
				for x: int in range(-12, 13):
					var local: Vector2 = map.map_to_surface(prop.cell) + Vector2(x, y)
					if map.prop_at_point(local) == prop and not actions.units.any(func(unit: CombatUnit) -> bool:
						return unit.hit_points > 0 and unit.contains_body_point(unit.to_local(map.to_global(local)))):
						var point: Vector2 = map.get_global_transform_with_canvas() * local
						row.cells[prop.kind] = [point.x, point.y]
						found = true
						break
				if found: break
	var file: FileAccess = FileAccess.open(directory.path_join("frames.jsonl"), FileAccess.READ_WRITE if FileAccess.file_exists(directory.path_join("frames.jsonl")) else FileAccess.WRITE)
	file.seek_end()
	file.store_line(JSON.stringify(row))
	print("[NATIVE_FRAME] %s %s" % [shots, label])
