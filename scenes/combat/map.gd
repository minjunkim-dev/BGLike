class_name CombatMap
extends TileMapLayer
## 바닥 높이의 표시 위치와 필드 입력을 같은 좌표로 변환한다.

var revision: int = 0
var _animating_prop: CombatGrid.Prop
var _animation_marker: Node2D
var _prop_effects: Array[Node2D] = []
var grid: CombatGrid
var _overlays: Array[Node2D] = []
var _blocked_markers: Array[Node2D] = []
var _ground_markers: Array[Node2D] = []
var _prop_markers: Array[Node2D] = []
var _unit_markers: Array[Node2D] = []
var _height_edges: Array[Node2D] = []
static var _edge_textures: Dictionary[String, Texture2D] = {}
const EDGE_FRONT: int = 2
const EDGE_LIGHT: Color = Color(1.0, 0.95, 0.8, 0.55)
const EDGE_DARK: Color = Color(0.06, 0.05, 0.04, 0.7)
const EDGE_CONTACT_ALPHA: float = 0.55


func build_grid(combat_grid: CombatGrid, floors: TileSet, stage: CombatStage = null) -> void:
	revision += 1
	# Tween의 완료 대기를 끊지 않는다. 이전 호출은 깨어난 뒤 세대가 다르면 정리만 한다.
	if is_instance_valid(_animation_marker):
		_animation_marker.hide()
	_animating_prop = null
	for effect: Node2D in _prop_effects.duplicate():
		effect.free()
	grid = combat_grid
	reveal_units([])
	clear()
	show_movement([], [], [], Vector2i.ZERO)
	show_grounds([])
	show_props([])
	for marker: Node2D in _blocked_markers + _height_edges:
		marker.free()
	_blocked_markers.clear()
	_height_edges.clear()
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
	_show_height_edges()
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

## 가림 판정·클릭은 원래 픽셀을 쓰고 표시만 옅게 한다(#349).
func reveal_units(units: Array[CombatUnit]) -> void:
	for marker: Node2D in _unit_markers:
		marker.free()
	_unit_markers.clear()
	for unit: CombatUnit in units:
		var foot: Vector2 = to_local(unit.to_global(Vector2(0, unit.floor_offset_y)))
		if not unit.visible or not (occludes(unit.cell, foot) or occludes(unit.cell, foot + Vector2(0, -10))):
			continue
		var marker: Line2D = Line2D.new()
		marker.position = foot
		marker.z_index = 1
		marker.points = PackedVector2Array([Vector2(-8, 0), Vector2(0, -4), Vector2(8, 0), Vector2(0, 4)])
		marker.closed = true
		marker.width = 0.7
		marker.default_color = CombatUnit.ALLY_COLOR if unit.is_ally else CombatUnit.ENEMY_COLOR
		add_child(marker)
		_unit_markers.append(marker)
	for marker: Node2D in _blocked_markers + _prop_markers:
		marker.modulate.a = 1.0
		for unit: CombatUnit in units:
			if not unit.visible or marker.position.y <= map_to_local(unit.cell).y:
				continue
			var foot: Vector2 = to_local(unit.to_global(Vector2(0, unit.floor_offset_y)))
			if _art_contains(marker, foot) or _art_contains(marker, foot + Vector2(0, -10)):
				marker.modulate.a = 0.32
				break


## 판정 직전의 경로만 표시한다. 호출자가 입력을 잠그고 끝난 뒤 기존 판정을 실행한다.
func animate_prop(prop: CombatGrid.Prop, roll: CombatActions.RockRoll, can_continue: Callable) -> void:
	var generation: int = revision
	var marker: Node2D = _art_marker(prop.cell, prop.kind, 4.0)
	marker.name = "PropAnimation"
	_animating_prop = prop
	_animation_marker = marker
	add_child(marker)
	for original: Node2D in _prop_markers:
		if original.get_meta("prop") == prop:
			original.hide()
	var sprite: Sprite2D = marker.get_node("Sprite") as Sprite2D
	if roll == null:
		var tween: Tween = create_tween()
		var origin: float = sprite.position.x
		for offset: float in [-1.5, 1.5, -1.0, 0.0]:
			tween.tween_property(sprite, "position:x", origin + offset, 0.035)
		await tween.finished
	else:
		for step: CombatActions.RockStep in roll.steps:
			if generation != revision or not can_continue.call():
				break
			var destination: Vector2 = map_to_local(step.cell) if step.advance else marker.position
			var tween: Tween = create_tween().set_parallel(true)
			tween.tween_property(marker, "position", destination, 0.14)
			tween.tween_property(sprite, "position:y", map_to_surface(step.cell).y - destination.y + 4.0
				if step.advance else sprite.position.y, 0.14)
			tween.tween_property(sprite, "skew", 0.15, 0.07)
			await tween.finished
			if generation != revision or not can_continue.call():
				break
			sprite.skew = 0.0
			if step.target != null:
				prop_impact(step.cell, false)
			if step.destroyed or not step.advance:
				break
	if _animation_marker == marker:
		_animation_marker = null
		_animating_prop = null
		for original: Node2D in _prop_markers:
			original.show()
	marker.free()


func prop_impact(cell: Vector2i, broken: bool) -> void:
	var effect: Node2D = Node2D.new()
	effect.position = map_to_local(cell)
	effect.z_index = 2
	var center: Vector2 = map_to_surface(cell) - effect.position
	effect.draw.connect(func() -> void:
		var color: Color = Color("d8bc85") if broken else Color("f4cf69")
		effect.draw_arc(center, 6.0, 0, TAU, 16, color, 1.0)
		if broken:
			for offset: Vector2 in [Vector2(-5, -4), Vector2(5, -3), Vector2(-3, 2), Vector2(4, 3)]:
				effect.draw_line(center + offset, center + offset * 1.7, color, 1.5))
	add_child(effect)
	_prop_effects.append(effect)
	effect.tree_exiting.connect(func() -> void: _prop_effects.erase(effect))
	var tween: Tween = effect.create_tween()
	tween.tween_property(effect, "modulate:a", 0.0, 0.3)
	tween.tween_callback(effect.queue_free)


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
		overlay.color = Color(0.22, 0.8, 0.5, 0.12) if cell in attack_cells else Color(0.22, 0.56, 0.92, 0.1)
		var edge: Line2D = Line2D.new()
		edge.points = overlay.polygon
		edge.closed = true
		edge.width = 0.5
		edge.default_color = Color(overlay.color.r, overlay.color.g, overlay.color.b, 0.75)
		overlay.add_child(edge)
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
	sprite.material = preload("res://scenes/combat/art/pixel_art.tres")
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
		if prop == _animating_prop:
			marker.hide()


## 이웃과 높이가 다른 윗면 가장자리를 칸마다 표시한다(#392). 판정·좌표에는 쓰지 않는다.
## 뒤쪽 내리막은 높이 단위마다 어두운 선과 밝은 선 한 쌍(차2 이상은 두 쌍), 앞쪽 내리막은 밝은 윗면 끝선,
## 뒤쪽 높은 이웃의 발치는 접지 그림자다. 맵 밖·낭떠러지 이웃은 기존 표시를 그대로 둔다.
func _show_height_edges() -> void:
	for cell: Vector2i in get_used_cells():
		var edges: Array[int] = [0, 0, 0, 0]
		for direction: Vector2i in CombatGrid.neighbors(Vector2i.ZERO):
			var neighbor: Vector2i = cell + direction
			if not grid.is_floor(neighbor):
				continue
			var delta: Vector2 = map_to_local(neighbor) - map_to_local(cell)
			var edge: int = (EDGE_FRONT if delta.y > 0 else 0) + (1 if delta.x > 0 else 0)
			var step: int = clampi(grid.height_at(cell) - grid.height_at(neighbor), -2, 2)
			# 앞쪽 이웃이 더 높으면 그 윗면이 이 가장자리를 덮는다.
			edges[edge] = step if step > 0 or edge < EDGE_FRONT else 0
		if edges == [0, 0, 0, 0]:
			continue
		var key: String = str(tile_set.tile_size, edges)
		if not _edge_textures.has(key):
			_edge_textures[key] = _height_edge_texture(edges)
		var marker: Node2D = Node2D.new()
		marker.name = "HeightEdge"
		marker.position = map_to_local(cell)
		marker.set_meta("edges", edges)
		var sprite: Sprite2D = Sprite2D.new()
		sprite.name = "Sprite"
		sprite.texture = _edge_textures[key]
		sprite.scale = Vector2.ONE * 0.5
		sprite.material = preload("res://scenes/combat/art/pixel_art.tres")
		sprite.position = map_to_surface(cell) - marker.position
		marker.add_child(sprite)
		add_child(marker)
		_height_edges.append(marker)


## edges는 왼쪽 위·오른쪽 위·왼쪽 아래·오른쪽 아래 가장자리의 높이 차(-2..2)다.
## 바닥 원본과 같은 두 배 밀도 마름모에 그려 정수 배율과 sharp bilinear에서 도트 격자를 따른다.
func _height_edge_texture(edges: Array[int]) -> Texture2D:
	var size: Vector2i = tile_set.tile_size * 2
	var image: Image = Image.create(size.x, size.y, false, Image.FORMAT_RGBA8)
	var slope: int = size.x / size.y
	for y: int in range(size.y):
		var front: bool = y >= size.y / 2
		var row: int = size.y - 1 - y if front else y
		for x: int in range(size.x):
			var right: bool = x >= size.x / 2
			var inset: int = (size.x / 2 + slope * row - x) if right else (x - (size.x / 2 - 1 - slope * row))
			if inset < 0:
				continue
			# 가장자리에서 안쪽으로 센 도트 줄. 2:1 마름모라 한 줄은 가로 slope 도트다.
			var band: int = inset / slope
			var step: int = edges[(EDGE_FRONT if front else 0) + (1 if right else 0)]
			if step > 0 and front and band == 0:
				image.set_pixel(x, y, EDGE_LIGHT)
			elif step > 0 and not front and band < step * 2:
				image.set_pixel(x, y, EDGE_DARK if band % 2 == 0 else EDGE_LIGHT)
			elif step < 0 and band < 1 - step:
				image.set_pixel(x, y, Color(EDGE_DARK, EDGE_CONTACT_ALPHA * (1.0 - band / (1.0 - step))))
	return ImageTexture.create_from_image(image)


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
						var top: float = center.y + size.y / 2.0 - absf(x + 0.5 - center.x) * 0.5
						var depth: int = maxi(0, int(y + 0.5 - top))
						color = color.darkened((0.44 if direction > 0 else 0.22) + minf(depth * 0.003, 0.12))
						if depth % (size.y / 2) == 0:
							color = color.darkened(0.25)
						image.set_pixel(left + x, y, color)
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
