extends SceneTree
## 궁수 2a(#500): 기름 장판(생성·갱신·시전자 사후 유지), 점화와 속성 반응표, 미끌거림, 넘어짐, 기름병 던지기, 저장.
## design.md의 「테스트할 seam」 목록만 다룬다.

class Fixture extends RefCounted:
	var units: Array[CombatUnit] = []
	var turns: CombatTurns = CombatTurns.new()
	var actions: CombatActions = CombatActions.new()
	var logs: Array[String] = []


const ScriptedDice = preload("res://tests/scripted_dice.gd")

var _checks: int = 0
var _failures: int = 0
var _created: Array[CombatUnit] = []


func _initialize() -> void:
	create_timer(30.0).timeout.connect(func() -> void:
		push_error("Combat oil: test timeout")
		quit(1)
	)
	_run.call_deferred()


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error(message)


## 아군 궁수(3,4)·아군 전사(3,6), 적 전사(5,4)·적 궁수(7,4). 순서는 궁수, 전사, 적 전사, 적 궁수다.
func _fixture() -> Fixture:
	var f: Fixture = Fixture.new()
	var kinds: Array[CombatUnit.Kind] = [CombatUnit.Kind.ARCHER, CombatUnit.Kind.WARRIOR, CombatUnit.Kind.WARRIOR,
		CombatUnit.Kind.ARCHER]
	var cells: Array[Vector2i] = [Vector2i(3, 4), Vector2i(3, 6), Vector2i(5, 4), Vector2i(7, 4)]
	for index: int in range(4):
		var unit: CombatUnit = CombatUnit.new()
		unit.kind = kinds[index]
		unit.is_ally = index < 2
		unit.cell = cells[index]
		unit.hit_points = unit.get_max_hit_points()
		f.units.append(unit)
		_created.append(unit)
	ScriptedDice.arrange_turns(f.turns, f.units, f.units)
	f.actions.initialize(f.units, f.turns)
	f.actions.logged.connect(f.logs.append)
	return f


func _dice(values: Array[int], sides: Array[int]) -> ScriptedDice:
	return ScriptedDice.new(values, sides)


func _oil_cells(f: Fixture) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for ground: CombatActions.Ground in f.actions.get_grounds():
		if ground.kind == "oil":
			cells.append(ground.cell)
	return cells


func _grounds_of(f: Fixture, kind: String) -> int:
	return f.actions.get_grounds().filter(func(ground: CombatActions.Ground) -> bool: return ground.kind == kind).size()


## 한 칸짜리 기름 장판을 직접 둔다. 십자 모양 없이 칸 하나만 필요한 검사에 쓴다.
func _single_oil(f: Fixture, cell: Vector2i, source: CombatUnit) -> void:
	f.actions._grounds.append(CombatActions.Ground.new(source, cell, "oil"))


func _run() -> void:
	await _test_pure_rules()
	await _test_create_oil()
	await _test_ignite()
	await _test_touch_attribute()
	await _test_leaving_slip()
	await _test_entering_slip()
	await _test_forced_entry_slip()
	await _test_turn_start_release()
	await _test_fallen_limits_and_stand_up()
	await _test_fallen_agility_save()
	await _test_oil_clock()
	await _test_oil_throw()
	await _test_status_text()
	await _test_save()
	for unit: CombatUnit in _created:
		unit.free()
	var dice_problems: Array[String] = ScriptedDice.finish()
	_check(dice_problems.is_empty(), "준비한 주사위 값을 요청대로 모두 굴림 " + str(dice_problems))
	print("Combat oil: %d checks, %d failures" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)


## 반응표, 이어진 기름 칸, 십자 모양, 일어서기 비용 (CombatOil 순수 규칙).
func _test_pure_rules() -> void:
	_check(CombatOil.reaction("fire", "oil") == "ignite", "화염은 기름을 점화")
	_check(CombatOil.reaction("water", "oil") == "remove" and CombatOil.reaction("water", "burn") == "remove",
		"물은 기름과 불 장판을 지움")
	_check(CombatOil.reaction("fire", "burn") == "" and CombatOil.reaction("none", "oil") == ""
		and CombatOil.reaction("water", "poison") == "", "그 밖의 조합은 반응 없음")
	_check(CombatOil.standing_cost(6) == 3 and CombatOil.standing_cost(3) == 2 and CombatOil.standing_cost(5) == 3,
		"일어서기 비용은 최대 이동력의 절반을 올림")
	var cross: Array[Vector2i] = CombatOil.cross_cells(Vector2i(4, 4))
	_check(cross.size() == 5 and Vector2i(4, 4) in cross and Vector2i(3, 4) in cross and Vector2i(5, 4) in cross
		and Vector2i(4, 3) in cross and Vector2i(4, 5) in cross and not (Vector2i(3, 3) in cross),
		"십자 모양은 중심과 상하좌우 5칸")
	var oil: Array[Vector2i] = [Vector2i(4, 4), Vector2i(4, 5), Vector2i(5, 5), Vector2i(7, 7)]
	var group: Array[Vector2i] = CombatOil.connected(Vector2i(4, 4), oil)
	_check(group.size() == 3 and Vector2i(7, 7) not in group and Vector2i(5, 5) in group,
		"점화 범위는 상하좌우로 이어진 기름 칸 전체")
	_check(CombatOil.connected(Vector2i(9, 9), oil).is_empty(), "기름이 아닌 칸은 이어진 범위가 없음")


## 생성, 갱신(같은 칸은 하나, 기간만 3), 물·막힌 칸 거부, 높이 차 밖 칸 제외.
func _test_create_oil() -> void:
	var f: Fixture = _fixture()
	var archer: CombatUnit = f.units[0]
	_check(f.actions.create_oil(archer, Vector2i(4, 4)), "기름병 던지기 장판 생성")
	_check(_grounds_of(f, "oil") == 5 and f.actions.get_grounds().all(func(ground: CombatActions.Ground) -> bool:
		return ground.kind != "oil" or (ground.turns_left == 3 and ground.source == archer)),
		"십자 5칸에 3턴 기름, 시전자는 궁수")
	_check(f.units[0].status_effects.is_empty() and archer.fallen == false,
		"기름 생성은 점유 유닛에게 즉시 효과를 주지 않음")
	_check(f.actions.create_oil(f.units[1], Vector2i(4, 4)) and _grounds_of(f, "oil") == 5
		and f.actions.get_grounds()[0].source == archer, "같은 칸 갱신은 칸 하나를 유지하고 원 시전자를 유지")
	f.actions.grid.water_cells = [Vector2i(4, 3)]
	_check(not f.actions.create_oil(archer, Vector2i(4, 3)), "물 칸 중심은 거부")
	var g: Fixture = _fixture()
	g.actions.grid.blocked_cells = [Vector2i(4, 3)]
	g.actions.grid.water_cells = [Vector2i(3, 4)]
	_check(g.actions.create_oil(g.units[0], Vector2i(4, 4)) and _grounds_of(g, "oil") == 3,
		"막힌 칸과 물 칸을 뺀 나머지 칸에만 기름")
	var h: Fixture = _fixture()
	h.actions.grid.heights = {Vector2i(4, 5): 2}
	_check(h.actions.create_oil(h.units[0], Vector2i(4, 4)) and _grounds_of(h, "oil") == 4 and Vector2i(4, 5) not in _oil_cells(h),
		"높이 차 2 이상인 칸은 기름이 없음")
	_check(not h.actions.create_oil(h.units[0], Vector2i(-1, 0)), "맵 밖 중심은 거부")


## 점화: 이어진 기름 칸 전체가 타고, 그 칸 위 모든 유닛이 화상 2중첩, 물 칸 유닛은 화상 없음.
func _test_ignite() -> void:
	var f: Fixture = _fixture()
	var archer: CombatUnit = f.units[0]
	f.actions.create_oil(archer, Vector2i(4, 4))
	f.units[1].cell = Vector2i(4, 5)
	f.actions.create_ground(f.units[3], Vector2i(9, 9), "burn")
	_check(not f.actions.ignite(Vector2i(9, 9), archer) and _grounds_of(f, "oil") == 5,
		"기름이 없는 칸은 점화하지 않음")
	_check(f.actions.ignite(Vector2i(4, 4), archer) and _grounds_of(f, "oil") == 0,
		"점화하면 이어진 기름 칸이 모두 사라짐")
	_check(archer.get_status_count("burn") == 2 and f.units[1].get_status_count("burn") == 2
		and archer.status_effects[0].source == archer, "점화로 그 칸 위 유닛이 화상 2중첩, 화상 시전자는 점화한 유닛")
	var g: Fixture = _fixture()
	g.actions.create_oil(g.units[0], Vector2i(4, 4))
	g.actions.grid.water_cells = [Vector2i(3, 4)]
	g.actions.ignite(Vector2i(4, 4), g.units[0])
	_check(g.units[0].get_status_count("burn") == 0 and g.units[0].hit_points == g.units[0].get_max_hit_points(),
		"물 칸 위 유닛은 화상을 받지 않음")
	_check(f.actions.get_grounds().filter(func(ground: CombatActions.Ground) -> bool: return ground.kind == "burn").size() == 1,
		"점화는 다른 칸의 불 장판을 건드리지 않음")
	# 불 장판이 기름 칸에 닿으면 점화하고 그 칸에 불 장판을 새로 두지 않는다.
	var h: Fixture = _fixture()
	h.actions.create_oil(h.units[0], Vector2i(4, 4))
	_check(h.actions.create_ground(h.units[3], Vector2i(4, 4), "burn") and _grounds_of(h, "oil") == 0
		and _grounds_of(h, "burn") == 0, "불 장판이 기름 칸에 생기면 점화하고 불 장판은 남지 않음")


## 속성 반응표를 칸에 적용: 화염은 기름을 점화, 물은 닿은 칸의 기름·불 장판만 지운다.
func _test_touch_attribute() -> void:
	var f: Fixture = _fixture()
	var archer: CombatUnit = f.units[0]
	f.actions.create_oil(archer, Vector2i(4, 4))
	f.actions.create_ground(f.units[3], Vector2i(9, 9), "burn")
	_check(f.actions.touch_attribute(Vector2i(4, 4), "water", archer) and _grounds_of(f, "oil") == 4,
		"물 속성은 닿은 칸의 기름만 지움(이웃 칸은 그대로)")
	_check(f.actions.touch_attribute(Vector2i(9, 9), "water", archer) and _grounds_of(f, "burn") == 0,
		"물 속성은 닿은 칸의 불 장판을 지움")
	_check(not f.actions.touch_attribute(Vector2i(9, 0), "fire", archer) and not f.actions.touch_attribute(Vector2i(3, 4), "none", archer),
		"반응이 없는 칸·속성은 아무것도 바꾸지 않음")
	_check(f.actions.touch_attribute(Vector2i(3, 4), "fire", archer) and _grounds_of(f, "oil") == 3
		and archer.get_status_count("burn") == 2, "화염 속성은 이어진 기름을 점화(닿은 칸 기름이 혼자면 그 칸만)")


## 떠나기 굴림은 기회 공격보다 먼저 한다. 실패하면 이동이 취소되고 칸을 떠나지 않는다.
func _test_leaving_slip() -> void:
	var f: Fixture = _fixture()
	var archer: CombatUnit = f.units[0]
	_single_oil(f, Vector2i(3, 4), archer)
	f.actions.dice = _dice([1], [20])
	_check(await f.actions.move_to(archer, Vector2i(3, 2)) and archer.cell == Vector2i(3, 4)
		and archer.movement_left == 6 and archer.fallen and archer.oil_slipped,
		"떠나기 굴림 실패: 칸을 떠나지 않고 이동력도 쓰지 않으며 넘어짐")
	_check(f.logs.any(func(message: String) -> bool: return "넘어짐" in message), "넘어짐을 로그에 남김")
	# 떠나기 성공 뒤 다음 칸이 기름이어도 같은 턴에는 굴리지 않는다(기름 장판 전체에 1회).
	var g: Fixture = _fixture()
	var walker: CombatUnit = g.units[0]
	_single_oil(g, Vector2i(3, 4), walker)
	_single_oil(g, Vector2i(3, 3), walker)
	g.actions.dice = _dice([10], [20])
	_check(await g.actions.move_to(walker, Vector2i(3, 2)) and walker.cell == Vector2i(3, 2)
		and not walker.fallen and walker.movement_left == 4,
		"떠나기 성공은 이동을 진행하고, 이어서 기름 칸을 밟아도 두 번째로 굴리지 않음")


## 들어가기 굴림: 실패하면 그 칸에서 넘어지고 이동은 그 칸에서 멈춘다. 걸음 1칸 비용은 쓴다.
func _test_entering_slip() -> void:
	var f: Fixture = _fixture()
	var archer: CombatUnit = f.units[0]
	_single_oil(f, Vector2i(3, 3), archer)
	f.actions.dice = _dice([1], [20])
	_check(await f.actions.move_to(archer, Vector2i(3, 2)) and archer.cell == Vector2i(3, 3)
		and archer.fallen and archer.movement_left == 5 and archer.oil_slipped,
		"들어가기 실패: 기름 칸에서 넘어지고 이동 정지, 걸음 1칸 비용")
	var g: Fixture = _fixture()
	_single_oil(g, Vector2i(3, 3), g.units[0])
	g.actions.dice = _dice([10], [20])
	_check(await g.actions.move_to(g.units[0], Vector2i(3, 2)) and g.units[0].cell == Vector2i(3, 2)
		and not g.units[0].fallen, "들어가기 성공은 이동을 계속함")
	_check(_oil_cells(g).size() == 1, "기름 칸 밖의 다른 기름은 그대로")


## 강제 이동 착지는 진입 굴림만 한다(떠나기 없음).
func _test_forced_entry_slip() -> void:
	var f: Fixture = _fixture()
	var archer: CombatUnit = f.units[0]
	_single_oil(f, Vector2i(3, 4), archer)
	f.actions.dice = _dice([], [])
	f.actions._apply_grounds(archer, false)
	_check(not archer.fallen and not archer.oil_slipped, "가만히 서 있는 것은 굴리지 않음")
	f.actions.dice = _dice([1], [20])
	f.actions._apply_grounds(archer, true)
	_check(archer.fallen and archer.oil_slipped, "강제 이동으로 기름 칸에 들어가면 진입 굴림 실패 시 넘어짐")


## 자기 실제 턴 시작: 넘어짐 자동 해제(굴림·비용 없음)와 미끌거림 1회 기록 초기화. 기름 칸에 서 있어도 굴리지 않는다.
func _test_turn_start_release() -> void:
	var f: Fixture = _fixture()
	var archer: CombatUnit = f.units[0]
	_single_oil(f, Vector2i(3, 4), archer)
	archer.fallen = true
	archer.oil_slipped = true
	f.actions.dice = _dice([], [])
	f.actions._on_turn_started(archer)
	_check(not archer.fallen and not archer.oil_slipped and archer.movement_left == 6,
		"자기 턴 시작에 넘어짐과 기름 기록을 비용 없이 해제")


## 넘어짐 중에는 행동·보조 행동·반응을 쓸 수 없고, 이동 시도는 일어서기 비용을 먼저 낸다.
func _test_fallen_limits_and_stand_up() -> void:
	var f: Fixture = _fixture()
	var archer: CombatUnit = f.units[0]
	archer.fallen = true
	_check(not f.actions.can_use(archer, "attack") and not f.actions.can_use(archer, "jump")
		and not f.actions.can_use(archer, "oil_throw") and not f.actions._can_react(archer),
		"넘어짐: 행동·보조 행동·반응 불가")
	_check(f.actions.can_move(archer, Vector2i(3, 2)) and f.actions.reachable_cells(archer).size() > 0,
		"넘어짐에서도 이동 시도는 일어서기 비용(절반)을 내고 가능")
	archer.movement_left = 2
	_check(not f.actions.stand_up(archer) and archer.fallen and not f.actions.can_move(archer, Vector2i(3, 2)),
		"이동력이 비용보다 적으면 일어나지 못하고 이동도 못함")
	archer.movement_left = 6
	_check(f.actions.stand_up(archer) and not archer.fallen and archer.movement_left == 3
		and f.actions.can_use(archer, "attack"), "일어서면 비용 3을 내고 행동을 다시 씀")
	var g: Fixture = _fixture()
	g.units[0].fallen = true
	g.actions.dice = _dice([], [])
	_check(await g.actions.move_to(g.units[0], Vector2i(3, 2)) and not g.units[0].fallen
		and g.units[0].cell == Vector2i(3, 2) and g.units[0].movement_left == 1,
		"이동 시도로 일어서면 비용 3을 먼저 내고 남은 이동력(3)으로 2칸 걸음")


## 넘어짐은 민첩 내성에만 불리(회전회오리). 다른 능력치는 그대로다.
func _test_fallen_agility_save() -> void:
	var f: Fixture = _fixture()
	var target: CombatUnit = f.units[1]
	_check(CombatActionRules.save_mode(target, CombatUnit.Ability.AGILITY) == CombatChecks.RollMode.NORMAL,
		"넘어지지 않은 민첩 내성은 일반")
	target.fallen = true
	_check(CombatActionRules.save_mode(target, CombatUnit.Ability.AGILITY) == CombatChecks.RollMode.DISADVANTAGE
		and CombatActionRules.save_mode(target, CombatUnit.Ability.HEALTH) == CombatChecks.RollMode.NORMAL
		and CombatActionRules.save_mode(target, CombatUnit.Ability.STRENGTH) == CombatChecks.RollMode.NORMAL,
		"넘어짐은 민첩 내성에만 불리")


## 시전자가 쓰러져도 기름은 남고, 살아 있는 시전자의 턴 시작 틱으로는 줄지 않는다(시계 슬롯만 줄임).
func _test_oil_clock() -> void:
	var f: Fixture = _fixture()
	var archer: CombatUnit = f.units[0]
	f.actions.create_oil(archer, Vector2i(4, 4))
	# 살아 있는 시전자의 턴 시작 감소는 기름을 한 번만 줄인다(비-안개 루프에서 또 줄이지 않음).
	f.actions._decrease_durations(archer)
	_check(f.actions.get_grounds().all(func(ground: CombatActions.Ground) -> bool:
		return ground.kind != "oil" or ground.turns_left == 2), "살아 있는 시전자의 턴 시작 감소는 기름을 한 번만 줄임")
	f.actions._damage(archer, archer.hit_points)
	_check(_grounds_of(f, "oil") == 5, "시전자가 쓰러져도 기름은 남음")
	f.actions._tick_unit_effects(archer)
	_check(_grounds_of(f, "oil") == 5, "쓰러진 시전자의 시계 슬롯이 한 번 줄여도 아직 남음")
	f.actions._tick_unit_effects(archer)
	_check(_grounds_of(f, "oil") == 0 and f.logs.any(func(message: String) -> bool: return "기름 장판 만료" in message),
		"시계 두 번째에 기름 장판이 사라짐(남은 기간 2)")


## 기름병 던지기: 보조 행동, 전투마다 1, 사거리 = 힘 면 수 ÷ 2(궁수 3), 곡사, 십자 5칸.
func _test_oil_throw() -> void:
	var f: Fixture = _fixture()
	var archer: CombatUnit = f.units[0]
	_check(CombatActionRules.belongs_to(archer, "oil_throw") and not CombatActionRules.belongs_to(f.units[3], "oil_throw"),
		"기름병 던지기는 궁수만 씀")
	_check(f.actions.can_aim(archer, "oil_throw", Vector2i(6, 4)) and not f.actions.can_aim(archer, "oil_throw", Vector2i(7, 4))
		and f.actions.can_aim(archer, "oil_throw", Vector2i(3, 4)), "사거리 3(맨해튼 거리 3 이하)과 자기 칸")
	_check(f.actions.throw_oil(archer, Vector2i(6, 4)) and _grounds_of(f, "oil") == 5 and archer.bonus_action_left == 0
		and archer.oil_throw_left == 0, "던지면 십자 5칸 기름, 보조 행동 1과 전투 횟수 1 소비")
	_check(Vector2i(6, 4) in _oil_cells(f) and Vector2i(7, 4) in _oil_cells(f) and Vector2i(6, 5) in _oil_cells(f),
		"목표 칸 십자 5칸")
	archer.bonus_action_left = 1
	_check(not f.actions.can_use(archer, "oil_throw") and not f.actions.throw_oil(archer, Vector2i(3, 4)),
		"전투 횟수를 다 쓰면 다시 던질 수 없음")
	archer.begin_stage(false)
	_check(archer.oil_throw_left == 1, "새 전투가 시작되면 횟수가 회복")


## 넘어짐은 유닛 상태 줄에 보인다.
func _test_status_text() -> void:
	var f: Fixture = _fixture()
	f.units[0].fallen = true
	_check(f.units[0].get_status_text().contains("넘어짐"), "넘어짐을 상태 글자에 보임")


## 저장: 기름 장판, 넘어짐, 미끌거림 기록, 기름병 횟수가 왕복하고, 기름 DC가 4가 아니면 거부한다.
func _test_save() -> void:
	var f: Fixture = _fixture()
	var archer: CombatUnit = f.units[0]
	f.actions.create_oil(archer, Vector2i(4, 4))
	archer.fallen = true
	archer.oil_slipped = true
	archer.oil_throw_left = 0
	var state: Dictionary = f.actions.save_state()
	var unit_data: Dictionary = archer.save_state(f.units)
	_check(unit_data.get("fallen") == true and unit_data.get("oil_slipped") == true and unit_data.get("oil_throw_left") == 0,
		"유닛 저장에 넘어짐·미끌거림·기름병 횟수가 들어감")
	_check(CombatActions.is_valid_state(state, 4, Vector2i(10, 10)) and archer.is_valid_state(unit_data, 4, Vector2i(10, 10)),
		"기름 장판과 넘어짐 저장은 유효")
	var g: Fixture = _fixture()
	g.actions.load_state(state)
	g.units[0].load_state(unit_data, g.units)
	_check(_grounds_of(g, "oil") == 5 and g.units[0].fallen and g.units[0].oil_slipped and g.units[0].oil_throw_left == 0,
		"저장 값을 되돌리면 기름 장판과 유닛 상태가 같음")
	var broken: Dictionary = state.duplicate(true)
	broken.grounds[0][5] = 3
	_check(not CombatActions.is_valid_state(broken, 4, Vector2i(10, 10)), "기름 장판의 DC가 4가 아니면 거부")
	var kind_broken: Dictionary = state.duplicate(true)
	kind_broken.grounds[0][2] = "ice"
	_check(not CombatActions.is_valid_state(kind_broken, 4, Vector2i(10, 10)), "알 수 없는 장판 종류는 거부")
