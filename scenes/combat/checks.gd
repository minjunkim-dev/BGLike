class_name CombatChecks
extends RefCounted
## M1 판정 규칙. 주사위 생성기는 호출자가 주어 결과를 재현할 수 있다.

enum RollMode { NORMAL, ADVANTAGE, DISADVANTAGE }


class RollResult extends RefCounted:
	var rolls: Array[int] = []
	var selected_roll: int = 0
	var total: int = 0
	var success: bool = false
	var critical: bool = false
	var mode: RollMode = RollMode.NORMAL


class ContestResult extends RefCounted:
	var attacker_roll: int = 0
	var defender_roll: int = 0
	var attacker_total: int = 0
	var defender_total: int = 0
	var attacker_wins: bool = false


class AttackPreview extends RefCounted:
	var valid_target: bool = false
	var in_range: bool = false
	var chance: float = 0.0
	var mode: RollMode = RollMode.NORMAL
	var reasons: PackedStringArray = []
	var blocked_reason: String = ""


static func roll_mode(advantage_count: int, disadvantage_count: int) -> RollMode:
	if advantage_count > 0 and disadvantage_count == 0:
		return RollMode.ADVANTAGE
	if disadvantage_count > 0 and advantage_count == 0:
		return RollMode.DISADVANTAGE
	return RollMode.NORMAL


static func attack(
	attack_bonus: int, armor_class: int, mode: RollMode, dice: CombatDice
) -> RollResult:
	var result: RollResult = _roll_d20(mode, dice)
	result.total = result.selected_roll + attack_bonus
	result.critical = result.selected_roll == 20
	result.success = _attack_hits(result.selected_roll, attack_bonus, armor_class)
	return result


static func saving_throw(modifier: int, dc: int, dice: CombatDice) -> RollResult:
	var result: RollResult = _roll_d20(RollMode.NORMAL, dice)
	result.total = result.selected_roll + modifier
	# 내성은 1과 20도 합계로만 판단한다.
	result.success = result.total >= dc
	return result


static func contest(
	attacker_modifier: int, defender_modifier: int, dice: CombatDice
) -> ContestResult:
	var result: ContestResult = ContestResult.new()
	result.attacker_roll = dice.roll(20)
	result.defender_roll = dice.roll(20)
	result.attacker_total = result.attacker_roll + attacker_modifier
	result.defender_total = result.defender_roll + defender_modifier
	result.attacker_wins = result.attacker_total > result.defender_total
	return result


static func hit_chance(attack_bonus: int, armor_class: int, mode: RollMode) -> float:
	var hits: int = 0
	for natural: int in range(1, 21):
		if _attack_hits(natural, attack_bonus, armor_class):
			hits += 1
	var normal: float = hits / 20.0
	match mode:
		RollMode.ADVANTAGE:
			return 1.0 - (1.0 - normal) * (1.0 - normal)
		RollMode.DISADVANTAGE:
			return normal * normal
	return normal


static func _roll_d20(mode: RollMode, dice: CombatDice) -> RollResult:
	var result: RollResult = RollResult.new()
	result.mode = mode
	result.rolls.append(dice.roll(20))
	result.selected_roll = result.rolls[0]
	if mode != RollMode.NORMAL:
		result.rolls.append(dice.roll(20))
		result.selected_roll = (maxi(result.rolls[0], result.rolls[1])
			if mode == RollMode.ADVANTAGE else mini(result.rolls[0], result.rolls[1]))
	return result


static func _attack_hits(natural: int, bonus: int, armor_class: int) -> bool:
	return natural == 20 or (natural != 1 and natural + bonus >= armor_class)
