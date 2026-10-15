extends CombatDice
## 테스트용 주사위 adapter. 정해진 값을 차례로 주고, 값이 다 떨어지면 고정 seed의 굴림을 이어 준다.
## 값 0은 그 자리만 고정 seed로 굴린다. sides를 주면 실제로 요청한 주사위 면 수도 확인한다.
## chances는 chance() 확률 굴림에 차례로 준다.

var _values: Array[int] = []
var _sides: Array[int] = []
var _chances: Array[float] = []
## 모든 인스턴스에서 요청과 맞지 않은 값. 테스트 끝에 finish()로 확인한다.
static var mismatches: Array[String] = []
## finish()가 남은 준비값을 확인할 인스턴스.
static var _created: Array = []


func _init(values: Array[int], sides: Array[int] = [], chances: Array[float] = []) -> void:
	_values = values.duplicate()
	_sides = sides.duplicate()
	_chances = chances.duplicate()
	_rng.seed = 0
	_created.append(self)


## 테스트 끝에 한 번 부른다. 요청 불일치와 굴리지 않고 남은 준비값을 돌려주고, 만든 인스턴스를 놓아 준다.
static func finish() -> Array[String]:
	var problems: Array[String] = mismatches.duplicate()
	for dice in _created:
		if not dice.unused().is_empty():
			problems.append("굴리지 않은 준비값 %s" % [dice.unused()])
	_created.clear()
	return problems


## 아직 굴리지 않은 준비값. 정수 값 뒤에 확률 값을 잇는다.
func unused() -> Array:
	return _values + _chances


func chance() -> float:
	if _chances.is_empty():
		return super()
	return _chances.pop_front()


func roll_between(low: int, high: int) -> int:
	if _values.is_empty():
		return super(low, high)
	var value: int = _values.pop_front()
	var expected_high: int = _sides.pop_front() if not _sides.is_empty() else high
	if expected_high != high:
		mismatches.append("d%d 요청에 d%d 값 준비" % [high, expected_high])
	if value == 0:
		return super(low, high)
	if value < low or value > high:
		mismatches.append("%d는 %d~%d 밖" % [value, low, high])
	return value
