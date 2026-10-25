extends "res://.cache/click-point-regression/autoplay.gd"

func _initialize() -> void:
	_check.call_deferred()

func _check() -> void:
	var target: CombatUnit = CombatUnit.new()
	target.kind = CombatUnit.Kind.SPIDERLING
	target.is_ally = false
	root.add_child(target)
	var sprite: AnimatedSprite2D = target.get("_sprite")
	sprite.play("idle_left")
	sprite.stop()
	var unstable: int = 0
	var stable: int = 0
	var failures: int = 0
	for y: int in range(-28, 1):
		for x: int in range(-16, 17):
			var point: Vector2 = Vector2(x, y)
			sprite.frame = 0
			var first: bool = target.contains_body_point(point)
			sprite.frame = 1
			var second: bool = target.contains_body_point(point)
			if second and not first:
				unstable += 1
				if _stable_body_point(target, target.to_global(point)): failures += 1
			if first and second:
				stable += 1
				if not _stable_body_point(target, target.to_global(point)): failures += 1
	assert(unstable > 0 and stable > 0)
	print("CLICK_POINT unstable=%d stable=%d failures=%d" % [unstable, stable, failures])
	target.queue_free()
	await process_frame
	quit(1 if failures > 0 else 0)
