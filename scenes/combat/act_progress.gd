class_name CombatActProgress
extends RefCounted
## 3막 진행. 스테이지 승패에 따라 정비 단계 보상, 막 재시작, 3막 졸업을 정한다.

const STAGES_PER_ACT: int = 3

var stage_count: int
var stage_index: int = 0
var graduated: bool = false
## 파티 주사위 레벨. 모든 캐릭터와 6개 능력치가 공유한다. 새 게임은 0이고 막의 마지막 스테이지를 처음 이길 때 1 오른다 (#477).
var level: int = 0
## 이번 스테이지의 드랍. 승리를 처음 기록할 때 한 번만 굴린다.
var rewards: Array[Dictionary] = []
var _victory_recorded: bool = false


func _init(count: int) -> void:
	stage_count = count


func act_number() -> int:
	return stage_index / STAGES_PER_ACT + 1


func stage_in_act() -> int:
	return stage_index % STAGES_PER_ACT + 1


func is_final_stage() -> bool:
	return stage_index == stage_count - 1


func is_last_in_act() -> bool:
	return stage_in_act() == STAGES_PER_ACT


## 막의 첫 스테이지는 HP, 전투 불능, 스킬 횟수를 회복한다.
func starts_act() -> bool:
	return stage_in_act() == 1


func begin_stage() -> void:
	rewards.clear()
	_victory_recorded = false


## picked는 이번 전투에서 주운 상자 아이템이다. 굴린 드랍 뒤에 합산한다.
func record_victory(loot: CombatLoot, monster_count: int, dice: CombatDice, picked: Array[Dictionary] = []) -> void:
	if _victory_recorded:
		return
	rewards = loot.roll_rewards(monster_count, dice, act_number())
	rewards.append_array(picked.duplicate(true))
	_victory_recorded = true
	# 깬 막 번호로 올려 이미 깬 막의 재클리어가 두 번 오르지 않게 한다.
	if is_last_in_act():
		level = maxi(level, act_number())


func save_state() -> Dictionary:
	return {"stage": stage_index, "rewards": rewards, "rewarded": _victory_recorded, "level": level}


## 이어하기. 승리 뒤에 저장했다면 굴린 드랍을 그대로 쓰고 다시 굴리지 않는다.
func load_state(data: Dictionary) -> void:
	stage_index = data.stage
	graduated = false
	rewards.assign(data.rewards)
	_victory_recorded = data.rewarded
	level = data.level


## 아군 전멸 뒤 그 막의 첫 스테이지로 돌아간다.
func restart_act() -> void:
	stage_index -= stage_index % STAGES_PER_ACT


## 정비 단계를 마친 뒤 다음 스테이지로 간다. 마지막 스테이지면 3막 졸업이다.
func advance() -> void:
	if is_final_stage():
		graduated = true
	else:
		stage_index += 1
