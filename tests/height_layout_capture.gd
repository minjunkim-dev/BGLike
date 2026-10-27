extends SceneTree
## #364 비교 시안: 같은 카메라·해상도·유닛 조건에서 정본과 후보 높이를 원본 Viewport로 저장한다.
## 인자: --capture-dir=DIR --case=<stage_index>:<res path>:<label>:<x>,<y>
const ScriptedDice = preload("res://tests/scripted_dice.gd")
func _initialize() -> void:
	_run.call_deferred()
func _run() -> void:
	var output: String
	var cases: Array[String] = []
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--capture-dir="):
			output = arg.trim_prefix("--capture-dir=")
		if arg.begins_with("--case="):
			cases.append(arg.trim_prefix("--case="))
	DirAccess.make_dir_recursive_absolute(output)
	GameSave.autosave = false
	GameSave.path = output.path_join("unused-save.bin")
	GameSettings.path = output.path_join("unused-settings.cfg")
	var game: Node = load("res://scenes/game.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	var battle: Node = game.get_node("Battle")
	battle.set_process(false)
	for spec: String in cases:
		var parts: PackedStringArray = spec.split(":")
		var index: int = int(parts[0])
		(battle.get("stages") as Array)[index] = load("res://" + parts[1]) as CombatStage
		(battle.get("progress") as CombatActProgress).stage_index = index
		battle.call("_start_stage", true)
		battle.call("start_battle")
		var units: Array[CombatUnit] = battle.get("units")
		var party: Array[CombatUnit] = battle.get("party")
		ScriptedDice.arrange_turns(battle.get("turns"), units, party)
		battle.call("_update_turn_ui")
		for frame: int in range(8):
			await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(output.path_join(parts[2] + "-start.png"))
		var xy: PackedStringArray = parts[3].split(",")
		party[0].cell = Vector2i(int(xy[0]), int(xy[1]))
		party[0].position = (battle.get("map") as CombatMap).map_to_surface(party[0].cell)
		battle.call("_update_turn_ui")
		for frame: int in range(8):
			await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(output.path_join(parts[2] + "-moved.png"))
		print("[CAPTURE] ", parts[2], " occluded=", party[0].is_occluded)
	quit()
