class_name CombatLoot
extends RefCounted
## 보상은 독립 Dictionary로 보관한다. 수령한 장비만 캐릭터 장착 칸에 남는다.

const DATA_PATH: String = "res://scenes/combat/item_data.json"
const STAT_NAMES: Dictionary = {
	"attack_bonus": "명중", "damage_bonus": "피해", "armor_class": "AC"
}

var data: Dictionary


func _init() -> void:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(DATA_PATH))
	assert(parsed is Dictionary, "아이템 데이터 JSON을 읽을 수 없습니다.")
	data = parsed
	assert(int(data.get("potion_limit", 0)) > 0, "물약 한도는 양수여야 합니다.")
	assert(float(data.get("extra_drop_chance", -1)) >= 0.0
		and float(data["extra_drop_chance"]) <= 1.0, "추가 드랍 확률은0~1이어야 합니다.")
	var definitions: Variant = data.get("items", null)
	assert(definitions is Array and not definitions.is_empty(),
		"아이템 종류가 필요합니다.")
	var total_weight: int = 0
	for item: Dictionary in data["items"]:
		assert(item.get("kind", "") in ["weapon", "armor", "potion"], "알 수 없는 아이템 종류")
		assert(not str(item.get("name", "")).is_empty(), "아이템 이름이 필요합니다.")
		assert(int(item.get("weight", 0)) > 0, "아이템 추첨 비중은 양수여야 합니다.")
		total_weight += int(item["weight"])
		assert(item.get("stats", null) is Dictionary, "stats가 필요합니다. 물약은 빈 객체를 둡니다.")
		for stat: String in item["stats"]:
			var bounds: Array = item["stats"][stat]
			assert(stat in STAT_NAMES and item["kind"] != "potion", "지원하지 않는 장비 수치")
			assert(bounds.size() == 2 and int(bounds[0]) >= 0
				and int(bounds[0]) <= int(bounds[1]), "장비 범위는0이상 최소·최대입니다.")
	assert(total_weight > 0)


func roll_rewards(monster_count: int, dice: RandomNumberGenerator) -> Array[Dictionary]:
	var rewards: Array[Dictionary] = [_roll_item(dice)]
	var chance: float = float(data["extra_drop_chance"])
	for index: int in range(monster_count):
		if chance >= 1.0 or dice.randf() < chance:
			rewards.append(_roll_item(dice))
	return rewards


func _roll_item(dice: RandomNumberGenerator) -> Dictionary:
	var total: int = 0
	for definition: Dictionary in data["items"]:
		total += int(definition["weight"])
	var ticket: int = dice.randi_range(1, total)
	for definition: Dictionary in data["items"]:
		ticket -= int(definition["weight"])
		if ticket > 0:
			continue
		var item: Dictionary = definition.duplicate(true)
		for stat: String in definition["stats"]:
			var bounds: Array = definition["stats"][stat]
			item["stats"][stat] = dice.randi_range(int(bounds[0]), int(bounds[1]))
		return item
	return {}


func receive(unit: CombatUnit, item: Dictionary) -> bool:
	match str(item.get("kind", "")):
		"weapon":
			unit.weapon = item.duplicate(true)
		"armor":
			unit.armor = item.duplicate(true)
		"potion":
			if unit.potion_left >= int(data["potion_limit"]):
				return false
			unit.potion_left += 1
		_:
			return false
	return true


func transfer_potion(source: CombatUnit, target: CombatUnit) -> bool:
	if source == target or source.potion_left <= 0 or target.potion_left >= int(data["potion_limit"]):
		return false
	source.potion_left -= 1
	target.potion_left += 1
	return true


static func describe(item: Dictionary) -> String:
	if item.is_empty():
		return "없음"
	var text: String = str(item["name"])
	for stat: String in item["stats"]:
		text += " · %s+%d" % [STAT_NAMES[stat], int(item["stats"][stat])]
	return text
