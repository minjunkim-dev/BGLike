class_name CombatMap
extends TileMapLayer
## 바닥 높이의 표시 위치와 필드 입력을 같은 좌표로 변환한다.

var grid: CombatGrid
var _overlays: Array[Node2D] = []
var _blocked_markers: Array[Node2D] = []
var _ground_markers: Array[Node2D] = []
var _prop_markers: Array[Node2D] = []


func build_grid(combat_grid: CombatGrid, floors: TileSet, stage: CombatStage = null) -> void:
	grid = combat_grid
	clear()
	show_movement([], [], [], Vector2i.ZERO)
	show_grounds([])
	show_props([])
	for marker: Node2D in _blocked_markers:
		marker.free()
	_blocked_markers.clear()
	tile_set = floors.duplicate(true) as TileSet
	var sources: Dictionary[int, int] = {}
	for y: int in range(grid.map_size.y):
		for x: int in range(grid.map_size.x):
			var cell: Vector2i = Vector2i(x, y)
			if not grid.is_floor(cell):
				continue
			var height: int = grid.height_at(cell)
			if not sources.has(height):
				sources[height] = _add_height_source(height)
			var material: int = 0
			if stage != null:
				if stage.path_cells.has(cell):
					material = 2
				if stage.stone_cells.has(cell):
					material = 4
			if grid.water_cells.has(cell):
				material = 6
			set_cell(cell, sources[height], Vector2i(material + (x + y) % 2, 0))
	var occupied: Array[Vector2i] = []
	if stage != null:
		for anchor: Vector2i in stage.scenery:
			var id: String = stage.scenery[anchor]
			var size: Vector2i = CombatStage.SCENERY_SIZE[id]
			var front: Vector2i = anchor + size - Vector2i.ONE
			var marker: Node2D = _art_marker(front, id, 8.0 if id == "cottage" else 4.0)
			marker.set_meta("cell", front)
			add_child(marker)
			_blocked_markers.append(marker)
			for y: int in range(size.y):
				for x: int in range(size.x):
					occupied.append(anchor + Vector2i(x, y))
	for cell: Vector2i in grid.blocked_cells:
		if grid.is_floor(cell) and not occupied.has(cell):
			var marker: Node2D = _art_marker(cell, "ruin_wall", 4.0)
			marker.name = "BlockedCell"
			marker.set_meta("cell", cell)
			add_child(marker)
			_blocked_markers.append(marker)

func map_to_surface(cell: Vector2i) -> Vector2:
	var height: int = grid.height_at(cell) if grid != null else 0
	return map_to_local(cell) - Vector2(0, height * tile_set.tile_size.y / 2.0)


func surface_to_map(point: Vector2) -> Vector2i:
	var scenery: Node2D
	for marker: Node2D in _blocked_markers:
		if _art_contains(marker, point) and (scenery == null or marker.position.y > scenery.position.y):
			scenery = marker
	var cells: Array[Vector2i] = get_used_cells()
	cells.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return a.x + a.y > b.x + b.y)
	for cell: Vector2i in cells:
		if _contains_surface(cell, point) or _contains_sides(cell, point):
			if scenery != null and scenery.position.y >= map_to_local(cell).y:
				return scenery.get_meta("cell") as Vector2i
			return cell if _contains_surface(cell, point) else Vector2i(-1, -1)
	return scenery.get_meta("cell") as Vector2i if scenery != null else Vector2i(-1, -1)


func occludes(unit_cell: Vector2i, point: Vector2) -> bool:
	for marker: Node2D in _blocked_markers + _prop_markers:
		if marker.position.y > map_to_local(unit_cell).y and _art_contains(marker, point):
			return true
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
	var ground: Vector2 = map_to_local(cell) + Vector2(0, 8 if grid.height_at(cell) >= 0 else 0)
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
	var markers: Array[Node2D] = _prop_markers.duplicate()
	markers.sort_custom(func(a: Node2D, b: Node2D) -> bool: return a.position.y > b.position.y)
	for marker: Node2D in markers:
		var prop: CombatGrid.Prop = marker.get_meta("prop") as CombatGrid.Prop
		if _art_contains(marker, point) and not occludes(prop.cell, point):
			return prop
	return null


func _art_marker(cell: Vector2i, id: String, foot: float) -> Node2D:
	var marker: Node2D = Node2D.new()
	marker.position = map_to_local(cell)
	var sprite: Sprite2D = Sprite2D.new()
	sprite.name = "Sprite"
	sprite.texture = load("res://scenes/combat/art/props/%s.png" % id) as Texture2D
	sprite.centered = false
	sprite.offset = Vector2(-sprite.texture.get_width() / 2.0, -sprite.texture.get_height() + 8)
	sprite.scale = Vector2.ONE * 0.5
	sprite.position = map_to_surface(cell) - marker.position + Vector2(0, foot)
	marker.add_child(sprite)
	return marker


func _art_contains(marker: Node2D, point: Vector2) -> bool:
	var sprite: Sprite2D = marker.get_node("Sprite") as Sprite2D
	var pixel: Vector2i = Vector2i((sprite.to_local(to_global(point)) - sprite.offset).floor())
	var image: Image = sprite.texture.get_image()
	return Rect2i(Vector2i.ZERO, image.get_size()).has_point(pixel) and image.get_pixelv(pixel).a > 0.0


func show_props(props: Array[CombatGrid.Prop], preview: CombatGrid.Prop = null) -> void:
	for marker: Node2D in _prop_markers:
		marker.free()
	_prop_markers.clear()
	for prop: CombatGrid.Prop in props:
		var marker: Node2D = _art_marker(prop.cell, prop.kind, 4.0)
		marker.set_meta("prop", prop)
		var sprite: Sprite2D = marker.get_node("Sprite") as Sprite2D
		if prop == preview:
			var outline: Sprite2D = sprite.duplicate() as Sprite2D
			outline.name = "Outline"
			outline.z_index = 1
			var material: ShaderMaterial = ShaderMaterial.new()
			material.shader = preload("res://scenes/combat/art/unit_outline.gdshader")
			material.set_shader_parameter("outline_color", Color("f4cf69"))
			outline.material = material
			marker.add_child(outline)
		if prop.kind == "crate":
			var top: float = sprite.position.y + (sprite.texture.get_image().get_used_rect().position.y
				+ sprite.offset.y) * 0.5 - 3.0
			marker.draw.connect(func() -> void:
				marker.draw_line(Vector2(-6, top), Vector2(6, top), Color("382c21"), 2.0)
				marker.draw_line(Vector2(-6, top), Vector2(-6 + prop.hit_points * 2, top), Color("e7bf6d"), 2.0))
		add_child(marker)
		_prop_markers.append(marker)


func _add_height_source(height: int) -> int:
	var size: Vector2i = tile_set.tile_size * 2
	var rise: int = height * size.y / 2
	var foundation: int = 16 if height >= 0 else 0
	var floor_image: Image = (tile_set.get_source(0) as TileSetAtlasSource).texture.get_image()
	floor_image.convert(Image.FORMAT_RGBA8)
	var wall: Image = preload("res://scenes/combat/art/terrain/wall.png").get_image()
	var image: Image = Image.create(size.x * 8, size.y + absi(rise) + foundation, false, Image.FORMAT_RGBA8)
	for index: int in range(8):
		var left: int = index * size.x
		var center: Vector2 = Vector2(size.x / 2.0, size.y / 2.0 + maxi(-rise, 0))
		var bottom: Vector2 = center + Vector2(0, rise + foundation)
		for direction: int in [-1, 1]:
			var side: PackedVector2Array = [
				center + Vector2(direction * size.x / 2.0, 0), center + Vector2(0, size.y / 2.0),
				bottom + Vector2(0, size.y / 2.0), bottom + Vector2(direction * size.x / 2.0, 0)]
			for y: int in range(image.get_height()):
				for x: int in range(size.x):
					if Geometry2D.is_point_in_polygon(Vector2(x + 0.5, y + 0.5), side):
						var color: Color = wall.get_pixel(x % wall.get_width(), y % wall.get_height())
						image.set_pixel(left + x, y, color.darkened(0.28 if direction > 0 else 0.12))
	image.blend_rect(floor_image, Rect2i(Vector2i.ZERO, Vector2i(size.x * 8, size.y)), Vector2i(0, maxi(-rise, 0)))
	var detail: ShaderMaterial = ShaderMaterial.new()
	detail.shader = preload("res://scenes/combat/art/terrain_detail.gdshader")
	detail.set_shader_parameter("detail_texture", ImageTexture.create_from_image(image))
	var proxy: Image = image.duplicate()
	proxy.resize(image.get_width() / 2, image.get_height() / 2, Image.INTERPOLATE_NEAREST)
	var source: TileSetAtlasSource = TileSetAtlasSource.new()
	source.use_texture_padding = false
	source.texture_region_size = Vector2i(size.x, image.get_height()) / 2
	source.texture = ImageTexture.create_from_image(proxy)
	for index: int in range(8):
		source.create_tile(Vector2i(index, 0))
		source.get_tile_data(Vector2i(index, 0), 0).material = detail
		source.get_tile_data(Vector2i(index, 0), 0).texture_origin = Vector2i(0, roundi((rise - foundation) / 4.0))
		source.get_tile_data(Vector2i(index, 0), 0).y_sort_origin = -1
	return tile_set.add_source(source)
