class_name CombatActionRules
extends RefCounted
## 스킬과 공용 동작의 정의. 비용 자원, 직업 제한, 막당 횟수와 설명을 한 곳에 둔다.

## 비용 자원(행동, 보조 행동, 반응) 순서의 묶음. HUD의 배치 순서이기도 하다.
## 복합 비용 스킬은 첫 자원의 묶음에 둔다(십자 베기는 임시로 행동, 9-3).
const GROUPS: Array[Array] = [
	["attack", "sweep", "cross_slash", "battle_cry", "shock", "spawn", "pull", "spin"],
	["holy_veil", "steel_charge", "second_wind", "mark", "disengage", "shove", "jump", "potion"],
	["opportunity"]
]
## 묶음의 자원과 함께 모두 소비하는 비용. 하나라도 부족하면 쓸 수 없다 (5-3). 점프의 이동력은 칸마다 다르다.
const EXTRA_COSTS: Dictionary[String, String] = {
	"cross_slash": "bonus_action", "steel_charge": "movement", "jump": "movement"
}
static var NAMES: Dictionary[String, String] = {
	"attack": TranslationServer.tr("공격"), "second_wind": TranslationServer.tr("숨 고르기"),
	"sweep": TranslationServer.tr("휩쓸기"), "cross_slash": TranslationServer.tr("십자 베기"), "steel_charge": TranslationServer.tr("강철 돌진"),
	"holy_veil": TranslationServer.tr("성스러운 장막"), "battle_cry": TranslationServer.tr("전투의 함성"),
	"mark": TranslationServer.tr("표식"), "shock": TranslationServer.tr("충격 화살"), "disengage": TranslationServer.tr("물러서며 쏘기"),
	"shove": TranslationServer.tr("밀치기"), "potion": TranslationServer.tr("물약"), "opportunity": TranslationServer.tr("기회 공격"),
	"spawn": TranslationServer.tr("새끼 낳기"), "pull": TranslationServer.tr("만능팔"), "spin": TranslationServer.tr("회전회오리"), "jump": TranslationServer.tr("점프")
}
static var EFFECTS: Dictionary[String, String] = {
	"jump": TranslationServer.tr("1~2칸의 빈 바닥으로 점프.\n상승2까지, 낙하 차3부터 피해."),
	"spawn": TranslationServer.tr("인접한 빈 칸에 새끼 거미1마리를 만듭니다."),
	"spin": TranslationServer.tr("상하좌우1칸·높이 차이1 이하인 모든 아군이 각자 힘 내성굴림.\n성공하면 피해 절반. 밀어내지 않습니다. 횟수와 쉬는 턴 제한 없음."),
	"second_wind": TranslationServer.tr("HP 1d10+1 회복.\n최대 HP를 넘지 않습니다."),
	"sweep": TranslationServer.tr("인접한 칸을 골라 정면을 정하고\n정면 반달 5칸의 적만 시계방향으로\n각각 공격합니다. 아군은 맞지 않습니다."),
	"cross_slash": TranslationServer.tr("인접한 적 1명을 기본 공격 2회.\n첫 타격으로 쓰러지면 둘째는 취소."),
	"steel_charge": TranslationServer.tr("인접한 적을 공격. 명중하면 피해 후\n1칸 밀치고 빈 칸으로 1칸 전진.\n밀 수 없으면 피해만. 전진은 기회 공격 없음."),
	"holy_veil": TranslationServer.tr("건강 굴림값만큼 방어막.\nHP보다 먼저 모든 피해를 받습니다.\n3턴. 다시 쓰면 큰 값을 유지합니다."),
	"battle_cry": TranslationServer.tr("의지 굴림값을 모든 아군의\n명중굴림에 더합니다. 2턴.\n전사가 쓰러져도 유지됩니다."),
	"mark": TranslationServer.tr("1~6칸 적에게 표식.\n이 궁수가 맞히면 피해 +1d6.\n전투 중 유지됩니다."),
	"shock": TranslationServer.tr("1~6칸 공격.\n명중하면 기절. 보스는 기절 면역."),
	"pull": TranslationServer.tr("2~3칸 대상을 끌어옵니다. 대상이 힘 내성굴림에\n성공하면 버팁니다. 피해와 기회 공격 없음.\n다음 턴에는 쓸 수 없습니다."),
	"disengage": TranslationServer.tr("이번 턴의 남은 이동에서\n기회 공격을 받지 않습니다.\n공격을 실행하지 않습니다."),
	"shove": TranslationServer.tr("대상이 힘 내성굴림.\n실패하면 1칸 밀리고, 성공하면 버팁니다.\n기절 대상은 내성 없이 밀림.\n아군은 판정 없이 밀림."),
	"potion": TranslationServer.tr("HP 2d4+2 회복.\n최대 HP를 넘지 않습니다."),
	"opportunity": TranslationServer.tr("적이 내 인접 칸을 벗어나면 기본 공격.")
}
## 대상 없이 바로 쓰는 동작.
const SELF_TARGET: Array[String] = ["holy_veil", "battle_cry", "second_wind", "disengage", "potion"]
## 표식과 충격 화살의 사거리.
const SKILL_RANGE: int = 6
## 아군 직업의 고유 동작과 패시브(팔랑크스, 괴력의 사내). 몬스터의 동작은 정의의 actions가 정한다.
const CLASS_ONLY: Dictionary[String, CombatUnit.Kind] = {
	"sweep": CombatUnit.Kind.WARRIOR, "cross_slash": CombatUnit.Kind.WARRIOR, "steel_charge": CombatUnit.Kind.WARRIOR,
	"holy_veil": CombatUnit.Kind.WARRIOR, "battle_cry": CombatUnit.Kind.WARRIOR,
	"phalanx": CombatUnit.Kind.WARRIOR, "brawn": CombatUnit.Kind.WARRIOR,
	"mark": CombatUnit.Kind.ARCHER, "shock": CombatUnit.Kind.ARCHER, "disengage": CombatUnit.Kind.ARCHER
}
## 아군이 쓰지 않는 몬스터 동작. 풋내기 야만인의 숨 고르기도 여기 있다.
const MONSTER_ONLY: Array[String] = ["second_wind", "spawn", "pull", "spin"]
const USE_COUNTERS: Dictionary[String, StringName] = {
	"second_wind": &"second_wind_left", "mark": &"mark_left",
	"shock": &"shock_left", "disengage": &"disengage_left", "potion": &"potion_left",
	"cross_slash": &"cross_slash_left", "steel_charge": &"steel_charge_left", "battle_cry": &"battle_cry_left"
}
## 막 시작에 회복하는 횟수. 물약은 보유 개수라서 회복하지 않는다.
const USES_PER_ACT: Dictionary[String, int] = {
	"second_wind": 1, "mark": 1, "shock": 1, "disengage": 2
}
## 새 전투(스테이지)가 시작될 때 회복하는 횟수 (5-3).
const USES_PER_COMBAT: Dictionary[String, int] = {
	"cross_slash": 1, "steel_charge": 1, "battle_cry": 1
}
## 성스러운 장막과 전투의 함성의 기간. 시전자 턴 시작마다 1씩 준다.
const SHIELD_TURNS: int = 3
const BATTLE_CRY_TURNS: int = 2
## 피해 능력치를 명중 능력치와 다르게 지정한 동작 (능력치 기획서 4-9). 지금 있는 스킬은 모두 같아 비어 있다.
## 동작 이름으로 찾으므로 기회 공격("opportunity")은 "attack"과 따로 지정한다.
static var DAMAGE_ABILITIES: Dictionary[String, CombatUnit.Ability] = {}
## 내성굴림 동작의 시전 능력치(DC)와 대상의 내성 능력치 (4-3, 8장). 기존 동작은 현행(힘)을 유지한다.
const CAST_ABILITIES: Dictionary[String, CombatUnit.Ability] = {
	"spin": CombatUnit.Ability.STRENGTH, "shove": CombatUnit.Ability.STRENGTH, "pull": CombatUnit.Ability.STRENGTH
}
const SAVE_ABILITIES: Dictionary[String, CombatUnit.Ability] = {
	"spin": CombatUnit.Ability.STRENGTH, "shove": CombatUnit.Ability.STRENGTH, "pull": CombatUnit.Ability.STRENGTH
}
## 스킬의 DC 보정. 지정이 없으면 0이다. 지금 있는 스킬은 모두 0이라 비어 있다.
static var DC_BONUSES: Dictionary[String, int] = {}
## 아군 스킬과 공용 동작의 아이콘. 48px 원본(64px 설계 격자)이다.
const ICON_PATH: String = "res://scenes/combat/art/icons/skills/%s.png"
## #362: 스킬과 정비 아이템 그림의 표시 크기(논리 px). 버튼·칸의 입력 영역은 각 화면이 따로 유지한다.
const ICON_SIZE: int = 24


static func resource_of(action: String) -> CombatUnit.TurnResource:
	for index: int in range(GROUPS.size()):
		if action in GROUPS[index]:
			return index as CombatUnit.TurnResource
	return CombatUnit.TurnResource.ACTION


## 동작의 피해 굴림 능력치. 지정이 없으면 명중 능력치, 내성굴림 동작은 시전 능력치다.
static func damage_ability(actor: CombatUnit, action: String) -> CombatUnit.Ability:
	return DAMAGE_ABILITIES.get(action, CAST_ABILITIES.get(action, actor.get_attack_ability()))


## 시전 때 정하는 내성굴림 동작의 DC. 대상이 어떤 능력치로 막든 같다 (4-3).
static func save_dc(actor: CombatUnit, action: String) -> int:
	return CombatChecks.save_dc(actor.get_ability_sides(CAST_ABILITIES[action]), actor.get_attack_bonus(),
		DC_BONUSES.get(action, 0))


static func belongs_to(actor: CombatUnit, action: String) -> bool:
	if action == "jump":
		return true
	# 기회 공격은 근접 기본 공격을 가진 모든 유닛의 공용 동작이다 (5-2).
	if action == "opportunity":
		return actor.get_attack_range() == 1
	if not actor.is_ally:
		return action in CombatEnemyDefinitions.for_kind(actor.kind)["actions"]
	return action not in MONSTER_ONLY and (action not in CLASS_ONLY or actor.kind == CLASS_ONLY[action])


## 남은 횟수. 횟수 제한이 없는 동작은 -1이다.
static func uses_left(actor: CombatUnit, action: String) -> int:
	return int(actor.get(USE_COUNTERS[action])) if action in USE_COUNTERS else -1


## 직업이 쓸 수 있고 횟수가 남았는지. 턴 자원과 대상은 확인하지 않는다.
static func has_uses(actor: CombatUnit, action: String) -> bool:
	return belongs_to(actor, action) and (action not in USE_COUNTERS or uses_left(actor, action) > 0)


static func spend_use(actor: CombatUnit, action: String) -> void:
	if action in USE_COUNTERS:
		actor.set(USE_COUNTERS[action], uses_left(actor, action) - 1)


static func restore_uses(unit: CombatUnit) -> void:
	for action: String in USES_PER_ACT:
		unit.set(USE_COUNTERS[action], USES_PER_ACT[action])


static func restore_combat_uses(unit: CombatUnit) -> void:
	for action: String in USES_PER_COMBAT:
		unit.set(USE_COUNTERS[action], USES_PER_COMBAT[action])


## 복합 비용의 호버 문구. 자원 하나만 쓰는 동작은 빈 문자열이다 (5-3).
static func cost_text(action: String) -> String:
	if action not in EXTRA_COSTS:
		return ""
	var names: Array[String] = [TranslationServer.tr("행동 1"), TranslationServer.tr("보조 행동 1")]
	var extra: String = {"bonus_action": TranslationServer.tr("보조 행동 1"), "movement": TranslationServer.tr("이동력 1")}[EXTRA_COSTS[action]]
	if action == "jump":
		extra = TranslationServer.tr("이동력(칸 수와 오르는 높이)")
	return TranslationServer.tr("비용: %s + %s") % [names[resource_of(action)], extra]


## 전투마다 횟수의 호버 문구. 전투 중에는 남은 횟수를 함께 보인다 (5-3).
static func combat_uses_text(actor: CombatUnit, action: String) -> String:
	if action not in USES_PER_COMBAT:
		return ""
	return TranslationServer.tr("전투마다 %d회 · %d회 남음") % [USES_PER_COMBAT[action], uses_left(actor, action)]


## 동작의 피해 보정. 강철 돌진은 기타 가산치를 더하지 않는다 (전사 문서).
static func damage_bonus(actor: CombatUnit, action: String) -> int:
	return 0 if action == "steel_charge" else actor.get_damage_bonus()


## 적 전용 스킬처럼 아이콘이 없으면 null이다.
static func icon_of(action: String) -> Texture2D:
	var path: String = ICON_PATH % action
	return load(path) as Texture2D if ResourceLoader.exists(path) else null


## 호버의 사거리·피해 또는 회복·판정 줄. 현재 장비의 명중·피해 보정을 반영한다.
## 회전회오리는 units 가운데 살아 있는 반대편 유닛마다 내성 성공률을 더한다.
static func details(actor: CombatUnit, action: String, units: Array[CombatUnit] = []) -> String:
	var melee: bool = actor.get_attack_range() == 1
	var weapon: String = damage_text(actor, action)
	var hit: String = TranslationServer.tr("%s d%d %+d 대 AC") % [CombatUnit.ability_name(actor.get_attack_ability()),
		actor.get_ability_sides(actor.get_attack_ability()), actor.get_hit_bonus()]
	var lines: Array[String] = []
	match action:
		"attack", "opportunity", "cross_slash", "steel_charge":
			lines = [TranslationServer.tr("사거리: 인접1칸") if melee else TranslationServer.tr("사거리: 1~%d칸") % actor.get_attack_range(), weapon,
				TranslationServer.tr("판정: %s") % hit]
		"sweep":
			var bonus: int = damage_bonus(actor, action)
			lines = [TranslationServer.tr("사거리: 정면 반달 5칸"), TranslationServer.tr("피해: %s d%d ÷2 올림%s") % [
				CombatUnit.ability_name(damage_ability(actor, action)), actor.get_ability_sides(damage_ability(actor, action)),
				"" if bonus == 0 else " %+d" % bonus], TranslationServer.tr("판정: 대상마다 %s") % hit]
		"shock":
			lines = [TranslationServer.tr("사거리: 1~%d칸") % SKILL_RANGE, weapon, TranslationServer.tr("판정: %s, 명중하면 기절") % hit]
		"mark":
			lines = [TranslationServer.tr("사거리: 1~%d칸") % SKILL_RANGE, TranslationServer.tr("판정: 없음")]
		"shove":
			lines = [TranslationServer.tr("사거리: 인접1칸"), TranslationServer.tr("판정: 대상의 %s 내성 대 DC %d, 성공하면 버팀") % [
				CombatUnit.ability_name(SAVE_ABILITIES[action]), save_dc(actor, action)]]
		"pull":
			lines = [TranslationServer.tr("사거리: 2~3칸"), TranslationServer.tr("판정: 대상의 %s 내성 대 DC %d, 성공하면 버팀") % [
				CombatUnit.ability_name(SAVE_ABILITIES[action]), save_dc(actor, action)]]
		"jump":
			lines = [TranslationServer.tr("사거리: 1~2칸"), TranslationServer.tr("판정: 없음")]
		"second_wind":
			lines = [TranslationServer.tr("사거리: 자신"), TranslationServer.tr("회복: 1d10+1"), TranslationServer.tr("판정: 없음")]
		"potion":
			lines = [TranslationServer.tr("사거리: 자신"), TranslationServer.tr("회복: 2d4+2"), TranslationServer.tr("판정: 없음")]
		"disengage":
			lines = [TranslationServer.tr("사거리: 자신"), TranslationServer.tr("판정: 없음")]
		"holy_veil":
			lines = [TranslationServer.tr("사거리: 자신"), TranslationServer.tr("방어막: 건강 d%d") % actor.get_ability_sides(CombatUnit.Ability.HEALTH),
				TranslationServer.tr("판정: 없음")]
		"battle_cry":
			lines = [TranslationServer.tr("사거리: 모든 아군"), TranslationServer.tr("명중 보너스: 의지 d%d") % actor.get_ability_sides(CombatUnit.Ability.WILL),
				TranslationServer.tr("판정: 없음")]
		"spin":
			lines = [TranslationServer.tr("사거리: 인접1칸"), weapon, TranslationServer.tr("판정: 대상의 %s 내성 대 DC %d, 성공하면 피해 절반") % [
				CombatUnit.ability_name(SAVE_ABILITIES[action]), save_dc(actor, action)]]
			var chances: Array[String] = []
			for unit: CombatUnit in units:
				if unit.hit_points > 0 and unit.is_ally != actor.is_ally:
					chances.append("%s %.1f%%" % [unit.get_display_name(), save_chance(actor, unit, action) * 100.0])
			if not chances.is_empty():
				lines.append(TranslationServer.tr("내성 성공률: %s") % " · ".join(chances))
	for line: String in [cost_text(action), combat_uses_text(actor, action)]:
		if not line.is_empty():
			lines.append(line)
	return "\n".join(lines)


## 대상의 내성굴림 유리/불리. 굴리는 쪽(대상)의 요인만 센다 (4-7). 지금 내성굴림에 붙는 요인은 없다.
static func save_mode(_target: CombatUnit) -> CombatChecks.RollMode:
	return CombatChecks.roll_mode(0, 0)


## 밀치기에 내성굴림이 있는지. 기절한 대상과 아군은 판정 없이 밀린다 (8장).
static func shove_saves(actor: CombatUnit, target: CombatUnit) -> bool:
	return not target.is_stunned and actor.is_ally != target.is_ally


## 대상의 실제 내성 성공률. 내성 능력치 주사위, 방어 가산, 유리/불리와 절대면을 반영한다.
static func save_chance(actor: CombatUnit, target: CombatUnit, action: String) -> float:
	return CombatChecks.save_chance(target.get_ability_sides(SAVE_ABILITIES[action]), target.get_defense_bonus(),
		save_dc(actor, action), save_mode(target))


## 호버의 피해 줄. 피해 능력치가 명중 능력치와 다르면 둘을 함께 보인다 (4-9).
static func damage_text(actor: CombatUnit, action: String) -> String:
	var hit_ability: CombatUnit.Ability = actor.get_attack_ability()
	var ability: CombatUnit.Ability = damage_ability(actor, action)
	var bonus: String = "" if damage_bonus(actor, action) == 0 else "%+d" % damage_bonus(actor, action)
	if ability == hit_ability:
		return TranslationServer.tr("피해: %s d%d%s") % [CombatUnit.ability_name(ability), actor.get_ability_sides(ability), bonus]
	return TranslationServer.tr("피해: 명중 %s d%d → 피해 %s d%d%s") % [CombatUnit.ability_name(hit_ability),
		actor.get_ability_sides(hit_ability), CombatUnit.ability_name(ability), actor.get_ability_sides(ability), bonus]


static func effect(actor: CombatUnit, action: String) -> String:
	if action == "attack":
		return TranslationServer.tr("인접한 적을 기본 공격합니다.") if actor.get_attack_range() == 1 else TranslationServer.tr("1~6칸 원거리 공격.\n옆에 적이 있으면 불리.")
	# 패시브 칸이 정해지기 전까지 괴력의 사내는 기회 공격 호버로 안내한다 (#434).
	if action == "opportunity" and belongs_to(actor, "brawn"):
		return EFFECTS[action] + "\n" + TranslationServer.tr("괴력의 사내: 명중하면 대상의 이동을 멈춥니다.")
	return EFFECTS.get(action, "")
