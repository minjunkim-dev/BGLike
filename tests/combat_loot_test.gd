extends SceneTree
## 드랍 모델과 실제 보상·정비 입력을 검사한다.

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
		var dice: RandomNumberGenerator = RandomNumberGenerator.new()
		dice.seed = 55
		_test_armor_hit_points(loot)
		_test_act_values(loot, dice)
		loot.data["extra_drop_chance"] = 0.0
		_check(loot.roll_rewards(2, dice, 1).size() == 1, "추가 확률0이어도 보장1개")
		loot.data["extra_drop_chance"] = 1.0
		_check(loot.roll_rewards(2, dice, 1).size() == 3, "확률1이면 보장1개와 몬스터당1개")
		_test_items(loot, dice)
	await _test_reward_flow()
	await _test_accidental_advance()
	await _test_scaled_combat()
	# 완료된 검사 코루틴의 참조를 해제한 뒤 종료한다.
	await process_frame
	print("Combat loot: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)


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


func _test_items(loot: CombatLoot, dice: RandomNumberGenerator) -> void:
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


func _test_act_values(loot: CombatLoot, dice: RandomNumberGenerator) -> void:
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


func _test_reward_flow() -> void:
	var main: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
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
		party[1].hit_points = 0
		party[1].potion_left = 1
		(battle.get("turns") as CombatTurns).remove_unit(party[1])
		for unit: CombatUnit in battle.get("units"):
			if not unit.is_ally:
				unit.hit_points = 0
				(battle.get("turns") as CombatTurns).remove_unit(unit)
		(battle.get("actions") as CombatActions).changed.emit()
		var actual_rewards: Array[Dictionary] = battle.get("rewards")
		_check(actual_rewards.size() >= 1 and actual_rewards.size() <= 3, "실제 승리에서 적2명 기준 드랍")
		(battle.get("actions") as CombatActions).changed.emit()
		_check(actual_rewards == battle.get("rewards"), "결과 갱신은 드랍을 다시 굴리지 않음")
		# 입력 검사를 재현할 고정 보상. 드랍 생성은 위와 모델 검사에서 별도로 확인한다.
		actual_rewards.clear()
		actual_rewards.append({"kind": "armor", "name": "검사 방어구",
			"stats": {"armor_class": 2, "max_hit_points": 4}})
		actual_rewards.append({"kind": "potion", "name": "검사 물약", "stats": {}})
		actual_rewards.append({"kind": "weapon", "name": "버릴 무기", "stats": {"damage_bonus": 1}})
		await _click(hud.restart_button)
		var preparation: CombatPreparation = battle.get_node("UI/Preparation") as CombatPreparation
		_check(preparation.visible and not preparation.maintaining, "승리 뒤 보상 화면 진입")
		_check(battle.get("stage_index") == 0, "보상 확인은 다음 전투를 시작하지 않음")
		_check(preparation.content.get_node("Item0").get_child_count() == 1,
			"보상 확인 단계는 수치를 보여 주고 정비에서만 분배")
		await _click(preparation.continue_button)
		_check(preparation.maintaining and preparation.title_label.text == "정비", "보상 다음 정비 단계")
		await _click(preparation.content.get_node("Item0/Ally1") as Button)
		_check(party[1].get_armor_class() == 16 and party[1].hit_points == 0
			and party[1].get_max_hit_points() == 18,
			"실제 분배 버튼은 전투 불능 궁수에게 방어구 장착")
		_check(preparation.continue_button.has_focus(), "분배 뒤 키보드 포커스 유지")
		await _click(preparation.content.get_node("Item0/Ally1") as Button)
		_check(party[1].potion_left == 2 and actual_rewards.size() == 1, "물약 분배와 보상 목록에서 제거")
		actual_rewards.append({"kind": "potion", "name": "검사 물약", "stats": {}})
		# 다음 정비 조작에서 화면을 갱신한 뒤 한도 수령을 검사한다.
		var transfer: Button = preparation.content.find_child("Transfer1To0", true, false) as Button
		await _click(transfer)
		_check(party[1].potion_left == 1 and party[0].potion_left == 1, "정비 양도 버튼은 물약1개 이동")
		_check(preparation.continue_button.has_focus(), "양도 뒤 키보드 포커스 유지")
		actual_rewards.append({"kind": "potion", "name": "검사 물약", "stats": {}})
		actual_rewards.append({"kind": "potion", "name": "검사 물약", "stats": {}})
		await _click(preparation.content.get_node("Item1/Ally1") as Button)
		await _click(preparation.content.get_node("Item1/Ally1") as Button)
		_check((preparation.content.get_node("Item1/Ally1") as Button).disabled
			and (preparation.content.find_child("Transfer0To1", true, false) as Button).disabled,
			"물약3개 캐릭터는 수령·양도 도착 버튼 잠금")
		await _click(preparation.content.find_child("Transfer1To0", true, false) as Button)
		await _click(preparation.content.find_child("Transfer1To0", true, false) as Button)
		_check(party[1].potion_left == 1 and party[0].potion_left == 3, "양도 도착 한도3까지")
		await _click(preparation.continue_button)
		preparation.discard_dialog.confirmed.emit()
		await process_frame
		_check(battle.get("stage_index") == 1 and actual_rewards.is_empty()
			and not preparation.visible, "미수령 보상 폐기 뒤 다음 전투")
		_check(party[1].hit_points == 0 and party[1].get_armor_class() == 16,
			"같은 막 다음 전투는 전투 불능과 장비 유지")
		_check(party[0].weapon["name"] != "버릴 무기", "미수령 장비는 자동 장착하지 않음")
		var actions: CombatActions = battle.get("actions") as CombatActions
		# 실제 보유 물약을 보조 행동으로 소비한다.
		var turns: CombatTurns = battle.get("turns") as CombatTurns
		var dice: RandomNumberGenerator = RandomNumberGenerator.new()
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
			unit.hit_points = 0
			turns.remove_unit(unit)
		actions.changed.emit()
		_check(battle.get("rewards").is_empty(), "패배는 드랍을 주지 않음")
		await _click(hud.restart_button)
		_check(battle.get("stage_index") == 0 and party[0].potion_left == 2
			and party[1].potion_left == 1 and party[1].get_armor_class() == 16,
			"막 재시작은 장비·남은 물약 유지, 소비한 물약 복구 없음")
		_check(party[1].hit_points == 18, "실제 막 재시작에서 방어구 최대 HP 포함 부활")
	main.queue_free()
	await process_frame


func _test_scaled_combat() -> void:
	var main: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	current_scene = main
	var battle: Node2D = main.get_node("Battle") as Node2D
	battle.set_process(false)
	battle.set("stage_index", 6)
	battle.call("_start_stage", true)
	var units: Array[CombatUnit] = battle.get("units")
	var actor: CombatUnit = units[2]
	var target: CombatUnit = units[0]
	actor.cell = Vector2i(4, 3)
	target.cell = Vector2i(4, 4)
	var turns: CombatTurns = battle.get("turns") as CombatTurns
	var dice: RandomNumberGenerator = RandomNumberGenerator.new()
	for seed_value: int in range(100):
		dice.seed = seed_value
		turns.start(units, dice)
		if turns.current_unit == actor:
			break
	var preview: CombatChecks.AttackPreview = CombatChecks.attack_preview(actor, target, units)
	_check(is_equal_approx(preview.chance, 0.75), "3막 적 명중+10 대 아군 AC16 미리보기")
	var actions: CombatActions = battle.get("actions") as CombatActions
	actions.save_dc = 0
	for seed_value: int in range(100):
		dice.seed = seed_value
		if dice.randi_range(1, 20) >= 6:
			actions.dice.seed = seed_value
			break
	var used: bool = await actions.attack(actor, target)
	_check(used and actions.last_attack.success
		and actions.last_attack.total == actions.last_attack.selected_roll + 10,
		"3막 실제 적 공격에 명중+5 강화 적용")
	var rolled_damage: int = 0
	for rolled: int in actions.last_damage_rolls:
		rolled_damage += rolled
	_check(actions.last_damage == rolled_damage + 7, "3막 실제 적 피해에+4 강화 한 번 적용")
	# 적 강화와 별개로 방어구 최대 HP를 실제 물약 회복 상한에 적용한다.
	var loot: CombatLoot = battle.get("loot") as CombatLoot
	loot.receive(units[1], {"kind": "armor", "name": "검사 방어구",
		"stats": {"armor_class": 7, "max_hit_points": 14}})
	units[1].hit_points = 26
	units[1].potion_left = 1
	dice.seed = 33
	turns.start(units, dice)
	turns.current_unit = units[1]
	_check(actions.use_self(units[1], "potion") and units[1].hit_points == 28,
		"실제 물약 회복은 방어구 포함 최대 HP에서 제한")
	loot.data["extra_drop_chance"] = 0.0
	loot.data["items"] = [loot.data["items"][1]]
	for unit: CombatUnit in units:
		if not unit.is_ally:
			unit.hit_points = 0
			turns.remove_unit(unit)
	actions.changed.emit()
	var rewards: Array[Dictionary] = battle.get("rewards")
	_check(rewards.size() == 1 and rewards[0]["stats"]["max_hit_points"] >= 9
		and rewards[0]["stats"]["max_hit_points"] <= 14
		and rewards[0]["stats"]["armor_class"] >= 5,
		"실제3막 승리는 얻은3막의 방어구 수치로 보상 생성")
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
	var dice: RandomNumberGenerator = RandomNumberGenerator.new()
	dice.seed = 33
	turns.start(units, dice)
	turns.select_unit(party[0])
	var actions: CombatActions = battle.get("actions") as CombatActions
	actions.save_dc = 0
	var attack_seed: int = 0
	for candidate: int in range(100):
		dice.seed = candidate
		if dice.randi_range(1, 20) >= 12:
			attack_seed = candidate
			break
	actions.dice.seed = attack_seed
	await actions.attack(party[0], target)
	_check(actions.last_attack.success and actions.last_attack.total == actions.last_attack.selected_roll + 7,
		"실제 공격 판정은 무기 명중+2 포함")
	var damage_dice: int = 0
	for value: int in actions.last_damage_rolls:
		damage_dice += value
	_check(actions.last_damage == damage_dice + 6, "실제 피해 판정은 무기 피해+3을 한 번 포함")
	party[0].cell = Vector2i(4, 1)
	units[3].cell = Vector2i(4, 0)
	var preview: CombatChecks.AttackPreview = CombatChecks.attack_preview(party[0], units[3], units)
	_check(is_equal_approx(preview.chance, 0.7), "명중 미리보기도 장비 포함+7 대 AC14")


func _click(button: Button) -> void:
	await process_frame
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
	root.add_child(main)
	current_scene = main
	var battle: Node2D = main.get_node("Battle") as Node2D
	battle.set_process(false)
	for unit: CombatUnit in battle.get("units"):
		if not unit.is_ally:
			unit.hit_points = 0
			(battle.get("turns") as CombatTurns).remove_unit(unit)
	(battle.get("actions") as CombatActions).changed.emit()
	await _click((battle.get_node("UI/TurnHud") as CombatTurnHud).restart_button)
	var preparation: CombatPreparation = battle.get_node("UI/Preparation") as CombatPreparation
	var count: int = preparation.rewards.size()
	await _click(preparation.continue_button)
	await _click(preparation.continue_button)
	_check(battle.get("stage_index") == 0 and preparation.rewards.size() == count,
		"정비 진입 버튼 연속 클릭은 미수령 보상을 바로 폐기하지 않음")
	if preparation.has_node("Discard"):
		var dialog: ConfirmationDialog = preparation.get_node("Discard") as ConfirmationDialog
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
		_check(battle.get("stage_index") == 1 and preparation.rewards.is_empty(), "명시적 폐기 확인 후 진행")
	main.queue_free()
	await process_frame
