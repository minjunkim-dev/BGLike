extends Node2D
## 1차 전투 프로토타입: 턴 진행, 입력, 적 AI, 화면 표시.
## 판정 규칙은 CombatRules에 있다.

const MAP_SIZE := Vector2i(10, 10)
const MOVE_SPEED := 6
const STEP_TIME := 0.09
const AI_DELAY := 0.45
const PLATFORM_DEPTH := 10.0
const NO_CELL := Vector2i(-1, -1)

const UNITS_TEXTURE := preload("res://scenes/combat/art/units.png")
const COLOR_ALLY := Color("4a8fd9")
const COLOR_ENEMY := Color("d9544a")
const COLOR_CURRENT := Color("ffd84a")

## 0이면 매번 무작위. 같은 결과를 재현할 때 값을 넣는다.
@export var fixed_seed := 0
## 켜면 아군도 AI가 조작한다. 밸런스 확인용.
@export var allies_use_ai := false

var rng := RandomNumberGenerator.new()
var astar := AStarGrid2D.new()
var units: Array[Unit] = []
var turn_order: Array[Unit] = []
var initiative := {}
var turn_index := -1
var round_number := 0
var current: Unit
var moves_left := 0
var action_used := false
var busy := false
var battle_over := false
## 셀 -> 그 셀까지의 경로. 현재 아군이 이동할 수 있는 칸.
var reachable := {}
var pending_cell := NO_CELL
var hovered_cell := NO_CELL

@onready var map: TileMapLayer = $Map
@onready var overlay: Node2D = $Overlay
@onready var effects: Node2D = $Effects
@onready var turn_bar: Control = %TurnBar
@onready var header_label: Label = %Header
@onready var hp_bar: ProgressBar = %HpBar
@onready var hp_text: Label = %HpText
@onready var stats_label: Label = %Stats
@onready var hint_label: Label = %Hint
@onready var log_label: RichTextLabel = %Log
@onready var end_turn_button: Button = %EndTurn
@onready var result_dim: ColorRect = %ResultDim
@onready var result_panel: Control = %Result
@onready var result_label: Label = %ResultLabel


func _ready() -> void:
	_build_map()
	astar.region = Rect2i(Vector2i.ZERO, MAP_SIZE)
	astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ALWAYS
	# 대각선도 1칸으로 센다.
	astar.default_compute_heuristic = AStarGrid2D.HEURISTIC_CHEBYSHEV
	astar.default_estimate_heuristic = AStarGrid2D.HEURISTIC_CHEBYSHEV
	astar.update()

	for child in $Units.get_children():
		var unit := child as Unit
		units.append(unit)
		unit.position = map.map_to_local(unit.cell)

	overlay.draw.connect(_draw_overlay)
	turn_bar.draw.connect(_draw_turn_bar)
	end_turn_button.pressed.connect(_on_end_turn_pressed)
	%Restart.pressed.connect(func() -> void: get_tree().reload_current_scene())
	get_viewport().size_changed.connect(_center_map)
	_center_map()

	if fixed_seed != 0:
		rng.seed = fixed_seed
	else:
		rng.randomize()
	_log("시드 %d" % rng.seed, Color.DIM_GRAY)
	for unit in units:
		var result := CombatRules.roll_initiative(rng, unit)
		initiative[unit] = result.total
		_log(result.text, Color.LIGHT_GRAY)
	turn_order = units.duplicate()
	turn_order.sort_custom(_initiative_first)
	_next_turn()


func _process(_delta: float) -> void:
	overlay.queue_redraw()


## 풀 타일을 무작위로 섞어 깔고, 맵 아래에 땅 옆면을 그려 떠 있는 판처럼 보이게 한다.
func _build_map() -> void:
	var tile_rng := RandomNumberGenerator.new()
	tile_rng.seed = 7
	for x in MAP_SIZE.x:
		for y in MAP_SIZE.y:
			var roll := tile_rng.randf()
			var variant := 0 if roll < 0.55 else 1 if roll < 0.85 else 2 if roll < 0.93 else 3
			map.set_cell(Vector2i(x, y), 0, Vector2i(variant, 0))

	var half := Vector2(map.tile_set.tile_size) / 2
	var top := map.map_to_local(Vector2i.ZERO) + Vector2(0, -half.y)
	var right := map.map_to_local(Vector2i(MAP_SIZE.x - 1, 0)) + Vector2(half.x, 0)
	var bottom := map.map_to_local(MAP_SIZE - Vector2i.ONE) + Vector2(0, half.y)
	var left := map.map_to_local(Vector2i(0, MAP_SIZE.y - 1)) + Vector2(-half.x, 0)
	var depth := Vector2(0, PLATFORM_DEPTH)
	_add_platform_face([left, bottom, bottom + depth, left + depth], Color("4a3a30"))
	_add_platform_face([bottom, right, right + depth, bottom + depth], Color("36291f"))
	_add_platform_face([top, right, bottom, left], Color("2b3a26"))


func _add_platform_face(points: PackedVector2Array, color: Color) -> void:
	var face := Polygon2D.new()
	face.polygon = points
	face.color = color
	$Platform.add_child(face)


func _initiative_first(a: Unit, b: Unit) -> bool:
	if initiative[a] != initiative[b]:
		return initiative[a] > initiative[b]
	if a.dex_mod != b.dex_mod:
		return a.dex_mod > b.dex_mod
	return a.is_ally and not b.is_ally


func _center_map() -> void:
	var middle := (map.map_to_local(Vector2i.ZERO) + map.map_to_local(MAP_SIZE - Vector2i.ONE)) / 2
	position = (get_viewport_rect().size / 2 - middle + Vector2(0, 4)).round()


# --- 턴 진행 ---

func _next_turn() -> void:
	if _check_battle_end():
		return
	turn_index = (turn_index + 1) % turn_order.size()
	if turn_index == 0:
		round_number += 1
	current = turn_order[turn_index]
	if current.is_down():
		_next_turn()
		return
	moves_left = MOVE_SPEED
	action_used = false
	pending_cell = NO_CELL
	_log("— %s 턴" % current.label(), COLOR_ALLY if current.is_ally else COLOR_ENEMY)
	if _is_player_turn():
		_refresh_reachable()
		_update_ui("이동할 칸이나 공격할 적을 누르세요.")
	else:
		reachable.clear()
		_update_ui("")
		_run_ai()


func _is_player_turn() -> bool:
	return current != null and current.is_ally and not allies_use_ai and not battle_over


func _after_step() -> void:
	if battle_over or _check_battle_end():
		return
	if moves_left == 0 and action_used:
		_next_turn()
		return
	_refresh_reachable()
	_update_ui("")


func _check_battle_end() -> bool:
	if battle_over:
		return true
	var allies_alive := units.any(func(u: Unit) -> bool: return u.is_ally and not u.is_down())
	var enemies_alive := units.any(func(u: Unit) -> bool: return not u.is_ally and not u.is_down())
	if allies_alive and enemies_alive:
		return false
	battle_over = true
	reachable.clear()
	pending_cell = NO_CELL
	result_label.text = "승리!" if allies_alive else "패배..."
	_log(result_label.text, COLOR_CURRENT)
	result_dim.show()
	result_panel.show()
	_update_ui("")
	return true


func _on_end_turn_pressed() -> void:
	if _is_player_turn() and not busy:
		_next_turn()


# --- 플레이어 입력: 한 번 누르면 미리보기, 같은 칸을 한 번 더 누르면 확정 ---

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var cell := map.local_to_map(map.get_local_mouse_position())
		if cell != hovered_cell:
			hovered_cell = cell
		return
	var click := event as InputEventMouseButton
	if click == null or not click.pressed or click.button_index != MOUSE_BUTTON_LEFT:
		return
	if busy or not _is_player_turn():
		return
	_on_tap(map.local_to_map(map.get_local_mouse_position()))


func _on_tap(cell: Vector2i) -> void:
	var target := _unit_at(cell)
	var confirmed := cell == pending_cell
	pending_cell = NO_CELL
	if not astar.is_in_boundsv(cell) or (target != null and target.is_ally):
		_update_ui("")
	elif target != null:
		if action_used:
			_update_ui("이번 턴에는 이미 행동했습니다.")
		elif _distance(current.cell, cell) > current.attack_range:
			_update_ui("사거리 밖입니다.")
		elif confirmed:
			await _attack(current, target)
			_after_step()
		else:
			pending_cell = cell
			var chance := CombatRules.hit_chance(CombatRules.attack_bonus(current), target.armor_class)
			_update_ui("%s 명중률 %d%% · 한 번 더 누르면 공격" % [target.label(), roundi(chance * 100)])
	elif not reachable.has(cell):
		_update_ui("이동할 수 없는 칸입니다.")
	elif confirmed:
		await _move(current, reachable[cell])
		_after_step()
	else:
		pending_cell = cell
		_update_ui("%d칸 이동 · 한 번 더 누르면 이동" % (reachable[cell].size() - 1))


# --- 행동 ---

func _move(unit: Unit, path: Array[Vector2i]) -> void:
	busy = true
	for step in path.slice(1):
		var to := map.map_to_local(step)
		unit.face_toward(to)
		var tween := create_tween()
		tween.tween_property(unit, "position", to, STEP_TIME)
		var hop := create_tween()
		hop.tween_property(unit.sprite, "offset:y", -15.0, STEP_TIME / 2)
		hop.tween_property(unit.sprite, "offset:y", -12.0, STEP_TIME / 2)
		await tween.finished
		unit.cell = step
	moves_left -= path.size() - 1
	busy = false


func _attack(attacker: Unit, target: Unit) -> void:
	busy = true
	var result := CombatRules.resolve_attack(rng, attacker, target)
	_log(result.text, COLOR_CURRENT if result.crit else Color.WHITE if result.damage > 0 else Color.GRAY)
	action_used = true
	attacker.face_toward(target.position)
	if attacker.attack_range > 1:
		await _shoot_arrow(attacker.position, target.position)
	else:
		var tween := create_tween()
		tween.tween_property(attacker, "position", attacker.position.lerp(target.position, 0.35), 0.08)
		tween.tween_property(attacker, "position", attacker.position, 0.1)
		await tween.finished
	target.take_damage(result.damage)
	if result.damage == 0:
		_popup(target.position, "빗나감", Color.LIGHT_GRAY)
	elif result.crit:
		_popup(target.position, "-%d 치명타!" % result.damage, COLOR_CURRENT, 13)
	else:
		_popup(target.position, "-%d" % result.damage, Color.WHITE)
	if target.is_down():
		_log("%s 전투 불능" % target.label(), COLOR_ENEMY)
		await target.play_down()
	busy = false


func _shoot_arrow(from: Vector2, to: Vector2) -> void:
	var arrow := Polygon2D.new()
	arrow.polygon = PackedVector2Array([Vector2(-4, -1), Vector2(4, -1), Vector2(4, 1), Vector2(-4, 1)])
	arrow.color = Color("efe4c8")
	arrow.position = from + Vector2(0, -14)
	arrow.rotation = (to - from).angle()
	effects.add_child(arrow)
	var tween := create_tween()
	tween.tween_property(arrow, "position", to + Vector2(0, -14), 0.16)
	await tween.finished
	arrow.queue_free()


func _popup(at: Vector2, text: String, color: Color, size := 11) -> void:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", Color("1a1620"))
	label.add_theme_constant_override("outline_size", 3)
	label.add_theme_font_size_override("font_size", size)
	label.size = Vector2(80, 16)
	label.position = (at + Vector2(-40, -44)).round()
	effects.add_child(label)
	var tween := create_tween().set_parallel()
	tween.tween_property(label, "position:y", label.position.y - 14, 0.7).set_ease(Tween.EASE_OUT)
	tween.tween_property(label, "modulate:a", 0.0, 0.4).set_delay(0.4)
	tween.chain().tween_callback(label.queue_free)


# --- 적 AI: 사거리 안의 대상 중 HP가 낮은 쪽을 공격하고, 없으면 가장 가까운 대상에게 다가간다 ---

func _run_ai() -> void:
	await get_tree().create_timer(AI_DELAY).timeout
	var target := _weakest_target_in_range(current)
	if target == null:
		var path := _approach_path(current)
		if path.size() > 1:
			await _move(current, path)
		target = _weakest_target_in_range(current)
	if target != null:
		await _attack(current, target)
	_next_turn()


func _opponents(unit: Unit) -> Array[Unit]:
	var result: Array[Unit] = []
	result.assign(units.filter(func(u: Unit) -> bool: return u.is_ally != unit.is_ally and not u.is_down()))
	return result


func _weakest_target_in_range(unit: Unit) -> Unit:
	var best: Unit = null
	for other in _opponents(unit):
		if _distance(unit.cell, other.cell) > unit.attack_range:
			continue
		if best == null or other.hp < best.hp:
			best = other
	return best


## 가장 가까운 대상 쪽으로 이동력만큼, 사거리에 들어오면 멈추는 경로.
func _approach_path(unit: Unit) -> Array[Vector2i]:
	var best: Array[Vector2i] = []
	var best_length := 0
	for other in _opponents(unit):
		var full := _find_path(unit.cell, other.cell)
		if full.is_empty() or (not best.is_empty() and full.size() >= best_length):
			continue
		var path: Array[Vector2i] = [full[0]]
		for step in full.slice(1, full.size() - 1):
			if path.size() > MOVE_SPEED:
				break
			path.append(step)
			if _distance(step, other.cell) <= unit.attack_range:
				break
		best = path
		best_length = full.size()
	return best


# --- 격자 ---

func _distance(a: Vector2i, b: Vector2i) -> int:
	return maxi(absi(a.x - b.x), absi(a.y - b.y))


func _unit_at(cell: Vector2i) -> Unit:
	for unit in units:
		if unit.cell == cell and not unit.is_down():
			return unit
	return null


## 다른 캐릭터가 있는 칸은 지나갈 수 없다. 출발 칸과 도착 칸은 비어 있다고 본다.
func _find_path(from: Vector2i, to: Vector2i) -> Array[Vector2i]:
	astar.fill_solid_region(astar.region, false)
	for unit in units:
		if not unit.is_down():
			astar.set_point_solid(unit.cell, true)
	astar.set_point_solid(from, false)
	astar.set_point_solid(to, false)
	return astar.get_id_path(from, to)


func _refresh_reachable() -> void:
	reachable.clear()
	if moves_left == 0:
		return
	for x in MAP_SIZE.x:
		for y in MAP_SIZE.y:
			var cell := Vector2i(x, y)
			if _unit_at(cell) != null:
				continue
			var path := _find_path(current.cell, cell)
			if path.size() > 1 and path.size() - 1 <= moves_left:
				reachable[cell] = path


# --- 화면 ---

func _log(line: String, color := Color.WHITE) -> void:
	log_label.append_text("[color=#%s]%s[/color]\n" % [color.to_html(false), line])


func _update_ui(message: String) -> void:
	if current != null and not battle_over:
		header_label.text = "라운드 %d · %s" % [round_number, current.label()]
		hp_bar.max_value = current.max_hp
		hp_bar.value = current.hp
		hp_text.text = "%d/%d" % [current.hp, current.max_hp]
		stats_label.text = "AC %d · 이동 %d칸 · 행동 %s" % [
			current.armor_class, moves_left, "사용함" if action_used else "가능"]
	else:
		header_label.text = "전투 종료"
	hint_label.text = message
	end_turn_button.disabled = not _is_player_turn()
	turn_bar.queue_redraw()


func _draw_turn_bar() -> void:
	var font := turn_bar.get_theme_default_font()
	var x := 0.0
	for unit in turn_order:
		var is_current := unit == current and not battle_over
		var box := Rect2(x, 4.0 if is_current else 6.0, 24, 30)
		var team := COLOR_ALLY if unit.is_ally else COLOR_ENEMY
		var alpha := 0.35 if unit.is_down() else 1.0
		turn_bar.draw_rect(box, Color("14121c", 0.92 * alpha))
		turn_bar.draw_rect(box, (COLOR_CURRENT if is_current else team) * Color(1, 1, 1, alpha), false, 1.0)
		var frame := unit.sprite_frame()
		var region := Rect2(Vector2(frame % 2 * 16, frame / 2 * 24 + 1), Vector2(16, 12))
		turn_bar.draw_texture_rect_region(UNITS_TEXTURE, Rect2(box.position + Vector2(4, 3), region.size), region,
			Color(1, 1, 1, alpha))
		var ratio := float(unit.hp) / unit.max_hp
		turn_bar.draw_rect(Rect2(box.position + Vector2(3, 18), Vector2(18, 3)), Color("2a2634"))
		turn_bar.draw_rect(Rect2(box.position + Vector2(3, 18), Vector2(18 * ratio, 3)), Color("5cc15c", alpha))
		turn_bar.draw_string(font, box.position + Vector2(3, 28), str(initiative[unit]), HORIZONTAL_ALIGNMENT_LEFT, 18, 7,
			Color(0.75, 0.72, 0.8, alpha))
		x += 27.0


func _cell_polygon(cell: Vector2i, inset := 0.0) -> PackedVector2Array:
	var center := map.map_to_local(cell)
	var half := Vector2(map.tile_set.tile_size) / 2 - Vector2(inset * 2, inset)
	return PackedVector2Array([
		center + Vector2(0, -half.y), center + Vector2(half.x, 0),
		center + Vector2(0, half.y), center + Vector2(-half.x, 0)])


func _draw_overlay() -> void:
	var pulse := 0.6 + 0.4 * sin(Time.get_ticks_msec() / 180.0)
	for cell in reachable:
		overlay.draw_colored_polygon(_cell_polygon(cell, 1), Color(0.6, 0.82, 1.0, 0.4))
	if _is_player_turn() and not busy:
		for enemy in _opponents(current):
			if _distance(current.cell, enemy.cell) <= current.attack_range and not action_used:
				_draw_outline(enemy.cell, Color(COLOR_ENEMY, 0.5 + 0.4 * pulse))
		if reachable.has(hovered_cell) and hovered_cell != pending_cell:
			overlay.draw_colored_polygon(_cell_polygon(hovered_cell, 1), Color(1, 1, 1, 0.15))
	if reachable.has(pending_cell):
		var path: Array[Vector2i] = reachable[pending_cell]
		for step in path.slice(1):
			overlay.draw_colored_polygon(_cell_polygon(step, 1), Color(1, 0.85, 0.2, 0.35))
		_draw_outline(pending_cell, COLOR_CURRENT)
	elif pending_cell != NO_CELL:
		_draw_outline(pending_cell, Color("ff5a4a"), 2.0)
	if current != null and not battle_over:
		_draw_outline(current.cell, Color(COLOR_CURRENT, 0.5 + 0.5 * pulse))


func _draw_outline(cell: Vector2i, color: Color, width := 1.0) -> void:
	var points := _cell_polygon(cell, 0.5)
	points.append(points[0])
	overlay.draw_polyline(points, color, width)
