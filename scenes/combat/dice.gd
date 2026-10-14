class_name CombatDice
extends RefCounted
## 전투 판정의 주사위 seam. 게임은 이 RNG adapter를 쓰고, 테스트는 정해진 값을 주는 adapter를 쓴다.

var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
## 같은 seed는 같은 굴림 순서를 재현한다.
var seed: int:
	get:
		return _rng.seed
	set(value):
		_rng.seed = value


func randomize() -> void:
	_rng.randomize()


## low 이상 high 이하의 정수 하나. 모든 정수 굴림이 이 함수를 지난다.
func roll_between(low: int, high: int) -> int:
	return _rng.randi_range(low, high)


## 1부터 sides까지의 주사위 하나.
func roll(sides: int) -> int:
	return roll_between(1, sides)


## 0 이상 1 미만의 확률 값.
func chance() -> float:
	return _rng.randf()
