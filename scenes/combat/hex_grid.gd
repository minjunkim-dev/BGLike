class_name CombatHexGrid
extends RefCounted
## pointy-top, TileSet STACKED / HORIZONTAL과 같은 홀수 행 오른쪽 오프셋.

const DIRECTIONS: Array[Vector2i] = [
	Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 1),
	Vector2i(-1, 0), Vector2i(0, -1), Vector2i(1, -1)
]

var units: Array[CombatUnit] = []
var map_size: Vector2i = Vector2i(10, 10)


class Routes extends RefCounted:
	var parents: Dictionary[Vector2i, Vector2i] = {}
	var costs: Dictionary[Vector2i, int] = {}


static func to_axial(cell: Vector2i) -> Vector2i:
	return Vector2i(cell.x - (cell.y - (cell.y & 1)) / 2, cell.y)


static func from_axial(cell: Vector2i) -> Vector2i:
	return Vector2i(cell.x + (cell.y - (cell.y & 1)) / 2, cell.y)


static func distance(a: Vector2i, b: Vector2i) -> int:
	var delta: Vector2i = to_axial(b) - to_axial(a)
	return maxi(maxi(absi(delta.x), absi(delta.y)), absi(delta.x + delta.y))


static func neighbors(cell: Vector2i) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	var axial: Vector2i = to_axial(cell)
	for direction: Vector2i in DIRECTIONS:
		result.append(from_axial(axial + direction))
	return result


static func push_destination(origin: Vector2i, target: Vector2i) -> Vector2i:
	return from_axial(to_axial(target) * 2 - to_axial(origin))


func unit_at(cell: Vector2i) -> CombatUnit:
	for unit: CombatUnit in units:
		if unit.hit_points > 0 and unit.cell == cell:
			return unit
	return null


func is_inside(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.y >= 0 and cell.x < map_size.x and cell.y < map_size.y


func path_to(actor: CombatUnit, destination: Vector2i) -> Array[Vector2i]:
	var path: Array[Vector2i] = []
	if actor == null or not is_inside(destination) or unit_at(destination) != null:
		return path
	var routes: Routes = _search(actor.cell, map_size.x * map_size.y, destination)
	if not routes.parents.has(destination):
		return path
	var cursor: Vector2i = destination
	while cursor != actor.cell:
		path.push_front(cursor)
		cursor = routes.parents[cursor]
	return path


func reachable_cells(actor: CombatUnit) -> Dictionary[Vector2i, int]:
	if actor == null:
		return {}
	var routes: Routes = _search(actor.cell, actor.movement_left)
	routes.costs.erase(actor.cell)
	return routes.costs


func _search(origin: Vector2i, budget: int, destination: Vector2i = Vector2i(-1, -1)) -> Routes:
	var routes: Routes = Routes.new()
	routes.parents[origin] = origin
	routes.costs[origin] = 0
	var frontier: Array[Vector2i] = [origin]
	var index: int = 0
	while index < frontier.size() and not routes.parents.has(destination):
		var here: Vector2i = frontier[index]
		index += 1
		var cost: int = routes.costs[here] + 1
		if cost > budget:
			continue
		# 이웃 순서는 같은 비용의 경로와 AI 선택을 결정한다.
		for next: Vector2i in neighbors(here):
			if is_inside(next) and not routes.parents.has(next) and unit_at(next) == null:
				routes.parents[next] = here
				routes.costs[next] = cost
				frontier.append(next)
	return routes


static func in_range(origin: Vector2i, target: Vector2i, maximum: int, minimum: int = 1) -> bool:
	var separation: int = distance(origin, target)
	return separation >= minimum and separation <= maximum


func can_target(actor: CombatUnit, target: CombatUnit, action: String,
	from_cell: Vector2i = Vector2i(-1, -1)) -> bool:
	if actor == null or target == null:
		return false
	var origin: Vector2i = actor.cell if from_cell == Vector2i(-1, -1) else from_cell
	match action:
		"attack":
			return in_range(origin, target.cell, actor.get_attack_range())
		"shock", "mark":
			return in_range(origin, target.cell, CombatActionRules.SKILL_RANGE)
		"shove":
			return in_range(origin, target.cell, 1) and can_shove(actor, target)
		"pull":
			return in_range(origin, target.cell, 3, 2) and not pull_cells(actor, target, origin).is_empty()
	return false


func opponents_in_range(actor: CombatUnit, maximum: int) -> Array[CombatUnit]:
	var targets: Array[CombatUnit] = []
	for unit: CombatUnit in units:
		if (unit.hit_points > 0 and unit.is_ally != actor.is_ally
			and in_range(actor.cell, unit.cell, maximum)):
			targets.append(unit)
	return targets


static func leaves_reach(reactor: CombatUnit, origin: Vector2i, destination: Vector2i) -> bool:
	return in_range(reactor.cell, origin, 1) and distance(reactor.cell, destination) > 1


func empty_neighbors(origin: Vector2i) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for cell: Vector2i in neighbors(origin):
		if is_inside(cell) and unit_at(cell) == null:
			cells.append(cell)
	return cells


func pull_cells(actor: CombatUnit, target: CombatUnit,
	from_cell: Vector2i = Vector2i(-1, -1)) -> Array[Vector2i]:
	var origin: Vector2i = actor.cell if from_cell == Vector2i(-1, -1) else from_cell
	var cells: Array[Vector2i] = []
	var nearest: int = map_size.x + map_size.y
	for cell: Vector2i in neighbors(origin):
		var occupant: CombatUnit = unit_at(cell)
		if not is_inside(cell) or (occupant != null and occupant != actor):
			continue
		var separation: int = distance(cell, target.cell)
		if separation < nearest:
			nearest = separation
			cells.clear()
		if separation == nearest:
			cells.append(cell)
	return cells


func can_shove(actor: CombatUnit, target: CombatUnit) -> bool:
	if actor == null or target == null or not in_range(actor.cell, target.cell, 1):
		return false
	var destination: Vector2i = push_destination(actor.cell, target.cell)
	return is_inside(destination) and unit_at(destination) == null


func nearest_distance(cell: Vector2i, targets: Array[CombatUnit]) -> int:
	var nearest: int = map_size.x + map_size.y
	for target: CombatUnit in targets:
		nearest = mini(nearest, distance(cell, target.cell))
	return nearest


func attack_preview(attacker: CombatUnit, target: CombatUnit) -> CombatChecks.AttackPreview:
	var preview: CombatChecks.AttackPreview = CombatChecks.AttackPreview.new()
	if (attacker == null or target == null or attacker.is_ally == target.is_ally
		or attacker.hit_points <= 0 or target.hit_points <= 0):
		return preview
	preview.valid_target = true
	if attacker.is_stunned:
		preview.blocked_reason = "기절하여 공격 불가"
	preview.in_range = in_range(attacker.cell, target.cell, attacker.get_attack_range())
	var advantages: int = 0
	var disadvantages: int = 0
	if target.is_stunned:
		advantages = 1
		preview.reasons.append("기절한 대상")
	if attacker.kind == CombatUnit.Kind.ARCHER:
		for unit: CombatUnit in opponents_in_range(attacker, 1):
			if not unit.is_stunned:
				disadvantages = 1
				preview.reasons.append("옆에 적")
				break
	preview.mode = CombatChecks.roll_mode(advantages, disadvantages)
	if preview.in_range and preview.blocked_reason.is_empty():
		preview.chance = CombatChecks.hit_chance(attacker.get_attack_bonus(), target.get_armor_class(), preview.mode)
	return preview
