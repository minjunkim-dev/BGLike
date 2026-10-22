extends SceneTree
## 실제 메인 장면에서 타이틀 버튼, 키보드·컨트롤러 조작, 출처 화면과 새 게임 진입을 검사한다 (#283).

const WINDOWS: Array[Vector2i] = [Vector2i(1280, 720), Vector2i(1920, 1080), Vector2i(1440, 900)]

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
	# 사용자의 실제 저장을 건드리지 않는다.
	GameSave.path = "user://title_test_save.bin"
	GameSave.delete()
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
	_check(shown == ["새 게임", "설정", "출처", "종료"], "저장이 없을 때 타이틀 버튼: %s" % [shown])
	_check((title.menu.get_node("Name") as Label).text == "BGLike", "임시 이름 BGLike")
	_check(not title.continue_button.visible and not title.has_save(), "저장이 없으면 이어하기를 숨김")
	_check(title.settings_button.disabled, "설정 화면이 생기기 전에는 설정 버튼을 꺼 둠")
	_check(title.quit_button.pressed.is_connected(quit), "종료 버튼은 SceneTree.quit에 연결")
	_check(title.new_game_button.has_focus(), "시작 포커스는 새 게임")
	await _check_layout(title)
	# 방향키로 출처까지 내려가 Enter로 연다.
	var path: PackedStringArray = []
	while path.size() < 4 and not title.credits_button.has_focus():
		await _tap(_action("ui_down"))
		var owner: Control = root.gui_get_focus_owner()
		path.append(owner.name if owner else "-")
	_check(title.credits_button.has_focus(), "방향키 아래로 출처 버튼: %s" % [path])
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
	_finish()


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


## 1280×720·1920×1080·1440×900 창에서 타이틀과 출처 화면이 논리 화면 안에 겹치지 않고 들어간다.
func _check_layout(title: TitleScreen) -> void:
	for size: Vector2i in WINDOWS:
		root.size = size
		await process_frame
		await process_frame
		var screen: Rect2 = Rect2(Vector2.ZERO, title.get_viewport_rect().size)
		_check(title.get_global_rect() == screen, "%s: 타이틀이 논리 화면 전체를 채움" % size)
		var areas: Array[Control] = []
		if title.menu.visible:
			for node: Node in title.menu.get_children():
				if (node as Control).visible:
					areas.append(node as Control)
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
	if current_scene:
		current_scene.queue_free()
	await process_frame
	quit(0 if failures == 0 else 1)
