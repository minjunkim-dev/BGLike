class_name CombatEnemyDefinitions
extends RefCounted
## 몬스터의 고정 수치와 사용 동작. 아군 직업 수치와 따로 관리한다.

static var NOVICE_BARBARIAN: Dictionary = {
	"name": TranslationServer.tr("풋내기 야만인"), "max_hit_points": 12, "armor_class": 12,
	"strength": 3, "dexterity": 1, "constitution": 2, "mental": -2,
	"attack_bonus": 5, "damage_bonus": 1, "damage_sides": 4, "attack_range": 1, "save_dc": 11,
	"actions": ["attack", "second_wind", "opportunity"]
}
static var NOVICE_ARCHER: Dictionary = {
	"name": TranslationServer.tr("풋내기 궁수"), "max_hit_points": 14, "armor_class": 11,
	"strength": 0, "dexterity": 3, "constitution": 1, "mental": 0,
	"attack_bonus": 5, "damage_bonus": 1, "damage_sides": 4, "attack_range": 6, "save_dc": 11,
	"actions": ["attack", "disengage"]
}
static var SCRAP_ROBOT_1000: Dictionary = {
	"name": TranslationServer.tr("고철로봇-1000"), "boss": true, "max_hit_points": 40, "armor_class": 14,
	"strength": 3, "dexterity": -1, "constitution": 3, "mental": 0, "movement": 4,
	"attack_bonus": 5, "damage_bonus": 2, "damage_sides": 8, "attack_range": 1, "save_dc": 13,
	"actions": ["attack", "opportunity"]
}
static var SCRAP_ROBOT_2000: Dictionary = {
	"name": TranslationServer.tr("고철로봇-2000"), "boss": true, "max_hit_points": 45, "armor_class": 15,
	"strength": 3, "dexterity": -1, "constitution": 3, "mental": 0, "movement": 4,
	"attack_bonus": 5, "damage_bonus": 2, "damage_sides": 8, "attack_range": 1, "save_dc": 13,
	"actions": ["attack", "opportunity", "pull"]
}
static var SCRAP_ROBOT_3000: Dictionary = {
	"name": TranslationServer.tr("고철로봇-3000"), "boss": true, "max_hit_points": 50, "armor_class": 16,
	"strength": 3, "dexterity": -1, "constitution": 3, "mental": 0, "movement": 4,
	"attack_bonus": 5, "damage_bonus": 2, "damage_sides": 8, "attack_range": 1, "save_dc": 13,
	"actions": ["attack", "opportunity", "pull", "spin"]
}
static var SPIDERLING: Dictionary = {
	"name": TranslationServer.tr("새끼 거미"), "max_hit_points": 1, "armor_class": 6,
	"strength": 0, "dexterity": 2, "constitution": -2, "mental": -2,
	"attack_bonus": 4, "damage_bonus": 1, "damage_sides": 0, "attack_range": 1, "save_dc": 10,
	"actions": ["attack"]
}
static var MOTHER_SPIDER: Dictionary = {
	"name": TranslationServer.tr("엄마 거미"), "max_hit_points": 20, "armor_class": 13,
	"strength": 2, "dexterity": 0, "constitution": 2, "mental": 1, "movement": 4,
	"attack_bonus": 4, "damage_bonus": 2, "damage_sides": 6, "attack_range": 1, "save_dc": 12,
	"actions": ["attack", "spawn", "opportunity"]
}


static func for_kind(kind: CombatUnit.Kind) -> Dictionary:
	if kind == CombatUnit.Kind.SCRAP_ROBOT_3000:
		return SCRAP_ROBOT_3000
	if kind == CombatUnit.Kind.SCRAP_ROBOT_2000:
		return SCRAP_ROBOT_2000
	if kind == CombatUnit.Kind.SCRAP_ROBOT_1000:
		return SCRAP_ROBOT_1000
	if kind == CombatUnit.Kind.MOTHER_SPIDER:
		return MOTHER_SPIDER
	if kind == CombatUnit.Kind.SPIDERLING:
		return SPIDERLING
	return NOVICE_BARBARIAN if kind == CombatUnit.Kind.WARRIOR else NOVICE_ARCHER
