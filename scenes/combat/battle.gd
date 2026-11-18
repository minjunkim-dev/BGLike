extends Node2D
## 전투 화면과 3막 진행. 적 묶음은 이니셔티브 순서대로 실행한다.

const MOVE_STEP_TIME: float = 0.09
const ARROW_FLIGHT_TIME: float = 0.16
## 칸을 조준하는 동작. 한 번 눌러 칸(과 범위)을 보고, 같은 칸을 다시 누르면 실행한다.
const AIM_ACTIONS: Array[String] = ["oil_throw", "oil_bottle", "trick_arrow", "firework_arrow"]
## 인접한 칸을 눌러 방향(정면)을 고르는 동작. 휩쓸기는 정면 반달, 효시는 세 줄 띠다.
const FACING_ACTIONS: Array[String] = ["sweep", "whistle"]
const ENEMY_PAUSE_TIME: float = 0.35
## 근접 공격 뒤 기다리는 시간(기본값). 전체 속도 계수로 늘어난다.
const MELEE_ATTACK_TIME: float = 1.0 / 6.0
## 적 턴에 Space를 누르고 있는 동안의 시간 배율. 규칙이 아니라 표시 속도다.
const ENEMY_FAST_SPEED: float = 4.0

## 자동 저장을 마친 뒤. 검사가 저장한 순간의 상태를 비교한다.
signal autosaved

@export var stages: Array[CombatStage] = []

var progress: CombatActProgress
## 처음 열 스테이지 번호(0부터). 타이틀의 디버그 테스트 진입(#512)이 장면을 트리에 넣기 전에 정한다.
var start_stage: int = 0
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

var hit_effects: CombatHitEffects
var sounds: CombatSounds
@onready var map: CombatMap = $Map
@onready var camera: CombatCamera = $Camera
@onready var hud: CombatTurnHud = $UI/TurnHud
@onready var pause_menu: PauseMenu = $Pause/PauseMenu
@onready var dice_view: CombatDiceRollView = $UI/DiceRollView


func _ready() -> void:
	assert(stages.size() == 9, "전투 진행에는 스테이지 데이터9개가 필요합니다.")
	progress = CombatActProgress.new(stages.size())
	progress.stage_index = start_stage
	# 파티 노드를 유지해 같은 막의 HP와 스킬 횟수를 이어 간다.
	for child: Node in $Units.get_children():
		party.append(child as CombatUnit)
	sounds = CombatSounds.new()
	sounds.name = "Sounds"
	add_child(sounds)
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
	staging.add_child(hint)
	start_button = Button.new()
	start_button.name = "StartBattle"
	start_button.text = tr("전투 시작")
	start_button.custom_minimum_size.x = 96
	start_button.add_theme_font_size_override("font_size", 14)
	start_button.pressed.connect(start_battle)
	staging.add_child(start_button)

	hud.unit_selected.connect(_on_unit_selected)
	hud.unit_hovered.connect(_on_unit_hovered)
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
			unit.show_feedback(str(amount), hud.feedback_obstacles(), CombatUnit.HEAL_COLOR)
			sounds.play(&"heal")
			hit_effects.play_heal(unit))
	actions.damaged.connect(func(target: Object) -> void:
		if not _replaying():
			sounds.play_hit(target))
	actions.critical_hit.connect(func(_target: CombatUnit) -> void:
		if not _replaying():
			sounds.play_critical())
	actions.downed.connect(func(_unit: CombatUnit) -> void:
		if not _replaying():
			sounds.play(&"downed"))
	actions.self_used.connect(func(actor: CombatUnit, action: String) -> void:
		if _replaying():
			return
		if action == "holy_veil":
			sounds.play(&"shield")
			hit_effects.play_shield(actor)
		elif action == "battle_cry":
			sounds.play(&"shout")
			for unit: CombatUnit in units:
				if unit.hit_points > 0 and unit.battle_cry_source == actor:
					hit_effects.play_buff(unit))
	actions.swept.connect(func(actor: CombatUnit, facing: Vector2i) -> void:
		if not _replaying():
			hit_effects.play_sweep(actor, map.map_to_local(facing) - map.map_to_local(actor.cell)))
	actions.status_applied.connect(func(target: CombatUnit, kind: String) -> void:
		if not _replaying():
			hit_effects.play_status(target, kind))
	actions.status_ticked.connect(func(unit: CombatUnit, kind: String, _amount: int) -> void:
		if not _replaying():
			hit_effects.play_status(unit, kind))
	actions.oil_ignited.connect(func(cells: Array[Vector2i]) -> void:
		if not _replaying():
			for cell: Vector2i in cells:
				hit_effects.play_ignite(map.map_to_surface(cell)))
	hit_effects = CombatHitEffects.new()
	hit_effects.name = "HitEffects"
	hit_effects.z_index = 5
	add_child(hit_effects)
	actions.struck.connect(_on_struck)
	actions.reaction_requested.connect(_on_reaction_requested)
	hud.reflex_selected.connect(_on_reflex_selected)
	hud.reflex_previewed.connect(_on_reflex_previewed)
	hud.reflex_label = _reflex_arrow
	hud.grid = actions.grid
	actions.movement_animation = _animate_movement
	actions.jump_animation = _animate_jump
	actions.attack_animation = _animate_attack
	actions.cell_attack_animation = _animate_cell_attack
	actions.roll_animation = _animate_roll
	turns.changed.connect(_on_turn_changed)
	turns.turn_started.connect(_on_turn_started_sound)
	turns.order_rotated.connect(hud.prepare_order_rotation)
	_start_stage(true)


## 타격 섬광·히트스톱·빗나감 잔상(#559). 이어하기 재실행에서는 피해 팝업·피격음처럼 생략한다.
func _on_struck(attacker: CombatUnit, target: CombatUnit, cell: Vector2i, hit: bool) -> void:
	if _replaying():
		return
	if not hit:
		sounds.play(&"miss")
		hit_effects.play_miss(attacker, target)
	elif target == null:
		hit_effects.play_hit(attacker, null, map.map_to_surface(cell) + Vector2(0, -8))
	else:
		hit_effects.play_hit(attacker, target, target.position + Vector2(0, target.floor_offset_y - 14))


## 반응 확인 창을 띄운다. 반사신경이면 후보 칸을 맵에 보인다.
func _on_reaction_requested(kind: String, prompt: String) -> void:
	hud.show_reaction(kind, prompt, actions.pending_cells)
	if kind == "reflex":
		_update_turn_ui()


func _on_reflex_selected(cell: Vector2i) -> void:
	actions.resolve_reflex(cell)
	_update_turn_ui()


## 칸 버튼에 올린 칸으로 가는 경로를 미리 보인다. 벗어나면 후보 칸만 보인다.
func _on_reflex_previewed(cell: Vector2i) -> void:
	if actions.pending_kind != "reflex" or actions.pending_reactor == null:
		return
	var path: Array[Vector2i] = []
	if cell != Vector2i(-1, -1):
		path.append(cell)
	map.show_movement(actions.pending_cells, [], path, actions.pending_reactor.cell)


## 반사신경 칸 버튼의 글자: 화면에서 본 방향이다. 칸 좌표가 아니라 맵 투영의 화면 위치로 정한다.
func _reflex_arrow(cell: Vector2i) -> String:
	if actions.pending_reactor == null:
		return "%d, %d" % [cell.x, cell.y]
	var delta: Vector2 = map.map_to_local(cell) - map.map_to_local(actions.pending_reactor.cell)
	return ("↖" if delta.y < 0 else "↙") if delta.x < 0 else ("↗" if delta.y < 0 else "↘")


func _exit_tree() -> void:
	if sounds != null:
		sounds.stop_ambient()
	actions.movement_animation = Callable()
	actions.jump_animation = Callable()
	actions.attack_animation = Callable()
	actions.cell_attack_animation = Callable()
	actions.roll_animation = Callable()
	Engine.time_scale = 1.0


func _start_stage(restore_act: bool) -> void:
	waiting_for_start = true
	sounds.stop_ambient()
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
	# 시작 전 정비 화면에서 장비가 바뀌면 최대 이동이 달라진다. 아직 아무 행동도 없었으므로 다시 채운다(3-3).
	for unit: CombatUnit in party:
		unit.refill_turn_resources()
	waiting_for_start = false
	_save_pending = true
	get_viewport().gui_release_focus()
	sounds.start_ambient(actions.grid)
	_on_turn_started_sound(turns.current_unit)
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
	actions.grid.trees = stage.tree_cells()
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
	actions.loot = loot
	actions.act_number = progress.act_number()
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
	# 유닛 load_state 전에 맞춘다. 레벨 setter가 보정한 HP를 저장한 HP로 덮는다.
	_sync_party_level()
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
	# 파티 레벨은 깬 막 수를 넘을 수 없다. 막의 마지막 스테이지는 승리를 기록한 뒤에 깬 것으로 센다 (#477).
	if not (state.get("level") is int and state.level >= 0
			and state.level <= state.stage / CombatActProgress.STAGES_PER_ACT
			+ (1 if state.rewarded and state.stage % CombatActProgress.STAGES_PER_ACT == CombatActProgress.STAGES_PER_ACT - 1 else 0)):
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
				or not (saved.armor.is_empty() or loot.is_valid_item(saved.armor) and saved.armor.kind == "armor")
				or not loot.is_valid_potions(saved.potions) or not (saved.ally or saved.potions.is_empty())):
			return false
		var agility_sides: int = (CombatUnit.ALLY_ABILITY_SIDES[saved.kind][CombatUnit.Ability.AGILITY]
			if saved.ally else CombatEnemyDefinitions.for_kind(saved.kind)["abilities"][CombatUnit.Ability.AGILITY])
		# 생성한 새끼는 굴리지 않고 엄마 앞에 삽입되므로 원본 값 0을 보존한다.
		if saved.initiative_roll < (1 if index < identities.size() else 0) or saved.initiative_roll > agility_sides:
			return false
	if not (state.last_ally >= 0 and state.last_ally < count and saved_units[state.last_ally].ally
			and CombatTurns.is_valid_state(state.get("turns"), count)
			and CombatActions.is_valid_state(state, count, stage.map_size, stage.tree_cells())):
		return false
	# 떨어진·주운 아이템은 이 스테이지의 상자 수를 넘지 않고, 남은 상자 칸에 떨어져 있지 않다.
	var crates: Array = state.props.filter(func(saved: Array) -> bool: return saved[0] == "crate")
	if not (CombatFloorLoot.is_valid_state(state.get("floor_loot"), stage.map_size,
			maxi(0, stage.crate_cells.size() - crates.size()), loot.is_valid_item)
			and crates.all(func(saved: Array) -> bool: return state.floor_loot.drops.all(
				func(drop: Array) -> bool: return drop[0] != saved[1]))):
		return false
	# 턴 순서는 살아 있는 유닛 전부다. 쓰러진 유닛이나 빠진 유닛이 있으면 턴이 끝없이 넘어가거나 멈춘다.
	var order: Array = state.turns.order
	var living: Array = range(count).filter(func(index: int) -> bool: return saved_units[index].hit_points > 0)
	if (order.size() != living.size() or not living.all(func(index: int) -> bool: return index in order)
			or not order.is_empty() and state.turns.current < 0):
		return false
	# 시계 슬롯은 쓰러진 시전자의 자리다. 시전자가 살아 있으면 두 번 줄고, 기준 유닛이 쓰러졌으면 줄지 않는다.
	for slot: Array in state.clock_slots:
		if slot[0] in order or slot[1] not in order:
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
			# 반응 답은 bool이거나, 반사신경이 고른 지도 안의 칸이다.
			and replay.get("reactions", []).all(func(answer: Variant) -> bool:
				return answer is bool or answer is Vector2i and Rect2i(Vector2i.ZERO, stage.map_size).has_point(answer))
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
			progress.is_last_in_act(), screen.maintaining, actions.floor_loot.cells().size())
		hud.hide_result()
		_sync_music()
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
			progress.is_last_in_act(), false, actions.floor_loot.cells().size())
		hud.hide_result()
		_sync_music()
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
	await get_tree().create_timer(CombatPresentation.duration(ENEMY_PAUSE_TIME), false).timeout


## 적 턴의 첫 이동·공격 연출 전에 한 번 멈춰 행동할 적을 보여 준다.
func _show_enemy_action() -> void:
	if not _enemy_turn_running:
		return
	_enemy_acted = true
	if not _enemy_shown:
		_enemy_shown = true
		await get_tree().create_timer(CombatPresentation.duration(ENEMY_PAUSE_TIME), false).timeout


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
	if waiting_for_start or actor == null or not actor.is_ally:
		return
	if action == "stand_up":
		actions.stand_up(actor)
		_update_turn_ui()
		return
	if not actions.can_use(actor, action):
		return
	if selection.select_action(action):
		actions.use_self(actor, action)
		selection.finish_execution()
	_update_turn_ui()


## 마우스가 올라간 칸. 떨어진 아이템이 있으면 종류와 수치를 안내한다.
var _hover_cell: Vector2i = Vector2i(-1, -1)


func _hover_floor_loot(screen_position: Vector2) -> void:
	var world_position: Vector2 = get_canvas_transform().affine_inverse() * screen_position
	var cell: Vector2i = map.surface_to_map(map.to_local(world_position))
	if cell == _hover_cell:
		return
	var affected: bool = (not actions.floor_loot.item_at(_hover_cell).is_empty()
		or not actions.floor_loot.item_at(cell).is_empty())
	_hover_cell = cell
	if affected:
		_update_turn_ui()


## 적 위협 범위(#556). T로 켜고 끄며 기본은 꺼짐이다. 저장하지 않는다.
var threat_visible: bool = false
## 마우스가 올라간 적(몸통 또는 턴 순서 초상). 있으면 그 적의 범위만 보인다.
var _threat_unit: CombatUnit
var _body_hover_unit: CombatUnit
var _portrait_hover_unit: CombatUnit


func _on_unit_hovered(unit: CombatUnit) -> void:
	_portrait_hover_unit = unit
	_sync_threat_hover()


func _hover_enemy_body(screen_position: Vector2) -> void:
	var world_position: Vector2 = get_canvas_transform().affine_inverse() * screen_position
	var candidates: Array[CombatUnit] = []
	for unit: CombatUnit in units:
		if unit.visible and unit.hit_points > 0 and unit.contains_body_point(unit.to_local(world_position)):
			candidates.append(unit)
	candidates.sort_custom(func(a: CombatUnit, b: CombatUnit) -> bool:
		if a.position.y != b.position.y:
			return a.position.y > b.position.y
		return a.get_index() > b.get_index())
	var found: CombatUnit = candidates[0] if not candidates.is_empty() else actions.grid.unit_at(
		map.surface_to_map(map.to_local(world_position)))
	_body_hover_unit = found
	_sync_threat_hover()


func _sync_threat_hover() -> void:
	var picked: CombatUnit = _portrait_hover_unit if _portrait_hover_unit != null else _body_hover_unit
	if picked != null and (picked.is_ally or picked.hit_points <= 0 or picked not in units):
		picked = null
	if picked == _threat_unit:
		return
	_threat_unit = picked
	_refresh_threat()


func _refresh_threat() -> void:
	var cells: Array[Vector2i] = []
	if not preparation.visible and not actions.is_over():
		var shown: Array[CombatUnit] = []
		if _threat_unit != null and _threat_unit.hit_points > 0 and _threat_unit in units:
			shown.append(_threat_unit)
		elif threat_visible:
			for unit: CombatUnit in units:
				if not unit.is_ally and unit.visible and unit.hit_points > 0 and not unit.stealthed:
					shown.append(unit)
		for enemy: CombatUnit in shown:
			for cell: Vector2i in actions.threat_cells(enemy):
				if cell not in cells:
					cells.append(cell)
	map.show_threat(cells)


func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and not preparation.visible:
		_hover_floor_loot(event.position)
		_hover_enemy_body(event.position)
	if (event is InputEventKey and event.physical_keycode == KEY_T and not preparation.visible
			and not event.is_command_or_control_pressed()):
		get_viewport().set_input_as_handled()
		if event.pressed and not event.echo:
			threat_visible = not threat_visible
			_refresh_threat()
		return
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


## 방향 동작(휩쓸기·효시)의 클릭이 가리키는 방향 칸. 인접 칸의 몸통이나 사물을 눌러도 그 칸을 방향으로 고른다.
## 인접하지 않은 몸통(자기 자신 등)이 가린 칸은 격자 위치로 고르고, 그래도 인접하지 않거나 맵 밖이면 호출자가 미리보기만 지운다.
func _facing_at(actor: CombatUnit, cell: Vector2i, candidates: Array[CombatUnit], prop: CombatGrid.Prop,
		world_position: Vector2) -> Vector2i:
	var facing: Vector2i = cell
	if not candidates.is_empty() and CombatGrid.distance(actor.cell, candidates[0].cell) == 1:
		facing = candidates[0].cell
	elif prop != null and CombatGrid.distance(actor.cell, prop.cell) == 1:
		facing = prop.cell
	elif not actions.grid.is_inside(cell):
		# 낭떠러지 칸은 바닥 타일이 없어 격자 위치로 잡히지 않으므로 인접한 낭떠러지의 윗면으로 찾는다.
		# 높이 때문에 윗면이 겹쳐도 맵 안 칸이 잡혔으면 그 칸을 방향으로 둔다.
		for neighbor: Vector2i in CombatGrid.neighbors(actor.cell):
			if actions.grid.pits.has(neighbor) and map.contains_surface(neighbor, map.to_local(world_position)):
				facing = neighbor
	return facing


func _can_face(actor: CombatUnit, action: String, facing: Vector2i) -> bool:
	return actions.can_sweep(actor, facing) if action == "sweep" else actions.can_whistle(actor, facing)


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
	if selection.selected_action in CombatActionRules.OIL_ACTIONS:
		get_viewport().set_input_as_handled()
		_select_aim_cell(cell)
		return
	if selection.selected_action in AIM_ACTIONS:
		get_viewport().set_input_as_handled()
		# 유닛 몸통이나 사물을 눌러도 그 칸을 고른다.
		var aimed_cell: Vector2i = cell
		if not candidates.is_empty():
			aimed_cell = candidates[0].cell
		elif prop != null:
			aimed_cell = prop.cell
		await _select_aim_cell(aimed_cell)
		return
	if selection.selected_action in FACING_ACTIONS:
		get_viewport().set_input_as_handled()
		var facing: Vector2i = _facing_at(actor, cell, candidates, prop, world_position)
		var facing_action: String = selection.selected_action
		if CombatGrid.distance(actor.cell, facing) != 1 or not actions.grid.is_inside(facing):
			selection.clear_preview()
		elif selection.select_cell(facing, _can_face(actor, facing_action, facing)):
			selection.begin_execution()
			if facing_action == "sweep":
				await actions.sweep(actor, facing)
			else:
				await actions.whistle(actor, facing)
			selection.finish_execution()
		_update_turn_ui()
		return
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
			_offer_moving_shot(actor)
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


## 칸 조준 동작(기름병 던지기, 장난스러운 화살, 폭죽 화살). 한 번 눌러 범위를 보고, 같은 칸을 다시 누르면 실행한다.
func _select_aim_cell(cell: Vector2i) -> void:
	var actor: CombatUnit = turns.current_unit
	var action: String = selection.selected_action
	if selection.select_cell(cell, actions.can_aim(actor, action, cell)):
		selection.begin_execution()
		match action:
			"oil_throw", "oil_bottle":
				actions.throw_oil(actor, cell, action)
			"trick_arrow":
				await actions.trick_arrow(actor, cell)
			"firework_arrow":
				await actions.firework_arrow(actor, cell)
		selection.finish_execution()
		_offer_moving_shot(actor)
	_update_turn_ui()


func _select_move_cell(cell: Vector2i) -> void:
	var actor: CombatUnit = turns.current_unit
	var path: Array[Vector2i] = []
	var jumping: bool = selection.selected_action == "jump"
	# 무빙샷 도약도 점프처럼 착지 칸을 먼저 보고 같은 칸을 다시 우클릭하면 뛴다(#528).
	var leaping: bool = selection.selected_action == "moving_shot"
	if actor != null and actor.is_ally:
		if leaping:
			if cell in actions.moving_shot_cells(actor):
				path = [cell]
		elif jumping and actions.jump_cells(actor).has(cell):
			path = actions.grid.jump_path(actor, cell)
		elif not jumping and actions.can_move(actor, cell):
			path = actions.grid.path_to(actor, cell)
	if selection.select_move(cell, path):
		var executed: bool
		if leaping:
			executed = await actions.moving_shot(actor, cell)
		elif jumping:
			executed = await actions.jump_to(actor, cell)
		else:
			executed = await actions.move_to(actor, cell)
		if executed:
			selection.finish_execution()
	_update_turn_ui()


## 무빙샷을 쓸 수 있게 되면 선택을 도약으로 바꿔 도착 칸을 보인다(#528).
func _offer_moving_shot(actor: CombatUnit) -> void:
	if actor != null and actor.moving_shot_ready and actor == turns.current_unit:
		selection.selected_action = "moving_shot"


func preview_enemy(target: CombatUnit) -> bool:
	if (turns.current_unit == null or not turns.current_unit.is_ally
		or target not in units or target.is_ally or target.hit_points <= 0):
		return false
	selection.preview_unit(target)
	_update_turn_ui()
	return true


## 진영이 바뀌는 턴 시작 신호음. 전투 준비 중과 이어하기 재실행에서는 내지 않는다.
func _on_turn_started_sound(unit: CombatUnit) -> void:
	if not waiting_for_start and not _replaying():
		sounds.turn_started(unit)


func _on_actions_changed() -> void:
	_save_pending = true
	if actions.is_over():
		sounds.stop_ambient()
	if actions.is_over() and actions.is_victory():
		var monster_count: int = 0
		for unit: CombatUnit in units:
			if unit.can_drop_extra_reward():
				monster_count += 1
		# 전투 주사위로 굴려 이어하기가 마지막 공격을 다시 해도 드랍이 바뀌지 않는다.
		progress.record_victory(loot, monster_count, actions.dice, actions.floor_loot.picked)
		_sync_party_level()
	_update_turn_ui()


## 파티 레벨을 아군 모두에 맞춘다. 몬스터는 늘 레벨 0이다 (#477).
func _sync_party_level() -> void:
	for unit: CombatUnit in party:
		unit.dice_level = progress.level


## 화면에 맞는 배경음을 고른다(#629). 정비·보상 확인은 차분한 곡, 끝난 전투는 승리·패배 곡, 그 밖은 전투 곡이다.
func _sync_music() -> void:
	if preparation.visible:
		GameMusic.play(get_tree(), GameMusic.CALM)
	elif actions.is_over():
		GameMusic.play(get_tree(), GameMusic.VICTORY if actions.is_victory() else GameMusic.DEFEAT)
	else:
		GameMusic.play(get_tree(), GameMusic.BATTLE)


func _on_turn_changed() -> void:
	_save_pending = true
	selection.reset()
	_update_turn_ui()


func _execute_target(target: CombatUnit) -> void:
	var actor: CombatUnit = turns.current_unit
	var action: String = selection.begin_execution()
	match action:
		"attack":
			await actions.attack(actor, target)
		"cross_slash":
			await actions.cross_slash(actor, target)
		"steel_charge":
			await actions.steel_charge(actor, target)
		"bow_bash":
			await actions.bow_bash(actor, target)
		"shove":
			actions.shove(actor, target)
	selection.finish_execution()
	_offer_moving_shot(actor)
	_update_turn_ui()


func _animate_movement(unit: CombatUnit, cell: Vector2i) -> void:
	var destination: Vector2 = map.map_to_local(cell)
	# 다시 실행할 때도 방향은 저장하는 상태라 그대로 바꾼다.
	if _replaying():
		unit.face_toward(destination)
		return
	await _show_enemy_action()
	unit.face_toward(destination)
	sounds.play(CombatSounds.step_cue(actions.grid, stages[progress.stage_index], cell))
	unit.is_moving = true
	var tween: Tween = create_tween().set_parallel()
	var step_time: float = CombatPresentation.duration(MOVE_STEP_TIME)
	tween.tween_property(unit, "position", destination, step_time)
	tween.tween_property(unit, "floor_offset_y", map.map_to_surface(cell).y - destination.y, step_time)
	tween.tween_property(unit, "body_offset_y", -3.0, step_time / 2.0)
	tween.tween_property(unit, "body_offset_y", 0.0, step_time / 2.0).from(-3.0).set_delay(step_time / 2.0)
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
	var duration: float = CombatPresentation.duration(MOVE_STEP_TIME * 2.0)
	var apex: float = -float(map.tile_set.tile_size.y)
	unit.face_toward(destination)
	sounds.play(&"jump")
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
	sounds.play(&"land")


func _animate_attack(actor: CombatUnit, target: CombatUnit) -> void:
	var destination: Vector2 = target.position + Vector2(0, target.floor_offset_y - 14)
	if _replaying():
		actor.face_toward(destination)
		return
	await _show_enemy_action()
	await _animate_attack_at(actor, destination)


## 아군이 굴릴 때만 보인다. 몬스터의 굴림과 이어하기로 다시 실행하는 굴림은 보이지 않는다.
func _animate_roll(roll: CombatDiceRoll) -> void:
	if _replaying() or not roll.roller.is_ally:
		return
	await dice_view.play(roll)


## 빈 칸을 겨눈 화살 연출.
func _animate_cell_attack(actor: CombatUnit, cell: Vector2i) -> void:
	await _animate_attack_at(actor, map.map_to_surface(cell) + Vector2(0, -8))


func _animate_attack_at(actor: CombatUnit, destination: Vector2) -> void:
	actor.face_toward(destination)
	actor.play_attack()
	if actor.kind != CombatUnit.Kind.ARCHER:
		await get_tree().create_timer(CombatPresentation.duration(MELEE_ATTACK_TIME), false).timeout
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
	tween.tween_property(arrow, "position", destination, CombatPresentation.duration(ARROW_FLIGHT_TIME))
	await tween.finished
	arrow.queue_free()


func _update_turn_ui() -> void:
	selection.discard_incapacitated_inspection()
	if selection.preview_prop != null and selection.preview_prop not in actions.get_props():
		selection.clear_preview()
	var sweeping: bool = (selection.selected_action in FACING_ACTIONS and turns.current_unit != null
		and turns.current_unit.is_ally and selection.preview_cell != Vector2i(-1, -1))
	var sweep_targets: Array[CombatUnit] = []
	if sweeping:
		sweep_targets = (actions.sweep_targets(turns.current_unit, selection.preview_cell) if selection.selected_action == "sweep"
			else actions.whistle_targets(turns.current_unit, selection.preview_cell))
	for unit: CombatUnit in units:
		if not unit.is_moving:
			unit.position = map.map_to_local(unit.cell)
			unit.floor_offset_y = map.map_to_surface(unit.cell).y - unit.position.y
		unit.visible = unit.hit_points > 0
		unit.is_selected = unit == turns.current_unit
		unit.is_previewed = unit == selection.preview_target or (not selection.preview_path.is_empty()
			and actions.can_target(turns.current_unit, unit, "attack", selection.preview_cell)) or unit in sweep_targets
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
		elif selection.selected_action == "moving_shot":
			movement_cells.assign(actions.moving_shot_cells(turns.current_unit))
		elif sweeping:
			movement_cells.assign(actions.grid.sweep_cells(turns.current_unit.cell, selection.preview_cell)
				if selection.selected_action == "sweep" else actions.grid.band_cells(turns.current_unit.cell, selection.preview_cell))
		elif selection.selected_action in AIM_ACTIONS:
			var aim_action: String = selection.selected_action
			var aimed: bool = actions.can_aim(turns.current_unit, aim_action, selection.preview_cell)
			if aimed and aim_action == "trick_arrow":
				movement_cells.assign([selection.preview_cell])
			elif aimed:
				movement_cells.assign(actions.aim_area(turns.current_unit, aim_action, selection.preview_cell))
			else:
				movement_cells.assign(actions.aim_cells(turns.current_unit, aim_action))
		elif selection.selected_action in FACING_ACTIONS:
			# 방향을 고르기 전에는 고를 수 있는 인접 칸을 보인다.
			for cell: Vector2i in CombatGrid.neighbors(turns.current_unit.cell):
				if _can_face(turns.current_unit, selection.selected_action, cell):
					movement_cells.append(cell)
	var attack_cells: Array[Vector2i] = []
	var origin: Vector2i = turns.current_unit.cell if turns.current_unit != null else Vector2i.ZERO
	var path: Array[Vector2i] = selection.preview_path
	if actions.pending_kind == "reflex" and actions.pending_reactor != null:
		# 반사신경 확인 창이 열린 동안에는 회피할 후보 칸만 이동 칸처럼 보인다.
		movement_cells.assign(actions.pending_cells)
		origin = actions.pending_reactor.cell
		path = []
	else:
		for cell: Vector2i in movement_cells:
			if selection.selected_action in FACING_ACTIONS or not _attack_targets_from(cell).is_empty():
				attack_cells.append(cell)
	map.show_movement(movement_cells, attack_cells, path, origin)
	map.show_grounds(actions.get_grounds())
	map.show_trees(actions.grid.trees)
	map.show_floor_loot(actions.floor_loot.drops)
	map.show_props(actions.get_props(), selection.preview_prop)
	_refresh_threat()
	map.reveal_units(units)
	# 가림 판정은 방금 그린 사물 위치를 사용한다.
	for unit: CombatUnit in units:
		unit.is_occluded = map.occludes(unit.cell,
			map.to_local(unit.to_global(Vector2(0, unit.floor_offset_y - 10))))
	if selection.preview_target != null:
		# 고른 동작의 명중 능력치·근접 여부를 따른다(활 후려치기는 힘 d6, 원거리 불리 없음).
		var preview: CombatChecks.AttackPreview = actions.grid.attack_preview(
			turns.current_unit, selection.preview_target, selection.selected_action)
		hud.show_attack_preview(selection.preview_target, preview)
		if selection.selected_action == "shove":
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
		elif selection.selected_action == "steel_charge":
			var actor: CombatUnit = turns.current_unit
			var target: CombatUnit = selection.preview_target
			if not actions.can_target(actor, target, "steel_charge"):
				hud.show_target_note(tr("강철 돌진을 사용할 수 없음"))
			else:
				# 전진하는 아군은 대상이 있던 칸에 도착해 그 칸의 아이템을 줍는다 (환경요소 3-5).
				var advance: String = actions.pickup_note(actor, [target.cell])
				if actions.grid.can_shove(actor, target):
					var cell: Vector2i = actions.grid.push_destination(actor.cell, target.cell)
					var landing: String = actions.shove_landing(target, cell)
					hud.show_target_note(tr("명중하면 밀려날 칸: %d, %d") % [cell.x, cell.y] + ("" if landing.is_empty() else " · " + landing)
						+ ("" if advance.is_empty() else " · " + advance))
				else:
					hud.show_target_note(tr("밀려날 칸이 막힘 · 명중하면 피해만, 쓰러뜨리면 그 칸으로 전진")
						+ ("" if advance.is_empty() else " · " + advance))
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
					var landing: String = actions.rock_collision_note(roll, unit)
					collisions.append((tr("아군 피해4: %s") if unit.is_ally else tr("적 피해4: %s")) % unit.get_display_name()
						+ ("" if landing.is_empty() else " · " + landing))
				note = tr("행동1 · 피해 굴림 없음\n%s · %d칸 · %s\n%s\n같은 바위를 다시 좌클릭하면 굴립니다.") % [
					direction, roll.cells.size(), roll.reason,
					", ".join(collisions) if not collisions.is_empty() else tr("충돌 없음")]
			else:
				var ability: CombatUnit.Ability = CombatActionRules.damage_ability(actor, "attack")
				var modifier: int = actor.get_ability_modifier(ability)
				var minimum: int = maxi(1, actor.get_damage_bonus() + maxi(1, 1 + modifier))
				var maximum: int = maxi(1, actor.get_damage_bonus() + maxi(1, actor.get_ability_sides(ability) + modifier))
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
	# 걷기·무빙샷 도약 미리보기는 안내를 숨기지만, 도착 칸이 물이면 서기 전에 물 칸 화상 규칙을, 기름 칸이면 미끌거림 안내를 보인다(#503, #600).
	if selection.selected_action != "jump" and not selection.preview_path.is_empty():
		var notes: Array[String] = []
		for note: String in [actions.water_note(selection.preview_cell),
				actions.slip_note(turns.current_unit, selection.preview_path),
				actions.pickup_note(turns.current_unit, selection.preview_path)]:
			if not note.is_empty():
				notes.append(note)
		if not notes.is_empty():
			hud.show_move_mode(false)
			hud.show_target_note("\n".join(notes))
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
			var water: String = actions.water_note(cell)
			if not water.is_empty():
				note += "\n" + water
			# 점프는 넘어가는 중간 칸에 서지 않으므로 미끌거림은 착지 칸 기준이다(#600).
			var slip: String = actions.slip_note(actor, [cell])
			if not slip.is_empty():
				note += "\n" + slip
			var pickup: String = actions.pickup_note(actor, [cell])
			if not pickup.is_empty():
				note += "\n" + pickup
		hud.show_target_note(note)
	elif (selection.selected_action == "sweep" and turns.current_unit != null and turns.current_unit.is_ally
			and not actions.busy):
		var note: String = tr("휩쓸기 · 정면으로 삼을 인접한 칸을 좌클릭합니다.\n같은 칸을 다시 좌클릭하면 실행합니다.")
		if sweeping and sweep_targets.is_empty():
			note = tr("휩쓸기 · 행동1 · 영향 칸에 적이 없음\n같은 칸을 다시 좌클릭하면 실행합니다.")
		elif sweeping:
			var chances: Array[String] = []
			for target: CombatUnit in sweep_targets:
				chances.append("%s %.1f%%" % [target.get_display_name(), actions.sweep_chance(turns.current_unit, target) * 100.0])
			note = tr("휩쓸기 · 행동1 · 시계방향 명중률\n%s\n같은 칸을 다시 좌클릭하면 실행합니다.") % " → ".join(chances)
		hud.show_target_note(note)
	elif (selection.selected_action == "whistle" and turns.current_unit != null and turns.current_unit.is_ally
			and not actions.busy):
		var whistle_note: String = tr("효시 · 방향으로 삼을 인접한 칸을 좌클릭합니다.\n같은 칸을 다시 좌클릭하면 실행합니다.")
		if sweeping and sweep_targets.is_empty():
			whistle_note = tr("효시 · 행동1 · 영향 칸에 적이 없음\n같은 칸을 다시 좌클릭하면 실행합니다.")
		elif sweeping:
			var whistle_chances: Array[String] = []
			for target: CombatUnit in sweep_targets:
				whistle_chances.append(CombatActionRules.save_chance_text(turns.current_unit, target, "whistle"))
			whistle_note = tr("효시 · 행동1 · 전투마다 1 · 의지 내성 성공률\n%s\n같은 칸을 다시 좌클릭하면 실행합니다.") % " · ".join(whistle_chances)
		hud.show_target_note(whistle_note)
	elif (selection.selected_action in CombatActionRules.OIL_ACTIONS and turns.current_unit != null and turns.current_unit.is_ally
			and not actions.busy):
		var oil_name: String = CombatActionRules.NAMES[selection.selected_action]
		hud.show_target_note(tr("%s · 보조 행동1 · 기름을 깔 칸을 좌클릭합니다.\n같은 칸을 다시 좌클릭하면 던집니다.") % oil_name
			if not actions.can_aim(turns.current_unit, selection.selected_action, selection.preview_cell)
			else tr("%s · 보조 행동1 · 십자 5칸 기름 3턴\n같은 칸을 다시 좌클릭하면 던집니다.") % oil_name)
	elif (selection.selected_action in ["trick_arrow", "firework_arrow"] and turns.current_unit != null
			and turns.current_unit.is_ally and not actions.busy):
		hud.show_target_note(_arrow_note(turns.current_unit, selection.selected_action, selection.preview_cell))
	var hovered: Dictionary = actions.floor_loot.item_at(_hover_cell)
	if (not hovered.is_empty() and selection.preview_target == null and selection.preview_prop == null
			and selection.preview_path.is_empty()
			and selection.selected_action not in ["jump", "sweep", "whistle", "oil_throw", "oil_bottle", "moving_shot", "trick_arrow", "firework_arrow"]):
		hud.show_move_mode(false)
		hud.show_target_note(tr("바닥 아이템 · %s") % CombatLoot.describe(hovered))
	if actions.is_over():
		hud.show_outcome(actions.is_victory())
		if not preparation.visible:
			hud.show_result(actions.is_victory(), progress.graduated, _enemy_turn_running or actions.busy)
	# 이어하기는 장면을 연 뒤에 정비 화면을 다시 열므로, 그 프레임이 끝난 마지막 상태로 곡을 고른다.
	_sync_music.call_deferred()
	queue_redraw()


## 두 화살의 안내 문구. 칸을 고르기 전에는 사용법을, 고른 뒤에는 확률과 맞는 유닛을 보인다.
func _arrow_note(actor: CombatUnit, action: String, cell: Vector2i) -> String:
	var name: String = CombatActionRules.NAMES[action]
	if not actions.can_aim(actor, action, cell):
		return tr("%s · 행동1 · 겨눌 칸을 좌클릭합니다.\n같은 칸을 다시 좌클릭하면 쏩니다.") % name
	if action == "trick_arrow":
		var note: String = tr("장난스러운 화살 · 행동1 · 삐끗 16.7% · 물 33.3% · 화염 50%")
		var target: CombatUnit = actions.grid.unit_at(cell)
		if target != null and target.hit_points > 0:
			var preview: CombatChecks.AttackPreview = actions.grid.attack_preview(actor, target, action)
			note += "\n" + tr("%s 명중률 %.1f%%") % [target.get_display_name(), preview.chance * 100.0]
			if target.is_ally:
				note += " · " + tr("아군")
		if actions.grid.is_tree(cell):
			note += "\n" + tr("화염이 나오면 나무가 타서 길이 열림")
		return note + "\n" + tr("같은 칸을 다시 좌클릭하면 쏩니다.")
	var chances: Array[String] = []
	for unit: CombatUnit in units:
		if unit.hit_points > 0 and unit.cell in actions.aim_area(actor, action, cell):
			chances.append("%s %.1f%%" % [unit.get_display_name(), CombatActionRules.save_chance(actor, unit, action) * 100.0])
	var firework: String = tr("폭죽 화살 · 행동1 · 막당 1 · 아군과 자신도 맞음\n민첩 내성 성공률: %s\n같은 칸을 다시 좌클릭하면 쏩니다.") % (
		" · ".join(chances) if not chances.is_empty() else tr("대상 없음"))
	if actions.aim_area(actor, action, cell).any(func(area_cell: Vector2i) -> bool: return actions.grid.is_tree(area_cell)):
		firework += "\n" + tr("나무가 타서 길이 열림")
	return firework


func _attack_targets_from(cell: Vector2i) -> Array[CombatUnit]:
	var targets: Array[CombatUnit] = []
	for unit: CombatUnit in units:
		if actions.can_target(turns.current_unit, unit, "attack", cell):
			targets.append(unit)
	return targets
