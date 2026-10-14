extends CombatDice
## 테스트용 주사위 adapter. 정해진 값을 차례로 주고, 값이 다 떨어지면 고정 seed의 굴림을 이어 준다.
## 값 0은 그 자리만 고정 seed로 굴린다. sides를 주면 실제로 요청한 주사위 면 수도 확인한다.

var _values: Array[int] = []
var _sides: Array[int] = []
## 모든 인스턴스에서 요청과 맞지 않은 값. 테스트가 끝에 비어 있는지 확인한다.
static var mismatches: Array[String] = []


func _init(values: Array[int], sides: Array[int] = []) -> void:
	_values = values.duplicate()
	_sides = sides.duplicate()
	_rng.seed = 0


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
