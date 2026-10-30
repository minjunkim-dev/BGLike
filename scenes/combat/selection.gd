class_name CombatSelection
extends RefCounted
## 전투 조작의 선택·취소·확정. 좌표 입력과 실행·표시는 battle이 맡는다.

var selected_action: String = "attack"
var preview_target: CombatUnit
var preview_prop: CombatGrid.Prop
var preview_cell: Vector2i = Vector2i(-1, -1)
var preview_path: Array[Vector2i] = []
var inspected_unit: CombatUnit


func reset() -> void:
	selected_action = "attack"
	inspected_unit = null
	clear_preview()


func clear_preview() -> void:
	preview_target = null
	preview_prop = null
	preview_cell = Vector2i(-1, -1)
	preview_path.clear()


func inspect(unit: CombatUnit) -> void:
	if selected_action in ["move", "jump"]:
		selected_action = "attack"
	clear_preview()
	inspected_unit = unit


## 같은 보조 행동을 다시 선택하면 호출자가 실행한다.
func select_action(action: String) -> bool:
	inspected_unit = null
	clear_preview()
	if action == selected_action and action in CombatActionRules.SELF_TARGET:
		return true
	selected_action = action
	return false


func begin_field_input(left_click: bool) -> void:
	inspected_unit = null
	if left_click and selected_action in ["move", "jump"]:
		selected_action = "attack"
		clear_preview()


## 유효한 같은 목적지를 다시 선택하면 호출자가 이동을 실행한다.
func select_move(cell: Vector2i, path: Array[Vector2i]) -> bool:
	if selected_action != "jump":
		selected_action = "move"
	var confirmed: bool = not path.is_empty() and cell == preview_cell
	clear_preview()
	if not confirmed and not path.is_empty():
		preview_cell = cell
		preview_path = path.duplicate()
	return confirmed


func preview_unit(target: CombatUnit) -> void:
	clear_preview()
	preview_target = target


func select_target(target: CombatUnit, can_execute: bool) -> bool:
	if target == preview_target and can_execute:
		return true
	preview_unit(target)
	return false


func select_prop(prop: CombatGrid.Prop, can_execute: bool) -> bool:
	if prop == preview_prop and can_execute:
		return true
	clear_preview()
	preview_prop = prop
	return false


func begin_execution() -> String:
	var action: String = selected_action
	clear_preview()
	return action


func finish_execution() -> void:
	selected_action = "attack"


func discard_incapacitated_inspection() -> void:
	if inspected_unit != null and inspected_unit.hit_points <= 0:
		inspected_unit = null
