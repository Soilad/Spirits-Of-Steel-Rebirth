extends Node

@export var camera: Camera2D = get_parent()
@export var base_speed: float = 600.0

var is_dragging := false


func _process(delta: float) -> void:
	if Console.is_visible() or GameState.decision_menu_open:
		return
	_handle_keyboard_movement(delta)


func _is_mouse_over_ui() -> bool:
	var hovered = get_viewport().gui_get_hovered_control()
	return hovered != null


func _input(event: InputEvent) -> void:
	if Console.is_visible() or _is_mouse_over_ui():
		return

	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_MIDDLE:
		is_dragging = event.pressed
		get_viewport().set_input_as_handled()

	if event is InputEventMouseMotion and is_dragging:
		camera.position -= event.relative / camera.zoom.x
		_clamp_camera_position()

	if event is InputEventMouseButton and event.is_pressed():
		var zoom_dir = 0
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			zoom_dir = 1
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			zoom_dir = -1

		if zoom_dir != 0:
			_perform_zoom(zoom_dir)


func _handle_keyboard_movement(delta: float) -> void:
	var input_dir = Input.get_vector("move_left", "move_right", "move_up", "move_down")
	camera.position += input_dir * (base_speed / camera.zoom.x) * delta
	_clamp_camera_position()


func _perform_zoom(direction: int) -> void:
	var mouse_pos_before := camera.get_global_mouse_position()

	var new_zoom := camera.zoom + Vector2.ONE * direction
	camera.zoom = new_zoom.clamp(Vector2.ONE, Vector2.ONE * 12)

	var mouse_pos_after := camera.get_global_mouse_position()
	camera.position += mouse_pos_before - mouse_pos_after
	_clamp_camera_position()


func _clamp_camera_position() -> void:
	if not MapManager.id_map_image:
		return
	
	var map_height = MapManager.id_map_image.get_height()
	# Optional: You might want to allow seeing a bit of the void (e.g. half screen height)
	# But the request was specifically "cant pan away from it into nothing".
	# So strict clamping to 0 and map_height seems correct.
	# We use clampf to keep the camera center within the vertical bounds of the map.
	# This allows some empty space if zoomed out, but prevents panning away completely.

	
	var min_y = -35.0 / camera.zoom.x
	print(camera.zoom.x)
	var max_y = (map_height - 35.0) / camera.zoom.x if camera.zoom.x > 1.0 else -23.0
	camera.position.y = clampf(camera.position.y, min_y, max_y)
