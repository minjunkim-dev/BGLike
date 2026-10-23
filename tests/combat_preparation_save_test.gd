extends SceneTree
## 보상 확인·정비 화면 중 자동 저장과 이어하기 (#282). 동작마다 저장하고, 저장을 새 게임 장면에 복원해
## 같은 화면 단계·가방·장비·물약으로 돌아오는지 본다. 칸 선택과 확인 창은 저장하지 않는다.

## 여러 worktree가 같은 user://를 쓰므로 실행마다 폴더를 나눈다. 사용자의 저장을 건드리지 않는다.
var directory: String = "user://tests/preparation_save/%d" % OS.get_process_id()
var checks: int = 0
var failures: int = 0
var _save_count: int = 0


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
	await _test_actions()
	await _test_continue_after_restore()
	await _test_rejects_bad_saves()
	GameSave.autosave = false
	GameSave.delete()
	DirAccess.remove_absolute(directory)
	print("Preparation save: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)


## 1-1을 이긴 게임 장면. 아군 장비·가방·물약과 이번 드랍을 정해 둔다. 결과 창까지 저장한 상태다.
func _won_battle() -> Node2D:
	var battle: Node2D = _battle()
	var loot: CombatLoot = battle.get("loot")
	var party: Array[CombatUnit] = battle.get("party")
	var actions: CombatActions = battle.get("actions")
	loot.receive(party[0], _item("weapon", {"attack_bonus": 1, "damage_bonus": 1}))
	loot.receive(party[1], _item("armor", {"armor_class": 1, "max_hit_points": 2}))
	loot.bag.append_array([_item("weapon", {"attack_bonus": 1, "damage_bonus": 2}), _item("potion", {})])
	party[0].potion_left = 2
	for unit: CombatUnit in actions.units:
		if not unit.is_ally:
			actions.incapacitate(unit)
	actions.changed.emit()
	var rewards: Array[Dictionary] = (battle.get("progress") as CombatActProgress).rewards
	var armor: Dictionary = _item("armor", {"armor_class": 2, "max_hit_points": 2})
	rewards.assign([_item("weapon", {"attack_bonus": 1, "damage_bonus": 3}), _item("potion", {}), armor, armor])
	battle.call("_process", 0.0)
	return battle


func _battle() -> Node2D:
	var main: Node = (load("res://scenes/game.tscn") as PackedScene).instantiate()
	root.add_child(main)
	var battle: Node2D = main.get_node("Battle") as Node2D
	battle.set_process(false)
	return battle


func _item(kind: String, stats: Dictionary) -> Dictionary:
	var items: Array = CombatLoot.new().data["items"]
	var item: Dictionary = items[items.find_custom(func(entry: Dictionary) -> bool: return entry.kind == kind)]
	item = item.duplicate(true)
	item["stats"] = stats
	return item


func _free(battle: Node2D) -> void:
	battle.get_parent().queue_free()
	await process_frame


## 저장한 프레임을 지나 파일의 저장이 그 순간의 상태와 같고, 새 장면에 복원하면 같은 화면으로 돌아오는지 본다.
func _check_saved(battle: Node2D, label: String) -> void:
	var before: int = _save_count
	battle.call("_process", 0.0)
	var preparation: CombatPreparation = battle.get("preparation")
	var sections: Dictionary = GameSave.read().get("sections", {})
	_check(_save_count == before + 1, label + ": 동작 뒤 한 번 저장")
	_check(sections.get("combat") == battle.call("combat_state"), label + ": 저장한 전투 상태가 그 순간과 같음")
	var screen: Dictionary = {"maintaining": preparation.maintaining} if preparation.visible else {}
	_check(sections.get("preparation", {}) == screen, label + ": 저장한 화면 단계 %s" % sections.get("preparation"))
	var restored: Node2D = _battle()
	_count_saves(restored)
	_check(restored.call("restore_save", sections), label + ": 복원 성공")
	var copy: CombatPreparation = restored.get("preparation")
	_check(restored.call("combat_state") == battle.call("combat_state"),
		label + ": 복원한 가방·장비·물약·남은 보상이 같음")
	_check(copy.visible == preparation.visible and (not copy.visible or copy.maintaining == preparation.maintaining
		and copy.title_label.text == preparation.title_label.text), label + ": 같은 화면 단계로 돌아옴")
	_check(not (copy.visible and (restored.get_node("UI/TurnHud/Result") as Control).visible),
		label + ": 결과 창 없이 정비 화면만 열림")
	restored.call("_process", 0.0)
	_check(_save_count == before + 1, label + ": 복원한 상태를 다시 저장하지 않음")
	await _free(restored)


func _count_saves(battle: Node2D) -> void:
	battle.connect("autosaved", func() -> void: _save_count += 1)


## 보상 수령, 장착·교체·해제, 물약 주기·넘기기, 폐기, 미수령 보상 보관 뒤마다 저장·복원한다.
func _test_actions() -> void:
	var battle: Node2D = _won_battle()
	_count_saves(battle)
	var preparation: CombatPreparation = battle.get("preparation")
	var loot: CombatLoot = battle.get("loot")
	var party: Array[CombatUnit] = battle.get("party")
	_check(GameSave.read().get("sections", {}).keys() == ["combat"], "결과 창은 전투 칸만 저장")
	battle.call("_restart")
	await _check_saved(battle, "보상 확인 화면")
	preparation._continue()
	await _check_saved(battle, "정비 화면")
	preparation._receive(0, 0)
	_check(party[0].weapon.stats.damage_bonus == 3 and loot.bag.size() == 3, "보상 장착으로 무기 교체")
	await _check_saved(battle, "보상 장착·교체")
	preparation._receive(0, 1)
	_check(party[1].potion_left == 1, "보상 물약 주기")
	await _check_saved(battle, "보상 물약 주기")
	preparation._receive(0, 0)
	_check(party[0].armor.stats.armor_class == 2, "보상 방어구 장착")
	await _check_saved(battle, "보상 방어구 장착")
	preparation._receive_bag(0, 0)
	_check(party[0].weapon.stats.damage_bonus == 2, "가방 무기 장착")
	await _check_saved(battle, "가방에서 장착")
	preparation._receive_bag(loot.bag.find_custom(func(item: Dictionary) -> bool: return item.kind == "potion"), 1)
	_check(party[1].potion_left == 2, "가방 물약 주기")
	await _check_saved(battle, "가방에서 물약 주기")
	preparation._unequip_armor(1)
	_check(party[1].armor.is_empty(), "방어구 해제")
	await _check_saved(battle, "방어구 해제")
	preparation._transfer(0, 1)
	_check(party[0].potion_left == 1 and party[1].potion_left == 3, "물약 넘기기")
	await _check_saved(battle, "물약 넘기기")

	# 칸 선택과 열린 확인 창은 상태를 바꾸지 않아 저장하지 않는다.
	var before: int = _save_count
	preparation._select("bag", 0)
	preparation._discard(0)
	battle.call("_process", 0.0)
	_check(_save_count == before and preparation.discard_dialog.visible, "칸 선택·폐기 확인 창은 저장하지 않음")
	var bag: int = loot.bag.size()
	preparation._confirm()
	_check(loot.bag.size() == bag - 1, "가방 아이템 폐기")
	await _check_saved(battle, "폐기")

	preparation._continue()
	battle.call("_process", 0.0)
	_check(_save_count == before + 1 and preparation.discard_dialog.visible, "정비 종료 확인 창은 저장하지 않음")
	var stored: Dictionary = preparation.rewards[0].duplicate(true)
	preparation._confirm()
	_check(not preparation.visible and (battle.get("progress") as CombatActProgress).stage_index == 1
		and loot.bag.back() == stored, "미수령 보상을 가방에 보관하고 다음 전투 시작")
	await _check_saved(battle, "정비 종료 뒤 다음 전투 시작")
	await _free(battle)


## 자동 저장이 꺼져 있으면 정비 동작도 사용자의 저장 파일을 만들지 않는다.
func _test_autosave_switch() -> void:
	GameSave.delete()
	var battle: Node2D = _won_battle()
	var preparation: CombatPreparation = battle.get("preparation")
	battle.call("_restart")
	preparation._continue()
	preparation._transfer(0, 1)
	battle.call("_process", 0.0)
	_check(not GameSave.has_save(), "자동 저장이 꺼져 있으면 정비 화면도 저장하지 않음")
	await _free(battle)


## 고친 정비 칸은 읽을 수 없는 저장이다. 전투를 바꾸지 않고 false를 돌려준다.
func _test_rejects_bad_saves() -> void:
	var source: Node2D = _won_battle()
	source.call("_restart")
	source.call("_process", 0.0)
	var good: Dictionary = GameSave.read().sections
	await _free(source)
	var fighting: Node2D = _battle()
	var ongoing: Dictionary = fighting.call("combat_state")
	ongoing.rewarded = true
	await _free(fighting)
	var unrolled: Dictionary = good.combat.duplicate(true)
	unrolled.rewarded = false
	var cases: Dictionary[String, Variant] = {
		"정비 칸이 Dictionary가 아님": {"combat": good.combat, "preparation": true},
		"정비 단계가 bool이 아님": {"combat": good.combat, "preparation": {"maintaining": 1}},
		"모르는 정비 칸 값": {"combat": good.combat, "preparation": {"maintaining": true, "selected": 0}},
		"살아 있는 적이 있는 정비 화면": {"combat": ongoing, "preparation": {"maintaining": false}},
		"드랍을 굴리지 않은 정비 화면": {"combat": unrolled, "preparation": {"maintaining": false}},
		"전투 칸 없음": {"preparation": {"maintaining": false}},
		"sections가 Dictionary가 아님": [good],
	}
	for name: String in cases:
		var battle: Node2D = _battle()
		var before: Dictionary = battle.call("combat_state")
		_check(not battle.call("restore_save", cases[name]) and battle.call("combat_state") == before
			and not (battle.get("preparation") as CombatPreparation).visible, name + ": 읽지 않고 전투를 바꾸지 않음")
		await _free(battle)
	var battle: Node2D = _battle()
	_check(battle.call("restore_save", {"combat": good.combat}), "정비 칸 없는 승리 저장은 결과 창으로 복원")
	_check(not (battle.get("preparation") as CombatPreparation).visible
		and (battle.get_node("UI/TurnHud/Result") as Control).visible, "정비 칸 없으면 결과 창")
	await _free(battle)


## 이어한 정비 화면에서 동작하면 그 동작도 저장된다. 남은 보상 목록이 전투 저장과 같은 목록이다.
func _test_continue_after_restore() -> void:
	var source: Node2D = _won_battle()
	source.call("_restart")
	(source.get("preparation") as CombatPreparation)._continue()
	source.call("_process", 0.0)
	var sections: Dictionary = GameSave.read().sections
	await _free(source)
	var battle: Node2D = _battle()
	_count_saves(battle)
	_check(battle.call("restore_save", sections), "정비 화면 저장 복원")
	var before: int = _save_count
	(battle.get("preparation") as CombatPreparation)._receive(1, 1)
	battle.call("_process", 0.0)
	var saved: Dictionary = GameSave.read().sections
	_check(_save_count == before + 1 and saved.combat.rewards.size() == 3
		and saved.combat.units[1].potion_left == 1 and saved.preparation == {"maintaining": true},
		"이어한 정비 화면의 물약 주기가 남은 보상과 함께 저장됨")
	await _free(battle)
