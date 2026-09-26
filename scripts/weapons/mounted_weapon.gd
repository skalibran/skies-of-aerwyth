@tool
class_name MountedWeapon
extends MountedEquipment

const SEARCH_INTERVAL: float = 0.2
const SOLVE_BUDGET: int = 4

@export var aim_pivot: Node3D
## Optional reusable shot smoke. Weapons sharing a scene share one world batch.
@export var shot_smoke_scene: PackedScene

var cooldown: float = 0.0
var shots_fired: int = 0
var solve_count: int = 0
var search_count: int = 0
var firing_target: Airship
var _previous_main: Airship
var _search_time: float = 0.0
# IDs remember unsuccessful attempts across searches without retaining ship objects.
var _searched_candidates: Dictionary[int, bool] = {}
var _shortlist: Array[Airship] = []
var _shortlist_distances: Array[float] = []

var weapon: WeaponDefinition:
	get:
		return definition as WeaponDefinition


func is_valid() -> bool:
	return weapon != null and super.is_valid() and aim_pivot != null


func initialize_phase(entity_id: int, slot_index: int) -> void:
	_search_time = float((entity_id * 7 + slot_index * 3) % 12) / 12.0 * SEARCH_INTERVAL


func launch_for(target: Airship) -> Vector3:
	if not is_instance_valid(target) or not target.alive or target.is_queued_for_deletion():
		return Vector3.ZERO
	var relative := target.global_position - global_position
	if relative.length_squared() > weapon.range_units * weapon.range_units:
		return Vector3.ZERO
	if not _could_fit_cone(relative, target.linear_velocity, (-slot.global_basis.z).normalized(), deg_to_rad(slot.cone_half_angle), weapon.gravity * weapon.lifetime * 0.5, 1.0 / weapon.launch_speed):
		return Vector3.ZERO
	solve_count += 1
	var time := Ballistics.intercept_time(relative, target.linear_velocity, weapon.launch_speed, weapon.gravity, weapon.lifetime)
	if time <= 0.0 or (relative + target.linear_velocity * time).length_squared() > weapon.range_units * weapon.range_units:
		return Vector3.ZERO
	var launch := Ballistics.launch_velocity(relative, target.linear_velocity, weapon.gravity, time)
	return launch if slot.accepts_direction(launch) else Vector3.ZERO


func _could_fit_cone(relative: Vector3, target_velocity: Vector3, forward: Vector3, half_angle: float, gravity_bound: float, inverse_speed: float) -> bool:
	# v0 = relative / t + target_velocity + UP * gravity * t / 2.
	# For every t within lifetime, bound how far lead/gravity can rotate v0
	# away from the direct bearing. This is only a conservative rejection;
	# the solved launch vector still passes the exact cone test afterward.
	var deviation := (target_velocity.length() + gravity_bound) * inverse_speed
	if deviation >= 1.0:
		return true
	var angle := half_angle + asin(deviation)
	return angle >= PI or forward.dot(relative.normalized()) >= cos(angle) - 0.000001


func step(delta: float, ship: Airship, perception: CombatPerception, projectiles: ProjectileController) -> void:
	if delta <= 0.0 or not ship.alive:
		return
	cooldown = maxf(0.0, cooldown - delta)
	_search_time -= delta
	var main := ship.combat.target
	if main != _previous_main:
		_previous_main = main
		# Keep the acquisition phase when many ships acquire pursuit together.
		# The new main target gets priority at the next scheduled search.
		_searched_candidates.clear()
	if not perception.is_hostile(ship, firing_target) or (not slot.fire_at_targets_in_range and firing_target != main):
		firing_target = null
	if cooldown > 0.000001:
		return
	var search_due := _search_time <= 0.000001
	var attempts: int = 0
	if search_due:
		_search_time = SEARCH_INTERVAL
		search_count += 1
		if perception.is_hostile(ship, main):
			attempts += 1
			if _try_fire(ship, main, projectiles):
				return
			if firing_target == main:
				firing_target = null
	var previous := firing_target
	if firing_target != null:
		attempts += 1
		if _try_fire(ship, firing_target, projectiles):
			return
		_searched_candidates[firing_target.get_instance_id()] = true
		firing_target = null
	if not search_due or not slot.fire_at_targets_in_range:
		return
	var remaining := _collect_shortlist(ship, perception, main, previous, SOLVE_BUDGET - attempts)
	for candidate in _shortlist:
		_searched_candidates[candidate.get_instance_id()] = true
		if _try_fire(ship, candidate, projectiles):
			return
	if remaining <= _shortlist.size():
		_searched_candidates.clear()


func _collect_shortlist(ship: Airship, perception: CombatPerception, main: Airship, previous: Airship, limit: int) -> int:
	_shortlist.clear()
	_shortlist_distances.clear()
	var candidates := perception.weapon_candidates(ship)
	# These values are common to this entire search. Firing still revalidates the
	# chosen target through launch_for, including the current transform and motion.
	var muzzle := global_position
	var forward := (-slot.global_basis.z).normalized()
	var half_angle := deg_to_rad(slot.cone_half_angle)
	var range_squared := weapon.range_units * weapon.range_units
	var gravity_bound := weapon.gravity * weapon.lifetime * 0.5
	var inverse_speed := 1.0 / weapon.launch_speed
	# If the remaining candidates disappeared or left the cone/range, restart the
	# sweep immediately. At most two linear scans are needed, with no full sort.
	for sweep in range(2):
		var remaining: int = 0
		for other: Airship in candidates:
			if other == main or other == previous or not perception.is_hostile(ship, other):
				continue
			if _searched_candidates.has(other.get_instance_id()):
				continue
			var relative := other.global_position - muzzle
			var distance := relative.length_squared()
			if distance > range_squared or not _could_fit_cone(relative, other.linear_velocity, forward, half_angle, gravity_bound, inverse_speed):
				continue
			remaining += 1
			_insert_candidate(other, distance, limit)
		if remaining > 0 or _searched_candidates.is_empty():
			return remaining
		_searched_candidates.clear()
	return 0


func _insert_candidate(candidate: Airship, distance: float, limit: int) -> void:
	var index: int = 0
	while index < _shortlist.size():
		var other_distance := _shortlist_distances[index]
		if distance < other_distance or (distance == other_distance and candidate.entity_id < _shortlist[index].entity_id):
			break
		index += 1
	if index >= limit:
		return
	if _shortlist.size() == limit:
		_shortlist.pop_back()
		_shortlist_distances.pop_back()
	_shortlist.insert(index, candidate)
	_shortlist_distances.insert(index, distance)


func forget(removed: Airship) -> void:
	if firing_target == removed:
		firing_target = null
		# Preserve the phase when a shared target disappears, just as on acquisition.
	if _previous_main == removed:
		_previous_main = null
	_searched_candidates.erase(removed.get_instance_id())
	var index := _shortlist.find(removed)
	if index >= 0:
		_shortlist.remove_at(index)
		_shortlist_distances.remove_at(index)


func _try_fire(ship: Airship, target: Airship, projectiles: ProjectileController) -> bool:
	var launch := launch_for(target)
	if launch == Vector3.ZERO:
		return false
	var up := Vector3.FORWARD if absf(launch.normalized().dot(Vector3.UP)) > 0.99 else Vector3.UP
	aim_pivot.look_at(global_position + launch, up)
	projectiles.fire(ship, global_position, launch, weapon, shot_smoke_scene)
	firing_target = target
	cooldown = weapon.reload_seconds
	shots_fired += 1
	_searched_candidates.clear()
	return true
