extends SceneTree
## #364 비교 시안: 스테이지 자원의 배치 불변 조건(progression 검사와 같은 조건)과 가림 칸을 함께 보고한다.
var fails: Array[String] = []
func ck(ok: bool, msg: String) -> void:
	if not ok:
		fails.append(msg)
func _initialize() -> void:
	_run.call_deferred()
func _run() -> void:
	var map: CombatMap = (load("res://scenes/combat/battle.tscn").instantiate() as Node).get_node("Map")
	root.add_child(map.get_parent())
	for arg: String in OS.get_cmdline_user_args():
		if not arg.begins_with("--stage="):
			continue
		var path: String = arg.trim_prefix("--stage=")
		fails.clear()
		var stage: CombatStage = load(path) as CombatStage
		var grid: CombatGrid = CombatGrid.new()
		grid.map_size = stage.map_size
		grid.heights = stage.heights.duplicate()
		grid.pits = stage.pits.duplicate()
		grid.water_cells = stage.water_cells.duplicate()
		grid.blocked_cells = stage.get_blocked_cells()
		for anchor: Vector2i in stage.scenery:
			var size: Vector2i = CombatStage.SCENERY_SIZE[stage.scenery[anchor]]
			for y: int in range(size.y):
				for x: int in range(size.x):
					ck(grid.height_at(anchor + Vector2i(x, y)) == grid.height_at(anchor), "scenery height " + str(anchor))
		for cell: Vector2i in stage.crate_cells:
			grid.props.append(CombatGrid.Prop.new(cell, "crate"))
		for cell: Vector2i in stage.rock_cells:
			grid.props.append(CombatGrid.Prop.new(cell, "rock"))
		var actor: CombatUnit = CombatUnit.new()
		actor.cell = stage.ally_cells[0]
		var unreachable: Array[Vector2i] = []
		var total_path: int = 0
		for y: int in range(stage.map_size.y):
			for x: int in range(stage.map_size.x):
				var cell: Vector2i = Vector2i(x, y)
				if grid.is_floor(cell) and not grid.is_blocked(cell) and cell != actor.cell:
					var p: Array[Vector2i] = grid.path_to(actor, cell)
					if p.is_empty():
						unreachable.append(cell)
					total_path += p.size()
		ck(unreachable.is_empty(), "unreachable " + str(unreachable))
		var enemies: Node = stage.enemies.instantiate()
		var enemy_dist: Array[int] = []
		for unit: CombatUnit in enemies.get_children():
			var p: Array[Vector2i] = grid.path_to(actor, unit.start_cell)
			ck(not p.is_empty(), "enemy spawn path " + str(unit.start_cell))
			enemy_dist.append(p.size())
		for enemy: CombatUnit in enemies.get_children():
			enemy.cell = enemy.start_cell
			grid.units.append(enemy)
			if enemy.kind == CombatUnit.Kind.MOTHER_SPIDER:
				ck(grid.empty_neighbors(enemy.cell).size() == 3, "mother spawn room")
		var crate: CombatGrid.Prop = grid.prop_at(stage.crate_cells[0])
		var gate: Vector2i = crate.cell + Vector2i.RIGHT
		var detour: Array[Vector2i] = grid.path_to(actor, gate)
		grid.props.erase(crate)
		var opened: Array[Vector2i] = grid.path_to(actor, gate)
		ck(not detour.is_empty() and not opened.is_empty() and opened.has(crate.cell) and opened.size() < detour.size(), "crate shortcut %d/%d" % [detour.size(), opened.size()])
		grid.props.append(crate)
		var rock: CombatGrid.Prop = grid.prop_at(stage.rock_cells[0])
		var stand: Vector2i = rock.cell + Vector2i.LEFT
		ck(not grid.path_to(actor, stand).is_empty() and grid.are_adjacent(stand, rock.cell), "rock stand")
		var actions: CombatActions = CombatActions.new()
		actions.grid = grid
		actor.cell = stand
		var roll: CombatActions.RockRoll = actions.preview_rock(actor, rock)
		ck(not roll.collisions.is_empty() and not roll.destroyed, "rock roll hits enemy")
		actor.cell = stage.ally_cells[0]
		grid.units.clear()
		map.build_grid(grid, stage.tile_set, stage)
		var hidden: Array[Vector2i] = []
		for y: int in range(stage.map_size.y):
			for x: int in range(stage.map_size.x):
				var cell: Vector2i = Vector2i(x, y)
				if not grid.is_floor(cell) or grid.blocked_cells.has(cell):
					continue
				var foot: Vector2 = map.map_to_surface(cell)
				for c: Vector2i in map.get_used_cells():
					if c.x + c.y > cell.x + cell.y and not hidden.has(cell):
						for pt: Vector2 in [foot, foot + Vector2(0, -10)]:
							if not hidden.has(cell) and (map.call("_contains_surface", c, pt) or map.call("_contains_sides", c, pt)):
								hidden.append(cell)
		var spawn_hidden: Array[Vector2i] = []
		for unit: CombatUnit in enemies.get_children():
			if hidden.has(unit.start_cell):
				spawn_hidden.append(unit.start_cell)
		for cell: Vector2i in stage.ally_cells:
			if hidden.has(cell):
				spawn_hidden.append(cell)
		var high: int = stage.heights.values().filter(func(h: int) -> bool: return h >= 2).size()
		print("[LAYOUT] %s hidden=%d high2+=%d raised=%d enemy_path=%s total_path=%d spawn_hidden=%s hidden_cells=%s fails=%s" % [path.get_file(), hidden.size(), high, stage.heights.size(), str(enemy_dist), total_path, str(spawn_hidden), str(hidden), str(fails)])
		enemies.free()
		actor.free()
	quit()
