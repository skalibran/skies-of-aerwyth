extends SceneTree

const JOURNEY_SCENE := preload("res://scenes/world/journey.tscn")
const SHIP_SCENE := preload("res://scenes/ships/ship.tscn")

var _rate: int = Engine.physics_ticks_per_second
var _delta: float = 1.0 / _rate
var _failures: Array[String] = []
var _journey: Journey
var _visual: bool = false


func _initialize() -> void:
	_visual = "--visual" in OS.get_cmdline_user_args()
	_run.call_deferred()


func _run() -> void:
	_check_coordinates()
	_journey = JOURNEY_SCENE.instantiate() as Journey
	_journey.combat_enabled = false
	root.add_child(_journey)
	await _frames(3 * _rate)
	_check(_journey.ships.size() == 9, "The authored fleet has nine ships.")
	_check(_journey.fleet.anchor.position.z < -10.0, "The fleet makes forward progress.")
	_check_initial_surroundings()
	await _capture("fleet")
	if _visual:
		await _capture_surroundings()
	await _check_camera()
	_check_free_camera()
	await _check_free_camera_follow()
	await _check_camera_membership()
	_check_zoom()
	_check_navigation_debug()
	_check_rebase()
	_check_spawns()
	if not _visual:
		if "--extended" in OS.get_cmdline_user_args():
			await _check_long_travel()
		await _check_slowdown()
		await _check_membership()
		await _check_encounters()
	else:
		var rig := _journey.camera_rig
		var saved_distance := rig.orbit_distance
		rig.follow_ship(_journey.ships[4])
		rig.zoom(200.0 - rig.camera.position.z)
		await _frames(2)
		await _capture("zoomed")
		rig.pan(Vector3.ZERO)
		rig.pitch = -0.1
		rig.yaw += 0.35
		await _frames(2)
		await _capture("free-camera")
		rig.orbit_distance = saved_distance
		rig.pitch = -0.52
		rig.yaw = 0.5
		DisplayServer.window_set_size(Vector2i(760, 540))
		await _frames(10)
		_journey.camera_rig.focus_fleet()
		await _capture("resized")
		DisplayServer.window_set_size(Vector2i(1280, 800))
		_set_distant_origin()
		_journey.origin.shift_segments(-1)
		await _frames(10)
		await _capture("after-rebase")
	_journey.queue_free()
	await process_frame
	if _failures.is_empty():
		print("PASS: movement checks (%s)." % ("rendering and input" if _visual else "simulation and input"))
	else:
		for failure in _failures:
			printerr("FAIL: ", failure)
	quit(0 if _failures.is_empty() else 1)


func _check_coordinates() -> void:
	var negative := RoutePosition.new(0, -2.5)
	_check(negative.segment == -1 and is_equal_approx(negative.offset, 10237.5), "Negative offsets normalize across zero.")
	var boundary := RoutePosition.new(-7, 10240.0)
	_check(boundary.segment == -6 and boundary.offset == 0.0, "Exact positive boundaries carry once.")
	var large_segment: int = -9007199254740995
	var distant := RoutePosition.new(large_segment, 125.0)
	_check(distant.to_scene(large_segment + 1) == -10115.0, "Integer segment subtraction preserves precision beyond 2^53.")
	var restored := RoutePosition.from_scene(distant.to_scene(large_segment + 1), large_segment + 1)
	_check(restored.compare(distant) == 0, "Logical coordinates round-trip at a huge segment index.")
	_check(distant.advanced(-200.0).compare(distant) < 0, "Forward movement decreases logical Z.")


func _check_camera() -> void:
	var rig := _journey.camera_rig
	var ship := _journey.ships[4]
	# Exercise the same click path as real input after physics has synchronized.
	var pixel := rig.camera.unproject_position(ship.global_position)
	Input.warp_mouse(pixel)
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.position = pixel
	click.pressed = true
	# Viewport-local injection also works with the headless driver's 64px window.
	root.push_input(click, true)
	await _frames(3)
	_check(rig.mode == FleetCamera.Mode.SHIP, "Mouse click selects a ship through the input/picking path.")
	click.pressed = false
	root.push_input(click, true)
	await _capture("ship")
	var before_pan := _journey.anchor_route_position()
	var key := InputEventKey.new()
	key.physical_keycode = KEY_D
	key.pressed = true
	Input.parse_input_event(key)
	await _frames(12)
	key.pressed = false
	Input.parse_input_event(key)
	await _frames(2)
	_check(rig.mode == FleetCamera.Mode.FREE, "WASD actions release tracking.")
	_check(not paused and _journey.anchor_route_position().compare(before_pan) < 0, "Panning never pauses gameplay.")
	for direction in [Vector3.RIGHT, Vector3.LEFT, Vector3.FORWARD, Vector3.BACK, Vector3.UP, Vector3.DOWN]:
		rig.pan(direction * 10000.0)
		var center := _journey.fleet.anchor.get_global_transform_interpolated().origin
		_check(rig.camera.global_position.distance_to(center) <= rig.viewing_radius + 0.1, "The final camera position stays inside its sphere.")
	rig.focus_fleet()
	var original_yaw := rig.yaw
	var motion := InputEventMouseMotion.new()
	motion.screen_relative = Vector2(30.0, 0.0)
	Input.parse_input_event(motion)
	await _frames(2)
	_check(is_equal_approx(rig.yaw, original_yaw), "Mouse motion without RMB does not rotate.")
	var button := InputEventMouseButton.new()
	button.button_index = MOUSE_BUTTON_RIGHT
	button.position = pixel
	button.pressed = true
	Input.parse_input_event(button)
	Input.parse_input_event(motion)
	await _frames(2)
	_check(not is_equal_approx(rig.yaw, original_yaw), "Held RMB enables orbit rotation.")
	button.pressed = false
	Input.parse_input_event(button)
	await _frames(2)
	original_yaw = rig.yaw
	Input.parse_input_event(motion)
	await _frames(2)
	_check(is_equal_approx(rig.yaw, original_yaw), "RMB release ends rotation.")
	button.pressed = true
	Input.parse_input_event(button.duplicate())
	rig.notification(NOTIFICATION_APPLICATION_FOCUS_OUT)
	_check(Input.mouse_mode == Input.MOUSE_MODE_VISIBLE, "Focus loss releases captured rotation.")
	rig.notification(NOTIFICATION_APPLICATION_FOCUS_IN)
	button.pressed = false
	Input.parse_input_event(button.duplicate())
	await _frames(2)
	Input.parse_input_event(_stick(JOY_AXIS_LEFT_X, 0.05))
	await _frames(3)
	_check(rig.mode == FleetCamera.Mode.FLEET, "Small controller drift stays in the deadzone.")
	Input.parse_input_event(_stick(JOY_AXIS_LEFT_X, 0.8))
	await _frames(4)
	_check(rig.mode == FleetCamera.Mode.FREE, "Left-stick movement releases tracking.")
	Input.parse_input_event(_stick(JOY_AXIS_LEFT_X, 0.0))
	await _frames(2)
	rig.focus_fleet()
	original_yaw = rig.yaw
	Input.parse_input_event(_stick(JOY_AXIS_RIGHT_X, 0.8))
	await _frames(4)
	Input.parse_input_event(_stick(JOY_AXIS_RIGHT_X, 0.0))
	_check(rig.mode == FleetCamera.Mode.FLEET and not is_equal_approx(rig.yaw, original_yaw), "Right-stick orbit preserves tracking (mode %d, yaw %.4f -> %.4f)." % [rig.mode, original_yaw, rig.yaw])
	rig._process(0.0)
	_check(rig.global_position.is_equal_approx(_journey.fleet.anchor.get_global_transform_interpolated().origin), "Fleet tracking follows the persistent anchor.")
	rig.yaw = 0.5
	rig.focus_fleet()


func _check_free_camera() -> void:
	var rig := _journey.camera_rig
	# Drive render steps explicitly to compare controls at different frame rates.
	rig.set_process(false)
	for track_ship in [false, true]:
		if track_ship:
			rig.follow_ship(_journey.ships[4])
		else:
			rig.focus_fleet()
		var before := rig.camera.global_transform
		rig.pan(Vector3.ZERO)
		_check(rig.camera.global_transform.is_equal_approx(before), "Releasing either focus preserves the camera's view.")
		var eye := rig.camera.global_position
		rig.yaw += 0.4
		rig.pitch = 0.3
		rig.apply_view_bounds()
		_check(rig.camera.global_position.is_equal_approx(eye), "Free look rotates at the eye, without an orbit arm.")
		_check(rig.camera.global_basis.z.y < 0.0, "Free look can face above the horizon.")
	var start := rig.camera.global_position
	var forward := -rig.camera.global_basis.z
	_send_input(_key(KEY_W, true))
	rig._process(0.1)
	var base_distance := rig.camera.global_position.distance_to(start)
	_check((rig.camera.global_position - start).is_equal_approx(forward * rig.pan_speed * 0.1), "Free flight moves forward along the pitched view direction.")
	rig.pan(start - rig.camera.global_position)
	_send_input(_key(KEY_SHIFT, true))
	rig._process(0.1)
	_check(is_equal_approx(rig.camera.global_position.distance_to(start), base_distance * rig.sprint_multiplier), "Shift boosts free-camera movement.")
	_send_input(_key(KEY_SHIFT, false))
	rig.pan(start - rig.camera.global_position)
	_send_input(_stick(JOY_AXIS_TRIGGER_LEFT, 1.0))
	for frame in range(6):
		rig._process(1.0 / 60.0)
	_check(absf(rig.camera.global_position.distance_to(start) - base_distance * rig.sprint_multiplier) < 0.01, "LT boosts free-camera movement independently of frame rate.")
	_send_input(_stick(JOY_AXIS_TRIGGER_LEFT, 0.0))
	rig.pan(start - rig.camera.global_position)
	rig._process(0.1)
	_check(is_equal_approx(rig.camera.global_position.distance_to(start), base_distance), "Releasing sprint restores free-camera speed.")
	_send_input(_key(KEY_W, false))
	var before_zoom := rig.camera.global_transform
	_scroll(MOUSE_BUTTON_WHEEL_UP)
	_check(rig.camera.global_transform.is_equal_approx(before_zoom), "Wheel zoom has no effect in free mode.")
	var relative_eye := rig.camera.global_position - _journey.ships[0].global_position
	_journey.origin.shift_segments(-1)
	rig.apply_view_bounds()
	_check((rig.camera.global_position - _journey.ships[0].global_position).distance_to(relative_eye) < 0.01, "Rebasing preserves the free camera's position relative to the fleet.")
	_journey.origin.shift_segments(1)
	rig.yaw = 0.5
	rig.pitch = -0.52
	rig.focus_fleet()
	start = rig.camera.global_position
	_send_input(_key(KEY_W, true))
	_send_input(_stick(JOY_AXIS_RIGHT_X, 0.8))
	rig._process(0.1)
	var expected_displacement := -rig.camera.global_basis.z * rig.pan_speed * 0.1
	_check((rig.camera.global_position - start).distance_to(expected_displacement) < 0.01, "Simultaneous movement and look release the orbit before turning.")
	_send_input(_key(KEY_W, false))
	_send_input(_stick(JOY_AXIS_RIGHT_X, 0.0))
	rig.yaw = 0.5
	rig.focus_fleet()
	rig.set_process(true)


func _check_free_camera_follow() -> void:
	var rig := _journey.camera_rig
	var fleet := _journey.fleet
	rig.focus_fleet()
	rig.pan(Vector3(120.0, 30.0, 0.0))
	var anchor_start := fleet.anchor.get_global_transform_interpolated().origin
	var offset := rig.camera.global_position - anchor_start
	var orientation := rig.camera.global_basis
	await _frames(roundi(1.5 * _rate))
	rig._process(0.0)
	var anchor_now := fleet.anchor.get_global_transform_interpolated().origin
	_check(anchor_now.z < anchor_start.z - 10.0, "The anchor advances during idle free-camera tracking.")
	_check((rig.camera.global_position - anchor_now).distance_to(offset) < 0.01, "An idle free camera keeps its offset from the anchor.")
	_check(rig.camera.global_basis.is_equal_approx(orientation), "Following anchor translation does not change free-look orientation.")
	# Stop translation, let interpolation settle, and change membership independently.
	_freeze_fixture(true)
	await _frames(2)
	rig._process(0.0)
	var stopped_eye := rig.camera.global_position
	await _frames(20)
	rig._process(0.0)
	_check(rig.camera.global_position.distance_to(stopped_eye) < 0.01, "The free camera stops when the anchor stops.")
	var member := fleet.members[0]
	fleet.unregister_ship(member)
	fleet.advance(0.0)
	fleet.average_focus.reset_physics_interpolation()
	rig._process(0.0)
	_check(rig.camera.global_position.distance_to(stopped_eye) < 0.01, "A membership-driven mean change does not tug an interior free camera.")
	fleet.register_ship(member)
	fleet.advance(0.0)
	fleet.average_focus.reset_physics_interpolation()
	var relative_eye := rig.camera.global_position - fleet.anchor.get_global_transform_interpolated().origin
	_journey.origin.shift_segments(-1)
	rig._process(0.0)
	_check((rig.camera.global_position - fleet.anchor.get_global_transform_interpolated().origin).distance_to(relative_eye) < 0.01, "A free camera retains its anchor offset on the next frame after rebasing.")
	_journey.origin.shift_segments(1)
	rig._process(0.0)
	rig.pan(Vector3.RIGHT * rig.viewing_radius * 3.0)
	var clamped_eye := rig.camera.global_position
	rig._process(0.0)
	_check(rig.camera.global_position.distance_to(clamped_eye) < 0.01, "Sphere clamping persists in the anchor-relative free position.")
	_freeze_fixture(false)
	rig.focus_fleet()


func _check_camera_membership() -> void:
	var rig := _journey.camera_rig
	var fleet := _journey.fleet
	_freeze_fixture(true)
	await _frames(2)
	var anchor_position := fleet.anchor.global_position
	var saved_distance := rig.orbit_distance
	# Test the boundary too: an average-centered clamp can move an anchor-focused camera.
	for camera_mode in [FleetCamera.Mode.FLEET, FleetCamera.Mode.SHIP, FleetCamera.Mode.FREE]:
		rig.orbit_distance = rig.maximum_orbit_distance
		rig.focus_fleet()
		if camera_mode == FleetCamera.Mode.SHIP:
			rig.follow_ship(_journey.ships[4])
		elif camera_mode == FleetCamera.Mode.FREE:
			rig.pan(Vector3.RIGHT * rig.viewing_radius * 3.0)
		rig._process(0.0)
		var view := rig.camera.global_transform
		var mean_before := fleet.average_position
		var member := SHIP_SCENE.instantiate() as Airship
		member.entity_id = _journey.allocate_ship_id()
		_journey.add_child(member)
		member.global_position = anchor_position - (view.origin - anchor_position).normalized() * 6000.0
		_journey.register_ship(member)
		fleet.advance(0.0)
		fleet.average_focus.reset_physics_interpolation()
		rig._process(0.0)
		_check(fleet.average_position.distance_to(mean_before) > 100.0, "Spawn fixture meaningfully shifts the fleet average.")
		_check(rig.camera.global_transform.is_equal_approx(view), "Spawning a player preserves the camera view in mode %d at the sphere edge." % camera_mode)
		member.take_damage(member.maximum_health, Factions.ENEMY)
		_journey._remove_dead_ships()
		fleet.advance(0.0)
		fleet.average_focus.reset_physics_interpolation()
		await _frames(2)
		rig._process(0.0)
		_check(rig.camera.global_transform.is_equal_approx(view), "An unrelated player's death preserves the camera view in mode %d." % camera_mode)
		_check(fleet.anchor.global_position == anchor_position, "Membership changes never reposition the camera anchor.")
		_check(view.origin.distance_to(anchor_position) <= rig.viewing_radius + 0.01, "Each camera mode respects the anchor-centered sphere.")
	rig.orbit_distance = saved_distance
	rig.focus_fleet()
	_freeze_fixture(false)


func _check_zoom() -> void:
	var rig := _journey.camera_rig
	rig.set_process(false)
	var initial_distance := rig.orbit_distance
	for track_ship in [false, true]:
		if track_ship:
			rig.follow_ship(_journey.ships[4])
		else:
			rig.focus_fleet()
		var original_mode := rig.mode
		var original_focus := rig.global_position
		_scroll(MOUSE_BUTTON_WHEEL_UP)
		_check(is_equal_approx(rig.camera.position.z, initial_distance - rig.zoom_step), "Wheel up zooms toward either orbit target.")
		_check(rig.mode == original_mode and rig.global_position == original_focus, "Orbit zoom preserves tracking and focus.")
		_scroll(MOUSE_BUTTON_WHEEL_DOWN)
		_check(is_equal_approx(rig.orbit_distance, initial_distance), "Wheel down reverses orbit zoom.")
	_send_input(_key(KEY_SHIFT, true))
	_scroll(MOUSE_BUTTON_WHEEL_UP)
	_check(is_equal_approx(rig.orbit_distance, initial_distance - rig.zoom_step * rig.sprint_multiplier), "Shift boosts wheel zoom.")
	_send_input(_key(KEY_SHIFT, false))
	rig.orbit_distance = initial_distance
	rig.apply_view_bounds()
	_send_input(_joy_button(JOY_BUTTON_DPAD_UP, true))
	rig._process(0.1)
	_check(is_equal_approx(rig.orbit_distance, initial_distance - rig.zoom_speed * 0.1), "Held controller zoom advances at its configured rate.")
	_send_input(_joy_button(JOY_BUTTON_DPAD_UP, false))
	rig.orbit_distance = initial_distance
	rig.apply_view_bounds()
	_send_input(_stick(JOY_AXIS_TRIGGER_LEFT, 1.0))
	_send_input(_joy_button(JOY_BUTTON_DPAD_DOWN, true))
	for frame in range(6):
		rig._process(1.0 / 60.0)
	_check(absf(rig.orbit_distance - initial_distance - rig.zoom_speed * rig.sprint_multiplier * 0.1) < 0.01, "LT boosts controller zoom independently of frame rate.")
	_send_input(_joy_button(JOY_BUTTON_DPAD_DOWN, false))
	_send_input(_stick(JOY_AXIS_TRIGGER_LEFT, 0.0))
	var stopped_distance := rig.orbit_distance
	rig._process(0.1)
	_check(is_equal_approx(rig.orbit_distance, stopped_distance), "Releasing controller zoom stops it.")
	rig.zoom(-100000.0)
	_check(is_equal_approx(rig.camera.position.z, rig.minimum_orbit_distance), "Orbit zoom stops before passing through the target.")
	rig.zoom(100000.0)
	var center := _journey.fleet.anchor.get_global_transform_interpolated().origin
	_check(rig.camera.global_position.distance_to(center) <= rig.viewing_radius + 0.01, "Zoom out respects the fleet viewing sphere.")
	var bounded_distance := rig.camera.position.z
	_scroll(MOUSE_BUTTON_WHEEL_UP)
	_check(is_equal_approx(rig.camera.position.z, bounded_distance - rig.zoom_step), "Zoom in responds immediately after reaching the sphere boundary.")
	rig.orbit_distance = initial_distance
	rig.focus_fleet()
	rig.set_process(true)


func _check_navigation_debug() -> void:
	var debug := _journey.get_node("FleetAnchor/NavigationDebug") as ShipNavigationDebug
	var ship := _journey.ships[0]
	var random_state := ship.travel.rng.state
	var goal := ship.travel.goal_offset
	_check(not debug.enabled and not debug.visible and not debug.is_processing(), "Navigation debug starts disabled.")
	_send_input(_key(KEY_F3, true))
	_send_input(_key(KEY_F3, false))
	_check(debug.enabled and debug.visible and debug.is_processing(), "F3 enables navigation debug.")
	debug.redraw()
	_send_input(_key(KEY_F3, true))
	_send_input(_key(KEY_F3, false))
	_check(not debug.enabled and not debug.visible and not debug.is_processing(), "F3 hides navigation debug and stops rebuilding geometry.")
	_check(random_state == ship.travel.rng.state and goal == ship.travel.goal_offset, "Navigation debug does not alter travel goals or randomness.")


func _send_input(event: InputEvent) -> void:
	Input.parse_input_event(event.duplicate())
	Input.flush_buffered_events()


func _key(code: Key, pressed: bool) -> InputEventKey:
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.pressed = pressed
	return event


func _joy_button(button: JoyButton, pressed: bool) -> InputEventJoypadButton:
	var event := InputEventJoypadButton.new()
	event.button_index = button
	event.pressed = pressed
	return event


func _scroll(button: MouseButton) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = button
	event.factor = 1.0
	event.pressed = true
	_send_input(event)
	event.pressed = false
	_send_input(event)


func _check_initial_surroundings() -> void:
	var sides := Vector4.ZERO
	var anchor := _journey.fleet.anchor.global_position
	for island in _journey.island_spawner.obstacles:
		var offset := island.global_position - anchor
		if offset.x < -_journey.fleet.formation_extent.x * 2.0:
			sides.x += 1.0
		if offset.x > _journey.fleet.formation_extent.x * 2.0:
			sides.y += 1.0
		if offset.z < -_journey.fleet.formation_extent.z:
			sides.z += 1.0
		if offset.z > _journey.fleet.formation_extent.z:
			sides.w += 1.0
		_check(island.global_position.y + island.bottom_offset > _journey.terrain.profile.maximum_height(), "Floating islands remain above the terrain's maximum height.")
	_check(sides.x > 0.0 and sides.y > 0.0 and sides.z > 0.0 and sides.w > 0.0, "The starting field has scenery well to both sides, ahead, and behind.")
	var query := PhysicsShapeQueryParameters3D.new()
	query.collision_mask = 2
	for ship in _journey.ships:
		query.shape = ship.hull_collider.shape
		query.transform = ship.hull_collider.global_transform
		_check(ship.get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty(), "Initial scenery leaves the starting ships clear of island solids.")


func _capture_surroundings() -> void:
	var rig := _journey.camera_rig
	var saved_distance := rig.orbit_distance
	var saved_yaw := rig.yaw
	rig.orbit_distance = 6000.0
	await _frames(2)
	await _capture("open-field")
	rig.yaw += PI
	await _frames(2)
	await _capture("field-behind")
	rig.orbit_distance = saved_distance
	rig.yaw = saved_yaw
	await _frames(2)


func _check_rebase() -> void:
	var before := _journey.anchor_route_position()
	var first := _journey.ships[0]
	var position := RoutePosition.from_scene(first.position.z, _journey.origin.segment)
	var velocity := first.linear_velocity
	var goal := first.travel.goal_offset
	var relative := first.global_position - _journey.ships[1].global_position
	var rng_state := _journey.island_spawner.rng.state
	var ship_rng := first.travel.rng.state
	var camera_mode := _journey.camera_rig.mode
	var progress_before := _journey.progression.distance
	var terrain_chunk: MeshInstance3D = _journey.terrain.chunks.values()[0]
	var terrain_relative := terrain_chunk.global_position - _journey.fleet.anchor.global_position
	_journey.origin.shift_segments(-1)
	_journey.progression.update(_journey.anchor_route_position())
	_check(is_equal_approx(progress_before, _journey.progression.distance), "Origin shifts do not advance the numeric journey progression.")
	var after := _journey.anchor_route_position()
	var shifted_position := RoutePosition.from_scene(first.position.z, _journey.origin.segment)
	_check(before.segment == after.segment and absf(before.offset - after.offset) < 0.01, "Rebasing preserves anchor progression.")
	_check(position.segment == shifted_position.segment and absf(position.offset - shifted_position.offset) < 0.01, "Rebasing preserves ship logical position.")
	_check(first.linear_velocity == velocity and first.travel.goal_offset == goal, "Rebasing preserves velocity and relative goals.")
	_check(relative.distance_to(first.global_position - _journey.ships[1].global_position) < 0.01, "Rebasing preserves ship separation.")
	_check(rng_state == _journey.island_spawner.rng.state and ship_rng == first.travel.rng.state, "Rebasing does not consume randomness.")
	_check(camera_mode == _journey.camera_rig.mode, "Rebasing retains camera mode.")
	_check(terrain_relative.distance_to(terrain_chunk.global_position - _journey.fleet.anchor.global_position) < 0.01, "Rebasing preserves terrain relative to the fleet.")


func _check_spawns() -> void:
	var spawner := _journey.island_spawner
	spawner.update_region(_journey.anchor_route_position())
	var count := spawner.records.size()
	var state := spawner.rng.state
	spawner.update_region(_journey.anchor_route_position())
	_check(count == spawner.records.size() and state == spawner.rng.state, "Repeated streaming updates do not duplicate islands.")
	var ids: Dictionary[int, bool] = {}
	for record in spawner.records:
		_check(not ids.has(record.entity_id), "Island IDs remain unique.")
		ids[record.entity_id] = true


func _check_long_travel() -> void:
	var first_goal := _journey.ships[0].travel.goals_reached
	for batch in range(12):
		await _frames(20 * _rate)
		for ship in _journey.ships:
			_check(ship.global_position.is_finite() and ship.linear_velocity.is_finite(), "Ship positions and velocities stay finite.")
			_check(absf(ship.visual_root.rotation.x) <= deg_to_rad(ship.pitch_limit_degrees) + 0.001, "Pitch remains bounded.")
			_check(absf(ship.visual_root.rotation.z) <= deg_to_rad(ship.bank_limit_degrees) + 0.001, "Bank remains bounded.")
			var relative := (ship.global_position - _journey.fleet.anchor.global_position) / _journey.fleet.formation_extent
			_check(relative.length() < 1.25, "Ships stay within reach of the formation.")
	_check(_journey.origin.shift_count >= 2, "Long travel crosses multiple origins.")
	var spawner := _journey.island_spawner
	var maximum_loaded := ceili((spawner.look_ahead + spawner.keep_behind) / spawner.minimum_spacing) + 2
	_check(spawner.active.size() <= maximum_loaded, "Loaded island count stays bounded by the streaming window.")
	_check(_journey.island_spawner.records.size() > _journey.island_spawner.active.size(), "Passed islands retain their records after unloading.")
	_check(_journey.ships[0].travel.goals_reached > first_goal + 2, "Ships repeatedly reach moving navigation goals.")
	_check_spawns()
	print("Long travel: ", _journey.origin.shift_count, " shifts; ", _journey.island_spawner.records.size(), " records; ", _journey.island_spawner.active.size(), " live islands.")
	# A fresh origin near an enormous route position keeps scene transforms small.
	_set_distant_origin()
	await _frames(3 * _rate)
	_check_rebase()
	_check_spawns()


func _check_slowdown() -> void:
	_freeze_fixture(true)
	var fleet := _journey.fleet
	fleet.anchor.position.z -= 600.0
	for tick in range(4 * _rate):
		fleet.advance(_delta)
	_check(fleet.speed < fleet.cruise_speed * 0.5, "The anchor slows when the fleet is held behind.")
	var gap := fleet.anchor.position.distance_to(fleet.average_position)
	_freeze_fixture(false)
	await _frames(40 * _rate)
	_check(fleet.anchor.position.distance_to(fleet.average_position) < gap * 0.6, "Ships recover after being held behind.")
	_check(fleet.speed > fleet.cruise_speed * 0.8, "The anchor recovers cruising speed.")


func _check_membership() -> void:
	var ship := _journey.ships[0]
	_journey.camera_rig.follow_ship(ship)
	var anchor_position := _journey.fleet.anchor.position
	_journey.unregister_ship(ship)
	_check(_journey.fleet.anchor.position == anchor_position, "Removing a member cannot teleport the anchor.")
	_journey.register_ship(ship)
	_check(_journey.fleet.members.count(ship) == 1 and _journey.fleet.anchor.position == anchor_position, "Re-registering a live ship preserves identity and progression.")
	_journey.unregister_ship(ship)
	ship.queue_free()
	await _frames(3)
	_check(_journey.camera_rig.mode == FleetCamera.Mode.FLEET, "A destroyed camera target falls back to fleet tracking.")
	_journey.camera_rig._process(0.0)
	_check(_journey.camera_rig.global_position.is_equal_approx(_journey.fleet.anchor.get_global_transform_interpolated().origin), "A destroyed camera target restores the persistent anchor focus.")
	while _journey.ships.size() > 1:
		var remaining: Airship = _journey.ships.back()
		_journey.unregister_ship(remaining)
		remaining.queue_free()
	var single_start := _journey.anchor_route_position()
	await _frames(roundi(1.5 * _rate))
	_check(_journey.fleet.members.size() == 1 and _journey.anchor_route_position().compare(single_start) < 0, "A single remaining ship keeps the fleet moving.")
	var last_ship := _journey.ships[0]
	_journey.unregister_ship(last_ship)
	last_ship.queue_free()
	await _frames(3)
	anchor_position = _journey.fleet.anchor.position
	await _frames(roundi(0.5 * _rate))
	_check(_journey.fleet.speed == 0.0 and _journey.fleet.anchor.position == anchor_position, "An empty fleet stops the anchor safely.")
	_check(_journey.camera_rig.global_position.is_equal_approx(anchor_position), "The camera keeps its anchor focus when no ships remain.")


func _check_encounters() -> void:
	var setups := [
		[Vector3(0, 0, 180), Vector3(0, 0, -180), Vector3(0, 0, -80), Vector3(0, 0, 80)],
		[Vector3(-180, 0, 0), Vector3(0, 0, 180), Vector3(80, 0, 0), Vector3(0, 0, -80)],
		[Vector3(0, 0, 140), Vector3(0, 0, -40), Vector3(0, 0, -120), Vector3(0, 0, -60)],
		[Vector3(-28.0, 0, 0), Vector3(28.0, 0, 0), Vector3(0, 0, -80), Vector3(0, 0, -80)]
	]
	for setup_index in range(setups.size()):
		var setup: Array = setups[setup_index]
		var pair: Array[Airship] = []
		for index in range(2):
			var ship := SHIP_SCENE.instantiate() as Airship
			ship.entity_id = 101 + index
			ship.faction = Factions.NEUTRAL
			_journey.add_child(ship)
			ship.global_position = _journey.fleet.anchor.position + setup[index]
			ship.set_preferred_velocity(setup[index + 2])
			ship.rotation.y = atan2(-ship.preferred_velocity.x, -ship.preferred_velocity.z)
			_journey.register_ship(ship)
			ship.reset_physics_interpolation()
			pair.append(ship)
		var starts: Array[Vector3] = [pair[0].position, pair[1].position]
		var minimum_clearance: float = INF
		for tick in range(10 * _rate):
			await physics_frame
			var first_axis := pair[0].basis.z * pair[0].hull_half_segment
			var second_axis := pair[1].basis.z * pair[1].hull_half_segment
			var closest := Geometry3D.get_closest_points_between_segments(pair[0].position - first_axis, pair[0].position + first_axis, pair[1].position - second_axis, pair[1].position + second_axis)
			minimum_clearance = minf(minimum_clearance, closest[0].distance_to(closest[1]) - pair[0].hull_radius - pair[1].hull_radius)
		_check(minimum_clearance > -3.0, "Encounter %d avoids sustained hull overlap (clearance %.3f)." % [setup_index, minimum_clearance])
		for index in range(2):
			_check((pair[index].position - starts[index]).dot(pair[index].preferred_velocity.normalized()) > 300.0, "Encounter %d resolves without deadlock." % setup_index)
			_journey.unregister_ship(pair[index])
			pair[index].queue_free()
		await _frames(2)
		print("Encounter ", setup_index, ": minimum hull clearance ", minimum_clearance)


func _stick(axis: JoyAxis, value: float) -> InputEventJoypadMotion:
	var event := InputEventJoypadMotion.new()
	event.device = 0
	event.axis = axis
	event.axis_value = value
	return event


func _set_distant_origin() -> void:
	var difference: int = -9007199254740995 - _journey.origin.segment
	_journey.origin.segment += difference
	for record in _journey.island_spawner.records:
		record.route_position.segment += difference
	_journey.island_spawner.next_position.segment += difference
	_journey.progression.update(_journey.anchor_route_position())
	_journey.terrain.update_region(_journey.fleet.anchor.global_position.x, _journey.anchor_route_position(), _journey.camera_rig.camera.global_position)
	_journey.terrain.build_pending(10000)


func _frames(count: int) -> void:
	for frame in range(count):
		await physics_frame


func _capture(label: String) -> void:
	if not _visual:
		return
	var directory := OS.get_environment("AERWYTH_CAPTURE_DIR")
	_check(not directory.is_empty(), "Visual validation needs an external capture directory.")
	if directory.is_empty():
		return
	await RenderingServer.frame_post_draw
	var result := root.get_texture().get_image().save_png(directory.path_join(label + ".png"))
	_check(result == OK, "Rendered capture was written: " + label)


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _freeze_fixture(frozen: bool) -> void:
	_journey.set_physics_process(not frozen)
	for ship in _journey.ships:
		ship.freeze = frozen
