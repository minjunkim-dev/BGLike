extends ScrollContainer
## 실제 초상 그룹과 스크롤바만 필드 입력을 막는다.


func _has_point(point: Vector2) -> bool:
	if not Rect2(Vector2.ZERO, size).has_point(point):
		return false
	var order_bar: HBoxContainer = $OrderBar
	for panel: Control in order_bar.get_children():
		if panel.is_visible_in_tree() and panel.get_rect().has_point(point - order_bar.position):
			return true
	for bar: ScrollBar in [get_h_scroll_bar(), get_v_scroll_bar()]:
		if bar.is_visible_in_tree() and bar.get_rect().has_point(point):
			return true
	return false
