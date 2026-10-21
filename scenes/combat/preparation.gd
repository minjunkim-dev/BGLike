class_name CombatPreparation
extends ColorRect
## 전투 사이 보상 확인과 정비. 전투 화면 정보 구조는 바꾸지 않는다.

signal finished

var loot: CombatLoot
var party: Array[CombatUnit] = []
var rewards: Array[Dictionary] = []
var maintaining: bool = false
var final_stage: bool = false
var last_in_act: bool = false
var title_label: Label
var content: VBoxContainer
var continue_button: Button
var discard_dialog: ConfirmationDialog
var bag_notice: Label
var skip_confirmation: CheckBox
var confirmation_text: Label
var _discard_index: int = -1
var _confirm_finish: bool = true


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	color = Color(0.04, 0.06, 0.08, 1.0)
	var margin: MarginContainer = MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side: String in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 16)
	add_child(margin)
	var layout: VBoxContainer = VBoxContainer.new()
	layout.add_theme_constant_override("separation", 8)
	margin.add_child(layout)
	title_label = Label.new()
	title_label.add_theme_font_size_override("font_size", 16)
	layout.add_child(title_label)
	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	layout.add_child(scroll)
	content = VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 8)
	scroll.add_child(content)
	bag_notice = _label(layout, "")
	bag_notice.name = "BagNotice"
	bag_notice.hide()
	continue_button = Button.new()
	continue_button.name = "Continue"
	continue_button.custom_minimum_size.y = 32
	continue_button.pressed.connect(_continue)
	layout.add_child(continue_button)
	discard_dialog = ConfirmationDialog.new()
	discard_dialog.name = "Discard"
	discard_dialog.title = "정비 종료 확인"
	discard_dialog.ok_button_text = "마치기"
	discard_dialog.cancel_button_text = "돌아가기"
	discard_dialog.dialog_hide_on_ok = false
	discard_dialog.confirmed.connect(_confirm)
	discard_dialog.canceled.connect(_hide_discard)
	discard_dialog.get_label().hide()
	var confirmation_content: VBoxContainer = VBoxContainer.new()
	discard_dialog.add_child(confirmation_content)
	confirmation_text = _label(confirmation_content, "")
	confirmation_text.autowrap_mode = TextServer.AUTOWRAP_OFF
	skip_confirmation = CheckBox.new()
	skip_confirmation.name = "SkipConfirmation"
	skip_confirmation.text = "더 이상 이 메시지를 띄우지 않음"
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
			discard_dialog.title = "정비 종료 확인"
			discard_dialog.ok_button_text = "마치기"
			discard_dialog.dialog_text = "받지 않은 아이템이 있습니다. 마치시겠습니까?"
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
	discard_dialog.title = "가방 아이템 폐기"
	discard_dialog.ok_button_text = "폐기"
	discard_dialog.dialog_text = "%s\n아이템 한 개를 버리시겠습니까?" % CombatLoot.describe(loot.bag[index])
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
		bag_notice.text = "가방 공간이 %d칸 부족합니다. 장착·물약 분배 또는 가방 아이템 폐기로 공간을 확보하세요." % missing
		bag_notice.show()
		continue_button.grab_focus()
		return
	loot.bag.append_array(rewards)
	rewards.clear()
	hide()
	finished.emit()


func _render() -> void:
	bag_notice.hide()
	for child: Node in content.get_children():
		content.remove_child(child)
		child.queue_free()
	title_label.text = "정비" if maintaining else "보상 · %d개" % rewards.size()
	continue_button.text = ("3막 졸업" if final_stage else "다음 막 시작" if last_in_act
		else "다음 스테이지") if maintaining else "정비하기"
	if maintaining:
		var enable: Button = _button(content, "정비 종료 확인 다시 켜기", "EnableConfirmation")
		enable.disabled = _confirm_finish
		enable.pressed.connect(func() -> void:
			_confirm_finish = true
			_render()
			continue_button.grab_focus())
		var allies: HBoxContainer = HBoxContainer.new()
		allies.add_theme_constant_override("separation", 12)
		content.add_child(allies)
		for index: int in range(party.size()):
			var unit: CombatUnit = party[index]
			var card: VBoxContainer = VBoxContainer.new()
			card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			allies.add_child(card)
			_label(card, unit.get_display_name() + (" · 전투 불능" if unit.hit_points <= 0 else ""))
			_label(card, "HP %d / %d" % [unit.hit_points, unit.get_max_hit_points()])
			_label(card, "무기: " + CombatLoot.describe(unit.weapon))
			_label(card, "방어구: " + CombatLoot.describe(unit.armor))
			var unequip: Button = _button(card, "방어구 해제", "UnequipArmor%d" % index)
			unequip.tooltip_text = loot.armor_unequip_blocker(unit)
			unequip.disabled = not unequip.tooltip_text.is_empty()
			unequip.pressed.connect(func() -> void: _unequip_armor(index))
			_label(card, "물약 %d/%d" % [unit.potion_left, int(loot.data["potion_limit"])])
			for target: int in range(party.size()):
				if target == index:
					continue
				var button: Button = _button(card, "물약1개 → " + party[target].get_display_name(),
					"Transfer%dTo%d" % [index, target])
				button.disabled = unit.potion_left <= 0 or party[target].potion_left >= int(loot.data["potion_limit"])
				button.pressed.connect(func() -> void: _transfer(index, target))
		_label(content, "교체·해제한 장비와 받지 않은 보상은 공용 가방에 보관합니다.")
	_render_items(rewards, false)
	if rewards.is_empty():
		_label(content, "남은 보상 없음")
	if maintaining:
		_label(content, "공용 가방 · %d/%d칸" % [loot.bag.size(), int(loot.data["bag_limit"])])
		_render_items(loot.bag, true)
		if loot.bag.is_empty():
			_label(content, "가방이 비었습니다.")


func _render_items(items: Array[Dictionary], from_bag: bool) -> void:
	for index: int in range(items.size()):
		var item: Dictionary = items[index]
		var row: HBoxContainer = HBoxContainer.new()
		row.name = ("BagItem%d" if from_bag else "Item%d") % index
		content.add_child(row)
		_label(row, CombatLoot.describe(item))
		if maintaining:
			for ally: int in range(party.size()):
				var button: Button = _button(row, "전사" if party[ally].kind == CombatUnit.Kind.WARRIOR
					else "궁수", "Ally%d" % ally)
				button.disabled = (item["kind"] == "potion"
					and party[ally].potion_left >= int(loot.data["potion_limit"])) if from_bag else not loot.can_receive(party[ally], item)
				if from_bag:
					button.pressed.connect(func() -> void: _receive_bag(index, ally))
				else:
					button.pressed.connect(func() -> void: _receive(index, ally))
			if from_bag:
				var discard: Button = _button(row, "폐기", "Discard")
				discard.pressed.connect(func() -> void: _discard(index))


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


func _label(parent: Node, text: String) -> Label:
	var label: Label = Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.add_theme_font_size_override("font_size", 12)
	parent.add_child(label)
	return label


func _button(parent: Node, text: String, node_name: String) -> Button:
	var button: Button = Button.new()
	button.name = node_name
	button.text = text
	button.add_theme_font_size_override("font_size", 12)
	parent.add_child(button)
	return button
