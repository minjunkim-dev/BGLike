class_name GameSave
extends RefCounted
## 자동 저장 한 슬롯. 파일은 8바이트 머리(MAGIC, 형식 버전)와 Variant 바이너리 본문이다 (docs/adr/0003).
## 본문은 {act, stage, sections}다. 전투·정비 저장은 자기 상태를 sections에 이름별로 넣는다.

const MAGIC: String = "BGLS"
## 본문 모양을 호환되지 않게 바꾸면 올린다. 다른 버전의 파일은 읽지 않는다.
const FORMAT_VERSION: int = 1
const HEADER_SIZE: int = 8

## 테스트는 다른 경로로 바꾼다.
static var path: String = "user://save.bin"


static func has_save() -> bool:
	return FileAccess.file_exists(path)


## sections의 값은 Object가 아닌 Variant만 담는다. 64비트 정수, Vector2i, 키 타입이 그대로 돌아온다.
static func write(act: int, stage: int, sections: Dictionary) -> Error:
	var data: PackedByteArray = MAGIC.to_ascii_buffer()
	data.resize(HEADER_SIZE)
	data.encode_u32(4, FORMAT_VERSION)
	data.append_array(var_to_bytes({"act": act, "stage": stage, "sections": sections}))
	return write_atomic(path, data)


## 저장 본문. 파일이 없거나 읽을 수 없으면 빈 Dictionary다. 게임을 멈추지 않는다.
static func read() -> Dictionary:
	if not has_save():
		return {}
	var bytes: PackedByteArray = FileAccess.get_file_as_bytes(path)
	if bytes.size() <= HEADER_SIZE or bytes.slice(0, 4).get_string_from_ascii() != MAGIC:
		push_warning("저장 파일 형식이 아님: %s" % path)
		return {}
	var version: int = bytes.decode_u32(4)
	if version != FORMAT_VERSION:
		push_warning("저장 형식 버전 %d을 읽을 수 없음(지원 %d): %s" % [version, FORMAT_VERSION, path])
		return {}
	var save: Variant = bytes_to_var(bytes.slice(HEADER_SIZE))
	if not (save is Dictionary and save.get("act") is int and save.get("stage") is int
			and save.get("sections") is Dictionary):
		push_warning("저장 본문이 깨짐: %s" % path)
		return {}
	return save


## 새 게임·졸업에서 부른다. 설정 파일(GameSettings)은 건드리지 않는다.
static func delete() -> Error:
	for file: String in [path, path + ".tmp"]:
		if FileAccess.file_exists(file) and DirAccess.remove_absolute(file) != OK:
			push_warning("저장을 지울 수 없음: %s" % file)
			return FAILED
	return OK


## 덮어쓰기 확인 창과 이어하기에 보일 한 줄. read()의 결과를 받는다.
static func summary_text(save: Dictionary) -> String:
	if save.is_empty():
		return TranslationServer.tr("저장을 읽을 수 없음")
	return TranslationServer.tr("%d막 %d스테이지 진행 중") % [save.act, save.stage]


## 임시 파일에 다 쓴 뒤 이름을 바꾼다. 쓰는 도중 종료되면 target은 이전 내용 그대로다.
static func write_atomic(target: String, data: PackedByteArray) -> Error:
	var temp: String = target + ".tmp"
	var file: FileAccess = FileAccess.open(temp, FileAccess.WRITE)
	if file == null:
		push_warning("저장 임시 파일을 열 수 없음: %s" % temp)
		return FileAccess.get_open_error()
	var stored: bool = file.store_buffer(data)
	var error: Error = file.get_error()
	file.close()
	# 디스크가 가득 차 잘린 임시 파일이 이전 저장을 덮지 않게 한다.
	if error == OK and (not stored or FileAccess.get_size(temp) != data.size()):
		error = ERR_FILE_CANT_WRITE
	if error == OK:
		error = DirAccess.rename_absolute(temp, target)
	if error != OK:
		push_warning("저장 실패(%s): %s" % [error_string(error), target])
	return error
