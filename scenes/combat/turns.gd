class_name CombatTurns
extends RefCounted
## 한 라운드의 이니셔티브 순서와 연속한 같은 편의 턴 묶음.

signal changed

var ordered_units: Array[CombatUnit] = []
var current_unit: CombatUnit
var round_number: int = 0

var _group_start: int = 0
var _group_end: int = -1
var _finished_units: Array[CombatUnit] = []
var _started_units: Array[CombatUnit] = []
var _stunned_turns: Array[CombatUnit] = []


func start(combat_units: Array[CombatUnit], dice: RandomNumberGenerator) -> void:
	ordered_units = combat_units.duplicate()
	for unit: CombatUnit in ordered_units:
		unit.initiative_roll = dice.randi_range(1, 20)
	# sort_custom은 안정 정렬이 아니므로 완전히 같은 값은 배치 순서를 보존한다.
	var placement_order: Array[CombatUnit] = ordered_units.duplicate()
	ordered_units.sort_custom(func(a: CombatUnit, b: CombatUnit) -> bool:
		if a.get_initiative() != b.get_initiative():
			return a.get_initiative() > b.get_initiative()
		if a.get_dexterity() != b.get_dexterity():
			return a.get_dexterity() > b.get_dexterity()
		if a.is_ally != b.is_ally:
			return a.is_ally
		return placement_order.find(a) < placement_order.find(b)
	)
	round_number = 1 if not ordered_units.is_empty() else 0
	_finished_units.clear()
	_started_units.clear()
	_stunned_turns.clear()
	current_unit = null
	_group_start = 0
	_group_end = -1
	if not ordered_units.is_empty():
		_start_group_at(0)
	changed.emit()


func get_turn_groups() -> Array[Array]:
	var groups: Array[Array] = []
	for unit: CombatUnit in ordered_units:
		if groups.is_empty() or (groups.back().back() as CombatUnit).is_ally != unit.is_ally:
			groups.append([])
		groups.back().append(unit)
	return groups


func get_current_group() -> Array[CombatUnit]:
	if _group_end < _group_start:
		return []
	return ordered_units.slice(_group_start, _group_end + 1)


func is_turn_finished(unit: CombatUnit) -> bool:
	return unit in _finished_units


func select_unit(unit: CombatUnit) -> bool:
	if not unit.is_ally or unit.is_stunned or unit not in get_current_group() or is_turn_finished(unit):
		return false
	current_unit = unit
	changed.emit()
	return true


func end_turn() -> bool:
	if current_unit == null:
		return false
	_finished_units.append(current_unit)
	_select_next_or_advance()
	changed.emit()
	return true


func remove_unit(unit: CombatUnit) -> void:
	var index: int = ordered_units.find(unit)
	if index == -1:
		return
	ordered_units.remove_at(index)
	_finished_units.erase(unit)
	_started_units.erase(unit)
	_stunned_turns.erase(unit)
	var previous_current: CombatUnit = current_unit
	if current_unit == unit:
		current_unit = null
	if index < _group_start:
		_group_start -= 1
	if index <= _group_end:
		_group_end -= 1
	if ordered_units.is_empty():
		current_unit = null
		_group_start = 0
		_group_end = -1
	else:
		# 탈락 뒤 같은 편이 연속하면 묶음을 다시 계산한다. 이미 끝낸 턴은 되살리지 않는다.
		var anchor: int = ordered_units.find(current_unit) if current_unit != null else _group_start
		_start_group_at(anchor)
		if previous_current != unit and previous_current in get_current_group():
			current_unit = previous_current
	changed.emit()


func _select_next_or_advance() -> void:
	for unit: CombatUnit in get_current_group():
		if unit in _stunned_turns:
			# 실제로 이 유닛의 순서를 건너뛸 때 턴을 끝내고 기절을 푼다.
			unit.is_stunned = false
			_finished_units.append(unit)
			_stunned_turns.erase(unit)
		if not is_turn_finished(unit):
			current_unit = unit
			return
	_start_group_at(_group_end + 1)


func _start_group_at(index: int) -> void:
	if index >= ordered_units.size():
		index = 0
		round_number += 1
		_finished_units.clear()
		_started_units.clear()
		_stunned_turns.clear()
	_group_start = index
	while (_group_start > 0
		and ordered_units[_group_start - 1].is_ally == ordered_units[index].is_ally):
		_group_start -= 1
	_group_end = index
	while (_group_end + 1 < ordered_units.size()
		and ordered_units[_group_end + 1].is_ally == ordered_units[_group_start].is_ally):
		_group_end += 1
	for unit: CombatUnit in get_current_group():
		if unit not in _started_units:
			unit.begin_turn()
			_started_units.append(unit)
			if unit.is_stunned:
				_stunned_turns.append(unit)
	_select_next_or_advance()
