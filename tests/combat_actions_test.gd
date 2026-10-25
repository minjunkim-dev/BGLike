extends SceneTree
## 동작의 정상 흐름, 자원·횟수, 반응 중단과 실제 두 번 클릭 경로.

class Fixture extends RefCounted:
	var units: Array[CombatUnit] = []
	var turns: CombatTurns = CombatTurns.new()
	var actions: CombatActions = CombatActions.new()
	var hits: Array[bool] = []


const ScriptedDice = preload("res://tests/scripted_dice.gd")

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
	ScriptedDice.arrange_turns(f.turns, f.units, f.units)
	f.actions.initialize(f.units, f.turns)
	f.actions.hit_landed.connect(f.hits.append.bind(true))
	return f


func _dice_for(expected: Array[int], sides: Array[int]) -> ScriptedDice:
	return ScriptedDice.new(expected, sides)


func _ability_sides(unit: CombatUnit) -> Array[int]:
	var sides: Array[int] = []
	for ability: CombatUnit.Ability in CombatUnit.Ability.values():
		sides.append(unit.get_ability_sides(ability))
	return sides


func _test_rock_roll() -> void:
	var f: Fixture = _fixture()
	var rock: CombatGrid.Prop = f.actions.create_prop(Vector2i(4, 5), "rock")
	_check(rock != null, "유효한 빈 바닥에 바위를 생성한다")
	if rock == null:
		return
	f.actions.dice = _dice_for([], [])
	_check(f.actions.attack_prop(f.units[0], rock) and rock.cell == Vector2i(4, 8)
		and f.units[0].action_left == 0 and f.actions.last_damage == 0,
		"기본 공격 행동1로 바위를 공격자 반대 방향3칸 굴리며 주사위와 무기 피해를 쓰지 않는다")
	_check(not f.actions.attack_prop(f.units[0], rock) and rock.cell == Vector2i(4, 8),
		"행동을 쓴 뒤 반복 바위 공격은 실행하지 않는다")


func _test_rock_geometry() -> void:
	for obstacle: String in ["wall", "crate", "rock", "up"]:
		var f: Fixture = _fixture()
		var rock: CombatGrid.Prop = f.actions.create_prop(Vector2i(4, 5), "rock")
		if obstacle == "wall":
			f.actions.grid.blocked_cells = [Vector2i(4, 7)]
		elif obstacle == "up":
			f.actions.grid.heights[Vector2i(4, 7)] = 1
		else:
			f.actions.create_prop(Vector2i(4, 7), obstacle)
		var preview: RefCounted = f.actions.preview_rock(f.units[0], rock)
		_check(preview.get("cells") == [Vector2i(4, 6)] and rock.cell == Vector2i(4, 5)
			and f.units[0].action_left == 1, "순수 바위 경로 미리보기는 장애물 앞까지만 보여준다: " + obstacle)
		f.actions.dice = _dice_for([], [])
		_check(f.actions.attack_prop(f.units[0], rock) and rock.cell == Vector2i(4, 6),
			"실제 바위는 미리보기와 같은 장애물 앞에서 멈춘다: " + obstacle)
	for hazard: String in ["pit", "drop"]:
		var f: Fixture = _fixture()
		var rock: CombatGrid.Prop = f.actions.create_prop(Vector2i(4, 5), "rock")
		if hazard == "pit":
			f.actions.grid.pits = [Vector2i(4, 6)]
		else:
			f.actions.grid.heights[f.units[0].cell] = 2
			f.actions.grid.heights[rock.cell] = 2
		var preview: RefCounted = f.actions.preview_rock(f.units[0], rock)
		_check(preview.get("destroyed") and preview.get("cells") == [Vector2i(4, 6)],
			"낭떠러지와 한단계 높이차2 파괴를 미리 보여준다: " + hazard)
		f.actions.dice = _dice_for([], [])
		_check(f.actions.attack_prop(f.units[0], rock) and f.actions.get_props().is_empty(),
			"바위는 유닛 충돌 전에 낭떠러지/높이차2에서 제거된다: " + hazard)
	var f: Fixture = _fixture()
	var rock: CombatGrid.Prop = f.actions.create_prop(Vector2i(5, 5), "rock")
	f.units[0].kind = CombatUnit.Kind.ARCHER
	f.units[0].cell = Vector2i(7, 6)
	f.actions.dice = _dice_for([], [])
	_check(f.actions.attack_prop(f.units[0], rock) and rock.cell == Vector2i(2, 5),
		"원거리 공격은 공격자에서 바위로 향한 큰축 음수 방향으로 굴린다")
	f.units[0].begin_turn()
	f.units[0].cell = Vector2i(1, 4)
	rock.cell = Vector2i(2, 5)
	_check(f.actions.preview_rock(f.units[0], rock).get("direction") == Vector2i(1, 0),
		"대각선 거리의 두 축이 같으면 x축을 쓴다")
	rock.cell = Vector2i(9, 5)
	f.units[0].cell = Vector2i(8, 5)
	_check(f.actions.attack_prop(f.units[0], rock) and rock.cell == Vector2i(9, 5),
		"맵 경계 앞의 유효한 바위 공격은 행동1을 쓰고 제자리에 멈춘다")
	f.units[0].begin_turn()
	f.units[0].cell = rock.cell
	_check(not f.actions.attack_prop(f.units[0], rock) and f.units[0].action_left == 1,
		"공격자와 같은 칸의 바위는 방향을 만들지 않고 거부한다")


func _test_rock_collisions() -> void:
	for ally: bool in [false, true]:
		var f: Fixture = _fixture()
		var target: CombatUnit = f.units[1] if ally else f.units[2]
		target.cell = Vector2i(4, 6)
		var before: int = target.hit_points
		var rock: CombatGrid.Prop = f.actions.create_prop(Vector2i(4, 5), "rock")
		var preview: RefCounted = f.actions.preview_rock(f.units[0], rock)
		_check(preview.get("cells") == [Vector2i(4, 6), Vector2i(4, 7), Vector2i(4, 8)]
			and preview.get("collisions") == [target] and target.hit_points == before
			and target.cell == Vector2i(4, 6), "미리보기는 아군/적 충돌과 반복 밀기를 상태 변경 없이 예측한다")
		f.actions.dice = _dice_for([], [])
		_check(f.actions.attack_prop(f.units[0], rock) and target.hit_points == before - 4
			and target.cell == Vector2i(4, 9) and rock.cell == Vector2i(4, 8) and f.hits.size() == 1,
			"아군과 적 모두 한 굴림에서4피해1회만 받고 최대3회 밀린다")
		_check(target.movement_left == 6 and target.action_left == 1 and target.reaction_left == 1,
			"바위의 강제 밀기는 대상 자원이나 기회 공격을 소비하지 않는다")
	for obstacle: String in ["wall", "unit", "crate", "rock", "up"]:
		var f: Fixture = _fixture()
		var target: CombatUnit = f.units[2]
		target.cell = Vector2i(4, 6)
		var rock: CombatGrid.Prop = f.actions.create_prop(Vector2i(4, 5), "rock")
		if obstacle == "wall":
			f.actions.grid.blocked_cells = [Vector2i(4, 7)]
		elif obstacle == "unit":
			f.units[3].cell = Vector2i(4, 7)
		elif obstacle == "up":
			f.actions.grid.heights[Vector2i(4, 7)] = 1
		else:
			f.actions.create_prop(Vector2i(4, 7), obstacle)
		f.actions.dice = _dice_for([], [])
		_check(f.actions.attack_prop(f.units[0], rock) and target.hit_points == 8
			and target.cell == Vector2i(4, 6) and rock.cell == Vector2i(4, 5)
			and f.units[3].hit_points == 14, "밀 수 없으면 충돌 피해만 주고 대상 앞에서 멈추며 연쇄 밀지 않는다: " + obstacle)
	var f: Fixture = _fixture()
	f.units[2].cell = Vector2i(4, 6)
	f.units[2].hit_points = 4
	var rock: CombatGrid.Prop = f.actions.create_prop(Vector2i(4, 5), "rock")
	f.actions.dice = _dice_for([], [])
	_check(f.actions.attack_prop(f.units[0], rock) and f.units[2].hit_points == 0
		and rock.cell == Vector2i(4, 8), "충돌로 전투 불능이 된 대상의 빈칸으로 바위가 계속 굴러간다")
	f = _fixture()
	f.units[2].cell = Vector2i(4, 6)
	f.actions.grid.pits = [Vector2i(4, 7)]
	rock = f.actions.create_prop(Vector2i(4, 5), "rock")
	f.actions.dice = _dice_for([], [])
	_check(f.actions.attack_prop(f.units[0], rock) and f.units[2].hit_points == 0
		and f.units[2].cell == Vector2i(4, 7) and f.actions.get_props().is_empty(),
		"대상을 낭떠러지로 민 뒤 바위도 다음 낭떠러지에서 소멸한다")
	f = _fixture()
	var target: CombatUnit = f.units[2]
	target.cell = Vector2i(4, 6)
	for cell: Vector2i in [f.units[0].cell, Vector2i(4, 5), target.cell]:
		f.actions.grid.heights[cell] = 3
	f.actions.grid.water_cells = [Vector2i(4, 7)]
	f.actions.apply_status(f.units[0], target, "burn")
	f.actions.create_ground(f.units[0], Vector2i(4, 7), "burn")
	f.actions.create_ground(f.units[3], Vector2i(4, 7), "poison")
	rock = f.actions.create_prop(Vector2i(4, 5), "rock")
	f.actions.dice = _dice_for([], [])
	_check(f.actions.attack_prop(f.units[0], rock) and target.cell == Vector2i(4, 7)
		and target.hit_points == 6 and target.get_status_count("burn") == 0
		and target.get_status_count("poison") == 1 and f.actions.get_props().is_empty(),
		"바위 밀기는 기존 물→낙하2피해→장판 착지를 거치고 바위는 높이차3에서 먼저 파괴된다")
	f = _fixture()
	f.units[2].cell = Vector2i(4, 6)
	f.actions.grid.heights[f.units[0].cell] = 2
	f.actions.grid.heights[Vector2i(4, 5)] = 2
	rock = f.actions.create_prop(Vector2i(4, 5), "rock")
	f.actions.dice = _dice_for([], [])
	_check(f.actions.attack_prop(f.units[0], rock) and f.units[2].hit_points == 12
		and f.actions.get_props().is_empty(), "높이차2 파괴는 같은 칸의 유닛 충돌 피해보다 먼저 적용한다")


func _test_rock_interruptions() -> void:
	for pit: bool in [false, true]:
		var f: Fixture = _fixture()
		f.units[3].hit_points = 0
		f.units[2].cell = Vector2i(4, 6)
		f.units[2].hit_points = 5 if pit else 4
		if pit:
			f.actions.grid.pits = [Vector2i(4, 7)]
		var rock: CombatGrid.Prop = f.actions.create_prop(Vector2i(4, 5), "rock")
		var preview: RefCounted = f.actions.preview_rock(f.units[0], rock)
		_check(preview.get("cells") == [] and preview.get("reason") == "전투 종료",
			"미리보기도 충돌/낙사로 전투가 끝나면 남은 굴림을 예측하지 않는다")
		f.actions.dice = _dice_for([], [])
		_check(f.actions.attack_prop(f.units[0], rock) and f.actions.is_over()
			and rock.cell == Vector2i(4, 5), "실제 충돌/낙사로 전투가 끝나면 바위의 남은 이동을 중단한다")
	for change: String in ["reset", "unit_remove", "rock_remove", "rock_move", "over"]:
		var f: Fixture = _fixture()
		var target: CombatUnit = f.units[2]
		target.cell = Vector2i(4, 6)
		var rock: CombatGrid.Prop = f.actions.create_prop(Vector2i(4, 5), "rock")
		var callback: Callable = func() -> void:
			match change:
				"reset":
					f.actions.initialize(f.units, f.turns)
					f.actions.create_prop(Vector2i(4, 5), "rock")
					target.cell = Vector2i(8, 8)
				"unit_remove":
					f.units.erase(target)
				"rock_remove":
					f.actions.grid.props.erase(rock)
				"rock_move":
					rock.cell = Vector2i(8, 8)
				"over":
					f.actions.incapacitate(target)
					f.actions.incapacitate(f.units[3])
		f.actions.hit_landed.connect(callback)
		f.actions.dice = _dice_for([], [])
		var executed: bool = f.actions.attack_prop(f.units[0], rock)
		f.actions.hit_landed.disconnect(callback)
		_check(executed and not f.actions.busy and f.hits.size() == 1
			and rock.cell == (Vector2i(8, 8) if change == "rock_move" else Vector2i(4, 5)),
			"충돌 callback의 reset/유닛제거/물체제거·이동/종료는 남은 굴림을 중단한다: " + change)
		if change == "reset":
			var replacement: CombatGrid.Prop = f.actions.grid.prop_at(Vector2i(4, 5))
			_check(replacement != rock and replacement != null and replacement.hit_points == 6
				and target.cell == Vector2i(8, 8) and target.hit_points == 8,
				"초기화 callback의 새 바위나 바뀐 유닛에 지난 충돌을 다시 적용하지 않는다")
	var f: Fixture = _fixture()
	var target: CombatUnit = f.units[2]
	target.cell = Vector2i(4, 6)
	for cell: Vector2i in [f.units[0].cell, Vector2i(4, 5), target.cell]:
		f.actions.grid.heights[cell] = 3
	f.actions.grid.water_cells = [Vector2i(4, 7)]
	f.actions.apply_status(f.units[0], target, "burn")
	var rock: CombatGrid.Prop = f.actions.create_prop(Vector2i(4, 5), "rock")
	var reset: Array[bool] = [false]
	var callback: Callable = func() -> void:
		if reset[0] or target.cell != Vector2i(4, 7):
			return
		reset[0] = true
		f.actions.initialize(f.units, f.turns)
		target.cell = Vector2i(8, 8)
		target.hit_points = target.get_max_hit_points()
		f.actions.create_prop(Vector2i(1, 1), "rock")
		f.actions.create_ground(f.units[3], target.cell, "poison")
	f.actions.changed.connect(callback)
	f.actions.dice = _dice_for([], [])
	f.actions.attack_prop(f.units[0], rock)
	f.actions.changed.disconnect(callback)
	_check(reset[0] and target.hit_points == 12 and target.get_status_count("poison") == 0
		and f.actions.get_props().size() == 1 and f.actions.grid.prop_at(Vector2i(1, 1)) != null,
		"물의 화상 해제 callback이 전투를 초기화하면 지난 낙하/새 장판을 적용하지 않는다")


func _test_rock_logs() -> void:
	var f: Fixture = _fixture()
	f.units[2].cell = Vector2i(4, 6)
	f.units[2].hit_points = 4
	f.units[3].hit_points = 0
	var rock: CombatGrid.Prop = f.actions.create_prop(Vector2i(4, 5), "rock")
	var messages: Array[String] = []
	var record: Callable = func(message: String) -> void: messages.append(message)
	f.actions.logged.connect(record)
	f.actions.dice = _dice_for([], [])
	f.actions.attack_prop(f.units[0], rock)
	_check("바위 충돌: 피해4" in "\n".join(messages) and "전투 종료" in messages[-1]
		and "피해4" in messages[-1],
		"마지막 적을 쓰러뜨린 최종 정지 로그에도 충돌 피해4를 남긴다")
	f.actions.logged.disconnect(record)
	f = _fixture()
	rock = f.actions.create_prop(Vector2i(4, 5), "rock")
	var moves: Array[int] = [0]
	var stale: Array[bool] = [false]
	var callback: Callable = func(message: String) -> void:
		if "바위 이동" in message:
			moves[0] += 1
			if moves[0] == 3:
				f.actions.initialize(f.units, f.turns)
				f.actions.create_prop(Vector2i(1, 1), "rock")
		elif moves[0] == 3 and "최대3칸" in message:
			stale[0] = true
	f.actions.logged.connect(callback)
	f.actions.dice = _dice_for([], [])
	f.actions.attack_prop(f.units[0], rock)
	f.actions.logged.disconnect(callback)
	_check(moves[0] == 3 and not stale[0] and f.actions.grid.prop_at(Vector2i(1, 1)) != null,
		"마지막 이동 로그의 초기화 callback 뒤 새 전투에 지난 정지 로그를 추가하지 않는다")


func _test_rock_pit_reset_callbacks() -> void:
	for reset_at: String in ["ground_log", "turn_changed"]:
		var f: Fixture = _fixture()
		var target: CombatUnit = f.units[2]
		target.cell = Vector2i(4, 6)
		f.actions.grid.pits = [Vector2i(4, 7)]
		f.actions.create_ground(target, Vector2i(8, 8), "poison")
		var rock: CombatGrid.Prop = f.actions.create_prop(Vector2i(4, 5), "rock")
		var old_turns: CombatTurns = f.turns
		var reset_done: Array[bool] = [false]
		var stale: Array[String] = []
		var reset: Callable = func() -> void:
			if reset_done[0]:
				return
			reset_done[0] = true
			target.begin_stage(true)
			target.cell = Vector2i(8, 8)
			target.visible = true
			f.turns = CombatTurns.new()
			f.actions.initialize(f.units, f.turns)
			ScriptedDice.arrange_turns(f.turns, f.units, f.units)
			f.actions.create_prop(Vector2i(1, 1), "rock")
		var on_log: Callable = func(message: String) -> void:
			if reset_at == "ground_log" and "장판 해제" in message:
				reset.call()
			elif reset_done[0] and "낙사" in message:
				stale.append(message)
		var on_feedback: Callable = func(_unit: CombatUnit, text: String) -> void:
			if reset_done[0] and text == "낙사":
				stale.append(text)
		f.actions.logged.connect(on_log)
		f.actions.feedback.connect(on_feedback)
		if reset_at == "turn_changed":
			old_turns.changed.connect(reset)
		f.actions.dice = _dice_for([], [])
		f.actions.attack_prop(f.units[0], rock)
		f.actions.logged.disconnect(on_log)
		f.actions.feedback.disconnect(on_feedback)
		if reset_at == "turn_changed":
			old_turns.changed.disconnect(reset)
		_check(reset_done[0] and target in f.turns.ordered_units and target.visible
			and target.hit_points == 12 and f.actions.grid.prop_at(Vector2i(1, 1)) != null,
			"낙사 중 초기화 callback 뒤 새 턴 목록/표시/바위를 보존한다: " + reset_at)
		_check(stale.is_empty() and rock.cell == Vector2i(4, 5),
			"낙사 중 초기화 callback 뒤 지난 낙사 로그/피드백/굴림을 중단한다: " + reset_at)


func _test_rock_landing_removal() -> void:
	var f: Fixture = _fixture()
	var target: CombatUnit = f.units[2]
	var other: CombatUnit = f.units[3]
	target.cell = Vector2i(4, 6)
	other.cell = Vector2i(4, 8)
	f.actions.grid.water_cells = [Vector2i(4, 7)]
	f.actions.apply_status(f.units[0], target, "burn")
	var rock: CombatGrid.Prop = f.actions.create_prop(Vector2i(4, 5), "rock")
	var removed: Array[bool] = [false]
	var callback: Callable = func() -> void:
		if not removed[0] and target.cell == Vector2i(4, 7):
			removed[0] = true
			f.units.erase(target)
	f.actions.changed.connect(callback)
	f.actions.dice = _dice_for([], [])
	f.actions.attack_prop(f.units[0], rock)
	f.actions.changed.disconnect(callback)
	_check(removed[0] and target.hit_points == 8 and other.hit_points == 14
		and other.cell == Vector2i(4, 8) and rock.cell == Vector2i(4, 5) and f.hits.size() == 1,
		"착지의 화상 해제 callback이 대상을 제거하면 남은 굴림과 뒤 유닛 추가 피해를 중단한다")


func _test_rock_downhill_and_reentry() -> void:
	var f: Fixture = _fixture()
	f.actions.grid.heights[f.units[0].cell] = 2
	f.actions.grid.heights[Vector2i(4, 5)] = 2
	f.actions.grid.heights[Vector2i(4, 6)] = 1
	f.actions.grid.water_cells = [Vector2i(4, 7)]
	f.actions.create_ground(f.units[0], Vector2i(4, 6), "burn")
	f.actions.create_ground(f.units[3], Vector2i(4, 7), "poison")
	var rock: CombatGrid.Prop = f.actions.create_prop(Vector2i(4, 5), "rock")
	f.actions.dice = _dice_for([], [])
	_check(f.actions.preview_rock(f.units[0], rock).cells.size() == 3
		and f.actions.attack_prop(f.units[0], rock) and rock.cell == Vector2i(4, 8)
		and rock.hit_points == 6 and f.actions.get_grounds().size() == 2,
		"높이 차1씩 내려가는 길과 물/장판은 바위를 바꾸지 않고3칸 진행을 허용한다")
	f = _fixture()
	f.units[2].cell = Vector2i(4, 6)
	rock = f.actions.create_prop(Vector2i(4, 5), "rock")
	var attempts: Array[bool] = []
	var callback: Callable = func() -> void:
		f.units[0].begin_turn()
		attempts.append(f.actions.attack_prop(f.units[0], rock))
	f.actions.hit_landed.connect(callback)
	f.actions.dice = _dice_for([], [])
	f.actions.attack_prop(f.units[0], rock)
	f.actions.hit_landed.disconnect(callback)
	_check(attempts == [false] and f.units[2].hit_points == 8 and f.hits.size() == 1,
		"충돌 기록은 callback 전에 남기고 자원을 다시 채운 재진입 호출도 busy로 막는다")
	f = _fixture()
	rock = f.actions.create_prop(Vector2i(4, 5), "rock")
	f.actions.dice = _dice_for([], [])
	f.units[0].is_stunned = true
	_check(not f.actions.attack_prop(f.units[0], rock) and f.units[0].action_left == 1,
		"기절한 유닛은 바위 공격을 시작하지 않는다")
	f.units[0].is_stunned = false
	f.actions.busy = true
	_check(not f.actions.attack_prop(f.units[0], rock), "바쁜 동안 바위 공격을 시작하지 않는다")
	f.actions.busy = false
	_check(not f.actions.attack_prop(f.units[1], rock), "현재 조작자가 아니면 바위 공격을 시작하지 않는다")
	f.actions.initialize(f.units, f.turns)
	var replacement: CombatGrid.Prop = f.actions.create_prop(Vector2i(4, 5), "rock")
	_check(not f.actions.attack_prop(f.units[0], rock) and replacement.cell == Vector2i(4, 5)
		and f.units[0].action_left == 1, "지난 전투 바위의 호출은 같은 칸의 새 바위를 굴리지 않는다")


func _test_rock_scene_input() -> void:
	var scene: Node = (load("res://scenes/game.tscn") as PackedScene).instantiate()
	var battle: Node2D = scene.get_node("Battle") as Node2D
	var stage: CombatStage = (load("res://scenes/combat/stage.tres") as CombatStage).duplicate() as CombatStage
	stage.crate_cells = []
	battle.stages[0] = stage
	root.add_child(scene)
	battle.set_process(false)
	battle.call("start_battle")
	await process_frame
	var actions: CombatActions = battle.get("actions") as CombatActions
	var turns: CombatTurns = battle.get("turns") as CombatTurns
	var units: Array[CombatUnit] = battle.get("units")
	var selection: CombatSelection = battle.get("selection") as CombatSelection
	var map: CombatMap = battle.get("map") as CombatMap
	var hud: CombatTurnHud = battle.get("hud") as CombatTurnHud
	ScriptedDice.arrange_turns(turns, units, units)
	units[1].cell = Vector2i(1, 2)
	# 밀치기를 허용하는 인접 적은 바위 그림을 가리지 않는 쪽에 둔다.
	units[2].cell = Vector2i(1, 5)
	var rock: CombatGrid.Prop = actions.create_prop(Vector2i(1, 3), "rock")
	var point: Vector2 = map.get_global_transform_with_canvas() * (map.map_to_surface(rock.cell) + Vector2(0, -7))
	await _click(point)
	_check(selection.preview_prop == rock and units[0].action_left == 1 and units[1].hit_points == 14,
		"실제 바위 몸통 첫 클릭은 비용/충돌 피해 없이 미리보기를 연다")
	_check("바위" in hud.preview_label.text and "아군 피해4" in hud.preview_label.text
		and "주사위 없음" in hud.preview_label.text and "방향 0,-1" in hud.preview_label.text
		and "밀기 막힘" in hud.preview_label.text,
		"바위 안내는 같은 충돌규칙의 방향/경로/정지와 아군 피해4/무굴림을 표시한다")
	actions.grid.pits.append(Vector2i(1, 1))
	battle.call("_update_turn_ui")
	_check("아군 피해4: %s · 낙사" % units[1].get_display_name() in hud.preview_label.text,
		"바위 안내의 충돌 대상 뒤에 밀려서 받는 낙사를 붙인다")
	actions.grid.pits.erase(Vector2i(1, 1))
	battle.call("_update_turn_ui")
	await _click(point, MOUSE_BUTTON_RIGHT)
	_check(selection.preview_prop == null and rock.cell == Vector2i(1, 3), "바위 미리보기를 우클릭으로 취소한다")
	hud.action_selected.emit("shove")
	await _click(point)
	await _click(point)
	_check(units[0].action_left == 1 and units[1].hit_points == 14 and "기본 공격만" in hud.preview_label.text,
		"유닛 스킬로 바위 몸통을 재클릭해도 굴리지 않는다")
	hud.action_selected.emit("attack")
	actions.dice = _dice_for([], [])
	await _click(point)
	await _click(point)
	_check(units[0].action_left == 0 and units[1].hit_points == 10
		and units[1].cell == Vector2i(1, 0) and rock.cell == Vector2i(1, 1)
		and selection.preview_prop == null and "바위" in hud.message_label.text
		and "피해4" in hud.message_label.text,
		"실제 바위 두번 클릭은 아군을 두번 밀고 경계 앞에 멈추며 최종HUD로그에 피해4를 보존한다")
	point = map.get_global_transform_with_canvas() * (map.map_to_surface(rock.cell) + Vector2(0, -7))
	await _click(point)
	await _click(point)
	_check(units[1].hit_points == 10 and "행동 없음" in hud.preview_label.text,
		"이동한 바위를 반복 선택해도 행동이 없으면 추가 충돌을 실행하지 않는다")
	units[0].cell = Vector2i(1, 2)
	units[0].begin_turn()
	hud.action_selected.emit("attack")
	actions.changed.emit()
	await _click(point)
	await _click(point)
	_check(units[1].hit_points == 6 and rock.cell == Vector2i(1, 1),
		"새 굴림은 같은 대상에 다시4피해를 줄 수 있으며 경계 밖으로 연쇄 밀지 않는다")
	scene.free()
	await process_frame


func _test_crate_creation() -> void:
	var f: Fixture = _fixture()
	var crate: CombatGrid.Prop = f.actions.create_prop(Vector2i(4, 5), "crate")
	_check(crate != null and crate.cell == Vector2i(4, 5) and crate.hit_points == 6,
		"빈 바닥에 내구도6 나무 상자를 생성한다")
	_check(f.actions.get_props() == [crate] and f.units.size() == 4,
		"환경 오브젝트는 유닛 배열에 들어가지 않는다")
	var copy: Array = f.actions.get_props()
	copy.clear()
	_check(f.actions.get_props().size() == 1, "조회 배열 변경으로 상자가 사라지지 않는다")


func _test_crate_blocks_routes() -> void:
	var f: Fixture = _fixture()
	f.actions.create_prop(Vector2i(4, 5), "crate")
	_check(f.actions.grid.is_blocked(Vector2i(4, 5))
		and f.actions.grid.path_to(f.units[0], Vector2i(4, 5)).is_empty(),
		"나무 상자 칸은 걷기 목적지가 아니다")
	_check(f.actions.grid.jump_path(f.units[0], Vector2i(4, 5)).is_empty()
		and f.actions.grid.jump_path(f.units[0], Vector2i(4, 6)).is_empty(),
		"나무 상자 칸은 점프 통과와 착지를 막는다")
	f.actions.create_prop(Vector2i(6, 4), "crate")
	_check(not f.actions.grid.can_shove(f.units[0], f.units[2])
		and Vector2i(4, 5) not in f.actions.grid.pull_cells(f.units[0], f.units[3]),
		"상자 칸으로 밀치거나 끌지 않는다")


func _test_crate_attack() -> void:
	var f: Fixture = _fixture()
	var actor: CombatUnit = f.units[0]
	var crate: CombatGrid.Prop = f.actions.create_prop(Vector2i(4, 5), "crate")
	f.actions.dice = _dice_for([1], [8])
	_check(f.actions.can_attack_prop(actor, crate) and f.actions.attack_prop(actor, crate),
		"기본 공격으로 인접 나무 상자를 자동 명중한다")
	_check(crate.hit_points == 2 and actor.action_left == 0 and actor.bonus_action_left == 1
		and actor.reaction_left == 1 and actor.movement_left == 6 and f.hits.size() == 1,
		"상자는 d8의1+힘3 피해를 받고 행동1만 소비한다")
	_check(not f.actions.attack_prop(actor, crate) and crate.hit_points == 2,
		"행동이 없으면 상자를 다시 공격하거나 주사위를 굴리지 않는다")
	actor.begin_turn()
	f.actions.dice = _dice_for([1], [8])
	_check(f.actions.attack_prop(actor, crate) and crate.hit_points == 0
		and f.actions.get_props().is_empty() and f.actions.can_move(actor, Vector2i(4, 5)),
		"상자를 부수면 즉시 빈 칸이 되어 기존 이동 경로가 열린다")
	_check(not f.actions.attack_prop(actor, crate) and f.units.size() == 4,
		"파괴한 상자는 재공격/드랍/유닛 변경을 만들지 않는다")


func _test_crate_action_availability() -> void:
	var f: Fixture = _fixture()
	f.units[2].cell = Vector2i(9, 9)
	f.units[3].cell = Vector2i(8, 9)
	f.units[0].movement_left = 0
	f.actions.create_prop(Vector2i(4, 5), "crate")
	_check(f.actions.can_use(f.units[0], "attack") and f.actions.has_available_action(f.units[0]),
		"유닛 대상이 없어도 상자가 사거리 안이면 기본 공격을 사용할 수 있다")
	_check(not f.actions.can_use(f.units[0], "shock") and not f.actions.can_use(f.units[0], "mark"),
		"상자는 유닛 전용 스킬의 사용 가능 대상을 늘리지 않는다")


func _test_crate_stage() -> void:
	var scene: Node = (load("res://scenes/game.tscn") as PackedScene).instantiate()
	var battle: Node2D = scene.get_node("Battle") as Node2D
	root.add_child(scene)
	battle.set_process(false)
	battle.call("start_battle")
	await process_frame
	var actions: CombatActions = battle.get("actions") as CombatActions
	var units: Array[CombatUnit] = battle.get("units")
	var crate: CombatGrid.Prop = actions.grid.prop_at(Vector2i(3, 4))
	_check(crate != null and crate.hit_points == 6 and actions.get_props().size() == 2
		and units.size() == 6, "실제1막1스테이지는 기존6유닛과(3,4)의 상자/(6,6)의 바위로 시작한다")
	var rock: CombatGrid.Prop = actions.grid.prop_at(Vector2i(6, 6))
	_check(rock != null and rock.kind == "rock" and actions.grid.water_cells == [Vector2i(5, 1)]
		and actions.grid.pits == [Vector2i(6, 1)] and actions.grid.height_at(Vector2i(3, 0)) == 1
		and actions.grid.height_at(Vector2i(4, 0)) == 2 and actions.grid.height_at(Vector2i(5, 0)) == 2,
		"실제 첫 전투에 승인한 바위/물/낭떠러지/높이1·2 대표지형을 배치한다")
	if crate != null:
		actions.incapacitate(units[0])
		actions.incapacitate(units[1])
		(battle.get("hud") as CombatTurnHud).restart_requested.emit()
		var restored: CombatGrid.Prop = actions.grid.prop_at(Vector2i(3, 4))
		_check(restored != null and restored != crate and restored.hit_points == 6
			and actions.get_props().size() == 2 and actions.grid.prop_at(Vector2i(6, 6)) != rock,
			"막 재시작은 상자와 바위의 초기 위치/상자 내구도를 새로 복원한다")
	scene.free()
	await process_frame


func _test_crate_scene_input() -> void:
	var scene: Node = (load("res://scenes/game.tscn") as PackedScene).instantiate()
	var battle: Node2D = scene.get_node("Battle") as Node2D
	var stage: CombatStage = (load("res://scenes/combat/stage.tres") as CombatStage).duplicate() as CombatStage
	stage.crate_cells = [Vector2i(1, 3)]
	battle.stages[0] = stage
	root.add_child(scene)
	battle.set_process(false)
	battle.call("start_battle")
	await process_frame
	var actions: CombatActions = battle.get("actions") as CombatActions
	var turns: CombatTurns = battle.get("turns") as CombatTurns
	var units: Array[CombatUnit] = battle.get("units")
	var selection: CombatSelection = battle.get("selection") as CombatSelection
	var map: CombatMap = battle.get("map") as CombatMap
	var hud: CombatTurnHud = battle.get("hud") as CombatTurnHud
	ScriptedDice.arrange_turns(turns, units, units)
	var crate: CombatGrid.Prop = actions.grid.prop_at(Vector2i(1, 3))
	var point: Vector2 = map.get_global_transform_with_canvas() * (map.map_to_surface(crate.cell) + Vector2(0, -7))
	await _click(point)
	_check(selection.preview_prop == crate and crate.hit_points == 6 and units[0].action_left == 1,
		"상자 몸통의 첫 좌클릭은 기본 공격 미리보기이며 피해와 비용이 없다")
	_check("내구도 6/6" in hud.preview_label.text and "4~11" in hud.preview_label.text,
		"상자 안내는 내구도와 현재 무기 피해 범위를 표시한다")
	await _click(point, MOUSE_BUTTON_RIGHT)
	_check(selection.preview_prop == null and crate.hit_points == 6,
		"우클릭으로 상자 미리보기를 취소하며 막힌 칸으로 이동하지 않는다")
	units[2].cell = Vector2i(1, 5)
	actions.changed.emit()
	hud.action_selected.emit("shove")
	await _click(point)
	await _click(point)
	_check(crate.hit_points == 6 and units[0].action_left == 1 and "기본 공격만" in hud.preview_label.text,
		"유닛 스킬 선택 상태로 상자를 재클릭해도 실행하지 않는다")
	hud.action_selected.emit("attack")
	actions.dice = _dice_for([1], [8])
	await _click(point)
	await _click(point)
	_check(crate.hit_points == 2 and units[0].action_left == 0 and "내구도 2/6" in hud.message_label.text,
		"실제 상자 두번 클릭은 무기 피해와 행동 소비를 로그에 반영한다")
	await _click(point)
	await _click(point)
	_check(crate.hit_points == 2 and "행동 없음" in hud.preview_label.text,
		"행동이 없으면 상자 안내에서 사유를 표시하고 반복 실행을 막는다")
	units[0].begin_turn()
	hud.action_selected.emit("attack")
	actions.dice = _dice_for([1], [8])
	await _click(point)
	await _click(point)
	_check(actions.get_props().is_empty() and selection.preview_prop == null
		and "파괴" in hud.message_label.text and actions.can_move(units[0], Vector2i(1, 3)),
		"상자 파괴 후 대상 표시를 지우고 열린 길과 파괴 로그를 갱신한다")
	actions.create_prop(Vector2i(1, 3), "crate")
	await _click(point)
	actions.initialize(units, turns)
	actions.changed.emit()
	_check(selection.preview_prop == null and hud.preview_label.text.is_empty(),
		"외부 전투 초기화로 사라진 상자의 미리보기와 안내를 즉시 지운다")
	scene.free()
	await process_frame


func _test_crate_boundaries() -> void:
	var f: Fixture = _fixture()
	f.actions.grid.pits = [Vector2i(2, 2)]
	f.actions.grid.blocked_cells = [Vector2i(2, 3)]
	for cell: Vector2i in [Vector2i(-1, 0), Vector2i(10, 0), Vector2i(2, 2), Vector2i(2, 3), f.units[0].cell]:
		_check(f.actions.create_prop(cell, "crate") == null, "유효하지 않은 상자 시작 칸 거부: " + str(cell))
	_check(f.actions.create_prop(Vector2i(4, 5), "unknown") == null, "알 수 없는 환경 오브젝트 종류 거부")
	f.actions.grid.water_cells = [Vector2i(2, 4)]
	f.actions.create_ground(f.units[0], Vector2i(2, 4), "burn")
	var crate: CombatGrid.Prop = f.actions.create_prop(Vector2i(2, 4), "crate")
	_check(crate != null and f.actions.get_grounds().size() == 1
		and f.actions.create_prop(Vector2i(2, 4), "crate") == null,
		"물과 기존 장판 위에 상자를 만들되 다른 물체와 겹치지 않는다")
	f.actions.initialize(f.units, f.turns)
	_check(f.actions.get_props().is_empty() and f.actions.get_grounds().is_empty(),
		"전투 초기화는 지난 물체와 장판을 남기지 않는다")
	var target: CombatGrid.Prop = f.actions.create_prop(Vector2i(4, 5), "crate")
	var actor: CombatUnit = f.units[0]
	f.actions.dice = _dice_for([], [])
	actor.is_stunned = true
	_check(not f.actions.attack_prop(actor, target) and actor.action_left == 1, "기절한 유닛은 상자 공격 비용을 쓰지 않는다")
	actor.is_stunned = false
	f.actions.busy = true
	_check(not f.actions.attack_prop(actor, target), "바쁜 동안 상자 공격 거부")
	f.actions.busy = false
	_check(not f.actions.attack_prop(f.units[1], target), "현재 조작하지 않는 유닛의 상자 공격 거부")
	f.actions.grid.heights[target.cell] = 2
	_check(not f.actions.attack_prop(actor, target) and target.hit_points == 6,
		"근접 공격은 높이 차2의 상자를 공격하지 않는다")
	actor.kind = CombatUnit.Kind.ARCHER
	f.actions.dice = _dice_for([2], [6])
	_check(f.actions.attack_prop(actor, target) and target.hit_points == 3,
		"원거리 공격은 높이 차2에서도 d6의2+현재 피해 보정1을 준다")
	actor.begin_turn()
	f.actions.initialize(f.units, f.turns)
	var replacement: CombatGrid.Prop = f.actions.create_prop(Vector2i(4, 5), "crate")
	f.actions.dice = _dice_for([], [])
	_check(not f.actions.attack_prop(actor, target) and replacement.hit_points == 6 and actor.action_left == 1,
		"같은 칸에 새 상자가 있어도 지난 전투의 대상을 재사용하지 않는다")
	var far: CombatGrid.Prop = f.actions.create_prop(Vector2i(9, 9), "crate")
	_check(not f.actions.attack_prop(actor, far) and far.hit_points == 6 and actor.action_left == 1,
		"원거리 기본 공격도 현재 사거리 밖의 상자를 공격하지 않는다")
	_check(not f.actions.attack_prop(null, replacement) and not f.actions.attack_prop(actor, null),
		"유효하지 않은 행위자나 환경 오브젝트를 거부한다")


func _test_crate_ai_path() -> void:
	var f: Fixture = _fixture()
	var ally: CombatUnit = f.units[0]
	var enemy: CombatUnit = f.units[2]
	ally.cell = Vector2i(0, 0)
	enemy.cell = Vector2i(4, 0)
	enemy.kind = CombatUnit.Kind.SPIDERLING
	enemy.hit_points = 1
	f.units[1].hit_points = 0
	f.units[3].hit_points = 0
	f.actions.grid.map_size = Vector2i(5, 1)
	var crate: CombatGrid.Prop = f.actions.create_prop(Vector2i(2, 0), "crate")
	ScriptedDice.arrange_turns(f.turns, [enemy, ally], [enemy, ally])
	f.actions.dice = _dice_for([], [])
	var ai: CombatEnemyAi = CombatEnemyAi.new()
	await ai.play_turn(enemy, f.actions)
	_check(enemy.cell == Vector2i(3, 0) and enemy.action_left == 1 and crate.hit_points == 6,
		"기존 적 AI는 상자로 막힌 길을 통과하거나 상자를 공격하지 않는다")
	f.turns.end_turn()
	await f.actions.move_to(ally, Vector2i(1, 0))
	f.actions.dice = _dice_for([3], [8])
	_check(f.actions.attack_prop(ally, crate), "아군의 기본 공격으로 좁은 길의 상자를 부순다")
	f.turns.end_turn()
	f.actions.dice = _dice_for([1, 20], [4, 20])
	await ai.play_turn(enemy, f.actions)
	_check(enemy.cell == Vector2i(2, 0) and enemy.action_left == 0 and ally.hit_points == 12,
		"기존 적 AI는 파괴 후 열린 상자 칸으로 이동하고 기존 유닛 공격을 실행한다")


func _test_crate_callback_reset() -> void:
	var f: Fixture = _fixture()
	var crate: CombatGrid.Prop = f.actions.create_prop(Vector2i(4, 5), "crate")
	var reset: Callable = func() -> void:
		f.actions.initialize(f.units, f.turns)
		f.actions.create_prop(Vector2i(4, 5), "crate")
	f.actions.hit_landed.connect(reset)
	f.actions.dice = _dice_for([3], [8])
	var executed: bool = f.actions.attack_prop(f.units[0], crate)
	f.actions.hit_landed.disconnect(reset)
	var replacement: CombatGrid.Prop = f.actions.grid.prop_at(Vector2i(4, 5))
	_check(executed and crate.hit_points == 0 and replacement != null and replacement != crate
		and replacement.hit_points == 6 and not f.actions.busy and f.units[0].action_left == 0,
		"명중 callback의 전투 초기화는 새 상자에 지난 피해를 다시 적용하지 않는다")


func _run() -> void:
	_test_rock_roll()
	_test_rock_geometry()
	_test_rock_collisions()
	_test_rock_interruptions()
	_test_rock_logs()
	_test_rock_pit_reset_callbacks()
	_test_rock_landing_removal()
	_test_rock_downhill_and_reentry()
	await _test_rock_scene_input()
	_test_crate_creation()
	_test_crate_blocks_routes()
	_test_crate_attack()
	_test_crate_action_availability()
	_test_crate_boundaries()
	await _test_crate_ai_path()
	_test_crate_callback_reset()
	await _test_crate_stage()
	await _test_crate_scene_input()
	_test_novice_stats()
	_test_scrap_robot_stats()
	_test_scrap_robot_2000_stats()
	_test_scrap_robot_3000_stats()
	await _test_spin_attacks()
	_test_spin_height_availability()
	await _test_spin_height_targets()
	await _test_spin_height_recheck()
	_test_area_cells()
	await _test_spin_reactions_and_reuse()
	await _test_spin_incapacitation()
	_test_pull_success()
	_test_pull_contest_and_cooldown()
	_test_pull_destinations()
	_test_scrap_robot_overload()
	_test_scrap_robot_turn_damage()
	await _test_spiderling_stats_and_damage()
	await _test_mother_stats_and_damage()
	_test_spawn_spiderling()
	_test_novice_uses()
	await _test_novice_damage()
	await _test_scrap_robot_stun_immunity()
	await _test_scrap_robot_opportunity()
	await _test_movement()
	await _test_height_movement()
	_test_jump_path()
	_test_jump_height_path()
	_test_jump_routes()
	_test_blocked_cells()
	await _test_jump_cost_and_landing()
	await _test_jump_opportunity()
	await _test_height_adjacency()
	await _test_high_ground()
	_test_fall_damage()
	await _test_pit_movement()
	_test_pit_spawn()
	_test_pit_forced_movement()
	_test_forced_move_landing_preview()
	await _test_height_opportunity()
	_test_height_shove()
	_test_height_pull()
	_test_height_spawn()
	_test_ally_shove()
	_test_grid_queries()
	await _test_square_rules()
	await _test_attacks()
	await _test_archer_balance()
	_test_self_actions()
	_test_shove()
	await _test_mark_and_stun()
	await _test_stun_source_incapacitation()
	await _test_stunned_caster_expiry()
	await _test_deferred_stun_caster()
	await _test_stun_reapplication()
	await _test_stun_landing_incapacitation()
	await _test_finished_stun_removal()
	_test_burn_turn_start()
	_test_burn_caster_duration()
	_test_burn_stack_limit()
	_test_poison_tick()
	_test_status_fifo()
	_test_poison_save_oldest()
	_test_status_caster_incapacitation()
	_test_status_stage_reset()
	_test_poison_caster_duration()
	_test_status_lethal_tick()
	_test_common_stun_application()
	await _test_water_walk()
	_test_water_shove()
	_test_water_immunity()
	_test_water_turn_start()
	await _test_water_jump()
	_test_water_pull()
	_test_deferred_water_shove()
	_test_self_status_expiry()
	_test_status_removed_during_tick()
	_test_poison_removed_during_save()
	await _test_water_stage()
	_test_status_application_boundaries()
	_test_ground_creation()
	await _test_ground_walk_entry()
	_test_ground_start_and_expiry()
	_test_ground_cleanup()
	_test_ground_cleanup_observers()
	_test_ground_expiry_observers()
	await _test_ground_landings()
	await _test_ground_entry_reset()
	await _test_ground_rejected_entry()
	_test_deferred_ground_start()
	await _test_ground_entry_incapacitation()
	_test_ground_fifo()
	_test_self_ground_expiry()
	_test_ground_fall_and_water()
	await _test_ground_source_removed_during_entry()
	_test_ground_refresh_and_boundaries()
	await _test_reactions()
	await _test_own_turn_parry()
	_test_isometric_surface()
	await _test_scene_input()
	await _test_scene_ally_shove()
	await _test_height_scene_input()
	await _test_blocked_scene_input()
	await _test_jump_scene_input()
	await _test_jump_scene_animation()
	await _test_scene_fall_feedback()
	await _test_pit_scene_input()
	await _test_pit_scene_victory()
	await _test_isometric_unit_occlusion()
	await _test_terrain_hidden_unit_outline()
	await _test_scene_shock()
	for f: Fixture in _fixtures:
		for connection: Dictionary in f.actions.reaction_requested.get_connections():
			f.actions.reaction_requested.disconnect(connection["callable"] as Callable)
		for connection: Dictionary in f.actions.feedback.get_connections():
			f.actions.feedback.disconnect(connection["callable"] as Callable)
	_fixtures.clear()
	for unit: CombatUnit in _created:
		unit.free()
	var dice_problems: Array[String] = ScriptedDice.finish()
	_check(dice_problems.is_empty(), "준비한 주사위 값을 요청대로 모두 굴림 " + str(dice_problems))
	print("Combat actions: %d checks, %d failures" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)


func _test_scrap_robot_stats() -> void:
	var boss: CombatUnit = _fixture().units[2]
	boss.kind = CombatUnit.Kind.SCRAP_ROBOT_1000
	boss.hit_points = boss.get_max_hit_points()
	boss.begin_turn()
	_check(boss.get_max_hit_points() == 40 and boss.get_defense_bonus() == 2
		and boss.get_attack_bonus() == 3 and boss.get_damage_bonus() == 2
		and boss.get_damage_sides() == 8 and boss.get_attack_range() == 1
		and boss.movement_left == 4,
		"고철로봇-1000 전투 수치는 모든 막에서 고정")
	_check(_ability_sides(boss) == [12, 4, 8, 4, 12, 4],
		"고철로봇-1000 능력치")
	_check(boss.is_boss() and boss.get_display_name() == "고철로봇-1000"
		and CombatActionRules.belongs_to(boss, "opportunity")
		and not CombatActionRules.belongs_to(boss, "second_wind")
		and not CombatActionRules.belongs_to(boss, "surge"), "보스는 기본 공격과 기회 공격만 사용")


func _test_scrap_robot_2000_stats() -> void:
	var f: Fixture = _fixture()
	var boss: CombatUnit = f.units[2]
	boss.kind = CombatUnit.Kind.SCRAP_ROBOT_2000
	boss.hit_points = boss.get_max_hit_points()
	boss.begin_turn()
	_check(boss.is_boss() and boss.get_display_name() == "고철로봇-2000"
		and boss.get_max_hit_points() == 45 and boss.get_defense_bonus() == 3
		and boss.get_attack_bonus() == 3 and boss.get_damage_sides() == 8
		and boss.get_damage_bonus() == 2 and boss.get_attack_range() == 1
		and boss.movement_left == 4
		and boss.can_drop_extra_reward(), "고철로봇-2000은 모든 막에서 HP45·방어 가산3와 공통 보스 수치")
	boss.hit_points = 23
	boss.begin_turn()
	_check(not boss.overloaded and boss.action_left == 1, "2000은 HP23에서 과부하 없음")
	boss.hit_points = 22
	boss.begin_turn()
	_check(boss.overloaded and boss.action_left == 2, "2000은 HP22에서 과부하와 행동2개")
	_check(CombatActionRules.belongs_to(boss, "pull")
		and CombatActionRules.belongs_to(boss, "opportunity")
		and not CombatActionRules.belongs_to(f.units[0], "pull")
		and not CombatActionRules.belongs_to(f.units[1], "pull"), "만능팔은 아군 스킬로 노출하지 않음")


func _test_scrap_robot_3000_stats() -> void:
	var f: Fixture = _fixture()
	var boss: CombatUnit = f.units[2]
	boss.kind = CombatUnit.Kind.SCRAP_ROBOT_3000
	boss.hit_points = boss.get_max_hit_points()
	boss.begin_turn()
	_check(boss.is_boss() and boss.get_display_name() == "고철로봇-3000"
		and boss.get_max_hit_points() == 50 and boss.get_defense_bonus() == 4
		and boss.get_attack_bonus() == 3 and boss.get_damage_sides() == 8
		and boss.get_damage_bonus() == 2 and boss.get_attack_range() == 1
		and boss.movement_left == 4
		and boss.can_drop_extra_reward(), "고철로봇-3000은 모든 막에서 HP50·방어 가산4과 공통 보스 수치")
	boss.hit_points = 26
	boss.begin_turn()
	_check(not boss.overloaded and boss.action_left == 1, "3000은 HP26에서 과부하 없음")
	boss.hit_points = 25
	boss.begin_turn()
	_check(boss.overloaded and boss.action_left == 2, "3000은 HP25에서 과부하와 행동2개")
	_check(CombatActionRules.belongs_to(boss, "pull") and CombatActionRules.belongs_to(boss, "spin")
		and CombatActionRules.belongs_to(boss, "opportunity")
		and not CombatActionRules.belongs_to(f.units[0], "spin")
		and not CombatActionRules.belongs_to(f.units[1], "spin"), "3000의 만능팔·회전회오리·기회 공격 범위")


func _test_spin_attacks() -> void:
	var f: Fixture = _fixture()
	var boss: CombatUnit = f.units[2]
	boss.kind = CombatUnit.Kind.SCRAP_ROBOT_3000
	boss.hit_points = 50
	boss.begin_turn()
	f.turns.current_unit = boss
	f.units[1].cell = Vector2i(5, 3)
	f.units[0].parry_left = 0
	f.actions.dice = _dice_for([6, 9, 2, 6], [12, 20, 8, 8])
	_check(await f.actions.spin(boss), "회전회오리 실행")
	_check(f.units[0].hit_points == 12 and f.units[1].hit_points == 6,
		"공통 힘 d12의6+3에 각 대상이 방어해 첫 동점은 빗나가고 두 번째만 1d8+2 피해")
	_check(f.actions.last_attack.rolls == [6] and f.actions.last_attack.defender_roll == 2
		and f.units[0].cell == Vector2i(4, 4) and f.units[1].cell == Vector2i(5, 3),
		"회전회오리는 대상을 밀어내지 않음")
	_check(boss.action_left == 0 and boss.bonus_action_left == 1 and boss.reaction_left == 1
		and boss.movement_left == 4 and not f.actions.busy, "여러 대상이어도 행동1개만 소비하고 입력 잠금을 해제")


func _test_spin_height_availability() -> void:
	var f: Fixture = _fixture()
	var boss: CombatUnit = f.units[2]
	boss.kind = CombatUnit.Kind.SCRAP_ROBOT_3000
	boss.hit_points = 50
	boss.begin_turn()
	f.turns.current_unit = boss
	f.actions.grid.heights[f.units[0].cell] = 2
	_check(not f.actions.can_use(boss, "spin") and boss.action_left == 1,
		"높이 차이2인 대상만 인접하면 회전회오리를 쓸 수 없고 행동을 보존")


func _test_spin_height_targets() -> void:
	var f: Fixture = _fixture()
	var boss: CombatUnit = f.units[2]
	boss.kind = CombatUnit.Kind.SCRAP_ROBOT_3000
	boss.hit_points = 50
	boss.begin_turn()
	f.turns.current_unit = boss
	f.units[0].reaction_left = 0
	f.units[1].cell = Vector2i(5, 3)
	f.actions.grid.heights = {f.units[0].cell: 2, f.units[1].cell: 1}
	var attacked: Array[CombatUnit] = []
	f.actions.attack_animation = func(_actor: CombatUnit, target: CombatUnit) -> void:
		attacked.append(target)
		await process_frame
	_check(await f.actions.spin(boss) and attacked == [f.units[1]]
		and f.units[0].hit_points == 12 and boss.action_left == 0,
		"회전회오리는 높이1 대상만 실제 판정하고 높이2 대상·기존 유닛 순서·행동1 소비를 보존")
	f.actions.attack_animation = Callable()


func _test_spin_height_recheck() -> void:
	var f: Fixture = _fixture()
	var boss: CombatUnit = f.units[2]
	boss.kind = CombatUnit.Kind.SCRAP_ROBOT_3000
	boss.hit_points = 50
	boss.begin_turn()
	f.turns.current_unit = boss
	f.units[0].reaction_left = 0
	f.units[1].cell = Vector2i(5, 3)
	var attacked: Array[CombatUnit] = []
	f.actions.attack_animation = func(_actor: CombatUnit, target: CombatUnit) -> void:
		attacked.append(target)
		f.actions.grid.heights[f.units[1].cell] = 2
		await process_frame
	f.actions.dice = _dice_for([11, 1, 1], [12, 20, 8])
	_check(await f.actions.spin(boss) and attacked == [f.units[0]]
		and f.units[0].hit_points == 9 and f.units[1].hit_points == 14,
		"첫 공격 대기 뒤 두 번째 대상의 높이가 바뀌면 주사위·피해 없이 제외")
	f.actions.attack_animation = Callable()


func _test_area_cells() -> void:
	var grid: CombatGrid = _fixture().actions.grid
	grid.map_size = Vector2i(3, 3)
	_check(grid.area_cells(Vector2i.ZERO, 1) == [Vector2i.ZERO, Vector2i(1, 0), Vector2i(0, 1)],
		"모서리 반경1은 중심과 맵 안 상하좌우만 포함하고 대각선을 제외")
	grid.heights = {Vector2i(1, 0): 1, Vector2i(0, 1): -1}
	_check(grid.area_cells(Vector2i.ZERO, 1).size() == 3,
		"영향 칸은 중심보다 높거나 낮아도 높이 차이1을 포함")
	grid.blocked_cells = [Vector2i(1, 0)]
	grid.pits = [Vector2i(0, 1)]
	_check(grid.area_cells(Vector2i.ZERO, 2) == [Vector2i.ZERO, Vector2i(2, 0), Vector2i(1, 1), Vector2i(0, 2)],
		"반경2는 막힌 칸과 낭떠러지를 제외하되 중간 칸을 따라 전파하지 않음")
	grid.heights = {Vector2i(2, 0): 2, Vector2i(0, 2): -2, Vector2i(1, 1): 1}
	_check(grid.area_cells(Vector2i.ZERO, 2) == [Vector2i.ZERO, Vector2i(1, 1)],
		"넓은 반경에서도 모든 영향 칸의 높이는 중심과 직접 비교")
	_check(grid.area_cells(Vector2i.ZERO, 0) == [Vector2i.ZERO]
		and grid.area_cells(Vector2i.ZERO, -1).is_empty(), "반경0은 중심만 포함하고 음의 반경은 거부")
	_check(grid.area_cells(Vector2i(-1, 0), 1).is_empty()
		and grid.area_cells(Vector2i(1, 0), 1).is_empty()
		and grid.area_cells(Vector2i(0, 1), 1).is_empty(), "맵 밖·막힌 칸·낭떠러지 중심은 빈 범위")
	_check(grid.in_range(Vector2i.ZERO, Vector2i(2, 0), 2),
		"일반 사거리는 범위 스킬의 높이 제한을 적용하지 않고 평면 거리를 유지")


func _test_spin_reactions_and_reuse() -> void:
	var f: Fixture = _fixture()
	var boss: CombatUnit = f.units[2]
	boss.kind = CombatUnit.Kind.SCRAP_ROBOT_3000
	boss.hit_points = 25
	boss.begin_turn()
	f.turns.current_unit = boss
	f.units[1].cell = Vector2i(5, 3)
	var prompts: Array[String] = []
	f.actions.reaction_requested.connect(func(kind: String, _prompt: String) -> void:
		prompts.append(kind)
		_check(kind == "parry" and f.actions.busy and f.units[1].hit_points == 14
			and not f.actions.can_use(boss, "spin"), "첫 대상의 반응을 기다리는 동안 다음 대상 판정과 중복 입력을 잠금")
		f.actions.resolve_reaction(true)
	)
	f.actions.dice = _dice_for([5, 1, 5, 1, 1], [12, 20, 8, 8, 8])
	_check(await f.actions.spin(boss) and f.units[0].hit_points == 12 and f.units[1].hit_points == 11
		and f.units[0].reaction_left == 0 and f.units[0].parry_left == 1,
		"첫 대상은 같은 공격 합계8을 민첩5+3 흘려내기로 막고 다음 대상은 독립 피해를 받음")
	f.actions.dice = _dice_for([12, 1, 3, 1, 1], [12, 20, 8, 8, 8])
	_check(await f.actions.spin(boss) and f.units[0].hit_points == 7 and f.units[1].hit_points == 8
		and prompts == ["parry"] and boss.action_left == 0,
		"과부하 같은 턴에 회전회오리를 다시 쓰며 공통 최댓값에도 피해를 한 번씩 굴리고 소비한 반응을 유지")
	boss.begin_turn()
	f.units[1].cell = Vector2i(9, 9)
	f.actions.dice = _dice_for([11, 1, 1], [12, 20, 8])
	_check(await f.actions.spin(boss) and f.units[0].hit_points == 4 and f.units[1].hit_points == 8
		and CombatActionRules.uses_left(boss, "spin") == -1,
		"다음 턴에도 횟수·대기 제한 없이 쓰며 사거리 밖 아군은 공격하지 않음")


func _test_spin_incapacitation() -> void:
	var f: Fixture = _fixture()
	var boss: CombatUnit = f.units[2]
	boss.kind = CombatUnit.Kind.SCRAP_ROBOT_3000
	boss.hit_points = 50
	f.units[0].hit_points = 3
	f.units[0].parry_left = 0
	f.units[1].cell = Vector2i(5, 3)
	ScriptedDice.arrange_turns(f.turns, f.units, [f.units[2], f.units[1], f.units[0], f.units[3]])
	f.actions.dice = _dice_for([11, 1, 1, 1, 2], [12, 20, 8, 8, 8])
	_check(await f.actions.spin(boss) and f.units[0].hit_points == 0
		and f.units[1].hit_points == 10 and boss.action_left == 0,
		"첫 대상 전투 불능 뒤 남은 대상 공격과 한 번 소비한 행동을 유지")
	var interrupted: Fixture = _fixture()
	boss = interrupted.units[2]
	boss.kind = CombatUnit.Kind.SCRAP_ROBOT_3000
	boss.hit_points = 50
	interrupted.units[0].parry_left = 0
	interrupted.units[1].cell = Vector2i(5, 3)
	ScriptedDice.arrange_turns(interrupted.turns, interrupted.units, [interrupted.units[2], interrupted.units[1], interrupted.units[0], interrupted.units[3]])
	interrupted.actions.attack_animation = func(actor: CombatUnit, _target: CombatUnit) -> void:
		interrupted.actions.incapacitate(actor)
		await process_frame
	interrupted.actions.dice = _dice_for([11], [12])
	_check(await interrupted.actions.spin(boss) and boss.hit_points == 0
		and interrupted.units[0].hit_points == 12 and interrupted.units[1].hit_points == 14
		and not interrupted.actions.busy, "연출 대기 중 공격자가 전투 불능이면 공통 공격 굴림 뒤 대상 방어·피해 없이 중단하고 입력 잠금 해제")
	interrupted.actions.attack_animation = Callable()


func _test_pull_success() -> void:
	var f: Fixture = _fixture()
	var boss: CombatUnit = f.units[2]
	boss.kind = CombatUnit.Kind.SCRAP_ROBOT_2000
	boss.hit_points = 45
	boss.cell = Vector2i(4, 4)
	boss.begin_turn()
	f.turns.current_unit = boss
	f.units[0].cell = Vector2i(1, 1)
	var target: CombatUnit = f.units[1]
	target.cell = Vector2i(7, 4)
	var reactor: CombatUnit = f.units[3]
	reactor.kind = CombatUnit.Kind.WARRIOR
	reactor.cell = Vector2i(7, 3)
	_check(CombatGrid.distance(reactor.cell, target.cell) == 1,
		"만능팔 검사 대상은 다른 적의 기회 공격 위협 칸에서 시작")
	f.actions.dice = _dice_for([12, 1], [12, 8])
	_check(f.actions.pull(boss, target), "거리3 만능팔 실행")
	_check(target.cell == Vector2i(5, 4) and target.hit_points == 14
		and target.movement_left == 6 and reactor.reaction_left == 1,
		"성공 시 대상에게 가장 가까운 인접 빈 칸으로 피해·이동력 소비·기회 공격 없이 끌어옴")
	_check(boss.action_left == 0 and boss.bonus_action_left == 1,
		"만능팔은 행동 하나만 소비")


func _test_pull_contest_and_cooldown() -> void:
	var f: Fixture = _fixture()
	var boss: CombatUnit = f.units[2]
	boss.kind = CombatUnit.Kind.SCRAP_ROBOT_2000
	boss.hit_points = 22
	boss.cell = Vector2i(4, 4)
	f.units[0].cell = Vector2i(1, 1)
	var target: CombatUnit = f.units[1]
	target.cell = Vector2i(7, 4)
	f.units[3].cell = Vector2i(9, 9)
	ScriptedDice.arrange_turns(f.turns, f.units, [f.units[2], f.units[1], f.units[0], f.units[3]])
	f.actions.dice = _dice_for([5, 8], [12, 8])
	_check(f.actions.pull(boss, target) and target.cell == Vector2i(7, 4),
		"만능팔은 대상 힘 d8을 사용하며 대결 동점은 방어자 승리")
	_check(boss.action_left == 1 and not f.actions.can_use(boss, "pull")
		and not f.actions.pull(boss, target), "실패해도 과부하 두 번째 행동으로 만능팔 재사용 불가")
	for turn: int in range(4):
		f.turns.end_turn()
	_check(f.turns.current_unit == boss and boss.action_left == 2
		and not f.actions.can_use(boss, "pull") and not f.actions.pull(boss, target),
		"다음 실제 보스 턴에는 만능팔을 쉬고 행동을 소비하지 않음")
	for turn: int in range(4):
		f.turns.end_turn()
	_check(f.turns.current_unit == boss and f.actions.can_use(boss, "pull"),
		"그다음 실제 보스 턴부터 만능팔 재사용 가능")
	target.kind = CombatUnit.Kind.WARRIOR
	target.hit_points = 12
	f.actions.dice = _dice_for([10, 14], [12, 20])
	_check(f.actions.pull(boss, target) and target.cell == Vector2i(7, 4)
		and target.hit_points == 12, "전사도 힘 d20으로 저항하고 실패 시 위치·HP 유지")


func _test_pull_destinations() -> void:
	for choice: int in [1, 2]:
		var f: Fixture = _fixture()
		var boss: CombatUnit = f.units[2]
		boss.kind = CombatUnit.Kind.SCRAP_ROBOT_2000
		boss.hit_points = 45
		boss.cell = Vector2i(4, 4)
		f.turns.current_unit = boss
		f.units[0].cell = Vector2i(1, 1)
		f.units[1].cell = Vector2i(6, 5)
		f.units[3].cell = Vector2i(9, 9)
		f.actions.dice = _dice_for([12, 1, choice], [12, 8, 2])
		_check(f.actions.pull(boss, f.units[1])
			and f.units[1].cell == [Vector2i(5, 4), Vector2i(4, 5)][choice - 1],
			"대상에게 같은 거리인 인접 빈 칸 두 곳을 d2로 선택")
	var f: Fixture = _fixture()
	var boss: CombatUnit = f.units[2]
	boss.kind = CombatUnit.Kind.SCRAP_ROBOT_2000
	boss.hit_points = 45
	boss.cell = Vector2i(4, 4)
	f.turns.current_unit = boss
	f.units[0].cell = Vector2i(1, 1)
	f.units[3].cell = Vector2i(9, 9)
	for distance: int in range(5):
		f.units[1].cell = Vector2i(4 + distance, 4)
		_check(f.actions.can_target(boss, f.units[1], "pull") == (distance in [2, 3]),
			"만능팔은 거리2~3만 대상")
	f.units[1].cell = Vector2i(6, 5)
	f.units[3].cell = Vector2i(5, 4)
	f.actions.dice = _dice_for([12, 1], [12, 8])
	_check(f.actions.pull(boss, f.units[1]) and f.units[1].cell == Vector2i(4, 5),
		"가장 가까운 한 칸이 차 있으면 남은 가까운 빈 칸을 선택")
	boss.begin_stage(false)
	f.units[1].cell = Vector2i(7, 4)
	for cell: Vector2i in CombatGrid.neighbors(boss.cell):
		if f.actions.grid.unit_at(cell) != null:
			continue
		var blocker: CombatUnit = CombatUnit.new()
		blocker.is_ally = false
		blocker.cell = cell
		f.units.append(blocker)
		_created.append(blocker)
	f.actions.dice = _dice_for([], [])
	_check(not f.actions.can_use(boss, "pull") and not f.actions.pull(boss, f.units[1])
		and boss.action_left == 1, "인접 빈 칸이 없으면 판정·행동 소비 없이 만능팔 거부")


func _test_scrap_robot_overload() -> void:
	var boss: CombatUnit = _fixture().units[2]
	boss.kind = CombatUnit.Kind.SCRAP_ROBOT_1000
	boss.hit_points = 21
	boss.begin_turn()
	_check(boss.action_left == 1, "HP 21에서 과부하가 켜지지 않음")
	boss.hit_points = 20
	boss.begin_turn()
	_check(boss.action_left == 2, "HP 20에서 턴 행동 2개")
	boss.spend_resource(CombatUnit.TurnResource.ACTION)
	boss.hit_points = 19
	_check(boss.action_left == 1, "추가 피해로 과부하 행동을 중복 지급하지 않음")
	boss.hit_points = 40
	boss.begin_turn()
	_check(boss.action_left == 2, "회복해도 과부하가 전투 중 유지됨")


func _test_scrap_robot_turn_damage() -> void:
	var f: Fixture = _fixture()
	var boss: CombatUnit = f.units[2]
	boss.kind = CombatUnit.Kind.SCRAP_ROBOT_1000
	boss.hit_points = 20
	ScriptedDice.arrange_turns(f.turns, f.units, [f.units[0], f.units[1], f.units[3], f.units[2]])
	f.turns.end_turn()
	f.turns.end_turn()
	_check(f.turns.current_unit == f.units[3] and boss.hit_points == 20,
		"같은 적 묶음에 들어가도 실제 보스 순서 전에는 자기 피해 없음")
	f.turns.end_turn()
	_check(f.turns.current_unit == boss and boss.hit_points == 18 and boss.action_left == 2,
		"보스 실제 턴 시작에 자기 피해 2와 행동 2개")
	f.turns.remove_unit(f.units[3])
	_check(boss.hit_points == 18, "묶음 재계산으로 자기 피해를 중복 적용하지 않음")
	f.turns.end_turn()
	f.turns.end_turn()
	f.turns.end_turn()
	_check(f.turns.current_unit == boss and boss.hit_points == 16,
		"다음 라운드 자기 턴에 다시 자기 피해 2")
	for remaining_enemy: bool in [false, true]:
		var dying: Fixture = _fixture()
		var doomed: CombatUnit = dying.units[2]
		doomed.kind = CombatUnit.Kind.SCRAP_ROBOT_1000
		doomed.hit_points = 2 if remaining_enemy else 1
		dying.units[1].marked_target = doomed
		if not remaining_enemy:
			dying.actions.incapacitate(dying.units[3])
		var living: Array[CombatUnit] = dying.units.duplicate()
		var order: Array[CombatUnit] = [living[0], living[1], living[3], living[2]]
		if not remaining_enemy:
			living.erase(dying.units[3])
			order.erase(dying.units[3])
		ScriptedDice.arrange_turns(dying.turns, living, order)
		dying.turns.end_turn()
		dying.turns.end_turn()
		if remaining_enemy:
			dying.turns.end_turn()
		_check(doomed.hit_points == 0 and doomed not in dying.turns.ordered_units
			and not doomed.visible and dying.units[1].marked_target == null,
			"자기 피해 HP 0은 즉시 전투 불능·턴 제거·표식 해제")
		_check(dying.actions.is_victory() == not remaining_enemy
			and dying.actions.is_over() == not remaining_enemy,
			"다른 살아 있는 적이 없을 때만 승리")
		_check(not dying.actions.can_use(doomed, "attack")
			and dying.turns.current_unit != doomed, "전투 불능 보스는 그 턴과 이후 턴에 행동 불가")


func _test_scrap_robot_stun_immunity() -> void:
	var f: Fixture = _fixture()
	var boss: CombatUnit = f.units[2]
	boss.kind = CombatUnit.Kind.SCRAP_ROBOT_1000
	boss.hit_points = 40
	boss.cell = Vector2i(6, 4)
	var archer: CombatUnit = f.units[1]
	f.turns.select_unit(archer)
	f.actions.dice = _dice_for([10, 1, 3], [20, 4, 6])
	_check(await f.actions.attack(archer, boss, true), "보스에게 충격 화살 공격 가능")
	_check(boss.hit_points == 36 and not boss.is_stunned and archer.shock_left == 0,
		"보스는 충격 화살 피해를 받지만 내성 굴림 없이 기절에 면역")


func _test_scrap_robot_opportunity() -> void:
	var f: Fixture = _fixture()
	var boss: CombatUnit = f.units[2]
	boss.kind = CombatUnit.Kind.SCRAP_ROBOT_1000
	boss.hit_points = 40
	f.units[0].parry_left = 0
	f.actions.dice = _dice_for([11, 1, 8], [12, 20, 8])
	_check(await f.actions.move_to(f.units[0], Vector2i(3, 5)), "보스 인접 칸에서 이동")
	_check(f.units[0].hit_points == 2 and boss.reaction_left == 0,
		"보스 기회 공격은 힘 d12 +3·피해 1d8+2로 반응을 소비")


func _test_novice_stats() -> void:
	var f: Fixture = _fixture()
	for index: int in [2, 3]:
		var enemy: CombatUnit = f.units[index]
		_check(enemy.get_max_hit_points() == (12 if index == 2 else 14)
			and enemy.get_defense_bonus() == 0
			and enemy.get_attack_bonus() == (3 if index == 2 else 0) and enemy.get_damage_bonus() == 1,
			"풋내기 HP·방어 가산·공격 가산·피해는 모든 막에서 고정")
		_check(_ability_sides(enemy) == ([10, 6, 4, 4, 4, 4] if index == 2 else [4, 10, 4, 4, 4, 4])
			and enemy.get_attack_range() == (1 if index == 2 else 6)
			and enemy.movement_left == 6, "풋내기 능력치·이동력·사거리")
	_check(CombatActionRules.belongs_to(f.units[2], "second_wind")
		and CombatActionRules.belongs_to(f.units[2], "opportunity")
		and not CombatActionRules.belongs_to(f.units[2], "parry")
		and not CombatActionRules.belongs_to(f.units[2], "surge"), "야만인은 숨 고르기와 기회 공격만 사용")
	_check(CombatActionRules.belongs_to(f.units[3], "disengage")
		and not CombatActionRules.belongs_to(f.units[3], "opportunity")
		and not CombatActionRules.belongs_to(f.units[3], "mark")
		and not CombatActionRules.belongs_to(f.units[3], "shock"), "풋내기 궁수는 물러서며 쏘기만 사용")
	_check(_ability_sides(f.units[0]) == [20, 8, 6, 4, 12, 6]
		and f.units[0].get_defense_bonus() == 0 and f.units[0].get_damage_bonus() == 3
		and _ability_sides(f.units[1]) == [8, 20, 12, 6, 4, 6]
		and f.units[1].get_defense_bonus() == 0 and f.units[1].get_damage_bonus() == 1,
		"아군 전사·궁수의 여섯 주사위와 기존 피해 가산")


func _test_novice_damage() -> void:
	for index: int in [2, 3]:
		for maximum: bool in [false, true]:
			var f: Fixture = _fixture()
			var actor: CombatUnit = f.units[index]
			var target: CombatUnit = f.units[0]
			f.turns.end_turn()
			f.turns.end_turn()
			if index == 3:
				f.turns.end_turn()
			target.reaction_left = 0
			var attack_sides: int = actor.get_ability_sides(actor.get_attack_ability())
			var defense_sides: int = 20 if index == 2 else 8
			f.actions.dice = _dice_for([attack_sides if maximum else 5, 1, 4], [attack_sides, defense_sides, 4])
			_check(await f.actions.attack(actor, target), "풋내기 기본 공격 실행")
			_check(f.actions.last_damage == 5 and target.hit_points == 7
				and not f.actions.last_attack.critical and f.actions.last_damage_rolls == [4],
				"풋내기 피해는 최대 면에서도 주사위 한 번의 1d4+1")


func _test_spiderling_stats_and_damage() -> void:
	for attack_roll: int in [1, 4]:
		var f: Fixture = _fixture()
		var spiderling: CombatUnit = f.units[2]
		spiderling.kind = CombatUnit.Kind.SPIDERLING
		_check(spiderling.get_max_hit_points() == 1 and spiderling.get_defense_bonus() == 0
			and spiderling.get_attack_bonus() == 3 and spiderling.get_damage_bonus() == 1
			and spiderling.get_damage_sides() == 0 and spiderling.get_attack_range() == 1
			and _ability_sides(spiderling) == [4, 8, 4, 4, 4, 4], "새끼 거미의 HP·방어·공격은 모든 막에서 고정")
		_check(spiderling.movement_left == 6, "새끼 거미의 능력치·이동력")
		for action: String in CombatActionRules.NAMES:
			_check(CombatActionRules.belongs_to(spiderling, action) == (action in ["attack", "jump"]),
				"새끼 거미는 기본 공격과 공용 점프만 사용: " + action)
		f.turns.end_turn()
		f.turns.end_turn()
		f.units[0].reaction_left = 0
		f.actions.dice = _dice_for([attack_roll, 1], [4, 20])
		var logs: Array[String] = []
		f.actions.logged.connect(func(line: String) -> void: logs.append(line))
		_check(await f.actions.attack(spiderling, f.units[0]), "새끼 거미 기본 공격 실행")
		_check(f.actions.last_damage == 1 and f.units[0].hit_points == 11
			and f.actions.last_damage_rolls.is_empty(), "새끼 거미는 최솟값·최댓값 명중 모두 피해1이며 피해 주사위를 굴리지 않음")
		_check(logs[-1] == "%s 피해: 1 · HP 11" % f.units[0].get_display_name(),
			"주사위 없는 고정 피해 로그는 빈 괄호 없이 고정값만 표시: " + logs[-1])


func _test_mother_stats_and_damage() -> void:
	var f: Fixture = _fixture()
	var mother: CombatUnit = f.units[2]
	mother.kind = CombatUnit.Kind.MOTHER_SPIDER
	mother.begin_turn()
	_check(mother.get_max_hit_points() == 20 and mother.get_defense_bonus() == 1
		and mother.get_attack_bonus() == 3 and mother.get_damage_bonus() == 2
		and mother.get_damage_sides() == 6 and mother.get_attack_range() == 1
		and mother.movement_left == 4,
		"엄마 거미의 HP·방어·공격·이동력은 모든 막에서 고정")
	_check(_ability_sides(mother) == [8, 6, 4, 4, 6, 8],
		"엄마 거미의 여섯 능력치 주사위")
	_check(CombatActionRules.belongs_to(mother, "opportunity")
		and not CombatActionRules.belongs_to(mother, "parry"), "엄마 거미는 기회 공격을 하고 흘려내기는 하지 않음")
	f.turns.end_turn()
	f.turns.end_turn()
	f.units[0].reaction_left = 0
	f.actions.dice = _dice_for([8, 1, 6], [8, 20, 6])
	_check(await f.actions.attack(mother, f.units[0]) and f.actions.last_damage == 8
		and f.units[0].hit_points == 4, "엄마 거미 기본 공격은 힘 d8+3와 피해1d6+2 적용")


func _test_spawn_spiderling() -> void:
	var expected: Array[Vector2i] = [Vector2i(4, 5), Vector2i(3, 4), Vector2i(4, 3)]
	for choice: int in range(expected.size()):
		var f: Fixture = _fixture()
		var mother: CombatUnit = f.units[2]
		mother.kind = CombatUnit.Kind.MOTHER_SPIDER
		mother.cell = Vector2i(4, 4)
		f.units[0].cell = Vector2i(5, 4)
		f.units[1].cell = Vector2i(1, 4)
		f.units[3].cell = Vector2i(9, 9)
		f.turns.end_turn()
		f.turns.end_turn()
		f.actions.dice = _dice_for([choice + 1], [3])
		_check(f.actions.can_use(mother, "spawn") and f.actions.spawn_spiderling(mother),
			"엄마 거미는 점유 칸을 뺀 무작위 빈 칸에 새끼 낳기")
		var child: CombatUnit = f.units.back()
		_created.append(child)
		_check(f.units.size() == 5 and child.kind == CombatUnit.Kind.SPIDERLING
			and child.hit_points == 1 and child.cell == expected[choice] and not child.is_ally,
			"무작위 선택은 모든 인접 빈 칸을 포함하고 HP1 새끼를 생성")
		_check(mother.action_left == 0 and mother.bonus_action_left == 1
			and mother.movement_left == 4 and f.turns.current_unit == mother
			and f.turns.is_turn_finished(child), "새끼 낳기는 행동만 쓰고 새끼는 생성 라운드 대기")
		_check(f.actions.grid.unit_at(child.cell) == child and not f.actions.can_move(mother, child.cell)
			and f.actions.can_target(f.units[1], child, "attack"),
			"생성한 새끼를 기존 점유 칸·공격 대상 검사에 반영")
		_check(not f.actions.spawn_spiderling(mother) and f.units.size() == 5,
			"행동을 쓴 엄마는 같은 턴에 새끼를 다시 낳지 못함")
	var edge: Fixture = _fixture()
	var mother: CombatUnit = edge.units[2]
	mother.kind = CombatUnit.Kind.MOTHER_SPIDER
	mother.cell = Vector2i.ZERO
	edge.actions.grid.map_size = Vector2i(2, 2)
	edge.units[0].cell = Vector2i(1, 0)
	edge.units[1].cell = Vector2i(0, 1)
	edge.units[3].cell = Vector2i(9, 9)
	edge.turns.end_turn()
	edge.turns.end_turn()
	_check(not edge.actions.can_use(mother, "spawn") and not edge.actions.spawn_spiderling(mother)
		and mother.action_left == 1, "가장자리의 맵 안 인접 칸이 모두 점유되면 생성·비용 소비 없음")
	edge.units[1].cell = Vector2i(1, 1)
	mother.is_stunned = true
	_check(not edge.actions.can_use(mother, "spawn") and not edge.actions.spawn_spiderling(mother),
		"빈 칸이 있어도 기절한 엄마는 새끼 낳기 불가")
	mother.is_stunned = false
	edge.actions.dice = _dice_for([1], [1])
	_check(edge.actions.spawn_spiderling(mother), "빈 칸이 다시 생기면 새끼 낳기 가능")
	var child: CombatUnit = edge.units.back()
	_created.append(child)
	_check(child.cell == Vector2i(0, 1), "가장자리에서는 맵 밖 좌표를 생성 후보에서 제외")


func _test_novice_uses() -> void:
	var f: Fixture = _fixture()
	f.turns.end_turn()
	f.turns.end_turn()
	var barbarian: CombatUnit = f.units[2]
	barbarian.hit_points = 6
	f.actions.dice = _dice_for([10], [10])
	_check(f.actions.use_self(barbarian, "second_wind") and barbarian.hit_points == 12
		and barbarian.bonus_action_left == 0 and barbarian.second_wind_left == 0,
		"야만인 숨 고르기는1d10+1 회복을 최대 HP에 제한하고 보조 행동·횟수 소비")
	barbarian.begin_turn()
	barbarian.hit_points = 6
	_check(not f.actions.can_use(barbarian, "second_wind"), "야만인은 다음 턴에도 숨 고르기 재사용 불가")
	f.turns.end_turn()
	var archer: CombatUnit = f.units[3]
	for use: int in range(2):
		archer.begin_turn()
		_check(f.actions.use_self(archer, "disengage") and archer.disengage_left == 1 - use
			and archer.bonus_action_left == 0 and archer.action_left == 1
			and archer.movement_left == 6 and f.actions.last_attack == null,
			"풋내기 궁수 물러서며 쏘기는2회이며 공격·이동을 실행하지 않음")
	archer.begin_turn()
	_check(not archer.disengaged and not f.actions.can_use(archer, "disengage"),
		"궁수는 다음 턴에 면제를 해제하고 소진한2회를 회복하지 않음")


func _test_movement() -> void:
	var f: Fixture = _fixture()
	for action: String in CombatActionRules.USE_COUNTERS:
		_check(CombatActionRules.USE_COUNTERS[action] in f.units[0],
			"동작 횟수 필드가 유닛에 있음: " + action)
	f.units[2].cell = Vector2i(9, 0)
	var actor: CombatUnit = f.units[0]
	_check(not f.actions.can_move(actor, actor.cell), "같은 칸 이동 거부")
	_check(not f.actions.can_move(actor, Vector2i(-1, 4)), "맵 밖 이동 거부")
	_check(not f.actions.can_move(actor, f.units[2].cell), "점유 칸 이동 거부")
	var reachable: Dictionary[Vector2i, int] = f.actions.reachable_cells(actor)
	var costs_match: bool = not reachable.is_empty()
	for cell: Vector2i in reachable:
		costs_match = costs_match and reachable[cell] == f.actions.grid.path_to(actor, cell).size() \
			and reachable[cell] <= actor.movement_left
	_check(costs_match and not reachable.has(actor.cell) and not reachable.has(f.units[2].cell),
		"도달 칸 비용은 최단 경로 길이이고 남은 이동 안")
	var all_listed: bool = true
	for x: int in range(f.actions.grid.map_size.x):
		for y: int in range(f.actions.grid.map_size.y):
			var path: Array[Vector2i] = f.actions.grid.path_to(actor, Vector2i(x, y))
			if not path.is_empty() and path.size() <= actor.movement_left:
				all_listed = all_listed and reachable.has(Vector2i(x, y))
	_check(all_listed, "남은 이동 안의 경로가 있는 칸은 모두 도달 칸")
	_check(CombatGrid.distance(Vector2i(4, 4), Vector2i(5, 5)) == 2,
		"짝수 행도 사각 대각선 거리는2")
	_check(CombatGrid.distance(Vector2i(4, 5), Vector2i(5, 6)) == 2,
		"홀수 행도 사각 대각선 거리는2이고 인접이 아님")
	_check(f.actions.grid.path_to(actor, Vector2i(5, 5)).size() == 2,
		"대각선은 상하좌우 경로로2칸 이동")
	_check(f.actions.grid.path_to(actor, Vector2i(4, 6)).size() == 2, "4방향 이동 경로와 비용")
	_check(await f.actions.move_to(actor, Vector2i(4, 6)), "첫 이동 실행")
	_check(actor.cell == Vector2i(4, 6) and actor.movement_left == 4, "이동2 소비와 위치 갱신")
	_check(await f.actions.move_to(actor, Vector2i(4, 7)), "이동을 나눠서 실행")
	_check(actor.movement_left == 3 and actor.action_left == 1 and actor.bonus_action_left == 1,
		"나눈 이동은 누적 비용만 쓰며 행동 자원은 유지")
	_check(not f.actions.can_move(actor, Vector2i(0, 0)), "남은 이동을 넘는 경로 거부")
	f.units[1].cell = Vector2i(2, 2)
	_check(f.actions.grid.path_to(actor, Vector2i(2, 2)).is_empty(), "아군 점유 칸도 거부")
	actor.is_stunned = true
	_check(not f.actions.can_move(actor, Vector2i(4, 8)), "기절한 유닛 이동 거부")
	actor.is_stunned = false
	f.turns.select_unit(f.units[1])
	_check(not f.actions.can_move(actor, Vector2i(4, 8)), "현재 유닛이 아닌 이동 거부")


func _test_height_movement() -> void:
	var f: Fixture = _fixture()
	var actor: CombatUnit = f.units[0]
	actor.cell = Vector2i.ZERO
	f.actions.grid.map_size = Vector2i(3, 1)
	f.actions.grid.heights = {Vector2i(1, 0): 1, Vector2i(2, 0): 3}
	_check(f.actions.can_move(actor, Vector2i(1, 0)), "높이 차1의 인접 바닥으로 걷기 가능")
	_check(await f.actions.move_to(actor, Vector2i(1, 0)), "높이1 오르기 실행")
	_check(actor.cell == Vector2i(1, 0) and actor.movement_left == 5,
		"높이1 오르기는 이동1만 소비")
	_check(f.actions.grid.path_to(actor, Vector2i(2, 0)).is_empty()
		and not f.actions.can_move(actor, Vector2i(2, 0)), "높이 차2는 경로와 도달 칸에서 제외")
	_check(not await f.actions.move_to(actor, Vector2i(2, 0))
		and actor.cell == Vector2i(1, 0) and actor.movement_left == 5,
		"높이 차2 걷기 거부는 위치와 자원을 보존")
	f.actions.grid.heights[Vector2i(2, 0)] = 0
	_check(await f.actions.move_to(actor, Vector2i(2, 0))
		and actor.cell == Vector2i(2, 0) and actor.movement_left == 4,
		"높이1 내려가기도 이동1만 소비")
	_check(actor.action_left == 1 and actor.bonus_action_left == 1,
		"오르내리기는 행동과 보조 행동을 보존")


func _test_jump_cost_and_landing() -> void:
	for scenario: Array in [[0, 0, 2, true, 2, 0], [0, 2, 4, true, 4, 0],
		[0, 2, 3, false, 4, 0], [3, 0, 2, true, 2, 2]]:
		var f: Fixture = _fixture()
		var actor: CombatUnit = f.units[0]
		var origin: Vector2i = actor.cell
		var destination: Vector2i = origin + Vector2i(0, 2)
		f.units[2].cell = Vector2i(9, 0)
		f.actions.grid.heights = {origin: scenario[0], destination: scenario[1]}
		actor.movement_left = scenario[2]
		var before: int = actor.hit_points
		var expected_cost: int = scenario[4]
		var cells: Dictionary[Vector2i, int] = f.actions.jump_cells(actor)
		_check(cells.has(destination) == scenario[3], "점프 도달 칸은 평면 거리와 상승 비용을 남은 이동과 비교")
		if scenario[3]:
			_check(cells.get(destination, -1) == expected_cost, "점프 미리보기 비용은 거리2와 양수 상승분의 합")
		f.actions.dice = _dice_for([], [])
		_check(await f.actions.jump_to(actor, destination) == scenario[3], "점프 실행도 같은 비용 조건 적용")
		_check(actor.cell == (destination if scenario[3] else origin)
			and actor.movement_left == (scenario[2] - expected_cost if scenario[3] else scenario[2])
			and actor.bonus_action_left == (0 if scenario[3] else 1) and actor.action_left == 1,
			"점프 성공만 이동과 보조 행동1을 쓰고 행동은 보존")
		_check(actor.hit_points == before - scenario[5] and not f.actions.busy,
			"착지 차3부터 기존 고정 낙하 피해를 주사위 없이 적용하고 잠금 해제")
		_check(not await f.actions.jump_to(actor, origin) and actor.bonus_action_left == (0 if scenario[3] else 1),
			"보조 행동 소진 또는 같은 칸 점프 거부는 자원 보존")
	var denied: Fixture = _fixture()
	var actor: CombatUnit = denied.units[0]
	actor.bonus_action_left = 0
	_check(denied.actions.jump_cells(actor).is_empty() and not denied.actions.can_use(actor, "jump"),
		"보조 행동이 없으면 점프 버튼과 착지 후보 사용 불가")
	actor.bonus_action_left = 1
	_check(denied.actions.can_use(actor, "jump"), "빈 착지 칸과 자원이 있으면 점프 가능")
	actor.is_stunned = true
	_check(denied.actions.jump_cells(actor).is_empty() and not await denied.actions.jump_to(actor, Vector2i(4, 6)),
		"기절한 유닛은 점프 거부")
	_check(CombatActionRules.resource_of("jump") == CombatUnit.TurnResource.BONUS_ACTION
		and CombatActionRules.belongs_to(denied.units[2], "jump"), "점프는 적도 쓸 수 있는 공용 보조 행동")
	var killed: Fixture = _fixture()
	actor = killed.units[0]
	killed.units[2].cell = Vector2i(9, 0)
	killed.actions.grid.heights[actor.cell] = 3
	actor.hit_points = 1
	killed.actions.dice = _dice_for([], [])
	_check(await killed.actions.jump_to(actor, Vector2i(4, 6)) and actor.cell == Vector2i(4, 6)
		and actor.hit_points == 0 and actor.movement_left == 4 and actor.bonus_action_left == 0,
		"착지 낙하 전투 불능은 목적지에서 발생하고 이미 쓴 점프 비용은 복구하지 않음")
	_check(actor not in killed.turns.ordered_units and not actor.visible
		and killed.actions.grid.unit_at(Vector2i(4, 6)) == null, "점프 낙하 전투 불능도 턴·표시·점유 정리")


func _test_jump_opportunity() -> void:
	for scenario: Array in [[false, false], [true, false], [true, true]]:
		var f: Fixture = _fixture()
		_enemy_archer(f)
		var actor: CombatUnit = f.units[3]
		var origin: Vector2i = actor.cell
		var destination: Vector2i = Vector2i(6, 5)
		var asked: Array[String] = []
		if scenario[1]:
			actor.hit_points = 1
		f.actions.reaction_requested.connect(func(kind: String, _prompt: String) -> void:
			asked.append(kind)
			_check(actor.cell == origin and actor.movement_left == 6 and actor.bonus_action_left == 1,
				"점프 기회 공격은 출발과 비용 소비 전에 확인")
			_check(f.actions.busy and f.actions.jump_cells(actor).is_empty(), "점프 반응 대기 중 입력 잠금")
			f.actions.resolve_reaction(scenario[0])
		)
		f.actions.dice = (_dice_for([20, 1, 1], [20, 4, 8]) if scenario[1]
			else _dice_for([1, 4], [20, 4]) if scenario[0] else _dice_for([], []))
		_check(await f.actions.jump_to(actor, destination), "기회 공격을 포함한 점프 시도 처리")
		_check(asked == ["opportunity"]
			and (scenario[1] or f.units[0].reaction_left == (0 if scenario[0] else 1)),
			"출발에서 인접하고 착지에서 벗어나는 적에게 한 번만 기회 공격")
		_check(actor.cell == (origin if scenario[1] else destination)
			and actor.movement_left == (6 if scenario[1] else 4)
			and actor.bonus_action_left == (1 if scenario[1] else 0),
			"기회 공격 전투 불능은 원점·이동·보조 행동 보존, 생존은 착지·비용 소비")
		_check(not f.actions.busy and f.actions.pending_reactor == null, "점프 반응 종료 후 잠금 해제")
	for reactor_cell: Vector2i in [Vector2i(5, 5), Vector2i(4, 5)]:
		var f: Fixture = _fixture()
		var actor: CombatUnit = f.units[0]
		f.units[1].cell = Vector2i.ZERO
		f.units[2].cell = reactor_cell
		f.units[3].cell = Vector2i(9, 9)
		f.actions.dice = _dice_for([], [])
		var destination: Vector2i = Vector2i(6, 4) if reactor_cell.x == 5 else Vector2i(5, 5)
		_check(await f.actions.jump_to(actor, destination) and f.units[2].reaction_left == 1,
			"공중 경로에만 인접하거나 착지에도 인접하면 기회 공격 없음")


func _test_height_adjacency() -> void:
	for scenario: Array in [[1, true, CombatChecks.RollMode.DISADVANTAGE],
		[2, false, CombatChecks.RollMode.NORMAL]]:
		var f: Fixture = _fixture()
		var actor: CombatUnit = f.units[0]
		var target: CombatUnit = f.units[2]
		f.actions.grid.heights[target.cell] = scenario[0]
		_check(f.actions.can_target(actor, target, "attack") == scenario[1]
			and f.actions.grid.attack_preview(actor, target).in_range == scenario[1],
			"근접 공격과 미리보기는 높이 차1까지만 인접")
		actor.kind = CombatUnit.Kind.ARCHER
		_check(f.actions.can_target(actor, target, "attack"),
			"원거리 공격 사거리는 높이 차를 제외한 평면 거리")
		_check(f.actions.grid.attack_preview(actor, target).mode == scenario[2],
			"원거리 인접 불리도 높이 차1까지만 적용")
		actor.kind = CombatUnit.Kind.WARRIOR
		if not scenario[1]:
			var hit_points: int = target.hit_points
			f.actions.dice = _dice_for([], [])
			_check(not await f.actions.attack(actor, target)
				and actor.action_left == 1 and target.hit_points == hit_points,
				"높이 차2 근접 공격 거부는 주사위·행동·대상HP를 보존")
	var ranged: Fixture = _fixture()
	var archer: CombatUnit = ranged.units[0]
	var target: CombatUnit = ranged.units[2]
	archer.kind = CombatUnit.Kind.ARCHER
	archer.cell = Vector2i(0, 0)
	target.cell = Vector2i(6, 0)
	ranged.actions.grid.heights = {Vector2i(3, 0): 20, target.cell: 10}
	_check(ranged.actions.can_target(archer, target, "attack")
		and ranged.actions.grid.attack_preview(archer, target).in_range,
		"높은 대상과 더 높은 중간 바닥이 있어도 평면 거리6 원거리 공격 허용")
	target.cell = Vector2i(7, 0)
	_check(not ranged.actions.can_target(archer, target, "attack")
		and not ranged.actions.grid.attack_preview(archer, target).in_range,
		"높이와 무관하게 평면 거리7 원거리 공격 거부")


func _test_high_ground() -> void:
	var f: Fixture = _fixture()
	var archer: CombatUnit = f.units[0]
	var target: CombatUnit = f.units[2]
	archer.kind = CombatUnit.Kind.ARCHER
	target.cell = Vector2i(7, 4)
	f.units[3].cell = Vector2i(9, 9)
	for height: int in [1, 2, 3]:
		f.actions.grid.heights[archer.cell] = height
		var preview: CombatChecks.AttackPreview = f.actions.grid.attack_preview(archer, target)
		_check(preview.mode == (CombatChecks.RollMode.NORMAL if height == 1 else CombatChecks.RollMode.ADVANTAGE)
			and preview.reasons.has("고지대") == (height >= 2),
			"고지대 유리는 높이 차2부터 원거리 미리보기에 표시")
	f.actions.grid.heights[archer.cell] = 2
	f.actions.dice = _dice_for([3, 15, 1, 1], [20, 20, 6, 6])
	await f.actions.attack(archer, target)
	_check(f.actions.last_attack.mode == CombatChecks.RollMode.ADVANTAGE
		and f.actions.last_attack.rolls == [3, 15] and archer.action_left == 0,
		"실제 고지대 원거리 공격은 두d20중큰값을 쓰고 행동1 소비")
	f.units[3].cell = Vector2i(4, 5)
	f.actions.grid.heights[f.units[3].cell] = 1
	_check(f.actions.grid.attack_preview(archer, target).mode == CombatChecks.RollMode.NORMAL,
		"고지대 유리와 높이포함 인접 적 불리는 상쇄")
	target.is_stunned = true
	_check(f.actions.grid.attack_preview(archer, target).mode == CombatChecks.RollMode.NORMAL,
		"고지대와 기절 유리가 함께 있어도 인접 불리와 기존방식으로 상쇄")
	archer.kind = CombatUnit.Kind.WARRIOR
	target.is_stunned = false
	target.cell = Vector2i(5, 4)
	_check(f.actions.grid.attack_preview(archer, target).mode == CombatChecks.RollMode.NORMAL
		and not f.actions.grid.attack_preview(archer, target).in_range,
		"근접에는 고지대 유리를 주지 않고 높이 차2 공격도 계속 거부")


func _test_fall_damage() -> void:
	for scenario: Array in [[2, 7], [3, 5], [4, 3]]:
		var f: Fixture = _fixture()
		var actor: CombatUnit = f.units[0]
		var target: CombatUnit = f.units[2]
		var drop: int = scenario[0]
		f.actions.grid.heights = {actor.cell: drop - 1, target.cell: drop}
		target.is_stunned = true
		target.hit_points = 7
		f.actions.dice = _dice_for([], [])
		_check(f.actions.shove(actor, target) and target.cell == Vector2i(6, 4)
			and target.hit_points == scenario[1] and actor.bonus_action_left == 0,
			"밀치기 낙하 차2무피해·차3최대HP12의15%올림2·차4올림4, 주사위 없음")
		_check(f.hits.size() == (0 if drop == 2 else 1), "실제 낙하 피해만 기존 피해 신호를 보냄")
	var killed: Fixture = _fixture()
	var target: CombatUnit = killed.units[2]
	killed.actions.grid.heights = {killed.units[0].cell: 2, target.cell: 3}
	target.is_stunned = true
	target.hit_points = 1
	killed.units[0].marked_target = target
	killed.units[1].marked_target = target
	killed.actions.dice = _dice_for([], [])
	_check(killed.actions.shove(killed.units[0], target) and target.hit_points == 0,
		"낙하 피해로 HP0이면 전투 불능")
	_check(target not in killed.turns.ordered_units and not target.visible
		and killed.actions.grid.unit_at(Vector2i(6, 4)) == null
		and killed.units[0].marked_target == null and killed.units[1].marked_target == null,
		"낙하 전투 불능은 턴·표식·표시·점유를 기존 방식으로 정리")
	var pulled: Fixture = _fixture()
	var boss: CombatUnit = pulled.units[2]
	boss.kind = CombatUnit.Kind.SCRAP_ROBOT_2000
	boss.cell = Vector2i(4, 4)
	boss.begin_turn()
	pulled.turns.current_unit = boss
	target = pulled.units[0]
	target.cell = Vector2i(7, 4)
	target.hit_points = 7
	pulled.units[3].cell = Vector2i(9, 9)
	pulled.actions.grid.heights[target.cell] = 3
	pulled.actions.dice = _dice_for([12, 1], [12, 20])
	_check(pulled.actions.pull(boss, target)
		and target.cell == Vector2i(5, 4) and target.hit_points == 5,
		"끌기 착지에도 같은 최대HP기준 고정 낙하 피해 적용")
	_check(boss.action_left == 0 and boss.pull_cooldown == 2,
		"끌기 대결 외 낙하 주사위·내성 없이 기존 행동과 대기턴만 소비")


func _test_pit_movement() -> void:
	var f: Fixture = _fixture()
	var actor: CombatUnit = f.units[0]
	actor.cell = Vector2i.ZERO
	f.actions.grid.map_size = Vector2i(3, 1)
	f.actions.grid.pits = [Vector2i(1, 0)]
	f.actions.dice = _dice_for([], [])
	_check(not f.actions.can_move(actor, Vector2i(1, 0))
		and not f.actions.can_move(actor, Vector2i(2, 0))
		and f.actions.reachable_cells(actor).is_empty(),
		"낭떠러지는 걷기 목적지나 통과 경로가 될 수 없음")
	_check(not await f.actions.move_to(actor, Vector2i(1, 0))
		and actor.cell == Vector2i.ZERO and actor.movement_left == 6,
		"낭떠러지 걷기 거부는 위치·이동력·주사위를 보존")


func _test_pit_spawn() -> void:
	for available: bool in [false, true]:
		var f: Fixture = _fixture()
		var mother: CombatUnit = f.units[2]
		mother.kind = CombatUnit.Kind.MOTHER_SPIDER
		mother.cell = Vector2i.ZERO
		f.units[0].cell = Vector2i(9, 9)
		f.units[1].cell = Vector2i(9, 8)
		f.units[3].cell = Vector2i(8, 8)
		f.actions.grid.map_size = Vector2i(2, 2)
		f.actions.grid.pits = [Vector2i(1, 0)]
		if not available:
			f.actions.grid.pits.append(Vector2i(0, 1))
		f.turns.end_turn()
		f.turns.end_turn()
		f.actions.dice = _dice_for([1], [1]) if available else _dice_for([], [])
		_check(f.actions.can_use(mother, "spawn") == available
			and f.actions.spawn_spiderling(mother) == available,
			"소환 후보에서 낭떠러지를 제외하고 빈 바닥이 없으면 실행 거부")
		if f.units.size() > 4:
			_created.append(f.units.back())
		_check(f.units.size() == (5 if available else 4)
			and mother.action_left == (0 if available else 1),
			"낭떠러지뿐이면 소환·행동·주사위를 보존")
		if available:
			_check(f.units.back().cell == Vector2i(0, 1), "낭떠러지 옆의 유일한 빈 바닥에만 소환")


func _test_pit_forced_movement() -> void:
	for ally: bool in [false, true]:
		for height: int in [0, -2]:
			var f: Fixture = _fixture()
			var actor: CombatUnit = f.units[0]
			var target: CombatUnit = f.units[1 if ally else 2]
			if ally:
				f.units[2].cell = Vector2i(9, 9)
			target.cell = Vector2i(5, 4)
			target.is_stunned = not ally
			f.actions.grid.heights = {actor.cell: height, target.cell: height + 1}
			f.actions.grid.pits = [Vector2i(6, 4)]
			f.units[3].marked_target = target
			f.actions.dice = _dice_for([], [])
			_check(f.actions.shove(actor, target) and target.hit_points == 0
				and target.cell == Vector2i(6, 4) and actor.bonus_action_left == 0,
				"아군·적 모두 낭떠러지에 밀리면 바닥 높이 비교·낙하 주사위 없이 즉시 전투 불능")
			_check(target not in f.turns.ordered_units and not target.visible
				and f.actions.grid.unit_at(Vector2i(6, 4)) == null and f.units[3].marked_target == null,
				"낙사도 턴·점유·표식·표시를 함께 정리")
			_check(f.hits.size() == 1, "낙사도 HP 감소라 타격음을 한 번 재생")
	var pulled: Fixture = _fixture()
	var boss: CombatUnit = pulled.units[2]
	boss.kind = CombatUnit.Kind.SCRAP_ROBOT_2000
	boss.cell = Vector2i(4, 4)
	boss.begin_turn()
	pulled.turns.current_unit = boss
	var target: CombatUnit = pulled.units[0]
	target.cell = Vector2i(7, 4)
	pulled.units[3].cell = Vector2i(9, 9)
	pulled.actions.grid.heights = {boss.cell: -2, Vector2i(4, 5): -1}
	pulled.actions.grid.pits = [Vector2i(5, 4)]
	pulled.actions.dice = _dice_for([12, 1], [12, 20])
	_check(pulled.actions.grid.pull_cells(boss, target) == [Vector2i(5, 4)]
		and pulled.actions.pull(boss, target) and target.hit_points == 0,
		"끌기도 시전자 옆 낭떠러지의 없는 바닥 높이와 비교하지 않고 즉시 낙사")
	_check(pulled.hits.size() == 1, "끌기 낙사도 타격음을 한 번 재생")
	var last: Fixture = _fixture()
	last.actions.incapacitate(last.units[3])
	last.units[2].is_stunned = true
	last.actions.grid.pits = [Vector2i(6, 4)]
	last.actions.dice = _dice_for([], [])
	_check(last.actions.shove(last.units[0], last.units[2])
		and last.actions.is_over() and last.actions.is_victory(),
		"마지막 적의 낙사는 기존 전투 승리 결과로 연결")


func _test_forced_move_landing_preview() -> void:
	var f: Fixture = _fixture()
	var target: CombatUnit = f.units[2]
	target.is_stunned = true
	_check(f.actions.shove_landing(target, Vector2i(6, 4)).is_empty(), "평지 밀치기 미리보기는 착지 결과를 붙이지 않는다")
	f.actions.grid.pits = [Vector2i(6, 4)]
	f.actions.dice = _dice_for([], [])
	_check(f.actions.shove_landing(target, Vector2i(6, 4)) == "낙사"
		and f.actions.shove(f.units[0], target) and target.hit_points == 0,
		"낭떠러지 옆 밀치기 미리보기는 실제 결과와 같은 낙사를 보인다")
	for burning: bool in [false, true]:
		f = _fixture()
		target = f.units[2]
		target.is_stunned = true
		f.actions.grid.heights = {f.units[0].cell: 3, target.cell: 3}
		if burning:
			f.actions.grid.water_cells = [Vector2i(6, 4)]
			f.actions.apply_status(f.units[0], target, "burn")
		var note: String = f.actions.shove_landing(target, Vector2i(6, 4))
		var before: int = target.hit_points
		f.actions.dice = _dice_for([], [])
		_check(f.actions.shove(f.units[0], target) and before > target.hit_points
			and note == ("물: 화상 해제 · " if burning else "") + "낙하 피해 %d" % (before - target.hit_points)
			and target.get_status_count("burn") == 0,
			"높이 차3 밀치기 미리보기는 실제 낙하 피해와 물의 화상 해제를 보인다")
	f = _fixture()
	target = f.units[2]
	target.cell = Vector2i(4, 6)
	f.actions.grid.pits = [Vector2i(4, 7)]
	var rock: CombatGrid.Prop = f.actions.create_prop(Vector2i(4, 5), "rock")
	var roll: CombatActions.RockRoll = f.actions.preview_rock(f.units[0], rock)
	f.actions.dice = _dice_for([], [])
	_check(f.actions.rock_landing(roll, target) == "낙사"
		and f.actions.attack_prop(f.units[0], rock) and target.hit_points == 0,
		"바위가 대상을 낭떠러지로 밀면 미리보기에 실제와 같은 낙사를 보인다")
	f = _fixture()
	target = f.units[2]
	target.cell = Vector2i(4, 6)
	f.actions.grid.pits = [Vector2i(4, 8)]
	rock = f.actions.create_prop(Vector2i(4, 5), "rock")
	roll = f.actions.preview_rock(f.units[0], rock)
	f.actions.dice = _dice_for([], [])
	_check(f.actions.rock_landing(roll, target) == "낙사"
		and f.actions.attack_prop(f.units[0], rock) and target.hit_points == 0 and target.cell == Vector2i(4, 8),
		"바위의 두 번째 밀기가 낭떠러지로 떨어뜨려도 미리보기에 낙사를 보인다")
	f = _fixture()
	target = f.units[2]
	target.cell = Vector2i(4, 6)
	for cell: Vector2i in [f.units[0].cell, Vector2i(4, 5), target.cell]:
		f.actions.grid.heights[cell] = 3
	rock = f.actions.create_prop(Vector2i(4, 5), "rock")
	roll = f.actions.preview_rock(f.units[0], rock)
	var before: int = target.hit_points
	f.actions.dice = _dice_for([], [])
	_check(f.actions.attack_prop(f.units[0], rock) and before - 4 > target.hit_points
		and f.actions.rock_landing(roll, target) == "낙하 피해 %d" % (before - 4 - target.hit_points),
		"바위 밀기 미리보기는 충돌 피해와 별도로 실제 낙하 피해를 보인다")


func _test_height_opportunity() -> void:
	for scenario: Array in [[1, 1], [2, 0]]:
		var f: Fixture = _fixture()
		_enemy_archer(f)
		var reactor: CombatUnit = f.units[0]
		var actor: CombatUnit = f.units[3]
		f.actions.grid.heights[reactor.cell] = scenario[0]
		f.actions.dice = _dice_for([], [])
		var prompts: Array[int] = [0]
		f.actions.reaction_requested.connect(func(kind: String, _prompt: String) -> void:
			if kind == "opportunity":
				prompts[0] += 1
			f.actions.resolve_reaction(false)
		)
		_check(await f.actions.move_to(actor, Vector2i(6, 4)), "높이가 다른 적 옆에서 실제 걷기")
		_check(prompts[0] == scenario[1], "기회 공격도 출발 높이 차1까지만 인접")
		_check(actor.cell == Vector2i(6, 4) and actor.movement_left == 5
			and reactor.reaction_left == 1, "기회 공격을 넘기거나 안 물으면 반응을 보존하고 이동1 소비")


func _test_height_shove() -> void:
	for scenario: Array in [[2, false, Vector2i(5, 4), 1],
		[1, true, Vector2i(6, 4), 0], [0, true, Vector2i(6, 4), 0]]:
		var f: Fixture = _fixture()
		var actor: CombatUnit = f.units[0]
		var target: CombatUnit = f.units[2]
		target.is_stunned = true
		f.actions.grid.heights = {actor.cell: 1, target.cell: 1, Vector2i(6, 4): scenario[0]}
		f.actions.dice = _dice_for([], [])
		_check(f.actions.can_target(actor, target, "shove") == scenario[1],
			"밀치기는 대상보다 같은 높이나 낮은 착지 칸만 선택")
		_check(f.actions.shove(actor, target) == scenario[1], "높이를 확인한 밀치기 실제 실행")
		_check(target.cell == scenario[2] and actor.bonus_action_left == scenario[3],
			"밀치기 성공만 이동·보조 행동을 소비하고 거부는 보존")
	var separated: Fixture = _fixture()
	separated.actions.grid.heights[separated.units[2].cell] = 2
	_check(not separated.actions.can_target(separated.units[0], separated.units[2], "shove"),
		"밀치기 대상도 높이 차2이면 인접하지 않음")


func _test_height_pull() -> void:
	for available: bool in [true, false]:
		var f: Fixture = _fixture()
		var boss: CombatUnit = f.units[2]
		boss.kind = CombatUnit.Kind.SCRAP_ROBOT_2000
		boss.hit_points = 45
		boss.cell = Vector2i(4, 4)
		boss.begin_turn()
		f.turns.current_unit = boss
		f.units[0].cell = Vector2i(1, 1)
		var target: CombatUnit = f.units[1]
		target.cell = Vector2i(7, 4)
		f.units[3].cell = Vector2i(9, 9)
		f.actions.grid.heights = {boss.cell: 3, target.cell: 2,
			Vector2i(5, 4): 1, Vector2i(4, 5): 2 if available else 3,
			Vector2i(3, 4): 4, Vector2i(4, 3): 3}
		var expected: Array[Vector2i] = []
		if available:
			expected.append(Vector2i(4, 5))
		_check(f.actions.grid.pull_cells(boss, target) == expected
			and f.actions.can_target(boss, target, "pull") == available,
			"끌기는 보스에 높이 포함 인접하고 대상보다 높지 않은 칸만 선택")
		f.actions.dice = _dice_for([12, 1], [12, 8]) if available else _dice_for([], [])
		_check(f.actions.pull(boss, target) == available, "높이 착지 조건에 따른 실제 만능팔 실행")
		_check(target.cell == (Vector2i(4, 5) if available else Vector2i(7, 4))
			and boss.action_left == (0 if available else 1)
			and boss.pull_cooldown == (2 if available else 0) and target.hit_points == 14,
			"끌기 성공만 행동·재사용 대기를 소비하고 거부는 보존")


func _test_height_spawn() -> void:
	for available: bool in [true, false]:
		var f: Fixture = _fixture()
		var mother: CombatUnit = f.units[2]
		mother.kind = CombatUnit.Kind.MOTHER_SPIDER
		mother.cell = Vector2i.ZERO
		f.units[0].cell = Vector2i(9, 9)
		f.units[1].cell = Vector2i(9, 8)
		f.units[3].cell = Vector2i(8, 8)
		f.actions.grid.map_size = Vector2i(2, 2)
		f.actions.grid.heights = {Vector2i(1, 0): 2, Vector2i(0, 1): 1 if available else 2}
		f.turns.end_turn()
		f.turns.end_turn()
		f.actions.dice = _dice_for([1], [1]) if available else _dice_for([], [])
		_check(f.actions.can_use(mother, "spawn") == available,
			"엄마 높이 차1의 빈 인접 바닥이 있을 때만 새끼 낳기 가능")
		_check(f.actions.spawn_spiderling(mother) == available, "높이 인접 조건에 따른 실제 새끼 낳기")
		if f.units.size() > 4:
			_created.append(f.units.back())
		_check(f.units.size() == (5 if available else 4)
			and mother.action_left == (0 if available else 1),
			"출생 칸이 없으면 생성과 행동 소비를 모두 거부")
		if available:
			_check(f.units.back().cell == Vector2i(0, 1) and f.turns.is_turn_finished(f.units.back()),
				"높이1 인접 칸에서 태어난 새끼는 생성 라운드에 대기")


func _test_ally_shove() -> void:
	var f: Fixture = _fixture()
	var actor: CombatUnit = f.units[0]
	var target: CombatUnit = f.units[1]
	target.cell = Vector2i(5, 4)
	f.units[2].cell = Vector2i(9, 0)
	f.actions.grid.heights = {actor.cell: 1, target.cell: 1}
	f.actions.dice = _dice_for([], [])
	_check(f.actions.can_target(actor, target, "shove"), "인접 아군도 밀치기 대상으로 선택 가능")
	_check(f.actions.shove(actor, target), "기절하지 않은 아군을 대결 없이 밀치기")
	_check(target.cell == Vector2i(6, 4) and actor.bonus_action_left == 0
		and actor.action_left == 1 and target.hit_points == 14 and target.movement_left == 6
		and target.bonus_action_left == 1 and target.reaction_left == 1,
		"아군 밀치기는 밀친 유닛의 보조 행동만 쓰고 대상 자원을 보존")


func _test_grid_queries() -> void:
	var f: Fixture = _fixture()
	var grid: CombatGrid = f.actions.grid
	grid.map_size = Vector2i(3, 3)
	var actor: CombatUnit = f.units[0]
	actor.cell = Vector2i.ZERO
	f.units[1].cell = Vector2i(2, 2)
	f.units[2].cell = Vector2i(2, 1)
	f.units[3].cell = Vector2i(2, 0)
	var destination: Vector2i = Vector2i(1, 1)
	var first_path: Array[Vector2i] = [Vector2i(1, 0), destination]
	_check(grid.path_to(actor, destination) == first_path, "동률 경로는 기존 이웃 탐색 순서를 유지")
	var blocker: CombatUnit = CombatUnit.new()
	blocker.cell = Vector2i(1, 0)
	_created.append(blocker)
	f.units.append(blocker)
	_check(grid.unit_at(blocker.cell) == blocker, "초기화 뒤 추가한 유닛도 같은 전투판에서 조회")
	var detour: Array[Vector2i] = [Vector2i(0, 1), destination]
	_check(grid.path_to(actor, destination) == detour
		and grid.reachable_cells(actor)[destination] == 2, "실시간 점유 변경을 경로·도달 비용에 함께 반영")
	blocker.hit_points = 0
	_check(grid.path_to(actor, destination) == first_path, "전투 불능은 점유 캐시 갱신 없이 경로에 반영")
	f.units.erase(blocker)
	var replacement: Array[CombatUnit] = [actor]
	f.actions.initialize(replacement, f.turns)
	_check(grid.unit_at(f.units[2].cell) == null and is_same(f.actions.units, replacement),
		"스테이지 교체는 새 유닛 배열 하나를 실행·전투판이 공유")
	actor.movement_left = 0
	_check(grid.reachable_cells(actor).is_empty() and not f.actions.can_move(actor, destination),
		"이동력이 없으면 도달 칸과 실행 모두 거부")
	_check(grid.path_to(null, destination).is_empty() and grid.reachable_cells(null).is_empty(),
		"유닛 없는 공간 질의는 빈 결과")


func _test_square_rules() -> void:
	# 행의 홀짝과 관계없이 상하좌우 이웃과 그 방향의 다음 칸을 직접 정한다.
	var adjacent_rows: Array[Array] = [
		[Vector2i(5, 4), Vector2i(4, 5), Vector2i(3, 4), Vector2i(4, 3)],
		[Vector2i(5, 5), Vector2i(4, 6), Vector2i(3, 5), Vector2i(4, 4)]
	]
	var pushed_rows: Array[Array] = [
		[Vector2i(6, 4), Vector2i(4, 6), Vector2i(2, 4), Vector2i(4, 2)],
		[Vector2i(6, 5), Vector2i(4, 7), Vector2i(2, 5), Vector2i(4, 3)]
	]
	for row: int in range(2):
		var f: Fixture = _fixture()
		var actor: CombatUnit = f.units[0]
		var target: CombatUnit = f.units[2]
		actor.cell = Vector2i(4, 4 + row)
		f.units[1].cell = Vector2i(0, 9)
		f.units[3].cell = Vector2i(9, 9)
		for index: int in range(4):
			var neighbor: Vector2i = adjacent_rows[row][index]
			var pushed: Vector2i = pushed_rows[row][index]
			target.cell = Vector2i(9, 0)
			_check(f.actions.grid.path_to(actor, neighbor).size() == 1,
				"두 행의4방향 이웃은 이동 비용1")
			target.cell = neighbor
			_check(f.actions.can_target(actor, target, "attack"), "4방향 근접 공격 가능")
			actor.kind = CombatUnit.Kind.ARCHER
			_check(f.actions.grid.attack_preview(actor, target).mode == CombatChecks.RollMode.DISADVANTAGE,
				"4방향 적은 원거리 불리")
			actor.kind = CombatUnit.Kind.WARRIOR
			_check(f.actions.grid.push_destination(actor.cell, target.cell) == pushed, "행이 바뀌어도 같은 사각 방향으로 밀치기")
			f.units[3].cell = pushed
			_check(not f.actions.can_target(actor, target, "shove"), "밀려날 칸 점유 시 선택 불가")
			f.units[3].cell = Vector2i(9, 9)
			target.is_stunned = true
			actor.bonus_action_left = 1
			_check(f.actions.shove(actor, target) and target.cell == pushed, "4방향 밀치기 실제 위치 일치")
			actor.bonus_action_left = 1
			target.is_stunned = false
			var opportunity: Fixture = _fixture()
			_enemy_archer(opportunity)
			opportunity.units[0].cell = actor.cell
			opportunity.units[1].cell = Vector2i(0, 9)
			opportunity.units[2].cell = Vector2i(9, 0)
			opportunity.units[3].cell = neighbor
			var prompts: Array[int] = [0]
			opportunity.actions.reaction_requested.connect(func(kind: String, _prompt: String) -> void:
				if kind == "opportunity":
					prompts[0] += 1
				opportunity.actions.resolve_reaction(false)
			)
			await opportunity.actions.move_to(opportunity.units[3], pushed)
			_check(prompts[0] == 1, "4방향 인접을 벗어나면 기회 공격")
	var edge: Fixture = _fixture()
	edge.units[0].cell = Vector2i(0, 1)
	edge.units[2].cell = Vector2i(0, 0)
	_check(not edge.actions.can_target(edge.units[0], edge.units[2], "shove"), "밀려날 칸이 맵 밖이면 선택 불가")
	var ranged: Fixture = _fixture()
	ranged.units[0].kind = CombatUnit.Kind.ARCHER
	ranged.units[0].cell = Vector2i(0, 0)
	ranged.units[2].cell = Vector2i(3, 3)
	_check(ranged.actions.can_target(ranged.units[0], ranged.units[2], "attack"), "평면 거리6 공격 가능")
	ranged.units[2].cell = Vector2i(4, 3)
	_check(not ranged.actions.can_target(ranged.units[0], ranged.units[2], "attack"), "평면 거리7 공격 불가")
	_check(ranged.actions.grid.path_to(ranged.units[0], Vector2i(3, 3)).size() == 6
		and ranged.actions.can_move(ranged.units[0], Vector2i(3, 3))
		and not ranged.actions.can_move(ranged.units[0], Vector2i(4, 3)), "이동력6 경계도 사각 최단 경로 기준")


func _test_attacks() -> void:
	var f: Fixture = _fixture()
	var actor: CombatUnit = f.units[0]
	var target: CombatUnit = f.units[2]
	target.parry_left = 0
	f.actions.dice = _dice_for([1, 1], [20, 10])
	_check(await f.actions.attack(actor, target), "빗나간 공격도 실행 성공")
	_check(actor.action_left == 0 and target.hit_points == 12 and f.actions.last_damage == 0,
		"동점 공격은 행동을 소비하고 피해 없음")
	_check(f.hits.is_empty(), "빗나감은 타격음을 요청하지 않음")
	_check(not await f.actions.attack(actor, target), "행동 없는 재공격 거부")
	actor.action_left = 1
	f.actions.dice = _dice_for([20, 10, 1], [20, 10, 8])
	_check(await f.actions.attack(actor, target), "최댓값 공격")
	_check(not f.actions.last_attack.critical and f.actions.last_damage_rolls == [1]
		and f.actions.last_attack.rolls == [20] and f.actions.last_attack.defender_roll == 10,
		"최댓값도 치명타 없이 무기 주사위 한 개")
	var total: int = 3
	for rolled: int in f.actions.last_damage_rolls:
		total += rolled
	_check(f.actions.last_damage == total, "기존 피해 가산3은 최댓값에서도 한 번만 더함")
	_check(target.hit_points == maxi(0, 12 - total), "피해와 HP0 하한")
	_check(f.hits.size() == 1, "최댓값 명중 타격음은 한 번")
	var killed: Fixture = _fixture()
	killed.units[2].hit_points = 1
	killed.units[2].parry_left = 0
	killed.units[1].marked_target = killed.units[2]
	killed.actions.dice = _dice_for([11, 1, 1], [20, 10, 8])
	await killed.actions.attack(killed.units[0], killed.units[2])
	_check(killed.units[2].hit_points == 0 and killed.units[2] not in killed.turns.ordered_units,
		"HP0은 즉시 전투 불능과 턴 순서 제거")
	_check(killed.units[1].marked_target == null, "전투 불능 대상의 표식 제거")
	_check(not killed.units[2].visible and not killed.actions.is_marked(killed.units[2]),
		"전투 불능 대상은 숨기고 표식 표시도 해제")
	_check(not await killed.actions.attack(killed.units[0], killed.units[2]), "전투 불능 대상 재공격 거부")
	_check(killed.hits.size() == 1, "전투 불능 타격도 한 번 재생하고 거부한 공격은 무음")
	f.actions._damage(target, 0)
	_check(f.hits.size() == 1, "HP가 줄지 않으면 타격음을 요청하지 않음")
	var healed: Array = []
	f.actions.healed.connect(func(unit: CombatUnit, amount: int) -> void: healed.append([unit, amount]))
	f.actions.feedback.connect(func(unit: CombatUnit, text: String) -> void: healed.append([unit, text]))
	actor.hit_points -= 1
	f.actions._heal(actor, 1, "회복 검사")
	_check(f.hits.size() == 1, "회복은 타격음을 요청하지 않음")
	_check(healed == [[actor, 1]], "회복은 일반 팝업 없이 실제 회복량만 보냄: %s" % str(healed))


func _test_archer_balance() -> void:
	for actor_index: int in [1, 3]:
		for marked: bool in [false, true]:
			if actor_index == 3 and marked:
				continue
			for maximum: bool in [false, true]:
				var f: Fixture = _fixture()
				var actor: CombatUnit = f.units[actor_index]
				var target: CombatUnit = f.units[3 if actor_index == 1 else 1]
				if actor_index == 1:
					f.turns.select_unit(actor)
				else:
					_enemy_archer(f)
					actor.cell = Vector2i(7, 4)
					f.units[0].cell = Vector2i(9, 9)
					target.cell = Vector2i(3, 4)
				var attack_sides: int = 20 if actor.is_ally else 10
				var attack_roll: int = attack_sides if maximum else 5
				if not marked and not maximum:
					_check(actor.hit_points == 14 and actor.get_max_hit_points() == 14,
						"아군과 적 궁수의 시작·최대 HP는14")
					_check(actor.get_ability_sides(CombatUnit.Ability.DEXTERITY) == attack_sides
						and actor.get_attack_bonus() == 0,
						"아군 민첩d20·풋내기d10은 피해 고정값과 별개")
				if marked:
					_check(f.actions.mark(actor, target), "궁수 피해 검사에서 표식 사용")
				var logs: Array[String] = []
				f.actions.logged.connect(func(line: String) -> void: logs.append(line))
				var rolls: Array[int] = [attack_roll, 1, 4]
				var sides: Array[int] = [attack_sides, 10 if actor.is_ally else 20, 6 if actor.is_ally else 4]
				if marked:
					rolls.append(2)
					sides.append(6)
				f.actions.dice = _dice_for(rolls, sides)
				_check(await f.actions.attack(actor, target), "양쪽 궁수 기본 공격 실행")
				_check(f.hits.size() == 1, "아군·적 궁수와 표식 공격도 타격음 한 번")
				var count: int = 2 if marked else 1
				var total: int = 1
				for rolled: int in f.actions.last_damage_rolls:
					total += rolled
				_check(f.actions.last_damage_rolls.size() == count and f.actions.last_damage == total
					and target.hit_points == maxi(0, 14 - total),
					"궁수 피해는 무기·표식 주사위에 고정값1을 한 번만 더함")
				_check(" + 1 = %d · HP %d" % [total, target.hit_points] in "\n".join(logs),
					"궁수 피해 로그도 고정값1과 실제 HP를 표시")


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
	_check(warrior.second_wind_left == 0, "자기 턴은 막당 횟수를 회복하지 않음")
	warrior.action_left = 0
	_check(f.actions.use_self(warrior, "surge"), "몰아치기 사용")
	_check(warrior.action_left == 1 and warrior.bonus_action_left == 0 and warrior.surge_left == 0,
		"몰아치기는 행동을 최대1로 채움")
	warrior.begin_turn()
	warrior.hit_points = 1
	warrior.potion_left = 1
	f.actions.dice = _dice_for([4, 4], [4, 4])
	_check(f.actions.use_self(warrior, "potion"), "물약 사용")
	_check(warrior.hit_points == 11 and warrior.potion_left == 0, "보유 물약 소비와2d4+2 회복")
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
	f.actions.dice = _dice_for([20, 1], [20, 10])
	_check(f.actions.shove(actor, target), "밀치기 실행")
	_check(target.cell == Vector2i(6, 4) and actor.bonus_action_left == 0, "대결 승리 시1칸 이동과 자원 소비")
	_check(target.reaction_left == 1, "강제 이동은 기회 공격 없음")
	actor.bonus_action_left = 1
	target.cell = Vector2i(5, 4)
	f.units[3].cell = Vector2i(6, 4)
	_check(not f.actions.shove(actor, target) and actor.bonus_action_left == 1, "막힌 밀림 칸은 선택·소비 거부")
	f.units[3].cell = Vector2i(7, 4)
	f.actions.dice = _dice_for([10, 10], [20, 10])
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


func _test_stun_landing_incapacitation() -> void:
	for pit: bool in [false, true]:
		var f: Fixture = _fixture()
		var source: CombatUnit = f.units[1]
		var target: CombatUnit = f.units[2]
		f.turns.select_unit(source)
		target.reaction_left = 0
		f.actions.dice = _dice_for([11, 1, 1], [20, 6, 6])
		await f.actions.attack(source, target, true)
		if pit:
			f.actions.grid.pits.append(Vector2i(2, 4))
			f.turns.select_unit(f.units[0])
			_check(f.actions.shove(f.units[0], source), "아군 시전자를 낭떠러지로 밀치기")
		else:
			f.actions.grid.heights[source.cell] = 9
			_check(await f.actions.jump_to(source, Vector2i(3, 5)), "충격 화살 뒤 치명적인 낙하 점프")
		_check(source.hit_points == 0 and not source.visible and not target.is_stunned,
			"시전자의 실제 착지 전투 불능은 기절을 즉시 해제: " + str(pit))


func _test_finished_stun_removal() -> void:
	var f: Fixture = _fixture()
	var source: CombatUnit = f.units[1]
	var target: CombatUnit = f.units[2]
	f.turns.select_unit(source)
	target.reaction_left = 0
	f.actions.dice = _dice_for([11, 1, 1], [20, 6, 6])
	await f.actions.attack(source, target, true)
	f.turns.end_turn()
	f.turns.end_turn()
	_check(f.turns.is_turn_finished(target) and f.turns.current_unit == f.units[3],
		"시전자 탈락 전 이미 기절 대상의 차례를 건너뜀")
	f.actions.incapacitate(source)
	_check(not target.is_stunned and f.turns.is_turn_finished(target)
		and f.turns.current_unit == f.units[3], "기절 해제는 이미 완료한 차례를 소급하지 않음")


func _test_stun_reapplication() -> void:
	var f: Fixture = _fixture()
	var first: CombatUnit = f.units[1]
	var latest: CombatUnit = f.units[0]
	var target: CombatUnit = f.units[2]
	latest.kind = CombatUnit.Kind.ARCHER
	latest.cell = Vector2i(2, 4)
	f.turns.select_unit(first)
	target.reaction_left = 0
	f.actions.dice = _dice_for([11, 1, 1], [20, 6, 6])
	_check(await f.actions.attack(first, target, true) and target.is_stunned and target.hit_points > 0,
		"첫 시전자의 충격 화살")
	f.turns.select_unit(latest)
	f.actions.dice = _dice_for([11, 11, 1, 1], [20, 20, 6, 6])
	_check(await f.actions.attack(latest, target, true) and target.is_stunned and target.hit_points > 0,
		"기절 대상 재적용은 중첩 없이 최신 시전자로 갱신")
	f.actions.incapacitate(first)
	_check(target.is_stunned, "이전 시전자 전투 불능은 갱신된 기절을 해제하지 않음")
	f.turns.end_turn()
	_check(target.is_stunned and f.turns.is_turn_finished(target),
		"갱신된 기절도 대상 차례 종료로 풀리지 않음")
	f.turns.end_turn()
	_check(not target.is_stunned and f.turns.current_unit == latest,
		"최신 시전자의 다음 실제 턴 시작에 갱신된 기절 해제")


func _test_burn_turn_start() -> void:
	var f: Fixture = _fixture()
	var source: CombatUnit = f.units[1]
	var target: CombatUnit = f.units[2]
	_check(f.actions.apply_status(source, target, "burn"), "살아 있는 전투 유닛에게 화상 부여")
	_check(target.hit_points == 12, "화상 부여 순간에는 피해 없음")
	f.actions.dice = _dice_for([3], [4])
	f.turns.end_turn()
	f.turns.end_turn()
	_check(f.turns.current_unit == target and target.hit_points == 9,
		"대상 실제 턴 시작에 화상1중첩은 d4 피해 한 번")
	f.turns.select_unit(f.units[3])
	f.turns.select_unit(target)
	_check(target.hit_points == 9, "묶음 재선택은 화상 틱을 반복하지 않음")


func _test_burn_caster_duration() -> void:
	var f: Fixture = _fixture()
	var source: CombatUnit = f.units[1]
	var target: CombatUnit = f.units[2]
	f.turns.select_unit(source)
	f.actions.apply_status(source, target, "burn")
	f.actions.dice = _dice_for([3, 2], [4, 4])
	for expected_hp: int in [9, 7, 7]:
		f.turns.end_turn()
		f.turns.end_turn()
		_check(f.turns.current_unit == target and target.hit_points == expected_hp,
			"화상은 대상 차례가 아니라 시전자 두 번째 시작에 만료: HP" + str(expected_hp))
		f.turns.end_turn()
		f.turns.end_turn()
		f.turns.select_unit(source)


func _test_burn_stack_limit() -> void:
	var f: Fixture = _fixture()
	var target: CombatUnit = f.units[2]
	f.turns.select_unit(f.units[1])
	_check(f.actions.apply_status(f.units[1], target, "burn"), "첫 화상 중첩")
	_check(f.actions.apply_status(f.units[0], target, "burn"), "다른 시전자의 화상도 같은 상한에 포함")
	_check(f.actions.apply_status(f.units[1], target, "burn"), "세 번째 화상 중첩")
	_check(not f.actions.apply_status(f.units[0], target, "burn"), "화상 상한3 이후 부여 거부")
	var messages: Array[String] = []
	f.actions.feedback.connect(func(unit: CombatUnit, text: String) -> void:
		if unit == target:
			messages.append(text)
	)
	f.actions.dice = _dice_for([1, 2, 3], [4, 4, 4])
	f.turns.end_turn()
	f.turns.end_turn()
	_check(target.hit_points == 6 and messages == ["화상 1", "화상 2", "화상 3"],
		"서로 다른 시전자의 화상3중첩은 각각 한 번씩 부여 순서로 피해")


func _test_poison_tick() -> void:
	var f: Fixture = _fixture()
	var target: CombatUnit = f.units[2]
	f.turns.select_unit(f.units[1])
	_check(f.actions.apply_status(f.units[1], target, "poison"), "독 부여")
	f.actions.dice = _dice_for([3], [4])
	f.turns.end_turn()
	f.turns.end_turn()
	_check(target.hit_points == 11, "자연 d4의3은 강도4 미달이라 독 고정1 피해")


func _test_status_fifo() -> void:
	var f: Fixture = _fixture()
	var target: CombatUnit = f.units[2]
	f.turns.select_unit(f.units[1])
	f.actions.apply_status(f.units[0], target, "burn")
	f.actions.apply_status(f.units[1], target, "poison")
	f.actions.apply_status(f.units[0], target, "burn")
	f.actions.apply_status(f.units[3], target, "poison")
	var messages: Array[String] = []
	f.actions.feedback.connect(func(unit: CombatUnit, text: String) -> void:
		if unit == target:
			messages.append(text)
	)
	f.actions.dice = _dice_for([2, 3, 3], [4, 4, 4])
	f.turns.end_turn()
	f.turns.end_turn()
	_check(target.hit_points == 5 and messages == ["화상 2", "독 1", "화상 3", "독 1"],
		"다른 상태도 전체 FIFO: 첫 독 강도4로 자연 판정 한 번만 굴리고 각 중첩 피해")


func _test_poison_save_oldest() -> void:
	var f: Fixture = _fixture()
	var target: CombatUnit = f.units[2]
	f.turns.select_unit(f.units[1])
	f.actions.apply_status(f.units[3], target, "poison")
	f.actions.apply_status(f.units[1], target, "poison")
	f.actions.apply_status(f.units[1], target, "poison")
	_check(not f.actions.apply_status(f.units[1], target, "poison"), "독도 상한3 이후 거부")
	f.units[3].kind = CombatUnit.Kind.SCRAP_ROBOT_1000
	f.actions.dice = _dice_for([4], [4])
	var messages: Array[String] = []
	var record: Callable = func(unit: CombatUnit, text: String) -> void:
		if unit == target:
			messages.append(text)
	f.actions.feedback.connect(record)
	f.turns.end_turn()
	f.turns.end_turn()
	f.actions.feedback.disconnect(record)
	_check(target.hit_points == 10, "자연4는 강도4 동점 성공: 가장 오래된 하나만 제거 후 두 틱")
	_check(messages == ["독 제거", "독 1", "독 1"], "제거 성공은 이름만, 남은 틱은 원인과 피해: %s" % str(messages))
	# 내성으로 없어진 시전자를 제거해도 남은 두 독은 그대로다.
	f.actions.incapacitate(f.units[3])
	f.actions.dice = _dice_for([3], [4])
	f.turns.end_turn()
	f.turns.end_turn()
	f.turns.end_turn()
	_check(target.hit_points == 8, "제거한 독의 다음 제거도 새 가장 오래된 강도4로 한 번만 판정")


func _test_status_caster_incapacitation() -> void:
	var f: Fixture = _fixture()
	var target: CombatUnit = f.units[2]
	f.actions.apply_status(f.units[1], target, "burn")
	f.actions.apply_status(f.units[0], target, "poison")
	f.actions.incapacitate(f.units[1])
	_check(not f.actions.apply_status(f.units[1], target, "burn"), "전투 불능 시전자의 새 부여 거부")
	f.actions.dice = _dice_for([1], [4])
	f.turns.end_turn()
	_check(f.turns.current_unit == target and target.hit_points == 11,
		"시전자 전투 불능은 자기 화상만 즉시 제거하고 다른 시전자의 독은 유지")


func _test_status_stage_reset() -> void:
	var f: Fixture = _fixture()
	var target: CombatUnit = f.units[2]
	f.actions.apply_status(f.units[1], target, "burn")
	target.begin_stage(false)
	f.actions.dice = _dice_for([], [])
	f.turns.end_turn()
	f.turns.end_turn()
	_check(target.hit_points == 12, "다음 스테이지는 지난 화상을 제거하고 틱 주사위를 굴리지 않음")


func _test_poison_caster_duration() -> void:
	var f: Fixture = _fixture()
	var source: CombatUnit = f.units[1]
	var target: CombatUnit = f.units[2]
	f.turns.select_unit(source)
	f.actions.apply_status(source, target, "poison")
	f.actions.dice = _dice_for([1, 1, 1, 1], [4, 4, 4, 4])
	for expected_hp: int in [11, 10, 9, 8, 8]:
		f.turns.end_turn()
		f.turns.end_turn()
		_check(target.hit_points == expected_hp, "독은 네 번째 시전자 시작에 만료: HP" + str(expected_hp))
		f.turns.end_turn()
		f.turns.end_turn()
		f.turns.select_unit(source)


func _test_status_lethal_tick() -> void:
	var f: Fixture = _fixture()
	var target: CombatUnit = f.units[0]
	target.hit_points = 2
	f.actions.apply_status(f.units[3], target, "burn")
	f.actions.apply_status(f.units[2], target, "poison")
	f.actions.dice = _dice_for([2], [4])
	ScriptedDice.arrange_turns(f.turns, f.units, f.units)
	_check(target.hit_points == 0 and not target.visible and f.turns.current_unit == f.units[1],
		"시작 화상으로 전투 불능이면 남은 독 내성/피해 없이 동료로 진행")


func _test_ground_creation() -> void:
	var f: Fixture = _fixture()
	var cell: Vector2i = f.units[0].cell
	_check(f.actions.create_ground(f.units[3], cell, "burn"), "점유 바닥에 불 장판 생성")
	_check(f.actions.create_ground(f.units[2], cell, "poison"), "독 장판은 같은 칸에 함께 생성")
	var grounds: Array = f.actions.get_grounds()
	_check(grounds.size() == 2 and grounds[0].kind == "burn" and grounds[0].turns_left == 2
		and grounds[1].kind == "poison" and grounds[1].turns_left == 4,
		"장판 조회는 생성 순서와 불2/독4 기간을 표시")
	_check(f.units[0].status_effects.is_empty(), "장판 생성은 점유 유닛에 즉시 부여하지 않음")
	_check(f.actions.create_ground(f.units[1], cell, "burn") and f.actions.get_grounds().size() == 2
		and f.actions.get_grounds()[0].source == f.units[3], "같은 불 장판 갱신은 원 시전자와 순서를 유지")
	f.actions.grid.blocked_cells = [Vector2i(1, 1)]
	f.actions.grid.pits = [Vector2i(2, 1)]
	for invalid: Vector2i in [Vector2i(-1, 0), Vector2i(1, 1), Vector2i(2, 1)]:
		_check(not f.actions.create_ground(f.units[3], invalid, "burn"), "바닥 없는 칸/막힌 칸은 장판 거부")
	_check(not f.actions.create_ground(f.units[3], cell, "ice"), "미정 종류는 거부")


func _test_ground_walk_entry() -> void:
	var f: Fixture = _fixture()
	var target: CombatUnit = f.units[0]
	f.units[2].reaction_left = 0
	f.actions.dice = _dice_for([], [])
	f.actions.create_ground(f.units[3], Vector2i(4, 5), "burn")
	f.actions.create_ground(f.units[3], Vector2i(4, 6), "poison")
	_check(await f.actions.move_to(target, Vector2i(4, 5)) and target.get_status_count("burn") == 1
		and target.hit_points == 12, "걷기 진입은 화상1개만 부여하고 즉시 피해/주사위 없음")
	await f.actions.move_to(target, Vector2i(4, 4))
	f.actions.create_ground(f.units[1], Vector2i(4, 5), "burn")
	await f.actions.move_to(target, Vector2i(4, 6))
	_check(target.get_status_count("burn") == 1 and target.get_status_count("poison") == 1
		and target.movement_left == 2 and target.hit_points == 12,
		"경로 중간 재진입/다른 시전자 갱신은 진입 제한 유지, 다른 칸 독은 별도 부여")


func _test_ground_start_and_expiry() -> void:
	var f: Fixture = _fixture()
	var target: CombatUnit = f.units[2]
	f.actions.create_ground(f.units[1], target.cell, "burn")
	f.actions.create_ground(f.units[1], target.cell, "poison")
	f.actions.dice = _dice_for([2, 1, 2, 1], [4, 4, 4, 4])
	f.turns.end_turn()
	_check(f.actions.get_grounds()[0].turns_left == 1 and f.actions.get_grounds()[1].turns_left == 3,
		"시전자의 실제 시작에 장판 기간 감소")
	f.turns.end_turn()
	_check(target.hit_points == 9 and target.get_status_count("burn") == 1
		and target.get_status_count("poison") == 1, "대상 실제 시작에 장판 부여 후 새 효과도 FIFO 틱")
	for index: int in range(4):
		f.turns.end_turn()
	_check(f.actions.get_grounds().size() == 1 and f.actions.get_grounds()[0].kind == "poison"
		and f.actions.get_grounds()[0].turns_left == 2 and target.get_status_count("burn") == 1,
		"시전자 두 번째 시작에 불 장판 만료, 뒤늦게 부여한 화상 자체의 기간은 보존")
	_check(target.hit_points == 5 and target.get_status_count("poison") == 2,
		"다음 실제 시작은 남은 화상/독과 장판의 새 독을 함께 처리")


func _test_ground_cleanup() -> void:
	var f: Fixture = _fixture()
	f.actions.dice = _dice_for([], [])
	f.actions.create_ground(f.units[0], f.units[1].cell, "burn")
	f.actions.create_ground(f.units[3], f.units[2].cell, "poison")
	var observed: Array[int] = []
	var observer: Callable = func(_unit: CombatUnit) -> void:
		observed.append(f.actions.get_grounds().size())
	f.turns.turn_started.connect(observer)
	f.actions.incapacitate(f.units[0])
	f.turns.turn_started.disconnect(observer)
	_check(observed == [1] and f.actions.get_grounds().size() == 1
		and f.actions.get_grounds()[0].source == f.units[3],
		"현재 시전자 전투 불능은 다음 실제 턴 시작 전에 자기 장판만 정리")
	_check(not f.actions.create_ground(f.units[0], Vector2i(0, 0), "burn"), "전투 불능 시전자는 새 장판 거부")
	f.actions.initialize(f.units, f.turns)
	_check(f.actions.get_grounds().is_empty(), "전투 재초기화는 이전 장판/진입 기록 정리")


func _test_ground_cleanup_observers() -> void:
	var f: Fixture = _fixture()
	f.actions.dice = _dice_for([], [])
	f.actions.create_ground(f.units[0], f.units[1].cell, "burn")
	f.actions.create_ground(f.units[0], f.units[1].cell, "poison")
	f.actions.apply_status(f.units[0], f.units[2], "burn")
	var observed: Array[Vector2i] = []
	var observer: Callable = func(message: String) -> void:
		if "장판 해제" in message:
			observed.append(Vector2i(f.actions.get_grounds().size(), f.units[2].get_status_count("burn")))
	f.actions.logged.connect(observer)
	f.actions.incapacitate(f.units[0])
	f.actions.logged.disconnect(observer)
	_check(observed == [Vector2i.ZERO, Vector2i.ZERO],
		"소멸 로그 콜백도 시전자의 모든 장판과 상태 이상이 정리된 결과만 관측")


func _test_ground_expiry_observers() -> void:
	var f: Fixture = _fixture()
	f.actions.create_ground(f.units[1], Vector2i.ZERO, "burn")
	f.actions.apply_status(f.units[1], f.units[0], "burn")
	f.actions.dice = _dice_for([2], [4])
	var observed: Array[int] = []
	var observer: Callable = func(message: String) -> void:
		if "장판 만료" in message:
			observed.append(f.units[0].get_status_count("burn"))
	f.actions.logged.connect(observer)
	for index: int in range(5):
		f.turns.end_turn()
	f.actions.logged.disconnect(observer)
	_check(observed == [0], "장판 만료 로그 전에 같은 시전자의 만료 상태 이상도 정리")


func _test_ground_landings() -> void:
	var jumping: Fixture = _fixture()
	jumping.units[2].reaction_left = 0
	jumping.actions.dice = _dice_for([], [])
	jumping.actions.create_ground(jumping.units[3], Vector2i(4, 5), "burn")
	jumping.actions.create_ground(jumping.units[3], Vector2i(4, 6), "poison")
	_check(await jumping.actions.jump_to(jumping.units[0], Vector2i(4, 6))
		and jumping.units[0].get_status_count("burn") == 0
		and jumping.units[0].get_status_count("poison") == 1, "점프는 공중 장판을 건너뛰고 착지 장판만 적용")
	var pushing: Fixture = _fixture()
	pushing.actions.dice = _dice_for([], [])
	pushing.actions.create_ground(pushing.units[3], Vector2i(2, 4), "burn")
	pushing.actions.create_ground(pushing.units[3], Vector2i(2, 4), "poison")
	_check(pushing.actions.shove(pushing.units[0], pushing.units[1])
		and pushing.units[1].get_status_count("burn") == 1
		and pushing.units[1].get_status_count("poison") == 1, "밀치기는 겹친 착지 장판을 둘 다 적용")
	var pulling: Fixture = _fixture()
	pulling.units[0].cell = Vector2i(2, 4)
	pulling.units[2].kind = CombatUnit.Kind.SCRAP_ROBOT_2000
	pulling.actions.create_ground(pulling.units[3], Vector2i(4, 4), "burn")
	pulling.turns.end_turn()
	pulling.turns.end_turn()
	pulling.actions.dice = _dice_for([12, 1], [12, 20])
	_check(pulling.actions.pull(pulling.units[2], pulling.units[0])
		and pulling.units[0].get_status_count("burn") == 1, "끌기 착지도 장판 적용")


func _test_ground_entry_reset() -> void:
	var f: Fixture = _fixture()
	var target: CombatUnit = f.units[0]
	f.units[2].cell = Vector2i(9, 9)
	f.actions.create_ground(f.units[3], Vector2i(4, 5), "burn")
	f.actions.dice = _dice_for([2], [4])
	await f.actions.move_to(target, Vector2i(4, 5))
	await f.actions.move_to(target, Vector2i(4, 4))
	for index: int in range(4):
		f.turns.end_turn()
	_check(target.hit_points == 10 and target.get_status_count("burn") == 1,
		"장판 밖 실제 시작은 기존 화상만 틱하고 진입 제한 초기화")
	f.turns.end_turn()
	_check(f.turns.select_unit(target) and target.hit_points == 10, "턴 종료 취소는 장판/틱 시작 반복 없음")
	await f.actions.move_to(target, Vector2i(4, 5))
	await f.actions.move_to(target, Vector2i(4, 4))
	await f.actions.move_to(target, Vector2i(4, 5))
	_check(target.get_status_count("burn") == 2 and target.hit_points == 10,
		"새 실제 턴의 첫 진입만 허용하고 종료 취소/재진입으로 반복하지 않음")


func _test_ground_rejected_entry() -> void:
	for capped: bool in [false, true]:
		var f: Fixture = _fixture()
		var target: CombatUnit = f.units[0]
		f.units[2].reaction_left = 0
		f.actions.dice = _dice_for([], [])
		f.actions.create_ground(f.units[3], Vector2i(4, 5), "burn")
		if capped:
			for index: int in range(3):
				f.actions.apply_status(f.units[1], target, "burn")
			f.actions.grid.water_cells = [Vector2i(4, 6)]
		else:
			f.actions.grid.water_cells = [Vector2i(4, 5)]
		await f.actions.move_to(target, Vector2i(4, 5))
		await f.actions.move_to(target, Vector2i(4, 6))
		f.actions.grid.water_cells.clear()
		await f.actions.move_to(target, Vector2i(4, 5))
		_check(target.get_status_count("burn") == 0 and f.actions.get_grounds().size() == 1,
			"물/상한 거부도 진입 시도 소비, 물은 장판 자체를 없애지 않음: " + str(capped))


func _test_deferred_ground_start() -> void:
	var f: Fixture = _fixture()
	var target: CombatUnit = f.units[0]
	var actor: CombatUnit = f.units[1]
	target.cell = Vector2i(3, 4)
	actor.cell = Vector2i(4, 4)
	var order: Array[CombatUnit] = [target, f.units[2], f.units[3], actor]
	ScriptedDice.arrange_turns(f.turns, f.units, order)
	f.actions.create_ground(f.units[2], Vector2i(2, 4), "burn")
	f.actions.dice = _dice_for([2, 3], [4, 4])
	for index: int in range(3):
		f.turns.end_turn()
	_check(f.turns.current_unit == actor and not f.turns.is_turn_started(target), "장판 사례의 동료는 경계 묶음에서 지연")
	_check(f.actions.shove(actor, target) and target.get_status_count("burn") == 1
		and target.hit_points == 12 and not f.turns.is_turn_started(target), "지연된 동료도 진입 시 부여하지만 틱은 대기")
	_check(f.turns.select_unit(target) and target.hit_points == 7 and target.get_status_count("burn") == 2,
		"처음 선택할 때 시작 부여와 FIFO 틱, 기존 진입과 시작은 별도")
	f.turns.select_unit(actor)
	f.turns.select_unit(target)
	f.turns.end_turn()
	_check(f.turns.select_unit(target) and target.hit_points == 7 and target.get_status_count("burn") == 2,
		"Tab에 쓰는 공개 선택/종료 취소는 지연된 시작의 장판을 반복하지 않음")


func _test_ground_entry_incapacitation() -> void:
	var f: Fixture = _fixture()
	var target: CombatUnit = f.units[0]
	f.units[2].cell = Vector2i(5, 5)
	f.actions.create_ground(f.units[3], Vector2i(4, 5), "burn")
	f.actions.create_ground(f.units[3], Vector2i(4, 5), "poison")
	f.actions.dice = _dice_for([], [])
	var observer: Callable = func() -> void:
		if target.hit_points > 0 and target.get_status_count("burn") == 1:
			f.actions.incapacitate(target)
	f.actions.changed.connect(observer)
	await f.actions.move_to(target, Vector2i(4, 6))
	f.actions.changed.disconnect(observer)
	_check(target.hit_points == 0 and target.cell == Vector2i(4, 5)
		and target.status_effects.is_empty() and f.units[2].reaction_left == 1,
		"진입 부여 콜백의 전투 불능 뒤 남은 장판/이동/기회 공격과 굴림 중단")


func _test_ground_fifo() -> void:
	var f: Fixture = _fixture()
	var target: CombatUnit = f.units[2]
	f.actions.create_ground(f.units[3], target.cell, "poison")
	f.actions.create_ground(f.units[1], target.cell, "burn")
	f.actions.dice = _dice_for([1, 2], [4, 4])
	var messages: Array[String] = []
	f.actions.feedback.connect(func(unit: CombatUnit, text: String) -> void:
		if unit == target:
			messages.append(text))
	f.turns.end_turn()
	f.turns.end_turn()
	_check(messages == ["독 1", "화상 2"] and target.hit_points == 9,
		"겹친 장판은 종류 고정 순서 대신 먼저 생성한 독부터 부여/FIFO 처리")


func _test_self_ground_expiry() -> void:
	var f: Fixture = _fixture()
	var target: CombatUnit = f.units[0]
	f.actions.create_ground(target, target.cell, "burn")
	f.actions.dice = _dice_for([2, 2], [4, 4])
	for expected_hp: int in [10, 8, 8]:
		for index: int in range(4):
			f.turns.end_turn()
		_check(target.hit_points == expected_hp, "자기 장판도 만료 먼저, 이미 부여한 화상은 자기 기간 유지: " + str(expected_hp))
	_check(f.actions.get_grounds().is_empty() and target.status_effects.is_empty(), "자기 장판과 뒤늦게 받은 화상 모두 정상 만료")


func _test_ground_fall_and_water() -> void:
	for hp: int in [3, 4]:
		var f: Fixture = _fixture()
		var target: CombatUnit = f.units[1]
		target.hit_points = hp
		f.actions.grid.heights = {f.units[0].cell: 3, target.cell: 3}
		f.actions.create_ground(f.units[3], Vector2i(2, 4), "burn")
		f.actions.dice = _dice_for([], [])
		_check(f.actions.shove(f.units[0], target) and target.hit_points == hp - 3
			and target.get_status_count("burn") == (1 if hp == 4 else 0),
			"낙하를 먼저 처리하고 살아남은 착지만 장판 부여: " + str(hp))
	var wet: Fixture = _fixture()
	var target: CombatUnit = wet.units[2]
	wet.actions.grid.water_cells = [target.cell]
	wet.actions.create_ground(wet.units[3], target.cell, "burn")
	wet.actions.create_ground(wet.units[3], target.cell, "poison")
	wet.actions.dice = _dice_for([1], [4])
	wet.turns.end_turn()
	wet.turns.end_turn()
	_check(target.hit_points == 11 and target.get_status_count("burn") == 0
		and target.get_status_count("poison") == 1 and wet.actions.get_grounds().size() == 2,
		"물 위 겹친 장판 시작은 불 틱 없이 독만 적용하고 장판은 보존")


func _test_ground_source_removed_during_entry() -> void:
	var f: Fixture = _fixture()
	var target: CombatUnit = f.units[0]
	f.units[2].reaction_left = 0
	f.actions.create_ground(f.units[3], Vector2i(4, 5), "burn")
	f.actions.create_ground(f.units[3], Vector2i(4, 5), "poison")
	f.actions.dice = _dice_for([], [])
	var observer: Callable = func() -> void:
		if target.get_status_count("burn") == 1:
			f.actions.incapacitate(f.units[3])
	f.actions.changed.connect(observer)
	await f.actions.move_to(target, Vector2i(4, 5))
	f.actions.changed.disconnect(observer)
	_check(target.status_effects.is_empty() and f.actions.get_grounds().is_empty(),
		"첫 장판 부여 콜백에서 시전자가 탈락하면 snapshot에 남은 뒤 장판도 중단")


func _test_ground_refresh_and_boundaries() -> void:
	var f: Fixture = _fixture()
	f.actions.dice = _dice_for([], [])
	f.actions.create_ground(f.units[1], Vector2i.ZERO, "burn")
	f.turns.end_turn()
	_check(f.actions.get_grounds()[0].turns_left == 1, "갱신 전에 원 시전자 시계로 기간 감소")
	f.actions.create_ground(f.units[3], Vector2i.ZERO, "burn")
	_check(f.actions.get_grounds()[0].turns_left == 2 and f.actions.get_grounds()[0].source == f.units[1],
		"다른 시전자의 갱신은 기간만2로 복원하고 원 시전자 유지")
	f.actions.create_ground(f.units[1], Vector2i(0, 1), "burn")
	_check(f.actions.get_grounds().size() == 2, "인접 칸의 같은 종류는 별개 장판")
	var outsider: CombatUnit = CombatUnit.new()
	_created.append(outsider)
	_check(not f.actions.create_ground(outsider, Vector2i.ZERO, "burn")
		and not f.actions.create_ground(null, Vector2i.ZERO, "burn"), "외부/없는 시전자는 거부")


func _test_common_stun_application() -> void:
	var f: Fixture = _fixture()
	_check(f.actions.apply_status(f.units[1], f.units[2], "stun") and f.units[2].is_stunned,
		"공통 부여는 기존 기절도 지원")
	f.actions.incapacitate(f.units[1])
	_check(not f.units[2].is_stunned, "공통 기절 부여도 시전자 전투 불능에 즉시 해제")
	f.units[3].kind = CombatUnit.Kind.SCRAP_ROBOT_1000
	_check(not f.actions.apply_status(f.units[0], f.units[3], "stun") and not f.units[3].is_stunned,
		"공통 기절 부여도 기존 보스 면역 보존")


func _test_water_walk() -> void:
	var f: Fixture = _fixture()
	var target: CombatUnit = f.units[0]
	f.units[2].reaction_left = 0
	f.actions.grid.water_cells = [Vector2i(4, 5)]
	f.actions.apply_status(f.units[3], target, "burn")
	_check(await f.actions.move_to(target, Vector2i(4, 6)), "물 칸을 지나 마른 땅까지 걷기")
	_check(target.get_status_count("burn") == 0 and target.hit_points == 12
		and target.movement_left == 4 and target.cell == Vector2i(4, 6),
		"걷는 중간 물 칸에서 화상 즉시 해제, 물의 추가 이동 비용/피해 없음")


func _test_water_shove() -> void:
	var f: Fixture = _fixture()
	var target: CombatUnit = f.units[1]
	f.actions.grid.water_cells = [Vector2i(2, 4)]
	f.actions.apply_status(f.units[3], target, "burn")
	f.actions.apply_status(f.units[2], target, "poison")
	f.actions.dice = _dice_for([1], [6])
	_check(f.actions.shove(f.units[0], target), "동료를 물로 밀치기")
	_check(target.cell == Vector2i(2, 4) and target.get_status_count("burn") == 0
		and target.get_status_count("poison") == 1 and target.hit_points == 14,
		"물로 밀치기는 화상만 즉시 해제, 독/HP/대상 실제 턴 시작은 유지")
	_check(f.turns.select_unit(target) and target.hit_points == 13,
		"물에 밀린 동료를 처음 조작할 때 화상 없이 남은 독만 처리")


func _test_water_immunity() -> void:
	var f: Fixture = _fixture()
	var target: CombatUnit = f.units[0]
	f.actions.grid.water_cells = [target.cell]
	_check(not f.actions.apply_status(f.units[3], target, "burn")
		and target.get_status_count("burn") == 0, "물 위 새 화상 부여 거부")
	_check(f.actions.apply_status(f.units[3], target, "poison")
		and target.get_status_count("poison") == 1, "물은 독 부여를 막지 않음")


func _test_water_turn_start() -> void:
	var f: Fixture = _fixture()
	var target: CombatUnit = f.units[2]
	f.actions.apply_status(f.units[1], target, "burn")
	f.actions.grid.water_cells = [target.cell]
	f.actions.apply_status(f.units[3], target, "poison")
	f.actions.dice = _dice_for([1], [4])
	var messages: Array[String] = []
	f.actions.feedback.connect(func(unit: CombatUnit, text: String) -> void:
		if unit == target:
			messages.append(text)
	)
	f.turns.end_turn()
	f.turns.end_turn()
	_check(target.hit_points == 11 and messages == ["물: 화상 해제", "독 1"],
		"물 위 실제 시작은 화상 틱 전에 해제하고 독만 유지")


func _test_water_jump() -> void:
	var cases: Array[Dictionary] = [
		{"water": Vector2i(4, 5), "burns": 1}, {"water": Vector2i(4, 6), "burns": 0}]
	for example: Dictionary in cases:
		var f: Fixture = _fixture()
		var target: CombatUnit = f.units[0]
		f.units[2].reaction_left = 0
		f.actions.apply_status(f.units[3], target, "burn")
		f.actions.grid.water_cells = [example["water"]]
		f.actions.dice = _dice_for([], [])
		_check(await f.actions.jump_to(target, Vector2i(4, 6)), "물 통과/착지 점프 실행")
		_check(target.get_status_count("burn") == example["burns"] and target.hit_points == 12,
			"점프는 물 착지에서만 해제하고 공중 통과에는 적용하지 않음: " + str(example["water"]))


func _test_water_pull() -> void:
	var f: Fixture = _fixture()
	var target: CombatUnit = f.units[0]
	var robot: CombatUnit = f.units[2]
	robot.kind = CombatUnit.Kind.SCRAP_ROBOT_2000
	target.cell = Vector2i(2, 4)
	f.actions.apply_status(f.units[1], target, "burn")
	f.actions.grid.water_cells = [Vector2i(4, 4)]
	f.turns.end_turn()
	f.turns.end_turn()
	f.actions.dice = _dice_for([12, 1], [12, 20])
	_check(f.actions.pull(robot, target) and target.cell == Vector2i(4, 4)
		and target.get_status_count("burn") == 0, "로봇의 실제 끌기 도착 물에서 화상 해제")


func _test_deferred_water_shove() -> void:
	var f: Fixture = _fixture()
	var target: CombatUnit = f.units[0]
	var actor: CombatUnit = f.units[1]
	target.cell = Vector2i(3, 4)
	actor.cell = Vector2i(4, 4)
	var order: Array[CombatUnit] = [target, f.units[2], f.units[3], actor]
	ScriptedDice.arrange_turns(f.turns, f.units, order)
	f.turns.end_turn()
	f.actions.apply_status(f.units[2], target, "burn")
	f.turns.end_turn()
	f.turns.end_turn()
	_check(f.turns.current_unit == actor and not f.turns.is_turn_started(target),
		"라운드 경계로 합친 동료는 실제 턴 시작을 기다림")
	f.actions.grid.water_cells = [Vector2i(2, 4)]
	f.actions.dice = _dice_for([], [])
	_check(f.actions.shove(actor, target) and not f.turns.is_turn_started(target)
		and target.get_status_count("burn") == 0, "지연된 동료의 시작 전에 물로 밀어 화상 해제")
	_check(f.turns.select_unit(target) and target.hit_points == 12,
		"동료를 처음 조작해도 제거한 화상의 틱을 굴리지 않음")


func _test_self_status_expiry() -> void:
	var f: Fixture = _fixture()
	var target: CombatUnit = f.units[0]
	f.actions.apply_status(target, target, "burn")
	f.actions.dice = _dice_for([2], [4])
	for expected_hp: int in [10, 10]:
		for index: int in range(4):
			f.turns.end_turn()
		_check(target.hit_points == expected_hp, "자기 시전자도 만료를 대상 틱보다 먼저 처리: " + str(expected_hp))


func _test_status_removed_during_tick() -> void:
	var f: Fixture = _fixture()
	var target: CombatUnit = f.units[2]
	f.turns.select_unit(f.units[1])
	f.actions.apply_status(f.units[1], target, "burn")
	f.actions.apply_status(f.units[3], target, "burn")
	f.actions.feedback.connect(func(unit: CombatUnit, text: String) -> void:
		if unit == target and text == "화상 2":
			f.actions.incapacitate(f.units[3])
	)
	f.actions.dice = _dice_for([2], [4])
	f.turns.end_turn()
	f.turns.end_turn()
	_check(target.hit_points == 10, "앞 틱의 피드백 중 시전자가 탈락하면 제거된 뒤 효과를 실행하지 않음")


func _test_poison_removed_during_save() -> void:
	for boundary: int in range(3):
		var f: Fixture = _fixture()
		var target: CombatUnit = f.units[2]
		f.turns.select_unit(f.units[1])
		f.actions.apply_status(f.units[1] if boundary == 0 else f.units[3], target, "poison")
		var damage_messages: Array[String] = []
		# 제거 실패는 팝업이 없으므로 같은 시점의 제거 로그에서 끼어든다.
		var interrupt: Callable = func(message: String) -> void:
			if not message.begins_with("%s 독 제거" % target.get_display_name()):
				return
			if boundary == 0:
				f.actions.incapacitate(f.units[1])
			elif boundary == 1:
				f.actions.incapacitate(target)
			else:
				f.actions.incapacitate(f.units[0])
				f.actions.incapacitate(f.units[1])
		var record: Callable = func(unit: CombatUnit, text: String) -> void:
			if unit == target and text.begins_with("독 "):
				damage_messages.append(text)
		f.actions.logged.connect(interrupt)
		f.actions.feedback.connect(record)
		f.actions.dice = _dice_for([1], [4])
		f.turns.end_turn()
		f.turns.end_turn()
		# 픽스처를 잡은 콜백이 순환 참조로 남지 않게 끊는다.
		f.actions.logged.disconnect(interrupt)
		f.actions.feedback.disconnect(record)
		_check(target.hit_points == (0 if boundary == 1 else 12) and damage_messages.is_empty(),
			"독 제거 로그 중 시전자·대상 탈락 또는 전투 종료 뒤 독 피해를 실행하지 않음: " + str(boundary))


func _test_water_stage() -> void:
	var scene: Node = (load("res://scenes/game.tscn") as PackedScene).instantiate()
	var battle_scene: Node2D = scene.get_node("Battle") as Node2D
	var stage: CombatStage = (load("res://scenes/combat/stage.tres") as CombatStage).duplicate() as CombatStage
	stage.water_cells = [Vector2i(4, 5), Vector2i(3, 4)]
	battle_scene.stages[0] = stage
	root.add_child(scene)
	battle_scene.set_process(false)
	await process_frame
	var scene_actions: CombatActions = battle_scene.get("actions") as CombatActions
	var map: CombatMap = battle_scene.get("map") as CombatMap
	_check(scene_actions.grid.water_cells == [Vector2i(4, 5), Vector2i(3, 4)],
		"스테이지의 물 칸을 실제 전투 격자에 전달")
	_check(map.surface_to_map(map.map_to_surface(Vector2i(4, 5))) == Vector2i(4, 5),
		"물 표시도 기존 아이소메트릭 바닥 좌표로 선택")
	stage.water_cells.append(Vector2i(9, 9))
	_check(scene_actions.grid.water_cells.size() == 2, "원본 스테이지 데이터 변경은 실행 중 격자를 바꾸지 않음")
	scene.free()
	await process_frame


func _test_status_application_boundaries() -> void:
	var f: Fixture = _fixture()
	var target: CombatUnit = f.units[2]
	var outsider: CombatUnit = CombatUnit.new()
	_created.append(outsider)
	_check(not f.actions.apply_status(null, target, "burn"), "없는 시전자의 효과 거부")
	_check(not f.actions.apply_status(outsider, target, "burn")
		and not f.actions.apply_status(f.units[0], outsider, "burn"), "전투 밖 시전자/대상 거부")
	_check(not f.actions.apply_status(f.units[0], target, "unknown")
		and target.get_status_count("burn") == 0, "알려지지 않은 상태는 대상 상태를 바꾸지 않음")
	f.actions.incapacitate(target)
	_check(not f.actions.apply_status(f.units[0], target, "poison"), "전투 불능 대상의 효과 거부")


func _test_deferred_stun_caster() -> void:
	var f: Fixture = _fixture()
	var source: CombatUnit = f.units[1]
	var target: CombatUnit = f.units[3]
	f.turns.select_unit(source)
	target.reaction_left = 0
	f.actions.dice = _dice_for([11, 1, 1], [20, 10, 6])
	await f.actions.attack(source, target, true)
	var order: Array[CombatUnit] = [f.units[0], f.units[2], source, target]
	ScriptedDice.arrange_turns(f.turns, f.units, order)
	f.actions.incapacitate(f.units[2])
	_check(target.is_stunned and not f.turns.is_turn_started(source),
		"묶음 결합만으로 지연된 시전자의 효과를 만료하지 않음")
	f.turns.select_unit(f.units[0])
	_check(target.is_stunned, "동료 선택은 지연된 시전자 턴 시작이 아님")
	_check(f.turns.select_unit(source) and not target.is_stunned,
		"지연된 시전자를 처음 조작할 때 기절 만료")
	source.shock_left = 1
	target.hit_points = target.get_max_hit_points()
	f.actions.dice = _dice_for([11, 1, 1], [20, 10, 6])
	_check(await f.actions.attack(source, target, true) and target.is_stunned,
		"시전자 턴 시작 뒤 새 충격 화살의 기절 부여")
	f.turns.end_turn()
	_check(target.is_stunned and f.turns.select_unit(source) and target.is_stunned,
		"턴 종료 취소는 같은 시전자 턴의 기절을 다시 만료하지 않음")
	f.turns.select_unit(f.units[0])
	f.turns.select_unit(source)
	_check(target.is_stunned, "선택 전환을 반복해도 같은 턴 시작은 한 번")


func _test_stunned_caster_expiry() -> void:
	var f: Fixture = _fixture()
	var source: CombatUnit = f.units[1]
	var target: CombatUnit = f.units[2]
	f.turns.select_unit(source)
	target.reaction_left = 0
	f.actions.dice = _dice_for([11, 1, 1], [20, 6, 6])
	await f.actions.attack(source, target, true)
	source.is_stunned = true
	f.turns.end_turn()
	f.turns.end_turn()
	f.turns.end_turn()
	_check(f.turns.current_unit == f.units[0] and target.is_stunned,
		"기절한 시전자의 실제 차례 전까지 대상 기절 유지")
	f.turns.end_turn()
	_check(not target.is_stunned and f.turns.current_unit == target,
		"기절한 시전자도 실제 턴 시작에 효과를 만료하고 대상은 정상 차례를 받음")
	_check(source.is_stunned and f.turns.is_turn_finished(source),
		"기절한 시전자는 시작 효과 처리 후 자기 차례만 건너뜀")


func _test_stun_source_incapacitation() -> void:
	var f: Fixture = _fixture()
	var source: CombatUnit = f.units[1]
	var target: CombatUnit = f.units[3]
	f.turns.select_unit(source)
	target.reaction_left = 0
	f.actions.dice = _dice_for([11, 1, 1], [20, 10, 6])
	_check(await f.actions.attack(source, target, true) and target.is_stunned,
		"시전자 탈락 사례의 충격 화살")
	f.turns.end_turn()
	f.turns.end_turn()
	_check(f.turns.current_unit == f.units[2] and not f.turns.is_turn_finished(target),
		"같은 적 묶음의 기절 대상 차례는 아직 남음")
	f.actions.incapacitate(source)
	_check(not target.is_stunned, "시전자 전투 불능 시 그 시전자의 기절을 즉시 해제")
	f.turns.end_turn()
	_check(f.turns.current_unit == target and f.turns.round_number == 1,
		"해제된 기절 대상은 오래된 건너뛰기 기록 없이 남은 차례를 받음")


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
	f.actions.dice = _dice_for([20, 1, 2, 3], [20, 10, 6, 6])
	await f.actions.attack(actor, target)
	_check(f.actions.last_damage_rolls == [2, 3] and not f.actions.last_attack.critical,
		"최댓값 표식도 무기와 표식을 각각 한 번만 굴림")
	var shock: Fixture = _fixture()
	_check(shock.units[1].get_ability_sides(CombatUnit.Ability.DEXTERITY) == 20, "아군 궁수는 민첩d20")
	shock.turns.select_unit(shock.units[1])
	shock.units[2].reaction_left = 0
	shock.actions.dice = _dice_for([11, 1, 1], [20, 6, 6])
	_check(await shock.actions.attack(shock.units[1], shock.units[2], true), "충격 화살 실행")
	_check(shock.units[1].shock_left == 0 and shock.units[1].action_left == 0, "충격 화살 횟수와 행동 소비")
	_check(shock.units[2].is_stunned and shock.units[2].hit_points > 0, "명중·피해 후 별도 방어 굴림 없이 기절")
	_check(shock.hits.size() == 1, "충격 화살 피해와 기절은 타격음 한 번")
	shock.turns.end_turn()
	shock.turns.end_turn()
	_check(shock.turns.current_unit == shock.units[3] and shock.turns.is_turn_finished(shock.units[2]),
		"기절한 다음 턴은 자동으로 건너뜀")
	_check(shock.units[2].is_stunned, "대상 차례를 건너뛰어도 시전자 턴 전까지 기절 유지")
	shock.turns.end_turn()
	_check(shock.units[2].is_stunned, "다른 아군 턴 시작은 시전자의 기절을 해제하지 않음")
	shock.turns.select_unit(shock.units[1])
	_check(not shock.units[2].is_stunned, "충격 화살 시전자의 실제 턴 시작에 기절 해제")
	for attack_roll: int in [6, 7]:
		var boundary: Fixture = _fixture()
		boundary.turns.select_unit(boundary.units[1])
		boundary.units[2].reaction_left = 0
		boundary.actions.dice = (_dice_for([attack_roll, 6, 4], [20, 6, 6]) if attack_roll == 7
			else _dice_for([attack_roll, 6], [20, 6]))
		await boundary.actions.attack(boundary.units[1], boundary.units[2], true)
		_check(boundary.units[2].hit_points == (7 if attack_roll == 7 else 12), "충격 화살은 민첩 대결 승리 때만 피해 적용")
		_check(boundary.units[2].is_stunned == (attack_roll == 7),
			"풋내기 민첩6과 동점은 무효, 공격7 명중은 추가 판정 없이 기절")
	var waiting: Fixture = _fixture()
	waiting.units[1].is_stunned = true
	ScriptedDice.arrange_turns(waiting.turns, waiting.units, waiting.units)
	_check(waiting.turns.current_unit == waiting.units[0] and waiting.units[1].is_stunned,
		"두 번째 기절 유닛은 앞 유닛이 동작하는 동안 기절 유지")
	_check(not waiting.turns.select_unit(waiting.units[1]), "아직 건너뛰지 않은 기절 유닛 선택 거부")
	waiting.turns.remove_unit(waiting.units[3])
	_check(waiting.units[1].is_stunned, "다른 유닛 탈락의 묶음 재계산은 기절을 풀지 않음")
	waiting.turns.end_turn()
	_check(waiting.units[1].is_stunned and waiting.turns.is_turn_finished(waiting.units[1]),
		"두 번째 유닛 순서를 건너뛰어도 기절 유지")
	var missed: Fixture = _fixture()
	missed.turns.select_unit(missed.units[1])
	var before_miss: int = missed.units[3].hit_points
	missed.actions.dice = _dice_for([1, 1], [20, 10])
	await missed.actions.attack(missed.units[1], missed.units[3], true)
	_check(missed.units[1].action_left == 0 and missed.units[1].shock_left == 0
		and missed.units[3].hit_points == before_miss and not missed.units[3].is_stunned,
		"빗나가도 충격 화살 행동·횟수 모두 소비, 피해·기절 없음")
	_check(not missed.actions.can_use(missed.units[1], "shock"), "빗나간 충격 화살 재사용 거부")
	missed.units[1].action_left = 1
	_check(not missed.actions.can_use(missed.units[1], "shock"), "행동만 회복해도 사용 횟수는 돌아오지 않음")
	_check(not missed.actions.can_target(missed.units[3], missed.units[0], "shock"),
		"풋내기 궁수의 충격 화살 실행 거부")


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
	f.actions.dice = _dice_for([1, 4], [20, 4])
	await f.actions.move_to(f.units[3], Vector2i(6, 4))
	_check(asked == ["opportunity"] and f.units[0].reaction_left == 0, "아군 기회 공격은 물어보고 반응 소비")
	_check(f.units[3].cell == Vector2i(6, 4) and f.units[3].movement_left == 5, "빗나가면 이동 계속")
	_check(not f.actions.busy and f.actions.pending_reactor == null, "반응 종료 후 대기 해제")
	f.actions.dice = _dice_for([10, 1, 4], [10, 8, 4])
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
	dead.actions.dice = _dice_for([20, 1, 1], [20, 4, 8])
	await dead.actions.move_to(dead.units[3], Vector2i(6, 4))
	_check(dead.units[3].hit_points == 0 and dead.units[3].cell == Vector2i(5, 4)
		and dead.units[3].movement_left == 6, "기회 공격으로 탈락하면 벗어나기 전 칸에서 이동 중단")
	_check(dead.hits.size() == 1, "기회 공격 피해도 타격음 한 번")
	var parry: Fixture = _fixture()
	parry.units[0].cell = Vector2i(4, 4)
	parry.units[2].cell = Vector2i(5, 4)
	parry.turns.end_turn()
	parry.turns.end_turn()
	parry.actions.reaction_requested.connect(func(kind: String, prompt: String) -> void:
		_check(kind == "parry" and parry.actions.last_damage_rolls.is_empty(), "피해 굴림 전에 흘려내기 확인")
		_check("50.0%" in prompt, "공격 합계8에 민첩d8+3 흘려내기 성공률50%")
		parry.actions.resolve_reaction(true)
	)
	parry.actions.dice = _dice_for([5, 1, 5], [10, 20, 8])
	await parry.actions.attack(parry.units[2], parry.units[0])
	_check(parry.units[0].hit_points == 12 and parry.actions.last_damage == 0, "흘려내기는 이미 굴린 공격 합계와 동점이어도 무효화")
	_check(parry.hits.is_empty(), "성공한 흘려내기는 타격음을 요청하지 않음")
	_check(parry.units[0].reaction_left == 0 and parry.units[0].parry_left == 1, "흘려내기 반응과 막당 횟수 소비")
	_check(parry.units[2].action_left == 0, "흘려내기 성공해도 공격자 행동 소비")
	parry.units[2].action_left = 1
	parry.units[0].reaction_left = 1
	parry.actions.dice = _dice_for([5, 1, 4, 4], [10, 20, 8, 4])
	await parry.actions.attack(parry.units[2], parry.units[0])
	_check(parry.actions.last_damage > 0 and parry.actions.last_damage_rolls == [4],
		"민첩4+3은 이미 굴린 공격8 미달로 피해 주사위 한 번 적용")
	_check(parry.hits.size() == 1, "실패한 흘려내기는 실제 피해 타격음 한 번")
	_check(parry.units[0].reaction_left == 0 and parry.units[0].parry_left == 0,
		"흘려내기 대결 실패도 반응과 횟수 소비")
	var automatic: Fixture = _fixture()
	automatic.actions.dice = _dice_for([11, 1, 4], [20, 10, 8])
	await automatic.actions.attack(automatic.units[0], automatic.units[2])
	_check(automatic.units[2].parry_left == 2 and automatic.units[2].reaction_left == 1
		and automatic.units[2].hit_points == 5, "야만인은 흘려내기 없이 아군 피해를 받음")
	var parried_shock: Fixture = _fixture()
	_enemy_archer(parried_shock)
	parried_shock.actions.reaction_requested.connect(func(_kind: String, _prompt: String) -> void:
		parried_shock.actions.resolve_reaction(true)
	)
	_check(not await parried_shock.actions.attack(parried_shock.units[3], parried_shock.units[0], true),
		"풋내기 궁수는 충격 화살로 공격하지 못함")
	_check(parried_shock.units[0].hit_points == 12 and not parried_shock.units[0].is_stunned
		and parried_shock.units[3].shock_left == 1, "불가능한 스킬은 피해·기절·횟수를 바꾸지 않음")


func _test_own_turn_parry() -> void:
	var scene: PackedScene = load("res://scenes/combat/battle.tscn") as PackedScene
	for choice: int in range(3):
		var battle: Node2D = scene.instantiate() as Node2D
		battle.stages[0] = load("res://scenes/combat/stage.tres") as CombatStage
		root.add_child(battle)
		battle.set_process(false)
		battle.call("start_battle")
		await process_frame
		var units: Array[CombatUnit] = battle.get("units")
		var turns: CombatTurns = battle.get("turns") as CombatTurns
		var actions: CombatActions = battle.get("actions") as CombatActions
		var hud: CombatTurnHud = battle.get_node("UI/TurnHud") as CombatTurnHud
		ScriptedDice.arrange_turns(turns, units, units)
		units[0].cell = Vector2i(4, 4)
		units[1].cell = Vector2i(0, 0)
		units[2].cell = Vector2i(5, 4)
		units[3].cell = Vector2i(0, 9)
		battle.call("_update_turn_ui")
		_check(units[1].hit_points == 14 and units[3].hit_points == 14,
			"실제 장면의 아군과 적 궁수 HP는14")
		var asked: Array[String] = []
		var respond: Callable = func(kind: String, prompt: String) -> void:
			asked.append(kind)
			_check(kind == "parry" and turns.current_unit == units[0]
				and actions.pending_reactor == units[0], "자기 턴 기회 공격 명중에도 흘려내기 요청")
			_check(hud.reaction_dialog.visible and hud.end_button.disabled
				and actions.busy, "자기 턴 흘려내기 창과 입력 잠금")
			_check("50.0%" in prompt and actions.last_damage_rolls.is_empty(),
				"자기 턴에도 피해 굴림 전에 공격 합계8·50% 표시")
			if choice == 2:
				hud.reaction_dialog.get_cancel_button().pressed.emit()
			else:
				hud.reaction_dialog.get_ok_button().pressed.emit()
		actions.reaction_requested.connect(respond)
		if choice == 0:
			actions.dice = _dice_for([5, 1, 5], [10, 20, 8])
		elif choice == 1:
			actions.dice = _dice_for([5, 1, 4, 4], [10, 20, 8, 4])
		else:
			actions.dice = _dice_for([5, 1, 4], [10, 20, 4])
		_check(await actions.move_to(units[0], Vector2i(3, 4)), "자기 턴 기회 공격 후 이동 완료")
		await process_frame
		_check(asked == ["parry"] and units[2].reaction_left == 0, "적 기회 공격은 자동이며 반응 소비")
		_check(units[0].hit_points == (12 if choice == 0 else 7),
			"흘려내기 성공은 피해 무효, 실패·넘기기는 피해 적용")
		var reaction: int = 1 if choice == 2 else 0
		var uses: int = 2 if choice == 2 else 1
		_check(units[0].reaction_left == reaction and units[0].parry_left == uses,
			"성공·실패는 반응과 횟수 소비, 넘기기는 유지")
		_check(units[0].cell == Vector2i(3, 4) and units[0].movement_left == 5
			and units[0].action_left == 1 and units[0].bonus_action_left == 1,
			"흘려내기 뒤 이동1만 소비하고 행동·보조 행동 유지")
		_check(not hud.reaction_dialog.visible and not actions.busy
			and actions.pending_reactor == null and not hud.end_button.disabled,
			"자기 턴 반응 선택 후 창과 입력 잠금 해제")
		turns.select_unit(units[1])
		turns.select_unit(units[0])
		_check(units[0].reaction_left == reaction, "아군 선택 전환은 쓴 반응을 회복하지 않음")
		turns.end_turn()
		turns.end_turn()
		_check(not turns.current_unit.is_ally and units[0].reaction_left == reaction,
			"적 턴 시작에도 아군 반응 회복 없음")
		turns.end_turn()
		turns.end_turn()
		_check(turns.current_unit == units[0] and units[0].reaction_left == 1
			and units[0].parry_left == uses, "다음 자기 턴 시작에는 반응만 회복")
		actions.reaction_requested.disconnect(respond)
		battle.queue_free()
		await process_frame


func _test_isometric_surface() -> void:
	var map: CombatMap = CombatMap.new()
	var grid: CombatGrid = CombatGrid.new()
	map.build_grid(grid, load("res://scenes/combat/floor_tiles.tres") as TileSet)
	var origin: Vector2 = map.map_to_surface(Vector2i.ZERO)
	_check(map.map_to_surface(Vector2i(1, 0)) - origin == Vector2(16, 8)
		and map.map_to_surface(Vector2i(0, 1)) - origin == Vector2(-16, 8),
		"사각 논리 격자의 두 축은 화면에서32×16 마름모의 대각 방향")
	var cell: Vector2i = Vector2i(4, 4)
	var center: Vector2 = map.map_to_surface(cell)
	_check(map.surface_to_map(center) == cell
		and map.surface_to_map(center + Vector2(12, 6)) != cell,
		"마름모 중심은 해당 칸이고 바깥 모서리는 같은 칸으로 선택하지 않음")
	var matched: int = 0
	for y: int in range(10):
		for x: int in range(10):
			var target: Vector2i = Vector2i(x, y)
			if map.surface_to_map(map.map_to_surface(target)) == target:
				matched += 1
	_check(matched == 100, "평면100칸의 마름모 중심을 모두 올바른 논리 칸으로 선택")
	map.free()


func _test_scene_input() -> void:
	var scene: PackedScene = load("res://scenes/combat/battle.tscn") as PackedScene
	var battle: Node2D = scene.instantiate() as Node2D
	battle.stages[0] = load("res://scenes/combat/stage.tres") as CombatStage
	root.add_child(battle)
	battle.set_process(false)
	battle.call("start_battle")
	await process_frame
	var turns: CombatTurns = battle.get("turns") as CombatTurns
	var actions: CombatActions = battle.get("actions") as CombatActions
	var units: Array[CombatUnit] = battle.get("units")
	var map: TileMapLayer = battle.get_node("Map") as TileMapLayer
	var hud: CombatTurnHud = battle.get_node("UI/TurnHud") as CombatTurnHud
	ScriptedDice.arrange_turns(turns, units, units)
	var destination: Vector2i = Vector2i(1, 6)
	var screen: Vector2 = map.get_global_transform_with_canvas() * map.map_to_local(destination)
	await _click(screen, MOUSE_BUTTON_RIGHT)
	_check(units[0].cell == Vector2i(1, 4) and not ((battle.get("selection") as CombatSelection).preview_path as Array).is_empty(), "이동 첫 클릭은 미리보기")
	await _click(screen, MOUSE_BUTTON_RIGHT)
	_check(units[0].cell == destination and units[0].movement_left == 4, "이동 두 번째 클릭 실행")
	units[2].cell = Vector2i(2, 6)
	units[2].parry_left = 0
	battle.call("_update_turn_ui")
	actions.dice = _dice_for([1, 1], [20, 10])
	var point: Vector2 = units[2].get_global_transform_with_canvas() * Vector2(0, -10)
	await _click(point)
	_check(units[0].action_left == 1 and (battle.get("selection") as CombatSelection).preview_target == units[2], "공격 첫 클릭은 피해·자원 소비 없음")
	await _click(point)
	_check(units[0].action_left == 0 and units[2].hit_points == 12, "공격 두 번째 클릭과 빗나감 처리")
	hud.action_selected.emit("surge")
	_check(units[0].surge_left == 1, "자기 대상 동작 첫 클릭은 선택만")
	hud.action_selected.emit("surge")
	_check(units[0].surge_left == 0 and units[0].action_left == 1, "자기 대상 동작 두 번째 클릭 실행")
	_check("몰아치기" in hud.message_label.text, "실행 결과 화면 피드백")
	actions.dice = _dice_for([11, 1, 1], [20, 10, 8])
	await _click(point)
	_check(units[0].action_left == 1 and units[2].hit_points == 12
		and (battle.get("selection") as CombatSelection).preview_target == units[2], "몰아치기 뒤 추가 공격 첫 클릭은 미리보기")
	await _click(point)
	_check(turns.current_unit == units[0] and units[0].action_left == 0
		and units[0].bonus_action_left == 0 and units[2].hit_points < 12,
		"아군은 같은 턴에 몰아치기 뒤 두 번째 클릭으로 추가 공격")
	turns.end_turn()
	turns.end_turn()
	_check(units[0].get_ability_sides(CombatUnit.Ability.STRENGTH) == 20
		and units[2].get_ability_sides(CombatUnit.Ability.STRENGTH) == 10,
		"실제 장면도 전사 힘d20과 풋내기 힘d10을 사용")
	actions.dice = _dice_for([5, 1, 5], [10, 20, 8])
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
	overlap.stages[0] = load("res://scenes/combat/stage.tres") as CombatStage
	root.add_child(overlap)
	overlap.set_process(false)
	overlap.call("start_battle")
	await process_frame
	var overlap_units: Array[CombatUnit] = overlap.get("units")
	var overlap_turns: CombatTurns = overlap.get("turns") as CombatTurns
	var overlap_hud: CombatTurnHud = overlap.get_node("UI/TurnHud") as CombatTurnHud
	var overlap_map: TileMapLayer = overlap.get_node("Map") as TileMapLayer
	ScriptedDice.arrange_turns(overlap_turns, overlap_units, overlap_units)
	var hidden_cell: Vector2i = overlap_units[0].cell - Vector2i.ONE
	var hidden_local: Vector2 = overlap_map.map_to_local(hidden_cell) + Vector2(5, 0)
	var hidden_screen: Vector2 = overlap_map.get_global_transform_with_canvas() * hidden_local
	_check(overlap_units[0].contains_body_point(overlap_units[0].to_local(overlap_map.to_global(hidden_local))),
		"빈 칸 입력점은 실제 도트 몸통에 가려진다")
	await _click(hidden_screen, MOUSE_BUTTON_RIGHT)
	_check((overlap.get("selection") as CombatSelection).preview_cell == hidden_cell, "이동 모드에서 몸통 뒤 빈 사각 칸 선택")
	await _click(hidden_screen, MOUSE_BUTTON_RIGHT)
	_check(overlap_units[0].cell == hidden_cell, "몸통에 가린 빈 칸 이동 실행")
	overlap_hud.action_selected.emit("attack")
	overlap_units[2].cell = Vector2i(4, 4)
	overlap_units[3].cell = Vector2i(5, 5)
	overlap.call("_update_turn_ui")
	var overlap_world: Vector2 = overlap_units[2].to_global(Vector2(0, -8))
	var overlap_point: Vector2 = overlap_units[2].get_global_transform_with_canvas() * Vector2(0, -8)
	_check(overlap_units[2].contains_body_point(Vector2(0, -8))
		and overlap_units[3].contains_body_point(overlap_units[3].to_local(overlap_world)),
		"겹침 입력점은 두 실제 도트 몸통에 모두 포함된다")
	await _click(overlap_point)
	_check((overlap.get("selection") as CombatSelection).preview_target == overlap_units[3], "겹친 몸통은 y-sort 앞쪽 유닛 선택")
	overlap.queue_free()
	await process_frame


func _test_scene_ally_shove() -> void:
	var battle: Node2D = (load("res://scenes/combat/battle.tscn") as PackedScene).instantiate() as Node2D
	battle.stages[0] = load("res://scenes/combat/stage.tres") as CombatStage
	root.add_child(battle)
	battle.set_process(false)
	battle.call("start_battle")
	await process_frame
	var units: Array[CombatUnit] = battle.get("units")
	var turns: CombatTurns = battle.get("turns") as CombatTurns
	var actions: CombatActions = battle.get("actions") as CombatActions
	var hud: CombatTurnHud = battle.get_node("UI/TurnHud") as CombatTurnHud
	ScriptedDice.arrange_turns(turns, units, units)
	units[1].cell = Vector2i(2, 4)
	battle.call("_update_turn_ui")
	actions.dice = _dice_for([], [])
	hud.action_selected.emit("shove")
	var point: Vector2 = units[1].get_global_transform_with_canvas() * Vector2(0, -10)
	await _click(point)
	_check((battle.get("selection") as CombatSelection).preview_target == units[1]
		and units[0].bonus_action_left == 1 and turns.current_unit == units[0],
		"실제 아군 몸통 첫 클릭은 조작 유닛을 바꾸지 않고 밀치기 미리보기")
	_check("밀려날 칸: 3, 4" in hud.preview_label.text, "아군 밀치기도 같은 착지 칸 안내")
	actions.grid.pits.append(Vector2i(3, 4))
	battle.call("_update_turn_ui")
	_check("밀려날 칸: 3, 4 · 낙사" in hud.preview_label.text, "밀치기 안내는 착지 칸과 같은 줄에 낙사를 보인다")
	actions.grid.pits.erase(Vector2i(3, 4))
	battle.call("_update_turn_ui")
	await _click(point)
	_check(units[1].cell == Vector2i(3, 4) and units[0].bonus_action_left == 0
		and units[1].movement_left == 6 and turns.current_unit == units[0],
		"실제 아군 몸통 두 번째 클릭은 무대결 밀치기를 실행")
	point = units[1].get_global_transform_with_canvas() * Vector2(0, -10)
	await _click(point)
	_check((battle.get("selection") as CombatSelection).preview_target == null
		and units[0].action_left == 1 and units[1].hit_points == 14,
		"기본 공격에서 아군 몸통 클릭은 계속 공격을 취소")
	battle.queue_free()
	await process_frame


func _test_isometric_unit_occlusion() -> void:
	var battle: Node2D = (load("res://scenes/combat/battle.tscn") as PackedScene).instantiate() as Node2D
	var stage: CombatStage = (load("res://scenes/combat/stage.tres") as CombatStage).duplicate() as CombatStage
	stage.heights = {Vector2i(5, 5): 4}
	battle.stages[0] = stage
	root.add_child(battle)
	battle.set_process(false)
	battle.call("start_battle")
	await process_frame
	var units: Array[CombatUnit] = battle.get("units")
	var turns: CombatTurns = battle.get("turns") as CombatTurns
	var map: CombatMap = battle.get_node("Map") as CombatMap
	units[1].cell = Vector2i(1, 4)
	units[2].cell = Vector2i(4, 4)
	ScriptedDice.arrange_turns(turns, units, units)
	turns.select_unit(units[1])
	battle.call("_update_turn_ui")
	var point: Vector2 = map.get_global_transform_with_canvas() * (
		map.map_to_surface(units[2].cell) + Vector2(0, -10))
	await _click(point)
	_check((battle.get("selection") as CombatSelection).preview_target == units[2]
		and units[1].action_left == 1 and units[2].hit_points == 12,
		"높은 지형에 몸통이 가려져도 사거리 안 적의 윤곽을 눌러 공격 미리보기")
	(battle.get("actions") as CombatActions).dice = _dice_for([1, 1], [20, 6])
	await _click(point)
	_check(units[1].action_left == 0 and units[2].hit_points == 12,
		"가린 적의 두 번째 클릭도 원거리 공격을 실행하고 행동1 소비")
	(battle.get("actions") as CombatActions).grid.heights.clear()
	map.build_grid((battle.get("actions") as CombatActions).grid, stage.tile_set)
	ScriptedDice.arrange_turns(turns, units, units)
	turns.select_unit(units[1])
	(battle.get("selection") as CombatSelection).clear_preview()
	battle.call("_update_turn_ui")
	await _click(point)
	_check((battle.get("selection") as CombatSelection).preview_target == units[2]
		and units[1].action_left == 1 and units[2].hit_points == 12,
		"가리는 지형이 없어지면 같은 화면 위치의 유닛을 미리보기")
	battle.queue_free()
	await process_frame


func _test_terrain_hidden_unit_outline() -> void:
	# 종류, 앞 칸, 앞 칸 바닥 높이, 그림이 못 가리는 몸통 px. 나무는 잎 틈으로 1px가 보인다.
	for config: Array in [["rock", Vector2i(6, 4), 1, 0], ["crate", Vector2i(6, 4), 1, 0],
			["ruin_wall", Vector2i(6, 4), 2, 0], ["tree", Vector2i(6, 4), 0, 1], ["cottage", Vector2i(5, 4), 1, 0]]:
		var kind: String = config[0]
		var front: Vector2i = config[1]
		var stage: CombatStage = (load("res://scenes/combat/stages/act2_stage1.tres") as CombatStage).duplicate() as CombatStage
		var heights: Dictionary[Vector2i, int] = stage.heights.duplicate()
		var scenery: Dictionary[Vector2i, String] = stage.scenery.duplicate()
		var footprint: Vector2i = CombatStage.SCENERY_SIZE.get(kind, Vector2i.ONE)
		for y: int in range(footprint.y):
			for x: int in range(footprint.x):
				heights[front + Vector2i(x, y)] = config[2]
		var props: Array[Vector2i] = [front]
		var none: Array[Vector2i] = []
		stage.heights = heights
		stage.rock_cells = props if kind == "rock" else none
		stage.crate_cells = props if kind == "crate" else none
		if CombatStage.SCENERY_SIZE.has(kind):
			scenery[front] = kind
		stage.scenery = scenery
		var battle: Node2D = (load("res://scenes/combat/battle.tscn") as PackedScene).instantiate() as Node2D
		battle.stages[0] = stage
		root.add_child(battle)
		battle.set_process(false)
		battle.call("start_battle")
		await process_frame
		var units: Array[CombatUnit] = battle.get("units")
		var map: CombatMap = battle.get_node("Map") as CombatMap
		var actions: CombatActions = battle.get("actions") as CombatActions
		var selection: CombatSelection = battle.get("selection") as CombatSelection
		var archer: CombatUnit = units[1]
		var spider: CombatUnit = units[2]
		archer.cell = Vector2i(2, 3)
		spider.cell = Vector2i(5, 3)
		ScriptedDice.arrange_turns(battle.get("turns") as CombatTurns, [archer, spider], [archer, spider])
		battle.call("_update_turn_ui")
		await process_frame
		var body: Array[Vector2] = []
		var hidden: Array[Vector2] = []
		for y: int in range(-40, 8):
			for x: int in range(-24, 25):
				var point: Vector2 = Vector2(x, y)
				if spider.contains_body_point(point):
					body.append(point)
					if map.occludes(spider.cell, map.to_local(spider.to_global(point))):
						hidden.append(point)
		_check(spider.kind == CombatUnit.Kind.SPIDERLING and not body.is_empty()
			and hidden.size() >= body.size() - (config[3] as int), "%s 뒤 새끼 거미의 몸통이 가려짐" % kind)
		_check(spider.is_occluded and (spider.get("_silhouette") as Sprite2D).visible,
			"%s에 몸통이 가린 유닛은 팀색 윤곽을 표시" % kind)
		_check(((spider.get("_silhouette") as Sprite2D).material as ShaderMaterial).get_shader_parameter("fill_alpha") > 0.0
			and not (map.get("_unit_markers") as Array).is_empty(), "가린 몸통의 채움과 발밑 위치를 표시")
		var faded: bool = false
		for marker: Node2D in (map.get("_blocked_markers") as Array) + (map.get("_prop_markers") as Array):
			faded = faded or marker.modulate.a < 1.0
		_check(faded, "가리는 사물만 옅게 표시하고 지형은 윤곽·발밑으로 보완")
		if hidden.is_empty():
			battle.queue_free()
			await process_frame
			continue
		var click: Vector2 = spider.get_global_transform_with_canvas() * hidden[hidden.size() / 2]
		await _click(click)
		_check(selection.preview_target == spider and selection.preview_prop == null and archer.action_left == 1,
			"%s에 가린 윤곽 첫 좌클릭은 공격 미리보기" % kind)
		actions.dice = _dice_for([1, 1], [20, 8])
		await _click(click)
		var placed: Array[CombatGrid.Prop] = actions.get_props()
		_check(archer.action_left == 0 and (placed.is_empty() or (placed[0].cell == front and placed[0].hit_points == 6)),
			"%s에 가린 윤곽 두 번째 좌클릭은 유닛 공격이며 사물은 그대로" % kind)
		if kind == "rock":
			await _check_rock_around_hidden_unit(battle, placed[0], hidden)
		battle.queue_free()
		await process_frame


func _check_rock_around_hidden_unit(battle: Node2D, rock: CombatGrid.Prop, hidden: Array[Vector2]) -> void:
	var units: Array[CombatUnit] = battle.get("units")
	var map: CombatMap = battle.get_node("Map") as CombatMap
	var actions: CombatActions = battle.get("actions") as CombatActions
	var selection: CombatSelection = battle.get("selection") as CombatSelection
	var spider: CombatUnit = units[2]
	var outside: Vector2 = Vector2.INF
	for y: int in range(-48, 8):
		for x: int in range(-24, 25):
			var point: Vector2 = map.map_to_surface(rock.cell) + Vector2(x, y)
			if (outside == Vector2.INF and map.prop_at_point(point) == rock
				and not spider.contains_body_point(spider.to_local(map.to_global(point)))):
				outside = point
	selection.clear_preview()
	await _click(map.get_global_transform_with_canvas() * outside)
	_check(outside != Vector2.INF and selection.preview_prop == rock,
		"가린 유닛 몸통 밖의 바위 픽셀은 계속 바위를 선택")
	var warrior: CombatUnit = units[0]
	spider.cell = Vector2i(9, 9)
	warrior.cell = Vector2i(5, 3)
	selection.clear_preview()
	battle.call("_update_turn_ui")
	var body: Vector2 = hidden[hidden.size() / 2]
	_check(warrior.is_occluded and not spider.is_occluded and warrior.contains_body_point(body),
		"바위 뒤로 옮긴 아군도 윤곽을 표시하고 클릭 지점은 아군 몸통")
	await _click(warrior.get_global_transform_with_canvas() * body)
	_check(selection.preview_prop == rock, "동작이 없는 가린 아군 몸통보다 앞 바위 선택을 우선")
	actions.grid.props.erase(rock)
	battle.call("_update_turn_ui")
	_check(not warrior.is_occluded, "바위가 사라진 같은 화면 갱신에서 윤곽을 해제")


func _test_jump_path() -> void:
	var f: Fixture = _fixture()
	var actor: CombatUnit = f.units[0]
	_check(f.actions.grid.jump_path(actor, Vector2i(4, 6)) == [Vector2i(4, 5), Vector2i(4, 6)],
		"평지 점프는 출발에서2칸 떨어진 착지까지 선택한 경로를 공개 질의로 반환")


func _test_jump_height_path() -> void:
	var f: Fixture = _fixture()
	var actor: CombatUnit = f.units[0]
	var destination: Vector2i = Vector2i(4, 6)
	var middle: Vector2i = Vector2i(4, 5)
	f.actions.grid.heights[destination] = 3
	_check(f.actions.grid.jump_path(actor, destination).is_empty(), "점프 착지 상승3은 금지")
	f.actions.grid.heights[destination] = 2
	_check(f.actions.grid.jump_path(actor, destination) == [middle, destination], "점프 착지 상승2는 허용")
	f.actions.grid.heights[destination] = 0
	f.actions.grid.heights[middle] = 2
	_check(f.actions.grid.jump_path(actor, destination).is_empty(), "점프 중간 바닥 상승2는 최종Q12에 따라 금지")
	f.actions.grid.heights[middle] = 99
	f.actions.grid.pits = [middle]
	_check(f.actions.grid.jump_path(actor, destination) == [middle, destination],
		"중간 낭떠러지는 바닥 높이가 없으므로 가상 높이를 비교하지 않고 통과")
	f.actions.grid.pits = [destination]
	_check(f.actions.grid.jump_path(actor, destination).is_empty(), "낭떠러지에는 점프 착지 금지")


func _test_jump_routes() -> void:
	var f: Fixture = _fixture()
	var actor: CombatUnit = f.units[0]
	var destination: Vector2i = Vector2i(5, 5)
	f.units[2].cell = Vector2i(9, 0)
	_check(f.actions.grid.jump_path(actor, destination) == [Vector2i(5, 4), destination],
		"두 대각선 최단 경로가 열리면 기존4방향 순서의 첫 경로 선택")
	f.actions.grid.blocked_cells = [Vector2i(5, 4)]
	_check(f.actions.grid.jump_path(actor, destination) == [Vector2i(4, 5), destination],
		"대각선 첫 경로가 막히면 두 번째 열린 경로 선택")
	f.actions.grid.blocked_cells.append(Vector2i(4, 5))
	_check(f.actions.grid.jump_path(actor, destination).is_empty(), "두 대각선 경로가 모두 막히면 점프 거부")
	f.actions.grid.blocked_cells.clear()
	f.units[1].cell = Vector2i(5, 4)
	_check(f.actions.grid.jump_path(actor, destination) == [Vector2i(4, 5), destination],
		"아군 점유 중간 칸은 건너뛰지 않고 다른 열린 경로 선택")
	f.units[1].hit_points = 0
	_check(f.actions.grid.jump_path(actor, destination) == [Vector2i(5, 4), destination],
		"전투 불능 유닛은 점프 중간 칸을 점유하지 않음")
	f.actions.grid.heights[Vector2i(5, 4)] = 2
	_check(f.actions.grid.jump_path(actor, Vector2i(5, 4)) == [Vector2i(5, 4)]
		and f.actions.jump_cells(actor).get(Vector2i(5, 4), -1) == 3,
		"옆 칸 높이2 점프는 중간 칸 없이 이동3 소비")
	_check(f.actions.grid.jump_path(actor, actor.cell).is_empty()
		and f.actions.grid.jump_path(actor, Vector2i(7, 4)).is_empty()
		and f.actions.grid.jump_path(actor, Vector2i(-1, 4)).is_empty(), "같은 칸·거리3·맵 밖 점프 거부")


func _test_blocked_cells() -> void:
	var f: Fixture = _fixture()
	var actor: CombatUnit = f.units[0]
	var middle: Vector2i = Vector2i(4, 5)
	var destination: Vector2i = Vector2i(4, 6)
	f.actions.grid.blocked_cells = [middle]
	_check(f.actions.grid.jump_path(actor, destination).is_empty(), "명시적 벽·장애물이 있는 중간 칸은 점프 통과 금지")
	_check(not f.actions.can_move(actor, middle) and middle not in f.actions.grid.empty_neighbors(actor.cell),
		"막힌 칸은 걷기와 빈 인접 칸 질의에서도 제외")
	f.actions.grid.blocked_cells = [destination]
	_check(f.actions.grid.jump_path(actor, destination).is_empty()
		and f.actions.grid.path_to(actor, destination).is_empty(), "막힌 바닥에는 걷거나 점프 착지 금지")
	f.actions.grid.blocked_cells = [Vector2i(6, 4)]
	_check(not f.actions.grid.can_shove(actor, f.units[2]), "막힌 칸으로 밀치기 금지")
	f.actions.grid.blocked_cells = [Vector2i(4, 5), Vector2i(4, 3)]
	_check(f.actions.grid.pull_cells(actor, f.units[3]).is_empty(), "막힌 칸으로 끌기 금지")
	actor.kind = CombatUnit.Kind.MOTHER_SPIDER
	_check(not f.actions.can_use(actor, "spawn"), "점유 칸과 막힌 칸뿐이면 소환 거부")


func _test_jump_scene_input() -> void:
	var battle: Node2D = (load("res://scenes/combat/battle.tscn") as PackedScene).instantiate() as Node2D
	var stage: CombatStage = (load("res://scenes/combat/stage.tres") as CombatStage).duplicate() as CombatStage
	var destination: Vector2i = Vector2i(1, 6)
	stage.pits = [Vector2i(1, 5)]
	stage.heights = {destination: 2}
	stage.blocked_cells = [Vector2i(2, 5)]
	battle.stages[0] = stage
	root.add_child(battle)
	battle.set_process(false)
	battle.call("start_battle")
	await process_frame
	var units: Array[CombatUnit] = battle.get("units")
	var actions: CombatActions = battle.get("actions") as CombatActions
	var turns: CombatTurns = battle.get("turns") as CombatTurns
	var hud: CombatTurnHud = battle.get_node("UI/TurnHud") as CombatTurnHud
	var map: CombatMap = battle.get_node("Map") as CombatMap
	var selection: CombatSelection = battle.get("selection") as CombatSelection
	ScriptedDice.arrange_turns(turns, units, [units[1], units[0], units[3], units[2]])
	turns.select_unit(units[0])
	actions.dice = _dice_for([], [])
	var button: Button = (hud.get("_actions") as Dictionary)["jump"] as Button
	_check(button.is_visible_in_tree() and not button.disabled, "실제 장면에 공용 점프 버튼 표시")
	button.pressed.emit()
	var point: Vector2 = map.get_global_transform_with_canvas() * map.map_to_surface(Vector2i(2, 5))
	await _click(point, MOUSE_BUTTON_RIGHT)
	_check(selection.selected_action == "jump" and selection.preview_path.is_empty()
		and units[0].movement_left == 6 and units[0].bonus_action_left == 1, "막힌 착지 클릭은 점프와 자원 보존")
	button.pressed.emit()
	point = map.get_global_transform_with_canvas() * map.map_to_surface(destination)
	await _click(point, MOUSE_BUTTON_RIGHT)
	_check(selection.selected_action == "jump" and selection.preview_path == [Vector2i(1, 5), destination]
		and units[0].cell == Vector2i(1, 4) and units[0].movement_left == 6,
		"첫 우클릭은 낭떠러지를 넘는 선택 경로와 상승2 착지를 미리보기")
	_check(hud.preview_label.visible and "이동 4" in hud.preview_label.text
		and "보조 행동1" in hud.preview_label.text and "기회 공격 없음" in hud.preview_label.text
		and "낙하 없음" in hud.preview_label.text, "점프 미리보기는 비용과 기회 공격·낙하 위험 표시")
	await _click(map.get_global_transform_with_canvas() * map.map_to_surface(Vector2i.ZERO))
	_check(selection.selected_action == "attack" and selection.preview_path.is_empty()
		and units[0].movement_left == 6 and units[0].bonus_action_left == 1, "필드 좌클릭으로 점프 취소, 비용 없음")
	button.pressed.emit()
	await _click(point, MOUSE_BUTTON_RIGHT)
	await _click(point, MOUSE_BUTTON_RIGHT)
	_check(units[0].cell == destination and units[0].movement_left == 2 and units[0].bonus_action_left == 0
		and selection.selected_action == "attack" and selection.preview_path.is_empty(),
		"같은 착지 두 번째 우클릭은 점프 비용만 쓰고 기본 공격으로 복귀")
	_check(units[0].position + Vector2(0, units[0].floor_offset_y) == map.map_to_surface(destination),
		"점프 실행 후 표시한 발 위치는 착지 표면과 일치")
	battle.queue_free()
	await process_frame


func _test_jump_scene_animation() -> void:
	var battle: Node2D = (load("res://scenes/combat/battle.tscn") as PackedScene).instantiate() as Node2D
	var stage: CombatStage = (load("res://scenes/combat/stage.tres") as CombatStage).duplicate() as CombatStage
	var origin: Vector2i = Vector2i(4, 4)
	var destination: Vector2i = Vector2i(4, 6)
	stage.ally_cells = [origin, Vector2i.ZERO]
	stage.heights = {origin: 3, Vector2i(5, 4): 2}
	stage.pits = [Vector2i(4, 5)]
	battle.stages[0] = stage
	root.add_child(battle)
	battle.set_process(false)
	battle.call("start_battle")
	await process_frame
	var units: Array[CombatUnit] = battle.get("units")
	var actor: CombatUnit = units[0]
	var actions: CombatActions = battle.get("actions") as CombatActions
	var turns: CombatTurns = battle.get("turns") as CombatTurns
	var hud: CombatTurnHud = battle.get_node("UI/TurnHud") as CombatTurnHud
	var map: CombatMap = battle.get_node("Map") as CombatMap
	units[2].cell = Vector2i(5, 4)
	units[3].cell = Vector2i(9, 9)
	ScriptedDice.arrange_turns(turns, units, [units[1], units[0], units[3], units[2]])
	turns.select_unit(actor)
	actions.dice = _dice_for([1, 4], [10, 20])
	var point: Vector2 = map.get_global_transform_with_canvas() * map.map_to_surface(destination)
	((hud.get("_actions") as Dictionary)["jump"] as Button).pressed.emit()
	await _click(point, MOUSE_BUTTON_RIGHT)
	_check("기회 공격 1명" in hud.preview_label.text and "낙하 피해 2" in hud.preview_label.text,
		"점프 미리보기는 실제 출발 인접 반응과 최대HP12의 낙하 피해2 표시")
	var before: int = actor.hit_points
	var finished: Array[bool] = [false]
	_jump_scene(actions, actor, destination, finished)
	_check(actions.busy and not actor.is_moving and actor.cell == origin
		and actor.movement_left == 6 and actor.bonus_action_left == 1,
		"기회 공격 연출 중에는 점프 비용과 논리 원점을 유지한다")
	for frame: int in range(600):
		if actor.is_moving or finished[0]:
			break
		await process_frame
	_check(actions.busy and actor.is_moving and actor.cell == origin
		and actor.movement_left == 4 and actor.bonus_action_left == 0 and actor.hit_points == before,
		"기회 공격 생존 후 비용을 먼저 쓰고 논리 원점에서 점프 연출, 착지 피해 대기")
	hud.end_button.pressed.emit()
	hud.unit_selected.emit(units[1])
	_check(turns.current_unit == actor and not actions.can_use(actor, "jump"), "점프 중 턴 종료·아군 전환·중복 실행 잠금")
	await process_frame
	await process_frame
	await process_frame
	_check(actor.body_offset_y < 0 and actor.cell == origin and actor.hit_points == before,
		"공중 연출 중 몸은 떠 있고 중간 칸의 낙하·착지 효과 없음")
	while not finished[0]:
		await process_frame
	_check(actor.cell == destination and actor.hit_points == before - 2 and not actions.busy
		and not actor.is_moving and actor.body_offset_y == 0.0
		and actor.position + Vector2(0, actor.floor_offset_y) == map.map_to_surface(destination),
		"착지 후에만 낙하 피해와 논리 칸을 적용하고 표시·잠금 복구")
	battle.queue_free()
	await process_frame


func _jump_scene(actions: CombatActions, actor: CombatUnit, destination: Vector2i, finished: Array[bool]) -> void:
	await actions.jump_to(actor, destination)
	finished[0] = true


func _test_height_scene_input() -> void:
	var battle: Node2D = (load("res://scenes/combat/battle.tscn") as PackedScene).instantiate() as Node2D
	var stage: CombatStage = (load("res://scenes/combat/stage.tres") as CombatStage).duplicate() as CombatStage
	stage.heights = {Vector2i(1, 4): 1, Vector2i(1, 5): 2, Vector2i(3, 5): 4}
	battle.stages[0] = stage
	root.add_child(battle)
	battle.set_process(false)
	battle.call("start_battle")
	await process_frame
	var units: Array[CombatUnit] = battle.get("units")
	var turns: CombatTurns = battle.get("turns") as CombatTurns
	var actions: CombatActions = battle.get("actions") as CombatActions
	var map: TileMapLayer = battle.get_node("Map") as TileMapLayer
	ScriptedDice.arrange_turns(turns, units, units)
	_check(actions.grid.height_at(Vector2i(1, 4)) == 1
		and not actions.can_move(units[0], Vector2i(3, 5)), "실제 스테이지 높이가 걷기 판정에 연결")
	_check(units[0].position + Vector2(0, units[0].floor_offset_y) == map.map_to_local(Vector2i(1, 4)) - Vector2(0, 8),
		"높이1 유닛의 발은16px 바닥의 절반인8px 위에 표시")
	var destination: Vector2i = Vector2i(1, 5)
	var point: Vector2 = map.get_global_transform_with_canvas() * (map.map_to_local(destination) - Vector2(0, 16))
	await _click(point, MOUSE_BUTTON_RIGHT)
	_check((battle.get("selection") as CombatSelection).preview_cell == destination
		and units[0].cell == Vector2i(1, 4) and units[0].movement_left == 6,
		"높이2 바닥의 실제 표면 첫 클릭은 올바른 칸을 미리보기")
	await _click(point, MOUSE_BUTTON_RIGHT)
	_check(units[0].cell == destination and units[0].movement_left == 5
		and units[0].position + Vector2(0, units[0].floor_offset_y) == map.map_to_local(destination) - Vector2(0, 16),
		"높이 표면 두 번째 클릭은 이동1과 도착 표시 높이를 일치")
	point = map.get_global_transform_with_canvas() * (map.map_to_local(Vector2i(3, 5)) - Vector2(0, 32))
	await _click(point, MOUSE_BUTTON_RIGHT)
	await _click(point, MOUSE_BUTTON_RIGHT)
	_check((battle.get("selection") as CombatSelection).preview_path.is_empty()
		and units[0].cell == destination and units[0].movement_left == 5,
		"높이 차2의 바닥 표면 클릭도 이동·자원 소비 거부")
	point = map.get_global_transform_with_canvas() * (map.map_to_local(Vector2i(2, 4)) - Vector2(0, 4))
	await _click(point, MOUSE_BUTTON_RIGHT)
	await _click(point, MOUSE_BUTTON_RIGHT)
	_check((battle.get("selection") as CombatSelection).preview_path.is_empty()
		and units[0].cell == destination and units[0].movement_left == 5,
		"앞 칸의 높은 옆면을 눌러도 가려진 뒤 칸을 선택하거나 이동하지 않음")
	(battle.get("progress") as CombatActProgress).stage_index = 1
	battle.call("_start_stage", true)
	battle.call("start_battle")
	_check(actions.grid.heights == battle.stages[1].heights
		and units[0].position == map.map_to_local(units[0].cell),
		"다음 실제 스테이지의 높이로 교체하고 fixture 높이를 이어받지 않음")
	battle.queue_free()
	await process_frame


func _test_blocked_scene_input() -> void:
	var battle: Node2D = (load("res://scenes/combat/battle.tscn") as PackedScene).instantiate() as Node2D
	var stage: CombatStage = (load("res://scenes/combat/stage.tres") as CombatStage).duplicate() as CombatStage
	var blocked: Vector2i = Vector2i(2, 4)
	stage.blocked_cells = [blocked]
	battle.stages[0] = stage
	root.add_child(battle)
	battle.set_process(false)
	battle.call("start_battle")
	await process_frame
	var units: Array[CombatUnit] = battle.get("units")
	var turns: CombatTurns = battle.get("turns") as CombatTurns
	var actions: CombatActions = battle.get("actions") as CombatActions
	var map: CombatMap = battle.get_node("Map") as CombatMap
	ScriptedDice.arrange_turns(turns, units, units)
	_check(actions.grid.blocked_cells == [blocked] and actions.grid.is_floor(blocked)
		and map.get_used_cells().size() == 100, "실제 스테이지의 막힌 칸은 바닥을 유지하고 판정에 연결")
	_check(map.has_node("BlockedCell") and (map.get_node_or_null("BlockedCell") as Node2D).visible,
		"막힌 바닥은 낭떠러지와 구분할 수 있는 표시를 유지")
	var point: Vector2 = map.get_global_transform_with_canvas() * map.map_to_surface(blocked)
	await _click(point, MOUSE_BUTTON_RIGHT)
	await _click(point, MOUSE_BUTTON_RIGHT)
	_check(units[0].cell == Vector2i(1, 4) and units[0].movement_left == 6
		and (battle.get("selection") as CombatSelection).preview_path.is_empty(),
		"막힌 바닥의 두 번 우클릭은 이동·자원을 소비하지 않음")
	(battle.get("progress") as CombatActProgress).stage_index = 1
	battle.call("_start_stage", true)
	battle.call("start_battle")
	_check(actions.grid.blocked_cells == battle.stages[1].get_blocked_cells() and not actions.grid.is_blocked(blocked)
		and map.get_used_cells().size() == 100, "다음 스테이지는 막힌 칸 fixture를 이어받지 않음")
	_check(not map.has_node("BlockedCell"), "다음 스테이지에서 막힌 칸 표시 정리")
	battle.queue_free()
	await process_frame


func _test_scene_fall_feedback() -> void:
	var battle: Node2D = (load("res://scenes/combat/battle.tscn") as PackedScene).instantiate() as Node2D
	var stage: CombatStage = (load("res://scenes/combat/stage.tres") as CombatStage).duplicate() as CombatStage
	stage.ally_cells = [Vector2i(1, 4), Vector2i(2, 4)]
	stage.heights = {Vector2i(1, 4): 2, Vector2i(2, 4): 3}
	battle.stages[0] = stage
	root.add_child(battle)
	battle.set_process(false)
	battle.call("start_battle")
	await process_frame
	var units: Array[CombatUnit] = battle.get("units")
	var turns: CombatTurns = battle.get("turns") as CombatTurns
	var actions: CombatActions = battle.get("actions") as CombatActions
	var map: CombatMap = battle.get_node("Map") as CombatMap
	ScriptedDice.arrange_turns(turns, units, [units[1], units[0], units[3], units[2]])
	turns.select_unit(units[0])
	actions.dice = _dice_for([], [])
	var feedback_feet: Array[Vector2] = []
	actions.feedback.connect(func(unit: CombatUnit, text: String) -> void:
		if unit == units[1] and text == "3":
			feedback_feet.append(unit.position + Vector2(0, unit.floor_offset_y)))
	_check(actions.shove(units[0], units[1]) and units[1].cell == Vector2i(3, 4)
		and units[1].hit_points == 11 and units[0].bonus_action_left == 0,
		"실제 장면의3칸 낙하는 고정 피해3과 밀치기 비용을 적용")
	_check(feedback_feet == [map.map_to_surface(Vector2i(3, 4))],
		"실제 낙하 피해 피드백은 착지 바닥의 유닛 위치에서 발생")
	battle.queue_free()
	await process_frame


func _test_pit_scene_input() -> void:
	var battle: Node2D = (load("res://scenes/combat/battle.tscn") as PackedScene).instantiate() as Node2D
	var stage: CombatStage = (load("res://scenes/combat/stage.tres") as CombatStage).duplicate() as CombatStage
	var pit: Vector2i = Vector2i(2, 4)
	stage.pits = [pit]
	battle.stages[0] = stage
	root.add_child(battle)
	battle.set_process(false)
	battle.call("start_battle")
	await process_frame
	var units: Array[CombatUnit] = battle.get("units")
	var turns: CombatTurns = battle.get("turns") as CombatTurns
	var actions: CombatActions = battle.get("actions") as CombatActions
	var map: TileMapLayer = battle.get_node("Map") as TileMapLayer
	ScriptedDice.arrange_turns(turns, units, units)
	_check(actions.grid.pits == [pit] and not actions.can_move(units[0], pit)
		and map.get_used_cells().size() == 99 and pit not in map.get_used_cells(),
		"실제 낭떠러지 스테이지는 바닥을 그리지 않고 걷기도 금지")
	var point: Vector2 = map.get_global_transform_with_canvas() * map.map_to_local(pit)
	await _click(point, MOUSE_BUTTON_RIGHT)
	await _click(point, MOUSE_BUTTON_RIGHT)
	_check(units[0].cell == Vector2i(1, 4) and units[0].movement_left == 6
		and (battle.get("selection") as CombatSelection).preview_path.is_empty(),
		"보이는 낭떠러지의 두 번 우클릭은 이동·자원을 소비하지 않음")
	(battle.get("progress") as CombatActProgress).stage_index = 1
	battle.call("_start_stage", true)
	battle.call("start_battle")
	_check(actions.grid.pits.is_empty() and map.get_used_cells().size() == 100,
		"다음 실제 스테이지는 낭떠러지 fixture를 이어받지 않고 평면100칸 복귀")
	battle.queue_free()
	await process_frame


func _test_pit_scene_victory() -> void:
	var battle: Node2D = (load("res://scenes/combat/battle.tscn") as PackedScene).instantiate() as Node2D
	var stage: CombatStage = (load("res://scenes/combat/stage.tres") as CombatStage).duplicate() as CombatStage
	stage.ally_cells = [Vector2i(4, 4), Vector2i(3, 4)]
	stage.pits = [Vector2i(6, 4)]
	battle.stages[0] = stage
	root.add_child(battle)
	battle.set_process(false)
	battle.call("start_battle")
	await process_frame
	var units: Array[CombatUnit] = battle.get("units")
	var turns: CombatTurns = battle.get("turns") as CombatTurns
	var actions: CombatActions = battle.get("actions") as CombatActions
	var hud: CombatTurnHud = battle.get_node("UI/TurnHud") as CombatTurnHud
	ScriptedDice.arrange_turns(turns, units, units)
	units[2].cell = Vector2i(5, 4)
	units[2].is_stunned = true
	actions.incapacitate(units[3])
	battle.call("_update_turn_ui")
	# 무굴림 밀치기가 끝난 뒤 승리 보상에만 별도의 RNG를 쓴다.
	actions.dice = _dice_for([], [])
	var reward_dice: CombatDice = CombatDice.new()
	reward_dice.seed = 321
	var use_reward_dice: Callable = func(message: String) -> void:
		if message == "밀치기 성공":
			actions.dice = reward_dice
	actions.logged.connect(use_reward_dice)
	hud.action_selected.emit("shove")
	var point: Vector2 = units[2].get_global_transform_with_canvas() * Vector2(0, -10)
	await _click(point)
	await _click(point)
	_check(actions.is_victory() and units[2].hit_points == 0 and not units[2].visible
		and hud.get_node("Result").visible and "낙사" in hud.message_label.text,
		"기절시킨 마지막 적을 실제 HUD·몸통 입력으로 밀면 낙사 로그와 승리 결과 표시")
	actions.logged.disconnect(use_reward_dice)
	battle.queue_free()
	await process_frame


func _test_scene_shock() -> void:
	var scene: PackedScene = load("res://scenes/combat/battle.tscn") as PackedScene
	var battle: Node2D = scene.instantiate() as Node2D
	battle.stages[0] = load("res://scenes/combat/stage.tres") as CombatStage
	root.add_child(battle)
	battle.set_process(false)
	battle.call("start_battle")
	await process_frame
	var units: Array[CombatUnit] = battle.get("units")
	var turns: CombatTurns = battle.get("turns") as CombatTurns
	var actions: CombatActions = battle.get("actions") as CombatActions
	var hud: CombatTurnHud = battle.get_node("UI/TurnHud") as CombatTurnHud
	ScriptedDice.arrange_turns(turns, units, units)
	units[3].cell = Vector2i(3, 5)
	turns.select_unit(units[1])
	var buttons: Dictionary = hud.get("_actions")
	var shock_button: Button = buttons["shock"] as Button
	_check(shock_button.visible and not shock_button.disabled, "실제 장면의 충격 화살 버튼 활성화")
	shock_button.pressed.emit()
	var before_miss: int = units[3].hit_points
	actions.dice = _dice_for([1, 1], [20, 10])
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


func _click(point: Vector2, button_index: MouseButton = MOUSE_BUTTON_LEFT) -> void:
	var battle: Node2D
	for child: Node in root.get_children():
		if child.is_queued_for_deletion():
			continue
		if child is Node2D and child.has_node("Map") and child.has_node("UI/TurnHud"):
			battle = child as Node2D
		else:
			battle = child.get_node_or_null("Battle") as Node2D
		if battle != null and not battle.is_queued_for_deletion():
			break
	if battle == null:
		_check(false, "포인터 검사의 활성 전투 장면이 존재한다")
		return
	var already_busy: bool = (battle.get("actions") as CombatActions).busy
	var event: InputEventMouseButton = InputEventMouseButton.new()
	event.position = root.get_final_transform() * point
	event.global_position = event.position
	event.button_index = button_index
	event.pressed = true
	Input.parse_input_event(event)
	await process_frame
	event.pressed = false
	Input.parse_input_event(event)
	await process_frame
	var actions: CombatActions = battle.get("actions") as CombatActions
	var hud: CombatTurnHud = battle.get("hud") as CombatTurnHud
	for frame: int in range(600):
		var moving: bool = false
		for unit: CombatUnit in battle.get("units"):
			moving = moving or unit.is_moving
		if not moving and not battle.has_node("Arrow") and (not actions.busy or already_busy or hud.reaction_dialog.visible):
			return
		await process_frame
	_check(false, "포인터 입력 후 연출이 제한 시간 안에 끝나지 않음")
