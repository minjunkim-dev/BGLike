extends SceneTree
## #394 개발자 진입점. 기능 테스트용 큰 맵(28×20)으로 전투를 바로 시작한다.
## 실행: `godot --path . --script res://tests/large_map_battle.gd`
## 이 세션의 1-1 자리만 큰 맵으로 바꾸고 자동 저장을 끈다. 실제 진행·저장·배포 묶음에는 들어가지 않는다.

const STAGE_PATH: String = "res://tests/large_map.tres"
const GAME_SCENE: String = "res://scenes/game.tscn"


## 첫 스테이지를 큰 맵으로 바꾼 게임 장면. 새 배열을 넣어 장면 파일의 실제9개 진행은 그대로 두고 자동 저장을 끈다.
static func instantiate_game() -> Node:
	GameSave.autosave = false
	var game: Node = (load(GAME_SCENE) as PackedScene).instantiate()
	var battle: Node = game.get_node("Battle")
	var stages: Array[CombatStage] = []
	stages.assign(battle.get("stages"))
	stages[0] = load(STAGE_PATH) as CombatStage
	# 전투 장면의 _ready가 1-1을 만들기 전에 바꾼다.
	battle.set("stages", stages)
	return game


func _initialize() -> void:
	_start.call_deferred()


func _start() -> void:
	GameSettings.apply()
	var game: Node = instantiate_game()
	root.add_child(game)
	current_scene = game
