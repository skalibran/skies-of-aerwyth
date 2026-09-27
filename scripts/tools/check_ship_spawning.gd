extends SceneTree

const JOURNEY := preload("res://scenes/world/journey.tscn")
const ISLAND := preload("res://scenes/islands/island.tscn")
const KESTREL := preload("res://resources/ships/kestrel.tres")

var _failures: Array[String] = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var journey := JOURNEY.instantiate() as Journey
	journey.combat_enabled = false
	journey.encounters.enabled = false
	root.add_child(journey)
	journey.set_physics_process(false)
	journey.camera_rig.set_process(false)
	journey._spawn_rng.seed = 71937
	journey._enemy_spawn_rng.seed = 71937
	for ship in journey.ships:
		ship.freeze = true
	await physics_frame
	await physics_frame
	for definition in journey.available_ships:
		var authored := definition.scene.instantiate() as Airship
		_check(authored.spawn_layer == (Airship.SpawnLayer.UPPER_CLOUD if definition.display_name == "Manta" else Airship.SpawnLayer.ISLE), "The catalog has authored upper-cloud Manta and isle spawns for the other ships.")
		authored.free()
		for faction: StringName in [Factions.PLAYER, Factions.ENEMY]:
			var placed := journey._spawn_ship(definition, faction)
			_check(placed, "Normal scenery conceals " + definition.display_name + " for " + str(faction))
			if placed:
				var ship: Airship = journey.ships.back()
				_check_spawn(ship, journey)
				ship.free()
	var original := journey.island_spawner.obstacles
	var isle := ISLAND.instantiate() as FloatingIsland
	journey.add_child(isle)
	journey.origin.register_root(isle)
	journey.island_spawner.obstacles = [isle]
	var record := IslandRecord.new()
	record.route_position = RoutePosition.new(0, 1800.0)
	record.altitude = 3800.0
	record.radius = 220.0
	record.depth = 300.0
	isle.configure(record, 0)
	var eye := journey.camera_rig.camera
	if "--visual" in OS.get_cmdline_user_args():
		eye.fov = 20.0
	for side: int in [1, -1]:
		record.route_position = RoutePosition.new(0, 1800.0 * side)
		isle.configure(record, 0)
		for camera_z: float in [0.0, 4000.0 * side]:
			eye.global_position = Vector3(0, 3700, camera_z)
			eye.look_at(isle.to_global(isle.spawn_occlusion_center))
			eye.reset_physics_interpolation()
			await physics_frame
			await physics_frame
			journey._spawn_rng.seed = 197
			journey._enemy_spawn_rng.seed = 197
			var placed := journey._spawn_ship(KESTREL, Factions.PLAYER if side == 1 else Factions.ENEMY)
			_check(placed, "An isle hides a spawn from cameras on either Z side, for both factions.")
			if not placed:
				continue
			var ship: Airship = journey.ships.back()
			ship.freeze = true
			_check_spawn(ship, journey)
			_check((ship.global_position.z - isle.global_position.z) * (isle.global_position.z - eye.global_position.z) > 0.0, "Reversing the camera reverses which side of the isle conceals the ship.")
			_check_mesh_occlusion(isle, eye.global_position, ship.global_position, _radius(ship))
			var relative := ship.global_position - isle.global_position
			journey.origin.shift_segments(-1)
			_check(isle.hides_sphere(eye.global_position, ship.global_position, _radius(ship)) and (ship.global_position - isle.global_position).distance_to(relative) < 0.005, "Origin shifts preserve concealed placement.")
			journey.origin.shift_segments(1)
			if "--visual" in OS.get_cmdline_user_args() and side == 1:
				await _capture(journey, isle, "front" if camera_z == 0.0 else "behind")
			ship.free()
	_check_transformed_occluder(isle)
	isle.position.z = 499.0
	await physics_frame
	_check(not journey._spawn_ship(KESTREL, Factions.PLAYER), "An isle less than 500 meters along Z cannot be a spawn source.")
	isle.position.z = 1800.0
	isle.hide()
	_check(not journey._spawn_ship(KESTREL, Factions.PLAYER), "Hidden isles cannot conceal spawns.")
	journey.island_spawner.obstacles = []
	_check(not journey._spawn_ship(KESTREL, Factions.PLAYER), "Missing isles fail without falling back to visible or cloud placement.")
	journey.island_spawner.obstacles = original
	isle.free()
	journey.queue_free()
	await process_frame
	for failure in _failures:
		printerr("FAIL: ", failure)
	if _failures.is_empty():
		print("PASS: authored spawn layers, all catalog ships and factions, whole-hull isle occlusion from both camera sides, visible mesh ray checks, 500-meter Z clearance, rebasing, and unavailable sources.")
	quit(0 if _failures.is_empty() else 1)


func _check_spawn(ship: Airship, journey: Journey) -> void:
	var radius := _radius(ship)
	var marker := journey.fleet.marker.global_position
	var side: float = -1.0 if ship.faction == Factions.ENEMY else 1.0
	_check((ship.global_position.z - marker.z) * side >= 500.0 + radius, "The entire hull clears the marker's 500-meter Z exclusion zone.")
	if ship.spawn_layer == Airship.SpawnLayer.ISLE:
		var hidden := false
		for isle in journey.island_spawner.obstacles:
			if (isle.global_position.z - marker.z) * side >= 500.0 and isle.hides_sphere(journey.camera_rig.camera.global_position, ship.global_position, radius):
				hidden = true
				_check_mesh_occlusion(isle, journey.camera_rig.camera.global_position, ship.global_position, radius)
				break
		_check(hidden, "A suitably distant visible isle conceals the whole spawned hull.")
	else:
		var layer := journey.clouds.profile.preferred_spawn_layer(marker.y, -1 if ship.spawn_layer == Airship.SpawnLayer.LOWER_CLOUD else 1)
		var cloud := journey.clouds.closest_spawn_cloud(marker, side, radius, layer, 500.0)
		_check(cloud != null and journey.clouds.volumes[cloud.mesh].contains_sphere(ship.global_position - cloud.global_position, radius), "Cloud spawns retain their authored layer and conceal the whole hull.")


func _check_mesh_occlusion(isle: FloatingIsland, camera: Vector3, center: Vector3, radius: float) -> void:
	# Independent geometry oracle: rays to 26 points on the hull sphere must hit rock triangles.
	var faces := isle.underside_mesh.mesh.get_faces()
	var transform := isle.underside_mesh.global_transform
	for x in range(-1, 2):
		for y in range(-1, 2):
			for z in range(-1, 2):
				if x == 0 and y == 0 and z == 0:
					continue
				var point := center + Vector3(x, y, z).normalized() * radius
				var blocked := false
				for index in range(0, faces.size(), 3):
					if Geometry3D.segment_intersects_triangle(camera, point, transform * faces[index], transform * faces[index + 1], transform * faces[index + 2]) != null:
						blocked = true
						break
				_check(blocked, "The visible rock mesh blocks the hull silhouette, not only the navigation capsule.")


func _check_transformed_occluder(isle: FloatingIsland) -> void:
	var original := isle.underside_mesh.transform
	isle.underside_mesh.rotation.z = deg_to_rad(60.0)
	isle._build_spawn_occluder()
	var rng := RandomNumberGenerator.new()
	rng.seed = 818
	for direction: Vector3 in [Vector3.LEFT, Vector3.RIGHT, Vector3.UP, Vector3.DOWN, Vector3.FORWARD, Vector3.BACK]:
		var camera := isle.global_position + direction * 4000.0
		var point := isle.sample_hidden_position(camera, 40.0, 20.0, rng)
		_check(point.is_finite(), "A transformed convex rock retains an interior spawn occluder.")
		if point.is_finite():
			_check_mesh_occlusion(isle, camera, point, 40.0)
	isle.underside_mesh.transform = original
	isle._build_spawn_occluder()


func _radius(ship: Airship) -> float:
	return ship.hull_radius + ship.hull_half_segment + ShipNavigation.HULL_CLEARANCE


func _capture(journey: Journey, isle: FloatingIsland, label: String) -> void:
	var directory := OS.get_environment("AERWYTH_CAPTURE_DIR")
	_check(not directory.is_empty(), "Visual checks require an external capture directory.")
	if directory.is_empty():
		return
	journey.clouds.hide()
	for frame in range(3):
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(directory.path_join("isle-spawn-" + label + "-hidden.png"))
	isle.hide()
	for frame in range(3):
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(directory.path_join("isle-spawn-" + label + "-revealed.png"))
	isle.show()
	journey.clouds.show()


func _check(condition: bool, message: String) -> void:
	if not condition and message not in _failures:
		_failures.append(message)
