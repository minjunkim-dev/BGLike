class_name CombatCamera
extends Camera2D
## 전투 맵 카메라(#393). 휠·트랙패드 집기로 확대/축소, 가운데 버튼 드래그·트랙패드 두 손가락·WASD로 이동, C로 되돌린다.
## 화면 위치는 저장하지 않는다. 스테이지를 만들거나 이어하기로 다시 열면 1배 가운데로 돌아간다(docs/adr/0002).

## 정수 배율만 쓴다. 칸 끝이 화면 픽셀 경계에 남아 지형 원본의 이웃 칸을 읽지 않는다(docs/adr/0002, #731).
const ZOOMS: Array[float] = [1.0, 2.0, 3.0, 4.0]
## 맵 기준점 F를 화면 가운데에서 위로 20 논리px에 둔다(#555, #618). 확대해도 화면에서 같은 거리다.
const FOCUS_OFFSET: Vector2 = Vector2(0, 20)
## WASD 이동 속도(논리 화면 px/초).
const PAN_SPEED: float = 240.0
## 트랙패드 두 손가락 이동 1단위의 논리 화면 px.
const PAN_GESTURE_SPEED: float = 40.0
## 트랙패드 집기 배율이 이만큼 쌓이면 한 단계 바꾼다.
const MAGNIFY_STEP: float = 1.25
## 맵 중앙 영역 C(F를 가운데로 한 논리 화면 px 사각형, #555). 행동 유닛이 이 밖이면 따라간다(#516).
const CENTER_SIZE: Vector2 = Vector2(128, 64)
## 턴이 넘어올 때 행동 유닛을 F로 옮기는 게임 시간(초). 전체 속도 계수(`PRESENTATION_SPEED`)를 적용하지 않는다(#516 2절).
const TURN_FOCUS_TIME: float = 0.4
## 이동 중 따라잡기: 남은 거리의 비율이 초당 이 값의 지수 감쇠로 줄어든다(게임 시간). 플레이로 조정하는 시작값이다(#516 2절).
const FOLLOW_RATE: float = 10.0
## 남은 화면 거리가 이보다 작으면 목표로 맞추고 멈춘다(논리 px).
const FOLLOW_SNAP: float = 1.0

## 맵 칸 좌표(소수)에서 맵 좌표로. 기준점을 맵 칸 범위 안에 묶을 때 쓴다.
var _grid: Transform2D
var _last_cell: Vector2
## 화면 기준점에 둘 맵 좌표. 반올림 전 값이라 느린 드래그도 잃지 않는다.
var _focus: Vector2
var _dragging: bool = false
var _magnify: float = 1.0
## 따라가는 행동 유닛(#516). null이면 따라가지 않는다.
var _followed: CombatUnit
## 따라가는 턴의 순환 번호. 혼자인 유닛은 다음 순환에도 같은 유닛으로 턴을 받으므로 유닛과 함께 본다.
var _followed_round: int = 0
## 플레이어가 화면을 직접 움직였다. 그 유닛의 턴이 끝날 때까지 따라잡기(2)를 끈다.
var _hand_moved: bool = false
## 턴 이동(1)의 진행. 시작 화면 기준점·끝 목표·처음 목표 점(바뀌면 유닛이 움직이기 시작한 것)·지난 시간.
var _turning: bool = false
var _turn_from: Vector2
var _turn_to: Vector2
var _turn_goal: Vector2
var _turn_elapsed: float = 0.0
## 이동 중 따라잡기(2)가 F에 닿기 전이다.
var _catching_up: bool = false


## 새 맵의 칸 범위로 1배 가운데에 둔다.
func frame(map: TileMapLayer, map_size: Vector2i) -> void:
	var origin: Vector2 = map.map_to_local(Vector2i.ZERO)
	_grid = Transform2D(map.map_to_local(Vector2i.RIGHT) - origin, map.map_to_local(Vector2i.DOWN) - origin, origin)
	_last_cell = Vector2(map_size - Vector2i.ONE)
	_dragging = false
	_followed = null
	_hand_moved = false
	_stop_following()
	# 창 크기가 바뀌면 화면 가운데가 0.5 논리 px 움직일 수 있어 원점을 다시 맞춘다.
	if not get_viewport().size_changed.is_connected(_apply):
		get_viewport().size_changed.connect(_apply)
	_home()


## C 키: 1배로 줄이고 맵 가운데로 되돌린다. 플레이어의 손 조작이라 따라가기를 멈춘다.
func reset() -> void:
	_hand_moved = true
	_stop_following()
	_home()


func _home() -> void:
	zoom = Vector2.ONE * ZOOMS[0]
	_magnify = 1.0
	_focus = _grid * (_last_cell / 2.0)
	_apply()


func pan(screen_delta: Vector2) -> void:
	_hand_moved = true
	_stop_following()
	_focus += screen_delta / zoom.x
	_apply()


## screen_point(뷰포트 좌표) 아래의 맵 위치를 그대로 둔 채 확대 단계를 step만큼 바꾼다.
func zoom_at(screen_point: Vector2, step: int) -> void:
	_hand_moved = true
	_stop_following()
	var index: int = clampi(ZOOMS.find(zoom.x) + step, 0, ZOOMS.size() - 1)
	var from_focus: Vector2 = screen_point - (get_viewport_rect().size / 2.0 - FOCUS_OFFSET)
	var world: Vector2 = _focus + from_focus / zoom.x
	zoom = Vector2.ONE * ZOOMS[index]
	_focus = world - from_focus / zoom.x
	_apply()


## 따라갈 행동 유닛과 그 턴의 순환 번호(`CombatTurns.round_number`)를 알린다(#516 2절). 유닛이나 순환이 바뀔 때만 새로 시작한다:
## 손 조작 표시를 지우고, 유닛이 C 밖이면 턴 이동(1)을 연다.
## null(전투 시작 전·전투 끝·전투 불능)이면 따라가지 않고 진행 중인 따라가기도 멈춘다.
func follow_turn(unit: CombatUnit, round_number: int) -> void:
	if unit == _followed and round_number == _followed_round:
		return
	_followed = unit
	_followed_round = round_number
	_hand_moved = false
	_stop_following()
	if unit != null and _outside_center(_target_point()):
		_turning = true
		_turn_elapsed = 0.0
		_turn_from = _focus
		_turn_goal = _target_point()
		_turn_to = _clamp_focus(_turn_goal)


## 턴 이동(1)이 진행 중인지. 적 턴의 첫 행동 전 멈춤이 이것을 기다린다.
func is_turning() -> bool:
	return _turning


## 따라가기를 delta(게임 시간 초)만큼 진행한다. 4배속에서는 delta가 4배라 같은 규칙이 실제로 더 빨리 돈다.
func advance(delta: float) -> void:
	if not is_instance_valid(_followed):
		_followed = null
		_stop_following()
		return
	var goal: Vector2 = _target_point()
	if _turning and not goal.is_equal_approx(_turn_goal):
		# 턴 이동 중 유닛이 움직이기 시작했다. 그 자리에서 멈추고 지금 카메라 위치에서 이어 따라잡는다.
		_turning = false
		_catching_up = true
	if _turning:
		_turn_elapsed += delta
		var ratio: float = clampf(_turn_elapsed / TURN_FOCUS_TIME, 0.0, 1.0)
		_focus = _turn_from.lerp(_turn_to, sin(ratio * PI / 2.0))
		_turning = ratio < 1.0
		_apply()
		return
	if _hand_moved:
		return
	if not _catching_up and not _outside_center(goal):
		return
	_catching_up = true
	var target: Vector2 = _clamp_focus(goal)
	var remaining: Vector2 = target - _focus
	if remaining.length() * zoom.x < FOLLOW_SNAP:
		_catching_up = false
		if remaining != Vector2.ZERO:
			_focus = target
			_apply()
		return
	_focus += remaining * (1.0 - exp(-FOLLOW_RATE * delta))
	_apply()


func _stop_following() -> void:
	_turning = false
	_catching_up = false


## 행동 유닛 칸 윗면 가운데 점(카메라와 같은 맵 좌표). 점프로 그림이 뜨는 높이(`body_offset_y`)는 넣지 않는다.
func _target_point() -> Vector2:
	return (get_parent() as Node2D).to_local(_followed.to_global(Vector2(0, _followed.floor_offset_y)))


## 점이 지금 화면의 맵 중앙 영역 C 밖인지. C는 F를 가운데로 한 화면 사각형이라 맵 좌표 거리에 배율을 곱해 본다.
func _outside_center(point: Vector2) -> bool:
	var from_focus: Vector2 = (point - _focus) * zoom.x
	return absf(from_focus.x) > CENTER_SIZE.x / 2.0 or absf(from_focus.y) > CENTER_SIZE.y / 2.0


## 기준점이 맵 칸 범위를 벗어나지 않게 묶는다.
func _clamp_focus(point: Vector2) -> Vector2:
	return _grid * (_grid.affine_inverse() * point).clamp(Vector2.ZERO, _last_cell)


func _apply() -> void:
	# 기준점이 맵 칸 범위를 벗어나지 않아 화면에 늘 맵이 남는다.
	_focus = _clamp_focus(_focus)
	offset = FOCUS_OFFSET / zoom.x
	# 화면 원점을 정수 논리 px에 맞춘다. 정수 창 배율과 정수 확대에서 텍셀 경계가 화면 픽셀 경계에 놓인다.
	var center: Vector2 = get_viewport_rect().size / 2.0
	position = (center - (center - (_focus + offset) * zoom.x).round()) / zoom.x - offset
	force_update_scroll()


func _process(delta: float) -> void:
	var direction: Vector2 = Vector2(
		int(Input.is_physical_key_pressed(KEY_D)) - int(Input.is_physical_key_pressed(KEY_A)),
		int(Input.is_physical_key_pressed(KEY_S)) - int(Input.is_physical_key_pressed(KEY_W)))
	if direction != Vector2.ZERO:
		# 적 턴 가속(Engine.time_scale)과 관계없이 같은 속도로 움직인다.
		pan(direction.normalized() * PAN_SPEED * delta / Engine.time_scale)
	advance(delta)


func _input(event: InputEvent) -> void:
	# 드래그는 HUD 위를 지나거나 HUD 위에서 놓아도 이어서 받는다.
	if not _dragging:
		return
	# 일시정지 중이나 창 밖에서 버튼을 떼면 그 이벤트가 오지 않는다. 이동 이벤트의 버튼 상태로 끝낸다.
	if event is InputEventMouseMotion and event.button_mask & MOUSE_BUTTON_MASK_MIDDLE == 0:
		_dragging = false
	elif event is InputEventMouseMotion:
		pan(-event.relative)
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_MIDDLE and not event.pressed:
		_dragging = false


## HUD가 받지 않은 입력만 쓴다. 패널은 휠·제스처를 소비하지 않으므로 HUD 위의 입력은 직접 거른다.
func _unhandled_input(event: InputEvent) -> void:
	if ((event is InputEventMouseButton and event.pressed or event is InputEventGesture)
			and get_viewport().gui_get_hovered_control() != null):
		return
	if event is InputEventMouseButton and event.pressed:
		match event.button_index:
			MOUSE_BUTTON_WHEEL_UP:
				zoom_at(event.position, 1)
			MOUSE_BUTTON_WHEEL_DOWN:
				zoom_at(event.position, -1)
			MOUSE_BUTTON_MIDDLE:
				_dragging = true
			_:
				return
	elif event is InputEventPanGesture:
		pan(event.delta * PAN_GESTURE_SPEED)
	elif event is InputEventMagnifyGesture:
		_magnify *= event.factor
		if _magnify >= MAGNIFY_STEP or _magnify <= 1.0 / MAGNIFY_STEP:
			zoom_at(event.position, 1 if _magnify > 1.0 else -1)
			_magnify = 1.0
	elif event is InputEventKey and event.physical_keycode == KEY_C and event.pressed and not event.echo \
			and not event.is_command_or_control_pressed():
		reset()
	else:
		return
	get_viewport().set_input_as_handled()
