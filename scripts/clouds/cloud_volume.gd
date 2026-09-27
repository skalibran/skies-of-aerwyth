class_name CloudVolume
extends RefCounted

var dimensions: Vector3i
var filled: PackedByteArray
var local_origin: Vector3
var voxel_size: float


## Test a camera proximity sphere against nearby filled voxel boxes.
func intersects_sphere(local_position: Vector3, radius: float) -> bool:
	var point := (local_position - local_origin) / voxel_size
	var cell_radius := maxf(0.0, radius) / voxel_size
	var radius_squared := cell_radius * cell_radius
	if point.distance_squared_to(point.clamp(Vector3.ZERO, Vector3(dimensions))) > radius_squared:
		return false
	# Include boxes touching either end of the sphere, even on exact grid boundaries.
	var minimum := (Vector3i((point - Vector3.ONE * cell_radius).ceil()) - Vector3i.ONE).max(Vector3i.ZERO)
	var maximum := Vector3i((point + Vector3.ONE * cell_radius).floor()).min(dimensions - Vector3i.ONE)
	for z in range(minimum.z, maximum.z + 1):
		for y in range(minimum.y, maximum.y + 1):
			for x in range(minimum.x, maximum.x + 1):
				if not filled[(z * dimensions.y + y) * dimensions.x + x]:
					continue
				var closest := point.clamp(Vector3(x, y, z), Vector3(x + 1, y + 1, z + 1))
				if point.distance_squared_to(closest) <= radius_squared:
					return true
	return false


## A conservative hull sphere must fit entirely inside occupied voxels.
func contains_sphere(local_position: Vector3, radius: float) -> bool:
	var point := (local_position - local_origin) / voxel_size
	var cell_radius := radius / voxel_size
	var minimum := Vector3i((point - Vector3.ONE * cell_radius).floor())
	var maximum := Vector3i((point + Vector3.ONE * cell_radius).floor())
	if minimum.x < 0 or minimum.y < 0 or minimum.z < 0 or maximum.x >= dimensions.x or maximum.y >= dimensions.y or maximum.z >= dimensions.z:
		return false
	for z in range(minimum.z, maximum.z + 1):
		for y in range(minimum.y, maximum.y + 1):
			for x in range(minimum.x, maximum.x + 1):
				if filled[(z * dimensions.y + y) * dimensions.x + x]:
					continue
				var closest := point.clamp(Vector3(x, y, z), Vector3(x + 1, y + 1, z + 1))
				if point.distance_squared_to(closest) <= cell_radius * cell_radius:
					return false
	return true


## Interpolate the mesh's occupancy over one voxel at exposed surfaces.
func sample_density(local_position: Vector3) -> float:
	var point := (local_position - local_origin) / voxel_size - Vector3.ONE * 0.5
	if point.x < -1.0 or point.y < -1.0 or point.z < -1.0 or point.x >= dimensions.x or point.y >= dimensions.y or point.z >= dimensions.z:
		return 0.0
	var cell := Vector3i(point.floor())
	var weight := point - Vector3(cell)
	var density: float = 0.0
	for z in range(2):
		for y in range(2):
			for x in range(2):
				var sample_cell := cell + Vector3i(x, y, z)
				if sample_cell.x < 0 or sample_cell.y < 0 or sample_cell.z < 0 or sample_cell.x >= dimensions.x or sample_cell.y >= dimensions.y or sample_cell.z >= dimensions.z:
					continue
				if filled[(sample_cell.z * dimensions.y + sample_cell.y) * dimensions.x + sample_cell.x]:
					density += (weight.x if x else 1.0 - weight.x) * (weight.y if y else 1.0 - weight.y) * (weight.z if z else 1.0 - weight.z)
	return clampf(density, 0.0, 1.0)
