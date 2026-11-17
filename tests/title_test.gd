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
	"Space 누르고 있기", "Esc", "휠", "가운데 버튼 드래그", "WASD", "C:", "점프", "유리", "불리", "능력치 주사위와 AC", "건강", "반응", "기회 공격", "전사 스킬", "십자 베기", "강철 돌진", "성스러운 장막", "전투의 함성", "팔랑크스", "장난스러운 화살", "폭죽 화살", "은신", "효시", "산만함",
	"전투 시작 버튼", "정비:", "정비 버튼:", "물약 1개", "설명 보기"]
## 도움말 탭(#557): 탭 제목과 각 섹션이 담는 본문 노드. 본문 문구는 바꾸지 않고 묶기만 한다.
const HELP_SECTIONS: Array = [
	["마우스", ["Mouse1", "MouseJump", "Mouse2", "Mouse3", "Mouse4", "Mouse5", "MouseStart", "MouseTooltip", "MouseCamera"]],
	["키보드·컨트롤러", ["Keys1", "Keys2", "Keys3", "Keys4", "Keys5", "Keys6", "KeysCamera", "KeysThreat"]],
	["정비", ["MousePreparation", "MousePreparation2"]],
	["유리 / 불리", ["Advantage1", "Advantage2", "Advantage3"]],
	["능력치 주사위와 AC", ["Saves1", "Saves2"]],
	["반응", ["Reactions1", "Reactions2", "Reactions3", "Reactions4"]],
	["전사 스킬", ["Warrior1", "Warrior2"]],
	["궁수 스킬", ["Archer1", "Archer2", "Archer3"]],
]
## #209 6번: 이번 도움말에 넣지 않는 메커닉. 점프는 조작만 적고 높이 규칙은 적지 않는다.
## 물 칸의 명중굴림 불리는 #532 완료 조건대로 유리/불리 항목에 적는다. 물 칸 화상 규칙은 여전히 넣지 않는다.
const HELP_EXCLUDED: Array[String] = ["높이", "낙하", "낭떠러지", "화상"]
## 출처 화면의 UI 글꼴 고지. THIRD_PARTY_NOTICES.md의 Galmuri 행과 같은 문구다 (ui-theme).
const FONT_NOTICE: String = "UI 글꼴: Galmuri11 v2.40.4 (Copyright © 2019–2025 Lee Minseo, SIL Open Font License 1.1)"
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
	await _check_debug_entry()
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
	var expected: Array = ["새 게임", "설정", "도움말", "출처", "종료"]
	if OS.is_debug_build():
		expected.append("테스트 진입 (디버그)")
	_check(shown == expected, "저장이 없을 때 타이틀 버튼: %s" % [shown])
	_check_logo(title)
	_check_backdrop(title)
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
	await _check_screen_fit()
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
	_check_help_tabs(help)
	await _check_layout(title)
	# 오른쪽 방향키로 끝(궁수 스킬) 탭까지 간다. 끝에서 멈추고, 탭을 바꾸면 맨 위부터 읽는다.
	for step: int in range(HELP_SECTIONS.size() - 1):
		await _tap(_action("ui_right"))
	_check(help.tabs.current_tab == 7 and help.back_button.has_focus(), "오른쪽 방향키로 마지막 탭, 포커스는 뒤로 그대로")
	await _tap(_joypad(JOY_BUTTON_DPAD_RIGHT))
	_check(help.tabs.current_tab == 7, "마지막 탭에서 오른쪽은 멈춤")
	await _check_layout(title)
	# 1280×720에서 글이 화면보다 길어도 컨트롤러만으로 끝까지 읽는다.
	var bar: VScrollBar = help.scroll.get_v_scroll_bar()
	var bottom: int = int(bar.max_value - bar.page)
	_check(bottom > 0, "1280×720에서 궁수 스킬 탭은 스크롤이 필요한 길이: %d" % bottom)
	var taps: int = 0
	while help.scroll.scroll_vertical < bottom and taps < 100:
		await _tap(_joypad(JOY_BUTTON_DPAD_DOWN))
		taps += 1
	_check(help.scroll.scroll_vertical == bottom and help.back_button.has_focus(),
		"D-pad 아래로 도움말 끝까지 스크롤: %d/%d" % [help.scroll.scroll_vertical, bottom])
	await _tap(_action("ui_up"))
	_check(help.scroll.scroll_vertical < bottom, "위 방향키로 도움말 글 되돌림")
	await _tap(_action("ui_left"))
	_check(help.tabs.current_tab == 6 and help.scroll.scroll_vertical == 0, "왼쪽 방향키로 이전 탭, 맨 위부터")
	help.tabs.current_tab = 1
	_check(not help.sections[0].visible and help.sections[1].visible, "탭을 눌러도 그 섹션만 보임")
	await _tap(_action("ui_left"))
	await _tap(_joypad(JOY_BUTTON_DPAD_LEFT))
	_check(help.tabs.current_tab == 0, "첫 탭에서 왼쪽은 멈춤")
	await _tap(_action("ui_cancel"))
	_check(not help.visible and title.menu.visible and title.help_button.has_focus(),
		"Esc로 도움말을 닫고 도움말 버튼으로 포커스 복귀")
	await _tap(_action("ui_accept"))
	_check(help.visible and help.scroll.scroll_vertical == 0 and help.tabs.current_tab == 0
		and help.back_button.has_focus(), "다시 열면 첫 탭의 맨 위부터, 포커스는 뒤로")
	await _tap(_joypad(JOY_BUTTON_A))
	_check(not help.visible and title.help_button.has_focus(), "컨트롤러 A로 뒤로 버튼을 눌러 도움말을 닫음")


## 로고(#557): 임시 이름 BGLike의 도트 그림이 이름 글자를 대신한다.
func _check_logo(title: TitleScreen) -> void:
	var logo: TextureRect = title.menu.get_node_or_null("Logo") as TextureRect
	_check(logo != null and title.menu.get_node_or_null("Name") == null, "메뉴 맨 위는 Logo이고 Name 글자는 없음")
	if logo == null:
		return
	_check(logo.get_index() == 0 and logo.texture != null
		and logo.texture.resource_path == "res://scenes/ui/art/title/logo.png", "Logo는 메뉴의 첫 항목이고 logo.png")
	_check(logo.accessibility_name == "BGLike", "Logo의 접근성 이름은 임시 이름 BGLike")


## 배경(#557): 1막 1스테이지의 실제 맵과 전사·궁수 대기 도트를 어둡게 깐 정지 그림이다.
func _check_backdrop(title: TitleScreen) -> void:
	var backdrop: TitleBackdrop = title.get_child(0) as TitleBackdrop
	_check(backdrop != null and title.menu.get_index() > 0, "배경은 타이틀의 첫 자식이라 메뉴 뒤에 그려짐")
	if backdrop == null:
		return
	var stage: CombatStage = load("res://scenes/combat/stages/act1_stage1.tres") as CombatStage
	var expected: Array[Vector2i] = []
	for y: int in range(stage.map_size.y):
		for x: int in range(stage.map_size.x):
			if not stage.pits.has(Vector2i(x, y)):
				expected.append(Vector2i(x, y))
	var used: Array[Vector2i] = backdrop.map.get_used_cells()
	used.sort()
	expected.sort()
	_check(used == expected, "배경 맵의 칸은 1-1의 바닥 칸과 같음: %d/%d" % [used.size(), expected.size()])
	var sprites: Array[Sprite2D] = backdrop.unit_sprites
	_check(sprites.size() == 2 and "/units/warrior/idle/right/000.png" in sprites[0].texture.resource_path
		and "/units/archer/idle/right/000.png" in sprites[1].texture.resource_path, "전사·궁수의 오른쪽 대기 그림 한 장씩")
	for index: int in range(mini(sprites.size(), 2)):
		var surface: Vector2 = backdrop.map.to_global(backdrop.map.map_to_surface(stage.ally_cells[index]))
		_check(sprites[index].global_position.is_equal_approx(surface),
			"아군 %d은 1-1 시작 칸 %s" % [index, stage.ally_cells[index]])
	_check(backdrop.find_children("*", "AnimatedSprite2D", true, false).is_empty() and not backdrop.is_processing(),
		"배경은 애니메이션도 매 프레임 처리도 없는 정지 그림")
	_check(backdrop.modulate.r < 1.0 and backdrop.modulate.g < 1.0 and backdrop.modulate.b < 1.0, "배경은 어둡게 깔림")


## 맵 바닥 칸 표면의 가운데가 논리 화면 가운데에서 1 논리 px 안에 있다.
func _check_backdrop_centered(title: TitleScreen, size: Vector2i, screen: Rect2) -> void:
	var backdrop: TitleBackdrop = title.get_child(0) as TitleBackdrop
	if backdrop == null:
		return
	var low: Vector2 = Vector2(INF, INF)
	var high: Vector2 = Vector2(-INF, -INF)
	for cell: Vector2i in backdrop.map.get_used_cells():
		var point: Vector2 = backdrop.map.to_global(backdrop.map.map_to_surface(cell))
		low = low.min(point)
		high = high.max(point)
	var center: Vector2 = (low + high) / 2.0
	_check(center.distance_to(screen.get_center()) <= 1.0, "%s: 배경 맵의 가운데가 화면 가운데: %s / %s" % [size, center, screen.get_center()])


## 도움말 탭(#557): 제목 순서, 섹션이 담는 본문 노드, 한 번에 한 섹션만 보임.
func _check_help_tabs(help: HelpScreen) -> void:
	_check(help.tabs.tab_count == HELP_SECTIONS.size() and help.sections.size() == HELP_SECTIONS.size(),
		"도움말 탭 %d개" % HELP_SECTIONS.size())
	for index: int in range(mini(help.sections.size(), HELP_SECTIONS.size())):
		var section: Control = help.sections[index]
		_check(help.tabs.get_tab_title(index) == HELP_SECTIONS[index][0], "탭 %d 제목: %s" % [index, HELP_SECTIONS[index][0]])
		var names: Array = []
		for child: Node in section.get_children():
			if child is Label and (child as Label).visible:
				names.append(String(child.name))
		_check(names == HELP_SECTIONS[index][1], "탭 %s의 본문 노드: %s" % [HELP_SECTIONS[index][0], names])
		_check(section.visible == (index == 0), "처음에는 첫 섹션만 보임: %d" % index)


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
	await _tap(_joypad(JOY_BUTTON_DPAD_RIGHT))
	_check(help.tabs.current_tab == 1, "게임을 멈춘 동안에도 D-pad 오른쪽으로 탭 이동")
	for step: int in range(6):
		await _tap(_joypad(JOY_BUTTON_DPAD_RIGHT))
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
	_check(settings.bgm_slider.value == 100 and settings.bgm_label.text == "100%"
		and settings.sfx_slider.value == 100 and settings.sfx_label.text == "100%", "처음 배경음·효과음 음량은 100%")
	_check(is_equal_approx(AudioServer.get_bus_volume_linear(AudioServer.get_bus_index(GameSettings.BUS_BGM)), 1.0)
		and is_equal_approx(AudioServer.get_bus_volume_linear(AudioServer.get_bus_index(GameSettings.BUS_SFX)), 1.0),
		"시작할 때 배경음·효과음 버스에도 처음 음량을 적용")
	_check(not settings.fullscreen_box.button_pressed, "처음 창 모드는 창")
	_check(is_equal_approx(AudioServer.get_bus_volume_linear(0), 0.8), "시작할 때 처음 음량을 Master 버스에 적용")
	await _check_layout(title)
	_check_settings_panel(settings)
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
	_check(settings.bgm_slider.has_focus(), "D-pad 아래로 배경음 슬라이더")
	for step: int in range(3):
		await _tap(_action("ui_left"))
	var bgm_bus: int = AudioServer.get_bus_index(GameSettings.BUS_BGM)
	var sfx_bus: int = AudioServer.get_bus_index(GameSettings.BUS_SFX)
	_check(settings.bgm_slider.value == 70 and settings.bgm_label.text == "70%"
		and GameSettings.volume(GameSettings.BUS_BGM) == 70 and is_equal_approx(AudioServer.get_bus_volume_linear(bgm_bus), 0.7),
		"배경음 70%를 파일에 쓰고 BGM 버스에 적용")
	_check(GameSettings.volume() == 10 and is_equal_approx(AudioServer.get_bus_volume_linear(0), 0.1)
		and GameSettings.volume(GameSettings.BUS_SFX) == 100 and is_equal_approx(AudioServer.get_bus_volume_linear(sfx_bus), 1.0),
		"배경음을 바꿔도 마스터·효과음은 그대로")
	await _tap(_action("ui_down"))
	_check(settings.sfx_slider.has_focus(), "아래로 효과음 슬라이더")
	for step: int in range(10):
		await _tap(_action("ui_left"))
	_check(settings.sfx_slider.value == 0 and settings.sfx_label.text == "음소거"
		and AudioServer.get_bus_volume_linear(sfx_bus) == 0.0 and GameSettings.volume(GameSettings.BUS_SFX) == 0,
		"효과음 0은 음소거로 보이고 SFX 버스를 끄고 파일에 씀")
	await _tap(_action("ui_right"))
	_check(settings.sfx_slider.value == 10 and is_equal_approx(AudioServer.get_bus_volume_linear(sfx_bus), 0.1)
		and is_equal_approx(AudioServer.get_bus_volume_linear(bgm_bus), 0.7), "효과음 10%, 배경음 버스는 그대로")
	await _tap(_action("ui_down"))
	_check(settings.fullscreen_box.has_focus(), "아래로 전체 화면 칸")
	await _tap(_joypad(JOY_BUTTON_A))
	_check(settings.fullscreen_box.button_pressed and GameSettings.fullscreen(), "컨트롤러 A로 전체 화면을 켜고 파일에 씀")
	await _tap(_action("ui_down"))
	_check(settings.fill_box.has_focus() and not settings.fill_box.button_pressed, "아래로 화면 맞춤 칸, 처음은 끔")
	await _tap(_action("ui_accept"))
	_check(settings.fill_box.button_pressed and GameSettings.fill_screen()
		and root.content_scale_stretch == Window.CONTENT_SCALE_STRETCH_FRACTIONAL,
		"Enter로 꽉 채우기를 켜고 파일에 쓰고 적용")
	await _tap(_action("ui_down"))
	await _tap(_action("ui_down"))
	_check(settings.back_button.has_focus(), "아래로 뒤로 버튼, 끝에서 멈춤")
	await _tap(_joypad(JOY_BUTTON_A))
	_check(not settings.visible and title.menu.visible and title.settings_button.has_focus(),
		"뒤로 버튼으로 닫고 설정 버튼으로 포커스 복귀")
	# 다시 열면 저장한 값을 보이고, Esc로 닫는다.
	await _tap(_action("ui_accept"))
	_check(settings.visible and settings.volume_slider.value == 10 and settings.fullscreen_box.button_pressed
		and settings.fill_box.button_pressed, "다시 열면 저장한 값")
	_check(settings.bgm_slider.value == 70 and settings.sfx_slider.value == 10
		and settings.bgm_label.text == "70%" and settings.sfx_label.text == "10%", "다시 열면 저장한 배경음·효과음 음량")
	await _tap(_action("ui_cancel"))
	_check(not settings.visible and title.settings_button.has_focus(), "Esc로 설정 화면을 닫음")
	title.new_game_button.grab_focus()


## 설정 패널 프레임(#557): 내용이 MenuPanel 안에 있고, 틀을 씌워도 포커스 이웃이 그대로다.
func _check_settings_panel(settings: SettingsScreen) -> void:
	var panel: PanelContainer = settings.find_child("Panel", true, false) as PanelContainer
	_check(panel != null and panel.theme_type_variation == &"MenuPanel", "설정 내용은 MenuPanel 안에 있음")
	if panel != null:
		for name: String in ["Heading", "Grid", "Back"]:
			_check(panel.is_ancestor_of(settings.find_child(name)) and panel.get_global_rect().encloses(
				(settings.find_child(name) as Control).get_global_rect()), "패널이 %s를 감쌈" % name)
		_check(settings.get_global_rect().encloses(panel.get_global_rect()), "패널이 화면 안")
	var order: Array[Control] = [settings.volume_slider, settings.bgm_slider, settings.sfx_slider,
		settings.fullscreen_box, settings.fill_box, settings.back_button]
	for index: int in range(1, order.size()):
		_check(order[index - 1].get_node(order[index - 1].focus_neighbor_bottom) == order[index]
			and order[index].get_node(order[index].focus_neighbor_top) == order[index - 1],
			"포커스 이웃: %s ↔ %s" % [order[index - 1].name, order[index].name])


## 새 게임은 설정 파일을 지우지 않는다. 게임을 다시 켠 것처럼 타이틀을 새로 열면 저장한 설정을 적용한다.
func _check_settings_kept() -> void:
	_check(GameSettings.volume() == 10 and GameSettings.fullscreen() and GameSettings.fill_screen()
		and GameSettings.volume(GameSettings.BUS_BGM) == 70 and GameSettings.volume(GameSettings.BUS_SFX) == 10,
		"새 게임 뒤에도 설정 유지")
	AudioServer.set_bus_volume_linear(0, 1.0)
	AudioServer.set_bus_volume_linear(AudioServer.get_bus_index(GameSettings.BUS_BGM), 1.0)
	AudioServer.set_bus_volume_linear(AudioServer.get_bus_index(GameSettings.BUS_SFX), 1.0)
	GameSettings.apply_screen_fit(root, false)  # 저장한 값(켬)을 새 타이틀이 적용하는지 보려고 되돌린다.
	var title: TitleScreen = (load("res://scenes/main.tscn") as PackedScene).instantiate() as TitleScreen
	root.add_child(title)
	await process_frame
	_check(is_equal_approx(AudioServer.get_bus_volume_linear(0), 0.1), "다시 시작하면 저장한 음량 10%를 적용")
	_check(is_equal_approx(AudioServer.get_bus_volume_linear(AudioServer.get_bus_index(GameSettings.BUS_BGM)), 0.7)
		and is_equal_approx(AudioServer.get_bus_volume_linear(AudioServer.get_bus_index(GameSettings.BUS_SFX)), 0.1),
		"다시 시작하면 저장한 배경음 70%·효과음 10%를 적용")
	_check(root.content_scale_stretch == Window.CONTENT_SCALE_STRETCH_FRACTIONAL, "다시 시작하면 저장한 화면 맞춤을 적용")
	_check(title.settings_button.visible, "다시 시작한 타이틀에서도 설정을 엶")
	title.queue_free()
	# 화면이 있는 실행(화면 밖 Docker 등)에서 창이 전체 화면으로 남지 않게 되돌린다.
	GameSettings.write("fullscreen", false)
	GameSettings.apply_window_mode(false)
	GameSettings.write("fill_screen", false)
	GameSettings.apply_screen_fit(root, false)
	await process_frame


## 꽉 채우기를 켜면 1440×900 창 전체를 그리고, 끄면 정수 배율이라 남는 자리가 생긴다 (docs/adr/0002).
func _check_screen_fit() -> void:
	root.size = Vector2i(1440, 900)
	GameSettings.write("fill_screen", true)
	GameSettings.apply_screen_fit(root, true)
	await process_frame
	await process_frame
	var drawn: Vector2 = root.get_visible_rect().size * root.get_stretch_transform().x.x
	_check(drawn.is_equal_approx(Vector2(root.size)), "꽉 채우기: 1440×900 창 전체를 그림 %s" % drawn)
	GameSettings.write("fill_screen", false)
	GameSettings.apply_screen_fit(root, false)
	await process_frame
	await process_frame
	drawn = root.get_visible_rect().size * root.get_stretch_transform().x.x
	_check(not drawn.is_equal_approx(Vector2(root.size)), "정수 배율: 1440×900에서 남는 자리가 있음 %s" % drawn)
	root.size = WINDOWS[0]
	await process_frame
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


## #512 디버그 테스트 진입: 고른 막·스테이지로 바로 가고, 사용자의 저장을 읽거나 쓰지 않고, 출시 빌드에서는 열리지 않는다.
func _check_debug_entry() -> void:
	_check(TitleScreen.debug_entry == (OS.is_debug_build() and not OS.has_feature("verification_draft")),
		"테스트 진입은 디버그 빌드에서만, Draft 묶음(verification_draft)에서는 꺼짐")
	var original: bool = TitleScreen.debug_entry
	# 출시 빌드: 메뉴를 만들지 않고 직접 불러도 전투를 열지 않는다.
	TitleScreen.debug_entry = false
	var title: TitleScreen = (load("res://scenes/main.tscn") as PackedScene).instantiate() as TitleScreen
	root.add_child(title)
	await process_frame
	_check(title.debug_stage == null and title.menu.find_child("DebugStage", false, false) == null,
		"출시 빌드는 테스트 진입 메뉴를 만들지 않음")
	title.start_debug_stage(6)
	await process_frame
	_check(is_instance_valid(title) and title.is_inside_tree() and root.get_children().all(func(node: Node) -> bool:
		return node.scene_file_path != TitleScreen.GAME_SCENE), "출시 빌드는 테스트 진입 호출을 무시")
	title.queue_free()
	await process_frame
	TitleScreen.debug_entry = true
	# 사용자의 저장이 있고 자동 저장이 켜진 뒤에 들어가도 저장 파일은 그대로다.
	_check(GameSave.write(2, 1, {}) == OK, "검사용 사용자 저장 쓰기")
	var before: PackedByteArray = FileAccess.get_file_as_bytes(GameSave.path)
	GameSave.autosave = true
	title = (load("res://scenes/main.tscn") as PackedScene).instantiate() as TitleScreen
	root.add_child(title)
	await process_frame
	var picker: OptionButton = title.debug_stage
	_check(picker != null and picker.get_parent() == title.menu and picker.item_count == 10
		and picker.is_item_disabled(0) and picker.get_item_text(1) == "1-1" and picker.get_item_text(9) == "3-3",
		"디버그 빌드는 메뉴 끝에 1-1~3-3 테스트 진입")
	picker.select(7)
	picker.item_selected.emit(7)
	await process_frame
	var game: Node = current_scene
	_check(game != null and game.scene_file_path == TitleScreen.GAME_SCENE and not is_instance_valid(title),
		"테스트 진입은 타이틀을 닫고 게임 장면으로 바꿈")
	if game != null and game.has_node("Battle"):
		var battle: Node2D = game.get_node("Battle") as Node2D
		var progress: CombatActProgress = battle.get("progress") as CombatActProgress
		var hud: CombatTurnHud = battle.get_node("UI/TurnHud") as CombatTurnHud
		_check(progress.stage_index == 6 and (hud.get_node("Progress") as Label).text == "3막 · 1스테이지",
			"3-1을 고르면 3막 1스테이지 전투")
		_check(not GameSave.autosave, "테스트 진입은 자동 저장을 끔")
		battle.call("start_battle")
		for frame: int in range(5):
			await process_frame
		_check(FileAccess.get_file_as_bytes(GameSave.path) == before, "테스트 진입 전투는 사용자 저장을 바꾸지 않음")
		game.queue_free()
		await process_frame
	GameSave.delete()
	TitleScreen.debug_entry = original


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
	var music: String = (notices.get_node("Music") as Label).text
	_check(notices.get_node("MusicHeading") != null and notices.get_node("MusicHeading").get_index() == notices.get_node("Sound").get_index() + 1
		and notices.get_node("Music").get_index() == notices.get_node("MusicHeading").get_index() + 1, "배경음 절은 효과음 절 다음")
	for author: String in ["Juhani Junkala", "celestialghost8", "Kosmo The Cat"]:
		_check(author in music, "배경음 작가 표기: %s" % author)
	_check(music.count("CC0") == 4, "배경음 네 곡 모두 CC0 표기")
	_check((notices.get_node("Font") as Label).text == FONT_NOTICE, "UI 글꼴 Galmuri11 고지 문구")


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
			_check_backdrop_centered(title, size, screen)
			for node: Node in title.menu.get_children():
				if (node as Control).visible:
					areas.append(node as Control)
		elif title.help.visible:
			_check(title.help.get_global_rect() == screen, "%s: 도움말이 논리 화면 전체를 채움" % size)
			areas = [title.help.find_child("Heading") as Control, title.help.tabs, title.help.scroll, title.help.back_button]
			_check(not title.help.tabs.get_offset_buttons_visible() and title.help.tabs.get_tab_rect(
				title.help.tabs.tab_count - 1).end.x <= title.help.tabs.size.x, "%s: 도움말 탭이 모두 한 줄에 들어감" % size)
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
