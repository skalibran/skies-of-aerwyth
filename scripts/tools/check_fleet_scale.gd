extends SceneTree

const JOURNEY_SCENE := preload("res://scenes/world/journey.tscn")
const SHIP_SCENE := preload("res://scenes/ships/ship.tscn")
const SHIP_COUNT: int = 128
const ROUTE_OBSTACLE_ID: int = 200000

var _journey: Journey
var _failures: Array[String] = []
var _visual: bool = false
var _detoured_ships: Dictionary[int, bool] = {}


func _initialize() -> void:
	_visual = "--visual" in OS.get_cmdline_user_args()
	_run.call_deferred()


func _run() -> void:
	_journey = JOURNEY_SCENE.instantiate() as Journey
	root.add_child(_journey)
	_journey.set_physics_process(false)
	_build_fleet()
	_rebuild_starting_scenery()
	_add_route_obstacle()
	var rig := _journey.camera_rig
	rig.orbit_distance = 480.0
	rig.focus_fleet()
	var timings := PackedFloat64Array()
	var starting_route := _journey.anchor_route_position()
	for tick in range(1800):
		await physics_frame
		var started := Time.get_ticks_usec()
		_journey.step_simulation(1.0 / 60.0)
		if tick >= 120:
			timings.append(float(Time.get_ticks_usec() - started) / 1000.0)
		if tick % 120 == 0:
			_check_formation()
		if tick == 900:
			var before := _journey.anchor_route_position()
			_journey.origin.shift_segments(-1)
			var after := _journey.anchor_route_position()
			_check(absf(after.to_scene(before.segment) - before.offset) < 0.001, "Rebasing the large fleet preserves progression within local float precision.")
	_check(_journey.ships.size() == SHIP_COUNT, "All 128 ships remain registered.")
	_check(_journey.anchor_route_position().compare(starting_route.advanced(-180.0)) < 0, "The large fleet sustains forward progress.")
	var total_goals: int = 0
	for ship in _journey.ships:
		total_goals += ship.travel.goals_reached
	_check(total_goals > SHIP_COUNT, "Large-fleet ships keep reaching nearby destinations.")
	_check(_detoured_ships.size() >= 5, "Multiple ships in the large fleet navigate around an island.")
	_check_scenery()
	if _visual:
		await _capture("fleet-128")
		rig.zoom(10000.0)
		await _capture("fleet-128-wide")
		rig.follow_ship(_journey.ships.back())
		rig.zoom(35.0 - rig.camera.position.z)
		await _capture("fleet-128-ship")
	timings.sort()
	print("128 ships, scripted simulation step: median %.3f ms, p95 %.3f ms; %d goals reached; %d ships detoured." % [timings[timings.size() / 2], timings[int(timings.size() * 0.95)], total_goals, _detoured_ships.size()])
	_journey.queue_free()
	await process_frame
	for failure in _failures:
		printerr("FAIL: ", failure)
	if _failures.is_empty():
		print("PASS: 128-ship fleet scale check.")
	quit(0 if _failures.is_empty() else 1)


func _build_fleet() -> void:
	for ship in _journey.ships.duplicate():
		_journey.unregister_ship(ship)
		ship.queue_free()
	# Four altitude layers exercise a volume rather than a shallow starting sheet.
	for index in range(SHIP_COUNT):
		var ship := SHIP_SCENE.instantiate() as Airship
		ship.entity_id = 1000 + index
		var offset := Vector3((index % 8 - 3.5) * 32.0, ((index / 8) % 4 - 1.5) * 42.0, (index / 32 - 1.5) * 42.0)
		_journey.add_child(ship)
		ship.global_position = _journey.fleet.anchor.global_position + offset
		_journey.register_ship(ship)
		ship.reset_physics_interpolation()


func _rebuild_starting_scenery() -> void:
	# Startup clearance must use the replacement fleet's positions, not the nine
	# ships in the authored scene that were present during Journey._ready().
	var spawner := _journey.island_spawner
	for island in spawner.obstacles:
		_journey.origin.unregister_root(island)
		island.queue_free()
	spawner.obstacles.clear()
	spawner.active.clear()
	spawner.records.clear()
	spawner.initialize(_journey.anchor_route_position())


func _add_route_obstacle() -> void:
	var record := IslandRecord.new()
	record.entity_id = ROUTE_OBSTACLE_ID
	record.route_position = _journey.anchor_route_position().advanced(-160.0)
	record.lateral_position = 0.0
	record.altitude = 15.0
	record.radius = 30.0
	record.depth = 30.0
	_journey.island_spawner.records.insert(0, record)
	_journey.island_spawner._load_record(record)


func _check_formation() -> void:
	var extent := _journey.fleet.formation_extent
	var query := PhysicsShapeQueryParameters3D.new()
	var probe := CapsuleShape3D.new()
	probe.radius = 2.05
	probe.height = 9.7
	query.shape = probe
	query.collision_mask = 2
	for ship in _journey.ships:
		_check(ship.global_position.is_finite() and ship.velocity.is_finite(), "Large-fleet movement stays finite.")
		var relative := ship.global_position - _journey.fleet.anchor.global_position
		_check((relative / extent).length() < 1.25, "Ships stay within reach of the expanded formation.")
		_check((ship.travel.goal_offset / extent).length() < 1.25, "Travel goals stay within the formation while detours temporarily increase their distance.")
		if ship.island_navigation.has_waypoint():
			_detoured_ships[ship.entity_id] = true
		query.transform = ship.hull_collider.global_transform
		_check(ship.get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty(), "Large-fleet hulls do not penetrate island solids.")
	var rig := _journey.camera_rig
	var center := _journey.fleet.average_focus.get_global_transform_interpolated().origin
	_check(rig.camera.global_position.distance_to(center) <= rig.viewing_radius + 1.0, "The large-fleet camera stays inside its viewing sphere.")


func _check_scenery() -> void:
	var spawner := _journey.island_spawner
	_check(spawner.look_ahead >= _journey.camera_rig.viewing_radius + _journey.fleet.formation_extent.z, "Scenery loads ahead of the expanded viewing sphere.")
	_check(spawner.keep_behind >= _journey.camera_rig.viewing_radius + _journey.fleet.formation_extent.z, "Scenery is retained behind the expanded viewing sphere.")
	for record in spawner.records:
		_check(absf(record.lateral_position) <= spawner.field_half_width, "Islands remain within the authored field width.")
	var inside_route: int = 0
	for record in spawner.records:
		if record.entity_id != ROUTE_OBSTACLE_ID and absf(record.lateral_position) < _journey.fleet.formation_extent.x:
			inside_route += 1
	_check(inside_route > 0, "The route no longer excludes islands from the fleet's path.")


func _capture(label: String) -> void:
	var directory := OS.get_environment("AERWYTH_CAPTURE_DIR")
	_check(not directory.is_empty(), "Rendering checks need an external capture directory.")
	if directory.is_empty():
		return
	await RenderingServer.frame_post_draw
	_check(root.get_texture().get_image().save_png(directory.path_join(label + ".png")) == OK, "Fleet capture was written.")


func _check(condition: bool, message: String) -> void:
	if not condition and message not in _failures:
		_failures.append(message)
