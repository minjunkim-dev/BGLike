extends SceneTree
## 주사위 굴림 연출: 어떤 굴림이 언제 훅에 전달되는지, 아군만 보이는지, 뷰가 결과를 정확히 보이는지.

class Fixture extends RefCounted:
	var units: Array[CombatUnit] = []
	var turns: CombatTurns = CombatTurns.new()
	var actions: CombatActions = CombatActions.new()
	var events: Array[String] = []
	var rolls: Array[CombatDiceRoll] = []


const ScriptedDice = preload("res://tests/scripted_dice.gd")

var _checks: int = 0
var _failures: int = 0
var _created: Array[CombatUnit] = []
var _fixtures: Array[Fixture] = []


func _initialize() -> void:
	create_timer(60.0).timeout.connect(func() -> void:
		push_error("Combat dice roll: test timeout")
		quit(1)
	)
	_run.call_deferred()


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error(message)


func _run() -> void:
	_test_shapes()
	_test_liquid_surface()
	_test_total_text()
	_test_textures()
	_test_rolling_frames()
	_test_die_offset()
	_test_rising_surface()
	_test_effect_pixels()
	_test_panel_placement()
	await _test_hit_roll_is_awaited_before_the_log()
	_test_poison_roll_does_not_block_the_turn()
	await _test_spin_save_is_awaited_before_damage()
	await _test_give_up_during_roll()
	await _test_give_up_during_spin_roll()
	_test_pull_save_does_not_block_the_action()
	_test_rock_stun_save_is_presented()
	_test_values_without_presentation()
	await _test_scene()
	for f: Fixture in _fixtures:
		# 훅 람다가 픽스처를 붙잡고 있어 순환을 끊는다.
		f.actions.roll_animation = Callable()
		for connection: Dictionary in f.actions.logged.get_connections():
			f.actions.logged.disconnect(connection["callable"] as Callable)
		for connection: Dictionary in f.actions.reaction_requested.get_connections():
			f.actions.reaction_requested.disconnect(connection["callable"] as Callable)
	_fixtures.clear()
	for unit: CombatUnit in _created:
		unit.free()
	var dice_problems: Array[String] = ScriptedDice.finish()
	_check(dice_problems.is_empty(), "준비한 주사위 값을 요청대로 모두 굴림 " + str(dice_problems))
	print("Combat dice roll: %d checks, %d failures" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)



## 액체 표면 행: draw_dice.py sheet_cell과 같은 공식. 마스크 행 12~35(24행)의 d20 꼴을 예로 든다.
func _test_liquid_surface() -> void:
	var cases: Array = [[0, 24], [6, 12], [-6, 36], [100, 12], [-100, 36], [2, 20], [-3, 30]]
	for entry: Array in cases:
		_check(CombatDiceRollView.liquid_surface(12, 35, entry[0]) == entry[1],
			"여유 %d의 액체 표면은 %d행: %d" % [entry[0], entry[1], CombatDiceRollView.liquid_surface(12, 35, entry[0])])


func _test_total_text() -> void:
	_check(CombatDiceRollView.total_text(_result([14], 14, 17, true)) == "17 = 14+3", "합계 옆 식은 17 = 14+3")
	_check(CombatDiceRollView.total_text(_result([11], 11, 9, false)) == "9 = 11-2", "음수 보정은 9 = 11-2")
	_check(CombatDiceRollView.total_text(_result([14], 14, 14, true)) == "14 = 14+0", "0 보정은 14 = 14+0")
	_check(CombatDiceRollView.total_text(_result([20], 20, 23, true, CombatChecks.Face.ABSOLUTE_SUCCESS)) == "20",
		"절대면은 굴린 눈만 보인다")


func _test_textures() -> void:
	for sides: int in [4, 6, 8, 10, 12, 20]:
		for state: String in ["rolling", "success", "failure", "absolute_success", "absolute_failure"]:
			var texture: Texture2D = CombatDiceRollView.die_texture(sides, state)
			_check(texture != null and texture.get_size() == Vector2(48, 48), "d%d_%s 그림은 48×48이다" % [sides, state])
		var mask: Texture2D = CombatDiceRollView.liquid_texture(sides)
		_check(mask != null and mask.get_size() == Vector2(48, 48), "d%d 액체 마스크는 48×48이다" % sides)
	_check(CombatDiceRollView.die_texture(7, "success") == null and CombatDiceRollView.liquid_texture(7) == null,
		"그림이 없는 면 수는 null이라 벡터 그림으로 남는다")


func _test_panel_placement() -> void:
	var screen: Rect2 = Rect2(0, 0, 640, 360)
	var panel: Vector2 = CombatDiceRollView.PANEL_SIZE
	var above: Vector2 = CombatDiceRollView.panel_origin(Vector2(320.4, 200.6), panel, screen)
	_check(above == above.round() and absf(above.x + panel.x * 0.5 - 320.4) <= 0.5 and absf(above.y + panel.y - 200.6) <= 0.5
		and not CombatDiceRollView.is_offscreen(Vector2(320.4, 200.6), panel, screen),
		"머리 위 패널은 정수 논리 px이고 가운데가 유닛 x, 아랫변이 머리 점이다: " + str(above))
	var spot: Rect2 = Rect2(CombatDiceRollView.panel_origin(Vector2(-50, 200), panel, screen), panel)
	_check(CombatDiceRollView.is_offscreen(Vector2(-50, 200), panel, screen)
		and CombatDiceRollView.is_offscreen(Vector2(320, 5), panel, screen)
		and CombatDiceRollView.is_offscreen(Vector2(700, 200), panel, screen)
		and CombatDiceRollView.is_offscreen(Vector2.INF, panel, screen),
		"패널이 화면을 벗어나면 화면 밖이다")
	# 합계 글자는 패널 오른쪽 밖까지 나간다. 오른쪽 가장자리 근처 유닛은 글자가 잘리지 않게 화면 밖 자리로 간다(PR #646 리뷰, #727 배경 여백 포함).
	_check(not CombatDiceRollView.is_offscreen(Vector2(569, 200), panel, screen)
		and CombatDiceRollView.is_offscreen(Vector2(569, 200), CombatDiceRollView.footprint(1), screen)
		and CombatDiceRollView.footprint(1).x == 150.0 + 2.0 * CombatDiceRollView.BACKDROP_PAD.x
		and CombatDiceRollView.footprint(2).x == 178.0 + 2.0 * CombatDiceRollView.BACKDROP_PAD.x
		and not CombatDiceRollView.is_offscreen(Vector2(320, 200), CombatDiceRollView.footprint(2), screen),
		"화면 밖 판정은 기준값·합계 글자 폭과 배경 패널 여백까지 본다")
	_check(screen.encloses(spot) and spot.position == spot.position.round()
		and absf(spot.get_center().x - 320.0) <= 0.5
		and spot.position.y >= 86.0 and not spot.intersects(Rect2(256, 128, 128, 64)),
		"화면 밖 자리는 가운데 위, 턴 순서 막대(y 86) 아래이고 C와 겹치지 않는다: " + str(spot))


## 아군 둘(0·1)과 적 둘(2·3). 연출 훅은 사건 순서를 기록하고 한 프레임을 기다린다.
func _fixture() -> Fixture:
	var f: Fixture = Fixture.new()
	_fixtures.append(f)
	for index: int in range(4):
		var unit: CombatUnit = CombatUnit.new()
		unit.kind = CombatUnit.Kind.WARRIOR if index % 2 == 0 else CombatUnit.Kind.ARCHER
		unit.is_ally = index < 2
		unit.cell = [Vector2i(4, 4), Vector2i(3, 4), Vector2i(5, 4), Vector2i(7, 4)][index]
		unit.hit_points = unit.get_max_hit_points()
		f.units.append(unit)
		_created.append(unit)
	ScriptedDice.arrange_turns(f.turns, f.units, f.units)
	f.actions.initialize(f.units, f.turns)
	f.actions.logged.connect(func(message: String) -> void: f.events.append("log: " + message))
	f.actions.roll_animation = func(roll: CombatDiceRoll) -> void:
		f.rolls.append(roll)
		f.events.append("roll start")
		await process_frame
		f.events.append("roll end")
	return f


func _dice_for(expected: Array[int], sides: Array) -> ScriptedDice:
	var typed: Array[int] = []
	typed.assign(sides)
	return ScriptedDice.new(expected, typed)


## 굴림 프레임: 눈 바꾸기 단계(8단계)와 함께 0→1→2→3→0으로 넘어간다. 멈춘 상태 그림은 프레임과 상관없다.
func _test_rolling_frames() -> void:
	var cases: Array = [[0.0, 0], [0.06, 1], [0.12, 2], [0.17, 3], [0.23, 0], [0.29, 1], [0.45, 0], [9.0, 0]]
	for entry: Array in cases:
		_check(CombatDiceRollView.rolling_frame(entry[0]) == entry[1],
			"굴림 %.2f초의 프레임은 %d: %d" % [entry[0], entry[1], CombatDiceRollView.rolling_frame(entry[0])])
	for sides: int in [4, 6, 8, 10, 12, 20]:
		var seen: Dictionary[PackedByteArray, bool] = {}
		for frame: int in range(4):
			var texture: Texture2D = CombatDiceRollView.die_texture(sides, "rolling", frame)
			_check(texture != null and texture.get_size() == Vector2(48, 48), "d%d 굴림 프레임 %d은 48×48이다" % [sides, frame])
			if texture != null:
				seen[texture.get_image().get_data()] = true
		_check(seen.size() == 4, "d%d 굴림 프레임 4장은 서로 다르다" % sides)
		_check(CombatDiceRollView.die_texture(sides, "success", 2) == CombatDiceRollView.die_texture(sides, "success"),
			"멈춘 상태 그림은 프레임과 상관없다")
	_check(CombatDiceRollView.die_texture(7, "rolling", 1) == null, "그림이 없는 면 수는 굴림 프레임도 null이다")


func _test_die_offset() -> void:
	var success: CombatChecks.RollResult = _result([9], 9, 12, true)
	var failure: CombatChecks.RollResult = _result([3], 3, 6, false)
	var absolute_success: CombatChecks.RollResult = _result([20], 20, 23, true, CombatChecks.Face.ABSOLUTE_SUCCESS)
	var absolute_failure: CombatChecks.RollResult = _result([1], 1, 4, false, CombatChecks.Face.ABSOLUTE_FAILURE)
	_check(CombatDiceRollView.die_offset(success, true, 1, 0.0) == Vector2i(0, -1)
		and CombatDiceRollView.die_offset(success, true, 2, 0.0) == Vector2i.ZERO
		and CombatDiceRollView.die_offset(success, true, 7, 0.0) == Vector2i(0, -1),
		"굴리는 동안 홀수 단계에 1 논리px 위로 튄다")
	var shake: Array = [[0.015, Vector2i(1, 0)], [0.045, Vector2i(-1, 0)], [0.075, Vector2i(1, 0)], [0.105, Vector2i.ZERO]]
	for entry: Array in shake:
		_check(CombatDiceRollView.die_offset(failure, false, 8, entry[0]) == entry[1], "실패 흔들림 %.3f초" % entry[0])
	_check(CombatDiceRollView.die_offset(absolute_failure, false, 8, 0.03) == Vector2i(0, 1)
		and CombatDiceRollView.die_offset(absolute_failure, false, 8, 0.07) == Vector2i.ZERO,
		"절대실패는 1 논리px 내려앉았다 돌아온다")
	_check(CombatDiceRollView.die_offset(success, false, 8, 0.03) == Vector2i.ZERO
		and CombatDiceRollView.die_offset(absolute_success, false, 8, 0.03) == Vector2i.ZERO,
		"성공·절대성공은 흔들리지 않는다")
	for result: CombatChecks.RollResult in [success, failure, absolute_success, absolute_failure]:
		_check(CombatDiceRollView.die_offset(result, false, 8, CombatDiceRollView.EFFECT_TIME + 0.01) == Vector2i.ZERO,
			"효과 시간이 지나면 모두 0이다")


func _test_rising_surface() -> void:
	_check(CombatDiceRollView.rising_surface(12, 35, 3, 0.0) == 36
		and CombatDiceRollView.rising_surface(12, 35, 3, CombatDiceRollView.RISE_TIME) == 3
		and CombatDiceRollView.rising_surface(12, 35, 3, 5.0) == 3,
		"액체는 바닥 아래(bottom + 1)에서 시작해 차오름 시간 뒤 결과 표면에 닿는다")
	var previous: int = 99
	var monotone: bool = true
	for step: int in range(13):
		var row: int = CombatDiceRollView.rising_surface(12, 35, 20, CombatDiceRollView.RISE_TIME * step / 12.0)
		monotone = monotone and row <= previous and row >= 20 and row <= 36
		previous = row
	_check(monotone, "차오르는 표면 행은 줄어들기만 하고 바닥과 결과 사이에 있다")
	_check(CombatDiceRollView.rising_surface(12, 35, 36, 0.03) == 36, "결과 표면이 바닥이면 차오르지 않는다")


func _test_effect_pixels() -> void:
	var normal: PackedVector2Array = CombatDiceRollView.effect_pixels(CombatChecks.Face.NORMAL, 0.05)
	_check(normal.is_empty(), "일반 면은 불티·파편이 없다")
	var sparks_start: PackedVector2Array = CombatDiceRollView.effect_pixels(CombatChecks.Face.ABSOLUTE_SUCCESS, 0.0)
	var sparks_late: PackedVector2Array = CombatDiceRollView.effect_pixels(CombatChecks.Face.ABSOLUTE_SUCCESS, 0.2)
	_check(sparks_start.size() == 5 and sparks_late.size() == 5, "절대성공은 불티 5개다")
	var integers: bool = true
	for point: Vector2 in sparks_late:
		integers = integers and point == point.round()
	_check(integers, "불티 좌표는 정수 논리 px다")
	_check(sparks_start.size() == 5 and sparks_late.size() == 5 and sparks_late[2].length() > sparks_start[2].length(),
		"불티는 시간이 지날수록 바깥으로 나간다")
	_check(sparks_start[2].y < 0.0, "가운데 불티는 주사위 위쪽으로 나간다")
	var shards_start: PackedVector2Array = CombatDiceRollView.effect_pixels(CombatChecks.Face.ABSOLUTE_FAILURE, 0.0)
	var shards_late: PackedVector2Array = CombatDiceRollView.effect_pixels(CombatChecks.Face.ABSOLUTE_FAILURE, 0.2)
	_check(shards_start.size() == 3 and shards_late.size() == 3 and shards_late[0].y - shards_start[0].y >= 2.0,
		"절대실패는 파편 3개가 아래로 떨어진다")
	for face: CombatChecks.Face in [CombatChecks.Face.ABSOLUTE_SUCCESS, CombatChecks.Face.ABSOLUTE_FAILURE]:
		_check(CombatDiceRollView.effect_pixels(face, CombatDiceRollView.EFFECT_TIME + 0.01).is_empty(),
			"효과 시간이 지나면 불티·파편이 사라진다")


func _result(rolls: Array[int], selected: int, total: int, success: bool,
		face: CombatChecks.Face = CombatChecks.Face.NORMAL) -> CombatChecks.RollResult:
	var result: CombatChecks.RollResult = CombatChecks.RollResult.new()
	result.rolls = rolls
	result.selected_roll = selected
	result.total = total
	result.success = success
	result.face = face
	if rolls.size() > 1:
		result.mode = CombatChecks.RollMode.ADVANTAGE
	return result


func _test_shapes() -> void:
	var corners: Dictionary[int, int] = {4: 3, 6: 4, 8: 4, 10: 4, 12: 5, 20: 6, 7: 16}
	for sides: int in corners:
		_check(CombatDiceRollView.shape_points(sides).size() == corners[sides],
			"d%d는 %d각 윤곽으로 굴린다" % [sides, corners[sides]])
	_check(CombatDiceRollView.shape_points(6) != CombatDiceRollView.shape_points(8),
		"d6와 d8은 모양이 다르다")


func _test_hit_roll_is_awaited_before_the_log() -> void:
	var f: Fixture = _fixture()
	var attacker: CombatUnit = f.units[0]
	var target: CombatUnit = f.units[2]
	f.actions.dice = _dice_for([11, 4], ScriptedDice.attack_sides(attacker) + ScriptedDice.damage_sides(attacker))
	await f.actions.attack(attacker, target)
	_check(f.rolls.size() == 1, "명중과 피해를 굴려도 연출은 명중굴림 하나만 받는다: %d" % f.rolls.size())
	var roll: CombatDiceRoll = f.rolls[0]
	_check(roll.category == CombatDiceRoll.Category.HIT and roll.roller == attacker
		and roll.sides == attacker.get_ability_sides(attacker.get_attack_ability())
		and roll.bonus == attacker.get_attack_bonus() and roll.target_value == target.get_armor_class()
		and roll.result == f.actions.last_attack, "명중굴림은 확정된 결과와 AC·보정을 그대로 전달한다")
	var first_log: int = f.events.find_custom(func(event: String) -> bool: return event.begins_with("log: "))
	_check(f.events.find("roll end") != -1 and f.events.find("roll end") < first_log,
		"연출이 끝난 뒤에 공격 로그와 피해를 낸다: %s" % str(f.events))
	_check(target.hit_points < target.get_max_hit_points(), "연출을 기다려도 피해는 그대로 적용한다")


func _test_poison_roll_does_not_block_the_turn() -> void:
	var f: Fixture = _fixture()
	var target: CombatUnit = f.units[2]
	f.turns.select_unit(f.units[1])
	f.actions.apply_status(f.units[1], target, "poison")
	var dc: int = target.status_effects[0].dc
	f.actions.dice = _dice_for([3], [4])
	f.turns.end_turn()
	f.turns.end_turn()
	_check(target.hit_points == 11, "연출 훅이 기다려도 독 처리는 같은 시점에 끝난다")
	_check(f.rolls.size() == 1 and f.rolls[0].category == CombatDiceRoll.Category.SAVE
		and f.rolls[0].roller == target and f.rolls[0].target_value == dc
		and f.rolls[0].target_label == tr("DC") and f.rolls[0].sides == 4,
		"독 제거는 건강 내성굴림과 독 DC를 기준으로 전달한다")


## 회전회오리는 대상마다 내성굴림을 연출이 끝난 뒤 피해로 이어 간다 (#389 이관, dice-presentation.md 내성).
func _test_spin_save_is_awaited_before_damage() -> void:
	var f: Fixture = _fixture()
	var boss: CombatUnit = f.units[2]
	boss.kind = CombatUnit.Kind.SCRAP_ROBOT_3000
	boss.hit_points = 50
	boss.begin_turn()
	f.turns.current_unit = boss
	f.units[1].cell = Vector2i(5, 3)
	# 전사 민첩 d8 8은 DC 10에 실패하고 궁수 민첩 d12 10은 성공한다 (#528).
	f.actions.dice = _dice_for([8, 6, 10, 6], [8, 12, 12, 12])
	_check(await f.actions.spin(boss), "회전회오리 실행")
	_check(f.rolls.size() == 2 and f.rolls.all(func(roll: CombatDiceRoll) -> bool:
			return roll.category == CombatDiceRoll.Category.SAVE and roll.target_label == tr("DC") and roll.target_value == 10)
		and f.rolls[0].roller == f.units[0] and f.rolls[0].sides == 8 and not f.rolls[0].result.success
		and f.rolls[1].roller == f.units[1] and f.rolls[1].sides == 12 and f.rolls[1].result.success,
		"회전회오리는 대상마다 민첩 내성굴림을 DC 기준으로 전달한다")
	var first_damage: int = -1
	for index: int in range(f.events.size()):
		if f.events[index].begins_with("log: ") and "피해" in f.events[index]:
			first_damage = index
			break
	_check(first_damage > f.events.find("roll end"), "회전회오리 피해는 첫 내성굴림 연출이 끝난 뒤 나온다")


## 연출 중 일시정지 메뉴에서 전투를 포기하면 남은 굴림 결과를 적용하지 않는다.
func _test_give_up_during_roll() -> void:
	var f: Fixture = _fixture()
	var target: CombatUnit = f.units[2]
	target.hit_points = 1
	f.units[3].hit_points = 0
	f.actions.roll_animation = func(roll: CombatDiceRoll) -> void:
		f.rolls.append(roll)
		f.actions.give_up()
		await process_frame
	f.actions.dice = _dice_for([15], ScriptedDice.attack_sides(f.units[0]))
	await f.actions.attack(f.units[0], target)
	_check(f.rolls.size() == 1 and target.hit_points == 1 and f.actions.last_damage == 0
		and f.actions.is_over() and not f.actions.is_victory(), "연출 중 전투를 포기하면 명중해도 피해와 승리를 적용하지 않는다")
	_check(not f.actions.busy, "명중 연출 중 포기한 뒤 동작 잠금을 푼다")


## 회전회오리 첫 내성굴림 연출 중 포기하면 그 대상의 피해도, 남은 대상의 굴림도 없고 동작 잠금이 풀린다.
func _test_give_up_during_spin_roll() -> void:
	var f: Fixture = _fixture()
	var boss: CombatUnit = f.units[2]
	boss.kind = CombatUnit.Kind.SCRAP_ROBOT_3000
	boss.hit_points = 50
	boss.begin_turn()
	f.turns.current_unit = boss
	f.units[1].cell = Vector2i(5, 3)
	f.actions.roll_animation = func(roll: CombatDiceRoll) -> void:
		f.rolls.append(roll)
		f.actions.give_up()
		await process_frame
	# 첫 대상(전사)은 민첩 d8로 내성굴림한다(#528).
	f.actions.dice = _dice_for([1], [8])
	_check(await f.actions.spin(boss), "회전회오리 실행")
	_check(f.rolls.size() == 1 and f.actions.last_damage == 0
		and not f.events.any(func(event: String) -> bool: return "피해" in event),
		"연출 중 포기하면 회전회오리 피해와 다음 대상의 굴림을 적용하지 않는다: %s" % str(f.events))
	_check(f.actions.is_over() and not f.actions.is_victory() and boss.hit_points == 50, "포기는 패배로 끝난다")
	_check(not f.actions.busy, "회전회오리 연출 중 포기한 뒤 동작 잠금을 푼다")


## 만능팔은 동작이 바로 끝나는 동기 처리라 내성굴림을 기다리지 않는다.
func _test_pull_save_does_not_block_the_action() -> void:
	var f: Fixture = _fixture()
	var boss: CombatUnit = f.units[2]
	boss.kind = CombatUnit.Kind.SCRAP_ROBOT_2000
	boss.hit_points = 45
	boss.cell = Vector2i(4, 4)
	boss.begin_turn()
	f.turns.current_unit = boss
	f.units[0].cell = Vector2i(1, 1)
	f.units[3].cell = Vector2i(0, 9)
	var target: CombatUnit = f.units[1]
	target.cell = Vector2i(7, 4)
	f.actions.dice = _dice_for([1], [6])
	_check(f.actions.pull(boss, target) and target.cell == Vector2i(5, 4), "만능팔 실행과 끌어오기")
	_check(f.rolls.size() == 1 and f.rolls[0].category == CombatDiceRoll.Category.SAVE
		and f.rolls[0].roller == target and f.rolls[0].target_label == tr("DC") and not f.rolls[0].result.success,
		"만능팔은 대상의 힘 내성굴림을 DC 기준으로 전달한다")
	_check(f.events.find("roll end") == -1, "만능팔 연출은 동작 처리를 멈추지 않는다")


## 바위 충돌 기절 내성굴림도 다른 내성처럼 연출 훅으로 간다. 기다리지 않고, 보스는 굴리지 않아 연출도 없다(#560).
func _test_rock_stun_save_is_presented() -> void:
	var agility: CombatUnit.Ability = CombatUnit.Ability.AGILITY
	var f: Fixture = _fixture()
	var target: CombatUnit = f.units[2]
	target.cell = Vector2i(4, 6)
	var rock: CombatGrid.Prop = f.actions.create_prop(Vector2i(4, 5), "rock")
	f.actions.dice = _dice_for([1], [target.get_ability_sides(agility)])
	_check(f.actions.attack_prop(f.units[0], rock) and target.is_stunned, "바위 충돌 기절 전제: 내성 실패로 기절")
	_check(f.rolls.size() == 1 and f.rolls[0].category == CombatDiceRoll.Category.SAVE
		and f.rolls[0].roller == target and f.rolls[0].sides == target.get_ability_sides(agility)
		and f.rolls[0].target_label == tr("DC") and f.rolls[0].target_value == CombatActions.ROCK_STUN_DC
		and not f.rolls[0].result.success,
		"바위 기절 내성굴림을 DC 기준 내성 연출로 전달한다")
	_check(f.events.find("roll end") == -1, "바위 기절 연출은 바위 처리를 멈추지 않는다")
	var boss_fixture: Fixture = _fixture()
	var boss: CombatUnit = boss_fixture.units[2]
	boss.kind = CombatUnit.Kind.SCRAP_ROBOT_1000
	boss.hit_points = boss.get_max_hit_points()
	boss.cell = Vector2i(4, 6)
	var boss_rock: CombatGrid.Prop = boss_fixture.actions.create_prop(Vector2i(4, 5), "rock")
	boss_fixture.actions.dice = _dice_for([], [])
	_check(boss_fixture.actions.attack_prop(boss_fixture.units[0], boss_rock) and boss_fixture.rolls.is_empty(),
		"보스 대상은 굴리지 않아 연출도 없다")


func _test_values_without_presentation() -> void:
	var f: Fixture = _fixture()
	f.units[0].hit_points = 5
	f.units[0].potions.assign(["healing_potion"])
	f.actions.dice = _dice_for([1, 1], [4, 4])
	_check(f.actions.use_self(f.units[0], "potion") and f.units[0].hit_points == 5 + 1 + 1 + 2, "물약 회복 실행")
	_check(f.rolls.is_empty(), "회복 굴림은 연출하지 않는다")
	var bare: CombatActions = CombatActions.new()
	_check(not bare.roll_animation.is_valid(), "훅이 없으면 연출 없이 넘어간다")


func _test_scene() -> void:
	var main: Node = (load("res://scenes/game.tscn") as PackedScene).instantiate()
	(main.get_node("Battle") as Node2D).stages[0] = load("res://scenes/combat/stage.tres") as CombatStage
	root.add_child(main)
	main.get_node("Battle").set_process(false)
	main.get_node("Battle").call("start_battle")
	current_scene = main
	await process_frame
	var battle: Node2D = current_scene.get_node("Battle") as Node2D
	var units: Array[CombatUnit] = battle.get("units")
	var actions: CombatActions = battle.get("actions") as CombatActions
	var view: CombatDiceRollView = battle.get("dice_view") as CombatDiceRollView
	var summary: Label = view.get_node("Summary") as Label
	var target: Label = view.get_node("Target") as Label
	var total: Label = view.get_node("Total") as Label
	_check(view != null and not view.visible and actions.roll_animation.is_valid(),
		"전투 장면은 숨겨진 주사위 뷰를 가지고 훅을 연결한다")
	var ally: CombatUnit = units.filter(func(unit: CombatUnit) -> bool: return unit.is_ally)[0]
	var enemy: CombatUnit = units.filter(func(unit: CombatUnit) -> bool: return not unit.is_ally)[0]
	var dice_state: int = actions.dice.state

	# 몬스터의 굴림은 보이지 않는다.
	var monster_roll: CombatDiceRoll = CombatDiceRoll.hit(enemy, 20, _result([9], 9, 12, true), 3, 12)
	await actions.roll_animation.call(monster_roll)
	_check(not view.visible, "몬스터의 명중굴림은 연출하지 않는다")
	monster_roll = CombatDiceRoll.save(enemy, 4, _result([3], 3, 3, false), 0, tr("DC"), 4)
	await actions.roll_animation.call(monster_roll)
	_check(not view.visible, "몬스터의 독 제거는 연출하지 않는다")

	# 이어하기로 다시 실행하는 중에는 아군이어도 보이지 않는다.
	battle.set("_replay_actions", 1)
	await actions.roll_animation.call(CombatDiceRoll.hit(ally, 20, _result([9], 9, 12, true), 3, 12))
	_check(not view.visible, "이어하기로 다시 실행하는 굴림은 연출하지 않는다")
	battle.set("_replay_actions", 0)

	# 아군의 명중굴림: 기준값을 먼저 보이고, 멈추면 합계와 색을 보인다.
	var hit: CombatDiceRoll = CombatDiceRoll.hit(ally, 20, _result([9], 9, 12, true), 3, 12)
	var finished: Array[bool] = [false]
	# 돌아온 그 순간의 상태. 프레임 길이와 상관없이 바로 숨기지 않고 페이드 중인지 본다.
	var fading_on_return: Array[bool] = [false]
	var play: Callable = func(roll: CombatDiceRoll) -> void:
		finished[0] = false
		await actions.roll_animation.call(roll)
		var tween: Tween = view.get("_fade") as Tween
		fading_on_return[0] = view.visible and tween != null and tween.is_running()
		finished[0] = true
	play.call(hit)
	await process_frame
	_check(view.visible and target.text == "AC 12" and summary.text == "" and not finished[0],
		"굴리는 동안 기준값 AC 12가 먼저 보이고 판정 단어는 아직 없다: " + target.text)
	await create_timer(CombatDiceRollView.TUMBLE_TIME + 0.1).timeout
	_check(summary.text.ends_with(tr("간신히 성공") + "  ±0") and target.text == "AC 12"
		and summary.get_theme_color("font_color") == CombatDiceRollView.SUCCESS_COLOR,
		"멈추면 판정 단어와 여유를 성공 색으로 보인다: " + summary.text)
	_check(total.text == "12 = 9+3" and total.get_theme_color("font_color") == CombatDiceRollView.SUCCESS_COLOR,
		"멈추면 합계 옆에 눈과 보정을 함께 보인다: " + total.text)
	var origin: Vector2 = view.get("_origin")
	_check(not view.get("_offscreen") and origin == origin.round(),
		"유닛이 화면 안이면 머리 위 정수 위치에 둔다: " + str(origin))
	var backdrop_rect: Rect2 = view.get("_backdrop_rect")
	_check(view.has_node("Backdrop") and backdrop_rect.size.x > CombatDiceRollView.DIE_SIZE
		and backdrop_rect.position.x <= origin.x + CombatDiceRollView.PANEL_SIZE.x * 0.5 - CombatDiceRollView.DIE_SIZE * 0.5 - CombatDiceRollView.SIDE_LABEL_GAP
		and backdrop_rect.end.x >= total.position.x + total.get_minimum_size().x
		and backdrop_rect.position.y <= origin.y and backdrop_rect.end.y >= summary.position.y + summary.size.y,
		"배경 패널은 주사위·기준값·합계·판정 단어 줄을 감싼다(#727): " + str(backdrop_rect))
	_check((view.get_node("SuccessSound") as AudioStreamPlayer).playing
		and not (view.get_node("FailureSound") as AudioStreamPlayer).playing, "성공 결과음을 쓴다")
	for _frame: int in range(120):
		if finished[0]:
			break
		await process_frame
	var fade: Tween = view.get("_fade") as Tween
	_check(finished[0] and fading_on_return[0],
		"결과를 잠시 보인 뒤 바로 숨기지 않고 페이드아웃하며, 페이드를 기다리지 않고 대기하던 쪽에 돌려준다")

	# 실패. 앞 결과가 페이드아웃하는 중에 시작해 페이드를 끊는다. 이미 다 흐려졌어도 새 굴림은 불투명해야 한다.
	await create_timer(CombatDiceRollView.FADE_TIME * 0.5).timeout
	play.call(CombatDiceRoll.save(ally, 8, _result([3], 3, 6, false), 3, tr("DC"), 8))
	await process_frame
	_check(view.visible and view.modulate.a == 1.0 and not fade.is_valid() and target.text == "DC 8",
		"페이드아웃 중에 다음 굴림이 오면 페이드를 끊고 바로 새 굴림을 보인다: %.2f" % view.modulate.a)
	await create_timer(CombatDiceRollView.TUMBLE_TIME + 0.1).timeout
	_check(view.visible and view.modulate.a == 1.0, "끊긴 페이드는 끝난 뒤에도 새 굴림을 숨기지 않는다")
	_check(summary.text.ends_with(tr("실패") + "  -2") and target.text == "DC 8"
		and summary.get_theme_color("font_color") == CombatDiceRollView.FAILURE_COLOR
		and (view.get_node("FailureSound") as AudioStreamPlayer).playing,
		"기준에 못 미치면 실패 색과 실패 결과음을 쓴다: " + summary.text)
	await create_timer(CombatDiceRollView.HOLD_TIME + 0.1).timeout

	# 유리: 두 주사위를 함께 보이고 버려지는 쪽을 흐리게 한다.
	var advantage: CombatChecks.RollResult = _result([4, 15], 15, 18, true)
	play.call(CombatDiceRoll.hit(ally, 20, advantage, 3, 12))
	await process_frame
	_check((view.get("_dice") as Array).size() == 2, "유리·불리는 주사위 두 개를 함께 굴린다")
	await create_timer(CombatDiceRollView.TUMBLE_TIME + 0.1).timeout
	var dice: Array = view.get("_dice")
	_check(dice[0].alpha < dice[1].alpha and not dice[0].applied and dice[1].applied
		and dice[0].shown == 4 and dice[1].shown == 15 and dice[0].state == dice[1].state,
		"적용되는 쪽만 액체를 받고 버려지는 쪽은 같은 그림을 흐리게 한다")
	_check(total.text == "18 = 15+3", "버린 주사위의 눈은 합계 식에 넣지 않는다: " + total.text)
	var adv_backdrop: Rect2 = view.get("_backdrop_rect")
	_check(adv_backdrop.size.x >= 2.0 * CombatDiceRollView.DIE_SIZE + CombatDiceRollView.DIE_SPACING + 2.0 * CombatDiceRollView.BACKDROP_PAD.x
		and adv_backdrop.end.x >= total.position.x + total.get_minimum_size().x,
		"유리·불리 주사위 2개와 합계도 배경 패널 안에 들어간다(#727): " + str(adv_backdrop))
	await create_timer(CombatDiceRollView.HOLD_TIME + 0.1).timeout

	_check(GameMusic.duck_level(self) == 0.0, "보통 굴림과 내성굴림은 배경음을 낮추지 않는다")
	# 절대성공: 비교 대신 이름을 보이고 강조한다.
	play.call(CombatDiceRoll.hit(ally, 20, _result([20], 20, 23, true, CombatChecks.Face.ABSOLUTE_SUCCESS), 3, 30))
	await create_timer(CombatDiceRollView.TUMBLE_TIME + 0.1).timeout
	_check(GameMusic.duck_level(self) < 0.0, "명중굴림의 절대성공이 멈추면 배경음을 낮춘다: %s" % GameMusic.duck_level(self))
	dice = view.get("_dice")
	_check(summary.text.ends_with(tr("절대성공")) and dice[0].state == "absolute_success" and total.text == "20",
		"절대성공은 절대성공 그림과 굴린 눈만 보인다: " + summary.text + " / " + total.text)
	await create_timer(CombatDiceRollView.HOLD_TIME + 0.1).timeout
	_check(view.visible and view.modulate.a == 1.0, "명중굴림의 절대성공은 일반 표시 시간이 지나도 흐려지지 않고 보인다")
	await create_timer(CombatDiceRollView.ABSOLUTE_HIT_HOLD_TIME - CombatDiceRollView.HOLD_TIME).timeout
	_check(view.modulate.a < 1.0, "명중굴림의 절대성공은 늘어난 표시 시간 뒤에 페이드아웃한다")

	play.call(CombatDiceRoll.hit(ally, 20, _result([1], 1, 4, false, CombatChecks.Face.ABSOLUTE_FAILURE), 3, 2))
	# 절대면 바로 뒤에 일반 굴림을 이어 붙여, 뒤 굴림이 늘어난 표시 시간만큼 기다리는지 본다.
	play.call(CombatDiceRoll.hit(ally, 20, _result([9], 9, 12, true), 3, 12))
	await create_timer(CombatDiceRollView.TUMBLE_TIME + 0.1).timeout
	dice = view.get("_dice")
	_check(summary.text.ends_with(tr("절대실패")) and dice[0].state == "absolute_failure" and total.text == "1",
		"절대실패는 절대실패 그림과 굴린 눈만 보인다: " + summary.text + " / " + total.text)
	await create_timer(CombatDiceRollView.HOLD_TIME + 0.1).timeout
	_check(summary.text.ends_with(tr("절대실패")), "뒤 굴림은 절대면의 일반 표시 시간이 지나도 시작하지 않는다: " + summary.text)
	await create_timer(CombatDiceRollView.ABSOLUTE_HIT_HOLD_TIME - CombatDiceRollView.HOLD_TIME).timeout
	_check(summary.text == "" and (view.get_node("Target") as Label).text == "AC 12" and view.modulate.a == 1.0,
		"뒤 굴림은 늘어난 표시 시간이 끝난 뒤 페이드를 기다리지 않고 굴린다: " + summary.text)
	await create_timer(CombatDiceRollView.TUMBLE_TIME).timeout

	# 절대면 다음 일반 굴림은 그림 상태·글자 크기를 이어받지 않는다.
	dice = view.get("_dice")
	_check(dice[0].state == "success" and summary.get_theme_font_size("font_size") == CombatDiceRollView.WORD_FONT_SIZE
		and summary.text.ends_with(tr("간신히 성공") + "  ±0"),
		"절대면 다음 일반 굴림은 그림 상태와 글자 크기를 이어받지 않는다: " + summary.text)
	await create_timer(CombatDiceRollView.HOLD_TIME + 0.1).timeout

	_test_grades()
	await _test_overhead(battle, view, ally, play)
	await _test_animation(view, ally, play, finished)
	await _test_overlapping_rolls(actions, view, ally, play, finished)

	_check(actions.dice.state == dice_state, "화면 연출은 게임의 주사위 순서와 저장 상태를 바꾸지 않는다")
	current_scene.queue_free()
	await process_frame


## 머리 위 표시: 유닛과 카메라를 따라가고, 유닛이 화면 밖이면 정해진 자리에 이름과 함께 보이며, 돌아오면 머리 위로 간다.
func _test_overhead(battle: Node2D, view: CombatDiceRollView, ally: CombatUnit, play: Callable) -> void:
	var camera: CombatCamera = battle.get("camera") as CombatCamera
	var summary: Label = view.get_node("Summary") as Label
	var screen: Rect2 = view.get_viewport_rect()
	play.call(CombatDiceRoll.hit(ally, 20, _result([9], 9, 12, true), 3, 12))
	await create_timer(CombatDiceRollView.TUMBLE_TIME + 0.1).timeout
	var head: Vector2 = view.get("_head")
	var panel: Vector2 = CombatDiceRollView.PANEL_SIZE
	_check(head.is_finite() and not view.get("_offscreen")
		and view.get("_origin") == CombatDiceRollView.panel_origin(head, panel, screen),
		"아군 굴림은 그 유닛의 머리 위 점에 패널을 둔다: " + str(head))
	camera.zoom_at(Vector2(100, 100), 1)
	await process_frame
	await process_frame
	var zoomed: Vector2 = view.get("_head")
	_check(zoomed != head and zoomed == ally.get_global_transform_with_canvas() * (
		Vector2(0.0, ally.floor_offset_y + ally.get_status_label_y() - CombatDiceRollView.HEAD_RISE)),
		"카메라를 확대하면 패널이 다시 유닛 머리 위로 따라간다: %s → %s" % [head, zoomed])
	camera.reset()
	await process_frame
	var home: Vector2 = ally.position
	ally.position = home + Vector2(5000.0, 0.0)
	await process_frame
	var spot: Vector2 = view.get("_origin")
	_check(view.get("_offscreen") == true
		and spot == CombatDiceRollView.panel_origin(Vector2.INF, panel, screen)
		and summary.text.begins_with(ally.get_display_name() + " · "),
		"유닛이 화면 밖이면 정해진 자리에 유닛 이름과 함께 보인다: %s %s" % [spot, summary.text])
	ally.position = home
	await process_frame
	_check(view.get("_offscreen") == false and not summary.text.begins_with(ally.get_display_name() + " · ")
		and view.get("_origin") != spot, "카메라나 유닛이 돌아와 화면 안이 되면 다시 머리 위로 간다")
	await create_timer(CombatDiceRollView.HOLD_TIME + 0.1).timeout


## 굴림·결과·사라짐 애니메이션(#626): 프레임이 넘어가고, 효과가 결과 표시 안에 끝나며, 떠오름은 정수이고,
## 4배속에서 같은 굴림이 약 1/4 시간에 끝난다.
func _test_animation(view: CombatDiceRollView, ally: CombatUnit, play: Callable, finished: Array[bool]) -> void:
	var screen: Rect2 = view.get_viewport_rect()
	var frames: Dictionary[int, bool] = {}
	play.call(CombatDiceRoll.hit(ally, 20, _result([3], 3, 6, false), 3, 12))
	var started: int = Time.get_ticks_msec()
	while Time.get_ticks_msec() - started < int(CombatDiceRollView.TUMBLE_TIME * 1000.0) - 30:
		frames[view.get("_frame") as int] = true
		await process_frame
	_check(frames.size() > 1, "굴리는 동안 굴림 프레임이 넘어간다: " + str(frames.keys()))
	# 굴림이 멈추고 효과가 끝난 뒤, 결과 표시 시간이 끝나기 전.
	await create_timer(0.38).timeout
	var head: Vector2 = view.get("_head")
	_check(view.get("_settled_elapsed") as float >= CombatDiceRollView.EFFECT_TIME
		and view.get("_origin") == CombatDiceRollView.panel_origin(head, CombatDiceRollView.PANEL_SIZE, screen)
		and view.get("_lift") == 0 and view.modulate.a == 1.0,
		"효과가 끝나도 패널은 머리 위 자리에 있고 떠오르지 않는다")
	var lifts: Dictionary[int, bool] = {}
	for _frame: int in range(240):
		if finished[0]:
			break
		await process_frame
	started = Time.get_ticks_msec()
	while view.visible and Time.get_ticks_msec() - started < 600:
		lifts[view.get("_lift") as int] = true
		await process_frame
	var all_in_range: bool = true
	for lift: int in lifts:
		all_in_range = all_in_range and lift >= 0 and lift <= CombatDiceRollView.LIFT_MAX
	_check(all_in_range and lifts.keys().max() == CombatDiceRollView.LIFT_MAX and not view.visible and view.get("_lift") == CombatDiceRollView.LIFT_MAX,
		"사라지는 동안 0~2 논리px 정수로 떠오르고 숨긴다: " + str(lifts.keys()))
	play.call(CombatDiceRoll.hit(ally, 20, _result([9], 9, 12, true), 3, 12))
	await create_timer(CombatDiceRollView.TUMBLE_TIME + 0.1).timeout
	await create_timer(CombatDiceRollView.HOLD_TIME + 0.1).timeout
	# 페이드 중에 새 굴림이 오면 떠오름도 0으로 돌아온다.
	play.call(CombatDiceRoll.hit(ally, 20, _result([9], 9, 12, true), 3, 12))
	await process_frame
	_check(view.get("_lift") == 0 and view.modulate.a == 1.0, "페이드를 끊는 새 굴림은 떠오름도 0으로 돌린다")
	await create_timer(CombatDiceRollView.TUMBLE_TIME + CombatDiceRollView.HOLD_TIME + CombatDiceRollView.FADE_TIME + 0.2).timeout
	# 4배속: 같은 굴림이 게임 시간으로 같은 길이이므로 실제 시간은 약 1/4이다.
	Engine.time_scale = 4.0
	var fast_frames: Dictionary[int, bool] = {}
	finished[0] = false
	play.call(CombatDiceRoll.hit(ally, 20, _result([9], 9, 12, true), 3, 12))
	started = Time.get_ticks_msec()
	while not finished[0] and Time.get_ticks_msec() - started < 3000:
		fast_frames[view.get("_frame") as int] = true
		await process_frame
	var real_ms: int = Time.get_ticks_msec() - started
	Engine.time_scale = 1.0
	_check(finished[0] and real_ms < 500 and fast_frames.size() > 1,
		"4배속에서 한 굴림이 약 1/4 시간에 끝나고 프레임도 넘어간다: %d ms, 프레임 %s" % [real_ms, str(fast_frames.keys())])
	await create_timer(CombatDiceRollView.FADE_TIME + 0.1).timeout


## 판정 단어의 등급은 규칙의 성공/실패 방향을 바꾸지 않고 여유로만 세분한다.
func _test_grades() -> void:
	var cases: Array = [
		# [총합, 성공, 절대면, 기대 등급, 이름]
		[17, true, CombatChecks.Face.NORMAL, CombatDiceRollView.Grade.BIG_SUCCESS, "여유 +5"],
		[16, true, CombatChecks.Face.NORMAL, CombatDiceRollView.Grade.SUCCESS, "여유 +4"],
		[14, true, CombatChecks.Face.NORMAL, CombatDiceRollView.Grade.SUCCESS, "여유 +2"],
		[13, true, CombatChecks.Face.NORMAL, CombatDiceRollView.Grade.NARROW_SUCCESS, "여유 +1"],
		[12, true, CombatChecks.Face.NORMAL, CombatDiceRollView.Grade.NARROW_SUCCESS, "여유 0"],
		[11, false, CombatChecks.Face.NORMAL, CombatDiceRollView.Grade.NARROW_FAILURE, "여유 -1"],
		[10, false, CombatChecks.Face.NORMAL, CombatDiceRollView.Grade.FAILURE, "여유 -2"],
		[8, false, CombatChecks.Face.NORMAL, CombatDiceRollView.Grade.FAILURE, "여유 -4"],
		[7, false, CombatChecks.Face.NORMAL, CombatDiceRollView.Grade.BIG_FAILURE, "여유 -5"],
		[3, true, CombatChecks.Face.ABSOLUTE_SUCCESS, CombatDiceRollView.Grade.ABSOLUTE_SUCCESS, "절대성공은 여유와 무관"],
		[40, false, CombatChecks.Face.ABSOLUTE_FAILURE, CombatDiceRollView.Grade.ABSOLUTE_FAILURE, "절대실패는 여유와 무관"],
	]
	for entry: Array in cases:
		var result: CombatChecks.RollResult = _result([entry[0] - 3], entry[0] - 3, entry[0], entry[1], entry[2])
		_check(CombatDiceRollView.grade(result, 12) == entry[3], "등급: " + str(entry[4]))
	var absolute_result: CombatChecks.RollResult = _result([20], 20, 23, true, CombatChecks.Face.ABSOLUTE_SUCCESS)
	var normal_result: CombatChecks.RollResult = _result([9], 9, 12, true)
	var hit_absolute: CombatDiceRoll = CombatDiceRoll.hit(null, 20, absolute_result, 3, 30)
	var save_absolute: CombatDiceRoll = CombatDiceRoll.save(null, 20, absolute_result, 3, tr("DC"), 10)
	_check(CombatDiceRollView.hold_time(hit_absolute) == CombatDiceRollView.ABSOLUTE_HIT_HOLD_TIME
		and CombatDiceRollView.hold_time(CombatDiceRoll.hit(null, 20, normal_result, 3, 12)) == CombatDiceRollView.HOLD_TIME
		and CombatDiceRollView.hold_time(save_absolute) == CombatDiceRollView.HOLD_TIME
		and is_equal_approx(CombatDiceRollView.HOLD_TIME, 0.8)
		and is_equal_approx(CombatDiceRollView.ABSOLUTE_HIT_HOLD_TIME, 1.1)
		and CombatDiceRollView.ABSOLUTE_HIT_HOLD_TIME > CombatDiceRollView.HOLD_TIME,
		"표시 시간은 일반 0.8초·명중 절대면 1.1초이며 명중굴림의 절대면만 늘어난다(#727)")
	var absolute_failure: CombatChecks.RollResult = _result([1], 1, 4, false, CombatChecks.Face.ABSOLUTE_FAILURE)
	_check(CombatDiceRollView.ducks_music(hit_absolute)
		and CombatDiceRollView.ducks_music(CombatDiceRoll.hit(null, 20, absolute_failure, 3, 2))
		and not CombatDiceRollView.ducks_music(CombatDiceRoll.hit(null, 20, normal_result, 3, 12))
		and not CombatDiceRollView.ducks_music(save_absolute),
		"배경음은 명중굴림의 절대성공·절대실패에서만 낮춘다")


## 기다리지 않는 독 제거 둘이 연달아 오고 기다리는 명중굴림이 뒤따라도, 먼저 온 굴림부터 결과를 끝까지 보인다.
## 기다리지 않는 쪽은 바로 돌아오고, 기다리는 쪽은 앞 굴림이 닫힌 뒤 자기 연출까지 마치고 돌아온다.
func _test_overlapping_rolls(actions: CombatActions, view: CombatDiceRollView, ally: CombatUnit,
		play: Callable, finished: Array[bool]) -> void:
	var summary: Label = view.get_node("Summary") as Label
	var target: Label = view.get_node("Target") as Label
	for player_name: String in ["RollSound", "SuccessSound", "FailureSound"]:
		_check((view.get_node(player_name) as AudioStreamPlayer).max_polyphony > 1,
			"%s는 겹쳐 재생해 앞 소리를 끊지 않는다" % player_name)
		_check((view.get_node(player_name) as AudioStreamPlayer).bus == GameSettings.BUS_SFX,
			"%s는 SFX 버스로 나간다" % player_name)
	var roll_stream: AudioStreamRandomizer = (view.get_node("RollSound") as AudioStreamPlayer).stream as AudioStreamRandomizer
	_check(roll_stream != null and roll_stream.streams_count == 3 and is_equal_approx(roll_stream.random_pitch, 1.06)
		and roll_stream.playback_mode == AudioStreamRandomizer.PLAYBACK_RANDOM_NO_REPEATS,
		"굴림 소리는 갈래 3개·높낮이 1.06·반복 없이 고름")
	for player_name: String in ["SuccessSound", "FailureSound"]:
		_check((view.get_node(player_name) as AudioStreamPlayer).stream is AudioStreamOggVorbis,
			"%s는 신호음이라 OGG 그대로" % player_name)
	var limits: Dictionary = {"RollSound": CombatDiceRollView.TUMBLE_TIME, "SuccessSound": CombatDiceRollView.HOLD_TIME,
		"FailureSound": CombatDiceRollView.HOLD_TIME}
	for player_name: String in limits:
		var length: float = SoundVariants.longest((view.get_node(player_name) as AudioStreamPlayer).stream)
		_check(length > 0.0 and length <= float(limits[player_name]),
			"%s는 비어 있지 않고 표시 시간(%.2f초) 안에 끝난다: %.3f초" % [player_name, limits[player_name], length])
	actions.roll_animation.call(CombatDiceRoll.save(ally, 4, _result([4], 4, 4, true), 0, tr("DC"), 3))
	actions.roll_animation.call(CombatDiceRoll.save(ally, 4, _result([1], 1, 1, false), 0, tr("DC"), 3))
	play.call(CombatDiceRoll.hit(ally, 20, _result([9], 9, 12, true), 3, 12))
	await create_timer(CombatDiceRollView.TUMBLE_TIME + 0.1).timeout
	_check(summary.text.ends_with(tr("간신히 성공") + "  +1") and summary.get_theme_color("font_color") == CombatDiceRollView.SUCCESS_COLOR
		and (view.get_node("SuccessSound") as AudioStreamPlayer).playing,
		"뒤 굴림이 와도 첫 굴림의 결과 숫자·색·결과음이 나온다: " + summary.text)
	await create_timer(CombatDiceRollView.HOLD_TIME).timeout
	_check(view.visible and view.modulate.a == 1.0 and target.text == "DC 3" and summary.text == "",
		"첫 결과가 닫힌 뒤 페이드를 기다리지 않고 두 번째 굴림을 굴린다: " + summary.text)
	await create_timer(CombatDiceRollView.TUMBLE_TIME).timeout
	_check(summary.text.ends_with(tr("실패") + "  -2") and summary.get_theme_color("font_color") == CombatDiceRollView.FAILURE_COLOR
		and (view.get_node("FailureSound") as AudioStreamPlayer).playing,
		"두 번째 굴림도 결과 숫자·색·결과음이 나온다: " + summary.text)
	await create_timer(CombatDiceRollView.HOLD_TIME).timeout
	_check(view.visible and target.text == "AC 12" and not finished[0],
		"기다리는 명중굴림은 앞 굴림들이 닫힌 뒤 차례로 굴리고 아직 돌아오지 않는다: " + summary.text)
	# 뒤따르는 굴림이 없어 여유를 더 둔다. 뷰의 마지막 타이머가 이 타이머보다 늦게 만들어진다.
	await create_timer(CombatDiceRollView.TUMBLE_TIME + CombatDiceRollView.HOLD_TIME + 0.1).timeout
	_check(finished[0] and view.modulate.a < 1.0, "명중굴림은 자기 연출까지 마친 뒤 페이드를 기다리지 않고 돌아온다")
	await create_timer(CombatDiceRollView.FADE_TIME).timeout
	_check(not view.visible and view.modulate.a == 0.0, "페이드아웃이 끝나면 주사위 뷰를 숨긴다")
