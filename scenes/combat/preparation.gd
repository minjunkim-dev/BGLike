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
	continue_button = Button.new()
	continue_button.name = "Continue"
	continue_button.custom_minimum_size.y = 32
	continue_button.pressed.connect(_continue)
	layout.add_child(continue_button)
	discard_dialog = ConfirmationDialog.new()
	discard_dialog.name = "Discard"
	discard_dialog.title = "남은 보상 버리기"
	discard_dialog.ok_button_text = "보상 버리고 진행"
	discard_dialog.cancel_button_text = "돌아가기"
	discard_dialog.confirmed.connect(_finish)
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
		if rewards.is_empty():
			_finish()
		else:
			discard_dialog.dialog_text = "받지 않은 보상 %d개를 버리고 진행할까요?" % rewards.size()
			discard_dialog.popup_centered(Vector2i(360, 120))
			# 연속 Enter 입력으로도 보상을 버리지 않게 돌아가기를 기본 선택한다.
			discard_dialog.get_cancel_button().grab_focus()


func _finish() -> void:
	if not visible or not maintaining:
		return
	discard_dialog.hide()
	rewards.clear()
	hide()
	finished.emit()


func _render() -> void:
	for child: Node in content.get_children():
		content.remove_child(child)
		child.queue_free()
	title_label.text = "정비" if maintaining else "보상 · %d개" % rewards.size()
	continue_button.text = ("3막 졸업" if final_stage else "다음 막 시작" if last_in_act
		else "다음 스테이지") if maintaining else "정비하기"
	if maintaining:
		var allies: HBoxContainer = HBoxContainer.new()
		allies.add_theme_constant_override("separation", 12)
		content.add_child(allies)
		for index: int in range(party.size()):
			var unit: CombatUnit = party[index]
			var card: VBoxContainer = VBoxContainer.new()
			card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			allies.add_child(card)
			_label(card, unit.get_display_name() + (" · 전투 불능" if unit.hit_points <= 0 else ""))
			_label(card, "무기: " + CombatLoot.describe(unit.weapon))
			_label(card, "방어구: " + CombatLoot.describe(unit.armor))
			_label(card, "물약 %d/%d" % [unit.potion_left, int(loot.data["potion_limit"])])
			for target: int in range(party.size()):
				if target == index:
					continue
				var button: Button = _button(card, "물약1개 → " + party[target].get_display_name(),
					"Transfer%dTo%d" % [index, target])
				button.disabled = unit.potion_left <= 0 or party[target].potion_left >= int(loot.data["potion_limit"])
				button.pressed.connect(func() -> void: _transfer(index, target))
		_label(content, "장비 교체 시 이전 장비를 버립니다. 받지 않은 보상은 정비 종료 시 버립니다.")
	for index: int in range(rewards.size()):
		var item: Dictionary = rewards[index]
		var row: HBoxContainer = HBoxContainer.new()
		row.name = "Item%d" % index
		content.add_child(row)
		_label(row, CombatLoot.describe(item))
		if maintaining:
			for ally: int in range(party.size()):
				var button: Button = _button(row, "전사" if party[ally].kind == CombatUnit.Kind.WARRIOR
					else "궁수", "Ally%d" % ally)
				button.disabled = (item["kind"] == "potion"
					and party[ally].potion_left >= int(loot.data["potion_limit"]))
				button.pressed.connect(func() -> void: _receive(index, ally))
	if rewards.is_empty():
		_label(content, "남은 보상 없음")


func _receive(index: int, ally: int) -> void:
	if not visible or not maintaining or index < 0 or index >= rewards.size():
		return
	if loot.receive(party[ally], rewards[index]):
		rewards.remove_at(index)
		_render()
		continue_button.grab_focus()


func _transfer(source: int, target: int) -> void:
	if visible and maintaining and loot.transfer_potion(party[source], party[target]):
		_render()
		continue_button.grab_focus()


func _label(parent: Node, text: String) -> void:
	var label: Label = Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.add_theme_font_size_override("font_size", 12)
	parent.add_child(label)


func _button(parent: Node, text: String, node_name: String) -> Button:
	var button: Button = Button.new()
	button.name = node_name
	button.text = text
	button.add_theme_font_size_override("font_size", 12)
	parent.add_child(button)
	return button
