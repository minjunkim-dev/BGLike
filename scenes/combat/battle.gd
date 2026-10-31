extends Node2D
## 전투 화면과 3막 진행. 적 묶음은 이니셔티브 순서대로 실행한다.

const MOVE_STEP_TIME: float = 0.09
const ARROW_FLIGHT_TIME: float = 0.16
const ENEMY_PAUSE_TIME: float = 0.35
## 적 턴에 Space를 누르고 있는 동안의 시간 배율. 규칙이 아니라 표시 속도다.
const ENEMY_FAST_SPEED: float = 4.0

## 자동 저장을 마친 뒤. 검사가 저장한 순간의 상태를 비교한다.
signal autosaved

@export var stages: Array[CombatStage] = []

var progress: CombatActProgress
var map_size: Vector2i
var party: Array[CombatUnit] = []

var units: Array[CombatUnit] = []
var turns: CombatTurns = CombatTurns.new()
var actions: CombatActions = CombatActions.new()
var enemy_ai: CombatEnemyAi = CombatEnemyAi.new()
var _enemy_turn_running: bool = false
var _enemy_shown: bool = false
var _enemy_acted: bool = false
var selection: CombatSelection = CombatSelection.new()
var movement_cells: Array[Vector2i] = []
var _last_ally: CombatUnit
var loot: CombatLoot = CombatLoot.new()
var preparation: CombatPreparation
var _save_pending: bool = false
## 진행 중인 적 턴이 시작한 순간의 상태와 그 뒤 끝낸 적 행동 수. 적 턴 중간 저장에 쓴다.
var _turn_start: Dictionary = {}
var _turn_actions: int = 0
## 이어하기가 연출 없이 다시 실행할 적 행동 수.
var _replay_actions: int = 0
## #345: 지도를 보고 명시적으로 전투를 시작한다. 적 선공도 이때까지 기다린다.
## #395: 지도 준비에서는 정비를 열지 않는다. 정비는 승리 뒤 보상 확인 다음에만 연다.
var waiting_for_start: bool = true
var staging: HBoxContainer
var start_button: Button

@onready var map: CombatMap = $Map
@onready var camera: CombatCamera = $Camera
@onready var hud: CombatTurnHud = $UI/TurnHud
@onready var pause_menu: PauseMenu = $Pause/PauseMenu


func _ready() -> void:
	assert(stages.size() == 9, "전투 진행에는 스테이지 데이터9개가 필요합니다.")
	progress = CombatActProgress.new(stages.size())
	# 파티 노드를 유지해 같은 막의 HP와 스킬 횟수를 이어 간다.
	for child: Node in $Units.get_children():
		party.append(child as CombatUnit)
	preparation = CombatPreparation.new()
	preparation.name = "Preparation"
	$UI.add_child(preparation)
	preparation.finished.connect(_finish_preparation)
	preparation.changed.connect(func() -> void: _save_pending = true)
	staging = HBoxContainer.new()
	staging.name = "Staging"
	staging.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	staging.offset_left = 8
	staging.offset_right = -8
	staging.offset_top = -58
	staging.offset_bottom = -8
	staging.add_theme_constant_override("separation", 8)
	hud.add_child(staging)
	var hint: Label = Label.new()
	hint.text = tr("전투 준비 · 지형과 적을 확인하고 전투를 시작합니다.")
	hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hint.add_theme_font_size_override("font_size", 12)
	staging.add_child(hint)
	start_button = Button.new()
	start_button.name = "StartBattle"
	start_button.text = tr("전투 시작")
	start_button.custom_minimum_size.x = 96
	start_button.add_theme_font_size_override("font_size", 14)
	start_button.pressed.connect(start_battle)
	staging.add_child(start_button)

	hud.unit_selected.connect(_on_unit_selected)
	hud.end_turn_requested.connect(_end_turn)
	hud.action_selected.connect(_on_action_selected)
	hud.reaction_selected.connect(actions.resolve_reaction)
	hud.restart_requested.connect(_restart)
	pause_menu.give_up_confirmed.connect(_give_up)
	actions.changed.connect(_on_actions_changed)
	actions.logged.connect(hud.add_log)
	actions.feedback.connect(func(unit: CombatUnit, text: String) -> void:
		if not _replaying():
			unit.show_feedback(text, hud.feedback_obstacles()))
	actions.healed.connect(func(unit: CombatUnit, amount: int) -> void:
		if not _replaying():
			unit.show_feedback(str(amount), hud.feedback_obstacles(), CombatUnit.HEAL_COLOR))
	actions.hit_landed.connect(func() -> void:
		if not _replaying():
			$HitSound.play())
	actions.reaction_requested.connect(hud.show_reaction)
	actions.movement_animation = _animate_movement
	actions.jump_animation = _animate_jump
	actions.attack_animation = _animate_attack
	turns.changed.connect(_on_turn_changed)
	turns.order_rotated.connect(hud.prepare_order_rotation)
	_start_stage(true)


func _exit_tree() -> void:
	actions.movement_animation = Callable()
	actions.jump_animation = Callable()
	actions.attack_animation = Callable()
	Engine.time_scale = 1.0


func _start_stage(restore_act: bool) -> void:
	waiting_for_start = true
	_replay_actions = 0
	actions.replay_answers.clear()
	for unit: CombatUnit in party:
		unit.begin_stage(restore_act)
	var stage: CombatStage = _build_stage()
	for index: int in range(party.size()):
		party[index].cell = stage.ally_cells[index]
		party[index].facing_left = false
	var dice: CombatDice = CombatDice.new()
	dice.randomize()
	var living: Array[CombatUnit] = []
	for unit: CombatUnit in units:
		if unit.hit_points > 0:
			living.append(unit)
	_last_ally = living[0]
	turns.start(living, dice)
	for cell: Vector2i in stage.crate_cells:
		var prop: CombatGrid.Prop = actions.create_prop(cell, "crate")
		assert(prop != null, "나무 상자 시작 칸이 유효하지 않습니다: %s %s" % [stage.resource_path, cell])
	for cell: Vector2i in stage.rock_cells:
		var prop: CombatGrid.Prop = actions.create_prop(cell, "rock")
		assert(prop != null, "바위 시작 칸이 유효하지 않습니다: %s %s" % [stage.resource_path, cell])
	_update_turn_ui()
	start_button.grab_focus()


func start_battle() -> void:
	if not waiting_for_start:
		return
	waiting_for_start = false
	_save_pending = true
	get_viewport().gui_release_focus()
	_update_turn_ui()


## 지금 스테이지의 지도와 처음 배치의 적을 새로 만든다. 아군 상태와 턴 순서는 건드리지 않는다.
func _build_stage() -> CombatStage:
	progress.begin_stage()
	var stage: CombatStage = stages[progress.stage_index]
	assert(stage != null, "스테이지 데이터가 비어 있습니다: %d" % (progress.stage_index + 1))
	assert(stage.ally_cells.size() == party.size(),
		"아군 시작 칸 수가 파티 크기와 다릅니다: " + stage.resource_path)
	for unit: CombatUnit in units:
		if not unit.is_ally:
			unit.free()
	for child: Node in $Units.get_children():
		if child is Label:
			child.free()
	units = party.duplicate()
	map_size = stage.map_size
	actions.grid.map_size = map_size
	actions.grid.heights = stage.heights.duplicate()
	actions.grid.pits = stage.pits.duplicate()
	actions.grid.blocked_cells = stage.get_blocked_cells()
	actions.grid.water_cells = stage.water_cells.duplicate()
	map.build_grid(actions.grid, stage.tile_set, stage)
	var enemies: Node = stage.enemies.instantiate()
	$Units.add_child(enemies)
	for child: Node in enemies.get_children():
		var unit: CombatUnit = child as CombatUnit
		unit.reparent($Units, false)
		units.append(unit)
	enemies.free()
	camera.frame(map, map_size)
	selection.reset()
	hud.begin_stage(progress.act_number(), progress.stage_in_act())
	actions.initialize(units, turns)
	return stage


## 이어하기에 필요한 전투 상태 전체. Object 없이 GameSave에 그대로 쓸 수 있는 값이다 (docs/adr/0003).
func combat_state() -> Dictionary:
	var state: Dictionary = progress.save_state()
	state["waiting_for_start"] = waiting_for_start
	state.merge(actions.save_state())
	state["bag"] = loot.bag
	state["units"] = units.map(func(unit: CombatUnit) -> Dictionary: return unit.save_state(units))
	state["turns"] = turns.save_state(units)
	state["last_ally"] = units.find(_last_ally)
	return state.duplicate(true)


## combat_state()로 저장한 전투로 되돌린다. 저장이 맞지 않으면 아무것도 바꾸지 않고 false다.
## 값은 GameSave.read()의 sections.combat을 그대로 받는다.
## 적 턴 중간의 저장이면 그 적 턴이 시작한 상태로 되돌리고, 다음 프레임에 끝낸 적 행동까지 연출 없이 다시 실행한다.
func restore_combat(state: Variant) -> bool:
	if actions.busy or _enemy_turn_running or preparation.visible or not (state is Dictionary and _is_valid_state(state)):
		push_warning("전투 저장을 읽을 수 없음")
		return false
	progress.stage_index = state.stage
	_build_stage()
	progress.load_state(state)
	waiting_for_start = state.get("waiting_for_start", false)
	loot.bag.assign(state.bag)
	for saved: Dictionary in state.units.slice(units.size()):
		var child: CombatUnit = (preload("res://scenes/combat/unit.tscn") as PackedScene).instantiate() as CombatUnit
		child.kind = saved.kind
		child.is_ally = false
		$Units.add_child(child)
		units.append(child)
	for index: int in range(units.size()):
		units[index].load_state(state.units[index], units)
	actions.load_state(state)
	turns.load_state(state.turns, units)
	_last_ally = units[state.last_ally]
	var replay: Dictionary = state.get("replay", {})
	_replay_actions = replay.get("actions", 0)
	actions.replay_answers.assign(replay.get("reactions", []))
	selection.reset()
	_update_turn_ui()
	# 방금 읽은 저장과 같은 상태다. 적 턴 중간 저장을 시작 상태로 덮지 않는다.
	_save_pending = false
	return true


## 저장 파일의 값은 신뢰하지 않는다. 스테이지·유닛 구성·번호·칸·아이템을 모두 확인한다.
func _is_valid_state(state: Dictionary) -> bool:
	if not state.get("waiting_for_start", false) is bool:
		return false
	if not (state.get("stage") is int and state.stage >= 0 and state.stage < stages.size()
			and state.get("rewarded") is bool and state.get("units") is Array and state.get("last_ally") is int
			and _valid_items(state.get("rewards")) and _valid_items(state.get("bag"))
			and state.rewards.size() <= CombatUnit.SAVED_INT_LIMIT and state.bag.size() <= int(loot.data["bag_limit"])):
		return false
	if state.get("waiting_for_start", false) and state.rewarded:
		return false
	var stage: CombatStage = stages[state.stage]
	var identities: Array = party.map(func(unit: CombatUnit) -> Array: return [unit.kind, true])
	var enemies: Node = stage.enemies.instantiate()
	for child: Node in enemies.get_children():
		identities.append([(child as CombatUnit).kind, false])
	enemies.free()
	var saved_units: Array = state.units
	var count: int = saved_units.size()
	# 늘어나는 유닛은 새끼 거미뿐이고 한 칸에 하나다.
	if count < identities.size() or count > identities.size() + stage.map_size.x * stage.map_size.y:
		return false
	for index: int in range(count):
		var saved: Variant = saved_units[index]
		var identity: Array = identities[index] if index < identities.size() else [CombatUnit.Kind.SPIDERLING, false]
		if (not party[0].is_valid_state(saved, count, stage.map_size) or [saved.kind, saved.ally] != identity
				or not (saved.weapon.is_empty() or loot.is_valid_item(saved.weapon) and saved.weapon.kind == "weapon")
				or not (saved.armor.is_empty() or loot.is_valid_item(saved.armor) and saved.armor.kind == "armor")):
			return false
		var agility_sides: int = (CombatUnit.ALLY_ABILITY_SIDES[saved.kind][CombatUnit.Ability.AGILITY]
			if saved.ally else CombatEnemyDefinitions.for_kind(saved.kind)["abilities"][CombatUnit.Ability.AGILITY])
		# 생성한 새끼는 굴리지 않고 엄마 앞에 삽입되므로 원본 값 0을 보존한다.
		if saved.initiative_roll < (1 if index < identities.size() else 0) or saved.initiative_roll > agility_sides:
			return false
	if not (state.last_ally >= 0 and state.last_ally < count and saved_units[state.last_ally].ally
			and CombatTurns.is_valid_state(state.get("turns"), count)
			and CombatActions.is_valid_state(state, count, stage.map_size)):
		return false
	# 턴 순서는 살아 있는 유닛 전부다. 쓰러진 유닛이나 빠진 유닛이 있으면 턴이 끝없이 넘어가거나 멈춘다.
	var order: Array = state.turns.order
	var living: Array = range(count).filter(func(index: int) -> bool: return saved_units[index].hit_points > 0)
	if (order.size() != living.size() or not living.all(func(index: int) -> bool: return index in order)
			or not order.is_empty() and state.turns.current < 0):
		return false
	# 기절은 시전자의 턴이 와야 풀린다. 시전자가 살아서 순서에 있어야 턴이 끝없이 넘어가지 않는다.
	for saved: Dictionary in saved_units:
		if saved.stunned and saved.hit_points > 0 and (saved_units[saved.stun_source].hit_points <= 0
				or saved.stun_source not in state.turns.order):
			return false
	var replay: Variant = state.get("replay", {})
	if not (replay is Dictionary and replay.get("actions", 0) is int
			and replay.get("actions", 0) <= CombatUnit.SAVED_INT_LIMIT and replay.get("reactions", []) is Array
			and replay.get("reactions", []).size() <= CombatUnit.SAVED_INT_LIMIT
			and replay.get("reactions", []).all(func(answer: Variant) -> bool: return answer is bool)
			and (replay.get("actions", 0) > 0 or replay.get("reactions", []).is_empty())):
		return false
	if state.get("waiting_for_start", false) and (state.turns.round != 1 or replay.get("actions", 0) != 0):
		return false
	if replay.get("actions", 0) == 0:
		return true
	# 적 턴 중간 저장은 살아 있는 적의 차례이고 양편이 남아 있을 때만 있다.
	var current: int = state.turns.current
	return (replay.actions > 0 and current >= 0 and not saved_units[current].ally
		and saved_units[current].hit_points > 0
		and saved_units.any(func(unit: Dictionary) -> bool: return unit.ally and unit.hit_points > 0))


## 이어하기. GameSave.read()의 sections를 그대로 받는다. 정비·보상 확인 화면 중의 저장이면 그 화면과 단계를 다시 연다.
## 저장이 맞지 않으면 아무것도 바꾸지 않고 false다.
func restore_save(sections: Variant) -> bool:
	var combat: Variant = sections.get("combat") if sections is Dictionary else null
	var screen: Variant = sections.get("preparation", {}) if sections is Dictionary else null
	if not (screen is Dictionary and combat is Dictionary and _is_valid_state(combat)):
		push_warning("저장을 읽을 수 없음")
		return false
	# #345의 지도 준비 정비 화면 저장(`before_battle`)은 #395 뒤에 만들지 않는다. 그 화면의 변경은 이미 combat에 있어
	# 같은 지도 준비로 이어한다.
	var before_battle: bool = screen.get("before_battle") is bool and screen.before_battle
	if not screen.is_empty():
		var valid: bool = screen.get("maintaining") is bool
		if before_battle:
			valid = valid and screen.size() == 2 and screen.maintaining and combat.get("waiting_for_start", false)
		else:
			valid = valid and screen.keys() == ["maintaining"] and combat.rewarded
			valid = valid and combat.units.all(func(unit: Dictionary) -> bool: return unit.ally or unit.hit_points <= 0)
		if not valid:
			push_warning("저장한 정비 단계가 전투 상태와 맞지 않음")
			return false
	if not restore_combat(combat):
		return false
	if not screen.is_empty() and not before_battle:
		preparation.open_rewards(loot, party, progress.rewards, progress.is_final_stage(),
			progress.is_last_in_act(), screen.maintaining)
		hud.hide_result()
		# 방금 읽은 저장과 같은 상태다.
		_save_pending = false
	return true


func _valid_items(items: Variant) -> bool:
	return items is Array and (items as Array).all(loot.is_valid_item)


func _restart() -> void:
	if not actions.is_over() or actions.busy or _enemy_turn_running:
		return
	if actions.is_victory():
		# 졸업 화면의 버튼은 `타이틀로` 하나다 (#209 9번).
		if progress.graduated:
			get_tree().change_scene_to_file(PauseMenu.TITLE_SCENE)
			return
		if preparation.visible:
			return
		preparation.open_rewards(loot, party, progress.rewards, progress.is_final_stage(),
			progress.is_last_in_act())
		hud.hide_result()
		return
	progress.restart_act()
	_start_stage(progress.starts_act())


## 일시정지 메뉴의 `전투 포기`(#286). 전멸과 같은 패배라 결과 화면에서 이 막을 처음부터 다시 한다.
## 확정한 순간을 행동 하나로 바로 저장한다. 적 턴·연출 중이어도 강제 종료로 포기를 되돌릴 수 없다(#220 3번).
func _give_up() -> void:
	actions.give_up()
	if GameSave.autosave:
		# 진행 중이던 적 행동이 끝나며 적 턴 시작 상태로 덮어쓰지 않게 한다.
		_turn_start = {}
		_autosave(combat_state())


func _finish_preparation() -> void:
	if not actions.is_over() or actions.busy or _enemy_turn_running or not actions.is_victory():
		return
	progress.advance()
	if progress.graduated:
		# 졸업 화면이 뜨는 순간 저장을 지운다. 이어하기로 마지막 정비 화면에 돌아가지 않는다 (#209 9번).
		# 스위치가 꺼진 검사·장면 직접 실행은 사용자의 저장을 건드리지 않는다.
		if GameSave.autosave:
			GameSave.delete()
		_update_turn_ui()
		return
	_start_stage(progress.starts_act())


func _process(_delta: float) -> void:
	if _save_pending and GameSave.autosave and _can_save():
		_autosave(combat_state())
	# 반응 확인 창은 가속과 관계없이 보통 속도로 선택을 기다린다.
	Engine.time_scale = ENEMY_FAST_SPEED if (_enemy_turn_running and not hud.reaction_dialog.visible
		and Input.is_key_pressed(KEY_SPACE)) else 1.0
	var actor: CombatUnit = turns.current_unit
	if (not waiting_for_start and actor != null and not actor.is_ally and not actions.busy
		and not actions.is_over() and not _enemy_turn_running):
		_play_enemy_turn(actor)


func _play_enemy_turn(actor: CombatUnit) -> void:
	_enemy_turn_running = true
	_enemy_shown = false
	_enemy_acted = false
	_turn_actions = 0
	actions.reaction_answers.clear()
	if GameSave.autosave:
		_turn_start = combat_state()
	await enemy_ai.play_turn(actor, actions, _pause_enemy_action)
	_replay_actions = 0
	actions.replay_answers.clear()
	_turn_start = {}
	if not actions.is_over() and turns.current_unit == actor:
		turns.end_turn()
	_enemy_turn_running = false
	_update_turn_ui()


## 적 행동 하나가 끝날 때마다 AI가 부른다. 저장한 뒤, 이동·공격하지 않은 적 행동 뒤에는 기다리지 않는다.
func _pause_enemy_action() -> void:
	_turn_actions += 1
	if _turn_actions < _replay_actions:
		return
	_replay_actions = 0
	if GameSave.autosave and not _turn_start.is_empty():
		# AI는 턴 안의 진행을 지역 값으로 들고 있어 중간 상태에서 다시 시작하면 다른 선택을 할 수 있다.
		# 그래서 턴 시작 상태와 끝낸 행동 수, 아군의 반응 답을 저장하고 이어하기가 같은 난수로 다시 실행한다.
		var state: Dictionary = _turn_start.duplicate()
		state["replay"] = {"actions": _turn_actions, "reactions": actions.reaction_answers.duplicate()}
		_autosave(state)
	if actions.is_over() or not _enemy_acted:
		return
	_enemy_acted = false
	# 연출 타이머는 일시정지 메뉴가 열린 동안 멈춘다.
	await get_tree().create_timer(ENEMY_PAUSE_TIME, false).timeout


## 적 턴의 첫 이동·공격 연출 전에 한 번 멈춰 행동할 적을 보여 준다.
func _show_enemy_action() -> void:
	if not _enemy_turn_running:
		return
	_enemy_acted = true
	if not _enemy_shown:
		_enemy_shown = true
		await get_tree().create_timer(ENEMY_PAUSE_TIME, false).timeout


## 행동이 끝나 연출·반응 확인 창을 기다리지 않는 순간. 확정 전 입력(선택·미리보기)은 상태를 바꾸지 않는다.
func _can_save() -> bool:
	return not actions.busy and not _enemy_turn_running and actions.pending_reactor == null and not progress.graduated


## 쓰기에 실패하면 이전 저장이 남고 다음 행동이 끝날 때 다시 쓴다. 매 프레임 다시 쓰지 않는다.
func _autosave(state: Dictionary) -> void:
	_save_pending = false
	var sections: Dictionary = {"combat": state}
	# 선택한 칸과 열린 확인 창은 저장하지 않는다. 이어하기는 같은 화면 단계에서 아무것도 고르지 않은 채 시작한다.
	if preparation.visible:
		sections["preparation"] = {"maintaining": preparation.maintaining}
	if GameSave.write(progress.act_number(), progress.stage_in_act(), sections) == OK:
		autosaved.emit()


## 이어하기가 끝낸 적 행동을 다시 실행하는 중인지. 연출·팝업·소리를 건너뛴다.
func _replaying() -> bool:
	return _turn_actions < _replay_actions


func _on_unit_selected(unit: CombatUnit) -> void:
	if actions.busy or actions.is_over() or unit not in units or unit.hit_points <= 0:
		return
	selection.clear_preview()
	if waiting_for_start:
		hud.show_unit(unit)
		return
	# 조작 가능한 아군만 전환한다. 다른 초상은 정보만 표시한다.
	turns.select_unit(unit)
	selection.inspect(unit)
	_update_turn_ui()


func _end_turn() -> void:
	if (not waiting_for_start and turns.current_unit != null and turns.current_unit.is_ally
		and not actions.busy and not actions.is_over()):
		turns.end_turn()


func _on_action_selected(action: String) -> void:
	var actor: CombatUnit = turns.current_unit
	if waiting_for_start or actor == null or not actor.is_ally or not actions.can_use(actor, action):
		return
	if selection.select_action(action):
		actions.use_self(actor, action)
		selection.finish_execution()
	_update_turn_ui()


func _input(event: InputEvent) -> void:
	# 반응·정비 확인 창이 떠 있으면 그 창이 Esc·Start를 먼저 받는다. Esc는 지금처럼 반응을 넘긴다.
	if event.is_action_pressed("pause"):
		get_viewport().set_input_as_handled()
		if get_viewport().gui_is_dragging():
			get_viewport().gui_cancel_drag()
			return
		# 졸업 화면에는 `타이틀로`만 둔다.
		if progress.graduated:
			return
		# 멈추면 _process가 돌지 않는다. 메뉴에서 바로 타이틀로·종료해도 끝난 행동이 남게 먼저 쓴다.
		if _save_pending and GameSave.autosave and _can_save():
			_autosave(combat_state())
		pause_menu.open(not actions.is_over() and not waiting_for_start)
		return
	if event is InputEventKey and event.keycode == KEY_SPACE and not actions.is_over():
		# Space는 적 턴 가속 키다. 포커스된 버튼(턴 종료 등)을 누르지 않게 소비한다.
		get_viewport().set_input_as_handled()
		return
	# 숫자 키 1~9는 스킬 바의 버튼을 왼쪽부터 고른다. 자판 배열과 관계없이 윗줄 숫자 자리를 쓴다.
	if event is InputEventKey and event.physical_keycode >= KEY_1 and event.physical_keycode <= KEY_9:
		if event.pressed and not event.echo and _ally_input_open():
			get_viewport().set_input_as_handled()
			hud.focus_action_slot(event.physical_keycode - KEY_1, true)
		return
	# 포커스가 없으면 좌우 방향키·D-pad가 스킬 바의 첫 버튼으로 들어간다.
	if ((event.is_action_pressed("ui_left") or event.is_action_pressed("ui_right"))
		and get_viewport().gui_get_focus_owner() == null and _ally_input_open()):
		get_viewport().set_input_as_handled()
		hud.focus_action_slot(0, false)
		return
	if event is not InputEventKey or event.keycode != KEY_TAB or preparation.visible or waiting_for_start:
		return
	# GUI보다 먼저 소비해 전투 중 기본 Tab 포커스 이동을 막는다.
	get_viewport().set_input_as_handled()
	if not event.pressed or event.echo or not _ally_input_open():
		return
	var actor: CombatUnit = turns.current_unit
	var group: Array[CombatUnit] = turns.get_current_group()
	var index: int = group.find(actor)
	var direction: int = -1 if event.shift_pressed else 1
	for step: int in range(1, group.size() + 1):
		var unit: CombatUnit = group[wrapi(index + step * direction, 0, group.size())]
		if turns.select_unit(unit):
			selection.inspect(unit)
			_update_turn_ui()
			return


## 아군 턴의 키보드 조작을 받을 수 있는지. 연출·반응 확인·결과·정비 화면에서는 잠근다.
func _ally_input_open() -> bool:
	var actor: CombatUnit = turns.current_unit
	return (not waiting_for_start and actor != null and actor.is_ally and not actions.busy and not actions.is_over()
		and not hud.reaction_dialog.visible and not hud.get_node("Result").visible and not preparation.visible)


func _unhandled_input(event: InputEvent) -> void:
	if (event is not InputEventMouseButton or not event.pressed
		or event.button_index not in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT]):
		return
	if actions.busy or actions.is_over():
		return
	var world_position: Vector2 = get_canvas_transform().affine_inverse() * event.position
	var cell: Vector2i = map.surface_to_map(map.to_local(world_position))
	if waiting_for_start:
		for unit: CombatUnit in units:
			if unit.visible and unit.hit_points > 0 and unit.contains_body_point(unit.to_local(world_position)):
				hud.show_unit(unit)
				get_viewport().set_input_as_handled()
				break
		return
	var actor: CombatUnit = turns.current_unit
	if actor == null or not actor.is_ally:
		return
	selection.begin_field_input(event.button_index == MOUSE_BUTTON_LEFT)
	# 우클릭은 몸통에 가려진 칸도 격자 위치로 이동 판정한다.
	if event.button_index == MOUSE_BUTTON_RIGHT:
		get_viewport().set_input_as_handled()
		await _select_move_cell(cell)
		return
	var candidates: Array[CombatUnit] = []
	for unit: CombatUnit in units:
		if unit.hit_points > 0 and unit.contains_body_point(unit.to_local(world_position)):
			candidates.append(unit)
	candidates.sort_custom(func(a: CombatUnit, b: CombatUnit) -> bool:
		if a.position.y != b.position.y:
			return a.position.y > b.position.y
		return a.get_index() > b.get_index()
	)
	var prop: CombatGrid.Prop = map.prop_at_point(map.to_local(world_position))
	# 윤곽이 보이는 가린 유닛은 몸통 클릭이 동작할 때만 앞 사물보다 우선한다.
	var unit_first: bool = not candidates.is_empty() and candidates[0].is_occluded and (
		not candidates[0].is_ally or selection.selected_action == "shove")
	if prop != null and not unit_first and (candidates.is_empty()
			or map.map_to_local(prop.cell).y >= candidates[0].position.y):
		get_viewport().set_input_as_handled()
		if selection.select_prop(prop, selection.selected_action == "attack" and actions.can_attack_prop(actor, prop)):
			selection.begin_execution()
			var generation: int = map.revision
			actions.busy = true
			await _animate_attack_at(actor, map.map_to_surface(prop.cell) + Vector2(0, -8))
			if generation != map.revision:
				return
			var origin: Vector2i = prop.cell
			var roll: CombatActions.RockRoll = actions.preview_rock(actor, prop) if prop.kind == "rock" else null
			if not actions.is_over():
				await map.animate_prop(prop, roll, func() -> bool: return not actions.is_over())
			if generation != map.revision:
				return
			actions.busy = false
			if actions.attack_prop(actor, prop):
				map.prop_impact(prop.cell, prop.hit_points == 0)
				if prop.cell != origin:
					map.prop_impact(origin, false)
			selection.finish_execution()
		_update_turn_ui()
		return
	if not candidates.is_empty():
		var unit: CombatUnit = candidates[0]
		get_viewport().set_input_as_handled()
		if unit.is_ally and selection.selected_action != "shove":
			selection.clear_preview()
		elif selection.select_target(unit, actions.can_target(actor, unit, selection.selected_action)):
			await _execute_target(unit)
		_update_turn_ui()
		return
	selection.clear_preview()
	_update_turn_ui()


func _select_move_cell(cell: Vector2i) -> void:
	var actor: CombatUnit = turns.current_unit
	var path: Array[Vector2i] = []
	var jumping: bool = selection.selected_action == "jump"
	if actor != null and actor.is_ally:
		if jumping and actions.jump_cells(actor).has(cell):
			path = actions.grid.jump_path(actor, cell)
		elif not jumping and actions.can_move(actor, cell):
			path = actions.grid.path_to(actor, cell)
	if selection.select_move(cell, path):
		var executed: bool = await actions.jump_to(actor, cell) if jumping else await actions.move_to(actor, cell)
		if executed:
			selection.finish_execution()
	_update_turn_ui()


func preview_enemy(target: CombatUnit) -> bool:
	if (turns.current_unit == null or not turns.current_unit.is_ally
		or target not in units or target.is_ally or target.hit_points <= 0):
		return false
	selection.preview_unit(target)
	_update_turn_ui()
	return true


func _on_actions_changed() -> void:
	_save_pending = true
	if actions.is_over() and actions.is_victory():
		var monster_count: int = 0
		for unit: CombatUnit in units:
			if unit.can_drop_extra_reward():
				monster_count += 1
		# 전투 주사위로 굴려 이어하기가 마지막 공격을 다시 해도 드랍이 바뀌지 않는다.
		progress.record_victory(loot, monster_count, actions.dice)
	_update_turn_ui()


func _on_turn_changed() -> void:
	_save_pending = true
	selection.reset()
	_update_turn_ui()


func _execute_target(target: CombatUnit) -> void:
	var actor: CombatUnit = turns.current_unit
	var action: String = selection.begin_execution()
	match action:
		"attack", "shock":
			await actions.attack(actor, target, action == "shock")
		"mark":
			actions.mark(actor, target)
		"shove":
			actions.shove(actor, target)
	selection.finish_execution()
	_update_turn_ui()


func _animate_movement(unit: CombatUnit, cell: Vector2i) -> void:
	var destination: Vector2 = map.map_to_local(cell)
	# 다시 실행할 때도 방향은 저장하는 상태라 그대로 바꾼다.
	if _replaying():
		unit.face_toward(destination)
		return
	await _show_enemy_action()
	unit.face_toward(destination)
	unit.is_moving = true
	var tween: Tween = create_tween().set_parallel()
	tween.tween_property(unit, "position", destination, MOVE_STEP_TIME)
	tween.tween_property(unit, "floor_offset_y", map.map_to_surface(cell).y - destination.y, MOVE_STEP_TIME)
	tween.tween_property(unit, "body_offset_y", -3.0, MOVE_STEP_TIME / 2.0)
	tween.tween_property(unit, "body_offset_y", 0.0, MOVE_STEP_TIME / 2.0).from(-3.0).set_delay(MOVE_STEP_TIME / 2.0)
	await tween.finished
	unit.position = destination
	unit.body_offset_y = 0.0
	unit.is_moving = false


func _animate_jump(unit: CombatUnit, cell: Vector2i) -> void:
	var destination: Vector2 = map.map_to_local(cell)
	if _replaying():
		unit.face_toward(destination)
		return
	await _show_enemy_action()
	var duration: float = MOVE_STEP_TIME * 2.0
	var apex: float = -float(map.tile_set.tile_size.y)
	unit.face_toward(destination)
	unit.is_moving = true
	var tween: Tween = create_tween().set_parallel()
	tween.tween_property(unit, "position", destination, duration)
	tween.tween_property(unit, "floor_offset_y", map.map_to_surface(cell).y - destination.y, duration)
	tween.tween_property(unit, "body_offset_y", apex, duration / 2.0).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.tween_property(unit, "body_offset_y", 0.0, duration / 2.0).from(apex).set_delay(duration / 2.0).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	await tween.finished
	unit.position = destination
	unit.body_offset_y = 0.0
	unit.is_moving = false


func _animate_attack(actor: CombatUnit, target: CombatUnit) -> void:
	var destination: Vector2 = target.position + Vector2(0, target.floor_offset_y - 14)
	if _replaying():
		actor.face_toward(destination)
		return
	await _show_enemy_action()
	await _animate_attack_at(actor, destination)


func _animate_attack_at(actor: CombatUnit, destination: Vector2) -> void:
	actor.face_toward(destination)
	actor.play_attack()
	if actor.kind != CombatUnit.Kind.ARCHER:
		await get_tree().create_timer(1.0 / 6.0, false).timeout
		return
	var arrow: Polygon2D = Polygon2D.new()
	arrow.name = "Arrow"
	arrow.polygon = PackedVector2Array([
		Vector2(-4, -1), Vector2(4, -1), Vector2(4, 1), Vector2(-4, 1)
	])
	arrow.color = Color("efe4c8")
	arrow.z_index = 1
	arrow.position = actor.position + Vector2(-8 if actor.facing_left else 8, actor.floor_offset_y - 16)
	arrow.rotation = (destination - arrow.position).angle()
	add_child(arrow)
	var tween: Tween = create_tween()
	tween.tween_property(arrow, "position", destination, ARROW_FLIGHT_TIME)
	await tween.finished
	arrow.queue_free()


func _update_turn_ui() -> void:
	selection.discard_incapacitated_inspection()
	if selection.preview_prop != null and selection.preview_prop not in actions.get_props():
		selection.clear_preview()
	for unit: CombatUnit in units:
		unit.has_mark = actions.is_marked(unit)
		if not unit.is_moving:
			unit.position = map.map_to_local(unit.cell)
			unit.floor_offset_y = map.map_to_surface(unit.cell).y - unit.position.y
		unit.visible = unit.hit_points > 0
		unit.is_selected = unit == turns.current_unit
		unit.is_previewed = unit == selection.preview_target or (not selection.preview_path.is_empty()
			and actions.can_target(turns.current_unit, unit, "attack", selection.preview_cell))
		unit.queue_redraw()
	if turns.current_unit != null and turns.current_unit.is_ally:
		_last_ally = turns.current_unit
	var can_act: bool = actions.has_available_action(turns.current_unit)
	hud.refresh(turns, can_act)
	movement_cells.clear()
	if turns.current_unit != null and turns.current_unit.is_ally:
		if selection.selected_action == "move":
			movement_cells.assign(actions.reachable_cells(turns.current_unit).keys())
		elif selection.selected_action == "jump":
			movement_cells.assign(actions.jump_cells(turns.current_unit).keys())
	var attack_cells: Array[Vector2i] = []
	for cell: Vector2i in movement_cells:
		if not _attack_targets_from(cell).is_empty():
			attack_cells.append(cell)
	map.show_movement(movement_cells, attack_cells, selection.preview_path,
		turns.current_unit.cell if turns.current_unit != null else Vector2i.ZERO)
	map.show_grounds(actions.get_grounds())
	map.show_props(actions.get_props(), selection.preview_prop)
	map.reveal_units(units)
	# 가림 판정은 방금 그린 사물 위치를 사용한다.
	for unit: CombatUnit in units:
		unit.is_occluded = map.occludes(unit.cell,
			map.to_local(unit.to_global(Vector2(0, unit.floor_offset_y - 10))))
	if selection.preview_target != null:
		var preview: CombatChecks.AttackPreview = actions.grid.attack_preview(
			turns.current_unit, selection.preview_target)
		hud.show_attack_preview(selection.preview_target, preview)
		if selection.selected_action == "mark":
			hud.show_target_note(tr("표식 대상") if actions.can_target(turns.current_unit, selection.preview_target, "mark") else tr("표식을 사용할 수 없음"))
		elif selection.selected_action == "shove":
			if actions.can_target(turns.current_unit, selection.preview_target, "shove"):
				var cell: Vector2i = actions.grid.push_destination(turns.current_unit.cell, selection.preview_target.cell)
				var landing: String = actions.shove_landing(selection.preview_target, cell)
				var chance: float = 1.0
				if CombatActionRules.shove_saves(turns.current_unit, selection.preview_target):
					chance -= CombatActionRules.save_chance(turns.current_unit, selection.preview_target, "shove")
				hud.show_target_note(tr("밀려날 칸: %d, %d") % [cell.x, cell.y]
					+ ("" if landing.is_empty() else " · " + landing) + " · " + tr("밀칠 확률 %.1f%%") % (chance * 100.0))
			else:
				hud.show_target_note(tr("밀치기를 사용할 수 없음"))
	elif selection.preview_prop != null:
		var actor: CombatUnit = turns.current_unit
		var prop: CombatGrid.Prop = selection.preview_prop
		var note: String = tr("기본 공격만 가능")
		var title: String = tr("바위") if prop.kind == "rock" else tr("나무 상자 · 내구도 %d/6") % prop.hit_points
		if selection.selected_action == "attack" and actor != null:
			if prop.kind == "rock":
				var roll: CombatActions.RockRoll = actions.preview_rock(actor, prop)
				map.show_rock_roll(prop.cell, roll)
				var direction: String = {
					Vector2i.RIGHT: tr("오른쪽 아래"), Vector2i.DOWN: tr("왼쪽 아래"),
					Vector2i.LEFT: tr("왼쪽 위"), Vector2i.UP: tr("오른쪽 위")
				}.get(roll.direction, tr("방향 없음"))
				var collisions: Array[String] = []
				for unit: CombatUnit in roll.collisions:
					var landing: String = actions.rock_landing(roll, unit)
					collisions.append((tr("아군 피해4: %s") if unit.is_ally else tr("적 피해4: %s")) % unit.get_display_name()
						+ ("" if landing.is_empty() else " · " + landing))
				note = tr("행동1 · 주사위 없음\n%s · %d칸 · %s\n%s\n같은 바위를 다시 좌클릭하면 굴립니다.") % [
					direction, roll.cells.size(), roll.reason,
					", ".join(collisions) if not collisions.is_empty() else tr("충돌 없음")]
			else:
				var sides: int = actor.get_ability_sides(CombatActionRules.damage_ability(actor, "attack"))
				var minimum: int = maxi(1, actor.get_damage_bonus() + 1)
				var maximum: int = maxi(1, actor.get_damage_bonus() + sides)
				note = tr("피해 %d~%d · 행동1 · 자동 명중\n같은 상자를 다시 좌클릭하면 공격합니다.") % [minimum, maximum]
			if not actions.can_attack_prop(actor, prop):
				if actor.action_left <= 0:
					note = tr("행동 없음")
				elif actor.is_stunned:
					note = tr("기절하여 공격 불가")
				else:
					note = actions.unavailable_reason(actor, "attack")
					if note.is_empty():
						note = tr("사거리 또는 높이 조건을 확인")
		hud.show_target_note(title + "\n" + note)
	elif selection.inspected_unit != null:
		hud.show_unit(selection.inspected_unit)
	var showing_move: bool = selection.selected_action == "move" or not selection.preview_path.is_empty()
	hud.refresh_actions(actions, selection.selected_action, _last_ally)
	staging.visible = waiting_for_start
	if waiting_for_start:
		hud.get_node("Round").text = tr("전투 준비")
	hud.get_node("Skills").visible = not waiting_for_start
	hud.get_node("EndTurn").visible = not waiting_for_start
	hud.show_move_mode(showing_move)
	if selection.selected_action == "jump":
		hud.show_move_mode(false)
		var note: String = tr("점프 · 착지할 칸을 우클릭합니다.\n같은 칸을 다시 우클릭하면 확정합니다.")
		if not selection.preview_path.is_empty():
			var actor: CombatUnit = turns.current_unit
			var cell: Vector2i = selection.preview_cell
			var reactors: int = actions.jump_reactors(actor, cell).size()
			var fall: int = actions.fall_damage(actor, cell)
			note = tr("점프 · 이동 %d · 보조 행동1\n%s · %s") % [actions.jump_cells(actor).get(cell, 0),
				tr_n("기회 공격 %d명", "기회 공격 %d명", reactors) % reactors if reactors > 0 else tr("기회 공격 없음"),
				tr("낙하 피해 %d") % fall if fall > 0 else tr("낙하 없음")]
		hud.show_target_note(note)
	if actions.is_over():
		hud.show_outcome(actions.is_victory())
		if not preparation.visible:
			hud.show_result(actions.is_victory(), progress.graduated, _enemy_turn_running or actions.busy)
	queue_redraw()


func _attack_targets_from(cell: Vector2i) -> Array[CombatUnit]:
	var targets: Array[CombatUnit] = []
	for unit: CombatUnit in units:
		if actions.can_target(turns.current_unit, unit, "attack", cell):
			targets.append(unit)
	return targets
