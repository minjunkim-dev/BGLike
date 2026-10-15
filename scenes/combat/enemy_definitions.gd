class_name CombatEnemyDefinitions
extends RefCounted
## 풋내기의 고정 수치와 사용 동작. 아군 직업 수치와 따로 관리한다.

const NOVICE_BARBARIAN: Dictionary = {
	"name": "풋내기 야만인", "max_hit_points": 12, "armor_class": 12,
	"strength": 3, "dexterity": 1, "constitution": 2, "mental": -2,
	"attack_bonus": 5, "damage_bonus": 1, "damage_sides": 4, "attack_range": 1, "save_dc": 11,
	"actions": ["attack", "second_wind", "opportunity"]
}
const NOVICE_ARCHER: Dictionary = {
	"name": "풋내기 궁수", "max_hit_points": 14, "armor_class": 11,
	"strength": 0, "dexterity": 3, "constitution": 1, "mental": 0,
	"attack_bonus": 5, "damage_bonus": 1, "damage_sides": 4, "attack_range": 6, "save_dc": 11,
	"actions": ["attack", "disengage"]
}


static func for_kind(kind: CombatUnit.Kind) -> Dictionary:
	return NOVICE_BARBARIAN if kind == CombatUnit.Kind.WARRIOR else NOVICE_ARCHER
