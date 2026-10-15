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
