extends SceneTree
## 저장 한 슬롯과 설정 파일: 정상, 버전 불일치, 깨진 파일, 쓰기 중단, 삭제 범위를 검사한다.

## 여러 worktree가 같은 user://를 쓰므로 실행마다 폴더를 나눈다.
var directory: String = "user://tests/save/%d" % OS.get_process_id()

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
	DirAccess.make_dir_recursive_absolute(directory)
	GameSave.path = directory + "/save.bin"
	GameSettings.path = directory + "/settings.cfg"
	_clean()
	_test_round_trip()
	_test_version_mismatch()
	_test_corrupt_files()
	_test_interrupted_write()
	_test_settings_survive_delete()
	_clean()
	DirAccess.remove_absolute(directory)
	print("Save: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)


func _clean() -> void:
	GameSave.delete()
	for file: String in [GameSettings.path, GameSettings.path + ".tmp"]:
		if FileAccess.file_exists(file):
			DirAccess.remove_absolute(file)


func _sections() -> Dictionary:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 0x7FFF_FFFF_FFFF_FFF1
	rng.randi()
	return {"combat": {"rng_state": rng.state, "cells": {Vector2i(3, -2): "rock"}, "hit_points": [12, 0]}}


func _test_round_trip() -> void:
	_check(not GameSave.has_save() and GameSave.read().is_empty(), "저장이 없으면 없음으로 조회")
	_check(GameSave.write(3, 2, _sections()) == OK, "저장 쓰기 성공")
	_check(GameSave.has_save(), "쓴 뒤 저장 있음")
	_check(FileAccess.get_file_as_bytes(GameSave.path).decode_u32(4) == 2, "현재 형식 2의 머리로 저장")
	var save: Dictionary = GameSave.read()
	_check(save.get("act") == 3 and save.get("stage") == 2, "막과 스테이지를 그대로 읽음")
	_check(save.get("sections") == _sections(), "64비트 난수 상태, Vector2i 키, 배열을 그대로 읽음")
	_check(GameSave.summary_text(save) == "3막 2스테이지 진행 중", "요약 문구: " + GameSave.summary_text(save))
	_check(not FileAccess.file_exists(GameSave.path + ".tmp"), "쓰기 뒤 임시 파일이 남지 않음")
	_check(GameSave.delete() == OK, "삭제 성공")
	_check(not GameSave.has_save() and GameSave.read().is_empty(), "삭제 뒤 저장 없음")


func _test_version_mismatch() -> void:
	GameSave.write(1, 1, _sections())
	var bytes: PackedByteArray = FileAccess.get_file_as_bytes(GameSave.path)
	for version: int in [0, 1, GameSave.FORMAT_VERSION + 1]:
		bytes.encode_u32(4, version)
		_write_raw(GameSave.path, bytes)
		_check(GameSave.has_save() and GameSave.read().is_empty(), "형식 버전 %d은 읽지 않음" % version)
		_check(FileAccess.get_file_as_bytes(GameSave.path) == bytes, "읽을 수 없는 형식 버전 %d의 파일을 보존" % version)
	_check(GameSave.summary_text({}) == "저장을 읽을 수 없음", "읽을 수 없는 저장의 요약")
	GameSave.delete()


func _test_corrupt_files() -> void:
	GameSave.write(1, 1, _sections())
	var good: PackedByteArray = FileAccess.get_file_as_bytes(GameSave.path)
	var header: PackedByteArray = good.slice(0, GameSave.HEADER_SIZE)
	var cases: Dictionary[String, PackedByteArray] = {
		"빈 파일": PackedByteArray(),
		"머리만 있음": header,
		"다른 파일": "not a save file".to_utf8_buffer(),
		"본문이 잘림": good.slice(0, good.size() - 7),
		"본문이 쓰레기": header + PackedByteArray([250, 1, 2, 3, 4, 5, 6, 7, 8, 9]),
		"본문 모양이 다름": header + var_to_bytes([1, 2, 3]),
		"막이 정수가 아님": header + var_to_bytes({"act": "3", "stage": 2, "sections": {}}),
		"스테이지가 없음": header + var_to_bytes({"act": 3, "sections": {}}),
		"sections가 배열": header + var_to_bytes({"act": 3, "stage": 2, "sections": []}),
	}
	# Godot는 깨진 본문을 해석할 때 ERROR를 출력한다. 결과는 read()의 반환값으로 판정한다.
	for name: String in cases:
		_write_raw(GameSave.path, cases[name])
		_check(GameSave.read().is_empty(), "깨진 저장을 거부: " + name)
	GameSave.delete()


func _test_interrupted_write() -> void:
	GameSave.write(2, 3, _sections())
	var previous: Dictionary = GameSave.read()
	# 새 저장을 임시 파일에 반쯤 쓰다 종료된 상태.
	var partial: PackedByteArray = FileAccess.get_file_as_bytes(GameSave.path)
	_write_raw(GameSave.path + ".tmp", partial.slice(0, partial.size() / 2))
	_check(GameSave.read() == previous, "임시 파일이 반만 쓰여도 이전 저장을 읽음")
	_check(GameSave.write(3, 1, _sections()) == OK and GameSave.read().get("act") == 3,
		"남은 임시 파일을 덮어 다음 저장을 씀")
	# 임시 파일을 열 수 없어 쓰기가 실패해도 이전 저장은 남는다.
	previous = GameSave.read()
	DirAccess.make_dir_absolute(GameSave.path + ".tmp")
	_check(GameSave.write(1, 1, {}) != OK, "임시 파일을 못 쓰면 실패를 돌려줌")
	_check(GameSave.read() == previous, "쓰기 실패 뒤 이전 저장이 남음")
	DirAccess.remove_absolute(GameSave.path + ".tmp")
	GameSave.delete()


func _test_settings_survive_delete() -> void:
	_check(GameSettings.volume() == GameSettings.VOLUME_DEFAULT and not GameSettings.fullscreen(),
		"설정이 없으면 기본값: 음량 %d%%, 창" % GameSettings.VOLUME_DEFAULT)
	_check(GameSettings.write("master_volume", 30) == OK, "설정 쓰기 성공")
	GameSettings.write("fullscreen", true)
	_check(GameSettings.path != GameSave.path, "설정은 게임 저장과 다른 파일")
	GameSave.write(3, 3, _sections())
	GameSave.delete()
	_check(GameSettings.volume() == 30 and GameSettings.fullscreen(), "저장 삭제(새 게임·졸업) 뒤에도 설정이 남음")
	_check(GameSettings.read("fullscreen", "창") == "창", "타입이 다른 값은 기본값")
	# 손으로 고친 음량은 0–100의 한 단계 값으로 맞춘다.
	for case: Array in [[34, 30], [35, 40], [-5, 0], [300, 100], [0.5, GameSettings.VOLUME_DEFAULT]]:
		GameSettings.write("master_volume", case[0])
		_check(GameSettings.volume() == case[1], "음량 %s → %d: %d" % [case[0], case[1], GameSettings.volume()])
	_write_raw(GameSettings.path, "[settings\nmaster_volume=".to_utf8_buffer())
	_check(GameSettings.volume() == GameSettings.VOLUME_DEFAULT and not GameSettings.fullscreen(),
		"깨진 설정 파일은 기본값")


func _write_raw(target: String, bytes: PackedByteArray) -> void:
	var file: FileAccess = FileAccess.open(target, FileAccess.WRITE)
	file.store_buffer(bytes)
	file.close()
