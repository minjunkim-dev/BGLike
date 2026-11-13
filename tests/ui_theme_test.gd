extends SceneTree
## 공용 테마(scenes/ui_theme.tres)의 글꼴·크기·버튼 상태 색(seam B)과 글꼴 고지 파일(seam D)을 검사한다 (ui-theme, docs/PIXEL_ART.md UI 절).

const THEME_PATH: String = "res://scenes/ui_theme.tres"
const FONT_PATH: String = "res://scenes/ui/fonts/Galmuri11.ttf"
const LICENSE_PATH: String = "res://scenes/ui/fonts/LICENSE-Galmuri.txt"
const NOTICES_PATH: String = "res://THIRD_PARTY_NOTICES.md"
const FRAME_PATHS: Array[String] = ["res://scenes/ui/art/frames/panel.png",
	"res://scenes/ui/art/frames/accent_panel.png", "res://scenes/ui/art/frames/button.png"]

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
	var theme: Theme = load(THEME_PATH) as Theme
	_check(theme != null, "공용 테마를 불러옴")
	if theme == null:
		_finish()
		return
	_check_font(theme)
	_check_button_states(theme)
	_check_panel(theme)
	_check_notices()
	_finish()


## seam B: 기본 글꼴은 Galmuri11이고 기본 크기는 11이다.
func _check_font(theme: Theme) -> void:
	_check(theme.default_font != null and theme.default_font.resource_path == FONT_PATH,
		"기본 글꼴은 Galmuri11")
	_check(theme.default_font_size == 11, "기본 글자 크기 11: %d" % theme.default_font_size)


## seam B: 버튼 네 상태는 StyleBoxTexture이고 modulate 색이 설계 표 값과 같다.
func _check_button_states(theme: Theme) -> void:
	var expected: Dictionary = {
		"normal": "223940",
		"hover": "365d61",
		"pressed": "18292d",
		"disabled": "464254",
	}
	for state: String in expected:
		var style: StyleBox = theme.get_stylebox(state, "Button")
		_check(style is StyleBoxTexture, "Button %s는 StyleBoxTexture" % state)
		if style is StyleBoxTexture:
			_check((style as StyleBoxTexture).modulate_color.is_equal_approx(Color.html(expected[state])),
				"Button %s 색은 #%s" % [state, expected[state]])
	_check(theme.get_stylebox("focus", "Button") is StyleBoxFlat, "포커스는 StyleBoxFlat 테두리")
	_check(theme.get_color("font_color", "Button").is_equal_approx(Color.html("f5ebdb")),
		"버튼 본문 글자 #F5EBDB")
	_check(theme.get_color("font_disabled_color", "Button").is_equal_approx(Color.html("85736c")),
		"버튼 비활성 글자 #85736C")
	_check(theme.get_color("font_color", "Label").is_equal_approx(Color.html("f5ebdb")),
		"라벨 본문 글자 #F5EBDB")


## seam B: 패널 면은 StyleBoxTexture이고 색은 #21223D이다.
func _check_panel(theme: Theme) -> void:
	var panel: StyleBox = theme.get_stylebox("panel", "AcceptDialog")
	_check(panel is StyleBoxTexture, "대화상자 패널은 StyleBoxTexture")
	if panel is StyleBoxTexture:
		_check((panel as StyleBoxTexture).modulate_color.is_equal_approx(Color.html("21223d")),
			"패널 면 색은 #21223D")
		_check((panel as StyleBoxTexture).texture_margin_left == 4.0, "9-slice 여백 4px")
	for path: String in FRAME_PATHS:
		_check(ResourceLoader.exists(path), "프레임 파일 있음: %s" % path)


## seam D: 글꼴 파일과 라이선스가 있고, THIRD_PARTY_NOTICES.md에 Galmuri 행과 OFL-1.1 표기가 있다.
func _check_notices() -> void:
	_check(FileAccess.file_exists(FONT_PATH), "Galmuri11.ttf가 있음")
	_check(FileAccess.file_exists(LICENSE_PATH), "LICENSE-Galmuri.txt가 있음")
	var notices: String = FileAccess.get_file_as_string(NOTICES_PATH)
	_check("`scenes/ui/fonts/Galmuri11.ttf`" in notices, "고지 문서에 Galmuri11 행")
	_check("SIL Open Font License 1.1" in notices, "고지 문서에 OFL 1.1 표기")
	_check("`scenes/ui/art/frames/panel.png`" in notices and "`button.png`" in notices,
		"고지 문서에 자체 제작 프레임 행")


func _finish() -> void:
	print("UI theme: %d checks, %d failures;" % [checks, failures])
	quit(0 if failures == 0 else 1)
