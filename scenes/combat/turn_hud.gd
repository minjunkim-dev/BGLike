class_name CombatTurnHud
extends Control
## 전투 화면. 비용 기호와 막당 횟수를 서로 다른 위치에 표시한다.

signal unit_selected(unit: CombatUnit)
signal end_turn_requested
signal action_selected(action: String)
signal reaction_selected(use_reaction: bool)
signal restart_requested

const DEFAULT_BUTTON_COLOR: Color = Color("354656")
const END_BUTTON_COLOR: Color = Color("926725")
const RESOURCE_COLORS: Array[Color] = [Color("70c76d"), Color("edaa54"), Color("ac90e5")]
const ACTION_NAMES: Dictionary[String, String] = {
	"attack": "공격", "second_wind": "숨 고르기", "surge": "몰아치기",
	"mark": "표식", "shock": "충격 화살", "disengage": "물러서며 쏘기",
	"shove": "밀치기", "potion": "물약", "opportunity": "기회 공격", "parry": "흘려내기"
}
const ACTION_GROUPS: Array[Array] = [
	["attack", "shock"], ["second_wind", "surge", "mark", "disengage", "shove", "potion"],
	["opportunity", "parry"]
]
const ACTION_EFFECTS: Dictionary[String, String] = {
	"second_wind": "HP 1d10+1 회복.\n최대 HP를 넘지 않습니다.",
	"surge": "이미 쓴 행동을 다시 채워\n한 번 더 공격할 수 있습니다.",
	"mark": "1~6칸 적에게 표식.\n이 궁수가 맞히면 피해 +1d6.\n전투 중 유지됩니다.",
	"shock": "1~6칸 공격.\n명중 후 정신 내성 실패 시 기절.\n빗나가도 비용은 사용.",
	"disengage": "이번 턴의 남은 이동에서\n기회 공격을 받지 않습니다.\n공격을 실행하지 않습니다.",
	"shove": "내 힘 대 상대의 힘/민첩\n중 높은 값으로 대결.\n성공: 1칸 밀기, 동점: 실패.\n기절 대상은 대결 없이 성공.",
	"potion": "HP 2d4+2 회복.\n최대 HP를 넘지 않습니다.",
	"opportunity": "적이 내 인접 칸을 벗어나면 기본 공격. 발동할 때 사용 여부를 묻습니다.",
	"parry": "공격에 맞으면 사용 여부를 묻습니다. 민첩 내성에 성공하면 피해와 추가 효과를 피합니다."
}
const MOVEMENT_HELP: String = "파랑: 이동 가능한 칸\n초록: 도착 시 공격할 적 있음\n\n이동은 행동을 쓰지 않습니다.\n우클릭으로 경로 확인.\n같은 칸을 다시 우클릭하면 이동."

var _shown_order: Array[CombatUnit] = []
var _portraits: Dictionary[CombatUnit, Button] = {}
var _actions: Dictionary[String, Button] = {}
var _badges: Dictionary[String, Label] = {}
var _costs: Dictionary[String, Label] = {}
var _containers: Array[PanelContainer] = []
var _titles: Array[Label] = []
var _log_lines: Array[String] = []
var reaction_dialog: ConfirmationDialog = ConfirmationDialog.new()

@onready var round_label: Label = $Round
@onready var progress_label: Label = $Progress
@onready var order_bar: HBoxContainer = $OrderBar
@onready var unit_label: Label = $UnitDetails/UnitPanel/Info/CurrentUnit
@onready var actor_label: Label = $UnitDetails/UnitPanel/Info/Actor
@onready var resource_label: Label = $UnitDetails/UnitPanel/Info/Resources
@onready var health_bar: ProgressBar = $UnitDetails/UnitPanel/Info/Health
@onready var end_button: Button = $EndTurn
@onready var input_hint: Label = $InputHint
@onready var preview_label: Label = $UnitDetails/AttackPreview
@onready var action_bar: HBoxContainer = $Skills/Groups
@onready var message_label: Label = $CombatLog/Message
@onready var help_title: Label = $ActionHelp/Contents/Title
@onready var help_label: RichTextLabel = $ActionHelp/Contents/Details
@onready var result_label: Label = $Result/Panel/Contents/Outcome
@onready var restart_button: Button = $Result/Panel/Contents/Restart


func _ready() -> void:
	end_button.pressed.connect(func() -> void: end_turn_requested.emit())
	restart_button.pressed.connect(func() -> void: restart_requested.emit())
	for index: int in range(ACTION_GROUPS.size()):
		var panel: PanelContainer = PanelContainer.new()
		panel.add_theme_stylebox_override("panel", _panel_style())
		action_bar.add_child(panel)
		_containers.append(panel)
		var column: VBoxContainer = VBoxContainer.new()
		column.add_theme_constant_override("separation", 3)
		panel.add_child(column)
		var title: Label = Label.new()
		title.mouse_filter = Control.MOUSE_FILTER_PASS
		title.add_theme_font_size_override("font_size", 10)
		title.add_theme_color_override("font_color", RESOURCE_COLORS[index])
		column.add_child(title)
		_titles.append(title)
		var buttons: HBoxContainer = HBoxContainer.new()
		buttons.add_theme_constant_override("separation", 3)
		column.add_child(buttons)
		for action: String in ACTION_GROUPS[index]:
			var button: Button = Button.new()
			button.custom_minimum_size.y = 23
			button.add_theme_font_size_override("font_size", 10)
			button.add_theme_color_override("font_disabled_color", Color("8a939b"))
			# 반응은 표시용이다. 자기 턴의 입력에는 연결하지 않는다.
			if index != 2:
				button.pressed.connect(func() -> void: action_selected.emit(action))
			buttons.add_child(button)
			_actions[action] = button
			button.alignment = HORIZONTAL_ALIGNMENT_LEFT
			var cost: Label = Label.new()
			cost.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
			cost.position = Vector2(-13, 5)
			cost.add_theme_font_size_override("font_size", 10)
			cost.add_theme_color_override("font_color", RESOURCE_COLORS[index])
			cost.mouse_filter = Control.MOUSE_FILTER_IGNORE
			cost.reset_size()
			button.add_child(cost)
			_costs[action] = cost
			var badge: Label = Label.new()
			badge.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
			badge.position = Vector2(-12, -8)
			badge.custom_minimum_size.x = 12
			badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			badge.add_theme_font_size_override("font_size", 8)
			badge.add_theme_color_override("font_color", Color("ffffff"))
			var badge_style: StyleBoxFlat = _button_style(Color("485568"))
			badge_style.content_margin_left = 1
			badge_style.content_margin_right = 1
			badge_style.content_margin_top = 0
			badge_style.content_margin_bottom = 0
			badge.add_theme_stylebox_override("normal", badge_style)
			badge.reset_size()
			badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
			button.add_child(badge)
			_badges[action] = badge
	add_child(reaction_dialog)
	reaction_dialog.title = "반응"
	reaction_dialog.dialog_autowrap = true
	reaction_dialog.confirmed.connect(func() -> void: reaction_selected.emit(true))
	reaction_dialog.canceled.connect(func() -> void: reaction_selected.emit(false))


func refresh_actions(actions: CombatActions, selected: String, last_ally: CombatUnit,
		show_action_help: bool = true) -> void:
	var actor: CombatUnit = actions.turns.current_unit
	var shown: CombatUnit = actor if actor != null and actor.is_ally else last_ally
	var ally_turn: bool = actor != null and actor.is_ally
	var locked: bool = actions.busy or actions.is_over()
	var symbols: Array[String] = ["●", "▲", "◆"]
	var empty_symbols: Array[String] = ["○", "△", "◇"]
	var names: Array[String] = ["행동", "보조 행동", "반응"]
	for index: int in range(_containers.size()):
		_containers[index].visible = shown != null and (index != 2 or shown.kind == CombatUnit.Kind.WARRIOR)
		if shown == null:
			continue
		var amounts: Array[int] = [shown.action_left, shown.bonus_action_left, shown.reaction_left]
		_titles[index].text = "%s %s · %s" % [names[index],
			symbols[index] if amounts[index] > 0 else empty_symbols[index],
			"남음" if amounts[index] > 0 else "사용함"]
		_titles[index].tooltip_text = "%s: 자기 턴 시작에 1회 회복. 채운 기호는 남음, 빈 기호는 사용함." % names[index]
		if index == 2:
			_titles[index].tooltip_text += "\n기회 공격과 흘려내기가 같은 반응을 씁니다."
		_titles[index].modulate = Color.WHITE if ally_turn else Color("888888")
		for action: String in ACTION_GROUPS[index]:
			var button: Button = _actions[action]
			button.visible = _belongs_to(shown, action)
			button.text = ACTION_NAMES[action] + "    "
			_costs[action].text = symbols[index]
			button.tooltip_text = action_details(actions, shown, action)
			button.tooltip_text += "\n오른쪽 기호: 이번 턴 비용. 위 숫자: " + (
				"현재 보유 물약." if action == "potion" else "이번 막의 남은 횟수.")
			var active: bool = ally_turn and not locked and actions.can_use(actor, action)
			# 반응은 횟수나 자원을 다 써도 자기 턴에는 켜진 표시로 남는다.
			button.disabled = (not ally_turn or locked) if index == 2 else not active
			var color: Color = Color("293541") if not button.disabled else Color("242a30")
			var border: Color = Color("f4cf69") if selected == action and active else Color("61717e")
			for state: String in ["normal", "hover", "pressed", "disabled", "focus"]:
				button.add_theme_stylebox_override(state, _button_style(color, border))
			var uses: int = _remaining_uses(shown, action)
			_badges[action].visible = uses >= 0
			_badges[action].text = str(uses)
			_badges[action].reset_size()
			_costs[action].reset_size()
			_badges[action].modulate = Color.WHITE if ally_turn else Color("888888")
			_costs[action].modulate = Color.WHITE if not button.disabled else Color("666666")
	input_hint.modulate = Color.WHITE if ally_turn and not locked else Color("888888")
	input_hint.tooltip_text = "이동력만 씁니다. 행동과 보조 행동은 쓰지 않습니다.\n자기 턴에 6칸 회복. 나눠 이동할 수 있습니다.\n우클릭으로 경로 확인, 같은 칸을 다시 우클릭해 이동."
	end_button.disabled = not ally_turn or locked
	for button: Button in _portraits.values():
		button.disabled = button.disabled or locked
	if not show_action_help:
		return
	if not ally_turn:
		show_help("적 턴", "적이 자동으로 이동·공격합니다.\n이동·공격 입력은 잠깁니다.\n초상으로 정보를 확인할 수 있습니다.\n반응 확인 창에서 사용할지 고르세요.\n\n● 행동: 공격\n▲ 보조 행동: 보조 스킬\n◆ 반응: 조건이 맞으면 사용\n빈 기호는 이미 쓴 자원입니다.")
	else:
		show_help("이동 안내" if selected == "move" else ACTION_NAMES.get(selected, "동작 안내"),
			action_details(actions, shown, selected))


func show_help(title: String, details: String) -> void:
	var changed: bool = help_title.text != title or help_label.text != details
	help_title.text = title
	help_label.text = details
	if changed:
		help_label.get_v_scroll_bar().value = 0


func action_details(actions: CombatActions, actor: CombatUnit, action: String) -> String:
	if actor == null:
		return ""
	if action == "move":
		return MOVEMENT_HELP + "\n" + movement_caution(actor)
	var effect: String = ACTION_EFFECTS.get(action, "")
	if action == "attack":
		effect = "인접한 적을 기본 공격합니다." if actor.kind == CombatUnit.Kind.WARRIOR else "1~6칸 원거리 공격.\n옆에 적이 있으면 불리."
	var index: int = 0 if action in ACTION_GROUPS[0] else 1 if action in ACTION_GROUPS[1] else 2
	var costs: Array[String] = ["행동 ●", "보조 행동 ▲", "반응 ◆"]
	var amount: int = [actor.action_left, actor.bonus_action_left, actor.reaction_left][index]
	var text: String = "비용: %s · %s" % [costs[index], "남음" if amount > 0 else "사용함"]
	var uses: int = _remaining_uses(actor, action)
	if action == "potion":
		text += "\n보유 물약 %d개" % uses
	else:
		text += "\n막당 %d회 남음" % uses if uses >= 0 else "\n횟수 제한 없음"
	text += "\n" + effect
	if index == 2:
		return text + "\n버튼으로 실행하지 않습니다. 발동 시 확인 창을 사용합니다."
	var reason: String = _unavailable_reason(actions, actor, action, amount, uses)
	if not reason.is_empty():
		return text + "\n지금 사용 불가: " + reason
	return text + ("\n같은 버튼을 다시 눌러 사용." if action in ["second_wind", "surge", "disengage", "potion"]
		else "\n적을 좌클릭해 미리보기.\n같은 적을 다시 좌클릭하면 사용.")


func _unavailable_reason(actions: CombatActions, actor: CombatUnit, action: String,
	amount: int, uses: int) -> String:
	if actions.busy or actions.is_over():
		return "전투 입력 잠금"
	if actor != actions.turns.current_unit or not actor.is_ally:
		return "아군의 자기 턴에만 사용"
	if uses == 0:
		return "보유 물약 없음" if action == "potion" else "이번 막의 횟수를 모두 씀"
	if amount == 0:
		return "자원을 이미 씀. 자기 턴 시작에 회복"
	if action in ["second_wind", "potion"] and actor.hit_points == actor.get_max_hit_points():
		return "HP가 이미 최대"
	if action == "surge" and actor.action_left > 0:
		return "행동이 아직 남아 있음"
	if not actions.can_use(actor, action):
		return "이동이 없거나 이미 효과 적용 중" if action == "disengage" else "사거리 또는 대상 조건을 확인"
	return ""


func movement_caution(actor: CombatUnit) -> String:
	return "이번 턴 기회 공격 없음." if actor != null and actor.disengaged else "적 곁에서 반격 주의."


func _belongs_to(actor: CombatUnit, action: String) -> bool:
	if action in ["second_wind", "surge", "opportunity", "parry"]:
		return actor.kind == CombatUnit.Kind.WARRIOR
	if action in ["mark", "shock", "disengage"]:
		return actor.kind == CombatUnit.Kind.ARCHER
	return true


func _remaining_uses(actor: CombatUnit, action: String) -> int:
	match action:
		"second_wind": return actor.second_wind_left
		"surge": return actor.surge_left
		"mark": return actor.mark_left
		"shock": return actor.shock_left
		"disengage": return actor.disengage_left
		"potion": return actor.potion_left
		"parry": return actor.parry_left
	return -1


func add_log(message: String) -> void:
	_log_lines.append(message.replace("\n", " "))
	while _log_lines.size() > 3:
		_log_lines.pop_front()
	message_label.text = "\n".join(_log_lines)


func show_reaction(kind: String, prompt: String) -> void:
	reaction_dialog.dialog_text = prompt
	reaction_dialog.get_ok_button().text = "공격" if kind == "opportunity" else "흘려내기"
	reaction_dialog.get_cancel_button().text = "넘기기"
	reaction_dialog.popup_centered(Vector2i(360, 110))


func begin_stage(act: int, stage: int) -> void:
	progress_label.text = "%d막 · %d스테이지" % [act, stage]
	$Result.hide()
	reaction_dialog.hide()
	_log_lines.clear()
	message_label.text = ""
	restart_button.show()


func show_result(victory: bool, final_stage: bool = false, last_in_act: bool = false) -> void:
	reaction_dialog.hide()
	var graduated: bool = victory and final_stage
	result_label.text = "3막 졸업" if graduated else "승리" if victory else "패배"
	restart_button.visible = not graduated
	restart_button.text = ("다음 막 시작" if last_in_act else "다음 스테이지") if victory else "이 막 다시 시작"
	$Result.show()
	if not graduated:
		restart_button.grab_focus()


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
		actor_label.text = ""
		return
	round_label.text = "라운드 %d · %s 턴 묶음" % [turns.round_number, "아군" if current.is_ally else "적"]
	actor_label.text = ("조작: " if current.is_ally else "진행: ") + current.get_display_name()
	show_unit(current)
	for unit: CombatUnit in _portraits:
		var button: Button = _portraits[unit]
		button.text = "%s\n%s\n%d" % ["아군" if unit.is_ally else "적",
			"전사" if unit.kind == CombatUnit.Kind.WARRIOR else "궁수", unit.get_initiative()]
		button.tooltip_text = "%s: d20 %d + 민첩 %d = %d" % [
			unit.get_display_name(), unit.initiative_roll, unit.get_dexterity(), unit.get_initiative()]
		var in_group: bool = unit in turns.get_current_group()
		button.disabled = false
		var color: Color = CombatUnit.ALLY_COLOR if unit.is_ally else CombatUnit.ENEMY_COLOR
		if not in_group or turns.is_turn_finished(unit):
			color = color.darkened(0.6)
		var border: Color = Color("f4cf69") if unit == current else Color("61717e")
		for state: String in ["normal", "disabled", "hover", "pressed", "focus"]:
			button.add_theme_stylebox_override(state, _button_style(color.darkened(0.3), border))
	var end_color: Color = DEFAULT_BUTTON_COLOR if has_available_action else END_BUTTON_COLOR
	end_button.add_theme_stylebox_override("normal", _button_style(end_color))
	end_button.add_theme_stylebox_override("hover", _button_style(end_color.lightened(0.12)))
	end_button.add_theme_stylebox_override("pressed", _button_style(end_color.darkened(0.12)))


func show_unit(unit: CombatUnit) -> void:
	unit_label.text = unit.get_display_name()
	health_bar.max_value = unit.get_max_hit_points()
	health_bar.value = unit.hit_points
	var states: Array[String] = []
	if unit.is_stunned:
		states.append("기절")
	if unit.has_mark:
		states.append("◎ 표식")
	if unit.disengaged:
		states.append("기회 공격 면제")
	resource_label.text = "HP %d / %d   AC %d\n힘 %+d · 민첩 %+d · 체력 %+d · 정신 %+d\n명중 %+d · 사거리 %d칸\n이동 %d / %d · 행동 %d · 보조 %d · 반응 %d\n상태: %s" % [
		unit.hit_points, unit.get_max_hit_points(), unit.get_armor_class(),
		unit.get_attribute(CombatUnit.Attribute.STRENGTH), unit.get_dexterity(),
		unit.get_attribute(CombatUnit.Attribute.CONSTITUTION), unit.get_attribute(CombatUnit.Attribute.MENTAL),
		unit.get_attack_bonus(), unit.get_attack_range(),
		unit.movement_left, CombatUnit.MOVEMENT_PER_TURN,
		unit.action_left, unit.bonus_action_left, unit.reaction_left,
		", ".join(states) if not states.is_empty() else "없음"]


func show_attack_preview(target: CombatUnit, preview: CombatChecks.AttackPreview) -> void:
	show_unit(target)
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
		panel.add_theme_stylebox_override("panel", _panel_style())
		var box: HBoxContainer = HBoxContainer.new()
		box.add_theme_constant_override("separation", 3)
		panel.add_child(box)
		order_bar.add_child(panel)
		for unit: CombatUnit in group:
			var button: Button = Button.new()
			button.custom_minimum_size = Vector2(40, 43)
			button.add_theme_font_size_override("font_size", 10)
			button.add_theme_color_override("font_disabled_color", Color("b5bdc4"))
			button.pressed.connect(func() -> void: unit_selected.emit(unit))
			box.add_child(button)
			_portraits[unit] = button


func _panel_style() -> StyleBoxFlat:
	var style: StyleBoxFlat = _button_style(Color("202b35"))
	style.content_margin_left = 4
	style.content_margin_right = 4
	style.content_margin_top = 3
	style.content_margin_bottom = 3
	return style


func _button_style(color: Color, border: Color = Color("61717e")) -> StyleBoxFlat:
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = color
	style.border_color = border
	style.set_border_width_all(1)
	style.content_margin_left = 4
	style.content_margin_right = 4
	return style
