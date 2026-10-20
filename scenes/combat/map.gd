class_name CombatMap
extends TileMapLayer
## 바닥 높이의 표시 위치와 필드 입력을 같은 좌표로 변환한다.

var grid: CombatGrid
var _overlays: Array[Node2D] = []
var _blocked_markers: Array[Node2D] = []
var _water_markers: Array[Node2D] = []
var _ground_markers: Array[Node2D] = []
var _prop_markers: Array[Node2D] = []


func build_grid(combat_grid: CombatGrid, floors: TileSet) -> void:
	grid = combat_grid
	clear()
	show_movement([], [], [], Vector2i.ZERO)
	show_grounds([])
	show_props([])
	for marker: Node2D in _blocked_markers:
		marker.free()
	_blocked_markers.clear()
	for marker: Node2D in _water_markers:
		marker.free()
	_water_markers.clear()
	tile_set = floors
	if not grid.heights.is_empty():
		tile_set = floors.duplicate(true) as TileSet
	var sources: Dictionary[int, int] = {0: 0}
	for y: int in range(grid.map_size.y):
		for x: int in range(grid.map_size.x):
			var cell: Vector2i = Vector2i(x, y)
			if not grid.is_floor(cell):
				continue
			var height: int = grid.height_at(cell)
			if not sources.has(height):
				sources[height] = _add_height_source(height)
			set_cell(cell, sources[height], Vector2i((x + y) % 2, 0))
	for cell: Vector2i in grid.water_cells:
		if not grid.is_floor(cell) or grid.blocked_cells.has(cell):
			continue
		var marker: Polygon2D = Polygon2D.new()
		marker.position = map_to_local(cell)
		var center: Vector2 = map_to_surface(cell) - marker.position
		var half: Vector2 = Vector2(tile_set.tile_size) / 2.0 - Vector2(2, 1)
		marker.polygon = PackedVector2Array([
			center + Vector2(0, -half.y), center + Vector2(half.x, 0),
			center + Vector2(0, half.y), center + Vector2(-half.x, 0)])
		marker.color = Color("287f92")
		add_child(marker)
		_water_markers.append(marker)
	for cell: Vector2i in grid.blocked_cells:
		if not grid.is_floor(cell):
			continue
		var marker: Node2D = Node2D.new()
		marker.name = "BlockedCell"
		marker.position = map_to_local(cell)
		var center: Vector2 = map_to_surface(cell) - marker.position
		marker.draw.connect(func() -> void:
			marker.draw_colored_polygon(PackedVector2Array([
				center + Vector2(0, -6), center + Vector2(12, 0),
				center + Vector2(0, 6), center + Vector2(-12, 0)]), Color("35414a"))
			marker.draw_line(center + Vector2(-4, -3), center + Vector2(4, 3), Color("edaa54"), 2.0)
			marker.draw_line(center + Vector2(4, -3), center + Vector2(-4, 3), Color("edaa54"), 2.0))
		add_child(marker)
		_blocked_markers.append(marker)


func map_to_surface(cell: Vector2i) -> Vector2:
	var height: int = grid.height_at(cell) if grid != null else 0
	return map_to_local(cell) - Vector2(0, height * tile_set.tile_size.y / 2.0)


func surface_to_map(point: Vector2) -> Vector2i:
	var cells: Array[Vector2i] = get_used_cells()
	cells.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return a.x + a.y > b.x + b.y)
	for cell: Vector2i in cells:
		if _contains_surface(cell, point):
			return cell
		# 앞 칸의 옆면은 뒤 칸의 바닥 클릭도 가린다.
		if _contains_sides(cell, point):
			return Vector2i(-1, -1)
	return Vector2i(-1, -1)


func occludes(unit_cell: Vector2i, point: Vector2) -> bool:
	for cell: Vector2i in get_used_cells():
		if cell.x + cell.y > unit_cell.x + unit_cell.y:
			if _contains_surface(cell, point) or _contains_sides(cell, point):
				return true
	return false


func _contains_surface(cell: Vector2i, point: Vector2) -> bool:
	var offset: Vector2 = (point - map_to_surface(cell)).abs() / (Vector2(tile_set.tile_size) / 2.0)
	return offset.x + offset.y <= 1.0


func _contains_sides(cell: Vector2i, point: Vector2) -> bool:
	var surface: Vector2 = map_to_surface(cell)
	var ground: Vector2 = map_to_local(cell)
	if ground == surface:
		return false
	var half: Vector2 = Vector2(tile_set.tile_size) / 2.0
	return Geometry2D.is_point_in_polygon(point, PackedVector2Array([
		surface + Vector2(-half.x, 0), surface + Vector2(0, half.y),
		surface + Vector2(half.x, 0), ground + Vector2(half.x, 0),
		ground + Vector2(0, half.y), ground + Vector2(-half.x, 0)
	]))


func show_movement(cells: Array[Vector2i], attack_cells: Array[Vector2i],
		path: Array[Vector2i], origin: Vector2i) -> void:
	for overlay: Node2D in _overlays:
		overlay.free()
	_overlays.clear()
	if cells.is_empty() and path.is_empty():
		return
	var half: Vector2 = Vector2(tile_set.tile_size) / 2.0
	for cell: Vector2i in cells:
		var overlay: Polygon2D = Polygon2D.new()
		overlay.position = map_to_local(cell)
		var center: Vector2 = map_to_surface(cell) - overlay.position
		overlay.polygon = PackedVector2Array([
			center + Vector2(0, -half.y), center + Vector2(half.x, 0),
			center + Vector2(0, half.y), center + Vector2(-half.x, 0)
		])
		overlay.color = Color(0.22, 0.8, 0.5, 0.45) if cell in attack_cells else Color(0.22, 0.56, 0.92, 0.4)
		add_child(overlay)
		_overlays.append(overlay)
	var previous: Vector2 = map_to_surface(origin)
	for cell: Vector2i in path:
		var line: Line2D = Line2D.new()
		line.position = map_to_local(cell)
		var destination: Vector2 = map_to_surface(cell)
		line.points = PackedVector2Array([previous - line.position, destination - line.position])
		line.width = 1.0
		line.default_color = Color("f4cf69")
		add_child(line)
		_overlays.append(line)
		previous = destination
	if not path.is_empty():
		var marker: Node2D = Node2D.new()
		marker.position = map_to_local(path[-1])
		var center: Vector2 = previous - marker.position
		marker.draw.connect(func() -> void: marker.draw_circle(center, 3.0, Color("f4cf69"), false))
		add_child(marker)
		_overlays.append(marker)


func show_rock_roll(origin: Vector2i, roll: CombatActions.RockRoll) -> void:
	var previous: Vector2 = map_to_surface(origin)
	for cell: Vector2i in roll.cells:
		var marker: Node2D = Node2D.new()
		marker.position = map_to_local(cell)
		var start: Vector2 = previous - marker.position
		var end: Vector2 = map_to_surface(cell) - marker.position
		var forward: Vector2 = (end - start).normalized()
		marker.draw.connect(func() -> void:
			var color: Color = Color("f5a35c")
			marker.draw_line(start, end, color)
			marker.draw_line(end, end - forward * 4 + forward.orthogonal() * 2, color)
			marker.draw_line(end, end - forward * 4 - forward.orthogonal() * 2, color))
		add_child(marker)
		_overlays.append(marker)
		previous = map_to_surface(cell)
	for unit: CombatUnit in roll.collisions:
		var marker: Node2D = Node2D.new()
		marker.position = map_to_local(unit.cell)
		var center: Vector2 = map_to_surface(unit.cell) - marker.position
		marker.draw.connect(func() -> void: marker.draw_circle(center, 5.0, Color("f07b73"), false))
		add_child(marker)
		_overlays.append(marker)
	if not roll.reason.is_empty():
		var marker: Node2D = Node2D.new()
		marker.position = map_to_local(roll.stop_cell)
		var center: Vector2 = map_to_surface(roll.stop_cell) - marker.position
		marker.draw.connect(func() -> void: marker.draw_circle(center, 2.0, Color("f07b73"), false))
		add_child(marker)
		_overlays.append(marker)


func show_grounds(grounds: Array[CombatActions.Ground]) -> void:
	for marker: Node2D in _ground_markers:
		marker.free()
	_ground_markers.clear()
	for ground: CombatActions.Ground in grounds:
		var marker: Node2D = Node2D.new()
		marker.position = map_to_local(ground.cell)
		var center: Vector2 = map_to_surface(ground.cell) - marker.position
		center.x += -7 if ground.kind == "burn" else 7
		marker.draw.connect(func() -> void:
			var color: Color = Color("ffb653") if ground.kind == "burn" else Color("b3e86c")
			if ground.kind == "burn":
				marker.draw_colored_polygon(PackedVector2Array([
					center + Vector2(-4, 2), center + Vector2(-2, -3), center + Vector2(0, -1),
					center + Vector2(2, -5), center + Vector2(4, 2), center + Vector2(0, 4)]), color)
			else:
				marker.draw_line(center + Vector2(-3, -3), center + Vector2(3, 3), color, 2.0)
				marker.draw_line(center + Vector2(3, -3), center + Vector2(-3, 3), color, 2.0)
			for index: int in range(ground.turns_left):
				marker.draw_circle(center + Vector2(-3 + index * 2, 6), 0.75, color))
		add_child(marker)
		_ground_markers.append(marker)


func prop_at_point(point: Vector2) -> CombatGrid.Prop:
	var props: Array[CombatGrid.Prop] = grid.props.duplicate()
	props.sort_custom(func(a: CombatGrid.Prop, b: CombatGrid.Prop) -> bool:
		return a.cell.x + a.cell.y > b.cell.x + b.cell.y)
	for prop: CombatGrid.Prop in props:
		if (Rect2(map_to_surface(prop.cell) + Vector2(-10, -14), Vector2(20, 20)).has_point(point)
			and not occludes(prop.cell, point)):
			return prop
	return null


func show_props(props: Array[CombatGrid.Prop], preview: CombatGrid.Prop = null) -> void:
	for marker: Node2D in _prop_markers:
		marker.free()
	_prop_markers.clear()
	for prop: CombatGrid.Prop in props:
		var marker: Node2D = Node2D.new()
		marker.position = map_to_local(prop.cell)
		var center: Vector2 = map_to_surface(prop.cell) - marker.position
		marker.draw.connect(func() -> void:
			if prop.kind == "rock":
				var outline: PackedVector2Array = [
					center + Vector2(-9, -4), center + Vector2(-7, -10), center + Vector2(-2, -13),
					center + Vector2(6, -11), center + Vector2(10, -5), center + Vector2(7, 2),
					center + Vector2(-6, 4), center + Vector2(-9, -4)]
				marker.draw_colored_polygon(outline, Color("77858c"))
				marker.draw_colored_polygon(PackedVector2Array([
					center + Vector2(-9, -4), center + Vector2(1, -1), center + Vector2(10, -5),
					center + Vector2(7, 2), center + Vector2(-6, 4)]), Color("4c5962"))
				marker.draw_polyline(outline, Color("f4cf69") if prop == preview else Color("303b42"))
				marker.draw_line(center + Vector2(-3, -9), center + Vector2(3, -5), Color("b2c1c6"))
				return
			marker.draw_colored_polygon(PackedVector2Array([
				center + Vector2(-8, -9), center + Vector2(0, -5),
				center + Vector2(0, 3), center + Vector2(-8, -1)]), Color("a27643"))
			marker.draw_colored_polygon(PackedVector2Array([
				center + Vector2(0, -5), center + Vector2(8, -9),
				center + Vector2(8, -1), center + Vector2(0, 3)]), Color("68442b"))
			marker.draw_colored_polygon(PackedVector2Array([
				center + Vector2(-8, -9), center + Vector2(0, -13),
				center + Vector2(8, -9), center + Vector2(0, -5)]), Color("c99b5c"))
			var edge: Color = Color("f4cf69") if prop == preview else Color("382c21")
			marker.draw_polyline(PackedVector2Array([
				center + Vector2(-8, -1), center + Vector2(-8, -9), center + Vector2(0, -13),
				center + Vector2(8, -9), center + Vector2(8, -1), center + Vector2(0, 3),
				center + Vector2(-8, -1)]), edge)
			marker.draw_line(center + Vector2(-6, -15), center + Vector2(6, -15), Color("382c21"), 2.0)
			marker.draw_line(center + Vector2(-6, -15), center + Vector2(-6 + prop.hit_points * 2, -15),
				Color("e7bf6d"), 2.0))
		add_child(marker)
		_prop_markers.append(marker)


func _add_height_source(height: int) -> int:
	var size: Vector2i = tile_set.tile_size
	var rise: int = roundi(height * size.y / 2.0)
	var depth: int = absi(rise)
	var floor_image: Image = (tile_set.get_source(0) as TileSetAtlasSource).texture.get_image()
	floor_image.convert(Image.FORMAT_RGBA8)
	var image: Image = Image.create(size.x * 2, size.y + depth, false, Image.FORMAT_RGBA8)
	for index: int in range(2):
		var left: int = index * size.x
		var shade: Color = floor_image.get_pixel(left + size.x / 2, size.y / 2).darkened(0.3)
		var center: Vector2 = Vector2(size.x / 2.0, size.y / 2.0 + maxi(-rise, 0))
		var bottom: Vector2 = center + Vector2(0, rise)
		for direction: int in [-1, 1]:
			var side: PackedVector2Array = [
				center + Vector2(direction * size.x / 2.0, 0), center + Vector2(0, size.y / 2.0),
				bottom + Vector2(0, size.y / 2.0), bottom + Vector2(direction * size.x / 2.0, 0)
			]
			for y: int in range(image.get_height()):
				for x: int in range(size.x):
					if Geometry2D.is_point_in_polygon(Vector2(x + 0.5, y + 0.5), side):
						image.set_pixel(left + x, y, shade.darkened(0.2) if direction > 0 else shade)
	image.blend_rect(floor_image, Rect2i(Vector2i.ZERO, Vector2i(size.x * 2, size.y)),
		Vector2i(0, maxi(-rise, 0)))
	var source: TileSetAtlasSource = TileSetAtlasSource.new()
	source.texture_region_size = Vector2i(size.x, size.y + depth)
	source.texture = ImageTexture.create_from_image(image)
	for index: int in range(2):
		source.create_tile(Vector2i(index, 0))
		source.get_tile_data(Vector2i(index, 0), 0).texture_origin = Vector2i(0, roundi(rise / 2.0))
		source.get_tile_data(Vector2i(index, 0), 0).y_sort_origin = -1
	return tile_set.add_source(source)
