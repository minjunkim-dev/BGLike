class_name CombatActionRules
extends RefCounted
## 스킬과 공용 동작의 정의. 비용 자원, 직업 제한, 막당 횟수와 설명을 한 곳에 둔다.

## 비용 자원(행동, 보조 행동, 반응) 순서의 묶음. HUD의 배치 순서이기도 하다.
const GROUPS: Array[Array] = [
	["attack", "shock", "spawn", "pull", "spin"], ["second_wind", "surge", "mark", "disengage", "shove", "jump", "potion"],
	["opportunity", "parry"]
]
const NAMES: Dictionary[String, String] = {
	"attack": "공격", "second_wind": "숨 고르기", "surge": "몰아치기",
	"mark": "표식", "shock": "충격 화살", "disengage": "물러서며 쏘기",
	"shove": "밀치기", "potion": "물약", "opportunity": "기회 공격", "parry": "흘려내기",
	"spawn": "새끼 낳기", "pull": "만능팔", "spin": "회전회오리", "jump": "점프"
}
const EFFECTS: Dictionary[String, String] = {
	"jump": "1~2칸의 빈 바닥으로 점프.\n상승2까지, 낙하 차3부터 피해.",
	"spawn": "인접한 빈 칸에 새끼 거미1마리를 만듭니다.",
	"spin": "상하좌우1칸·높이 차이1 이하인 모든 아군에게 각각 기본 공격.\n밀어내지 않습니다. 횟수와 쉬는 턴 제한 없음.",
	"second_wind": "HP 1d10+1 회복.\n최대 HP를 넘지 않습니다.",
	"surge": "이미 쓴 행동을 다시 채워\n한 번 더 공격할 수 있습니다.",
	"mark": "1~6칸 적에게 표식.\n이 궁수가 맞히면 피해 +1d6.\n전투 중 유지됩니다.",
	"shock": "1~6칸 공격.\n명중 후 정신 내성 실패 시 기절.",
	"pull": "2~3칸 대상을 힘 대 힘/민첩 대결로 끌어옵니다.\n피해와 기회 공격 없음. 다음 턴에는 쓸 수 없습니다.",
	"disengage": "이번 턴의 남은 이동에서\n기회 공격을 받지 않습니다.\n공격을 실행하지 않습니다.",
	"shove": "내 힘 대 상대의 힘/민첩\n중 높은 값으로 대결.\n성공: 1칸 밀기, 동점: 실패.\n기절 대상은 대결 없이 성공.",
	"potion": "HP 2d4+2 회복.\n최대 HP를 넘지 않습니다.",
	"opportunity": "적이 내 인접 칸을 벗어나면 기본 공격.",
	"parry": "공격에 맞았을 때 민첩 내성에 성공하면\n피해와 추가 효과를 피합니다."
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


static func resource_of(action: String) -> CombatUnit.TurnResource:
	for index: int in range(GROUPS.size()):
		if action in GROUPS[index]:
			return index as CombatUnit.TurnResource
	return CombatUnit.TurnResource.ACTION


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


static func effect(actor: CombatUnit, action: String) -> String:
	if action == "attack":
		return "인접한 적을 기본 공격합니다." if actor.get_attack_range() == 1 else "1~6칸 원거리 공격.\n옆에 적이 있으면 불리."
	return EFFECTS.get(action, "")
