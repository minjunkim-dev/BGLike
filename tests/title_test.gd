extends SceneTree
## 실제 메인 장면에서 타이틀 버튼, 키보드·컨트롤러 조작, 설정·도움말·출처 화면과 새 게임 진입을 검사한다 (#283, #285, #287).

const WINDOWS: Array[Vector2i] = [Vector2i(1280, 720), Vector2i(1920, 1080), Vector2i(1440, 900)]
## 창별 논리 화면. headless 기본 창이 아니라 이 크기의 실제 창에서 배치를 본다 (#272).
const LOGICAL: Dictionary[Vector2i, Vector2] = {Vector2i(1280, 720): Vector2(640, 360),
	Vector2i(1920, 1080): Vector2(640, 360), Vector2i(1440, 900): Vector2(640, 400)}
## ADR 0002의 레이아웃 자동 검사 창: 16:10 4배, 넓은 비율, 비정수 배율.
const EXTRA_WINDOWS: Array[Vector2i] = [Vector2i(2560, 1600), Vector2i(2560, 1080), Vector2i(1366, 768)]
## 도움말에 적을 조작과 규칙. README·전투 기획서의 이름을 쓴다.
const HELP_TOPICS: Array[String] = ["우클릭", "좌클릭", "숫자 키 1~9", "방향키", "D-pad", "Enter", "Tab",
	"Space 누르고 있기", "Esc", "점프", "유리", "불리", "내성", "반응", "기회 공격", "흘려내기"]
## #209 6번: 이번 도움말에 넣지 않는 메커닉. 점프는 조작만 적고 높이 규칙은 적지 않는다.
const HELP_EXCLUDED: Array[String] = ["높이", "낙하", "낭떠러지", "화상", "물 칸"]
## 여러 worktree가 같은 user://를 쓰므로 실행마다 폴더를 나눈다 (docs/adr/0003).
var directory: String = "user://tests/title/%d" % OS.get_process_id()

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
	await _check_continue_with_save()
	var main_scene: String = ProjectSettings.get_setting("application/run/main_scene")
	var title: TitleScreen = (load(main_scene) as PackedScene).instantiate() as TitleScreen
	_check(title != null, "메인 장면의 시작점은 타이틀 화면")
	if title == null:
		_finish()
		return
	root.size = WINDOWS[0]
	root.add_child(title)
	current_scene = title
	await process_frame
	var shown: Array = title.menu.get_children().filter(func(node: Node) -> bool:
		return node is Button and (node as Button).visible).map(func(button: Button) -> String:
			return button.text)
	_check(shown == ["새 게임", "설정", "도움말", "출처", "종료"], "저장이 없을 때 타이틀 버튼: %s" % [shown])
	_check((title.menu.get_node("Name") as Label).text == "BGLike", "임시 이름 BGLike")
	_check(not title.continue_button.visible and not title.has_save(), "저장이 없으면 이어하기를 숨김")
	_check(not title.settings_button.disabled, "설정 버튼을 누를 수 있음")
	_check(title.quit_button.pressed.is_connected(quit), "종료 버튼은 SceneTree.quit에 연결")
	_check(title.new_game_button.has_focus(), "시작 포커스는 새 게임")
	_check(not title.help.visible, "처음 실행할 때 도움말을 저절로 열지 않음")
	await _check_layout(title)
	await _check_settings(title)
	# 방향키로 도움말까지 내려가 Enter로 연다.
	var path: PackedStringArray = []
	while path.size() < 4 and not title.help_button.has_focus():
		await _tap(_action("ui_down"))
		var owner: Control = root.gui_get_focus_owner()
		path.append(owner.name if owner else "-")
	_check(title.help_button.has_focus(), "방향키 아래로 도움말 버튼: %s" % [path])
	await _check_help(title)
	await _tap(_action("ui_down"))
	_check(title.credits_button.has_focus(), "도움말 다음은 출처 버튼")
	await _tap(_action("ui_accept"))
	_check(title.credits.visible and not title.menu.visible and title.back_button.has_focus(),
		"Enter로 출처 화면을 열고 뒤로 버튼에 포커스")
	_check_notices(title)
	await _check_layout(title)
	# 컨트롤러 D-pad로 긴 고지문을 스크롤한다.
	await _tap(_joypad(JOY_BUTTON_DPAD_DOWN))
	var scrolled: int = title.credits_scroll.scroll_vertical
	_check(scrolled > 0 and title.back_button.has_focus(), "D-pad 아래로 출처 글 스크롤: %d" % scrolled)
	await _tap(_joypad(JOY_BUTTON_DPAD_UP))
	_check(title.credits_scroll.scroll_vertical < scrolled, "D-pad 위로 출처 글 되돌림")
	await _tap(_action("ui_cancel"))
	_check(not title.credits.visible and title.menu.visible and title.credits_button.has_focus(),
		"Esc로 출처 화면을 닫고 출처 버튼으로 포커스 복귀")
	await _tap(_action("ui_accept"))
	_check(title.credits.visible and title.back_button.has_focus(), "Enter로 출처 화면을 다시 엶")
	await _tap(_joypad(JOY_BUTTON_A))
	_check(not title.credits.visible and title.credits_button.has_focus(), "컨트롤러 A로 뒤로 버튼을 눌러 닫음")
	await _check_help_entry()
	# 새 게임은 지금처럼 1막 1스테이지 전투로 간다.
	title.new_game_button.grab_focus()
	await _tap(_action("ui_accept"))
	await process_frame
	var game: Node = current_scene
	_check(game != null and game.scene_file_path == TitleScreen.GAME_SCENE and not is_instance_valid(title),
		"새 게임은 타이틀을 닫고 게임 장면으로 바꿈")
	if game != null and game.has_node("Battle"):
		var battle: Node2D = game.get_node("Battle") as Node2D
		battle.set_process(false)
		var progress: CombatActProgress = battle.get("progress") as CombatActProgress
		_check(progress.stage_index == 0 and progress.act_number() == 1, "새 게임은 1막 1스테이지")
		var hud: CombatTurnHud = battle.get_node("UI/TurnHud") as CombatTurnHud
		_check((hud.get_node("Progress") as Label).text == "1막 · 1스테이지", "1-1 전투 화면")
	await _check_settings_kept()
	_finish()


## 도움말: Enter로 열고, 내용을 확인하고, D-pad로 끝까지 스크롤하고, Esc와 컨트롤러 A로 닫는다.
func _check_help(title: TitleScreen) -> void:
	var help: HelpScreen = title.help
	await _tap(_action("ui_accept"))
	_check(help.visible and not title.menu.visible and help.back_button.has_focus(),
		"Enter로 도움말을 열고 뒤로 버튼에 포커스")
	var text: String = "\n".join(help.scroll.find_children("*", "Label", true, false).map(
		func(label: Label) -> String: return label.text))
	for topic: String in HELP_TOPICS:
		_check(topic in text, "도움말에 %s" % topic)
	for excluded: String in HELP_EXCLUDED:
		_check(excluded not in text, "도움말에 새 메커닉 %s를 넣지 않음" % excluded)
	await _check_layout(title)
	# 1280×720에서 글이 화면보다 길어도 컨트롤러만으로 끝까지 읽는다.
	var bar: VScrollBar = help.scroll.get_v_scroll_bar()
	var bottom: int = int(bar.max_value - bar.page)
	_check(bottom > 0, "1280×720에서 도움말은 스크롤이 필요한 길이: %d" % bottom)
	var taps: int = 0
	while help.scroll.scroll_vertical < bottom and taps < 100:
		await _tap(_joypad(JOY_BUTTON_DPAD_DOWN))
		taps += 1
	_check(help.scroll.scroll_vertical == bottom and help.back_button.has_focus(),
		"D-pad 아래로 도움말 끝까지 스크롤: %d/%d" % [help.scroll.scroll_vertical, bottom])
	await _tap(_action("ui_up"))
	_check(help.scroll.scroll_vertical < bottom, "위 방향키로 도움말 글 되돌림")
	await _tap(_action("ui_cancel"))
	_check(not help.visible and title.menu.visible and title.help_button.has_focus(),
		"Esc로 도움말을 닫고 도움말 버튼으로 포커스 복귀")
	await _tap(_action("ui_accept"))
	_check(help.visible and help.scroll.scroll_vertical == 0, "다시 열면 도움말 맨 위부터")
	await _tap(_joypad(JOY_BUTTON_A))
	_check(not help.visible and title.help_button.has_focus(), "컨트롤러 A로 뒤로 버튼을 눌러 도움말을 닫음")


## 일시정지 메뉴(#286)가 쓸 진입점: 도움말 장면만 넣고 `open()`을 부르면 게임을 멈춘 동안에도 읽고 닫는다.
func _check_help_entry() -> void:
	var help: HelpScreen = (load("res://scenes/help.tscn") as PackedScene).instantiate() as HelpScreen
	root.add_child(help)
	await process_frame
	var closed: Array[bool] = []
	help.closed.connect(func() -> void: closed.append(true))
	paused = true
	help.open()
	await process_frame
	_check(help.visible and help.back_button.has_focus() and help.theme != null, "도움말 장면만으로 열림, 공용 테마")
	await _tap(_joypad(JOY_BUTTON_DPAD_DOWN))
	_check(help.scroll.scroll_vertical > 0, "게임을 멈춘 동안에도 D-pad로 도움말 스크롤")
	await _tap(_action("ui_cancel"))
	_check(not help.visible and closed == [true], "게임을 멈춘 동안에도 Esc로 닫고 closed 신호")
	paused = false
	help.queue_free()
	await process_frame


## 설정 화면을 키보드와 컨트롤러로 열고 바꾸고 닫는다. 바꾼 값은 바로 설정 파일에 쓰고 적용한다.
func _check_settings(title: TitleScreen) -> void:
	var settings: SettingsScreen = title.settings
	await _tap(_action("ui_down"))
	_check(title.settings_button.has_focus(), "새 게임 아래가 설정 버튼")
	await _tap(_action("ui_accept"))
	_check(settings.visible and not title.menu.visible and settings.volume_slider.has_focus(),
		"Enter로 설정 화면을 열고 음량 슬라이더에 포커스")
	_check(settings.volume_slider.value == 80 and settings.volume_label.text == "80%", "처음 음량은 80%")
	_check(not settings.fullscreen_box.button_pressed, "처음 창 모드는 창")
	_check(is_equal_approx(AudioServer.get_bus_volume_linear(0), 0.8), "시작할 때 처음 음량을 Master 버스에 적용")
	await _check_layout(title)
	# 왼쪽 방향키 한 번에 10%씩 줄어 0에서 멈춘다. 0이 음소거다.
	for step: int in range(9):
		await _tap(_action("ui_left"))
	_check(settings.volume_slider.value == 0 and settings.volume_slider.has_focus(), "왼쪽 방향키로 0까지, 0에서 멈춤")
	_check(settings.volume_label.text == "음소거" and AudioServer.get_bus_volume_linear(0) == 0.0
		and GameSettings.volume() == 0, "0은 음소거로 보이고 Master 버스를 끄고 파일에 씀")
	await _tap(_joypad(JOY_BUTTON_DPAD_RIGHT))
	_check(settings.volume_slider.value == 10 and GameSettings.volume() == 10
		and is_equal_approx(AudioServer.get_bus_volume_linear(0), 0.1), "D-pad 오른쪽으로 10%")
	# 설정 파일을 쓸 수 없어도 화면에 보인 값과 Master 버스는 같다.
	var saved_path: String = GameSettings.path
	GameSettings.path = directory + "/missing/settings.cfg"
	await _tap(_action("ui_right"))
	_check(settings.volume_label.text == "20%" and is_equal_approx(AudioServer.get_bus_volume_linear(0), 0.2),
		"쓰기 실패에도 보인 20%를 적용")
	GameSettings.path = saved_path
	await _tap(_action("ui_left"))
	await _tap(_action("ui_up"))
	_check(settings.volume_slider.has_focus(), "음량 위로는 포커스가 나가지 않음")
	await _tap(_joypad(JOY_BUTTON_DPAD_DOWN))
	_check(settings.fullscreen_box.has_focus(), "D-pad 아래로 전체 화면 칸")
	await _tap(_joypad(JOY_BUTTON_A))
	_check(settings.fullscreen_box.button_pressed and GameSettings.fullscreen(), "컨트롤러 A로 전체 화면을 켜고 파일에 씀")
	await _tap(_action("ui_down"))
	await _tap(_action("ui_down"))
	_check(settings.back_button.has_focus(), "아래로 뒤로 버튼, 끝에서 멈춤")
	await _tap(_joypad(JOY_BUTTON_A))
	_check(not settings.visible and title.menu.visible and title.settings_button.has_focus(),
		"뒤로 버튼으로 닫고 설정 버튼으로 포커스 복귀")
	# 다시 열면 저장한 값을 보이고, Esc로 닫는다.
	await _tap(_action("ui_accept"))
	_check(settings.visible and settings.volume_slider.value == 10 and settings.fullscreen_box.button_pressed,
		"다시 열면 저장한 값")
	await _tap(_action("ui_cancel"))
	_check(not settings.visible and title.settings_button.has_focus(), "Esc로 설정 화면을 닫음")
	title.new_game_button.grab_focus()


## 새 게임은 설정 파일을 지우지 않는다. 게임을 다시 켠 것처럼 타이틀을 새로 열면 저장한 설정을 적용한다.
func _check_settings_kept() -> void:
	_check(GameSettings.volume() == 10 and GameSettings.fullscreen(), "새 게임 뒤에도 설정 유지")
	AudioServer.set_bus_volume_linear(0, 1.0)
	var title: TitleScreen = (load("res://scenes/main.tscn") as PackedScene).instantiate() as TitleScreen
	root.add_child(title)
	await process_frame
	_check(is_equal_approx(AudioServer.get_bus_volume_linear(0), 0.1), "다시 시작하면 저장한 음량 10%를 적용")
	_check(title.settings_button.visible, "다시 시작한 타이틀에서도 설정을 엶")
	title.queue_free()
	# 화면이 있는 실행(화면 밖 Docker 등)에서 창이 전체 화면으로 남지 않게 되돌린다.
	GameSettings.write("fullscreen", false)
	GameSettings.apply_window_mode(false)
	await process_frame


## 저장이 있으면 `새 게임` 다음에 `이어하기`가 보인다.
func _check_continue_with_save() -> void:
	_check(GameSave.write(1, 1, {}) == OK, "검사용 저장 쓰기")
	var title: TitleScreen = (load("res://scenes/main.tscn") as PackedScene).instantiate() as TitleScreen
	root.add_child(title)
	await process_frame
	_check(title.continue_button.visible and title.continue_button.get_index() == title.new_game_button.get_index() + 1,
		"저장이 있으면 새 게임 다음에 이어하기를 보임")
	title.queue_free()
	await process_frame
	GameSave.delete()


## 출처 화면은 SRD 5.1 표기를 THIRD_PARTY_NOTICES.md의 원문 그대로 보이고 엔진 라이선스 전문을 싣는다.
func _check_notices(title: TitleScreen) -> void:
	var srd: String = ""
	for line: String in FileAccess.get_file_as_string("res://THIRD_PARTY_NOTICES.md").split("\n"):
		if line.begins_with("> This work includes material taken from the System Reference Document 5.1"):
			srd = line.trim_prefix("> ")
	var notices: Control = title.credits_scroll.get_child(0) as Control
	_check(srd != "" and (notices.get_node("SrdNotice") as Label).text == srd, "SRD 5.1 CC-BY-4.0 표기 원문")
	var version: Dictionary = Engine.get_version_info()
	_check((notices.get_node("EngineLicense") as Label).text == Engine.get_license_text()
		and "Godot Engine %d.%d.%d" % [version.major, version.minor, version.patch]
		in (notices.get_node("Engine") as Label).text, "실행 중인 Godot Engine 버전과 MIT 라이선스 전문")
	for name: String in ["SrdNotice", "EngineLicense"]:
		_check((notices.get_node(name) as Node).auto_translate_mode == Node.AUTO_TRANSLATE_MODE_DISABLED,
			"법적 고지문 %s은 번역하지 않음" % name)
	_check("Kenney" in (notices.get_node("Sound") as Label).text, "효과음 원본 표기")


## ADR 0002의 여섯 창에서 타이틀, 설정, 도움말, 출처 화면이 논리 화면 안에 겹치지 않고 들어간다.
func _check_layout(title: TitleScreen) -> void:
	for size: Vector2i in WINDOWS + EXTRA_WINDOWS:
		root.size = size
		await process_frame
		await process_frame
		var screen: Rect2 = Rect2(Vector2.ZERO, title.get_viewport_rect().size)
		_check(root.size == size and screen.size == LOGICAL.get(size, screen.size),
			"%s: 창과 논리 화면 %s" % [size, screen.size])
		_check(title.get_global_rect() == screen, "%s: 타이틀이 논리 화면 전체를 채움" % size)
		var areas: Array[Control] = []
		if title.settings.visible:
			_check(title.settings.get_global_rect() == screen, "%s: 설정 화면이 논리 화면 전체를 채움" % size)
			var grid: Node = title.settings.find_child("Grid")
			areas = [title.settings.find_child("Heading") as Control, title.settings.back_button]
			areas.append_array(grid.get_children())
		elif title.menu.visible:
			for node: Node in title.menu.get_children():
				if (node as Control).visible:
					areas.append(node as Control)
		elif title.help.visible:
			_check(title.help.get_global_rect() == screen, "%s: 도움말이 논리 화면 전체를 채움" % size)
			areas = [title.help.find_child("Heading") as Control, title.help.scroll, title.help.back_button]
			var topics: Control = title.help.scroll.get_child(0) as Control
			_check(topics.size.x <= title.help.scroll.size.x, "%s: 도움말 글이 가로로 넘치지 않음" % size)
		else:
			_check(title.credits.get_global_rect() == screen, "%s: 출처 화면이 논리 화면 전체를 채움" % size)
			areas = [title.credits.find_child("Heading") as Control, title.credits_scroll, title.back_button]
			var notices: Control = title.credits_scroll.get_child(0) as Control
			_check(notices.size.x <= title.credits_scroll.size.x, "%s: 출처 글이 가로로 넘치지 않음" % size)
		for index: int in range(areas.size()):
			var rect: Rect2 = areas[index].get_global_rect()
			_check(screen.encloses(rect), "%s: 화면 안: %s" % [size, areas[index].name])
			for other: Control in areas.slice(index + 1):
				_check(not rect.intersects(other.get_global_rect()),
					"%s: 겹치지 않음: %s, %s" % [size, areas[index].name, other.name])
	root.size = WINDOWS[0]
	await process_frame
	await process_frame


func _action(action: String) -> InputEventAction:
	var event: InputEventAction = InputEventAction.new()
	event.action = action
	return event


func _joypad(button: JoyButton) -> InputEventJoypadButton:
	var event: InputEventJoypadButton = InputEventJoypadButton.new()
	event.button_index = button
	return event


## 누름과 뗌을 한 프레임씩 보낸다.
func _tap(event: InputEvent) -> void:
	event.set("pressed", true)
	Input.parse_input_event(event)
	await process_frame
	event.set("pressed", false)
	Input.parse_input_event(event)
	await process_frame


func _finish() -> void:
	print("Title: %d checks, %d failures;" % [checks, failures])
	GameSave.autosave = false
	if current_scene:
		current_scene.queue_free()
	await process_frame
	GameSave.delete()
	for file: String in [GameSettings.path, GameSettings.path + ".tmp"]:
		DirAccess.remove_absolute(file)
	DirAccess.remove_absolute(directory)
	quit(0 if failures == 0 else 1)
