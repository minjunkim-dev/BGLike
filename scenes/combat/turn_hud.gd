class_name CombatTurnHud
extends Control
## 전투 화면. 비용 기호와 막당 횟수를 서로 다른 위치에 표시한다.

signal unit_selected(unit: CombatUnit)
signal end_turn_requested
signal action_selected(action: String)
signal reaction_selected(use_reaction: bool)
signal restart_requested

# Space는 적 턴 가속 키다. 반응 확인 창의 포커스된 버튼을 누르지 않는다.
class SpaceBlocker extends Node:
	func _input(event: InputEvent) -> void:
		if event is InputEventKey and event.keycode == KEY_SPACE:
			get_viewport().set_input_as_handled()

## 확인 창 모양은 프로젝트 공용 테마에서 가져온다(#262).
const UI_THEME: Theme = preload("res://scenes/ui_theme.tres")
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
# 스킬 컨테이너 맨 왼쪽의 패시브 칸(#457). 켜짐·적용 중에만 강조한다.
var _passives: Dictionary[String, Button] = {}
var _passive_dots: Dictionary[String, Label] = {}
var _titles: Array[Label] = []
var _log_lines: Array[String] = []
# 기본 툴팁 창 대신 같은 HUD의 최상단에 설명을 그린다.
var _tooltip: HoverTooltip = HoverTooltip.new()
var reaction_dialog: ConfirmationDialog = ConfirmationDialog.new()
## 유닛 패널의 AC와 팔랑크스 상태를 위치로 계산한다. 없으면 유닛 AC만 보인다.
var grid: CombatGrid

@onready var round_label: Label = $Round
@onready var progress_label: Label = $Progress
@onready var order_bar: HBoxContainer = $OrderScroll/OrderBar
@onready var unit_label: Label = $UnitDetails/UnitPanel/Info/CurrentUnit
@onready var actor_label: Label = $UnitDetails/UnitPanel/Info/Actor
@onready var resource_label: RichTextLabel = $UnitDetails/UnitPanel/Info/Resources
@onready var health_bar: ProgressBar = $UnitDetails/UnitPanel/Info/Health
@onready var end_button: Button = $EndTurn
@onready var preview_label: Label = $UnitDetails/AttackPreview
@onready var action_bar: VBoxContainer = $Skills/Groups
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
	# 스킬 설명은 전투 로그와 스킬 패널 위에 띄워 판정 기록을 가리지 않는다.
	_tooltip.top_of = func(target: Control) -> float:
		return minf(($CombatLog as Control).get_global_rect().position.y, ($Skills as Control).get_global_rect().position.y) \
			if $Skills.is_ancestor_of(target) else target.get_global_rect().position.y
	_tooltip.hidden_when = func() -> bool: return reaction_dialog.visible or $Result.visible
	_tooltip.colorize_numbers = true
	add_child(_tooltip)
	end_button.pressed.connect(func() -> void: end_turn_requested.emit())
	restart_button.pressed.connect(func() -> void: restart_requested.emit())
	_build_passives()
	for index: int in range(CombatActionRules.GROUPS.size()):
		var panel: PanelContainer = PanelContainer.new()
		panel.add_theme_stylebox_override("panel", _panel_style())
		action_bar.add_child(panel)
		_containers.append(panel)
		# 컨테이너마다 한 줄이다. 버튼이 줄을 넘치면 같은 컨테이너 안에서 다음 줄로 넘긴다(#438).
		var row: HBoxContainer = HBoxContainer.new()
		row.add_theme_constant_override("separation", 4)
		panel.add_child(row)
		var title: Label = Label.new()
		title.mouse_filter = Control.MOUSE_FILTER_IGNORE
		title.add_theme_font_size_override("font_size", 10)
		title.add_theme_color_override("font_color", RESOURCE_COLORS[index])
		# 제목 폭을 맞춰 세 줄의 첫 버튼을 같은 세로선에 둔다.
		title.custom_minimum_size.x = 58
		title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		row.add_child(title)
		_titles.append(title)
		var buttons: HFlowContainer = HFlowContainer.new()
		buttons.add_theme_constant_override("h_separation", 3)
		buttons.add_theme_constant_override("v_separation", 3)
		buttons.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(buttons)
		for action: String in CombatActionRules.GROUPS[index]:
			var button: Button = HoverTooltip.HoverButton.new()
			# 아이콘 오른쪽에 비용 마크 자리를 남긴다. 높이는 그림을 줄이기 전(#362)의 입력 영역이다.
			button.custom_minimum_size = Vector2(52, 34)
			button.icon = CombatActionRules.icon_of(action)
			button.material = preload("res://scenes/combat/art/pixel_art.tres")
			button.add_theme_constant_override("icon_max_width", CombatActionRules.ICON_SIZE)
			# 곱셈 색은 채도를 빼지 못해 반투명으로 어둡게 눌러 회색 배경에 묻는다.
			button.add_theme_color_override("icon_disabled_color", Color("8a939b", 0.55))
			button.accessibility_name = CombatActionRules.NAMES[action]
			# 반응은 표시용이다. 자기 턴의 입력에는 연결하지 않는다.
			if index != 2:
				button.pressed.connect(func() -> void: action_selected.emit(action))
			buttons.add_child(button)
			_tooltip.attach(button)
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
	reaction_dialog.theme = UI_THEME
	reaction_dialog.add_child(SpaceBlocker.new())
	reaction_dialog.title = tr("반응")
	reaction_dialog.dialog_autowrap = true
	reaction_dialog.dialog_hide_on_ok = false
	reaction_dialog.confirmed.connect(_finish_reaction.bind(true))
	reaction_dialog.canceled.connect(_finish_reaction.bind(false))


## 컨테이너 묶음(Groups)을 가로 줄로 감싸고 그 왼쪽 끝에 패시브 칸을 둔다. 버튼에는 비용 기호와 횟수 배지가 없다.
func _build_passives() -> void:
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 3)
	$Skills.add_child(row)
	var column: VBoxContainer = VBoxContainer.new()
	column.add_theme_constant_override("separation", 3)
	row.add_child(column)
	action_bar.reparent(row)
	action_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for passive: String in CombatActionRules.PASSIVES:
		var button: Button = HoverTooltip.HoverButton.new()
		button.custom_minimum_size = Vector2(22, 34)
		# 아이콘이 생기기 전에는 이름 첫 글자를 보인다.
		button.text = CombatActionRules.PASSIVE_NAMES[passive].left(1)
		button.add_theme_font_size_override("font_size", 12)
		button.focus_mode = Control.FOCUS_NONE
		button.accessibility_name = CombatActionRules.PASSIVE_NAMES[passive]
		button.tooltip_text = CombatActionRules.PASSIVE_NAMES[passive] + "\n" + CombatActionRules.PASSIVE_EFFECTS[passive]
		column.add_child(button)
		_tooltip.attach(button)
		_passives[passive] = button
		# 켜짐 표시는 버튼 아래쪽 작은 점이다. 오른쪽 위는 횟수 배지 자리라 비운다.
		var dot: Label = Label.new()
		dot.text = "●"
		dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		dot.add_theme_font_size_override("font_size", 6)
		dot.add_theme_color_override("font_color", Color("f4ead1"))
		button.add_child(dot)
		dot.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
		dot.position.y -= 2
		_passive_dots[passive] = dot


## 패시브 칸을 갱신한다. 팔랑크스는 아군이 인접해 실제로 적용되는 동안만 강조한다. 괴력의 사내는 상태가 없어 평범한 모습이다.
func _refresh_passives(shown: CombatUnit) -> void:
	for passive: String in CombatActionRules.PASSIVES:
		var button: Button = _passives[passive]
		button.visible = shown != null and CombatActionRules.belongs_to(shown, passive)
		if not button.visible:
			continue
		var on: bool = passive == "phalanx" and grid != null and grid.phalanx_bonus(shown) > 0
		var style: StyleBoxFlat = _button_style(Color("3b4f63") if on else Color("293541"), Color("f4ead1") if on else Color("61717e"))
		if on:
			style.set_border_width_all(2)
		for state: String in ["normal", "hover", "pressed", "disabled"]:
			button.add_theme_stylebox_override(state, style)
		# 꺼짐·조건 미충족은 어둡게 하지 않는다. 회색은 사용 불가의 뜻이라 글자색은 켜짐과 같다.
		button.add_theme_color_override("font_color", Color.WHITE)
		_passive_dots[passive].visible = on


func refresh_actions(actions: CombatActions, selected: String, last_ally: CombatUnit) -> void:
	var actor: CombatUnit = actions.turns.current_unit
	var shown: CombatUnit = actor if actor != null and actor.is_ally else last_ally
	var ally_turn: bool = actor != null and actor.is_ally
	var locked: bool = actions.busy or actions.is_over()
	var symbols: Array[String] = ["●", "▲", "◆"]
	var empty_symbols: Array[String] = ["○", "△", "◇"]
	var names: Array[String] = [tr("행동"), tr("보조 행동"), tr("반응")]
	_action_slots.clear()
	_refresh_passives(shown)
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
			# 복합 비용은 함께 소비하는 턴 자원 기호를 잇는다. 이동력은 기호가 없다.
			_costs[action].text = symbols[index] + ("▲" if CombatActionRules.EXTRA_COSTS.get(action) == "bonus_action" else "")
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
	var details: String = CombatActionRules.details(actor, action, actions.units)
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
	reaction_dialog.get_ok_button().text = tr("반격") if kind == "counter" else tr("공격")
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
	restart_button.text = tr("타이틀로") if complete else tr("보상 확인") if victory else tr("이 막 다시 시작")
	$Result.show()
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
			button.tooltip_text = tr("%s: %s = %d") % [
				unit.get_display_name(), CombatUnit.ability_text(unit, CombatUnit.Ability.AGILITY), unit.get_initiative()]
		# 고철로봇은 켜지기 전부터 과부하 조건·효과와 물 칸 규칙을 읽는다(#503).
		var overload: String = CombatActionRules.overload_text(unit)
		if not overload.is_empty():
			button.tooltip_text += "\n" + overload
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


## 상태 줄은 상태와 상태 사이에서만 줄을 바꾼다. 자동 줄바꿈은 한글 단어 중간(`기절 면/역`)도 끊는다(#503).
func _join_states(states: Array[String]) -> String:
	if states.is_empty():
		return tr("없음")
	var font: Font = resource_label.get_theme_font("normal_font")
	var font_size: int = resource_label.get_theme_font_size("normal_font_size")
	var width: float = resource_label.size.x
	var joined: String = states[0]
	var line: String = "상태: " + states[0]
	for state: String in states.slice(1):
		var candidate: String = line + ", " + state
		if width > 0.0 and font.get_string_size(candidate + ",", HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x > width:
			joined += ",\n" + state
			line = state
		else:
			joined += ", " + state
			line = candidate
	return joined


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
	# 켜지기 전에는 과부하 조건을 보인다(#503).
	var overload: String = CombatActionRules.overload_status(unit)
	if not overload.is_empty():
		states.append(overload)
	if unit.is_boss():
		states.append(tr("기절 면역"))
	if unit.pull_cooldown > 0:
		states.append(tr("만능팔 대기"))
	if unit.has_mark:
		states.append(tr("◎ 표식"))
	if unit.disengaged:
		states.append(tr("기회 공격 면제"))
	if unit.shield_points > 0:
		states.append(tr("방어막 %d (%d턴)") % [unit.shield_points, unit.shield_turns])
	if unit.battle_cry_turns > 0:
		states.append(tr("전투의 함성 명중 +%d (%d턴)") % [unit.battle_cry_bonus, unit.battle_cry_turns])
	var phalanx: int = grid.phalanx_bonus(unit) if grid != null else 0
	if phalanx > 0:
		states.append(tr("팔랑크스 AC +%d") % phalanx)
	resource_label.text = CombatActionRules.colorize(tr("HP %d / %d   AC %d\n%s · %s · %s\n%s · %s · %s\n공격 %+d · 사거리 %d칸\n상태: %s") % [
		unit.hit_points, unit.get_max_hit_points(), unit.get_armor_class() + phalanx,
		CombatUnit.ability_text(unit, CombatUnit.Ability.STRENGTH), CombatUnit.ability_text(unit, CombatUnit.Ability.AGILITY),
		CombatUnit.ability_text(unit, CombatUnit.Ability.FINESSE), CombatUnit.ability_text(unit, CombatUnit.Ability.INTELLIGENCE),
		CombatUnit.ability_text(unit, CombatUnit.Ability.WILL), CombatUnit.ability_text(unit, CombatUnit.Ability.HEALTH),
		unit.get_attack_bonus(), unit.get_attack_range(),
		_join_states(states)])


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
			var button: Button = HoverTooltip.HoverButton.new()
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
			_tooltip.attach(button)
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
