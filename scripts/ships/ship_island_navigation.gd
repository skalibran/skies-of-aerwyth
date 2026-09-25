class_name ShipIslandNavigation
extends RefCounted

const RING_POINTS: int = 8

var waypoint_island: FloatingIsland
var waypoint_offset := Vector3.ZERO
var _retry_time: float = 0.0
var _near: Array[FloatingIsland] = []
var _centers := PackedVector2Array()
var _radii := PackedFloat32Array()


func has_waypoint() -> bool:
	return is_instance_valid(waypoint_island) and not waypoint_island.is_queued_for_deletion()


func waypoint_position() -> Vector3:
	return waypoint_island.global_position + waypoint_offset


static func look_ahead_distance(ship: Airship) -> float:
	var preferred := Vector2(ship.preferred_velocity.x, ship.preferred_velocity.z)
	var speed := maxf(preferred.length(), ship.velocity.length())
	return maxf(90.0, speed * 6.0 + speed * speed / (2.0 * ship.braking))


static func search_radius(ship: Airship, maximum_island_radius: float) -> float:
	return look_ahead_distance(ship) + (maximum_island_radius + ship.hull_radius + ship.hull_half_segment + ship.island_clearance) * 3.0


func steer(ship: Airship, islands: Array[FloatingIsland], delta: float) -> Vector3:
	_retry_time = maxf(0.0, _retry_time - delta)
	var start := Vector2(ship.global_position.x, ship.global_position.z)
	var preferred := Vector2(ship.preferred_velocity.x, ship.preferred_velocity.z)
	if preferred.length_squared() < 0.01:
		waypoint_island = null
		return ship.preferred_velocity
	var look_ahead := look_ahead_distance(ship)
	_collect_obstacles(ship, islands, start, look_ahead)
	var direction := preferred.normalized()
	var end := start + direction * look_ahead
	# A moving travel goal can lie inside an island. Plan past the obstruction
	# instead of repeatedly seeking an unreachable point within its solid volume.
	for attempt in range(_near.size() + 1):
		var blocked_end := false
		for index in range(_near.size()):
			if end.distance_squared_to(_centers[index]) < _radii[index] * _radii[index]:
				end += direction * (_radii[index] * 2.0 + 1.0)
				blocked_end = true
		if not blocked_end:
			break
	if _segment_clear(start, end):
		waypoint_island = null
		return ship.preferred_velocity
	if has_waypoint():
		var point := waypoint_position()
		var waypoint := Vector2(point.x, point.z)
		if start.distance_to(waypoint) < 3.0 or not _segment_clear(start, waypoint):
			waypoint_island = null
	if not has_waypoint():
		if _retry_time > 0.0 or not _plan(start, end, ship):
			_retry_time = 0.25 if _retry_time <= 0.0 else _retry_time
			return Vector3.ZERO
	var displacement := waypoint_position() - ship.global_position
	var detour_speed := minf(ship.maximum_speed * 0.75, maxf(preferred.length(), 6.0))
	# Slow into corners so heavy ships do not cut through the clearance envelope.
	return displacement.normalized() * minf(detour_speed, displacement.length() * 0.65)


func _collect_obstacles(ship: Airship, islands: Array[FloatingIsland], start: Vector2, look_ahead: float) -> void:
	_near.clear()
	_centers.clear()
	_radii.clear()
	var end_y := ship.global_position.y + clampf(ship.preferred_velocity.y, -ship.climb_speed, ship.climb_speed) * 6.0
	for island in islands:
		var radius := island.navigation_radius + ship.hull_radius + ship.hull_half_segment + ship.island_clearance
		var position := island.global_position
		var center := Vector2(position.x, position.z)
		if start.distance_squared_to(center) > pow(look_ahead + radius * 3.0, 2.0):
			continue
		if not island.overlaps_height(minf(ship.global_position.y, end_y), maxf(ship.global_position.y, end_y), ship.hull_radius + 2.0):
			continue
		_near.append(island)
		_centers.append(center)
		_radii.append(radius)


func _segment_clear(start: Vector2, end: Vector2) -> bool:
	var segment := end - start
	var length_squared := segment.length_squared()
	for index in range(_near.size()):
		var relative := start - _centers[index]
		var radius_squared := _radii[index] * _radii[index]
		if relative.length_squared() < radius_squared - 0.01:
			# A ship pushed into soft clearance may leave it, but must not cut deeper.
			if relative.dot(segment) < -0.01 or end.distance_squared_to(_centers[index]) < radius_squared:
				return false
			continue
		var fraction := clampf(-relative.dot(segment) / maxf(length_squared, 0.001), 0.0, 1.0)
		if (relative + segment * fraction).length_squared() < radius_squared - 0.01:
			return false
	return true


func _plan(start: Vector2, end: Vector2, ship: Airship) -> bool:
	var points := PackedVector2Array([start, end])
	var owners := PackedInt32Array([-1, -1])
	for index in range(_near.size()):
		# A circumscribed octagon keeps even the edges outside the padded circle.
		var radius := _radii[index] / cos(PI / RING_POINTS) + 1.0
		for ring_index in range(RING_POINTS):
			var angle := TAU * float(ring_index) / RING_POINTS
			if ship.entity_id % 2 == 0:
				angle = PI - angle
			var candidate := _centers[index] + Vector2(cos(angle), sin(angle)) * radius
			if _point_clear(candidate):
				points.append(candidate)
				owners.append(index)
	var distances := PackedFloat64Array()
	var previous := PackedInt32Array()
	var visited: Array[bool] = []
	distances.resize(points.size())
	distances.fill(INF)
	previous.resize(points.size())
	previous.fill(-1)
	visited.resize(points.size())
	visited.fill(false)
	distances[0] = 0.0
	for iteration in range(points.size()):
		var current: int = -1
		for index in range(points.size()):
			if not visited[index] and (current < 0 or distances[index] < distances[current]):
				current = index
		if current < 0 or is_inf(distances[current]):
			break
		if current == 1:
			break
		visited[current] = true
		for neighbor in range(points.size()):
			if visited[neighbor]:
				continue
			var cost := distances[current] + points[current].distance_to(points[neighbor])
			if cost < distances[neighbor] and _segment_clear(points[current], points[neighbor]):
				distances[neighbor] = cost
				previous[neighbor] = current
	if previous[1] < 0:
		return false
	var next: int = 1
	while previous[next] > 0:
		next = previous[next]
	if owners[next] < 0:
		return false
	waypoint_island = _near[owners[next]]
	waypoint_offset = Vector3(points[next].x, ship.global_position.y, points[next].y) - waypoint_island.global_position
	return true


func _point_clear(point: Vector2) -> bool:
	for index in range(_near.size()):
		if point.distance_squared_to(_centers[index]) < _radii[index] * _radii[index]:
			return false
	return true
