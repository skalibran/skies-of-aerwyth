class_name VoxelTerrain
extends Node3D

class Patch:
	var x: int
	var segment: int
	var offset_z: int
	var size: int
	var priority: float

	func key() -> String:
		return "%d:%d:%d:%d" % [x, segment, offset_z, size]


class BuildJob:
	var patch: Patch
	var profile: TerrainProfile
	var journey_start: RoutePosition
	var task_id: int
	var arrays: Array
	var build_ms: float

	func run() -> void:
		var started := Time.get_ticks_usec()
		var worker_sampler := TerrainSampler.new(profile, journey_start)
		arrays = TerrainMeshBuilder.new().build_arrays(worker_sampler, patch.x, patch.segment, patch.offset_z, patch.size)
		build_ms = (Time.get_ticks_usec() - started) / 1000.0


@export var profile: TerrainProfile
@export var material: Material
@export var origin: FloatingOrigin
@export var progression: JourneyProgress
## Root coverage includes the 900-unit camera sphere and 3000-unit far plane.
@export_range(1, 8, 1) var chunk_radius: int = 4
## Larger values retain source voxels farther from the camera.
@export_range(1.0, 4.0, 0.25) var detail_distance: float = 2.0
@export_range(1.0, 8.0, 0.5) var build_budget_ms: float = 3.0
@export_range(1, 4, 1) var build_workers: int = 2

var sampler: TerrainSampler
var chunks: Dictionary[String, MeshInstance3D] = {}
var desired: Dictionary[String, Patch] = {}
var _pending: Array[Patch] = []
var _jobs: Dictionary[String, BuildJob] = {}
var _region_key: String = ""
var _initialized: bool = false
var _layout_dirty: bool = false


func _process(_delta: float) -> void:
	if _pending.is_empty() and _jobs.is_empty():
		return
	var deadline := Time.get_ticks_usec() + int(build_budget_ms * 1000.0)
	for key in _jobs.keys():
		if Time.get_ticks_usec() >= deadline:
			break
		if WorkerThreadPool.is_task_completed(_jobs[key].task_id):
			_finish_job(key)
	_dispatch_jobs()
	if _layout_dirty and not has_pending_work():
		_commit_region()


func _exit_tree() -> void:
	_discard_generation()


func _discard_generation() -> void:
	# Jobs own only private sampling data, never this node or live GPU resources.
	for job in _jobs.values():
		WorkerThreadPool.wait_for_task_completion(job.task_id)
	_jobs.clear()
	# Child exit unregisters origin roots. Do not keep stale views/queues on re-entry.
	for chunk in chunks.values():
		chunk.queue_free()
	chunks.clear()
	desired.clear()
	_pending.clear()
	sampler = null
	_region_key = ""
	_initialized = false
	_layout_dirty = false


func has_pending_work() -> bool:
	if not _pending.is_empty():
		return true
	for key in _jobs:
		if desired.has(key):
			return true
	return false


func update_region(world_x: float, route: RoutePosition, camera_position: Vector3) -> void:
	var root_size := profile.root_size()
	var root_x := floori(world_x / root_size)
	var root_z := TerrainGrid.tile_at(route, root_size)
	var view_route := RoutePosition.from_scene(camera_position.z, origin.segment)
	# Quantizing the LOD focus avoids new layouts for every tiny camera move.
	var focus_step := maxi(32, profile.voxel_size * 8)
	var view_x := floori(camera_position.x / focus_step) * focus_step
	view_route = TerrainGrid.cell_center(view_route, focus_step).advanced(-focus_step * 0.5)
	var view_y := floori(maxf(0.0, camera_position.y - profile.maximum_height()) / focus_step) * focus_step
	var region_key := "%d:%d:%d:%d:%d:%d" % [root_x, root_z, view_x, view_route.segment, int(view_route.offset), view_y]
	if _initialized and region_key == _region_key:
		return
	if sampler == null:
		sampler = TerrainSampler.new(profile, progression.start_position)
	if not _initialized:
		_build_initial_coverage(root_x, root_z)
	_region_key = region_key
	_layout_dirty = true
	desired.clear()
	_pending.clear()
	for z in range(-chunk_radius, chunk_radius + 1):
		for x in range(-chunk_radius, chunk_radius + 1):
			var start := TerrainGrid.tile_start(root_z + z, root_size)
			_select_patch((root_x + x) * root_size, start.segment, int(start.offset), root_size, view_x, view_route, view_y)
	# Visible coverage remains until replacements are ready. Discard obsolete staging.
	for key in chunks.keys():
		if not chunks[key].visible and not desired.has(key):
			_remove_chunk(key)
	_pending.sort_custom(func(a: Patch, b: Patch) -> bool: return a.priority < b.priority)
	var first := TerrainGrid.tile_start(root_z - chunk_radius, root_size)
	var last := TerrainGrid.tile_start(root_z + chunk_radius + 1, root_size)
	sampler.retain_segments(first.segment - 1, last.segment + 1)
	if not has_pending_work():
		_commit_region()
	_initialized = true


## Synchronous draining is for checks/offline tools. Runtime builds use worker jobs.
func build_pending(limit: int) -> void:
	for key in _jobs.keys():
		_finish_job(key)
	for index in range(mini(limit, _pending.size())):
		var patch: Patch = _pending.pop_front()
		_build_patch(patch)
	if _layout_dirty and not has_pending_work():
		_commit_region()


func _build_initial_coverage(root_x: int, root_z: int) -> void:
	# Coarse coverage appears immediately; source detail is refined in the background.
	var size := profile.root_size()
	for z in range(-chunk_radius, chunk_radius + 1):
		var start := TerrainGrid.tile_start(root_z + z, size)
		for x in range(-chunk_radius, chunk_radius + 1):
			var patch := Patch.new()
			patch.x = (root_x + x) * size
			patch.segment = start.segment
			patch.offset_z = int(start.offset)
			patch.size = size
			_build_patch(patch)
			chunks[patch.key()].visible = true


func _build_patch(patch: Patch) -> void:
	var started := Time.get_ticks_usec()
	var arrays := TerrainMeshBuilder.new().build_arrays(sampler, patch.x, patch.segment, patch.offset_z, patch.size)
	_publish_patch(patch, arrays, (Time.get_ticks_usec() - started) / 1000.0)


func _dispatch_jobs() -> void:
	while _jobs.size() < build_workers and not _pending.is_empty():
		var job := BuildJob.new()
		job.patch = _pending.pop_front()
		# FastNoiseLite and nested resources must not be shared with another worker.
		job.profile = profile.duplicate(true)
		job.journey_start = RoutePosition.new(progression.start_position.segment, progression.start_position.offset)
		job.task_id = WorkerThreadPool.add_task(job.run, false, "Terrain patch")
		_jobs[job.patch.key()] = job


func _finish_job(key: String) -> void:
	var job := _jobs[key]
	WorkerThreadPool.wait_for_task_completion(job.task_id)
	_jobs.erase(key)
	# Region changes can make a completed result obsolete. Never publish stale work.
	if desired.has(key) and not chunks.has(key):
		_publish_patch(job.patch, job.arrays, job.build_ms)


func _publish_patch(patch: Patch, arrays: Array, _build_ms: float) -> void:
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var chunk := MeshInstance3D.new()
	chunk.mesh = mesh
	chunk.material_override = material
	chunk.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	chunk.visible = false
	add_child(chunk)
	# Resolve the current origin here: it may have shifted while the job was running.
	chunk.global_position = Vector3(float(patch.x), 0.0, float(patch.segment - origin.segment) * RoutePosition.SEGMENT_LENGTH + patch.offset_z)
	origin.register_root(chunk)
	chunk.reset_physics_interpolation()
	chunks[patch.key()] = chunk


func _select_patch(x: int, segment: int, offset_z: int, size: int, view_x: int, view_route: RoutePosition, view_y: int) -> void:
	var local_z := float(segment - view_route.segment) * RoutePosition.SEGMENT_LENGTH + offset_z
	var dx := maxf(maxf(x - view_x, view_x - (x + size)), 0.0)
	var dz := maxf(maxf(local_z - view_route.offset, view_route.offset - (local_z + size)), 0.0)
	var distance_squared := dx * dx + dz * dz + view_y * view_y
	if size > TerrainProfile.CELLS_PER_PATCH * profile.voxel_size and distance_squared < pow(size * detail_distance, 2.0):
		var half := size / 2
		for z in range(2):
			for column in range(2):
				_select_patch(x + column * half, segment, offset_z + z * half, half, view_x, view_route, view_y)
		return
	var patch := Patch.new()
	patch.x = x
	var start := RoutePosition.new(segment, offset_z)
	patch.segment = start.segment
	patch.offset_z = int(start.offset)
	patch.size = size
	patch.priority = distance_squared
	var key := patch.key()
	desired[key] = patch
	if not chunks.has(key) and not _jobs.has(key):
		_pending.append(patch)


func _commit_region() -> void:
	_layout_dirty = false
	for key in chunks.keys():
		if not desired.has(key):
			_remove_chunk(key)
		else:
			chunks[key].visible = true


func _remove_chunk(key: String) -> void:
	origin.unregister_root(chunks[key])
	chunks[key].queue_free()
	chunks.erase(key)
