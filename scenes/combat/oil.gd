class_name CombatOil
extends RefCounted
## 궁수 기름 규칙(#500 2a)의 순수 함수. 상태와 부수 효과는 CombatActions가 갖는다 (전투 시스템 기획서 6-7, 궁수 문서).

## 기름 장판의 지속(시전자 턴)과 미끌거림 DC(장판 정의의 고정값).
const TURNS: int = 3
const SLIP_DC: int = 4
## 속성 반응표. 바깥 키는 동작의 속성, 안 키는 닿은 장판 종류, 값은 반응이다. 빈 값은 반응 없음이다.
const REACTIONS: Dictionary = {
	"fire": {"oil": "ignite"},
	"water": {"oil": "remove", "burn": "remove"},
}


static func reaction(attribute: String, ground_kind: String) -> String:
	return REACTIONS.get(attribute, {}).get(ground_kind, "")


## 중심과 상하좌우 4칸(곡사 반경 1의 십자 5칸). 맵과 막힌 칸은 호출자가 거른다.
static func cross_cells(center: Vector2i) -> Array[Vector2i]:
	var cells: Array[Vector2i] = [center]
	for offset: Vector2i in [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]:
		cells.append(center + offset)
	return cells


## start에서 상하좌우로 이어진 기름 칸 전체. start가 기름 칸이 아니면 비어 있다.
static func connected(start: Vector2i, oil_cells: Array[Vector2i]) -> Array[Vector2i]:
	var found: Array[Vector2i] = []
	if start not in oil_cells:
		return found
	var frontier: Array[Vector2i] = [start]
	found.append(start)
	while not frontier.is_empty():
		var here: Vector2i = frontier.pop_back()
		for offset: Vector2i in [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]:
			var next: Vector2i = here + offset
			if next in oil_cells and next not in found:
				found.append(next)
				frontier.append(next)
	return found


## 일어서기 비용: 최대 이동력의 절반을 올림 (궁수 3, 전사 2).
static func standing_cost(max_movement: int) -> int:
	return ceili(max_movement / 2.0)
