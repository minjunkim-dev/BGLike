extends SceneTree
## #621 반복 검수. 14×14 1-1의 처음 화면과 호버 설명 두 장을 원본 Viewport로 저장하고,
## 전투 화면 배치 명세(#555)의 수치를 논리 px로 잰다. 아군 차례만 통제하고 카메라는 처음 화면 그대로 둔다.
## 스크립트 입력이라 OS 입력 경로는 거치지 않는다. 창 크기를 바꾸지 않는다.
const ScriptedDice = preload("res://tests/scripted_dice.gd")
const STAGE_INDEX: int = 0
const MAP_SIZE: Vector2i = Vector2i(14, 14)
var output: String
var preflight: bool
var checks: int = 0
var failures: int = 0
var game: Node
var battle: Node
var hud: CombatTurnHud
var measured: Dictionary = {}

func _initialize() -> void:
	_run.call_deferred()

func ck(ok: bool, message: String) -> bool:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)
	return ok

func _run() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--capture-dir="):
			output = arg.trim_prefix("--capture-dir=")
	preflight = "--fixture-precheck" in OS.get_cmdline_user_args()
	assert(not output.is_empty())
	DirAccess.make_dir_recursive_absolute(output)
	GameSave.autosave = false
	GameSave.path = output.path_join("unused-save.bin")
	GameSettings.path = output.path_join("unused-settings.cfg")
	game = load("res://scenes/game.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	battle = game.get_node("Battle")
	battle.set_process(false)
	(battle.get("progress") as CombatActProgress).stage_index = STAGE_INDEX
	battle.call("_start_stage", true)
	battle.call("start_battle")
	hud = battle.get_node("UI/TurnHud") as CombatTurnHud
	var units: Array[CombatUnit] = battle.get("units")
	var party: Array[CombatUnit] = battle.get("party")
	var actions: CombatActions = battle.get("actions")
	var map: CombatMap = battle.get("map")
	var turns: CombatTurns = battle.get("turns")
	ScriptedDice.arrange_turns(turns, units, party)
	battle.call("_update_turn_ui")
	await _settle()
	var portraits: Dictionary = hud.get("_portraits")
	var buttons: Dictionary = hud.get("_actions")
	var visible_buttons: Array[Button] = []
	for action: String in CombatActionRules.NAMES:
		var button: Button = buttons[action] as Button
		if button.is_visible_in_tree():
			visible_buttons.append(button)
	if ck(actions.grid.map_size == MAP_SIZE, "1-1은 14×14 맵: %s" % actions.grid.map_size) \
		and ck(turns.current_unit == party[0] and party[0].is_ally, "아군 차례로 고정") \
		and ck(portraits.size() == units.size() and portraits.size() >= 3, "초상 수 확인: %d" % portraits.size()) \
		and ck(visible_buttons.size() >= 3, "보이는 스킬 버튼 수 확인: %d" % visible_buttons.size()):
		await _measure(map, party[0], portraits, visible_buttons)
	var file: FileAccess = FileAccess.open(output.path_join("measurements.json"), FileAccess.WRITE)
	measured["checks"] = checks
	measured["failures"] = failures
	file.store_string(JSON.stringify(measured, "\t"))
	file.close()
	if preflight:
		print("[LAYOUT_PREFLIGHT_PASS]" if failures == 0 else "[LAYOUT_PREFLIGHT_FAIL] %d failures;" % failures)
	else:
		print("[LAYOUT_QA_DONE] %d checks, %d failures;" % [checks, failures])
	game.queue_free()
	await process_frame
	quit(0 if failures == 0 else 1)

func _settle() -> void:
	for frame: int in range(3):
		await process_frame

func _rect(control: Control) -> Dictionary:
	var rect: Rect2 = control.get_global_rect()
	return {"x": rect.position.x, "y": rect.position.y, "w": rect.size.x, "h": rect.size.y,
		"right": rect.end.x, "bottom": rect.end.y}

func _measure(map: CombatMap, actor: CombatUnit, portraits: Dictionary, skill_buttons: Array[Button]) -> void:
	var screen: Vector2 = hud.get_global_rect().size
	var focus: Vector2 = screen / 2.0 - Vector2(0, 20)
	var center: Rect2 = Rect2(focus - Vector2(64, 32), Vector2(128, 64))
	var to_screen: Transform2D = map.get_global_transform_with_canvas()
	var hud_rects: Dictionary = {
		"order_scroll": hud.get_node("OrderScroll"), "order_divider": hud.get_node("OrderDivider"),
		"round": hud.round_label, "progress": hud.progress_label,
		"unit_details": hud.get_node("UnitDetails"), "attack_preview": hud.preview_label,
		"combat_log": hud.get_node("CombatLog"), "skills": hud.get_node("Skills"),
		"end_turn": hud.end_button, "stand": hud.stand_button}
	var rects: Dictionary = {}
	for key: String in hud_rects:
		rects[key] = _rect(hud_rects[key] as Control)
	var corners: Dictionary = {}
	var last: Vector2i = MAP_SIZE - Vector2i.ONE
	var named: Dictionary = {"north_0_0": Vector2i(0, 0), "east_13_0": Vector2i(last.x, 0),
		"west_0_13": Vector2i(0, last.y), "south_13_13": last,
		"center_7_7": Vector2i(7, 7)}
	var xs: Array[float] = []
	var ys: Array[float] = []
	for key: String in named:
		var point: Vector2 = to_screen * map.map_to_surface(named[key] as Vector2i)
		var under: Array[String] = []
		for name: String in hud_rects:
			if (hud_rects[name] as Control).get_global_rect().has_point(point):
				under.append(name)
		corners[key] = {"x": point.x, "y": point.y, "under_hud": under}
		xs.append(point.x)
		ys.append(point.y)
	var overlaps: Array[String] = []
	for key: String in hud_rects:
		if (hud_rects[key] as Control).get_global_rect().intersects(center):
			overlaps.append(key)
	var window: Vector2i = DisplayServer.window_get_size()
	measured["window"] = {"x": window.x, "y": window.y}
	measured["visible_rect"] = {"w": screen.x, "h": screen.y}
	measured["content_scale_factor"] = root.content_scale_factor
	measured["F"] = {"x": focus.x, "y": focus.y}
	measured["C"] = {"x": center.position.x, "y": center.position.y, "w": center.size.x, "h": center.size.y}
	measured["hud"] = rects
	measured["hud_overlapping_C"] = overlaps
	measured["map_cells"] = corners
	measured["floor_extent"] = {"min_x": xs.min(), "max_x": xs.max(), "min_y": ys.min(), "max_y": ys.max()}
	ck(true, "측정 기록")
	await _capture("initial")
	# 가장 긴 설명의 스킬 버튼과 첫 아군 초상. 마우스를 움직이고 0.5초 지연을 기다린다.
	var longest: Button = skill_buttons[0]
	for button: Button in skill_buttons:
		if button.tooltip_text.length() > longest.tooltip_text.length():
			longest = button
	measured["tooltips"] = {}
	await _hover_capture("skill-hover", "skill", longest, center)
	await _hover_capture("portrait-hover", "portrait", portraits[actor] as Button, center)

func _hover_capture(label: String, key: String, control: Control, center: Rect2) -> void:
	var tooltip: PanelContainer = hud.get("_tooltip") as PanelContainer
	await _settle()
	var motion: InputEventMouseMotion = InputEventMouseMotion.new()
	motion.position = root.get_final_transform() * control.get_global_rect().get_center()
	motion.global_position = motion.position
	Input.parse_input_event(motion)
	await create_timer(0.8).timeout
	if not ck(tooltip.visible, label + ": 호버 설명이 뜸"):
		return
	var rect: Rect2 = tooltip.get_global_rect()
	var info: Dictionary = _rect(tooltip)
	info["intersects_C"] = rect.intersects(center)
	info["skills_top"] = (hud.get_node("Skills") as Control).get_global_rect().position.y
	info["order_scroll_bottom"] = (hud.get_node("OrderScroll") as Control).get_global_rect().end.y
	(measured["tooltips"] as Dictionary)[key] = info
	await _capture(label)

func _capture(label: String) -> void:
	if preflight:
		return
	await RenderingServer.frame_post_draw
	ck(root.get_texture().get_image().save_png(output.path_join(label + ".png")) == OK, "원본 PNG 저장: " + label)
