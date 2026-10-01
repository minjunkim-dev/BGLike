extends SceneTree
## 전투 자동 확인. 판정 규칙을 검사하고, 아군까지 AI로 조작해 전투가 끝까지 도는지 본다.
## 실행: godot --headless --path . -s res://scenes/combat/combat_check.gd

const BATTLES := 20

var failed := false


func _initialize() -> void:
	_expect(not CombatRules.is_hit(1, 100, 10), "1은 자동 실패")
	_expect(CombatRules.is_hit(20, -100, 30), "20은 자동 명중")
	_expect(CombatRules.is_hit(11, 5, 16), "합계가 AC와 같으면 명중")
	_expect(not CombatRules.is_hit(10, 5, 16), "합계가 AC보다 작으면 빗나감")
	_expect(CombatRules.hit_chance(5, 16) == 0.5, "+5 vs AC 16 = 50%")
	_expect(CombatRules.hit_chance(5, 14) == 0.6, "+5 vs AC 14 = 60%")
	_expect(CombatRules.hit_chance(100, 10) == 0.95, "최대 95%")
	_expect(CombatRules.hit_chance(-100, 30) == 0.05, "최소 5%")

	Engine.time_scale = 50.0
	await _check_player_taps()

	var wins := 0
	for i in BATTLES:
		var battle: Node = load("res://scenes/combat/battle.tscn").instantiate()
		battle.fixed_seed = i + 1
		battle.allies_use_ai = true
		root.add_child(battle)
		var frames := 0
		while not battle.battle_over and frames < 20000:
			await process_frame
			frames += 1
		_expect(battle.battle_over, "시드 %d 전투가 끝나야 함" % (i + 1))
		if battle.result_label.text == "승리!":
			wins += 1
		battle.free()
	print("AI 대 AI %d판: 아군 승리 %d" % [BATTLES, wins])
	print("실패" if failed else "통과")
	quit(1 if failed else 0)


## 한 번 누르면 미리보기, 같은 칸을 한 번 더 누르면 확정되는지 본다.
func _check_player_taps() -> void:
	var battle: Node = load("res://scenes/combat/battle.tscn").instantiate()
	battle.fixed_seed = 1
	root.add_child(battle)
	while not battle._is_player_turn():
		await process_frame
	var mover: Unit = battle.current
	var cell: Vector2i = battle.reachable.keys()[0]
	battle._on_tap(cell)
	_expect(mover.cell != cell and battle.pending_cell == cell, "첫 탭은 미리보기만")
	await battle._on_tap(cell)
	_expect(mover.cell == cell and battle.moves_left < 6, "두 번째 탭에 이동")

	# 궁수는 사거리 12칸이라 10×10 맵 어디든 닿는다. 궁수 턴까지 턴을 넘긴다.
	var frames := 0
	while not (battle._is_player_turn() and battle.current.attack_range > 1) and frames < 20000:
		if battle._is_player_turn() and not battle.busy:
			battle._on_end_turn_pressed()
		await process_frame
		frames += 1
	_expect(battle._is_player_turn() and battle.current.attack_range > 1, "아군 궁수 턴이 와야 함")
	var enemy: Unit = battle._opponents(battle.current)[0]
	battle._on_tap(enemy.cell)
	_expect(not battle.action_used and battle.pending_cell == enemy.cell, "첫 탭은 명중률만 표시")
	await battle._on_tap(enemy.cell)
	_expect(battle.action_used, "두 번째 탭에 공격")
	battle.free()


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failed = true
		push_error("실패: " + message)
