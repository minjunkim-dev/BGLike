extends Node

## 전투 콜백을 덮어쓰지 않고 신호와 독립 Timer로 원본 Viewport를 기록한다.

const INTERVAL: float = 0.1
const BURST_MSEC: int = 1200

var frame_count: int = 0
var event_count: int = 0
var last_error: Error = OK
var renders_frames: bool = DisplayServer.get_name() != "headless"

var _battle: Node2D
var _actions: CombatActions
var _turns: CombatTurns
var _directory: String
var _manifest: FileAccess
var _timer: Timer
var _capture_until: int = 0
var _pending: bool = false
var _message: String = ""


func start(battle: Node2D, directory: String) -> Error:
	if _battle != null or not is_inside_tree():
		return ERR_ALREADY_IN_USE
	var result: Error = DirAccess.make_dir_recursive_absolute(directory)
	if result != OK:
		return result
	var path: String = directory.path_join("frames.jsonl")
	if FileAccess.file_exists(path):
		return ERR_ALREADY_EXISTS
	_manifest = FileAccess.open(path, FileAccess.WRITE)
	if _manifest == null:
		return FileAccess.get_open_error()
	_battle = battle
	_actions = battle.get("actions") as CombatActions
	_turns = battle.get("turns") as CombatTurns
	_directory = directory
	_actions.logged.connect(record)
	_actions.feedback.connect(_on_feedback)
	_actions.healed.connect(_on_healed)
	_turns.changed.connect(_on_turn_changed)
	_timer = Timer.new()
	_timer.wait_time = INTERVAL
	_timer.timeout.connect(_capture_frame)
	add_child(_timer)
	if renders_frames:
		_timer.start()
	record("CAPTURE_STARTED renderer=%s display=%s" % [
		RenderingServer.get_current_rendering_method(), DisplayServer.get_name()])
	return last_error


func record(message: String) -> void:
	if _manifest == null or last_error != OK:
		return
	event_count += 1
	_message = message
	_capture_until = Time.get_ticks_msec() + BURST_MSEC
	var entry: Dictionary = _entry()
	entry["message"] = message
	_store(entry)
	print("[CAPTURE] event=%d %s" % [event_count, message])


func stop() -> void:
	if _timer != null:
		_timer.stop()
	if _actions != null:
		_actions.logged.disconnect(record)
		_actions.feedback.disconnect(_on_feedback)
		_actions.healed.disconnect(_on_healed)
		_actions = null
	if _turns != null:
		_turns.changed.disconnect(_on_turn_changed)
		_turns = null
	_manifest = null


func _exit_tree() -> void:
	stop()


func _on_feedback(unit: CombatUnit, message: String) -> void:
	record("FEEDBACK %s: %s" % [unit.get_display_name(), message])


func _on_healed(unit: CombatUnit, amount: int) -> void:
	record("FEEDBACK %s: %d (heal)" % [unit.get_display_name(), amount])


func _on_turn_changed() -> void:
	var actor: CombatUnit = _turns.current_unit
	record("TURN round=%d actor=%s ally=%s" % [_turns.round_number,
		actor.get_display_name() if actor != null else "none",
		str(actor != null and actor.is_ally)])


func _entry() -> Dictionary:
	var actor: CombatUnit = _turns.current_unit
	return {"event": event_count, "ms": Time.get_ticks_msec(),
		"round": _turns.round_number, "ally": actor != null and actor.is_ally,
		"actor": actor.get_display_name() if actor != null else "none"}


func _store(entry: Dictionary) -> void:
	_manifest.store_line(JSON.stringify(entry))
	_manifest.flush()
	last_error = _manifest.get_error()
	if last_error != OK:
		_timer.stop()
		push_error("Capture manifest write failed: %s" % error_string(last_error))


func _capture_frame() -> void:
	if _pending or _manifest == null or Time.get_ticks_msec() > _capture_until:
		return
	_pending = true
	await RenderingServer.frame_post_draw
	_pending = false
	if not is_inside_tree() or _manifest == null or last_error != OK:
		return
	var image: Image = _battle.get_viewport().get_texture().get_image()
	if image == null or image.is_empty():
		last_error = ERR_CANT_CREATE
	else:
		var filename: String = "frame_%05d_event_%04d.png" % [frame_count + 1, event_count]
		last_error = image.save_png(_directory.path_join(filename))
		if last_error == OK:
			frame_count += 1
			var entry: Dictionary = _entry()
			entry.merge({"frame": frame_count, "png": filename, "message": _message})
			_store(entry)
	if last_error != OK:
		_timer.stop()
		push_error("Capture frame save failed: %s" % error_string(last_error))
