class_name ShipCombat
extends RefCounted

const DIRECTIONS: Dictionary[String, Vector3] = {
	"front": Vector3(0, 0, -1), "front_left": Vector3(-1, 0, -1),
	"left": Vector3(-1, 0, 0), "left_back": Vector3(-1, 0, 1),
	"back": Vector3(0, 0, 1), "back_right": Vector3(1, 0, 1),
	"right": Vector3(1, 0, 0), "front_right": Vector3(1, 0, -1),
	"front_up": Vector3(0, 1, -1), "up": Vector3(0, 1, 0),
	"back_up": Vector3(0, 1, 1), "back_bottom": Vector3(0, -1, 1),
	"bottom": Vector3(0, -1, 0), "front_bottom": Vector3(0, -1, -1),
}

var target: Airship
var bearing: String = ""
var goal_offset := Vector3.ZERO
var passing: bool = false
var returning_to_anchor: bool = false
var stand_off_distance: float = 60.0
var _search_time: float = 0.0
var _approach_axis := Vector3.RIGHT
var _reconsider_time: float = 2.0
var _pass_time: float = 0.0
var _pass_direction := Vector3.FORWARD


static func direction(name: String) -> Vector3:
	return DIRECTIONS.get(name, Vector3.ZERO).normalized()


func has_target() -> bool:
	return is_instance_valid(target) and target.alive and not target.is_queued_for_deletion()


func forget(removed: Airship) -> void:
	if target == removed:
		clear_target()


func clear_target() -> void:
	# Regrouping belongs to the anchor boundary and survives target/loadout changes.
	target = null
	bearing = ""
	_search_time = 0.0
	passing = false
	_pass_time = 0.0


func prepare(delta: float, ship: Airship, ships: Array[Airship], fleet: FleetController) -> bool:
	_search_time -= delta
	var offset := ship.global_position - fleet.anchor.global_position
	var distance := offset.length()
	if has_target() and (not Factions.are_hostile(ship.faction, target.faction) or target.global_position.distance_squared_to(fleet.anchor.global_position) > fleet.combat_radii.y * fleet.combat_radii.y):
		clear_target()
	if distance >= fleet.combat_radii.y:
		returning_to_anchor = true
	elif distance <= fleet.combat_radii.x:
		returning_to_anchor = false
	if returning_to_anchor:
		passing = false
		_pass_time = 0.0
		# Keep weapons independent of regrouping; flight and avoidance still own motion.
		ship.set_preferred_velocity(fleet.velocity - offset.normalized() * ship.maximum_speed)
		return true
	if not has_target():
		if _search_time > 0.0:
			return false
		_search_time = 0.2
		if not _has_weapon(ship):
			return false
		_select_target(ship, ships, fleet)
		if not has_target():
			return false
		stand_off_distance = ship.engagement_distance
		_pass_time = 0.0
		_choose_bearing(ship, fleet)
	if bearing.is_empty():
		return false
	_reconsider_time -= delta
	if _reconsider_time <= 0.0:
		_reconsider_time = 2.0
		if ship.global_position.distance_to(target.global_position) <= ship.engagement_distance + 5.0 and not _can_reach_target(ship):
			stand_off_distance = maxf(12.0, stand_off_distance * 0.7)
	_prepare_course(delta, ship, fleet)
	var weight := smoothstep(fleet.combat_radii.x, fleet.combat_radii.y, distance)
	if weight > 0.0:
		var relative_velocity := ship.preferred_velocity - fleet.velocity
		var inward := -offset.normalized() * ship.maximum_speed
		ship.set_preferred_velocity(fleet.velocity + relative_velocity.lerp(inward, weight))
	return true


func _prepare_course(delta: float, ship: Airship, fleet: FleetController) -> void:
	var preferred := direction(bearing)
	var relative := target.global_position - ship.global_position
	var horizontal := Vector3(relative.x, 0.0, relative.z)
	var radius := stand_off_distance * Vector2(preferred.x, preferred.z).length()
	var height_error := relative.y - preferred.y * stand_off_distance
	_pass_time = maxf(0.0, _pass_time - delta)
	if horizontal.length() > radius * 1.75 + 15.0 or absf(height_error) > 15.0:
		_pass_time = 0.0
	if _pass_time <= 0.0 and horizontal.length() <= radius * 1.35 + 8.0 and absf(height_error) <= 10.0:
		if ship.global_position.distance_squared_to(fleet.anchor.global_position) > fleet.combat_radii.x * fleet.combat_radii.x:
			_choose_bearing(ship, fleet)
			preferred = direction(bearing)
			height_error = relative.y - preferred.y * stand_off_distance
		_pass_direction = _pass_course(ship, relative, preferred)
		_pass_time = ship.combat_pass_seconds
	passing = _pass_time > 0.0
	if passing:
		# Hold a firing-pass course instead of continually turning broadside while
		# commanding sideways pursuit. Navigation and flight still own the turn.
		var cruise := _pass_direction * ship.maximum_speed * ship.combat_speed_ratio
		goal_offset = -horizontal + cruise * 3.0
		goal_offset.y = -preferred.y * stand_off_distance
		cruise.y = clampf(height_error * 0.45, -ship.climb_speed, ship.climb_speed)
		ship.set_preferred_velocity(target.linear_velocity + cruise)
	else:
		if horizontal.length_squared() > 0.001:
			_approach_axis = -horizontal.normalized()
		goal_offset = _approach_axis * radius
		goal_offset.y = -preferred.y * stand_off_distance
		var error := relative + goal_offset
		ship.set_preferred_velocity(target.linear_velocity + (error * 0.45).limit_length(ship.maximum_speed))


func _has_weapon(ship: Airship) -> bool:
	for slot in ship.mounted_slots:
		if slot.equipment is MountedWeapon:
			return true
	return false


func _select_target(ship: Airship, ships: Array[Airship], fleet: FleetController) -> void:
	target = null
	var nearest := INF
	for other in ships:
		if not other.alive or other.is_queued_for_deletion() or not Factions.are_hostile(ship.faction, other.faction):
			continue
		if other.global_position.distance_squared_to(fleet.anchor.global_position) > fleet.combat_radii.y * fleet.combat_radii.y:
			continue
		var distance := ship.global_position.distance_squared_to(other.global_position)
		if distance < nearest or (is_equal_approx(distance, nearest) and is_instance_valid(target) and other.entity_id < target.entity_id):
			target = other
			nearest = distance


func _choose_bearing(ship: Airship, fleet: FleetController) -> void:
	bearing = ""
	var relative := target.global_position - ship.global_position
	_approach_axis = Vector3(-relative.x, 0.0, -relative.z).normalized()
	if _approach_axis == Vector3.ZERO:
		_approach_axis = Vector3.RIGHT if ship.entity_id % 2 == 0 else Vector3.LEFT
	var current := ship.global_basis.inverse() * relative.normalized()
	var inward := fleet.anchor.global_position - ship.global_position
	var weight := smoothstep(fleet.combat_radii.x, fleet.combat_radii.y, inward.length())
	var best_score := -INF
	for name in ship.preferred_combat_positions:
		var candidate := direction(name)
		if candidate == Vector3.ZERO or not _mount_can_present(ship, candidate):
			continue
		var score := current.dot(candidate)
		if weight > 0.0:
			score += 3.0 * weight * _pass_course(ship, relative, candidate).dot(inward.normalized())
		if score > best_score:
			best_score = score
			bearing = name
	_reconsider_time = 2.0


func _pass_course(ship: Airship, relative: Vector3, preferred: Vector3) -> Vector3:
	var heading := ship.rotation.y
	if Vector2(preferred.x, preferred.z).length_squared() > 0.001 and Vector2(relative.x, relative.z).length_squared() > 0.001:
		heading = atan2(-relative.x, -relative.z) - atan2(-preferred.x, -preferred.z)
	return Basis(Vector3.UP, heading) * ShipFlight.primary_axis(ship)


func _can_reach_target(ship: Airship) -> bool:
	# Reachability is independent of current facing while the ship is turning.
	# Keep a reduced stand-off until the target changes to avoid range oscillation.
	for slot in ship.mounted_slots:
		var mounted := slot.equipment as MountedWeapon
		if mounted == null:
			continue
		var weapon := mounted.weapon
		var relative := target.global_position - slot.global_position
		var time := Ballistics.intercept_time(relative, target.linear_velocity, weapon.launch_speed, weapon.gravity, weapon.lifetime)
		if time > 0.0 and (relative + target.linear_velocity * time).length_squared() <= weapon.range_units * weapon.range_units:
			return true
	return false


func _mount_can_present(ship: Airship, candidate: Vector3) -> bool:
	# Unusable authored preferences remain enabled, but cannot strand a ship in a
	# bearing from which none of its mounts could fire even after settling.
	for slot in ship.mounted_slots:
		var mounted := slot.equipment as MountedWeapon
		if mounted == null:
			continue
		var weapon := mounted.weapon
		var relative := candidate * ship.engagement_distance
		var time := Ballistics.intercept_time(relative, Vector3.ZERO, weapon.launch_speed, weapon.gravity, weapon.lifetime)
		if time <= 0.0:
			continue
		var launch := Ballistics.launch_velocity(relative, Vector3.ZERO, weapon.gravity, time)
		if slot.accepts_direction(ship.global_basis * launch):
			return true
	return false
