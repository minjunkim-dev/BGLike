class_name CombatActions
extends RefCounted
## 아군과 적 AI가 함께 쓰는 동작 실행과 반응 대기.

signal changed
signal logged(message: String)
signal feedback(unit: CombatUnit, text: String)
signal hit_landed
signal reaction_requested(kind: String, prompt: String)
signal reaction_decided(use_reaction: bool)

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


func initialize(combat_units: Array[CombatUnit], combat_turns: CombatTurns) -> void:
	if turns != null and turns.turn_started.is_connected(_on_turn_started):
		turns.turn_started.disconnect(_on_turn_started)
	# 소환과 전투 불능 이후에도 현재 유닛 배열을 그대로 조회한다.
	grid.units = combat_units
	turns = combat_turns
	turns.turn_started.connect(_on_turn_started)
	dice.randomize()


func _on_turn_started(unit: CombatUnit) -> void:
	for target: CombatUnit in units:
		if target.stun_source == unit:
			target.is_stunned = false
	if not unit.overloaded or unit.hit_points <= 0 or is_over():
		return
	_damage(unit, 2)
	logged.emit("%s 과부하: 자기 피해 2 · HP %d" % [unit.get_display_name(), unit.hit_points])
	feedback.emit(unit, "과부하 -2")
	changed.emit()


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
		if unit.stun_source == target:
			unit.is_stunned = false
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
	var drop: int = grid.height_at(actor.cell) - grid.height_at(destination)
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
				and not grid.opponents_in_range(actor, 1).is_empty())
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
	var targets: Array[CombatUnit] = grid.opponents_in_range(actor, 1)
	busy = true
	actor.spend_resource(CombatUnit.TurnResource.ACTION)
	logged.emit("%s 회전회오리: 인접 대상 %d명" % [actor.get_display_name(), targets.size()])
	changed.emit()
	for target: CombatUnit in targets:
		if actor.hit_points <= 0 or actor.is_stunned or actor != turns.current_unit or is_over():
			break
		if target.hit_points > 0 and grid.in_range(actor.cell, target.cell, 1):
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
			target.is_stunned = true
			target.stun_source = actor
		logged.emit("정신 내성: d20 %d + %d = %d / DC %d · %s" % [saved.selected_roll,
			target.get_attribute(CombatUnit.Attribute.MENTAL), saved.total, save_dc,
			"기절" if not saved.success else "버팀"])
		feedback.emit(target, "정신 내성 %d" % saved.total)


func _land(target: CombatUnit, destination: Vector2i) -> void:
	var amount: int = fall_damage(target, destination)
	target.cell = destination
	if grid.pits.has(destination):
		incapacitate(target)
		logged.emit("%s 낙사: 전투 불능" % target.get_display_name())
		feedback.emit(target, "낙사")
		return
	if amount == 0:
		return
	_damage(target, amount)
	# 낙하 피드백 전에 착지 위치와 HP를 화면에 반영한다.
	changed.emit()
	logged.emit("%s 낙하 피해: %d · HP %d" % [target.get_display_name(), amount, target.hit_points])
	feedback.emit(target, "-%d" % amount)


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
