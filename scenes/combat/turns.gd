class_name CombatTurns
extends RefCounted
## 한 라운드의 이니셔티브 순서와 연속한 같은 편의 턴 묶음.

signal changed
signal turn_started(unit: CombatUnit)
signal order_rotated(units: Array[CombatUnit])

## 저장 키와 그 키에 담는 내부 목록.
const SAVED_LISTS: Dictionary[String, StringName] = {
	"finished": &"_finished_units", "pending": &"_pending_finished_units", "started": &"_started_units",
	"activated": &"_activated_units", "deferred": &"_deferred_units"
}

var ordered_units: Array[CombatUnit] = []
var current_unit: CombatUnit
var round_number: int = 0

var _group_start: int = 0
var _group_end: int = -1
var _finished_units: Array[CombatUnit] = []
var _pending_finished_units: Array[CombatUnit] = []
var _started_units: Array[CombatUnit] = []
var _activated_units: Array[CombatUnit] = []
var _deferred_units: Array[CombatUnit] = []


func start(combat_units: Array[CombatUnit], dice: CombatDice) -> void:
	ordered_units = combat_units.duplicate()
	for unit: CombatUnit in ordered_units:
		unit.initiative_roll = dice.roll(20)
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
	_pending_finished_units.clear()
	_started_units.clear()
	_activated_units.clear()
	_deferred_units.clear()
	current_unit = null
	_group_start = 0
	_group_end = -1
	if not ordered_units.is_empty():
		_start_group_at(0)
	changed.emit()


## 저장할 순서와 묶음 진행. 유닛은 전투 유닛 목록의 번호로 적는다.
func save_state(units: Array[CombatUnit]) -> Dictionary:
	var data: Dictionary = {"order": _indices(ordered_units, units), "current": units.find(current_unit),
		"round": round_number, "group": Vector2i(_group_start, _group_end)}
	for key: String in SAVED_LISTS:
		data[key] = _indices(get(SAVED_LISTS[key]), units)
	return data


## save_state()의 값으로 되돌린다. 턴 시작 효과는 다시 실행하지 않는다. is_valid_state()를 먼저 확인한다.
func load_state(data: Dictionary, units: Array[CombatUnit]) -> void:
	ordered_units = _units(data.order, units)
	current_unit = units[data.current] if data.current >= 0 else null
	round_number = data.round
	_group_start = data.group.x
	_group_end = data.group.y
	for key: String in SAVED_LISTS:
		set(SAVED_LISTS[key], _units(data[key], units))
	changed.emit()


## 저장 파일의 값을 load_state()에 넘겨도 되는지. count는 전투 유닛 수다.
static func is_valid_state(data: Variant, count: int) -> bool:
	if not (data is Dictionary and data.get("current") is int and data.get("round") is int
			and data.get("group") is Vector2i and _valid_indices(data.get("order"), count)):
		return false
	for key: String in SAVED_LISTS:
		if not _valid_indices(data.get(key), count):
			return false
	var order: Array = data.order
	var group: Vector2i = data.group
	for index: int in order:
		if order.count(index) > 1:
			return false
	if order.is_empty():
		return group == Vector2i(0, -1) and data.current == -1
	return (group.x >= 0 and group.x <= group.y and group.y < order.size()
		and (data.current == -1 or data.current in order))


static func _valid_indices(value: Variant, count: int) -> bool:
	return value is Array and (value as Array).all(func(index: Variant) -> bool:
		return index is int and index >= 0 and index < count)


static func _indices(members: Array[CombatUnit], units: Array[CombatUnit]) -> Array:
	return members.map(func(unit: CombatUnit) -> int: return units.find(unit))


static func _units(indices: Array, units: Array[CombatUnit]) -> Array[CombatUnit]:
	var members: Array[CombatUnit] = []
	for index: int in indices:
		members.append(units[index])
	return members


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


func is_turn_started(unit: CombatUnit) -> bool:
	return unit in _started_units


## 현재 유닛이 만든 동료를 바로 앞에 넣고 생성 라운드에는 대기시킨다.
func insert_before(unit: CombatUnit, anchor: CombatUnit) -> bool:
	if (unit == null or anchor == null or anchor != current_unit
		or unit in ordered_units or unit.is_ally != anchor.is_ally
		or unit.hit_points <= 0 or anchor.hit_points <= 0):
		return false
	var index: int = ordered_units.find(anchor)
	if index < 0:
		return false
	ordered_units.insert(index, unit)
	_group_end += 1
	_finished_units.append(unit)
	_started_units.append(unit)
	changed.emit()
	return true


func select_unit(unit: CombatUnit) -> bool:
	if (not unit.is_ally or unit.is_stunned or unit not in get_current_group()
		or (is_turn_finished(unit) and unit not in _pending_finished_units)):
		return false
	_finished_units.erase(unit)
	_pending_finished_units.erase(unit)
	current_unit = unit
	_activate_current_unit()
	changed.emit()
	return true


func end_turn() -> bool:
	if current_unit == null:
		return false
	_finished_units.append(current_unit)
	_pending_finished_units.append(current_unit)
	_select_next_or_advance()
	changed.emit()
	return true


func remove_unit(unit: CombatUnit) -> void:
	var index: int = ordered_units.find(unit)
	if index == -1:
		return
	var continuing_group: bool = false
	for member: CombatUnit in get_current_group():
		if member != unit:
			continuing_group = true
	ordered_units.remove_at(index)
	_finished_units.erase(unit)
	_pending_finished_units.erase(unit)
	_started_units.erase(unit)
	_activated_units.erase(unit)
	_deferred_units.erase(unit)
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
		_start_group_at(anchor, continuing_group)
		if previous_current != unit and previous_current in get_current_group():
			current_unit = previous_current
	changed.emit()


func _select_next_or_advance() -> void:
	for unit: CombatUnit in get_current_group():
		if is_turn_finished(unit) or (unit in _deferred_units and unit.is_stunned):
			continue
		current_unit = unit
		_activate_current_unit()
		if unit not in ordered_units or current_unit != unit:
			return
		if not unit.is_stunned:
			return
		_finished_units.append(unit)
	for unit: CombatUnit in get_current_group():
		if unit not in _deferred_units or not unit.is_stunned or is_turn_finished(unit):
			continue
		current_unit = unit
		_activate_current_unit()
		if unit not in ordered_units or current_unit != unit:
			return
		if not unit.is_stunned:
			return
		_finished_units.append(unit)
	_pending_finished_units.clear()
	_start_group_at(_group_end + 1)


func _activate_current_unit() -> void:
	if current_unit not in _started_units:
		_begin_unit_turn(current_unit)
	if current_unit not in _activated_units:
		_activated_units.append(current_unit)
		# 처리 중 전투 불능이 되면 remove_unit이 다음 유닛을 선택할 수 있다.
		turn_started.emit(current_unit)


func _begin_unit_turn(unit: CombatUnit) -> void:
	unit.begin_turn()
	_started_units.append(unit)
	_deferred_units.erase(unit)


func _start_group_at(index: int, defer_new: bool = false) -> void:
	if index >= ordered_units.size():
		index = 0
		round_number += 1
		_finished_units.clear()
		_started_units.clear()
		_activated_units.clear()
		_deferred_units.clear()
	_group_start = index
	while (_group_start > 0
		and ordered_units[_group_start - 1].is_ally == ordered_units[index].is_ally):
		_group_start -= 1
	_group_end = index
	while (_group_end + 1 < ordered_units.size()
		and ordered_units[_group_end + 1].is_ally == ordered_units[_group_start].is_ally):
		_group_end += 1
	if (_group_start > 0 and _group_end == ordered_units.size() - 1
		and ordered_units[0].is_ally == ordered_units[_group_start].is_ally):
		var prefix_size: int = 1
		while ordered_units[prefix_size].is_ally == ordered_units[0].is_ally:
			prefix_size += 1
		var moved: Array[CombatUnit] = ordered_units.slice(0, prefix_size)
		ordered_units = ordered_units.slice(prefix_size)
		ordered_units.append_array(moved)
		_group_start -= prefix_size
		_group_end = ordered_units.size() - 1
		for unit: CombatUnit in moved:
			_finished_units.erase(unit)
			_pending_finished_units.erase(unit)
			_started_units.erase(unit)
			_activated_units.erase(unit)
			_deferred_units.append(unit)
		order_rotated.emit(moved)
	for unit: CombatUnit in get_current_group():
		if unit not in _started_units:
			if defer_new and unit not in _deferred_units:
				_deferred_units.append(unit)
			if unit not in _deferred_units:
				_begin_unit_turn(unit)
	_select_next_or_advance()
