extends SceneTree

const JOURNEY := preload("res://scenes/world/journey.tscn")
const ISLAND := preload("res://scenes/islands/island.tscn")
const KESTREL := preload("res://resources/ships/kestrel.tres")
const BATCH_SIZE: int = 12
const RUN_SECONDS: int = 120

var _failures: Array[String] = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	await _check_batch()
	await _check_detour_lifetime()
	for failure in _failures:
		printerr("FAIL: ", failure)
	if _failures.is_empty():
		print("PASS: bounded spawn queue, simultaneous friendly/enemy isle arrivals, native movement, separation, continuous fleet travel, contained final goals, detour rebasing and unloading.")
	quit(0 if _failures.is_empty() else 1)


func _check_batch() -> void:
	var journey := JOURNEY.instantiate() as Journey
	journey.combat_enabled = false
	journey.encounters.enabled = false
	root.add_child(journey)
	journey.set_physics_process(false)
	journey.profile_steps = true
	journey._spawn_rng.seed = 71937
	journey._enemy_spawn_rng.seed = 71937
	var spawned: Array[Airship] = []
	journey.ship_spawned.connect(func(ship: Airship) -> void: spawned.append(ship))
	var failures: Array[ShipDefinition] = []
	journey.ship_spawn_failed.connect(func(definition: ShipDefinition) -> void: failures.append(definition))
	var rate := Engine.physics_ticks_per_second
	var delta := 1.0 / rate
	await physics_frame
	for index in range(BATCH_SIZE):
		journey.request_ship_spawn(KESTREL)
	var times: Array[int] = []
	var navigation_times: Array[int] = []
	var entered: Dictionary[int, bool] = {}
	var requested_enemies: int = 0
	var initial := journey.fleet.marker.global_position
	var maximum_stalled: int = 0
	for tick in range(RUN_SECONDS * rate):
		var previous_count := spawned.size()
		var began := Time.get_ticks_usec()
		journey.step_simulation(delta)
		times.append(Time.get_ticks_usec() - began)
		navigation_times.append(journey.step_timings_usec[Journey.StepPhase.NAVIGATION])
		_check(spawned.size() - previous_count <= journey.friendly_spawns_per_tick, "Picker instantiation honors the per-tick budget.")
		# Enemy waves have their own existing director budget. Add this fixture's
		# ships outside the measured picker tick, retaining normal placement checks.
		if requested_enemies < BATCH_SIZE:
			if journey.try_spawn_enemy(KESTREL):
				requested_enemies += 1
		var stalled: int = 0
		for ship in spawned:
			_check(ship.navigation.goal_offset.length() <= ship.navigation.usable_radius(ship) + 0.01, "Final destinations remain inside the fleet sphere during detours.")
			if ship.global_position.distance_to(journey.fleet.marker.global_position) <= ship.navigation.usable_radius(ship):
				entered[ship.entity_id] = true
			elif ship.linear_velocity.length() < 1.0:
				stalled += 1
		if tick >= 10 * rate:
			maximum_stalled = maxi(maximum_stalled, stalled)
		_check(journey.fleet.speed > 0.0, "Concealed arrivals do not stop the fleet marker.")
		if "--visual" in OS.get_cmdline_user_args() and tick in [5 * rate, 30 * rate, 90 * rate]:
			await _capture(journey, tick / rate)
		await physics_frame
	_check(failures.is_empty() and journey._spawn_requests.is_empty(), "A picker burst drains without dropping requests or reporting false placement failures.")
	_check(spawned.size() == BATCH_SIZE * 2, "Both factions spawn the complete requested batch.")
	_check(entered.size() == spawned.size(), "Every ship escapes its spawn isle and reaches the moving sphere within the bounded run.")
	_check(initial.z - journey.fleet.marker.global_position.z > 2500.0, "The fleet continues its journey during the arrival batch.")
	for ship in spawned:
		if not entered.has(ship.entity_id):
			print("STRANDED id=", ship.entity_id, " faction=", ship.faction, " position=", ship.global_position, " velocity=", ship.linear_velocity, " blocked=", ship.navigation.blocked)
	times.sort()
	navigation_times.sort()
	print("ARRIVAL_BATCH ships=", spawned.size(), " entered=", entered.size(), " max_stalled_after_10s=", maximum_stalled,
		" step_median_ms=", times[times.size() / 2] / 1000.0, " step_p95_ms=", times[int(times.size() * 0.95)] / 1000.0,
		" navigation_p95_ms=", navigation_times[int(navigation_times.size() * 0.95)] / 1000.0)
	journey.free()
	await process_frame


func _check_detour_lifetime() -> void:
	var journey := JOURNEY.instantiate() as Journey
	journey.combat_enabled = false
	journey.encounters.enabled = false
	root.add_child(journey)
	journey.set_physics_process(false)
	journey.camera_rig.set_process(false)
	var isle := ISLAND.instantiate() as FloatingIsland
	journey.add_child(isle)
	journey.origin.register_root(isle)
	var record := IslandRecord.new()
	record.route_position = RoutePosition.new(0, 1800.0)
	record.altitude = 3900.0
	record.radius = 220.0
	record.depth = 300.0
	isle.configure(record, 0)
	journey.island_spawner.obstacles = [isle]
	journey.camera_rig.camera.global_position = Vector3(0, 3800, 0)
	journey._spawn_rng.seed = 197
	await physics_frame
	await physics_frame
	_check(journey._spawn_ship(KESTREL, Factions.PLAYER), "The lifetime fixture spawns concealed behind its isle.")
	var ship: Airship = journey.ships.back()
	ship.freeze = true
	journey.fleet.prepare_step(1.0 / Engine.physics_ticks_per_second)
	ship.navigation.plan(ship, [isle])
	_check(is_instance_valid(ship.navigation._arrival_island) and not ship.navigation.blocked, "An isle blocking the entire fleet sphere produces a usable approach detour.")
	var before := ship.navigation.steer(ship, Vector3.ZERO, [isle])
	journey.origin.shift_segments(-1)
	ship.navigation.plan(ship, [isle])
	var after := ship.navigation.steer(ship, Vector3.ZERO, [isle])
	_check(before.length() > 0.0 and before.distance_to(after) < 0.02, "Rebasing preserves the cached island-relative approach leg.")
	journey.island_spawner.obstacles = []
	isle.free()
	ship.navigation.plan(ship, [])
	_check(not ship.navigation.blocked and ship.navigation._arrival_island == null and ship.navigation.steer(ship, Vector3.ZERO, []).length() > 0.0, "Unloading the detour island resumes direct approach without a stale reference.")
	journey.free()
	await process_frame


func _capture(journey: Journey, seconds: int) -> void:
	var directory := OS.get_environment("AERWYTH_CAPTURE_DIR")
	_check(not directory.is_empty(), "Visual mode requires an external capture directory.")
	if directory.is_empty():
		return
	journey.camera_rig.orbit_distance = 4500.0
	journey.camera_rig.pitch = -0.5
	for frame in range(3):
		await process_frame
	await RenderingServer.frame_post_draw
	_check(root.get_texture().get_image().save_png(directory.path_join("arrival-%ds.png" % seconds)) == OK, "Arrival capture saves successfully.")


func _check(condition: bool, message: String) -> void:
	if not condition and message not in _failures:
		_failures.append(message)
