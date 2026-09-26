class_name FleetCamera
extends Node3D

enum Mode { FLEET, SHIP, FREE }

@export var camera: Camera3D
@export var fleet: FleetController
@export_range(100.0, 12000.0) var orbit_distance: float = 1800.0
@export_range(50.0, 500.0) var minimum_orbit_distance: float = 100.0
@export_range(500.0, 20000.0) var maximum_orbit_distance: float = 12000.0
@export_range(10.0, 1000.0) var zoom_step: float = 200.0
@export_range(10.0, 5000.0) var zoom_speed: float = 1200.0
@export_range(1.0, 10.0) var sprint_multiplier: float = 3.0
@export_range(800.0, 20000.0) var viewing_radius: float = 9000.0
@export_range(10.0, 5000.0) var pan_speed: float = 1000.0
@export_range(0.001, 0.02, 0.001) var mouse_sensitivity: float = 0.004
@export_range(0.1, 5.0) var stick_rotation_speed: float = 1.8

var mode: Mode = Mode.FLEET
var followed_ship: Airship
var yaw: float = 0.5
var pitch: float = -0.52
var _rotating: bool = false
var _window_active: bool = true
var _cursor_before_rotation := Vector2.ZERO
var _pending_pick := Vector2.INF
var _free_anchor_offset := Vector3.ZERO


func _ready() -> void:
	focus_fleet()


func _process(delta: float) -> void:
	_update_follow_focus()
	if _window_active:
		_update_navigation(delta)
	apply_view_bounds()


func _physics_process(_delta: float) -> void:
	if _pending_pick != Vector2.INF:
		pick_ship(_pending_pick)
		_pending_pick = Vector2.INF


func _input(event: InputEvent) -> void:
	# Handle release independently of the unhandled-input path.
	if event.is_action_released("camera_rotate_hold"):
		_end_rotation()
	if event is InputEventMouseMotion and _rotating:
		yaw -= event.screen_relative.x * mouse_sensitivity
		pitch -= event.screen_relative.y * mouse_sensitivity
		get_viewport().set_input_as_handled()


func _unhandled_input(event: InputEvent) -> void:
	var wheel_factor: float = event.factor if event is InputEventMouseButton else 1.0
	if event.is_action_pressed("camera_zoom_in"):
		zoom(-zoom_step * wheel_factor * _speed_multiplier())
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("camera_zoom_out"):
		zoom(zoom_step * wheel_factor * _speed_multiplier())
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("camera_rotate_hold"):
		_cursor_before_rotation = get_viewport().get_mouse_position()
		_rotating = true
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("select_ship") and not _rotating:
		_pending_pick = event.position if event is InputEventMouseButton else get_viewport().get_mouse_position()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("camera_focus_fleet"):
		focus_fleet()
		get_viewport().set_input_as_handled()


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		_window_active = false
		_pending_pick = Vector2.INF
		_end_rotation(false)
	elif what == NOTIFICATION_APPLICATION_FOCUS_IN:
		_window_active = true


func _exit_tree() -> void:
	_clear_followed_ship()
	_end_rotation(false)


func focus_fleet() -> void:
	_clear_followed_ship()
	mode = Mode.FLEET
	_update_follow_focus()
	apply_view_bounds()


func follow_ship(ship: Airship) -> void:
	if not ship.alive:
		return
	_clear_followed_ship()
	followed_ship = ship
	followed_ship.tree_exiting.connect(focus_fleet, CONNECT_ONE_SHOT)
	followed_ship.died.connect(_on_followed_ship_died, CONNECT_ONE_SHOT)
	mode = Mode.SHIP
	global_position = ship.global_position
	apply_view_bounds()


func pick_ship(screen_position: Vector2) -> void:
	var start := camera.project_ray_origin(screen_position)
	var end := start + camera.project_ray_normal(screen_position) * camera.far
	var query := PhysicsRayQueryParameters3D.create(start, end, 3)
	var space := get_world_3d().direct_space_state
	var excluded: Array[RID] = []
	while true:
		var hit := space.intersect_ray(query)
		if hit.is_empty() or not hit.collider is Airship:
			return
		var ship := hit.collider as Airship
		if ship.alive:
			follow_ship(ship)
			return
		# Wrecks keep physical contacts, but cannot occlude a selectable ship.
		excluded.append(ship.get_rid())
		query.exclude = excluded


func pan(displacement: Vector3) -> void:
	if mode != Mode.FREE:
		# The rig becomes the eye position in free mode, preserving the rendered view.
		var eye_position := camera.global_position
		_clear_followed_ship()
		mode = Mode.FREE
		camera.position = Vector3.ZERO
		_free_anchor_offset = eye_position - fleet.anchor.get_global_transform_interpolated().origin
	_free_anchor_offset += displacement
	_update_follow_focus()
	apply_view_bounds()


func zoom(distance_change: float) -> void:
	if mode == Mode.FREE:
		return
	# Start from the visible distance so the sphere edge cannot accumulate zoom debt.
	orbit_distance = clampf(camera.position.z + distance_change, minimum_orbit_distance, maximum_orbit_distance)
	apply_view_bounds()


func apply_view_bounds() -> void:
	if not is_instance_valid(fleet) or not is_instance_valid(camera):
		return
	_update_rotation()
	var center := fleet.anchor.get_global_transform_interpolated().origin
	var radius := maxf(viewing_radius, 100.0)
	if mode == Mode.FREE:
		var relative_eye := global_position - center
		if relative_eye.length_squared() > radius * radius:
			global_position = center + relative_eye.limit_length(radius)
			_free_anchor_offset = global_position - center
		camera.position = Vector3.ZERO
		return
	var relative_focus := (global_position - center).limit_length(radius - 80.0)
	global_position = center + relative_focus
	var boom_direction := global_basis.z
	var projection := relative_focus.dot(boom_direction)
	var available_distance := -projection + sqrt(maxf(0.0, projection * projection + radius * radius - relative_focus.length_squared()))
	orbit_distance = clampf(orbit_distance, minimum_orbit_distance, maximum_orbit_distance)
	camera.position = Vector3(0.0, 0.0, minf(orbit_distance, available_distance))


func _update_follow_focus() -> void:
	if not is_instance_valid(fleet):
		return
	if mode == Mode.SHIP:
		if not is_instance_valid(followed_ship):
			focus_fleet()
			return
		global_position = followed_ship.get_global_transform_interpolated().origin
	elif mode == Mode.FLEET:
		global_position = fleet.anchor.get_global_transform_interpolated().origin
	elif mode == Mode.FREE:
		# Follow translation only; the offset survives rebasing and never rotates with the anchor.
		global_position = fleet.anchor.get_global_transform_interpolated().origin + _free_anchor_offset


func _update_navigation(delta: float) -> void:
	var movement := Input.get_vector("camera_pan_left", "camera_pan_right", "camera_pan_forward", "camera_pan_back", 0.2)
	if movement.length_squared() > 0.0 and mode != Mode.FREE:
		# Release before turning so simultaneous move/look input cannot orbit for one frame.
		pan(Vector3.ZERO)
	var look := Input.get_vector("camera_look_left", "camera_look_right", "camera_look_up", "camera_look_down", 0.2)
	yaw -= look.x * stick_rotation_speed * delta
	pitch -= look.y * stick_rotation_speed * delta
	_update_rotation()
	var multiplier := _speed_multiplier()
	if movement.length_squared() > 0.0:
		pan(global_basis * Vector3(movement.x, 0.0, movement.y) * pan_speed * multiplier * delta)
	var zoom_input := Input.get_axis("camera_zoom_in_hold", "camera_zoom_out_hold")
	if not is_zero_approx(zoom_input):
		zoom(zoom_input * zoom_speed * multiplier * delta)


func _update_rotation() -> void:
	if mode == Mode.FREE:
		pitch = clampf(pitch, deg_to_rad(-85.0), deg_to_rad(85.0))
	else:
		pitch = clampf(pitch, deg_to_rad(-80.0), deg_to_rad(-8.0))
	rotation = Vector3(pitch, yaw, 0.0)


func _speed_multiplier() -> float:
	return sprint_multiplier if Input.is_action_pressed("camera_sprint") else 1.0


func _clear_followed_ship() -> void:
	if is_instance_valid(followed_ship):
		if followed_ship.tree_exiting.is_connected(focus_fleet):
			followed_ship.tree_exiting.disconnect(focus_fleet)
		if followed_ship.died.is_connected(_on_followed_ship_died):
			followed_ship.died.disconnect(_on_followed_ship_died)
	followed_ship = null


func _on_followed_ship_died(_ship: Airship) -> void:
	focus_fleet()


func _end_rotation(restore_cursor: bool = true) -> void:
	if not _rotating:
		return
	_rotating = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if restore_cursor:
		Input.warp_mouse(_cursor_before_rotation)
