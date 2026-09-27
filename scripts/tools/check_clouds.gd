extends SceneTree

const JOURNEY_SCENE := preload("res://scenes/world/journey.tscn")
const PROFILE := preload("res://resources/clouds/journey_clouds.tres")

var _failures: Array[String] = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_check_types_and_meshes()
	var started := Time.get_ticks_msec()
	var journey := JOURNEY_SCENE.instantiate() as Journey
	journey.combat_enabled = false
	root.add_child(journey)
	journey.set_physics_process(false)
	for ship in journey.ships:
		ship.freeze = true
	var clouds := journey.clouds
	_check_spawn_selection()
	_check_spawn_layers()
	_check_live_spawn_layers(journey)
	_check_proximity_slots()
	var initial := _snapshot(clouds)
	print("Cloud field: %d clouds, %d cached meshes; Journey startup %d ms." % [initial.size(), clouds.meshes.size(), Time.get_ticks_msec() - started])
	_check(initial.size() > 0, "Journey starts with a populated cloud field.")
	_check(clouds.meshes.size() == PROFILE.types.size() * PROFILE.variants_per_type, "Mesh cache is bounded by types and variants.")
	_check(clouds.volumes.size() == clouds.meshes.size(), "Each shared mesh retains one matching occupancy volume.")
	_check(clouds.cloud_layers.size() == initial.size(), "Every loaded cloud retains its authored layer.")
	for index in range(clouds.meshes.size()):
		_check_mesh_grid(clouds.meshes[index], PROFILE.variant_span(index % PROFILE.variants_per_type), PROFILE.voxel_size)
	var cell_count := clouds.cells.size()
	var first := _first_cloud(clouds)
	var relative := first.global_position - journey.fleet.marker.global_position
	var first_mesh := first.mesh
	var inside_probe := _occupied_point(clouds.volumes[first_mesh])
	var occupied: Array[MeshInstance3D] = []
	clouds.query_clouds(first.global_position + inside_probe, occupied)
	_check(first in occupied, "Filled cloud voxels identify the occupied cloud.")
	journey.origin.shift_segments(-1)
	clouds.update_region(0.0, journey.marker_route_position())
	_check((first.global_position - journey.fleet.marker.global_position).is_equal_approx(relative), "Origin shift preserves cloud positions relative to the fleet.")
	_check(first.mesh == first_mesh and clouds.cells.size() == cell_count, "Rebasing neither rebuilds meshes nor changes the field.")
	clouds.query_clouds(first.global_position + inside_probe, occupied)
	_check(first in occupied, "Rebasing preserves the occupied cloud query.")
	journey.origin.shift_segments(1)
	var occupied_layers: Dictionary[int, bool] = {}
	for cloud: MeshInstance3D in clouds.cells.values():
		if cloud == null:
			continue
		var bounds := cloud.mesh.get_aabb().size * cloud.scale
		var span := maxf(bounds.x, bounds.z)
		_check(span >= 999.99 and span <= 3000.01, "Every cloud spans 1000–3000 meters.")
		_check(cloud.global_basis.is_equal_approx(Basis.IDENTITY), "Clouds retain their generated dimensions and orientation without scaling or rotation.")
		var layer_index := _layer_at(cloud.global_position.y)
		_check(layer_index >= 0, "Every cloud base stays in an authored height band.")
		occupied_layers[layer_index] = true
		_check(cloud.mesh in clouds.meshes and cloud.get_child_count() == 0, "Clouds share meshes without voxel nodes or colliders.")
		_check(clouds._clears_landscape(cloud.global_position.x, RoutePosition.from_scene(cloud.global_position.z, journey.origin.segment), cloud.global_position.y, span), "Cloud bases clear sampled terrain.")
		@warning_ignore("integer_division")
		var type_index := clouds.meshes.find(cloud.mesh) / PROFILE.variants_per_type
		_check(PROFILE.types[type_index].altitude_weight(cloud.global_position.y) > 0.0, "Spawned type fits its cloud-base altitude.")
	_check(occupied_layers.size() == PROFILE.layers.size(), "All authored layers populate the initial field.")
	_check_cloud_spacing(clouds)
	_check_dissolve(journey)
	clouds.update_region(0.0, RoutePosition.new(0, -1280.0))
	_check(clouds.cells.size() == cell_count, "Forward streaming retains a bounded cell count.")
	await process_frame
	clouds.update_region(0.0, RoutePosition.new(0, -200000.0))
	await process_frame
	_check(clouds.cells.size() == cell_count, "A route jump replaces cells without retaining traveled history.")
	clouds.update_region(0.0, RoutePosition.new())
	await process_frame
	_check(_snapshot(clouds) == initial, "Returning to a region restores identical positions, shapes, sizes, and orientation.")
	_check(_cloud_root_count(clouds) == initial.size(), "Unloaded clouds unregister from the origin.")
	# Test int64 route identity beyond exact floating-point integer precision.
	journey.origin.segment = -9007199254740995
	clouds.update_region(0.0, RoutePosition.new(journey.origin.segment, 0.0))
	await process_frame
	for cloud: MeshInstance3D in clouds.cells.values():
		if cloud != null:
			_check(absf(cloud.global_position.z) < PROFILE.look_ahead + PROFILE.keep_behind, "Huge route indices still produce local cloud transforms.")
	_check_cloud_spacing(clouds)
	journey.origin.segment = 0
	clouds.update_region(0.0, RoutePosition.new())
	await process_frame
	if "--visual" in OS.get_cmdline_user_args():
		await _capture_views(journey)
	elif "--dissolve-visual" in OS.get_cmdline_user_args():
		journey.terrain.build_pending(10000)
		await _capture_dissolve(journey)
	await _check_layer_controls(clouds)
	_check(_snapshot(clouds) == initial, "Layer fixture leaves shared authored settings and seeded content intact.")
	var profile := PROFILE.duplicate() as CloudProfile
	profile.layers = []
	for layer in PROFILE.layers:
		var empty_layer := layer.duplicate() as CloudLayer
		empty_layer.density = 0.0
		profile.layers.append(empty_layer)
	clouds.profile = profile
	clouds.update_region(0.0, RoutePosition.new(0, -200000.0))
	await process_frame
	_check(_snapshot(clouds).is_empty(), "Zero density produces no clouds.")
	_check(_cloud_root_count(clouds) == 0, "Empty region releases every cloud origin root.")
	_check(clouds.cloud_layers.is_empty(), "Unloading releases cloud layer references.")
	clouds.query_clouds(Vector3(0.0, 4500.0, 0.0), occupied)
	_check(occupied.is_empty(), "Unloaded clouds leave no occupied instances behind.")
	journey.queue_free()
	await process_frame
	for failure in _failures:
		printerr("FAIL: ", failure)
	if _failures.is_empty():
		print("PASS: fixed 50-meter voxels, 1000–3000-meter spans, unscaled and unrotated instances, separated cloud footprints, even layer coverage, height bands, exact Y levels, layer density, altitude selection, terrain clearance, deterministic streaming, rebasing, bounded ownership, and teardown.")
	quit(0 if _failures.is_empty() else 1)


func _check_types_and_meshes() -> void:
	_check_volume_sampling()
	PROFILE.validate()
	var rng := RandomNumberGenerator.new()
	rng.seed = 2718
	for altitude: float in [1700.0, 3100.0, 4500.0, 6800.0, 8700.0]:
		for attempt in range(100):
			var selected := PROFILE.select_type(altitude, rng)
			_check(selected >= 0 and PROFILE.types[selected].altitude_weight(altitude) > 0.0, "Selection uses only suitable altitude bands.")
	_check(PROFILE.select_type(20000.0, rng) == -1, "An uncovered altitude produces no unsuitable cloud.")
	for cloud_type in PROFILE.types:
		var mesh := CloudMeshBuilder.new().build(cloud_type, 100, 1000.0, 50.0)
		var repeated := CloudMeshBuilder.new().build(cloud_type, 100, 1000.0, 50.0)
		var different := CloudMeshBuilder.new().build(cloud_type, 101, 1000.0, 50.0)
		var large := CloudMeshBuilder.new().build(cloud_type, 100, 3000.0, 50.0)
		var arrays := mesh.surface_get_arrays(0)
		_check(arrays == repeated.surface_get_arrays(0), "A seed reproduces identical voxel geometry and colors.")
		_check(arrays != different.surface_get_arrays(0), "Different seeds vary the cloud shape.")
		_check_mesh_grid(mesh, 1000.0, 50.0)
		_check_mesh_grid(large, 3000.0, 50.0)
		_check(large.surface_get_array_len(0) > mesh.surface_get_array_len(0), "Larger clouds add voxel detail instead of stretching a smaller mesh.")
	var fixed_profile := PROFILE.duplicate() as CloudProfile
	fixed_profile.span_range = Vector2(3000.0, 3000.0)
	fixed_profile.validate()
	for variant in range(fixed_profile.variants_per_type):
		_check(fixed_profile.variant_span(variant) == 3000.0, "Equal span endpoints give every cached variant the same physical size.")


func _check_volume_sampling() -> void:
	var volume := CloudVolume.new()
	volume.dimensions = Vector3i(3, 3, 3)
	volume.voxel_size = 50.0
	volume.local_origin = Vector3(-75.0, 0.0, -75.0)
	volume.filled.resize(27)
	volume.filled[13] = 1
	_check(is_equal_approx(volume.sample_density(Vector3(0.0, 75.0, 0.0)), 1.0), "Occupied voxel centers have full cloud density.")
	_check(is_equal_approx(volume.sample_density(Vector3(25.0, 75.0, 0.0)), 0.5), "Cloud surfaces interpolate density for a smooth entry.")
	_check(is_zero_approx(volume.sample_density(Vector3(50.0, 75.0, 0.0))), "Empty voxels inside the bounding box do not trigger the effect.")
	_check(is_zero_approx(volume.sample_density(Vector3(0.0, -100.0, 0.0))), "Positions beyond a cloud volume have no density.")
	_check(volume.contains_sphere(Vector3(0.0, 75.0, 0.0), 24.0), "A hull can fit entirely inside an occupied voxel.")
	_check(not volume.contains_sphere(Vector3(0.0, 75.0, 0.0), 26.0), "A hull overlapping empty neighboring voxels cannot spawn at an occupied center.")
	_check(not volume.contains_sphere(Vector3(50.0, 75.0, 0.0), 10.0), "An empty voxel inside the bounds cannot conceal a ship.")
	_check(volume.intersects_sphere(Vector3(0, 75, 0), 0.0), "A point inside a filled voxel intersects its cloud.")
	_check(volume.intersects_sphere(Vector3(125, 75, 0), 100.0), "Proximity includes the exact distance from a voxel face.")
	_check(not volume.intersects_sphere(Vector3(126, 75, 0), 100.0), "Proximity ends beyond its authored distance.")
	_check(volume.intersects_sphere(Vector3(0, 200, 0), 100.0), "Proximity includes vertical distance above clouds.")
	_check(not volume.intersects_sphere(Vector3(115, 75, 115), 100.0), "Spherical proximity rejects diagonal points inside an expanded box but beyond the surface radius.")
	_check(not volume.intersects_sphere(Vector3(50, 75, 0), 10.0), "Empty cloud gaps remain clear when their surfaces are outside proximity.")
	volume.filled.fill(1)
	volume.filled[13] = 0
	_check(not volume.contains_sphere(Vector3(50.0, 75.0, 0.0), 26.0), "An enclosed empty pocket rejects a hull that intersects it.")
	_check(volume.contains_sphere(Vector3(50.0, 75.0, 0.0), 24.0), "Nearby empty pockets do not reject fully contained hulls.")
	_check(not volume.contains_sphere(Vector3(70.0, 75.0, 0.0), 10.0), "A hull must remain inside the volume's outer boundary.")


func _check_spawn_selection() -> void:
	var clouds := CloudSpawner.new()
	clouds.material = ShaderMaterial.new()
	clouds.material.shader = preload("res://shaders/clouds/cloud_surface.gdshader")
	clouds.material.set_shader_parameter(&"distance_fade_start", 8000.0)
	var camera := Camera3D.new()
	clouds.add_child(camera)
	clouds.camera = camera
	root.add_child(clouds)
	var mesh := BoxMesh.new()
	mesh.size = Vector3.ONE * 100.0
	mesh.material = clouds.material
	var volume := CloudVolume.new()
	volume.dimensions = Vector3i(2, 2, 2)
	volume.voxel_size = 50.0
	volume.local_origin = Vector3.ONE * -50.0
	volume.filled.resize(8)
	volume.filled.fill(1)
	clouds.volumes[mesh] = volume
	var marker := Vector3(123.0, 3800.0, 456.0)
	var lower := CloudLayer.new()
	var upper := CloudLayer.new()
	var offsets: Array[Vector3] = [Vector3(0, 0, 200), Vector3(0, 0, 400), Vector3(0, 0, -200), Vector3(0, 0, -400), Vector3(0, 800, 100)]
	for index in range(offsets.size()):
		var cloud := MeshInstance3D.new()
		cloud.mesh = mesh
		clouds.add_child(cloud)
		cloud.global_position = marker + offsets[index]
		clouds.cells[str(index)] = cloud
		clouds.cloud_layers[cloud] = lower if index in [0, 2] else upper
	camera.global_position = marker
	_check(clouds.closest_spawn_cloud(marker, 1.0, 15.0, upper, 500.0) == null, "Cloud sources within 500 meters along Z are excluded even when their 3D distance is greater.")
	clouds.cells["1"].position.z += 100.0
	_check(clouds.closest_spawn_cloud(marker, 1.0, 15.0, upper, 500.0) == clouds.cells["1"], "A cloud source at exactly 500 meters along Z is eligible.")
	clouds.cells["1"].position.z -= 100.0
	_check(clouds.closest_spawn_cloud(marker, 1.0, 15.0) == clouds.cells["0"], "Friendlies choose the closest Z+ cloud by 3D distance to the marker.")
	_check(clouds.closest_spawn_cloud(marker, -1.0, 15.0) == clouds.cells["2"], "Enemies choose the closest Z- cloud relative to the marker.")
	_check(clouds.closest_spawn_cloud(marker, 1.0, 15.0, upper) == clouds.cells["1"], "A preferred layer outranks a nearer cloud in another layer.")
	_check(clouds.closest_spawn_cloud(marker, -1.0, 15.0, upper) == clouds.cells["3"], "Layer preference also preserves the enemy Z- side.")
	camera.global_position = clouds.cells["1"].global_position
	_check(clouds.closest_spawn_cloud(marker, 1.0, 15.0, upper) == clouds.cells["4"], "Camera exclusion selects the next eligible cloud in the preferred layer.")
	clouds.cells["4"].hide()
	_check(clouds.closest_spawn_cloud(marker, 1.0, 15.0, upper) == null, "An unavailable authored layer does not switch to another layer.")
	clouds.cells["4"].show()
	camera.global_position = clouds.cells["0"].global_position
	_check(clouds.closest_spawn_cloud(marker, 1.0, 15.0) == clouds.cells["1"], "The camera's cloud is excluded even when it is closest.")
	camera.global_position = clouds.cells["2"].global_position
	_check(clouds.closest_spawn_cloud(marker, -1.0, 15.0) == clouds.cells["3"], "Camera exclusion also applies to enemy clouds.")
	camera.global_position += Vector3(60, 0, 0)
	_check(clouds.closest_spawn_cloud(marker, -1.0, 15.0) == clouds.cells["3"], "The feathered camera-interior fringe also excludes its cloud.")
	camera.global_position = clouds.cells["2"].global_position + Vector3(125, 0, 0)
	_check(clouds.closest_spawn_cloud(marker, -1.0, 15.0) == clouds.cells["3"], "A cloud dissolving before camera entry cannot conceal a spawn.")
	clouds.camera_proximity_distance = 0.0
	_check(clouds.closest_spawn_cloud(marker, -1.0, 15.0) == clouds.cells["2"], "Disabling proximity restores occupancy-only spawn exclusion.")
	volume.filled[7] = 0
	camera.global_position = clouds.cells["2"].global_position + Vector3.ONE * 35.0
	_check(clouds.closest_spawn_cloud(marker, -1.0, 15.0) == clouds.cells["2"], "Camera positions in empty parts of a cloud's bounds do not exclude it.")
	volume.filled[7] = 1
	camera.global_position = marker
	clouds.cells["0"].hide()
	_check(clouds.closest_spawn_cloud(marker, 1.0, 15.0) == clouds.cells["1"], "Hidden clouds cannot conceal spawning ships.")
	clouds.cells["0"].show()
	for coverage: float in [0.0, 0.5, 0.999]:
		clouds.cells["0"].set_instance_shader_parameter(&"camera_fade_coverage", coverage)
		_check(clouds.closest_spawn_cloud(marker, 1.0, 15.0) == clouds.cells["1"], "A cloud remains ineligible until its dissolve has fully restored after the camera leaves.")
	clouds.cells["0"].set_instance_shader_parameter(&"camera_fade_coverage", 1.0)
	_check(clouds.closest_spawn_cloud(marker, 1.0, 15.0) == clouds.cells["0"], "A fully restored cloud can conceal spawns again.")
	camera.global_position = marker + Vector3.BACK * 8200.0
	_check(clouds.closest_spawn_cloud(marker, 1.0, 15.0) == clouds.cells["1"], "Distance fading excludes even a cloud whose center is just inside the opaque range.")
	clouds.material.set_shader_parameter(&"distance_fade_start", 7900.0)
	camera.global_position.z += 100.0
	_check(clouds.closest_spawn_cloud(marker, 1.0, 15.0) == null, "Spawn concealment follows the material's authored fade distance.")
	camera.global_position = marker
	_check(clouds.closest_spawn_cloud(marker, 1.0, 60.0) == null, "Clouds too thin for the hull are ineligible.")
	var rng := RandomNumberGenerator.new()
	rng.seed = 71937
	for attempt in range(32):
		var point := clouds.sample_spawn_position(clouds.cells["0"], 15.0, rng)
		var offset := (point - clouds.cells["0"].global_position).abs()
		_check(point.is_finite() and offset.x <= 35.0 and offset.y <= 35.0 and offset.z <= 35.0, "Sampled hulls remain concealed in occupied cloud voxels.")
	clouds.hide()
	_check(clouds.closest_spawn_cloud(marker, -1.0, 15.0) == null, "A disabled cloud field supplies no spawn location.")
	clouds.free()


func _check_spawn_layers() -> void:
	var profile := PROFILE.duplicate(true) as CloudProfile
	var lower := profile.layers[0]
	var upper := profile.layers[1]
	var high := profile.layers[2]
	profile.layers = [high, lower, upper]
	_check(profile.preferred_spawn_layer(3800.0, -1) == lower, "Lower cloud selects the layer below the marker independently of array order.")
	_check(profile.preferred_spawn_layer(3800.0, 1) == upper, "Upper cloud selects the nearest upper layer rather than the highest layer.")
	upper.density = 0.0
	_check(profile.preferred_spawn_layer(3800.0, 1) == high, "A disabled layer is skipped in the public preference query.")
	high.density = 0.0
	_check(profile.preferred_spawn_layer(3800.0, 1) == null, "A missing upper layer cannot silently choose a lower layer.")
	lower.density = 0.0
	_check(profile.preferred_spawn_layer(3800.0, 1) == null, "An empty profile has no preferred spawn layer.")


func _check_live_spawn_layers(journey: Journey) -> void:
	var authored := preload("res://scenes/ships/kestrel.tscn").instantiate() as Airship
	authored.spawn_layer = Airship.SpawnLayer.LOWER_CLOUD
	authored.preferred_combat_positions = PackedStringArray(["bottom"])
	var lower_cloud := ShipDefinition.new()
	lower_cloud.scene = PackedScene.new()
	_check(lower_cloud.scene.pack(authored) == OK, "The lower-cloud fixture packs successfully.")
	authored.free()
	var definitions: Array[ShipDefinition] = [lower_cloud, preload("res://resources/ships/manta.tres")]
	journey._spawn_rng.seed = 71937
	journey._enemy_spawn_rng.seed = 71937
	for faction: StringName in [Factions.PLAYER, Factions.ENEMY]:
		for index in range(definitions.size()):
			var placed := journey._spawn_ship(definitions[index], faction)
			_check(placed, "Both factions can spawn in their authored cloud layer independently of combat bias.")
			if not placed:
				continue
			var ship: Airship = journey.ships.back()
			var marker := journey.fleet.marker.global_position
			var side: float = -1.0 if faction == Factions.ENEMY else 1.0
			var radius := ship.hull_radius + ship.hull_half_segment + ShipNavigation.HULL_CLEARANCE
			var layer := journey.clouds.profile.preferred_spawn_layer(marker.y, -1 if ship.spawn_layer == Airship.SpawnLayer.LOWER_CLOUD else 1)
			var cloud := journey.clouds.closest_spawn_cloud(marker, side, radius, layer, ShipSpawnPlacement.MINIMUM_Z_DISTANCE)
			_check(layer == journey.clouds.profile.layers[0 if index == 0 else 1], "Authored spawn choices select the expected lower or upper layer.")
			_check(cloud != null and journey.clouds.cloud_layers[cloud] == layer and journey.clouds.volumes[cloud.mesh].contains_sphere(ship.global_position - cloud.global_position, radius), "Runtime placement conceals the whole hull in the closest preferred-layer cloud.")
			_check((ship.global_position.z - marker.z) * side >= ShipSpawnPlacement.MINIMUM_Z_DISTANCE + radius, "The complete spawned hull stays at least 500 meters along its faction's Z side.")
			ship.free()


func _check_proximity_slots() -> void:
	var clouds := CloudSpawner.new()
	clouds.profile = PROFILE
	clouds.origin = FloatingOrigin.new()
	clouds.add_child(clouds.origin)
	root.add_child(clouds)
	clouds._placement_sizes = [Vector2(2560, 2560)]
	clouds._row_shifts = {"0:-1:3": 40.0, "0:0:0": -40.0}
	var mesh := BoxMesh.new()
	mesh.size = Vector3.ONE * 50.0
	var volume := CloudVolume.new()
	volume.dimensions = Vector3i.ONE
	volume.voxel_size = 50.0
	volume.local_origin = Vector3.ONE * -25.0
	volume.filled = PackedByteArray([1])
	clouds.volumes[mesh] = volume
	var keys: Array[String] = ["0:0:-1:7680", "0:-1:0:0"]
	var positions: Array[Vector3] = [Vector3(90, 0, -60), Vector3(-90, 0, 60)]
	for index in range(keys.size()):
		var cloud := MeshInstance3D.new()
		cloud.mesh = mesh
		clouds.add_child(cloud)
		cloud.position = positions[index]
		clouds.cells[keys[index]] = cloud
		clouds.origin.register_root(cloud)
	var nearby: Array[MeshInstance3D] = []
	clouds.query_clouds(Vector3.ZERO, nearby)
	_check(nearby.is_empty(), "An empty gap has no camera occupancy.")
	clouds.query_clouds(Vector3.ZERO, nearby, 100.0)
	_check(nearby.size() == 2, "Proximity finds both clouds across staggered slots and a negative route-segment boundary.")
	clouds.origin.shift_segments(-1)
	clouds.query_clouds(Vector3(0, 0, 10240), nearby, 100.0)
	_check(nearby.size() == 2, "Rebasing preserves neighboring-slot proximity results.")
	clouds.cells[keys[0]].hide()
	clouds.query_clouds(Vector3(0, 0, 10240), nearby, 100.0)
	_check(nearby.size() == 1 and nearby[0] == clouds.cells[keys[1]], "Hidden neighboring clouds are omitted from proximity.")
	clouds.free()


func _occupied_point(volume: CloudVolume) -> Vector3:
	var best := Vector3.ZERO
	var best_distance: float = INF
	var center := Vector3(volume.dimensions) * 0.5
	for z in range(volume.dimensions.z):
		for y in range(volume.dimensions.y):
			for x in range(volume.dimensions.x):
				if not volume.filled[(z * volume.dimensions.y + y) * volume.dimensions.x + x]:
					continue
				var point := Vector3(x, y, z) + Vector3.ONE * 0.5
				var distance := point.distance_squared_to(center)
				if distance < best_distance:
					best = point
					best_distance = distance
	return volume.local_origin + best * volume.voxel_size


func _proximity_point(volume: CloudVolume, distance: float) -> Vector3:
	# The rightmost filled face gives an unambiguous point outside the whole shape.
	for x in range(volume.dimensions.x - 1, -1, -1):
		for z in range(volume.dimensions.z):
			for y in range(volume.dimensions.y):
				if volume.filled[(z * volume.dimensions.y + y) * volume.dimensions.x + x]:
					return volume.local_origin + Vector3(x + 1, y + 0.5, z + 0.5) * volume.voxel_size + Vector3.RIGHT * distance
	return Vector3.INF


func _interior_cloud(clouds: CloudSpawner) -> MeshInstance3D:
	var nearest: MeshInstance3D
	var distance: float = INF
	var type_index := PROFILE.types.find(preload("res://resources/clouds/cumulus.tres"))
	var cumulus_meshes := clouds.meshes.slice(type_index * PROFILE.variants_per_type, (type_index + 1) * PROFILE.variants_per_type)
	for cloud: MeshInstance3D in clouds.cells.values():
		if cloud != null and cloud.mesh in cumulus_meshes and cloud.global_position.length_squared() < distance:
			nearest = cloud
			distance = cloud.global_position.length_squared()
	return nearest


func _check_dissolve(journey: Journey) -> void:
	var clouds := journey.clouds
	var dissolve := clouds.get_node("Dissolve") as CloudDissolve
	var eye := clouds.camera
	var saved_transform := eye.global_transform
	var cloud := _interior_cloud(clouds)
	var inside := cloud.global_position + _occupied_point(clouds.volumes[cloud.mesh])
	var near_surface := _proximity_point(clouds.volumes[cloud.mesh], clouds.camera_proximity_distance * 0.75)
	eye.global_position = cloud.global_position + near_surface
	_check(is_zero_approx(clouds.volumes[cloud.mesh].sample_density(near_surface)), "Proximity fixture starts outside the existing surface fringe.")
	dissolve.update_effect(dissolve.fade_duration)
	_check(is_zero_approx(cloud.get_instance_shader_parameter(&"camera_fade_coverage")), "A nearby camera dissolves the cloud before entering its voxels.")
	eye.global_position += Vector3.RIGHT * (clouds.camera_proximity_distance + 50.0)
	dissolve.update_effect(dissolve.fade_duration)
	_check(is_equal_approx(cloud.get_instance_shader_parameter(&"camera_fade_coverage"), 1.0), "Moving beyond proximity restores the cloud.")
	eye.global_position = inside
	dissolve.update_effect(dissolve.fade_duration * 0.5)
	_check(is_equal_approx(cloud.get_instance_shader_parameter(&"camera_fade_coverage"), 0.5), "Entry dissolves cloud coverage over the authored duration.")
	dissolve.update_effect(dissolve.fade_duration * 0.5)
	_check(is_zero_approx(cloud.get_instance_shader_parameter(&"camera_fade_coverage")), "The occupied cloud dissolves completely.")
	_check(cloud.is_visible_in_tree(), "Dissolving keeps the cloud registered for camera exclusion and occupancy queries.")
	for other: MeshInstance3D in clouds.cells.values():
		if other != null and other != cloud and other.mesh == cloud.mesh:
			var coverage: Variant = other.get_instance_shader_parameter(&"camera_fade_coverage")
			_check(coverage == null or is_equal_approx(coverage, 1.0), "Other instances sharing the same mesh remain opaque.")
			break
	journey.origin.shift_segments(-1)
	dissolve.update_effect(0.0)
	_check(cloud in dissolve._occupied and is_zero_approx(cloud.get_instance_shader_parameter(&"camera_fade_coverage")), "Rebasing retains occupancy and dissolve coverage.")
	journey.origin.shift_segments(1)
	eye.global_position = inside + Vector3.UP * 20000.0
	dissolve.update_effect(dissolve.fade_duration * 0.5)
	_check(is_equal_approx(cloud.get_instance_shader_parameter(&"camera_fade_coverage"), 0.5), "Exit gradually restores cloud coverage.")
	dissolve.update_effect(dissolve.fade_duration * 0.5)
	_check(is_equal_approx(cloud.get_instance_shader_parameter(&"camera_fade_coverage"), 1.0) and dissolve._coverage.is_empty(), "Restored clouds leave the active dissolve set.")
	eye.global_position = inside
	dissolve.update_effect(dissolve.fade_duration)
	clouds.camera = null
	dissolve.update_effect(dissolve.fade_duration)
	_check(is_equal_approx(cloud.get_instance_shader_parameter(&"camera_fade_coverage"), 1.0), "A missing camera restores dissolved clouds.")
	clouds.camera = eye
	eye.global_transform = saved_transform
	eye.reset_physics_interpolation()


func _check_mesh_grid(mesh: ArrayMesh, span: float, voxel_size: float) -> void:
	var bounds := mesh.get_aabb()
	_check(is_equal_approx(maxf(bounds.size.x, bounds.size.z), span) and is_zero_approx(bounds.position.y), "Final geometry preserves the requested span and cloud-base altitude.")
	var arrays := mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	for vertex in vertices:
		_check(vertex.is_equal_approx(vertex.snapped(Vector3.ONE * voxel_size)), "Every mesh vertex lies on the fixed physical voxel grid.")
	var smallest_edge: float = INF
	for index in range(0, vertices.size(), 4):
		for edge in range(4):
			smallest_edge = minf(smallest_edge, vertices[index + edge].distance_to(vertices[index + (edge + 1) % 4]))
	_check(is_equal_approx(smallest_edge, voxel_size), "Both small and large clouds retain single-voxel steps of the authored width.")
	for index in range(0, indices.size(), 3):
		var a := indices[index]
		var b := indices[index + 1]
		var c := indices[index + 2]
		_check((vertices[b] - vertices[a]).cross(vertices[c] - vertices[a]).dot(normals[a]) < 0.0, "Every cloud triangle winds clockwise with an outward normal.")


func _snapshot(clouds: CloudSpawner) -> Dictionary:
	var result := {}
	for key in clouds.cells:
		var cloud := clouds.cells[key]
		if cloud != null:
			result[key] = [cloud.transform, cloud.mesh]
	return result


func _layer_at(altitude: float) -> int:
	for index in range(PROFILE.layers.size()):
		var layer: CloudLayer = PROFILE.layers[index]
		if absf(altitude - layer.altitude) <= layer.height_variation + 0.01:
			return index
	return -1


func _check_cloud_spacing(clouds: CloudSpawner) -> void:
	for layer_index in range(PROFILE.layers.size()):
		var bounds: Array[AABB] = []
		var occupied: int = 0
		var total: int = 0
		for key in clouds.cells:
			if key.get_slice(":", 0).to_int() != layer_index:
				continue
			total += 1
			var cloud: MeshInstance3D = clouds.cells[key]
			if cloud == null:
				continue
			occupied += 1
			var box := cloud.mesh.get_aabb()
			box.position += cloud.global_position
			for other in bounds:
				var gap_x := maxf(box.position.x - other.end.x, other.position.x - box.end.x)
				var gap_z := maxf(box.position.z - other.end.z, other.position.z - box.end.z)
				_check(maxf(gap_x, gap_z) >= PROFILE.cloud_gap - 0.1, "Cloud footprints in a layer retain their authored gap, including across row and segment boundaries.")
			bounds.append(box)
		if layer_index > 0:
			_check(occupied > 0 and occupied == total, "Clear upper layers populate every placement slot instead of leaving random empty patches.")


func _check_layer_controls(clouds: CloudSpawner) -> void:
	var profile := PROFILE.duplicate() as CloudProfile
	profile.layers = []
	for index in range(PROFILE.layers.size()):
		var layer := PROFILE.layers[index].duplicate() as CloudLayer
		layer.height_variation = 0.0
		layer.density = 1.0 if index == 1 else 0.0
		profile.layers.append(layer)
	profile.validate()
	clouds.profile = profile
	clouds.update_region(0.0, RoutePosition.new(0, -200000.0))
	await process_frame
	var populated := _snapshot(clouds).size()
	_check(populated > 0 and populated == clouds.cells.size(), "An enabled layer fills its placement slots while zero-density layers allocate none.")
	for cloud: MeshInstance3D in clouds.cells.values():
		if cloud == null:
			continue
		_check(is_equal_approx(cloud.global_position.y, profile.layers[1].altitude), "Zero height variation places every cloud base at the exact layer Y.")
	clouds.profile = PROFILE
	clouds.update_region(0.0, RoutePosition.new())
	await process_frame


func _first_cloud(clouds: CloudSpawner) -> MeshInstance3D:
	for cloud in clouds.cells.values():
		if cloud != null:
			return cloud
	return null


func _cloud_root_count(clouds: CloudSpawner) -> int:
	var count: int = 0
	for origin_root in clouds.origin._roots:
		if origin_root.get_parent() == clouds:
			count += 1
	return count


func _capture_views(journey: Journey) -> void:
	journey.terrain.build_pending(10000)
	await _capture("clouds-fleet")
	journey.camera_rig.set_process(false)
	var eye := journey.camera_rig.camera
	eye.global_position = journey.fleet.marker.global_position + Vector3(0.0, 100.0, 600.0)
	eye.look_at(journey.fleet.marker.global_position + Vector3(0.0, 700.0, -2500.0))
	eye.reset_physics_interpolation()
	await _capture("clouds-sky")
	eye.global_position = Vector3(2000.0, 5500.0, 8000.0)
	eye.look_at(Vector3(0.0, 4000.0, -1000.0))
	eye.reset_physics_interpolation()
	await _capture("clouds-layers")
	await _capture_dissolve(journey)
	# Inspect each largest preset separately so it fits inside the distance fade.
	journey.clouds.hide()
	journey.get_node("Islands").hide()
	journey.get_node("MasterUI").hide()
	var gallery := Node3D.new()
	journey.add_child(gallery)
	for type_index in range(PROFILE.types.size()):
		var cloud := MeshInstance3D.new()
		cloud.mesh = journey.clouds.meshes[(type_index + 1) * PROFILE.variants_per_type - 1]
		cloud.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		gallery.add_child(cloud)
		cloud.position = Vector3(0.0, 4000.0, -2000.0)
		var center := cloud.position + cloud.mesh.get_aabb().size * cloud.scale * Vector3(0.0, 0.5, 0.0)
		eye.global_position = center + Vector3(0.0, 900.0, 3750.0)
		eye.look_at(center)
		eye.reset_physics_interpolation()
		await _capture("clouds-" + PROFILE.types[type_index].display_name.to_lower())
		eye.global_position = center + Vector3(0.0, 2400.0, 3000.0)
		eye.look_at(center)
		eye.reset_physics_interpolation()
		await _capture("clouds-" + PROFILE.types[type_index].display_name.to_lower() + "-above")
		cloud.queue_free()
		await process_frame
	gallery.queue_free()


func _capture_dissolve(journey: Journey) -> void:
	var clouds := journey.clouds
	var dissolve := clouds.get_node("Dissolve") as CloudDissolve
	dissolve.set_process(false)
	journey.camera_rig.set_process(false)
	var cloud := _interior_cloud(clouds)
	var inside := cloud.global_position + _occupied_point(clouds.volumes[cloud.mesh])
	var eye := clouds.camera
	var near_surface := _proximity_point(clouds.volumes[cloud.mesh], clouds.camera_proximity_distance * 0.75)
	eye.global_position = cloud.global_position + near_surface + Vector3.RIGHT * 200.0
	dissolve.update_effect(dissolve.fade_duration)
	eye.global_position = cloud.global_position + near_surface
	eye.look_at(eye.global_position + Vector3(-1.0, -0.15, 0.0))
	eye.reset_physics_interpolation()
	_check(is_zero_approx(clouds.volumes[cloud.mesh].sample_density(near_surface)), "Rendered proximity fixture remains outside occupied voxels and their fringe.")
	await _capture("clouds-proximity-solid")
	dissolve.update_effect(dissolve.fade_duration * 0.5)
	await _capture("clouds-proximity-half")
	dissolve.update_effect(dissolve.fade_duration * 0.5)
	_check(is_zero_approx(cloud.get_instance_shader_parameter(&"camera_fade_coverage")), "Rendered proximity dissolves the cloud before entry.")
	await _capture("clouds-proximity-clear")
	eye.global_position += Vector3.RIGHT * 200.0
	dissolve.update_effect(dissolve.fade_duration)
	eye.global_position = inside
	eye.look_at(inside + Vector3(0.0, -0.25, -1.0))
	eye.reset_physics_interpolation()
	# Compare identical hulls and scenery through solid, partial, and dissolved clouds.
	var ship_transforms: Array[Transform3D] = []
	var offsets: Array[Vector3] = [Vector3(-15.0, 0.0, -75.0), Vector3(25.0, 0.0, -250.0), Vector3(0.0, 0.0, -600.0)]
	for index in range(journey.ships.size()):
		var ship := journey.ships[index]
		ship_transforms.append(ship.global_transform)
		ship.global_position = eye.global_transform * offsets[index]
		ship.reset_physics_interpolation()
	await _capture("clouds-dissolve-solid")
	dissolve.update_effect(dissolve.fade_duration * 0.5)
	await _capture("clouds-dissolve-half")
	journey.origin.shift_segments(-1)
	dissolve.update_effect(0.0)
	await _capture("clouds-dissolve-rebased")
	journey.origin.shift_segments(1)
	dissolve.update_effect(dissolve.fade_duration * 0.5)
	_check(is_zero_approx(cloud.get_instance_shader_parameter(&"camera_fade_coverage")), "Rendered interior fixture fully dissolves the occupied cloud.")
	await _capture("clouds-dissolve-inside")
	# Frame the complete cloud from outside to inspect its return to full coverage.
	var bounds := cloud.mesh.get_aabb()
	var center := cloud.global_position + bounds.get_center()
	eye.global_position = center + Vector3(0.0, bounds.size.y * 0.3, maxf(bounds.size.x, bounds.size.z) * 1.2)
	eye.look_at(center)
	eye.reset_physics_interpolation()
	dissolve.update_effect(dissolve.fade_duration * 0.5)
	await _capture("clouds-dissolve-exit-half")
	dissolve.update_effect(dissolve.fade_duration * 0.5)
	_check(is_equal_approx(cloud.get_instance_shader_parameter(&"camera_fade_coverage"), 1.0), "Rendered exit restores the cloud.")
	await _capture("clouds-dissolve-exit")
	for index in range(journey.ships.size()):
		journey.ships[index].global_transform = ship_transforms[index]
		journey.ships[index].reset_physics_interpolation()
	dissolve.set_process(true)


func _capture(label: String) -> void:
	var directory := OS.get_environment("AERWYTH_CAPTURE_DIR")
	_check(not directory.is_empty(), "Visual validation requires an external capture directory.")
	if directory.is_empty():
		return
	for frame in range(3):
		await process_frame
	await RenderingServer.frame_post_draw
	_check(root.get_texture().get_image().save_png(directory.path_join(label + ".png")) == OK, "Saved " + label)


func _check(condition: bool, message: String) -> void:
	if not condition and message not in _failures:
		_failures.append(message)
