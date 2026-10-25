extends "res://.cache/click-point-regression/test_click_point.gd"
func _stable_body_point(target: CombatUnit, world: Vector2) -> bool:
	return target.contains_body_point(target.to_local(world))
