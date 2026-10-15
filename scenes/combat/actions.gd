class_name CombatActions
extends RefCounted
## 아군과 적 AI가 함께 쓰는 동작 실행과 반응 대기.

signal changed
signal logged(message: String)
signal feedback(unit: CombatUnit, text: String)
signal hit_landed
signal reaction_requested(kind: String, prompt: String)
signal reaction_decided(use_reaction: bool)

var units: Array[CombatUnit] = []
var turns: CombatTurns
var dice: CombatDice = CombatDice.new()
var map_size: Vector2i = Vector2i(10, 10)
var busy: bool = false
var pending_reactor: CombatUnit
var pending_kind: String = ""
var last_attack: CombatChecks.RollResult
var last_damage_rolls: Array[int] = []
var last_damage: int = 0
var movement_animation: Callable
var attack_animation: Callable


func initialize(combat_units: Array[CombatUnit], combat_turns: CombatTurns) -> void:
	if turns != null and turns.turn_started.is_connected(_on_turn_started):
		turns.turn_started.disconnect(_on_turn_started)
	units = combat_units
	turns = combat_turns
	turns.turn_started.connect(_on_turn_started)
	dice.randomize()


func _on_turn_started(unit: CombatUnit) -> void:
	if not unit.overloaded or unit.hit_points <= 0 or is_over():
		return
	_damage(unit, 2)
	logged.emit("%s 과부하: 자기 피해 2 · HP %d" % [unit.get_display_name(), unit.hit_points])
	feedback.emit(unit, "과부하 -2")
	changed.emit()


func unit_at(cell: Vector2i) -> CombatUnit:
	for unit: CombatUnit in units:
		if unit.hit_points > 0 and unit.cell == cell:
			return unit
	return null


func is_inside(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.y >= 0 and cell.x < map_size.x and cell.y < map_size.y


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
	target.hit_points = 0
	for unit: CombatUnit in units:
		if unit.marked_target == target:
			unit.marked_target = null
	turns.remove_unit(target)
	target.visible = false


func is_over() -> bool:
	var ally: bool = false
	var enemy: bool = false
	for unit: CombatUnit in units:
		if unit.hit_points > 0:
			ally = ally or unit.is_ally
			enemy = enemy or not unit.is_ally
	return not ally or not enemy


func path_to(actor: CombatUnit, destination: Vector2i) -> Array[Vector2i]:
	var path: Array[Vector2i] = []
	if actor == null or not is_inside(destination) or unit_at(destination) != null:
		return path
	var parents: Dictionary[Vector2i, Vector2i] = {actor.cell: actor.cell}
	var frontier: Array[Vector2i] = [actor.cell]
	var index: int = 0
	while index < frontier.size() and not parents.has(destination):
		var here: Vector2i = frontier[index]
		index += 1
		for next: Vector2i in CombatHexGrid.neighbors(here):
			if is_inside(next) and not parents.has(next) and unit_at(next) == null:
				parents[next] = here
				frontier.append(next)
	if not parents.has(destination):
		return path
	var cursor: Vector2i = destination
	while cursor != actor.cell:
		path.push_front(cursor)
		cursor = parents[cursor]
	return path


## 이번 턴에 도착할 수 있는 칸과 이동 비용. 현재 칸과 점유 칸은 빠진다.
func reachable_cells(actor: CombatUnit) -> Dictionary[Vector2i, int]:
	var costs: Dictionary[Vector2i, int] = {}
	if not _can_act(actor):
		return costs
	var frontier: Array[Vector2i] = [actor.cell]
	var index: int = 0
	while index < frontier.size():
		var here: Vector2i = frontier[index]
		index += 1
		var cost: int = costs.get(here, 0) + 1
		if cost > actor.movement_left:
			continue
		for next: Vector2i in CombatHexGrid.neighbors(here):
			if next != actor.cell and not costs.has(next) and is_inside(next) and unit_at(next) == null:
				costs[next] = cost
				frontier.append(next)
	return costs


func can_move(actor: CombatUnit, destination: Vector2i) -> bool:
	return reachable_cells(actor).has(destination)


func can_target(actor: CombatUnit, target: CombatUnit, action: String,
	from_cell: Vector2i = Vector2i(-1, -1)) -> bool:
	if (actor == null or target == null or target.hit_points <= 0 or actor.is_ally == target.is_ally
		or not CombatActionRules.belongs_to(actor, action)):
		return false
	var origin: Vector2i = actor.cell if from_cell == Vector2i(-1, -1) else from_cell
	var separation: int = CombatHexGrid.distance(origin, target.cell)
	match action:
		"attack":
			return actor.action_left > 0 and separation >= 1 and separation <= actor.get_attack_range()
		"shock":
			return (CombatActionRules.has_uses(actor, action) and actor.action_left > 0
				and actor.get_save_dc() > 0 and separation >= 1 and separation <= CombatActionRules.SKILL_RANGE)
		"mark":
			return (CombatActionRules.has_uses(actor, action) and actor.bonus_action_left > 0
				and separation >= 1 and separation <= CombatActionRules.SKILL_RANGE)
		"shove":
			return actor.bonus_action_left > 0 and separation == 1 and can_shove(actor, target)
	return false


func can_use(actor: CombatUnit, action: String) -> bool:
	if not _can_act(actor):
		return false
	match action:
		"move":
			for neighbor: Vector2i in CombatHexGrid.neighbors(actor.cell):
				if can_move(actor, neighbor):
					return true
		"attack", "shock", "mark", "shove":
			for target: CombatUnit in units:
				if can_target(actor, target, action):
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
	if actor.movement_left > 0:
		for neighbor: Vector2i in CombatHexGrid.neighbors(actor.cell):
			if can_move(actor, neighbor):
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
	var path: Array[Vector2i] = path_to(actor, destination)
	busy = true
	changed.emit()
	var moved: int = 0
	for step: Vector2i in path:
		if not actor.disengaged:
			for reactor: CombatUnit in units:
				if (reactor.hit_points > 0 and not reactor.is_stunned and reactor.is_ally != actor.is_ally
					and CombatActionRules.belongs_to(reactor, "opportunity") and reactor.reaction_left > 0
					and CombatHexGrid.distance(reactor.cell, actor.cell) == 1 and CombatHexGrid.distance(reactor.cell, step) > 1):
					var chance: float = CombatChecks.attack_preview(reactor, actor, units).chance
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


func shove_destination(actor: CombatUnit, target: CombatUnit) -> Vector2i:
	return CombatHexGrid.push_destination(actor.cell, target.cell)


func can_shove(actor: CombatUnit, target: CombatUnit) -> bool:
	if actor == null or target == null or CombatHexGrid.distance(actor.cell, target.cell) != 1:
		return false
	var destination: Vector2i = shove_destination(actor, target)
	return is_inside(destination) and unit_at(destination) == null


func shove(actor: CombatUnit, target: CombatUnit) -> bool:
	if not _can_act(actor) or not can_target(actor, target, "shove"):
		return false
	actor.spend_resource(CombatUnit.TurnResource.BONUS_ACTION)
	var won: bool = target.is_stunned
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
		target.cell = shove_destination(actor, target)
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
	var preview: CombatChecks.AttackPreview = CombatChecks.attack_preview(actor, target, units)
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
			target.is_stunned = true
		logged.emit("정신 내성: d20 %d + %d = %d / DC %d · %s" % [saved.selected_roll,
			target.get_attribute(CombatUnit.Attribute.MENTAL), saved.total, save_dc,
			"기절" if not saved.success else "버팀"])
		feedback.emit(target, "정신 내성 %d" % saved.total)


func _damage(target: CombatUnit, amount: int) -> void:
	var before: int = target.hit_points
	target.hit_points = maxi(0, target.hit_points - amount)
	if target.hit_points < before:
		hit_landed.emit()
	if target.hit_points == 0:
		incapacitate(target)


func _heal(actor: CombatUnit, amount: int, name: String) -> void:
	var before: int = actor.hit_points
	actor.hit_points = mini(actor.get_max_hit_points(), actor.hit_points + amount)
	logged.emit("%s %s: HP +%d → %d" % [actor.get_display_name(), name, actor.hit_points - before, actor.hit_points])
	feedback.emit(actor, "+%d" % (actor.hit_points - before))


func _finish() -> void:
	busy = false
	changed.emit()
