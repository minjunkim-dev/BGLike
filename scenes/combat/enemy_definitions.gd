class_name CombatEnemyDefinitions
extends RefCounted
## 몬스터의 고정 수치와 사용 동작. 아군 직업 수치와 따로 관리한다.

static var NOVICE_BARBARIAN: Dictionary = {
	"abilities": [10, 6, 4, 4, 4, 4], "defense_bonus": 0,
	"name": TranslationServer.tr("풋내기 야만인"), "max_hit_points": 12,
	"attack_bonus": 3, "damage_bonus": 1, "attack_range": 1,
	"actions": ["attack", "second_wind", "opportunity"]
}
static var NOVICE_ARCHER: Dictionary = {
	"abilities": [4, 10, 4, 4, 4, 4], "defense_bonus": 0,
	"name": TranslationServer.tr("풋내기 궁수"), "max_hit_points": 14,
	"attack_bonus": 0, "damage_bonus": 1, "attack_range": 6,
	"actions": ["attack", "disengage"]
}
static var SCRAP_ROBOT_1000: Dictionary = {
	"abilities": [12, 4, 8, 4, 12, 4], "defense_bonus": 2,
	"name": TranslationServer.tr("고철로봇-1000"), "boss": true, "max_hit_points": 40,
	"movement": 4,
	"attack_bonus": 3, "damage_bonus": 2, "attack_range": 1,
	"actions": ["attack", "opportunity"]
}
static var SCRAP_ROBOT_2000: Dictionary = {
	"abilities": [12, 4, 8, 4, 12, 4], "defense_bonus": 3,
	"name": TranslationServer.tr("고철로봇-2000"), "boss": true, "max_hit_points": 45,
	"movement": 4,
	"attack_bonus": 3, "damage_bonus": 2, "attack_range": 1,
	"actions": ["attack", "opportunity", "pull"]
}
static var SCRAP_ROBOT_3000: Dictionary = {
	"abilities": [12, 4, 8, 4, 12, 4], "defense_bonus": 4,
	"name": TranslationServer.tr("고철로봇-3000"), "boss": true, "max_hit_points": 50,
	"movement": 4,
	"attack_bonus": 3, "damage_bonus": 2, "attack_range": 1,
	"actions": ["attack", "opportunity", "pull", "spin"]
}
static var SPIDERLING: Dictionary = {
	"abilities": [4, 8, 4, 4, 4, 4], "defense_bonus": 0,
	"name": TranslationServer.tr("새끼 거미"), "max_hit_points": 1,
	"attack_bonus": 3, "damage_bonus": 1, "attack_range": 1,
	"actions": ["attack"]
}
static var MOTHER_SPIDER: Dictionary = {
	"abilities": [8, 6, 4, 4, 6, 8], "defense_bonus": 1,
	"name": TranslationServer.tr("엄마 거미"), "max_hit_points": 20,
	"movement": 4,
	"attack_bonus": 3, "damage_bonus": 2, "attack_range": 1,
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
