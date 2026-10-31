class_name CombatActions
extends RefCounted
## 아군과 적 AI가 함께 쓰는 동작 실행과 반응 대기.

signal changed
signal logged(message: String)
signal feedback(unit: CombatUnit, text: String)
signal healed(unit: CombatUnit, amount: int)
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
	var reason: String = TranslationServer.tr("최대3칸")


class Ground extends RefCounted:
	## 독 장판 정의의 고정 DC (능력치 기획서 8장). 부여한 독이 이 값을 보존한다.
	const POISON_DC: int = 4
	var source: CombatUnit
	var cell: Vector2i
	var kind: String
	var turns_left: int
	var dc: int
	var entered: Array[CombatUnit] = []

	func _init(caster: CombatUnit, position: Vector2i, effect: String) -> void:
		source = caster
		cell = position
		kind = effect
		turns_left = 2 if kind == "burn" else 4
		dc = POISON_DC if kind == "poison" else 0


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
## 마지막 내성굴림. 회전회오리처럼 시전자가 굴리지 않는 동작의 대상 굴림이다.
var last_save: CombatChecks.RollResult
var last_damage_rolls: Array[int] = []
var last_damage: int = 0
var movement_animation: Callable
var jump_animation: Callable
var attack_animation: Callable
## 이번 적 턴에 아군이 답한 반응. 적 턴 중간 저장이 기록한다.
var reaction_answers: Array[bool] = []
## 이어하기가 다시 실행하는 적 턴에서 묻지 않고 차례로 쓸 반응 답.
var replay_answers: Array[bool] = []
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


## 이어하기용 상자·바위, 장판, 난수 상태. 유닛은 전투 유닛 목록의 번호로 적는다.
func save_state() -> Dictionary:
	var props: Array = []
	for prop: CombatGrid.Prop in grid.props:
		props.append([prop.kind, prop.cell, prop.hit_points])
	var grounds: Array = []
	for ground: Ground in _grounds:
		grounds.append([units.find(ground.source), ground.cell, ground.kind, ground.turns_left,
			ground.entered.map(func(unit: CombatUnit) -> int: return units.find(unit)), ground.dc])
	return {"props": props, "grounds": grounds, "dice": dice.state}


## save_state()의 값으로 되돌린다. initialize() 뒤에 부르고, is_valid_state()를 먼저 확인한다.
func load_state(data: Dictionary) -> void:
	grid.props.clear()
	for saved: Array in data.props:
		var prop: CombatGrid.Prop = CombatGrid.Prop.new(saved[1], saved[0])
		prop.hit_points = saved[2]
		grid.props.append(prop)
	_grounds.clear()
	for saved: Array in data.grounds:
		var ground: Ground = Ground.new(units[saved[0]], saved[1], saved[2])
		ground.turns_left = saved[3]
		ground.dc = saved[5]
		for index: int in saved[4]:
			ground.entered.append(units[index])
		_grounds.append(ground)
	dice.state = data.dice


## 저장 파일의 값을 load_state()에 넘겨도 되는지. count는 전투 유닛 수다.
static func is_valid_state(data: Variant, count: int, map_size: Vector2i) -> bool:
	var area: Rect2i = Rect2i(Vector2i.ZERO, map_size)
	if not (data is Dictionary and data.get("dice") is int and data.get("props") is Array
			and data.props.size() <= area.get_area() and data.get("grounds") is Array
			and data.grounds.size() <= area.get_area() * 2):
		return false
	var unit_index: Callable = func(index: Variant) -> bool: return index is int and index >= 0 and index < count
	return (data.props.all(func(saved: Variant) -> bool:
			return (saved is Array and saved.size() == 3 and saved[0] in ["crate", "rock"]
				and saved[1] is Vector2i and area.has_point(saved[1]) and saved[2] is int and saved[2] > 0
				and saved[2] <= 6))
		and data.grounds.all(func(saved: Variant) -> bool:
			return (saved is Array and saved.size() == 6 and unit_index.call(saved[0])
				and saved[1] is Vector2i and area.has_point(saved[1]) and saved[2] in ["burn", "poison"]
				and saved[3] is int and saved[3] >= 1 and saved[3] <= 4
				and saved[4] is Array and saved[4].size() <= count and saved[4].all(unit_index)
				and saved[5] is int and saved[5] >= 0 and saved[5] <= CombatUnit.SAVED_INT_LIMIT
				and (saved[5] == 0 if saved[2] == "burn" else saved[5] > 0))))


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
	last_damage_rolls.append(CombatChecks.damage_roll(
		actor.get_ability_sides(CombatActionRules.damage_ability(actor, "attack")), dice))
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
	var message: String = tr("%s 나무 상자 공격: %d, %d · 피해 %d · 내구도 %d/6%s") % [
		actor.get_display_name(), prop.cell.x, prop.cell.y, last_damage, prop.hit_points,
		tr(" · 파괴") if prop.hit_points == 0 else ""]
	hit_landed.emit()
	logged.emit(message)
	busy = false
	changed.emit()
	return true


func preview_rock(actor: CombatUnit, prop: CombatGrid.Prop) -> RockRoll:
	var roll: RockRoll = RockRoll.new()
	if (not is_instance_valid(actor) or prop == null or prop not in grid.props
		or prop.kind != "rock" or prop.hit_points <= 0):
		roll.reason = tr("대상 없음")
		return roll
	var offset: Vector2i = prop.cell - actor.cell
	roll.direction = (Vector2i(signi(offset.x), 0) if absi(offset.x) >= absi(offset.y)
		else Vector2i(0, signi(offset.y)))
	if roll.direction == Vector2i.ZERO:
		roll.reason = tr("방향 없음")
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
			step.reason = tr("맵 경계")
		elif grid.is_blocked(next):
			step.advance = false
			step.reason = tr("물체") if grid.prop_at(next) != null else tr("장벽")
		elif grid.height_at(next) > grid.height_at(cell):
			step.advance = false
			step.reason = tr("오르막")
		elif grid.pits.has(next) or grid.height_at(cell) - grid.height_at(next) >= 2:
			step.destroyed = true
			step.reason = tr("낭떠러지 소멸") if grid.pits.has(next) else tr("높이 차2 파괴")
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
						step.reason = tr("밀기 막힘")
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
						step.reason = tr("전투 종료")
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
	var impact_summary: String = ""
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
			impact_summary += (tr(" · 충돌: %s 피해4") if impact_summary.is_empty() else tr(", %s 피해4")) % target.get_display_name()
			logged.emit(tr("%s 바위 충돌: 피해4 · HP %d") % [target.get_display_name(), target.hit_points])
			if not _can_continue_rock(actor, prop, origin) or not is_instance_valid(target) or target not in units:
				return
			if is_over():
				logged.emit(tr("바위 정지: 전투 종료") + impact_summary)
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
				logged.emit(tr("바위 정지: 전투 종료") + impact_summary)
				return
			step = _trace_rock(prop, direction, 1, struck).steps[0]
			if step.damage > 0:
				return
		if step.advance:
			prop.cell = step.cell
		if step.destroyed:
			prop.hit_points = 0
			grid.props.erase(prop)
		logged.emit(tr("바위 %s: %d, %d") % [step.reason if not step.reason.is_empty() else tr("이동"),
			prop.cell.x, prop.cell.y] + (impact_summary if not step.reason.is_empty() else ""))
		if step.destroyed or not step.advance:
			return
		if not _can_continue_rock(actor, prop, step.cell) or is_over():
			return
	logged.emit(tr("바위 정지: 최대3칸") + impact_summary)


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
				ground_messages.append(tr("%s %s 장판 만료: %d, %d") % [unit.get_display_name(),
					tr("불") if ground.kind == "burn" else tr("독"), ground.cell.x, ground.cell.y])
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
		logged.emit(tr("%s 과부하: 자기 피해 2 · HP %d") % [unit.get_display_name(), unit.hit_points])
		feedback.emit(unit, tr("과부하 2"))
	_apply_grounds(unit, false)
	var poison_checked: bool = false
	for effect: CombatUnit.StatusEffect in unit.status_effects.duplicate():
		if unit.hit_points <= 0 or is_over():
			break
		if effect not in unit.status_effects:
			continue
		var name: String = tr("화상") if effect.kind == "burn" else tr("독")
		if effect.kind == "poison" and not poison_checked:
			poison_checked = true
			var health_sides: int = unit.get_ability_sides(CombatUnit.Ability.HEALTH)
			var saved: CombatChecks.RollResult = CombatChecks.saving_throw(health_sides, unit.get_defense_bonus(),
				effect.dc, CombatActionRules.save_mode(unit), dice)
			logged.emit(tr("%s 독 제거(건강 내성): 건강 d%d %s %+d = %d / DC %d · %s") % [unit.get_display_name(),
				health_sides, str(saved.rolls), unit.get_defense_bonus(), saved.total, effect.dc, _save_outcome(saved)])
			# 실패는 뒤따르는 `독 1` 틱 팝업이 효과 이름을 보인다.
			if saved.success:
				feedback.emit(unit, tr("독 제거"))
			if unit.hit_points <= 0 or is_over():
				break
			if effect not in unit.status_effects:
				continue
			if saved.success:
				unit.status_effects.erase(effect)
				continue
		var amount: int = dice.roll(4) if effect.kind == "burn" else 1
		_damage(unit, amount)
		logged.emit(tr("%s %s: %d · HP %d") % [unit.get_display_name(), name, amount, unit.hit_points])
		feedback.emit(unit, "%s %d" % [name, amount])
	changed.emit()


func apply_status(source: CombatUnit, target: CombatUnit, kind: String,
	dc: int = Ground.POISON_DC) -> bool:
	if (not is_instance_valid(source) or not is_instance_valid(target)
		or source not in units or target not in units or source.hit_points <= 0 or target.hit_points <= 0
		or kind not in ["stun", "burn", "poison"]
		or kind == "poison" and (dc < 1 or dc > CombatUnit.SAVED_INT_LIMIT)):
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
		target.status_effects.append(CombatUnit.StatusEffect.new(kind, source, 2 if kind == "burn" else 4, dc))
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
	logged.emit(tr("%s %s 장판 %s: %d, %d") % [owner.get_display_name(),
		tr("불") if kind == "burn" else tr("독"), tr("갱신") if refreshed else tr("생성"), cell.x, cell.y])
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
			ground_messages.append(tr("%s %s 장판 해제: %d, %d") % [target.get_display_name(),
				tr("불") if ground.kind == "burn" else tr("독"), ground.cell.x, ground.cell.y])
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


## 전투 포기(#286). 남은 아군을 모두 전투 불능으로 만들어 전멸과 똑같이 패배한다.
func give_up() -> void:
	if is_over():
		return
	var allies: Array[CombatUnit] = units.filter(func(unit: CombatUnit) -> bool:
		return unit.is_ally and unit.hit_points > 0)
	# 먼저 모두 0으로 두어 전투를 끝낸다. 하나씩 빼다 시작된 다음 적 묶음의 턴 시작 효과(과부하·화상)가 들지 않는다.
	for unit: CombatUnit in allies:
		unit.hit_points = 0
	for unit: CombatUnit in allies:
		incapacitate(unit)
	logged.emit(tr("전투 포기"))
	changed.emit()


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
		if await _ask_reaction(reactor, "opportunity", tr("%s가 벗어납니다. 기회 공격할까요? (명중률 %.1f%%)") % [actor.get_display_name(), chance * 100.0]):
			reactor.spend_resource(CombatUnit.TurnResource.REACTION)
			if not reactor.is_ally:
				logged.emit(tr("%s 기회 공격: 반응 사용") % reactor.get_display_name())
			await _perform_attack(reactor, actor, "opportunity")
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
	logged.emit(tr("%s 점프: 이동 %d, 보조 행동1 · 남은 이동 %d") % [
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


# _land와 같은 순서로 밀린 착지 결과를 안내한다.
func shove_landing(target: CombatUnit, destination: Vector2i) -> String:
	if grid.pits.has(destination):
		return tr("낙사")
	var notes: Array[String] = []
	if destination in grid.water_cells and target.get_status_count("burn") > 0:
		notes.append(tr("물: 화상 해제"))
	var fall: int = fall_damage(target, destination)
	if fall > 0:
		notes.append(tr("낙하 피해 %d") % fall)
	return " · ".join(notes)


# _trace_rock이 예측한 밀기마다 같은 낙하 계산을 더한다.
func rock_landing(roll: RockRoll, target: CombatUnit) -> String:
	var fall: int = 0
	for step: RockStep in roll.steps:
		if step.push and step.target == target:
			if grid.pits.has(step.push_cell):
				return tr("낙사")
			fall += _fall_damage_from(target, step.cell, step.push_cell)
	return tr("낙하 피해 %d") % fall if fall > 0 else ""


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
			return CombatActionRules.has_uses(actor, action) and actor.action_left > 0
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
		return tr("전투 입력 잠금")
	if not reaction and (actor != turns.current_unit or not actor.is_ally):
		return tr("아군의 자기 턴에만 사용")
	if CombatActionRules.uses_left(actor, action) == 0:
		return tr("보유 물약 없음") if action == "potion" else tr("이번 막의 횟수를 모두 씀")
	if [actor.action_left, actor.bonus_action_left, actor.reaction_left][resource] == 0:
		return tr("자원을 이미 씀")
	if reaction:
		if actor.hit_points <= 0:
			return tr("전투 불능")
		return tr("기절 상태") if actor.is_stunned else ""
	if action in ["second_wind", "potion"] and actor.hit_points == actor.get_max_hit_points():
		return tr("HP가 이미 최대")
	if action == "surge" and actor.action_left > 0:
		return tr("행동이 아직 남아 있음")
	if not can_use(actor, action):
		return tr("이동이 없거나 이미 효과 적용 중") if action == "disengage" else tr("사거리 또는 대상 조건을 확인")
	return ""


func move_to(actor: CombatUnit, destination: Vector2i) -> bool:
	if not can_move(actor, destination):
		return false
	var ground_cells: Array[Vector2i] = []
	if not actor.is_ally:
		for ground: Ground in _grounds:
			if ground.cell not in ground_cells:
				ground_cells.append(ground.cell)
	var path: Array[Vector2i] = grid.path_to(actor, destination, ground_cells)
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
					if await _ask_reaction(reactor, "opportunity", tr("%s가 벗어납니다. 기회 공격할까요? (명중률 %.1f%%)") % [actor.get_display_name(), chance * 100.0]):
						reactor.spend_resource(CombatUnit.TurnResource.REACTION)
						if not reactor.is_ally:
							logged.emit(tr("%s 기회 공격: 반응 사용") % reactor.get_display_name())
						await _perform_attack(reactor, actor, "opportunity")
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
	logged.emit(tr_n("%s 이동: %d칸, 남은 이동 %d", "%s 이동: %d칸, 남은 이동 %d", moved) % [actor.get_display_name(), moved, actor.movement_left])
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
	await _perform_attack(actor, target, action)
	_finish()
	return true


func spin(actor: CombatUnit) -> bool:
	if not can_use(actor, "spin"):
		return false
	var targets: Array[CombatUnit] = grid.opponents_in_area(actor, 1)
	# DC는 시전 때 한 번 정하고 모든 대상의 내성굴림에 쓴다 (동작 유형 기획서 4-2).
	var dc: int = CombatActionRules.save_dc(actor, "spin")
	busy = true
	actor.spend_resource(CombatUnit.TurnResource.ACTION)
	logged.emit(tr_n("%s 회전회오리: 인접 대상 %d명 · DC %d", "%s 회전회오리: 인접 대상 %d명 · DC %d", targets.size()) % [
		actor.get_display_name(), targets.size(), dc])
	changed.emit()
	for target: CombatUnit in targets:
		if actor.hit_points <= 0 or actor.is_stunned or actor != turns.current_unit or is_over():
			break
		if target.hit_points > 0 and target.cell in grid.area_cells(actor.cell, 1):
			await _perform_save(actor, target, "spin", dc)
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
	logged.emit(tr("%s 새끼 낳기: %s") % [actor.get_display_name(), child.cell])
	_finish()
	return true


func use_self(actor: CombatUnit, action: String) -> bool:
	if not can_use(actor, action) or action not in CombatActionRules.SELF_TARGET:
		return false
	actor.spend_resource(CombatUnit.TurnResource.BONUS_ACTION)
	CombatActionRules.spend_use(actor, action)
	match action:
		"second_wind":
			_heal(actor, dice.roll(10) + 1, tr("숨 고르기"))
		"surge":
			actor.action_left = 1
			logged.emit(tr("%s 몰아치기: 행동 회복") % actor.get_display_name())
		"disengage":
			actor.disengaged = true
			logged.emit(tr("%s 물러서며 쏘기: 이번 턴 이동은 기회 공격 제외") % actor.get_display_name())
		"potion":
			_heal(actor, dice.roll(4) + dice.roll(4) + 2, tr("물약"))
	changed.emit()
	return true


func mark(actor: CombatUnit, target: CombatUnit) -> bool:
	if not _can_act(actor) or not can_target(actor, target, "mark"):
		return false
	actor.spend_resource(CombatUnit.TurnResource.BONUS_ACTION)
	CombatActionRules.spend_use(actor, "mark")
	actor.marked_target = target
	logged.emit(tr("%s 표식: %s") % [actor.get_display_name(), target.get_display_name()])
	changed.emit()
	return true


func pull(actor: CombatUnit, target: CombatUnit) -> bool:
	if not _can_act(actor) or not can_target(actor, target, "pull"):
		return false
	actor.spend_resource(CombatUnit.TurnResource.ACTION)
	actor.pull_cooldown = 2
	last_attack = null
	var dc: int = CombatActionRules.save_dc(actor, "pull")
	logged.emit(tr("%s 만능팔: %s · DC %d") % [actor.get_display_name(), target.get_display_name(), dc])
	var pulled: bool = not _roll_save(target, "pull", dc).success
	if pulled:
		var cells: Array[Vector2i] = grid.pull_cells(actor, target)
		_land(target, cells[0] if cells.size() == 1 else cells[dice.roll(cells.size()) - 1])
	logged.emit(tr("만능팔 %s") % (tr("성공") if pulled else tr("실패")))
	feedback.emit(target, tr("끌어옴") if pulled else tr("만능팔 저항"))
	changed.emit()
	return true


func shove(actor: CombatUnit, target: CombatUnit) -> bool:
	if not _can_act(actor) or not can_target(actor, target, "shove"):
		return false
	actor.spend_resource(CombatUnit.TurnResource.BONUS_ACTION)
	last_attack = null
	last_save = null
	var won: bool = not CombatActionRules.shove_saves(actor, target)
	if not won:
		var dc: int = CombatActionRules.save_dc(actor, "shove")
		logged.emit(tr("%s 밀치기: %s · DC %d") % [actor.get_display_name(), target.get_display_name(), dc])
		won = not _roll_save(target, "shove", dc).success
	feedback.emit(target, tr("밀치기 성공") if won else tr("밀치기 실패"))
	if won:
		_land(target, grid.push_destination(actor.cell, target.cell))
	logged.emit(tr("밀치기 %s") % (tr("성공") if won else tr("실패")))
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
	var accepted: bool
	if not replay_answers.is_empty():
		accepted = replay_answers.pop_front()
	else:
		pending_reactor = reactor
		pending_kind = kind
		_emit_reaction.call_deferred(kind, prompt)
		accepted = await reaction_decided
	reaction_answers.append(accepted)
	logged.emit("%s %s: %s" % [reactor.get_display_name(),
		tr("기회 공격") if kind == "opportunity" else tr("흘려내기"), tr("사용") if accepted else tr("넘기기")])
	pending_kind = ""
	return accepted


func _emit_reaction(kind: String, prompt: String) -> void:
	reaction_requested.emit(kind, prompt)


func _perform_attack(actor: CombatUnit, target: CombatUnit, action: String) -> void:
	if attack_animation.is_valid():
		await attack_animation.call(actor, target)
	if actor.hit_points <= 0 or target.hit_points <= 0 or is_over():
		return
	var attack_ability: CombatUnit.Ability = actor.get_attack_ability()
	var attack_sides: int = actor.get_ability_sides(attack_ability)
	last_damage = 0
	last_damage_rolls.clear()
	last_save = null
	var preview: CombatChecks.AttackPreview = grid.attack_preview(actor, target)
	last_attack = CombatChecks.hit_roll(attack_sides, actor.get_attack_bonus(), target.get_armor_class(), preview.mode, dice)
	var outcome: String = tr("명중") if last_attack.success else tr("빗나감")
	if last_attack.face == CombatChecks.Face.ABSOLUTE_SUCCESS:
		outcome = tr("명중(절대성공)")
	elif last_attack.face == CombatChecks.Face.ABSOLUTE_FAILURE:
		outcome = tr("빗나감(절대실패)")
	logged.emit(tr("%s 공격(%s): %s d%d %s %+d = %d / AC %d · %s") % [
		actor.get_display_name(), _mode_name(last_attack.mode), CombatUnit.ability_name(attack_ability), attack_sides,
		str(last_attack.rolls), actor.get_attack_bonus(), last_attack.total, target.get_armor_class(), outcome])
	if not last_attack.success:
		feedback.emit(target, tr("빗나감"))
		return
	if (CombatActionRules.has_uses(target, "parry") and not target.is_stunned
		and target.reaction_left > 0):
		var parry_sides: int = target.get_ability_sides(CombatUnit.Ability.AGILITY)
		var chance: float = CombatChecks.threshold_chance(parry_sides, 3, last_attack.total)
		if await _ask_reaction(target, "parry", tr("%s가 공격에 맞았습니다. 흘려낼까요? (성공률 %.1f%%, 남은 횟수 %d)") % [target.get_display_name(), chance * 100.0, target.parry_left]):
			target.spend_resource(CombatUnit.TurnResource.REACTION)
			CombatActionRules.spend_use(target, "parry")
			var saved: CombatChecks.RollResult = CombatChecks.threshold(parry_sides, 3, last_attack.total, dice)
			logged.emit(tr("흘려내기: 민첩 d%d %d + 3 = %d / 공격 %d · %s") % [parry_sides,
				saved.selected_roll, saved.total, last_attack.total, tr("성공") if saved.success else tr("실패")])
			if saved.success:
				feedback.emit(target, tr("흘려내기"))
				return
	_deal_damage(actor, target, action, actor.marked_target == target, false)
	if action == "shock" and target.hit_points > 0:
		if target.is_boss():
			logged.emit(tr("%s 기절 면역") % target.get_display_name())
			feedback.emit(target, tr("기절 면역"))
		else:
			apply_status(actor, target, "stun")
			logged.emit(tr("%s 충격 화살: 명중하여 기절") % target.get_display_name())
			feedback.emit(target, tr("기절"))


## 내성굴림 피해형 동작의 대상 하나. 대상이 시전 때 정한 DC에 내성굴림하고, 성공하면 피해가 절반이다 (4-1).
## 명중굴림이 없으므로 공격 굴림과 비교하는 흘려내기와 명중에 붙는 표식 추가 피해는 쓰지 않는다.
func _perform_save(actor: CombatUnit, target: CombatUnit, action: String, dc: int) -> void:
	if attack_animation.is_valid():
		await attack_animation.call(actor, target)
	if actor.hit_points <= 0 or target.hit_points <= 0 or is_over():
		return
	last_attack = null
	last_damage = 0
	last_damage_rolls.clear()
	_deal_damage(actor, target, action, false, _roll_save(target, action, dc).success)


## 대상이 동작의 내성 능력치로 DC에 내성굴림하고 로그를 남긴다. 결과는 last_save에도 둔다 (4-1).
func _roll_save(target: CombatUnit, action: String, dc: int) -> CombatChecks.RollResult:
	var ability: CombatUnit.Ability = CombatActionRules.SAVE_ABILITIES[action]
	var sides: int = target.get_ability_sides(ability)
	last_save = CombatChecks.saving_throw(sides, target.get_defense_bonus(), dc, CombatActionRules.save_mode(target), dice)
	logged.emit(tr("%s %s 내성(%s): %s d%d %s %+d = %d / DC %d · %s") % [target.get_display_name(),
		CombatUnit.ability_name(ability), _mode_name(last_save.mode), CombatUnit.ability_name(ability), sides,
		str(last_save.rolls), target.get_defense_bonus(), last_save.total, dc, _save_outcome(last_save)])
	return last_save


## 피해는 명중·내성 굴림과 무관하게 피해 능력치 주사위를 새로 굴린다 (능력치 기획서 4-9).
func _deal_damage(actor: CombatUnit, target: CombatUnit, action: String, has_mark_damage: bool, halved: bool) -> void:
	assert(not (has_mark_damage and halved))
	var damage_ability: CombatUnit.Ability = CombatActionRules.damage_ability(actor, action)
	var damage_sides: int = actor.get_ability_sides(damage_ability)
	last_damage_rolls.append(CombatChecks.damage_roll(damage_sides, dice))
	if has_mark_damage:
		last_damage_rolls.append(dice.roll(6))
	var damage_bonus: int = actor.get_damage_bonus()
	var rolled_total: int = damage_bonus
	for rolled: int in last_damage_rolls:
		rolled_total += rolled
	last_damage = CombatChecks.halve_damage(rolled_total) if halved else rolled_total
	_damage(target, last_damage)
	if has_mark_damage:
		logged.emit(tr("%s 피해 (표식 추가): %s d%d %s + d6 %s %+d = %d · HP %d") % [target.get_display_name(),
			CombatUnit.ability_name(damage_ability), damage_sides, str([last_damage_rolls[0]]),
			str([last_damage_rolls[1]]), damage_bonus, last_damage, target.hit_points])
	elif halved:
		logged.emit(tr("%s 피해 (내성 성공 절반): %s d%d %s %+d = %d → %d · HP %d") % [target.get_display_name(),
			CombatUnit.ability_name(damage_ability), damage_sides, str(last_damage_rolls),
			damage_bonus, rolled_total, last_damage, target.hit_points])
	else:
		logged.emit(tr("%s 피해: %s d%d %s %+d = %d · HP %d") % [target.get_display_name(),
			CombatUnit.ability_name(damage_ability), damage_sides, str(last_damage_rolls),
			damage_bonus, last_damage, target.hit_points])
	feedback.emit(target, str(last_damage))


func _mode_name(mode: CombatChecks.RollMode) -> String:
	if mode == CombatChecks.RollMode.ADVANTAGE:
		return tr("유리")
	if mode == CombatChecks.RollMode.DISADVANTAGE:
		return tr("불리")
	return tr("일반")


func _save_outcome(result: CombatChecks.RollResult) -> String:
	if result.face == CombatChecks.Face.ABSOLUTE_SUCCESS:
		return tr("성공(절대성공)")
	if result.face == CombatChecks.Face.ABSOLUTE_FAILURE:
		return tr("실패(절대실패)")
	return tr("성공") if result.success else tr("실패")


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
		if apply_status(ground.source, unit, ground.kind, ground.dc):
			logged.emit(tr("%s %s 장판: %s 부여") % [unit.get_display_name(),
				tr("불") if ground.kind == "burn" else tr("독"), tr("화상") if ground.kind == "burn" else tr("독")])


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
	logged.emit(tr("%s 물: 화상 해제") % unit.get_display_name())
	if not _same_combat(unit, revision):
		return
	feedback.emit(unit, tr("물: 화상 해제"))


func _land(target: CombatUnit, destination: Vector2i) -> void:
	var revision: int = _revision
	var amount: int = fall_damage(target, destination)
	target.cell = destination
	if grid.pits.has(destination):
		_damage(target, target.hit_points)
		if not _same_combat(target, revision):
			return
		logged.emit(tr("%s 낙사: 전투 불능") % target.get_display_name())
		if not _same_combat(target, revision):
			return
		feedback.emit(target, tr("낙사"))
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
		logged.emit(tr("%s 낙하 피해: %d · HP %d") % [target.get_display_name(), amount, target.hit_points])
		if not _same_combat(target, revision):
			return
		feedback.emit(target, str(amount))
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
	logged.emit(tr("%s %s: HP +%d → %d") % [actor.get_display_name(), name, actor.hit_points - before, actor.hit_points])
	healed.emit(actor, actor.hit_points - before)


func _finish() -> void:
	busy = false
	changed.emit()
