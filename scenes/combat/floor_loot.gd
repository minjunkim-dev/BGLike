class_name CombatFloorLoot
extends RefCounted
## 상자에서 떨어진 아이템과 이번 전투에서 주운 아이템 (docs/ENVIRONMENT_ELEMENTS.md 3장).
## 떨어진 아이템은 물체가 아니다. 칸마다 하나이고 이동·공격 판정에 영향을 주지 않는다.

## 칸 → 아이템.
var drops: Dictionary[Vector2i, Dictionary] = {}
## 이번 전투에서 주운 아이템. 승리 때 보상에 합산한다.
var picked: Array[Dictionary] = []


func clear() -> void:
	drops.clear()
	picked.clear()


func drop(cell: Vector2i, item: Dictionary) -> void:
	assert(not drops.has(cell), "한 칸에 아이템은 1개뿐입니다: %s" % cell)
	drops[cell] = item


func item_at(cell: Vector2i) -> Dictionary:
	return drops.get(cell, {})


func cells() -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	result.assign(drops.keys())
	return result


## 칸의 아이템을 주워 주운 목록에 더한다. 없으면 빈 Dictionary다.
func pick_up(cell: Vector2i) -> Dictionary:
	if not drops.has(cell):
		return {}
	var item: Dictionary = drops[cell]
	drops.erase(cell)
	picked.append(item)
	return item


## Object 없이 GameSave에 그대로 쓸 수 있는 값이다.
func save_state() -> Dictionary:
	var saved_drops: Array = []
	for cell: Vector2i in drops:
		saved_drops.append([cell, drops[cell]])
	return {"drops": saved_drops, "picked": picked.duplicate(true)}


## is_valid_state()를 먼저 확인한다.
func load_state(data: Dictionary) -> void:
	clear()
	for saved: Array in data.drops:
		drops[saved[0]] = (saved[1] as Dictionary).duplicate(true)
	for item: Dictionary in data.picked:
		picked.append(item.duplicate(true))


## 저장 파일의 값을 load_state()에 넘겨도 되는지. limit은 한 전투에서 떨어질 수 있는 아이템의 최대 수(스테이지의 상자 수)다.
static func is_valid_state(data: Variant, map_size: Vector2i, limit: int, is_valid_item: Callable) -> bool:
	if not (data is Dictionary and data.keys().size() == 2 and data.get("drops") is Array and data.get("picked") is Array):
		return false
	var area: Rect2i = Rect2i(Vector2i.ZERO, map_size)
	if data.drops.size() + data.picked.size() > limit:
		return false
	var seen: Array[Vector2i] = []
	for saved: Variant in data.drops:
		if not (saved is Array and saved.size() == 2 and saved[0] is Vector2i and area.has_point(saved[0])
				and saved[0] not in seen and is_valid_item.call(saved[1])):
			return false
		seen.append(saved[0])
	return data.picked.all(func(item: Variant) -> bool: return is_valid_item.call(item))
