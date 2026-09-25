extends SceneTree

const JOURNEY_SCENE := preload("res://scenes/world/journey.tscn")
const SHIP_SCENE := preload("res://scenes/ships/ship.tscn")

var _journey: Journey
var _failures: Array[String] = []
var _visual: bool = false


func _initialize() -> void:
	_visual = "--visual" in OS.get_cmdline_user_args()
	_run.call_deferred()


func _run() -> void:
	await _encounter("head_on", 0.0, false, false)
	await _encounter("cluster", 0.0, true, false)
	await _encounter("upper_cap", 16.0, false, false)
	await _encounter("above", 35.0, false, false, false)
	await _encounter("below", -45.0, false, false, false)
	await _encounter("moving_goal", 0.0, false, true)
	await _unload_during_detour()
	for failure in _failures:
		printerr("FAIL: ", failure)
	if _failures.is_empty():
		print("PASS: island navigation, collision, rebasing, and unloading checks.")
	quit(0 if _failures.is_empty() else 1)


func _create_journey() -> void:
	_journey = JOURNEY_SCENE.instantiate() as Journey
	root.add_child(_journey)
	for ship in _journey.ships.duplicate():
		_journey.unregister_ship(ship)
		ship.queue_free()
	var spawner := _journey.island_spawner
	for island in spawner.obstacles:
		_journey.origin.unregister_root(island)
		island.queue_free()
	spawner.obstacles.clear()
	spawner.active.clear()
	spawner.records.clear()
	spawner.next_position = RoutePosition.new(-1000, 0.0)


func _add_island(id: int, position: Vector3) -> FloatingIsland:
	var record := IslandRecord.new()
	record.entity_id = id
	record.route_position = RoutePosition.from_scene(position.z, _journey.origin.segment)
	record.lateral_position = position.x
	record.altitude = position.y
	record.radius = 22.0
	record.depth = 25.0
	_journey.island_spawner.records.append(record)
	_journey.island_spawner._load_record(record)
	return _journey.island_spawner.active[id]


func _add_ship(height: float, friendly: bool = false) -> Airship:
	var ship := SHIP_SCENE.instantiate() as Airship
	ship.entity_id = 9001
	ship.faction = Airship.Faction.FRIENDLY if friendly else Airship.Faction.NEUTRAL
	_journey.add_child(ship)
	ship.global_position = Vector3(0.0, height, 90.0)
	_journey.register_ship(ship)
	ship.set_preferred_velocity(Vector3.FORWARD * 9.0)
	if friendly:
		ship.travel.goal_offset = Vector3.ZERO
	ship.reset_physics_interpolation()
	_journey.camera_rig.follow_ship(ship)
	_journey.camera_rig.orbit_distance = 130.0
	return ship


func _encounter(label: String, height: float, cluster: bool, friendly: bool, blocked: bool = true) -> void:
	_create_journey()
	var island := _add_island(5001, Vector3(-15.0 if cluster else 0.0, 10.0, 0.0))
	if cluster:
		_add_island(5002, Vector3(18.0, 10.0, -12.0))
	var ship := _add_ship(height, friendly)
	await physics_frame
	await physics_frame
	_check(island.collider.shape is CapsuleShape3D, label + ": islands use capsule colliders.")
	if blocked:
		var contact := ship.move_and_collide(Vector3(0.0, 0.0, -180.0), true)
		_check(contact != null and contact.get_collider() is StaticBody3D, label + ": the capsule island collider blocks direct physical travel.")
	var query := PhysicsShapeQueryParameters3D.new()
	var probe := CapsuleShape3D.new()
	probe.radius = ship.hull_radius - 0.15
	probe.height = ship.hull_half_segment * 2.0 + ship.hull_radius * 2.0 - 0.3
	query.shape = probe
	query.collision_mask = 2
	var detoured := false
	var rebased := false
	var passed := false
	var lateral_motion: float = 0.0
	for tick in range(3600):
		await physics_frame
		lateral_motion = maxf(lateral_motion, absf(ship.global_position.x))
		if ship.island_navigation.has_waypoint():
			detoured = true
			if not rebased:
				var before := ship.island_navigation.waypoint_position() - ship.global_position
				_journey.origin.shift_segments(-1)
				var after := ship.island_navigation.waypoint_position() - ship.global_position
				_check(before.distance_to(after) < 0.001, label + ": detour waypoint survives rebasing.")
				rebased = true
		if tick % 10 == 0:
			query.transform = ship.hull_collider.global_transform
			_check(ship.get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty(), label + ": the ship hull does not penetrate an island.")
		if _visual and tick == 600:
			await _capture(label)
		if ship.global_position.z < island.global_position.z - 70.0:
			passed = true
			break
	_check(passed, label + ": the ship passes the obstacle instead of stalling.")
	if blocked:
		_check(detoured and lateral_motion > 25.0, label + ": the blocked path produces a lateral detour.")
	else:
		_check(not detoured and lateral_motion < 0.1, label + ": clear altitude does not require a lateral detour.")
	print(label, ": passed=", passed, ", detoured=", detoured, ", maximum lateral motion=", lateral_motion, ", final position=", ship.global_position)
	_journey.queue_free()
	await process_frame


func _unload_during_detour() -> void:
	_create_journey()
	var island := _add_island(5001, Vector3(0.0, 10.0, 0.0))
	var ship := _add_ship(0.0)
	for tick in range(30):
		await physics_frame
	_check(ship.island_navigation.has_waypoint(), "Unloading fixture starts with an active detour.")
	_journey.island_spawner.obstacles.erase(island)
	_journey.island_spawner.active.erase(5001)
	_journey.origin.unregister_root(island)
	island.queue_free()
	for tick in range(10):
		await physics_frame
	_check(not ship.island_navigation.has_waypoint(), "Unloading an obstacle clears its detour reference.")
	_journey.queue_free()
	await process_frame


func _capture(label: String) -> void:
	var directory := OS.get_environment("AERWYTH_CAPTURE_DIR")
	_check(not directory.is_empty(), "Rendered checks require an external capture directory.")
	if directory.is_empty():
		return
	await RenderingServer.frame_post_draw
	_check(root.get_texture().get_image().save_png(directory.path_join("island-" + label + ".png")) == OK, "Island capture was written.")


func _check(condition: bool, message: String) -> void:
	if not condition and message not in _failures:
		_failures.append(message)
