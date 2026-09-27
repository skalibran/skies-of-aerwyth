class_name CloudMeshBuilder
extends RefCounted

var volume: CloudVolume
var _vertices := PackedVector3Array()
var _normals := PackedVector3Array()
var _indices := PackedInt32Array()


## Build the final dimensions from fixed-size cubes. Instances need no scaling.
func build(cloud_type: CloudType, shape_seed: int, span: float, voxel_size: float) -> ArrayMesh:
	cloud_type.validate()
	assert(voxel_size > 0.0 and span >= voxel_size * 2.0)
	assert(is_equal_approx(span, snappedf(span, voxel_size)))
	_vertices.clear()
	_normals.clear()
	_indices.clear()
	var width := roundi(span / voxel_size)
	var dimensions := Vector3i(width, maxi(2, roundi(width * cloud_type.height_ratio)), maxi(2, roundi(width * cloud_type.depth_ratio)))
	var filled := _sample_shape(cloud_type, shape_seed, dimensions)
	var grid := _fit_to_span(filled, dimensions, width)
	for axis in range(3):
		for direction: int in [-1, 1]:
			_merge_faces(grid.filled, grid.dimensions, axis, direction)
	assert(not _vertices.is_empty(), "Cloud parameters must produce a visible shape.")
	var bounds := AABB(_vertices[0], Vector3.ZERO)
	for vertex in _vertices:
		bounds = bounds.expand(vertex)
	# Keep the pivot on a voxel boundary, including for odd voxel counts.
	var center := bounds.position + (bounds.size * Vector3(0.5, 0.0, 0.5)).floor()
	grid.local_origin = -center * voxel_size
	grid.voxel_size = voxel_size
	volume = grid
	var colors := PackedColorArray()
	for index in range(_vertices.size()):
		var height := (_vertices[index].y - bounds.position.y) / maxf(bounds.size.y, 1.0)
		colors.append(cloud_type.base_color.lerp(cloud_type.top_color, smoothstep(0.0, 0.85, height)))
		_vertices[index] = (_vertices[index] - center) * voxel_size
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = _vertices
	arrays[Mesh.ARRAY_NORMAL] = _normals
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = _indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


func _sample_shape(cloud_type: CloudType, shape_seed: int, dimensions: Vector3i) -> PackedByteArray:
	var rng := RandomNumberGenerator.new()
	rng.seed = shape_seed
	var noise := FastNoiseLite.new()
	noise.seed = shape_seed
	noise.frequency = 0.19
	var centers := PackedVector3Array()
	var radii := PackedVector3Array()
	for puff in range(cloud_type.puff_count):
		var size_variation := rng.randf_range(0.6, 1.25)
		var radius := cloud_type.puff_size * size_variation
		var puff_radii := Vector3(radius, minf(0.9, 0.7 * size_variation), minf(0.9, radius / cloud_type.depth_ratio))
		# Spread lobes across the footprint. Smaller lobes rise less from a common base.
		var along := (float(puff) + rng.randf_range(0.2, 0.8)) / cloud_type.puff_count
		var center := Vector3(lerpf(-0.8, 0.8, along), -0.75 + puff_radii.y, rng.randf_range(-0.65, 0.65))
		# Keep rounded puff tips inside the sample box instead of clipping flat tops.
		var limit := Vector3.ONE * 0.98 - puff_radii
		centers.append(center.clamp(-limit, limit))
		radii.append(puff_radii)
	var filled := PackedByteArray()
	filled.resize(dimensions.x * dimensions.y * dimensions.z)
	for z in range(dimensions.z):
		for y in range(dimensions.y):
			for x in range(dimensions.x):
				var cell := Vector3i(x, y, z)
				var point := (Vector3(cell) + Vector3.ONE * 0.5) / Vector3(dimensions) * 2.0 - Vector3.ONE
				if point.y < cloud_type.base_cut:
					continue
				point.z += sin(point.x * 4.0 + float(shape_seed % 100)) * cloud_type.curl
				# Only the lobes fill space, leaving scalloped edges and gaps between puffs.
				var distance: float = INF
				for puff in range(centers.size()):
					distance = minf(distance, ((point - centers[puff]) / radii[puff]).length_squared())
				if distance < 1.0 + noise.get_noise_3d(x, y, z) * cloud_type.erosion:
					filled[_index(cell, dimensions)] = 1
	return filled


func _fit_to_span(filled: PackedByteArray, dimensions: Vector3i, width: int) -> CloudVolume:
	var minimum := dimensions
	var maximum := Vector3i(-1, -1, -1)
	for z in range(dimensions.z):
		for y in range(dimensions.y):
			for x in range(dimensions.x):
				var cell := Vector3i(x, y, z)
				if filled[_index(cell, dimensions)]:
					minimum = minimum.min(cell)
					maximum = maximum.max(cell)
	assert(maximum.x >= 0, "Cloud parameters must produce a visible shape.")
	var occupied := maximum - minimum + Vector3i.ONE
	var fit := float(width) / maxi(occupied.x, occupied.z)
	var grid := CloudVolume.new()
	grid.dimensions = Vector3i((Vector3(occupied) * fit).round())
	grid.filled.resize(grid.dimensions.x * grid.dimensions.y * grid.dimensions.z)
	# Remove empty margins by resampling occupancy onto the final integer grid.
	# Every emitted cube still has the same physical width on all three axes.
	var sample_step := Vector3(occupied) / Vector3(grid.dimensions)
	for z in range(grid.dimensions.z):
		for y in range(grid.dimensions.y):
			for x in range(grid.dimensions.x):
				var cell := Vector3i(x, y, z)
				var source := minimum + Vector3i((Vector3(cell) + Vector3.ONE * 0.5) * sample_step)
				grid.filled[_index(cell, grid.dimensions)] = filled[_index(source, dimensions)]
	return grid


func _merge_faces(filled: PackedByteArray, dimensions: Vector3i, axis: int, direction: int) -> void:
	var u_axis := (axis + 1) % 3
	var v_axis := (axis + 2) % 3
	var width := dimensions[u_axis]
	var depth := dimensions[v_axis]
	var normal := Vector3.ZERO
	normal[axis] = direction
	for slice in range(dimensions[axis]):
		var mask := PackedByteArray()
		mask.resize(width * depth)
		for v in range(depth):
			for u in range(width):
				var cell := Vector3i.ZERO
				cell[axis] = slice
				cell[u_axis] = u
				cell[v_axis] = v
				if not filled[_index(cell, dimensions)]:
					continue
				var neighbor := cell
				neighbor[axis] += direction
				if neighbor[axis] < 0 or neighbor[axis] >= dimensions[axis] or not filled[_index(neighbor, dimensions)]:
					mask[v * width + u] = 1
		for v in range(depth):
			for u in range(width):
				if not mask[v * width + u]:
					continue
				var run_u := 1
				while u + run_u < width and mask[v * width + u + run_u]:
					run_u += 1
				var run_v := 1
				var extend := true
				while v + run_v < depth and extend:
					for offset in range(run_u):
						if not mask[(v + run_v) * width + u + offset]:
							extend = false
							break
					if extend:
						run_v += 1
				for dv in range(run_v):
					for du in range(run_u):
						mask[(v + dv) * width + u + du] = 0
				var corner := Vector3.ZERO
				corner[axis] = slice + (1 if direction > 0 else 0)
				corner[u_axis] = u
				corner[v_axis] = v
				var edge_u := Vector3.ZERO
				var edge_v := Vector3.ZERO
				edge_u[u_axis] = run_u
				edge_v[v_axis] = run_v
				# Godot front faces are clockwise when viewed from outside.
				if direction > 0:
					_quad(corner, edge_v, edge_u, normal)
				else:
					_quad(corner, edge_u, edge_v, normal)


func _index(cell: Vector3i, dimensions: Vector3i) -> int:
	return (cell.z * dimensions.y + cell.y) * dimensions.x + cell.x


func _quad(corner: Vector3, u: Vector3, v: Vector3, normal: Vector3) -> void:
	var start := _vertices.size()
	_vertices.append_array(PackedVector3Array([corner, corner + u, corner + u + v, corner + v]))
	for vertex in range(4):
		_normals.append(normal)
	_indices.append_array(PackedInt32Array([start, start + 1, start + 2, start, start + 2, start + 3]))
