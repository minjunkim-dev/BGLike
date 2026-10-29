class_name CombatChecks
extends RefCounted
## 판정 규칙. 주사위 생성기는 호출자가 주어 결과를 재현할 수 있다.
## 명중굴림은 능력치 기획서 4장의 개정 규칙, 나머지 대결·기준값 판정은 이관 전 규칙이다.

enum RollMode { NORMAL, ADVANTAGE, DISADVANTAGE }


class RollResult extends RefCounted:
	var rolls: Array[int] = []
	var selected_roll: int = 0
	var total: int = 0
	var defender_roll: int = 0
	var defender_total: int = 0
	var success: bool = false
	## 고른 굴림이 절대면이면 1(절대성공) 또는 -1(절대실패)이다. 명중굴림만 채운다.
	var absolute: int = 0
	var mode: RollMode = RollMode.NORMAL


class AttackPreview extends RefCounted:
	var valid_target: bool = false
	var in_range: bool = false
	var chance: float = 0.0
	var mode: RollMode = RollMode.NORMAL
	var reasons: PackedStringArray = []
	var blocked_reason: String = ""


## 그 굴림의 유리 요인 수와 불리 요인 수를 비교한다. 같으면 일반이다 (능력치 기획서 4-7).
static func roll_mode(advantage_count: int, disadvantage_count: int) -> RollMode:
	if advantage_count > disadvantage_count:
		return RollMode.ADVANTAGE
	if disadvantage_count > advantage_count:
		return RollMode.DISADVANTAGE
	return RollMode.NORMAL


## 시작 상태의 절대성공면 수 (능력치 기획서 4-11). 1번 면은 모든 주사위에서 절대실패다.
static func absolute_successes(sides: int) -> int:
	return {12: 1, 20: 3}.get(sides, 0)


## 면 자리의 숫자값. 절대성공면은 최댓값, 절대실패면은 1이고 나머지는 자리 번호다.
static func face_value(sides: int, face: int) -> int:
	return sides if face > sides - absolute_successes(sides) else face


## 면 숫자값 평균의 반올림(.5는 올림). AC·DC의 기반이다.
static func standard_value(sides: int) -> int:
	var total: int = 0
	for face: int in range(1, sides + 1):
		total += face_value(sides, face)
	return (2 * total + sides) / (2 * sides)


## 명중굴림: 공격 굴림이 AC 이상이면 명중. 대상은 굴리지 않는다.
static func hit_roll(sides: int, bonus: int, armor_class: int, mode: RollMode, dice: CombatDice) -> RollResult:
	assert(sides > 0)
	var result: RollResult = RollResult.new()
	result.mode = mode
	for count: int in range(1 if mode == RollMode.NORMAL else 2):
		result.rolls.append(face_value(sides, dice.roll(sides)))
	# 두 번 굴린 값은 숫자 순서로 고른다. 숫자값 1과 최댓값(절대성공이 있을 때)은 절대면에만 있다.
	result.selected_roll = result.rolls.max() if mode == RollMode.ADVANTAGE else result.rolls.min()
	result.total = result.selected_roll + bonus
	result.absolute = _absolute_of(sides, result.selected_roll)
	result.success = _hits(sides, result.selected_roll, bonus, armor_class)
	return result


## 면 열거로 구한 실제 명중률. 유리/불리는 두 면의 모든 조합을 센다.
static func hit_chance(sides: int, bonus: int, armor_class: int, mode: RollMode) -> float:
	assert(sides > 0)
	var hits: int = 0
	var second_faces: int = 1 if mode == RollMode.NORMAL else sides
	for first: int in range(1, sides + 1):
		for second: int in range(1, second_faces + 1):
			var value: int = face_value(sides, first)
			if mode == RollMode.ADVANTAGE:
				value = maxi(value, face_value(sides, second))
			elif mode == RollMode.DISADVANTAGE:
				value = mini(value, face_value(sides, second))
			if _hits(sides, value, bonus, armor_class):
				hits += 1
	return hits / float(sides * second_faces)


## 고른 숫자값이 명중인지. 절대면은 가산·AC와 무관하다.
static func _hits(sides: int, value: int, bonus: int, armor_class: int) -> bool:
	var absolute: int = _absolute_of(sides, value)
	return absolute == 1 or (absolute == 0 and value + bonus >= armor_class)


static func _absolute_of(sides: int, value: int) -> int:
	if value == 1:
		return -1
	return 1 if value == sides and absolute_successes(sides) > 0 else 0


static func opposed_attack(attack_sides: int, defense_sides: int,
	attack_bonus: int, defense_bonus: int, mode: RollMode, dice: CombatDice) -> RollResult:
	return defend_against(attack_roll(attack_sides, attack_bonus, mode, dice), defense_sides, defense_bonus, dice)


## 광역 공격이 한 공격 굴림을 모든 대상에 공유한다.
static func attack_roll(sides: int, bonus: int, mode: RollMode, dice: CombatDice) -> RollResult:
	assert(sides > 0)
	var result: RollResult = _roll_die(sides, mode, dice)
	result.total = result.selected_roll + bonus
	return result


static func defend_against(attack_result: RollResult, defense_sides: int,
	defense_bonus: int, dice: CombatDice) -> RollResult:
	assert(defense_sides > 0)
	var result: RollResult = RollResult.new()
	result.rolls = attack_result.rolls.duplicate()
	result.selected_roll = attack_result.selected_roll
	result.total = attack_result.total
	result.mode = attack_result.mode
	result.defender_roll = dice.roll(defense_sides)
	result.defender_total = result.defender_roll + defense_bonus
	result.success = result.total > result.defender_total
	return result


## 흘려내기와 독 제거는 이미 정해진 공격값·강도 이상이면 성공한다.
static func threshold(sides: int, bonus: int, target: int, dice: CombatDice) -> RollResult:
	var result: RollResult = attack_roll(sides, bonus, RollMode.NORMAL, dice)
	result.success = result.total >= target
	return result


static func threshold_chance(sides: int, bonus: int, target: int) -> float:
	assert(sides > 0)
	return clampi(sides + bonus - target + 1, 0, sides) / float(sides)


static func _roll_die(sides: int, mode: RollMode, dice: CombatDice) -> RollResult:
	var result: RollResult = RollResult.new()
	result.mode = mode
	result.rolls.append(dice.roll(sides))
	result.selected_roll = result.rolls[0]
	if mode != RollMode.NORMAL:
		result.rolls.append(dice.roll(sides))
		result.selected_roll = (maxi(result.rolls[0], result.rolls[1])
			if mode == RollMode.ADVANTAGE else mini(result.rolls[0], result.rolls[1]))
	return result
