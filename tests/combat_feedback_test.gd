extends SceneTree

## 실제 전투 피드백의 이동 경로와 상태 표시 겹침을 매 프레임 검사한다.

const ScriptedDice = preload("res://tests/scripted_dice.gd")
const CaptureObserver = preload("res://tests/capture_observer.gd")

var checks: int = 0
var failures: int = 0
var battle: Node2D
var turns: CombatTurns
var observer: CaptureObserver
var collisions: Array[String] = []
var messages: Array[String] = []
var monitoring: bool = true
var popup_samples: int = 0
var popup_styles: Dictionary[String, Array] = {}
var manual: bool = "--manual" in OS.get_cmdline_user_args()
var finished: bool = false


func _initialize() -> void:
	_run.call_deferred()


func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)


func _run() -> void:
	create_timer(180.0 if manual else 30.0).timeout.connect(func() -> void:
		if not finished:
			push_error("Combat feedback watchdog expired")
			quit(1))
	root.size = Vector2i(1280, 720)
	var main: Node = (load("res://scenes/game.tscn") as PackedScene).instantiate()
	root.add_child(main)
	current_scene = main
	battle = main.get_node("Battle") as Node2D
	(battle.get("progress") as CombatActProgress).stage_index = 8
	battle.call("_start_stage", true)
	battle.call("start_battle")
	var units: Array[CombatUnit] = battle.get("units")
	_check(units.size() == 3, "반복 공격 전제조건: 3-3 유닛 3개")
	if units.size() != 3:
		await _abort_fixture()
		return
	var boss: CombatUnit = units[2]
	units[0].cell = Vector2i(3, 5)
	units[1].cell = Vector2i(5, 5)
	boss.cell = Vector2i(4, 5)
	boss.hit_points = 25
	turns = battle.get("turns") as CombatTurns
	ScriptedDice.arrange_turns(turns, units, units)
	var actions: CombatActions = battle.get("actions") as CombatActions
	# 내성 실패·성공 피해가 같은 반복 광역에서 발생하는 통제된 재현이다.
	# 회전회오리 두 번. 대상마다 민첩 내성(#528) → 피해: 첫 번째는 둘 다 실패, 두 번째는 궁수만 절대성공면 12로 성공.
	# 전사 민첩 d8은 DC 10에 닿지 못한다. 과부하 고철로봇의 턴 시작 화상(#464)이 전사의 다음 턴 시작에 d4 하나를 굴린다.
	actions.dice = ScriptedDice.new([1, 1, 1, 1, 8, 1, 12, 1, 4], [8, 12, 12, 12, 8, 12, 12, 12, 4])
	for unit: CombatUnit in units:
		if unit.is_ally:
			unit.reaction_left = 0
	actions.logged.connect(func(message: String) -> void: messages.append(message))
	battle.call("_update_turn_ui")
	if not _fixture_ready(units):
		await _abort_fixture()
		return
	print("[FEEDBACK_FIXTURE] 통제된 재현: HP25·배치·주사위 고정, 아군 반응0")
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--capture-dir="):
			observer = CaptureObserver.new()
			battle.add_child(observer)
			_check(observer.start(battle, argument.trim_prefix("--capture-dir=")) == OK,
				"독립 캡처 관찰 Node 시작")
	_monitor()
	await create_timer(0.2).timeout
	if manual:
		print("[FEEDBACK_CHECK] READY: 통제된 반복 공격 재현. 아군 두 명의 턴 종료를 누르세요.")
		_check(await _wait_for(func() -> bool:
			return turns.current_unit != null and not turns.current_unit.is_ally, 120.0),
			"직접 입력으로 적 차례 진입")
	else:
		var hud: CombatTurnHud = battle.get_node("UI/TurnHud") as CombatTurnHud
		hud.end_turn_requested.emit()
		hud.end_turn_requested.emit()
	_check(await _wait_for(func() -> bool:
		return (turns.round_number == 2 and turns.current_unit.is_ally
			and not battle.get("_enemy_turn_running")), 10.0), "실제 적 AI 종료와 아군 차례 복귀")
	# 마지막 팝업이 사라지는 구간까지 검사한다.
	await create_timer(1.0).timeout
	_check(popup_samples > 0, "반복 공격에서 실제 팝업을 관찰함")
	_check(collisions.is_empty(), "반복 공격 팝업 겹침 없음: %s" % str(collisions))
	_check(not popup_styles.has("치명타!"), "능력치 판정은 치명타 팝업을 생성하지 않음")
	_check(not popup_styles.has("빗나감") and not popup_styles.has("자동 실패"),
		"내성굴림 광역은 빗나감 없이 피해 팝업만: %s" % str(popup_styles.keys()))
	_check(popup_styles.keys().all(func(text: String) -> bool:
		return not text.begins_with("공격 ") and not text.begins_with("-")),
		"공격자 판정 합계 팝업과 피해 부호 없음: %s" % str(popup_styles.keys()))
	_check(messages.filter(func(line: String) -> bool: return "회전회오리:" in line).size() == 2,
		"과부하 중 회전 공격 두 번 유지")
	_check(units[0].hit_points == 1 and units[1].hit_points == 5 and boss.hit_points == 23
		and messages.any(func(line: String) -> bool: return "피해 (내성 성공 절반)" in line),
		"내성 실패 피해·내성 성공 절반 피해와 과부하 자해 유지")
	_check(_popups().is_empty(), "마지막 피드백 이후 팝업 제거")
	actions.dice = ScriptedDice.new([], []).then_seeded()
	await _test_stunned_target_feedback()
	await _test_crowded_feedback()
	await _test_hit_effects()
	await _test_skill_effects()
	await _test_status_effects()
	await _test_down_effect()
	monitoring = false
	if observer != null:
		_check(observer.last_error == OK and observer.frame_count > 0, "Forward+ 원본 프레임 저장")
		observer.stop()
	var problems: Array[String] = ScriptedDice.finish()
	_check(problems.is_empty(), "준비한 주사위 모두 소비: %s" % str(problems))
	finished = true
	print("Combat feedback: %d checks, %d failures; samples=%d; collisions=%s" % [
		checks, failures, popup_samples, str(collisions)])
	if manual and failures == 0:
		print("[FEEDBACK_CHECK] PASS")
		return
	main.queue_free()
	await process_frame
	quit(0 if failures == 0 else 1)


func _fixture_ready(units: Array[CombatUnit]) -> bool:
	var previous_failures: int = failures
	var boss: CombatUnit = units[2]
	var grid: CombatGrid = (battle.get("actions") as CombatActions).grid
	for unit: CombatUnit in units:
		_check(grid.is_floor(unit.cell) and not grid.is_blocked(unit.cell) and grid.unit_at(unit.cell) == unit,
			"반복 공격 전제조건: 장애물·다른 유닛과 겹치지 않는 바닥")
	_check(units[0].is_ally and units[0].kind == CombatUnit.Kind.WARRIOR
		and units[1].is_ally and units[1].kind == CombatUnit.Kind.ARCHER
		and not boss.is_ally and boss.kind == CombatUnit.Kind.SCRAP_ROBOT_3000,
		"반복 공격 전제조건: 전사·궁수·고철로봇 3000")
	var portraits: Dictionary = battle.get_node("UI/TurnHud").get("_portraits")
	_check(portraits.size() == 3 and portraits.has(units[0]) and portraits.has(units[1])
		and portraits.has(boss), "반복 공격 전제조건: 실제 유닛의 초상 3개")
	_check(boss.hit_points == 25 and boss.overloaded and boss.action_left == 1,
		"반복 공격 전제조건: HP25 과부하, 행동2는 보스 턴 시작에 받음")
	for ally: CombatUnit in [units[0], units[1]]:
		_check(CombatGrid.distance(ally.cell, boss.cell) == 1
			and ally.hit_points == ally.get_max_hit_points()
			and ally.movement_left == ally.get_movement()
			and ally.action_left == 1 and ally.bonus_action_left == 1 and ally.reaction_left == 0,
			"반복 공격 전제조건: 인접 아군의 정상 HP·턴 자원과 반응0")
	return failures == previous_failures


func _abort_fixture() -> void:
	finished = true
	monitoring = false
	current_scene.queue_free()
	await process_frame
	quit(1)


## 기절 상태 글자가 떠 있는 대상의 피해 팝업. 충격 화살(#528에서 삭제) 대신 기절을 직접 건다.
func _test_stunned_target_feedback() -> void:
	(battle.get("progress") as CombatActProgress).stage_index = 1
	battle.call("_start_stage", true)
	battle.call("start_battle")
	var units: Array[CombatUnit] = battle.get("units")
	var archer: CombatUnit = units[1]
	var target: CombatUnit = units[2]
	units[0].cell = Vector2i(0, 9)
	archer.cell = Vector2i(2, 4)
	target.cell = Vector2i(5, 4)
	target.reaction_left = 0
	ScriptedDice.arrange_turns(turns, units, [archer, units[0], target])
	var actions: CombatActions = battle.get("actions") as CombatActions
	_check(actions.apply_status(archer, target, "stun"), "공격 전 기절 적용")
	# 기절한 대상은 유리라 명중굴림을 두 번 굴린다.
	actions.dice = ScriptedDice.new([15, 15, 2], ScriptedDice.attack_sides(archer, 2) + ScriptedDice.damage_sides(archer))
	battle.call("_update_turn_ui")
	_check(await actions.attack(archer, target), "기절한 대상에게 실제 기본 공격")
	_check(target.is_stunned and target.hit_points == 10, "기절 유지와 피해 2")
	await create_timer(1.0).timeout
	_check(collisions.is_empty(), "피해 팝업·기절 상태 표시 겹침 없음: %s" % str(collisions))
	_check(_popups().is_empty(), "피해 팝업 제거")


## #260: 3-1에서 궁수를 여섯 유닛이 둘러싼 밀집 배치. 새끼 거미의 연속 피해 팝업이 대상 가까이에 순서대로 쌓여야 한다.
func _test_crowded_feedback() -> void:
	battle.set_process(false)  # 적 AI 대신 정해진 공격 한 번만 실행한다.
	battle.call("start_battle")
	(battle.get("progress") as CombatActProgress).stage_index = 6
	battle.call("_start_stage", true)
	battle.call("start_battle")
	var units: Array[CombatUnit] = battle.get("units")
	_check(units.size() == 7, "밀집 팝업 전제조건: 3-1 유닛 7개")
	if units.size() != 7:
		return
	var archer: CombatUnit = units[1]
	var attacker: CombatUnit = units[2]
	# 위쪽 HUD와 떨어진 자리라 같은 대상의 팝업을 위로 쌓을 공간이 있다.
	var cells: Array[Vector2i] = [Vector2i(7, 8), Vector2i(8, 7), Vector2i(8, 6), Vector2i(9, 7), Vector2i(7, 7),
		Vector2i(8, 8), Vector2i(9, 6)]
	for index: int in range(units.size()):
		units[index].cell = cells[index]
		units[index].reaction_left = 0
	ScriptedDice.arrange_turns(turns, units, [attacker])
	var actions: CombatActions = battle.get("actions") as CombatActions
	# 새끼 거미 힘 4+3은 궁수 AC 7과 같아 두 번 모두 명중하고, 피해 힘 d4의 1 + 1 = 2다.
	var sides: Array[int] = ScriptedDice.attack_sides(attacker) + ScriptedDice.damage_sides(attacker)
	actions.dice = ScriptedDice.new([4, 1, 4, 1], sides + sides)
	battle.call("_update_turn_ui")
	_check(turns.current_unit == attacker and attacker.kind == CombatUnit.Kind.SPIDERLING
		and archer.kind == CombatUnit.Kind.ARCHER, "밀집 팝업 전제조건: 새끼 거미 차례, 궁수 대상")
	var parent: Node2D = battle.get_node("Units") as Node2D
	var placed: Array[Dictionary] = []
	var recorded: Array[int] = []
	var record: Callable = func(unit: CombatUnit, text: String) -> void:
		for child: Node in parent.get_children():
			if (child is Label and child.text == text and child.get_meta("feedback_unit", 0) == unit.get_instance_id()
				and child.get_instance_id() not in recorded):
				recorded.append(child.get_instance_id())
				var canvas: Transform2D = parent.get_global_transform_with_canvas()
				var scale: float = absf(canvas.get_scale().x)
				placed.append({"unit": unit, "text": text, "rect": canvas * (child as Label).get_rect(),
					"origin": canvas * (unit.position + Vector2(-16, unit.floor_offset_y + unit.get_status_label_y() - 5)),
					"padding": 2.0 * scale, "near": CombatUnit.FEEDBACK_NEAR * scale})
	actions.feedback.connect(record)
	_check(await actions.attack(attacker, archer), "밀집 배치에서 새끼 거미 공격 실행")
	attacker.refill_turn_resources()
	_check(await actions.attack(attacker, archer), "첫 팝업이 남아 있을 때 같은 대상 연속 공격")
	actions.feedback.disconnect(record)
	var texts: Array = placed.map(func(entry: Dictionary) -> String: return entry["text"])
	_check(texts == ["2", "2"], "밀집 배치의 연속 피해 팝업: %s" % str(texts))
	# 기준 자리: 대상 상태 줄 기준점. 같은 대상의 이전 팝업이 있으면 그 팝업 바로 위가 더 위쪽일 때 그 자리.
	var latest: Dictionary = {}
	for entry: Dictionary in placed:
		var rect: Rect2 = entry["rect"]
		var slot: Vector2 = entry["origin"]
		if latest.has(entry["unit"]):
			var previous: Rect2 = latest[entry["unit"]]
			_check(rect.end.y < previous.position.y, "같은 대상의 다음 팝업은 이전 팝업 위: %s %s / %s" % [
				entry["text"], rect, previous])
			slot.y = minf(slot.y, previous.position.y - 3.0 * entry["padding"] - rect.size.y)
		_check(rect.position.distance_to(slot) <= entry["near"], "밀집 배치 팝업은 기준 자리에서 %.0fpx 안: %s %s / 기준 %s" % [
			entry["near"], entry["text"], rect, slot])
		latest[entry["unit"]] = rect
	await create_timer(1.0).timeout
	_check(collisions.is_empty(), "밀집 배치 팝업 겹침·화면 밖·HUD 침범 없음: %s" % str(collisions))
	_check(_popups().is_empty(), "밀집 배치 팝업 제거")


## 명중 섬광·히트스톱·빗나감 잔상(#559). actions.struck 신호를 보내 전투 장면의 연결을 본다.
func _test_hit_effects() -> void:
	var units: Array[CombatUnit] = battle.get("units")
	var actions: CombatActions = battle.get("actions") as CombatActions
	var effects: Node = battle.get_node_or_null("HitEffects")
	_check(effects != null, "전투 장면에 HitEffects 노드가 있다")
	if effects == null:
		return
	var attacker: CombatUnit = units[0]
	var target: CombatUnit = units[1]
	var home: Vector2 = target.position
	var shader: Material = load("res://scenes/combat/art/pixel_art.tres")
	actions.struck.emit(attacker, target, target.cell, true)
	await process_frame
	var flash: AnimatedSprite2D
	for child: Node in effects.get_children():
		if child is AnimatedSprite2D:
			flash = child
	_check(flash != null and flash.material == shader and absf(flash.scale.x - 0.5) < 0.001,
		"명중하면 pixel_art 재질의 0.5배 섬광이 생긴다")
	var paused_seen: bool = false
	var recoil_seen: float = 0.0
	var deadline: int = Time.get_ticks_msec() + 1500
	while effects.get_child_count() > 0 and Time.get_ticks_msec() < deadline:
		paused_seen = paused_seen or target.get_node("Sprite").speed_scale == 0.0
		recoil_seen = maxf(recoil_seen, absf(target.recoil_offset.x))
		await process_frame
	await create_timer(0.15).timeout
	_check(paused_seen and recoil_seen > 1.0 and recoil_seen <= 2.001,
		"히트스톱 동안 대상 그림이 멈추고 2 논리px 안으로 밀린다")
	_check(effects.get_child_count() == 0 and target.recoil_offset == Vector2.ZERO
		and target.position == home and target.get_node("Sprite").speed_scale == 1.0,
		"끝나면 섬광이 사라지고 밀림·멈춤이 풀리며 위치는 그대로다")
	actions.struck.emit(attacker, target, target.cell, false)
	await process_frame
	var afterimage: Sprite2D
	for child: Node in effects.get_children():
		if child is Sprite2D:
			afterimage = child
	_check(afterimage != null and afterimage.material == shader and target.recoil_offset == Vector2.ZERO,
		"빗나가면 대상은 움직이지 않고 잔상 그림이 생긴다")
	await create_timer(0.5).timeout
	_check(effects.get_child_count() == 0, "잔상은 0.5초 안에 사라진다")
	Engine.time_scale = 4.0
	var started: int = Time.get_ticks_msec()
	actions.struck.emit(attacker, target, target.cell, true)
	await process_frame
	while effects.get_child_count() > 0 and Time.get_ticks_msec() - started < 2000:
		await process_frame
	var fast_msec: int = Time.get_ticks_msec() - started
	Engine.time_scale = 1.0
	_check(fast_msec < 200, "4배속에서는 1배속 섬광 길이(250ms)보다 짧은 실제 시간에 끝난다: %dms" % fast_msec)
	await create_timer(0.1).timeout
	var turn_actions: int = battle.get("_turn_actions")
	battle.set("_turn_actions", 0)
	battle.set("_replay_actions", 1)
	actions.struck.emit(attacker, target, target.cell, true)
	actions.struck.emit(attacker, target, target.cell, false)
	await process_frame
	_check(effects.get_child_count() == 0 and target.recoil_offset == Vector2.ZERO,
		"이어하기 재실행 중에는 이펙트를 만들지 않는다")
	battle.set("_replay_actions", 0)
	battle.set("_turn_actions", turn_actions)
	var temporary: CombatUnit = CombatUnit.new()
	battle.get_node("Units").add_child(temporary)
	actions.struck.emit(attacker, temporary, temporary.cell, true)
	await process_frame
	temporary.free()
	await create_timer(0.5).timeout
	_check(effects.get_child_count() == 0, "이펙트 도중 대상이 해제되어도 정리된다")


## 상태 이상 효과(#635): 신호마다 맞는 폴더의 효과가 한 번 재생되고, 4배속에서 줄며, 이어하기 재실행에서는 없다.
func _test_status_effects() -> void:
	var units: Array[CombatUnit] = battle.get("units")
	var actions: CombatActions = battle.get("actions") as CombatActions
	var effects: Node = battle.get_node_or_null("HitEffects")
	_check(effects != null, "상태 효과 시험: HitEffects 노드가 있다")
	if effects == null:
		return
	var shader: Material = load("res://scenes/combat/art/pixel_art.tres")
	var unit: CombatUnit = units[0]
	var cases: Array = [
		["stun", func() -> void: actions.status_applied.emit(unit, "stun")],
		["burn", func() -> void: actions.status_applied.emit(unit, "burn")],
		["poison", func() -> void: actions.status_applied.emit(unit, "poison")],
		["fallen", func() -> void: actions.status_applied.emit(unit, "fallen")],
		["burn", func() -> void: actions.status_ticked.emit(unit, "burn", 3)],
		["poison", func() -> void: actions.status_ticked.emit(unit, "poison", 1)],
	]
	for entry: Array in cases:
		(entry[1] as Callable).call()
		await process_frame
		var found: Array[Node] = _sprites(effects)
		var path: String = found[0].sprite_frames.get_frame_texture(&"play", 0).resource_path if found.size() == 1 else ""
		_check(found.size() == 1 and ("/%s/" % entry[0]) in path and found[0].material == shader and absf(found[0].scale.x - 0.5) < 0.001,
			"상태 효과 %s는 pixel_art 재질의 0.5배 효과 하나: %s" % [entry[0], path])
		var finished: bool = await _wait_for(func() -> bool: return effects.get_child_count() == 0, 1.0)
		_check(finished, "상태 효과 %s는 한 번 재생하고 사라진다" % entry[0])
	var map: TileMapLayer = battle.get("map")
	var cells: Array[Vector2i] = [unit.cell, unit.cell + Vector2i(1, 0), unit.cell + Vector2i(0, 1)]
	actions.oil_ignited.emit(cells)
	await process_frame
	var fires: Array[Node] = _sprites(effects)
	var fire_path: String = fires[0].sprite_frames.get_frame_texture(&"play", 0).resource_path if fires.size() > 0 else ""
	_check(fires.size() == cells.size() and "/ignite/" in fire_path and fires[0].material == shader,
		"점화는 탄 칸마다 ignite 효과를 만든다: %d/%d" % [fires.size(), cells.size()])
	_check(fires.size() > 0 and fires[0].position.distance_to(map.map_to_surface(cells[0])) < 20.0,
		"점화 효과는 칸 표면 근처에 놓인다")
	await _wait_for(func() -> bool: return effects.get_child_count() == 0, 1.0)
	# 밀려나 기름에 미끄러진 순간처럼 칸만 바뀌고 그림 위치는 아직 떠난 칸이다.
	var departure: Vector2i = unit.cell
	unit.cell = departure + Vector2i(1, 0)
	actions.status_applied.emit(unit, "fallen")
	await process_frame
	var dust: Array[Node] = _sprites(effects)
	_check(dust.size() == 1 and dust[0].position.distance_to(map.map_to_surface(unit.cell)) < dust[0].position.distance_to(map.map_to_surface(departure)),
		"상태 효과는 떠난 칸이 아니라 대상이 지금 선 칸에 놓인다")
	unit.cell = departure
	await _wait_for(func() -> bool: return effects.get_child_count() == 0, 1.0)
	Engine.time_scale = 4.0
	var started: int = Time.get_ticks_msec()
	actions.status_applied.emit(unit, "stun")
	await process_frame
	var fast_spawned: bool = _sprites(effects).size() == 1
	while effects.get_child_count() > 0 and Time.get_ticks_msec() - started < 2000:
		await process_frame
	var fast_msec: int = Time.get_ticks_msec() - started
	Engine.time_scale = 1.0
	_check(fast_spawned and fast_msec < 200, "4배속에서는 1배속 기절 길이(333ms)보다 짧은 실제 시간에 끝난다: %dms" % fast_msec)
	await create_timer(0.1).timeout
	var turn_actions: int = battle.get("_turn_actions")
	battle.set("_turn_actions", 0)
	battle.set("_replay_actions", 1)
	actions.status_applied.emit(unit, "burn")
	actions.status_ticked.emit(unit, "poison", 1)
	actions.oil_ignited.emit(cells)
	await process_frame
	_check(effects.get_child_count() == 0, "이어하기 재실행 중에는 상태 효과를 만들지 않는다")
	battle.set("_replay_actions", 0)
	battle.set("_turn_actions", turn_actions)


## 전투 불능 효과(#636): downed 신호에 유닛 그림 복제 잔상과 down 폭발이 한 번 생기고, 전체 속도 계수를 따르며, 4배속에서 줄고, 이어하기 재실행에서는 없다.
func _test_down_effect() -> void:
	var units: Array[CombatUnit] = battle.get("units")
	var actions: CombatActions = battle.get("actions") as CombatActions
	var effects: Node = battle.get_node_or_null("HitEffects")
	_check(effects != null, "전투 불능 효과 시험: HitEffects 노드가 있다")
	if effects == null:
		return
	var shader: Material = load("res://scenes/combat/art/pixel_art.tres")
	var unit: CombatUnit = units[0]
	var foot: Vector2 = unit.position + Vector2(0, unit.floor_offset_y + unit.body_offset_y)
	var frame: Texture2D = unit.current_frame_texture()
	var down_started: int = Time.get_ticks_msec()
	actions.downed.emit(unit)
	await process_frame
	var bursts: Array[Node] = _sprites(effects)
	var ghosts: Array[Node] = _ghosts(effects)
	var path: String = bursts[0].sprite_frames.get_frame_texture(&"play", 0).resource_path if bursts.size() == 1 else ""
	_check(bursts.size() == 1 and "/down/" in path and bursts[0].material == shader and absf(bursts[0].scale.x - 0.5) < 0.001,
		"전투 불능은 pixel_art 재질의 0.5배 down 폭발 하나: %s" % path)
	_check(bursts.size() == 1 and absf(bursts[0].sprite_frames.get_animation_speed(&"play") - CombatPresentation.fps(12.0)) < 0.001
		and not bursts[0].sprite_frames.get_animation_loop(&"play"),
		"down 폭발 속도는 전체 속도 계수를 따르고 반복하지 않는다")
	_check(ghosts.size() == 1 and (ghosts[0] as Sprite2D).texture == frame and (ghosts[0] as Sprite2D).material == shader
		and ghosts[0].position.distance_to(foot) < 2.0,
		"유닛 그림을 복제한 쓰러짐 잔상이 유닛 발 기준 자리에 하나 생긴다")
	# 잔상은 번쩍인 뒤에야 가라앉기 시작한다(둘이 동시에 시작하면 안 된다).
	var sink_msec: int = -1
	while ghosts.size() == 1 and is_instance_valid(ghosts[0]) and Time.get_ticks_msec() - down_started < 1000:
		if absf(ghosts[0].position.y - foot.y) > 0.001:
			sink_msec = Time.get_ticks_msec() - down_started
			break
		await process_frame
	_check(sink_msec >= 40, "잔상은 섬광(60ms)이 끝난 뒤에 가라앉기 시작한다: %dms" % sink_msec)
	var finished: bool = await _wait_for(func() -> bool: return effects.get_child_count() == 0, 1.5)
	_check(finished, "쓰러짐 폭발과 잔상은 한 번 재생하고 사라진다")
	Engine.time_scale = 4.0
	var started: int = Time.get_ticks_msec()
	actions.downed.emit(unit)
	await process_frame
	var fast_spawned: bool = _sprites(effects).size() == 1 and _ghosts(effects).size() == 1
	while effects.get_child_count() > 0 and Time.get_ticks_msec() - started < 2000:
		await process_frame
	var fast_msec: int = Time.get_ticks_msec() - started
	Engine.time_scale = 1.0
	_check(fast_spawned and fast_msec < 350, "4배속에서는 1배속 길이(약 0.5초)보다 짧은 실제 시간에 끝난다: %dms" % fast_msec)
	await create_timer(0.1).timeout
	var turn_actions: int = battle.get("_turn_actions")
	battle.set("_turn_actions", 0)
	battle.set("_replay_actions", 1)
	actions.downed.emit(unit)
	await process_frame
	_check(effects.get_child_count() == 0, "이어하기 재실행 중에는 전투 불능 효과를 만들지 않는다")
	battle.set("_replay_actions", 0)
	battle.set("_turn_actions", turn_actions)
	var temporary: CombatUnit = CombatUnit.new()
	battle.get_node("Units").add_child(temporary)
	actions.downed.emit(temporary)
	await process_frame
	temporary.free()
	await create_timer(0.7).timeout
	_check(effects.get_child_count() == 0, "쓰러짐 효과 도중 유닛이 해제되어도 정리된다")
	# #717: 밀림·낙하·낙사는 _land가 cell만 바꾸고 downed를 낸다. 표시 좌표는 아직 출발 칸이므로 효과는 착지 칸 표면에 떠야 한다.
	var land_map: TileMapLayer = battle.get("map")
	var origin_cell: Vector2i = unit.cell
	var landing_cell: Vector2i = origin_cell + Vector2i(1, 0)
	var origin_foot: Vector2 = unit.position + Vector2(0, unit.floor_offset_y + unit.body_offset_y)
	var landing_surface: Vector2 = land_map.map_to_surface(landing_cell)
	unit.cell = landing_cell
	actions.downed.emit(unit)
	await process_frame
	var landed_bursts: Array[Node] = _sprites(effects)
	var landed_ghosts: Array[Node] = _ghosts(effects)
	_check(landed_ghosts.size() == 1 and landed_ghosts[0].position.distance_to(landing_surface) < 0.01
		and landed_ghosts[0].position.distance_to(origin_foot) > 4.0,
		"밀려 쓰러지면 잔상이 착지 칸 표면에 뜬다(출발 칸이 아니다)")
	_check(landed_bursts.size() == 1 and landed_bursts[0].position.distance_to(landing_surface + Vector2(0, -12)) < 0.01
		and landed_bursts[0].position.distance_to(origin_foot + Vector2(0, -12)) > 4.0,
		"밀려 쓰러지면 down 폭발이 착지 칸 표면에 뜬다(출발 칸이 아니다)")
	unit.cell = origin_cell
	await _wait_for(func() -> bool: return effects.get_child_count() == 0, 1.5)
	# 실제 전투 불능 전환이 유닛을 숨기기 전에 그림을 잡는다. 전투 상태를 바꾸므로 맨 끝에 둔다.
	var last: CombatUnit = units[units.size() - 1]
	var seen: Array[bool] = [false]
	actions.downed.connect(func(_unit: CombatUnit) -> void: seen[0] = true, CONNECT_ONE_SHOT)
	actions.incapacitate(last)
	await process_frame
	_check(seen[0] and not last.visible and _sprites(effects).size() == 1 and _ghosts(effects).size() == 1,
		"incapacitate 한 번으로 효과가 생기고 유닛은 숨겨진다")
	await _wait_for(func() -> bool: return effects.get_child_count() == 0, 1.5)


## 스킬 효과(#634). 신호를 직접 보내 전투 장면의 연결을 본다.
func _test_skill_effects() -> void:
	var units: Array[CombatUnit] = battle.get("units")
	var actions: CombatActions = battle.get("actions") as CombatActions
	var effects: Node = battle.get_node_or_null("HitEffects")
	_check(effects != null, "스킬 효과 시험: HitEffects 노드가 있다")
	if effects == null:
		return
	var shader: Material = load("res://scenes/combat/art/pixel_art.tres")
	var caster: CombatUnit = units[0]
	actions.self_used.emit(caster, "holy_veil")
	await process_frame
	var shield: Array[Node] = _sprites(effects)
	_check(shield.size() == 1 and shield[0].material == shader and absf(shield[0].scale.x - 0.5) < 0.001,
		"성스러운 장막은 pixel_art 재질의 0.5배 효과 하나를 만든다")
	await _wait_for(func() -> bool: return effects.get_child_count() == 0, 1.0)
	_check(effects.get_child_count() == 0, "방어막 효과는 한 번 재생하고 사라진다")
	actions.healed.emit(caster, 3)
	await process_frame
	var heal: Array[Node] = _sprites(effects)
	_check(heal.size() == 1 and heal[0].material == shader and absf(heal[0].scale.x - 0.5) < 0.001,
		"회복(숨 고르기·물약)은 pixel_art 재질의 0.5배 효과 하나를 만든다")
	await _wait_for(func() -> bool: return effects.get_child_count() == 0, 1.0)
	var buffed: int = 0
	for unit: CombatUnit in units:
		if unit.is_ally and unit.hit_points > 0:
			unit.battle_cry_source = caster
			buffed += 1
	actions.self_used.emit(caster, "battle_cry")
	await process_frame
	_check(buffed >= 2 and _sprites(effects).size() == buffed,
		"전투의 함성은 시전자의 함성을 받은 아군마다 효과를 만든다: %d/%d" % [_sprites(effects).size(), buffed])
	await _wait_for(func() -> bool: return effects.get_child_count() == 0, 1.0)
	for unit: CombatUnit in units:
		unit.battle_cry_source = null
	var map: TileMapLayer = battle.get("map")
	var neighbors: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
	var leftmost: Vector2i = neighbors[0]
	var rightmost: Vector2i = neighbors[0]
	for step: Vector2i in neighbors:
		var screen_x: float = map.map_to_local(caster.cell + step).x
		if screen_x < map.map_to_local(caster.cell + leftmost).x:
			leftmost = step
		if screen_x > map.map_to_local(caster.cell + rightmost).x:
			rightmost = step
	actions.swept.emit(caster, caster.cell + leftmost)
	await process_frame
	var left_trail: Array[Node] = _sprites(effects)
	_check(left_trail.size() == 1 and left_trail[0].material == shader and left_trail[0].flip_h,
		"왼쪽 정면의 휩쓸기 궤적은 pixel_art 재질로 좌우를 뒤집는다")
	await _wait_for(func() -> bool: return effects.get_child_count() == 0, 1.0)
	actions.swept.emit(caster, caster.cell + rightmost)
	await process_frame
	var right_trail: Array[Node] = _sprites(effects)
	_check(right_trail.size() == 1 and not right_trail[0].flip_h, "오른쪽 정면의 궤적은 뒤집지 않는다")
	await _wait_for(func() -> bool: return effects.get_child_count() == 0, 1.0)
	var below: Vector2i = neighbors[0]
	var above: Vector2i = neighbors[0]
	for step: Vector2i in neighbors:
		if map.map_to_local(caster.cell + step).y > map.map_to_local(caster.cell + below).y:
			below = step
		if map.map_to_local(caster.cell + step).y < map.map_to_local(caster.cell + above).y:
			above = step
	actions.swept.emit(caster, caster.cell + below)
	await process_frame
	var front: Array[Node] = _sprites(effects)
	var front_path: String = front[0].sprite_frames.get_frame_texture(&"play", 0).resource_path if front.size() == 1 else ""
	await _wait_for(func() -> bool: return effects.get_child_count() == 0, 1.0)
	actions.swept.emit(caster, caster.cell + above)
	await process_frame
	var back: Array[Node] = _sprites(effects)
	var back_path: String = back[0].sprite_frames.get_frame_texture(&"play", 0).resource_path if back.size() == 1 else ""
	await _wait_for(func() -> bool: return effects.get_child_count() == 0, 1.0)
	_check("sweep_front" in front_path and "sweep_back" in back_path, "화면 아래쪽 정면은 앞 궤적, 위쪽 정면은 뒤 궤적: %s / %s" % [front_path, back_path])
	Engine.time_scale = 4.0
	var started: int = Time.get_ticks_msec()
	actions.self_used.emit(caster, "holy_veil")
	await process_frame
	while effects.get_child_count() > 0 and Time.get_ticks_msec() - started < 2000:
		await process_frame
	var fast_msec: int = Time.get_ticks_msec() - started
	Engine.time_scale = 1.0
	_check(fast_msec < 200, "4배속에서는 1배속 방어막 길이(333ms)보다 짧은 실제 시간에 끝난다: %dms" % fast_msec)
	await create_timer(0.1).timeout
	var turn_actions: int = battle.get("_turn_actions")
	battle.set("_turn_actions", 0)
	battle.set("_replay_actions", 1)
	actions.self_used.emit(caster, "holy_veil")
	actions.self_used.emit(caster, "battle_cry")
	actions.healed.emit(caster, 2)
	actions.swept.emit(caster, caster.cell + rightmost)
	await process_frame
	_check(effects.get_child_count() == 0, "이어하기 재실행 중에는 스킬 효과를 만들지 않는다")
	battle.set("_replay_actions", 0)
	battle.set("_turn_actions", turn_actions)
	var temporary: CombatUnit = CombatUnit.new()
	battle.get_node("Units").add_child(temporary)
	actions.healed.emit(temporary, 2)
	await process_frame
	temporary.free()
	await create_timer(0.6).timeout
	_check(effects.get_child_count() == 0, "효과 도중 유닛이 해제되어도 정리된다")


func _sprites(effects: Node) -> Array[Node]:
	var found: Array[Node] = []
	for child: Node in effects.get_children():
		if child is AnimatedSprite2D:
			found.append(child)
	return found


func _ghosts(effects: Node) -> Array[Node]:
	var found: Array[Node] = []
	for child: Node in effects.get_children():
		if child is Sprite2D:
			found.append(child)
	return found


func _wait_for(predicate: Callable, seconds: float) -> bool:
	var deadline: int = Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < deadline:
		if predicate.call():
			return true
		await create_timer(0.02).timeout
	return false


func _popups() -> Array[Label]:
	var result: Array[Label] = []
	for child: Node in battle.get_node("Units").get_children():
		if child is Label and child.has_meta("feedback_unit"):
			result.append(child)
	return result


func _monitor() -> void:
	while monitoring:
		await process_frame
		if not monitoring:
			return
		var popups: Array[Label] = _popups()
		popup_samples += popups.size()
		for index: int in range(popups.size()):
			var popup: Label = popups[index]
			popup_styles[popup.text] = [popup.get_theme_color("font_color"), popup.get_theme_font_size("font_size")]
			if popup.modulate.a < 0.1:
				continue
			var rect: Rect2 = popup.get_global_transform_with_canvas() * Rect2(Vector2.ZERO, popup.size)
			var outside: String = "화면 밖: %s" % popup.text
			if not root.get_visible_rect().encloses(rect.grow(2)) and outside not in collisions:
				collisions.append(outside)
			var hud: CombatTurnHud = battle.get_node("UI/TurnHud") as CombatTurnHud
			for unit: CombatUnit in battle.get("units"):
				var status: String = "기절" if unit.is_stunned else ""
				if status.is_empty():
					continue
				var font: Font = ThemeDB.fallback_font
				var width: float = font.get_string_size(status, HORIZONTAL_ALIGNMENT_LEFT, -1, 10).x
				var status_rect: Rect2 = unit.get_global_transform_with_canvas() * Rect2(
					Vector2(-width / 2.0, unit.floor_offset_y + unit.get_status_label_y() - font.get_ascent(10)),
					Vector2(width, font.get_height(10)))
				var status_pair: String = "%s / %s %s" % [popup.text, unit.get_display_name(), status]
				if rect.grow(2).intersects(status_rect) and status_pair not in collisions:
					collisions.append(status_pair)
			for panel: String in ["Round", "Progress", "OrderScroll", "UnitDetails", "Skills", "CombatLog", "EndTurn"]:
				var control: Control = hud.get_node(panel) as Control
				var blocked: String = "%s / HUD %s" % [popup.text, panel]
				if rect.grow(2).intersects(control.get_global_rect()) and blocked not in collisions:
					collisions.append(blocked)
			for other_index: int in range(index):
				var other: Label = popups[other_index]
				var other_rect: Rect2 = other.get_global_transform_with_canvas() * Rect2(Vector2.ZERO, other.size)
				var pair: String = "%s / %s" % [other.text, popup.text]
				if (other.modulate.a >= 0.1 and rect.grow(2).intersects(other_rect.grow(2))
					and pair not in collisions):
					collisions.append(pair)
