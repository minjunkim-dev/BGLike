class_name CombatDiceRoll
extends RefCounted
## 화면에 보일 굴림 하나. 규칙은 CombatChecks가 이미 확정했고 연출은 이 값을 보이기만 한다.

## 연출이 있는 굴림 종류. 다른 굴림(피해·회복·이니셔티브·무작위 선택)은 연출하지 않는다.
enum Category { HIT, SAVE }

var category: Category
var roller: CombatUnit
var sides: int
var result: CombatChecks.RollResult
var bonus: int
## 기준값의 이름과 값. 명중은 AC, 흘려내기는 공격, 독 제거는 강도다.
var target_label: String
var target_value: int


## 명중굴림. 면 열거 결과에 절대성공·절대실패가 담긴다.
static func hit(roller: CombatUnit, sides: int, result: CombatChecks.RollResult,
		bonus: int, armor_class: int) -> CombatDiceRoll:
	return _create(Category.HIT, roller, sides, result, bonus, TranslationServer.translate("AC"), armor_class)


## 기준값 이상이면 성공하는 굴림(흘려내기·독 제거).
static func save(roller: CombatUnit, sides: int, result: CombatChecks.RollResult,
		bonus: int, target_label: String, target_value: int) -> CombatDiceRoll:
	return _create(Category.SAVE, roller, sides, result, bonus, target_label, target_value)


static func _create(category: Category, roller: CombatUnit, sides: int, result: CombatChecks.RollResult,
		bonus: int, target_label: String, target_value: int) -> CombatDiceRoll:
	var roll: CombatDiceRoll = CombatDiceRoll.new()
	roll.category = category
	roll.roller = roller
	roll.sides = sides
	roll.result = result
	roll.bonus = bonus
	roll.target_label = target_label
	roll.target_value = target_value
	return roll
