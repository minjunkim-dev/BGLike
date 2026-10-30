class_name CombatActionRules
extends RefCounted
## 스킬과 공용 동작의 정의. 비용 자원, 직업 제한, 막당 횟수와 설명을 한 곳에 둔다.

## 비용 자원(행동, 보조 행동, 반응) 순서의 묶음. HUD의 배치 순서이기도 하다.
const GROUPS: Array[Array] = [
	["attack", "shock", "spawn", "pull", "spin"], ["second_wind", "surge", "mark", "disengage", "shove", "jump", "potion"],
	["opportunity", "parry"]
]
static var NAMES: Dictionary[String, String] = {
	"attack": TranslationServer.tr("공격"), "second_wind": TranslationServer.tr("숨 고르기"), "surge": TranslationServer.tr("몰아치기"),
	"mark": TranslationServer.tr("표식"), "shock": TranslationServer.tr("충격 화살"), "disengage": TranslationServer.tr("물러서며 쏘기"),
	"shove": TranslationServer.tr("밀치기"), "potion": TranslationServer.tr("물약"), "opportunity": TranslationServer.tr("기회 공격"), "parry": TranslationServer.tr("흘려내기"),
	"spawn": TranslationServer.tr("새끼 낳기"), "pull": TranslationServer.tr("만능팔"), "spin": TranslationServer.tr("회전회오리"), "jump": TranslationServer.tr("점프")
}
static var EFFECTS: Dictionary[String, String] = {
	"jump": TranslationServer.tr("1~2칸의 빈 바닥으로 점프.\n상승2까지, 낙하 차3부터 피해."),
	"spawn": TranslationServer.tr("인접한 빈 칸에 새끼 거미1마리를 만듭니다."),
	"spin": TranslationServer.tr("상하좌우1칸·높이 차이1 이하인 모든 아군에게 공통 공격 굴림과 각자의 방어 굴림.\n밀어내지 않습니다. 횟수와 쉬는 턴 제한 없음."),
	"second_wind": TranslationServer.tr("HP 1d10+1 회복.\n최대 HP를 넘지 않습니다."),
	"surge": TranslationServer.tr("이미 쓴 행동을 다시 채워\n한 번 더 공격할 수 있습니다."),
	"mark": TranslationServer.tr("1~6칸 적에게 표식.\n이 궁수가 맞히면 피해 +1d6.\n전투 중 유지됩니다."),
	"shock": TranslationServer.tr("1~6칸 공격.\n명중하면 기절. 보스는 기절 면역."),
	"pull": TranslationServer.tr("2~3칸 대상을 힘 대 힘 대결로 끌어옵니다.\n피해와 기회 공격 없음. 다음 턴에는 쓸 수 없습니다."),
	"disengage": TranslationServer.tr("이번 턴의 남은 이동에서\n기회 공격을 받지 않습니다.\n공격을 실행하지 않습니다."),
	"shove": TranslationServer.tr("내 힘 대 상대의 힘 주사위로 대결.\n성공: 1칸 밀기, 동점: 실패.\n기절 대상은 대결 없이 성공.\n아군은 판정 없이 밀림."),
	"potion": TranslationServer.tr("HP 2d4+2 회복.\n최대 HP를 넘지 않습니다."),
	"opportunity": TranslationServer.tr("적이 내 인접 칸을 벗어나면 기본 공격."),
	"parry": TranslationServer.tr("공격에 맞았을 때 민첩 주사위 +3이\n공격 굴림 이상이면 피해와 추가 효과를 피합니다.")
}
## 대상 없이 바로 쓰는 보조 행동.
const SELF_TARGET: Array[String] = ["second_wind", "surge", "disengage", "potion"]
## 표식과 충격 화살의 사거리.
const SKILL_RANGE: int = 6
const CLASS_ONLY: Dictionary[String, CombatUnit.Kind] = {
	"second_wind": CombatUnit.Kind.WARRIOR, "surge": CombatUnit.Kind.WARRIOR,
	"opportunity": CombatUnit.Kind.WARRIOR, "parry": CombatUnit.Kind.WARRIOR,
	"mark": CombatUnit.Kind.ARCHER, "shock": CombatUnit.Kind.ARCHER,
	"disengage": CombatUnit.Kind.ARCHER, "spawn": CombatUnit.Kind.MOTHER_SPIDER,
	"pull": CombatUnit.Kind.SCRAP_ROBOT_2000, "spin": CombatUnit.Kind.SCRAP_ROBOT_3000
}
const USE_COUNTERS: Dictionary[String, StringName] = {
	"second_wind": &"second_wind_left", "surge": &"surge_left", "mark": &"mark_left",
	"shock": &"shock_left", "disengage": &"disengage_left", "potion": &"potion_left",
	"parry": &"parry_left"
}
## 막 시작에 회복하는 횟수. 물약은 보유 개수라서 회복하지 않는다.
const USES_PER_ACT: Dictionary[String, int] = {
	"second_wind": 1, "parry": 2, "surge": 1, "mark": 1, "shock": 1, "disengage": 2
}
## 피해 능력치를 명중 능력치와 다르게 지정한 동작 (능력치 기획서 4-9). 지금 있는 스킬은 모두 같아 비어 있다.
## 동작 이름으로 찾으므로 기회 공격("opportunity")은 "attack"과 따로 지정한다.
static var DAMAGE_ABILITIES: Dictionary[String, CombatUnit.Ability] = {}
## 아군 스킬과 공용 동작의 아이콘. 48px 원본(64px 설계 격자)이다.
const ICON_PATH: String = "res://scenes/combat/art/icons/skills/%s.png"
## #362: 스킬과 정비 아이템 그림의 표시 크기(논리 px). 버튼·칸의 입력 영역은 각 화면이 따로 유지한다.
const ICON_SIZE: int = 24


static func resource_of(action: String) -> CombatUnit.TurnResource:
	for index: int in range(GROUPS.size()):
		if action in GROUPS[index]:
			return index as CombatUnit.TurnResource
	return CombatUnit.TurnResource.ACTION


## 동작의 피해 굴림 능력치. 지정이 없으면 명중 능력치다.
static func damage_ability(actor: CombatUnit, action: String) -> CombatUnit.Ability:
	return DAMAGE_ABILITIES.get(action, actor.get_attack_ability())


static func belongs_to(actor: CombatUnit, action: String) -> bool:
	if action == "jump":
		return true
	if not actor.is_ally:
		return action in CombatEnemyDefinitions.for_kind(actor.kind)["actions"]
	return action not in CLASS_ONLY or actor.kind == CLASS_ONLY[action]


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


## 적 전용 스킬처럼 아이콘이 없으면 null이다.
static func icon_of(action: String) -> Texture2D:
	var path: String = ICON_PATH % action
	return load(path) as Texture2D if ResourceLoader.exists(path) else null


## 호버의 사거리·피해 또는 회복·판정 줄. 현재 장비의 명중·피해 보정을 반영한다.
static func details(actor: CombatUnit, action: String) -> String:
	var melee: bool = actor.get_attack_range() == 1
	var weapon: String = damage_text(actor, action)
	var hit: String = TranslationServer.tr("%s d%d %+d 대 AC") % [CombatUnit.ability_name(actor.get_attack_ability()),
		actor.get_ability_sides(actor.get_attack_ability()), actor.get_attack_bonus()]
	var lines: Array[String] = []
	match action:
		"attack", "opportunity":
			lines = [TranslationServer.tr("사거리: 인접1칸") if melee else TranslationServer.tr("사거리: 1~%d칸") % actor.get_attack_range(), weapon,
				TranslationServer.tr("판정: %s") % hit]
		"shock":
			lines = [TranslationServer.tr("사거리: 1~%d칸") % SKILL_RANGE, weapon, TranslationServer.tr("판정: %s, 명중하면 기절") % hit]
		"mark":
			lines = [TranslationServer.tr("사거리: 1~%d칸") % SKILL_RANGE, TranslationServer.tr("판정: 없음")]
		"shove":
			lines = [TranslationServer.tr("사거리: 인접1칸"), TranslationServer.tr("판정: 힘 d%d %+d 대 힘") % [actor.get_ability_sides(CombatUnit.Ability.STRENGTH), actor.get_attack_bonus()]]
		"jump":
			lines = [TranslationServer.tr("사거리: 1~2칸"), TranslationServer.tr("판정: 없음")]
		"second_wind":
			lines = [TranslationServer.tr("사거리: 자신"), TranslationServer.tr("회복: 1d10+1"), TranslationServer.tr("판정: 없음")]
		"potion":
			lines = [TranslationServer.tr("사거리: 자신"), TranslationServer.tr("회복: 2d4+2"), TranslationServer.tr("판정: 없음")]
		"surge", "disengage":
			lines = [TranslationServer.tr("사거리: 자신"), TranslationServer.tr("판정: 없음")]
		"parry":
			lines = [TranslationServer.tr("사거리: 자신"), TranslationServer.tr("판정: 민첩 d%d +3이 공격 굴림 이상") % actor.get_ability_sides(CombatUnit.Ability.AGILITY)]
	return "\n".join(lines)


## 호버의 피해 줄. 피해 능력치가 명중 능력치와 다르면 둘을 함께 보인다 (4-9).
static func damage_text(actor: CombatUnit, action: String) -> String:
	var hit_ability: CombatUnit.Ability = actor.get_attack_ability()
	var ability: CombatUnit.Ability = damage_ability(actor, action)
	var bonus: String = "" if actor.get_damage_bonus() == 0 else "%+d" % actor.get_damage_bonus()
	if ability == hit_ability:
		return TranslationServer.tr("피해: %s d%d%s") % [CombatUnit.ability_name(ability), actor.get_ability_sides(ability), bonus]
	return TranslationServer.tr("피해: 명중 %s d%d → 피해 %s d%d%s") % [CombatUnit.ability_name(hit_ability),
		actor.get_ability_sides(hit_ability), CombatUnit.ability_name(ability), actor.get_ability_sides(ability), bonus]


static func effect(actor: CombatUnit, action: String) -> String:
	if action == "attack":
		return TranslationServer.tr("인접한 적을 기본 공격합니다.") if actor.get_attack_range() == 1 else TranslationServer.tr("1~6칸 원거리 공격.\n옆에 적이 있으면 불리.")
	return EFFECTS.get(action, "")
