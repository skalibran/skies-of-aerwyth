class_name ShipAvoidance
extends RefCounted

const HORIZON: float = 2.0
const COMFORT_MARGIN: float = 0.8
const MAX_CORRECTION: float = 5.0


static func correction(index: int, ships: Array[Airship], positions: PackedVector3Array, velocities: PackedVector3Array, axes: PackedVector3Array) -> Vector3:
	var ship := ships[index]
	var result := Vector3.ZERO
	for other_index in range(ships.size()):
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
