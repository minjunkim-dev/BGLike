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
	_test_skill_icons()
	_test_cost_marks()
	var scene: PackedScene = load("res://scenes/game.tscn") as PackedScene
	var main: Node = scene.instantiate()
	# 전사·궁수 UI 회귀는 기존 풋내기 배치를 fixture로 유지한다.
	(main.get_node("Battle") as Node2D).stages[0] = load("res://scenes/combat/stage.tres") as CombatStage
	# 화면 fixture는 턴을 직접 고정한다. 자동 실행은 AI 장면 검사에서 확인한다.
	root.add_child(main)
	main.get_node("Battle").set_process(false)
	main.get_node("Battle").call("start_battle")
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
	ScriptedDice.arrange_turns(turns, units, units)
	units[2].cell = Vector2i(4, 8)
	units[3].cell = Vector2i(7, 9)
	battle.call("_update_turn_ui")
	await process_frame
	await process_frame
	_check("이니셔티브" not in hud.message_label.text, "전투 시작 로그에 이니셔티브 계산식 없음")
	_test_square_map()
	_test_movement_overlay()
	await _test_turn_tile_map()
	_test_threat_overlay()
	await _test_floor_loot_ui()
	_test_height_edges()
	_test_unit_art()
	_test_warrior()
	await _test_cost_slot_and_face()
	_test_passive_slot_and_number_colors()
	await _test_resources()
	_test_archer_and_enemy()
	_test_reflex_dialog()
	await _test_archer_moving_shot_input()
	await _test_log_and_status()
	await _test_hit_sound_mix()
	await _test_layout()
	await _test_guidance()
	_test_high_ground_guidance()
	_test_water_guidance()
	await _test_mouse_controls_and_inspection()
	await _test_threat_range_input()
	await _test_group_keyboard()
	await _test_skill_bar_keys()
	await _test_joined_group_hud()
	await _test_incapacitated_portrait_join()
	await _test_portrait_stage_reset()
	await _test_portrait_join_interrupted_by_order_change(true)
	await _test_portrait_join_interrupted_by_order_change(false)
	await _test_portrait_join_interrupted_by_order_change(false, true)
	await _test_boundary_incapacitated_portrait_join()
	await _test_order_bar_input()
	await _test_transparent_order_input()
	await _test_camera()
	await _test_zoomed_occlusion()
	await _test_camera_during_enemy_turn()
	await _test_camera_follow_turn()
	await _test_camera_follow_switch()
	await _test_camera_follow_hand()
	await _test_camera_follow_walk()
	await _test_camera_follow_takeover()
	await _test_camera_follow_zoomed()
	await _test_camera_follow_idle()
	await _test_camera_follow_enemy_turn(false)
	await _test_camera_follow_enemy_turn(true)
	await _test_reaction_flow()
	await _test_reaction_focus()
	_test_presentation_speed()
	await _test_presentation_move_time()
	await _test_turn_tile_battle()
	await _test_turn_tile_steps()
	await _test_action_animations()
	var previous_fps: int = Engine.max_fps
	var previous_scale: float = Engine.time_scale
	# 긴 프레임에서는 짧은 Tween이 프레임 관찰 사이에 끝날 수 있다.
	Engine.max_fps = 5
	Engine.time_scale = 3.0
	await _test_action_animations()
	Engine.max_fps = previous_fps
	Engine.time_scale = previous_scale
	await _test_rock_preview_guidance()
	await _test_sweep_input()
	await _test_whistle_input()
	await _test_rock_presentation()
	await _test_results_and_restart()
	await _test_tree_burn_ui()
	await _test_camera_follow_restore()
	(battle.get("sounds") as CombatSounds).stop_all()
	await create_timer(0.08).timeout
	current_scene.queue_free()
	await process_frame
	await _test_spawned_portrait_input()
	await _test_overload_and_water_guidance()
	var dice_problems: Array[String] = ScriptedDice.finish()
	_check(dice_problems.is_empty(), "준비한 주사위 값을 요청대로 모두 굴림 " + str(dice_problems))
	print("Combat HUD: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)


## 보이는 버튼이 차지하는 줄 수. 넘쳐 접힌 줄은 2 이상이다(#500 2안).
func _button_lines(panel: Control) -> int:
	var ys: Array[float] = []
	for button: Control in panel.get_child(0).get_child(1).get_children():
		if button.visible and button.global_position.y not in ys:
			ys.append(button.global_position.y)
	return ys.size()


## 떨어진 아이템의 칸 아이콘, 마우스 오버 수치, 이동·점프 미리보기의 줍기 표시(#529).
func _test_floor_loot_ui() -> void:
	var map: CombatMap = battle.get_node("Map") as CombatMap
	var selection: CombatSelection = battle.get("selection") as CombatSelection
	var weapon: Dictionary = {"name": "무기", "kind": "weapon", "icon": "sword", "stats": {"attack_bonus": 2, "damage_bonus": 3}}
	var armor: Dictionary = {"name": "방어구", "kind": "armor", "icon": "armor", "stats": {"defense_bonus": 1, "max_hit_points": 2}}
	var potion: Dictionary = {"name": "회복 물약", "kind": "potion", "icon": "potion", "stats": {}}
	actions.floor_loot.drop(Vector2i(2, 9), weapon)
	actions.floor_loot.drop(Vector2i(3, 9), armor)
	actions.floor_loot.drop(Vector2i(2, 8), potion)
	selection.clear_preview()
	battle.call("_update_turn_ui")
	var markers: Array[Node] = _floor_loot_markers(map)
	var icons: Array[String] = []
	for marker: Node in markers:
		icons.append((marker.get_node("Icon") as Sprite2D).texture.resource_path.get_file())
	icons.sort()
	_check(icons == ["armor.png", "potion.png", "sword.png"], "떨어진 아이템 칸마다 종류별 아이콘 하나: " + str(icons))
	# 마우스 오버는 종류와 수치를 안내한다.
	var point: Vector2 = map.get_global_transform_with_canvas() * map.map_to_surface(Vector2i(2, 9))
	battle.call("_hover_floor_loot", point)
	_check("바닥 아이템 · 무기 · 공격 가산+2 · 피해+3" in hud.preview_label.text, "아이템 칸 오버 수치: " + hud.preview_label.text)
	battle.call("_hover_floor_loot", map.get_global_transform_with_canvas() * map.map_to_surface(Vector2i(0, 9)))
	_check("바닥 아이템" not in hud.preview_label.text, "아이템이 없는 칸으로 옮기면 안내를 거둔다")
	# 걷기 경로가 아이템 칸을 지나면 줍는다는 표시를 한다. 도착 칸이 아니어도 표시한다.
	selection.selected_action = "move"
	selection.select_move(Vector2i(2, 9), [Vector2i(3, 9), Vector2i(2, 9)])
	battle.call("_update_turn_ui")
	_check("줍기: 방어구, 무기" in hud.preview_label.text, "이동 미리보기의 줍기 표시: " + hud.preview_label.text)
	# 점프는 착지 칸만 본다.
	selection.selected_action = "jump"
	selection.clear_preview()
	selection.select_move(Vector2i(2, 9), [Vector2i(3, 9), Vector2i(2, 9)])
	battle.call("_update_turn_ui")
	_check("줍기: 무기" in hud.preview_label.text and "방어구" not in hud.preview_label.text,
		"점프 미리보기는 착지 칸의 줍기만 표시: " + hud.preview_label.text)
	# 아이템이 없는 칸의 경로에는 표시하지 않는다.
	selection.selected_action = "move"
	selection.clear_preview()
	selection.select_move(Vector2i(0, 9), [Vector2i(0, 9)])
	battle.call("_update_turn_ui")
	_check("줍기" not in hud.preview_label.text, "아이템이 없는 경로는 줍기 표시가 없다")
	# 적이 고르는 경로와 밀려난 적은 줍지 않으므로 표시하지 않는다.
	_check(actions.pickup_note(units[2], [Vector2i(2, 9)]).is_empty() and actions.shove_landing(units[2], Vector2i(2, 9)).is_empty(),
		"적에게는 줍기 안내가 없다")
	_check("줍기: 무기" in actions.shove_landing(units[0], Vector2i(2, 9)), "밀려날 아군의 도착 칸에 줍기 안내")
	selection.clear_preview()
	selection.selected_action = "attack"
	actions.floor_loot.clear()
	battle.call("_hover_floor_loot", Vector2(-9999, -9999))
	battle.call("_update_turn_ui")
	_check(_floor_loot_markers(map).is_empty(), "아이템을 줍거나 잃으면 아이콘도 사라진다")


func _floor_loot_markers(map: CombatMap) -> Array[Node]:
	return map.get_children().filter(func(node: Node) -> bool: return node.has_meta("item"))


func _test_movement_overlay() -> void:
	var grid: CombatGrid = CombatGrid.new()
	grid.map_size = Vector2i(3, 2)
	grid.heights[Vector2i(1, 0)] = 1
	var map: CombatMap = CombatMap.new()
	root.add_child(map)
	map.build_grid(grid, load("res://scenes/combat/floor_tiles.tres") as TileSet)
	map.show_movement([Vector2i.ZERO, Vector2i(1, 0)], [Vector2i(1, 0)], [Vector2i(1, 0)], Vector2i.ZERO)
	_check(map._overlays.size() == 4, "이동 면2개·미리보기 선·도착점을 유지")
	for index: int in range(2):
		var overlay: Polygon2D = map._overlays[index] as Polygon2D
		_check(overlay.color.a > 0.0 and overlay.color.a <= 0.16, "이동 면 채움이 바닥 재질을 가리지 않음")
		_check(overlay.color.b > overlay.color.g if index == 0 else overlay.color.g > overlay.color.b,
			"기존 파랑 이동·초록 이동 후 공격의 의미 유지")
		_check(overlay.get_child_count() == 5 and overlay.get_children().all(func(node: Node) -> bool: return node is Line2D),
			"약한 면에 칸 윤곽과 네 꼭짓점 표시를 함께 표시")
		if overlay.get_child_count() == 5:
			var edge: Line2D = overlay.get_child(0) as Line2D
			_check(edge.closed and edge.points == overlay.polygon and is_equal_approx(edge.width, 1.5),
				"윤곽은 기존 바닥 마름모를 닫고 이전보다 1px 굵음(0.5→1.5)")
			var corners: Dictionary[Vector2, bool] = {}
			var inside: bool = true
			var middle: Vector2 = (overlay.polygon[0] + overlay.polygon[2]) / 2.0
			var half: Vector2 = Vector2(absf(overlay.polygon[1].x - overlay.polygon[3].x), absf(overlay.polygon[2].y - overlay.polygon[0].y)) / 2.0
			for corner_index: int in range(1, 5):
				var mark: Line2D = overlay.get_child(corner_index) as Line2D
				corners[mark.points[1]] = true
				inside = inside and mark.points.size() == 3 and not mark.closed and mark.width >= 1.0
				for point: Vector2 in mark.points:
					var offset: Vector2 = (point - middle).abs()
					inside = inside and offset.x / half.x + offset.y / half.y <= 1.0001
			var at_vertices: bool = true
			for vertex: Vector2 in overlay.polygon:
				at_vertices = at_vertices and corners.has(vertex)
			_check(inside and corners.size() == 4 and at_vertices,
				"꼭짓점 표시 4개는 마름모 네 꼭짓점에서 시작하고 바닥 안쪽에만 그려 측면을 칠하지 않음")
			_check(edge.default_color.a > 0.0 and (overlay.get_child(1) as Line2D).default_color.a >= edge.default_color.a,
				"꼭짓점 표시는 윤곽보다 옅지 않음")
		var center: Vector2 = Vector2.ZERO
		for point: Vector2 in overlay.polygon:
			center += point / overlay.polygon.size()
		_check((overlay.position + center).is_equal_approx(map.map_to_surface(Vector2i(index, 0))),
			"높이 있는 바닥 위에도 같은 좌표로 표시")
	map.show_movement([], [], [], Vector2i.ZERO)
	_check(map._overlays.is_empty(), "이동 표시를 닫으면 면·윤곽·경로를 함께 제거")
	map.free()


## #623: 행동 유닛 발밑 칸 표시(#516 1절). 맵 함수 단독 검사.
func _test_turn_tile_map() -> void:
	var grid: CombatGrid = CombatGrid.new()
	grid.map_size = Vector2i(3, 2)
	grid.heights[Vector2i(1, 0)] = 1
	var map: CombatMap = CombatMap.new()
	root.add_child(map)
	map.build_grid(grid, load("res://scenes/combat/floor_tiles.tres") as TileSet)
	_check(is_equal_approx(CombatMap.TURN_TILE_FADE_TIME, 0.2), "발밑 칸 나타남의 기본 시간은 0.2초")
	map.show_movement([Vector2i(1, 0)], [], [], Vector2i.ZERO)
	map.show_turn_tile(Vector2i(1, 0), true)
	var tile: Polygon2D = map._turn_tile
	_check(tile != null and tile.visible, "발밑 칸 표시가 그려짐")
	if tile == null:
		map.free()
		return
	var center: Vector2 = Vector2.ZERO
	for point: Vector2 in tile.polygon:
		center += point / tile.polygon.size()
	_check(tile.polygon.size() == 4 and (tile.position + center).is_equal_approx(map.map_to_surface(Vector2i(1, 0))),
		"높이 있는 바닥에서도 칸 윗면 가운데에 마름모를 그림")
	_check(tile.color.is_equal_approx(Color(Color("f4cf69"), 0.25)), "채움은 금색 #f4cf69 알파 0.25")
	var border: Line2D = tile.get_child(0) as Line2D
	_check(tile.get_child_count() == 1 and border != null and border.closed and border.points == tile.polygon
		and is_equal_approx(border.width, 1.0) and border.default_color.is_equal_approx(Color("f4cf69")),
		"테두리는 닫힌 금색 1px 선 하나이고 꺾쇠는 없음")
	_check(tile.z_index <= 0, "유닛 가림 마커보다 아래")
	_check(tile.get_index() == map.get_child_count() - 1, "같은 칸의 이동 범위 면보다 위(맵 자식의 맨 뒤)")
	_check(is_zero_approx(tile.modulate.a), "나타남은 알파 0에서 시작")
	var tween: Tween = map._turn_tile_tween
	_check(tween != null and tween.is_valid(), "나타남은 Tween으로 진행")
	if tween != null:
		tween.pause()
		var expected: float = CombatPresentation.duration(CombatMap.TURN_TILE_FADE_TIME)
		tween.custom_step(expected - 0.002)
		_check(tile.modulate.a > 0.0 and tile.modulate.a < 1.0, "나타남이 끝나기 직전에는 알파가 1 미만")
		tween.custom_step(0.004)
		_check(is_equal_approx(tile.modulate.a, 1.0), "계수 적용 시간 %s초 뒤 알파 1" % expected)
		# 위치만 옮기는 갱신은 나타남을 다시 돌리지 않는다.
		map.show_turn_tile(Vector2i(2, 1), false)
		_check(is_equal_approx(tile.modulate.a, 1.0), "위치만 옮기면 알파를 건드리지 않음")
	var moved: Vector2 = Vector2.ZERO
	for point: Vector2 in tile.polygon:
		moved += point / tile.polygon.size()
	_check((tile.position + moved).is_equal_approx(map.map_to_surface(Vector2i(2, 1))), "칸을 옮기면 새 칸 윗면으로 이동")
	# 나타남 도중의 위치 갱신은 진행 중인 알파를 그대로 둔다.
	map.show_turn_tile(Vector2i(0, 0), true)
	var running: Tween = map._turn_tile_tween
	running.pause()
	running.custom_step(0.05)
	var halfway: float = tile.modulate.a
	map.show_turn_tile(Vector2i(1, 1), false)
	_check(is_equal_approx(tile.modulate.a, halfway) and map._turn_tile_tween == running and running.is_valid(),
		"나타남 도중에 위치만 옮겨도 알파와 Tween을 건드리지 않음")
	map.show_turn_tile(Vector2i(-1, -1), false)
	_check(not tile.visible, "(-1, -1)이면 숨김")
	map.show_turn_tile(Vector2i(0, 0), false)
	_check(tile.visible, "다시 부르면 보임")
	map.show_movement([], [], [], Vector2i.ZERO)
	map.show_threat([Vector2i(0, 0)])
	_check(map._overlays.is_empty() and tile.get_index() == map.get_child_count() - 1,
		"이동 면 없이 위협 면을 그려도 발밑 칸이 맵 자식의 맨 뒤")
	map.show_threat([])
	map.build_grid(grid, load("res://scenes/combat/floor_tiles.tres") as TileSet)
	_check(not map._turn_tile.visible, "격자를 다시 만들면 숨겨짐")
	map.show_turn_tile(Vector2i(0, 1), false)
	var rebuilt: Vector2 = Vector2.ZERO
	for point: Vector2 in map._turn_tile.polygon:
		rebuilt += point / map._turn_tile.polygon.size()
	_check(map._turn_tile.visible and (map._turn_tile.position + rebuilt).is_equal_approx(map.map_to_surface(Vector2i(0, 1))),
		"격자를 다시 만든 뒤에도 새 격자에 맞게 그려짐")
	map.free()
	await process_frame


func _test_threat_overlay() -> void:
	var grid: CombatGrid = CombatGrid.new()
	grid.map_size = Vector2i(3, 2)
	var map: CombatMap = CombatMap.new()
	root.add_child(map)
	map.build_grid(grid, load("res://scenes/combat/floor_tiles.tres") as TileSet)
	map.show_threat([Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 1)])
	_check(map._threat_overlays.size() == 3, "위협 칸 수만큼 표시를 그림")
	var reddish: bool = true
	var plain: bool = true
	for overlay: Polygon2D in map._threat_overlays:
		reddish = reddish and overlay.color.r > overlay.color.b and overlay.color.r > overlay.color.g and overlay.color.a <= 0.16
		plain = plain and overlay.get_child_count() == 1 and overlay.get_child(0) is Line2D
	_check(reddish, "위협 면은 붉은 계열이고 바닥 재질을 가리지 않음")
	_check(plain, "위협 표시에는 꼭짓점 표시 없이 윤곽만 둠(이동 범위와 모양으로도 구분)")
	map.show_movement([Vector2i(0, 0)], [], [], Vector2i(2, 1))
	_check(map._threat_overlays.size() == 3 and map._overlays.size() == 1, "이동 표시를 바꿔도 위협 표시는 그대로")
	var movement_index: int = map._overlays[0].get_index()
	_check(map._threat_overlays.all(func(overlay: Node2D) -> bool: return overlay.get_index() < movement_index),
		"이동 표시가 나중에 와도 위협 표시 위에 그림")
	map.show_threat([Vector2i(1, 1)])
	_check(map._threat_overlays.size() == 1 and map._overlays.size() == 1
		and map._threat_overlays[0].get_index() < map._overlays[0].get_index(),
		"위협 표시를 다시 그려도 이동 표시 아래에 있음")
	map.show_movement([], [], [], Vector2i.ZERO)
	_check(map._threat_overlays.size() == 1, "이동 표시를 지워도 위협 표시는 그대로")
	map.show_threat([])
	_check(map._threat_overlays.is_empty(), "빈 목록으로 위협 표시를 지움")
	map.show_threat([Vector2i(0, 0)])
	map.build_grid(CombatGrid.new(), load("res://scenes/combat/floor_tiles.tres") as TileSet)
	_check(map._threat_overlays.is_empty(), "맵을 다시 만들면 위협 표시도 지움")
	map.free()


## #392: 높이가 다른 이웃 칸의 윗면 경계. 실제로 그린 두 배 밀도 텍스처의 가장자리 도트를 읽는다.
func _test_height_edges() -> void:
	var grid: CombatGrid = CombatGrid.new()
	grid.map_size = Vector2i(4, 4)
	grid.heights[Vector2i(1, 1)] = 1
	grid.heights[Vector2i(2, 2)] = 2
	grid.heights[Vector2i(3, 1)] = 1
	grid.pits.append(Vector2i(3, 0))
	var map: CombatMap = CombatMap.new()
	root.add_child(map)
	map.build_grid(grid, load("res://scenes/combat/floor_tiles.tres") as TileSet)
	var markers: Dictionary[Vector2i, Node2D] = {}
	for marker: Node2D in map._height_edges:
		markers[map.local_to_map(marker.position)] = marker
	_check(not markers.has(Vector2i(0, 3)) and not markers.has(Vector2i.ZERO),
		"같은 높이와 맵 밖 가장자리에는 경계를 더하지 않음")
	for cell: Vector2i in markers:
		var sprite: Sprite2D = markers[cell].get_node("Sprite") as Sprite2D
		_check((markers[cell].position + sprite.position).is_equal_approx(map.map_to_surface(cell))
			and sprite.texture.get_size() == Vector2(map.tile_set.tile_size * 2) and sprite.scale == Vector2.ONE * 0.5
			and sprite.material == preload("res://scenes/combat/art/pixel_art.tres"),
			"경계는 바닥 원본과 같은 두 배 밀도로 윗면에 맞춤: %s" % cell)
	var up: Vector2i = Vector2i(0, -1)
	var dark: Callable = func(color: Color) -> bool: return color.a > 0.0 and color.get_luminance() < 0.2
	var light: Callable = func(color: Color) -> bool: return color.a > 0.0 and color.get_luminance() > 0.8
	var one: Array[Color] = _edge_bands(map, markers, Vector2i(1, 1), up)
	_check(dark.call(one[0]) and light.call(one[1]) and one[2].a == 0.0,
		"뒤쪽 높이 차1은 어두운 선과 밝은 선 한 쌍")
	var two: Array[Color] = _edge_bands(map, markers, Vector2i(2, 2), up)
	_check(dark.call(two[0]) and light.call(two[1]) and dark.call(two[2]) and light.call(two[3]) and two[4].a == 0.0,
		"뒤쪽 높이 차2 이상은 두 쌍으로 차1과 구분")
	var front: Array[Color] = _edge_bands(map, markers, Vector2i(1, 1), Vector2i(1, 0))
	_check(light.call(front[0]) and front[1].a == 0.0, "앞쪽 내리막은 옆면 위에 밝은 윗면 끝선")
	var foot: Array[Color] = _edge_bands(map, markers, Vector2i(1, 2), up)
	var tall: Array[Color] = _edge_bands(map, markers, Vector2i(2, 3), up)
	_check(dark.call(foot[0]) and foot[1].a < foot[0].a and foot[2].a == 0.0 and tall[2].a > 0.0 and tall[3].a == 0.0,
		"뒤쪽 높은 이웃의 발치에 접지 그림자, 차2 이상은 더 넓음")
	_check(_edge_bands(map, markers, Vector2i(2, 1), Vector2i(0, 1))[0].a == 0.0,
		"앞쪽 높은 이웃이 덮는 가장자리는 그리지 않음")
	_check(_edge_bands(map, markers, Vector2i(3, 1), up)[0].a == 0.0
		and dark.call(_edge_bands(map, markers, Vector2i(3, 1), Vector2i(-1, 0))[0]),
		"낭떠러지 쪽은 기존 표시를 유지하고 바닥 이웃만 경계 표시")
	map.show_movement([Vector2i(1, 1)], [], [], Vector2i(1, 1))
	_check(map._overlays[0].get_index() > markers[Vector2i(1, 1)].get_index(),
		"같은 칸의 이동 범위 면·윤곽은 높이 경계 위에 그림")
	var old: Node2D = markers[Vector2i(1, 1)]
	map.build_grid(CombatGrid.new(), load("res://scenes/combat/floor_tiles.tres") as TileSet)
	_check(map._height_edges.is_empty() and not is_instance_valid(old), "맵을 다시 만들면 이전 높이 경계를 제거")
	map.free()


## cell에서 direction 이웃 쪽 윗면 가장자리의 도트를 바깥 줄부터 다섯 줄 읽는다. 마름모 가로 기울기는 2도트/줄이다.
func _edge_bands(map: CombatMap, markers: Dictionary[Vector2i, Node2D], cell: Vector2i,
		direction: Vector2i) -> Array[Color]:
	var bands: Array[Color] = []
	bands.resize(5)
	bands.fill(Color.TRANSPARENT)
	if not markers.has(cell):
		return bands
	var image: Image = (markers[cell].get_node("Sprite") as Sprite2D).texture.get_image()
	var delta: Vector2 = map.map_to_local(cell + direction) - map.map_to_local(cell)
	var half: Vector2i = image.get_size() / 2
	var row: int = half.y / 2
	var y: int = image.get_height() - 1 - row if delta.y > 0 else row
	for band: int in range(5):
		var x: int = half.x + row * 2 - band * 2 if delta.x > 0 else half.x - 1 - row * 2 + band * 2
		bands[band] = image.get_pixel(x, y)
	return bands


## 비용 기호 묶음에 든 기호 글자를 잇는다.
func _cost_text(marks: Control) -> String:
	var text: String = ""
	for mark: Node in marks.get_children():
		text += (mark as Label).text
	return text


## 비용 기호는 칸 오른쪽 아래에 기호마다 제 자원 색으로 서고, 횟수 배지와 떨어진다. 쓸 수 있는 칸과 없는 칸은 면이 다르다(#517).
func _test_cost_slot_and_face() -> void:
	var buttons: Dictionary = hud.get("_actions")
	var badges: Dictionary = hud.get("_badges")
	var costs: Dictionary = hud.get("_costs")
	await process_frame
	await process_frame
	for action: String in ["attack", "cross_slash", "battle_cry", "steel_charge", "holy_veil", "opportunity", "counter"]:
		var button: Button = buttons[action]
		var marks: Control = costs[action]
		var box: Rect2 = marks.get_global_rect()
		var slot: Rect2 = button.get_global_rect()
		_check(marks.visible and box.end.x <= slot.end.x and box.end.x >= slot.end.x - 4
			and box.end.y <= slot.end.y and box.end.y >= slot.end.y - 3,
			"비용 기호는 칸 오른쪽 아래: %s box=%s slot=%s" % [action, box, slot])
		_check(box.position.x >= slot.position.x + 4 + CombatActionRules.ICON_SIZE,
			"비용 기호는 아이콘 영역을 덮지 않음: %s box=%s slot=%s" % [action, box, slot])
		var expected: Array[int] = CombatActionRules.cost_marks(action)
		_check(marks.get_child_count() == expected.size(), "비용 기호는 자원마다 하나: " + action)
		for index: int in range(mini(marks.get_child_count(), expected.size())):
			_check((marks.get_child(index) as Label).get_theme_color("font_color") == CombatTurnHud.RESOURCE_COLORS[expected[index]],
				"비용 기호 %d는 제 자원 색: %s" % [index, action])
		var badge: Label = badges[action]
		if badge.visible:
			_check(badge.get_global_rect().end.y + 4 <= box.position.y, "횟수 배지와 비용 기호는 4 논리px 이상 떨어짐: " + action)
	var cross: Control = costs["cross_slash"]
	_check(cross.get_child_count() == 2
		and not (cross.get_child(0) as Control).get_global_rect().intersects((cross.get_child(1) as Control).get_global_rect())
		and (cross.get_child(0) as Label).get_theme_color("font_color") != (cross.get_child(1) as Label).get_theme_color("font_color"),
		"십자 베기의 ●▲는 서로 다른 색의 따로 선 기호")
	var active_face: Color = Color("365d61")
	var idle_face: Color = Color("242a30")
	_check((buttons["attack"] as Button).get_theme_stylebox("normal") is StyleBoxFlat
		and ((buttons["attack"] as Button).get_theme_stylebox("normal") as StyleBoxFlat).bg_color == active_face
		and ((buttons["potion"] as Button).get_theme_stylebox("normal") as StyleBoxFlat).bg_color == idle_face,
		"아군 턴: 쓸 수 있는 칸은 청록 면, 쓸 수 없는 칸은 어두운 면")
	# 숨은 물약 칸만 보면 보이는 비활성 칸의 면을 놓친다. 보조 행동을 다 쓴 상태로 보이는 칸을 본다.
	var bonus_left: int = units[0].bonus_action_left
	units[0].bonus_action_left = 0
	hud.refresh_actions(actions, "attack", units[0])
	var visible_disabled: int = 0
	for action: String in buttons:
		var slot_button: Button = buttons[action]
		if slot_button.visible and slot_button.disabled:
			visible_disabled += 1
			_check((slot_button.get_theme_stylebox("normal") as StyleBoxFlat).bg_color == idle_face,
				"아군 턴: 보이는 비활성 칸은 어두운 면: " + action)
	_check(visible_disabled > 0, "보조 행동을 다 쓰면 보이는 비활성 칸이 있다")
	units[0].bonus_action_left = bonus_left
	hud.refresh_actions(actions, "attack", units[0])
	for action: String in buttons:
		_check((buttons[action] as Button).get_theme_color("icon_disabled_color").a == 1.0,
			"비활성 아이콘 색은 불투명: " + action)
	var ally_turn_unit: CombatUnit = turns.current_unit
	turns.current_unit = units[2]
	hud.refresh_actions(actions, "attack", units[0])
	for action: String in buttons:
		var face: StyleBox = (buttons[action] as Button).get_theme_stylebox("normal")
		if (buttons[action] as Button).visible:
			_check(face is StyleBoxFlat and (face as StyleBoxFlat).bg_color == idle_face, "적 턴에는 모든 스킬 칸이 어두운 면: " + action)
	turns.current_unit = ally_turn_unit
	hud.refresh_actions(actions, "attack", units[0])
	await process_frame


## 비용 기호 목록은 묶음의 자원에 복합 비용의 보조 행동만 더한다. 이동력은 기호가 없다(#517).
func _test_cost_marks() -> void:
	_check(CombatActionRules.cost_marks("attack") == [0] and CombatActionRules.cost_marks("cross_slash") == [0, 1]
		and CombatActionRules.cost_marks("steel_charge") == [1] and CombatActionRules.cost_marks("opportunity") == [2]
		and CombatActionRules.cost_marks("reflex") == [2], "비용 기호 목록: 복합 비용은 보조 행동을 더하고 이동력은 기호 없음")


## 윤곽 안쪽 칠, 검 계열의 모양, 공격과 장비 검의 같음을 원본 픽셀로 본다(#517).
func _test_skill_icon_pixels() -> void:
	var masks: Dictionary[String, Array] = {}
	for action: String in CombatActionRules.NAMES:
		var icon: Texture2D = CombatActionRules.icon_of(action)
		if icon == null:
			continue
		var image: Image = icon.get_image()
		var mask: Array[bool] = []
		var fill: int = 0
		for y: int in range(image.get_height()):
			for x: int in range(image.get_width()):
				var pixel: Color = image.get_pixel(x, y)
				mask.append(pixel.a > 0.5)
				if pixel.a > 0.5 and pixel.to_html(false) != "120d16":
					fill += 1
		masks[action] = mask
		_check(float(fill) / (image.get_width() * image.get_height()) >= 0.10,
			"스킬 아이콘 윤곽 안쪽 칠이 원본의 10%% 이상: %s %.3f" % [action, float(fill) / (image.get_width() * image.get_height())])
	var sword_image: Image = (load("res://scenes/combat/art/icons/items/sword.png") as Texture2D).get_image()
	_check(CombatActionRules.icon_of("attack").get_image().get_data() == sword_image.get_data(), "공격 아이콘은 장비 검과 같은 그림")
	var swords: Array[String] = ["attack", "cross_slash", "opportunity", "counter"]
	for first: int in range(swords.size()):
		for second: int in range(first + 1, swords.size()):
			var both: int = 0
			var either: int = 0
			for index: int in range(masks[swords[first]].size()):
				var left: bool = masks[swords[first]][index]
				var right: bool = masks[swords[second]][index]
				both += int(left and right)
				either += int(left or right)
			_check(float(both) / either <= 0.5, "검 계열 실루엣이 갈림(마스크 IoU 0.5 이하): %s·%s %.2f" % [
				swords[first], swords[second], float(both) / either])


func _test_skill_icons() -> void:
	# 새 아군 동작을 NAMES에 추가하면 아이콘도 함께 요구한다.
	for action: String in CombatActionRules.NAMES:
		var icon: Texture2D = CombatActionRules.icon_of(action)
		if action in ["spawn", "pull", "spin", "disengage"]:
			_check(icon == null, "적 전용 스킬은 아이콘 범위 밖: " + action)
		elif action in ["reflex", "stealth"]:
			_check(icon == null, "반사신경·은신은 아이콘 자산 전까지 이름 첫 글자를 보임(아이콘은 후속): " + action)
		else:
			_check(icon != null and icon.get_size() == Vector2(48, 48), "#362 스킬 아이콘 48px 원본: " + action)
	_test_skill_icon_pixels()
	var oil_icon: Texture2D = CombatActionRules.icon_of("oil_throw")
	_check(oil_icon != null and oil_icon.resource_path.ends_with("/skills/oil_throw.png")
		and oil_icon != CombatActionRules.icon_of("potion"), "기름병 던지기는 물약을 빌리지 않고 전용 아이콘을 쓴다(#560)")


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
	var source: TileSetAtlasSource = map.tile_set.get_source(map.get_cell_source_id(Vector2i.ZERO)) as TileSetAtlasSource
	var material: ShaderMaterial = source.get_tile_data(map.get_cell_atlas_coords(Vector2i.ZERO), 0).material as ShaderMaterial
	_check(material != null, "지형 타일에 실제 고밀도 원본 렌더를 연결한다")
	if material == null:
		return
	var detail: Texture2D = material.get_shader_parameter("detail_texture") as Texture2D
	_check(detail.get_width() == source.texture.get_width() * 2,
		"지형도 논리 크기 두 배의 실제 도트 디테일을 보존한다")
	_check(source.get_runtime_texture().get_size() == source.texture.get_size(),
		"실제 타일 UV와 고밀도 원본 UV의 전체 크기가 일치한다")
	for index: int in range(8):
		var region: Rect2i = source.get_runtime_tile_texture_region(Vector2i(index, 0), 0)
		_check(region == Rect2i(Vector2i(index * source.texture_region_size.x, 0), source.texture_region_size),
			"실제 타일 UV가 원본의 테두리까지 보존한다: %d" % index)
	var colors: Dictionary[int, bool] = {}
	var floor_image: Image = detail.get_image()
	for y: int in range(floor_image.get_height()):
		for x: int in range(floor_image.get_width()):
			var color: Color = floor_image.get_pixel(x, y)
			if color.a > 0.0:
				colors[color.to_rgba32()] = true
	_check(colors.size() > 16, "평면 색 도형 대신 실제 바닥·벽 도트 텍스처를 사용한다")
	for id: String in ["crate", "rock", "tree", "ruin_wall", "cottage"]:
		var path: String = "res://scenes/combat/art/props/%s.png" % id
		_check(ResourceLoader.exists(path), "실제 지형 오브젝트 PNG: " + id)
		if ResourceLoader.exists(path):
			var image: Image = (load(path) as Texture2D).get_image()
			var size: Vector2i = Vector2i(128, 128) if id == "cottage" else (
				Vector2i(64, 96) if id == "tree" else Vector2i(64, 64))
			_check(image.get_size() == size and image.get_pixel(0, 0).a == 0.0,
				"지형 오브젝트의 고밀도 캔버스와 투명 배경: " + id)
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


func _test_unit_art() -> void:
	for unit_id: String in ["warrior", "archer", "spiderling", "mother_spider", "fog_spider",
		"novice_barbarian", "novice_archer", "scrap_robot_1000", "scrap_robot_2000", "scrap_robot_3000"]:
		for state: String in ["idle", "move", "attack"]:
			for direction: String in ["left", "right"]:
				var images: Array[Image] = []
				for frame: int in range(2):
					var path: String = "res://scenes/combat/art/units/%s/%s/%s/%03d.png" % [
						unit_id, state, direction, frame]
					_check(ResourceLoader.exists(path), "실제 유닛 프레임 납품: " + path)
					if not ResourceLoader.exists(path):
						continue
					var texture: Texture2D = load(path) as Texture2D
					var image: Image = texture.get_image()
					_check(image.get_size() == Vector2i(64, 64) and image.is_invisible() == false
						and image.get_pixel(0, 0).a == 0.0, "64×64 투명 프레임: " + path)
					_check(image.get_used_rect().end.y <= 56,
						"발밑 피벗56 아래는 투명 여백: " + path)
					var enlarged: Image = image.duplicate()
					enlarged.resize(32, 32, Image.INTERPOLATE_NEAREST)
					enlarged.resize(64, 64, Image.INTERPOLATE_NEAREST)
					_check(enlarged.get_data() != image.get_data(), "32px 단순 확대가 아닌 고밀도 원본: " + path)
					images.append(image)
				if images.size() == 2:
					_check(images[0].get_data() != images[1].get_data(),
						"상태마다 실제로 다른 애니메이션 프레임: %s/%s/%s" % [unit_id, state, direction])
	for unit: CombatUnit in units:
		var visible_sprites: int = 0
		for child: Node in unit.get_children():
			if child is AnimatedSprite2D and child.visible and child.sprite_frames != null:
				visible_sprites += 1
				var current: Texture2D = child.sprite_frames.get_frame_texture(child.animation, child.frame)
				_check(current.get_size() * child.scale == Vector2(32, 32)
					and child.offset * child.scale == Vector2(-16, -28),
					"고밀도 프레임도 기존 표시 크기와 발밑 유지")
		_check(visible_sprites == 1, "실제 전투 유닛은 도트 애니메이션1개로 표시: " + unit.get_display_name())
		var resting_status_y: float = unit.get_status_label_y()
		unit.body_offset_y = -16.0
		_check(unit.get_status_label_y() == resting_status_y - 16.0,
			"점프 정점에서도 HP·상태·팝업 기준이 실제 그림을 따라간다")
		unit.body_offset_y = 0.0
		var portrait: Button = (hud.get("_portraits") as Dictionary)[unit] as Button
		_check(portrait.icon != null and portrait.icon.get_size() == Vector2(64, 64)
			and portrait.get_theme_constant("icon_max_width") == 32,
			"고밀도 초상의 논리 표시 폭32 유지: " + unit.get_display_name())


## 패시브 아이콘(#517): 32px 원본이 16 논리px로 칸에 보이고 칸 크기·이름·설명은 그대로다.
func _test_passive_icons(passives: Dictionary) -> void:
	for passive: String in CombatActionRules.PASSIVES:
		var icon: Texture2D = CombatActionRules.passive_icon_of(passive)
		_check(icon != null and icon.get_size() == Vector2(32, 32)
			and icon.resource_path == "res://scenes/combat/art/icons/passives/%s.png" % passive,
			"패시브 아이콘 32×32 원본: " + passive)
		var button: Button = passives[passive]
		_check(button.icon == icon and button.text.is_empty()
			and button.get_theme_constant("icon_max_width") == CombatActionRules.PASSIVE_ICON_SIZE
			and button.get_theme_color("icon_disabled_color") == Color.WHITE
			and button.material == preload("res://scenes/combat/art/pixel_art.tres"),
			"패시브 칸은 첫 글자 대신 16 논리px 아이콘과 도트 셰이더: " + passive)
		_check(button.accessibility_name == CombatActionRules.PASSIVE_NAMES[passive]
			and button.tooltip_text == CombatActionRules.PASSIVE_NAMES[passive] + "\n" + CombatActionRules.PASSIVE_EFFECTS[passive],
			"패시브 칸 이름·설명 그대로: " + passive)
		if button.visible:
			# 숨은 칸은 갱신 때 건너뛰므로 스타일은 보이는 칸만 본다.
			for state: String in ["normal", "hover", "pressed", "disabled"]:
				var style: StyleBoxFlat = button.get_theme_stylebox(state) as StyleBoxFlat
				_check(style != null and style.content_margin_left == 3 and style.content_margin_right == 3,
					"패시브 칸 좌우 여백 3: %s %s" % [passive, state])
			_check(button.size == Vector2(22, 34), "패시브 칸 크기 22×34 그대로: %s %s" % [passive, button.size])


## 패시브 칸(#457): 전사에만 보이고 팔랑크스는 인접 아군이 있을 때만 켜진다. 수치 색은 가감 부호만 칠한다.
func _test_passive_slot_and_number_colors() -> void:
	var passives: Dictionary = hud.get("_passives")
	var dots: Dictionary = hud.get("_passive_dots")
	hud.refresh_actions(actions, "attack", units[0])
	_check((passives["phalanx"] as Button).visible and (passives["brawn"] as Button).visible,
		"패시브 칸: 전사 선택 시 팔랑크스·괴력의 사내 칸")
	_check((dots["phalanx"] as Label).visible == (actions.grid.phalanx_bonus(units[0]) > 0),
		"패시브 칸: 팔랑크스 강조 점은 실제 적용 중에만")
	# 인접 아군이 없으면 팔랑크스 강조가 꺼진다. 검사 뒤 궁수 위치를 되돌린다.
	var archer_cell: Vector2i = units[1].cell
	units[1].cell = Vector2i(9, 1)
	hud.refresh_actions(actions, "attack", units[0])
	_check(actions.grid.phalanx_bonus(units[0]) == 0 and not (dots["phalanx"] as Label).visible,
		"패시브 칸: 인접 아군이 없으면 팔랑크스 강조 꺼짐")
	units[1].cell = archer_cell
	hud.refresh_actions(actions, "attack", units[0])
	_check(not (dots["brawn"] as Label).visible, "패시브 칸: 괴력의 사내는 상시 강조 없음")
	_check(not CombatActionRules.belongs_to(units[1], "phalanx") and not CombatActionRules.belongs_to(units[1], "brawn"),
		"패시브 칸: 궁수에게는 전사 패시브가 없음")
	_check(not (passives["moving_shot"] as Button).visible, "패시브 칸: 전사에게는 무빙샷 칸이 없음")
	_test_passive_icons(passives)
	var colored: String = CombatActionRules.colorize("힘 d20+2 · 공격 -1 · AC +0 · 공격 +3 · HP 5")
	_check(colored.contains("[color=#70c76d]+2[/color]") and colored.contains("[color=#ff8a80]-1[/color]")
		and colored.contains("[color=#70c76d]+3[/color]") and not colored.contains("+0[/color]")
		and colored.contains("AC +0"), "수치 색: 가감 부호만 칠하고 +0은 칠하지 않음: " + colored)
	_check(CombatActionRules.colorize("HP 5 / 9") == "HP 5 / 9", "수치 색: 가감이 없는 줄은 그대로")
	# 방어막 바(#457): HP 뒤에 이어 그리고, 합이 최대 HP를 넘으면 합에 맞춘다. 검사 뒤 값을 되돌린다.
	var unit: CombatUnit = units[0]
	var saved_hp: int = unit.hit_points
	var saved_shield: int = unit.shield_points
	var max_hp: int = unit.get_max_hit_points()
	unit.hit_points = max_hp
	unit.shield_points = 0
	_check(unit.get_bar_fractions().is_equal_approx(Vector2(1, 0)), "방어막 바: 방어막이 없으면 HP만")
	unit.hit_points = max_hp - 4
	unit.shield_points = 2
	_check(unit.get_bar_fractions().is_equal_approx(Vector2(float(max_hp - 4) / max_hp, 2.0 / max_hp)),
		"방어막 바: 합이 최대 HP 이하면 최대 HP 기준")
	unit.hit_points = max_hp
	unit.shield_points = max_hp
	_check(unit.get_bar_fractions().is_equal_approx(Vector2(0.5, 0.5)), "방어막 바: 합이 넘으면 합 기준")
	unit.shield_points = 0
	_check(unit.get_bar_fractions().y == 0.0, "방어막 바: 방어막이 다 닳으면 사라짐")
	unit.hit_points = saved_hp
	unit.shield_points = saved_shield


func _test_warrior() -> void:
	var buttons: Dictionary = hud.get("_actions")
	var badges: Dictionary = hud.get("_badges")
	var costs: Dictionary = hud.get("_costs")
	var titles: Array = hud.get("_titles")
	_check(hud.unit_label.text == "아군 전사" and "HP 11 / 11" in hud.resource_label.get_parsed_text()
		and "AC 6" in hud.resource_label.get_parsed_text() and "팔랑크스 AC +1" in hud.resource_label.get_parsed_text()
		and "이동" not in hud.resource_label.get_parsed_text(),
		"현재 유닛 정보: HP·AC(민첩 d8 표준값 5 + 인접 궁수 팔랑크스 1) 표시, 남은 이동 제거")
	_check(hud.health_bar.value == 11, "현재 유닛 HP 바")
	for ability: String in ["힘 d20", "민첩 d8", "솜씨 d6", "지능 d4", "의지 d8", "건강 d12"]:
		_check(ability in hud.resource_label.get_parsed_text(), "현재 전사의 능력치 주사위 표시: " + ability)
	_check("자연" not in hud.resource_label.get_parsed_text() and "정신" not in hud.resource_label.get_parsed_text(),
		"폐지한 능력치는 유닛 정보에서 제거")
	var warrior_actions: Array[String] = ["attack", "sweep", "cross_slash", "battle_cry", "holy_veil", "steel_charge",
		"shove", "opportunity", "counter"]
	for action: String in warrior_actions:
		_check((buttons[action] as Button).is_visible_in_tree(), "전사 동작 표시: " + action)
	_check(not (buttons["potion"] as Button).is_visible_in_tree() and not (buttons["oil_bottle"] as Button).is_visible_in_tree(),
		"물약 칸이 빈 전사에게 물약류 버튼은 숨김(#576)")
	for action: String in ["aegisal", "bow_bash", "disengage"]:
		_check(not (buttons[action] as Button).visible, "궁수·몬스터 동작 숨김: " + action)
	_check(not buttons.has("mark") and not buttons.has("shock"), "옛 궁수 스킬 버튼 없음(#528)")
	_check(not (buttons["second_wind"] as Button).visible, "아군 전사는 몬스터 전용 숨 고르기 숨김")
	for action: String in warrior_actions:
		var button: Button = buttons[action]
		_check(button.size == Vector2(52, 34), "#362 스킬 버튼 입력 52×34 유지: " + action)
		_check(button.get_theme_constant("icon_max_width") == 24, "#362 스킬 그림 24 논리px: " + action)
	_check((titles[0] as Label).text == "행동 ●" and (titles[1] as Label).text == "보조 행동 ▲"
		and (titles[2] as Label).text == "반응 ◆", "컨테이너 제목이 자원 표시")
	_check(not (badges["attack"] as Label).visible and not (badges["shove"] as Label).visible,
		"횟수 제한이 없는 동작은 배지 숨김")
	_check((badges["battle_cry"] as Label).text == "1" and _cost_text(costs["battle_cry"]) == "●",
		"비용 기호와 횟수 숫자 분리")
	_check(_cost_text(costs["cross_slash"]) == "●▲" and _cost_text(costs["steel_charge"]) == "▲"
		and not (badges["opportunity"] as Label).visible and _cost_text(costs["opportunity"]) == "◆",
		"복합 비용은 함께 쓰는 턴 자원 기호를 잇고 이동력은 기호 없음")
	_check((badges["steel_charge"] as Label).text == "1" and (badges["potion"] as Label).text == "0"
		and _cost_text(costs["holy_veil"]) == "▲" and _cost_text(costs["potion"]) == "▲",
		"호버에서 제거한 스킬 횟수·물약 개수와 비용은 배지·마크에 유지")
	var badge: Label = badges["battle_cry"] as Label
	var cost: Control = costs["battle_cry"] as Control
	_check(badge.size.y <= 15 and not badge.get_global_rect().intersects(cost.get_global_rect()),
		"횟수 배지는 작고 비용 기호와 겹치지 않음: badge=%s cost=%s min=%s font=%d fontheight=%f" % [
			badge.get_global_rect(), cost.get_global_rect(), badge.get_combined_minimum_size(),
			badge.get_theme_font_size("font_size"), badge.get_theme_font("font").get_height(9)])
	_check((buttons["potion"] as Button).disabled, "효과 없는 동작 비활성화")
	var before: int = units[0].reaction_left
	(buttons["opportunity"] as Button).pressed.emit()
	(buttons["opportunity"] as Button).pressed.emit()
	_check(units[0].reaction_left == before and (battle.get("selection") as CombatSelection).selected_action == "attack",
		"자기 턴의 반응 항목은 아무 동작도 실행하지 않음")


func _test_resources() -> void:
	var buttons: Dictionary = hud.get("_actions")
	var titles: Array = hud.get("_titles")
	units[0].action_left = 0
	units[0].reaction_left = 0
	battle.call("_update_turn_ui")
	_check((titles[0] as Label).text == "행동 ○" and (titles[2] as Label).text == "반응 ◇",
		"소비 자원은 빈 기호")
	_check(not (buttons["holy_veil"] as Button).disabled and (buttons["cross_slash"] as Button).disabled
		and (buttons["battle_cry"] as Button).disabled, "행동을 쓰면 행동 스킬만 비활성화하고 보조 행동 장막은 활성화")
	_check(not (buttons["opportunity"] as Button).disabled, "자기 턴 반응 항목은 자원·횟수0도 켜진 표시")
	(buttons["holy_veil"] as Button).pressed.emit()
	_check(units[0].bonus_action_left == 1 and units[0].shield_points == 0, "자기 대상 첫 클릭은 미리보기")
	actions.dice = ScriptedDice.new([7], [12])
	(buttons["holy_veil"] as Button).pressed.emit()
	_check((titles[0] as Label).text == "행동 ○" and (titles[1] as Label).text == "보조 행동 △"
		and units[0].shield_points == 7 and units[0].shield_turns == CombatActionRules.SHIELD_TURNS,
		"성스러운 장막은 보조 행동 기호 한 개만 쓰고 건강 굴림값만큼 방어막")
	_check("방어막 7 (3턴)" in hud.resource_label.get_parsed_text(), "유닛 정보에 방어막 값과 남은 턴 표시")
	_check((buttons["holy_veil"] as Button).disabled, "보조 행동 소진 비활성화")
	units[0].clear_unit_effects()
	units[0].movement_left = 0
	units[0].action_left = 0
	battle.call("_update_turn_ui")
	var style: StyleBoxTexture = hud.end_button.get_theme_stylebox("normal") as StyleBoxTexture
	_check(style.modulate_color == CombatTurnHud.END_BUTTON_COLOR and turns.current_unit == units[0],
		"할 일이 없으면 색만 변경하고 턴 유지")
	await process_frame


## 반사신경 확인 창: 후보 칸마다 버튼 하나와 넘기기. 칸을 고르면 reflex_selected가 나온다. 다른 반응 창에는 칸 버튼이 남지 않는다.
func _test_reflex_dialog() -> void:
	var cells: Array[Vector2i] = [Vector2i(3, 9), Vector2i(5, 9)]
	var picked: Array[Vector2i] = []
	hud.reflex_selected.connect(func(cell: Vector2i) -> void: picked.append(cell))
	hud.show_reaction("reflex", "적의 공격이 명중했습니다.", cells)
	var dialog: ConfirmationDialog = hud.reaction_dialog
	var reflex_buttons: Array[Button] = hud.get("_reflex_buttons")
	_check(dialog.visible and not dialog.get_ok_button().visible and dialog.get_cancel_button().text == "넘기기"
		and reflex_buttons.size() == 2, "반사신경 창: 후보 칸 수만큼 버튼, 넘기기, 확인 버튼 숨김")
	reflex_buttons[1].pressed.emit()
	_check(picked == [cells[1]] and not dialog.visible, "칸 버튼을 누르면 그 칸을 보내고 창을 닫음: " + str(picked))
	hud.show_reaction("opportunity", "벗어납니다.")
	_check(dialog.get_ok_button().visible and (hud.get("_reflex_buttons") as Array).is_empty()
		and dialog.get_ok_button().text == "공격", "다른 반응 창에는 칸 버튼이 남지 않음")
	hud.reaction_dialog.hide()
	hud.show_reaction("reflex", "다시 묻습니다.", cells)
	_check((hud.get("_reflex_buttons") as Array).size() == 2, "다시 열어도 칸 버튼은 후보 수만큼만")
	dialog.get_cancel_button().pressed.emit()
	_check(picked == [cells[1]] and not dialog.visible, "넘기기는 칸을 보내지 않음")
	# battle 배선: 칸 버튼 글자는 맵 투영의 화면 방향이다(x+1은 오른쪽 아래, y+1은 왼쪽 아래).
	var at: Vector2i = units[1].cell
	actions.pending_reactor = units[1]
	actions.pending_kind = "reflex"
	actions.pending_cells = [at + Vector2i(-1, 0), at + Vector2i(1, 0), at + Vector2i(0, -1), at + Vector2i(0, 1)]
	actions.reaction_requested.emit("reflex", "배선 확인")
	var arrows: Array[String] = []
	for button: Button in hud.get("_reflex_buttons"):
		arrows.append(button.text)
	_check(arrows == ["↖", "↘", "↗", "↙"], "칸 버튼은 화면 방향 화살표: " + str(arrows))
	dialog.get_cancel_button().pressed.emit()
	actions.pending_kind = ""
	actions.pending_cells = []
	_check(actions.pending_reactor == null and not dialog.visible, "넘기기로 대기 해제")


func _test_archer_and_enemy() -> void:
	var buttons: Dictionary = hud.get("_actions")
	var containers: Array = hud.get("_containers")
	var before: int = units[0].movement_left
	hud.unit_selected.emit(units[1])
	_check(turns.current_unit == units[1] and units[0].movement_left == before, "초상 전환 자원 유지")
	for ability: String in ["힘 d6", "민첩 d12", "솜씨 d20", "지능 d6", "의지 d4", "건강 d8"]:
		_check(ability in hud.resource_label.get_parsed_text(), "궁수로 전환하면 능력치 주사위 갱신: " + ability)
	# 궁수의 반응 칸에는 반사신경만 있다. 기회 공격·반격은 없다.
	_check((containers[2] as PanelContainer).visible and (buttons["reflex"] as Button).visible
		and not (buttons["opportunity"] as Button).visible and not (buttons["counter"] as Button).visible,
		"궁수 반응 컨테이너는 반사신경 버튼만 표시")
	_check((buttons["reflex"] as Button).text == "반" and "반응 1 + 이동력 1" in (buttons["reflex"] as Button).tooltip_text,
		"반사신경은 아이콘이 없어 이름 첫 글자를 보이고 호버에 비용: " + (buttons["reflex"] as Button).tooltip_text)
	for action: String in ["attack", "aegisal", "bow_bash", "jump", "stealth"]:
		_check((buttons[action] as Button).visible, "궁수 스킬 표시: " + action)
	_check((buttons["stealth"] as Button).text == "은" and "전투마다 1회 · 1회 남음" in (buttons["stealth"] as Button).tooltip_text
		and (buttons["stealth"] as Button).tooltip_text.begins_with("은신\n"),
		"은신은 아이콘이 없어 이름 첫 글자를 보이고 호버에 횟수: " + (buttons["stealth"] as Button).tooltip_text)
	_check(not (buttons["cross_slash"] as Button).visible and not (buttons["disengage"] as Button).visible,
		"궁수 스킬만 표시")
	_check(battle.call("preview_enemy", units[2]), "적 미리보기 연결")
	_check(hud.unit_label.text == "풋내기 야만인" and "AC 4" in hud.resource_label.get_parsed_text(),
		"미리보기는 유닛 정보 자리를 사용하고 대상 AC를 표시")
	_check((buttons["aegisal"] as Button).visible, "미리보기에도 현재 아군의 스킬 유지")
	hud.unit_selected.emit(units[0])
	hud.end_button.pressed.emit()
	hud.end_button.pressed.emit()
	_check(not turns.current_unit.is_ally and hud.unit_label.text == turns.current_unit.get_display_name(),
		"적 턴에는 행동 중인 적 정보")
	_check(not hud.has_node("Move") and not hud.has_node("InputHint"), "이동 버튼과 상시 입력 안내 없음")
	_check(hud.end_button.disabled, "적 턴 종료는 AI가 처리하며 버튼은 잠김")
	_check((buttons["aegisal"] as Button).visible and (buttons["aegisal"] as Button).disabled
		and (containers[2] as PanelContainer).visible, "적 턴에는 마지막 궁수 패널 회색 유지")
	for button: Button in buttons.values():
		if button.is_visible_in_tree():
			_check(button.disabled, "적 턴 입력 잠금: " + button.text)
	actions.busy = true
	battle.call("_update_turn_ui")
	_check(hud.end_button.disabled, "반응 대기 중 턴 종료 잠금")
	actions.busy = false


## 나무 불타기 안내와 그림(#529): 화살 안내 줄과, 탄 나무의 그림이 사라짐.
func _test_tree_burn_ui() -> void:
	_reset_units()
	var archer: CombatUnit = units[1]
	var grid: CombatGrid = actions.grid
	var original: CombatStage = battle.stages[0]
	var staged: CombatStage = original.duplicate() as CombatStage
	staged.scenery = {Vector2i(2, 5): "tree", Vector2i(6, 5): "tree"}
	grid.blocked_cells = staged.get_blocked_cells()
	grid.trees = staged.tree_cells()
	(battle.get_node("Map") as CombatMap).build_grid(grid, staged.tile_set, staged)
	var tree: Vector2i = grid.trees[0]
	var corners: Array[Vector2i] = [Vector2i(0, 9), Vector2i(9, 9), Vector2i(9, 0), Vector2i(0, 0)]
	var corner: int = 0
	for unit: CombatUnit in units:
		if unit != archer and corner < corners.size():
			unit.cell = corners[corner]
			corner += 1
	var stand: Vector2i = Vector2i(-1, -1)
	for neighbor: Vector2i in CombatGrid.neighbors(tree):
		if grid.is_floor(neighbor) and not grid.is_blocked(neighbor) and grid.unit_at(neighbor) == null:
			stand = neighbor
	archer.cell = stand
	turns.select_unit(archer)
	battle.call("_update_turn_ui")
	var trick_note: String = battle.call("_arrow_note", archer, "trick_arrow", tree)
	_check(tr("화염이 나오면 나무가 타서 길이 열림") in trick_note, "장난스러운 화살이 나무를 겨누면 안내: " + trick_note)
	var plain: Vector2i = Vector2i(-1, -1)
	for cell: Vector2i in actions.aim_cells(archer, "firework_arrow"):
		if actions.aim_area(archer, "firework_arrow", cell).all(func(area_cell: Vector2i) -> bool: return not grid.is_tree(area_cell)):
			plain = cell
			break
	_check(plain != Vector2i(-1, -1) and tr("나무가 타서 길이 열림") not in (battle.call("_arrow_note", archer, "firework_arrow", plain) as String)
		and tr("나무가 타서 길이 열림") not in (battle.call("_arrow_note", archer, "trick_arrow", plain) as String), "나무가 없으면 안내 줄 없음")
	var firework_note: String = battle.call("_arrow_note", archer, "firework_arrow", tree)
	_check(firework_note.ends_with(tr("나무가 타서 길이 열림")), "폭죽 영역에 나무가 있으면 안내: " + firework_note)
	var map: CombatMap = battle.get_node("Map") as CombatMap
	var markers: Array = (map.get("_blocked_markers") as Array).filter(func(marker: Node2D) -> bool: return marker.get_meta("tree", false))
	actions.touch_attribute(tree, "fire", archer)
	battle.call("_update_turn_ui")
	var left: Array = (map.get("_blocked_markers") as Array).filter(func(marker: Node2D) -> bool: return marker.get_meta("tree", false))
	_check(left.size() == markers.size() - 1 and left.all(func(marker: Node2D) -> bool: return marker.get_meta("cell") != tree),
		"탄 나무의 그림만 사라짐: %d → %d" % [markers.size(), left.size()])
	grid.blocked_cells = original.get_blocked_cells()
	grid.trees = original.tree_cells()
	map.build_grid(grid, original.tile_set, original)
	actions.burned_trees.clear()


## 궁수 스킬 패널과 무빙샷 입력(#528): 공격 뒤 선택이 무빙샷으로 바뀌고, 같은 빈 칸을 두 번 우클릭하면 도약한다.
func _test_archer_moving_shot_input() -> void:
	_reset_units()
	var archer: CombatUnit = units[1]
	var target: CombatUnit = units[3]
	units[0].cell = Vector2i(0, 9)
	archer.cell = Vector2i(4, 4)
	units[2].cell = Vector2i(9, 9)
	target.cell = Vector2i(4, 7)
	target.reaction_left = 0
	turns.select_unit(archer)
	battle.call("_update_turn_ui")
	await process_frame
	var buttons: Dictionary = hud.get("_actions")
	var passives: Dictionary = hud.get("_passives")
	var dots: Dictionary = hud.get("_passive_dots")
	var shown: Array[String] = []
	for action: String in buttons:
		if (buttons[action] as Button).is_visible_in_tree():
			shown.append(action)
	_check(shown == ["attack", "trick_arrow", "firework_arrow", "whistle", "aegisal", "bow_bash", "shove", "jump", "oil_throw", "stealth", "reflex"], "궁수 스킬 패널의 버튼(공용 밀치기 포함, 물약 칸이 비면 물약류 버튼은 숨김): " + str(shown))
	# 기름병 던지기: 버튼을 고르고 칸을 한 번 누르면 십자 범위를 보이고, 같은 칸을 다시 누르면 던진다(#500 2a).
	var oil_cells: Array[Vector2i] = []
	oil_cells.assign(actions.aim_cells(archer, "oil_throw").filter(func(cell: Vector2i) -> bool:
		return cell != archer.cell and actions._oil_site_ok(cell, cell)))
	_check(not oil_cells.is_empty(), "기름병 검사 전제: 던질 수 있는 칸이 있음")
	if not oil_cells.is_empty():
		battle.call("_on_action_selected", "oil_throw")
		var oil_selection: CombatSelection = battle.get("selection") as CombatSelection
		_check(oil_selection.selected_action == "oil_throw", "기름병 던지기 버튼은 칸 조준 모드로 들어감")
		battle.call("_select_aim_cell", oil_cells[0])
		_check(actions.get_grounds().all(func(ground: CombatActions.Ground) -> bool: return ground.kind != "oil")
			and oil_selection.preview_cell == oil_cells[0], "첫 클릭은 칸만 고르고 던지지 않음")
		battle.call("_select_aim_cell", oil_cells[0])
		_check(actions.get_grounds().any(func(ground: CombatActions.Ground) -> bool:
			return ground.kind == "oil" and ground.cell == oil_cells[0]) and archer.oil_throw_left == 0,
			"같은 칸을 다시 누르면 그 칸에 기름을 던짐")
		actions._grounds.assign(actions._grounds.filter(func(ground: CombatActions.Ground) -> bool: return ground.kind != "oil"))
		archer.oil_throw_left = 1
		archer.bonus_action_left = 1
		battle.call("_update_turn_ui")
	# 물약류 버튼(#576): 가진 종류만 보이고 개수를 배지로 보이며 기름병 던지기 앞에 놓인다.
	var potion_button: Button = buttons["potion"]
	var bottle_button: Button = buttons["oil_bottle"]
	_check(not potion_button.is_visible_in_tree() and not bottle_button.is_visible_in_tree(), "물약 칸이 비면 두 종류 버튼 모두 숨김")
	archer.potions.assign(["healing_potion", "oil_bottle", "oil_bottle"])
	battle.call("_update_turn_ui")
	var badges: Dictionary = hud.get("_badges")
	_check(potion_button.is_visible_in_tree() and bottle_button.is_visible_in_tree()
		and (badges["potion"] as Label).text == "1" and (badges["oil_bottle"] as Label).text == "2",
		"가진 종류마다 버튼과 남은 개수 배지")
	_check(potion_button.get_index() < bottle_button.get_index() and bottle_button.get_index() < (buttons["oil_throw"] as Button).get_index(),
		"버튼 순서는 회복 물약, 기름병, 기름병 던지기")
	var bottle_icon: Texture2D = bottle_button.icon
	_check(bottle_icon != null and bottle_icon != (buttons["oil_throw"] as Button).icon and bottle_icon != potion_button.icon,
		"기름병 버튼은 던지기·회복 물약과 다른 그림")
	archer.potions.assign(["oil_bottle"])
	battle.call("_update_turn_ui")
	_check(not potion_button.is_visible_in_tree() and bottle_button.is_visible_in_tree(), "회복 물약이 없으면 그 버튼만 숨김")
	var bottle_cells: Array[Vector2i] = []
	bottle_cells.assign(actions.aim_cells(archer, "oil_bottle").filter(func(cell: Vector2i) -> bool:
		return cell != archer.cell and actions._oil_site_ok(cell, cell)))
	_check(not bottle_cells.is_empty(), "기름병 검사 전제: 던질 수 있는 칸이 있음")
	if not bottle_cells.is_empty():
		battle.call("_on_action_selected", "oil_bottle")
		var bottle_selection: CombatSelection = battle.get("selection") as CombatSelection
		_check(bottle_selection.selected_action == "oil_bottle", "기름병 버튼은 칸 조준 모드로 들어감")
		battle.call("_select_aim_cell", bottle_cells[0])
		_check(archer.potions == ["oil_bottle"] and bottle_selection.preview_cell == bottle_cells[0], "첫 클릭은 칸만 고름")
		battle.call("_select_aim_cell", bottle_cells[0])
		_check(actions.get_grounds().any(func(ground: CombatActions.Ground) -> bool:
			return ground.kind == "oil" and ground.cell == bottle_cells[0]) and archer.potions.is_empty() and archer.oil_throw_left == 1
			and not bottle_button.is_visible_in_tree(), "같은 칸을 다시 누르면 던지고 마지막 기름병이면 버튼이 사라짐")
		actions._grounds.assign(actions._grounds.filter(func(ground: CombatActions.Ground) -> bool: return ground.kind != "oil"))
		archer.bonus_action_left = 1
		battle.call("_update_turn_ui")
	# 장난스러운 화살·폭죽 화살(#500 2b): 첫 클릭은 칸만 고르고 같은 칸을 다시 누르면 쏜다.
	var free_cells: Array[Vector2i] = []
	free_cells.assign(actions.aim_cells(archer, "trick_arrow").filter(func(cell: Vector2i) -> bool:
		return actions.grid.unit_at(cell) == null and actions.grid.prop_at(cell) == null))
	_check(not free_cells.is_empty(), "화살 검사 전제: 빈 칸이 있음")
	if not free_cells.is_empty():
		var arrow_selection: CombatSelection = battle.get("selection") as CombatSelection
		for arrow: String in ["trick_arrow", "firework_arrow"]:
			archer.action_left = 1
			archer.firework_arrow_left = 1
			actions.dice = ScriptedDice.new([], []).then_seeded()
			battle.call("_on_action_selected", arrow)
			_check(arrow_selection.selected_action == arrow, "%s 버튼은 칸 조준 모드로 들어감" % arrow)
			await battle.call("_select_aim_cell", free_cells[0])
			_check(archer.action_left == 1 and arrow_selection.preview_cell == free_cells[0], "%s 첫 클릭은 칸만 고름" % arrow)
			await battle.call("_select_aim_cell", free_cells[0])
			_check(archer.action_left == 0 and (arrow != "firework_arrow" or archer.firework_arrow_left == 0),
				"%s 같은 칸을 다시 누르면 쏨" % arrow)
		archer.action_left = 1
		archer.firework_arrow_left = 1
		archer.moving_shot_ready = false
		archer.moving_shot_spent = false
		arrow_selection.selected_action = "attack"
		battle.call("_update_turn_ui")
	_check((passives["moving_shot"] as Button).visible and not (passives["phalanx"] as Button).visible
		and not (dots["moving_shot"] as Label).visible and (passives["moving_shot"] as Button).disabled,
		"궁수 패시브 칸의 무빙샷은 도약할 수 없는 동안 꺼짐")
	var selection: CombatSelection = battle.get("selection") as CombatSelection
	# 활 후려치기를 고르고 인접한 적을 처음 누르면, 필드 미리보기가 힘 d6 근접 판정(원거리 불리 없음)을 보인다.
	target.cell = Vector2i(4, 5)
	battle.call("_update_turn_ui")
	await process_frame
	(buttons["bow_bash"] as Button).pressed.emit()
	await _click(target.get_global_transform_with_canvas() * Vector2(0, -10))
	var bash: CombatChecks.AttackPreview = actions.grid.attack_preview(archer, target, "bow_bash")
	_check(selection.selected_action == "bow_bash" and selection.preview_target == target and archer.bonus_action_left == 1
		and actions.grid.attack_preview(archer, target).mode == CombatChecks.RollMode.DISADVANTAGE
		and hud.preview_label.text == tr("명중률 %.1f%% · %s") % [bash.chance * 100.0, tr("일반")],
		"활 후려치기 필드 미리보기는 그 동작의 명중률과 일반 판정: " + hud.preview_label.text)
	(buttons["attack"] as Button).pressed.emit()
	target.cell = Vector2i(4, 7)
	battle.call("_update_turn_ui")
	await process_frame
	actions.dice = ScriptedDice.new([15, 2], [20, 20])
	var point: Vector2 = target.get_global_transform_with_canvas() * Vector2(0, -10)
	await _click(point)
	await _click(point)
	_check(archer.action_left == 0 and archer.moving_shot_ready and selection.selected_action == "moving_shot",
		"공격 뒤 선택이 무빙샷으로 바뀜")
	var cells: Array[Vector2i] = battle.get("movement_cells")
	_check(cells.size() == 4 and Vector2i(5, 4) in cells and Vector2i(4, 3) in cells, "도약할 인접 빈 칸을 표시: " + str(cells))
	_check((dots["moving_shot"] as Label).visible and not (passives["moving_shot"] as Button).disabled,
		"도약할 수 있는 동안 무빙샷 켜짐 점")
	(buttons["aegisal"] as Button).pressed.emit()
	_check(selection.selected_action == "aegisal" and archer.moving_shot_ready and archer.bonus_action_left == 1,
		"다른 버튼을 고르기만 하면 도약 기회가 남음")
	(passives["moving_shot"] as Button).pressed.emit()
	_check(selection.selected_action == "moving_shot", "무빙샷 패시브 버튼으로 다시 도약 선택")
	var map: CombatMap = battle.get_node("Map") as CombatMap
	var leap: Vector2 = map.get_global_transform_with_canvas() * map.map_to_local(Vector2i(5, 4))
	# 도약 미리보기의 미끌거림 안내(#600): 기름 칸에 착지하면 보이고, 기름이 없으면 보이지 않는다.
	var slip_note: String = "미끌거림: 솜씨 내성 DC %d" % CombatOil.SLIP_DC
	var dry: Vector2 = map.get_global_transform_with_canvas() * map.map_to_local(Vector2i(4, 3))
	await _click(dry, MOUSE_BUTTON_RIGHT)
	_check(selection.preview_cell == Vector2i(4, 3) and slip_note not in hud.preview_label.text,
		"기름이 없는 도약 미리보기에는 미끌거림 안내가 없음: " + hud.preview_label.text)
	actions._grounds.append(CombatActions.Ground.new(archer, Vector2i(5, 4), "oil"))
	await _click(leap, MOUSE_BUTTON_RIGHT)
	_check(archer.cell == Vector2i(4, 4) and selection.preview_cell == Vector2i(5, 4), "첫 우클릭은 착지 칸 미리보기")
	_check(slip_note in hud.preview_label.text, "기름 칸으로 도약하는 미리보기에 미끌거림 안내: " + hud.preview_label.text)
	actions._grounds.clear()
	await _click(leap, MOUSE_BUTTON_RIGHT)
	_check(archer.cell == Vector2i(5, 4) and archer.movement_left == archer.get_movement() and not archer.moving_shot_ready
		and selection.selected_action == "attack" and not (dots["moving_shot"] as Label).visible,
		"같은 칸 두 번째 우클릭으로 이동력 없이 도약하고 선택을 되돌림")
	# 걷기 미리보기의 미끌거림 안내는 그대로다(#600 회귀).
	actions._grounds.append(CombatActions.Ground.new(archer, Vector2i(5, 5), "oil"))
	var walk: Vector2 = map.get_global_transform_with_canvas() * map.map_to_local(Vector2i(5, 6))
	await _click(walk, MOUSE_BUTTON_RIGHT)
	_check(selection.selected_action == "move" and not selection.preview_path.is_empty() and slip_note in hud.preview_label.text,
		"걷기 미리보기는 기름 칸 경로에 미끌거림 안내: " + hud.preview_label.text)
	actions._grounds.clear()
	selection.clear_preview()
	# 뒤 검사가 쓰는 처음 배치로 되돌린다.
	units[0].cell = Vector2i(4, 9)
	archer.cell = Vector2i(5, 9)
	units[2].cell = Vector2i(4, 8)
	target.cell = Vector2i(7, 9)
	_reset_units()
	battle.call("_update_turn_ui")


# WCAG 2 상대 휘도의 명암비. Color는 sRGB 값을 담는다.
func _contrast_ratio(a: Color, b: Color) -> float:
	var la: float = a.srgb_to_linear().get_luminance()
	var lb: float = b.srgb_to_linear().get_luminance()
	return (maxf(la, lb) + 0.05) / (minf(la, lb) + 0.05)


func _test_log_and_status() -> void:
	hud.add_log("첫째")
	hud.add_log("둘째")
	hud.add_log("셋째")
	hud.add_log("넷째")
	_check(hud.message_label.text == "둘째\n셋째\n넷째", "최근 로그는 정확히3줄")
	# 배경이 불투명해야 아래 지형과 관계없이 명암비가 고정된다.
	var log_panel: PanelContainer = hud.get_node("CombatLog") as PanelContainer
	var log_background: Color = (log_panel.get_theme_stylebox("panel") as StyleBoxTexture).modulate_color
	var log_contrast: float = _contrast_ratio(hud.message_label.get_theme_color("font_color"), log_background)
	_check(log_background.a == 1.0 and log_contrast >= 4.5,
		"전투 로그 불투명 배경과 WCAG AA 4.5:1 이상: alpha %.2f, %.2f" % [log_background.a, log_contrast])
	units[2].is_stunned = true
	units[2].hit_points = 5
	battle.call("_update_turn_ui")
	hud.show_unit(units[2])
	_check("기절" in hud.resource_label.get_parsed_text() and "◎" not in hud.resource_label.get_parsed_text(),
		"기절은 유닛 정보에 반영하고 표식(#528 삭제)은 없음")
	_check(hud.health_bar.value == 5, "대상 HP 갱신")
	units[2].fallen = true
	hud.show_unit(units[2])
	_check("넘어짐" in hud.resource_label.get_parsed_text(), "넘어짐은 유닛 정보 상태 줄에 보임(#500 2a)")
	units[2].fallen = false
	units[2].stealthed = true
	hud.show_unit(units[2])
	_check("은신" in hud.resource_label.get_parsed_text() and "은신" in units[2].get_status_text(),
		"은신은 유닛 정보 상태 줄과 유닛 위 상태 글자에 보임")
	units[2].stealthed = false
	# 넘어진 아군은 턴 종료 위의 일어나기 버튼으로 이동력 절반을 내고 일어난다(#500 2a 설계 결정 5).
	var standing: CombatUnit = actions.turns.current_unit
	_check(standing != null and standing.is_ally, "일어나기 검사 전제: 지금 턴은 아군")
	standing.fallen = true
	var stand_cost: int = CombatOil.standing_cost(standing.get_movement())
	standing.movement_left = stand_cost
	battle.call("_update_turn_ui")
	_check(hud.stand_button.visible and not hud.stand_button.disabled
		and hud.stand_button.text == "일어나기 · 이동력 %d" % stand_cost
		and not hud.stand_button.get_global_rect().intersects(hud.end_button.get_global_rect()),
		"넘어진 아군의 턴에는 비용을 적은 일어나기 버튼이 턴 종료 위에 보임")
	var prone_end_style: StyleBoxTexture = hud.end_button.get_theme_stylebox("normal") as StyleBoxTexture
	_check(prone_end_style.modulate_color != CombatTurnHud.END_BUTTON_COLOR,
		"넘어진 아군의 이동력이 일어서기 비용 이상이면 턴 종료를 강조하지 않음(#560)")
	standing.movement_left = stand_cost - 1
	battle.call("_update_turn_ui")
	prone_end_style = hud.end_button.get_theme_stylebox("normal") as StyleBoxTexture
	_check(prone_end_style.modulate_color == CombatTurnHud.END_BUTTON_COLOR,
		"이동력이 비용보다 적으면 턴 종료를 강조함(#560)")
	standing.movement_left = stand_cost
	battle.call("_update_turn_ui")
	hud.stand_button.pressed.emit()
	_check(not standing.fallen and standing.movement_left == 0 and not hud.stand_button.visible,
		"남은 이동력이 비용과 같아도 버튼으로 일어나고 버튼이 사라짐")
	standing.movement_left = standing.get_movement()
	actions.apply_status(units[1], units[2], "burn")
	actions.apply_status(units[1], units[2], "burn")
	actions.apply_status(units[0], units[2], "poison")
	hud.show_unit(units[2])
	_check("화상2" in hud.resource_label.get_parsed_text() and "독1" in hud.resource_label.get_parsed_text()
		and "기절" in hud.resource_label.get_parsed_text(),
		"기존 상태 정보에 화상/독 중첩 수를 함께 표시")
	await process_frame
	_check(hud.get_viewport_rect().encloses(hud.resource_label.get_global_rect()),
		"기절/화상/독의 상태 정보를 함께 표시해도 화면 안에 배치")
	units[2].begin_stage(false)
	units[1].aegisal_left = 2
	hud.show_unit(units[1])
	_check("애기살 2발" in hud.resource_label.get_parsed_text(), "애기살 남은 발수를 상태 줄에 표시")
	units[1].aegisal_left = 0
	battle.call("_update_turn_ui")
	# 실제 동작의 판정 로그와 숫자 팝업 연결. 마지막 적이 아닌 대상에 확정 명중.
	var hit_sound: AudioStreamPlayer = (battle.get("sounds") as CombatSounds).player(&"hit_flesh")
	var hit_randomizer: AudioStreamRandomizer = hit_sound.stream as AudioStreamRandomizer
	_check(hit_randomizer != null, "타격음은 갈래 스트림")
	var hit_variants_ok: bool = hit_randomizer != null
	for index: int in range(hit_randomizer.streams_count if hit_randomizer != null else 0):
		var variant: AudioStreamOggVorbis = hit_randomizer.get_stream(index) as AudioStreamOggVorbis
		hit_variants_ok = hit_variants_ok and variant != null and variant.get_length() > 0.0 \
			and variant.get_length() < 0.5 and not variant.loop
	_check(hit_variants_ok, "타격음 갈래는 모두 0.5초 미만의 반복 없는 OGG")
	_check(not hit_sound.autoplay and hit_sound.volume_db == -12.0
		and hit_sound.max_polyphony == 4, "타격음 자동 재생 없음·음량-12dB·동시4개 제한")
	_check(hit_sound.bus == GameSettings.BUS_SFX, "타격음은 SFX 버스로 나감")
	hit_sound.stop()
	# 짧은 타격음이 다음 프레임 전에 끝날 수 있어 피해 신호 시점의 재생을 관찰한다.
	var hit_played: Array[bool] = []
	var record_hit: Callable = func(_target: Object) -> void: hit_played.append(hit_sound.playing)
	actions.damaged.connect(record_hit)
	units[2].is_stunned = false
	units[2].reaction_left = 0
	units[2].hit_points = 12
	ScriptedDice.arrange_turns(turns, units, units)
	turns.select_unit(units[1])
	units[2].cell = Vector2i(5, 8)
	# 불리는 낮은 값 2를 골라 야만인 AC 4에 빗나간다.
	actions.dice = ScriptedDice.new([3, 2], ScriptedDice.attack_sides(units[1], 2))
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
	_check(not _has_feedback(units[1], "공격 %d" % actions.last_attack.total),
		"불리 공격도 공격자 판정 합계 팝업 없음")
	units[1].action_left = 1
	units[2].is_stunned = true
	var advantage_sides: Array[int] = ScriptedDice.attack_sides(units[1], 2) + ScriptedDice.damage_sides(units[1])
	actions.dice = ScriptedDice.new([17, 19, 3], advantage_sides)
	await actions.attack(units[1], units[2])
	_check(hit_played == [true], "실제 피해 신호가 장면의 타격음 재생으로 연결됨")
	actions.damaged.disconnect(record_hit)
	_check(_has_two_dice_log("유리"),
		"유리 판정은 로그에 주사위 두 값을 모두 표시")
	_check(not _has_feedback(units[1], "공격 %d" % actions.last_attack.total),
		"유리 공격도 공격자 판정 합계 팝업 없음")
	_check(_has_feedback(units[2], str(actions.last_damage)), "명중 팝업은 부호 없는 피해 합계")
	await _test_roll_popups()


func _test_hit_sound_mix() -> void:
	var sound: AudioStreamPlayer = (battle.get("sounds") as CombatSounds).player(&"hit_flesh")
	sound.stop()
	# 반복 재생 중인 환경음이 믹서 출력을 채우지 않게 끈다. 타격음만 잰다.
	(battle.get("sounds") as CombatSounds).stop_ambient()
	var capture: AudioEffectCapture = AudioEffectCapture.new()
	capture.buffer_length = 2.0
	var effect_index: int = AudioServer.get_bus_effect_count(0)
	AudioServer.add_bus_effect(0, capture)
	await create_timer(0.08).timeout
	capture.clear_buffer()
	for index: int in range(6):
		actions.damaged.emit(units[2])
	await create_timer(SoundVariants.longest(sound.stream) * (sound.stream as AudioStreamRandomizer).random_pitch + 0.2).timeout
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
	actions.dice = ScriptedDice.new([5, 2, 3], [10, 4, 4])
	actions.shove(warrior, target)
	_check(_has_feedback(target, "밀치기 성공")
		and not _has_feedback(target, "밀치기 5"),
		"밀치기는 대상 위에 결과만 표시")
	warrior.bonus_action_left = 1
	target.cell = Vector2i(5, 4)
	target.is_stunned = true
	var emitted: Array[String] = []
	var capture: Callable = func(_unit: CombatUnit, text: String) -> void: emitted.append(text)
	actions.feedback.connect(capture)
	actions.shove(warrior, target)
	_check(emitted == ["밀치기 성공"], "기절 대상의 자동 밀치기도 결과만 표시: %s" % str(emitted))
	var potions: Array[String] = warrior.potions.duplicate()
	var hit_points: int = warrior.hit_points
	warrior.bonus_action_left = 1
	warrior.potions.assign(["healing_potion"])
	warrior.hit_points = 1
	_check(actions.use_self(warrior, "potion"), "물약 실행")
	var healed: String = str(warrior.hit_points - 1)
	var heal_popup: Label = null
	for child: Node in warrior.get_parent().get_children():
		if child is Label and child.text == healed and child.get_meta("feedback_unit", 0) == warrior.get_instance_id():
			heal_popup = child
	_check(heal_popup != null and heal_popup.get_theme_color("font_color") == CombatUnit.HEAL_COLOR,
		"회복 팝업은 + 없는 수치를 초록색으로 표시")
	warrior.potions.assign(potions)
	warrior.hit_points = hit_points
	# 아군 전사의 방어막은 피해를 HP보다 먼저 받고 흡수량을 로그에 남긴다.
	target = warrior
	target.cell = Vector2i(4, 4)
	units[3].cell = Vector2i(1, 4)
	units[2].cell = Vector2i(9, 9)
	while turns.current_unit != units[3]:
		turns.end_turn()
	target.is_stunned = false
	target.hit_points = target.get_max_hit_points()
	target.reaction_left = 1
	target.shield_points = 20
	target.shield_turns = CombatActionRules.SHIELD_TURNS
	# 풋내기 궁수 공격 7은 전사 AC 5에 명중하고, 피해는 모두 방어막이 받는다.
	actions.dice = ScriptedDice.new([7, 2], ScriptedDice.attack_sides(units[3]) + ScriptedDice.damage_sides(units[3]))
	await actions.attack(units[3], target)
	var absorbed: int = actions.last_damage
	_check(absorbed > 0 and target.hit_points == target.get_max_hit_points() and target.shield_points == 20 - absorbed
		and "아군 전사 방어막: %d 흡수 · 남은 방어막 %d" % [absorbed, 20 - absorbed] in hud.message_label.text,
		"방어막은 HP보다 먼저 피해를 받고 흡수량을 로그에 표시")
	_check(str(absorbed) in emitted, "방어막이 받은 피해도 피해 팝업 표시: %s" % str(emitted))
	target.clear_unit_effects()
	var popup_rects: Array[Rect2] = []
	await process_frame
	for child: Node in target.get_parent().get_children():
		if child is Label and child.get_meta("feedback_unit", 0) == target.get_instance_id():
			for rect: Rect2 in popup_rects:
				_check(not rect.intersects(child.get_rect()), "같은 유닛의 숫자 팝업은 겹치지 않음")
			popup_rects.append(child.get_rect())
	actions.feedback.disconnect(capture)


func _has_two_dice_log(mode: String) -> bool:
	var marker: String = "): 솜씨 d20 ["
	for line: String in hud.message_label.text.split("\n"):
		if "공격(%s" % mode not in line or marker not in line:
			continue
		var values: PackedStringArray = line.get_slice(marker, 1).get_slice("]", 0).split(", ")
		return values.size() == 2 and values[0].is_valid_int() and values[1].is_valid_int()
	return false


## 공격자의 절대실패면 1이라 AC와 가산에 관계없이 빗나간다.
func _dice_for_miss(attacker: CombatUnit) -> CombatDice:
	return ScriptedDice.new([1], ScriptedDice.attack_sides(attacker))


func _test_layout() -> void:
	# 측정한 가장 긴 로그 줄로 세 줄 모두 줄바꿈한 가장 높은 로그에서도 겹치지 않아야 한다.
	for index: int in range(3):
		hud.add_log("아군 궁수 공격(불리): 솜씨 d20 [16, 1] +0 = 1 / AC 5 · 빗나감(절대실패)")
	# 해상도 ADR(docs/adr/0002-resolution.md)의 검증 창, 넓은 비율 창, 비정수 배율 창.
	for size: Vector2i in [Vector2i(1280, 720), Vector2i(1920, 1080), Vector2i(1440, 900),
		Vector2i(2560, 1600), Vector2i(2560, 1080), Vector2i(1366, 768)]:
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
			var end_turn: Rect2 = hud.end_button.get_global_rect()
			var details: Rect2 = (hud.get_node("UnitDetails") as Control).get_global_rect()
			_check(not skills.intersects(end_turn) and not skills.intersects(details), "스킬과 턴 종료·유닛 정보가 겹치지 않음")
			var combat_log: Rect2 = (hud.get_node("CombatLog") as Control).get_global_rect()
			_check(not combat_log.intersects(skills) and not combat_log.intersects(details)
				and not combat_log.intersects(end_turn) and not end_turn.intersects(details),
				"%s: 전투 로그·턴 종료·스킬·유닛 정보는 서로 겹치지 않음" % size)
			# #618: 맵 중앙 영역 C(#555)는 F(화면 가운데에서 위로 20)를 가운데로 한 128×64다. 어떤 HUD도 C와 겹치지 않는다.
			var center_area: Rect2 = Rect2(area.get_center() - Vector2(0, 20) - Vector2(64, 32), Vector2(128, 64))
			if size == Vector2i(1280, 720):
				_check(center_area == Rect2(256, 128, 128, 64), "640×360의 맵 중앙 영역 C는 (256, 128, 128, 64): %s" % center_area)
			var order_scroll: Rect2 = (hud.get_node("OrderScroll") as Control).get_global_rect()
			var order_divider: Rect2 = (hud.get_node("OrderDivider") as Control).get_global_rect()
			# 바는 C 왼쪽 끝(F.x − 64)까지이고 1 논리px 구분선이 그 끝에 붙는다.
			_check(is_equal_approx(order_divider.end.x, center_area.position.x)
				and is_equal_approx(order_scroll.end.x, order_divider.position.x),
				"%s: 턴 순서 바와 구분선은 C 왼쪽 끝에서 끝남 %s %s / %s" % [size, order_scroll, order_divider, center_area])
			# 일어나기 버튼은 넘어진 아군 차례에만 보이지만 자리는 늘 같다.
			_check(hud.stand_button.get_global_rect().size.y > 0 and hud.stand_button.get_global_rect().end.x > area.size.x * 0.5,
				"%s: 숨긴 일어나기 버튼도 오른쪽 아래 자리를 가짐 %s" % [size, hud.stand_button.get_global_rect()])
			var center_hud: Array[Rect2] = [order_scroll, order_divider, details, combat_log, skills, end_turn,
				hud.preview_label.get_global_rect(), hud.stand_button.get_global_rect()]
			for rect: Rect2 in center_hud:
				_check(not rect.intersects(center_area), "%s %s: HUD가 맵 중앙 영역 C와 겹치지 않음 %s / %s" % [size, kind, rect, center_area])
			# 아래 HUD는 화면 아래 절반 안에 두어 지도 가운데를 가리지 않는다.
			for bottom: Rect2 in [skills, combat_log, end_turn]:
				_check(bottom.position.y >= area.size.y * 0.5, "%s %s: 아래 HUD 높이 제한 %s" % [size, kind, bottom])
			# 행동·보조 행동·반응을 위에서 아래로 한 줄씩 쌓는다. 한 줄은 높이가 같다.
			var rows: Array = (hud.get("_containers") as Array).filter(func(panel: Control) -> bool: return panel.visible)
			# 궁수의 반응 칸은 반사신경 자리라 비어 있어도 보인다(#528).
			_check(rows.size() == 3, "%s: 보이는 컨테이너 수" % kind)
			for index: int in range(1, rows.size()):
				var above: Rect2 = (rows[index - 1] as Control).get_global_rect()
				var below: Rect2 = (rows[index] as Control).get_global_rect()
				# 접힌 줄(#438)은 버튼 줄 하나(34)와 줄 간격(3)만큼 더 높다. 그만큼 빼면 모든 줄의 높이가 같다. 빈 줄도 한 줄 높이다.
				var above_base: float = above.size.y - (maxi(_button_lines(rows[index - 1]), 1) - 1) * 37
				var below_base: float = below.size.y - (maxi(_button_lines(rows[index]), 1) - 1) * 37
				_check(below.position.y >= above.end.y and below_base == above_base,
					"%s %s: 컨테이너 %d는 앞 컨테이너 아래, 접힌 줄 수를 뺀 높이가 같음" % [size, kind, index])
			# 제목 폭을 맞춰 각 줄의 첫 버튼이 같은 세로선에 선다.
			var filled: Array = rows.filter(func(panel: Control) -> bool:
				return panel.get_child(0).get_child(1).get_children().any(func(button: Control) -> bool: return button.visible))
			var first_x: Array = filled.map(func(panel: Control) -> float:
				return (panel.get_child(0).get_child(1).get_children().filter(
					func(button: Control) -> bool: return button.visible)[0] as Control).global_position.x)
			_check(first_x.all(func(x: float) -> bool: return x == first_x[0]), "%s %s: 줄마다 첫 버튼 x 같음 %s" % [size, kind, first_x])
			var badges: Dictionary = hud.get("_badges")
			var costs: Dictionary = hud.get("_costs")
			for action: String in badges:
				var badge: Label = badges[action] as Label
				if badge.is_visible_in_tree():
					_check(badge.size.y <= 15 and not badge.get_global_rect().intersects(
						(costs[action] as Control).get_global_rect()), "크기 변경 후 배지 분리: " + action)
	# 다른 플랫폼의 글꼴이 줄 높이를 늘려도 정보 아래에 공격 예측을 배치한다.
	hud.resource_label.add_theme_constant_override("line_spacing", 6)
	battle.call("preview_enemy", units[2])
	await process_frame
	await process_frame
	_check(not (hud.get_node("UnitDetails/UnitPanel") as Control).get_global_rect().intersects(
		hud.preview_label.get_global_rect()), "줄 높이가 커져도 정보·공격 예측은 겹치지 않음")
	hud.resource_label.remove_theme_constant_override("line_spacing")
	root.size = Vector2i(1280, 720)
	await process_frame
	# 상태 줄과 공격 예측 원인 줄이 모두 길어진 유닛 정보도 가장 높은 로그와 겹치지 않는다.
	# 앞 검사가 적 턴으로 끝나므로 아군 턴으로 돌려야 적 미리보기가 유닛 정보를 바꾼다.
	_reset_units()
	# 상태 줄을 길게 하려고 표식(#528 삭제) 대신 애기살 발수를 둔다.
	units[2].aegisal_left = 12
	units[2].is_stunned = true
	units[2].overloaded = true
	actions.apply_status(units[1], units[2], "burn")
	actions.apply_status(units[0], units[2], "poison")
	_check(battle.call("preview_enemy", units[2]), "긴 유닛 정보 fixture: 아군 턴의 적 미리보기")
	hud.preview_label.text = "명중률 37.5% · 유리\n고지대, 기절한 대상, 애기살, 옆에 적"
	await process_frame
	await process_frame
	_check(hud.unit_label.text == units[2].get_display_name() and "기절" in hud.resource_label.get_parsed_text()
		and "화상1" in hud.resource_label.get_parsed_text() and "독1" in hud.resource_label.get_parsed_text()
		and "과부하" in hud.resource_label.get_parsed_text() and "애기살 12발" in hud.resource_label.get_parsed_text(),
		"긴 유닛 정보 fixture: 대상의 상태 줄 표시: " + hud.resource_label.get_parsed_text().replace("\n", " | "))
	_check(not (hud.get_node("UnitDetails") as Control).get_global_rect().intersects(
		(hud.get_node("CombatLog") as Control).get_global_rect()),
		"긴 상태·공격 예측의 유닛 정보와 가장 높은 로그는 겹치지 않음: %s / %s" % [
			(hud.get_node("UnitDetails") as Control).get_global_rect(), (hud.get_node("CombatLog") as Control).get_global_rect()])
	units[2].status_effects.clear()
	units[2].overloaded = false
	_reset_units()
	await _test_skill_panel_fixed()


# 칸 폭 계산(#554). 기대값은 손으로 센 값이다.
func _test_slot_width() -> void:
	_check(CombatTurnHud.slot_width(200.0, 3) == 52, "들어가면 원래 폭 52")
	_check(CombatTurnHud.slot_width(100.0, 3) == 31, "넘치면 간격 3을 빼고 나눈 폭: 31")
	_check(CombatTurnHud.slot_width(10.0, 5) == 28, "아무리 좁아도 하한 28")
	_check(CombatTurnHud.slot_width(100.0, 0) == 52, "버튼이 없으면 원래 폭")


# 어떤 아군도 한 줄에 SLOT_ROW_MAX개를 넘는 스킬을 갖지 않고, 그 개수는 최소 폭으로 줄에 들어간다(#554).
# 스킬이 늘어 이 검사가 실패하면 패널 배치를 다시 정한다.
func _test_slot_row_max() -> void:
	var room: int = CombatTurnHud.SLOT_MIN * CombatTurnHud.SLOT_ROW_MAX + CombatTurnHud.SLOT_GAP * (CombatTurnHud.SLOT_ROW_MAX - 1)
	for index: int in range(CombatActionRules.GROUPS.size()):
		_check(room <= hud.call("_slot_room", index), "줄 %d: 최소 폭 %d칸이 줄에 들어감 (%d / %.0f)" % [
			index, CombatTurnHud.SLOT_ROW_MAX, room, hud.call("_slot_room", index)])
		for who: CombatUnit in [units[0], units[1]]:
			# 물약류는 가진 종류만 보이므로, 모든 종류를 가졌을 때가 가장 긴 줄이다.
			var count: int = CombatActionRules.GROUPS[index].filter(
				func(action: String) -> bool: return CombatActionRules.belongs_to(who, action)).size()
			_check(count <= CombatTurnHud.SLOT_ROW_MAX, "%s 줄 %d: 스킬 %d개, 한 줄 최대 %d개" % [
				who.get_display_name(), index, count, CombatTurnHud.SLOT_ROW_MAX])


# 스킬 패널은 어떤 아군을 보이든 아군 턴·적 턴 모두 같은 자리에 있고, 넘치는 줄은 한 줄에서 칸 폭만 줄인다(#554).
func _test_skill_panel_fixed() -> void:
	_test_slot_width()
	_test_slot_row_max()
	_reset_units()
	var skills: Control = hud.get_node("Skills") as Control
	var archer: CombatUnit = units[1]
	var warrior: CombatUnit = units[0]
	# 궁수의 보조 행동 줄을 가장 길게 만든다: 물약과 기름병을 가진다.
	archer.potions.assign(["healing_potion", "oil_bottle"])
	for size: Vector2i in [Vector2i(1280, 720), Vector2i(1920, 1080)]:
		root.size = size
		await process_frame
		await process_frame
		var rects: Dictionary[String, Rect2] = {}
		for who: CombatUnit in [warrior, archer]:
			turns.select_unit(who)
			battle.call("_update_turn_ui")
			await process_frame
			await process_frame
			rects["%s 아군 턴" % who.get_display_name()] = skills.get_global_rect()
			# 적 턴: 현재 유닛이 적이고 패널은 마지막 아군의 것을 회색으로 보인다.
			var ally_turn_unit: CombatUnit = turns.current_unit
			turns.current_unit = units[2]
			hud.refresh_actions(actions, "attack", who)
			await process_frame
			await process_frame
			rects["%s 마지막 적 턴" % who.get_display_name()] = skills.get_global_rect()
			turns.current_unit = ally_turn_unit
		var reference: Rect2 = rects.values()[0]
		for label: String in rects:
			_check(rects[label].position == reference.position and rects[label].size == reference.size,
				"%s %s: 스킬 패널 자리·크기 고정 %s / %s" % [size, label, rects[label], reference])
		# 궁수의 보조 행동 줄: 한 줄에 모두 있고 칸 폭만 줄었다.
		turns.select_unit(archer)
		battle.call("_update_turn_ui")
		await process_frame
		await process_frame
		var row: PanelContainer = (hud.get("_containers") as Array)[1] as PanelContainer
		var shown: Array[Button] = []
		for button: Node in row.get_child(0).get_child(1).get_children():
			if (button as Button).visible:
				shown.append(button as Button)
		_check(shown.size() == 8, "%s: 궁수 보조 행동 줄 버튼 8개 fixture: %d" % [size, shown.size()])
		var panel: Rect2 = row.get_global_rect()
		var sizes: Array[Vector2] = []
		for button: Button in shown:
			sizes.append(button.size)
		var fits: bool = true
		for button: Button in shown:
			fits = (fits and button.global_position.y == shown[0].global_position.y
				and button.size.x >= 28.0 and button.size.x < 52.0 and panel.encloses(button.get_global_rect())
				and button.get_theme_constant("icon_max_width") == CombatActionRules.ICON_SIZE)
		_check(fits, "%s: 넘친 줄은 한 줄, 칸 폭 28 이상 52 미만, 아이콘 24 유지 %s" % [size, sizes])
		var costs: Dictionary = hud.get("_costs")
		var badges: Dictionary = hud.get("_badges")
		_check(not (costs["bow_bash"] as Control).visible and (badges["oil_throw"] as Label).visible,
			"%s: 축소한 줄은 하나뿐인 비용 기호를 숨기고 횟수 배지는 보임" % size)
		var rect: Rect2 = skills.get_global_rect()
		_check(hud.get_global_rect().encloses(rect)
			and not rect.intersects((hud.get_node("CombatLog") as Control).get_global_rect())
			and not rect.intersects(hud.end_button.get_global_rect()),
			"%s: 한 줄 고정 스킬 패널은 로그·턴 종료와 겹치지 않음" % size)
		# 가득 차지 않은 줄은 원래 폭이고 비용 기호도 보인다.
		var attack_row: PanelContainer = (hud.get("_containers") as Array)[0] as PanelContainer
		var attack_button: Button = (hud.get("_actions") as Dictionary)["attack"] as Button
		_check(attack_button.size.x == 52.0 and (costs["attack"] as Control).visible,
			"%s: 넘치지 않는 줄은 원래 폭 52와 비용 기호 %s" % [size, attack_button.size])
		_check(attack_row.visible, "%s: 행동 줄 보임" % size)
	archer.potions.clear()
	root.size = Vector2i(1280, 720)
	await process_frame
	_reset_units()
	turns.select_unit(warrior)
	battle.call("_update_turn_ui")
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
	_check(" · 유리\n" in hud.preview_label.text and "기절한 대상" in hud.preview_label.text
		and "고지대" in hud.preview_label.text and "옆에 적" in hud.preview_label.text,
		"고지대·기절 유리 둘이 인접 불리 하나보다 많아 실제 HUD에서 유리와 세 원인을 표시")
	units[3].is_stunned = true
	battle.call("preview_enemy", units[2])
	_check(" · 유리\n" in hud.preview_label.text and "상쇄" not in hud.preview_label.text,
		"고지대·기절 두 유리만 있을 때는 상쇄로 잘못 표시하지 않음")
	actions.grid.heights.clear()


## 환경요소 6장: 물 위 공격자의 명중률 미리보기에 불리와 `물 위: 불리`를 보이고, 고지대와 겹치면 상쇄로 보인다.
func _test_water_guidance() -> void:
	_reset_units()
	turns.select_unit(units[1])
	units[1].cell = Vector2i(4, 4)
	units[2].cell = Vector2i(7, 4)
	units[3].cell = Vector2i(9, 9)
	var saved_water: Array[Vector2i] = actions.grid.water_cells.duplicate()
	actions.grid.water_cells.assign([units[1].cell])
	battle.call("preview_enemy", units[2])
	_check(" · 불리\n" in hud.preview_label.text and "물 위: 불리" in hud.preview_label.text,
		"물 위 궁수의 명중률 미리보기에 불리와 요인 표시: " + hud.preview_label.text)
	actions.grid.heights = {units[1].cell: 2}
	battle.call("preview_enemy", units[2])
	_check("유리/불리 상쇄" in hud.preview_label.text and "고지대" in hud.preview_label.text
		and "물 위: 불리" in hud.preview_label.text, "고지대와 물 위가 겹치면 상쇄와 두 요인: " + hud.preview_label.text)
	actions.grid.heights.clear()
	actions.grid.water_cells.assign(saved_water)


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
	_check("아군은 판정 없이 밀림" in (buttons["shove"] as Button).tooltip_text,
		"밀치기 호버에 아군 무판정 안내")
	units[0].potions.assign(["healing_potion"])
	battle.call("_update_turn_ui")
	await _hover((buttons["potion"] as Button))
	_check((buttons["potion"] as Button).tooltip_text ==
		"회복 물약\nHP 2d4+2 회복.\n최대 HP를 넘지 않습니다.\n지금 사용 불가: HP가 이미 최대\n사거리: 자신\n회복: 2d4+2\n판정: 없음",
		"비활성 물약은 이름·효과·사거리·회복·판정·이유를 표시")
	_test_hover_order_and_colors(buttons)
	var potion_label: RichTextLabel = (hud.get("_tooltip") as Control).get("_label") as RichTextLabel
	_check(potion_label.text == hud.action_tooltip(actions, units[0], "potion"),
		"실제 호버 설명이 HUD가 만든 줄 역할별 색 글을 그린다: " + potion_label.text)
	units[0].potions.assign([])
	for action: String in buttons:
		var icon_button: Button = buttons[action] as Button
		var ally_action: bool = CombatActionRules.belongs_to(units[0], action) or CombatActionRules.belongs_to(units[1], action)
		var icon_text: String = {"reflex": "반", "stealth": "은"}.get(action, "")
		_check(icon_button.text == icon_text and (icon_button.icon != null or not ally_action or action in ["reflex", "stealth"])
			and icon_button.icon == CombatActionRules.icon_of(action)
			and icon_button.accessibility_name == CombatActionRules.NAMES[action],
			"스킬 버튼은 이름 대신 아이콘 표시: " + action)
	_check("사거리: 인접1칸\n피해: 힘 d20\n판정: 힘 d20 +0 대 AC" in (buttons["attack"] as Button).tooltip_text,
		"전사 공격 호버에 사거리·힘 d20 피해·명중굴림 표시")
	units[0].weapon = {"stats": {"attack_bonus": 1, "damage_bonus": 2}}
	battle.call("_update_turn_ui")
	_check("피해: 힘 d20+2\n판정: 힘 d20 +1 대 AC" in (buttons["attack"] as Button).tooltip_text
		and "피해: 힘 d20+2\n판정: 힘 d20 +1 대 AC" in (buttons["opportunity"] as Button).tooltip_text,
		"현재 장비의 피해·공격 가산을 호버에 반영")
	units[0].weapon = {}
	battle.call("_update_turn_ui")
	for title: Label in hud.get("_titles"):
		await _hover(title)
		_check(title.tooltip_text.is_empty() and not (hud.get("_tooltip") as Control).visible,
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
	units[0].refill_turn_resources()
	battle.call("_update_turn_ui")
	_check(titles[0].text == "행동 ●●●" and titles[0].tooltip_text.is_empty(),
		"자원 회복은 같은 개수의 마크를 다시 채움")
	units[0].action_capacity = 1
	units[0].bonus_action_capacity = 1
	units[0].reaction_capacity = 1
	units[0].refill_turn_resources()
	units[0].movement_left = 2
	battle.call("_update_turn_ui")
	var portraits: Dictionary = hud.get("_portraits")
	for unit: CombatUnit in portraits:
		var portrait: Button = portraits[unit] as Button
		_check(portrait.text.split("\n").size() == 2
			and "민첩 d%d" % unit.get_ability_sides(CombatUnit.Ability.AGILITY) in portrait.tooltip_text
			and str(unit.get_initiative()) == portrait.tooltip_text.get_slice(" = ", 1),
			"초상 숫자 제거, 호버에 실제 민첩 주사위와 원본 값 유지")
	await battle.call("_select_move_cell", Vector2i(2, 1))
	var cells: Array[Vector2i] = battle.get("movement_cells")
	_check(cells.has(Vector2i(2, 1)) and not cells.has(units[2].cell)
		and not cells.has(Vector2i(5, 1)) and not cells.has(units[0].cell),
		"이동 가능 범위는 남은 이동·점유 칸·현재 칸을 반영")
	_check(hud.preview_label.text.is_empty() and not hud.preview_label.visible
		and "이동" not in hud.resource_label.get_parsed_text() and units[2].is_previewed,
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
	actions.dice = _dice_for_miss(units[0])
	await _click(point)
	_check(units[0].action_left == 0 and units[0].movement_left == 1 and units[2].hit_points == 12,
		"같은 적 재클릭은 공격만 소비하고 남은 이동 유지")
	battle.call("_update_turn_ui")
	(buttons["holy_veil"] as Button).pressed.emit()
	var details: String = (buttons["holy_veil"] as Button).tooltip_text
	_check("성스러운 장막" in details and "건강 굴림값만큼 방어막" in details
		and units[0].bonus_action_left == 1 and units[0].shield_points == 0,
		"자기 대상 스킬 첫 클릭은 실행하지 않고 이름·효과 유지")
	for unit: CombatUnit in [units[0], units[1]]:
		turns.select_unit(unit)
		battle.call("_update_turn_ui")
		for action: String in CombatActionRules.NAMES:
			var button: Button = buttons[action] as Button
			if not button.visible:
				continue
			var hp: int = unit.hit_points
			var uses: Array[int] = [unit.action_left, unit.bonus_action_left, unit.shield_points]
			await _hover(button)
			_check(_has_tooltip(root, button.tooltip_text),
				"활성·비활성 버튼의 실제 호버 설명: " + action)
			var tooltip: PanelContainer = hud.get("_tooltip") as PanelContainer
			_check(hud.get_global_rect().encloses(tooltip.get_global_rect())
				and not tooltip.get_global_rect().intersects((hud.get_node("Skills") as Control).get_global_rect())
				and not tooltip.get_global_rect().intersects((hud.get_node("CombatLog") as Control).get_global_rect())
				and tooltip.z_index > (hud.get_node("Skills") as Control).z_index,
				"호버 전체 설명은 화면 안에서 스킬 패널·전투 로그를 가리지 않음: " + action)
			_check(_in_left_column(tooltip.get_global_rect(), hud.get_global_rect().size),
				"마우스 호버 설명도 왼쪽 열(최대 폭 240)이고 중앙 영역과 겹치지 않음: %s %s" % [action, tooltip.get_global_rect()])
			_check(button.tooltip_text.begins_with(CombatActionRules.NAMES[action] + "\n"),
				"호버에 동작 이름 유지: " + action)
			var removed_hints: Array[String] = ["비용", "막당 ", "횟수 제한", "\n보유 물약", "오른쪽 기호",
				"위 숫자", "좌클릭", "같은 버튼", "버튼으로 실행", "확인 창", "묻습니다"]
			# 복합 비용 스킬만 함께 소비하는 자원을 호버에 보인다.
			if action in CombatActionRules.EXTRA_COSTS:
				removed_hints.erase("비용")
				_check("\n" + CombatActionRules.cost_text(action) in button.tooltip_text,
					"복합 비용 스킬 호버에 비용 표시: " + action)
			if action in CombatActionRules.USES_PER_COMBAT:
				_check("\n전투마다 1회 · %d회 남음" % CombatActionRules.uses_left(unit, action) in button.tooltip_text,
					"전투마다 횟수 스킬 호버에 남은 횟수 표시: " + action)
			if action == "firework_arrow":
				removed_hints.erase("막당 ")
				_check("\n막당 1회 · %d회 남음" % CombatActionRules.uses_left(unit, action) in button.tooltip_text,
					"막당 횟수 스킬 호버에 남은 횟수 표시: " + action)
			for removed: String in removed_hints:
				_check(removed not in button.tooltip_text, "호버에서 안내 제거: %s / %s" % [action, removed])
			_check(unit.hit_points == hp and [unit.action_left, unit.bonus_action_left, unit.shield_points] == uses,
				"호버는 동작 실행·자원 소비 없음: " + action)
	_check("사거리: 인접1칸\n피해: 힘 d6\n판정: 힘 d6 +0 대 AC, 명중하면 1칸 밀침" in (buttons["bow_bash"] as Button).tooltip_text
		and "사거리: 1~6칸\n피해: 솜씨 d20\n판정: 솜씨 d20 +0 대 AC" in (buttons["attack"] as Button).tooltip_text
		and "판정: 대상의 힘 내성 대 DC 4, 성공하면 버팀" in (buttons["shove"] as Button).tooltip_text,
		"궁수 활 후려치기 호버에 힘 d6과 밀침, 기본 공격 사거리 1~6, 밀치기 호버에 대상의 힘 내성과 DC 표시")
	await _test_focus_tooltips(buttons)
	await _test_tooltip_column(buttons)
	# 비활성 버튼은 비용 소진·횟수 소진·효과 없음의 이유를 호버에 유지한다.
	turns.select_unit(units[0])
	units[0].action_left = 0
	units[0].cross_slash_left = 0
	units[0].potions.assign(["healing_potion"])
	battle.call("_update_turn_ui")
	_check("자원을 이미 씀" in (buttons["attack"] as Button).tooltip_text
		and "이번 전투의 횟수를 모두 씀" in (buttons["cross_slash"] as Button).tooltip_text
		and "HP가 이미 최대" in (buttons["potion"] as Button).tooltip_text,
		"사용 불가 이유는 비활성 버튼 호버에 유지")
	units[0].cross_slash_left = 1
	units[0].potions.assign([])
	units[0].reaction_left = 0
	battle.call("_update_turn_ui")
	_check("자원을 이미 씀" in (buttons["opportunity"] as Button).tooltip_text,
		"반응을 이미 썼으면 이유 표시")
	units[0].reaction_left = 1
	turns.select_unit(units[1])
	turns.end_turn()
	turns.end_turn()
	battle.call("_update_turn_ui")
	_check(not turns.current_unit.is_ally and (buttons["opportunity"] as Button).is_visible_in_tree()
		and "지금 사용 불가" not in (buttons["opportunity"] as Button).tooltip_text,
		"적 턴에도 남은 반응에 아군 자기 턴 제한을 안내하지 않음")
	actions.busy = true
	battle.call("_update_turn_ui")
	_check("지금 사용 불가" not in (buttons["opportunity"] as Button).tooltip_text,
		"적 행동 중의 입력 잠금은 반응 사용을 막지 않음")
	units[0].is_stunned = true
	battle.call("_update_turn_ui")
	_check("기절 상태" in (buttons["opportunity"] as Button).tooltip_text,
		"기절한 전사는 반응을 사용할 수 없는 이유 표시")
	units[0].is_stunned = false
	units[0].hit_points = 0
	battle.call("_update_turn_ui")
	_check("전투 불능" in (buttons["opportunity"] as Button).tooltip_text,
		"전투 불능 전사의 반응에는 사용 불가 이유 표시")
	units[0].hit_points = units[0].get_max_hit_points()
	actions.busy = false
	await _hover(hud.end_button)


# 키보드·컨트롤러 포커스로도 같은 설명이 화면과 HUD 안, 스킬 패널 위에 뜬다.
func _test_focus_tooltips(buttons: Dictionary) -> void:
	var tooltip: PanelContainer = hud.get("_tooltip") as PanelContainer
	var timer: Timer = hud.get("_tooltip").get("_timer") as Timer
	turns.select_unit(units[0])
	battle.call("_update_turn_ui")
	units[0].potions.assign(["healing_potion"])
	battle.call("_update_turn_ui")
	var hovered: Button = buttons["potion"] as Button
	await _hover(hovered)
	hovered.grab_focus()
	_check(tooltip.visible and timer.is_stopped(), "호버 중 같은 버튼이 포커스를 받아도 설명을 다시 기다리지 않음")
	hovered.release_focus()
	await _click(hovered.get_global_rect().get_center())
	_check(hovered.has_focus() and not hovered.has_focus(true),
		"클릭 포커스는 숨긴 포커스라 흰 테두리가 선택 금색 테두리를 덮지 않음")
	hovered.release_focus()
	units[0].potions.clear()
	battle.call("_update_turn_ui")
	for size: Vector2i in [Vector2i(1280, 720), Vector2i(1920, 1080), Vector2i(1440, 900), Vector2i(2560, 1600),
			Vector2i(2560, 1080), Vector2i(1366, 768)]:
		root.size = size
		await process_frame
		await process_frame
		var screen: Rect2 = Rect2(Vector2.ZERO, hud.get_viewport_rect().size)
		for unit: CombatUnit in [units[0], units[1]]:
			turns.select_unit(unit)
			battle.call("_update_turn_ui")
			for action: String in CombatActionRules.NAMES:
				var button: Button = buttons[action] as Button
				if not button.is_visible_in_tree():
					continue
				button.grab_focus()
				await timer.timeout
				await process_frame
				var rect: Rect2 = tooltip.get_global_rect()
				_check(tooltip.visible and _has_tooltip(root, button.tooltip_text)
					and screen.encloses(rect) and hud.get_global_rect().encloses(rect)
					and not rect.intersects((hud.get_node("Skills") as Control).get_global_rect())
					and not rect.intersects((hud.get_node("CombatLog") as Control).get_global_rect()),
					"%s 포커스 호버는 화면·HUD 안, 스킬 패널·전투 로그를 가리지 않음: %s" % [size, action])
				_check(_in_left_column(rect, screen.size) and is_equal_approx(rect.end.y,
					(hud.get_node("Skills") as Control).get_global_rect().position.y - 4.0),
					"%s 포커스 호버는 중앙 영역과 겹치지 않는 왼쪽 열, 아래 끝은 스킬 패널 위 -4: %s %s" % [size, action, rect])
				button.release_focus()
				_check(not tooltip.visible, "포커스를 잃으면 설명 숨김: " + action)
	root.size = Vector2i(1280, 720)
	await process_frame


# 호버 줄 순서와 줄 역할별 색(#620). 쓸 수 없을 때의 이유는 효과 바로 뒤이고 세부(사거리~횟수)는 그 뒤다.
func _test_hover_order_and_colors(buttons: Dictionary) -> void:
	var unusable: String = hud.action_details(actions, units[0], "potion")
	_check(unusable.contains("최대 HP를 넘지 않습니다.\n지금 사용 불가: HP가 이미 최대\n사거리: 자신")
		and unusable.find("지금 사용 불가") < unusable.find("사거리:"),
		"쓸 수 없는 스킬은 사용 불가 이유가 효과 바로 다음 줄: " + unusable)
	var tagged: String = hud.action_tooltip(actions, units[0], "potion")
	_check(tagged.contains("[color=#ebba84]회복 물약[/color]")
		and tagged.contains("[color=#f5ebdb]HP 2d4[color=#70c76d]+2[/color] 회복.\n최대 HP를 넘지 않습니다.[/color]")
		and tagged.contains("[color=#ff8a80]지금 사용 불가: HP가 이미 최대[/color]")
		and tagged.contains("[color=#c5b29f]사거리: 자신\n회복: 2d4[color=#70c76d]+2[/color]\n판정: 없음[/color]"),
		"이름·효과·사용 불가 이유·세부는 역할별 색: " + tagged)
	var probe: RichTextLabel = RichTextLabel.new()
	probe.bbcode_enabled = true
	probe.text = tagged
	_check(probe.get_parsed_text() == CombatActionRules.NAMES["potion"] + "\n" + unusable,
		"태그를 뺀 글은 이름 + 평문 설명과 같다: " + probe.get_parsed_text())
	probe.free()
	units[0].weapon = {"stats": {"attack_bonus": 1, "damage_bonus": 2}}
	_check(hud.action_tooltip(actions, units[0], "attack").contains("d20[color=#70c76d]+2[/color]"),
		"세부 색 안에서도 수치 가감 색(#457)은 남는다")
	units[0].weapon = {}
	var headed: String = HoverTooltip.headed("이름[줄]\n본문 하나\n본문 [둘]")
	_check(headed == "[color=#ebba84]이름[lb]줄][/color]\n[color=#f5ebdb]본문 하나\n본문 [lb]둘][/color]",
		"초상·패시브 설명은 첫 줄 강조·나머지 본문 색, [는 이스케이프: " + headed)


func _hover(control: Control) -> void:
	await process_frame
	await process_frame
	var motion: InputEventMouseMotion = InputEventMouseMotion.new()
	motion.position = root.get_final_transform() * control.get_global_rect().get_center()
	motion.global_position = motion.position
	Input.parse_input_event(motion)
	await create_timer(0.8).timeout


# 초상·패시브 호버도 왼쪽 열에 뜨고, 긴 설명은 폭 240에서 줄바꿈하며 글을 바꾸지 않고, 짧은 설명은 240으로 늘어나지 않는다(#619).
func _test_tooltip_column(buttons: Dictionary) -> void:
	var tooltip: PanelContainer = hud.get("_tooltip") as PanelContainer
	var screen: Vector2 = hud.get_global_rect().size
	turns.select_unit(units[0])
	battle.call("_update_turn_ui")
	var order_bottom: float = (hud.get_node("OrderScroll") as Control).get_global_rect().end.y
	var portraits: Dictionary = hud.get("_portraits")
	for unit: CombatUnit in [units[0], units[2]]:
		var portrait: Button = portraits[unit] as Button
		await _hover(portrait)
		var rect: Rect2 = tooltip.get_global_rect()
		_check(tooltip.visible and _has_tooltip(root, portrait.tooltip_text) and _in_left_column(rect, screen)
			and is_equal_approx(rect.position.y, order_bottom + 4.0),
			"초상 호버 설명은 왼쪽 열에서 위 끝이 턴 순서 바 아래 끝 +4: %s %s" % [unit.get_display_name(), rect])
		_check(((tooltip.get("_label") as RichTextLabel).text) == HoverTooltip.headed(portrait.tooltip_text),
			"초상 호버는 첫 줄 강조·나머지 본문 색: " + unit.get_display_name())
	# moving_shot은 궁수 패시브라 궁수를 고른 뒤 본다. 숨어 있으면 검사를 건너뛰지 않고 실패한다.
	turns.select_unit(units[1])
	battle.call("_update_turn_ui")
	var passive: Button = (hud.get("_passives") as Dictionary)["moving_shot"] as Button
	_check(passive.is_visible_in_tree(), "궁수를 고르면 moving_shot 패시브 칸이 보임")
	await _hover(passive)
	var passive_rect: Rect2 = tooltip.get_global_rect()
	_check(tooltip.visible and _has_tooltip(root, passive.tooltip_text) and _in_left_column(passive_rect, screen)
		and is_equal_approx(passive_rect.end.y, (hud.get_node("Skills") as Control).get_global_rect().position.y - 4.0),
		"패시브 호버 설명도 왼쪽 열에서 아래 끝이 스킬 패널 위 -4: " + str(passive_rect))
	turns.select_unit(units[0])
	battle.call("_update_turn_ui")
	# 가장 긴 아군 스킬 설명은 폭 240에서 줄바꿈하고 글은 그대로다. 한 줄 설명은 240보다 좁다.
	var longest: Button = null
	var shortest: Button = null
	for action: String in CombatActionRules.NAMES:
		var button: Button = buttons[action] as Button
		if not button.is_visible_in_tree():
			continue
		if longest == null or button.tooltip_text.length() > longest.tooltip_text.length():
			longest = button
		if shortest == null or button.tooltip_text.length() < shortest.tooltip_text.length():
			shortest = button
	await _hover(longest)
	var long_rect: Rect2 = tooltip.get_global_rect()
	_check(tooltip.visible and _has_tooltip(root, longest.tooltip_text) and long_rect.size.x <= 240.0 and long_rect.size.x > 200.0,
		"긴 설명은 폭 240 안에서 줄바꿈하고 글은 그대로: " + str(long_rect))
	await _hover(shortest)
	var short_rect: Rect2 = tooltip.get_global_rect()
	_check(tooltip.visible and _has_tooltip(root, shortest.tooltip_text) and short_rect.size.x < long_rect.size.x,
		"짧은 설명은 긴 설명보다 좁음: %s / %s" % [short_rect, long_rect])
	await _hover(hud.end_button)


# 맵 중앙 영역 C(#555): 맵 기준점 F(화면 가운데에서 위로 20)를 가운데로 한 128×64.
func _center_area(screen: Vector2) -> Rect2:
	return Rect2(Vector2(screen.x / 2.0 - 64.0, screen.y / 2.0 - 20.0 - 32.0), Vector2(128, 64))


# 호버 설명이 왼쪽 열(x 8, 폭 240 이하)에 있고 중앙 영역과 겹치지 않는지.
func _in_left_column(rect: Rect2, screen: Vector2) -> bool:
	return is_equal_approx(rect.position.x, 8.0) and rect.size.x <= 240.0 \
		and not rect.intersects(_center_area(screen))


func _has_tooltip(node: Node, text: String) -> bool:
	if node is Label and node.text == text and node.is_visible_in_tree():
		return true
	# 호버 설명은 수치 색을 위해 RichTextLabel이며, 글자는 태그를 뺀 원문으로 비교한다.
	if node is RichTextLabel and (node as RichTextLabel).get_parsed_text() == text and node.is_visible_in_tree():
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
		_check(units[index].hit_points == ally_hp[index] and units[index].potions.size() == 0,
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
		unit.aegisal_left = 0
		unit.clear_unit_effects()
		CombatActionRules.restore_combat_uses(unit)
	ScriptedDice.arrange_turns(turns, units, units)
	# #624: 카메라가 턴마다 따라가므로 fixture는 카메라를 가운데에 세워 두고 시작한다. 행동 유닛만 따라간 것으로 알린다.
	var camera: CombatCamera = battle.get_node("Camera") as CombatCamera
	camera.follow_turn(turns.current_unit, turns.round_number)
	camera.reset()


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
	_check((battle.get("selection") as CombatSelection).preview_cell == destination and units[0].movement_left == 4
		and not (battle.get("movement_cells") as Array).is_empty(), "첫 우클릭만으로 이동 범위·경로 표시")
	var other: Vector2i = Vector2i(4, 3)
	var other_point: Vector2 = map.get_global_transform_with_canvas() * map.map_to_local(other)
	await _click(other_point, MOUSE_BUTTON_RIGHT)
	_check((battle.get("selection") as CombatSelection).preview_cell == other and units[0].cell == Vector2i(4, 4),
		"다른 칸 우클릭은 이동하지 않고 목적지 변경")
	await _click(other_point)
	_check(units[0].movement_left == 4 and ((battle.get("selection") as CombatSelection).preview_path as Array).is_empty(),
		"이동 미리보기의 좌클릭은 이동 확정으로 처리하지 않음")
	await _click(point, MOUSE_BUTTON_RIGHT)
	await _click(point, MOUSE_BUTTON_RIGHT)
	_check(units[0].cell == destination and units[0].movement_left == 3 and units[0].action_left == 1,
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
		and "힘 d10" in hud.resource_label.get_parsed_text() and "민첩 d6" in hud.resource_label.get_parsed_text()
		and "솜씨 d4" in hud.resource_label.get_parsed_text() and "지능 d4" in hud.resource_label.get_parsed_text()
		and "의지 d4" in hud.resource_label.get_parsed_text() and "건강 d4" in hud.resource_label.get_parsed_text()
		and "자연" not in hud.resource_label.get_parsed_text() and "정신" not in hud.resource_label.get_parsed_text()
		and "공격 +3" in hud.resource_label.get_parsed_text() and "사거리 1칸" in hud.resource_label.get_parsed_text(),
		"정보 대상·조작 유닛을 구분하고 실제 능력치·공격 수치 표시")
	_check("행동" not in hud.resource_label.get_parsed_text() and "반응" not in hud.resource_label.get_parsed_text()
		and (hud.get("_titles") as Array)[0].text == "행동 ●"
		and (hud.get("_actions") as Dictionary).has("cross_slash"), "적 정보에도 현재 아군 자원 마크 유지")
	battle.call("_update_turn_ui")
	_check(hud.unit_label.text == "풋내기 야만인", "UI 갱신은 초상 정보 조회 유지")
	await _click(enemy_point)
	_check(units[0].action_left == 1 and (battle.get("selection") as CombatSelection).preview_target == units[2],
		"초상 조회 뒤 필드 적 클릭은 새 공격의 첫 미리보기")
	actions.dice = _dice_for_miss(units[0])
	await _click(enemy_point)
	_check(units[0].action_left == 0, "필드 적 두 번째 좌클릭은 공격 확정")
	await _click((portraits[units[1]] as Button).get_global_rect().get_center())
	_check(turns.current_unit == units[1] and units[0].action_left == 0
		and "힘 d6" in hud.resource_label.get_parsed_text() and "사거리 6칸" in hud.resource_label.get_parsed_text(),
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
	_check(turns.current_unit == units[0] and "기절" in hud.resource_label.get_parsed_text(),
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


func _threat_marks() -> Dictionary[Vector2, bool]:
	var marks: Dictionary[Vector2, bool] = {}
	for overlay: Node2D in battle.map._threat_overlays:
		marks[overlay.position] = true
	return marks


func _expected_threat(enemies: Array[CombatUnit]) -> Dictionary[Vector2, bool]:
	var marks: Dictionary[Vector2, bool] = {}
	for enemy: CombatUnit in enemies:
		for cell: Vector2i in actions.threat_cells(enemy):
			marks[battle.map.map_to_local(cell)] = true
	return marks


func _hover_point(point: Vector2) -> void:
	var motion: InputEventMouseMotion = InputEventMouseMotion.new()
	motion.position = root.get_final_transform() * point
	motion.global_position = motion.position
	Input.parse_input_event(motion)
	await process_frame
	await process_frame


func _test_threat_range_input() -> void:
	_reset_units()
	units[0].cell = Vector2i(4, 9)
	units[1].cell = Vector2i(5, 9)
	units[2].cell = Vector2i(4, 2)
	units[3].cell = Vector2i(8, 2)
	turns.select_unit(units[0])
	battle.call("_update_turn_ui")
	await process_frame
	var enemies: Array[CombatUnit] = [units[2], units[3]]
	_check(not battle.threat_visible and battle.map._threat_overlays.is_empty(), "위협 범위는 기본으로 꺼져 있음")
	var action_before: String = (battle.get("selection") as CombatSelection).selected_action
	var current_before: CombatUnit = turns.current_unit
	await _key(KEY_T)
	var both: Dictionary[Vector2, bool] = _expected_threat(enemies)
	_check(battle.threat_visible and not both.is_empty() and _threat_marks() == both,
		"T로 켜면 보이는 적 전체의 위협 범위가 겹쳐 보임")
	_check(turns.current_unit == current_before and (battle.get("selection") as CombatSelection).selected_action == action_before,
		"T는 선택 동작과 현재 턴을 바꾸지 않음")
	await _key(KEY_T)
	_check(not battle.threat_visible and battle.map._threat_overlays.is_empty(), "T를 다시 누르면 꺼짐")
	await _hover_point(units[2].get_global_transform_with_canvas() * Vector2(0, -10))
	var only_first: Dictionary[Vector2, bool] = _expected_threat([units[2]])
	_check(not battle.threat_visible and _threat_marks() == only_first and only_first.size() < both.size(),
		"꺼진 상태에서도 적 몸통에 마우스를 올리면 그 적의 범위만 보임")
	await _key(KEY_T)
	_check(_threat_marks() == only_first, "켠 채로 적에 올리면 그 적의 범위만 보임")
	await _hover_point(Vector2(-4000, -4000))
	_check(_threat_marks() == both, "마우스가 적에서 떠나면 전체 범위로 돌아감")
	hud.unit_hovered.emit(units[3])
	_check(_threat_marks() == _expected_threat([units[3]]), "턴 순서 초상 위에 올리면 그 적의 범위만 보임")
	hud.unit_hovered.emit(null)
	_check(_threat_marks() == both, "초상에서 떠나면 전체 범위로 돌아감")
	hud.unit_hovered.emit(units[3])
	hud.call("_build_portraits", turns)
	_check(_threat_marks() == both, "초상 버튼을 다시 만들면 낡은 초상 호버는 풀림")
	hud.unit_hovered.emit(units[0])
	_check(_threat_marks() == both, "아군 초상을 올려도 위협 표시는 바뀌지 않음")
	units[3].hit_points = 0
	battle.call("_update_turn_ui")
	_check(_threat_marks() == _expected_threat([units[2]]), "쓰러진 적의 위협은 사라짐")
	units[3].hit_points = units[3].get_max_hit_points()
	battle.preparation.visible = true
	await _key(KEY_T)
	_check(battle.threat_visible, "정비 화면에서는 T를 무시")
	battle.preparation.visible = false
	await _key(KEY_T)
	_check(not battle.threat_visible and battle.map._threat_overlays.is_empty(), "정비 화면을 닫고 T로 끔")
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
		and units[0].movement_left == 2 and units[0].action_left == 0,
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
	ScriptedDice.arrange_turns(turns, units, desired)
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
		and turns.current_unit == units[1] and units[0].action_left == 1,
		"경계 묶음의 미시작 유닛은 직전 확정 때 채운 자원을 유지하고 모래시계 표시")
	await process_frame
	_check(warrior.global_position.x < archer.global_position.x,
		"경계의 앞 초상은 기존 위치에서 합쳐지는 중간 위치를 표시")
	await create_timer(0.4).timeout
	_check(warrior.global_position.x > archer.global_position.x
		and not warrior.get_global_rect().intersects(archer.get_global_rect()),
		"1초 미만에 경계 초상이 묶음 뒤로 이동하고 겹침 없이 종료")
	await _tab()
	_check(turns.current_unit == units[0] and units[0].movement_left == 4
		and units[0].action_left == 1 and pending != null and not pending.visible,
		"Tab 첫 조작에서 턴을 시작하고 모래시계 제거")
	units[0].spend_resource(CombatUnit.TurnResource.ACTION)
	turns.end_turn()
	await _tab()
	_check(turns.current_unit == units[0] and units[0].action_left == 0
		and pending != null and not pending.visible, "결합 묶음의 종료 취소는 턴을 다시 시작하지 않음")
	_reset_units()


func _test_incapacitated_portrait_join() -> void:
	# 짧은 이동 중 입력 접점을 느린 검사 시계로 고정한다.
	var time_scale: float = Engine.time_scale
	Engine.time_scale = 0.1
	_reset_units()
	var desired: Array[CombatUnit] = [units[0], units[2], units[1], units[3]]
	ScriptedDice.arrange_turns(turns, units, desired)
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
		and units[0].movement_left == 2 and units[0].action_left == 0,
		"합류 이동 중 초상을 선택해도 첫 턴만 시작하고 동료 자원을 회복하지 않음")
	await create_timer(0.2).timeout
	_check(start <= before + 1.0 and start > middle and middle > archer.global_position.x
		and archer.get_parent() == (portraits[units[0]] as Button).get_parent()
		and not archer.get_global_rect().intersects((portraits[units[0]] as Button).get_global_rect()),
		"남은 초상은 즉시 새 위치로 뛰지 않고 0.25초 동안 합쳐져 겹침 없이 종료")
	units[2].show()
	Engine.time_scale = time_scale
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
	ScriptedDice.arrange_turns(turns, units, desired)
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


func _test_boundary_incapacitated_portrait_join() -> void:
	_reset_units()
	var desired: Array[CombatUnit] = [units[0], units[2], units[1], units[3]]
	ScriptedDice.arrange_turns(turns, units, desired)
	turns.end_turn()
	turns.end_turn()
	await process_frame
	await process_frame
	actions.incapacitate(units[3])
	_check(turns.current_unit == units[1] and turns.get_current_group() == [units[1], units[0]],
		"마지막 적의 전투 불능은 라운드 경계의 앞 아군을 현재 묶음 뒤에 즉시 합류시킴")
	await process_frame
	await process_frame
	var archer: Button = (hud.get("_portraits") as Dictionary)[units[1]]
	var start: float = archer.global_position.x
	await create_timer(0.1).timeout
	var middle: float = archer.global_position.x
	await create_timer(0.2).timeout
	_check(start > middle and middle > archer.global_position.x,
		"경계의 앞 아군 위치가 먼저 예약돼도 다른 생존 초상도 기존 표시 위치에서 이동함")
	units[3].show()
	_reset_units()


func _test_skill_bar_keys() -> void:
	_reset_units()
	units[0].potions.assign(["healing_potion"])
	turns.select_unit(units[0])
	battle.call("_update_turn_ui")
	root.gui_release_focus()
	var selection: CombatSelection = battle.get("selection") as CombatSelection
	var tooltip: PanelContainer = hud.get("_tooltip") as PanelContainer
	var timer: Timer = hud.get("_tooltip").get("_timer") as Timer
	var slots: Array[Button] = hud.get("_action_slots")
	var by_button: Dictionary[Button, String] = {}
	var expected: Array[Button] = []
	for action: String in CombatActionRules.NAMES:
		by_button[hud.get("_actions")[action]] = action
	for group: Array in CombatActionRules.GROUPS:
		for action: String in group:
			var button: Button = hud.get("_actions")[action]
			if button.is_visible_in_tree():
				expected.append(button)
	_check(slots == expected, "숫자 키 순서는 보이는 스킬 버튼의 왼쪽부터")
	_check(slots.map(func(button: Button) -> String: return by_button[button]) == ["attack", "sweep", "cross_slash", "battle_cry",
		"holy_veil", "steel_charge", "shove", "jump", "potion", "opportunity", "counter"], "전사 숫자 키 순서는 행동·보조 행동·반응 묶음 순")
	var disabled_seen: int = 0
	var pressed_seen: int = 0
	# 숫자 키는 1~9뿐이다. 전사의 열 번째·열한 번째 버튼(기회 공격, 반격)은 방향키·D-pad로만 간다.
	for slot: int in range(mini(slots.size(), 9)):
		var button: Button = slots[slot]
		var action: String = by_button[button]
		var before: String = selection.selected_action
		await _key(KEY_1 + slot)
		# 포커스가 옮겨지지 않으면 설명 타이머가 돌지 않아 기다리지 않는다.
		if button.has_focus():
			await timer.timeout
			await process_frame
		_check(button.has_focus(true) and tooltip.visible and _has_tooltip(root, button.tooltip_text),
			"숫자 키 %d는 %s에 보이는 포커스와 상세 설명을 줌" % [slot + 1, action])
		var reaction: bool = action in CombatActionRules.GROUPS[2]
		if button.disabled:
			disabled_seen += 1
			_check("지금 사용 불가" in button.tooltip_text and selection.selected_action == before,
				"비활성 버튼은 이유만 보이고 선택하지 않음: " + action)
		elif not reaction:
			pressed_seen += 1
			_check(selection.selected_action == action, "숫자 키는 활성 버튼을 선택: " + action)
		selection.selected_action = "attack"
		battle.call("_update_turn_ui")
	_check(disabled_seen > 0 and pressed_seen > 1, "숫자 키 검사는 활성·비활성 버튼을 모두 포함")
	# AZERTY의 숫자 1 자리는 &를 보낸다. 자리로 고른다.
	await _key(KEY_AMPERSAND, KEY_1)
	_check(slots[0].has_focus(true), "숫자 키는 자판 배열과 관계없이 윗줄 자리로 고름")
	if slots.size() < 9:
		await _key(KEY_1 + slots.size())
		_check(slots[0].has_focus(), "빈 숫자 키는 포커스를 옮기지 않음")
	var jump: Button = hud.get("_actions")["jump"]
	var potion: Button = hud.get("_actions")["potion"]
	_check(potion in slots and potion.disabled and jump in slots and not jump.disabled,
		"입력 fixture: 물약은 비활성, 점프는 활성")
	slots[0].grab_focus()
	await _key(KEY_RIGHT)
	_check(slots[1].has_focus(), "오른쪽 방향키는 다음 스킬 버튼으로 이동")
	await _key(KEY_LEFT)
	await _key(KEY_LEFT)
	_check(slots[0].has_focus(), "왼쪽 방향키는 첫 버튼에서 멈춤")
	slots.back().grab_focus()
	await _joypad(JOY_BUTTON_DPAD_RIGHT)
	_check(slots.back().has_focus(), "D-pad 오른쪽은 마지막 버튼에서 멈춤")
	await _joypad(JOY_BUTTON_DPAD_LEFT)
	_check(slots[slots.size() - 2].has_focus(), "D-pad 왼쪽도 스킬 바 안에서 이동")
	jump.grab_focus()
	await _key(KEY_ENTER)
	_check(selection.selected_action == "jump", "Enter는 포커스된 스킬을 선택")
	selection.selected_action = "attack"
	await _joypad(JOY_BUTTON_A)
	_check(selection.selected_action == "jump", "컨트롤러 확인 버튼은 포커스된 스킬을 선택")
	selection.selected_action = "attack"
	potion.grab_focus()
	await _key(KEY_ENTER)
	await _joypad(JOY_BUTTON_A)
	_check(selection.selected_action == "attack", "비활성 버튼은 Enter·확인 버튼으로 선택되지 않음")
	jump.grab_focus()
	await _key(KEY_SPACE)
	_check(selection.selected_action == "attack", "Space는 포커스된 스킬을 누르지 않음")
	# Esc는 일시정지 메뉴를 연다(#286). 다시 누르면 닫는다.
	await _key(KEY_ESCAPE)
	var pause_menu: PauseMenu = battle.get("pause_menu") as PauseMenu
	_check(pause_menu.visible and paused, "Esc는 일시정지 메뉴를 엶")
	await _key(KEY_ESCAPE)
	_check(not pause_menu.visible and not paused and selection.selected_action == "attack"
		and turns.current_unit == units[0], "Esc는 스킬 선택과 조작 유닛을 바꾸지 않음")
	await _tab()
	_check(turns.current_unit == units[1], "스킬 버튼 포커스 중에도 Tab은 아군 전환")
	await _tab()
	root.gui_release_focus()
	await _key(KEY_RIGHT)
	_check(slots[0].has_focus(true) and selection.selected_action == "attack",
		"포커스가 없으면 방향키는 첫 스킬 버튼에 포커스만 줌")
	root.gui_release_focus()
	await _joypad(JOY_BUTTON_DPAD_LEFT)
	_check(slots[0].has_focus(true), "포커스가 없으면 D-pad도 스킬 바로 진입")
	var lock: Callable = func(state: String, locked: bool) -> void:
		match state:
			"reaction":
				if locked:
					hud.reaction_dialog.popup_centered()
				else:
					hud.reaction_dialog.hide()
			"result":
				hud.get_node("Result").visible = locked
			"preparation":
				(battle.get("preparation") as Control).visible = locked
			"busy":
				actions.busy = locked
	for state: String in ["reaction", "result", "preparation", "busy"]:
		root.gui_release_focus()
		lock.call(state, true)
		# 반응 창은 키를 먼저 가져갈 수 있어 잠금 조건도 직접 확인한다.
		_check(not battle.call("_ally_input_open"), "아군 키 입력 잠금: " + state)
		await _key(KEY_3)
		await _key(KEY_RIGHT)
		_check(root.gui_get_focus_owner() == null and selection.selected_action == "attack",
			"잠긴 화면에서 숫자 키·방향키는 스킬을 고르지 않음: " + state)
		lock.call(state, false)
	turns.end_turn()
	turns.end_turn()
	_check(not turns.current_unit.is_ally, "입력 fixture: 적 턴")
	battle.call("_update_turn_ui")
	root.gui_release_focus()
	await _key(KEY_1)
	await _key(KEY_RIGHT)
	_check(root.gui_get_focus_owner() == null and selection.selected_action == "attack",
		"적 턴에 숫자 키·방향키는 스킬을 고르지 않음")
	units[0].potions.clear()
	_reset_units()
	battle.call("_update_turn_ui")


func _key(keycode: Key, physical: Key = keycode) -> void:
	var event: InputEventKey = InputEventKey.new()
	event.keycode = keycode
	event.physical_keycode = physical
	await _press(event)


func _joypad(button: JoyButton) -> void:
	var event: InputEventJoypadButton = InputEventJoypadButton.new()
	event.button_index = button
	await _press(event)


func _press(event: InputEvent) -> void:
	event.set("pressed", true)
	Input.parse_input_event(event)
	await process_frame
	event = event.duplicate() as InputEvent
	event.set("pressed", false)
	Input.parse_input_event(event)
	await process_frame


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
	# #618: 바가 F.x − 65에서 끝나 640 폭에서는 초상 4개가 바를 채운다. 빈 영역이 생기는 넓은 창(논리 폭 1147)에서 검사한다.
	root.size = Vector2i(3440, 1080)
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
	_check(turns.current_unit == units[1] and units[0].movement_left == 3,
		"빈 영역을 통과시켜도 자식 초상 클릭은 조작 전환만 수행")
	destination = Vector2i(1, 0)
	point = Vector2(80, 140)
	# #624: 초상으로 바뀐 행동 유닛을 카메라가 따라가는 중이라, 손 조작으로 멈춘 뒤 화면 원점을 직접 놓는다.
	camera.pan(Vector2.ZERO)
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
	root.size = Vector2i(1280, 720)
	await process_frame


func _test_transparent_order_input() -> void:
	for window_size: Vector2i in [Vector2i(1280, 720), Vector2i(1280, 800), Vector2i(1920, 1080)]:
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
		actions.dice = ScriptedDice.new([15, 2], ScriptedDice.attack_sides(units[0]) + ScriptedDice.damage_sides(units[0]))
		await _click(enemy_point)
		_check(units[0].action_left == 0 and units[2].hit_points == 10,
			"상단 유닛 몸통 두 번째 클릭은 공격 확정: %s" % window_size)
	root.size = Vector2i(1280, 720)
	_reset_units()
	battle.call("_update_turn_ui")
	await process_frame
	await process_frame


## #393: 확대·이동 뒤에도 클릭·미리보기·피해 팝업이 같은 맵 위치에 맞고, 화면 원점은 정수 논리 px에 남는다.
func _test_camera() -> void:
	var camera: CombatCamera = battle.get_node("Camera") as CombatCamera
	var map: TileMapLayer = battle.get_node("Map") as TileMapLayer
	var selection: CombatSelection = battle.get("selection") as CombatSelection
	for window_size: Vector2i in [Vector2i(1280, 720), Vector2i(1440, 900), Vector2i(1920, 1080)]:
		root.size = window_size
		_reset_units()
		units[0].cell = Vector2i(4, 4)
		units[1].cell = Vector2i(0, 0)
		units[2].cell = Vector2i(6, 3)
		units[3].cell = Vector2i(9, 9)
		units[2].reaction_left = 0
		battle.call("_update_turn_ui")
		camera.reset()
		await process_frame
		var home: Vector2 = camera.position
		var cell_point: Callable = func(cell: Vector2i) -> Vector2:
			return map.get_global_transform_with_canvas() * map.map_to_local(cell)
		# #618: 처음 화면과 C 되돌리기는 맵 가운데를 기준점 F(화면 가운데에서 위로 20)에 둔다.
		var map_center: Callable = func() -> Vector2:
			var last: Vector2 = Vector2(map.get_used_rect().size - Vector2i.ONE)
			var origin: Vector2 = map.map_to_local(Vector2i.ZERO)
			var point: Vector2 = origin + (map.map_to_local(Vector2i.RIGHT) - origin) * last.x / 2.0 \
				+ (map.map_to_local(Vector2i.DOWN) - origin) * last.y / 2.0
			return map.get_global_transform_with_canvas() * point
		var focus: Vector2 = root.get_visible_rect().size / 2.0 - Vector2(0, 20)
		_check((map_center.call() as Vector2).distance_to(focus) <= 1.0,
			"처음 화면은 맵 가운데를 기준점 F(화면 가운데에서 위로 20)에 둠: %s / %s" % [map_center.call(), focus])
		var anchor: Vector2 = cell_point.call(Vector2i(5, 4))
		var portraits: Dictionary = hud.get("_portraits")
		await _wheel((portraits[units[0]] as Button).get_global_rect().get_center(), MOUSE_BUTTON_WHEEL_UP)
		await _wheel((hud.get_node("CombatLog") as Control).get_global_rect().get_center(), MOUSE_BUTTON_WHEEL_UP)
		_check(camera.zoom == Vector2.ONE, "턴 순서 바 초상·전투 로그 위의 휠은 맵을 확대하지 않음: %s" % window_size)
		var hud_rects: Array = ["OrderScroll", "UnitDetails", "CombatLog", "Skills", "EndTurn"].map(
			func(path: String) -> Rect2: return (hud.get_node(path) as Control).get_global_rect())
		await _wheel(anchor, MOUSE_BUTTON_WHEEL_UP)
		_check(camera.zoom == Vector2(2, 2) and (cell_point.call(Vector2i(5, 4)) as Vector2).distance_to(anchor) <= 1.0
			and _camera_snapped(camera), "휠 위는 포인터 아래 칸을 그대로 둔 채 2배: %s" % window_size)
		await _wheel(anchor, MOUSE_BUTTON_WHEEL_UP)
		_check(camera.zoom == Vector2(2, 2), "2배보다 더 확대하지 않음: %s" % window_size)
		var delta: Vector2 = Vector2(13.5, -7.25)
		await _drag(anchor, delta)
		_check((cell_point.call(Vector2i(5, 4)) as Vector2).distance_to(anchor + delta) <= 1.0 and _camera_snapped(camera),
			"가운데 버튼 드래그는 맵을 포인터와 함께 옮기고 원점을 정수 px에 맞춤: %s" % window_size)
		var destination: Vector2i = Vector2i(4, 5)
		await _click(cell_point.call(destination), MOUSE_BUTTON_RIGHT)
		_check(selection.preview_cell == destination and units[0].cell == Vector2i(4, 4),
			"확대·이동 뒤 우클릭은 포인터 아래 칸의 이동 미리보기: %s" % window_size)
		var enemy_point: Vector2 = units[2].get_global_transform_with_canvas() * Vector2(0, -10)
		await _click(enemy_point)
		_check(selection.preview_target == units[2] and units[2].is_previewed,
			"확대·이동 뒤 적 몸통 좌클릭은 공격 미리보기: %s" % window_size)
		var saved_props: Array[CombatGrid.Prop] = actions.grid.props.duplicate()
		actions.grid.props.clear()
		var crate: CombatGrid.Prop = actions.create_prop(Vector2i(3, 5), "crate")
		battle.call("_on_action_selected", "attack")
		await _click(map.get_global_transform_with_canvas() * (map.map_to_surface(crate.cell) + Vector2(0, -8)))
		_check(selection.preview_prop == crate and crate.hit_points == 6,
			"확대·이동 뒤 상자 몸통 좌클릭은 상자 미리보기: %s" % window_size)
		actions.grid.props.clear()
		var rock: CombatGrid.Prop = actions.create_prop(Vector2i(3, 5), "rock")
		battle.call("_update_turn_ui")
		await _click(map.get_global_transform_with_canvas() * (map.map_to_surface(rock.cell) + Vector2(0, -8)))
		_check(selection.preview_prop == rock and rock.cell == Vector2i(3, 5),
			"확대·이동 뒤 바위 몸통 좌클릭은 바위 미리보기: %s" % window_size)
		_check(["OrderScroll", "UnitDetails", "CombatLog", "Skills", "EndTurn"].map(
			func(path: String) -> Rect2: return (hud.get_node(path) as Control).get_global_rect()) == hud_rects,
			"확대·이동해도 HUD는 같은 화면 자리: %s" % window_size)
		actions.grid.props.assign(saved_props)
		selection.clear_preview()
		await _click(enemy_point)
		units[2].show_feedback("-3", hud.feedback_obstacles())
		var popup: Label = units[2].get_parent().get_child(-1) as Label
		var popup_rect: Rect2 = popup.get_global_transform_with_canvas() * Rect2(Vector2.ZERO, popup.size)
		_check(popup_rect.size.y >= 2.0 * popup.size.y - 1.0 and popup_rect.get_center().distance_to(enemy_point) <= 64.0,
			"피해 팝업은 확대한 맵의 대상 위에 2배로 뜸: %s" % window_size)
		popup.free()
		var before: Vector2 = cell_point.call(Vector2i(5, 4))
		var panel: Vector2 = (hud.get_node("UnitDetails") as Control).get_global_rect().get_center()
		await _drag(anchor, panel - anchor)
		_check((cell_point.call(Vector2i(5, 4)) as Vector2).distance_to(before) > 100.0,
			"HUD 위로 끌어 놓아도 드래그가 이어짐: %s" % window_size)
		await _drag(anchor, Vector2(4000, 3000))
		var visible: Rect2 = root.get_visible_rect()
		_check(_camera_snapped(camera) and map.get_used_cells().any(func(cell: Vector2i) -> bool:
			return visible.has_point(cell_point.call(cell))), "맵을 멀리 끌어도 칸이 화면에 남음: %s" % window_size)
		await _key(KEY_C)
		_check(camera.zoom == Vector2.ONE and camera.position == home, "C는 1배 가운데로 되돌림: %s" % window_size)
		_check((map_center.call() as Vector2).distance_to(focus) <= 1.0,
			"C로 되돌린 맵 가운데는 기준점 F에 옴: %s" % window_size)
		await _wheel(anchor, MOUSE_BUTTON_WHEEL_DOWN)
		_check(camera.zoom == Vector2.ONE and camera.position == home, "1배보다 축소하지 않음: %s" % window_size)
		var gesture: InputEventPanGesture = InputEventPanGesture.new()
		gesture.position = root.get_final_transform() * anchor
		gesture.delta = Vector2(1, 0)
		# Godot 4.7.2의 Input.parse_input_event는 제스처를 두 번 보낸다. 창 입력 경로(push_input)로 한 번만 넣는다.
		root.push_input(gesture)
		await process_frame
		_check(camera.position.is_equal_approx(home + Vector2(CombatCamera.PAN_GESTURE_SPEED, 0)),
			"트랙패드 두 손가락 이동: %s" % window_size)
		var magnify: InputEventMagnifyGesture = InputEventMagnifyGesture.new()
		magnify.position = gesture.position
		magnify.factor = 1.15
		root.push_input(magnify)
		await process_frame
		_check(camera.zoom == Vector2.ONE, "집기 배율이 덜 쌓이면 그대로: %s" % window_size)
		root.push_input(magnify)
		await process_frame
		_check(camera.zoom == Vector2(2, 2), "집기 배율이 1.25배 쌓이면 2배: %s" % window_size)
		var over_hud: InputEventPanGesture = gesture.duplicate() as InputEventPanGesture
		over_hud.position = root.get_final_transform() * (hud.get_node("CombatLog") as Control).get_global_rect().get_center()
		var zoomed: Vector2 = camera.position
		# 제스처에는 포인터 이동이 없다. HUD 판정은 마지막 포인터 위치를 따르므로 먼저 로그 위로 옮긴다.
		var hover: InputEventMouseMotion = InputEventMouseMotion.new()
		hover.position = over_hud.position
		hover.global_position = over_hud.position
		root.push_input(hover)
		root.push_input(over_hud)
		await process_frame
		_check(camera.position == zoomed, "전투 로그 위의 트랙패드 이동은 맵을 옮기지 않음: %s" % window_size)
		await _key(KEY_C)
	var start: Vector2 = camera.position
	var key: InputEventKey = InputEventKey.new()
	key.physical_keycode = KEY_D
	key.pressed = true
	Input.parse_input_event(key)
	# 짧은 프레임에서도 반 논리 px 이상 움직이도록 0.1초를 기다린다.
	var pressed_at: int = Time.get_ticks_msec()
	while Time.get_ticks_msec() - pressed_at < 100:
		await process_frame
	key = key.duplicate() as InputEventKey
	key.pressed = false
	Input.parse_input_event(key)
	await process_frame
	_check(camera.position.x > start.x and camera.position.y == start.y and _camera_snapped(camera),
		"D를 누르고 있으면 맵이 오른쪽을 보도록 이동")
	# 2560×1080은 논리 폭이 홀수라 화면 가운데가 0.5 논리 px다.
	root.size = Vector2i(2560, 1080)
	await process_frame
	await process_frame
	_check(_camera_snapped(camera), "창 크기가 바뀌면 화면 원점을 다시 정수 px에 맞춤")
	root.size = Vector2i(1280, 720)
	camera.reset()
	_reset_units()
	battle.call("_update_turn_ui")
	await process_frame


## #393: 2배로 확대·이동해도 가린 유닛의 윤곽은 유닛 그림과 같은 맵 자리에 2배로 그리고, 윤곽 클릭은 앞 바위가 아닌 그 유닛을 고른다.
## HP 막대는 유닛 _draw가 유닛 캔버스에 그리므로 유닛 캔버스가 2배인지로 확인한다(headless에서는 픽셀을 읽지 않는다).
func _test_zoomed_occlusion() -> void:
	var camera: CombatCamera = battle.get_node("Camera") as CombatCamera
	var map: CombatMap = battle.get_node("Map") as CombatMap
	var selection: CombatSelection = battle.get("selection") as CombatSelection
	var enemy: CombatUnit = units[2]
	_reset_units()
	units[0].cell = Vector2i(2, 3)
	units[1].cell = Vector2i(0, 0)
	enemy.cell = Vector2i(5, 3)
	units[3].cell = Vector2i(9, 9)
	root.size = Vector2i(1280, 720)
	var saved_props: Array[CombatGrid.Prop] = actions.grid.props.duplicate()
	var saved_heights: Dictionary = actions.grid.heights.duplicate()
	actions.grid.props.clear()
	# 지형 가림 검사(combat_actions_test)의 바위 배치: 한 칸 높은 앞 칸 위의 바위.
	actions.grid.heights[Vector2i(6, 4)] = 1
	map.build_grid(actions.grid, battle.stages[0].tile_set, battle.stages[0])
	var rock: CombatGrid.Prop = actions.create_prop(Vector2i(6, 4), "rock")
	battle.call("_update_turn_ui")
	camera.reset()
	await process_frame
	var hidden: Vector2 = Vector2.INF
	for y: int in range(-40, 8):
		for x: int in range(-24, 25):
			var point: Vector2 = Vector2(x, y)
			var local: Vector2 = map.to_local(enemy.to_global(point))
			if (hidden == Vector2.INF and enemy.contains_body_point(point) and map.occludes(enemy.cell, local)
					and map.prop_at_point(local) == rock):
				hidden = point
	var silhouette: Sprite2D = enemy.get("_silhouette") as Sprite2D
	var sprite: AnimatedSprite2D = enemy.get("_sprite") as AnimatedSprite2D
	_check(enemy.is_occluded and silhouette.visible and hidden != Vector2.INF,
		"확대 검사 fixture: 바위 뒤 적은 윤곽 표시, 바위 그림이 가린 몸통 점이 있음")
	var anchor: Vector2 = enemy.get_global_transform_with_canvas() * hidden
	await _wheel(anchor, MOUSE_BUTTON_WHEEL_UP)
	await _drag(anchor, Vector2(-37, 21))
	battle.call("_update_turn_ui")
	await process_frame
	var body: Vector2 = enemy.get_global_transform_with_canvas() * hidden
	_check(camera.zoom == Vector2(2, 2) and enemy.is_occluded and silhouette.visible
		and silhouette.get_global_transform_with_canvas().is_equal_approx(sprite.get_global_transform_with_canvas())
		and silhouette.get_global_transform_with_canvas().get_scale().is_equal_approx(sprite.scale * 2.0),
		"2배 확대·이동 뒤에도 가린 유닛 윤곽은 유닛 그림과 같은 자리·같은 2배 크기")
	_check(enemy.get_global_transform_with_canvas().get_scale().is_equal_approx(Vector2(2, 2)),
		"HP 막대를 그리는 유닛 캔버스도 맵과 함께 2배")
	await _click(body)
	_check(selection.preview_target == enemy and selection.preview_prop == null,
		"2배 확대·이동 뒤 가린 윤곽 좌클릭은 바위가 아닌 유닛의 공격 미리보기")
	selection.clear_preview()
	actions.grid.props.assign(saved_props)
	actions.grid.heights = saved_heights
	map.build_grid(actions.grid, battle.stages[0].tile_set, battle.stages[0])
	camera.reset()
	_reset_units()
	battle.call("_update_turn_ui")
	await process_frame


## #393: 적 턴에도 드래그·WASD로 맵을 옮기고 적 턴은 끝까지 진행한다. Space 가속 중에도 WASD는 실제 시간 기준 속도다.
func _test_camera_during_enemy_turn() -> void:
	var camera: CombatCamera = battle.get_node("Camera") as CombatCamera
	var map: TileMapLayer = battle.get_node("Map") as TileMapLayer
	var selection: CombatSelection = battle.get("selection") as CombatSelection
	var saved_dice: CombatDice = actions.dice
	var saved_cells: Array = units.map(func(unit: CombatUnit) -> Vector2i: return unit.cell)
	actions.dice = CombatDice.new()
	actions.dice.seed = 393
	_reset_units()
	# 적이 닿지 못하는 거리라 공격·반응 확인 창 없이 이동만 한다.
	units[0].cell = Vector2i(0, 0)
	units[1].cell = Vector2i(1, 0)
	units[2].cell = Vector2i(9, 9)
	units[3].cell = Vector2i(8, 9)
	battle.call("_update_turn_ui")
	camera.reset()
	turns.end_turn()
	turns.end_turn()
	battle.set_process(true)
	await process_frame
	await process_frame
	_check(battle.get("_enemy_turn_running") and turns.current_unit == units[2], "카메라 검사 fixture: 첫 적의 턴 진행 중")
	var space: InputEventKey = InputEventKey.new()
	space.keycode = KEY_SPACE
	space.physical_keycode = KEY_SPACE
	space.pressed = true
	Input.parse_input_event(space)
	# 첫 적의 턴은 4배 가속에서 실제 약 0.26초라 다른 조작보다 먼저 잰다.
	# 가속이 걸린 다음 프레임부터 D를 눌러 time_scale이 바뀌는 프레임을 재지 않는다.
	await process_frame
	await process_frame
	# #624: 이 검사는 WASD 속도만 잰다. 적 턴이 시작하며 돈 따라가기는 손 조작(C 키)으로 멈추고 가운데에서 잰다.
	camera.reset()
	var start: Vector2 = camera.position
	var key: InputEventKey = InputEventKey.new()
	key.physical_keycode = KEY_D
	key.pressed = true
	Input.parse_input_event(key)
	var pressed_at: int = Time.get_ticks_usec()
	var slowest: float = INF
	# 다음 적으로 넘어가는 프레임은 time_scale이 1이라 첫 적의 턴 안에서만 잰다.
	while Time.get_ticks_usec() - pressed_at < 100000:
		await process_frame
		if turns.current_unit != units[2]:
			break
		slowest = minf(slowest, Engine.time_scale)
	# 뗀 키는 다음 프레임에 반영되어 그 프레임은 움직이지 않으므로 떼기 전까지의 시간으로 잰다.
	var expected: float = CombatCamera.PAN_SPEED * (Time.get_ticks_usec() - pressed_at) / 1000000.0
	key = key.duplicate() as InputEventKey
	key.pressed = false
	Input.parse_input_event(key)
	await process_frame
	space = space.duplicate() as InputEventKey
	space.pressed = false
	Input.parse_input_event(space)
	await process_frame
	var moved: float = camera.position.x - start.x
	_check(slowest != INF and slowest > 1.0, "Space를 누르는 동안 첫 적의 턴 가속: 최소 time_scale %s" % slowest)
	# time_scale에 끌려가면 4배(ENEMY_FAST_SPEED)로 움직인다.
	_check(camera.position.y == start.y and moved >= expected * 0.5 and moved <= expected * 1.5,
		"Space 가속 중에도 WASD는 실제 시간 기준 속도: %.1f px, 기대 %.1f px" % [moved, expected])
	_check(not turns.current_unit.is_ally, "드래그 검사 fixture: 아직 적 차례")
	var anchor: Vector2 = map.get_global_transform_with_canvas() * map.map_to_local(Vector2i(5, 4))
	var delta: Vector2 = Vector2(31, -17)
	await _drag(anchor, delta)
	_check((map.get_global_transform_with_canvas() * map.map_to_local(Vector2i(5, 4))).distance_to(anchor + delta) <= 1.0,
		"적 턴에도 가운데 버튼 드래그로 맵을 옮김")
	var waited: float = 0.0
	while (battle.get("_enemy_turn_running") or not turns.current_unit.is_ally) and waited < 10.0:
		await create_timer(0.05).timeout
		waited += 0.05
	_check(turns.current_unit.is_ally and not battle.get("_enemy_turn_running")
		and units[2].cell != Vector2i(9, 9) and units[3].cell != Vector2i(8, 9)
		and units[0].cell == Vector2i(0, 0) and selection.preview_cell == Vector2i(-1, -1),
		"카메라를 옮겨도 적 턴은 끝까지 진행하고 아군 차례로 돌아옴")
	battle.set_process(false)
	Engine.time_scale = 1.0
	actions.dice = saved_dice
	for index: int in range(units.size()):
		units[index].cell = saved_cells[index]
	camera.reset()
	_reset_units()
	battle.call("_update_turn_ui")
	await process_frame


func _camera_snapped(camera: Camera2D) -> bool:
	var origin: Vector2 = camera.get_canvas_transform().origin
	return origin.is_equal_approx(origin.round())


func _wheel(point: Vector2, button_index: MouseButton) -> void:
	var event: InputEventMouseButton = InputEventMouseButton.new()
	event.position = root.get_final_transform() * point
	event.global_position = event.position
	event.button_index = button_index
	await _press(event)


func _drag(point: Vector2, delta: Vector2) -> void:
	var event: InputEventMouseButton = InputEventMouseButton.new()
	event.position = root.get_final_transform() * point
	event.global_position = event.position
	event.button_index = MOUSE_BUTTON_MIDDLE
	event.pressed = true
	Input.parse_input_event(event)
	await process_frame
	var motion: InputEventMouseMotion = InputEventMouseMotion.new()
	motion.position = root.get_final_transform() * (point + delta)
	motion.global_position = motion.position
	motion.relative = root.get_final_transform().basis_xform(delta)
	motion.button_mask = MOUSE_BUTTON_MASK_MIDDLE
	Input.parse_input_event(motion)
	await process_frame
	event = event.duplicate() as InputEventMouseButton
	event.pressed = false
	event.position = motion.position
	event.global_position = motion.position
	Input.parse_input_event(event)
	await process_frame


## 행동 유닛의 칸 윗면 가운데 점이 화면(논리 px)에서 어디인지.
func _unit_screen_point(unit: CombatUnit) -> Vector2:
	return unit.get_global_transform_with_canvas() * Vector2(0, unit.floor_offset_y)


func _camera_focus_screen() -> Vector2:
	return root.get_visible_rect().size / 2.0 - Vector2(0, 20)


## 전투 시작 전 상태로 돌린 뒤 카메라를 1배 가운데에 두고, 유닛을 놓고, 전투를 시작해 첫 턴의 따라가기를 새로 시작한다.
func _begin_follow_fixture(cells: Array[Vector2i]) -> CombatCamera:
	var camera: CombatCamera = battle.get_node("Camera") as CombatCamera
	_reset_units()
	battle.set("waiting_for_start", true)
	battle.call("_update_turn_ui")
	camera.reset()
	for index: int in range(cells.size()):
		units[index].cell = cells[index]
	# 직접 진행시켜 프레임 시간에 기대지 않는다.
	camera.set_process(false)
	return camera


func _end_follow_fixture() -> void:
	var camera: CombatCamera = battle.get_node("Camera") as CombatCamera
	battle.set("waiting_for_start", false)
	_reset_units()
	units[0].cell = Vector2i(4, 4)
	units[1].cell = Vector2i(0, 0)
	units[2].cell = Vector2i(8, 8)
	units[3].cell = Vector2i(9, 9)
	battle.call("_update_turn_ui")
	camera.set_process(true)
	camera.reset()


## #624: 턴이 시작될 때 행동 유닛이 C 밖이면 카메라가 0.4초 동안 F로 옮긴다. C 안이면 움직이지 않는다.
func _test_camera_follow_turn() -> void:
	var camera: CombatCamera = _begin_follow_fixture([Vector2i(0, 0), Vector2i(4, 4), Vector2i(8, 8), Vector2i(9, 9)])
	var home: Vector2 = camera.position
	var focus: Vector2 = _camera_focus_screen()
	battle.set("waiting_for_start", false)
	battle.call("_update_turn_ui")
	var start: float = _unit_screen_point(units[0]).distance_to(focus)
	_check(start > 32.0 and camera.is_turning(), "첫 행동 유닛이 C 밖이면 따라가기가 시작됨: %s" % start)
	camera.advance(0.2)
	var middle: float = _unit_screen_point(units[0]).distance_to(focus)
	_check(middle > 1.0 and middle < start * 0.5, "0.2초에는 ease-out이라 절반보다 많이 옴: %s / %s" % [middle, start])
	camera.advance(0.2)
	_check(_unit_screen_point(units[0]).distance_to(focus) <= 1.0 and not camera.is_turning(),
		"0.4초 뒤 행동 유닛 칸이 기준점 F에 옴: %s" % _unit_screen_point(units[0]))
	_check(camera.zoom == Vector2.ONE and _camera_snapped(camera), "배율은 그대로이고 화면 원점은 정수 논리 px")
	# 이미 C 안인 유닛으로 넘어가면 움직이지 않는다.
	var settled: Vector2 = camera.position
	camera.reset()
	camera.advance(0.0)
	var centered: Vector2 = camera.position
	var offset: Vector2 = _unit_screen_point(units[1]) - focus
	_check(absf(offset.x) <= CombatCamera.CENTER_SIZE.x / 2.0 and absf(offset.y) <= CombatCamera.CENTER_SIZE.y / 2.0,
		"검사 fixture: 처음 화면에서 다음 유닛 칸이 C 안: %s" % offset)
	_check(turns.select_unit(units[1]), "같은 묶음의 다른 아군을 고를 수 있음")
	battle.call("_update_turn_ui")
	camera.advance(0.5)
	_check(units[1].cell == Vector2i(4, 4) and camera.position == centered and not camera.is_turning() and settled != centered,
		"행동 유닛이 C 안이면 카메라가 움직이지 않음")
	_end_follow_fixture()
	await process_frame


## 따라가기 검사 fixture를 놓고 전투를 시작해 첫 행동 유닛의 따라가기를 돌린다.
func _start_follow(camera: CombatCamera) -> void:
	battle.set("waiting_for_start", false)
	battle.call("_update_turn_ui")


## 이동 연출이 한 칸 도착한 것처럼 유닛을 그 칸에 둔다(Tween 없이 같은 값을 직접 쓴다).
func _walk_to(unit: CombatUnit, cell: Vector2i, body_offset: float = 0.0) -> void:
	var map: CombatMap = battle.map
	unit.is_moving = true
	unit.cell = cell
	unit.position = map.map_to_local(cell)
	unit.floor_offset_y = map.map_to_surface(cell).y - unit.position.y
	unit.body_offset_y = body_offset


func _stop_walking(unit: CombatUnit) -> void:
	unit.is_moving = false
	unit.body_offset_y = 0.0
	battle.call("_update_turn_ui")


## #624: 같은 아군 묶음에서 Tab·초상으로 유닛을 바꾸면 턴 이동이 돈다. 손으로 옮긴 화면에서도 돈다.
func _test_camera_follow_switch() -> void:
	var camera: CombatCamera = _begin_follow_fixture([Vector2i(4, 4), Vector2i(0, 0), Vector2i(8, 8), Vector2i(9, 9)])
	var home: Vector2 = camera.position
	var focus: Vector2 = _camera_focus_screen()
	_start_follow(camera)
	camera.advance(0.5)
	_check(camera.position == home and not camera.is_turning(), "첫 행동 유닛이 C 안이면 카메라가 가만히 있음")
	hud.unit_selected.emit(units[1])
	_check(turns.current_unit == units[1] and camera.is_turning(), "초상으로 C 밖 유닛을 고르면 턴 이동이 시작됨")
	camera.advance(0.4)
	_check(_unit_screen_point(units[1]).distance_to(focus) <= 1.0, "고른 유닛 칸이 기준점 F에 옴")
	camera.pan(Vector2(10, 30))
	_check(_unit_screen_point(units[1]).distance_to(focus) > 5.0, "화면을 손으로 옮김")
	hud.unit_selected.emit(units[0])
	_check(turns.current_unit == units[0] and camera.is_turning(), "손으로 옮긴 화면에서도 유닛을 바꾸면 턴 이동이 돎")
	camera.advance(0.4)
	_check(_unit_screen_point(units[0]).distance_to(focus) <= 1.0, "다시 고른 유닛 칸이 기준점 F에 옴")
	_end_follow_fixture()
	await process_frame


## #624: 드래그·휠·C 키는 진행 중인 턴 이동을 멈추고 그 유닛의 턴 동안 따라잡기를 끈다. 다음 유닛에서는 다시 돈다.
func _test_camera_follow_hand() -> void:
	var focus: Vector2 = _camera_focus_screen()
	for kind: String in ["drag", "wheel", "key"]:
		var camera: CombatCamera = _begin_follow_fixture([Vector2i(0, 0), Vector2i(9, 0), Vector2i(8, 8), Vector2i(9, 9)])
		_start_follow(camera)
		camera.advance(0.1)
		_check(camera.is_turning(), "손 조작 전에는 턴 이동이 진행 중: " + kind)
		match kind:
			"drag":
				await _drag(focus, Vector2(10, 0))
			"wheel":
				await _wheel(focus, MOUSE_BUTTON_WHEEL_UP)
			"key":
				await _key(KEY_C)
		_check(not camera.is_turning(), "손 조작이 진행 중인 턴 이동을 멈춤: " + kind)
		var stopped: Vector2 = camera.position
		camera.advance(0.5)
		_check(camera.position == stopped, "손 조작 뒤 가만히 있음(C 밖이어도 끌려가지 않음): " + kind)
		_walk_to(units[0], Vector2i(0, 3))
		camera.advance(0.3)
		_walk_to(units[0], Vector2i(0, 4))
		camera.advance(0.3)
		_check(camera.position == stopped, "손 조작 뒤 그 유닛이 걸어도 따라잡지 않음: " + kind)
		_stop_walking(units[0])
		# 혼자인 유닛은 다음 순환에도 같은 유닛으로 턴을 받는다. 새 턴이라 따라잡기가 다시 켜진다.
		turns.round_number += 1
		battle.call("_update_turn_ui")
		camera.advance(0.4)
		_walk_to(units[0], Vector2i(0, 9))
		for step: int in range(3):
			camera.advance(0.5)
		_check(_unit_screen_point(units[0]).distance_to(focus) <= 1.0,
			"같은 유닛이 다음 순환에 턴을 받으면 걸을 때 다시 따라잡음: " + kind)
		_stop_walking(units[0])
		turns.round_number -= 1
		hud.unit_selected.emit(units[1])
		_check(turns.current_unit == units[1] and camera.is_turning(), "다음 유닛에서는 다시 턴 이동이 돎: " + kind)
		camera.advance(0.4)
		_check(_unit_screen_point(units[1]).distance_to(focus) <= 1.0 and not camera.is_turning(), "다음 유닛이 F에 옴: " + kind)
		_end_follow_fixture()
		await process_frame


## #624: 걸어서 C 밖으로 나가면 카메라가 따라잡고, 이동이 끝난 뒤 곧 F에 닿는다. 점프 높이는 목표에 넣지 않는다.
func _test_camera_follow_walk() -> void:
	var camera: CombatCamera = _begin_follow_fixture([Vector2i(4, 4), Vector2i(0, 0), Vector2i(8, 0), Vector2i(9, 0)])
	var focus: Vector2 = _camera_focus_screen()
	_start_follow(camera)
	var home: Vector2 = camera.position
	# 점프 높이처럼 그림만 뜬 채 걷는다. 카메라 목표는 칸 윗면 가운데 점이다.
	for cell: Vector2i in [Vector2i(5, 5), Vector2i(6, 6)]:
		_walk_to(units[0], cell, -6.0)
		camera.advance(0.129)
		_check(camera.position == home, "C 안을 걷는 동안 카메라가 가만히 있음: %s" % cell)
	_walk_to(units[0], Vector2i(7, 7), -6.0)
	camera.advance(0.129)
	_check(camera.position != home and not camera.is_turning(), "C 밖으로 나가면 카메라가 따라잡기 시작함")
	_walk_to(units[0], Vector2i(8, 8), -6.0)
	camera.advance(0.129)
	_walk_to(units[0], Vector2i(9, 9), -6.0)
	camera.advance(0.129)
	_check(_unit_screen_point(units[0]).distance_to(focus) > 1.0, "걸음은 카메라를 기다리지 않아 카메라가 조금 뒤에서 따라옴")
	units[0].is_moving = false
	var steps: int = 0
	while steps < 5 and _unit_screen_point(units[0]).distance_to(focus) > 1.0:
		camera.advance(0.1)
		steps += 1
	_check(_unit_screen_point(units[0]).distance_to(focus) <= 1.0 and steps < 5,
		"이동이 끝난 뒤 0.5초 안에 칸 윗면 가운데가 F에 닿음(점프 높이는 목표에 넣지 않음): %d" % steps)
	_check(camera.zoom == Vector2.ONE and _camera_snapped(camera), "따라가는 동안 배율은 그대로이고 화면 원점은 정수 논리 px")
	camera.advance(0.5)
	var settled: Vector2 = camera.position
	camera.advance(0.5)
	_check(camera.position == settled, "F에 닿으면 멈춤")
	_stop_walking(units[0])
	_end_follow_fixture()
	await process_frame


## #624: 턴 이동 도중 행동 유닛이 움직이기 시작하면 턴 이동을 그 자리에서 멈추고 지금 위치에서 유닛을 따라간다.
func _test_camera_follow_takeover() -> void:
	var camera: CombatCamera = _begin_follow_fixture([Vector2i(0, 0), Vector2i(4, 4), Vector2i(8, 8), Vector2i(9, 9)])
	var focus: Vector2 = _camera_focus_screen()
	_start_follow(camera)
	camera.advance(0.1)
	_check(camera.is_turning(), "턴 이동이 진행 중")
	_walk_to(units[0], Vector2i(0, 1))
	camera.advance(0.016)
	_check(not camera.is_turning(), "턴 이동 중 유닛이 움직이기 시작하면 턴 이동이 멈춤")
	units[0].is_moving = false
	camera.advance(0.6)
	# 턴 이동이 처음 목표(옛 칸)로 계속 갔다면 새 칸은 F에서 한 칸 거리만큼 벗어난다.
	_check(_unit_screen_point(units[0]).distance_to(focus) <= 1.0, "넘겨받은 따라잡기가 유닛이 있는 새 칸에서 끝남")
	_stop_walking(units[0])
	_end_follow_fixture()
	await process_frame


## #624: 2배 확대에서도 배율은 그대로이고 유닛이 F에 온다.
func _test_camera_follow_zoomed() -> void:
	root.size = Vector2i(1920, 1080)
	await process_frame
	var camera: CombatCamera = _begin_follow_fixture([Vector2i(0, 0), Vector2i(4, 4), Vector2i(8, 8), Vector2i(9, 9)])
	camera.zoom_at(_camera_focus_screen(), 1)
	_check(camera.zoom == Vector2(2, 2), "검사 fixture: 2배 확대")
	_start_follow(camera)
	_check(camera.is_turning(), "2배에서도 C 밖 유닛이면 턴 이동이 시작됨")
	camera.advance(0.4)
	_check(camera.zoom == Vector2(2, 2) and _unit_screen_point(units[0]).distance_to(_camera_focus_screen()) <= 1.0
		and _camera_snapped(camera), "2배 확대 그대로 유닛이 기준점 F에 옴")
	_end_follow_fixture()
	root.size = Vector2i(1280, 720)
	await process_frame


## #624: 전투 시작 전, 전투가 끝난 뒤, 행동 유닛이 전투 불능일 때는 따라가지 않고 진행 중인 따라가기도 멈춘다.
func _test_camera_follow_idle() -> void:
	var camera: CombatCamera = _begin_follow_fixture([Vector2i(0, 0), Vector2i(4, 4), Vector2i(8, 8), Vector2i(9, 9)])
	var home: Vector2 = camera.position
	battle.call("_update_turn_ui")
	camera.advance(0.5)
	_check(camera.position == home and not camera.is_turning(), "전투 시작 전에는 C 밖 유닛이 있어도 따라가지 않음")
	_start_follow(camera)
	camera.advance(0.1)
	_check(camera.is_turning(), "전투가 시작되면 첫 행동 유닛으로 턴 이동이 돎")
	units[0].hit_points = 0
	battle.call("_update_turn_ui")
	var stopped: Vector2 = camera.position
	_check(not camera.is_turning(), "행동 유닛이 전투 불능이 되면 따라가기가 멈춤")
	camera.advance(0.5)
	_check(camera.position == stopped, "전투 불능 유닛은 따라가지 않음")
	units[0].hit_points = units[0].get_max_hit_points()
	battle.call("_update_turn_ui")
	_check(camera.is_turning(), "다시 살아난 행동 유닛으로 턴 이동이 새로 돎")
	camera.advance(0.4)
	_check(_unit_screen_point(units[0]).distance_to(_camera_focus_screen()) <= 1.0, "다시 살아난 행동 유닛 칸이 F에 옴")
	units[2].hit_points = 0
	units[3].hit_points = 0
	_check(actions.is_over(), "적이 모두 쓰러지면 전투가 끝남")
	# 결과 화면 같은 다른 갱신을 건드리지 않게 따라가기 갱신만 부른다.
	battle.call("_refresh_camera_follow")
	var over: Vector2 = camera.position
	_check(not camera.is_turning(), "전투가 끝나면 따라가기가 멈춤")
	camera.advance(0.5)
	_check(camera.position == over, "전투가 끝나면 따라가지 않음")
	_end_follow_fixture()
	await process_frame


## #624: 실제 적 턴. 적의 첫 이동 전에 카메라가 F에 닿아 있다(4배속도 같다). 적 턴은 끝까지 진행한다.
func _test_camera_follow_enemy_turn(fast: bool) -> void:
	var camera: CombatCamera = battle.get_node("Camera") as CombatCamera
	var saved_dice: CombatDice = actions.dice
	var saved_cells: Array = units.map(func(unit: CombatUnit) -> Vector2i: return unit.cell)
	actions.dice = CombatDice.new()
	actions.dice.seed = 624
	_reset_units()
	# 적이 닿지 못하는 거리라 공격·반응 확인 창 없이 이동만 한다. 첫 적은 C 밖이다.
	units[0].cell = Vector2i(0, 0)
	units[1].cell = Vector2i(1, 0)
	units[2].cell = Vector2i(9, 9)
	units[3].cell = Vector2i(8, 9)
	battle.call("_update_turn_ui")
	camera.reset()
	var space: InputEventKey = InputEventKey.new()
	space.keycode = KEY_SPACE
	space.physical_keycode = KEY_SPACE
	space.pressed = true
	if fast:
		Input.parse_input_event(space)
	turns.end_turn()
	turns.end_turn()
	battle.set_process(true)
	var focus: Vector2 = _camera_focus_screen()
	var gap: float = INF
	var last_gap: float = INF
	var began: int = Time.get_ticks_msec()
	while Time.get_ticks_msec() - began < 10000 and gap == INF:
		await process_frame
		if turns.current_unit != units[2]:
			continue
		if units[2].is_moving:
			# 움직임을 처음 본 프레임은 한 걸음이 더해져 있어, 그 직전 프레임에서 잰다.
			gap = last_gap
		else:
			last_gap = _unit_screen_point(units[2]).distance_to(focus)
	_check(gap <= 1.5, "적이 첫 이동을 시작할 때 카메라가 이미 F에 닿아 있음(%s): %s" % ["4배속" if fast else "보통", gap])
	if fast:
		_check(Engine.time_scale > 1.0, "4배속 검사 fixture: 가속 중")
	began = Time.get_ticks_msec()
	while (battle.get("_enemy_turn_running") or not turns.current_unit.is_ally) and Time.get_ticks_msec() - began < 15000:
		await process_frame
	_check(turns.current_unit.is_ally and not battle.get("_enemy_turn_running") and units[2].cell != Vector2i(9, 9),
		"카메라를 따라 움직여도 적 턴은 끝까지 진행해 아군 차례로 돌아옴")
	if fast:
		space = space.duplicate() as InputEventKey
		space.pressed = false
		Input.parse_input_event(space)
		await process_frame
	battle.set_process(false)
	Engine.time_scale = 1.0
	actions.dice = saved_dice
	for index: int in range(units.size()):
		units[index].cell = saved_cells[index]
	camera.reset()
	_reset_units()
	battle.call("_update_turn_ui")
	await process_frame


## #624: 이어하기로 연 전투는 1배 가운데에서 출발해 행동 유닛으로 턴 이동이 돈다.
func _test_camera_follow_restore() -> void:
	var camera: CombatCamera = battle.get_node("Camera") as CombatCamera
	_reset_units()
	battle.set("waiting_for_start", false)
	units[0].cell = Vector2i(0, 0)
	units[1].cell = Vector2i(1, 0)
	battle.call("_update_turn_ui")
	var state: Dictionary = battle.call("combat_state")
	_check(battle.call("restore_combat", state), "저장한 전투 상태를 다시 읽음")
	battle = current_scene.get_node("Battle") as Node2D
	units = battle.get("units")
	turns = battle.get("turns") as CombatTurns
	actions = battle.get("actions") as CombatActions
	hud = battle.get_node("UI/TurnHud") as CombatTurnHud
	camera = battle.get_node("Camera") as CombatCamera
	camera.set_process(false)
	var focus: Vector2 = _camera_focus_screen()
	_check(camera.is_turning() and _unit_screen_point(turns.current_unit).distance_to(focus) > 32.0,
		"이어하기로 연 전투는 1배 가운데에서 출발해 행동 유닛으로 턴 이동을 시작함")
	camera.advance(0.4)
	_check(_unit_screen_point(turns.current_unit).distance_to(focus) <= 1.0, "이어하기 뒤 행동 유닛이 기준점 F에 옴")
	camera.set_process(true)
	await process_frame


## #503: 실제 1-3(고철로봇-1000)에서 과부하 조건·효과를 켜지기 전부터 읽는다.
func _test_overload_and_water_guidance() -> void:
	root.size = Vector2i(1280, 720)
	var main: Node = (load("res://scenes/game.tscn") as PackedScene).instantiate()
	root.add_child(main)
	current_scene = main
	battle = main.get_node("Battle") as Node2D
	battle.set_process(false)
	battle.call("start_battle")
	(battle.get("progress") as CombatActProgress).stage_index = 2
	battle.call("_start_stage", true)
	battle.call("start_battle")
	units = battle.get("units")
	turns = battle.get("turns") as CombatTurns
	actions = battle.get("actions") as CombatActions
	hud = battle.get_node("UI/TurnHud") as CombatTurnHud
	var robot: CombatUnit = units[2] if units.size() == 3 else null
	_check(robot != null and robot.kind == CombatUnit.Kind.SCRAP_ROBOT_1000 and units[0].kind == CombatUnit.Kind.WARRIOR,
		"#503 전제조건: 1-3은 아군 전사·궁수와 고철로봇-1000")
	if robot == null or robot.kind != CombatUnit.Kind.SCRAP_ROBOT_1000:
		main.queue_free()
		await process_frame
		return
	var order: Array[CombatUnit] = [units[0], units[1], robot]
	ScriptedDice.arrange_turns(turns, units, order)
	battle.call("_update_turn_ui")
	await process_frame
	hud.show_unit(robot)
	_check("상태: 과부하 대기(HP 20 이하)" in hud.resource_label.get_parsed_text(),
		"켜지기 전 로봇 조회의 상태 줄에 과부하 조건")
	robot.hit_points = 20
	hud.show_unit(robot)
	var status: String = hud.resource_label.get_parsed_text()
	_check("상태: 기절 면역" not in status and "과부하, 기절 면역" in status and "과부하 대기" not in status,
		"켜진 뒤 로봇 상태 줄은 지금처럼 과부하")
	# 가장 긴 상태 줄도 상태 사이에서만 줄을 바꾼다(자동 줄바꿈이 `기절 면/역`처럼 단어를 끊지 않음).
	robot.hit_points = robot.get_max_hit_points()
	robot.overloaded = false
	for kind_name: String in ["burn", "poison"]:
		robot.status_effects.append(CombatUnit.StatusEffect.new(kind_name, units[0], 2))
	robot.pull_cooldown = 1
	hud.show_unit(robot)
	await process_frame
	var long_status: String = hud.resource_label.get_parsed_text()
	_check("기절 면역" in long_status and ",\n" in long_status
		and hud.resource_label.get_line_count() == long_status.count("\n") + 1,
		"가장 긴 상태 줄은 상태 사이에서 줄바꿈: " + long_status.replace("\n", " | "))
	robot.status_effects.clear()
	robot.pull_cooldown = 0
	robot.hit_points = 20
	hud.show_unit(units[0])
	_check("상태: 없음" in hud.resource_label.get_parsed_text() and "과부하" not in hud.resource_label.get_parsed_text(),
		"아군 상태 줄에는 과부하 글이 없음")
	robot.hit_points = robot.get_max_hit_points()
	robot.overloaded = false
	battle.call("_update_turn_ui")
	var portraits: Dictionary = hud.get("_portraits")
	var robot_lines: PackedStringArray = (portraits[robot] as Button).tooltip_text.split("\n")
	_check(robot_lines.size() == 7 and robot_lines[0].begins_with("고철로봇-1000: 민첩 d4 = ")
		and robot_lines[1] == "과부하 (꺼짐): HP 20 이하가 되면 켜짐" and robot_lines[2] == "· 턴마다 행동 2"
		and robot_lines[3] == "· 턴 시작에 자기 피해 2"
		and robot_lines[4] == "· 턴 시작에 반경 1(상하좌우, 높이 차 1 이하)의"
		and robot_lines[5] == "  모든 유닛에게 화상 1, 판정 없음"
		and robot_lines[6] == "물 칸에 선 유닛은 화상이 걸리지 않고 해제됨",
		"로봇 초상 호버는 이니셔티브 줄 아래 과부하 조건·효과·물 칸 규칙: " + " | ".join(robot_lines))
	for ally: CombatUnit in [units[0], units[1]]:
		var text: String = (portraits[ally] as Button).tooltip_text
		_check(text.split("\n").size() == 1 and "과부하" not in text and "물 칸" not in text,
			"아군 초상 호버는 이니셔티브 줄 그대로: " + text)
	robot.hit_points = 20
	battle.call("_update_turn_ui")
	_check("\n과부하 (켜짐): HP 20 이하가 되면 켜짐\n" in (portraits[robot] as Button).tooltip_text,
		"켜진 뒤 로봇 초상 호버는 켜짐 표시")
	robot.hit_points = robot.get_max_hit_points()
	robot.overloaded = false
	# 물 칸 규칙은 그 칸에 서기 전, 걷기·점프의 첫 우클릭 미리보기에서 읽는다. 1-3의 물은 (3,10)·(4,10)이다.
	units[0].cell = Vector2i(3, 8)
	units[1].cell = Vector2i(1, 8)
	robot.cell = Vector2i(8, 1)
	battle.call("_update_turn_ui")
	await process_frame
	# #624: 이 검사는 화면 좌표로 칸을 누른다. 따라가기를 손 조작(C 키)으로 멈추고 가운데에 세운다.
	(battle.get_node("Camera") as CombatCamera).reset()
	var map: TileMapLayer = battle.get_node("Map") as TileMapLayer
	var water: Vector2i = Vector2i(3, 10)
	var dry: Vector2i = Vector2i(2, 8)
	var water_point: Vector2 = map.get_global_transform_with_canvas() * map.map_to_local(water)
	var dry_point: Vector2 = map.get_global_transform_with_canvas() * map.map_to_local(dry)
	var selection: CombatSelection = battle.get("selection") as CombatSelection
	var note: String = "물 칸: 화상 해제 · 새 화상 걸리지 않음\n물: 명중굴림 불리"
	_check(water in actions.grid.water_cells and dry not in actions.grid.water_cells, "#503 전제조건: 1-3 물 칸 배치")
	await _click(water_point, MOUSE_BUTTON_RIGHT)
	_check(selection.preview_cell == water and units[0].cell == Vector2i(3, 8)
		and hud.preview_label.visible and hud.preview_label.text == note,
		"물 칸 걷기 첫 우클릭은 이동하지 않고 물 칸 화상 규칙을 보임: " + hud.preview_label.text)
	await _click(dry_point, MOUSE_BUTTON_RIGHT)
	_check(selection.preview_cell == dry and units[0].cell == Vector2i(3, 8) and not hud.preview_label.visible,
		"물이 아닌 칸 걷기 미리보기는 지금처럼 안내를 숨김")
	hud.action_selected.emit("jump")
	await _click(water_point, MOUSE_BUTTON_RIGHT)
	_check(selection.preview_cell == water and units[0].cell == Vector2i(3, 8) and hud.preview_label.visible
		and hud.preview_label.text.begins_with("점프 · 이동 2 · 보조 행동1\n")
		and hud.preview_label.text.ends_with("\n" + note),
		"물 칸 점프 첫 우클릭은 기존 점프 안내 끝에 물 칸 화상 규칙: " + hud.preview_label.text)
	await _click(dry_point, MOUSE_BUTTON_RIGHT)
	_check(selection.preview_cell == dry and hud.preview_label.text.begins_with("점프 · ")
		and "물 칸" not in hud.preview_label.text, "물이 아닌 칸 점프 안내는 그대로: " + hud.preview_label.text)
	(battle.get("sounds") as CombatSounds).stop_all()
	await create_timer(0.08).timeout
	main.queue_free()
	await process_frame


func _test_spawned_portrait_input() -> void:
	root.size = Vector2i(1280, 720)
	var main: Node = (load("res://scenes/game.tscn") as PackedScene).instantiate()
	root.add_child(main)
	current_scene = main
	battle = main.get_node("Battle") as Node2D
	battle.set_process(false)
	battle.call("start_battle")
	(battle.get("progress") as CombatActProgress).stage_index = 6
	battle.call("_start_stage", true)
	battle.call("start_battle")
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
	var initial_fogs: int = units.filter(func(unit: CombatUnit) -> bool:
		return not unit.is_ally and unit.kind == CombatUnit.Kind.FOG_SPIDER).size()
	var initial_ready: bool = (units.size() == 7 and initial_allies == 2
		and initial_spiderlings == 3 and initial_mothers == 1 and initial_fogs == 1
		and units[0].is_ally and units[0].kind == CombatUnit.Kind.WARRIOR
		and units[1].is_ally and units[1].kind == CombatUnit.Kind.ARCHER)
	_check(initial_ready,
		"소환 전제조건: 3-1 아군2·새끼3·엄마거미1·독안개 거미1")
	if not initial_ready:
		main.queue_free()
		await process_frame
		return
	var scroll: ScrollContainer = hud.get_node("OrderScroll") as ScrollContainer
	for size: Vector2i in [Vector2i(1920, 1080), Vector2i(1440, 900), Vector2i(1280, 720)]:
		root.size = size
		await process_frame
		await process_frame
		var visible_bar: Rect2 = scroll.get_global_rect().intersection(hud.order_bar.get_global_rect())
		_check((hud.get("_portraits") as Dictionary).size() == 7 and hud.order_bar.size.x > scroll.size.x
			and scroll.get_h_scroll_bar().is_visible_in_tree() and visible_bar.has_area()
			and not visible_bar.intersects((hud.get_node("UnitDetails") as Control).get_global_rect()),
			"%s: 3-1 시작 초상7개가 넘쳐도 보이는 턴 순서 바는 정보 패널과 겹치지 않고 가로 스크롤" % size)
		# #255: 바와 정보 패널 사이 구분선. 넘친 쪽 끝의 흐림은 엔진 스크롤 힌트가 그린다.
		var divider: Control = hud.get_node("OrderDivider") as Control
		_check(scroll.scroll_hint_mode == ScrollContainer.SCROLL_HINT_MODE_BOTTOM_AND_RIGHT
			and divider.get_global_rect().position.x >= scroll.get_global_rect().end.x
			and divider.get_global_rect().end.x <= (hud.get_node("UnitDetails") as Control).get_global_rect().position.x,
			"%s: 턴 순서 바 오른쪽 끝 흐림과 정보 패널 앞 구분선" % size)
	# 고철로봇의 긴 상태 줄도 정보 패널을 왼쪽으로 넓히지 않고 줄을 바꾼다.
	var status_unit: CombatUnit = units[2]
	var status_kind: CombatUnit.Kind = status_unit.kind
	status_unit.kind = CombatUnit.Kind.SCRAP_ROBOT_3000
	status_unit.overloaded = true
	status_unit.pull_cooldown = 1
	status_unit.aegisal_left = 12
	for stack: int in range(3):
		status_unit.status_effects.append(CombatUnit.StatusEffect.new("burn", status_unit, 2))
		status_unit.status_effects.append(CombatUnit.StatusEffect.new("poison", status_unit, 2))
	hud.show_unit(status_unit)
	await process_frame
	await process_frame
	_check(not scroll.get_global_rect().intersects((hud.get_node("UnitDetails") as Control).get_global_rect())
		and not (hud.get_node("UnitDetails/UnitPanel") as Control).get_global_rect().intersects(
			hud.preview_label.get_global_rect()), "긴 상태 줄도 정보 패널이 턴 순서 바를 가리지 않음")
	status_unit.kind = status_kind
	status_unit.overloaded = false
	status_unit.pull_cooldown = 0
	status_unit.aegisal_left = 0
	status_unit.status_effects.clear()
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
	var spawn_order: Array[CombatUnit] = units.slice(2)
	spawn_order.append_array([units[1], units[0]])
	ScriptedDice.arrange_turns(turns, units, spawn_order)
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
	_check(units.size() == 13 and turns.round_number == 6 and turns.current_unit == units[1],
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
	_check(resources == [CombatUnit.WARRIOR_MOVEMENT, 1, 1, 0,
		CombatUnit.MOVEMENT_PER_TURN, 1, 1, 0],
		"소환 전제조건: 새 라운드의 두 아군 자원은 가득, 적 턴에 쓴 반응은 자기 묶음 확정까지 비어 있음")
	if failures != fixture_failures:
		main.queue_free()
		await process_frame
		return
	# 포인터로 오른쪽 끝까지 이동한 뒤 가려졌던 아군 초상을 선택한다.
	for step: int in range(40):
		await _click(Vector2(80, 50), MOUSE_BUTTON_WHEEL_RIGHT)
	await _click((portraits[units[0]] as Button).get_global_rect().get_center())
	_check(turns.current_unit == units[0] and hud.unit_label.text == "아군 전사",
		"새끼가 누적되어도 오른쪽 아군 초상을 스크롤하고 실제 클릭으로 조작 전환")
	_check(resources == [units[0].movement_left, units[0].action_left, units[0].bonus_action_left,
		units[0].reaction_left, units[1].movement_left, units[1].action_left,
		units[1].bonus_action_left, units[1].reaction_left], "소환 후 아군 초상 전환은 두 아군 턴 자원 보존")
	for step: int in range(40):
		await _click(Vector2(80, 50), MOUSE_BUTTON_WHEEL_LEFT)
	var enemy: CombatUnit = turns.ordered_units.front()
	await _click((portraits[enemy] as Button).get_global_rect().get_center())
	_check(turns.current_unit == units[0] and hud.unit_label.text == enemy.get_display_name(),
		"반대쪽 끝의 적 초상도 스크롤하고 조회하며 아군 조작 유지")
	_check(resources == [units[0].movement_left, units[0].action_left, units[0].bonus_action_left,
		units[0].reaction_left, units[1].movement_left, units[1].action_left,
		units[1].bonus_action_left, units[1].reaction_left], "소환 후 스크롤·적 조회는 두 아군 턴 자원 보존")
	(battle.get("sounds") as CombatSounds).stop_all()
	await create_timer(0.08).timeout
	main.queue_free()
	await process_frame


func _click(point: Vector2, button_index: MouseButton = MOUSE_BUTTON_LEFT) -> void:
	var already_busy: bool = actions.busy
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
		if not moving and not battle.has_node("Arrow") and (not actions.busy or already_busy or hud.reaction_dialog.visible):
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
		and units[0].movement_left == 4, "이동 연출 시작은 입력 잠금, 논리 칸·이동력 유지")
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
	_check(units[0].cell == Vector2i(4, 2) and units[0].movement_left == 2
		and units[0].position == (battle.get_node("Map") as TileMapLayer).map_to_local(units[0].cell)
		and not units[0].is_moving and units[0].body_offset_y == 0.0 and not actions.busy,
		"두 사각 칸 이동은 도착 후 자원 갱신과 몸통·입력 복구")
	for side: bool in [true, false]:
		_reset_units()
		var actor: CombatUnit = units[1] if side else units[3]
		var target: CombatUnit = units[2] if side else units[0]
		actor.cell = Vector2i(1, 4) if side else Vector2i(4, 4)
		target.cell = Vector2i(4, 4) if side else Vector2i(1, 4)
		(units[0] if side else units[2]).cell = Vector2i(9, 9)
		(units[3] if side else units[1]).cell = Vector2i(0, 0)
		target.reaction_left = 0
		if side:
			turns.select_unit(actor)
		else:
			while turns.current_unit != actor:
				turns.end_turn()
		battle.call("_update_turn_ui")
		actions.dice = ScriptedDice.new([20 if side else 10, 2], ScriptedDice.attack_sides(actor) + ScriptedDice.damage_sides(actor))
		var hp: int = target.hit_points
		finished[0] = false
		_animated_attack(actor, target, finished)
		_check(actions.busy and battle.has_node("Arrow") and target.hit_points == hp,
			"아군·적 궁수 기본 공격은 비행 중 피해 적용 전: %s" % side)
		_check((battle.get_node("Arrow") as Node2D).position == actor.position + Vector2(
			8 if side else -8, actor.floor_offset_y - 16),
			"실제 도트 활의 발밑 기준 출발점과 좌우를 화살에 적용: %s" % side)
		_check(not actions.can_move(actor, Vector2i(2, 4)) and not actions.can_use(actor, "attack")
			and not await actions.attack(actor, target), "화살 비행 중 중복 입력 거부")
		while not finished[0]:
			await process_frame
		await process_frame
		_check(target.hit_points < hp and actor.action_left == 0
			and not battle.has_node("Arrow")
			and not actions.busy, "화살 도착 후 피해·비용 처리와 투사체 정리")
	_reset_units()
	units[1].cell = Vector2i(1, 4)
	units[2].cell = Vector2i(4, 4)
	turns.select_unit(units[1])
	battle.call("_update_turn_ui")
	actions.dice = _dice_for_miss(units[1])
	finished[0] = false
	_animated_attack(units[1], units[2], finished)
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
	actions.dice = ScriptedDice.new([10, 2], ScriptedDice.attack_sides(units[3]) + ScriptedDice.damage_sides(units[3]))
	var reactions: Array[int] = [0]
	var on_reaction: Callable = func(_kind: String, _prompt: String) -> void:
		reactions[0] += 1
		hud.reaction_dialog.get_cancel_button().pressed.emit()
	actions.reaction_requested.connect(on_reaction)
	await actions.attack(units[3], units[0])
	await process_frame
	# 흘려내기를 제거해 맞는 아군 전사에게 묻는 반응이 없다.
	_check(reactions[0] == 0 and units[0].hit_points < units[0].get_max_hit_points()
		and not actions.busy and not hud.reaction_dialog.visible,
		"적 화살 명중은 반응 확인 없이 피해를 주고 전투를 정상 재개")
	actions.reaction_requested.disconnect(on_reaction)
	_reset_units()
	actions.dice = CombatDice.new()
	actions.dice.seed = 100
	for actor: CombatUnit in [units[0], units[1]]:
		_reset_units()
		actions.grid.props.clear()
		actions.floor_loot.clear()
		actor.cell = Vector2i(5, 5)
		(units[1] if actor == units[0] else units[0]).cell = Vector2i(0, 0)
		units[2].cell = Vector2i(8, 8)
		units[3].cell = Vector2i(9, 9)
		turns.select_unit(actor)
		actor.facing_left = false
		var crate: CombatGrid.Prop = actions.create_prop(Vector2i(4, 5), "crate")
		battle.call("_update_turn_ui")
		var event: InputEventMouseButton = InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = true
		event.position = battle.map.get_global_transform_with_canvas() * (
			battle.map.map_to_surface(crate.cell) + Vector2(0, -8))
		var saw_impact: Array[bool] = [false]
		var on_impact: Callable = func(node: Node) -> void:
			if node.name == &"PropAnimation":
				saw_impact[0] = true
				_check(crate.hit_points == 6 and actor.action_left == 1, "상자 연출 생성은 피해·비용 확정 전")
		battle.map.child_entered_tree.connect(on_impact)
		battle.call("_unhandled_input", event)
		battle.call("_unhandled_input", event)
		var sprite: AnimatedSprite2D = actor.get_node("Sprite") as AnimatedSprite2D
		_check(actions.busy and actor.facing_left and sprite.animation == &"attack_left"
			and crate.hit_points == 6, "상자 공격은 방향·공격 자세를 먼저 표시하고 입력을 잠근다")
		if actor.kind == CombatUnit.Kind.ARCHER:
			_check(battle.has_node("Arrow"), "궁수의 상자 공격에도 실제 화살이 비행한다")
		while actions.busy:
			if battle.map.has_node("PropAnimation"):
				_check(crate.hit_points == 6 and actor.action_left == 1, "상자 연출 중 판정·비용은 아직 적용하지 않음")
				battle.call("_unhandled_input", event)
			await process_frame
		await process_frame
		battle.map.child_entered_tree.disconnect(on_impact)
		_check(saw_impact[0] and not battle.map.has_node("PropAnimation"), "물체 피격 연출을 보이고 임시 노드를 정리")
		_check(actor.action_left == 0 and crate.hit_points < 6 and not battle.has_node("Arrow"),
			"상자 공격 연출 뒤 기존 피해·행동 비용과 화살 정리를 유지한다")
	actions.grid.props.clear()
	_reset_units()


func _test_rock_preview_guidance() -> void:
	_reset_units()
	var actor: CombatUnit = units[0]
	var origin: Vector2i = Vector2i(5, 5)
	var directions: Array[Vector2i] = [Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT, Vector2i.UP]
	var labels: Array[String] = ["오른쪽 아래", "왼쪽 아래", "왼쪽 위", "오른쪽 위"]
	for index: int in range(directions.size()):
		actions.grid.props.clear()
		var direction: Vector2i = directions[index]
		actor.cell = origin - direction
		units[1].cell = Vector2i.ZERO
		units[2].cell = origin + direction * 2
		units[3].cell = Vector2i(9, 9)
		var rock: CombatGrid.Prop = actions.create_prop(origin, "rock")
		battle.call("_on_action_selected", "attack")
		await _click(battle.map.get_global_transform_with_canvas() * (battle.map.map_to_surface(origin) + Vector2(0, -8)))
		_check(labels[index] in hud.preview_label.text and "방향 " not in hud.preview_label.text,
			"바위 미리보기는 화면 방향을 표시: " + labels[index])
		_check("3칸 · 최대3칸" in hud.preview_label.text and "적 피해4: " + units[2].get_display_name() in hud.preview_label.text
			and "행동1" in hud.preview_label.text and "피해 굴림 없음" in hud.preview_label.text,
			"네 방향에서 기존 거리·충돌 대상·피해·비용·판정 정보 유지")
		_check(actor.action_left == 1 and rock.cell == origin and units[2].hit_points == units[2].get_max_hit_points(),
			"첫 클릭은 바위·HP·행동을 변경하지 않음")
		actions.grid.blocked_cells.append(origin + direction)
		battle.call("_update_turn_ui")
		_check(labels[index] in hud.preview_label.text and "0칸 · 장벽" in hud.preview_label.text
			and "충돌 없음" in hud.preview_label.text, "즉시 정지해도 방향·거리·정지 원인 보존")
		actions.grid.blocked_cells.erase(origin + direction)
	actions.grid.props.clear()
	_reset_units()


## 휩쓸기(#426): 인접한 칸을 좌클릭하면 영향 칸과 대상별 명중률을 보이고, 같은 칸을 다시 좌클릭하면 실행한다.
func _test_sweep_input() -> void:
	_reset_units()
	actions.grid.props.clear()
	var actor: CombatUnit = units[0]
	var map: TileMapLayer = battle.map
	var selection: CombatSelection = battle.get("selection") as CombatSelection
	actor.cell = Vector2i(4, 4)
	units[1].cell = Vector2i(3, 5)
	units[2].cell = Vector2i(5, 4)
	units[3].cell = Vector2i(4, 3)
	battle.call("_update_turn_ui")
	battle.call("_on_action_selected", "sweep")
	var overlays: Array = map.get("_overlays")
	_check(selection.selected_action == "sweep" and "정면으로 삼을 인접한 칸" in hud.preview_label.text
		and overlays.size() == 4, "휩쓸기를 고르면 안내와 고를 수 있는 인접 칸을 보임")
	_check(overlays.all(func(overlay: Polygon2D) -> bool: return overlay.color == (overlays[0] as Polygon2D).color),
		"고를 수 있는 인접 칸은 기본 공격 대상과 관계없이 같은 색")
	await _click(units[2].get_global_transform_with_canvas() * Vector2(0, -10))
	_check(selection.preview_cell == units[2].cell and units[2].is_previewed and units[3].is_previewed
		and actor.action_left == 1, "적 몸통을 눌러도 그 칸을 정면으로 미리보기")
	# 전사 자신의 몸통이 인접 칸 바닥을 가려도 격자 위치로 그 칸을 고른다.
	var covered: Vector2 = Vector2.INF
	var covered_cell: Vector2i = Vector2i(-1, -1)
	for y: int in range(-40, 1):
		for x: int in range(-16, 17):
			var local: Vector2 = Vector2(x, y)
			var floor_cell: Vector2i = map.surface_to_map(map.to_local(actor.to_global(local)))
			if (covered == Vector2.INF and actor.contains_body_point(local)
					and CombatGrid.distance(actor.cell, floor_cell) == 1):
				covered = actor.get_global_transform_with_canvas() * local
				covered_cell = floor_cell
	_check(covered != Vector2.INF, "입력 fixture: 전사 몸통이 덮은 인접 칸 바닥이 있음")
	if covered != Vector2.INF:
		await _click(covered)
		_check(selection.preview_cell == covered_cell, "자기 몸통이 가린 인접 칸도 정면으로 미리보기")
	# 빈 칸 (4, 5)를 정면으로 두면 왼쪽 옆 (5, 4)의 적만 맞고 앞오른쪽 (3, 5)의 아군은 맞지 않는다.
	var facing: Vector2i = Vector2i(4, 5)
	var point: Vector2 = map.get_global_transform_with_canvas() * map.map_to_surface(facing)
	await _click(point)
	var chance: String = "%s %.1f%%" % [units[2].get_display_name(), actions.sweep_chance(actor, units[2]) * 100.0]
	overlays = map.get("_overlays")
	_check(selection.preview_cell == facing and chance in hud.preview_label.text and "시계방향 명중률" in hud.preview_label.text
		and overlays.size() == actions.grid.sweep_cells(actor.cell, facing).size() and units[2].is_previewed
		and not units[1].is_previewed and not units[3].is_previewed and actor.action_left == 1,
		"빈 칸 첫 좌클릭은 영향 칸과 대상별 명중률 미리보기: " + hud.preview_label.text)
	var saved_dice: CombatDice = actions.dice
	actions.dice = ScriptedDice.new([15, 8], [20, 20])
	await _click(point)
	_check(units[2].hit_points == units[2].get_max_hit_points() - 4 and actor.action_left == 0
		and units[1].hit_points == units[1].get_max_hit_points() and selection.selected_action == "attack",
		"같은 칸을 다시 좌클릭하면 실행: ⌈8 ÷ 2⌉ 피해, 아군 제외")
	actions.dice = saved_dice
	# #407 답 5a: 반달에 적이 없어도 같은 칸을 다시 좌클릭하면 실행하고 행동을 소비한다.
	# 정면은 바닥 타일이 없는 낭떠러지 칸으로 둔다. 칠한 칸이면 눌러서 고를 수 있어야 한다.
	units[2].cell = Vector2i(8, 8)
	units[3].cell = Vector2i(9, 9)
	actor.action_left = 1
	facing = Vector2i(3, 4)
	var tile_source: int = map.get_cell_source_id(facing)
	var tile_atlas: Vector2i = map.get_cell_atlas_coords(facing)
	map.erase_cell(facing)
	actions.grid.pits = [facing]
	battle.call("_on_action_selected", "sweep")
	point = map.get_global_transform_with_canvas() * map.map_to_surface(facing)
	await _click(point)
	_check(selection.preview_cell == facing and "영향 칸에 적이 없음" in hud.preview_label.text
		and "같은 칸을 다시 좌클릭하면 실행합니다." in hud.preview_label.text and actor.action_left == 1,
		"타일 없는 낭떠러지 정면도 첫 좌클릭에 빈 반달 실행 안내와 함께 미리보기: " + hud.preview_label.text)
	await _click(point)
	_check(actor.action_left == 0 and selection.selected_action == "attack", "빈 반달도 같은 칸을 다시 좌클릭하면 실행")
	actions.grid.pits.clear()
	map.set_cell(facing, tile_source, tile_atlas)
	_reset_units()


## 효시(#500): 인접한 칸을 좌클릭해 방향을 고르면 띠와 대상별 의지 내성 성공률을 보이고, 같은 칸을 다시 좌클릭하면 실행한다.
func _test_whistle_input() -> void:
	_reset_units()
	actions.grid.props.clear()
	var actor: CombatUnit = units[1]
	var map: TileMapLayer = battle.map
	var selection: CombatSelection = battle.get("selection") as CombatSelection
	turns.select_unit(actor)
	actor.cell = Vector2i(4, 4)
	units[0].cell = Vector2i(6, 5)
	units[2].cell = Vector2i(6, 4)
	units[3].cell = Vector2i(6, 8)
	battle.call("_update_turn_ui")
	var button: Button = (hud.get("_actions") as Dictionary)["whistle"] as Button
	_check(button.icon != null and "DC 11" in button.tooltip_text and "전투마다 1회 · 1회 남음" in button.tooltip_text
		and "산만함 2턴" in button.tooltip_text and "내성굴림·명중굴림 불리" in button.tooltip_text,
		"효시 버튼은 아이콘과 호버(DC·횟수·산만함 효과)를 가짐: " + button.tooltip_text.replace("\n", " | "))
	battle.call("_on_action_selected", "whistle")
	var overlays: Array = map.get("_overlays")
	_check(selection.selected_action == "whistle" and "방향으로 삼을 인접한 칸" in hud.preview_label.text and overlays.size() == 4,
		"효시를 고르면 안내와 고를 수 있는 인접 칸을 보임: " + hud.preview_label.text)
	var facing: Vector2i = Vector2i(5, 4)
	var point: Vector2 = map.get_global_transform_with_canvas() * map.map_to_surface(facing)
	await _click(point)
	overlays = map.get("_overlays")
	var chance: String = CombatActionRules.save_chance_text(actor, units[2], "whistle")
	_check(selection.preview_cell == facing and chance in hud.preview_label.text and "의지 내성 성공률" in hud.preview_label.text
		and overlays.size() == actions.grid.band_cells(actor.cell, facing).size() and units[2].is_previewed
		and not units[0].is_previewed and not units[3].is_previewed and actor.action_left == 1,
		"첫 좌클릭은 띠와 대상별 의지 내성 성공률 미리보기: " + hud.preview_label.text)
	var saved_dice: CombatDice = actions.dice
	actions.dice = ScriptedDice.new([2], [units[2].get_ability_sides(CombatUnit.Ability.WILL)])
	await _click(point)
	_check(units[2].distracted_turns == 2 and actor.action_left == 0 and actor.whistle_left == 0 and units[0].distracted_turns == 0
		and selection.selected_action == "attack", "같은 칸을 다시 좌클릭하면 실행: 띠 안의 적만 산만함, 아군 제외")
	hud.show_unit(units[2])
	_check("산만함 2턴" in hud.resource_label.get_parsed_text(), "유닛 패널 상태 줄에 산만함 2턴: " + hud.resource_label.get_parsed_text())
	actions.dice = saved_dice
	# 인접하지 않은 칸을 누르면 미리보기만 지운다. 적이 없는 방향도 안내와 함께 고를 수 있다.
	actor.action_left = 1
	actor.whistle_left = 1
	units[2].distracted_turns = 0
	units[2].distracted_source = null
	battle.call("_on_action_selected", "whistle")
	await _click(map.get_global_transform_with_canvas() * map.map_to_surface(Vector2i(7, 4)))
	_check(selection.preview_cell == Vector2i(-1, -1) and actor.action_left == 1, "인접하지 않은 칸은 방향이 될 수 없음")
	units[2].cell = Vector2i(8, 8)
	units[0].cell = Vector2i(0, 0)
	battle.call("_update_turn_ui")
	var empty_facing: Vector2i = Vector2i(4, 3)
	await _click(map.get_global_transform_with_canvas() * map.map_to_surface(empty_facing))
	_check(selection.preview_cell == empty_facing and "영향 칸에 적이 없음" in hud.preview_label.text, "적이 없는 방향도 안내와 함께 미리보기")
	_reset_units()


func _test_rock_presentation() -> void:
	_reset_units()
	actions.grid.props.clear()
	var actor: CombatUnit = units[0]
	actor.cell = Vector2i(5, 5)
	units[1].cell = Vector2i(0, 0)
	units[2].cell = Vector2i(8, 5)
	units[3].cell = Vector2i(9, 9)
	turns.select_unit(actor)
	var rock: CombatGrid.Prop = actions.create_prop(Vector2i(6, 5), "rock")
	var preview: CombatActions.RockRoll = actions.preview_rock(actor, rock)
	var hp: int = units[2].hit_points
	var landing: Vector2i = units[2].cell
	for step: CombatActions.RockStep in preview.steps:
		if step.push and step.target == units[2]:
			landing = step.push_cell
	_check(landing != units[2].cell, "바위 연출 검수는 유닛을 미는 경로를 쓴다")
	battle.call("_update_turn_ui")
	var event: InputEventMouseButton = InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	event.position = battle.map.get_global_transform_with_canvas() * (battle.map.map_to_surface(rock.cell) + Vector2(0, -8))
	# 바위 연출 노드가 사라지는 순간 = 판정 직전. 밀린 유닛은 이미 착지 칸에 그려져 있어야 한다.
	var at_rock_end: Array = []
	var on_rock_end: Callable = func(node: Node) -> void:
		if node.name == &"PropAnimation":
			at_rock_end.append([units[2].position, units[2].cell])
	battle.map.child_exiting_tree.connect(on_rock_end)
	battle.call("_unhandled_input", event)
	battle.call("_unhandled_input", event)
	var seen: bool = false
	var moved_during_roll: bool = false
	while actions.busy:
		if battle.map.has_node("PropAnimation"):
			seen = true
			_check(rock.cell == Vector2i(6, 5) and units[2].hit_points == hp and actor.action_left == 1,
				"바위 연출 중 위치·피해·비용은 확정 전 상태")
			moved_during_roll = moved_during_roll or units[2].position != battle.map.map_to_local(Vector2i(8, 5))
			battle.call("_unhandled_input", event)
		await process_frame
	battle.map.child_exiting_tree.disconnect(on_rock_end)
	_check(seen and rock.cell == preview.cells[-1] and units[2].hit_points == hp - 4
		and actor.action_left == 0 and not battle.map.has_node("PropAnimation"),
		"바위 연출 후 미리보기와 같은 위치·충돌4피해·비용1, 중복 입력 차단")
	_check(moved_during_roll and at_rock_end.size() == 1
		and at_rock_end[0][0] == battle.map.map_to_local(landing) and at_rock_end[0][1] == Vector2i(8, 5)
		and units[2].cell == landing and units[2].position == battle.map.map_to_local(landing)
		and not units[2].is_moving,
		"밀린 유닛은 바위와 함께 트윈으로 움직이고 바위 연출 안에서 착지 칸에 도착한다: %s" % [at_rock_end])
	for cancel: String in ["giveup", "rebuild"]:
		_reset_units()
		actions.grid.props.clear()
		actor.cell = Vector2i(5, 5)
		units[2].cell = Vector2i(8, 5)
		turns.select_unit(actor)
		rock = actions.create_prop(Vector2i(6, 5), "rock")
		hp = units[2].hit_points
		battle.call("_update_turn_ui")
		battle.call("_on_action_selected", "attack")
		battle.call("_unhandled_input", event)
		battle.call("_unhandled_input", event)
		for frame: int in range(120):
			if battle.map.has_node("PropAnimation"):
				break
			await process_frame
		_check(battle.map.has_node("PropAnimation"), "중단 검수는 바위 연출 도중 시작")
		if cancel == "giveup":
			actions.give_up()
			for marker: Node2D in battle.map.get("_prop_markers"):
				_check(not marker.visible, "포기 후 UI를 다시 그려도 애니메이션과 원본을 중복 표시하지 않음")
		else:
			battle.map.prop_impact(rock.cell, false)
			var effect: Node2D = battle.map.get_child(battle.map.get_child_count() - 1)
			battle.map.build_grid(actions.grid, battle.stages[0].tile_set, battle.stages[0])
			_check(not is_instance_valid(effect), "맵 재구축은 이전 충돌 효과를 즉시 제거")
			(battle.get("selection") as CombatSelection).selected_action = "move"
		for frame: int in range(30):
			await process_frame
		_check(not battle.map.has_node("PropAnimation") and rock.cell == Vector2i(6, 5)
			and units[2].hit_points == hp, "중단한 연출은 이후 바위 이동·피해 없이 정리")
		_check(actions.busy == (cancel == "rebuild"), "포기하면 잠금 해제, 새 세대의 잠금은 이전 호출이 변경하지 않음")
		if cancel == "rebuild":
			_check((battle.get("selection") as CombatSelection).selected_action == "move", "이전 호출은 새 세대의 선택을 변경하지 않음")
		actions.busy = false
	actions.grid.props.clear()
	_reset_units()


func _animated_move(actor: CombatUnit, cell: Vector2i, finished: Array[bool]) -> void:
	await actions.move_to(actor, cell)
	finished[0] = true


func _animated_attack(actor: CombatUnit, target: CombatUnit, finished: Array[bool]) -> void:
	await actions.attack(actor, target)
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
		var shared: Theme = load("res://scenes/ui_theme.tres")
		_check(hud.reaction_dialog.get_theme_stylebox("embedded_border") == shared.get_stylebox("embedded_border", "Window")
			and hud.reaction_dialog.get_ok_button().get_theme_stylebox("normal") == shared.get_stylebox("normal", "Button"),
			"반응 확인 창은 공용 테마의 틀·버튼 모양")
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
	actions.dice = _dice_for_miss(units[0])
	messages.clear()
	await actions.move_to(units[3], Vector2i(6, 4))
	await process_frame
	var use_count: int = 0
	for message: String in messages:
		if "기회 공격:" in message and "사용" in message:
			use_count += 1
	_check(use_count == 1 and units[0].reaction_left == 0, "아군 반응 사용 로그·비용은 정확히 한 번")
	_check("힘 d20 [1]" in hud.message_label.text, "3줄 로그에 기회 공격 판정이 남음")
	_check(choices[0] == 2 and not hud.reaction_dialog.visible and not actions.busy, "두 선택의 연결과 입력 잠금 해제")
	actions.logged.disconnect(on_log)
	actions.reaction_requested.disconnect(on_reaction)
	hud.show_reaction("counter", "반격 문구")
	_check(hud.reaction_dialog.get_ok_button().text == "반격"
		and hud.reaction_dialog.get_cancel_button().text == "넘기기", "반격 선택 문구")
	hud.reaction_dialog.get_cancel_button().pressed.emit()
	await process_frame


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
		hud.show_reaction("opportunity", "접근성 포커스 회귀")
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


## #622: 전체 속도 계수의 환산과 적용 범위.
func _test_presentation_speed() -> void:
	var speed: float = CombatPresentation.PRESENTATION_SPEED
	_check(speed >= 0.5 and speed <= 0.75, "전체 속도 계수는 Issue가 정한 0.5~0.75 안: %s" % speed)
	_check(is_equal_approx(CombatPresentation.duration(0.09), 0.09 / speed), "시간은 계수로 나눠 늘어남")
	_check(is_equal_approx(CombatPresentation.fps(24.0), 24.0 * speed), "fps는 계수를 곱해 느려짐")
	var frames: SpriteFrames = units[0].get_node("Sprite").sprite_frames
	for direction: String in ["left", "right"]:
		_check(is_equal_approx(frames.get_animation_speed("move_" + direction), CombatPresentation.fps(24.0)),
			"move 애니메이션 fps에 계수 적용: " + direction)
		_check(is_equal_approx(frames.get_animation_speed("attack_" + direction), CombatPresentation.fps(12.0)),
			"attack 애니메이션 fps에 계수 적용: " + direction)
		_check(is_equal_approx(frames.get_animation_speed("idle_" + direction), 3.0),
			"idle 애니메이션 fps는 그대로: " + direction)


func _turn_tile_center(map: CombatMap) -> Vector2:
	var center: Vector2 = Vector2.ZERO
	for point: Vector2 in map._turn_tile.polygon:
		center += point / map._turn_tile.polygon.size()
	return map._turn_tile.position + center


func _turn_tile_on(unit: CombatUnit) -> bool:
	var map: CombatMap = battle.map
	return (map._turn_tile != null and map._turn_tile.visible
		and _turn_tile_center(map).is_equal_approx(map.map_to_surface(unit.cell)))


## #623: 전투 장면에서 발밑 칸 표시가 행동 유닛을 따라간다.
func _test_turn_tile_battle() -> void:
	var map: CombatMap = battle.map
	_reset_units()
	units[0].cell = Vector2i(4, 9)
	units[1].cell = Vector2i(5, 9)
	units[2].cell = Vector2i(4, 2)
	units[3].cell = Vector2i(8, 2)
	battle.call("_update_turn_ui")
	_check(turns.current_unit == units[0] and _turn_tile_on(units[0]), "아군 행동 유닛의 칸에 발밑 표시")
	_check(units[0].is_selected and not units[1].is_selected, "금색 몸 윤곽은 행동 유닛에만 켜져 있음")
	# 같은 아군 턴 묶음 안의 유닛 전환(Tab·초상)은 나타남을 다시 돌린다.
	_check(turns.select_unit(units[1]), "같은 묶음의 다른 아군을 고를 수 있음")
	battle.call("_update_turn_ui")
	_check(_turn_tile_on(units[1]) and is_zero_approx(map._turn_tile.modulate.a), "유닛 전환 때 새 칸에서 알파 0으로 나타남을 다시 시작")
	# 같은 유닛으로 다시 갱신하면 나타남을 다시 돌리지 않는다.
	var running: Tween = map._turn_tile_tween
	running.pause()
	running.custom_step(0.05)
	var halfway: float = map._turn_tile.modulate.a
	units[1].cell = Vector2i(6, 9)
	battle.call("_update_turn_ui")
	_check(_turn_tile_on(units[1]) and map._turn_tile_tween == running and is_equal_approx(map._turn_tile.modulate.a, halfway) and halfway > 0.0,
		"같은 유닛의 갱신은 칸만 옮기고 나타남을 다시 돌리지 않음")
	# 턴이 적으로 넘어오면 적도 같다.
	ScriptedDice.arrange_turns(turns, units, [units[2], units[3], units[0], units[1]])
	battle.call("_update_turn_ui")
	_check(turns.current_unit == units[2] and _turn_tile_on(units[2]) and is_zero_approx(map._turn_tile.modulate.a),
		"적 행동 유닛의 칸에도 같은 표시가 새로 나타남")
	_check(units[2].is_selected and not units[0].is_selected, "금색 몸 윤곽은 적 행동 유닛에도 지금처럼 켜짐")
	# 행동 유닛이 전투 불능이면 숨긴다.
	units[2].hit_points = 0
	battle.call("_update_turn_ui")
	_check(not map._turn_tile.visible, "행동 유닛이 전투 불능이면 숨김")
	_reset_units()
	battle.call("_update_turn_ui")
	_check(_turn_tile_on(units[0]), "다시 살아난 행동 유닛의 칸에 표시")
	# 전투 시작 전 지도 준비 중에는 아무의 턴도 아니라 그리지 않는다.
	battle.set("waiting_for_start", true)
	battle.call("_update_turn_ui")
	_check(not map._turn_tile.visible, "전투 시작 전에는 숨김")
	battle.set("waiting_for_start", false)
	battle.call("_update_turn_ui")
	_check(_turn_tile_on(units[0]) and is_zero_approx(map._turn_tile.modulate.a), "전투가 시작되면 첫 행동 유닛에서 나타남")
	# 전투가 끝나면 숨긴다.
	units[2].hit_points = 0
	units[3].hit_points = 0
	_check(actions.is_over(), "적이 모두 쓰러지면 전투가 끝남")
	# 결과 화면 같은 다른 갱신을 건드리지 않게 표시 갱신만 부른다.
	battle.call("_refresh_turn_tile")
	_check(not map._turn_tile.visible, "전투가 끝나면 숨김")
	_reset_units()
	units[0].cell = Vector2i(4, 4)
	units[1].cell = Vector2i(0, 0)
	units[2].cell = Vector2i(8, 8)
	units[3].cell = Vector2i(9, 9)
	battle.call("_update_turn_ui")
	await process_frame


## #623: 이동·점프 연출이 칸마다 도착한 칸으로 표시를 옮긴다.
func _test_turn_tile_steps() -> void:
	var map: CombatMap = battle.map
	_reset_units()
	units[0].cell = Vector2i(4, 4)
	units[1].cell = Vector2i(0, 0)
	units[2].cell = Vector2i(8, 8)
	units[3].cell = Vector2i(9, 9)
	battle.call("_update_turn_ui")
	for jump: bool in [false, true]:
		var destination: Vector2i = Vector2i(4, 3) if not jump else Vector2i(4, 2)
		var mover: CombatUnit = units[0]
		var before: Array[Tween] = get_processed_tweens()
		battle.call("_animate_jump" if jump else "_animate_movement", mover, destination)
		var tween: Tween = null
		for candidate: Tween in get_processed_tweens():
			if candidate not in before:
				tween = candidate
		_check(tween != null, "이동 연출 Tween이 생김: " + ("점프" if jump else "걸음"))
		if tween == null:
			continue
		var fade: Tween = map._turn_tile_tween
		tween.pause()
		tween.custom_step(0.01)
		_check(_turn_tile_on(mover) and map._turn_tile.visible and _turn_tile_center(map).is_equal_approx(map.map_to_surface(mover.cell)),
			"도착하기 전에는 출발 칸에 있음")
		tween.custom_step(1.0)
		await process_frame
		_check(_turn_tile_center(map).is_equal_approx(map.map_to_surface(destination)), "도착하면 도착한 칸으로 옮겨 감")
		_check(map._turn_tile_tween == fade, "칸을 옮겨도 나타남을 다시 돌리지 않음")
		mover.cell = destination
		battle.call("_update_turn_ui")
		_check(_turn_tile_on(mover), "행동이 끝난 갱신도 같은 칸")
	# 행동 유닛이 아닌 유닛의 이동은 표시를 옮기지 않는다.
	var other: CombatUnit = units[1]
	var stay: Vector2 = _turn_tile_center(map)
	var before_other: Array[Tween] = get_processed_tweens()
	battle.call("_animate_movement", other, Vector2i(0, 1))
	for candidate: Tween in get_processed_tweens():
		if candidate not in before_other:
			candidate.pause()
			candidate.custom_step(1.0)
	await process_frame
	_check(_turn_tile_center(map).is_equal_approx(stay), "행동 유닛이 아닌 유닛의 이동은 표시를 옮기지 않음")
	_reset_units()
	units[0].cell = Vector2i(4, 4)
	units[1].cell = Vector2i(0, 0)
	units[2].cell = Vector2i(8, 8)
	units[3].cell = Vector2i(9, 9)
	battle.call("_update_turn_ui")
	await process_frame


func _test_presentation_move_time() -> void:
	_reset_units()
	units[0].cell = Vector2i(4, 4)
	units[1].cell = Vector2i(0, 0)
	units[2].cell = Vector2i(8, 8)
	units[3].cell = Vector2i(9, 9)
	battle.call("_update_turn_ui")
	# 프레임 시간에 기대지 않고 이동 Tween을 멈춘 뒤 직접 진행시켜 길이를 잰다. 시간 재기는 CI의 긴 프레임에서 흔들린다.
	var before: Array[Tween] = get_processed_tweens()
	var finished: Array[bool] = [false]
	battle.call("_animate_movement", units[0], Vector2i(4, 3))
	var tween: Tween = null
	for candidate: Tween in get_processed_tweens():
		if candidate not in before:
			tween = candidate
	var base: float = battle.MOVE_STEP_TIME
	var expected: float = CombatPresentation.duration(base)
	_check(tween != null, "한 칸 이동은 Tween으로 움직임")
	if tween != null:
		tween.pause()
		tween.finished.connect(func() -> void: finished[0] = true)
		# 기대 길이 바로 앞까지 진행하면 아직 움직이고, 조금 더 가면 끝나야 한다.
		var first: float = expected - 0.002
		tween.custom_step(first)
		_check(not finished[0], "한 칸 이동은 계수 적용 시간 %s초 직전까지 끝나지 않는다(기본 %s초)" % [expected, base])
		# custom_step은 더하는 시간이라 남은 시간만 진행한다.
		tween.custom_step(expected - first + 0.002)
		_check(finished[0], "한 칸 이동은 계수 적용 시간 %s초 안에 끝난다" % expected)
	await process_frame
	await process_frame
	_check(Engine.time_scale == 1.0, "전체 속도는 Engine.time_scale을 바꾸지 않음")
