class_name CombatActions
extends RefCounted
## 동작 실행과 반응 대기. 적 AI는 같은 API를 이후 단계에서 호출한다.

signal changed
signal logged(message: String)
signal reaction_requested(kind: String, prompt: String)
signal reaction_decided(use_reaction: bool)

const DIRECTIONS: Array[Vector2i] = [
	Vector2i(0, -1), Vector2i(1, -1), Vector2i(1, 0), Vector2i(1, 1),
	Vector2i(0, 1), Vector2i(-1, 1), Vector2i(-1, 0), Vector2i(-1, -1)
]

var units: Array[CombatUnit] = []
var turns: CombatTurns
var dice: RandomNumberGenerator = RandomNumberGenerator.new()
var map_size: Vector2i = Vector2i(10, 10)
# 미결정 DC는 0으로 두고 해당 효과를 실행하지 않는다. 연결 전에 기획 결정을 받는다.
var save_dc: int = 0
var busy: bool = false
var pending_reactor: CombatUnit
var pending_kind: String = ""
var last_attack: CombatChecks.RollResult
var last_damage_rolls: Array[int] = []
var last_damage: int = 0


func initialize(combat_units: Array[CombatUnit], combat_turns: CombatTurns) -> void:
	units = combat_units
	turns = combat_turns
	dice.randomize()


func distance(a: Vector2i, b: Vector2i) -> int:
	return maxi(absi(a.x - b.x), absi(a.y - b.y))


func unit_at(cell: Vector2i) -> CombatUnit:
	for unit: CombatUnit in units:
		if unit.hit_points > 0 and unit.cell == cell:
			return unit
	return null


func is_inside(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.y >= 0 and cell.x < map_size.x and cell.y < map_size.y


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
		for direction: Vector2i in DIRECTIONS:
			var next: Vector2i = here + direction
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


func can_move(actor: CombatUnit, destination: Vector2i) -> bool:
	if not _can_act(actor):
		return false
	var path: Array[Vector2i] = path_to(actor, destination)
	return not path.is_empty() and path.size() <= actor.movement_left


func can_target(actor: CombatUnit, target: CombatUnit, action: String) -> bool:
	if actor == null or target == null or target.hit_points <= 0 or actor.is_ally == target.is_ally:
		return false
	var separation: int = distance(actor.cell, target.cell)
	match action:
		"attack":
			return actor.action_left > 0 and separation >= 1 and separation <= actor.get_attack_range()
		"shock":
			return (actor.kind == CombatUnit.Kind.ARCHER and actor.action_left > 0
				and actor.shock_left > 0 and save_dc > 0 and separation >= 1 and separation <= 6)
		"mark":
			return (actor.kind == CombatUnit.Kind.ARCHER and actor.bonus_action_left > 0
				and actor.mark_left > 0 and separation >= 1 and separation <= 6)
		"shove":
			return actor.bonus_action_left > 0 and separation == 1 and can_shove(actor, target)
	return false


func can_use(actor: CombatUnit, action: String) -> bool:
	if not _can_act(actor):
		return false
	match action:
		"move":
			for direction: Vector2i in DIRECTIONS:
				if can_move(actor, actor.cell + direction):
					return true
		"attack", "shock", "mark", "shove":
			for target: CombatUnit in units:
				if can_target(actor, target, action):
					return true
		"second_wind":
			return (actor.kind == CombatUnit.Kind.WARRIOR and actor.bonus_action_left > 0
				and actor.second_wind_left > 0 and actor.hit_points < actor.get_max_hit_points())
		"surge":
			return (actor.kind == CombatUnit.Kind.WARRIOR and actor.bonus_action_left > 0
				and actor.surge_left > 0 and actor.action_left == 0)
		"disengage":
			return (actor.kind == CombatUnit.Kind.ARCHER and actor.bonus_action_left > 0
				and actor.disengage_left > 0 and not actor.disengaged and actor.movement_left > 0)
		"potion":
			return (actor.bonus_action_left > 0 and actor.potion_left > 0
				and actor.hit_points < actor.get_max_hit_points())
	return false


func has_available_action(actor: CombatUnit) -> bool:
	if not _can_act(actor):
		return false
	if actor.movement_left > 0:
		for direction: Vector2i in DIRECTIONS:
			if can_move(actor, actor.cell + direction):
				return true
	for action: String in ["attack", "shock", "mark", "shove", "second_wind", "surge", "disengage", "potion"]:
		if can_use(actor, action):
			return true
	return false


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
					and reactor.kind == CombatUnit.Kind.WARRIOR and reactor.reaction_left > 0
					and distance(reactor.cell, actor.cell) == 1 and distance(reactor.cell, step) > 1):
					var chance: float = CombatChecks.attack_preview(reactor, actor, units).chance
					if await _ask_reaction(reactor, "opportunity", "%s가 벗어납니다. 기회 공격할까요? (명중률 %.1f%%)" % [actor.get_display_name(), chance * 100.0]):
						reactor.spend_resource(CombatUnit.TurnResource.REACTION)
						await _perform_attack(reactor, actor, false)
					if actor.hit_points <= 0:
						break
		if actor.hit_points <= 0:
			break
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
		actor.shock_left -= 1
	changed.emit()
	await _perform_attack(actor, target, shock)
	_finish()
	return true


func use_self(actor: CombatUnit, action: String) -> bool:
	if not can_use(actor, action) or action not in ["second_wind", "surge", "disengage", "potion"]:
		return false
	actor.spend_resource(CombatUnit.TurnResource.BONUS_ACTION)
	match action:
		"second_wind":
			actor.second_wind_left -= 1
			_heal(actor, dice.randi_range(1, 10) + 1, "숨 고르기")
		"surge":
			actor.surge_left -= 1
			actor.action_left = 1
			logged.emit("%s 몰아치기: 행동 회복" % actor.get_display_name())
		"disengage":
			actor.disengage_left -= 1
			actor.disengaged = true
			logged.emit("%s 물러서며 쏘기: 이번 턴 이동은 기회 공격 제외" % actor.get_display_name())
		"potion":
			actor.potion_left -= 1
			_heal(actor, dice.randi_range(1, 4) + dice.randi_range(1, 4) + 2, "물약")
	changed.emit()
	return true


func mark(actor: CombatUnit, target: CombatUnit) -> bool:
	if not _can_act(actor) or not can_target(actor, target, "mark"):
		return false
	actor.spend_resource(CombatUnit.TurnResource.BONUS_ACTION)
	actor.mark_left -= 1
	actor.marked_target = target
	logged.emit("%s 표식: %s" % [actor.get_display_name(), target.get_display_name()])
	changed.emit()
	return true


func shove_destination(actor: CombatUnit, target: CombatUnit) -> Vector2i:
	var delta: Vector2i = target.cell - actor.cell
	return target.cell + Vector2i(signi(delta.x), signi(delta.y))


func can_shove(actor: CombatUnit, target: CombatUnit) -> bool:
	if actor == null or target == null or distance(actor.cell, target.cell) != 1:
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
	pending_kind = ""
	return accepted


func _emit_reaction(kind: String, prompt: String) -> void:
	reaction_requested.emit(kind, prompt)


func _perform_attack(actor: CombatUnit, target: CombatUnit, shock: bool) -> void:
	var preview: CombatChecks.AttackPreview = CombatChecks.attack_preview(actor, target, units)
	last_attack = CombatChecks.attack(actor.get_attack_bonus(), target.get_armor_class(), preview.mode, dice)
	last_damage = 0
	last_damage_rolls.clear()
	logged.emit("%s 공격: d20 %s + %d = %d / AC %d · %s" % [actor.get_display_name(),
		str(last_attack.rolls), actor.get_attack_bonus(), last_attack.total, target.get_armor_class(),
		"치명타" if last_attack.critical else "명중" if last_attack.success else "빗나감"])
	if not last_attack.success:
		return
	if (save_dc > 0 and target.kind == CombatUnit.Kind.WARRIOR and not target.is_stunned
		and target.reaction_left > 0 and target.parry_left > 0):
		var success_rolls: int = clampi(21 + target.get_dexterity() - save_dc, 0, 20)
		if await _ask_reaction(target, "parry", "%s가 공격에 맞았습니다. 흘려낼까요? (성공률 %.1f%%, 남은 횟수 %d)" % [target.get_display_name(), success_rolls * 5.0, target.parry_left]):
			target.spend_resource(CombatUnit.TurnResource.REACTION)
			target.parry_left -= 1
			var saved: CombatChecks.RollResult = CombatChecks.saving_throw(target.get_dexterity(), save_dc, dice)
			logged.emit("흘려내기: d20 %d + %d = %d / DC %d · %s" % [saved.selected_roll,
				target.get_dexterity(), saved.total, save_dc, "성공" if saved.success else "실패"])
			if saved.success:
				return
	var count: int = 2 if last_attack.critical else 1
	var sides: int = 8 if actor.kind == CombatUnit.Kind.WARRIOR else 6
	for index: int in range(count):
		last_damage_rolls.append(dice.randi_range(1, sides))
	if actor.marked_target == target:
		for index: int in range(count):
			last_damage_rolls.append(dice.randi_range(1, 6))
	last_damage = 3
	for rolled: int in last_damage_rolls:
		last_damage += rolled
	_damage(target, last_damage)
	logged.emit("%s 피해: %s + 3 = %d · HP %d" % [target.get_display_name(),
		str(last_damage_rolls), last_damage, target.hit_points])
	if shock and target.hit_points > 0:
		var saved: CombatChecks.RollResult = CombatChecks.saving_throw(
			target.get_attribute(CombatUnit.Attribute.MENTAL), save_dc, dice)
		if not saved.success:
			target.is_stunned = true
		logged.emit("정신 내성: d20 %d + %d = %d / DC %d · %s" % [saved.selected_roll,
			target.get_attribute(CombatUnit.Attribute.MENTAL), saved.total, save_dc,
			"기절" if not saved.success else "버팀"])


func _damage(target: CombatUnit, amount: int) -> void:
	target.hit_points = maxi(0, target.hit_points - amount)
	if target.hit_points == 0:
		for unit: CombatUnit in units:
			if unit.marked_target == target:
				unit.marked_target = null
		turns.remove_unit(target)
		target.visible = false


func _heal(actor: CombatUnit, amount: int, name: String) -> void:
	var before: int = actor.hit_points
	actor.hit_points = mini(actor.get_max_hit_points(), actor.hit_points + amount)
	logged.emit("%s %s: HP +%d → %d" % [actor.get_display_name(), name, actor.hit_points - before, actor.hit_points])


func _finish() -> void:
	busy = false
	changed.emit()
