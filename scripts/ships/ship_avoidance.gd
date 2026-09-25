class_name ShipAvoidance
extends RefCounted

const HORIZON: float = 2.0
const COMFORT_MARGIN: float = 0.8
const MAX_CORRECTION: float = 5.0

var _cells: Dictionary[Vector3i, PackedInt32Array] = {}
var _cell_size: float = 1.0
var _candidates := PackedInt32Array()


func prepare_neighbors(ships: Array[Airship], positions: PackedVector3Array, velocities: PackedVector3Array) -> void:
	_cells.clear()
	var maximum_extent: float = 0.0
	var maximum_speed: float = 0.0
	for index in range(ships.size()):
		maximum_extent = maxf(maximum_extent, ships[index].hull_half_segment + ships[index].hull_radius)
		maximum_speed = maxf(maximum_speed, velocities[index].length())
	# Any pair that could interact within the existing horizon must be in this
	# cell or an adjacent one. Rebuild from the common snapshot after any rebase.
	_cell_size = maxf(1.0, 2.0 * maximum_extent + 2.0 * maximum_speed * HORIZON + COMFORT_MARGIN)
	for index in range(positions.size()):
		var cell := Vector3i((positions[index] / _cell_size).floor())
		var indices: PackedInt32Array = _cells.get(cell, PackedInt32Array())
		indices.append(index)
		_cells[cell] = indices


func neighbors(position: Vector3) -> PackedInt32Array:
	_candidates.clear()
	var cell := Vector3i((position / _cell_size).floor())
	for x in range(-1, 2):
		for y in range(-1, 2):
			for z in range(-1, 2):
				var key := cell + Vector3i(x, y, z)
				if _cells.has(key):
					_candidates.append_array(_cells[key])
	# Preserve the accumulation order of the original all-ship scan.
	_candidates.sort()
	return _candidates


static func correction(index: int, ships: Array[Airship], positions: PackedVector3Array, velocities: PackedVector3Array, axes: PackedVector3Array, candidates: PackedInt32Array = PackedInt32Array()) -> Vector3:
	var ship := ships[index]
	var result := Vector3.ZERO
	# Queries include the ship itself, so an empty argument unambiguously requests
	# the full scan used by isolated checks and by the broad-phase regression oracle.
	var full_scan := candidates.is_empty()
	for candidate in range(ships.size() if full_scan else candidates.size()):
		var other_index: int = candidate if full_scan else candidates[candidate]
		if index == other_index:
			continue
		var other := ships[other_index]
		var relative_position := positions[index] - positions[other_index]
		var relative_velocity := velocities[index] - velocities[other_index]
		var reach := ship.hull_half_segment + other.hull_half_segment + ship.hull_radius + other.hull_radius + COMFORT_MARGIN
		if relative_position.length() > reach + relative_velocity.length() * HORIZON:
			continue
		var approach_time: float = 0.0
		if relative_velocity.length_squared() > 0.001:
			approach_time = clampf(-relative_position.dot(relative_velocity) / relative_velocity.length_squared(), 0.0, HORIZON)
		var first := positions[index] + velocities[index] * approach_time
		var second := positions[other_index] + velocities[other_index] * approach_time
		# The hull capsules cannot meet if their enclosing spheres are separated
		# at the same predicted instant used by the exact segment calculation.
		if first.distance_squared_to(second) >= reach * reach:
			continue
		var first_axis := axes[index] * ship.hull_half_segment
		var second_axis := axes[other_index] * other.hull_half_segment
		var closest := Geometry3D.get_closest_points_between_segments(first - first_axis, first + first_axis, second - second_axis, second + second_axis)
		var separation: Vector3 = closest[0] - closest[1]
		var clearance := ship.hull_radius + other.hull_radius + COMFORT_MARGIN
		var distance := separation.length()
		if distance >= clearance:
			continue
		var direction := separation / distance if distance > 0.05 else _passing_side(ship.entity_id, other.entity_id)
		# Exact head-on approaches need lateral steering rather than mutual braking.
		if relative_velocity.length_squared() > 0.1 and absf(direction.dot(relative_velocity.normalized())) > 0.85:
			direction = _passing_side(ship.entity_id, other.entity_id)
		var urgency := (1.0 - distance / clearance) * (1.0 - 0.5 * approach_time / HORIZON)
		result += direction * urgency * MAX_CORRECTION
	return result.limit_length(MAX_CORRECTION)


static func _passing_side(first_id: int, second_id: int) -> Vector3:
	return Vector3.RIGHT if first_id < second_id else Vector3.LEFT
