class_name CombatChecks
extends RefCounted
## 판정 규칙. 주사위 생성기는 호출자가 주어 결과를 재현할 수 있다.

enum RollMode { NORMAL, ADVANTAGE, DISADVANTAGE }
## 절대면(능력치 기획서 4-11). 숫자로는 절대성공이 최댓값, 절대실패가 1이다.
enum Face { NORMAL, ABSOLUTE_SUCCESS, ABSOLUTE_FAILURE }


class RollResult extends RefCounted:
	var rolls: Array[int] = []
	var selected_roll: int = 0
	var total: int = 0
	var defender_roll: int = 0
	var defender_total: int = 0
	var success: bool = false
	var face: Face = Face.NORMAL
	var mode: RollMode = RollMode.NORMAL


class AttackPreview extends RefCounted:
	var valid_target: bool = false
	var in_range: bool = false
	var chance: float = 0.0
	var mode: RollMode = RollMode.NORMAL
	var reasons: PackedStringArray = []
	var blocked_reason: String = ""


## 굴림 하나에 붙은 유리·불리 요인 수를 비교한다. 같으면 일반이다 (4-7).
static func roll_mode(advantage_count: int, disadvantage_count: int) -> RollMode:
	if advantage_count > disadvantage_count:
		return RollMode.ADVANTAGE
	if disadvantage_count > advantage_count:
		return RollMode.DISADVANTAGE
	return RollMode.NORMAL


## 시작 상태의 절대성공면 수. d12 1개, d20 3개(시험용으로 최대치를 채움), 나머지는 없다.
static func absolute_success_faces(sides: int) -> int:
	return 3 if sides == 20 else (1 if sides == 12 else 0)


## 굴린 면(1~n)의 숫자 값. 가장 높은 일반면부터 절대성공면이 되어 최댓값으로 센다.
## 성장 전이라 주사위 레벨은 0이며 더하지 않는다 (#322).
static func face_value(sides: int, face: int) -> int:
	return sides if face > sides - absolute_success_faces(sides) else face


## 숫자 값의 면 종류. 절대성공면만 최댓값을, 절대실패면(첫 면)만 1을 가진다.
static func face_kind(sides: int, value: int) -> Face:
	if value == 1:
		return Face.ABSOLUTE_FAILURE
	if value == sides and absolute_success_faces(sides) > 0:
		return Face.ABSOLUTE_SUCCESS
	return Face.NORMAL


## 면 값 평균의 반올림(.5는 올림). AC·DC의 기반이다 (4-3).
static func standard_value(sides: int) -> int:
	var total: int = 0
	for face: int in range(1, sides + 1):
		total += face_value(sides, face)
	return (2 * total + sides) / (2 * sides)


## 명중굴림: 공격 굴림이 AC 이상이면 명중. 방어자는 굴리지 않는다.
static func hit_roll(sides: int, bonus: int, armor_class: int, mode: RollMode, dice: CombatDice) -> RollResult:
	return _roll_against(sides, bonus, armor_class, mode, dice)


## 내성굴림: 대상의 내성 굴림(내성 능력치 주사위 + 방어 가산)이 DC 이상이면 성공. 시전자는 굴리지 않는다 (4-1).
static func saving_throw(sides: int, bonus: int, dc: int, mode: RollMode, dice: CombatDice) -> RollResult:
	return _roll_against(sides, bonus, dc, mode, dice)


## DC = 시전 능력치 표준값 + 공격 가산 + 스킬의 DC 보정. 대상의 내성 능력치와 무관하다 (4-3).
static func save_dc(sides: int, attack_bonus: int, dc_bonus: int = 0) -> int:
	return standard_value(sides) + attack_bonus + dc_bonus


## 내성에 성공한 피해형 효과의 피해. 절반을 내림하고 최소 1이다 (4-1).
static func halve_damage(amount: int) -> int:
	return maxi(1, amount / 2)


## 면 열거로 구한 실제 명중률. 유리/불리는 두 면의 모든 조합을 센다.
static func hit_chance(sides: int, bonus: int, armor_class: int, mode: RollMode) -> float:
	return _chance_against(sides, bonus, armor_class, mode)


## 면 열거로 구한 실제 내성 성공률 (4-10).
static func save_chance(sides: int, bonus: int, dc: int, mode: RollMode) -> float:
	return _chance_against(sides, bonus, dc, mode)


## 명중굴림과 내성굴림은 굴리는 쪽만 다르고 "기준값 이상이면 성공"으로 같다.
static func _roll_against(sides: int, bonus: int, target: int, mode: RollMode, dice: CombatDice) -> RollResult:
	var result: RollResult = attack_roll(sides, bonus, mode, dice)
	result.face = face_kind(sides, result.selected_roll)
	result.success = _hits(result.face, result.total, target)
	return result


static func _chance_against(sides: int, bonus: int, target: int, mode: RollMode) -> float:
	assert(sides > 0)
	var hits: int = 0
	var second_faces: int = 1 if mode == RollMode.NORMAL else sides
	for first: int in range(1, sides + 1):
		for second: int in range(1, second_faces + 1):
			var value: int = face_value(sides, first)
			if mode != RollMode.NORMAL:
				var other: int = face_value(sides, second)
				value = maxi(value, other) if mode == RollMode.ADVANTAGE else mini(value, other)
			if _hits(face_kind(sides, value), value + bonus, target):
				hits += 1
	return hits / float(sides * second_faces)


## 피해 굴림: 피해 능력치 주사위를 새로 굴린 숫자 값. 유리/불리는 적용하지 않는다 (4-9).
static func damage_roll(sides: int, dice: CombatDice) -> int:
	assert(sides > 0)
	return face_value(sides, dice.roll(sides))


static func _hits(face: Face, total: int, target: int) -> bool:
	if face != Face.NORMAL:
		return face == Face.ABSOLUTE_SUCCESS
	return total >= target


## 밀치기·만능팔에만 남은 대결. 동점은 방어자 승이다. 이 두 동작의 내성굴림 이관은 후속 티켓이다.
static func opposed_attack(attack_sides: int, defense_sides: int,
	attack_bonus: int, defense_bonus: int, mode: RollMode, dice: CombatDice) -> RollResult:
	assert(defense_sides > 0)
	var result: RollResult = attack_roll(attack_sides, attack_bonus, mode, dice)
	result.defender_roll = face_value(defense_sides, dice.roll(defense_sides))
	result.defender_total = result.defender_roll + defense_bonus
	result.success = result.total > result.defender_total
	return result


## 굴리는 쪽의 능력치 주사위(유리/불리면 두 번) + 가산. 기준값 비교는 호출자가 한다.
static func attack_roll(sides: int, bonus: int, mode: RollMode, dice: CombatDice) -> RollResult:
	assert(sides > 0)
	var result: RollResult = _roll_die(sides, mode, dice)
	result.total = result.selected_roll + bonus
	return result


## 흘려내기는 이미 굴린 공격 굴림 이상이면 성공한다.
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
	result.rolls.append(face_value(sides, dice.roll(sides)))
	result.selected_roll = result.rolls[0]
	if mode != RollMode.NORMAL:
		result.rolls.append(face_value(sides, dice.roll(sides)))
		result.selected_roll = (maxi(result.rolls[0], result.rolls[1])
			if mode == RollMode.ADVANTAGE else mini(result.rolls[0], result.rolls[1]))
	return result
