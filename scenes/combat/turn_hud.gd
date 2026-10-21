class_name CombatTurnHud
extends Control
## 전투 화면. 비용 기호와 막당 횟수를 서로 다른 위치에 표시한다.

signal unit_selected(unit: CombatUnit)
signal end_turn_requested
signal action_selected(action: String)
signal reaction_selected(use_reaction: bool)
signal restart_requested

# 기본 툴팁 창 대신 같은 HUD의 최상단에 설명을 그린다.
class HoverButton extends Button:
	func _get_tooltip(_at_position: Vector2) -> String:
		return ""

# Space는 적 턴 가속 키다. 반응 확인 창의 포커스된 버튼을 누르지 않는다.
class SpaceBlocker extends Node:
	func _input(event: InputEvent) -> void:
		if event is InputEventKey and event.keycode == KEY_SPACE:
			get_viewport().set_input_as_handled()

const DEFAULT_BUTTON_COLOR: Color = Color("354656")
const END_BUTTON_COLOR: Color = Color("926725")
const RESOURCE_COLORS: Array[Color] = [Color("70c76d"), Color("edaa54"), Color("ac90e5")]

var _shown_order: Array[CombatUnit] = []
var _portraits: Dictionary[CombatUnit, Button] = {}
var _order_moves: Dictionary[CombatUnit, Vector2] = {}
var _order_tween: Tween
var _order_revision: int = 0
var _actions: Dictionary[String, Button] = {}
# 지금 보이는 스킬 버튼. 숫자 키와 방향키가 왼쪽부터 이 순서를 쓴다.
var _action_slots: Array[Button] = []
var _badges: Dictionary[String, Label] = {}
var _costs: Dictionary[String, Label] = {}
var _containers: Array[PanelContainer] = []
var _titles: Array[Label] = []
var _log_lines: Array[String] = []
var _tooltip_owner: Control
var _tooltip_panel: PanelContainer = PanelContainer.new()
var _tooltip_label: Label = Label.new()
var _tooltip_timer: Timer = Timer.new()
var reaction_dialog: ConfirmationDialog = ConfirmationDialog.new()

@onready var round_label: Label = $Round
@onready var progress_label: Label = $Progress
@onready var order_bar: HBoxContainer = $OrderScroll/OrderBar
@onready var unit_label: Label = $UnitDetails/UnitPanel/Info/CurrentUnit
@onready var actor_label: Label = $UnitDetails/UnitPanel/Info/Actor
@onready var resource_label: Label = $UnitDetails/UnitPanel/Info/Resources
@onready var health_bar: ProgressBar = $UnitDetails/UnitPanel/Info/Health
@onready var end_button: Button = $EndTurn
@onready var preview_label: Label = $UnitDetails/AttackPreview
@onready var action_bar: HBoxContainer = $Skills/Groups
@onready var message_label: Label = $CombatLog/Message
@onready var result_label: Label = $Result/Panel/Contents/Outcome
@onready var restart_button: Button = $Result/Panel/Contents/Restart


func feedback_obstacles() -> Array[Rect2]:
	var result: Array[Rect2] = []
	for panel: Control in [$Round, $Progress, $OrderScroll, $UnitDetails, $Skills, $CombatLog, $EndTurn]:
		if panel.is_visible_in_tree():
			result.append(panel.get_global_rect())
	return result


func _ready() -> void:
	# 기본 반투명 배경은 아래 지형에 따라 대비가 바뀐다. 불투명 패널로 WCAG AA를 고정한다.
	$CombatLog.add_theme_stylebox_override("panel", _panel_style())
	_tooltip_panel.z_index = 10
	_tooltip_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tooltip_panel.add_theme_stylebox_override("panel", _panel_style())
	_tooltip_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tooltip_label.add_theme_font_size_override("font_size", 10)
	_tooltip_panel.add_child(_tooltip_label)
	add_child(_tooltip_panel)
	_tooltip_panel.hide()
	_tooltip_timer.one_shot = true
	_tooltip_timer.wait_time = 0.5
	_tooltip_timer.timeout.connect(_update_tooltip)
	add_child(_tooltip_timer)
	end_button.pressed.connect(func() -> void: end_turn_requested.emit())
	restart_button.pressed.connect(func() -> void: restart_requested.emit())
	for index: int in range(CombatActionRules.GROUPS.size()):
		var panel: PanelContainer = PanelContainer.new()
		panel.add_theme_stylebox_override("panel", _panel_style())
		action_bar.add_child(panel)
		_containers.append(panel)
		var column: VBoxContainer = VBoxContainer.new()
		column.add_theme_constant_override("separation", 3)
		panel.add_child(column)
		var title: Label = Label.new()
		title.mouse_filter = Control.MOUSE_FILTER_IGNORE
		title.add_theme_font_size_override("font_size", 10)
		title.add_theme_color_override("font_color", RESOURCE_COLORS[index])
		column.add_child(title)
		_titles.append(title)
		var buttons: HBoxContainer = HBoxContainer.new()
		buttons.add_theme_constant_override("separation", 3)
		column.add_child(buttons)
		for action: String in CombatActionRules.GROUPS[index]:
			var button: Button = HoverButton.new()
			# 아이콘 오른쪽에 비용 마크 자리를 남긴다.
			button.custom_minimum_size.x = 52
			button.icon = CombatActionRules.icon_of(action)
			button.material = preload("res://scenes/combat/art/pixel_art.tres")
			button.add_theme_constant_override("icon_max_width", 32)
			# 곱셈 색은 채도를 빼지 못해 반투명으로 어둡게 눌러 회색 배경에 묻는다.
			button.add_theme_color_override("icon_disabled_color", Color("8a939b", 0.55))
			button.accessibility_name = CombatActionRules.NAMES[action]
			# 반응은 표시용이다. 자기 턴의 입력에는 연결하지 않는다.
			if index != 2:
				button.pressed.connect(func() -> void: action_selected.emit(action))
			buttons.add_child(button)
			_connect_tooltip(button)
			_actions[action] = button
			button.icon_alignment = HORIZONTAL_ALIGNMENT_LEFT
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
	reaction_dialog.add_child(SpaceBlocker.new())
	reaction_dialog.title = tr("반응")
	reaction_dialog.dialog_autowrap = true
	reaction_dialog.dialog_hide_on_ok = false
	reaction_dialog.confirmed.connect(_finish_reaction.bind(true))
	reaction_dialog.canceled.connect(_finish_reaction.bind(false))


func _connect_tooltip(control: Control) -> void:
	var start: Callable = func() -> void:
		# 호버 중 클릭으로 포커스를 받아도 떠 있는 설명을 다시 기다리게 하지 않는다.
		if _tooltip_owner == control and (_tooltip_panel.visible or not _tooltip_timer.is_stopped()):
			return
		_tooltip_owner = control
		_tooltip_panel.hide()
		_tooltip_timer.start()
	var stop: Callable = func() -> void:
		if _tooltip_owner == control:
			_tooltip_owner = null
			_tooltip_timer.stop()
			_tooltip_panel.hide()
	control.mouse_entered.connect(start)
	control.mouse_exited.connect(stop)
	# 키보드·컨트롤러 포커스도 같은 설명을 띄운다. 클릭으로 받은 포커스는 마우스가 떠나면 숨긴다.
	control.focus_entered.connect(start)
	control.focus_exited.connect(stop)


func _process(_delta: float) -> void:
	if _tooltip_panel.visible:
		_update_tooltip()


func _update_tooltip() -> void:
	if not is_instance_valid(_tooltip_owner) or not _tooltip_owner.is_visible_in_tree() \
		or reaction_dialog.visible or $Result.visible:
		_tooltip_panel.hide()
		return
	_tooltip_label.text = _tooltip_owner.tooltip_text
	_tooltip_panel.size = _tooltip_panel.get_combined_minimum_size()
	var rect: Rect2 = _tooltip_owner.get_global_rect()
	var top: float = ($Skills as Control).position.y if $Skills.is_ancestor_of(_tooltip_owner) else rect.position.y
	var y: float = top - _tooltip_panel.size.y - 4
	if y < 4:
		y = rect.end.y + 4
	_tooltip_panel.position = Vector2(
		clampf(rect.position.x, 4, size.x - _tooltip_panel.size.x - 4),
		clampf(y, 4, size.y - _tooltip_panel.size.y - 4))
	_tooltip_panel.show()


func refresh_actions(actions: CombatActions, selected: String, last_ally: CombatUnit) -> void:
	var actor: CombatUnit = actions.turns.current_unit
	var shown: CombatUnit = actor if actor != null and actor.is_ally else last_ally
	var ally_turn: bool = actor != null and actor.is_ally
	var locked: bool = actions.busy or actions.is_over()
	var symbols: Array[String] = ["●", "▲", "◆"]
	var empty_symbols: Array[String] = ["○", "△", "◇"]
	var names: Array[String] = [tr("행동"), tr("보조 행동"), tr("반응")]
	_action_slots.clear()
	for index: int in range(_containers.size()):
		_containers[index].visible = shown != null and (index != 2 or shown.kind == CombatUnit.Kind.WARRIOR)
		if shown == null:
			continue
		var amounts: Array[int] = [shown.action_left, shown.bonus_action_left, shown.reaction_left]
		var capacities: Array[int] = [shown.action_capacity, shown.bonus_action_capacity, shown.reaction_capacity]
		var remaining: int = clampi(amounts[index], 0, capacities[index])
		_titles[index].text = "%s %s" % [names[index],
			symbols[index].repeat(remaining) + empty_symbols[index].repeat(capacities[index] - remaining)]
		_titles[index].modulate = Color.WHITE if ally_turn else Color("888888")
		for action: String in CombatActionRules.GROUPS[index]:
			var button: Button = _actions[action]
			button.visible = CombatActionRules.belongs_to(shown, action)
			if button.visible and _containers[index].visible:
				_action_slots.append(button)
			_costs[action].text = symbols[index]
			button.tooltip_text = CombatActionRules.NAMES[action] + "\n" + action_details(actions, shown, action)
			var active: bool = ally_turn and not locked and actions.can_use(actor, action)
			# 반응은 횟수나 자원을 다 써도 자기 턴에는 켜진 표시로 남는다.
			button.disabled = (not ally_turn or locked) if index == 2 else not active
			var color: Color = Color("293541") if not button.disabled else Color("242a30")
			var border: Color = Color("f4cf69") if selected == action and active else Color("61717e")
			for state: String in ["normal", "hover", "pressed", "disabled"]:
				button.add_theme_stylebox_override(state, _button_style(color, border))
			# 키보드·컨트롤러 포커스는 배경 위에 흰 테두리만 겹친다.
			var focus: StyleBoxFlat = _button_style(color, Color.WHITE)
			focus.draw_center = false
			button.add_theme_stylebox_override("focus", focus)
			var uses: int = CombatActionRules.uses_left(shown, action)
			_badges[action].visible = uses >= 0
			_badges[action].text = str(uses)
			_badges[action].reset_size()
			_costs[action].reset_size()
			_badges[action].modulate = Color.WHITE if ally_turn else Color("888888")
			_costs[action].modulate = Color.WHITE if not button.disabled else Color("666666")
	# 좌우 방향키·D-pad는 스킬 바 안에서만 옮긴다. 스틱을 누르고 있어도 끝에서 멈춘다.
	for index: int in range(_action_slots.size()):
		var button: Button = _action_slots[index]
		button.focus_neighbor_left = button.get_path_to(_action_slots[maxi(index - 1, 0)])
		button.focus_neighbor_right = button.get_path_to(_action_slots[mini(index + 1, _action_slots.size() - 1)])
	end_button.disabled = not ally_turn or locked
	for button: Button in _portraits.values():
		button.disabled = button.disabled or locked


## 스킬 바의 slot번째 버튼에 포커스를 준다. 비활성 버튼은 설명만 보이고 누르지 않는다.
func focus_action_slot(slot: int, press: bool) -> void:
	if slot >= _action_slots.size():
		return
	var button: Button = _action_slots[slot]
	button.grab_focus()
	if press and not button.disabled:
		button.pressed.emit()


func action_details(actions: CombatActions, actor: CombatUnit, action: String) -> String:
	if actor == null:
		return ""
	var effect: String = CombatActionRules.effect(actor, action)
	var details: String = CombatActionRules.details(actor, action)
	if not details.is_empty():
		effect += "\n" + details
	var reason: String = actions.unavailable_reason(actor, action)
	if not reason.is_empty():
		return effect + "\n" + tr("지금 사용 불가: %s") % reason
	return effect


func add_log(message: String) -> void:
	_log_lines.append(message.replace("\n", " "))
	while _log_lines.size() > 3:
		_log_lines.pop_front()
	message_label.text = "\n".join(_log_lines)


func show_reaction(kind: String, prompt: String) -> void:
	reaction_dialog.dialog_text = prompt
	reaction_dialog.get_ok_button().text = tr("공격") if kind == "opportunity" else tr("흘려내기")
	reaction_dialog.get_cancel_button().text = tr("넘기기")
	reaction_dialog.exclusive = true
	reaction_dialog.popup_centered(Vector2i(360, 110))


func _hide_reaction() -> void:
	# Godot 4.7.2 접근성은 창 제거 중에도 exclusive child에 포커스를 전달한다.
	reaction_dialog.exclusive = false
	reaction_dialog.hide()


func _finish_reaction(use_reaction: bool) -> void:
	_hide_reaction()
	reaction_selected.emit(use_reaction)


func begin_stage(act: int, stage: int) -> void:
	_order_revision += 1
	if _order_tween != null:
		_order_tween.kill()
	_order_moves.clear()
	_shown_order.clear()
	progress_label.text = tr("%d막 · %d스테이지") % [act, stage]
	$Result.hide()
	_hide_reaction()
	_log_lines.clear()
	message_label.text = ""
	restart_button.show()


func show_result(victory: bool, graduated: bool = false, locked: bool = false) -> void:
	_hide_reaction()
	var complete: bool = victory and graduated
	result_label.text = tr("3막 졸업") if complete else tr("승리") if victory else tr("패배")
	restart_button.visible = not complete
	restart_button.text = tr("보상 확인") if victory else tr("이 막 다시 시작")
	$Result.show()
	if not complete:
		restart_button.grab_focus()
	restart_button.disabled = locked


func hide_result() -> void:
	$Result.hide()


func show_outcome(victory: bool) -> void:
	round_label.text = tr("승리") if victory else tr("패배")


## 표식·밀치기처럼 명중률 대신 보일 대상 안내.
func show_target_note(text: String) -> void:
	preview_label.text = text


func show_move_mode(showing_move: bool) -> void:
	preview_label.visible = not showing_move


func refresh(turns: CombatTurns, has_available_action: bool) -> void:
	preview_label.text = ""
	if _shown_order != turns.ordered_units:
		for unit: CombatUnit in _shown_order:
			if unit not in turns.ordered_units or (_order_tween != null and _order_tween.is_running()):
				prepare_order_rotation(_shown_order)
				break
		_build_portraits(turns)
	var current: CombatUnit = turns.current_unit
	end_button.disabled = current == null
	if current == null:
		round_label.text = tr("턴 종료")
		unit_label.text = tr("유닛 없음")
		resource_label.text = ""
		actor_label.text = ""
		return
	round_label.text = tr("라운드 %d · %s") % [turns.round_number, tr("아군 턴 묶음") if current.is_ally else tr("적 턴 묶음 · Space: 빠르게")]
	actor_label.text = (tr("조작: %s") if current.is_ally else tr("진행: %s")) % current.get_display_name()
	show_unit(current)
	for unit: CombatUnit in _portraits:
		var button: Button = _portraits[unit]
		button.text = "%s\n%s" % [tr("아군") if unit.is_ally else tr("적"),
			unit.get_display_name() if not unit.is_ally
			else tr("전사") if unit.kind == CombatUnit.Kind.WARRIOR else tr("궁수")]
		if unit.is_boss():
			button.text = unit.get_display_name().replace("-", "\n")
		if unit.initiative_roll == 0:
			button.tooltip_text = tr("%s: 엄마 거미 바로 앞 순서\n생성한 라운드에는 행동하지 않습니다.") % unit.get_display_name()
		else:
			button.tooltip_text = tr("%s: d20 %d + 민첩 %d = %d") % [
				unit.get_display_name(), unit.initiative_roll, unit.get_dexterity(), unit.get_initiative()]
		var in_group: bool = unit in turns.get_current_group()
		(button.get_node("PendingTurn") as Control).visible = (
			in_group and not turns.is_turn_started(unit) and not turns.is_turn_finished(unit))
		button.disabled = false
		var color: Color = CombatUnit.ALLY_COLOR if unit.is_ally else CombatUnit.ENEMY_COLOR
		if turns.is_turn_finished(unit):
			color = Color("777777")
		var border: Color = Color.WHITE if in_group else Color("61717e")
		if unit == current:
			border = Color("f4cf69")
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
		states.append(tr("기절"))
	var periodic: String = unit.get_periodic_status_text()
	if not periodic.is_empty():
		states.append(periodic)
	if unit.overloaded:
		states.append(tr("과부하"))
	if unit.is_boss():
		states.append(tr("기절 면역"))
	if unit.pull_cooldown > 0:
		states.append(tr("만능팔 대기"))
	if unit.has_mark:
		states.append(tr("◎ 표식"))
	if unit.disengaged:
		states.append(tr("기회 공격 면제"))
	resource_label.text = tr("HP %d / %d   AC %d\n힘 %+d · 민첩 %+d · 건강 %+d · 정신 %+d\n명중 %+d · 사거리 %d칸\n상태: %s") % [
		unit.hit_points, unit.get_max_hit_points(), unit.get_armor_class(),
		unit.get_attribute(CombatUnit.Attribute.STRENGTH), unit.get_dexterity(),
		unit.get_attribute(CombatUnit.Attribute.CONSTITUTION), unit.get_attribute(CombatUnit.Attribute.MENTAL),
		unit.get_attack_bonus(), unit.get_attack_range(),
		", ".join(states) if not states.is_empty() else tr("없음")]


func show_attack_preview(target: CombatUnit, preview: CombatChecks.AttackPreview) -> void:
	show_unit(target)
	var mode_text: String = tr("일반")
	if preview.mode == CombatChecks.RollMode.ADVANTAGE:
		mode_text = tr("유리")
	elif preview.mode == CombatChecks.RollMode.DISADVANTAGE:
		mode_text = tr("불리")
	elif preview.reasons.size() >= 2:
		mode_text = tr("유리/불리 상쇄")
	preview_label.text = tr("명중률 %.1f%% · %s") % [preview.chance * 100.0, mode_text]
	if not preview.valid_target:
		preview_label.text += "\n" + tr("공격할 수 없는 대상")
	elif not preview.blocked_reason.is_empty():
		preview_label.text += "\n" + preview.blocked_reason
	elif not preview.in_range:
		preview_label.text += "\n" + tr("사거리 밖")
	elif not preview.reasons.is_empty():
		preview_label.text += "\n" + ", ".join(preview.reasons)


func prepare_order_rotation(units: Array[CombatUnit]) -> void:
	for unit: CombatUnit in units:
		if unit in _portraits and unit not in _order_moves:
			_order_moves[unit] = _portraits[unit].global_position


func _build_portraits(turns: CombatTurns) -> void:
	_order_revision += 1
	if _order_tween != null:
		_order_tween.kill()
	for child: Node in order_bar.get_children():
		child.free()
	_portraits.clear()
	_shown_order = turns.ordered_units.duplicate()
	for group: Array in turns.get_turn_groups():
		var panel: PanelContainer = PanelContainer.new()
		# 묶음 배경만 낮춰 결과·정비 화면의 기존 표시 순서를 유지한다.
		panel.z_index = -1
		# 이동 중 초상을 덮는 다른 묶음의 빈 배경은 클릭을 받지 않는다.
		panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
		panel.add_theme_stylebox_override("panel", _panel_style())
		var box: HBoxContainer = HBoxContainer.new()
		box.mouse_filter = Control.MOUSE_FILTER_IGNORE
		box.add_theme_constant_override("separation", 3)
		panel.add_child(box)
		order_bar.add_child(panel)
		for unit: CombatUnit in group:
			var button: Button = HoverButton.new()
			# 이동 중에도 초상이 다른 묶음의 배경 위에 보이게 한다.
			button.z_index = 1
			button.custom_minimum_size = Vector2(40, 43)
			button.icon = load("res://scenes/combat/art/units/%s/idle/%s/000.png" % [
				unit.get_art_id(), "right" if unit.is_ally else "left"]) as Texture2D
			button.material = preload("res://scenes/combat/art/pixel_art.tres")
			button.add_theme_constant_override("icon_max_width", 32)
			button.add_theme_font_size_override("font_size", 10)
			button.add_theme_color_override("font_disabled_color", Color("b5bdc4"))
			button.pressed.connect(func() -> void: unit_selected.emit(unit))
			box.add_child(button)
			var pending: Label = Label.new()
			pending.name = "PendingTurn"
			pending.text = "⌛"
			pending.mouse_filter = Control.MOUSE_FILTER_IGNORE
			pending.add_theme_font_size_override("font_size", 12)
			button.add_child(pending)
			pending.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
			pending.offset_left = -15
			pending.offset_top = -16
			pending.offset_right = -1
			pending.offset_bottom = -1
			_connect_tooltip(button)
			_portraits[unit] = button
	if not _order_moves.is_empty():
		var positions: Dictionary[CombatUnit, Vector2] = _order_moves.duplicate()
		_animate_order_rotation(positions, _order_revision)


func _animate_order_rotation(positions: Dictionary[CombatUnit, Vector2], revision: int) -> void:
	await get_tree().process_frame
	if not is_inside_tree() or revision != _order_revision:
		return
	_order_moves.clear()
	_order_tween = create_tween().set_parallel(true)
	for unit: CombatUnit in positions:
		if unit not in _portraits:
			continue
		var button: Button = _portraits[unit]
		var destination: Vector2 = button.position
		button.position += positions[unit] - button.global_position
		_order_tween.tween_property(button, "position", destination, 0.25).set_trans(
			Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


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
