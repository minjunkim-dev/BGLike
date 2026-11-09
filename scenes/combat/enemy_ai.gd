class_name CombatEnemyAi
extends RefCounted
## 기획서 7장의 우선순위. 자원·판정·반응은 CombatActions가 실행한다.


func play_turn(actor: CombatUnit, actions: CombatActions, pause: Callable = Callable()) -> void:
	if not _active(actor, actions):
		return
	if actor.is_boss():
		await _boss_turn(actor, actions, pause)
	elif actor.kind == CombatUnit.Kind.MOTHER_SPIDER and actions.spawn_spiderling(actor):
		await _pause(pause)
		return
	elif actor.kind == CombatUnit.Kind.FOG_SPIDER:
		await _fog_spider_turn(actor, actions, pause)
	elif actor.kind == CombatUnit.Kind.ARCHER:
		await _archer_turn(actor, actions, pause)
	else:
		await _warrior_turn(actor, actions, pause)


func _boss_turn(actor: CombatUnit, actions: CombatActions, pause: Callable) -> void:
	while _active(actor, actions) and actor.action_left > 0:
		if (CombatActionRules.belongs_to(actor, "spin") and actions.grid.opponents_in_area(actor, 1).size() >= 2
			and await actions.spin(actor)):
			await _pause(pause)
			continue
		if await _try_pull(actor, actions, pause):
			continue
		if not _active(actor, actions):
			return
		var target: CombatUnit = _attack_target(actor, actions)
		if target == null:
			var destination: Vector2i = approach_cell(actor, actions)
			if destination != actor.cell:
				await _move_to(actor, actions, destination)
				await _pause(pause)
		if not _active(actor, actions):
			return
		target = _attack_target(actor, actions)
		if target == null or not await actions.attack(actor, target):
			return
		await _pause(pause)


func _pull_target(actor: CombatUnit, actions: CombatActions, targets: Array[CombatUnit],
	from_cell: Vector2i = Vector2i(-1, -1)) -> CombatUnit:
	var origin: Vector2i = actor.cell if from_cell == Vector2i(-1, -1) else from_cell
	var farthest: CombatUnit
	var farthest_distance: int = 0
	for target: CombatUnit in targets:
		var separation: int = CombatGrid.distance(origin, target.cell)
		if actions.can_target(actor, target, "pull", origin) and separation > farthest_distance:
			farthest = target
			farthest_distance = separation
	return farthest


func _pull_approach_cell(actor: CombatUnit, actions: CombatActions,
	targets: Array[CombatUnit]) -> Vector2i:
	var best: Vector2i = actor.cell
	var best_cost: int = actor.movement_left + 1
	var reachable: Dictionary[Vector2i, int] = _movement_cells(actor, actions)
	for cell: Vector2i in reachable:
		if reachable[cell] < best_cost and _pull_target(actor, actions, targets, cell) != null:
			best = cell
			best_cost = reachable[cell]
	return best


func _try_pull(actor: CombatUnit, actions: CombatActions, pause: Callable) -> bool:
	if (not CombatActionRules.belongs_to(actor, "pull") or actor.pull_cooldown > 0
		or actor.action_left == 0):
		return false
	var targets: Array[CombatUnit] = []
	for candidate: CombatUnit in _targets(actor, actions):
		if not actions.grid.in_range(actor.cell, candidate.cell, 1, 0):
			targets.append(candidate)
	var target: CombatUnit = _pull_target(actor, actions, targets)
	if target == null:
		var destination: Vector2i = _pull_approach_cell(actor, actions, targets)
		if destination != actor.cell:
			await _move_to(actor, actions, destination)
			await _pause(pause)
	if not _active(actor, actions):
		return false
	target = _pull_target(actor, actions, targets)
	if target == null or not actions.pull(actor, target):
		return false
	await _pause(pause)
	return true


func _active(actor: CombatUnit, actions: CombatActions) -> bool:
	return (actor != null and not actor.is_ally and actor.hit_points > 0
		and not actor.is_stunned and actions.turns.current_unit == actor
		and not actions.busy and not actions.is_over())


func _pause(pause: Callable) -> void:
	if pause.is_valid():
		await pause.call()


func _warrior_turn(actor: CombatUnit, actions: CombatActions, pause: Callable, focus: CombatUnit = null) -> void:
	if actor.hit_points * 2 <= actor.get_max_hit_points() and actions.can_use(actor, "second_wind"):
		actions.use_self(actor, "second_wind")
		await _pause(pause)
	if not _active(actor, actions):
		return
	var target: CombatUnit = _attack_target(actor, actions)
	if target == null:
		var destination: Vector2i = approach_cell(actor, actions, focus)
		if destination != actor.cell:
			await _move_to(actor, actions, destination)
			await _pause(pause)
	if not _active(actor, actions):
		return
	target = _attack_target(actor, actions)
	if target == null or not await actions.attack(actor, target):
		return
	await _pause(pause)


## 독안개 거미: 유효한 시전이 2건 미만이면 독안개를 쓰고 그 턴은 끝난다. 아니면 가장 가까운 아군에게 가서 기본 공격한다.
func _fog_spider_turn(actor: CombatUnit, actions: CombatActions, pause: Callable) -> void:
	if actions.fog_cast_count(actor) < 2 and actor.action_left > 0 and await _try_fog(actor, actions, pause):
		return
	await _warrior_turn(actor, actions, pause, _walk_nearest(actor, actions)[0])


func _try_fog(actor: CombatUnit, actions: CombatActions, pause: Callable) -> bool:
	var plan: Array = _fog_plan(actor, actions)
	if plan.is_empty():
		return false
	if plan[0] != actor.cell:
		await _move_to(actor, actions, plan[0])
		await _pause(pause)
	if not _active(actor, actions) or not actions.cast_fog(actor, plan[1]):
		return false
	await _pause(pause)
	return true


## [걸어서 가장 가까운 아군, 그중 mark 칸 밖에 있는 아군]. 걷기 거리가 같으면 공통 규칙(HP 낮은 쪽, 배치 순서)이고, 없으면 null이다.
func _walk_nearest(actor: CombatUnit, actions: CombatActions, mark: Array[Vector2i] = []) -> Array:
	var costs: Dictionary[Vector2i, int] = actions.grid.walk_costs(actor.cell)
	var distances: Dictionary[CombatUnit, int] = {}
	var nearest: CombatUnit
	var nearest_free: CombatUnit
	for ally: CombatUnit in _targets(actor, actions):
		for neighbor: Vector2i in CombatGrid.neighbors(ally.cell):
			if costs.has(neighbor) and costs[neighbor] + 1 < distances.get(ally, costs.size() + 2):
				distances[ally] = costs[neighbor] + 1
		if not distances.has(ally):
			continue
		if nearest == null or distances[ally] < distances[nearest]:
			nearest = ally
		if ally.cell not in mark and (nearest_free == null or distances[ally] < distances[nearest_free]):
			nearest_free = ally
	return [nearest, nearest_free]


## [서는 칸, 지정 칸] 또는 시전할 수 없으면 빈 배열.
## 가장 가까운 아군은 걷기 경로 거리, 같으면 공통 규칙(HP 낮은 쪽, 배치 순서)이다.
func _fog_plan(actor: CombatUnit, actions: CombatActions) -> Array:
	var fog: Array[Vector2i] = actions.fog_cells()
	var found: Array = _walk_nearest(actor, actions, fog)
	var nearest: CombatUnit = found[0]
	var nearest_free: CombatUnit = found[1]
	var costs: Dictionary[Vector2i, int] = actions.grid.walk_costs(actor.cell)
	if nearest == null:
		return []
	var stands: Dictionary[Vector2i, int] = _movement_cells(actor, actions, false)
	stands[actor.cell] = 0
	if nearest_free != null:
		return _fog_plan_for_ally(actor, actions, nearest_free, actions.fog_cells(actor), stands)
	return _fog_plan_on_path(actor, actions, nearest, fog, stands, costs)


## 아군이 영역에 드는 칸 중 자기 독안개와 겹침이 가장 적은 칸 (같으면 아군 칸, 그다음 거미에 가까운 칸).
func _fog_plan_for_ally(actor: CombatUnit, actions: CombatActions, ally: CombatUnit, mine: Array[Vector2i],
	stands: Dictionary[Vector2i, int]) -> Array:
	var best: Array = []
	var best_key: Array[int] = []
	for aim: Vector2i in [ally.cell] + CombatGrid.neighbors(ally.cell):
		if ally.cell not in actions.aim_area(actor, "fog", aim):
			continue
		var stand: Vector2i = _fog_stand(actor, actions, aim, ally.cell, stands)
		if stand == Vector2i(-1, -1):
			continue
		var overlap: int = actions.aim_area(actor, "fog", aim).filter(func(cell: Vector2i) -> bool: return cell in mine).size()
		var key: Array[int] = [overlap, 0 if aim == ally.cell else 1, CombatGrid.distance(actor.cell, aim)]
		if best.is_empty() or key < best_key:
			best = [stand, aim]
			best_key = key
	return best


## 모든 아군이 독안개 위일 때: 가장 가까운 아군까지 걷는 경로 위 독안개 없는 칸 중 거미에서 가장 먼 칸.
## 영역은 겹칠 수 있으므로 자기 독안개와의 겹침이 적은 칸이 먼저이고, 같으면 더 먼 칸이다.
func _fog_plan_on_path(actor: CombatUnit, actions: CombatActions, ally: CombatUnit, fog: Array[Vector2i],
	stands: Dictionary[Vector2i, int], costs: Dictionary[Vector2i, int]) -> Array:
	var approach: Vector2i = actor.cell
	var approach_cost: int = -1
	for neighbor: Vector2i in CombatGrid.neighbors(ally.cell):
		if costs.has(neighbor) and (approach_cost < 0 or costs[neighbor] < approach_cost):
			approach = neighbor
			approach_cost = costs[neighbor]
	var path: Array[Vector2i] = [actor.cell]
	path.append_array(actions.grid.path_to(actor, approach))
	var best: Array = []
	var best_overlap: int = 0
	var mine: Array[Vector2i] = actions.fog_cells(actor)
	for index: int in range(path.size() - 1, -1, -1):
		var aim: Vector2i = path[index]
		if aim in fog:
			continue
		var stand: Vector2i = _fog_stand(actor, actions, aim, ally.cell, stands)
		if stand == Vector2i(-1, -1):
			continue
		var overlap: int = actions.aim_area(actor, "fog", aim).filter(func(cell: Vector2i) -> bool: return cell in mine).size()
		if best.is_empty() or overlap < best_overlap:
			best = [stand, aim]
			best_overlap = overlap
	return best


## aim을 사거리 안에 두는 가장 짧은 이동의 칸 (같으면 아군에게서 먼 칸). 없으면 (-1, -1).
func _fog_stand(actor: CombatUnit, actions: CombatActions, aim: Vector2i, ally_cell: Vector2i,
	stands: Dictionary[Vector2i, int]) -> Vector2i:
	var best: Vector2i = Vector2i(-1, -1)
	for stand: Vector2i in stands:
		if not actions.can_aim(actor, "fog", aim, stand):
			continue
		if (best == Vector2i(-1, -1) or stands[stand] < stands[best]
			or stands[stand] == stands[best] and CombatGrid.distance(stand, ally_cell) > CombatGrid.distance(best, ally_cell)):
			best = stand
	return best


func _archer_turn(actor: CombatUnit, actions: CombatActions, pause: Callable) -> void:
	if _targets(actor, actions).any(func(target: CombatUnit) -> bool:
		return actions.grid.are_adjacent(actor.cell, target.cell)):
		var destination: Vector2i = _retreat(actor, actions, false)
		if destination != actor.cell:
			if actions.can_use(actor, "disengage"):
				actions.use_self(actor, "disengage")
				await _pause(pause)
			if not _active(actor, actions):
				return
		else:
			destination = _retreat(actor, actions)
		if destination != actor.cell:
			await _move_to(actor, actions, destination)
			await _pause(pause)
	if not _active(actor, actions):
		return
	var target: CombatUnit = _attack_target(actor, actions)
	if target == null:
		var destination: Vector2i = approach_cell(actor, actions)
		if destination != actor.cell:
			await _move_to(actor, actions, destination)
			await _pause(pause)
	if not _active(actor, actions):
		return
	target = _attack_target(actor, actions)
	if target == null:
		return
	if actions.can_target(actor, target, "mark"):
		actions.mark(actor, target)
		await _pause(pause)
	if _active(actor, actions):
		await actions.attack(actor, target, actions.can_target(actor, target, "shock"))
		await _pause(pause)


func _movement_cells(actor: CombatUnit, actions: CombatActions, include_jump: bool = true) -> Dictionary[Vector2i, int]:
	var cells: Dictionary[Vector2i, int] = actions.reachable_cells(actor)
	if include_jump:
		var jumps: Dictionary[Vector2i, int] = actions.jump_cells(actor)
		for cell: Vector2i in jumps:
			if not cells.has(cell) and actions.fall_damage(actor, cell) == 0:
				cells[cell] = jumps[cell]
	return cells


func _move_to(actor: CombatUnit, actions: CombatActions, destination: Vector2i) -> void:
	if actions.can_move(actor, destination):
		await actions.move_to(actor, destination)
	else:
		await actions.jump_to(actor, destination)


func _targets(actor: CombatUnit, actions: CombatActions) -> Array[CombatUnit]:
	var targets: Array[CombatUnit] = []
	for unit: CombatUnit in actions.units:
		if unit.hit_points > 0 and unit.is_ally != actor.is_ally:
			targets.append(unit)
	# HP가 같으면 배치 순서를 보존한다. HP가 낮은 대상을 우선한다.
	targets.sort_custom(func(a: CombatUnit, b: CombatUnit) -> bool:
		if a.hit_points != b.hit_points:
			return a.hit_points < b.hit_points
		return actions.units.find(a) < actions.units.find(b)
	)
	return targets


func _attack_target(actor: CombatUnit, actions: CombatActions) -> CombatUnit:
	for target: CombatUnit in _targets(actor, actions):
		if actions.can_target(actor, target, "attack"):
			return target
	return null


## 공격 사거리까지 가장 짧게 가는 칸. 못 닿으면 가장 가까운 대상에 가장 가까운 칸이다.
func approach_cell(actor: CombatUnit, actions: CombatActions, focus: CombatUnit = null) -> Vector2i:
	var targets: Array[CombatUnit] = _targets(actor, actions)
	if targets.is_empty():
		return actor.cell
	var target: CombatUnit = targets[0]
	for candidate: CombatUnit in targets:
		if CombatGrid.distance(actor.cell, candidate.cell) < CombatGrid.distance(actor.cell, target.cell):
			target = candidate
	if focus != null:
		target = focus
	var best: Vector2i = actor.cell
	var best_distance: int = CombatGrid.distance(best, target.cell)
	var best_cost: int = 0
	var reachable: Dictionary[Vector2i, int] = _movement_cells(actor, actions)
	for x: int in range(actions.grid.map_size.x):
		for y: int in range(actions.grid.map_size.y):
			var cell: Vector2i = Vector2i(x, y)
			if not reachable.has(cell):
				continue
			var separation: int = CombatGrid.distance(cell, target.cell)
			var cost: int = reachable[cell]
			# 사거리까지 가장 짧게 이동한다. 못 닿으면 가장 가까운 칸을 쓴다.
			var reaches: bool = actions.grid.can_target(actor, target, "attack", cell)
			var best_reaches: bool = actions.grid.can_target(actor, target, "attack", best)
			if ((reaches and not best_reaches)
				or (reaches and best_reaches and cost < best_cost)
				or (not reaches and not best_reaches and (separation < best_distance
					or (separation == best_distance and cost < best_cost)))):
				best = cell
				best_distance = separation
				best_cost = cost
	return best


func _retreat(actor: CombatUnit, actions: CombatActions, include_jump: bool = true) -> Vector2i:
	var targets: Array[CombatUnit] = _targets(actor, actions)
	var best: Vector2i = actor.cell
	var best_cost: int = actor.movement_left + 1
	var reachable: Dictionary[Vector2i, int] = _movement_cells(actor, actions, include_jump)
	# 모든 인접 위협에서 벗어나는 가장 짧은 이동. 같은 비용이면 맵 순서상 앞 칸이다.
	for x: int in range(actions.grid.map_size.x):
		for y: int in range(actions.grid.map_size.y):
			var cell: Vector2i = Vector2i(x, y)
			if not reachable.has(cell) or targets.any(func(target: CombatUnit) -> bool:
				return actions.grid.are_adjacent(cell, target.cell)):
				continue
			var cost: int = reachable[cell]
			if cost < best_cost:
				best = cell
				best_cost = cost
	return best
