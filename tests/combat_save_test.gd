extends SceneTree
## 전투 자동 저장과 이어하기 (#281). 9개 스테이지를 같은 규칙의 입력으로 진행하며 저장한 모든 시점을
## 새 전투에 복원해 상태가 같은지, 이어서 같은 입력을 주면 같은 굴림과 상태가 이어지는지 검사한다.

## 스테이지마다 진행할 입력 단계 수. 보스 스테이지도 여러 라운드를 지난다.
const MAX_STEPS: int = 140
const STAGE_COUNT: int = 9
## 저장 한 번(상태 수집과 파일 쓰기)의 평균 허용 시간. 60fps 한 프레임이다.
const FRAME_USEC: int = 16_667
## 실제 연출을 켠 채로 빠르게 진행한다. 다시 실행이 연출만 바꾸는 상태(방향)도 같게 만드는지 본다.
const TIME_SCALE: float = 100.0
## 연출을 기다리는 프레임의 상한. 멈춘 전투가 검사를 끝없이 붙잡지 않게 한다.
const MAX_FRAMES: int = 20_000

## 여러 worktree가 같은 user://를 쓰므로 실행마다 폴더를 나눈다.
var directory: String = "user://tests/combat_save/%d" % OS.get_process_id()
var checks: int = 0
var failures: int = 0
var save_usec: Array[int] = []
var save_bytes: Array[int] = []
## 아군이 반응에 답한 뒤 적 턴 중간에 저장한 스테이지 수.
var reaction_stages: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(directory)
	GameSave.path = directory + "/save.bin"
	await _test_autosave_switch()
	GameSave.autosave = true
	await _test_format_two_state()
	for stage_index: int in range(STAGE_COUNT):
		await _test_stage(stage_index)
	_check(reaction_stages >= 3, "여러 스테이지에서 아군 반응 답을 담은 적 턴 중간 저장을 복원함: %d" % reaction_stages)
	await _test_rejects_bad_saves()
	GameSave.autosave = false
	Engine.time_scale = 1.0
	GameSave.delete()
	DirAccess.remove_absolute(directory)
	save_usec.sort()
	save_bytes.sort()
	if not save_usec.is_empty():
		var total: int = 0
		for usec: int in save_usec:
			total += usec
		print("Combat save cost: %d saves, avg %d us, median %d us, max %d us, size %d~%d bytes" % [
			save_usec.size(), total / save_usec.size(), save_usec[save_usec.size() / 2], save_usec.back(),
			save_bytes.front(), save_bytes.back()])
		_check(total / save_usec.size() < FRAME_USEC, "저장 한 번의 평균 비용이 한 프레임보다 짧음")
	print("Combat save: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)


## 게임 장면 하나. 아군에게 장비·가방·물약을 주고 stage_index 스테이지를 새로 시작한다. -1이면 1-1 그대로 둔다.
func _battle(stage_index: int) -> Node2D:
	var main: Node = (load("res://scenes/game.tscn") as PackedScene).instantiate()
	root.add_child(main)
	var battle: Node2D = main.get_node("Battle") as Node2D
	battle.set_process(false)
	if stage_index < 0:
		return battle
	var loot: CombatLoot = battle.get("loot")
	var party: Array[CombatUnit] = battle.get("party")
	var items: Array = loot.data["items"]
	var weapon: Dictionary = items[0].duplicate(true)
	weapon["stats"] = {"attack_bonus": 1, "damage_bonus": 2}
	var armor: Dictionary = items[1].duplicate(true)
	armor["stats"] = {"defense_bonus": 1, "max_hit_points": 3}
	loot.receive(party[0], weapon)
	loot.receive(party[1], armor)
	loot.bag.append(items[2].duplicate(true))
	party[0].potion_left = 1
	(battle.get("progress") as CombatActProgress).stage_index = stage_index
	battle.call("_start_stage", true)
	# 같은 시드로 이니셔티브와 굴림을 정해 검사가 늘 같은 진행을 거친다.
	var dice: CombatDice = CombatDice.new()
	dice.seed = 281 + stage_index
	(battle.get("turns") as CombatTurns).start(battle.get("units"), dice)
	(battle.get("actions") as CombatActions).dice.seed = 281 + stage_index
	# 지금 게임에는 장판을 만드는 적이 없다. 아군 발밑에 깔아 장판 위의 저장을 만든다.
	var actions: CombatActions = battle.get("actions")
	var source: CombatUnit = actions.units.filter(func(unit: CombatUnit) -> bool: return not unit.is_ally)[0]
	_check(actions.create_ground(source, party[0].cell, "poison")
		and actions.create_ground(source, party[1].cell, "burn"), "검사용 장판 생성")
	return battle


func _free(battle: Node2D) -> void:
	battle.get_parent().queue_free()
	await process_frame


## 형식 2의 강도·장비·이니셔티브를 실제 상태에서 저장하고 그대로 복원한다.
func _test_format_two_state() -> void:
	var battle: Node2D = _battle(0)
	var actions: CombatActions = battle.get("actions")
	var party: Array[CombatUnit] = battle.get("party")
	var source: CombatUnit = actions.units.filter(func(unit: CombatUnit) -> bool: return not unit.is_ally)[0]
	_check(actions.apply_status(source, party[0], "poison") and actions.apply_status(source, party[1], "burn"),
		"형식 2 검사용 독·화상 부여")
	var state: Dictionary = battle.call("combat_state")
	_check(state.grounds.size() == 2 and state.grounds.all(func(ground: Array) -> bool:
		return ground.size() == 6 and ground[5] == (4 if ground[2] == "poison" else 0)),
		"장판은 여섯 값에 독 강도4·화상 강도0을 저장")
	_check(state.units[0].statuses == [["poison", actions.units.find(source), 4, 4]]
		and state.units[1].statuses == [["burn", actions.units.find(source), 2, 0]],
		"상태 이상은 내성 DC 대신 독 강도4·화상 강도0을 저장")
	_check(state.units[1].armor.stats == {"defense_bonus": 1, "max_hit_points": 3}, "방어 장비는 방어 가산으로 저장")
	for index: int in range(actions.units.size()):
		var unit: CombatUnit = actions.units[index]
		_check(state.units[index].initiative_roll == unit.get_initiative()
			and unit.initiative_roll >= 1 and unit.initiative_roll <= unit.get_ability_sides(CombatUnit.Ability.DEXTERITY),
			"민첩 주사위의 원본 결과를 저장: %d" % index)
	var restored: Node2D = _battle(-1)
	_check(restored.call("restore_combat", state) and restored.call("combat_state") == state,
		"형식 2의 강도·장비·이니셔티브를 포함한 상태 왕복")
	for value: int in [1, 8]:
		state.units[0].initiative_roll = value
		_check(restored.call("restore_combat", state) and restored.call("combat_state") == state,
			"전사 민첩 d8의 유효한 저장 경계: %d" % value)
	await _free(restored)
	await _free(battle)


## 자동 저장마다 파일에서 다시 읽은 저장과 그 순간의 전투 상태를 모은다.
func _track(battle: Node2D) -> Array[Dictionary]:
	var points: Array[Dictionary] = []
	battle.connect("autosaved", func() -> void:
		var save: Dictionary = GameSave.read()
		points.append({"save": save.get("sections", {}).get("combat", {}), "state": battle.call("combat_state"),
			"enemy_turn": battle.get("_enemy_turn_running")}))
	return points


## 한 단계 진행한다. 같은 상태에서는 늘 같은 입력을 주므로 원래 전투와 이어한 전투가 같은 입력을 받는다.
## 실제 게임처럼 저장할 프레임과 행동할 프레임을 나눈다. 연출 중인 적 턴은 한 프레임 기다리고 false다.
func _step(battle: Node2D, points: Array[Dictionary]) -> bool:
	var actions: CombatActions = battle.get("actions")
	var turns: CombatTurns = battle.get("turns")
	if actions.pending_reactor != null:
		# 반응 답은 난수 상태로 정해 받기와 넘기기를 모두 거친다.
		actions.resolve_reaction(actions.dice.state % 2 == 0)
		return true
	if battle.get("_enemy_turn_running"):
		await process_frame
		return false
	var saved: int = points.size()
	var actor: CombatUnit = turns.current_unit
	battle.call("_process", 0.0)
	# battle의 _process가 보통 속도로 되돌린다.
	Engine.time_scale = TIME_SCALE
	if (points.size() != saved or actions.is_over() or actor == null or not actor.is_ally
			or turns.current_unit != actor):
		return true
	for target: CombatUnit in actions.units:
		if target.hit_points <= 0 or target.is_ally:
			continue
		if actions.can_target(actor, target, "mark") and actor.marked_target == null:
			actions.mark(actor, target)
			return true
		if actions.can_target(actor, target, "attack"):
			await actions.attack(actor, target, actions.can_target(actor, target, "shock"))
			return true
	for heal: String in ["second_wind", "potion"]:
		if actor.hit_points * 2 <= actor.get_max_hit_points() and actions.can_use(actor, heal):
			actions.use_self(actor, heal)
			return true
	var cell: Vector2i = CombatEnemyAi.new().approach_cell(actor, actions)
	if cell != actor.cell and actions.can_move(actor, cell):
		await actions.move_to(actor, cell)
		return true
	battle.call("_end_turn")
	return true


func _test_stage(stage_index: int) -> void:
	var label: String = "%d-%d" % [stage_index / 3 + 1, stage_index % 3 + 1]
	var battle: Node2D = _battle(stage_index)
	var points: Array[Dictionary] = _track(battle)
	var base_count: int = (battle.get("units") as Array).size()
	var steps: int = 0
	var frames: int = 0
	while steps < MAX_STEPS and frames < MAX_FRAMES and not (battle.get("actions") as CombatActions).is_over():
		if await _step(battle, points):
			steps += 1
		else:
			frames += 1
	_check(frames < MAX_FRAMES, label + " 적 턴 연출이 끝남")
	battle.call("_process", 0.0)
	_measure(battle)
	await _free(battle)

	# 기획자가 정한 시점: 아군 턴, 적 턴 직후, 새끼 거미 생성 뒤, 장판 위. 적 턴 중간 저장도 따로 본다.
	var kinds: Dictionary[String, int] = {}
	for index: int in range(points.size()):
		var save: Dictionary = points[index].save
		var replay: int = save.get("replay", {}).get("actions", 0)
		if replay == 0:
			_check(save == points[index].state, "%s 저장 %d: 파일에서 읽은 저장이 그 순간의 상태와 같음" % [label, index])
		for kind: String in _kinds(points, index, base_count):
			if not kinds.has(kind):
				kinds[kind] = index
	var expected: Array[String] = ["ally_turn", "after_enemy_turn", "on_ground", "mid_enemy_turn"]
	if stage_index in [3, 6]:
		expected.append("after_spawn")
	for kind: String in expected:
		_check(kinds.has(kind), "%s %s 시점의 저장이 있음 (%s)" % [label, kind, kinds])
	if kinds.has("after_spawn"):
		var spawned: Dictionary = points[kinds.after_spawn].state.duplicate(true)
		_check(spawned.units[base_count].initiative_roll == 0, label + " 생성한 새끼는 이니셔티브를 굴리지 않음")
		var restored: Node2D = _battle(-1)
		for value: int in [0, 8]:
			spawned.units[base_count].initiative_roll = value
			_check(restored.call("restore_combat", spawned) and restored.call("combat_state") == spawned,
				"%s 생성한 새끼 민첩 d8의 유효한 저장 경계: %d" % [label, value])
		var before: Dictionary = restored.call("combat_state")
		for value: int in [-1, 9]:
			spawned.units[base_count].initiative_roll = value
			_check(not restored.call("restore_combat", spawned) and restored.call("combat_state") == before,
				"%s 생성한 새끼 이니셔티브 범위 밖 거부: %d" % [label, value])
		await _free(restored)
	print("%s: %d saves, first of each kind %s" % [label, points.size(), kinds])
	if kinds.has("reaction"):
		reaction_stages += 1

	for index: int in range(points.size()):
		var restored: Node2D = await _restore(points[index], "%s 저장 %d" % [label, index])
		if restored != null:
			await _free(restored)
	for kind: String in kinds:
		await _test_continuation(points, kinds[kind], "%s %s" % [label, kind])


func _kinds(points: Array[Dictionary], index: int, base_count: int) -> Array[String]:
	var kinds: Array[String] = []
	var save: Dictionary = points[index].save
	var state: Dictionary = points[index].state
	var units: Array = state.units
	var current: int = state.turns.current
	if index > 0 and units.size() > base_count and (points[index - 1].state.units as Array).size() < units.size():
		kinds.append("after_spawn")
	if save.has("replay"):
		kinds.append("mid_enemy_turn")
		if not save.replay.reactions.is_empty():
			kinds.append("reaction")
		return kinds
	if current >= 0 and units[current].ally:
		kinds.append("ally_turn")
	if index > 0 and points[index - 1].enemy_turn:
		kinds.append("after_enemy_turn")
	for ground: Array in state.grounds:
		if units.any(func(unit: Dictionary) -> bool: return unit.hit_points > 0 and unit.cell == ground[1]):
			kinds.append("on_ground")
			break
	return kinds


## 새 게임 장면에 저장을 복원한다. 적 턴 중간 저장은 다음 프레임에 끝낸 행동까지 연출 없이
## 바로 다시 실행해 같은 프레임 안에 저장 시점의 상태에 닿는다.
func _restore(point: Dictionary, label: String) -> Node2D:
	var battle: Node2D = _battle(-1)
	var points: Array[Dictionary] = _track(battle)
	if not battle.call("restore_combat", point.save):
		_check(false, label + " 복원 실패")
		await _free(battle)
		return null
	if point.save.get("replay", {}).get("actions", 0) == 0:
		_check(battle.call("combat_state") == point.state, label + " 복원한 상태가 저장한 순간과 같음")
		return battle
	battle.call("_process", 0.0)
	_check(not points.is_empty() and points[0].state == point.state,
		label + " 적 턴 중간 저장은 끝낸 적 행동까지 연출 없이 다시 실행해 같은 상태에 닿음")
	_check(not points.is_empty() and points[0].save == point.save, label + " 다시 실행한 순간의 저장이 같음")
	return battle


## 복원한 전투에 같은 입력을 이어서 주면 원래 전투와 같은 저장·상태(같은 굴림)가 차례로 나온다.
func _test_continuation(original: Array[Dictionary], from: int, label: String) -> void:
	var point: Dictionary = original[from]
	var battle: Node2D = _battle(-1)
	var points: Array[Dictionary] = _track(battle)
	if not battle.call("restore_combat", point.save):
		_check(false, label + " 이어하기 복원 실패")
		await _free(battle)
		return
	# 적 턴 중간 저장은 다시 실행한 순간에 같은 저장을 한 번 더 쓴다.
	var first: int = from if point.save.has("replay") else from + 1
	var expected: Array[Dictionary] = original.slice(first)
	var guard: int = 0
	var frames: int = 0
	while points.size() < expected.size() and guard < MAX_STEPS * 4 and frames < MAX_FRAMES:
		if await _step(battle, points):
			guard += 1
		else:
			frames += 1
	var matched: bool = points.size() >= expected.size()
	for index: int in range(mini(points.size(), expected.size())):
		if points[index].save != expected[index].save or points[index].state != expected[index].state:
			matched = false
			_check(false, "%s 이어하기 %d번째 저장부터 원래 전투와 다름" % [label, index])
			break
	_check(matched, "%s 이어한 전투가 원래 전투와 같은 굴림·상태로 %d번 저장" % [label, expected.size()])
	await _free(battle)


## 자동 저장 한 번과 같은 일(상태 수집, 파일 쓰기)의 시간을 잰다.
func _measure(battle: Node2D) -> void:
	for repeat: int in range(10):
		var started: int = Time.get_ticks_usec()
		GameSave.write(1, 1, {"combat": battle.call("combat_state")})
		save_usec.append(Time.get_ticks_usec() - started)
	save_bytes.append(FileAccess.get_file_as_bytes(GameSave.path).size())


## 자동 저장이 꺼져 있으면 행동해도 사용자의 저장 파일을 만들지 않는다.
func _test_autosave_switch() -> void:
	GameSave.delete()
	var battle: Node2D = _battle(-1)
	var points: Array[Dictionary] = _track(battle)
	for step: int in range(6):
		await _step(battle, points)
	_check(points.is_empty() and not GameSave.has_save(), "자동 저장이 꺼져 있으면 저장하지 않음")
	await _free(battle)


## 고친 저장은 읽을 수 없는 저장이다. 전투를 바꾸지 않고 false를 돌려준다.
func _test_rejects_bad_saves() -> void:
	var source: Node2D = _battle(3)
	var points: Array[Dictionary] = _track(source)
	for step: int in range(12):
		await _step(source, points)
	await _free(source)
	var good: Dictionary = points.back().save
	var enemy: int = (good.units as Array).find_custom(func(unit: Dictionary) -> bool: return not unit.ally)
	var cases: Dictionary[String, Callable] = {
		"스테이지 번호 밖": func(state: Dictionary) -> void: state.stage = 9,
		"유닛 칸이 지도 밖": func(state: Dictionary) -> void: state.units[0].cell = Vector2i(99, 0),
		"유닛 변수 타입이 다름": func(state: Dictionary) -> void: state.units[0].action_left = 1.0,
		"초기 전사 이니셔티브가 0": func(state: Dictionary) -> void: state.units[0].initiative_roll = 0,
		"전사 민첩 d8 밖 이니셔티브": func(state: Dictionary) -> void: state.units[0].initiative_roll = 9,
		"궁수 민첩 d20 밖 이니셔티브": func(state: Dictionary) -> void: state.units[1].initiative_roll = 21,
		"초기 새끼 거미 이니셔티브가 0": func(state: Dictionary) -> void: state.units[enemy].initiative_roll = 0,
		"새끼 거미 민첩 d8 밖 이니셔티브": func(state: Dictionary) -> void: state.units[enemy].initiative_roll = 9,
		"기본 배치와 다른 적 종류": func(state: Dictionary) -> void: state.units[enemy].kind = CombatUnit.Kind.SCRAP_ROBOT_3000,
		"새끼 거미가 아닌 늘어난 유닛": func(state: Dictionary) -> void:
			var extra: Dictionary = state.units[enemy].duplicate(true)
			extra.kind = CombatUnit.Kind.MOTHER_SPIDER
			state.units.append(extra),
		"없는 유닛을 가리키는 표식": func(state: Dictionary) -> void: state.units[0].marked_target = 99,
		"모르는 상태 이상": func(state: Dictionary) -> void: state.units[0].statuses = [["curse", 0, 1, 0]],
		"독 강도가 정수가 아님": func(state: Dictionary) -> void: state.units[0].statuses = [["poison", 0, 1, 4.0]],
		"독 강도가 없음": func(state: Dictionary) -> void: state.units[0].statuses = [["poison", 0, 1, 0]],
		"한도 밖 독 강도": func(state: Dictionary) -> void: state.units[0].statuses = [["poison", 0, 1, 1 << 60]],
		"턴 순서의 중복 유닛": func(state: Dictionary) -> void: state.turns.order.append(state.turns.order[0]),
		"묶음 범위 밖": func(state: Dictionary) -> void: state.turns.group = Vector2i(0, 99),
		"모르는 물체": func(state: Dictionary) -> void: state.props.append(["bomb", Vector2i.ZERO, 1]),
		"장판의 유닛 번호 밖": func(state: Dictionary) -> void: state.grounds.append([99, Vector2i.ZERO, "burn", 2, [], 0]),
		"이전 형식의 장판": func(state: Dictionary) -> void: state.grounds.append([0, Vector2i.ZERO, "burn", 2, []]),
		"장판 강도가 정수가 아님": func(state: Dictionary) -> void: state.grounds.append([0, Vector2i.ZERO, "poison", 4, [], 4.0]),
		"장판 독 강도가 없음": func(state: Dictionary) -> void: state.grounds.append([0, Vector2i.ZERO, "poison", 4, [], 0]),
		"한도 밖 장판 강도": func(state: Dictionary) -> void: state.grounds.append([0, Vector2i.ZERO, "poison", 4, [], 1 << 60]),
		"난수 상태가 정수가 아님": func(state: Dictionary) -> void: state.dice = "seed",
		"아이콘 경로를 바꾼 아이템": func(state: Dictionary) -> void: state.bag[0].icon = "../../../../project",
		"수치가 정수가 아닌 장비": func(state: Dictionary) -> void: state.units[0].weapon.stats.attack_bonus = [1],
		"무기 칸의 방어구": func(state: Dictionary) -> void: state.units[0].weapon = state.units[1].armor.duplicate(true),
		"아군 차례의 적 턴 다시 실행": func(state: Dictionary) -> void:
			state.turns.current = 0
			state.replay = {"actions": 1, "reactions": []},
		"반응 답이 bool이 아님": func(state: Dictionary) -> void: state.replay = {"actions": 0, "reactions": [1]},
		"마지막 아군이 적": func(state: Dictionary) -> void: state.last_ally = enemy,
		"끝나지 않는 행동 수": func(state: Dictionary) -> void: state.units[enemy].action_left = 1 << 40,
		"한도 밖 HP": func(state: Dictionary) -> void: state.units[0].hit_points = 1 << 60,
		"한도 밖 장비 수치": func(state: Dictionary) -> void: state.units[1].armor.stats.defense_bonus = 1 << 60,
		"시전자 없는 기절": func(state: Dictionary) -> void:
			state.units[0].stunned = true
			state.units[0].stun_source = -1,
		"쓰러진 시전자의 기절": func(state: Dictionary) -> void:
			state.units[0].stunned = true
			state.units[0].stun_source = enemy
			state.units[enemy].hit_points = 0,
		"끝난 전투의 적 턴 다시 실행": func(state: Dictionary) -> void:
			for unit: Dictionary in state.units:
				if unit.ally:
					unit.hit_points = 0
			state.turns.current = state.turns.order[state.turns.order.find_custom(
				func(index: int) -> bool: return not state.units[index].ally)]
			state.replay = {"actions": 1, "reactions": []},
		"너무 많은 다시 실행": func(state: Dictionary) -> void: state.replay = {"actions": 1 << 40, "reactions": []},
		"가방 한도 초과": func(state: Dictionary) -> void:
			for index: int in range(20):
				state.bag.append(state.bag[0].duplicate(true)),
		"턴 순서의 쓰러진 유닛": func(state: Dictionary) -> void: state.units[state.turns.order[0]].hit_points = 0,
		"턴 순서에 없는 살아 있는 유닛": func(state: Dictionary) -> void:
			state.turns.order.remove_at(state.turns.order.size() - 1),
		"현재 유닛 없음": func(state: Dictionary) -> void: state.turns.current = -1,
		"다시 실행 없는 반응 답": func(state: Dictionary) -> void: state.replay = {"actions": 0, "reactions": [true]},
		"묶음 밖의 현재 유닛": func(state: Dictionary) -> void:
			state.turns.group = Vector2i(0, 0)
			state.turns.current = state.turns.order[1],
		"유닛 목록이 없음": func(state: Dictionary) -> void: state.erase("units"),
	}
	var battle: Node2D = _battle(-1)
	_check(battle.call("restore_combat", good), "고치지 않은 저장은 복원")
	var before: Dictionary = battle.call("combat_state")
	for name: String in cases:
		var state: Dictionary = good.duplicate(true)
		cases[name].call(state)
		_check(not battle.call("restore_combat", state), "읽을 수 없는 저장 거부: " + name)
		_check(battle.call("combat_state") == before, "거부한 저장은 전투를 바꾸지 않음: " + name)
	await _free(battle)
