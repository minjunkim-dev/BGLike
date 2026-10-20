class_name CombatMap
extends TileMapLayer
## 바닥 높이의 표시 위치와 필드 입력을 같은 좌표로 변환한다.

var grid: CombatGrid


func build_grid(combat_grid: CombatGrid, floors: TileSet) -> void:
	grid = combat_grid
	clear()
	tile_set = floors
	if not grid.heights.is_empty():
		tile_set = floors.duplicate(true) as TileSet
	var sources: Dictionary[int, int] = {0: 0}
	for y: int in range(grid.map_size.y):
		for x: int in range(grid.map_size.x):
			var cell: Vector2i = Vector2i(x, y)
			var height: int = grid.height_at(cell)
			if not sources.has(height):
				sources[height] = _add_height_source(height)
			set_cell(cell, sources[height], Vector2i((x + y) % 2, 0))


func map_to_surface(cell: Vector2i) -> Vector2:
	var height: int = grid.height_at(cell) if grid != null else 0
	return map_to_local(cell) - Vector2(0, height * tile_set.tile_size.x / 2.0)


func surface_to_map(point: Vector2) -> Vector2i:
	var cells: Array[Vector2i] = get_used_cells()
	cells.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return a.y > b.y)
	var size: Vector2 = Vector2(tile_set.tile_size)
	for cell: Vector2i in cells:
		var surface: Vector2 = map_to_surface(cell)
		if Rect2(surface - size / 2.0, size).has_point(point):
			return cell
		var ground: Vector2 = map_to_local(cell)
		var column: Rect2 = Rect2(Vector2(surface.x - size.x / 2.0,
			minf(surface.y, ground.y) - size.y / 2.0),
			Vector2(size.x, size.y + absf(surface.y - ground.y)))
		# 앞 칸의 옆면은 뒤 칸의 바닥 클릭도 가린다.
		if column.has_point(point):
			return Vector2i(-1, -1)
	return Vector2i(-1, -1)


func _add_height_source(height: int) -> int:
	var size: Vector2i = tile_set.tile_size
	var rise: int = roundi(height * size.x / 2.0)
	var depth: int = absi(rise)
	var floor_image: Image = (tile_set.get_source(0) as TileSetAtlasSource).texture.get_image()
	floor_image.convert(Image.FORMAT_RGBA8)
	var image: Image = Image.create(size.x * 2, size.y + depth, false, Image.FORMAT_RGBA8)
	var side_y: int = size.y if rise > 0 else 0
	for index: int in range(2):
		var left: int = index * size.x
		var shade: Color = floor_image.get_pixel(left + size.x / 2, size.y / 2).darkened(0.3)
		var border: Color = floor_image.get_pixel(left, 0)
		image.fill_rect(Rect2i(left, side_y, size.x, depth), shade)
		image.fill_rect(Rect2i(left, side_y, 1, depth), border)
		image.fill_rect(Rect2i(left + size.x - 1, side_y, 1, depth), border)
		image.fill_rect(Rect2i(left, side_y + depth - 1, size.x, 1), border)
	image.blit_rect(floor_image, Rect2i(Vector2i.ZERO, Vector2i(size.x * 2, size.y)),
		Vector2i(0, maxi(-rise, 0)))
	var source: TileSetAtlasSource = TileSetAtlasSource.new()
	source.texture_region_size = Vector2i(size.x, size.y + depth)
	source.texture = ImageTexture.create_from_image(image)
	for index: int in range(2):
		source.create_tile(Vector2i(index, 0))
		source.get_tile_data(Vector2i(index, 0), 0).texture_origin = Vector2i(0, roundi(rise / 2.0))
	return tile_set.add_source(source)
