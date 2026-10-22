class_name GameSettings
extends RefCounted
## 설정 파일. 게임 저장과 다른 파일이라 새 게임·졸업(GameSave.delete)이 지우지 않는다 (docs/adr/0003).

const SECTION: String = "settings"
## 마스터 음량(%)의 처음 값과 한 단계. 0은 음소거다 (#285).
const VOLUME_DEFAULT: int = 80
const VOLUME_STEP: int = 10

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


## 저장한 마스터 음량(%). 손으로 고친 파일도 0–100의 한 단계 값으로 맞춘다.
static func volume() -> int:
	return snappedi(clampi(read("master_volume", VOLUME_DEFAULT), 0, 100), VOLUME_STEP)


static func fullscreen() -> bool:
	return read("fullscreen", false)


## 저장한 값을 Master 버스와 창에 적용한다. 게임을 시작할 때(타이틀)와 설정을 바꿀 때 부른다.
static func apply() -> void:
	AudioServer.set_bus_volume_linear(0, volume() / 100.0)
	# 창 모드에서는 최대화·최소화한 창을 그대로 둔다.
	var full: bool = DisplayServer.window_get_mode() in [DisplayServer.WINDOW_MODE_FULLSCREEN,
		DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN]
	if full != fullscreen():
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if fullscreen()
			else DisplayServer.WINDOW_MODE_WINDOWED)
