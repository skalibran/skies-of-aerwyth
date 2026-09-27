class_name CloudSpawner
extends Node3D

class Cell:
	var x: int
	var route: RoutePosition
	var layer_index: int
	var size: Vector2
	var row_shift: float

	func key() -> String:
		return "%d:%d:%d:%d" % [layer_index, x, route.segment, int(route.offset)]


@export var profile: CloudProfile
@export var material: ShaderMaterial
@export var origin: FloatingOrigin
@export var terrain: VoxelTerrain
@export var camera: Camera3D
## Start dissolving before entry and exclude these clouds from ship spawning.
@export_range(0.0, 500.0, 10.0, "suffix:m") var camera_proximity_distance: float = 100.0

var cells: Dictionary[String, MeshInstance3D] = {}
var meshes: Array[ArrayMesh] = []
var volumes: Dictionary[Mesh, CloudVolume] = {}
var cloud_layers: Dictionary[MeshInstance3D, CloudLayer] = {}
var _placement_sizes: Array[Vector2] = []
var _row_shifts: Dictionary[String, float] = {}
var _region_key: String = ""


func initialize(world_x: float, route: RoutePosition) -> void:
	profile.validate()
	if meshes.is_empty():
		for type_index in range(profile.types.size()):
			for variant in range(profile.variants_per_type):
				var builder := CloudMeshBuilder.new()
				var mesh := builder.build(profile.types[type_index], profile.world_seed + type_index * 7919 + variant * 101, profile.variant_span(variant), profile.voxel_size)
				mesh.surface_set_material(0, material)
				meshes.append(mesh)
				volumes[mesh] = builder.volume
	update_region(world_x, route)


func update_region(world_x: float, route: RoutePosition) -> void:
	if meshes.is_empty():
		return
	var sizes: Array[Vector2] = []
	var region_key := str(route.segment)
	for layer_index in range(profile.layers.size()):
		var size := _placement_size(layer_index)
		sizes.append(size)
		if size != Vector2.ZERO:
			region_key += ":%d:%d" % [floori(world_x / size.x), floori(route.offset / size.y)]
	if region_key == _region_key:
		return
	_region_key = region_key
	_placement_sizes = sizes
	_row_shifts.clear()
	var desired: Dictionary[String, Cell] = {}
	for layer_index in range(profile.layers.size()):
		var size := sizes[layer_index]
		if size == Vector2.ZERO:
			continue
		var center_x := floori(world_x / size.x)
		var center_z := floori(route.offset / size.y)
		var across := ceili(profile.field_half_width / size.x)
		# Each segment contains an integer number of rows, even at huge route indices.
		var rows_per_segment := roundi(RoutePosition.SEGMENT_LENGTH / size.y)
		for dz in range(-ceili(profile.look_ahead / size.y), ceili(profile.keep_behind / size.y) + 1):
			var row_index := center_z + dz
			var segment_delta := floori(float(row_index) / rows_per_segment)
			var local_row := posmod(row_index, rows_per_segment)
			var row := RoutePosition.new(route.segment + segment_delta, local_row * size.y)
			var row_shift := _row_shift(layer_index, row.segment, local_row, size.x)
			_row_shifts["%d:%d:%d" % [layer_index, row.segment, local_row]] = row_shift
			for x in range(center_x - across, center_x + across + 1):
				var cell := Cell.new()
				cell.x = x
				cell.route = row
				cell.layer_index = layer_index
				cell.size = size
				cell.row_shift = row_shift
				desired[cell.key()] = cell
	# Release old cells before filling the bounded region, including after jumps.
	for key in cells.keys():
		if not desired.has(key):
			if cells[key] != null:
				cloud_layers.erase(cells[key])
				origin.unregister_root(cells[key])
				cells[key].queue_free()
			cells.erase(key)
	for key in desired:
		if not cells.has(key):
			cells[key] = _spawn_cell(desired[key])


## Restrict to the authored layer and Z clearance, then rank by marker distance.
func closest_spawn_cloud(marker_position: Vector3, z_side: float, hull_radius: float, required_layer: CloudLayer = null, minimum_z_distance: float = 0.0) -> MeshInstance3D:
	var closest: MeshInstance3D
	var closest_distance: float = INF
	if not is_visible_in_tree():
		return null
	var fade_start: float = material.get_shader_parameter(&"distance_fade_start") if material != null else INF
	for cloud: MeshInstance3D in cells.values():
		if not is_instance_valid(cloud) or cloud.is_queued_for_deletion() or not cloud.is_visible_in_tree():
			continue
		if required_layer != null and cloud_layers.get(cloud) != required_layer:
			continue
		var bounds := cloud.mesh.get_aabb()
		if minf(bounds.size.x, minf(bounds.size.y, bounds.size.z)) <= hull_radius * 2.0:
			continue
		var center := cloud.global_position + bounds.get_center()
		if (center.z - marker_position.z) * z_side < maxf(0.001, minimum_z_distance):
			continue
		var coverage: Variant = cloud.get_instance_shader_parameter(&"camera_fade_coverage")
		if coverage != null and float(coverage) < 1.0:
			continue
		if is_instance_valid(camera):
			if _overlaps_cloud(cloud, camera.global_position, camera_proximity_distance):
				continue
			# The whole cloud must precede distance fading to conceal a spawn from every angle.
			var farthest_corner := (center - camera.global_position).abs() + bounds.size * 0.5
			if farthest_corner.length_squared() > fade_start * fade_start:
				continue
		var distance := center.distance_squared_to(marker_position)
		if distance < closest_distance:
			closest = cloud
			closest_distance = distance
	return closest


func sample_spawn_position(cloud: MeshInstance3D, hull_radius: float, rng: RandomNumberGenerator) -> Vector3:
	var bounds := cloud.mesh.get_aabb().grow(-hull_radius)
	var local_position := bounds.position + Vector3(rng.randf(), rng.randf(), rng.randf()) * bounds.size
	if not volumes[cloud.mesh].contains_sphere(local_position, hull_radius):
		return Vector3.INF
	return cloud.global_position + local_position


## Reuse the caller's array. Visit only placement slots touched by the query sphere.
func query_clouds(world_position: Vector3, result: Array[MeshInstance3D], proximity_distance: float = 0.0) -> void:
	result.clear()
	if not is_visible_in_tree() or origin == null:
		return
	var route := RoutePosition.from_scene(world_position.z, origin.segment)
	for layer_index in range(_placement_sizes.size()):
		var size := _placement_sizes[layer_index]
		if size == Vector2.ZERO:
			continue
		var padding := maxf(proximity_distance, profile.voxel_size * 0.5)
		var rows_per_segment := roundi(RoutePosition.SEGMENT_LENGTH / size.y)
		for row_index in range(floori((route.offset - padding) / size.y), floori((route.offset + padding) / size.y) + 1):
			var segment := route.segment + floori(float(row_index) / rows_per_segment)
			var local_row := posmod(row_index, rows_per_segment)
			var row_key := "%d:%d:%d" % [layer_index, segment, local_row]
			if not _row_shifts.has(row_key):
				continue
			var row_shift := _row_shifts[row_key]
			for cell_x in range(floori((world_position.x - row_shift - padding) / size.x), floori((world_position.x - row_shift + padding) / size.x) + 1):
				var key := "%d:%d:%d:%d" % [layer_index, cell_x, segment, int(local_row * size.y)]
				var cloud: MeshInstance3D = cells.get(key)
				if is_instance_valid(cloud) and not cloud.is_queued_for_deletion() and cloud.is_visible_in_tree():
					if _overlaps_cloud(cloud, world_position, proximity_distance):
						result.append(cloud)


func _overlaps_cloud(cloud: MeshInstance3D, world_position: Vector3, proximity_distance: float) -> bool:
	var local_position := world_position - cloud.global_position
	var volume := volumes[cloud.mesh]
	return volume.sample_density(local_position) > 0.0 or (proximity_distance > 0.0 and volume.intersects_sphere(local_position, proximity_distance))


func _row_shift(layer_index: int, segment: int, row_index: int, width: float) -> float:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("%d:%d:%d:%d" % [profile.world_seed, layer_index, segment, row_index])
	return rng.randf_range(-0.5, 0.5) * width


func _placement_size(layer_index: int) -> Vector2:
	var layer := profile.layers[layer_index]
	if layer.density <= 0.0:
		return Vector2.ZERO
	var footprint := Vector2.ZERO
	for type_index in range(profile.types.size()):
		var cloud_type := profile.types[type_index]
		if cloud_type.weight <= 0.0 or cloud_type.altitude_range.y < layer.altitude - layer.height_variation or cloud_type.altitude_range.x > layer.altitude + layer.height_variation:
			continue
		for variant in range(profile.variants_per_type):
			var bounds := meshes[type_index * profile.variants_per_type + variant].get_aabb().size
			footprint = footprint.max(Vector2(bounds.x, bounds.z))
	if footprint == Vector2.ZERO:
		return Vector2.ZERO
	var minimum := footprint + Vector2.ONE * profile.cloud_gap
	var target_area := float(profile.cell_size * profile.cell_size) / layer.density
	var size := minimum * maxf(1.0, sqrt(target_area / (minimum.x * minimum.y)))
	# Round row spacing up so a cloud and its clearance always fit inside one row.
	var rows := maxi(1, floori(RoutePosition.SEGMENT_LENGTH / size.y))
	size.y = RoutePosition.SEGMENT_LENGTH / rows
	size.x = maxf(minimum.x, target_area / size.y)
	return size


func _spawn_cell(cell: Cell) -> MeshInstance3D:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("%d:%s" % [profile.world_seed, cell.key()])
	var layer := profile.layers[cell.layer_index]
	var altitude := layer.altitude + rng.randf_range(-layer.height_variation, layer.height_variation)
	var type_index := profile.select_type(altitude, rng)
	if type_index < 0:
		return null
	var mesh := meshes[type_index * profile.variants_per_type + rng.randi_range(0, profile.variants_per_type - 1)]
	var bounds := mesh.get_aabb()
	var span := maxf(bounds.size.x, bounds.size.z)
	var footprint := Vector2(bounds.size.x, bounds.size.z)
	var freedom := ((cell.size - footprint - Vector2.ONE * profile.cloud_gap) * 0.5).max(Vector2.ZERO)
	freedom = freedom.min(cell.size * 0.2)
	var center := bounds.get_center()
	var route := cell.route.advanced(cell.size.y * 0.5 + rng.randf_range(-freedom.y, freedom.y) - center.z)
	var x := (cell.x + 0.5) * cell.size.x + cell.row_shift + rng.randf_range(-freedom.x, freedom.x) - center.x
	if not _clears_landscape(x, route, altitude, span):
		return null
	var cloud := MeshInstance3D.new()
	cloud.name = profile.types[type_index].display_name
	cloud.mesh = mesh
	cloud.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	cloud_layers[cloud] = layer
	add_child(cloud)
	cloud.global_position = Vector3(x, altitude, route.to_scene(origin.segment))
	cloud.reset_physics_interpolation()
	origin.register_root(cloud)
	return cloud


func _clears_landscape(x: float, route: RoutePosition, altitude: float, span: float) -> bool:
	if terrain == null or terrain.sampler == null:
		return true
	# Sample the center and a conservative margin around the cloud footprint.
	var radius := span * 0.71
	for dx: float in [-radius, 0.0, radius]:
		for dz: float in [-radius, 0.0, radius]:
			if terrain.sampler.surface_height(x + dx, route.advanced(dz)) + profile.ground_clearance > altitude:
				return false
	return true


func _exit_tree() -> void:
	# Children unregister through FloatingOrigin's lifetime connection.
	for cloud in cells.values():
		if is_instance_valid(cloud):
			cloud.queue_free()
	cells.clear()
	cloud_layers.clear()
	meshes.clear()
	volumes.clear()
	_placement_sizes.clear()
	_row_shifts.clear()
	_region_key = ""
