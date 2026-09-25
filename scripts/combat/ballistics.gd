class_name Ballistics
extends RefCounted

const MIN_TIME: float = 0.0001
const ROOT_ITERATIONS: int = 28


static func intercept_time(relative: Vector3, target_velocity: Vector3, speed: float, gravity: float, lifetime: float) -> float:
	if not relative.is_finite() or not target_velocity.is_finite():
		return -1.0
	if not is_finite(speed) or not is_finite(gravity) or not is_finite(lifetime):
		return -1.0
	if speed <= 0.0 or gravity < 0.0 or lifetime <= MIN_TIME or relative.length_squared() < 0.000001:
		return -1.0
	var acceleration := Vector3.DOWN * gravity
	var coefficients := PackedFloat64Array([
		relative.length_squared(), 2.0 * relative.dot(target_velocity),
		target_velocity.length_squared() - relative.dot(acceleration) - speed * speed,
		-target_velocity.dot(acceleration), 0.25 * acceleration.length_squared(),
	])
	var roots := _roots_between(coefficients, MIN_TIME, lifetime)
	for time in roots:
		var launch := launch_velocity(relative, target_velocity, gravity, time)
		if launch.is_finite() and absf(launch.length() - speed) < 0.001:
			return time
	return -1.0


static func launch_velocity(relative: Vector3, target_velocity: Vector3, gravity: float, time: float) -> Vector3:
	return (relative + target_velocity * time - Vector3.DOWN * (0.5 * gravity * time * time)) / time


static func displacement(velocity: Vector3, gravity: float, delta: float) -> Vector3:
	return velocity * delta + Vector3.DOWN * (0.5 * gravity * delta * delta)


# Derivative roots partition this degree-at-most-four polynomial into monotonic
# intervals. Checking the boundaries also finds tangent roots without a sign flip.
static func _roots_between(coefficients: PackedFloat64Array, start: float, end: float) -> PackedFloat64Array:
	while coefficients.size() > 1 and absf(coefficients[-1]) < 0.000000000001:
		coefficients.resize(coefficients.size() - 1)
	var degree := coefficients.size() - 1
	var roots := PackedFloat64Array()
	if degree == 0:
		return roots
	if degree == 1:
		var root := -coefficients[0] / coefficients[1]
		if root >= start and root <= end:
			roots.append(root)
		return roots
	if degree == 2:
		return _quadratic_roots(coefficients, start, end)
	var derivative := PackedFloat64Array()
	for index in range(1, coefficients.size()):
		derivative.append(coefficients[index] * index)
	var bounds := PackedFloat64Array([start])
	bounds.append_array(_roots_between(derivative, start, end))
	bounds.append(end)
	for index in range(bounds.size()):
		var left := bounds[index]
		var left_value := _evaluate(coefficients, left)
		var scale: float = 0.0
		for power in range(coefficients.size() - 1, -1, -1):
			scale = scale * left + absf(coefficients[power])
		if absf(left_value) <= maxf(0.0000001, scale * 0.0000001):
			roots.append(left)
		if index == bounds.size() - 1:
			break
		var right := bounds[index + 1]
		if left_value * _evaluate(coefficients, right) >= 0.0:
			continue
		for iteration in range(ROOT_ITERATIONS):
			var middle := (left + right) * 0.5
			var middle_value := _evaluate(coefficients, middle)
			if left_value * middle_value <= 0.0:
				right = middle
			else:
				left = middle
				left_value = middle_value
		roots.append((left + right) * 0.5)
	return roots


static func _quadratic_roots(coefficients: PackedFloat64Array, start: float, end: float) -> PackedFloat64Array:
	var a := coefficients[2]
	var b := coefficients[1]
	var c := coefficients[0]
	var discriminant := b * b - 4.0 * a * c
	var roots := PackedFloat64Array()
	if discriminant < -0.000000000001 * maxf(1.0, b * b + absf(4.0 * a * c)):
		return roots
	var square_root := sqrt(maxf(0.0, discriminant))
	# This form avoids subtracting almost equal values for the smaller root.
	var q := -0.5 * (b + (square_root if b >= 0.0 else -square_root))
	var first := q / a
	var second := c / q if absf(q) > 0.000000000001 else first
	for root in [minf(first, second), maxf(first, second)]:
		if root >= start and root <= end and (roots.is_empty() or absf(root - roots[-1]) > 0.0000001):
			roots.append(root)
	return roots


static func _evaluate(coefficients: PackedFloat64Array, time: float) -> float:
	var value: float = 0.0
	for index in range(coefficients.size() - 1, -1, -1):
		value = value * time + coefficients[index]
	return value
