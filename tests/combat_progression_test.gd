extends SceneTree
## 실제 메인 장면과 결과 버튼에서 막 진행과 자원 유지 규칙을 검사한다.

const ScriptedDice = preload("res://tests/scripted_dice.gd")

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
	_test_act_progress()
	_test_terrain_layouts()
	await _test_spiderling_placement_and_turns()
	await _test_mother_stages()
	await _test_novice_placements()
	await _test_scrap_robot_stage()
	await _test_scrap_robot_2000_stage()
	await _test_scrap_robot_3000_stage()
	var main: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	current_scene = main
	var battle: Node2D = main.get_node("Battle") as Node2D
	battle.set_process(false)
	await process_frame
	var hud: CombatTurnHud = battle.get_node("UI/TurnHud") as CombatTurnHud
	_check(hud.has_node("Progress"), "현재 막과 스테이지를 화면에 표시")
	if hud.has_node("Progress"):
		_check((hud.get_node("Progress") as Label).text == "1막 · 1스테이지", "첫 전투는1-1")
	for unit: CombatUnit in battle.get("units"):
		_check(unit.potion_left == 0, "드랍 전 시작 물약은0개")
	_check_enemy_values(battle, 1)
	await _test_stage_transition(battle)
	await _test_act_and_defeat(battle)
	await _test_graduation(battle)
	_test_usage_text(battle)
	main.queue_free()
	await process_frame
	await _test_async_transition()
	var dice_problems: Array[String] = ScriptedDice.finish()
	_check(dice_problems.is_empty(), "준비한 주사위 값을 요청대로 모두 굴림 " + str(dice_problems))
	print("Combat progression: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)


func _test_terrain_layouts() -> void:
	var sample: CombatStage = CombatStage.new()
	if sample.has_method("get_blocked_cells"):
		sample.blocked_cells = [Vector2i(1, 1), Vector2i(9, 9)]
		sample.scenery[Vector2i(1, 1)] = "cottage"
		var combined: Array[Vector2i] = sample.call("get_blocked_cells")
		_check(combined.size() == 5 and combined.has(Vector2i(2, 2))
			and sample.blocked_cells.size() == 2, "2×2 집의 footprint를 중복 없이 합치고 원본을 보존한다")
	var layouts: Dictionary[String, bool] = {}
	for act: int in range(1, 4):
		for number: int in range(1, 4):
			var stage: CombatStage = load("res://scenes/combat/stages/act%d_stage%d.tres" % [act, number]) as CombatStage
			var label: String = "%d-%d" % [act, number]
			_check(stage.heights.values().any(func(height: int) -> bool: return height >= 2),
				label + " 실제 높이2 이상 고지대")
			var paths: Variant = stage.get("path_cells")
			var stones: Variant = stage.get("stone_cells")
			var scenery: Variant = stage.get("scenery")
			_check(paths is Array and not paths.is_empty() and stones is Array and not stones.is_empty(),
				label + " 실제 길·석재 배치")
			_check(scenery is Dictionary and not scenery.is_empty() and stage.has_method("get_blocked_cells"),
				label + " 실제 장식과 같은 footprint의 이동 차단")
			if not stage.has_method("get_blocked_cells"):
				continue
			var grid: CombatGrid = CombatGrid.new()
			grid.map_size = stage.map_size
			grid.heights = stage.heights.duplicate()
			grid.pits = stage.pits.duplicate()
			grid.blocked_cells = stage.call("get_blocked_cells")
			for anchor: Vector2i in stage.scenery:
				var size: Vector2i = CombatStage.SCENERY_SIZE[stage.scenery[anchor]]
				for y: int in range(size.y):
					for x: int in range(size.x):
						var footprint: Vector2i = anchor + Vector2i(x, y)
						_check(grid.is_floor(footprint) and grid.blocked_cells.has(footprint)
							and grid.height_at(footprint) == grid.height_at(anchor),
							label + " 장식의 바닥·높이·차단 footprint 일치")
			for list: Array[Vector2i] in [stage.path_cells, stage.stone_cells, stage.water_cells,
				stage.crate_cells, stage.rock_cells, stage.ally_cells]:
				for cell: Vector2i in list:
					_check(grid.is_floor(cell), label + " 재질·물체·아군 칸은 유효한 바닥")
			for cell: Vector2i in stage.crate_cells:
				grid.props.append(CombatGrid.Prop.new(cell, "crate"))
			for cell: Vector2i in stage.rock_cells:
				grid.props.append(CombatGrid.Prop.new(cell, "rock"))
			for cell: Vector2i in stage.ally_cells:
				_check(not grid.is_blocked(cell), label + " 아군 스폰을 장식·물체가 막지 않음")
			var actor: CombatUnit = CombatUnit.new()
			actor.cell = stage.ally_cells[0]
			for y: int in range(stage.map_size.y):
				for x: int in range(stage.map_size.x):
					var cell: Vector2i = Vector2i(x, y)
					if grid.is_floor(cell) and not grid.is_blocked(cell) and cell != actor.cell:
						_check(not grid.path_to(actor, cell).is_empty(), label + " 보행 연결: " + str(cell))
			var enemies: Node = stage.enemies.instantiate()
			for unit: CombatUnit in enemies.get_children():
				_check(grid.is_floor(unit.start_cell) and not grid.is_blocked(unit.start_cell)
					and not grid.path_to(actor, unit.start_cell).is_empty(), label + " 적 스폰과 보행 교전 경로")
				if unit.kind == CombatUnit.Kind.MOTHER_SPIDER:
					_check(grid.empty_neighbors(unit.start_cell).size() >= 2, label + " 엄마 거미 소환 여유")
			enemies.free()
			actor.free()
			var signature: String = var_to_str([stage.heights, paths, stones, scenery])
			_check(not layouts.has(signature), label + " 독립적으로 배치한 지형")
			layouts[signature] = true


func _test_spiderling_placement_and_turns() -> void:
	var main: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	var battle: Node2D = main.get_node("Battle") as Node2D
	battle.set_process(false)
	var units: Array[CombatUnit] = battle.get("units")
	_check(units.size() == 6, "1막 1스테이지는 아군2명과 새끼 거미4마리")
	if units.size() != 6:
		main.queue_free()
		await process_frame
		return
	var cells: Array[Vector2i] = [Vector2i(7, 2), Vector2i(8, 4), Vector2i(7, 6), Vector2i(8, 8)]
	for index: int in range(4):
		_check(units[index + 2].kind == CombatUnit.Kind.SPIDERLING
			and units[index + 2].cell == cells[index] and units[index + 2].hit_points == 1,
			"처음 배치한 새끼 거미의 종류·HP·좌표 순서")
	var turns: CombatTurns = battle.get("turns") as CombatTurns
	turns.start(units, ScriptedDice.new([11, 9, 10, 10, 10, 10]))
	_check(turns.ordered_units == [units[1], units[2], units[3], units[4], units[5], units[0]],
		"이니셔티브 동점은 민첩을 먼저 비교하고 새끼끼리는 배치 좌표 순서")
	var rolls: Array[int] = [2, 1, 20, 18, 16, 14]
	turns.start(units, ScriptedDice.new(rolls))
	for index: int in range(units.size()):
		_check(units[index].initiative_roll == rolls[index]
			and units[index].get_initiative() == rolls[index] + units[index].get_dexterity(),
			"처음 배치한 새끼를 포함해 유닛마다 d20+민첩을 독립 적용")
	var actions: CombatActions = battle.get("actions") as CombatActions
	for index: int in range(2, 6):
		_check(turns.current_unit == units[index] and units[index].action_left == 1,
			"새끼 거미는 각자 이니셔티브 순서의 자기 턴으로 진입")
		_check(await actions.move_to(units[index], cells[index - 2] + Vector2i(-1, 0))
			and units[index].movement_left == 5, "새끼 거미는 자기 턴에 자기 이동력으로 이동")
		for waiting: int in range(index + 1, 6):
			_check(units[waiting].cell == cells[waiting - 2] and units[waiting].movement_left == 6,
				"다른 새끼의 이동은 대기 중인 새끼의 위치·이동력을 바꾸지 않음")
		turns.end_turn()
	var hud: CombatTurnHud = battle.get_node("UI/TurnHud") as CombatTurnHud
	var spiderling_portraits: int = 0
	for portrait: Node in hud.order_bar.find_children("*", "Button", true, false):
		if "새끼 거미" in (portrait as Button).text:
			spiderling_portraits += 1
	_check(spiderling_portraits == 4, "턴 순서 바는 새끼 거미4마리의 이름을 표시")
	main.queue_free()
	await process_frame


func _check_enemy_values(battle: Node2D, act: int) -> void:
	var expected: Dictionary = {
		CombatUnit.Kind.WARRIOR: [12, 5, 12, 1], CombatUnit.Kind.ARCHER: [14, 5, 11, 1],
		CombatUnit.Kind.SPIDERLING: [1, 4, 6, 1],
		CombatUnit.Kind.MOTHER_SPIDER: [20, 4, 13, 2],
		CombatUnit.Kind.SCRAP_ROBOT_1000: [40, 5, 14, 2],
		CombatUnit.Kind.SCRAP_ROBOT_2000: [45, 5, 15, 2],
		CombatUnit.Kind.SCRAP_ROBOT_3000: [50, 5, 16, 2]
	}
	for unit: CombatUnit in battle.get("units"):
		if unit.is_ally:
			_check(unit.get_attack_bonus() == 5
				and unit.get_armor_class() == (16 if unit.kind == CombatUnit.Kind.WARRIOR else 14),
				"막 강화는 아군 기본 명중·AC를 바꾸지 않음")
			continue
		var values: Array = expected[unit.kind]
		_check(unit.get_max_hit_points() == values[0] and unit.hit_points == values[0]
			and unit.get_attack_bonus() == values[1] and unit.get_armor_class() == values[2]
			and unit.get_damage_bonus() == values[3], "%d막 실제 적의 HP·명중·AC·피해" % act)


func _test_mother_stages() -> void:
	var placements: Dictionary = {
		3: [Vector2i(6, 1), Vector2i(7, 3), Vector2i(7, 6), Vector2i(6, 8), Vector2i(9, 4)],
		6: [Vector2i(7, 2), Vector2i(7, 4), Vector2i(7, 7), Vector2i(9, 2), Vector2i(9, 7)]
	}
	for stage: int in [3, 6]:
		var main: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
		root.add_child(main)
		var battle: Node2D = main.get_node("Battle") as Node2D
		battle.set_process(false)
		var progress: CombatActProgress = battle.get("progress") as CombatActProgress
		progress.stage_index = stage
		battle.call("_start_stage", true)
		var units: Array[CombatUnit] = battle.get("units")
		_check(units.size() == 7, "%d막 1스테이지의 처음 배치한 적5마리" % progress.act_number())
		if units.size() != 7:
			main.queue_free()
			await process_frame
			continue
		var mothers: Array[CombatUnit] = []
		for index: int in range(5):
			var unit: CombatUnit = units[index + 2]
			var is_mother: bool = index >= (4 if stage == 3 else 3)
			_check(unit.cell == placements[stage][index]
				and unit.kind == (CombatUnit.Kind.MOTHER_SPIDER if is_mother else CombatUnit.Kind.SPIDERLING),
				"엄마·새끼의 종류·수·시작 좌표를 실제 스테이지에 연결")
			if is_mother:
				mothers.append(unit)
				_check(unit.movement_left == 4 and unit.hit_points == 20, "실제 엄마는 이동력4·HP20에서 시작")
		var turns: CombatTurns = battle.get("turns") as CombatTurns
		var rolls: Array[int] = [20, 17, 1, 1, 1, 1, 18]
		if stage == 6:
			rolls = [20, 17, 1, 1, 1, 18, 17]
		turns.start(units, ScriptedDice.new(rolls))
		turns.end_turn()
		turns.end_turn()
		var actions: CombatActions = battle.get("actions") as CombatActions
		actions.dice = ScriptedDice.new([1], [3])
		await (battle.get("enemy_ai") as CombatEnemyAi).play_turn(mothers[0], actions)
		var child: CombatUnit = units.back()
		_check(units.size() == 8 and child.kind == CombatUnit.Kind.SPIDERLING
			and child.get_parent() == battle.get_node("Units") and child.is_inside_tree()
			and actions.grid.unit_at(child.cell) == child and turns.is_turn_finished(child),
			"실제 AI가 만든 새끼를 장면·점유 칸·대기 중 턴에 함께 연결")
		var portraits: Dictionary = (battle.get_node("UI/TurnHud") as CombatTurnHud).get("_portraits")
		var tooltip: String = (portraits[child] as Button).tooltip_text
		_check("d20" not in tooltip and "엄마 거미 바로 앞" in tooltip
			and "생성한 라운드" in tooltip, "생성한 새끼의 초상은 가짜 주사위 대신 생성 턴 규칙을 표시")
		var loot: CombatLoot = battle.get("loot") as CombatLoot
		loot.data["extra_drop_chance"] = 1.0
		loot.data["items"] = [{"kind": "potion", "name": "검사 물약", "weight": 1, "stats": {}}]
		for mother: CombatUnit in mothers:
			actions.incapacitate(mother)
		actions.changed.emit()
		_check(child.hit_points == 1 and child.visible and child in turns.ordered_units
			and not actions.is_victory() and progress.rewards.is_empty(),
			"엄마가 모두 탈락해도 생성한 새끼를 보존하고 전투 지속")
		for unit: CombatUnit in units:
			if not unit.is_ally and unit != child and unit.kind == CombatUnit.Kind.SPIDERLING:
				actions.incapacitate(unit)
		actions.changed.emit()
		_check(not actions.is_victory() and progress.rewards.is_empty(), "생성한 새끼까지 처치해야 승리")
		actions.incapacitate(child)
		actions.changed.emit()
		_check(actions.is_victory() and progress.rewards.size() == (2 if stage == 3 else 3),
			"보장1개에 엄마1마리·2마리분만 추가 드랍하고 처음·생성 새끼는 모두 제외")
		main.queue_free()
		await process_frame


func _test_novice_placements() -> void:
	var main: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	var battle: Node2D = main.get_node("Battle") as Node2D
	battle.set_process(false)
	var progress: CombatActProgress = battle.get("progress") as CombatActProgress
	var expected: Dictionary = {
		1: [[CombatUnit.Kind.WARRIOR, Vector2i(7, 4)]],
		4: [[CombatUnit.Kind.WARRIOR, Vector2i(6, 3)], [CombatUnit.Kind.ARCHER, Vector2i(8, 6)]],
		7: [[CombatUnit.Kind.WARRIOR, Vector2i(6, 2)], [CombatUnit.Kind.WARRIOR, Vector2i(6, 7)],
			[CombatUnit.Kind.ARCHER, Vector2i(9, 4)]]
	}
	for index: int in range(9):
		var party: Array[CombatUnit] = battle.get("party")
		for ally: CombatUnit in party:
			ally.facing_left = true
		progress.stage_index = index
		battle.call("_start_stage", true)
		_check(party[0].cell == Vector2i(1, 4) and party[1].cell == Vector2i(0, 5)
			and not party[0].facing_left and not party[1].facing_left,
			"모든 스테이지에서 아군이 왼쪽 두 칸에서 오른쪽을 보고 시작")
		_check(battle.get("map_size") == Vector2i(10, 10), "모든 스테이지의 기존 10×10 크기를 사각 맵으로 유지")
		_check_enemy_values(battle, progress.act_number())
		if not expected.has(index):
			continue
		var enemies: Array[CombatUnit] = []
		for unit: CombatUnit in battle.get("units"):
			if not unit.is_ally:
				enemies.append(unit)
		_check(enemies.size() == expected[index].size(), "%d막 2스테이지 풋내기 수" % progress.act_number())
		for enemy: int in range(mini(enemies.size(), expected[index].size())):
			_check(enemies[enemy].kind == expected[index][enemy][0]
				and enemies[enemy].cell == expected[index][enemy][1], "2스테이지 풋내기 종류와 좌표")
	main.queue_free()
	await process_frame


func _test_scrap_robot_stage() -> void:
	var main: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	var battle: Node2D = main.get_node("Battle") as Node2D
	battle.set_process(false)
	var progress: CombatActProgress = battle.get("progress") as CombatActProgress
	progress.stage_index = 2
	battle.call("_start_stage", true)
	var units: Array[CombatUnit] = battle.get("units")
	_check(units.size() == 3 and units[2].kind == CombatUnit.Kind.SCRAP_ROBOT_1000
		and units[2].cell == Vector2i(8, 4), "1막 3스테이지에 고철로봇-1000 한 마리 배치")
	var boss: CombatUnit = units[2]
	boss.hit_points = 2
	var turns: CombatTurns = battle.get("turns") as CombatTurns
	turns.start(units, ScriptedDice.new([19, 14, 2], [20, 20, 20]))
	turns.end_turn()
	turns.end_turn()
	var hud: CombatTurnHud = battle.get_node("UI/TurnHud") as CombatTurnHud
	_check(boss.hit_points == 0 and boss not in turns.ordered_units
		and hud.result_label.text == "승리", "실제 보스 자기 피해 전투 불능이 승리 UI로 연결")
	_check(progress.rewards.size() >= 1 and progress.rewards.size() <= 2,
		"보스 승리도 보장 아이템 1개와 한 마리분 추가 드랍 적용")
	hud.restart_button.pressed.emit()
	var preparation: CombatPreparation = battle.get_node("UI/Preparation") as CombatPreparation
	_check(preparation.visible, "보스 자기 피해 승리 뒤 정비 단계 진입")
	_finish_rewards(battle)
	_check(progress.stage_index == 3 and hud.progress_label.text == "2막 · 1스테이지",
		"보스 정비를 마치면 다음 막으로 진행")
	main.queue_free()
	await process_frame


func _test_scrap_robot_2000_stage() -> void:
	var main: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	var battle: Node2D = main.get_node("Battle") as Node2D
	battle.set_process(false)
	var progress: CombatActProgress = battle.get("progress") as CombatActProgress
	progress.stage_index = 5
	battle.call("_start_stage", true)
	var units: Array[CombatUnit] = battle.get("units")
	_check(units.size() == 3 and units[2].kind == CombatUnit.Kind.SCRAP_ROBOT_2000
		and units[2].cell == Vector2i(8, 4) and units[2].hit_points == 45,
		"2막 3스테이지에 HP45 고철로봇-2000 한 마리 배치")
	if units.size() != 3 or units[2].kind != CombatUnit.Kind.SCRAP_ROBOT_2000:
		main.queue_free()
		await process_frame
		return
	var boss: CombatUnit = units[2]
	boss.cell = Vector2i(4, 4)
	units[0].cell = Vector2i(1, 1)
	units[1].cell = Vector2i(7, 4)
	var turns: CombatTurns = battle.get("turns") as CombatTurns
	turns.start(units, ScriptedDice.new([5, 4, 20], [20, 20, 20]))
	var actions: CombatActions = battle.get("actions") as CombatActions
	actions.dice = ScriptedDice.new([12, 10], [20, 20])
	_check(actions.pull(boss, units[1]) and units[1].cell == Vector2i(5, 4),
		"실제 2000 보스 전투의 만능팔이 대상 위치와 화면 상태를 갱신")
	boss.hit_points = 2
	for turn: int in range(3):
		turns.end_turn()
	var hud: CombatTurnHud = battle.get_node("UI/TurnHud") as CombatTurnHud
	_check(boss.hit_points == 0 and hud.result_label.text == "승리"
		and progress.rewards.size() >= 1 and progress.rewards.size() <= 2,
		"2000도 자기 피해 승리와 보장1개·일반 추가 드랍을 계승")
	hud.restart_button.pressed.emit()
	_finish_rewards(battle)
	_check(progress.stage_index == 6 and hud.progress_label.text == "3막 · 1스테이지",
		"2000 보스 정비 뒤 3막 진행")
	main.queue_free()
	await process_frame


func _test_scrap_robot_3000_stage() -> void:
	var main: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	var battle: Node2D = main.get_node("Battle") as Node2D
	battle.set_process(false)
	var progress: CombatActProgress = battle.get("progress") as CombatActProgress
	progress.stage_index = 8
	battle.call("_start_stage", true)
	var units: Array[CombatUnit] = battle.get("units")
	_check(units.size() == 3 and units[2].kind == CombatUnit.Kind.SCRAP_ROBOT_3000
		and units[2].cell == Vector2i(8, 4) and units[2].hit_points == 50,
		"3막 3스테이지에 HP50 고철로봇-3000 한 마리 배치")
	if units.size() != 3 or units[2].kind != CombatUnit.Kind.SCRAP_ROBOT_3000:
		main.queue_free()
		await process_frame
		return
	var boss: CombatUnit = units[2]
	boss.hit_points = 25
	units[0].cell = Vector2i(7, 4)
	units[0].parry_left = 0
	units[1].cell = Vector2i(8, 5)
	var turns: CombatTurns = battle.get("turns") as CombatTurns
	turns.start(units, ScriptedDice.new([5, 4, 20], [20, 20, 20]))
	var actions: CombatActions = battle.get("actions") as CombatActions
	actions.dice = ScriptedDice.new([15, 3, 15, 3], [20, 8, 20, 8])
	_check(await actions.spin(boss) and units[0].hit_points == 7 and units[1].hit_points == 9
		and boss.action_left == 1 and boss.hit_points == 23,
		"실제 3000 과부하 턴 시작 자기 피해 뒤 회전회오리가 두 아군과 화면을 갱신")
	boss.hit_points = 2
	for turn: int in range(3):
		turns.end_turn()
	var hud: CombatTurnHud = battle.get_node("UI/TurnHud") as CombatTurnHud
	_check(boss.hit_points == 0 and hud.result_label.text == "승리"
		and progress.rewards.size() >= 1 and progress.rewards.size() <= 2,
		"최종 보스 자기 피해 전투 불능도 승리·보장1개·일반 추가 드랍으로 연결")
	hud.restart_button.pressed.emit()
	_check((battle.get_node("UI/Preparation") as CombatPreparation).visible,
		"최종 보스 승리 뒤 정비 단계 진입")
	_finish_rewards(battle)
	_check(progress.graduated and hud.result_label.text == "3막 졸업",
		"최종 보스 정비를 마치면 3막 졸업")
	main.queue_free()
	await process_frame


func _test_async_transition() -> void:
	var main: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	(main.get_node("Battle") as Node2D).stages[0] = load("res://scenes/combat/stage.tres") as CombatStage
	root.add_child(main)
	current_scene = main
	var battle: Node2D = main.get_node("Battle") as Node2D
	battle.set_process(false)
	var hud: CombatTurnHud = battle.get_node("UI/TurnHud") as CombatTurnHud
	var turns: CombatTurns = battle.get("turns") as CombatTurns
	var dice: CombatDice = CombatDice.new()
	dice.seed = 33
	turns.start(battle.get("units"), dice)
	hud.end_button.pressed.emit()
	hud.end_button.pressed.emit()
	battle.set_process(true)
	await process_frame
	await process_frame
	_check(battle.get("_enemy_turn_running"), "실제 적 턴 타이머가 실행 중")
	_win(battle)
	_check(hud.restart_button.disabled, "적 턴 타이머 처리 중 결과 버튼 잠금")
	hud.restart_button.pressed.emit()
	_check(hud.progress_label.text == "1막 · 1스테이지", "실제 AI await 중 전환 신호 거부")
	await create_timer(0.6).timeout
	battle.set_process(false)
	_check(not battle.get("_enemy_turn_running") and not hud.restart_button.disabled,
		"적 턴 await 완료 뒤 결과 버튼 잠금 해제")
	hud.restart_button.pressed.emit()
	_finish_rewards(battle)
	await process_frame
	_check_enemy_values(battle, int((battle.get("progress") as CombatActProgress).stage_index) / 3 + 1)
	_check(hud.progress_label.text == "1막 · 2스테이지"
		and not hud.get_node("Result").visible, "이전 적 턴 처리 종료 뒤 다음 전투로 진입")
	main.queue_free()
	await process_frame


func _test_act_progress() -> void:
	var progress: CombatActProgress = CombatActProgress.new(9)
	_check(progress.act_number() == 1 and progress.stage_in_act() == 1 and progress.starts_act(),
		"장면 없이 1막 1스테이지에서 시작")
	progress.stage_index = 5
	progress.restart_act()
	_check(progress.stage_index == 3 and progress.act_number() == 2 and progress.starts_act(),
		"2막 3스테이지 패배는 2막 1스테이지로 재시작")
	progress.stage_index = 2
	_check(progress.is_last_in_act() and not progress.is_final_stage(), "1막 마지막 스테이지")
	progress.advance()
	_check(progress.stage_index == 3 and progress.starts_act() and not progress.graduated,
		"정비 뒤 다음 막 첫 스테이지")
	progress.stage_index = 8
	progress.advance()
	_check(progress.graduated and progress.stage_index == 8, "마지막 스테이지 정비 뒤 3막 졸업")
	var loot: CombatLoot = CombatLoot.new()
	var dice: CombatDice = CombatDice.new()
	dice.seed = 7
	progress.begin_stage()
	progress.record_victory(loot, 2, dice)
	var first: Array[Dictionary] = progress.rewards
	progress.record_victory(loot, 2, dice)
	_check(not first.is_empty() and is_same(progress.rewards, first),
		"승리 기록은 스테이지마다 드랍을 한 번만 굴림")
	progress.begin_stage()
	_check(progress.rewards.is_empty(), "다음 스테이지 시작에서 드랍 비움")


func _win(battle: Node2D) -> void:
	var actions: CombatActions = battle.get("actions") as CombatActions
	for unit: CombatUnit in battle.get("units"):
		if not unit.is_ally:
			actions.incapacitate(unit)
	actions.changed.emit()


func _test_stage_transition(battle: Node2D) -> void:
	var loot: CombatLoot = battle.loot
	var stored: Dictionary = {"kind": "potion", "name": "계속 보관할 물약", "stats": {}}
	loot.bag.append(stored)
	var party: Array[CombatUnit] = []
	for unit: CombatUnit in battle.get("units"):
		if unit.is_ally:
			party.append(unit)
	var warrior: CombatUnit = party[0]
	var archer: CombatUnit = party[1]
	warrior.hit_points = 5
	warrior.second_wind_left = 0
	warrior.parry_left = 0
	warrior.surge_left = 0
	warrior.potion_left = 3
	warrior.is_stunned = true
	warrior.stun_source = (battle.get("units") as Array)[2] as CombatUnit
	warrior.disengaged = true
	warrior.marked_target = (battle.get("units") as Array)[2] as CombatUnit
	(battle.get("actions") as CombatActions).incapacitate(archer)
	var hud: CombatTurnHud = battle.get_node("UI/TurnHud") as CombatTurnHud
	var stages: Array[CombatStage] = battle.get("stages")
	var second: CombatStage = stages[1].duplicate() as CombatStage
	second.map_size = Vector2i(8, 9)
	second.ally_cells = [Vector2i(1, 8), Vector2i(2, 8)]
	stages[1] = second
	_win(battle)
	_check(not warrior.is_stunned, "승리 때 기절 시전자 탈락을 먼저 반영")
	_check(hud.result_label.text == "승리" and hud.restart_button.text == "보상 확인",
		"스테이지 승리 결과에서 보상 확인 안내")
	hud.restart_button.pressed.emit()
	_finish_rewards(battle)
	await process_frame
	await process_frame
	_check((hud.get_node("Progress") as Label).text == "1막 · 2스테이지", "승리 뒤1-2 진행")
	_check(loot.bag[0] == stored, "같은 막 다음 전투는 공용 가방 보존")
	_check((battle.get_node("Map") as TileMapLayer).get_used_cells().size() == 72
		and (battle.get("actions") as CombatActions).grid.map_size == Vector2i(8, 9)
		and warrior.cell == Vector2i(1, 8), "다음 스테이지 맵과 배치 데이터를 실제 전투에 적용")
	_check(warrior.hit_points == 5 and warrior.second_wind_left == 0
		and warrior.parry_left == 0 and warrior.surge_left == 0, "같은 막의 HP와 전사 스킬 횟수 유지")
	_check(archer.hit_points == 0 and not archer.visible
		and archer not in (battle.get("turns") as CombatTurns).ordered_units,
		"전투 불능 아군은 같은 막 다음 전투에 나오지 않음")
	_check(warrior.potion_left == 3, "스테이지 전환에서 가진 물약 유지")
	_check(not warrior.is_stunned and warrior.stun_source == null and not warrior.disengaged
		and warrior.marked_target == null and not warrior.has_mark,
		"기절·표식·이번 턴 효과는 전투 전환에서 해제")
	_check(not hud.get_node("Result").visible, "다음 전투에서 이전 승리 창 숨김")


func _next(battle: Node2D) -> void:
	var hud: CombatTurnHud = battle.get_node("UI/TurnHud") as CombatTurnHud
	_win(battle)
	await process_frame
	# 결과 버튼의 실제 포인터 입력을 사용한다.
	var point: Vector2 = root.get_final_transform() * hud.restart_button.get_global_rect().get_center()
	var click: InputEventMouseButton = InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.position = point
	click.global_position = point
	click.pressed = true
	Input.parse_input_event(click)
	await process_frame
	click.pressed = false
	Input.parse_input_event(click)
	await process_frame
	await process_frame
	_finish_rewards(battle)
	await process_frame
	_check_enemy_values(battle, int((battle.get("progress") as CombatActProgress).stage_index) / 3 + 1)


func _finish_rewards(battle: Node2D) -> void:
	var preparation: CombatPreparation = battle.get_node("UI/Preparation") as CombatPreparation
	preparation.continue_button.pressed.emit()
	var missing: int = battle.loot.bag.size() + preparation.rewards.size() - int(battle.loot.data["bag_limit"])
	# 9전투 진행 검사는 가방이 차면 실제 폐기 버튼과 확인을 거쳐 공간을 확보한다.
	for index: int in range(maxi(0, missing)):
		(preparation.content.get_node("BagItem0/Discard") as Button).pressed.emit()
		preparation.discard_dialog.confirmed.emit()
	preparation.continue_button.pressed.emit()
	preparation.discard_dialog.confirmed.emit()


func _test_act_and_defeat(battle: Node2D) -> void:
	var hud: CombatTurnHud = battle.get_node("UI/TurnHud") as CombatTurnHud
	await _next(battle)
	_check(hud.progress_label.text == "1막 · 3스테이지", "1-2에서1-3 진행")
	_check((battle.get_node("Map") as TileMapLayer).get_used_cells().size() == 100,
		"다음 스테이지 데이터가 이전 맵 크기를 덮어씀")
	_win(battle)
	var expected_bag: Array[Dictionary] = battle.loot.bag.duplicate(true)
	expected_bag.append_array(battle.progress.rewards)
	_check(hud.restart_button.text == "보상 확인", "막 마지막 전투도 보상 확인 안내")
	hud.restart_button.pressed.emit()
	var preparation: CombatPreparation = battle.get_node("UI/Preparation") as CombatPreparation
	preparation.continue_button.pressed.emit()
	_check(preparation.continue_button.text == "다음 막 시작", "정비 뒤 다음 막 안내")
	preparation.continue_button.pressed.emit()
	await process_frame
	preparation.discard_dialog.confirmed.emit()
	await process_frame
	_check(hud.progress_label.text == "2막 · 1스테이지", "1-3 승리 뒤2-1 진행")
	_check(battle.loot.bag == expected_bag, "다음 막 시작은 미수령 보상을 더한 공용 가방 보존")
	_check_enemy_values(battle, 2)
	_check((battle.get("turns") as CombatTurns).ordered_units.size() == 7,
		"새 막에서 전투 불능 아군 부활과 적 재배치")
	var party: Array[CombatUnit] = battle.get("party")
	for unit: CombatUnit in party:
		_check(unit.hit_points == unit.get_max_hit_points() and unit.second_wind_left == 1
			and unit.parry_left == 2 and unit.surge_left == 1 and unit.mark_left == 1
			and unit.shock_left == 1 and unit.disengage_left == 2,
			"막 시작에 전원 HP와 기존 스킬 횟수 회복")
	_check(party[0].potion_left == 3 and party[1].potion_left == 0,
		"막 시작은 물약을 지급하거나 제거하지 않음")
	party[1].hit_points = 8
	party[1].mark_left = 0
	party[1].shock_left = 0
	party[1].disengage_left = 0
	await _next(battle)
	_check(hud.progress_label.text == "2막 · 2스테이지" and party[1].hit_points == 8
		and party[1].mark_left == 0 and party[1].shock_left == 0 and party[1].disengage_left == 0,
		"같은 막에서 궁수 HP와 세 스킬 횟수 유지")
	# 전투 중 결과 버튼 신호를 보내도 스테이지가 바뀌지 않는다.
	hud.restart_button.pressed.emit()
	_check(hud.progress_label.text == "2막 · 2스테이지", "전투 중 임의 진행 거부")
	var actions: CombatActions = battle.get("actions") as CombatActions
	expected_bag = battle.loot.bag.duplicate(true)
	for unit: CombatUnit in party:
		(battle.get("actions") as CombatActions).incapacitate(unit)
	party[0].potion_left = 2
	actions.changed.emit()
	_check(hud.result_label.text == "패배" and hud.restart_button.text == "이 막 다시 시작",
		"아군 전멸은 막 재시작 안내")
	actions.busy = true
	hud.restart_button.pressed.emit()
	_check(hud.progress_label.text == "2막 · 2스테이지", "동작 처리 중 막 재시작 거부")
	actions.busy = false
	battle.set("_enemy_turn_running", true)
	hud.restart_button.pressed.emit()
	_check(hud.progress_label.text == "2막 · 2스테이지", "적 턴 처리 중 막 재시작 거부")
	battle.set("_enemy_turn_running", false)
	hud.restart_button.pressed.emit()
	await process_frame
	_check(hud.progress_label.text == "2막 · 1스테이지", "패배한 막의1스테이지로 복귀")
	_check(battle.loot.bag == expected_bag, "전멸한 막 재시작은 공용 가방 전량 보존")
	_check_enemy_values(battle, 2)
	for unit: CombatUnit in party:
		_check(unit.hit_points == unit.get_max_hit_points() and unit.mark_left == 1
			and unit.shock_left == 1 and unit.disengage_left == 2, "전멸 뒤 부활과 스킬 회복")
	_check(party[0].potion_left == 2, "사용한 물약은 막 재시작으로 돌아오지 않음")


func _test_graduation(battle: Node2D) -> void:
	var hud: CombatTurnHud = battle.get_node("UI/TurnHud") as CombatTurnHud
	for label: String in ["2막 · 2스테이지", "2막 · 3스테이지", "3막 · 1스테이지",
			"3막 · 2스테이지", "3막 · 3스테이지"]:
		await _next(battle)
		_check(hud.progress_label.text == label, "정해진 순서: " + label)
	for unit: CombatUnit in battle.get("party"):
		(battle.get("actions") as CombatActions).incapacitate(unit)
	(battle.get("actions") as CombatActions).changed.emit()
	hud.restart_button.pressed.emit()
	await process_frame
	_check(hud.progress_label.text == "3막 · 1스테이지" and not hud.get_node("Result").visible,
		"최종 스테이지 패배도 현재 막의 첫 전투로 복귀")
	_check_enemy_values(battle, 3)
	await _next(battle)
	await _next(battle)
	_win(battle)
	_check(hud.result_label.text == "승리" and hud.restart_button.visible,
		"3-3도 졸업 전에 보상과 정비 제공")
	hud.restart_button.pressed.emit()
	_finish_rewards(battle)
	_check(hud.result_label.text == "3막 졸업" and not hud.restart_button.visible,
		"3-3 승리 뒤 졸업 화면과 추가 스테이지 없음")
	hud.restart_button.pressed.emit()
	_check(hud.progress_label.text == "3막 · 3스테이지"
		and hud.result_label.text == "3막 졸업", "졸업 뒤 진행 신호 무시")


func _test_usage_text(battle: Node2D) -> void:
	var hud: CombatTurnHud = battle.get_node("UI/TurnHud") as CombatTurnHud
	var actions: CombatActions = battle.get("actions") as CombatActions
	var party: Array[CombatUnit] = battle.get("party")
	_check("HP 1d10+1 회복" in hud.action_details(actions, party[0], "second_wind")
		and "막당" not in hud.action_details(actions, party[0], "second_wind"),
		"스킬 호버에는 효과만 남기고 막당 횟수 줄 제거")
	_check("HP 2d4+2 회복" in hud.action_details(actions, party[0], "potion")
		and "\n보유 물약" not in hud.action_details(actions, party[0], "potion"),
		"물약 호버에는 효과만 남기고 보유 개수 줄 제거")
