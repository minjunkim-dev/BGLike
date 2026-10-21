extends SceneTree
## 드랍 모델과 실제 보상·정비 입력을 검사한다.

const ScriptedDice = preload("res://tests/scripted_dice.gd")

class ScriptedLoot extends CombatLoot:
	var scripted_dice: CombatDice

	func roll_rewards(monster_count: int, _dice: CombatDice, act_number: int) -> Array[Dictionary]:
		return super.roll_rewards(monster_count, scripted_dice, act_number)

var checks: int = 0
var failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)


func _run() -> void:
	var script: Script = load("res://scenes/combat/loot.gd") as Script
	_check(script != null, "드랍 모델 로드")
	if script != null:
		var loot: RefCounted = script.new()
		var dice: CombatDice = CombatDice.new()
		dice.seed = 55
		_test_armor_hit_points(loot)
		_test_bag_replacement()
		_test_bag_capacity()
		_test_bag_use()
		_test_armor_unequip()
		_test_act_values(loot, dice)
		_test_icons(loot)
		loot.data["extra_drop_chance"] = 0.0
		_check(loot.roll_rewards(2, dice, 1).size() == 1, "추가 확률0이어도 보장1개")
		loot.data["extra_drop_chance"] = 1.0
		_check(loot.roll_rewards(2, dice, 1).size() == 3, "확률1이면 보장1개와 몬스터당1개")
		loot.data["extra_drop_chance"] = 0.35
		_check(loot.roll_rewards(1, ScriptedDice.new([], [], [0.349]).then_seeded(), 1).size() == 2,
			"추가 드랍 굴림 0.349는 35% 성공")
		_check(loot.roll_rewards(1, ScriptedDice.new([], [], [0.35]).then_seeded(), 1).size() == 1,
			"추가 드랍 굴림 0.35는 35% 실패")
		_test_items(loot, dice)
	await _test_reward_flow()
	await _test_full_bag_finish()
	await _test_bag_scene_use()
	await _test_armor_unequip_scene()
	await _test_finish_preference()
	await _test_accidental_advance()
	await _test_scaled_combat()
	await _test_spiderling_rewards()
	await _test_boss_reward_boundary()
	# 완료된 검사 코루틴의 참조를 해제한 뒤 종료한다.
	await process_frame
	var dice_problems: Array[String] = ScriptedDice.finish()
	_check(dice_problems.is_empty(), "준비한 주사위 값을 요청대로 모두 굴림 " + str(dice_problems))
	print("Combat loot: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)


func _test_spiderling_rewards() -> void:
	for mixed: bool in [false, true]:
		var main: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
		root.add_child(main)
		var battle: Node2D = main.get_node("Battle") as Node2D
		battle.set_process(false)
		var units: Array[CombatUnit] = battle.get("units")
		var actions: CombatActions = battle.get("actions") as CombatActions
		var progress: CombatActProgress = battle.get("progress") as CombatActProgress
		var loot: CombatLoot = battle.get("loot") as CombatLoot
		# 추가 추첨을 모두 성공시켜도 새끼는 보상 수를 늘리지 않아야 한다.
		loot.data["extra_drop_chance"] = 1.0
		loot.data["items"] = [{"kind": "potion", "name": "검사 물약", "weight": 1, "stats": {}}]
		if mixed:
			units[2].kind = CombatUnit.Kind.WARRIOR
			units[2].hit_points = units[2].get_max_hit_points()
		for index: int in range(2, units.size()):
			actions.incapacitate(units[index])
			actions.changed.emit()
			if index < units.size() - 1:
				_check(not actions.is_victory() and progress.rewards.is_empty(),
					"새끼 거미가 한 마리라도 남으면 승리·보상 없음")
		_check(actions.is_victory() and progress.rewards.size() == (2 if mixed else 1),
			"새끼만 처치하면 보장1개이고 혼합 전투는 풋내기1마리분만 추가 드랍")
		if not mixed:
			# 실제 1-1의 사물·풍경과 지형. 정비 화면은 보상 흐름 검사에서 확인한다.
			_check_pixel_art(main, ["AnimatedSprite2D", "Sprite2D", "Button"])
		main.queue_free()
		await process_frame


func _test_boss_reward_boundary() -> void:
	for stage: int in [2, 5, 8]:
		for extra: bool in [false, true]:
			var main: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
			root.add_child(main)
			var battle: Node2D = main.get_node("Battle") as Node2D
			battle.set_process(false)
			var progress: CombatActProgress = battle.get("progress") as CombatActProgress
			progress.stage_index = stage
			battle.call("_start_stage", true)
			var units: Array[CombatUnit] = battle.get("units")
			_check(units.size() == 3 and units[2].is_boss(), "각 막의 실제3스테이지는 보스1마리")
			if units.size() != 3 or not units[2].is_boss():
				main.queue_free()
				await process_frame
				continue
			var loot: ScriptedLoot = ScriptedLoot.new()
			_check(is_equal_approx(float(loot.data["extra_drop_chance"]), 0.35),
				"각 보스의 실제 보상 연결도 제품 데이터의35% 사용")
			# 승리 연결이 만든 주사위만 교체한다. 추첨과 드랍 대상 수는 실제 코드를 실행한다.
			loot.scripted_dice = (ScriptedDice.new([1, 1], [1, 1], [0.349]) if extra
				else ScriptedDice.new([1], [1], [0.35]))
			loot.data["items"] = [{"kind": "potion", "name": "검사 물약", "weight": 1, "stats": {}}]
			battle.set("loot", loot)
			var actions: CombatActions = battle.get("actions") as CombatActions
			actions.incapacitate(units[2])
			actions.changed.emit()
			_check(actions.is_victory() and progress.rewards.size() == (2 if extra else 1),
				"%d막 보스 승리는 보장1개와0.349성공·0.35실패 경계를 적용" % progress.act_number())
			main.queue_free()
			await process_frame


func _test_bag_use() -> void:
	var loot: CombatLoot = CombatLoot.new()
	var unit: CombatUnit = CombatUnit.new()
	var old: Dictionary = {"kind": "armor", "name": "이전 방어구", "stats": {"max_hit_points": 2}}
	var next: Dictionary = {"kind": "armor", "name": "다음 방어구", "stats": {"max_hit_points": 5}}
	var potion: Dictionary = {"kind": "potion", "name": "물약", "stats": {}}
	unit.armor = old
	unit.hit_points = 5
	loot.bag.append(next)
	for index: int in range(11):
		loot.bag.append(potion.duplicate(true))
	_check(loot.receive_from_bag(unit, 0) and unit.armor == next and unit.hit_points == 8
		and loot.bag.size() == 12 and loot.bag[0] == old,
		"가득 찬 가방 장비는 같은 칸에 이전 장비를 교환하고 잃은 HP 유지")
	unit.hit_points = 0
	_check(loot.receive_from_bag(unit, 0) and unit.hit_points == 0 and loot.bag.size() == 12,
		"가방 방어구 교체는 전투 불능 캐릭터를 부활시키지 않음")
	unit.potion_left = 2
	_check(loot.receive_from_bag(unit, 1) and unit.potion_left == 3 and loot.bag.size() == 11,
		"가방 물약은 한 개를 분배하고 캐릭터 한도3 적용")
	var stored: Array[Dictionary] = loot.bag.duplicate(true)
	_check(not loot.receive_from_bag(unit, 1) and unit.potion_left == 3 and loot.bag == stored,
		"물약 한도에서 가방 수령 실패는 양쪽 소유권 보존")
	_check(not loot.receive_from_bag(unit, -1) and not loot.receive_from_bag(unit, 11)
		and loot.bag == stored, "무효 가방 칸은 소유권을 바꾸지 않음")
	unit.free()


func _test_armor_unequip() -> void:
	var loot: CombatLoot = CombatLoot.new()
	var unit: CombatUnit = CombatUnit.new()
	var armor: Dictionary = {"kind": "armor", "name": "HP 방어구", "stats": {"max_hit_points": 5}}
	var weapon: Dictionary = {"kind": "weapon", "name": "무기", "stats": {"damage_bonus": 1}}
	_check(not loot.armor_unequip_blocker(unit).is_empty() and not loot.unequip_armor(unit)
		and loot.bag.is_empty(), "방어구가 없으면 해제하지 못함")
	unit.weapon = weapon
	unit.armor = armor
	unit.hit_points = 1
	_check(unit.get_max_hit_points() == 17 and loot.armor_unequip_blocker(unit).is_empty(),
		"방어구 해제 가능 상태")
	_check(loot.unequip_armor(unit) and unit.armor.is_empty() and loot.bag == [armor]
		and unit.hit_points == 1 and unit.get_max_hit_points() == 12 and unit.weapon == weapon,
		"HP 1/17에서 최대 HP+5 방어구 해제는 1/12, 가방 보관, 무기 유지")
	_check(loot.receive_from_bag(unit, 0) and unit.armor == armor and loot.bag.is_empty()
		and unit.hit_points == 1 and unit.get_max_hit_points() == 17, "다시 장착하면 1/17")
	unit.hit_points = 10
	for index: int in range(12):
		loot.bag.append({"kind": "potion", "name": "물약", "stats": {}})
	var stored: Array[Dictionary] = loot.bag.duplicate(true)
	_check("빈 칸" in loot.armor_unequip_blocker(unit) and not loot.unequip_armor(unit)
		and unit.armor == armor and unit.hit_points == 10 and unit.get_max_hit_points() == 17
		and loot.bag == stored, "가방이 가득 차면 해제하지 못하고 방어구·HP·가방 보존")
	loot.bag.remove_at(0)
	unit.hit_points = 0
	_check(loot.unequip_armor(unit) and unit.hit_points == 0 and loot.bag.size() == 12,
		"전투 불능 캐릭터 방어구 해제는 부활시키지 않음")
	unit.free()


func _test_bag_capacity() -> void:
	var loot: CombatLoot = CombatLoot.new()
	_check(int(loot.data.get("bag_limit", 0)) == 12, "공용 가방의 제품 데이터 한도12칸")
	var potion: Dictionary = {"kind": "potion", "name": "물약", "stats": {}}
	for index: int in range(12):
		loot.bag.append(potion.duplicate(true))
	var stored: Array[Dictionary] = loot.bag.duplicate(true)
	for kind: String in ["weapon", "armor"]:
		var unit: CombatUnit = CombatUnit.new()
		var previous: Dictionary = {"kind": kind, "name": "이전 장비", "stats": {}}
		var next: Dictionary = {"kind": kind, "name": "다음 장비", "stats": {}}
		unit.weapon = previous if kind == "weapon" else {}
		unit.armor = previous if kind == "armor" else {}
		unit.hit_points = 5
		loot.bag.assign(stored)
		_check(not loot.receive(unit, next) and loot.bag == stored and unit.hit_points == 5
			and (unit.weapon if kind == "weapon" else unit.armor) == previous,
			"가방이 가득 차면 이전 장비 공간을 요구하고 교체 전체를 보존: " + kind)
		unit.free()
	loot.bag.assign(stored)
	var empty: CombatUnit = CombatUnit.new()
	_check(loot.receive(empty, {"kind": "weapon", "name": "첫 무기", "stats": {}})
		and loot.bag == stored, "빈 장착 칸은 가방이 가득 차도 수령 가능")
	_check(loot.receive(empty, potion) and empty.potion_left == 1 and loot.bag == stored,
		"물약 캐릭터 분배는 가방이 가득 차도 가능")
	empty.free()


func _test_bag_replacement() -> void:
	var loot: CombatLoot = CombatLoot.new()
	var unit: CombatUnit = CombatUnit.new()
	var first: Dictionary = {"kind": "weapon", "name": "이전 무기", "stats": {"damage_bonus": 1}}
	var second: Dictionary = {"kind": "weapon", "name": "새 무기", "stats": {"damage_bonus": 2}}
	_check(loot.receive(unit, first) and loot.bag.is_empty(), "빈 장착 칸 수령은 가방 공간을 쓰지 않음")
	_check(loot.receive(unit, second) and unit.weapon == second, "새 보상 무기 장착")
	_check(loot.bag == [first], "교체한 이전 무기는 공용 가방에 보존")
	unit.free()


func _test_armor_hit_points(loot: CombatLoot) -> void:
	var unit: CombatUnit = CombatUnit.new()
	unit.hit_points = 5
	var armor: Dictionary = {"kind": "armor", "name": "HP 방어구",
		"stats": {"armor_class": 2, "max_hit_points": 5}}
	loot.receive(unit, armor)
	_check(unit.hit_points == 10 and unit.get_max_hit_points() == 17,
		"방어구 최대 HP 증가 시 잃은 HP 7 유지")
	var weaker: Dictionary = {"kind": "armor", "name": "낮은 HP 방어구",
		"stats": {"armor_class": 1, "max_hit_points": 2}}
	loot.receive(unit, weaker)
	_check(unit.hit_points == 7 and unit.get_max_hit_points() == 14,
		"실제 수령 경로로 더 낮은 방어구 직접 교체 시 잃은 HP 유지")
	loot.receive(unit, armor)
	_check(unit.hit_points == 10 and unit.get_max_hit_points() == 17,
		"실제 수령 경로로 더 높은 방어구 직접 교체 시 잃은 HP 유지")
	unit.hit_points = 1
	loot.receive(unit, weaker)
	loot.receive(unit, armor)
	_check(unit.hit_points == 1 and unit.get_max_hit_points() == 17,
		"실제 방어구 직접 교체도 HP 하한에서 무료 회복 방지")
	unit.armor = {}
	_check(unit.hit_points == 1 and unit.get_max_hit_points() == 12,
		"방어구 해제는 현재 HP 최소1 유지")
	loot.receive(unit, armor)
	_check(unit.hit_points == 1 and unit.get_max_hit_points() == 17,
		"최소1 보정 전 잃은 HP를 기억해 재장착 회복 방지")
	unit.armor = {}
	unit.begin_stage(false)
	loot.receive(unit, armor)
	_check(unit.hit_points == 1, "같은 막 전투 전환도 HP 하한 손실 유지")
	unit.hit_points = 0
	unit.armor = {}
	loot.receive(unit, armor)
	_check(unit.hit_points == 0 and unit.get_max_hit_points() == 17,
		"전투 불능도 최대 HP 효과는 적용하지만 부활하지 않음")
	unit.begin_stage(true)
	_check(unit.hit_points == 17, "막 복구는 장비 포함 최대 HP까지 회복")
	unit.armor = {}
	loot.receive(unit, armor)
	_check(unit.hit_points == 17, "막 복구 뒤 과거 HP 하한 손실 제거")
	_check("최대 HP+5" in CombatLoot.describe(armor), "보상에 최대 HP 수치 표시")
	unit.free()


func _test_icons(loot: CombatLoot) -> void:
	var expected: Dictionary = {"weapon": "sword", "armor": "armor", "potion": "potion"}
	for item: Dictionary in loot.data["items"]:
		var texture: Texture2D = load(CombatLoot.icon_path(item)) as Texture2D
		_check(texture != null and texture.get_size() == Vector2(64, 64)
			and CombatLoot.icon_path(item).get_file() == expected[item["kind"]] + ".png",
			"실제 아이템 데이터의 64px 아이콘: " + str(item["id"]))
		_check(CombatLoot.icon_path(item, "warrior") == CombatLoot.icon_path(item),
			"전사는 공용 아이콘: " + str(item["id"]))
		var archer_path: String = CombatLoot.icon_path(item, "archer")
		_check(archer_path.get_file() == ("bow.png" if item["kind"] == "weapon" else expected[item["kind"]] + ".png")
			and load(archer_path) is Texture2D, "궁수 무기는 활, 나머지는 공용 아이콘: " + str(item["id"]))
	var dice: CombatDice = CombatDice.new()
	dice.seed = 224
	var rolled: Array[Dictionary] = loot.roll_rewards(4, dice, 1)
	for item: Dictionary in rolled:
		_check(CombatLoot.icon_path(item, "warrior") == CombatLoot.ICON_PATH % expected[item["kind"]],
			"추첨한 아이템도 아이콘을 유지")
	_check(CombatLoot.icon_path({"kind": "potion"}).is_empty(), "아이콘이 없는 검사 데이터는 빈 경로")


func _test_items(loot: CombatLoot, dice: CombatDice) -> void:
	loot.data["extra_drop_chance"] = 0.35
	loot.data["potion_limit"] = 3
	# 기획 데이터 변경과 독립된 검사 범위. 숫자는 검사 입력의 계약이다.
	loot.data["items"] = [
		{"kind": "weapon", "name": "검사 무기", "weight": 1,
			"stats": {"attack_bonus": [[0, 2], [0, 2], [0, 2]],
				"damage_bonus": [[1, 3], [1, 3], [1, 3]]}},
		{"kind": "armor", "name": "검사 방어구", "weight": 1,
			"stats": {"armor_class": [[1, 3], [1, 3], [1, 3]]}},
		{"kind": "potion", "name": "검사 물약", "weight": 1, "stats": {}}
	]
	var seen: Dictionary = {}
	var in_bounds: bool = true
	for sample: int in range(100):
		var drops: Array[Dictionary] = loot.roll_rewards(2, dice, 1)
		in_bounds = in_bounds and drops.size() >= 1 and drops.size() <= 3
		for item: Dictionary in drops:
			seen[item["kind"]] = true
			for stat: String in item["stats"]:
				var value: int = int(item["stats"][stat])
				in_bounds = in_bounds and value >= (0 if stat == "attack_bonus" else 1)
				in_bounds = in_bounds and value <= (2 if stat == "attack_bonus" else 3)
	_check(in_bounds and seen.size() == 3, "고정seed에서 세 종류·보장 수량·임시 수치 범위")
	loot.data["items"] = [{"kind": "weapon", "name": "데이터 무기", "weight": 1,
		"stats": {"attack_bonus": [[9, 9], [9, 9], [9, 9]]}}]
	var changed: Array[Dictionary] = loot.roll_rewards(0, dice, 1)
	_check(changed.size() == 1 and changed[0]["name"] == "데이터 무기"
		and changed[0]["stats"]["attack_bonus"] == 9, "종류·이름·수치 범위를 데이터 변경으로 적용")
	var warrior: CombatUnit = CombatUnit.new()
	var archer: CombatUnit = CombatUnit.new()
	archer.kind = CombatUnit.Kind.ARCHER
	archer.hit_points = 0
	var weapon: Dictionary = {"kind": "weapon", "name": "검사 무기", "stats": {"attack_bonus": 2, "damage_bonus": 3}}
	var armor: Dictionary = {"kind": "armor", "name": "검사 방어구", "stats": {"armor_class": 3}}
	_check(loot.receive(warrior, weapon) and loot.receive(warrior, armor), "무기·방어구 각1칸 수령")
	_check(warrior.get_attack_bonus() == 7 and warrior.get_damage_bonus() == 6
		and warrior.get_armor_class() == 19, "장비가 기본 전투 수치를 올림")
	weapon["stats"]["attack_bonus"] = 1
	_check(warrior.get_attack_bonus() == 7, "받은 장비 수치는 보상 원본 변경과 독립")
	loot.receive(warrior, weapon)
	_check(warrior.get_attack_bonus() == 6 and warrior.weapon["stats"]["attack_bonus"] == 1,
		"장비 교체는 이전 장비를 대체하고 합산하지 않음")
	_check(loot.receive(archer, armor) and archer.hit_points == 0
		and archer.get_armor_class() == 17, "전투 불능 캐릭터도 장비를 받고 전투 불능 유지")
	var potion: Dictionary = {"kind": "potion", "name": "물약", "stats": {}}
	for index: int in range(3):
		_check(loot.receive(archer, potion), "전투 불능 캐릭터도 물약 수령")
	_check(not loot.receive(archer, potion) and archer.potion_left == 3, "물약3개 한도")
	_check(loot.transfer_potion(archer, warrior) and archer.potion_left == 2
		and warrior.potion_left == 1, "전투 불능 캐릭터의 물약을 다른 캐릭터에게 양도")
	warrior.potion_left = 3
	_check(not loot.transfer_potion(archer, warrior) and archer.potion_left == 2,
		"물약 한도에 걸린 양도는 양쪽 개수를 보존")
	loot.data["potion_limit"] = 4
	_check(loot.transfer_potion(archer, warrior) and warrior.potion_left == 4, "데이터 물약 한도 적용")
	warrior.begin_stage(true)
	archer.begin_stage(true)
	_check(warrior.weapon["stats"]["attack_bonus"] == 1 and archer.get_armor_class() == 17
		and warrior.potion_left == 4 and archer.hit_points == 14, "막 복구는 장비·남은 물약 유지")
	warrior.free()
	archer.free()


func _test_act_values(loot: CombatLoot, dice: CombatDice) -> void:
	var expected: Dictionary = {
		"weapon": {"attack_bonus": [[1, 2], [3, 4], [5, 7]],
			"damage_bonus": [[1, 3], [4, 6], [7, 10]]},
		"armor": {"armor_class": [[1, 2], [3, 4], [5, 7]],
			"max_hit_points": [[2, 4], [5, 8], [9, 14]]},
		"potion": {}
	}
	var weights: Dictionary = {}
	for definition: Dictionary in loot.data["items"]:
		weights[definition["kind"]] = int(definition["weight"])
	_check(weights == {"weapon": 2, "armor": 2, "potion": 3}
		and is_equal_approx(float(loot.data["extra_drop_chance"]), 0.35),
		"실제 데이터 비중2/2/3과 몬스터당35%")
	loot.data["extra_drop_chance"] = 1.0
	for act: int in range(1, 4):
		var combinations: Dictionary = {"weapon": {}, "armor": {}}
		var valid: bool = true
		var seen: Dictionary = {}
		for sample: int in range(200):
			var drops: Array[Dictionary] = loot.roll_rewards(2, dice, act)
			valid = valid and drops.size() == 3
			for item: Dictionary in drops:
				var kind: String = item["kind"]
				seen[kind] = true
				valid = valid and item["stats"].size() == expected[kind].size()
				for stat: String in item["stats"]:
					var bounds: Array = expected[kind][stat][act - 1]
					valid = valid and int(item["stats"][stat]) >= int(bounds[0]) \
						and int(item["stats"][stat]) <= int(bounds[1])
				if kind != "potion":
					combinations[kind][str(item["stats"].values())] = true
		_check(valid and seen.size() == 3, "%d막 실제 데이터의 보장·추가 수치 범위" % act)
		_check(combinations["weapon"].size() > 3 and combinations["armor"].size() > 3,
			"%d막 두 수치를 독립 추첨" % act)


func _test_bag_scene_use() -> void:
	var main: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	current_scene = main
	var battle: Node2D = main.get_node("Battle") as Node2D
	battle.set_process(false)
	var loot: CombatLoot = battle.loot
	var party: Array[CombatUnit] = battle.party
	var old: Dictionary = {"kind": "armor", "name": "이전 방어구", "stats": {"max_hit_points": 2}}
	var next: Dictionary = {"kind": "armor", "name": "새 방어구", "stats": {"max_hit_points": 5}}
	party[0].armor = old
	party[0].hit_points = 5
	party[1].potion_left = 2
	battle.actions.incapacitate(party[1])
	loot.bag.append(next)
	for index: int in range(11):
		loot.bag.append({"kind": "potion", "name": "가방 물약", "stats": {}})
	for unit: CombatUnit in battle.units:
		if not unit.is_ally:
			battle.actions.incapacitate(unit)
	battle.actions.changed.emit()
	battle.progress.rewards.clear()
	await _click(battle.hud.restart_button)
	var preparation: CombatPreparation = battle.preparation
	await _click(preparation.continue_button)
	var equip: Button = await _pick(preparation, "BagItem0", "Ally0")
	_check(equip != null, "정비 화면의 공용 가방 칸을 고르면 상세 패널에 장착 버튼")
	if equip != null:
		await _click(equip)
		_check(party[0].armor == next and party[0].hit_points == 8
			and loot.bag.size() == 12 and loot.bag[0] == old,
			"실제 가방 장착 버튼은 같은 칸 교환과 잃은 HP 유지")
		await _click(await _pick(preparation, "BagItem1", "Ally1"))
		_check(party[1].potion_left == 3 and party[1].hit_points == 0 and loot.bag.size() == 11,
			"실제 가방 물약 버튼은 한도·전투 불능을 유지하며 한 개 분배")
		_check((await _pick(preparation, "BagItem1", "Ally1")).disabled,
			"한도에 도달하면 남은 가방 물약 분배 버튼 잠금")
	main.queue_free()
	await process_frame


func _test_armor_unequip_scene() -> void:
	var main: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	current_scene = main
	var battle: Node2D = main.get_node("Battle") as Node2D
	battle.set_process(false)
	var loot: CombatLoot = battle.loot
	var party: Array[CombatUnit] = battle.party
	var warrior_armor: Dictionary = {"kind": "armor", "name": "전사 방어구", "stats": {"max_hit_points": 5}}
	var archer_armor: Dictionary = {"kind": "armor", "name": "궁수 방어구", "stats": {"armor_class": 2}}
	party[0].armor = warrior_armor
	party[0].hit_points = 1
	party[1].armor = archer_armor
	var archer_hit_points: int = party[1].hit_points
	for index: int in range(11):
		loot.bag.append({"kind": "potion", "name": "가방 물약", "stats": {}})
	# 1막 마지막 스테이지 승리로 다음 막 전환까지 확인한다.
	battle.progress.stage_index = 2
	for unit: CombatUnit in battle.units:
		if not unit.is_ally:
			battle.actions.incapacitate(unit)
	battle.actions.changed.emit()
	battle.progress.rewards.clear()
	await _click(battle.hud.restart_button)
	var preparation: CombatPreparation = battle.preparation
	await _click(preparation.continue_button)
	var weapon_cell: Button = preparation.find_child("Weapon0", true, false) as Button
	weapon_cell.grab_focus()
	await _action("ui_accept")
	_check(weapon_cell.button_pressed and preparation.detail.find_children("*", "Button", true, false).is_empty(),
		"Enter로 무기 칸을 고르면 해제 버튼 없이 수치만 표시")
	await _action("ui_right")
	_check((preparation.find_child("Armor0", true, false) as Control).has_focus(), "방향키로 이웃 칸 이동")
	var unequip: Button = await _pick(preparation, "Armor0", "UnequipArmor0")
	# 고른 칸에서 방향키로 상세 패널의 동작 버튼까지 내려간다.
	for step: int in range(6):
		if unequip == null or unequip.has_focus():
			break
		await _action("ui_down")
	_check(unequip != null and unequip.has_focus(), "방향키로 상세 패널의 동작 버튼에 도달")
	_check(unequip != null and not unequip.disabled and unequip.tooltip_text.is_empty(),
		"정비 화면의 장착 방어구 해제 버튼")
	if unequip != null:
		await _click(unequip)
		_check(party[0].armor.is_empty() and party[0].hit_points == 1
			and party[0].get_max_hit_points() == 12 and loot.bag.size() == 12
			and loot.bag.back() == warrior_armor and preparation.continue_button.has_focus(),
			"실제 해제 버튼은 잃은 HP를 유지하고 방어구를 가방 빈 칸에 보관")
		unequip = await _pick(preparation, "Armor0", "UnequipArmor0")
		_check(unequip != null and unequip.disabled and not unequip.tooltip_text.is_empty(),
			"방어구가 없으면 해제 버튼 비활성과 이유 표시")
		var blocked: Button = await _pick(preparation, "Armor1", "UnequipArmor1")
		_check(blocked != null and blocked.disabled and "빈 칸" in blocked.tooltip_text,
			"가방이 가득 차면 해제 버튼 비활성과 호버 설명에 이유 표시")
		if blocked != null:
			await _click(blocked)
		# 비활성 버튼은 pressed를 내지 않으므로 화면 처리기의 거절도 직접 확인한다.
		preparation._unequip_armor(1)
		_check(party[1].armor == archer_armor and party[1].hit_points == archer_hit_points
			and loot.bag.size() == 12, "가득 찬 가방에서 해제 입력은 방어구·HP·가방 보존")
		await _click(preparation.continue_button)
		_check(not preparation.visible and battle.progress.act_number() == 2
			and battle.progress.stage_in_act() == 1 and party[0].armor.is_empty()
			and party[0].hit_points == 12 and party[1].armor == archer_armor
			and loot.bag.size() == 12 and loot.bag.back() == warrior_armor,
			"막 전환은 해제한 장비·가방 상태 유지")
		for unit: CombatUnit in party:
			battle.actions.incapacitate(unit)
		battle.actions.changed.emit()
		await _click(battle.hud.restart_button)
		_check(battle.progress.act_number() == 2 and battle.progress.stage_in_act() == 1
			and party[0].armor.is_empty() and party[0].hit_points == 12
			and party[1].armor == archer_armor and loot.bag.size() == 12
			and loot.bag.back() == warrior_armor, "전멸 재시작은 해제한 장비·가방 상태 유지")
	main.queue_free()
	await process_frame


func _test_finish_preference() -> void:
	var main: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	current_scene = main
	var battle: Node2D = main.get_node("Battle") as Node2D
	battle.set_process(false)
	var preparation: CombatPreparation = battle.preparation
	var loot: CombatLoot = battle.loot
	loot.data["extra_drop_chance"] = 0.0
	for unit: CombatUnit in battle.units:
		if not unit.is_ally:
			battle.actions.incapacitate(unit)
	battle.actions.changed.emit()
	await _click(battle.hud.restart_button)
	await _click(preparation.continue_button)
	await _click(preparation.continue_button)
	var skip: CheckBox = preparation.discard_dialog.find_child("SkipConfirmation", true, false) as CheckBox
	_check(skip != null, "정비 종료 확인의 다시 띄우지 않음 체크박스")
	if skip != null:
		_check(preparation.discard_dialog.size.y <= root.get_visible_rect().size.y,
			"정비 확인 창과 확인 버튼은 기준 화면 높이 안에 표시")
		_check(not skip.button_pressed and skip.text == "더 이상 이 메시지를 띄우지 않음",
			"종료 확인 생략은 기본 해제")
		for choice: String in ["cancel", "close", "escape"]:
			skip.button_pressed = true
			match choice:
				"cancel":
					preparation.discard_dialog.get_cancel_button().pressed.emit()
				"close":
					preparation.discard_dialog.notification(Window.NOTIFICATION_WM_CLOSE_REQUEST)
				"escape":
					var key: InputEventKey = InputEventKey.new()
					key.keycode = KEY_ESCAPE
					key.physical_keycode = KEY_ESCAPE
					key.pressed = true
					Input.parse_input_event(key)
					await process_frame
					key.pressed = false
					Input.parse_input_event(key)
			await process_frame
			_check(not preparation.discard_dialog.visible and preparation.visible
				and battle.progress.stage_index == 0 and loot.bag.is_empty(),
				"생략 체크 후 취소는 보상·스테이지 보존: " + choice)
			await _click(preparation.continue_button)
			_check(preparation.discard_dialog.visible and not skip.button_pressed,
				"취소한 생략 설정은 적용하지 않음: " + choice)
		for index: int in range(12):
			loot.bag.append({"kind": "potion", "name": "가방 물약", "stats": {}})
		skip.button_pressed = true
		preparation.discard_dialog.get_ok_button().grab_focus()
		await _enter_dialog(preparation.discard_dialog)
		_check(preparation.visible and battle.progress.stage_index == 0 and loot.bag.size() == 12,
			"생략 체크는 가방 용량 검사를 우회하지 않음")
		loot.bag.remove_at(0)
		await _click(preparation.continue_button)
		_check(preparation.discard_dialog.visible and not skip.button_pressed,
			"용량 부족으로 실패한 종료는 생략 설정을 저장하지 않음")
		skip.button_pressed = true
		preparation.discard_dialog.get_ok_button().grab_focus()
		await _enter_dialog(preparation.discard_dialog)
		_check(not preparation.visible and battle.progress.stage_index == 1 and loot.bag.size() == 12,
			"성공한 명시적 확인에서만 생략 설정 적용")
		for unit: CombatUnit in battle.units:
			if not unit.is_ally:
				battle.actions.incapacitate(unit)
		battle.actions.changed.emit()
		await _click(battle.hud.restart_button)
		await _click(preparation.continue_button)
		await _click(preparation.continue_button)
		_check(preparation.visible and not preparation.discard_dialog.visible
			and battle.progress.stage_index == 1 and loot.bag.size() == 12
			and battle.progress.rewards.size() == 1 and preparation.bag_notice.visible,
			"확인 생략 중에도 가득 찬 가방은 정비 종료 차단")
		await _click(await _pick(preparation, "BagItem0", "DiscardItem"))
		_check(preparation.discard_dialog.visible and not skip.visible
			and preparation.discard_dialog.get_cancel_button().has_focus(),
			"종료 확인 생략은 아이템 폐기 확인을 생략하지 않음")
		preparation.discard_dialog.get_ok_button().grab_focus()
		await _enter_dialog(preparation.discard_dialog)
		var enable: Button = preparation.find_child("EnableConfirmation", true, false) as Button
		_check(enable != null and not enable.disabled and enable.text == "정비 종료 확인 다시 켜기",
			"현재 실행의 확인 생략을 복원하는 정비 버튼")
		await _click(preparation.continue_button)
		_check(not preparation.visible and battle.progress.stage_index == 2
			and loot.bag.size() == 12, "설정한 다음 정비는 확인 없이 전부 보관하고 한 번 진행")
		for unit: CombatUnit in battle.units:
			if not unit.is_ally:
				battle.actions.incapacitate(unit)
		battle.actions.changed.emit()
		await _click(battle.hud.restart_button)
		await _click(preparation.continue_button)
		enable = preparation.find_child("EnableConfirmation", true, false) as Button
		if enable != null:
			await _click(enable)
			await _click(preparation.continue_button)
			_check(preparation.discard_dialog.visible and not skip.button_pressed,
				"다시 켜기 뒤 정비 종료 확인 복원")
			loot.bag.remove_at(0)
			skip.button_pressed = true
			preparation.discard_dialog.get_ok_button().grab_focus()
			await _enter_dialog(preparation.discard_dialog)
			_check(not preparation.visible and battle.progress.stage_index == 3,
				"확인을 다시 생략한 실행을 끝내고 새 실행 기본값 검사")
	main.queue_free()
	await process_frame
	main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	current_scene = main
	battle = main.get_node("Battle") as Node2D
	battle.set_process(false)
	_check(battle.loot.bag.is_empty(), "새 실행은 공용 가방이 비어 있음")
	for unit: CombatUnit in battle.units:
		if not unit.is_ally:
			battle.actions.incapacitate(unit)
	battle.actions.changed.emit()
	await _click(battle.hud.restart_button)
	preparation = battle.preparation
	await _click(preparation.continue_button)
	await _click(preparation.continue_button)
	_check(preparation.discard_dialog.visible, "새 실행은 종료 확인을 기본 표시")
	main.queue_free()
	await process_frame


func _test_full_bag_finish() -> void:
	var main: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	current_scene = main
	var battle: Node2D = main.get_node("Battle") as Node2D
	battle.set_process(false)
	var loot: CombatLoot = battle.loot
	var progress: CombatActProgress = battle.progress
	var potion: Dictionary = {"kind": "potion", "name": "보관 물약", "stats": {}}
	for index: int in range(12):
		var stored: Dictionary = potion.duplicate(true)
		stored["name"] = "가방 물약%d" % index
		loot.bag.append(stored)
	for unit: CombatUnit in battle.units:
		if not unit.is_ally:
			battle.actions.incapacitate(unit)
	battle.actions.changed.emit()
	progress.rewards.assign([potion.duplicate(true)])
	await _click(battle.hud.restart_button)
	var preparation: CombatPreparation = battle.preparation
	await _click(preparation.continue_button)
	await _click(preparation.continue_button)
	_check(preparation.discard_dialog.visible, "가방이 가득 찬 종료 확인 창 표시")
	preparation.discard_dialog.get_ok_button().grab_focus()
	var confirm: InputEventKey = InputEventKey.new()
	confirm.keycode = KEY_ENTER
	confirm.physical_keycode = KEY_ENTER
	confirm.pressed = true
	preparation.discard_dialog.push_input(confirm)
	await process_frame
	confirm.pressed = false
	preparation.discard_dialog.push_input(confirm)
	await process_frame
	_check(preparation.visible and preparation.maintaining and progress.stage_index == 0
		and progress.rewards == [potion] and loot.bag.size() == 12,
		"가방이 가득 차면 정비 종료 확인 후에도 보상을 남기고 부분 보관하지 않음")
	var notice: Label = preparation.find_child("BagNotice", true, false) as Label
	_check(notice != null and notice.visible and "1칸" in notice.text and "부족" in notice.text,
		"정비에 남겨 가방 부족 칸 수를 표시")
	var discard: Button = await _pick(preparation, "BagItem0", "DiscardItem")
	_check(discard != null, "가방 아이템별 폐기 버튼")
	if discard != null:
		await _click(discard)
		_check(preparation.discard_dialog.visible and preparation.discard_dialog.get_cancel_button().has_focus()
			and "가방 물약0" in preparation.discard_dialog.dialog_text,
			"선택한 가방 아이템의 폐기 확인은 돌아가기를 기본 선택")
		await _enter_dialog(preparation.discard_dialog)
		_check(loot.bag.size() == 12 and progress.rewards.size() == 1
			and not preparation.discard_dialog.visible, "폐기 확인 기본 Enter는 취소하고 아이템 보존")
		await _click(await _pick(preparation, "BagItem0", "DiscardItem"))
		preparation.discard_dialog.get_ok_button().grab_focus()
		await _enter_dialog(preparation.discard_dialog)
		preparation.discard_dialog.confirmed.emit()
		_check(loot.bag.size() == 11 and loot.bag[0]["name"] == "가방 물약1"
			and progress.stage_index == 0 and preparation.visible,
			"명시적 폐기는 선택한 한 개만 제거하고 중복 확인은 정비를 끝내지 않음")
		await _click(preparation.continue_button)
		preparation.discard_dialog.get_ok_button().grab_focus()
		await _enter_dialog(preparation.discard_dialog)
		_check(not preparation.visible and progress.stage_index == 1 and loot.bag.size() == 12
			and loot.bag.back()["name"] == "보관 물약" and progress.rewards.is_empty(),
			"공간 확보 후 종료는 남은 보상을 전부 보관하고 한 번 진행")
	main.queue_free()
	await process_frame


func _test_reward_flow() -> void:
	var main: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	(main.get_node("Battle") as Node2D).stages[0] = load("res://scenes/combat/stage.tres") as CombatStage
	root.add_child(main)
	current_scene = main
	var battle: Node2D = main.get_node("Battle") as Node2D
	battle.set_process(false)
	await process_frame
	_check(battle.has_node("UI/Preparation"), "전투 사이 보상·정비 화면")
	if battle.has_node("UI/Preparation"):
		var hud: CombatTurnHud = battle.get_node("UI/TurnHud") as CombatTurnHud
		var loot: CombatLoot = battle.get("loot") as CombatLoot
		loot.data["potion_limit"] = 3
		var party: Array[CombatUnit] = battle.get("party")
		await _test_equipped_attack(battle)
		party[1].potion_left = 1
		(battle.get("actions") as CombatActions).incapacitate(party[1])
		for unit: CombatUnit in battle.get("units"):
			if not unit.is_ally:
				(battle.get("actions") as CombatActions).incapacitate(unit)
		(battle.get("actions") as CombatActions).changed.emit()
		var actual_rewards: Array[Dictionary] = (battle.get("progress") as CombatActProgress).rewards
		_check(actual_rewards.size() >= 1 and actual_rewards.size() <= 3, "실제 승리에서 적2명 기준 드랍")
		(battle.get("actions") as CombatActions).changed.emit()
		_check(actual_rewards == (battle.get("progress") as CombatActProgress).rewards, "결과 갱신은 드랍을 다시 굴리지 않음")
		# 입력 검사를 재현할 고정 보상. 드랍 생성은 위와 모델 검사에서 별도로 확인한다.
		actual_rewards.clear()
		actual_rewards.append({"kind": "armor", "name": "검사 방어구",
			"stats": {"armor_class": 2, "max_hit_points": 4}})
		actual_rewards.append({"kind": "potion", "name": "검사 물약", "stats": {}})
		actual_rewards.append({"kind": "weapon", "name": "버릴 무기", "stats": {"damage_bonus": 1}})
		await _click(hud.restart_button)
		var preparation: CombatPreparation = battle.get_node("UI/Preparation") as CombatPreparation
		_check(preparation.visible and not preparation.maintaining, "승리 뒤 보상 화면 진입")
		_check((battle.get("progress") as CombatActProgress).stage_index == 0, "보상 확인은 다음 전투를 시작하지 않음")
		_check(await _pick(preparation, "Item0", "Ally1") == null
			and preparation.detail.find_children("*", "Button", true, false).is_empty()
			and preparation.detail.find_children("*", "Label", true, false).any(
				func(label: Label) -> bool: return "검사 방어구 · AC+2" in label.text),
			"보상 확인 단계는 수치를 보여 주고 정비에서만 분배")
		await _click(preparation.continue_button)
		_check(preparation.maintaining and preparation.title_label.text == "정비", "보상 다음 정비 단계")
		await _check_preparation_layout(preparation)
		var give: Button = await _pick(preparation, "Item0", "Ally1")
		# 칸을 골라 상세 패널에 동작 버튼이 생긴 상태도 검사한다.
		await _check_preparation_layout(preparation)
		await _click(give)
		_check(party[1].get_armor_class() == 16 and party[1].hit_points == 0
			and party[1].get_max_hit_points() == 18,
			"실제 분배 버튼은 전투 불능 궁수에게 방어구 장착")
		_check_pixel_art(main, ["AnimatedSprite2D", "Sprite2D", "Button", "TextureRect"])
		_check(preparation.continue_button.has_focus(), "분배 뒤 키보드 포커스 유지")
		await _click(await _pick(preparation, "Item0", "Ally1"))
		_check(party[1].potion_left == 2 and actual_rewards.size() == 1, "물약 분배와 보상 목록에서 제거")
		actual_rewards.append({"kind": "potion", "name": "검사 물약", "stats": {}})
		# 다음 정비 조작에서 화면을 갱신한 뒤 한도 수령을 검사한다.
		var transfer: Button = preparation.find_child("Transfer1To0", true, false) as Button
		await _click(transfer)
		_check(party[1].potion_left == 1 and party[0].potion_left == 1, "정비 양도 버튼은 물약1개 이동")
		_check(preparation.continue_button.has_focus(), "양도 뒤 키보드 포커스 유지")
		actual_rewards.append({"kind": "potion", "name": "검사 물약", "stats": {}})
		actual_rewards.append({"kind": "potion", "name": "검사 물약", "stats": {}})
		await _click(await _pick(preparation, "Item1", "Ally1"))
		await _click(await _pick(preparation, "Item1", "Ally1"))
		_check((await _pick(preparation, "Item1", "Ally1")).disabled
			and (preparation.find_child("Transfer0To1", true, false) as Button).disabled,
			"물약3개 캐릭터는 수령·양도 도착 버튼 잠금")
		await _click(preparation.find_child("Transfer1To0", true, false) as Button)
		await _click(preparation.find_child("Transfer1To0", true, false) as Button)
		_check(party[1].potion_left == 1 and party[0].potion_left == 3, "양도 도착 한도3까지")
		await _click(preparation.continue_button)
		preparation.discard_dialog.confirmed.emit()
		await process_frame
		_check((battle.get("progress") as CombatActProgress).stage_index == 1 and actual_rewards.is_empty()
			and not preparation.visible and loot.bag.size() == 2
			and loot.bag[0]["kind"] == "weapon" and loot.bag[1]["kind"] == "potion",
			"미수령 장비와 물약을 공용 가방에 보관한 뒤 다음 전투")
		_check(party[1].hit_points == 0 and party[1].get_armor_class() == 16,
			"같은 막 다음 전투는 전투 불능과 장비 유지")
		_check(party[0].weapon["name"] != "버릴 무기", "미수령 장비는 자동 장착하지 않음")
		var actions: CombatActions = battle.get("actions") as CombatActions
		# 실제 보유 물약을 보조 행동으로 소비한다.
		var turns: CombatTurns = battle.get("turns") as CombatTurns
		var dice: CombatDice = CombatDice.new()
		dice.seed = 33
		var living: Array[CombatUnit] = []
		for unit: CombatUnit in battle.get("units"):
			if unit.hit_points > 0:
				living.append(unit)
		turns.start(living, dice)
		party[0].hit_points = 4
		_check(actions.use_self(party[0], "potion") and party[0].potion_left == 2
			and party[0].bonus_action_left == 0, "드랍 물약은 전투 보조 행동으로1개 소비")
		for unit: CombatUnit in party:
			(battle.get("actions") as CombatActions).incapacitate(unit)
		actions.changed.emit()
		_check((battle.get("progress") as CombatActProgress).rewards.is_empty(), "패배는 드랍을 주지 않음")
		await _click(hud.restart_button)
		_check((battle.get("progress") as CombatActProgress).stage_index == 0 and party[0].potion_left == 2
			and party[1].potion_left == 1 and party[1].get_armor_class() == 16,
			"막 재시작은 장비·남은 물약 유지, 소비한 물약 복구 없음")
		_check(party[1].hit_points == 18, "실제 막 재시작에서 방어구 최대 HP 포함 부활")
		_check(loot.bag.size() == 2 and loot.bag[0]["name"] == "버릴 무기"
			and loot.bag[1]["kind"] == "potion", "패배 후 실제 막 재시작은 공용 가방 보존")
	main.queue_free()
	await process_frame


## #265: 16:9와 16:10(논리 640×400) 창에서 정비 화면의 영역이 화면 안에 있고 서로 겹치지 않는다.
func _check_preparation_layout(preparation: CombatPreparation) -> void:
	# 다른 정비 검사의 기존 창 크기를 되돌린다.
	var original: Vector2i = root.size
	for size: Vector2i in [Vector2i(1280, 720), Vector2i(1440, 900), Vector2i(2560, 1600)]:
		root.size = size
		await process_frame
		await process_frame
		var screen: Rect2 = Rect2(Vector2.ZERO, preparation.get_viewport_rect().size)
		_check(preparation.get_global_rect() == screen, "%s: 정비 화면이 논리 화면 전체를 채움" % size)
		var items: Control = preparation.content.get_parent().get_parent() as Control
		var areas: Array[Control] = [preparation.enable_button, preparation.cards, items,
			preparation.detail_panel, preparation.continue_button]
		for index: int in range(areas.size()):
			var rect: Rect2 = areas[index].get_global_rect()
			_check(screen.encloses(rect), "%s: 정비 화면 영역이 화면 안: %s" % [size, areas[index]])
			for other: Control in areas.slice(index + 1):
				_check(not rect.intersects(other.get_global_rect()),
					"%s: 정비 화면 영역끼리 겹치지 않음: %s, %s" % [size, areas[index], other])
	root.size = original
	await process_frame


## #264: 도트 아트(유닛·지형·사물·아이콘)를 그리는 노드는 모두 sharp bilinear 셰이더를 쓴다.
func _check_pixel_art(scene: Node, classes: Array[String]) -> void:
	const INCLUDE: String = '#include "res://scenes/combat/art/pixel_art.gdshaderinc"'
	var allowed: Array[Shader] = [preload("res://scenes/combat/art/pixel_art.gdshader"),
		preload("res://scenes/combat/art/unit_outline.gdshader")]
	var terrain: Shader = preload("res://scenes/combat/art/terrain_detail.gdshader")
	for shader: Shader in allowed + [terrain]:
		_check(INCLUDE in shader.code and "SHARP_TEXTURE(" in shader.code,
			"공용 sharp bilinear 샘플 사용: " + shader.resource_path)
	var counts: Dictionary[String, int] = {}
	for item: CanvasItem in scene.find_children("*", "CanvasItem", true, false):
		var texture: Texture2D = null
		if item is Sprite2D:
			texture = (item as Sprite2D).texture
		elif item is AnimatedSprite2D:
			var sprite: AnimatedSprite2D = item as AnimatedSprite2D
			texture = sprite.sprite_frames.get_frame_texture(sprite.animation, sprite.frame)
		elif item is TextureRect:
			texture = (item as TextureRect).texture
		elif item is Button:
			texture = (item as Button).icon
		if texture == null or not texture.resource_path.begins_with("res://scenes/combat/art/"):
			continue
		counts[item.get_class()] = counts.get(item.get_class(), 0) + 1
		var material: ShaderMaterial = item.material as ShaderMaterial
		_check(material != null and material.shader in allowed, "도트 아트 셰이더 적용: %s" % item.get_path())
	_check(counts.keys().all(func(name: String) -> bool: return name in classes)
		and classes.all(func(name: String) -> bool: return counts.get(name, 0) > 0),
		"도트 아트 노드 종류를 모두 검사: %s" % counts)
	var tiles: int = 0
	for map: TileMapLayer in scene.find_children("*", "TileMapLayer", true, false):
		for cell: Vector2i in map.get_used_cells():
			var material: ShaderMaterial = map.get_cell_tile_data(cell).material as ShaderMaterial
			_check(material != null and material.shader == terrain, "지형 칸 셰이더 적용: %s" % cell)
			tiles += 1
	_check(tiles > 0, "지형 칸을 검사")


func _test_scaled_combat() -> void:
	var main: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	(main.get_node("Battle") as Node2D).stages[6] = load("res://scenes/combat/stage.tres") as CombatStage
	root.add_child(main)
	current_scene = main
	var battle: Node2D = main.get_node("Battle") as Node2D
	battle.set_process(false)
	(battle.get("progress") as CombatActProgress).stage_index = 6
	battle.call("_start_stage", true)
	var units: Array[CombatUnit] = battle.get("units")
	var actor: CombatUnit = units[2]
	var target: CombatUnit = units[0]
	actor.cell = Vector2i(4, 3)
	target.cell = Vector2i(4, 4)
	var turns: CombatTurns = battle.get("turns") as CombatTurns
	var initiative: Array[int] = []
	for unit: CombatUnit in units:
		initiative.append(20 if unit == actor else 1)
	turns.start(units, ScriptedDice.new(initiative))
	_check(turns.current_unit == actor, "이니셔티브 d20 20으로 3막 적이 먼저 행동")
	var preview: CombatChecks.AttackPreview = (battle.get("actions") as CombatActions).grid.attack_preview(actor, target)
	_check(is_equal_approx(preview.chance, 0.5), "3막 풋내기 명중+5 대 아군 AC16 미리보기")
	var actions: CombatActions = battle.get("actions") as CombatActions
	target.reaction_left = 0
	actions.dice = ScriptedDice.new([15], [20]).then_seeded()
	var used: bool = await actions.attack(actor, target)
	_check(used and actions.last_attack.success
		and actions.last_attack.total == actions.last_attack.selected_roll + 5,
		"3막 풋내기 공격도 명중+5 고정")
	var rolled_damage: int = 0
	for rolled: int in actions.last_damage_rolls:
		rolled_damage += rolled
	_check(actions.last_damage == rolled_damage + 1, "3막 풋내기 피해도 고정값1 적용")
	# 방어구 최대 HP를 실제 물약 회복 상한에 적용한다.
	var loot: CombatLoot = battle.get("loot") as CombatLoot
	loot.receive(units[1], {"kind": "armor", "name": "검사 방어구",
		"stats": {"armor_class": 7, "max_hit_points": 14}})
	units[1].hit_points = 26
	units[1].potion_left = 1
	var dice: CombatDice = CombatDice.new()
	dice.seed = 33
	turns.start(units, dice)
	turns.current_unit = units[1]
	_check(actions.use_self(units[1], "potion") and units[1].hit_points == 28,
		"실제 물약 회복은 방어구 포함 최대 HP에서 제한")
	loot.data["extra_drop_chance"] = 0.0
	loot.data["items"] = [loot.data["items"][1]]
	for unit: CombatUnit in units:
		if not unit.is_ally:
			(battle.get("actions") as CombatActions).incapacitate(unit)
	actions.changed.emit()
	var rewards: Array[Dictionary] = (battle.get("progress") as CombatActProgress).rewards
	_check(rewards.size() == 1 and rewards[0]["stats"]["max_hit_points"] >= 9
		and rewards[0]["stats"]["max_hit_points"] <= 14
		and rewards[0]["stats"]["armor_class"] >= 5,
		"실제3막 승리는 얻은3막의 방어구 수치로 보상 생성")
	# 오디오 믹서가 재생 참조를 정리한 뒤 장면을 해제한다.
	(battle.get_node("HitSound") as AudioStreamPlayer).stop()
	await create_timer(0.4).timeout
	main.queue_free()
	await process_frame


func _test_equipped_attack(battle: Node2D) -> void:
	var party: Array[CombatUnit] = battle.get("party")
	var units: Array[CombatUnit] = battle.get("units")
	var loot: CombatLoot = battle.get("loot") as CombatLoot
	loot.receive(party[0], {"kind": "weapon", "name": "검사 무기",
		"stats": {"attack_bonus": 2, "damage_bonus": 3}})
	var target: CombatUnit = units[2]
	party[0].cell = Vector2i(4, 4)
	target.cell = Vector2i(4, 3)
	var turns: CombatTurns = battle.get("turns") as CombatTurns
	var dice: CombatDice = CombatDice.new()
	dice.seed = 33
	turns.start(units, dice)
	turns.select_unit(party[0])
	var actions: CombatActions = battle.get("actions") as CombatActions
	target.reaction_left = 0
	actions.dice = ScriptedDice.new([19], [20]).then_seeded()
	await actions.attack(party[0], target)
	_check(actions.last_attack.success and actions.last_attack.total == actions.last_attack.selected_roll + 7,
		"실제 공격 판정은 무기 명중+2 포함")
	var damage_dice: int = 0
	for value: int in actions.last_damage_rolls:
		damage_dice += value
	_check(actions.last_damage == damage_dice + 6, "실제 피해 판정은 무기 피해+3을 한 번 포함")
	party[0].cell = Vector2i(4, 1)
	units[3].cell = Vector2i(4, 0)
	var preview: CombatChecks.AttackPreview = actions.grid.attack_preview(party[0], units[3])
	_check(is_equal_approx(preview.chance, 0.85), "명중 미리보기도 장비 포함+7 대 AC11")


func _enter_dialog(dialog: ConfirmationDialog) -> void:
	var key: InputEventKey = InputEventKey.new()
	key.keycode = KEY_ENTER
	key.physical_keycode = KEY_ENTER
	key.pressed = true
	dialog.push_input(key)
	await process_frame
	key.pressed = false
	dialog.push_input(key)
	await process_frame


## 정비 칸을 클릭해 고르고 상세 패널의 동작 버튼을 돌려준다.
func _pick(preparation: CombatPreparation, cell: String, action: String) -> Button:
	var button: Button = preparation.find_child(cell, true, false) as Button
	if button == null:
		return null
	await _click(button)
	return preparation.detail.find_child(action, true, false) as Button


func _action(action: String) -> void:
	var event: InputEventAction = InputEventAction.new()
	event.action = action
	event.pressed = true
	Input.parse_input_event(event)
	await process_frame
	event.pressed = false
	Input.parse_input_event(event)
	await process_frame


func _click(button: Button) -> void:
	await process_frame
	var ancestor: Node = button.get_parent()
	while ancestor != null:
		if ancestor is ScrollContainer:
			(ancestor as ScrollContainer).ensure_control_visible(button)
			await process_frame
		ancestor = ancestor.get_parent()
	var point: Vector2 = root.get_final_transform() * button.get_global_rect().get_center()
	var click: InputEventMouseButton = InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.position = point
	click.global_position = point
	click.pressed = true
	Input.parse_input_event(click)
	await process_frame
	click.pressed = false
	Input.parse_input_event(click)
	await process_frame
	await process_frame


func _test_accidental_advance() -> void:
	var main: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	(main.get_node("Battle") as Node2D).stages[0] = load("res://scenes/combat/stage.tres") as CombatStage
	root.add_child(main)
	current_scene = main
	var battle: Node2D = main.get_node("Battle") as Node2D
	battle.set_process(false)
	for unit: CombatUnit in battle.get("units"):
		if not unit.is_ally:
			(battle.get("actions") as CombatActions).incapacitate(unit)
	(battle.get("actions") as CombatActions).changed.emit()
	await _click((battle.get_node("UI/TurnHud") as CombatTurnHud).restart_button)
	var preparation: CombatPreparation = battle.get_node("UI/Preparation") as CombatPreparation
	var count: int = preparation.rewards.size()
	await _click(preparation.continue_button)
	await _click(preparation.continue_button)
	_check((battle.get("progress") as CombatActProgress).stage_index == 0 and preparation.rewards.size() == count,
		"정비 진입 버튼 연속 클릭은 미수령 보상을 바로 폐기하지 않음")
	if preparation.has_node("Discard"):
		var dialog: ConfirmationDialog = preparation.get_node("Discard") as ConfirmationDialog
		var stale_focus_requests: Array[int] = [0]
		var finishes: Array[int] = [0]
		# Headless 접근성 분기 모형. 제거된 exclusive child에 보내는 포커스를 검출한다.
		var on_parent_focus: Callable = func() -> void:
			if dialog.exclusive:
				stale_focus_requests[0] += 1
				dialog.grab_focus()
		var on_finished: Callable = func() -> void: finishes[0] += 1
		root.focus_entered.connect(on_parent_focus)
		preparation.finished.connect(on_finished)
		_check(dialog.visible and dialog.get_cancel_button().has_focus(), "폐기 확인 기본 포커스는 돌아가기")
		var key: InputEventKey = InputEventKey.new()
		key.keycode = KEY_ENTER
		key.physical_keycode = KEY_ENTER
		key.pressed = true
		dialog.push_input(key)
		await process_frame
		key.pressed = false
		dialog.push_input(key)
		await process_frame
		_check(not dialog.visible and preparation.visible and preparation.rewards.size() == count,
			"확인 창의 Enter 입력은 돌아가기와 보상 유지")
		for choice: String in ["cancel", "close", "escape"]:
			preparation.continue_button.pressed.emit()
			await process_frame
			await process_frame
			_check(dialog.visible and dialog.exclusive and dialog.get_cancel_button().has_focus(),
				"폐기 재확인은 모달과 돌아가기 포커스를 복원: " + choice)
			match choice:
				"cancel":
					dialog.get_cancel_button().pressed.emit()
				"close":
					dialog.notification(Window.NOTIFICATION_WM_CLOSE_REQUEST)
				"escape":
					var escape_event: InputEventKey = InputEventKey.new()
					escape_event.keycode = KEY_ESCAPE
					escape_event.physical_keycode = KEY_ESCAPE
					escape_event.pressed = true
					Input.parse_input_event(escape_event)
					await process_frame
					escape_event.pressed = false
					Input.parse_input_event(escape_event)
			await process_frame
			await process_frame
			_check(not dialog.visible and preparation.visible and preparation.rewards.size() == count
				and finishes[0] == 0 and (battle.get("progress") as CombatActProgress).stage_index == 0,
				"폐기 취소는 보상과 스테이지를 유지: " + choice)
		preparation.continue_button.pressed.emit()
		await process_frame
		await process_frame
		dialog.get_ok_button().grab_focus()
		key.pressed = true
		dialog.push_input(key)
		await process_frame
		key.pressed = false
		dialog.push_input(key)
		await process_frame
		_check((battle.get("progress") as CombatActProgress).stage_index == 1
			and preparation.rewards.is_empty() and finishes[0] == 1, "명시적 폐기 확인 후 한 번 진행")
		_check(stale_focus_requests[0] == 0, "제거된 폐기 확인 창에 접근성 포커스를 전달하지 않음")
		root.focus_entered.disconnect(on_parent_focus)
		preparation.finished.disconnect(on_finished)
	main.queue_free()
	await process_frame
