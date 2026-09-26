class_name ShipFlight
extends RefCounted


static func primary_axis(ship: Airship) -> Vector3:
	var axis := Vector3(ship.primary_movement_direction.x, 0.0, ship.primary_movement_direction.z)
	return axis.normalized() if axis.length_squared() > 0.0001 else Vector3.FORWARD


static func apply_forces(ship: Airship, desired: Vector3, delta: float) -> void:
	if delta <= 0.0 or ship.freeze:
		return
	ship.apply_central_force(_acceleration(ship, desired, delta) * ship.mass)
	# Upright hulls rotate only about world Y. Use the body's actual inertia so
	# authored angular acceleration has the same meaning for different hull masses.
	var inverse_yaw_inertia := ship.get_inverse_inertia_tensor().y.y
	if inverse_yaw_inertia > 0.0:
		ship.apply_torque(Vector3.UP * _yaw_acceleration(ship, desired, delta) / inverse_yaw_inertia)


static func _acceleration(ship: Airship, desired: Vector3, delta: float) -> Vector3:
	var lift_limit := minf(ship.climb_speed, ship.maximum_speed)
	var lift_speed := clampf(desired.y, -lift_limit, lift_limit)
	var horizontal_limit := sqrt(maxf(0.0, ship.maximum_speed * ship.maximum_speed - lift_speed * lift_speed))
	var horizontal := Vector3(desired.x, 0.0, desired.z).limit_length(horizontal_limit)
	var forward := ship.global_basis * primary_axis(ship)
	var movement := Vector3(ship.linear_velocity.x, 0.0, ship.linear_velocity.z)
	var longitudinal := movement.dot(forward)
	var lateral := movement - forward * longitudinal
	# Propulsion follows the hull; existing momentum and collision impulses stay
	# with the physics body. Turning reduces throttle instead of rotating velocity.
	var alignment := maxf(0.0, forward.dot(horizontal.normalized()))
	var requested_speed := horizontal.length() * alignment * alignment
	var rate := ship.acceleration if requested_speed > longitudinal else ship.braking
	var thrust := clampf((requested_speed - longitudinal) / delta, -rate, rate)
	var result := forward * thrust - lateral * (1.0 - exp(-ship.lateral_drag * delta)) / delta
	result.y = clampf((lift_speed - ship.linear_velocity.y) / delta, -ship.acceleration, ship.acceleration)
	return result


static func _yaw_acceleration(ship: Airship, desired: Vector3, delta: float) -> float:
	var angular_acceleration := deg_to_rad(ship.yaw_acceleration_degrees)
	var maximum_rate := deg_to_rad(ship.yaw_speed_degrees)
	var error: float = 0.0
	if Vector2(desired.x, desired.z).length_squared() > 1.0:
		var primary := primary_axis(ship)
		var heading := atan2(-desired.x, -desired.z) - atan2(-primary.x, -primary.z)
		error = wrapf(heading - ship.global_rotation.y, -PI, PI)
	# Brake before reaching the desired heading. Contact-induced spin is corrected
	# through bounded torque, never erased by assigning a scripted angular velocity.
	var requested_rate := signf(error) * minf(maximum_rate, sqrt(2.0 * angular_acceleration * absf(error)))
	return clampf((requested_rate - ship.angular_velocity.y) / delta, -angular_acceleration, angular_acceleration)
