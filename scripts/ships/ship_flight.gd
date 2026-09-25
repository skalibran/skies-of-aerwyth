class_name ShipFlight
extends RefCounted

var yaw_velocity: float = 0.0


func primary_axis(ship: Airship) -> Vector3:
	var axis := Vector3(ship.primary_movement_direction.x, 0.0, ship.primary_movement_direction.z)
	return axis.normalized() if axis.length_squared() > 0.0001 else Vector3.FORWARD


func integrate(ship: Airship, desired: Vector3, delta: float) -> Vector3:
	if delta <= 0.0:
		return ship.velocity
	var horizontal := Vector3(desired.x, 0.0, desired.z).limit_length(ship.maximum_speed)
	_turn(ship, horizontal, delta)
	var forward := ship.global_basis * primary_axis(ship)
	var movement := Vector3(ship.velocity.x, 0.0, ship.velocity.z)
	var longitudinal := movement.dot(forward)
	var lateral := movement - forward * longitudinal
	# Turning redirects propulsion, never the velocity already carried by the hull.
	# Reduce throttle into a sharp turn so navigation can negotiate tight corners.
	var alignment := maxf(0.0, forward.dot(horizontal.normalized()))
	var requested_speed := horizontal.length() * alignment * alignment
	var rate := ship.acceleration if requested_speed > longitudinal else ship.braking
	longitudinal = move_toward(longitudinal, requested_speed, rate * delta)
	lateral *= exp(-ship.lateral_drag * delta)
	var result := forward * longitudinal + lateral
	result.y = move_toward(ship.velocity.y, clampf(desired.y, -ship.climb_speed, ship.climb_speed), ship.acceleration * delta)
	return result.limit_length(ship.maximum_speed)


func _turn(ship: Airship, desired: Vector3, delta: float) -> void:
	var angular_acceleration := deg_to_rad(ship.yaw_acceleration_degrees)
	var maximum_rate := deg_to_rad(ship.yaw_speed_degrees)
	var error: float = 0.0
	if desired.length_squared() > 0.01:
		var primary := primary_axis(ship)
		var heading := atan2(-desired.x, -desired.z) - atan2(-primary.x, -primary.z)
		error = wrapf(heading - ship.rotation.y, -PI, PI)
	# Brake rotation before reaching the requested heading, as with linear arrival.
	var requested_rate := signf(error) * minf(maximum_rate, sqrt(2.0 * angular_acceleration * absf(error)))
	yaw_velocity = move_toward(yaw_velocity, requested_rate, angular_acceleration * delta)
	var turn := yaw_velocity * delta
	if desired.length_squared() > 0.01 and turn * error >= 0.0 and absf(turn) >= absf(error):
		turn = error
		yaw_velocity = 0.0
	ship.rotation.y = wrapf(ship.rotation.y + turn, -PI, PI)
