class_name CombatEnemyAi
extends RefCounted
## 기획서 7장의 우선순위. 자원·판정·반응은 CombatActions가 실행한다.


func play_turn(actor: CombatUnit, actions: CombatActions, pause: Callable = Callable()) -> void:
	if not _active(actor, actions):
		return
	if actor.kind == CombatUnit.Kind.WARRIOR:
		await _warrior_turn(actor, actions, pause)
	else:
		await _archer_turn(actor, actions, pause)


func _active(actor: CombatUnit, actions: CombatActions) -> bool:
	return (actor != null and not actor.is_ally and actor.hit_points > 0
		and not actor.is_stunned and actions.turns.current_unit == actor
		and not actions.busy and not actions.is_over())


func _pause(pause: Callable) -> void:
	if pause.is_valid():
		await pause.call()


func _warrior_turn(actor: CombatUnit, actions: CombatActions, pause: Callable) -> void:
	if actor.hit_points * 2 <= actor.get_max_hit_points() and actions.can_use(actor, "second_wind"):
		actions.use_self(actor, "second_wind")
		await _pause(pause)
	if not _active(actor, actions):
		return
	var target: CombatUnit = _attack_target(actor, actions)
	if target == null:
		var destination: Vector2i = _approach(actor, actions)
		if destination != actor.cell:
			await actions.move_to(actor, destination)
			await _pause(pause)
	if not _active(actor, actions):
		return
	target = _attack_target(actor, actions)
	if target == null or not await actions.attack(actor, target):
		return
	await _pause(pause)
	if not _active(actor, actions) or not actions.can_use(actor, "surge"):
		return
	# 공격 뒤 탈락한 대상은 제외한다. 행동 회복 전이므로 거리로 확인한다.
	var remaining: Array[CombatUnit] = _targets(actor, actions)
	for candidate: CombatUnit in remaining:
		if actions.distance(actor.cell, candidate.cell) == 1:
			actions.use_self(actor, "surge")
			await _pause(pause)
			if _active(actor, actions):
				target = _attack_target(actor, actions)
				if target != null:
					await actions.attack(actor, target)
					await _pause(pause)
			return


func _archer_turn(actor: CombatUnit, actions: CombatActions, pause: Callable) -> void:
	if _nearest_distance(actor.cell, _targets(actor, actions), actions) == 1:
		var destination: Vector2i = _retreat(actor, actions)
		if destination != actor.cell:
			if actions.can_use(actor, "disengage"):
				actions.use_self(actor, "disengage")
				await _pause(pause)
			if not _active(actor, actions):
				return
			await actions.move_to(actor, destination)
			await _pause(pause)
	if not _active(actor, actions):
		return
	var target: CombatUnit = _attack_target(actor, actions)
	if target == null:
		var destination: Vector2i = _approach(actor, actions)
		if destination != actor.cell:
			await actions.move_to(actor, destination)
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


func _nearest_distance(cell: Vector2i, targets: Array[CombatUnit], actions: CombatActions) -> int:
	var nearest: int = actions.map_size.x + actions.map_size.y
	for target: CombatUnit in targets:
		nearest = mini(nearest, actions.distance(cell, target.cell))
	return nearest


func _approach(actor: CombatUnit, actions: CombatActions) -> Vector2i:
	var targets: Array[CombatUnit] = _targets(actor, actions)
	if targets.is_empty():
		return actor.cell
	var target: CombatUnit = targets[0]
	for candidate: CombatUnit in targets:
		if actions.distance(actor.cell, candidate.cell) < actions.distance(actor.cell, target.cell):
			target = candidate
	var best: Vector2i = actor.cell
	var best_distance: int = actions.distance(best, target.cell)
	var best_cost: int = 0
	for x: int in range(actions.map_size.x):
		for y: int in range(actions.map_size.y):
			var cell: Vector2i = Vector2i(x, y)
			if not actions.can_move(actor, cell):
				continue
			var separation: int = actions.distance(cell, target.cell)
			var cost: int = actions.path_to(actor, cell).size()
			# 사거리까지 가장 짧게 이동한다. 못 닿으면 가장 가까운 칸을 쓴다.
			var reaches: bool = separation <= actor.get_attack_range()
			var best_reaches: bool = best_distance <= actor.get_attack_range()
			if ((reaches and not best_reaches)
				or (reaches and best_reaches and cost < best_cost)
				or (not reaches and not best_reaches and (separation < best_distance
					or (separation == best_distance and cost < best_cost)))):
				best = cell
				best_distance = separation
				best_cost = cost
	return best


func _retreat(actor: CombatUnit, actions: CombatActions) -> Vector2i:
	var targets: Array[CombatUnit] = _targets(actor, actions)
	var best: Vector2i = actor.cell
	var best_cost: int = actor.movement_left + 1
	# 불리를 없애고 사거리 안에 남는 가장 짧은 이동. 맵/점유 규칙을 그대로 쓴다.
	for x: int in range(actions.map_size.x):
		for y: int in range(actions.map_size.y):
			var cell: Vector2i = Vector2i(x, y)
			if _nearest_distance(cell, targets, actions) <= 1 or not actions.can_move(actor, cell):
				continue
			var cost: int = actions.path_to(actor, cell).size()
			for target: CombatUnit in targets:
				if actions.distance(cell, target.cell) <= actor.get_attack_range() and cost < best_cost:
					best = cell
					best_cost = cost
	return best
