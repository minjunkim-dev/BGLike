class_name CombatActions
extends RefCounted
## 아군과 적 AI가 함께 쓰는 동작 실행과 반응 대기.

signal changed
signal logged(message: String)
signal feedback(unit: CombatUnit, text: String)
signal hit_landed
signal reaction_requested(kind: String, prompt: String)
signal reaction_decided(use_reaction: bool)

class RockStep extends RefCounted:
	var cell: Vector2i
	var target: CombatUnit
	var damage: int = 0
	var push: bool = false
	var push_cell: Vector2i
	var advance: bool = true
	var destroyed: bool = false
	var reason: String = ""


class RockRoll extends RefCounted:
	var direction: Vector2i = Vector2i.ZERO
	var cells: Array[Vector2i] = []
	var steps: Array[RockStep] = []
	var collisions: Array[CombatUnit] = []
	var stop_cell: Vector2i
	var destroyed: bool = false
	var reason: String = "최대3칸"


class Ground extends RefCounted:
	var source: CombatUnit
	var cell: Vector2i
	var kind: String
	var turns_left: int
	var entered: Array[CombatUnit] = []

	func _init(caster: CombatUnit, position: Vector2i, effect: String) -> void:
		source = caster
		cell = position
		kind = effect
		turns_left = 2 if kind == "burn" else 4


var grid: CombatGrid = CombatGrid.new()
var units: Array[CombatUnit]:
	get:
		return grid.units
var turns: CombatTurns
var dice: CombatDice = CombatDice.new()
var busy: bool = false
var pending_reactor: CombatUnit
var pending_kind: String = ""
var last_attack: CombatChecks.RollResult
var last_damage_rolls: Array[int] = []
var last_damage: int = 0
var movement_animation: Callable
var jump_animation: Callable
var attack_animation: Callable
var _grounds: Array[Ground] = []
var _revision: int = 0


func initialize(combat_units: Array[CombatUnit], combat_turns: CombatTurns) -> void:
	_revision += 1
	if turns != null and turns.turn_started.is_connected(_on_turn_started):
		turns.turn_started.disconnect(_on_turn_started)
	# 소환과 전투 불능 이후에도 현재 유닛 배열을 그대로 조회한다.
	grid.units = combat_units
	grid.props.clear()
	_grounds.clear()
	turns = combat_turns
	turns.turn_started.connect(_on_turn_started)
	dice.randomize()


func create_prop(cell: Vector2i, kind: String) -> CombatGrid.Prop:
	if (kind not in ["crate", "rock"] or not grid.is_floor(cell) or grid.is_blocked(cell)
		or grid.unit_at(cell) != null or grid.prop_at(cell) != null):
		return null
	var prop: CombatGrid.Prop = CombatGrid.Prop.new(cell, kind)
	grid.props.append(prop)
	changed.emit()
	return prop


func get_props() -> Array[CombatGrid.Prop]:
	return grid.props.duplicate()


func can_attack_prop(actor: CombatUnit, prop: CombatGrid.Prop) -> bool:
	if (not is_instance_valid(actor) or turns == null or actor not in units
		or not _can_act(actor) or turns.is_turn_finished(actor) or actor.action_left <= 0
		or not CombatActionRules.belongs_to(actor, "attack")
		or prop == null or prop not in grid.props or prop.hit_points <= 0):
		return false
	return (grid.in_range(actor.cell, prop.cell, actor.get_attack_range())
		and (actor.get_attack_range() > 1 or grid.are_adjacent(actor.cell, prop.cell)))


func attack_prop(actor: CombatUnit, prop: CombatGrid.Prop) -> bool:
	if not can_attack_prop(actor, prop):
		return false
	busy = true
	actor.spend_resource(CombatUnit.TurnResource.ACTION)
	last_damage_rolls.clear()
	if prop.kind == "rock":
		last_damage = 0
		_roll_rock(actor, prop)
		busy = false
		changed.emit()
		return true
	var sides: int = actor.get_damage_sides()
	if sides > 0:
		last_damage_rolls.append(dice.roll(sides))
	if (prop not in grid.props or not is_instance_valid(actor) or actor not in units
		or actor.hit_points <= 0 or is_over()):
		busy = false
		changed.emit()
		return false
	last_damage = actor.get_damage_bonus()
	for rolled: int in last_damage_rolls:
		last_damage += rolled
	last_damage = maxi(1, last_damage)
	prop.hit_points = maxi(0, prop.hit_points - last_damage)
	if prop.hit_points == 0:
		grid.props.erase(prop)
	var message: String = "%s 나무 상자 공격: %d, %d · 피해 %d · 내구도 %d/6%s" % [
		actor.get_display_name(), prop.cell.x, prop.cell.y, last_damage, prop.hit_points,
		" · 파괴" if prop.hit_points == 0 else ""]
	hit_landed.emit()
	logged.emit(message)
	busy = false
	changed.emit()
	return true


func preview_rock(actor: CombatUnit, prop: CombatGrid.Prop) -> RockRoll:
	var roll: RockRoll = RockRoll.new()
	if (not is_instance_valid(actor) or prop == null or prop not in grid.props
		or prop.kind != "rock" or prop.hit_points <= 0):
		roll.reason = "대상 없음"
		return roll
	var offset: Vector2i = prop.cell - actor.cell
	roll.direction = (Vector2i(signi(offset.x), 0) if absi(offset.x) >= absi(offset.y)
		else Vector2i(0, signi(offset.y)))
	if roll.direction == Vector2i.ZERO:
		roll.reason = "방향 없음"
		return roll
	return _trace_rock(prop, roll.direction, 3, [])


func _trace_rock(prop: CombatGrid.Prop, direction: Vector2i, limit: int,
		damaged: Array[CombatUnit]) -> RockRoll:
	var roll: RockRoll = RockRoll.new()
	roll.direction = direction
	var struck: Array[CombatUnit] = damaged.duplicate()
	var positions: Dictionary[CombatUnit, Vector2i] = {}
	var health: Dictionary[CombatUnit, int] = {}
	for unit: CombatUnit in units:
		if unit.hit_points > 0:
			positions[unit] = unit.cell
			health[unit] = unit.hit_points
	var cell: Vector2i = prop.cell
	for index: int in range(limit):
		var step: RockStep = RockStep.new()
		var next: Vector2i = cell + direction
		step.cell = next
		roll.stop_cell = next
		if not grid.is_inside(next):
			step.advance = false
			step.reason = "맵 경계"
		elif grid.is_blocked(next):
			step.advance = false
			step.reason = "물체" if grid.prop_at(next) != null else "장벽"
		elif grid.height_at(next) > grid.height_at(cell):
			step.advance = false
			step.reason = "오르막"
		elif grid.pits.has(next) or grid.height_at(cell) - grid.height_at(next) >= 2:
			step.destroyed = true
			step.reason = "낭떠러지 소멸" if grid.pits.has(next) else "높이 차2 파괴"
		else:
			for target: CombatUnit in positions:
				if positions[target] == next and health[target] > 0:
					step.target = target
					break
			if step.target != null:
				var target: CombatUnit = step.target
				if target not in struck:
					struck.append(target)
					step.damage = 4
					health[target] = maxi(0, health[target] - 4)
				if target not in roll.collisions:
					roll.collisions.append(target)
				if health[target] > 0:
					var destination: Vector2i = next + direction
					var blocked: bool = (not grid.is_inside(destination) or grid.is_blocked(destination)
						or grid.height_at(destination) > grid.height_at(next))
					for other: CombatUnit in positions:
						if other != target and health[other] > 0 and positions[other] == destination:
							blocked = true
					if blocked:
						step.advance = false
						step.reason = "밀기 막힘"
					else:
						step.push = true
						step.push_cell = destination
						positions[target] = destination
						var fall: int = _fall_damage_from(target, next, destination)
						health[target] = 0 if grid.pits.has(destination) else maxi(0, health[target] - fall)
				if health[target] == 0:
					var side_alive: bool = false
					for other: CombatUnit in health:
						if other.is_ally == target.is_ally and health[other] > 0:
							side_alive = true
					if not side_alive:
						step.advance = false
						step.reason = "전투 종료"
		roll.steps.append(step)
		if step.advance:
			roll.cells.append(next)
			cell = next
		if step.destroyed or not step.advance:
			roll.destroyed = step.destroyed
			roll.reason = step.reason
			break
	return roll


func _roll_rock(actor: CombatUnit, prop: CombatGrid.Prop) -> void:
	var direction: Vector2i = preview_rock(actor, prop).direction
	var struck: Array[CombatUnit] = []
	for index: int in range(3):
		var origin: Vector2i = prop.cell
		if not _can_continue_rock(actor, prop, origin) or is_over():
			return
		var step: RockStep = _trace_rock(prop, direction, 1, struck).steps[0]
		if step.target != null and step.damage > 0:
			var target: CombatUnit = step.target
			struck.append(target)
			_damage(target, step.damage)
			if not _can_continue_rock(actor, prop, origin) or not is_instance_valid(target) or target not in units:
				return
			logged.emit("%s 바위 충돌: 피해4 · HP %d" % [target.get_display_name(), target.hit_points])
			if not _can_continue_rock(actor, prop, origin) or not is_instance_valid(target) or target not in units:
				return
			if is_over():
				logged.emit("바위 정지: 전투 종료")
				return
			step = _trace_rock(prop, direction, 1, struck).steps[0]
			if step.damage > 0:
				return
		if step.push:
			var target: CombatUnit = step.target
			_land(target, step.push_cell)
			if not _can_continue_rock(actor, prop, origin) or not is_instance_valid(target) or target not in units:
				return
			if is_over():
				logged.emit("바위 정지: 전투 종료")
				return
			step = _trace_rock(prop, direction, 1, struck).steps[0]
			if step.damage > 0:
				return
		if step.advance:
			prop.cell = step.cell
		if step.destroyed:
			prop.hit_points = 0
			grid.props.erase(prop)
		logged.emit("바위 %s: %d, %d" % [step.reason if not step.reason.is_empty() else "이동",
			prop.cell.x, prop.cell.y])
		if step.destroyed or not step.advance:
			return
		if not _can_continue_rock(actor, prop, step.cell) or is_over():
			return
	logged.emit("바위 정지: 최대3칸")


func _can_continue_rock(actor: CombatUnit, prop: CombatGrid.Prop, cell: Vector2i) -> bool:
	return (prop in grid.props and prop.hit_points > 0 and prop.cell == cell and is_instance_valid(actor)
		and actor in units and actor.hit_points > 0 and turns.current_unit == actor)


func _on_turn_started(unit: CombatUnit) -> void:
	var ground_messages: Array[String] = []
	for ground: Ground in _grounds.duplicate():
		if ground not in _grounds:
			continue
		ground.entered.erase(unit)
		if ground.source == unit:
			ground.turns_left -= 1
			if ground.turns_left == 0:
				_grounds.erase(ground)
				ground_messages.append("%s %s 장판 만료: %d, %d" % [unit.get_display_name(),
					"불" if ground.kind == "burn" else "독", ground.cell.x, ground.cell.y])
	for target: CombatUnit in units:
		if target.stun_source == unit:
			target.is_stunned = false
		for effect: CombatUnit.StatusEffect in target.status_effects.duplicate():
			if effect.source == unit:
				effect.turns_left -= 1
				if effect.turns_left == 0:
					target.status_effects.erase(effect)
	for message: String in ground_messages:
		logged.emit(message)
	_clear_burn_in_water(unit)
	if unit.overloaded and unit.hit_points > 0 and not is_over():
		_damage(unit, 2)
		logged.emit("%s 과부하: 자기 피해 2 · HP %d" % [unit.get_display_name(), unit.hit_points])
		feedback.emit(unit, "과부하 -2")
	_apply_grounds(unit, false)
	var poison_checked: bool = false
	for effect: CombatUnit.StatusEffect in unit.status_effects.duplicate():
		if unit.hit_points <= 0 or is_over():
			break
		if effect not in unit.status_effects:
			continue
		var name: String = "화상" if effect.kind == "burn" else "독"
		if effect.kind == "poison" and not poison_checked:
			poison_checked = true
			var constitution: int = unit.get_attribute(CombatUnit.Attribute.CONSTITUTION)
			var saved: CombatChecks.RollResult = CombatChecks.saving_throw(constitution, effect.save_dc, dice)
			logged.emit("%s 독 건강 내성: d20 %d + %d = %d / DC %d · %s" % [unit.get_display_name(),
				saved.selected_roll, constitution, saved.total, effect.save_dc, "성공" if saved.success else "실패"])
			feedback.emit(unit, "독 내성 %d" % saved.total)
			if unit.hit_points <= 0 or is_over():
				break
			if effect not in unit.status_effects:
				continue
			if saved.success:
				unit.status_effects.erase(effect)
				continue
		var amount: int = dice.roll(4) if effect.kind == "burn" else 1
		_damage(unit, amount)
		logged.emit("%s %s: %d · HP %d" % [unit.get_display_name(), name, amount, unit.hit_points])
		feedback.emit(unit, "%s -%d" % [name, amount])
	changed.emit()


func apply_status(source: CombatUnit, target: CombatUnit, kind: String) -> bool:
	if (not is_instance_valid(source) or not is_instance_valid(target)
		or source not in units or target not in units or source.hit_points <= 0 or target.hit_points <= 0
		or kind not in ["stun", "burn", "poison"]):
		return false
	if kind == "burn" and target.cell in grid.water_cells:
		return false
	if kind == "stun":
		if target.is_boss():
			return false
		target.is_stunned = true
		target.stun_source = source
	else:
		if target.get_status_count(kind) >= 3:
			return false
		target.status_effects.append(CombatUnit.StatusEffect.new(kind, source, 2 if kind == "burn" else 4))
	changed.emit()
	return true


func get_grounds() -> Array[Ground]:
	return _grounds.duplicate()


func create_ground(source: CombatUnit, cell: Vector2i, kind: String) -> bool:
	if (not is_instance_valid(source) or source not in units or source.hit_points <= 0
		or kind not in ["burn", "poison"] or not grid.is_floor(cell) or grid.is_blocked(cell)):
		return false
	var refreshed: bool = false
	var owner: CombatUnit = source
	for ground: Ground in _grounds:
		if ground.cell == cell and ground.kind == kind:
			ground.turns_left = 2 if kind == "burn" else 4
			owner = ground.source
			refreshed = true
			break
	if not refreshed:
		_grounds.append(Ground.new(source, cell, kind))
	logged.emit("%s %s 장판 %s: %d, %d" % [owner.get_display_name(),
		"불" if kind == "burn" else "독", "갱신" if refreshed else "생성", cell.x, cell.y])
	changed.emit()
	return true


## 살아 있는 유닛이 이 대상을 표식으로 지정했는지.
func is_marked(target: CombatUnit) -> bool:
	for source: CombatUnit in units:
		if source.hit_points > 0 and source.marked_target == target:
			return true
	return false


## 남은 적이 없으면 승리다.
func is_victory() -> bool:
	for unit: CombatUnit in units:
		if not unit.is_ally and unit.hit_points > 0:
			return false
	return true


## 전투 불능 전환. 표식, 턴 순서와 표시를 함께 정리한다.
func incapacitate(target: CombatUnit) -> void:
	var revision: int = _revision
	target.hit_points = 0
	target.status_effects.clear()
	var ground_messages: Array[String] = []
	for ground: Ground in _grounds.duplicate():
		ground.entered.erase(target)
		if ground.source == target:
			_grounds.erase(ground)
			ground_messages.append("%s %s 장판 해제: %d, %d" % [target.get_display_name(),
				"불" if ground.kind == "burn" else "독", ground.cell.x, ground.cell.y])
	for unit: CombatUnit in units:
		if unit.marked_target == target:
			unit.marked_target = null
		if unit.stun_source == target:
			unit.is_stunned = false
		for effect: CombatUnit.StatusEffect in unit.status_effects.duplicate():
			if effect.source == target:
				unit.status_effects.erase(effect)
	for message: String in ground_messages:
		logged.emit(message)
		if not _same_combat(target, revision):
			return
	if not _same_combat(target, revision):
		return
	turns.remove_unit(target)
	if not _same_combat(target, revision):
		return
	target.visible = false


func is_over() -> bool:
	var ally: bool = false
	var enemy: bool = false
	for unit: CombatUnit in units:
		if unit.hit_points > 0:
			ally = ally or unit.is_ally
			enemy = enemy or not unit.is_ally
	return not ally or not enemy


## 이번 턴에 도착할 수 있는 칸과 이동 비용. 현재 칸과 점유 칸은 빠진다.
func reachable_cells(actor: CombatUnit) -> Dictionary[Vector2i, int]:
	if not _can_act(actor):
		return {}
	return grid.reachable_cells(actor)


func can_move(actor: CombatUnit, destination: Vector2i) -> bool:
	return reachable_cells(actor).has(destination)


func jump_cells(actor: CombatUnit) -> Dictionary[Vector2i, int]:
	var cells: Dictionary[Vector2i, int] = {}
	if not _can_act(actor) or actor.bonus_action_left <= 0:
		return cells
	for x: int in range(-2, 3):
		for y: int in range(-2, 3):
			var destination: Vector2i = actor.cell + Vector2i(x, y)
			var path: Array[Vector2i] = grid.jump_path(actor, destination)
			if path.is_empty():
				continue
			var cost: int = path.size() + maxi(grid.height_at(destination) - grid.height_at(actor.cell), 0)
			if cost <= actor.movement_left:
				cells[destination] = cost
	return cells


func jump_to(actor: CombatUnit, destination: Vector2i) -> bool:
	var cells: Dictionary[Vector2i, int] = jump_cells(actor)
	if not cells.has(destination):
		return false
	busy = true
	changed.emit()
	for reactor: CombatUnit in jump_reactors(actor, destination):
		var chance: float = grid.attack_preview(reactor, actor).chance
		if await _ask_reaction(reactor, "opportunity", "%s가 벗어납니다. 기회 공격할까요? (명중률 %.1f%%)" % [actor.get_display_name(), chance * 100.0]):
			reactor.spend_resource(CombatUnit.TurnResource.REACTION)
			if not reactor.is_ally:
				logged.emit("%s 기회 공격: 반응 사용" % reactor.get_display_name())
			await _perform_attack(reactor, actor, false)
		if actor.hit_points <= 0:
			break
	if actor.hit_points <= 0:
		_finish()
		return true
	actor.spend_movement(cells[destination])
	actor.spend_resource(CombatUnit.TurnResource.BONUS_ACTION)
	if jump_animation.is_valid():
		await jump_animation.call(actor, destination)
	_land(actor, destination)
	logged.emit("%s 점프: 이동 %d, 보조 행동1 · 남은 이동 %d" % [
		actor.get_display_name(), cells[destination], actor.movement_left])
	_finish()
	return true


func jump_reactors(actor: CombatUnit, destination: Vector2i) -> Array[CombatUnit]:
	var reactors: Array[CombatUnit] = []
	if actor == null or actor.disengaged:
		return reactors
	for reactor: CombatUnit in units:
		if (reactor.hit_points > 0 and not reactor.is_stunned and reactor.is_ally != actor.is_ally
			and CombatActionRules.belongs_to(reactor, "opportunity") and reactor.reaction_left > 0
			and grid.leaves_reach(reactor, actor.cell, destination)):
			reactors.append(reactor)
	return reactors


func fall_damage(actor: CombatUnit, destination: Vector2i) -> int:
	return _fall_damage_from(actor, actor.cell, destination)


func _fall_damage_from(actor: CombatUnit, origin: Vector2i, destination: Vector2i) -> int:
	var drop: int = grid.height_at(origin) - grid.height_at(destination)
	return ceili((drop - 2) * actor.get_max_hit_points() * 0.15) if drop >= 3 else 0


func can_target(actor: CombatUnit, target: CombatUnit, action: String,
	from_cell: Vector2i = Vector2i(-1, -1)) -> bool:
	if (actor == null or target == null or target.hit_points <= 0
		or (actor.is_ally == target.is_ally and action != "shove")
		or not CombatActionRules.belongs_to(actor, action) or not grid.can_target(actor, target, action, from_cell)):
		return false
	match action:
		"attack":
			return actor.action_left > 0
		"shock":
			return (CombatActionRules.has_uses(actor, action) and actor.action_left > 0
				and actor.get_save_dc() > 0)
		"mark":
			return CombatActionRules.has_uses(actor, action) and actor.bonus_action_left > 0
		"shove":
			return actor.bonus_action_left > 0
		"pull":
			return actor.action_left > 0 and actor.pull_cooldown == 0
	return false


func can_use(actor: CombatUnit, action: String) -> bool:
	if not _can_act(actor):
		return false
	match action:
		"spin":
			return (CombatActionRules.belongs_to(actor, action) and actor.action_left > 0
				and not grid.opponents_in_area(actor, 1).is_empty())
		"spawn":
			return (CombatActionRules.has_uses(actor, action) and actor.action_left > 0
				and actor in turns.ordered_units and not grid.empty_neighbors(actor.cell).is_empty())
		"move":
			return not reachable_cells(actor).is_empty()
		"jump":
			return not jump_cells(actor).is_empty()
		"attack", "shock", "mark", "shove", "pull":
			for target: CombatUnit in units:
				if can_target(actor, target, action):
					return true
			if action == "attack":
				for prop: CombatGrid.Prop in grid.props:
					if can_attack_prop(actor, prop):
						return true
		"second_wind", "potion":
			return (CombatActionRules.has_uses(actor, action) and actor.bonus_action_left > 0
				and actor.hit_points < actor.get_max_hit_points())
		"surge":
			return (CombatActionRules.has_uses(actor, action) and actor.bonus_action_left > 0
				and actor.action_left == 0)
		"disengage":
			return (CombatActionRules.has_uses(actor, action) and actor.bonus_action_left > 0
				and not actor.disengaged and actor.movement_left > 0)
	return false


func has_available_action(actor: CombatUnit) -> bool:
	if not _can_act(actor):
		return false
	if actor.movement_left > 0 and not reachable_cells(actor).is_empty():
		return true
	for group: Array in CombatActionRules.GROUPS.slice(0, 2):
		for action: String in group:
			if can_use(actor, action):
				return true
	return false


## 아군 조작 화면에 보일 사용 불가 이유. 빈 문자열이면 지금 쓸 수 있다.
func unavailable_reason(actor: CombatUnit, action: String) -> String:
	var resource: CombatUnit.TurnResource = CombatActionRules.resource_of(action)
	var reaction: bool = resource == CombatUnit.TurnResource.REACTION
	if is_over() or (busy and not reaction):
		return "전투 입력 잠금"
	if not reaction and (actor != turns.current_unit or not actor.is_ally):
		return "아군의 자기 턴에만 사용"
	if CombatActionRules.uses_left(actor, action) == 0:
		return "보유 물약 없음" if action == "potion" else "이번 막의 횟수를 모두 씀"
	if [actor.action_left, actor.bonus_action_left, actor.reaction_left][resource] == 0:
		return "자원을 이미 씀"
	if reaction:
		if actor.hit_points <= 0:
			return "전투 불능"
		return "기절 상태" if actor.is_stunned else ""
	if action in ["second_wind", "potion"] and actor.hit_points == actor.get_max_hit_points():
		return "HP가 이미 최대"
	if action == "surge" and actor.action_left > 0:
		return "행동이 아직 남아 있음"
	if not can_use(actor, action):
		return "이동이 없거나 이미 효과 적용 중" if action == "disengage" else "사거리 또는 대상 조건을 확인"
	return ""


func move_to(actor: CombatUnit, destination: Vector2i) -> bool:
	if not can_move(actor, destination):
		return false
	var path: Array[Vector2i] = grid.path_to(actor, destination)
	busy = true
	changed.emit()
	var moved: int = 0
	for step: Vector2i in path:
		if actor.hit_points <= 0 or is_over():
			break
		if not actor.disengaged:
			for reactor: CombatUnit in units:
				if (reactor.hit_points > 0 and not reactor.is_stunned and reactor.is_ally != actor.is_ally
					and CombatActionRules.belongs_to(reactor, "opportunity") and reactor.reaction_left > 0
					and grid.leaves_reach(reactor, actor.cell, step)):
					var chance: float = grid.attack_preview(reactor, actor).chance
					if await _ask_reaction(reactor, "opportunity", "%s가 벗어납니다. 기회 공격할까요? (명중률 %.1f%%)" % [actor.get_display_name(), chance * 100.0]):
						reactor.spend_resource(CombatUnit.TurnResource.REACTION)
						if not reactor.is_ally:
							logged.emit("%s 기회 공격: 반응 사용" % reactor.get_display_name())
						await _perform_attack(reactor, actor, false)
					if actor.hit_points <= 0:
						break
		if actor.hit_points <= 0:
			break
		if movement_animation.is_valid():
			await movement_animation.call(actor, step)
		actor.spend_movement(1)
		actor.cell = step
		_clear_burn_in_water(actor)
		_apply_grounds(actor, true)
		moved += 1
		changed.emit()
	logged.emit("%s 이동: %d칸, 남은 이동 %d" % [actor.get_display_name(), moved, actor.movement_left])
	_finish()
	return true


func attack(actor: CombatUnit, target: CombatUnit, shock: bool = false) -> bool:
	var action: String = "shock" if shock else "attack"
	if not _can_act(actor) or not can_target(actor, target, action):
		return false
	busy = true
	actor.spend_resource(CombatUnit.TurnResource.ACTION)
	if shock:
		CombatActionRules.spend_use(actor, action)
	changed.emit()
	await _perform_attack(actor, target, shock)
	_finish()
	return true


func spin(actor: CombatUnit) -> bool:
	if not can_use(actor, "spin"):
		return false
	var targets: Array[CombatUnit] = grid.opponents_in_area(actor, 1)
	busy = true
	actor.spend_resource(CombatUnit.TurnResource.ACTION)
	logged.emit("%s 회전회오리: 인접 대상 %d명" % [actor.get_display_name(), targets.size()])
	changed.emit()
	for target: CombatUnit in targets:
		if actor.hit_points <= 0 or actor.is_stunned or actor != turns.current_unit or is_over():
			break
		if target.hit_points > 0 and target.cell in grid.area_cells(actor.cell, 1):
			await _perform_attack(actor, target, false)
	_finish()
	return true


func spawn_spiderling(actor: CombatUnit) -> bool:
	if not can_use(actor, "spawn"):
		return false
	var cells: Array[Vector2i] = grid.empty_neighbors(actor.cell)
	var child: CombatUnit = (preload("res://scenes/combat/unit.tscn") as PackedScene).instantiate() as CombatUnit
	child.kind = CombatUnit.Kind.SPIDERLING
	child.is_ally = false
	child.start_cell = cells[dice.roll(cells.size()) - 1]
	child.cell = child.start_cell
	child.hit_points = child.get_max_hit_points()
	busy = true
	if actor.get_parent() != null:
		actor.get_parent().add_child(child)
	units.append(child)
	if not turns.insert_before(child, actor):
		units.erase(child)
		child.free()
		busy = false
		return false
	actor.spend_resource(CombatUnit.TurnResource.ACTION)
	logged.emit("%s 새끼 낳기: %s" % [actor.get_display_name(), child.cell])
	_finish()
	return true


func use_self(actor: CombatUnit, action: String) -> bool:
	if not can_use(actor, action) or action not in CombatActionRules.SELF_TARGET:
		return false
	actor.spend_resource(CombatUnit.TurnResource.BONUS_ACTION)
	CombatActionRules.spend_use(actor, action)
	match action:
		"second_wind":
			_heal(actor, dice.roll(10) + 1, "숨 고르기")
		"surge":
			actor.action_left = 1
			logged.emit("%s 몰아치기: 행동 회복" % actor.get_display_name())
		"disengage":
			actor.disengaged = true
			logged.emit("%s 물러서며 쏘기: 이번 턴 이동은 기회 공격 제외" % actor.get_display_name())
		"potion":
			_heal(actor, dice.roll(4) + dice.roll(4) + 2, "물약")
	changed.emit()
	return true


func mark(actor: CombatUnit, target: CombatUnit) -> bool:
	if not _can_act(actor) or not can_target(actor, target, "mark"):
		return false
	actor.spend_resource(CombatUnit.TurnResource.BONUS_ACTION)
	CombatActionRules.spend_use(actor, "mark")
	actor.marked_target = target
	logged.emit("%s 표식: %s" % [actor.get_display_name(), target.get_display_name()])
	changed.emit()
	return true


func pull(actor: CombatUnit, target: CombatUnit) -> bool:
	if not _can_act(actor) or not can_target(actor, target, "pull"):
		return false
	actor.spend_resource(CombatUnit.TurnResource.ACTION)
	actor.pull_cooldown = 2
	var result: CombatChecks.ContestResult = CombatChecks.contest(
		actor.get_attribute(CombatUnit.Attribute.STRENGTH),
		maxi(target.get_attribute(CombatUnit.Attribute.STRENGTH), target.get_dexterity()), dice)
	if result.attacker_wins:
		var cells: Array[Vector2i] = grid.pull_cells(actor, target)
		_land(target, cells[0] if cells.size() == 1 else cells[dice.roll(cells.size()) - 1])
	logged.emit("%s 만능팔: %d + %d = %d / %d + %d = %d · %s" % [
		actor.get_display_name(), result.attacker_roll,
		actor.get_attribute(CombatUnit.Attribute.STRENGTH), result.attacker_total,
		result.defender_roll, maxi(target.get_attribute(CombatUnit.Attribute.STRENGTH), target.get_dexterity()),
		result.defender_total, "성공" if result.attacker_wins else "실패"])
	feedback.emit(target, "끌어옴" if result.attacker_wins else "만능팔 저항")
	changed.emit()
	return true


func shove(actor: CombatUnit, target: CombatUnit) -> bool:
	if not _can_act(actor) or not can_target(actor, target, "shove"):
		return false
	actor.spend_resource(CombatUnit.TurnResource.BONUS_ACTION)
	var won: bool = target.is_stunned or actor.is_ally == target.is_ally
	if not won:
		var result: CombatChecks.ContestResult = CombatChecks.contest(
			actor.get_attribute(CombatUnit.Attribute.STRENGTH),
			maxi(target.get_attribute(CombatUnit.Attribute.STRENGTH), target.get_dexterity()), dice)
		won = result.attacker_wins
		feedback.emit(actor, "밀치기 %d" % result.attacker_total)
		feedback.emit(target, "저항 %d" % result.defender_total)
		logged.emit("밀치기 대결: %d + %d = %d / %d + %d = %d" % [
			result.attacker_roll, actor.get_attribute(CombatUnit.Attribute.STRENGTH), result.attacker_total,
			result.defender_roll, maxi(target.get_attribute(CombatUnit.Attribute.STRENGTH), target.get_dexterity()), result.defender_total])
	if won:
		_land(target, grid.push_destination(actor.cell, target.cell))
	logged.emit("밀치기 %s" % ("성공" if won else "실패"))
	changed.emit()
	return true


func resolve_reaction(use_reaction: bool) -> bool:
	if pending_reactor == null:
		return false
	# 중복 클릭은 같은 반응을 두 번 소비하지 않는다.
	var reactor: CombatUnit = pending_reactor
	pending_reactor = null
	reaction_decided.emit(use_reaction and reactor.hit_points > 0 and not reactor.is_stunned)
	return true


func _can_act(actor: CombatUnit) -> bool:
	return (actor != null and actor == turns.current_unit and actor.hit_points > 0
		and not actor.is_stunned and not busy and not is_over())


func _ask_reaction(reactor: CombatUnit, kind: String, prompt: String) -> bool:
	if not reactor.is_ally:
		return true
	pending_reactor = reactor
	pending_kind = kind
	_emit_reaction.call_deferred(kind, prompt)
	var accepted: bool = await reaction_decided
	logged.emit("%s %s: %s" % [reactor.get_display_name(),
		"기회 공격" if kind == "opportunity" else "흘려내기", "사용" if accepted else "넘기기"])
	pending_kind = ""
	return accepted


func _emit_reaction(kind: String, prompt: String) -> void:
	reaction_requested.emit(kind, prompt)


func _perform_attack(actor: CombatUnit, target: CombatUnit, shock: bool) -> void:
	var save_dc: int = actor.get_save_dc()
	if attack_animation.is_valid():
		await attack_animation.call(actor, target)
	if actor.hit_points <= 0 or target.hit_points <= 0 or is_over():
		return
	var preview: CombatChecks.AttackPreview = grid.attack_preview(actor, target)
	last_attack = CombatChecks.attack(actor.get_attack_bonus(), target.get_armor_class(), preview.mode, dice)
	last_damage = 0
	last_damage_rolls.clear()
	var mode_name: String = "일반"
	if last_attack.mode == CombatChecks.RollMode.ADVANTAGE:
		mode_name = "유리"
	elif last_attack.mode == CombatChecks.RollMode.DISADVANTAGE:
		mode_name = "불리"
	logged.emit("%s 공격(%s): d20 %s + %d = %d / AC %d · %s" % [actor.get_display_name(), mode_name,
		str(last_attack.rolls), actor.get_attack_bonus(), last_attack.total, target.get_armor_class(),
		"치명타" if last_attack.critical else "명중" if last_attack.success else "빗나감"])
	feedback.emit(actor, "공격 %d" % last_attack.total)
	if not last_attack.success:
		feedback.emit(target, "빗나감")
		return
	if (save_dc > 0 and CombatActionRules.has_uses(target, "parry") and not target.is_stunned
		and target.reaction_left > 0):
		var success_rolls: int = clampi(21 + target.get_dexterity() - save_dc, 0, 20)
		if await _ask_reaction(target, "parry", "%s가 공격에 맞았습니다. 흘려낼까요? (성공률 %.1f%%, 남은 횟수 %d)" % [target.get_display_name(), success_rolls * 5.0, target.parry_left]):
			target.spend_resource(CombatUnit.TurnResource.REACTION)
			CombatActionRules.spend_use(target, "parry")
			var saved: CombatChecks.RollResult = CombatChecks.saving_throw(target.get_dexterity(), save_dc, dice)
			logged.emit("흘려내기: d20 %d + %d = %d / DC %d · %s" % [saved.selected_roll,
				target.get_dexterity(), saved.total, save_dc, "성공" if saved.success else "실패"])
			feedback.emit(target, "흘려내기 %d" % saved.total)
			if saved.success:
				feedback.emit(target, "흘려내기")
				return
	var count: int = 2 if last_attack.critical else 1
	var sides: int = actor.get_damage_sides()
	if sides > 0:
		for index: int in range(count):
			last_damage_rolls.append(dice.roll(sides))
	var has_mark_damage: bool = actor.marked_target == target
	if has_mark_damage:
		for index: int in range(count):
			last_damage_rolls.append(dice.roll(6))
	var damage_bonus: int = actor.get_damage_bonus()
	last_damage = damage_bonus
	for rolled: int in last_damage_rolls:
		last_damage += rolled
	_damage(target, last_damage)
	logged.emit("%s 피해%s: %s + %d = %d · HP %d" % [target.get_display_name(),
		" (표식 추가)" if has_mark_damage else "",
		str(last_damage_rolls), damage_bonus, last_damage, target.hit_points])
	feedback.emit(target, "-%d" % last_damage)
	if shock and target.hit_points > 0 and target.is_boss():
		logged.emit("%s 기절 면역" % target.get_display_name())
		feedback.emit(target, "기절 면역")
		return
	if shock and target.hit_points > 0:
		var saved: CombatChecks.RollResult = CombatChecks.saving_throw(
			target.get_attribute(CombatUnit.Attribute.MENTAL), save_dc, dice)
		if not saved.success:
			apply_status(actor, target, "stun")
		logged.emit("정신 내성: d20 %d + %d = %d / DC %d · %s" % [saved.selected_roll,
			target.get_attribute(CombatUnit.Attribute.MENTAL), saved.total, save_dc,
			"기절" if not saved.success else "버팀"])
		feedback.emit(target, "정신 내성 %d" % saved.total)


func _apply_grounds(unit: CombatUnit, entering: bool) -> void:
	for ground: Ground in _grounds.duplicate():
		if not is_instance_valid(unit) or unit.hit_points <= 0 or is_over():
			break
		if (ground not in _grounds or ground.cell != unit.cell
			or not is_instance_valid(ground.source) or ground.source.hit_points <= 0):
			continue
		if entering:
			if unit in ground.entered:
				continue
			ground.entered.append(unit)
		if apply_status(ground.source, unit, ground.kind):
			logged.emit("%s %s 장판: %s 부여" % [unit.get_display_name(),
				"불" if ground.kind == "burn" else "독", "화상" if ground.kind == "burn" else "독"])


func _clear_burn_in_water(unit: CombatUnit) -> void:
	if unit.cell not in grid.water_cells or unit.get_status_count("burn") == 0:
		return
	var revision: int = _revision
	for effect: CombatUnit.StatusEffect in unit.status_effects.duplicate():
		if effect.kind == "burn":
			unit.status_effects.erase(effect)
	changed.emit()
	if not _same_combat(unit, revision):
		return
	logged.emit("%s 물: 화상 해제" % unit.get_display_name())
	if not _same_combat(unit, revision):
		return
	feedback.emit(unit, "물: 화상 해제")


func _land(target: CombatUnit, destination: Vector2i) -> void:
	var revision: int = _revision
	var amount: int = fall_damage(target, destination)
	target.cell = destination
	if grid.pits.has(destination):
		incapacitate(target)
		if not _same_combat(target, revision):
			return
		logged.emit("%s 낙사: 전투 불능" % target.get_display_name())
		if not _same_combat(target, revision):
			return
		feedback.emit(target, "낙사")
		return
	_clear_burn_in_water(target)
	if not _same_combat(target, revision):
		return
	if amount > 0:
		_damage(target, amount)
		if not _same_combat(target, revision):
			return
		# 낙하 피드백 전에 착지 위치와 HP를 화면에 반영한다.
		changed.emit()
		if not _same_combat(target, revision):
			return
		logged.emit("%s 낙하 피해: %d · HP %d" % [target.get_display_name(), amount, target.hit_points])
		if not _same_combat(target, revision):
			return
		feedback.emit(target, "-%d" % amount)
	if not _same_combat(target, revision):
		return
	_apply_grounds(target, true)


func _damage(target: CombatUnit, amount: int) -> void:
	var revision: int = _revision
	var before: int = target.hit_points
	target.hit_points = maxi(0, target.hit_points - amount)
	if target.hit_points < before:
		hit_landed.emit()
	if not _same_combat(target, revision):
		return
	if target.hit_points == 0:
		incapacitate(target)


func _same_combat(unit: CombatUnit, revision: int) -> bool:
	return revision == _revision and is_instance_valid(unit) and unit in units


func _heal(actor: CombatUnit, amount: int, name: String) -> void:
	var before: int = actor.hit_points
	actor.hit_points = mini(actor.get_max_hit_points(), actor.hit_points + amount)
	logged.emit("%s %s: HP +%d → %d" % [actor.get_display_name(), name, actor.hit_points - before, actor.hit_points])
	feedback.emit(actor, "+%d" % (actor.hit_points - before))


func _finish() -> void:
	busy = false
	changed.emit()
