class_name CombatLoot
extends RefCounted
## 독립 아이템의 드랍·장착·물약과 파티 공용 가방.

const DATA_PATH: String = "res://scenes/combat/item_data.json"
const ICON_PATH: String = "res://scenes/combat/art/icons/items/%s.png"
const STAT_NAMES: Dictionary = {
	"attack_bonus": "명중", "damage_bonus": "피해", "armor_class": "AC",
	"max_hit_points": "최대 HP"
}

var data: Dictionary
var bag: Array[Dictionary] = []


func _init() -> void:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(DATA_PATH))
	assert(parsed is Dictionary, "아이템 데이터 JSON을 읽을 수 없습니다.")
	data = parsed
	assert(int(data.get("bag_limit", 0)) > 0, "가방 한도는 양수여야 합니다.")
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
		assert(ResourceLoader.exists(icon_path(item)), "아이템 아이콘이 필요합니다.")
		for unit_id: String in item.get("unit_icons", {}):
			assert(ResourceLoader.exists(icon_path(item, unit_id)), "직업별 아이콘이 없습니다.")
		total_weight += int(item["weight"])
		assert(item.get("stats", null) is Dictionary, "stats가 필요합니다. 물약은 빈 객체를 둡니다.")
		for stat: String in item["stats"]:
			assert(stat in STAT_NAMES and item["kind"] != "potion", "지원하지 않는 장비 수치")
			assert(stat != "max_hit_points" or item["kind"] == "armor",
				"최대 HP 효과는 방어구 전용입니다.")
			var act_ranges: Array = item["stats"][stat]
			assert(act_ranges.size() == 3, "장비 수치는 막별 범위3개가 필요합니다.")
			for bounds: Array in act_ranges:
				assert(bounds.size() == 2 and int(bounds[0]) >= 0
					and int(bounds[0]) <= int(bounds[1]), "장비 범위는0이상 최소·최대입니다.")
	assert(total_weight > 0)


func roll_rewards(monster_count: int, dice: CombatDice, act_number: int) -> Array[Dictionary]:
	assert(act_number >= 1 and act_number <= 3, "아이템을 얻은 막은1~3입니다.")
	var rewards: Array[Dictionary] = [_roll_item(dice, act_number)]
	var chance: float = float(data["extra_drop_chance"])
	for index: int in range(monster_count):
		if chance >= 1.0 or dice.chance() < chance:
			rewards.append(_roll_item(dice, act_number))
	return rewards


func _roll_item(dice: CombatDice, act_number: int) -> Dictionary:
	var total: int = 0
	for definition: Dictionary in data["items"]:
		total += int(definition["weight"])
	var ticket: int = dice.roll(total)
	for definition: Dictionary in data["items"]:
		ticket -= int(definition["weight"])
		if ticket > 0:
			continue
		var item: Dictionary = definition.duplicate(true)
		for stat: String in definition["stats"]:
			var bounds: Array = definition["stats"][stat][act_number - 1]
			item["stats"][stat] = dice.roll_between(int(bounds[0]), int(bounds[1]))
		return item
	return {}


func can_receive(unit: CombatUnit, item: Dictionary) -> bool:
	match str(item.get("kind", "")):
		"weapon":
			return unit.weapon.is_empty() or bag.size() < int(data["bag_limit"])
		"armor":
			return unit.armor.is_empty() or bag.size() < int(data["bag_limit"])
		"potion":
			return unit.potion_left < int(data["potion_limit"])
	return false


func receive(unit: CombatUnit, item: Dictionary) -> bool:
	if not can_receive(unit, item):
		return false
	var previous: Dictionary = {}
	match str(item.get("kind", "")):
		"weapon":
			previous = unit.weapon
			unit.weapon = item.duplicate(true)
		"armor":
			previous = unit.armor
			unit.armor = item.duplicate(true)
		"potion":
			unit.potion_left += 1
		_:
			return false
	if not previous.is_empty():
		bag.append(previous)
	return true


func receive_from_bag(unit: CombatUnit, index: int) -> bool:
	if index < 0 or index >= bag.size():
		return false
	var count: int = bag.size()
	var item: Dictionary = bag[index]
	bag.remove_at(index)
	if not receive(unit, item):
		bag.insert(index, item)
		return false
	if bag.size() == count:
		var previous: Dictionary = bag.pop_back()
		bag.insert(index, previous)
	return true


## 방어구를 해제할 수 없는 이유. 해제할 수 있으면 빈 문자열이다. 무기 해제는 지원하지 않는다.
func armor_unequip_blocker(unit: CombatUnit) -> String:
	if unit.armor.is_empty():
		return "장착한 방어구가 없습니다."
	if bag.size() >= int(data["bag_limit"]):
		return "공용 가방에 빈 칸이 없어 해제할 수 없습니다."
	return ""


func unequip_armor(unit: CombatUnit) -> bool:
	if not armor_unequip_blocker(unit).is_empty():
		return false
	bag.append(unit.armor)
	unit.armor = {}
	return true


func transfer_potion(source: CombatUnit, target: CombatUnit) -> bool:
	if source == target or source.potion_left <= 0 or target.potion_left >= int(data["potion_limit"]):
		return false
	source.potion_left -= 1
	target.potion_left += 1
	return true


## 아이템 아이콘 경로. 장착한 직업의 `unit_icons`가 있으면 그 아이콘을 쓴다.
static func icon_path(item: Dictionary, unit_id: String = "") -> String:
	var icon: String = str(item.get("unit_icons", {}).get(unit_id, item.get("icon", "")))
	return "" if icon.is_empty() else ICON_PATH % icon


static func describe(item: Dictionary) -> String:
	if item.is_empty():
		return "없음"
	var text: String = str(item["name"])
	for stat: String in item["stats"]:
		text += " · %s+%d" % [STAT_NAMES[stat], int(item["stats"][stat])]
	return text
