class_name CombatPreparation
extends ColorRect
## 전투 사이 보상 확인과 정비. 칸을 클릭해 고르고 아래 상세 패널의 버튼으로 실행한다 (#229 A안).

signal finished

const TEXT_COLOR: Color = Color("d8dee4")
const DIM_COLOR: Color = Color("8d9aa6")
const GOLD_COLOR: Color = Color("d6ad4f")
const SELECT_COLOR: Color = Color("4fa3d6")
const LINE_COLOR: Color = Color("2a3642")
const DOWN_COLOR: Color = Color("e0675f")
const PANEL_COLOR: Color = Color("121a22")
const CELL_COLOR: Color = Color("0d141b")
const UNIT_FRAME: String = "res://scenes/combat/art/units/%s/idle/right/000.png"

var loot: CombatLoot
var party: Array[CombatUnit] = []
var rewards: Array[Dictionary] = []
var maintaining: bool = false
var final_stage: bool = false
var last_in_act: bool = false
var title_label: Label
var hint_label: Label
var enable_button: Button
var cards: VBoxContainer
## 받지 않은 보상과 공용 가방 칸.
var content: VBoxContainer
var detail_panel: PanelContainer
var detail: VBoxContainer
var continue_button: Button
var discard_dialog: ConfirmationDialog
var bag_notice: Label
var skip_confirmation: CheckBox
var confirmation_text: Label
var _discard_index: int = -1
var _confirm_finish: bool = true
var _cells: ButtonGroup
## 고른 칸: "reward"·"bag"·"weapon"·"armor"와 보상·가방·캐릭터 번호.
var _selected_kind: String = ""
var _selected_index: int = -1


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	color = Color(0.04, 0.06, 0.08, 1.0)
	var margin: MarginContainer = MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side: String in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 6)
	add_child(margin)
	var layout: VBoxContainer = VBoxContainer.new()
	layout.add_theme_constant_override("separation", 6)
	margin.add_child(layout)
	var top: HBoxContainer = HBoxContainer.new()
	top.add_theme_constant_override("separation", 12)
	layout.add_child(top)
	title_label = Label.new()
	title_label.add_theme_font_size_override("font_size", 16)
	top.add_child(title_label)
	hint_label = _label(top, "", DIM_COLOR, false)
	hint_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hint_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	enable_button = _button(top, tr("정비 종료 확인 다시 켜기"), "EnableConfirmation")
	enable_button.pressed.connect(func() -> void:
		_confirm_finish = true
		enable_button.disabled = true
		continue_button.grab_focus())
	var main: HBoxContainer = HBoxContainer.new()
	main.size_flags_vertical = Control.SIZE_EXPAND_FILL
	main.add_theme_constant_override("separation", 6)
	layout.add_child(main)
	cards = VBoxContainer.new()
	cards.add_theme_constant_override("separation", 6)
	main.add_child(cards)
	var items: PanelContainer = _panel(main, LINE_COLOR)
	items.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	items.add_child(scroll)
	content = VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 4)
	scroll.add_child(content)
	detail_panel = _panel(layout, LINE_COLOR)
	detail_panel.custom_minimum_size.y = 74
	detail = VBoxContainer.new()
	detail.add_theme_constant_override("separation", 2)
	detail_panel.add_child(detail)
	var bottom: HBoxContainer = HBoxContainer.new()
	bottom.add_theme_constant_override("separation", 8)
	bottom.alignment = BoxContainer.ALIGNMENT_END
	layout.add_child(bottom)
	bag_notice = _label(bottom, "", TEXT_COLOR)
	bag_notice.name = "BagNotice"
	bag_notice.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bag_notice.hide()
	continue_button = Button.new()
	continue_button.name = "Continue"
	continue_button.custom_minimum_size = Vector2(132, 26)
	_style_button(continue_button, SELECT_COLOR)
	continue_button.pressed.connect(_continue)
	bottom.add_child(continue_button)
	discard_dialog = ConfirmationDialog.new()
	discard_dialog.name = "Discard"
	discard_dialog.title = tr("정비 종료 확인")
	discard_dialog.ok_button_text = tr("마치기")
	discard_dialog.cancel_button_text = tr("돌아가기")
	discard_dialog.dialog_hide_on_ok = false
	discard_dialog.confirmed.connect(_confirm)
	discard_dialog.canceled.connect(_hide_discard)
	discard_dialog.get_label().hide()
	var confirmation_content: VBoxContainer = VBoxContainer.new()
	discard_dialog.add_child(confirmation_content)
	confirmation_text = _label(confirmation_content, "", TEXT_COLOR, false)
	skip_confirmation = CheckBox.new()
	skip_confirmation.name = "SkipConfirmation"
	skip_confirmation.text = tr("더 이상 이 메시지를 띄우지 않음")
	skip_confirmation.add_theme_font_size_override("font_size", 12)
	confirmation_content.add_child(skip_confirmation)
	add_child(discard_dialog)
	hide()


func open_rewards(
	model: CombatLoot, allies: Array[CombatUnit], drops: Array[Dictionary],
	is_final: bool, is_last_in_act: bool
) -> void:
	if visible:
		return
	loot = model
	party = allies
	rewards = drops
	final_stage = is_final
	last_in_act = is_last_in_act
	maintaining = false
	show()
	_render()
	continue_button.grab_focus()


func _continue() -> void:
	if not visible or discard_dialog.visible:
		return
	if not maintaining:
		maintaining = true
		_render()
		continue_button.grab_focus()
	else:
		if rewards.is_empty() or not _confirm_finish:
			_finish()
		else:
			discard_dialog.title = tr("정비 종료 확인")
			discard_dialog.ok_button_text = tr("마치기")
			discard_dialog.dialog_text = tr("받지 않은 아이템이 있습니다. 마치시겠습니까?")
			skip_confirmation.button_pressed = false
			skip_confirmation.show()
			_show_confirmation()


func _show_confirmation() -> void:
	confirmation_text.text = discard_dialog.dialog_text
	discard_dialog.exclusive = true
	discard_dialog.popup_centered(Vector2i(360, 120))
	# 연속 Enter 입력으로도 파괴적 결정을 확정하지 않게 돌아가기를 기본 선택한다.
	discard_dialog.get_cancel_button().grab_focus()


func _discard(index: int) -> void:
	if not visible or not maintaining or discard_dialog.visible or index < 0 or index >= loot.bag.size():
		return
	_discard_index = index
	discard_dialog.title = tr("가방 아이템 폐기")
	discard_dialog.ok_button_text = tr("폐기")
	discard_dialog.dialog_text = tr("%s\n아이템 한 개를 버리시겠습니까?") % CombatLoot.describe(loot.bag[index])
	skip_confirmation.hide()
	_show_confirmation()


func _confirm() -> void:
	if not discard_dialog.visible:
		return
	if _discard_index < 0:
		var skip_next: bool = skip_confirmation.button_pressed
		_finish()
		if not visible and skip_next:
			_confirm_finish = false
		return
	var index: int = _discard_index
	_hide_discard()
	if index < loot.bag.size():
		loot.bag.remove_at(index)
	_render()
	continue_button.grab_focus()


func _hide_discard() -> void:
	# Godot 4.7.2 접근성이 제거 중인 exclusive child에 포커스를 보내지 않게 한다.
	discard_dialog.exclusive = false
	discard_dialog.hide()
	_discard_index = -1


func _finish() -> void:
	if not visible or not maintaining:
		return
	_hide_discard()
	var missing: int = loot.bag.size() + rewards.size() - int(loot.data["bag_limit"])
	if missing > 0:
		bag_notice.text = tr_n("가방 공간이 %d칸 부족합니다. 장착·물약 분배 또는 가방 아이템 폐기로 공간을 확보하세요.",
			"가방 공간이 %d칸 부족합니다. 장착·물약 분배 또는 가방 아이템 폐기로 공간을 확보하세요.", missing) % missing
		bag_notice.show()
		continue_button.grab_focus()
		return
	loot.bag.append_array(rewards)
	rewards.clear()
	hide()
	finished.emit()


func _render() -> void:
	bag_notice.hide()
	for parent: Node in [cards, content]:
		for child: Node in parent.get_children():
			parent.remove_child(child)
			child.queue_free()
	_cells = ButtonGroup.new()
	_selected_kind = ""
	title_label.text = tr("정비") if maintaining else tr_n("보상 · %d개", "보상 · %d개", rewards.size()) % rewards.size()
	hint_label.text = (tr("칸을 클릭해 고르고 아래 버튼으로 장착·해제·폐기합니다.") if maintaining
		else tr("받은 보상을 확인합니다. 정비에서 캐릭터에게 나눠 줍니다."))
	continue_button.text = (tr("3막 졸업") if final_stage else tr("다음 막 시작") if last_in_act
		else tr("다음 스테이지")) if maintaining else tr("정비하기")
	enable_button.visible = maintaining
	enable_button.disabled = _confirm_finish
	for index: int in range(party.size()):
		_render_card(index)
	_label(content, tr_n("받지 않은 보상 %d · 정비를 마치면 공용 가방에 보관",
		"받지 않은 보상 %d · 정비를 마치면 공용 가방에 보관", rewards.size()) % rewards.size()
		if not rewards.is_empty() else tr("남은 보상 없음"), GOLD_COLOR, false)
	var reward_grid: GridContainer = _grid(content, 7)
	for index: int in range(rewards.size()):
		_cell(reward_grid, rewards[index], "", "Item%d" % index, GOLD_COLOR).pressed.connect(
			func() -> void: _select("reward", index))
	_label(content, tr("공용 가방 · %d/%d칸") % [loot.bag.size(), int(loot.data["bag_limit"])])
	var bag_grid: GridContainer = _grid(content, 6)
	for index: int in range(int(loot.data["bag_limit"])):
		if index < loot.bag.size():
			_cell(bag_grid, loot.bag[index], "", "BagItem%d" % index, LINE_COLOR).pressed.connect(
				func() -> void: _select("bag", index))
		else:
			var empty: Panel = Panel.new()
			empty.custom_minimum_size = Vector2(36, 36)
			empty.add_theme_stylebox_override("panel", _style(LINE_COLOR, 0, 1, CELL_COLOR))
			bag_grid.add_child(empty)
	_label(content, tr("교체·해제한 장비와 받지 않은 보상은 공용 가방에 보관합니다."), DIM_COLOR)
	_render_detail()


func _render_card(index: int) -> void:
	var unit: CombatUnit = party[index]
	var card: PanelContainer = _panel(cards, LINE_COLOR, 0)
	card.custom_minimum_size = Vector2(300, 97)
	# 목업 좌표를 그대로 쓰려고 카드 안은 고정 배치한다.
	var area: Control = Control.new()
	card.add_child(area)
	var portrait: TextureRect = TextureRect.new()
	portrait.texture = load(UNIT_FRAME % unit.get_art_id()) as Texture2D
	portrait.position = Vector2(6, 4)
	portrait.size = Vector2(64, 64)
	if unit.hit_points <= 0:
		portrait.modulate = Color(0.35, 0.35, 0.35)
	area.add_child(portrait)
	_label(area, unit.get_display_name(), TEXT_COLOR, false).position = Vector2(76, 1)
	var hit_points: Label = _label(area, tr("HP %d / %d") % [unit.hit_points, unit.get_max_hit_points()],
		TEXT_COLOR, false)
	if unit.hit_points <= 0:
		hit_points.text = tr("HP %d / %d · 전투 불능") % [unit.hit_points, unit.get_max_hit_points()]
		hit_points.add_theme_color_override("font_color", DOWN_COLOR)
	hit_points.position = Vector2(76, 18)
	var bar: ColorRect = ColorRect.new()
	bar.color = Color("2a1513")
	bar.position = Vector2(76, 36)
	bar.size = Vector2(120, 4)
	area.add_child(bar)
	var fill: ColorRect = ColorRect.new()
	fill.color = Color("c0544d")
	fill.size = Vector2(120.0 * clampf(float(unit.hit_points) / unit.get_max_hit_points(), 0.0, 1.0), 4)
	bar.add_child(fill)
	var stats: Label = _label(area, _equipment_text(unit.weapon, tr("무기 없음")) + "\n"
		+ _equipment_text(unit.armor, tr("방어구 없음")), DIM_COLOR, false)
	stats.add_theme_constant_override("line_spacing", -4)
	stats.position = Vector2(76, 42)
	for slot: int in range(2):
		var x: float = 214.0 + slot * 42.0
		var item: Dictionary = unit.armor if slot == 1 else unit.weapon
		var cell: Button = _cell(area, item, unit.get_art_id(), ("Armor%d" if slot == 1 else "Weapon%d") % index,
			LINE_COLOR)
		cell.position = Vector2(x, 2)
		cell.pressed.connect(func() -> void: _select("armor" if slot == 1 else "weapon", index))
		var caption: Label = _label(area, tr("방어구") if slot == 1 else tr("무기"), DIM_COLOR, false)
		caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		caption.size.x = 44
		caption.position = Vector2(x - 4, 37)
	var potions: HBoxContainer = HBoxContainer.new()
	potions.position = Vector2(6, 74)
	potions.add_theme_constant_override("separation", 2)
	area.add_child(potions)
	var potion_icon: Texture2D = load(CombatLoot.icon_path({"icon": "potion"})) as Texture2D
	for slot: int in range(int(loot.data["potion_limit"])):
		var pip: TextureRect = TextureRect.new()
		pip.texture = potion_icon
		pip.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		pip.custom_minimum_size = Vector2(16, 16)
		pip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		if slot >= unit.potion_left:
			pip.modulate = Color(1, 1, 1, 0.18)
		potions.add_child(pip)
	_label(potions, tr("물약 %d/%d") % [unit.potion_left, int(loot.data["potion_limit"])], DIM_COLOR, false)
	for target: int in range(party.size()):
		if target == index or not maintaining:
			continue
		var button: Button = _button(potions, tr("물약 1개 → %s") % _short_name(party[target]),
			"Transfer%dTo%d" % [index, target])
		button.tooltip_text = (tr("넘길 물약이 없습니다.") if unit.potion_left <= 0
			else tr("받는 캐릭터의 물약이 가득 찼습니다.")
			if party[target].potion_left >= int(loot.data["potion_limit"]) else "")
		button.disabled = not button.tooltip_text.is_empty()
		button.pressed.connect(func() -> void: _transfer(index, target))


func _select(kind: String, index: int) -> void:
	_selected_kind = kind
	_selected_index = index
	_render_detail()


func _render_detail() -> void:
	for child: Node in detail.get_children():
		detail.remove_child(child)
		child.queue_free()
	detail_panel.add_theme_stylebox_override("panel",
		_style(SELECT_COLOR if not _selected_kind.is_empty() else LINE_COLOR, 6))
	if _selected_kind.is_empty():
		_label(detail, tr("칸을 클릭하면 여기에 아이템과 동작이 나옵니다. 방향키로 칸을 옮기고 Enter로 고릅니다.")
			if maintaining else tr("칸을 클릭하면 아이템 수치를 봅니다."), DIM_COLOR)
		return
	var owner_unit: CombatUnit = null if _selected_kind in ["reward", "bag"] else party[_selected_index]
	var item: Dictionary = (rewards[_selected_index] if _selected_kind == "reward"
		else loot.bag[_selected_index] if _selected_kind == "bag"
		else owner_unit.weapon if _selected_kind == "weapon" else owner_unit.armor)
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	detail.add_child(row)
	var icon: TextureRect = TextureRect.new()
	icon.custom_minimum_size = Vector2(32, 32)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	icon.texture = _icon(item, owner_unit.get_art_id() if owner_unit else "")
	row.add_child(icon)
	var info: VBoxContainer = VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.add_theme_constant_override("separation", 0)
	row.add_child(info)
	_label(info, _equipment_text(item, tr("무기 없음") if _selected_kind == "weapon" else tr("방어구 없음")))
	var actions: HBoxContainer = HBoxContainer.new()
	actions.add_theme_constant_override("separation", 6)
	match _selected_kind:
		"reward", "bag":
			var from_bag: bool = _selected_kind == "bag"
			_label(info, (tr("공용 가방 · 장착하면 지금 장비는 이 칸으로 옵니다.") if from_bag
				else tr("받지 않은 보상 · 정비를 마치면 공용 가방에 보관합니다.")) if maintaining
				else tr("정비하기를 누른 뒤 캐릭터에게 나눠 줍니다."), DIM_COLOR)
			if maintaining:
				for ally: int in range(party.size()):
					_receive_button(actions, item, _selected_index, ally, from_bag)
				if from_bag:
					var discard: Button = _button(actions, tr("폐기"), "DiscardItem")
					var index: int = _selected_index
					discard.pressed.connect(func() -> void: _discard(index))
		"weapon":
			_label(info, tr("%s의 무기 · 무기는 해제할 수 없습니다.") % _short_name(owner_unit), DIM_COLOR)
		"armor":
			_label(info, (tr("%s의 방어구 · 해제하면 공용 가방 빈 칸에 보관합니다.") if maintaining
				else tr("%s의 방어구 · 정비에서 해제할 수 있습니다.")) % _short_name(owner_unit), DIM_COLOR)
			var ally: int = _selected_index
			if maintaining:
				var unequip: Button = _button(actions, tr("방어구 해제"), "UnequipArmor%d" % ally)
				unequip.tooltip_text = loot.armor_unequip_blocker(owner_unit)
				unequip.disabled = not unequip.tooltip_text.is_empty()
				unequip.pressed.connect(func() -> void: _unequip_armor(ally))
	if actions.get_child_count() > 0:
		info.add_child(actions)
	else:
		actions.free()


## 상세 패널의 장착·물약 받기 버튼과 지금 장비 비교.
func _receive_button(parent: Node, item: Dictionary, index: int, ally: int, from_bag: bool) -> void:
	var unit: CombatUnit = party[ally]
	var potion: bool = item["kind"] == "potion"
	var button: Button = _button(parent, (tr("%s에게 주기") if potion else tr("%s에게 장착")) % _short_name(unit),
		"Ally%d" % ally)
	var full: bool = (potion and unit.potion_left >= int(loot.data["potion_limit"])) if from_bag \
		else not loot.can_receive(unit, item)
	button.tooltip_text = "" if not full else (tr("물약을 더 가질 수 없습니다.") if potion
		else tr("공용 가방에 빈 칸이 없어 지금 장비를 보관할 수 없습니다."))
	button.disabled = full
	if from_bag:
		button.pressed.connect(func() -> void: _receive_bag(index, ally))
	else:
		button.pressed.connect(func() -> void: _receive(index, ally))
	var compare: String = tr("물약 %d/%d") % [unit.potion_left, int(loot.data["potion_limit"])]
	if not potion:
		var current: Dictionary = (unit.weapon if item["kind"] == "weapon" else unit.armor).get("stats", {})
		var parts: PackedStringArray = []
		for stat: String in current.merged(item["stats"]):
			parts.append("%s %+d→%+d" % [CombatLoot.STAT_NAMES[stat], int(current.get(stat, 0)),
				int(item["stats"].get(stat, 0))])
		compare = " · ".join(parts)
	_label(parent, compare, DIM_COLOR, false)


func _receive(index: int, ally: int) -> void:
	if not visible or not maintaining or discard_dialog.visible or index < 0 or index >= rewards.size():
		return
	if loot.receive(party[ally], rewards[index]):
		rewards.remove_at(index)
		_render()
		continue_button.grab_focus()


func _receive_bag(index: int, ally: int) -> void:
	if visible and maintaining and not discard_dialog.visible and loot.receive_from_bag(party[ally], index):
		_render()
		continue_button.grab_focus()


func _unequip_armor(ally: int) -> void:
	if visible and maintaining and not discard_dialog.visible and loot.unequip_armor(party[ally]):
		_render()
		continue_button.grab_focus()


func _transfer(source: int, target: int) -> void:
	if visible and maintaining and not discard_dialog.visible and loot.transfer_potion(party[source], party[target]):
		_render()
		continue_button.grab_focus()


func _short_name(unit: CombatUnit) -> String:
	return tr("전사") if unit.kind == CombatUnit.Kind.WARRIOR else tr("궁수")


func _equipment_text(item: Dictionary, empty: String) -> String:
	return empty if item.is_empty() else CombatLoot.describe(item)


func _icon(item: Dictionary, unit_id: String) -> Texture2D:
	var path: String = CombatLoot.icon_path(item, unit_id)
	return null if path.is_empty() else load(path) as Texture2D


## 아이템 칸. 고르면 파란 테두리가 남는다.
func _cell(parent: Node, item: Dictionary, unit_id: String, node_name: String, border: Color) -> Button:
	var cell: Button = Button.new()
	cell.name = node_name
	cell.custom_minimum_size = Vector2(36, 36)
	cell.toggle_mode = true
	cell.button_group = _cells
	cell.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cell.add_theme_constant_override("icon_max_width", 32)
	cell.icon = _icon(item, unit_id)
	if not item.is_empty():
		cell.tooltip_text = CombatLoot.describe(item)
	for state: String in ["normal", "hover", "disabled"]:
		cell.add_theme_stylebox_override(state,
			_style(border.lightened(0.25) if state == "hover" else border, 0, 1, CELL_COLOR))
	for state: String in ["pressed", "hover_pressed"]:
		cell.add_theme_stylebox_override(state, _style(SELECT_COLOR, 0, 2, CELL_COLOR))
	var focus: StyleBoxFlat = _style(TEXT_COLOR, 0)
	focus.draw_center = false
	cell.add_theme_stylebox_override("focus", focus)
	parent.add_child(cell)
	return cell


func _grid(parent: Node, columns: int) -> GridContainer:
	var grid: GridContainer = GridContainer.new()
	grid.columns = columns
	grid.add_theme_constant_override("h_separation", 4)
	grid.add_theme_constant_override("v_separation", 4)
	parent.add_child(grid)
	return grid


func _panel(parent: Node, border: Color, padding: int = 6) -> PanelContainer:
	var panel: PanelContainer = PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _style(border, padding))
	parent.add_child(panel)
	return panel


func _style(border: Color, padding: int, width: int = 1, background: Color = PANEL_COLOR) -> StyleBoxFlat:
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = border
	style.set_border_width_all(width)
	style.set_corner_radius_all(3)
	style.set_content_margin_all(padding)
	return style


## wrap이 거짓이면 한 줄 글자다. 고정 배치 카드 안에서는 줄바꿈 폭이 없어 한 줄로 쓴다.
func _label(parent: Node, text: String, font_color: Color = TEXT_COLOR, wrap: bool = true) -> Label:
	var label: Label = Label.new()
	label.text = text
	if wrap:
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.add_theme_font_size_override("font_size", 12)
	label.add_theme_color_override("font_color", font_color)
	parent.add_child(label)
	return label


func _button(parent: Node, text: String, node_name: String) -> Button:
	var button: Button = Button.new()
	button.name = node_name
	button.text = text
	button.add_theme_font_size_override("font_size", 12)
	_style_button(button, Color("3a4856"))
	parent.add_child(button)
	return button


## 목업의 낮은 버튼. 기본 테마보다 위아래 여백이 작아 캐릭터 카드 한 줄에 들어간다.
func _style_button(button: Button, border: Color) -> void:
	for state: String in ["normal", "hover", "pressed", "hover_pressed", "focus", "disabled"]:
		var style: StyleBoxFlat = _style(border.lightened(0.3) if state.begins_with("hover") else border, 0, 1,
			Color("1b2631") if state != "disabled" else Color("131a21"))
		style.content_margin_left = 6
		style.content_margin_right = 6
		style.content_margin_top = 1
		style.content_margin_bottom = 1
		if state == "focus":
			style.draw_center = false
			style.border_color = TEXT_COLOR
		elif state == "disabled":
			style.border_color = Color("26303a")
		button.add_theme_stylebox_override(state, style)
	button.add_theme_color_override("font_disabled_color", Color("5d6873"))
