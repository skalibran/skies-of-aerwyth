extends SceneTree

const JOURNEY_SCENE := preload("res://scenes/world/journey.tscn")
const TERRAIN_SCENE := preload("res://scenes/terrain/voxel_terrain.tscn")
const WATER_SCENE := preload("res://scenes/water/water.tscn")
const PROFILE := preload("res://resources/terrain/journey_terrain.tres")

class MeasuredTerrain extends VoxelTerrain:
	var builds: Array[Dictionary] = []
	var uploads_ms: Array[float] = []
	var updates_ms: Array[float] = []
	var process_ms: Array[float] = []
	var commits: int = 0

	func _publish_patch(patch: Patch, arrays: Array, build_ms: float) -> void:
		var started := Time.get_ticks_usec()
		super._publish_patch(patch, arrays, build_ms)
		uploads_ms.append((Time.get_ticks_usec() - started) / 1000.0)
		builds.append({"size": patch.size, "ms": build_ms})

	func update_region(x: float, route: RoutePosition, camera_position: Vector3) -> void:
		var started := Time.get_ticks_usec()
		super.update_region(x, route, camera_position)
		updates_ms.append((Time.get_ticks_usec() - started) / 1000.0)

	func _process(delta: float) -> void:
		var started := Time.get_ticks_usec()
		super._process(delta)
		process_ms.append((Time.get_ticks_usec() - started) / 1000.0)

	func _commit_region() -> void:
		super._commit_region()
		commits += 1


var _output: String
var _results: Array[Dictionary] = []
var _world: Node3D
var _terrain: MeasuredTerrain
var _water: WaterSurface
var _origin: FloatingOrigin
var _progression: JourneyProgress
var _camera: Camera3D
var _route: RoutePosition


func _initialize() -> void:
	_output = OS.get_environment("AERWYTH_PROFILE_DIR")
	_run.call_deferred()


func _run() -> void:
	if _output.is_empty() or DisplayServer.get_name() == "headless":
		printerr("Use a rendering-capable run and an external AERWYTH_PROFILE_DIR.")
		quit(1)
		return
	Engine.max_fps = 0
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	# Fix the actual render target even if Windows DPI or the user resizes the window.
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_VIEWPORT
	root.content_scale_size = Vector2i(1920, 1080)
	root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_IGNORE
	DisplayServer.window_set_size(Vector2i(1920, 1080))
	RenderingServer.viewport_set_measure_render_time(root.get_viewport_rid(), true)
	if "--cells" in OS.get_cmdline_user_args():
		await _compare_cells()
		_save_results("cells.json")
		quit()
		return
	var transition_midpoint := (PROFILE.mountain_start_distance + PROFILE.mountain_full_distance) * 0.5
	for distance: float in [0.0, transition_midpoint, PROFILE.mountain_full_distance * 1.2]:
		var started := Time.get_ticks_usec()
		_create_landscape(distance)
		while _terrain.has_pending_work():
			await process_frame
		var ready := {"phase": "detail_ready", "distance": distance, "ms": (Time.get_ticks_usec() - started) / 1000.0, "geometry": _geometry()}
		_results.append(ready)
		print("PROFILE ", JSON.stringify(ready))
		await _measure("stationary", 2.0)
		_water.hide()
		await _measure("without_water", 2.0)
		_terrain.hide()
		await _measure("sky_only", 2.0)
		_terrain.show()
		_water.show()
		await _measure("travel_90", 8.0, 90.0)
		await _measure("camera_1000", 5.0, 1000.0)
		await _measure("camera_3000", 5.0, 3000.0)
		# The fleet-altitude view does not exercise the most detailed terrain layout.
		_camera.position.y = _terrain.profile.maximum_height() + 300.0
		await _measure("close_camera_3000", 5.0, 3000.0)
		var settle_started := Time.get_ticks_usec()
		while _terrain.has_pending_work() and Time.get_ticks_usec() - settle_started < 15000000:
			await process_frame
		var settled := {"phase": "settled", "distance": distance, "ms": (Time.get_ticks_usec() - settle_started) / 1000.0, "backlog": _terrain._pending.size() + _terrain._jobs.size(), "geometry": _geometry()}
		_results.append(settled)
		print("PROFILE ", JSON.stringify(settled))
		_world.queue_free()
		await process_frame
	_save_results("landscape.json")
	quit()


func _save_results(filename: String) -> void:
	var file := FileAccess.open(_output.path_join(filename), FileAccess.WRITE)
	file.store_string(JSON.stringify(_results, "\t"))
	print("PROFILE_COMPLETE ", _output.path_join(filename))


func _create_landscape(distance: float, build_full: bool = true) -> void:
	_world = Node3D.new()
	root.add_child(_world)
	_origin = FloatingOrigin.new()
	_world.add_child(_origin)
	_progression = JourneyProgress.new()
	_world.add_child(_progression)
	_progression.initialize(RoutePosition.new())
	_route = RoutePosition.new(0, -distance)
	_origin.segment = _route.segment
	_progression.update(_route)
	# Reuse authored lighting/materials without fleet, island, or debug work.
	var template := JOURNEY_SCENE.instantiate() as Journey
	for child_name: String in ["WorldEnvironment", "Sun"]:
		var child := template.get_node(child_name)
		child.owner = null
		template.remove_child(child)
		_world.add_child(child)
	template.free()
	var definition := TERRAIN_SCENE.instantiate() as VoxelTerrain
	_terrain = MeasuredTerrain.new()
	_terrain.profile = definition.profile
	_terrain.material = definition.material
	_terrain.chunk_radius = definition.chunk_radius
	_terrain.detail_distance = definition.detail_distance
	_terrain.build_budget_ms = definition.build_budget_ms
	_terrain.build_workers = definition.build_workers
	_terrain.origin = _origin
	_terrain.progression = _progression
	definition.free()
	_world.add_child(_terrain)
	_water = WATER_SCENE.instantiate() as WaterSurface
	_world.add_child(_water)
	_origin.register_root(_water)
	_water.recenter(Vector3(0.0, 3800.0, _route.offset))
	_camera = Camera3D.new()
	_camera.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_camera.near = 0.5
	_camera.far = 30000.0
	_camera.rotation = Vector3(-0.52, 0.5, 0.0)
	_camera.position = Vector3(0.0, 3800.0, _route.offset) + _camera.basis.z * 1800.0
	_world.add_child(_camera)
	_origin.register_root(_camera)
	_camera.make_current()
	if not build_full:
		return
	var started := Time.get_ticks_usec()
	_terrain.update_region(0.0, _route, _camera.global_position)
	var startup := {"phase": "startup", "distance": distance, "ms": (Time.get_ticks_usec() - started) / 1000.0, "geometry": _geometry(), "patch_build_ms": _build_summary()}
	_results.append(startup)
	print("PROFILE ", JSON.stringify(startup))


func _compare_cells() -> void:
	# Equal physical coverage with exact 10-, 50-, or 100-meter cubic steps.
	# This is a local mesh experiment, not an alternate implementation of world LOD.
	for distance: float in [0.0, 64000.0]:
		for cell_size: int in [10, 50, 100]:
			_create_landscape(distance, false)
			var settings := _terrain.profile.duplicate() as TerrainProfile
			settings.voxel_size = cell_size
			var sampler := TerrainSampler.new(settings, RoutePosition.new())
			var builder := TerrainMeshBuilder.new()
			var size := 32 * cell_size
			var build_ms: Array[float] = []
			var shape_ms: Array[float] = []
			var height_count: Dictionary[float, bool] = {}
			var vertices := 0
			var triangles := 0
			for z in range(0, 3200, size):
				for x in range(-1600, 1600, size):
					var route := _route.advanced(z)
					var started := Time.get_ticks_usec()
					var mesh := builder.build(sampler, x, route.segment, int(route.offset), size, false)
					build_ms.append((Time.get_ticks_usec() - started) / 1000.0)
					vertices += mesh.surface_get_array_len(0)
					triangles += mesh.surface_get_array_index_len(0) / 3
					var mesh_arrays := mesh.surface_get_arrays(0)
					for vertex: Vector3 in mesh_arrays[Mesh.ARRAY_VERTEX]:
						height_count[vertex.y] = true
					started = Time.get_ticks_usec()
					var shape := mesh.create_trimesh_shape()
					shape_ms.append((Time.get_ticks_usec() - started) / 1000.0)
					# Resource cooking only; there is no wreck simulation in this experiment.
					shape = null
					var instance := MeshInstance3D.new()
					instance.mesh = mesh
					instance.material_override = _terrain.material
					instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
					_terrain.add_child(instance)
					instance.position = Vector3(x, 0.0, route.to_scene(_origin.segment))
			var target := Vector3(-720.0, 0.0, _route.offset + 1120.0)
			if distance > 0.0:
				target = Vector3(0.0, 400.0, _route.offset + 1600.0)
			_camera.position = target + Vector3(650.0, 1000.0, 850.0)
			_camera.look_at(target)
			for frame in range(90):
				await process_frame
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(_output.path_join("cells-%d-%d.png" % [int(distance), cell_size]))
			var result := {"phase": "cell_comparison", "distance": distance, "cell_size": cell_size, "coverage": "3200x3200", "patches": build_ms.size(), "build_ms": _summary(build_ms), "total_build_ms": _sum(build_ms), "shape_resource_ms": _summary(shape_ms), "total_shape_resource_ms": _sum(shape_ms), "vertices": vertices, "triangles": triangles, "distinct_y": height_count.size()}
			_results.append(result)
			print("PROFILE ", JSON.stringify(result))
			_world.queue_free()
			await process_frame


func _sum(values: Array[float]) -> float:
	var total := 0.0
	for value in values:
		total += value
	return total


func _measure(label: String, seconds: float, speed: float = 0.0) -> void:
	# Warm pipeline/state changes before collecting timing samples.
	for frame in range(90):
		await process_frame
	_terrain.builds.clear()
	_terrain.uploads_ms.clear()
	_terrain.process_ms.clear()
	_terrain.updates_ms.clear()
	_terrain.commits = 0
	_terrain.maximum_collider_build_usec = 0
	var frames_ms: Array[float] = []
	var gpu_ms: Array[float] = []
	var render_cpu_ms: Array[float] = []
	var draws: Array[float] = []
	var primitives: Array[float] = []
	var backlog_peak := 0
	var stream_timer := 0.0
	var started := Time.get_ticks_usec()
	var previous := started
	var viewport := root.get_viewport_rid()
	var camera_direction := -1.0
	while (Time.get_ticks_usec() - started) / 1000000.0 < seconds:
		await process_frame
		var now := Time.get_ticks_usec()
		var delta := (now - previous) / 1000000.0
		previous = now
		frames_ms.append(delta * 1000.0)
		gpu_ms.append(RenderingServer.viewport_get_measured_render_time_gpu(viewport))
		render_cpu_ms.append(RenderingServer.viewport_get_measured_render_time_cpu(viewport) + RenderingServer.get_frame_setup_time_cpu())
		draws.append(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
		primitives.append(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME))
		if speed > 0.0:
			_camera.position.z += speed * delta * camera_direction
			if label == "travel_90":
				_route = _route.advanced(-speed * delta)
				_origin.recenter_if_needed(_route.to_scene(_origin.segment))
				_progression.update(_route)
				_water.recenter(Vector3(0.0, 3800.0, _route.to_scene(_origin.segment)))
			else:
				# Reverse inside the actual viewing sphere rather than profiling unreachable views.
				var relative_z := _camera.position.z - _route.to_scene(_origin.segment)
				if absf(relative_z) > 7000.0:
					_camera.position.z = _route.to_scene(_origin.segment) + clampf(relative_z, -7000.0, 7000.0)
					camera_direction *= -1.0
			stream_timer -= delta
			if stream_timer <= 0.0:
				stream_timer = 0.25
				_terrain.update_region(0.0, _route, _camera.global_position)
		backlog_peak = maxi(backlog_peak, _terrain._pending.size() + _terrain._jobs.size())
	var result := {
		"phase": label, "distance": _progression.distance, "frames": frames_ms.size(),
		"render_target": [root.get_texture().get_width(), root.get_texture().get_height()],
		"wall_frame_ms": _summary(frames_ms), "gpu_ms": _summary(gpu_ms), "render_cpu_ms": _summary(render_cpu_ms),
		"terrain_process_ms": _summary(_terrain.process_ms), "region_update_ms": _summary(_terrain.updates_ms),
		"mesh_upload_ms": _summary(_terrain.uploads_ms),
		"collider_build_max_ms": _terrain.maximum_collider_build_usec / 1000.0,
		"patch_build_ms": _build_summary(), "built_patches": _terrain.builds.size(),
		"backlog_peak": backlog_peak, "backlog_end": _terrain._pending.size() + _terrain._jobs.size(), "committed_layouts": _terrain.commits,
		"draw_calls": _summary(draws), "rendered_primitives": _summary(primitives), "geometry": _geometry(),
	}
	_results.append(result)
	print("PROFILE ", JSON.stringify(result))
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(_output.path_join("%d-%s.png" % [int(_progression.distance), label]))


func _build_summary() -> Dictionary:
	var by_size: Dictionary = {}
	for entry in _terrain.builds:
		if not by_size.has(entry.size):
			by_size[entry.size] = []
		by_size[entry.size].append(entry.ms)
	var result := {}
	for size: int in by_size:
		var values: Array[float] = []
		values.assign(by_size[size])
		result[size] = _summary(values)
	return result


func _geometry() -> Dictionary:
	var vertices := 0
	var triangles := 0
	var visible := 0
	for chunk in _terrain.chunks.values():
		vertices += chunk.mesh.surface_get_array_len(0)
		triangles += chunk.mesh.surface_get_array_index_len(0) / 3
		visible += int(chunk.visible)
	return {"patches": _terrain.chunks.size(), "visible_patches": visible, "source_colliders": _terrain.colliders.size(), "vertices": vertices, "triangles": triangles}


func _summary(values: Array[float]) -> Dictionary:
	if values.is_empty():
		return {}
	var sorted := values.duplicate()
	sorted.sort()
	var total := 0.0
	var over_budget := 0
	for value in sorted:
		total += value
		over_budget += int(value > 16.667)
	return {"n": sorted.size(), "mean": total / sorted.size(), "p50": sorted[sorted.size() / 2], "p95": sorted[int((sorted.size() - 1) * 0.95)], "p99": sorted[int((sorted.size() - 1) * 0.99)], "max": sorted.back(), "over_16_67": over_budget}
