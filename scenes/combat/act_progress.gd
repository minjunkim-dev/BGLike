class_name CombatActProgress
extends RefCounted
## 3막 진행. 스테이지 승패에 따라 정비 단계 보상, 막 재시작, 3막 졸업을 정한다.

const STAGES_PER_ACT: int = 3

var stage_count: int
var stage_index: int = 0
var graduated: bool = false
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


func record_victory(loot: CombatLoot, monster_count: int, dice: CombatDice) -> void:
	if _victory_recorded:
		return
	rewards = loot.roll_rewards(monster_count, dice, act_number())
	_victory_recorded = true


## 아군 전멸 뒤 그 막의 첫 스테이지로 돌아간다.
func restart_act() -> void:
	stage_index -= stage_index % STAGES_PER_ACT


## 정비 단계를 마친 뒤 다음 스테이지로 간다. 마지막 스테이지면 3막 졸업이다.
func advance() -> void:
	if is_final_stage():
		graduated = true
	else:
		stage_index += 1
