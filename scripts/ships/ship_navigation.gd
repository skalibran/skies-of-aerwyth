class_name ShipNavigation
extends RefCounted

const HULL_CLEARANCE: float = 8.0
const CANDIDATE_COUNT: int = 32
const MINIMUM_GOAL_AGE: float = 1.0
const COMBAT_GOAL_INTERVAL: float = 3.0
const SPEED_STEPS: int = 4
const ARRIVAL_RETRY_SECONDS: float = 0.5

## One local destination owner for travel, combat, and obstacle avoidance.
var goal_offset := Vector3.ZERO
var goals_reached: int = 0
var arrival_radius: float = 10.0
var blocked: bool = false
## Route allowance at intended travel speed, independent of current marker motion.
var safe_marker_speed: float = INF
var rng := RandomNumberGenerator.new()
var fleet: FleetController
var _goal_age: float = INF
var _was_in_combat: bool = false
var _target: Airship
var _detour_time: float = 0.0
var _arrival_island: FloatingIsland
var _arrival_offset := Vector3.ZERO
var _arrival_retry: float = 0.0


func initialize(controller: FleetController, ship: Airship) -> void:
	fleet = controller
	rng.seed = ship.entity_id * 104729
	goal_offset = (ship.global_position - fleet.marker.global_position).limit_length(usable_radius(ship))
	safe_marker_speed = INF
	blocked = false
	_goal_age = INF
	_was_in_combat = fleet.in_combat
	_arrival_island = null
	_arrival_retry = 0.0


func usable_radius(ship: Airship) -> float:
	return maxf(1.0, fleet.radius - ship.hull_radius - ship.hull_half_segment - HULL_CLEARANCE)


static func search_radius(ship: Airship, maximum_island_radius: float) -> float:
	var turn := PI / deg_to_rad(ship.yaw_speed_degrees) + ship.yaw_speed_degrees / ship.yaw_acceleration_degrees
	var controller := ship.navigation.fleet
	var relative_speed := ship.linear_velocity.length()
	var request_speed := ship.maximum_speed
	var local_speed: float = 0.0
	var goal_reach: float = 0.0
	if controller != null:
		local_speed = controller.local_speed * ShipFlight.speed_multiplier(ship)
		relative_speed = (ship.linear_velocity - controller.velocity).length()
		request_speed = maxf(request_speed, maxf(controller.velocity.length(), controller.requested_speed) + local_speed)
		var relative := ship.global_position - controller.marker.global_position
		var center := relative.limit_length(ship.navigation.usable_radius(ship) * 0.9)
		goal_reach = relative.distance_to(center) + controller.local_step
		goal_reach = maxf(goal_reach, relative.distance_to(ship.navigation.goal_offset))
	# Contacts can exceed propulsion limits; displaced ships can sample well inside
	# the sphere. Include both their full goal segment and the braking/turn lookahead.
	var horizon := maxf(maxf(ship.linear_velocity.length(), relative_speed), request_speed) / ship.braking + turn + 1.0
	if controller != null:
		var clearance := maximum_island_radius + ship.hull_radius + ship.hull_half_segment + ship.island_clearance
		horizon = maxf(horizon, clearance / local_speed + turn + 1.0)
	return maximum_island_radius + ship.hull_radius + ship.hull_half_segment + ship.island_clearance + maxf(goal_reach, request_speed * horizon)


func prepare(delta: float, ship: Airship) -> void:
	_goal_age += delta
	_arrival_retry = maxf(0.0, _arrival_retry - delta)
	if _was_in_combat != fleet.in_combat or _target != ship.combat.target:
		_goal_age = INF
	_was_in_combat = fleet.in_combat
	_target = ship.combat.target


func plan(ship: Airship, islands: Array[FloatingIsland]) -> void:
	if _outside(ship):
		_plan_arrival(ship, islands)
		return
	_arrival_island = null
	_update_detour_time(ship, islands)
	var intended := Vector3.FORWARD * fleet.requested_speed
	var relative := ship.global_position - fleet.marker.global_position
	var arrived := relative.distance_to(goal_offset) <= arrival_radius
	var refresh := is_inf(_goal_age) or (arrived and _goal_age >= MINIMUM_GOAL_AGE) or (ship.combat_engaged and _goal_age >= COMBAT_GOAL_INTERVAL)
	if not refresh and _goal_clear(ship, goal_offset, intended, islands):
		safe_marker_speed = fleet.requested_speed
		blocked = false
		return
	if arrived:
		goals_reached += 1
	# Search at the desired pace first, even while the marker is stopped. Slower
	# choices remain useful detours; they do not imply that all flight must stop.
	for step in range(SPEED_STEPS + 1):
		var trial_speed := fleet.requested_speed * (1.0 - float(step) / SPEED_STEPS)
		if _choose_goal(ship, islands, Vector3.FORWARD * trial_speed):
			safe_marker_speed = trial_speed
			return
		if is_zero_approx(fleet.requested_speed):
			break
	safe_marker_speed = 0.0
	blocked = true
	goal_offset = relative.limit_length(usable_radius(ship) * 0.9)
	_goal_age = INF


func steer(ship: Airship, avoidance: Vector3, islands: Array[FloatingIsland]) -> Vector3:
	if _outside(ship):
		return _steer_arrival(ship, avoidance, islands)
	_update_detour_time(ship, islands)
	var relative := ship.global_position - fleet.marker.global_position
	var arrived := relative.distance_to(goal_offset) <= arrival_radius
	var refresh := is_inf(_goal_age) or (arrived and _goal_age >= MINIMUM_GOAL_AGE) or (ship.combat_engaged and _goal_age >= COMBAT_GOAL_INTERVAL)
	# Other friendly routes may have reduced the marker pace after planning.
	# Validate the actual course too, including separation and the new center.
	if refresh or not _goal_clear(ship, goal_offset, fleet.velocity, islands):
		if arrived:
			goals_reached += 1
		if not _choose_goal(ship, islands, fleet.velocity):
			blocked = true
			goal_offset = relative.limit_length(usable_radius(ship) * 0.9)
			_goal_age = INF
			return Vector3.ZERO
	blocked = false
	var destination := fleet.marker.global_position + goal_offset
	var request := _bounded_velocity(ship, destination, fleet.velocity, avoidance)
	if not _course_clear(ship, request, islands):
		request = _bounded_velocity(ship, destination, fleet.velocity)
	return request


func _outside(ship: Airship) -> bool:
	return ship.global_position.distance_squared_to(fleet.marker.global_position) > pow(usable_radius(ship), 2.0)


func _plan_arrival(ship: Airship, islands: Array[FloatingIsland]) -> void:
	# The final destination stays inside the sphere. Only the approach leg may
	# go around scenery outside it, without holding up the distant fleet marker.
	goal_offset = (ship.global_position - fleet.marker.global_position).limit_length(usable_radius(ship) * 0.9)
	safe_marker_speed = fleet.requested_speed
	_goal_age = INF
	var destination := fleet.marker.global_position + goal_offset
	var marker_velocity := Vector3.FORWARD * fleet.requested_speed
	# Leave the detour as soon as the fleet is reachable; converging vessels
	# must not queue for the exact same temporary waypoint.
	if _arrival_route_clear(ship, destination, marker_velocity, islands):
		_arrival_island = null
		blocked = false
		return
	if is_instance_valid(_arrival_island) and not _arrival_island.is_queued_for_deletion():
		var waypoint := _arrival_island.to_global(_arrival_offset)
		if ship.global_position.distance_to(waypoint) > arrival_radius and _arrival_route_clear(ship, waypoint, Vector3.ZERO, islands):
			blocked = false
			return
	_arrival_island = null
	blocked = true
	if _arrival_retry > 0.0:
		return
	_arrival_retry = ARRIVAL_RETRY_SECONDS
	var obstruction: FloatingIsland
	var nearest: float = INF
	for island in islands:
		if not is_instance_valid(island) or island.is_queued_for_deletion():
			continue
		var distance := ship.global_position.distance_squared_to(island.global_position)
		if distance < nearest and not _arrival_route_clear(ship, destination, marker_velocity, [island]):
			obstruction = island
			nearest = distance
	if obstruction == null:
		return
	var hull := ship.hull_radius + ship.hull_half_segment
	var speed := fleet.local_speed * ShipFlight.speed_multiplier(ship)
	var margin := maxf(60.0, speed * 1.5)
	var reach := obstruction.navigation_radius + hull + ship.island_clearance + margin
	var toward := (ship.global_position - obstruction.global_position) * Vector3(1, 0, 1)
	toward = toward.normalized() if toward.length_squared() > 0.01 else Vector3.BACK
	var sideways := toward.cross(Vector3.UP)
	var best_cost: float = INF
	for index in range(6):
		var candidate := obstruction.global_position
		if index < 4:
			candidate += sideways * reach * (1.0 if index % 2 == 0 else -1.0)
			if index >= 2:
				candidate += toward * reach * 0.6
			candidate.y = ship.global_position.y
		else:
			candidate.y += obstruction.top_offset + hull + margin if index == 4 else obstruction.bottom_offset - hull - margin
		if not _arrival_route_clear(ship, candidate, Vector3.ZERO, islands):
			continue
		# The next leg must get past this obstruction, even if another island
		# farther along the journey will require its own subsequent detour.
		if not _path_clear(ship, destination, [obstruction], candidate):
			continue
		var cost := ship.global_position.distance_to(candidate) + candidate.distance_to(destination)
		cost += ShipFlight.turn_time(ship, candidate - ship.global_position) * speed
		if cost < best_cost:
			best_cost = cost
			_arrival_island = obstruction
			_arrival_offset = obstruction.to_local(candidate)
	blocked = _arrival_island == null


func _steer_arrival(ship: Airship, avoidance: Vector3, islands: Array[FloatingIsland]) -> Vector3:
	if blocked:
		return Vector3.ZERO
	var detouring := is_instance_valid(_arrival_island) and not _arrival_island.is_queued_for_deletion()
	var destination := _arrival_island.to_global(_arrival_offset) if detouring else fleet.marker.global_position + goal_offset
	var marker_velocity := Vector3.ZERO if detouring else fleet.velocity
	var request := _velocity_to(ship, destination, marker_velocity)
	var multiplier := ShipFlight.speed_multiplier(ship)
	# Separation must still work while several ships approach the same isle.
	# Preserve inward progress while allowing lateral spacing around this leg.
	var course := (destination - ship.global_position).normalized()
	var correction := avoidance - course * minf(0.0, avoidance.dot(course) + (request - marker_velocity).dot(course) * 0.5)
	var corrected := (request + correction - marker_velocity).limit_length(fleet.local_speed * multiplier)
	corrected.y = clampf(corrected.y, -ship.climb_speed * multiplier, ship.climb_speed * multiplier)
	corrected += marker_velocity
	if not detouring and (corrected - marker_velocity).dot(fleet.marker.global_position - ship.global_position) <= 0.0:
		corrected = request
	if _arrival_course_clear(ship, corrected, destination, islands):
		return corrected
	if _arrival_course_clear(ship, request, destination, islands):
		return request
	_arrival_island = null
	blocked = true
	return Vector3.ZERO


func _arrival_route_clear(ship: Airship, destination: Vector3, marker_velocity: Vector3, islands: Array[FloatingIsland]) -> bool:
	return _path_clear(ship, destination, islands) and _arrival_course_clear(ship, _velocity_to(ship, destination, marker_velocity), destination, islands)


func _arrival_course_clear(ship: Airship, request: Vector3, destination: Vector3, islands: Array[FloatingIsland]) -> bool:
	# A turn at the waypoint ends this leg. Do not reject a safe approach because
	# extrapolating its velocity for an entire turn would cross scenery beyond it.
	var horizon := maxf(ship.linear_velocity.length(), request.length()) / ship.braking + ShipFlight.turn_time(ship, request) + 1.0
	horizon = minf(horizon, ship.global_position.distance_to(destination) / maxf(request.length(), 0.001))
	return _path_clear(ship, ship.global_position + request * horizon, islands)


func _choose_goal(ship: Airship, islands: Array[FloatingIsland], marker_velocity: Vector3) -> bool:
	var relative := ship.global_position - fleet.marker.global_position
	var radius := usable_radius(ship)
	var center := relative.limit_length(radius * 0.9)
	var forward := ship.global_basis * ShipFlight.primary_axis(ship)
	var best_score: float = -INF
	var best_goal := goal_offset
	var predicted := relative + (ship.linear_velocity - marker_velocity) * _horizon(ship)
	var edge_weight := clampf((predicted.length() / radius - 0.55) / 0.45, 0.0, 1.0)
	for index in range(CANDIDATE_COUNT):
		var direction := Vector3(rng.randf_range(-1.0, 1.0), rng.randf_range(-0.6, 0.6), rng.randf_range(-1.0, 1.0)).normalized()
		match index:
			0: direction = forward
			1: direction = -relative.normalized()
			2:
				if ship.combat.has_target():
					direction = (ship.combat.target.global_position - ship.global_position).normalized()
			3: direction = Vector3.LEFT
			4: direction = Vector3.RIGHT
			5: direction = Vector3.UP
			6: direction = Vector3.DOWN
			7: direction = Vector3.FORWARD
			8: direction = Vector3.BACK
		var candidate := center + direction * fleet.local_step
		if index == 9:
			candidate = goal_offset
		if not _goal_clear(ship, candidate, marker_velocity, islands):
			continue
		var world_goal := fleet.marker.global_position + candidate
		var course := (world_goal - ship.global_position).normalized()
		var request := _bounded_velocity(ship, world_goal, marker_velocity)
		var score := forward.dot(course) * 1.5 + rng.randf() * 0.5
		# Prefer inward turns before momentum carries the hull to the edge.
		score += course.dot(-relative.normalized()) * edge_weight * 5.0
		if ship.combat_engaged:
			score += ship.combat.score_destination(ship, world_goal, request)
		if score > best_score:
			best_score = score
			best_goal = candidate
	if is_inf(best_score):
		return false
	blocked = false
	goal_offset = best_goal
	_goal_age = 0.0
	return true


func _goal_clear(ship: Airship, candidate: Vector3, marker_velocity: Vector3, islands: Array[FloatingIsland]) -> bool:
	if candidate.length() > usable_radius(ship):
		return false
	var destination := fleet.marker.global_position + candidate
	if not _path_clear(ship, destination, islands):
		return false
	return _course_clear(ship, _bounded_velocity(ship, destination, marker_velocity), islands)


func _course_clear(ship: Airship, request: Vector3, islands: Array[FloatingIsland]) -> bool:
	# Static scenery sees world motion, not only the ship's local wandering speed.
	var turn := ShipFlight.turn_time(ship, request)
	var horizon := maxf(ship.linear_velocity.length(), request.length()) / ship.braking + turn + 1.0
	horizon = maxf(horizon, _detour_time + turn + 1.0)
	return _path_clear(ship, ship.global_position + request * horizon, islands)


func _update_detour_time(ship: Airship, islands: Array[FloatingIsland]) -> void:
	# Begin a broad detour while lateral correction still has time to clear it.
	# Braking distance alone lets fast translating fleets approach too closely.
	# Cache for this query so candidate scoring does not repeatedly scan its islands.
	_detour_time = 0.0
	var local_speed := fleet.local_speed * ShipFlight.speed_multiplier(ship)
	for island in islands:
		if is_instance_valid(island) and not island.is_queued_for_deletion():
			var clearance := island.navigation_radius + ship.hull_radius + ship.hull_half_segment + ship.island_clearance
			_detour_time = maxf(_detour_time, clearance / local_speed)


func _goal_velocity(ship: Airship, destination: Vector3) -> Vector3:
	return _velocity_to(ship, destination, fleet.velocity)


func _velocity_to(ship: Airship, destination: Vector3, marker_velocity: Vector3) -> Vector3:
	var error := destination - ship.global_position
	var multiplier := ShipFlight.speed_multiplier(ship)
	var climb_speed := ship.climb_speed * multiplier
	# Base braking remains conservative as the boost tapers toward the sphere.
	var request := marker_velocity + error.normalized() * minf(fleet.local_speed * multiplier, sqrt(2.0 * ship.braking * error.length()))
	request.y = clampf(request.y, -climb_speed, climb_speed)
	return request.limit_length(ship.maximum_speed * multiplier)


func _horizon(ship: Airship) -> float:
	return _steering_horizon(ship, _goal_velocity(ship, fleet.marker.global_position + goal_offset), fleet.velocity)


func _steering_horizon(ship: Airship, requested: Vector3, marker_velocity: Vector3) -> float:
	return maxf(1.0, (ship.linear_velocity - marker_velocity).length() / ship.braking + ShipFlight.turn_time(ship, requested))


func _bounded_velocity(ship: Airship, destination: Vector3, marker_velocity: Vector3, avoidance := Vector3.ZERO) -> Vector3:
	var relative := ship.global_position - fleet.marker.global_position
	var multiplier := ShipFlight.speed_multiplier(ship)
	var local_speed := fleet.local_speed * multiplier
	var climb_speed := ship.climb_speed * multiplier
	var requested := _velocity_to(ship, destination, marker_velocity)
	var horizon := _steering_horizon(ship, requested, marker_velocity)
	var relative_request := requested + avoidance - marker_velocity
	# Limit lift before checking the endpoint so the checked path matches flight.
	relative_request.y = clampf(relative_request.y, -climb_speed, climb_speed)
	relative_request = relative_request.limit_length(local_speed)
	var endpoint := relative + relative_request * horizon
	var radius := usable_radius(ship)
	if endpoint.length() > radius:
		relative_request = (endpoint.limit_length(radius) - relative) / horizon
	return marker_velocity + relative_request.limit_length(local_speed)


func _path_clear(ship: Airship, destination: Vector3, islands: Array[FloatingIsland], start := Vector3.INF) -> bool:
	if not start.is_finite():
		start = ship.global_position
	var segment := Vector2(destination.x - start.x, destination.z - start.z)
	var hull := ship.hull_radius + ship.hull_half_segment
	for island in islands:
		if not is_instance_valid(island) or island.is_queued_for_deletion():
			continue
		if not island.overlaps_height(minf(start.y, destination.y), maxf(start.y, destination.y), hull):
			continue
		var radius := island.navigation_radius + hull + ship.island_clearance
		var relative := Vector2(start.x - island.global_position.x, start.z - island.global_position.z)
		var first: float = 0.0
		var last: float = 1.0
		var height_change := destination.y - start.y
		if absf(height_change) > 0.001:
			var bottom := (island.global_position.y + island.bottom_offset - hull - start.y) / height_change
			var top := (island.global_position.y + island.top_offset + hull - start.y) / height_change
			first = maxf(0.0, minf(bottom, top))
			last = minf(1.0, maxf(bottom, top))
			if first > last:
				continue
		if first == 0.0 and relative.length_squared() < radius * radius:
			if relative.length_squared() > 0.01 and relative.dot(segment) > 0.0:
				continue
			return false
		var fraction := clampf(-relative.dot(segment) / maxf(0.001, segment.length_squared()), first, last)
		if (relative + segment * fraction).length_squared() < radius * radius:
			return false
	return true
