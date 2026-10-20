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
	elif actor.kind == CombatUnit.Kind.ARCHER:
		await _archer_turn(actor, actions, pause)
	else:
		await _warrior_turn(actor, actions, pause)


func _boss_turn(actor: CombatUnit, actions: CombatActions, pause: Callable) -> void:
	while _active(actor, actions) and actor.action_left > 0:
		if (CombatActionRules.belongs_to(actor, "spin") and actions.grid.opponents_in_range(actor, 1).size() >= 2
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


func _warrior_turn(actor: CombatUnit, actions: CombatActions, pause: Callable) -> void:
	var used_second_wind: bool = false
	if actor.hit_points * 2 <= actor.get_max_hit_points() and actions.can_use(actor, "second_wind"):
		used_second_wind = actions.use_self(actor, "second_wind")
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
	if target == null or not await actions.attack(actor, target):
		return
	await _pause(pause)
	if used_second_wind or not _active(actor, actions) or not actions.can_use(actor, "surge"):
		return
	# 공격 뒤 탈락한 대상은 제외한다. 행동 회복 전이므로 거리로 확인한다.
	var remaining: Array[CombatUnit] = _targets(actor, actions)
	for candidate: CombatUnit in remaining:
		if actions.grid.can_target(actor, candidate, "attack"):
			actions.use_self(actor, "surge")
			await _pause(pause)
			if _active(actor, actions):
				target = _attack_target(actor, actions)
				if target != null:
					await actions.attack(actor, target)
					await _pause(pause)
			return


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
func approach_cell(actor: CombatUnit, actions: CombatActions) -> Vector2i:
	var targets: Array[CombatUnit] = _targets(actor, actions)
	if targets.is_empty():
		return actor.cell
	var target: CombatUnit = targets[0]
	for candidate: CombatUnit in targets:
		if CombatGrid.distance(actor.cell, candidate.cell) < CombatGrid.distance(actor.cell, target.cell):
			target = candidate
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
