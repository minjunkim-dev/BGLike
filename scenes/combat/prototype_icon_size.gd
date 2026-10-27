extends Control
# PROTOTYPE. 전투 스킬 바와 정비 칸의 그림 크기 세 가지. 아래 막대와 ← → 로 바꾼다.
# 질문: 입력 영역을 스킬 52×40, 칸 36×36으로 둔 채 그림을 32·24·16 중 어디로 줄일 때 도트가 읽히는가.
# 실행: godot --path . res://scenes/combat/prototype_icon_size.tscn -- --variant=A
# 제품이 아니다. 고른 크기가 생기기 전에는 HUD와 정비 화면에 넣지 않는다.

const PICTURES: Dictionary[String, int] = {"A": 32, "B": 24, "C": 16}
const TITLES: Dictionary[String, String] = {
	"A": "채움 32", "B": "여백 24", "C": "도장 16"
}
const SKILL_HIT := Vector2(52, 40)
const CELL_HIT := Vector2(36, 36)
const ACTIONS: Array[String] = [
	"attack", "shock", "second_wind", "surge", "mark", "disengage", "shove", "jump", "potion", "parry"
]
const ITEMS: Array[String] = ["sword", "bow", "armor", "potion", "sword", "armor"]

var _variant: String = "A"
var _board: Control
var _state: Label
var _switch_label: Label
var _last_input: String = "아직 없음"


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--variant="):
			var requested: String = argument.trim_prefix("--variant=")
			if requested in PICTURES:
				_variant = requested
	var background := ColorRect.new()
	background.color = Color("121a22")
	background.set_anchors_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_bottom", 36)
	add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 6)
	margin.add_child(column)
	_state = Label.new()
	_state.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_state.add_theme_font_size_override("font_size", 10)
	_state.add_theme_color_override("font_color", Color("f4f7fb"))
	column.add_child(_state)
	_board = VBoxContainer.new()
	_board.add_theme_constant_override("separation", 8)
	_board.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(_board)
	_build_switcher()
	get_tree().root.size_changed.connect(_render)
	_render()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		var key: InputEventKey = event
		if key.keycode == KEY_LEFT or key.keycode == KEY_BRACKETLEFT:
			_step(-1)
		elif key.keycode == KEY_RIGHT or key.keycode == KEY_BRACKETRIGHT:
			_step(1)


func _step(direction: int) -> void:
	var keys: Array[String] = ["A", "B", "C"]
	_variant = keys[(keys.find(_variant) + direction + keys.size()) % keys.size()]
	_last_input = "아직 없음"
	_render()


func _render() -> void:
	for child: Node in _board.get_children():
		child.free()
	_board.add_child(_heading("전투 스킬 바"))
	var skills := HBoxContainer.new()
	skills.add_theme_constant_override("separation", 3)
	_board.add_child(skills)
	for action: String in ACTIONS:
		skills.add_child(_skill_button(action))
	_board.add_child(_heading("정비 칸, 선택 상세, 드래그 미리보기"))
	var cells := HBoxContainer.new()
	cells.add_theme_constant_override("separation", 3)
	_board.add_child(cells)
	for index: int in ITEMS.size():
		cells.add_child(_item_cell(ITEMS[index], index == 0))
	var detail := HBoxContainer.new()
	detail.add_theme_constant_override("separation", 8)
	_board.add_child(detail)
	detail.add_child(_picture("sword"))
	var detail_text := Label.new()
	detail_text.text = "검 · 공격+1"
	detail_text.add_theme_font_size_override("font_size", 10)
	detail_text.add_theme_color_override("font_color", Color("f4f7fb"))
	detail.add_child(detail_text)
	var drag := HBoxContainer.new()
	drag.add_theme_constant_override("separation", 8)
	_board.add_child(drag)
	drag.add_child(_picture("potion"))
	var drag_text := Label.new()
	drag_text.text = "드래그 미리보기. 그림 크기만 따르고 칸 입력은 따르지 않는다."
	drag_text.add_theme_font_size_override("font_size", 10)
	drag_text.add_theme_color_override("font_color", Color("f4f7fb"))
	drag.add_child(drag_text)
	_refresh_state()


func _refresh_state() -> void:
	var picture: int = PICTURES[_variant]
	var window := DisplayServer.window_get_size()
	var viewport := get_viewport().get_visible_rect().size
	var screen_per_logical := 0.0 if viewport.y == 0.0 else window.y / viewport.y
	var texel := 0.0 if picture == 0 else screen_per_logical * float(picture) / 64.0
	var whole := absf(texel - roundf(texel)) < 0.02
	_state.text = "PROTOTYPE  #362  %s (%s)\n그림 %d 논리px · 원본 64 · 창 %d×%d · 논리 화면 %.0f×%.0f · 텍셀당 화면 %.2fpx · 정수 텍셀 %s\n스킬 입력 %.0f×%.0f · 정비 칸 입력 %.0f×%.0f · 배지와 비용 마크는 입력 모서리에 고정\n마지막 입력: %s\n← → 는 이 시안의 변형만 바꾼다. 제품의 ← → 는 스킬 바 포커스다." % [
		_variant, TITLES[_variant], picture, window.x, window.y, viewport.x, viewport.y, texel,
		"예" if whole else "아니오", SKILL_HIT.x, SKILL_HIT.y, CELL_HIT.x, CELL_HIT.y, _last_input
	]
	_switch_label.text = "%s (%s)" % [_variant, TITLES[_variant]]
	DisplayServer.window_set_title("PROTOTYPE icon size %s" % _variant)


func _skill_button(action: String) -> Button:
	var button := Button.new()
	button.custom_minimum_size = SKILL_HIT
	button.focus_mode = Control.FOCUS_NONE
	button.icon = CombatActionRules.icon_of(action)
	button.material = preload("res://scenes/combat/art/pixel_art.tres")
	button.add_theme_constant_override("icon_max_width", PICTURES[_variant])
	button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER if _variant == "C" else HORIZONTAL_ALIGNMENT_LEFT
	button.add_theme_color_override("icon_disabled_color", Color("8a939b", 0.55))
	button.disabled = action == "potion"
	_paint(button, SKILL_HIT)
	var resource: int = CombatActionRules.resource_of(action)
	var mark := Label.new()
	mark.text = "●▲◆"[resource]
	mark.position = Vector2(-13, 5)
	mark.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mark.add_theme_font_size_override("font_size", 10)
	mark.add_theme_color_override("font_color", [Color("70c76d"), Color("edaa54"), Color("ac90e5")][resource])
	button.add_child(mark)
	if action in CombatActionRules.USES_PER_ACT:
		var badge := Label.new()
		badge.text = str(CombatActionRules.USES_PER_ACT[action])
		badge.position = Vector2(-12, -8)
		badge.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
		badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
		badge.add_theme_font_size_override("font_size", 8)
		badge.add_theme_color_override("font_color", Color("ffffff"))
		var badge_style := StyleBoxFlat.new()
		badge_style.bg_color = Color("485568")
		badge.add_theme_stylebox_override("normal", badge_style)
		button.add_child(badge)
	button.pressed.connect(func() -> void:
		_last_input = "%s 버튼, 입력 %.0f×%.0f, 그림 %d" % [CombatActionRules.NAMES[action], SKILL_HIT.x, SKILL_HIT.y, PICTURES[_variant]]
		_refresh_state()
	)
	return button


func _item_cell(icon_name: String, selected: bool) -> Button:
	var cell := Button.new()
	cell.custom_minimum_size = CELL_HIT
	cell.focus_mode = Control.FOCUS_NONE
	cell.icon = load("res://scenes/combat/art/icons/items/%s.png" % icon_name)
	cell.material = preload("res://scenes/combat/art/pixel_art.tres")
	cell.add_theme_constant_override("icon_max_width", PICTURES[_variant])
	cell.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_paint(cell, CELL_HIT, selected)
	cell.pressed.connect(func() -> void:
		_last_input = "%s 칸, 입력 %.0f×%.0f, 그림 %d" % [icon_name, CELL_HIT.x, CELL_HIT.y, PICTURES[_variant]]
		_refresh_state()
	)
	return cell


func _picture(icon_name: String) -> TextureRect:
	var picture := TextureRect.new()
	var size := PICTURES[_variant]
	picture.custom_minimum_size = Vector2(size, size)
	picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	picture.texture = load("res://scenes/combat/art/icons/items/%s.png" % icon_name)
	picture.material = preload("res://scenes/combat/art/pixel_art.tres")
	return picture


func _paint(button: Button, hit: Vector2, selected: bool = false) -> void:
	var border := Color("f2c14e") if _variant == "C" else Color("7eb6ff") if selected else Color("61717e")
	for state: String in ["normal", "hover", "disabled", "pressed"]:
		var style := StyleBoxFlat.new()
		style.bg_color = Color(0, 0, 0, 0) if _variant == "C" else Color("202b35")
		style.draw_center = _variant != "C"
		style.border_color = border
		style.set_border_width_all(2 if selected else 1)
		style.content_margin_left = 0
		style.content_margin_right = 0
		style.content_margin_top = 0
		style.content_margin_bottom = 0
		button.add_theme_stylebox_override(state, style)
	button.custom_minimum_size = hit


func _heading(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 11)
	label.add_theme_color_override("font_color", Color("edaa54"))
	return label


func _build_switcher() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 100
	add_child(layer)
	var bar := PanelContainer.new()
	bar.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	bar.offset_left = -150
	bar.offset_top = -32
	bar.offset_right = 150
	bar.offset_bottom = -6
	var plate := StyleBoxFlat.new()
	plate.bg_color = Color("111111")
	plate.border_color = Color("f4f7fb")
	plate.set_border_width_all(1)
	plate.corner_radius_top_left = 8
	plate.corner_radius_top_right = 8
	plate.corner_radius_bottom_left = 8
	plate.corner_radius_bottom_right = 8
	plate.content_margin_left = 8
	plate.content_margin_right = 8
	bar.add_theme_stylebox_override("panel", plate)
	layer.add_child(bar)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	bar.add_child(row)
	row.add_child(_arrow("←", -1))
	_switch_label = Label.new()
	_switch_label.custom_minimum_size.x = 120
	_switch_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_switch_label.add_theme_color_override("font_color", Color("f4f7fb"))
	row.add_child(_switch_label)
	row.add_child(_arrow("→", 1))


func _arrow(text: String, direction: int) -> Button:
	var button := Button.new()
	button.text = text
	button.focus_mode = Control.FOCUS_NONE
	button.pressed.connect(func() -> void: _step(direction))
	return button
