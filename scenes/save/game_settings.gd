class_name GameSettings
extends RefCounted
## 설정 파일. 게임 저장과 다른 파일이라 새 게임·졸업(GameSave.delete)이 지우지 않는다 (docs/adr/0003).

const SECTION: String = "settings"

## 테스트는 다른 경로로 바꾼다.
static var path: String = "user://settings.cfg"


## 저장한 값. 파일이 없거나 읽을 수 없거나 값의 타입이 fallback과 다르면 fallback이다.
static func read(key: String, fallback: Variant) -> Variant:
	var config: ConfigFile = ConfigFile.new()
	if config.load(path) != OK:
		return fallback
	var value: Variant = config.get_value(SECTION, key, fallback)
	return value if typeof(value) == typeof(fallback) else fallback


## 다른 키는 그대로 두고 key만 바꾼다. 쓰기는 게임 저장과 같은 원자적 쓰기다.
static func write(key: String, value: Variant) -> Error:
	var config: ConfigFile = ConfigFile.new()
	config.load(path)  # 없거나 깨졌으면 빈 설정에서 시작한다.
	config.set_value(SECTION, key, value)
	return GameSave.write_atomic(path, config.encode_to_text().to_utf8_buffer())
