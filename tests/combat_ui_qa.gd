extends SceneTree

## #457: 패시브 칸·방어막 HP 바·이로움/해로움 수치 색을 실제 게임 장면(game.tscn)에서 에이전트가 조작해 확인한다.
## 적 AI를 끈 채 HUD 갱신 API와 실제 동작(use_self, 피해 처리)을 호출한다. 주사위는 고정 seed다.
## 해로운 수치(공격 -1)는 현재 데이터에 없어 무기 능력치 fixture로 만든다. 실제 입력 장치 증거가 아니다.

const ScriptedDice = preload("res://tests/scripted_dice.gd")

var checks: int = 0
var failures: int = 0
var battle: Node2D
var actions: CombatActions
var units: Array[CombatUnit]
var hud: CombatTurnHud
var log_lines: Array[String] = []
var output: String = ""


func _initialize() -> void:
	_run.call_deferred()


func _check(condition: bool, message: String) -> void:
	checks += 1
	print("[COMBAT_UI_QA] %s: %s" % ["ok" if condition else "FAIL", message])
	if not condition:
		failures += 1
		push_error(message)


func _run() -> void:
	create_timer(60.0).timeout.connect(func() -> void:
		push_error("combat ui qa watchdog expired")
		quit(1))
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--capture-dir="):
			output = argument.trim_prefix("--capture-dir=")
			DirAccess.make_dir_recursive_absolute(output)
	root.size = Vector2i(1280, 720)
	GameSave.autosave = false
	var main: Node = (load("res://scenes/game.tscn") as PackedScene).instantiate()
	root.add_child(main)
	current_scene = main
	battle = main.get_node("Battle") as Node2D
	battle.set_process(false)
	(battle.get("progress") as CombatActProgress).stage_index = 8
	battle.call("_start_stage", true)
	battle.call("start_battle")
	units = battle.get("units")
	actions = battle.get("actions") as CombatActions
	hud = battle.get_node("UI/TurnHud") as CombatTurnHud
	actions.dice = ScriptedDice.new([], []).then_seeded()
	actions.logged.connect(func(line: String) -> void: log_lines.append(line))
	await create_timer(0.3).timeout
	var warrior: CombatUnit = units[0]
	var archer: CombatUnit = units[1]
	_check(warrior.kind == CombatUnit.Kind.WARRIOR and archer.kind == CombatUnit.Kind.ARCHER and units.size() == 3,
		"전제조건: 3-3의 전사·궁수·보스")
	ScriptedDice.arrange_turns(battle.get("turns") as CombatTurns, units, [warrior, archer, units[2]])
	await _passive_slot(warrior, archer)
	await _shield_bar(warrior)
	await _number_colors(warrior, archer)
	var problems: Array[String] = ScriptedDice.finish()
	_check(problems.is_empty(), "준비한 주사위 모두 소비: %s" % str(problems))
	print("Combat UI QA: %d checks, %d failures;" % [checks, failures])
	quit(0 if failures == 0 else 1)


func _capture(label: String) -> void:
	await create_timer(0.3).timeout
	if output.is_empty():
		return
	await RenderingServer.frame_post_draw
	_check(root.get_texture().get_image().save_png(output.path_join(label + ".png")) == OK, "캡처 저장: " + label)


## 항목 1: 패시브 칸은 스킬 버튼보다 왼쪽에 있고, 팔랑크스는 인접 아군이 있을 때만 강조된다.
func _passive_slot(warrior: CombatUnit, archer: CombatUnit) -> void:
	var passives: Dictionary = hud.get("_passives")
	var dots: Dictionary = hud.get("_passive_dots")
	var buttons: Dictionary = hud.get("_actions")
	var viewport: Rect2 = root.get_visible_rect()
	warrior.cell = Vector2i(3, 5)
	archer.cell = Vector2i(4, 5)  # 인접
	hud.refresh_actions(actions, "attack", warrior)
	await create_timer(0.2).timeout
	var phalanx: Button = passives["phalanx"]
	var brawn: Button = passives["brawn"]
	_check(phalanx.visible and brawn.visible and phalanx.get_global_rect().size.x > 0, "전사 선택: 팔랑크스·괴력의 사내 칸이 보임")
	_check(viewport.encloses(phalanx.get_global_rect()) and viewport.encloses(brawn.get_global_rect()), "패시브 칸이 화면 안")
	var leftmost: float = INF
	for action: String in buttons:
		var button: Button = buttons[action]
		if button.is_visible_in_tree():
			leftmost = minf(leftmost, button.get_global_rect().position.x)
	_check(leftmost < INF and phalanx.get_global_rect().end.x <= leftmost and brawn.get_global_rect().end.x <= leftmost,
		"패시브 칸이 모든 스킬 버튼의 왼쪽: 패시브 끝 %.1f ≤ 스킬 시작 %.1f" % [phalanx.get_global_rect().end.x, leftmost])
	_check(phalanx.text.is_empty() == false and phalanx.get_child_count() == 1 and brawn.get_child_count() == 1,
		"패시브 버튼에는 비용 기호·횟수 배지 없이 점 하나만 있음")
	_check(actions.grid.phalanx_bonus(warrior) > 0 and (dots["phalanx"] as Label).visible,
		"인접 아군 있음: 팔랑크스 강조 점 켜짐")
	var on_style: StyleBoxFlat = phalanx.get_theme_stylebox("normal") as StyleBoxFlat
	_check(on_style.border_width_left == 2, "인접 아군 있음: 팔랑크스 테두리 두꺼움")
	_check(not (dots["brawn"] as Label).visible, "괴력의 사내는 강조 없음")
	await _capture("passive-phalanx-on")
	archer.cell = Vector2i(9, 1)  # 인접하지 않음
	hud.refresh_actions(actions, "attack", warrior)
	await create_timer(0.2).timeout
	_check(actions.grid.phalanx_bonus(warrior) == 0 and phalanx.visible and not (dots["phalanx"] as Label).visible,
		"인접 아군 없음: 칸은 보이지만 강조 점 꺼짐")
	var off_style: StyleBoxFlat = phalanx.get_theme_stylebox("normal") as StyleBoxFlat
	_check(off_style.border_width_left != 2, "인접 아군 없음: 테두리 평범")
	await _capture("passive-phalanx-off")
	var turns: CombatTurns = battle.get("turns") as CombatTurns
	ScriptedDice.arrange_turns(turns, units, [archer, warrior, units[2]])
	hud.refresh_actions(actions, "attack", archer)
	_check(turns.current_unit == archer and not phalanx.visible and not brawn.visible, "궁수 차례: 패시브 칸 숨음")
	ScriptedDice.arrange_turns(turns, units, [warrior, archer, units[2]])
	hud.refresh_actions(actions, "attack", warrior)


## 항목 2: 성스러운 장막을 쓰면 HP 바에 방어막 구간이 생기고, 피해로 줄다가 0이 되면 사라진다.
func _shield_bar(warrior: CombatUnit) -> void:
	warrior.hit_points = warrior.get_max_hit_points() - 3
	var before: Vector2 = warrior.get_bar_fractions()
	_check(before.y == 0.0 and warrior.shield_points == 0, "장막 전: 방어막 구간 없음")
	var used: bool = actions.use_self(warrior, "holy_veil")
	hud.show_unit(warrior)
	await create_timer(0.3).timeout
	var shield: int = warrior.shield_points
	var bar: Vector2 = warrior.get_bar_fractions()
	_check(used and shield > 0 and warrior.shield_turns > 0, "성스러운 장막 사용: 방어막 %d, %d턴" % [shield, warrior.shield_turns])
	_check(bar.y > 0.0 and bar.x + bar.y <= 1.0001,
		"HP 바에 방어막 구간이 생김: HP %.3f + 방어막 %.3f" % [bar.x, bar.y])
	_check("방어막 %d (%d턴)" % [shield, warrior.shield_turns] in hud.resource_label.get_parsed_text(), "유닛 패널 상태 줄에 방어막과 남은 기간")
	await _capture("shield-on")
	log_lines.clear()
	var hp: int = warrior.hit_points
	var small: int = maxi(1, shield / 2)
	actions.call("_damage", warrior, small)
	hud.show_unit(warrior)
	_check(warrior.shield_points == shield - small and warrior.hit_points == hp, "작은 피해: 방어막만 %d 줄고 HP 그대로" % small)
	_check(warrior.get_bar_fractions().y < bar.y and warrior.get_bar_fractions().y > 0.0, "방어막 구간이 줄어듦")
	_check(log_lines.any(func(line: String) -> bool: return "방어막: %d 흡수 · 남은 방어막 %d" % [small, shield - small] in line),
		"로그: 방어막 흡수 문구: %s" % str(log_lines))
	await _capture("shield-reduced")
	actions.call("_damage", warrior, warrior.shield_points + 1)
	hud.show_unit(warrior)
	await create_timer(0.3).timeout
	_check(warrior.shield_points == 0 and warrior.shield_turns == 0 and warrior.get_bar_fractions().y == 0.0,
		"방어막 소진: 구간이 사라짐")
	_check(warrior.hit_points == hp - 1, "초과분 1만 HP가 받음")
	_check("방어막" not in hud.resource_label.get_parsed_text(), "방어막 소진: 상태 줄에서도 사라짐")
	await _capture("shield-gone")


## 항목 3: 이로움은 초록·해로움은 빨강으로 칠하고 부호를 함께 쓴다.
func _number_colors(warrior: CombatUnit, archer: CombatUnit) -> void:
	warrior.weapon = {"stats": {"attack_bonus": 2}}
	archer.weapon = {"stats": {"attack_bonus": -1}}  # fixture: 현재 데이터에는 해로운 수치가 없다
	archer.cell = Vector2i(4, 5)  # 전사 인접 → 팔랑크스 AC +1
	hud.show_unit(warrior)
	var good: String = hud.resource_label.text
	var parsed: String = hud.resource_label.get_parsed_text()
	_check(good.contains("[color=#70c76d]+2[/color]") and "공격 +2" in parsed, "이로움: 공격 +2가 초록이고 부호 유지")
	_check(good.contains("AC [color=#70c76d]+1[/color]") and "팔랑크스 AC +1" in parsed, "이로움: 팔랑크스 AC +1이 초록이고 부호 유지")
	await _capture("number-good")
	hud.show_unit(archer)
	var bad: String = hud.resource_label.text
	_check(bad.contains("[color=#ff8a80]-1[/color]") and "공격 -1" in hud.resource_label.get_parsed_text(),
		"해로움: 공격 -1이 빨강이고 부호 유지")
	archer.weapon = {"stats": {"attack_bonus": 0}}
	hud.show_unit(archer)
	_check("공격 +0" in hud.resource_label.get_parsed_text() and not hud.resource_label.text.contains("+0[/color]"),
		"공격 +0은 칠하지 않음")
	archer.weapon = {"stats": {"attack_bonus": -1}}
	hud.show_unit(archer)
	await _capture("number-bad")
