class_name TerrainMeshBuilder
extends RefCounted

var _vertices := PackedVector3Array()
var _normals := PackedVector3Array()
var _colors := PackedColorArray()
var _indices := PackedInt32Array()


func build(sampler: TerrainSampler, world_x: int, segment_z: int, offset_z: int, size: int, seal_edges: bool = true) -> ArrayMesh:
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, build_arrays(sampler, world_x, segment_z, offset_z, size, seal_edges))
	return mesh


## Worker jobs return plain mesh arrays; GPU resources are created on the main thread.
func build_arrays(sampler: TerrainSampler, world_x: int, segment_z: int, offset_z: int, size: int, seal_edges: bool = true) -> Array:
	_vertices.clear()
	_normals.clear()
	_colors.clear()
	_indices.clear()
	var count := TerrainProfile.CELLS_PER_PATCH
	var width := float(size) / count
	assert(width >= sampler.profile.voxel_size and is_zero_approx(fmod(width, sampler.profile.voxel_size)))
	var stride := count + 2
	var heights := PackedFloat32Array()
	var bands := PackedFloat32Array()
	var blends := PackedFloat32Array()
	var colors := PackedColorArray()
	heights.resize(stride * stride)
	bands.resize(stride * stride)
	blends.resize(stride)
	colors.resize(stride * stride)
	# A halo samples neighbors independently of which meshes are currently loaded.
	for z in range(-1, count + 1):
		var sample_route := TerrainGrid.cell_center(RoutePosition.new(segment_z, offset_z + (z + 0.5) * width), sampler.profile.voxel_size)
		var blend := sampler.mountain_weight(sample_route.segment, sample_route.offset)
		blends[z + 1] = blend
		for x in range(-1, count + 1):
			# Coarse display cells still sample the authoritative source grid.
			var sample_x := floorf((world_x + (x + 0.5) * width) / sampler.profile.voxel_size) * sampler.profile.voxel_size + sampler.profile.voxel_size * 0.5
			var noise := sampler.sample(sample_x, sample_route.segment, sample_route.offset)
			var index := (z + 1) * stride + x + 1
			heights[index] = sampler.height_from_noise(noise, blend)
			bands[index] = noise.z
			colors[index] = sampler.color_at(heights[index], noise.z, blend)
	_tops(count, width, heights, colors)
	for z in range(count):
		for x in range(count):
			var index := (z + 1) * stride + x + 1
			var corner := Vector3(x * width, heights[index], z * width)
			_wall(sampler, corner, Vector3.BACK * width, Vector3.LEFT, heights[index - 1], bands[index], blends[z + 1])
			_wall(sampler, corner + Vector3(width, 0.0, width), Vector3.FORWARD * width, Vector3.RIGHT, heights[index + 1], bands[index], blends[z + 1])
			_wall(sampler, corner + Vector3.RIGHT * width, Vector3.LEFT * width, Vector3.FORWARD, heights[index - stride], bands[index], blends[z + 1])
			_wall(sampler, corner + Vector3.BACK * width, Vector3.RIGHT * width, Vector3.BACK, heights[index + stride], bands[index], blends[z + 1])
	if seal_edges:
		_seal_edges(sampler.profile, count, width, heights, colors)
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = _vertices
	arrays[Mesh.ARRAY_NORMAL] = _normals
	arrays[Mesh.ARRAY_COLOR] = _colors
	arrays[Mesh.ARRAY_INDEX] = _indices
	return arrays


func _tops(count: int, width: float, heights: PackedFloat32Array, colors: PackedColorArray) -> void:
	var stride := count + 2
	var used := PackedByteArray()
	used.resize(count * count)
	# Merge only flat rectangles with identical color. Voxel outlines stay exact.
	for z in range(count):
		for x in range(count):
			if used[z * count + x]:
				continue
			var index := (z + 1) * stride + x + 1
			var height := heights[index]
			var color := colors[index]
			var run_x := 1
			while x + run_x < count and not used[z * count + x + run_x] and heights[index + run_x] == height and colors[index + run_x] == color:
				run_x += 1
			var run_z := 1
			var extend := true
			while z + run_z < count and extend:
				for dx in range(run_x):
					var next := index + run_z * stride + dx
					if used[(z + run_z) * count + x + dx] or heights[next] != height or colors[next] != color:
						extend = false
						break
				if extend:
					run_z += 1
			for dz in range(run_z):
				for dx in range(run_x):
					used[(z + dz) * count + x + dx] = 1
			_quad(Vector3(x * width, height, z * width), Vector3.RIGHT * run_x * width, Vector3.BACK * run_z * width, Vector3.UP, color)


func _wall(sampler: TerrainSampler, top: Vector3, edge: Vector3, normal: Vector3, bottom: float, band_noise: float, blend: float) -> void:
	if top.y <= bottom:
		return
	var height := top.y
	var run_top := height
	var color := sampler.color_at(height, band_noise, blend).darkened(sampler.profile.cliff_darkening)
	while height > bottom:
		var next_height := maxf(bottom, height - sampler.profile.voxel_size)
		var next_color := sampler.color_at(next_height, band_noise, blend).darkened(sampler.profile.cliff_darkening)
		if next_height == bottom or next_color != color:
			_quad(Vector3(top.x, run_top, top.z), edge, Vector3.DOWN * (run_top - next_height), normal, color)
			run_top = next_height
			color = next_color
		height = next_height


func _seal_edges(profile: TerrainProfile, count: int, width: float, heights: PackedFloat32Array, colors: PackedColorArray) -> void:
	var stride := count + 2
	var size := count * width
	for cell in range(count):
		var left := (cell + 1) * stride + 1
		var right := left + count - 1
		var front := stride + cell + 1
		var back := count * stride + cell + 1
		# Skirts start below regular walls to avoid coplanar duplicate faces.
		_skirt(Vector3(0.0, minf(heights[left], heights[left - 1]), cell * width), Vector3.BACK * width, Vector3.LEFT, colors[left], profile)
		_skirt(Vector3(size, minf(heights[right], heights[right + 1]), (cell + 1) * width), Vector3.FORWARD * width, Vector3.RIGHT, colors[right], profile)
		_skirt(Vector3((cell + 1) * width, minf(heights[front], heights[front - stride]), 0.0), Vector3.LEFT * width, Vector3.FORWARD, colors[front], profile)
		_skirt(Vector3(cell * width, minf(heights[back], heights[back + stride]), size), Vector3.RIGHT * width, Vector3.BACK, colors[back], profile)


func _skirt(top: Vector3, edge: Vector3, normal: Vector3, color: Color, profile: TerrainProfile) -> void:
	var depth := top.y - profile.minimum_height()
	if depth > 0.0:
		_quad(top, edge, Vector3.DOWN * depth, normal, color.darkened(profile.cliff_darkening))


func _quad(corner: Vector3, u: Vector3, v: Vector3, normal: Vector3, color: Color) -> void:
	var start := _vertices.size()
	_vertices.append_array(PackedVector3Array([corner, corner + u, corner + u + v, corner + v]))
	for vertex in range(4):
		_normals.append(normal)
		_colors.append(color)
	# Godot front faces are clockwise; u cross v points into the solid.
	_indices.append_array(PackedInt32Array([start, start + 1, start + 2, start, start + 2, start + 3]))
