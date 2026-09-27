extends SceneTree

const KESTREL := preload("res://scenes/ships/kestrel.tscn")
const ISLAND := preload("res://scenes/islands/island.tscn")
var _failures: Array[String] = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var fixture := Node3D.new()
	root.add_child(fixture)
	var fleet := FleetController.new()
	fixture.add_child(fleet)
	fleet.marker = Node3D.new()
	fixture.add_child(fleet.marker)
	fleet.minimum_radius = 400.0
	fleet.initialize()
	fleet.in_combat = true
	var ship := KESTREL.instantiate() as Airship
	ship.entity_id = 17
	ship.position = Vector3(-230, 0, 0)
	ship.rotation.y = -PI * 0.5
	fixture.add_child(ship)
	fleet.register_ship(ship)
	ship.navigation.initialize(fleet, ship)
	var target := KESTREL.instantiate() as Airship
	target.faction = Factions.ENEMY
	target.position = Vector3(230, 0, 0)
	target.freeze = true
	fixture.add_child(target)
	var island := ISLAND.instantiate() as FloatingIsland
	fixture.add_child(island)
	var record := IslandRecord.new()
	record.route_position = RoutePosition.new()
	record.radius = 50
	record.depth = 100
	record.altitude = 60
	island.configure(record, 0)
	var islands: Array[FloatingIsland] = [island]
	var dt := 1.0 / Engine.physics_ticks_per_second
	ship.linear_velocity = Vector3.LEFT * 300.0
	fleet.velocity = Vector3.FORWARD * 25.0
	ship.navigation.goal_offset = Vector3.RIGHT * 200.0
	var lookahead_request := ship.navigation._goal_velocity(ship, fleet.marker.position + ship.navigation.goal_offset)
	var lookahead := lookahead_request.length() * ship.navigation._horizon(ship)
	_check(ShipNavigation.search_radius(ship, island.navigation_radius) >= lookahead + island.navigation_radius, "Island filtering covers the steering horizon after a contact exceeds propulsion speed.")
	ship.position.x = -6000.0
	_check(ShipNavigation.search_radius(ship, island.navigation_radius) > 6200.0, "Island filtering covers a displaced hull's retained goal as well as newly sampled inward goals.")
	ship.position.x = -230.0
	ship.linear_velocity = Vector3.ZERO
	fleet.velocity = Vector3.ZERO
	_check(not ship.navigation._path_clear(ship, target.position, islands), "Solid island geometry rejects a direct route.")
	_check(ship.navigation._path_clear(ship, target.position + Vector3.UP * 600.0, islands), "A rising segment can clear the island before entering its horizontal footprint.")
	_check(ship.navigation._path_clear(ship, target.position + Vector3.DOWN * 600.0, islands), "A descending segment can pass below the island before entering its footprint.")
	ship.position.y = 300
	_check(ship.navigation._path_clear(ship, target.position + Vector3.UP * 300, islands), "A route above island collision remains available.")
	ship.position.y = -300
	_check(ship.navigation._path_clear(ship, target.position - Vector3.UP * 300, islands), "A route below island collision remains available.")
	ship.position.y = 0
	for tick in range(45 * Engine.physics_ticks_per_second):
		await physics_frame
		ship.prepare_navigation(dt, [ship, target], fleet)
		ship.apply_movement_forces(dt, Vector3.ZERO, islands)
		_check(ship.navigation.goal_offset.length() <= ship.navigation.usable_radius(ship) + 0.01, "Obstacle choices also stay inside the fleet sphere.")
		_check(ship.position.distance_to(island.position) > island.navigation_radius + ship.hull_radius, "The moving hull stays outside island solids.")
		if tick == 15 * Engine.physics_ticks_per_second:
			var offset := ship.navigation.goal_offset
			var random_state := ship.navigation.rng.state
			var request := ship.navigation_velocity
			ship.position.z += 10240
			target.position.z += 10240
			island.position.z += 10240
			fleet.marker.position.z += 10240
			ship.apply_movement_forces(dt, Vector3.ZERO, islands)
			_check(ship.navigation.goal_offset.distance_to(offset) < 0.01 and ship.navigation.rng.state == random_state and ship.navigation_velocity.distance_to(request) < 0.02, "Rebasing preserves obstacle-relative route choices.")
	_check(ship.position.x > -130, "A bounded obstacle route makes progress toward the selected target.")
	# An enclosing obstruction offers no legal outward route. The ship must wait.
	ship.freeze = true
	ship.position = fleet.marker.position
	island.position = fleet.marker.position
	island.navigation_radius = 1000
	island.bottom_offset = -1000
	island.top_offset = 1000
	ship.navigation._goal_age = INF
	ship.prepare_navigation(dt, [ship], fleet, false)
	fleet.prepare_step(dt)
	ship.navigation.plan(ship, islands)
	var stopped_at := fleet.marker.position
	fleet.advance(dt)
	_check(fleet.marker.position == stopped_at and ship.navigation.safe_marker_speed == 0.0, "A completely obstructed friendly route stops marker travel on the same tick.")
	ship.apply_movement_forces(dt, Vector3.ZERO, islands)
	# Test steering directly because a frozen validation body does not submit forces.
	var request := ship.navigation.steer(ship, Vector3.ZERO, islands)
	_check(ship.navigation.goal_offset.length() < fleet.radius, "Even an obstructed fleet retains bounded destinations.")
	_check(ship.navigation.blocked and request == Vector3.ZERO, "An enclosing obstruction stops movement instead of authoring a route outside the sphere.")
	island.queue_free()
	await process_frame
	islands.clear()
	ship.navigation._goal_age = INF
	fleet.prepare_step(dt)
	ship.navigation.plan(ship, islands)
	fleet.advance(dt)
	request = ship.navigation.steer(ship, Vector3.ZERO, islands)
	_check(not ship.navigation.blocked and request.is_finite(), "Unloading an island leaves no stale route references.")
	_check(fleet.speed > 0.0, "Clearing a complete obstruction resumes marker travel without a separate return state.")
	fixture.queue_free()
	await process_frame
	_check_route_pacing()
	for failure in _failures:
		printerr("FAIL: ", failure)
	if _failures.is_empty():
		print("PASS: bounded obstacle navigation, intended-speed detours, safe slowing, blockage recovery, altitude routes, rebasing, and unloading.")
	quit(0 if _failures.is_empty() else 1)


func _check_route_pacing() -> void:
	var fixture := Node3D.new()
	root.add_child(fixture)
	var fleet := FleetController.new()
	fixture.add_child(fleet)
	fleet.marker = Node3D.new()
	fixture.add_child(fleet.marker)
	fleet.minimum_radius = 400.0
	# Keep the waypoint short so this fixture isolates world-motion lookahead.
	fleet.local_step = 50.0
	var ship := KESTREL.instantiate() as Airship
	ship.entity_id = 17
	ship.freeze = true
	fixture.add_child(ship)
	fleet.register_ship(ship)
	fleet.initialize()
	ship.navigation.initialize(fleet, ship)
	var island := ISLAND.instantiate() as FloatingIsland
	fixture.add_child(island)
	var record := IslandRecord.new()
	record.route_position = RoutePosition.new()
	record.radius = 50.0
	record.depth = 100.0
	record.altitude = 60.0
	island.configure(record, 0)
	island.position.z = -150.0
	var islands: Array[FloatingIsland] = [island]
	var dt := 1.0 / Engine.physics_ticks_per_second
	ship.linear_velocity = Vector3.FORWARD * fleet.cruise_speed
	_check(ship.navigation._path_clear(ship, Vector3.FORWARD * fleet.local_step, islands), "The regression fixture has a clear short local waypoint.")
	_check(not ship.navigation._course_clear(ship, Vector3.FORWARD * (fleet.cruise_speed + fleet.local_speed), islands), "That waypoint's combined travel course intersects the island.")
	for sample in range(10):
		fleet.prepare_step(dt)
		ship.navigation.plan(ship, islands)
		_check(not ship.navigation.blocked and ship.navigation.safe_marker_speed > 0.0 and ship.navigation.safe_marker_speed < fleet.cruise_speed, "A viable slower route reports a speed allowance without declaring complete blockage.")
		_check(fleet.velocity == Vector3.ZERO and fleet.requested_speed == fleet.cruise_speed, "Repeated planning uses intended cruise even while the marker is stopped.")
	fleet.speed = fleet.cruise_speed
	fleet.advance(dt)
	_check(fleet.speed == ship.navigation.safe_marker_speed, "The marker honors the friendly route's speed allowance immediately.")
	var request := ship.navigation.steer(ship, Vector3.ZERO, islands)
	_check(ship.navigation._course_clear(ship, request, islands), "The actual slower course remains clear after marker translation.")
	var offset := ship.navigation.goal_offset
	var route_speed := ship.navigation.safe_marker_speed
	for node in [ship, island, fleet.marker]:
		node.position.z += 10240.0
	var rebased := ship.navigation.steer(ship, Vector3.ZERO, islands)
	_check(ship.navigation.goal_offset == offset and ship.navigation.safe_marker_speed == route_speed and request.distance_to(rebased) < 0.02, "Rebasing preserves the slower detour and its pace allowance.")
	island.position.z -= 1000.0
	fleet.prepare_step(dt)
	ship.navigation.plan(ship, islands)
	_check(ship.navigation.safe_marker_speed == fleet.cruise_speed, "An open intended course releases the slowdown without waiting for current speed to recover.")
	fixture.free()


func _check(condition: bool, message: String) -> void:
	if not condition and message not in _failures:
		_failures.append(message)
