extends SceneTree

const JOURNEY_SCENE := preload("res://scenes/world/journey.tscn")
const PROFILE := preload("res://resources/terrain/journey_terrain.tres")

var _failures: Array[String] = []
var _visual: bool = false


func _initialize() -> void:
	_visual = "--visual" in OS.get_cmdline_user_args()
	_run.call_deferred()


func _run() -> void:
	_check_progression()
	_check_grid()
	_check_sampling()
	_check_biome_contrast()
	_check_meshes()
	var start := Time.get_ticks_msec()
	var journey := JOURNEY_SCENE.instantiate() as Journey
	root.add_child(journey)
	journey.set_physics_process(false)
	var terrain := journey.terrain
	terrain.set_process(false)
	print("Initial terrain: %d patches in %d ms (including journey startup)." % [terrain.chunks.size(), Time.get_ticks_msec() - start])
	terrain.build_pending(10000)
	_check_water(journey)
	if _visual:
		await _capture_water(journey)
	var original_keys := terrain.chunks.keys()
	var original_chunk: MeshInstance3D = terrain.chunks[original_keys[0]]
	var original_arrays := original_chunk.mesh.surface_get_arrays(0)
	var relative := original_chunk.global_position - journey.fleet.anchor.global_position
	journey.origin.shift_segments(-1)
	_check((original_chunk.global_position - journey.fleet.anchor.global_position).is_equal_approx(relative), "Rebasing preserves terrain/fleet alignment.")
	_check(original_chunk.mesh.surface_get_arrays(0) == original_arrays, "Origin shifts do not rebuild terrain.")
	_check_layout(terrain)
	var visible_before := _visible_count(terrain)
	var distance_before := journey.progression.distance
	terrain.update_region(0.0, journey.anchor_route_position(), Vector3(7000.0, -3500.0, 10240.0))
	terrain.build_pending(1)
	_check(_visible_count(terrain) == visible_before, "Old coverage remains visible while replacement detail is incomplete.")
	_check(journey.progression.distance == distance_before, "Changing terrain detail or camera position does not advance progression.")
	terrain.build_pending(10000)
	_check_layout(terrain)
	# Exercise unloading, reloads, and signed origins without simulating the fleet.
	for segment: int in [-3, -8, -12, 0, -9007199254740995]:
		journey.origin.shift_segments(segment - journey.origin.segment)
		terrain.update_region(0.0, RoutePosition.new(segment, 0.0), Vector3.ZERO)
		terrain.build_pending(10000)
		_check_layout(terrain)
		for chunk in terrain.chunks.values():
			_check(absf(chunk.global_position.z) <= (terrain.chunk_radius + 2) * terrain.profile.root_size(), "Huge route indices produce small local transforms.")
		await process_frame
	# Cancellation must not publish an obsolete region.
	terrain.update_region(0.0, RoutePosition.new(journey.origin.segment - 10, 0.0), Vector3(0.0, 0.0, -102400.0))
	terrain.build_pending(1)
	terrain.update_region(0.0, RoutePosition.new(journey.origin.segment, 0.0), Vector3.ZERO)
	terrain.build_pending(10000)
	_check_layout(terrain)
	await _check_background_jobs(journey)
	if _visual:
		await _capture_stages(journey)
	journey.queue_free()
	await process_frame
	for failure in _failures:
		printerr("FAIL: ", failure)
	if _failures.is_empty():
		print("PASS: 10/50/100-meter grids, progression biomes, water, meshes, background streaming, cancellation, and rebasing.")
	quit(0 if _failures.is_empty() else 1)


func _check_progression() -> void:
	var progress := JourneyProgress.new()
	var start := RoutePosition.new(-9007199254740995, 130.0)
	progress.initialize(start)
	_check(progress.distance == 0.0, "Progression starts at zero even at huge coordinates.")
	progress.update(start.advanced(-21372.5))
	_check(progress.distance == 21372.5, "Progression counts forward world units across signed segment boundaries.")
	progress.update(start.advanced(40.0))
	_check(progress.distance == 0.0, "Positions behind the journey start do not give negative progression.")
	progress.free()


func _check_sampling() -> void:
	var sampler := TerrainSampler.new(PROFILE, RoutePosition.new())
	var second := TerrainSampler.new(PROFILE, RoutePosition.new())
	var seed := PROFILE.grassland.height_noise.seed
	for segment: int in [-9, -8, -3, 0, 5, 7, -9007199254740995]:
		for x in range(-10000, 10000, 800):
			var boundary := sampler.sample(float(x), segment, 10240.0)
			_check(boundary == sampler.sample(float(x), segment + 1, 0.0), "Noise matches exactly at segment boundaries.")
			_check(boundary.distance_to(sampler.sample(float(x), segment, 10239.99)) < 0.001, "Continuous noise has no segment seam.")
			var noise := sampler.sample(float(x), segment, 5120.0)
			_check(noise == second.sample(float(x), segment, 5120.0), "Sampling is deterministic.")
			var blend := sampler.mountain_weight(segment, 5120.0)
			var height := sampler.height_from_noise(noise, blend)
			_check(height >= PROFILE.minimum_height() and height <= PROFILE.maximum_height(), "Blended terrain stays in the authored altitude range.")
			_check(is_zero_approx(fmod(height, PROFILE.voxel_size)), "Terrain surfaces align with the selected vertical grid.")
			var color := sampler.color_at(height, noise.z, blend)
			if blend == 0.0:
				_check(color in PROFILE.grassland.palette.colors, "Grassland keeps discrete authored bands.")
			elif blend == 1.0:
				_check(color in PROFILE.mountains.palette.colors, "Mountains keep discrete authored bands.")
	_check(PROFILE.grassland.height_noise.seed == seed, "Sampling leaves shared resources unchanged.")
	for entry: Vector2 in [Vector2(0.0, 0.0), Vector2(15000.0, 0.0), Vector2(32500.0, 0.5), Vector2(50000.0, 1.0), Vector2(80000.0, 1.0)]:
		var route := RoutePosition.new(0, -entry.x)
		_check(is_equal_approx(sampler.mountain_weight(route.segment, route.offset), entry.y), "Progression smoothly controls the authored biome transition.")
	var grass_relief := Vector2(INF, -INF)
	var mountain_relief := Vector2(INF, -INF)
	for x in range(-15000, 15000, 250):
		var grass := sampler.surface_height(float(x), RoutePosition.new())
		var mountain := sampler.surface_height(float(x), RoutePosition.new(0, -60000.0))
		grass_relief = Vector2(minf(grass_relief.x, grass), maxf(grass_relief.y, grass))
		mountain_relief = Vector2(minf(mountain_relief.x, mountain), maxf(mountain_relief.y, mountain))
	_check(mountain_relief.y - mountain_relief.x > (grass_relief.y - grass_relief.x) * 1.5, "Later mountain ranges have substantially stronger relief.")
	_check(sampler.surface_height(121.0, RoutePosition.new(0, 251.0)) == sampler.surface_height(129.0, RoutePosition.new(0, 259.0)), "Points within one voxel column share the exact same top.")
	_check(sampler.sample(3000.0, -9007199254740995, 5000.0) != sampler.sample(3000.0, -9007199254740994, 5000.0), "Huge adjacent segments stay distinct.")
	var grass_levels: Dictionary[float, bool] = {}
	for z in range(-10000, 10010, 200):
		for x in range(-10000, 10010, 200):
			grass_levels[sampler.surface_height(x, RoutePosition.new(0, z))] = true
	var available_levels := int((PROFILE.grassland.height_range.y - PROFILE.grassland.height_range.x) / PROFILE.voxel_size) + 1
	_check(grass_levels.size() >= available_levels / 2, "Grassland uses a substantial part of its expanded height range.")
	_check(grass_levels.keys().max() > 200.0 and grass_levels.keys().min() < 0.0, "Grasslands rise above the previous plateau limit while retaining ponds.")
	print("Grassland levels: ", grass_levels.keys(), "; sampled relief: grass ", grass_relief, ", mountains ", mountain_relief)


func _check_grid() -> void:
	for voxel: int in [10, 50, 100]:
		var settings := PROFILE.duplicate() as TerrainProfile
		settings.voxel_size = voxel
		var width := settings.root_size()
		var sampler := TerrainSampler.new(settings, RoutePosition.new())
		for segment: int in [-9007199254740995, -17, -1, 0, 1, 17, 9007199254740995]:
			for offset: float in [0.0, 1.0, 3199.0, 10239.0]:
				var route := RoutePosition.new(segment, offset)
				var tile := TerrainGrid.tile_at(route, width)
				var start := TerrainGrid.tile_start(tile, width)
				_check(start.compare(route) <= 0 and start.advanced(width).compare(route) > 0, "Exact root lookup encloses positive, negative, and huge coordinates.")
				_check(TerrainGrid.tile_at(start, width) == tile, "Tile conversion round trips exactly.")
				_check(start.advanced(width).compare(TerrainGrid.tile_start(tile + 1, width)) == 0, "Adjacent root tiles share an exact border.")
				var center := TerrainGrid.cell_center(route, voxel)
				_check(TerrainGrid.cell_center(center, voxel).compare(center) == 0, "Voxel center lookup is idempotent at huge coordinates.")
				_check(center.advanced(-voxel * 0.5).compare(route) <= 0 and center.advanced(voxel * 0.5).compare(route) > 0, "Source cells enclose the queried coordinate across origin segments.")
				_check(sampler.surface_height(121.0, center.advanced(-4.0)) == sampler.surface_height(121.0, center.advanced(4.0)), "A source cell has one height even across a 10240-meter route boundary.")


func _check_biome_contrast() -> void:
	var biome := PROFILE.grassland.duplicate() as TerrainBiome
	biome.height_contrast = 0.0
	var midpoint := (biome.height_range.x + biome.height_range.y) * 0.5
	_check(biome.elevation(-1.0) == midpoint and biome.elevation(1.0) == midpoint, "Zero contrast produces a flat biome.")
	biome.height_contrast = 0.0001
	_check(absf(biome.elevation(1.0) - midpoint) < 0.1, "Near-zero contrast approaches flat continuously rather than jumping to full relief.")
	for settings: TerrainBiome in [PROFILE.grassland, PROFILE.mountains]:
		_check(settings.elevation(0.75) > settings.elevation(0.65), "High noise values retain distinct summit heights instead of clipping into plateaus.")


func _check_meshes() -> void:
	for voxel: int in [10, 50, 100]:
		_check_mesh_scale(voxel)


func _check_mesh_scale(voxel: int) -> void:
	var settings := PROFILE.duplicate() as TerrainProfile
	settings.voxel_size = voxel
	var size := 32 * voxel
	var sampler := TerrainSampler.new(settings, RoutePosition.new())
	var route := TerrainGrid.tile_start(TerrainGrid.tile_at(RoutePosition.new(-6, 10000.0), size), size)
	var next := route.advanced(size)
	var started := Time.get_ticks_usec()
	var first := TerrainMeshBuilder.new().build(sampler, 0, route.segment, int(route.offset), size, false)
	var neighbor := TerrainMeshBuilder.new().build(sampler, 0, next.segment, int(next.offset), size, false)
	print("Two %d-unit terrain patches: %.2f ms." % [voxel, float(Time.get_ticks_usec() - started) / 1000.0])
	var arrays := first.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var top_coverage := PackedInt32Array()
	top_coverage.resize(32 * 32)
	for vertex in vertices:
		_check(vertex / voxel == (vertex / voxel).floor(), "All near-terrain vertices lie on the selected cubic grid.")
	for triangle in range(0, indices.size(), 3):
		var a := vertices[indices[triangle]]
		var b := vertices[indices[triangle + 1]]
		var c := vertices[indices[triangle + 2]]
		_check((b - a).cross(c - a).dot(normals[indices[triangle]]) < 0.0, "Mesh faces have nonzero area and clockwise outward winding.")
	for quad in range(0, vertices.size(), 4):
		# ArrayMesh octahedral normal packing introduces a small round-trip error.
		if normals[quad].dot(Vector3.UP) < 0.999:
			continue
		var start := vertices[quad]
		var end := vertices[quad + 2]
		for z in range(int(start.z) / voxel, int(end.z) / voxel):
			for x in range(int(start.x) / voxel, int(end.x) / voxel):
				top_coverage[z * 32 + x] += 1
				_check(start.y == sampler.surface_height((x + 0.5) * voxel, route.advanced((z + 0.5) * voxel)), "Merged tops preserve exact source column heights.")
	for coverage in top_coverage:
		_check(coverage == 1, "Merged top rectangles cover every voxel exactly once.")
	var expected := 0.0
	for x in range(32):
		expected += absf(sampler.surface_height((x + 0.5) * voxel, next.advanced(-voxel * 0.5)) - sampler.surface_height((x + 0.5) * voxel, next.advanced(voxel * 0.5))) * voxel
	_check(is_equal_approx(_boundary_area(first, size) + _boundary_area(neighbor, 0.0), expected), "Neighboring patches expose the correct shared-border cliffs.")
	var repeated := TerrainMeshBuilder.new().build(TerrainSampler.new(settings, RoutePosition.new()), 0, route.segment, int(route.offset), size, false)
	_check(first.surface_get_arrays(0) == repeated.surface_get_arrays(0), "Regenerated geometry and colors match exactly.")
	var flat := settings.duplicate() as TerrainProfile
	flat.grassland = PROFILE.grassland.duplicate(true) as TerrainBiome
	flat.grassland.height_contrast = 0.0
	flat.band_warp_height = 0.0
	var flat_mesh := TerrainMeshBuilder.new().build(TerrainSampler.new(flat, RoutePosition.new()), 0, 0, 0, size, false)
	_check(flat_mesh.surface_get_array_len(0) == 4, "Flat same-color terrain merges 1024 voxel tops into one rectangle.")


func _check_layout(terrain: VoxelTerrain) -> void:
	var area := 0
	var near := 0
	var coarse := 0
	for patch in terrain.desired.values():
		area += patch.size * patch.size
		near += int(patch.size == 32 * terrain.profile.voxel_size)
		coarse += int(patch.size > 32 * terrain.profile.voxel_size)
		_check(terrain.chunks.has(patch.key()) and terrain.chunks[patch.key()].visible, "Every desired patch is published after generation.")
	_check(area == pow(terrain.chunk_radius * 2 + 1, 2) * terrain.profile.root_size() * terrain.profile.root_size(), "Adaptive patches retain the entire viewing area on the chosen grid.")
	_check(near > 0 and coarse > 0, "The camera has source detail with simplified distant coverage.")
	_check(terrain.chunks.size() == terrain.desired.size() and terrain.chunks.size() < 1200, "Published geometry is bounded and obsolete patches unload.")
	_check(terrain.sampler._regions.size() <= 12, "Noise caches remain bounded.")


func _check_background_jobs(journey: Journey) -> void:
	var terrain := journey.terrain
	var route := RoutePosition.new(journey.origin.segment, 0.0)
	terrain.update_region(0.0, route, Vector3(7200.0, 200.0, 0.0))
	terrain._process(0.0)
	_check(not terrain._jobs.is_empty() and terrain._jobs.size() <= terrain.build_workers, "Background work is bounded and actually dispatched.")
	journey.origin.shift_segments(-1)
	var deadline := Time.get_ticks_msec() + 15000
	while terrain.has_pending_work() and Time.get_ticks_msec() < deadline:
		await create_timer(0.005).timeout
		terrain._process(0.0)
	_check(not terrain.has_pending_work(), "Worker jobs finish and publish their requested region.")
	_check_layout(terrain)
	for patch in terrain.desired.values():
		var chunk := terrain.chunks[patch.key()]
		_check(RoutePosition.from_scene(chunk.global_position.z, journey.origin.segment).compare(RoutePosition.new(patch.segment, patch.offset_z)) == 0, "Jobs finishing after rebasing publish against the current origin.")
	terrain.update_region(0.0, route.advanced(-200000.0), Vector3(0.0, 200.0, -200000.0))
	terrain._process(0.0)
	var obsolete := terrain._jobs.keys()
	terrain.update_region(0.0, route, Vector3.ZERO)
	terrain.build_pending(10000)
	for key in obsolete:
		_check(not terrain.chunks.has(key), "Completed obsolete jobs are discarded.")
	_check_layout(terrain)
	var temporary := VoxelTerrain.new()
	var original_roots := journey.origin._roots.size()
	temporary.profile = PROFILE
	temporary.origin = journey.origin
	temporary.progression = journey.progression
	temporary.chunk_radius = 1
	journey.add_child(temporary)
	temporary.update_region(0.0, route, Vector3.ZERO)
	temporary._process(0.0)
	_check(not temporary._jobs.is_empty(), "Scene-exit check starts with outstanding jobs.")
	journey.remove_child(temporary)
	_check(temporary.chunks.is_empty() and temporary.desired.is_empty() and temporary._pending.is_empty() and temporary._jobs.is_empty(), "Scene exit discards all owned views and generation state.")
	_check(journey.origin._roots.size() == original_roots, "Detached terrain leaves no origin registrations behind.")
	journey.add_child(temporary)
	temporary.update_region(0.0, route, Vector3.ZERO)
	temporary.build_pending(10000)
	_check_layout(temporary)
	for chunk in temporary.chunks.values():
		_check(chunk in journey.origin._roots, "Reattached terrain registers every rebuilt mesh for rebasing.")
	temporary.free()
	await process_frame


func _visible_count(terrain: VoxelTerrain) -> int:
	var count := 0
	for chunk in terrain.chunks.values():
		count += int(chunk.visible)
	return count


func _check_water(journey: Journey) -> void:
	var water := journey.water
	var plane := water.mesh as PlaneMesh
	_check(water.global_position.y == 0.0, "The water surface is exactly at sea level.")
	var reach := journey.camera_rig.viewing_radius + journey.camera_rig.camera.far
	_check(minf(plane.size.x, plane.size.y) * 0.5 - RoutePosition.SEGMENT_LENGTH >= reach, "Water covers the complete viewing sphere and far range after recentering.")
	var wet := 0
	var dry := 0
	for z in range(-6400, 6410, 160):
		for x in range(-6400, 6410, 160):
			var height := journey.terrain.sampler.surface_height(x, RoutePosition.new(0, z))
			wet += int(height < 0.0)
			dry += int(height >= 0.0)
	_check(wet > 0 and dry > wet, "Starting grassland contains submerged basins surrounded by predominantly dry land.")
	var original := water.global_position
	for offset: float in [-35000.0, -10240.0, 0.0, 17000.0]:
		water.recenter(Vector3(4000.0, 3800.0, offset))
		_check(water.global_position.y == 0.0 and absf(water.global_position.z - offset) <= 5120.0, "Recentered water stays at Y = 0 with bounded local coverage.")
	water.global_position = original
	var relative := water.global_position - journey.fleet.anchor.global_position
	var progress := journey.progression.distance
	journey.origin.shift_segments(-2)
	water.recenter(journey.fleet.anchor.global_position)
	_check((water.global_position - journey.fleet.anchor.global_position).is_equal_approx(relative), "Water and fleet remain aligned across origin shifts.")
	_check(journey.progression.distance == progress, "Moving water coverage does not change journey progression.")
	journey.origin.shift_segments(2)
	print("Starting grassland samples: %d submerged, %d dry." % [wet, dry])


func _capture_water(journey: Journey) -> void:
	var directory := OS.get_environment("AERWYTH_CAPTURE_DIR")
	_check(not directory.is_empty(), "Water rendering checks need an external capture directory.")
	if directory.is_empty():
		return
	# Find a shallow basin near the fleet using the real terrain definition.
	var pond := Vector3.ZERO
	var best_distance := INF
	for z in range(-6400, 6410, 80):
		for x in range(-6400, 6410, 80):
			var height := journey.terrain.sampler.surface_height(x, RoutePosition.new(0, z))
			var distance := Vector2(x, z).length_squared()
			if height <= -30.0 and distance < best_distance:
				pond = Vector3(x, 0.0, z)
				best_distance = distance
	_check(best_distance < INF, "A starting pond is available for rendering checks.")
	var eye := Camera3D.new()
	journey.add_child(eye)
	journey.origin.register_root(eye)
	eye.near = 0.5
	eye.far = journey.camera_rig.camera.far
	eye.global_position = pond + Vector3(500.0, 550.0, 700.0)
	eye.look_at(pond)
	eye.make_current()
	journey.terrain.update_region(0.0, journey.anchor_route_position(), eye.global_position)
	journey.terrain.build_pending(10000)
	# Freeze shader time to compare the same view across a floating-origin shift.
	var material := journey.water.material_override.duplicate() as ShaderMaterial
	journey.water.material_override = material
	material.set_shader_parameter("animation_speed", 0.0)
	for frame in range(3):
		await process_frame
	await RenderingServer.frame_post_draw
	var before := root.get_texture().get_image()
	_check(before.save_png(directory.path_join("water-pond.png")) == OK, "Pond capture saved.")
	journey.origin.shift_segments(-1)
	journey.water.recenter(journey.fleet.anchor.global_position)
	for frame in range(3):
		await process_frame
	await RenderingServer.frame_post_draw
	var after := root.get_texture().get_image()
	_check(after.save_png(directory.path_join("water-rebased.png")) == OK, "Rebased pond capture saved.")
	# Ignore subpixel rasterization differences; a moved pattern would change whole squares.
	var difference := 0.0
	for y in range(0, before.get_height(), 4):
		for x in range(0, before.get_width(), 4):
			var a := before.get_pixel(x, y)
			var b := after.get_pixel(x, y)
			difference += absf(a.r - b.r) + absf(a.g - b.g) + absf(a.b - b.b)
	var samples := ceilf(before.get_width() / 4.0) * ceilf(before.get_height() / 4.0)
	_check(difference / samples < 0.01, "Rendered water and shorelines remain stable across origin shifts.")
	print("Pond at ", pond, "; mean rendered rebase difference: ", difference / samples)
	journey.origin.shift_segments(1)
	material.set_shader_parameter("animation_speed", 0.4)
	eye.global_position = pond + Vector3(80.0, 70.0, 100.0)
	eye.look_at(pond)
	await process_frame
	await RenderingServer.frame_post_draw
	_check(root.get_texture().get_image().save_png(directory.path_join("water-close.png")) == OK, "Close voxel-water capture saved.")
	journey.origin.unregister_root(eye)
	eye.queue_free()
	journey.camera_rig.camera.make_current()


func _boundary_area(mesh: ArrayMesh, z: float) -> float:
	var arrays := mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var area := 0.0
	for triangle in range(0, indices.size(), 3):
		var a := vertices[indices[triangle]]
		var b := vertices[indices[triangle + 1]]
		var c := vertices[indices[triangle + 2]]
		if a.z == z and b.z == z and c.z == z:
			area += (b - a).cross(c - a).length() * 0.5
	return area


func _capture_stages(journey: Journey) -> void:
	var directory := OS.get_environment("AERWYTH_CAPTURE_DIR")
	_check(not directory.is_empty(), "Visual checks need an external capture directory.")
	if directory.is_empty():
		return
	for distance: float in [0.0, 32500.0, 60000.0]:
		# Place the whole test scene at a new logical location without changing local transforms.
		var route := RoutePosition.new(0, -distance)
		journey.origin.segment = route.segment
		journey.fleet.anchor.position.z = route.offset
		journey.fleet.average_focus.position.z = route.offset
		journey.progression.update(route)
		journey.water.recenter(journey.fleet.anchor.global_position)
		var rig := journey.camera_rig
		rig.focus_fleet()
		rig.pan(Vector3.ZERO)
		var eye_route := route.advanced(220.0)
		var surface := journey.terrain.sampler.surface_height(0.0, eye_route)
		var blend := journey.terrain.sampler.mountain_weight(eye_route.segment, eye_route.offset)
		var highest := lerpf(PROFILE.grassland.height_range.y, PROFILE.mountains.height_range.y, blend)
		var eye_height := maxf(surface + 180.0, highest + 120.0)
		rig.pan(Vector3(0.0, eye_height, route.offset + 220.0) - rig.global_position)
		rig.yaw = 0.25
		rig.pitch = -0.32
		rig.apply_view_bounds()
		# Discard old fixture transforms after directly replacing the test origin.
		for key in journey.terrain.chunks.keys():
			journey.terrain._remove_chunk(key)
		journey.terrain._region_key = ""
		journey.terrain.update_region(0.0, route, rig.camera.global_position)
		journey.terrain.build_pending(10000)
		for frame in range(3):
			await process_frame
		await RenderingServer.frame_post_draw
		_check(root.get_texture().get_image().save_png(directory.path_join("terrain-%d.png" % int(distance))) == OK, "Terrain stage capture saved.")
		rig.pan(Vector3(0.0, 2400.0, 1700.0))
		rig.pitch = -0.7
		rig.apply_view_bounds()
		journey.terrain.update_region(0.0, route, rig.camera.global_position)
		journey.terrain.build_pending(10000)
		await process_frame
		await RenderingServer.frame_post_draw
		_check(root.get_texture().get_image().save_png(directory.path_join("terrain-wide-%d.png" % int(distance))) == OK, "Wide biome capture saved.")


func _check(condition: bool, message: String) -> void:
	if not condition and message not in _failures:
		_failures.append(message)
