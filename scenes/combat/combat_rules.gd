class_name CombatRules
## 주사위와 판정 규칙(SRD 5e 기준). 판정 규칙을 바꿀 때는 이 파일만 고친다.

const PROFICIENCY_BONUS := 2


static func roll(rng: RandomNumberGenerator, sides: int) -> int:
	return rng.randi_range(1, sides)


static func attack_bonus(attacker: Unit) -> int:
	return attacker.attack_mod() + PROFICIENCY_BONUS


## 1은 자동 실패, 20은 자동 명중.
static func is_hit(d20: int, bonus: int, armor_class: int) -> bool:
	if d20 == 1:
		return false
	if d20 == 20:
		return true
	return d20 + bonus >= armor_class


static func hit_chance(bonus: int, armor_class: int) -> float:
	var hits := 0
	for d20 in range(1, 21):
		if is_hit(d20, bonus, armor_class):
			hits += 1
	return hits / 20.0


## 반환값: { "total": 이니셔티브, "text": 로그 }
static func roll_initiative(rng: RandomNumberGenerator, unit: Unit) -> Dictionary:
	var d20 := roll(rng, 20)
	var total := d20 + unit.dex_mod
	return {
		"total": total,
		"text": "이니셔티브 %s: d20(%d)%+d=%d" % [unit.label(), d20, unit.dex_mod, total],
	}


## 반환값: { "damage": 피해량(빗나가면 0), "crit": 치명타 여부, "text": 로그 }
## 치명타는 피해 주사위를 두 번 굴린다.
static func resolve_attack(rng: RandomNumberGenerator, attacker: Unit, target: Unit) -> Dictionary:
	var d20 := roll(rng, 20)
	var bonus := attack_bonus(attacker)
	var text := "%s → %s: d20(%d)%+d=%d vs AC %d" % [
		attacker.label(), target.label(), d20, bonus, d20 + bonus, target.armor_class]
	if not is_hit(d20, bonus, target.armor_class):
		return {"damage": 0, "crit": false, "text": text + " 빗나감"}

	var crit := d20 == 20
	var dice := 2 if crit else 1
	var faces := PackedStringArray()
	var sum := 0
	for i in dice:
		var face := roll(rng, attacker.damage_die)
		faces.append(str(face))
		sum += face
	var damage := maxi(0, sum + attacker.attack_mod())
	text += " %s, %dd%d(%s)%+d=%d 피해" % [
		"치명타!" if crit else "명중", dice, attacker.damage_die, "+".join(faces), attacker.attack_mod(), damage]
	return {"damage": damage, "crit": crit, "text": text}
