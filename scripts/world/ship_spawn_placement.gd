class_name ShipSpawnPlacement
extends RefCounted

const MINIMUM_Z_DISTANCE: float = 500.0
const ATTEMPTS: int = 32
const ATTEMPTS_PER_ISLE: int = 4


static func find_position(journey: Journey, ship: Airship, faction: StringName, rng: RandomNumberGenerator) -> Vector3:
	var capsule := ship.hull_collider.shape as CapsuleShape3D
	var radius := maxf(capsule.radius, capsule.height * 0.5) + ShipNavigation.HULL_CLEARANCE
	var side: float = -1.0 if faction == Factions.ENEMY else 1.0
	var marker := journey.fleet.marker.global_position
	var cloud: MeshInstance3D
	var islands: Array[FloatingIsland] = []
	var camera: Camera3D = journey.camera_rig.camera
	if ship.spawn_layer == Airship.SpawnLayer.ISLE:
		if journey.island_spawner == null or not is_instance_valid(camera) or not camera.is_current():
			return Vector3.INF
		for island in journey.island_spawner.obstacles:
			if is_instance_valid(island) and not island.is_queued_for_deletion() and island.is_visible_in_tree() and (island.global_position.z - marker.z) * side >= MINIMUM_Z_DISTANCE:
				islands.append(island)
		islands.sort_custom(func(a: FloatingIsland, b: FloatingIsland) -> bool: return a.global_position.distance_squared_to(marker) < b.global_position.distance_squared_to(marker))
	else:
		if journey.clouds == null:
			return Vector3.INF
		var altitude_side: int = -1 if ship.spawn_layer == Airship.SpawnLayer.LOWER_CLOUD else 1
		var layer := journey.clouds.profile.preferred_spawn_layer(marker.y, altitude_side)
		if layer == null:
			return Vector3.INF
		cloud = journey.clouds.closest_spawn_cloud(marker, side, radius, layer, MINIMUM_Z_DISTANCE)
		if cloud == null:
			return Vector3.INF
	var probe := SphereShape3D.new()
	probe.radius = radius
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = probe
	query.collision_mask = 3
	for attempt in range(ATTEMPTS):
		var location: Vector3
		if ship.spawn_layer == Airship.SpawnLayer.ISLE:
			@warning_ignore("integer_division")
			var index: int = attempt / ATTEMPTS_PER_ISLE
			if index >= islands.size():
				break
			location = islands[index].sample_hidden_position(camera.global_position, radius, ship.island_clearance, rng)
		else:
			location = journey.clouds.sample_spawn_position(cloud, radius, rng)
		if not location.is_finite() or (location.z - marker.z) * side < MINIMUM_Z_DISTANCE + radius:
			continue
		if _position_clear(journey, location, radius, query):
			return location
	return Vector3.INF


static func _position_clear(journey: Journey, location: Vector3, radius: float, query: PhysicsShapeQueryParameters3D) -> bool:
	query.transform = Transform3D(Basis.IDENTITY, location)
	if not journey.get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty():
		return false
	# Include ships added this tick before the native broadphase synchronizes.
	for other in journey.ships:
		var clearance := radius + other.hull_radius + other.hull_half_segment
		if location.distance_squared_to(other.global_position) < clearance * clearance:
			return false
	return true
