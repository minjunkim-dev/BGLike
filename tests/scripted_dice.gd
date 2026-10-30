extends CombatDice
## 테스트용 주사위 adapter. 정해진 값을 차례로 주고, 값이 다 떨어진 뒤 굴리면 부족으로 보고한다.
## then_seeded()를 부른 인스턴스는 값이 다 떨어지면 보고 없이 고정 seed의 굴림을 이어 준다.
## 값 0은 그 자리만 고정 seed로 굴린다. sides를 주면 실제로 요청한 주사위 면 수도 확인한다.
## chances는 chance() 확률 굴림에 차례로 준다.

var _values: Array[int] = []
var _sides: Array[int] = []
var _chances: Array[float] = []
var _seeded: bool = false
## 모든 인스턴스에서 요청과 맞지 않은 값. 테스트 끝에 finish()로 확인한다.
static var _mismatches: Array[String] = []
## finish()가 남은 준비값을 확인할 인스턴스.
static var _created: Array = []


## 입력·연출 fixture의 순서만 저장 복원 API로 고정한다. 자연 이니셔티브의 증거로 쓰지 않는다.
## 모든 굴림 값은 유효한 1이며, 이니셔티브 수학은 combat_turns_test에서 실제 start()로 검사한다.
static func arrange_turns(turns: CombatTurns, units: Array[CombatUnit], desired: Array[CombatUnit]) -> void:
	var ordered: Array[CombatUnit] = desired.duplicate()
	for unit: CombatUnit in units:
		if unit not in ordered and unit.hit_points > 0:
			ordered.append(unit)
	ordered = ordered.filter(func(unit: CombatUnit) -> bool: return unit.hit_points > 0)
	assert(not ordered.is_empty())
	for unit: CombatUnit in ordered:
		unit.initiative_roll = 1
	var group: Array[int] = []
	for unit: CombatUnit in ordered:
		if unit.is_ally != ordered[0].is_ally:
			break
		unit.begin_turn()
		group.append(units.find(unit))
	turns.load_state({"order": ordered.map(func(unit: CombatUnit) -> int: return units.find(unit)),
		"current": units.find(ordered[0]), "round": 1, "group": Vector2i(0, group.size() - 1),
		"finished": [], "pending": [], "started": group, "activated": [units.find(ordered[0])], "deferred": []}, units)
	turns.turn_started.emit(ordered[0])


## 명중굴림의 면 수: 굴리는 유닛의 공격 능력치 주사위. 유리/불리면 count 2다 (#387).
static func attack_sides(attacker: CombatUnit, count: int = 1) -> Array[int]:
	var sides: Array[int] = []
	sides.resize(count)
	sides.fill(attacker.get_ability_sides(attacker.get_attack_ability()))
	return sides


## 명중 뒤 피해 굴림의 면 수. 피해가 능력치 주사위로 바뀌면(#388) 여기만 고친다.
static func damage_sides(attacker: CombatUnit) -> Array[int]:
	return [attacker.get_damage_sides()]


func _init(values: Array[int], sides: Array[int] = [], chances: Array[float] = []) -> void:
	_values = values.duplicate()
	_sides = sides.duplicate()
	_chances = chances.duplicate()
	_rng.seed = 0
	_created.append(self)


## 테스트 끝에 부른다. 요청 불일치와 굴리지 않고 남은 준비값을 돌려주고, 둘 다 비운 뒤 만든 인스턴스를 놓아 준다.
static func finish() -> Array[String]:
	var problems: Array[String] = _mismatches.duplicate()
	for dice in _created:
		if not dice.unused().is_empty():
			problems.append("굴리지 않은 준비값 %s" % [dice.unused()])
	_mismatches.clear()
	_created.clear()
	return problems


## 준비값이 다 떨어진 뒤의 굴림을 고정 seed로 허용한다. 의도한 fallback에만 쓴다.
func then_seeded() -> CombatDice:
	_seeded = true
	return self


## 아직 굴리지 않은 준비값. 정수 값 뒤에 확률 값을 잇는다.
func unused() -> Array:
	return _values + _chances


func chance() -> float:
	if _chances.is_empty():
		if not _seeded:
			_mismatches.append("확률 준비값 부족")
		return super()
	var value: float = _chances.pop_front()
	if value < 0.0 or value >= 1.0:
		_mismatches.append("확률 %s은 0 이상 1 미만 밖" % value)
	return value


func roll_between(low: int, high: int) -> int:
	if _values.is_empty():
		if not _seeded:
			_mismatches.append("준비값 부족 d%d" % high)
		return super(low, high)
	var value: int = _values.pop_front()
	var expected_high: int = _sides.pop_front() if not _sides.is_empty() else high
	if expected_high != high:
		_mismatches.append("d%d 요청에 d%d 값 준비" % [high, expected_high])
	if value == 0:
		return super(low, high)
	if value < low or value > high:
		_mismatches.append("%d는 %d~%d 밖" % [value, low, high])
	return value
