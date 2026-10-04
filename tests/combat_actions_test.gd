extends SceneTree
## 동작의 정상 흐름, 자원·횟수, 반응 중단과 실제 두 번 클릭 경로.

class Fixture extends RefCounted:
	var units: Array[CombatUnit] = []
	var turns: CombatTurns = CombatTurns.new()
	var actions: CombatActions = CombatActions.new()


var _checks: int = 0
var _failures: int = 0
var _created: Array[CombatUnit] = []
var _fixtures: Array[Fixture] = []


func _initialize() -> void:
	create_timer(30.0).timeout.connect(func() -> void:
		push_error("Combat actions: test timeout")
		quit(1)
	)
	_run.call_deferred()


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error(message)


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
	var dice: RandomNumberGenerator = RandomNumberGenerator.new()
	dice.seed = 33
	f.turns.start(f.units, dice)
	f.actions.initialize(f.units, f.turns)
	return f


func _dice_for(expected: Array[int], sides: Array[int]) -> RandomNumberGenerator:
	var dice: RandomNumberGenerator = RandomNumberGenerator.new()
	for seed_value: int in range(1000000):
		dice.seed = seed_value
		var matches: bool = true
		for index: int in range(expected.size()):
			var rolled: int = dice.randi_range(1, sides[index])
			if expected[index] != 0 and rolled != expected[index]:
				matches = false
				break
		if matches:
			dice.seed = seed_value
			return dice
	_check(false, "동작 주사위 fixture를 찾지 못함")
	return dice


func _run() -> void:
	await _test_movement()
	await _test_attacks()
	_test_self_actions()
	_test_shove()
	await _test_mark_and_stun()
	await _test_reactions()
	await _test_scene_input()
	await _test_scene_shock()
	for f: Fixture in _fixtures:
		for connection: Dictionary in f.actions.reaction_requested.get_connections():
			f.actions.reaction_requested.disconnect(connection["callable"] as Callable)
	_fixtures.clear()
	for unit: CombatUnit in _created:
		unit.free()
	print("Combat actions: %d checks, %d failures" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)


func _test_movement() -> void:
	var f: Fixture = _fixture()
	f.units[2].cell = Vector2i(9, 0)
	var actor: CombatUnit = f.units[0]
	_check(not f.actions.can_move(actor, actor.cell), "같은 칸 이동 거부")
	_check(not f.actions.can_move(actor, Vector2i(-1, 4)), "맵 밖 이동 거부")
	_check(not f.actions.can_move(actor, f.units[2].cell), "점유 칸 이동 거부")
	_check(f.actions.path_to(actor, Vector2i(4, 6)).size() == 2, "8방향 이동 경로와 비용")
	_check(await f.actions.move_to(actor, Vector2i(4, 6)), "첫 이동 실행")
	_check(actor.cell == Vector2i(4, 6) and actor.movement_left == 4, "이동2 소비와 위치 갱신")
	_check(await f.actions.move_to(actor, Vector2i(4, 7)), "이동을 나눠서 실행")
	_check(actor.movement_left == 3 and actor.action_left == 1 and actor.bonus_action_left == 1,
		"나눈 이동은 누적 비용만 쓰며 행동 자원은 유지")
	_check(not f.actions.can_move(actor, Vector2i(0, 0)), "남은 이동을 넘는 경로 거부")
	f.units[1].cell = Vector2i(2, 2)
	_check(f.actions.path_to(actor, Vector2i(2, 2)).is_empty(), "아군 점유 칸도 거부")
	actor.is_stunned = true
	_check(not f.actions.can_move(actor, Vector2i(4, 8)), "기절한 유닛 이동 거부")
	actor.is_stunned = false
	f.turns.select_unit(f.units[1])
	_check(not f.actions.can_move(actor, Vector2i(4, 8)), "현재 유닛이 아닌 이동 거부")


func _test_attacks() -> void:
	var f: Fixture = _fixture()
	var actor: CombatUnit = f.units[0]
	var target: CombatUnit = f.units[2]
	target.parry_left = 0
	f.actions.dice = _dice_for([1], [20])
	_check(await f.actions.attack(actor, target), "빗나간 공격도 실행 성공")
	_check(actor.action_left == 0 and target.hit_points == 12 and f.actions.last_damage == 0,
		"자연1 공격은 행동을 소비하고 피해 없음")
	_check(not await f.actions.attack(actor, target), "행동 없는 재공격 거부")
	actor.action_left = 1
	f.actions.dice = _dice_for([20], [20])
	_check(await f.actions.attack(actor, target), "치명타 공격")
	_check(f.actions.last_attack.critical and f.actions.last_damage_rolls.size() == 2,
		"치명타는 무기 주사위 두 개")
	var total: int = 3
	for rolled: int in f.actions.last_damage_rolls:
		total += rolled
	_check(f.actions.last_damage == total, "능력치3은 치명타에서도 한 번만 더함")
	_check(target.hit_points == maxi(0, 12 - total), "피해와 HP0 하한")
	var killed: Fixture = _fixture()
	killed.units[2].hit_points = 1
	killed.units[2].parry_left = 0
	killed.units[1].marked_target = killed.units[2]
	killed.actions.dice = _dice_for([11], [20])
	await killed.actions.attack(killed.units[0], killed.units[2])
	_check(killed.units[2].hit_points == 0 and killed.units[2] not in killed.turns.ordered_units,
		"HP0은 즉시 전투 불능과 턴 순서 제거")
	_check(killed.units[1].marked_target == null, "전투 불능 대상의 표식 제거")
	_check(not await killed.actions.attack(killed.units[0], killed.units[2]), "전투 불능 대상 재공격 거부")


func _test_self_actions() -> void:
	var f: Fixture = _fixture()
	var warrior: CombatUnit = f.units[0]
	_check(not f.actions.can_use(warrior, "second_wind"), "만HP 숨 고르기는 효과 없음")
	_check(not f.actions.can_use(warrior, "surge"), "행동이 남으면 몰아치기 불가")
	warrior.hit_points = 1
	f.actions.dice = _dice_for([10], [10])
	_check(f.actions.use_self(warrior, "second_wind"), "숨 고르기 사용")
	_check(warrior.hit_points == 12 and warrior.second_wind_left == 0 and warrior.bonus_action_left == 0,
		"1d10+1 회복과 횟수·보조 행동 소비")
	warrior.begin_turn()
	_check(warrior.second_wind_left == 0, "자기 턴은 전투당 횟수를 회복하지 않음")
	warrior.action_left = 0
	_check(f.actions.use_self(warrior, "surge"), "몰아치기 사용")
	_check(warrior.action_left == 1 and warrior.bonus_action_left == 0 and warrior.surge_left == 0,
		"몰아치기는 행동을 최대1로 채움")
	warrior.begin_turn()
	warrior.hit_points = 1
	f.actions.dice = _dice_for([4, 4], [4, 4])
	_check(f.actions.use_self(warrior, "potion"), "물약 사용")
	_check(warrior.hit_points == 11 and warrior.potion_left == 0, "2d4+2 회복과 유닛당 물약1개")
	warrior.begin_turn()
	_check(not f.actions.use_self(warrior, "potion"), "물약 횟수 회복 없음")
	f.turns.select_unit(f.units[1])
	var archer: CombatUnit = f.units[1]
	_check(f.actions.use_self(archer, "disengage"), "물러서며 쏘기 사용")
	_check(archer.disengaged and archer.disengage_left == 1 and archer.bonus_action_left == 0,
		"이번 턴 기회 공격 제외와 횟수 소비")
	archer.begin_turn()
	_check(not archer.disengaged and archer.disengage_left == 1, "다음 턴 면제만 해제")
	archer.is_stunned = true
	archer.hit_points = 1
	_check(not f.actions.use_self(archer, "potion"), "기절 중 보조 행동 거부")


func _test_shove() -> void:
	var f: Fixture = _fixture()
	var actor: CombatUnit = f.units[0]
	var target: CombatUnit = f.units[2]
	f.actions.dice = _dice_for([20, 1], [20, 20])
	_check(f.actions.shove(actor, target), "밀치기 실행")
	_check(target.cell == Vector2i(6, 4) and actor.bonus_action_left == 0, "대결 승리 시1칸 이동과 자원 소비")
	_check(target.reaction_left == 1, "강제 이동은 기회 공격 없음")
	actor.bonus_action_left = 1
	target.cell = Vector2i(5, 4)
	f.units[3].cell = Vector2i(6, 4)
	_check(not f.actions.shove(actor, target) and actor.bonus_action_left == 1, "막힌 밀림 칸은 선택·소비 거부")
	f.units[3].cell = Vector2i(7, 4)
	f.actions.dice = _dice_for([10, 10], [20, 20])
	f.actions.shove(actor, target)
	_check(target.cell == Vector2i(5, 4), "대결 동점은 방어 승")
	actor.bonus_action_left = 1
	target.is_stunned = true
	f.actions.shove(actor, target)
	_check(target.cell == Vector2i(6, 4), "기절 대상은 대결 자동 패배")
	actor.cell = Vector2i(8, 4)
	target.cell = Vector2i(9, 4)
	actor.bonus_action_left = 1
	_check(not f.actions.can_target(actor, target, "shove"), "맵 밖으로 밀어내기 거부")


func _test_mark_and_stun() -> void:
	var f: Fixture = _fixture()
	f.turns.select_unit(f.units[1])
	var actor: CombatUnit = f.units[1]
	var target: CombatUnit = f.units[3]
	_check(f.actions.mark(actor, target), "표식 부여")
	_check(actor.marked_target == target and actor.mark_left == 0 and actor.bonus_action_left == 0,
		"표식은 유닛별 대상·횟수·자원 기록")
	actor.bonus_action_left = 1
	_check(not f.actions.mark(actor, f.units[2]), "사용한 표식 대상 변경 거부")
	f.actions.dice = _dice_for([20], [20])
	await f.actions.attack(actor, target)
	_check(f.actions.last_damage_rolls.size() == 4, "표식 치명타는 무기와 표식 각각2개")
	var shock: Fixture = _fixture()
	_check(shock.actions.save_dc == 13, "제품 기본 내성 DC는13")
	shock.turns.select_unit(shock.units[1])
	shock.units[2].reaction_left = 0
	shock.actions.dice = _dice_for([11, 0, 1], [20, 6, 20])
	_check(await shock.actions.attack(shock.units[1], shock.units[2], true), "충격 화살 실행")
	_check(shock.units[1].shock_left == 0 and shock.units[1].action_left == 0, "충격 화살 횟수와 행동 소비")
	_check(shock.units[2].is_stunned and shock.units[2].hit_points > 0, "명중·피해 후 정신 내성 실패 기절")
	shock.turns.end_turn()
	shock.turns.end_turn()
	_check(shock.turns.current_unit == shock.units[3] and shock.turns.is_turn_finished(shock.units[2]),
		"기절한 다음 턴은 자동으로 건너뜀")
	_check(not shock.units[2].is_stunned, "건너뛴 턴 끝에서 기절 해제")
	for roll: int in [13, 14]:
		var boundary: Fixture = _fixture()
		boundary.turns.select_unit(boundary.units[1])
		boundary.units[2].reaction_left = 0
		boundary.actions.dice = _dice_for([11, 4, roll], [20, 6, 20])
		await boundary.actions.attack(boundary.units[1], boundary.units[2], true)
		_check(boundary.units[2].hit_points == 5, "내성 성공 여부와 관계없이 충격 화살 피해 적용")
		_check(boundary.units[2].is_stunned == (roll == 13),
			"정신-1의 DC13 경계: d20의13은 기절,14는 버팀")
	var waiting: Fixture = _fixture()
	waiting.units[1].is_stunned = true
	var start_dice: RandomNumberGenerator = RandomNumberGenerator.new()
	start_dice.seed = 33
	waiting.turns.start(waiting.units, start_dice)
	_check(waiting.turns.current_unit == waiting.units[0] and waiting.units[1].is_stunned,
		"두 번째 기절 유닛은 앞 유닛이 동작하는 동안 기절 유지")
	_check(not waiting.turns.select_unit(waiting.units[1]), "아직 건너뛰지 않은 기절 유닛 선택 거부")
	waiting.turns.remove_unit(waiting.units[3])
	_check(waiting.units[1].is_stunned, "다른 유닛 탈락의 묶음 재계산은 기절을 풀지 않음")
	waiting.turns.end_turn()
	_check(not waiting.units[1].is_stunned and waiting.turns.is_turn_finished(waiting.units[1]),
		"실제로 두 번째 유닛 순서를 건너뛴 끝에 기절 해제")
	var missed: Fixture = _fixture()
	missed.turns.select_unit(missed.units[1])
	var before_miss: int = missed.units[3].hit_points
	missed.actions.dice = _dice_for([1], [20])
	await missed.actions.attack(missed.units[1], missed.units[3], true)
	_check(missed.units[1].action_left == 0 and missed.units[1].shock_left == 0
		and missed.units[3].hit_points == before_miss and not missed.units[3].is_stunned,
		"빗나가도 충격 화살 행동·횟수 모두 소비, 피해·기절 없음")
	_check(not missed.actions.can_use(missed.units[1], "shock"), "빗나간 충격 화살 재사용 거부")
	missed.units[1].action_left = 1
	_check(not missed.actions.can_use(missed.units[1], "shock"), "행동만 회복해도 사용 횟수는 돌아오지 않음")
	missed.units[1].action_left = 1
	missed.units[1].shock_left = 1
	missed.actions.save_dc = 0
	_check(not missed.actions.can_use(missed.units[1], "shock"), "유효하지 않은 DC 효과 실행 거부")


func _enemy_archer(f: Fixture) -> void:
	f.units[0].cell = Vector2i(4, 4)
	f.units[1].cell = Vector2i(0, 0)
	f.units[2].cell = Vector2i(0, 9)
	f.units[3].cell = Vector2i(5, 4)
	f.turns.end_turn()
	f.turns.end_turn()
	f.turns.end_turn()


func _test_reactions() -> void:
	var f: Fixture = _fixture()
	_enemy_archer(f)
	var asked: Array[String] = []
	f.actions.reaction_requested.connect(func(kind: String, _prompt: String) -> void:
		asked.append(kind)
		_check(f.actions.busy and not f.actions.can_move(f.units[3], Vector2i(6, 4)), "반응 대기 중 새 동작 잠금")
		f.actions.resolve_reaction(true)
	)
	f.actions.dice = _dice_for([1], [20])
	await f.actions.move_to(f.units[3], Vector2i(6, 4))
	_check(asked == ["opportunity"] and f.units[0].reaction_left == 0, "아군 기회 공격은 물어보고 반응 소비")
	_check(f.units[3].cell == Vector2i(6, 4) and f.units[3].movement_left == 5, "빗나가면 이동 계속")
	_check(not f.actions.busy and f.actions.pending_reactor == null, "반응 종료 후 대기 해제")
	f.actions.dice = _dice_for([11], [20])
	await f.actions.attack(f.units[3], f.units[0])
	_check(asked.size() == 1 and f.units[0].parry_left == 2 and f.units[0].hit_points < 12,
		"기회 공격에 쓴 반응으로 흘려내기를 다시 쓸 수 없음")
	var skip: Fixture = _fixture()
	_enemy_archer(skip)
	skip.actions.reaction_requested.connect(func(_kind: String, _prompt: String) -> void: skip.actions.resolve_reaction(false))
	await skip.actions.move_to(skip.units[3], Vector2i(6, 4))
	_check(skip.units[0].reaction_left == 1 and skip.units[3].cell == Vector2i(6, 4), "넘기기는 반응을 쓰지 않음")
	var ranged: Fixture = _fixture()
	_enemy_archer(ranged)
	ranged.units[0].kind = CombatUnit.Kind.ARCHER
	await ranged.actions.move_to(ranged.units[3], Vector2i(6, 4))
	_check(ranged.units[0].reaction_left == 1, "궁수는 기회 공격 불가")
	var retreat: Fixture = _fixture()
	_enemy_archer(retreat)
	retreat.actions.use_self(retreat.units[3], "disengage")
	await retreat.actions.move_to(retreat.units[3], Vector2i(6, 4))
	_check(retreat.units[0].reaction_left == 1, "물러서며 쏘기 이동은 반응 안 함")
	var dead: Fixture = _fixture()
	_enemy_archer(dead)
	dead.units[3].hit_points = 1
	dead.actions.reaction_requested.connect(func(_kind: String, _prompt: String) -> void: dead.actions.resolve_reaction(true))
	dead.actions.dice = _dice_for([20], [20])
	await dead.actions.move_to(dead.units[3], Vector2i(6, 4))
	_check(dead.units[3].hit_points == 0 and dead.units[3].cell == Vector2i(5, 4)
		and dead.units[3].movement_left == 6, "기회 공격으로 탈락하면 벗어나기 전 칸에서 이동 중단")
	var parry: Fixture = _fixture()
	parry.units[0].cell = Vector2i(4, 4)
	parry.units[2].cell = Vector2i(5, 4)
	parry.turns.end_turn()
	parry.turns.end_turn()
	parry.actions.reaction_requested.connect(func(kind: String, prompt: String) -> void:
		_check(kind == "parry" and parry.actions.last_damage_rolls.is_empty(), "피해 굴림 전에 흘려내기 확인")
		_check("45.0%" in prompt, "DC13 흘려내기 확인은 성공률45%")
		parry.actions.resolve_reaction(true)
	)
	parry.actions.dice = _dice_for([20, 12], [20, 20])
	await parry.actions.attack(parry.units[2], parry.units[0])
	_check(parry.units[0].hit_points == 12 and parry.actions.last_damage == 0, "흘려내기 성공은 치명타도 무효")
	_check(parry.units[0].reaction_left == 0 and parry.units[0].parry_left == 1, "흘려내기 반응과 전투당 횟수 소비")
	_check(parry.units[2].action_left == 0, "흘려내기 성공해도 공격자 행동 소비")
	parry.units[2].action_left = 1
	parry.units[0].reaction_left = 1
	parry.actions.dice = _dice_for([20, 11], [20, 20])
	await parry.actions.attack(parry.units[2], parry.units[0])
	_check(parry.actions.last_damage > 0 and parry.actions.last_damage_rolls.size() == 2,
		"민첩+1의 d20의11은 DC13 미달로 치명타 피해 적용")
	_check(parry.units[0].reaction_left == 0 and parry.units[0].parry_left == 0,
		"흘려내기 내성 실패도 반응과 횟수 소비")
	var automatic: Fixture = _fixture()
	automatic.actions.dice = _dice_for([11, 12], [20, 20])
	await automatic.actions.attack(automatic.units[0], automatic.units[2])
	_check(automatic.units[2].parry_left == 1 and automatic.units[2].reaction_left == 0
		and automatic.units[2].hit_points == 12, "적 흘려내기는 자동 반응")
	var parried_shock: Fixture = _fixture()
	_enemy_archer(parried_shock)
	parried_shock.actions.reaction_requested.connect(func(_kind: String, _prompt: String) -> void:
		parried_shock.actions.resolve_reaction(true)
	)
	parried_shock.actions.dice = _dice_for([11, 12, 12], [20, 20, 20])
	await parried_shock.actions.attack(parried_shock.units[3], parried_shock.units[0], true)
	_check(parried_shock.units[0].hit_points == 12 and not parried_shock.units[0].is_stunned
		and parried_shock.units[3].shock_left == 0, "흘려낸 충격 화살은 피해와 기절도 없음")


func _test_scene_input() -> void:
	var scene: PackedScene = load("res://scenes/combat/battle.tscn") as PackedScene
	var battle: Node2D = scene.instantiate() as Node2D
	root.add_child(battle)
	battle.set_process(false)
	await process_frame
	var turns: CombatTurns = battle.get("turns") as CombatTurns
	var actions: CombatActions = battle.get("actions") as CombatActions
	var units: Array[CombatUnit] = battle.get("units")
	var map: TileMapLayer = battle.get_node("Map") as TileMapLayer
	var hud: CombatTurnHud = battle.get_node("UI/TurnHud") as CombatTurnHud
	var dice: RandomNumberGenerator = RandomNumberGenerator.new()
	dice.seed = 33
	turns.start(units, dice)
	var destination: Vector2i = Vector2i(4, 7)
	var screen: Vector2 = map.get_global_transform_with_canvas() * map.map_to_local(destination)
	await _click(screen)
	_check(units[0].cell == Vector2i(4, 9) and not (battle.get("preview_path") as Array).is_empty(), "이동 첫 클릭은 미리보기")
	await _click(screen)
	_check(units[0].cell == destination and units[0].movement_left == 4, "이동 두 번째 클릭 실행")
	units[2].cell = Vector2i(5, 7)
	units[2].parry_left = 0
	battle.call("_update_turn_ui")
	actions.dice = _dice_for([1], [20])
	var point: Vector2 = units[2].get_global_transform_with_canvas() * Vector2(0, -10)
	await _click(point)
	_check(units[0].action_left == 1 and battle.get("preview_target") == units[2], "공격 첫 클릭은 피해·자원 소비 없음")
	await _click(point)
	_check(units[0].action_left == 0 and units[2].hit_points == 12, "공격 두 번째 클릭과 빗나감 처리")
	hud.action_selected.emit("surge")
	_check(units[0].surge_left == 1, "자기 대상 동작 첫 클릭은 선택만")
	hud.action_selected.emit("surge")
	_check(units[0].surge_left == 0 and units[0].action_left == 1, "자기 대상 동작 두 번째 클릭 실행")
	_check("몰아치기" in hud.message_label.text, "실행 결과 화면 피드백")
	actions.dice = _dice_for([11], [20])
	await _click(point)
	_check(units[0].action_left == 1 and units[2].hit_points == 12
		and battle.get("preview_target") == units[2], "몰아치기 뒤 추가 공격 첫 클릭은 미리보기")
	await _click(point)
	_check(turns.current_unit == units[0] and units[0].action_left == 0
		and units[0].bonus_action_left == 0 and units[2].hit_points < 12,
		"아군은 같은 턴에 몰아치기 뒤 두 번째 클릭으로 추가 공격")
	turns.end_turn()
	turns.end_turn()
	_check(actions.save_dc == 13, "실제 장면도 DC13을 연결")
	actions.dice = _dice_for([20, 12], [20, 20])
	actions.reaction_requested.connect(func(kind: String, _prompt: String) -> void:
		_check(kind == "parry" and hud.reaction_dialog.visible and hud.end_button.disabled,
			"실제 확인 창이 뜨고 턴 종료가 잠김")
		hud.reaction_dialog.get_ok_button().pressed.emit()
	)
	await actions.attack(units[2], units[0])
	_check(units[0].parry_left == 1 and units[0].hit_points == 12,
		"실제 확인 창의 확인 버튼이 반응 모델에 연결됨")
	_check(not hud.reaction_dialog.visible and not actions.busy, "확인 후 창과 입력 잠금 해제")
	battle.queue_free()
	await process_frame
	# 몸통에 가린 빈 칸과 겹친 유닛은 실제 입력으로 별도 확인한다.
	var overlap: Node2D = scene.instantiate() as Node2D
	root.add_child(overlap)
	overlap.set_process(false)
	await process_frame
	var overlap_units: Array[CombatUnit] = overlap.get("units")
	var overlap_turns: CombatTurns = overlap.get("turns") as CombatTurns
	var overlap_hud: CombatTurnHud = overlap.get_node("UI/TurnHud") as CombatTurnHud
	var overlap_map: TileMapLayer = overlap.get_node("Map") as TileMapLayer
	dice.seed = 33
	overlap_turns.start(overlap_units, dice)
	overlap_hud.action_selected.emit("move")
	var hidden_cell: Vector2i = overlap_units[0].cell - Vector2i.ONE
	var hidden_screen: Vector2 = overlap_map.get_global_transform_with_canvas() * overlap_map.map_to_local(hidden_cell)
	await _click(hidden_screen)
	_check(overlap.get("preview_cell") == hidden_cell, "이동 모드에서 몸통 뒤 빈 칸 중앙 선택")
	await _click(hidden_screen)
	_check(overlap_units[0].cell == hidden_cell, "몸통에 가린 빈 칸 이동 실행")
	overlap_hud.action_selected.emit("attack")
	overlap_units[2].cell = Vector2i(5, 4)
	overlap_units[3].cell = Vector2i(6, 5)
	overlap.call("_update_turn_ui")
	var overlap_point: Vector2 = overlap_units[2].get_global_transform_with_canvas() * Vector2(0, -1)
	await _click(overlap_point)
	_check(overlap.get("preview_target") == overlap_units[3], "겹친 몸통은 y-sort 앞쪽 유닛 선택")
	overlap.queue_free()
	await process_frame


func _test_scene_shock() -> void:
	var scene: PackedScene = load("res://scenes/combat/battle.tscn") as PackedScene
	var battle: Node2D = scene.instantiate() as Node2D
	root.add_child(battle)
	battle.set_process(false)
	await process_frame
	var units: Array[CombatUnit] = battle.get("units")
	var turns: CombatTurns = battle.get("turns") as CombatTurns
	var actions: CombatActions = battle.get("actions") as CombatActions
	var hud: CombatTurnHud = battle.get_node("UI/TurnHud") as CombatTurnHud
	var dice: RandomNumberGenerator = RandomNumberGenerator.new()
	dice.seed = 33
	turns.start(units, dice)
	units[3].cell = Vector2i(7, 9)
	turns.select_unit(units[1])
	var buttons: Dictionary = hud.get("_actions")
	var shock_button: Button = buttons["shock"] as Button
	_check(shock_button.visible and not shock_button.disabled, "실제 장면의 충격 화살 버튼 활성화")
	shock_button.pressed.emit()
	var before_miss: int = units[3].hit_points
	actions.dice = _dice_for([1], [20])
	var point: Vector2 = units[3].get_global_transform_with_canvas() * Vector2(0, -10)
	await _click(point)
	_check(units[1].action_left == 1 and units[1].shock_left == 1, "충격 화살 미리보기는 행동·횟수 유지")
	await _click(point)
	_check(units[1].action_left == 0 and units[1].shock_left == 0
		and units[3].hit_points == before_miss and not units[3].is_stunned,
		"실제 두 번째 클릭의 충격 화살 빗나감은 행동·횟수만 소비")
	var badges: Dictionary = hud.get("_badges")
	_check(shock_button.disabled and (badges["shock"] as Label).text == "0",
		"실행 후 충격 화살 비활성화와 모서리 횟수 배지 갱신")
	battle.queue_free()
	await process_frame


func _click(point: Vector2) -> void:
	var event: InputEventMouseButton = InputEventMouseButton.new()
	event.position = root.get_final_transform() * point
	event.global_position = event.position
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	Input.parse_input_event(event)
	await process_frame
	event.pressed = false
	Input.parse_input_event(event)
	await process_frame
