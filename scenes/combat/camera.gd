class_name CombatCamera
extends Camera2D
## 전투 맵 카메라(#393). 휠·트랙패드 집기로 확대/축소, 가운데 버튼 드래그·트랙패드 두 손가락·WASD로 이동, C로 되돌린다.
## 화면 위치는 저장하지 않는다. 스테이지를 만들거나 이어하기로 다시 열면 1배 가운데로 돌아간다(docs/adr/0002).

## 정수 배율만 쓴다. 칸 끝이 화면 픽셀 경계에 남아 지형 원본의 이웃 칸을 읽지 않는다(docs/adr/0002).
const ZOOMS: Array[float] = [1.0, 2.0]
## 오른쪽 정보 패널만큼 맵 기준점을 화면 가운데에서 왼쪽 위로 옮긴다. 확대해도 화면에서 같은 거리다.
const FOCUS_OFFSET: Vector2 = Vector2(100, 12)
## WASD 이동 속도(논리 화면 px/초).
const PAN_SPEED: float = 240.0
## 트랙패드 두 손가락 이동 1단위의 논리 화면 px.
const PAN_GESTURE_SPEED: float = 40.0
## 트랙패드 집기 배율이 이만큼 쌓이면 한 단계 바꾼다.
const MAGNIFY_STEP: float = 1.25

## 맵 칸 좌표(소수)에서 맵 좌표로. 기준점을 맵 칸 범위 안에 묶을 때 쓴다.
var _grid: Transform2D
var _last_cell: Vector2
## 화면 기준점에 둘 맵 좌표. 반올림 전 값이라 느린 드래그도 잃지 않는다.
var _focus: Vector2
var _dragging: bool = false
var _magnify: float = 1.0


## 새 맵의 칸 범위로 1배 가운데에 둔다.
func frame(map: TileMapLayer, map_size: Vector2i) -> void:
	var origin: Vector2 = map.map_to_local(Vector2i.ZERO)
	_grid = Transform2D(map.map_to_local(Vector2i.RIGHT) - origin, map.map_to_local(Vector2i.DOWN) - origin, origin)
	_last_cell = Vector2(map_size - Vector2i.ONE)
	_dragging = false
	# 창 크기가 바뀌면 화면 가운데가 0.5 논리 px 움직일 수 있어 원점을 다시 맞춘다.
	if not get_viewport().size_changed.is_connected(_apply):
		get_viewport().size_changed.connect(_apply)
	reset()


func reset() -> void:
	zoom = Vector2.ONE * ZOOMS[0]
	_focus = _grid * (_last_cell / 2.0)
	_apply()


func pan(screen_delta: Vector2) -> void:
	_focus += screen_delta / zoom.x
	_apply()


## screen_point(뷰포트 좌표) 아래의 맵 위치를 그대로 둔 채 확대 단계를 step만큼 바꾼다.
func zoom_at(screen_point: Vector2, step: int) -> void:
	var index: int = clampi(ZOOMS.find(zoom.x) + step, 0, ZOOMS.size() - 1)
	var from_focus: Vector2 = screen_point - (get_viewport_rect().size / 2.0 - FOCUS_OFFSET)
	var world: Vector2 = _focus + from_focus / zoom.x
	zoom = Vector2.ONE * ZOOMS[index]
	_focus = world - from_focus / zoom.x
	_apply()


func _apply() -> void:
	# 기준점이 맵 칸 범위를 벗어나지 않아 화면에 늘 맵이 남는다.
	_focus = _grid * (_grid.affine_inverse() * _focus).clamp(Vector2.ZERO, _last_cell)
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


## HUD가 받지 않은 입력만 쓴다. 패널은 휠을 소비하지 않으므로 HUD 위의 휠은 직접 거른다.
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and get_viewport().gui_get_hovered_control() != null:
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
