@tool
class_name MountedWeapon
extends MountedEquipment

const SEARCH_INTERVAL: float = 0.2
const SOLVE_BUDGET: int = 4

@export var aim_pivot: Node3D

var cooldown: float = 0.0
var shots_fired: int = 0
var solve_count: int = 0
var _search_time: float = 0.0
var _candidate_cursor: int = 0
var _candidates: Array[Airship] = []

var weapon: WeaponDefinition:
	get:
		return definition as WeaponDefinition


func is_valid() -> bool:
	return weapon != null and super.is_valid() and aim_pivot != null


func initialize_phase(entity_id: int, slot_index: int) -> void:
	_search_time = float((entity_id * 7 + slot_index * 3) % 12) / 60.0


func launch_for(target: Airship) -> Vector3:
	if not is_instance_valid(target) or not target.alive:
		return Vector3.ZERO
	var relative := target.global_position - global_position
	if relative.length_squared() > weapon.range_units * weapon.range_units:
		return Vector3.ZERO
	solve_count += 1
	var time := Ballistics.intercept_time(relative, target.linear_velocity, weapon.launch_speed, weapon.gravity, weapon.lifetime)
	if time <= 0.0 or (relative + target.linear_velocity * time).length_squared() > weapon.range_units * weapon.range_units:
		return Vector3.ZERO
	var launch := Ballistics.launch_velocity(relative, target.linear_velocity, weapon.gravity, time)
	return launch if slot.accepts_direction(launch) else Vector3.ZERO


func step(delta: float, ship: Airship, ships: Array[Airship], projectiles: ProjectileController) -> void:
	cooldown = maxf(0.0, cooldown - delta)
	_search_time -= delta
	if not ship.alive or cooldown > 0.0 or _search_time > 0.0:
		return
	_search_time = SEARCH_INTERVAL
	var main := ship.combat.target
	if is_instance_valid(main) and main.alive and Factions.are_hostile(ship.faction, main.faction):
		if _try_fire(ship, main, projectiles):
			return
	if not slot.fire_at_targets_in_range:
		return
	_candidates.clear()
	for other in ships:
		if other != main and other.alive and Factions.are_hostile(ship.faction, other.faction) and global_position.distance_squared_to(other.global_position) <= weapon.range_units * weapon.range_units:
			_candidates.append(other)
	_candidates.sort_custom(_nearer)
	if _candidates.is_empty():
		_candidate_cursor = 0
		return
	for attempt in range(mini(SOLVE_BUDGET - 1, _candidates.size())):
		_candidate_cursor %= _candidates.size()
		var candidate := _candidates[_candidate_cursor]
		_candidate_cursor += 1
		if _try_fire(ship, candidate, projectiles):
			_candidate_cursor = 0
			return


func _try_fire(ship: Airship, target: Airship, projectiles: ProjectileController) -> bool:
	var launch := launch_for(target)
	if launch == Vector3.ZERO:
		return false
	var up := Vector3.FORWARD if absf(launch.normalized().dot(Vector3.UP)) > 0.99 else Vector3.UP
	aim_pivot.look_at(global_position + launch, up)
	projectiles.fire(ship, global_position, launch, weapon)
	cooldown = weapon.reload_seconds
	shots_fired += 1
	return true


func _nearer(first: Airship, second: Airship) -> bool:
	var a := global_position.distance_squared_to(first.global_position)
	var b := global_position.distance_squared_to(second.global_position)
	return first.entity_id < second.entity_id if is_equal_approx(a, b) else a < b
