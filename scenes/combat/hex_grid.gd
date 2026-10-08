class_name CombatHexGrid
extends RefCounted
## pointy-top, TileSet STACKED / HORIZONTAL과 같은 홀수 행 오른쪽 오프셋.

const DIRECTIONS: Array[Vector2i] = [
	Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 1),
	Vector2i(-1, 0), Vector2i(0, -1), Vector2i(1, -1)
]


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
