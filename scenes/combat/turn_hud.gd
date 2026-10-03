class_name CombatTurnHud
extends Control
## 턴 구조를 조작하는 최소 화면. 나머지 전투 UI는 M1 화면 단계에서 확장한다.

signal unit_selected(unit: CombatUnit)
signal end_turn_requested

const DEFAULT_BUTTON_COLOR: Color = Color("354656")
const END_BUTTON_COLOR: Color = Color("926725")

var _shown_order: Array[CombatUnit] = []
var _portraits: Dictionary[CombatUnit, Button] = {}

@onready var round_label: Label = $Round
@onready var order_bar: HBoxContainer = $OrderBar
@onready var unit_label: Label = $CurrentUnit
@onready var resource_label: Label = $Resources
@onready var end_button: Button = $EndTurn
@onready var preview_label: Label = $AttackPreview


func _ready() -> void:
	end_button.pressed.connect(func() -> void: end_turn_requested.emit())


func refresh(turns: CombatTurns, has_available_action: bool) -> void:
	preview_label.text = ""
	if _shown_order != turns.ordered_units:
		_build_portraits(turns)
	var current: CombatUnit = turns.current_unit
	end_button.disabled = current == null
	if current == null:
		round_label.text = "턴 종료"
		unit_label.text = "유닛 없음"
		resource_label.text = ""
		return
	round_label.text = "라운드 %d · %s 턴 묶음" % [turns.round_number, "아군" if current.is_ally else "적"]
	unit_label.text = current.get_display_name()
	resource_label.text = "이동 %d / %d\n행동 %s  보조 행동 %s  반응 %s" % [
		current.movement_left, CombatUnit.MOVEMENT_PER_TURN,
		"●" if current.action_left > 0 else "○",
		"▲" if current.bonus_action_left > 0 else "△",
		"◆" if current.reaction_left > 0 else "◇"
	]
	for unit: CombatUnit in _portraits:
		var button: Button = _portraits[unit]
		button.text = "%s\n%s\n%d" % ["아군" if unit.is_ally else "적",
			"전사" if unit.kind == CombatUnit.Kind.WARRIOR else "궁수", unit.get_initiative()]
		button.tooltip_text = "%s: d20 %d + 민첩 %d = %d" % [
			unit.get_display_name(), unit.initiative_roll, unit.get_dexterity(), unit.get_initiative()]
		var in_group: bool = unit in turns.get_current_group()
		button.disabled = not unit.is_ally or not in_group or turns.is_turn_finished(unit)
		var color: Color = CombatUnit.ALLY_COLOR if unit.is_ally else CombatUnit.ENEMY_COLOR
		if not in_group or turns.is_turn_finished(unit):
			color = color.darkened(0.6)
		var border: Color = Color("f4cf69") if unit == current else Color("61717e")
		var style: StyleBoxFlat = _button_style(color.darkened(0.3), border)
		for state: String in ["normal", "disabled", "hover", "pressed", "focus"]:
			button.add_theme_stylebox_override(state, style)
	var end_color: Color = DEFAULT_BUTTON_COLOR if has_available_action else END_BUTTON_COLOR
	end_button.add_theme_stylebox_override("normal", _button_style(end_color))
	end_button.add_theme_stylebox_override("hover", _button_style(end_color.lightened(0.12)))
	end_button.add_theme_stylebox_override("pressed", _button_style(end_color.darkened(0.12)))


func show_attack_preview(target: CombatUnit, preview: CombatChecks.AttackPreview) -> void:
	unit_label.text = target.get_display_name()
	resource_label.text = "HP %d / %d  AC %d\n상태: %s" % [
		target.hit_points, target.get_max_hit_points(), target.get_armor_class(),
		"기절" if target.is_stunned else "없음"
	]
	var mode_text: String = "일반"
	if preview.mode == CombatChecks.RollMode.ADVANTAGE:
		mode_text = "유리"
	elif preview.mode == CombatChecks.RollMode.DISADVANTAGE:
		mode_text = "불리"
	elif preview.reasons.size() == 2:
		mode_text = "유리/불리 상쇄"
	preview_label.text = "명중률 %.1f%% · %s" % [preview.chance * 100.0, mode_text]
	if not preview.valid_target:
		preview_label.text += "\n공격할 수 없는 대상"
	elif not preview.blocked_reason.is_empty():
		preview_label.text += "\n" + preview.blocked_reason
	elif not preview.in_range:
		preview_label.text += "\n사거리 밖"
	elif not preview.reasons.is_empty():
		preview_label.text += "\n" + ", ".join(preview.reasons)


func _build_portraits(turns: CombatTurns) -> void:
	for child: Node in order_bar.get_children():
		child.free()
	_portraits.clear()
	_shown_order = turns.ordered_units.duplicate()
	for group: Array in turns.get_turn_groups():
		var panel: PanelContainer = PanelContainer.new()
		var group_style: StyleBoxFlat = _button_style(Color("202b35"))
		group_style.content_margin_left = 4
		group_style.content_margin_right = 4
		group_style.content_margin_top = 4
		group_style.content_margin_bottom = 4
		panel.add_theme_stylebox_override("panel", group_style)
		var box: HBoxContainer = HBoxContainer.new()
		box.add_theme_constant_override("separation", 3)
		panel.add_child(box)
		order_bar.add_child(panel)
		for unit: CombatUnit in group:
			var button: Button = Button.new()
			button.custom_minimum_size = Vector2(48, 48)
			button.add_theme_font_size_override("font_size", 10)
			button.add_theme_color_override("font_disabled_color", Color("b5bdc4"))
			button.pressed.connect(func() -> void: unit_selected.emit(unit))
			box.add_child(button)
			_portraits[unit] = button


func _button_style(color: Color, border: Color = Color("61717e")) -> StyleBoxFlat:
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = color
	style.border_color = border
	style.set_border_width_all(1)
	return style
