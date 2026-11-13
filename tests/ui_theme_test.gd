extends SceneTree
## 공용 테마(scenes/ui_theme.tres)의 글꼴·크기·버튼 상태 색(seam B), 화면 글자의 잘림·겹침(seam C),
## 글꼴 고지 파일(seam D)을 검사한다 (ui-theme, docs/PIXEL_ART.md UI 절).

const THEME_PATH: String = "res://scenes/ui_theme.tres"
const FONT_PATH: String = "res://scenes/ui/fonts/Galmuri11.ttf"
const LICENSE_PATH: String = "res://scenes/ui/fonts/LICENSE-Galmuri.txt"
const NOTICES_PATH: String = "res://THIRD_PARTY_NOTICES.md"
const FRAME_PATHS: Array[String] = ["res://scenes/ui/art/frames/panel.png",
	"res://scenes/ui/art/frames/accent_panel.png", "res://scenes/ui/art/frames/button.png"]
## Issue #518이 전후 비교로 적은 두 창. 논리 화면은 둘 다 640×360이다.
const TEXT_WINDOWS: Array[Vector2i] = [Vector2i(1280, 720), Vector2i(1920, 1080)]
const LOGICAL_SCREEN: Vector2 = Vector2(640, 360)
## 여러 worktree가 같은 user://를 쓰므로 실행마다 폴더를 나눈다 (docs/adr/0003).
var directory: String = "user://tests/ui_theme/%d" % OS.get_process_id()

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
	await _check_text_layout()
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


## seam C: 테마를 쓰는 메뉴·설정·도움말·출처, 전투 HUD, 정비에서 글자가 잘리거나 서로 겹치지 않는다.
func _check_text_layout() -> void:
	DirAccess.make_dir_recursive_absolute(directory)
	GameSave.path = directory + "/save.bin"
	GameSettings.path = directory + "/settings.cfg"
	GameSave.autosave = false
	root.size = TEXT_WINDOWS[0]
	var title: TitleScreen = (load("res://scenes/main.tscn") as PackedScene).instantiate() as TitleScreen
	var game: Node = (load(TitleScreen.GAME_SCENE) as PackedScene).instantiate()
	game.visible = false
	root.add_child(title)
	root.add_child(game)
	current_scene = title
	var battle: Node = game.get_node("Battle")
	battle.set_process(false)
	await process_frame
	await process_frame
	var hud: Control = battle.get_node("UI/TurnHud")
	var preparation: CombatPreparation = battle.get("preparation")
	var pause_menu: PauseMenu = battle.get("pause_menu")
	for size: Vector2i in TEXT_WINDOWS:
		root.size = size
		await process_frame
		await process_frame
		var screen: Rect2 = title.get_viewport_rect()
		_check(screen.size == LOGICAL_SCREEN, "%s: 논리 화면 %s" % [size, screen.size])
		_audit_text(title.menu, size, "메뉴")
		title.show_settings(true)
		await process_frame
		await process_frame
		_audit_text(title.settings, size, "설정")
		title.settings.close()
		title.show_help(true)
		await process_frame
		await process_frame
		_audit_text(title.help, size, "도움말")
		title.help.close()
		title.show_credits(true)
		await process_frame
		await process_frame
		_audit_text(title.credits, size, "출처")
		title.show_credits(false)
	_force_ally_turn(battle)
	for size: Vector2i in TEXT_WINDOWS:
		root.size = size
		title.visible = false
		game.visible = true
		preparation.hide()
		pause_menu.hide()
		await process_frame
		await process_frame
		_audit_text(hud, size, "전투 준비 HUD")
	battle.call("start_battle")
	await process_frame
	await process_frame
	for size: Vector2i in TEXT_WINDOWS:
		root.size = size
		await process_frame
		await process_frame
		_audit_text(hud, size, "전투 HUD")
	var loot: CombatLoot = battle.get("loot")
	var allies: Array[CombatUnit] = []
	allies.assign(battle.get("party"))
	var progress: CombatActProgress = battle.get("progress")
	var drops: Array[Dictionary] = []
	drops.assign(progress.rewards)
	preparation.open_rewards(loot, allies, drops, false, false, false)
	for size: Vector2i in TEXT_WINDOWS:
		root.size = size
		await process_frame
		await process_frame
		_audit_text(preparation, size, "정비")
	preparation.hide()
	for size: Vector2i in TEXT_WINDOWS:
		root.size = size
		pause_menu.open(true)
		await process_frame
		await process_frame
		_audit_text(pause_menu.menu, size, "일시정지 메뉴")
		pause_menu.close()
	title.queue_free()
	game.queue_free()
	await process_frame
	GameSave.autosave = false
	GameSave.delete()
	for file: String in [GameSettings.path, GameSettings.path + ".tmp"]:
		DirAccess.remove_absolute(file)
	DirAccess.remove_absolute(directory)


## 전투 HUD 문구가 시드에 따라 바뀌지 않게 아군 턴으로 맞춘다.
func _force_ally_turn(battle: Node) -> void:
	var turns: CombatTurns = battle.get("turns")
	var units: Array[CombatUnit] = []
	units.assign(battle.get("units"))
	var dice: CombatDice = CombatDice.new()
	var guard: int = 0
	# RandomNumberGenerator는 생성 시 시각으로 시드된다. 검사 수가 실행마다 흔들리지 않게 1부터 고정한다.
	while (turns.current_unit == null or not turns.current_unit.is_ally) and guard < 30:
		guard += 1
		dice.seed = guard
		turns.start(units, dice)
	_check(turns.current_unit != null and turns.current_unit.is_ally, "전투 HUD 검사는 아군 턴")


func _audit_text(screen: Control, size: Vector2i, screen_name: String) -> void:
	_hide_tooltips(screen)
	var texts: Array[Control] = []
	_collect_text(screen, texts)
	_check(texts.size() >= 2, "%s %s: 글자 컨트롤 %d개를 검사" % [size, screen_name, texts.size()])
	var drawn: Array[Rect2] = []
	for control: Control in texts:
		var rect: Rect2 = _drawn_text_rect(control)
		var reason: String = _clip_reason(control, rect)
		_check(reason.is_empty(), "%s %s: 글자가 잘리지 않음: %s (%s) %s" % [
			size, screen_name, _node_path(screen, control), _snippet(control), reason])
		drawn.append(rect)
	for index: int in range(texts.size()):
		for other: int in range(index + 1, texts.size()):
			if _nested(texts[index], texts[other]):
				continue
			var left: Rect2 = _overlap_rect(texts[index], drawn[index], texts[other])
			var right: Rect2 = _overlap_rect(texts[other], drawn[other], texts[index])
			if left.size.x <= 1.0 or left.size.y <= 1.0 or right.size.x <= 1.0 or right.size.y <= 1.0:
				continue
			_check(not left.grow(-0.5).intersects(right.grow(-0.5)),
				"%s %s: 글자가 겹치지 않음: %s (%s) / %s (%s)" % [
					size, screen_name, _node_path(screen, texts[index]), _snippet(texts[index]),
					_node_path(screen, texts[other]), _snippet(texts[other])])


func _hide_tooltips(node: Node) -> void:
	if node is HoverTooltip:
		(node as HoverTooltip).hide()
	for child: Node in node.get_children():
		_hide_tooltips(child)


func _collect_text(node: Node, into: Array[Control]) -> void:
	if node is CanvasItem and not (node as CanvasItem).visible:
		return
	# 아직 열지 않은 Window(정비 확인 창 등)의 글자는 화면에 없다.
	if node is Window and node != root:
		return
	if (node is Label or node is RichTextLabel or node is BaseButton) and not _control_text(node as Control).is_empty():
		into.append(node as Control)
	for child: Node in node.get_children():
		_collect_text(child, into)


func _control_text(control: Control) -> String:
	var text: String = ""
	if control is RichTextLabel:
		text = (control as RichTextLabel).get_parsed_text()
	elif control is Label:
		text = (control as Label).text
	elif control is BaseButton:
		text = (control as BaseButton).text
	return text.strip_edges()


func _snippet(control: Control) -> String:
	var text: String = _control_text(control).replace("\n", " ")
	if text.length() > 24:
		text = text.left(24) + "…"
	return text


func _node_path(screen: Node, control: Node) -> String:
	return str(screen.get_path_to(control))


func _nested(a: Node, b: Node) -> bool:
	return a.is_ancestor_of(b) or b.is_ancestor_of(a)


## 스크롤 밖 글자는 접힌 내용이다. 스크롤 경계 너머의 컨트롤과 비교할 때만 보이는 부분으로 자른다.
func _overlap_rect(control: Control, drawn: Rect2, other: Control) -> Rect2:
	var scroll: ScrollContainer = _scroll_of(control)
	if scroll != null and scroll == _scroll_of(other):
		return drawn
	return _clip_to_scroll(control, drawn)


func _clip_to_scroll(control: Control, drawn: Rect2) -> Rect2:
	var rect: Rect2 = drawn
	var node: Node = control.get_parent()
	while node != null:
		if node is ScrollContainer:
			rect = rect.intersection((node as Control).get_global_rect())
		node = node.get_parent()
	return rect


func _scroll_of(control: Node) -> ScrollContainer:
	var node: Node = control.get_parent()
	while node != null:
		if node is ScrollContainer:
			return node as ScrollContainer
		node = node.get_parent()
	return null


## 실제로 칠해지는 글자 사각형. 칸이 글자보다 넓으면 여백은 겹침이 아니다.
## clip_text가 꺼진 한 줄 라벨은 칸 너비 밖으로 그린다.
func _drawn_text_rect(control: Control) -> Rect2:
	var rect: Rect2 = control.get_global_rect()
	if not control is Label:
		return rect
	var label: Label = control as Label
	var font: Font = label.get_theme_font("font")
	var font_size: int = label.get_theme_font_size("font_size")
	if font == null or label.text.is_empty() or rect.size.x <= 1.0 or rect.size.y <= 1.0:
		return rect
	var width: float = 0.0
	var line_count: int = maxi(label.get_line_count(), 1)
	if label.autowrap_mode == TextServer.AUTOWRAP_OFF:
		for line: String in label.text.split("\n"):
			width = maxf(width, font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x)
	else:
		width = minf(font.get_multiline_string_size(label.text, label.horizontal_alignment,
			rect.size.x, font_size).x, rect.size.x)
	var spacing: int = label.get_theme_constant("line_spacing")
	var height: float = font.get_height(font_size) * line_count + spacing * maxi(line_count - 1, 0)
	var glyph: Rect2 = Rect2(rect.position, Vector2(width, height))
	if label.horizontal_alignment == HORIZONTAL_ALIGNMENT_CENTER:
		glyph.position.x += (rect.size.x - width) * 0.5
	elif label.horizontal_alignment == HORIZONTAL_ALIGNMENT_RIGHT:
		glyph.position.x += rect.size.x - width
	if label.vertical_alignment == VERTICAL_ALIGNMENT_CENTER:
		glyph.position.y += (rect.size.y - height) * 0.5
	elif label.vertical_alignment == VERTICAL_ALIGNMENT_BOTTOM:
		glyph.position.y += rect.size.y - height
	var clips: bool = label.clip_text or label.text_overrun_behavior != TextServer.OVERRUN_NO_TRIMMING \
		or label.autowrap_mode != TextServer.AUTOWRAP_OFF
	if clips:
		glyph = glyph.intersection(rect)
	return glyph


## 비어 있으면 잘리지 않는다. 이유는 실패 메시지에 붙인다.
func _clip_reason(control: Control, drawn: Rect2) -> String:
	var screen: Rect2 = control.get_viewport_rect()
	var visible: Rect2 = _clip_to_scroll(control, drawn)
	if _scroll_of(control) == null and not screen.grow(1.0).encloses(drawn):
		return "화면 밖 %s" % drawn
	if _scroll_of(control) != null and visible.size.x <= 0.0 and visible.size.y <= 0.0 \
			and not screen.grow(1.0).encloses(drawn):
		return ""
	if control is Label:
		var label: Label = control as Label
		if label.get_line_count() > 0 and label.get_visible_line_count() < label.get_line_count():
			return "보이는 줄 %d / 전체 %d" % [label.get_visible_line_count(), label.get_line_count()]
		if label.autowrap_mode == TextServer.AUTOWRAP_OFF and (label.clip_text \
				or label.text_overrun_behavior != TextServer.OVERRUN_NO_TRIMMING):
			var font: Font = label.get_theme_font("font")
			var font_size: int = label.get_theme_font_size("font_size")
			if font != null and font.get_string_size(label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x \
					> label.size.x + 1.0:
				return "가로로 잘림"
		if label.size.y <= 1.0 and label.get_line_count() > 0:
			return "높이가 0이라 글자가 안 보임"
	elif control is RichTextLabel:
		var rich: RichTextLabel = control as RichTextLabel
		if not rich.scroll_active and rich.get_content_height() > rich.size.y + 1.0:
			return "리치 텍스트 높이 %.0f > %.0f" % [rich.get_content_height(), rich.size.y]
	elif control is BaseButton:
		var minimum: Vector2 = control.get_combined_minimum_size()
		if control.size.x + 1.0 < minimum.x or control.size.y + 1.0 < minimum.y:
			return "버튼이 글자보다 작음 %s < %s" % [control.size, minimum]
		if control is Button and (control as Button).clip_text:
			var font: Font = control.get_theme_font("font")
			var font_size: int = control.get_theme_font_size("font_size")
			if font != null and font.get_string_size((control as Button).text, HORIZONTAL_ALIGNMENT_LEFT, -1,
					font_size).x > control.size.x + 1.0:
				return "버튼 글자 잘림"
	return ""


func _finish() -> void:
	print("UI theme: %d checks, %d failures;" % [checks, failures])
	quit(0 if failures == 0 else 1)
