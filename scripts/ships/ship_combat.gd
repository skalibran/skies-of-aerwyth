class_name ShipCombat
extends RefCounted

const DIRECTIONS: Dictionary[String, Vector3] = {
	"front": Vector3(0, 0, -1), "front_left": Vector3(-1, 0, -1),
	"left": Vector3(-1, 0, 0), "left_back": Vector3(-1, 0, 1),
	"back": Vector3(0, 0, 1), "back_right": Vector3(1, 0, 1),
	"right": Vector3(1, 0, 0), "front_right": Vector3(1, 0, -1),
	"front_up": Vector3(0, 1, -1), "up": Vector3(0, 1, 0),
	"left_up": Vector3(-1, 1, 0), "right_up": Vector3(1, 1, 0),
	"back_up": Vector3(0, 1, 1), "back_bottom": Vector3(0, -1, 1),
	"bottom": Vector3(0, -1, 0), "front_bottom": Vector3(0, -1, -1),
	"left_bottom": Vector3(-1, -1, 0), "right_bottom": Vector3(1, -1, 0),
}
const STRONG_VERTICAL_BIAS: float = 0.5

var target: Airship
var engagement_range: float = 120.0
var _search_time: float = 0.0
var _bearings: Array[Vector3] = []


static func direction(name: String) -> Vector3:
	return DIRECTIONS.get(name, Vector3.ZERO).normalized()


## Authored target-bearing bias: negative aims below, positive aims above.
## Independent of scene readiness, current target, and temporary visual banking.
static func vertical_bias(positions: PackedStringArray) -> float:
	var seen := PackedStringArray()
	var total: float = 0.0
	for name in positions:
		var bearing := direction(name)
		if bearing == Vector3.ZERO or name in seen:
			continue
		seen.append(name)
		total += bearing.y
	return total / seen.size() if not seen.is_empty() else 0.0


func has_target() -> bool:
	return is_instance_valid(target) and target.alive and not target.is_queued_for_deletion()


func forget(removed: Airship) -> void:
	if target == removed:
		clear_target()


func clear_target() -> void:
	target = null
	_bearings.clear()
	_search_time = 0.0


func prepare(delta: float, ship: Airship, ships: Array[Airship], fleet: FleetController) -> bool:
	var reach := fleet.radius + fleet.entry_range
	if has_target() and (not Factions.are_hostile(ship.faction, target.faction) or target.global_position.distance_to(fleet.marker.global_position) > reach):
		clear_target()
	if has_target() and _bearings.is_empty():
		_collect_bearings(ship)
	_search_time -= delta
	engagement_range = minf(ship.engagement_distance, fleet.radius * 0.75)
	if not has_target() and _search_time <= 0.0:
		_search_time = 0.2
		_collect_bearings(ship)
		if _bearings.is_empty():
			return false
		var nearest: float = INF
		for other in ships:
			if not other.alive or other.is_queued_for_deletion() or not Factions.are_hostile(ship.faction, other.faction):
				continue
			if other.global_position.distance_to(fleet.marker.global_position) > reach:
				continue
			var distance := ship.global_position.distance_squared_to(other.global_position)
			if distance < nearest or (distance == nearest and is_instance_valid(target) and other.entity_id < target.entity_id):
				target = other
				nearest = distance
	return has_target() and not _bearings.is_empty()


func _collect_bearings(ship: Airship) -> void:
	_bearings.clear()
	for name in ship.preferred_combat_positions:
		var candidate := direction(name)
		if candidate == Vector3.ZERO:
			continue
		for slot in ship.mounted_slots:
			if slot.equipment is MountedWeapon and slot.accepts_direction(ship.global_basis * candidate):
				_bearings.append(candidate)
				break


func score_destination(ship: Airship, destination: Vector3, requested_velocity: Vector3) -> float:
	if not has_target():
		return 0.0
	var course := destination - ship.global_position
	var primary := ShipFlight.primary_axis(ship)
	# Flight turns toward world velocity, including the moving marker's contribution.
	var heading := ship.global_rotation.y
	if Vector2(requested_velocity.x, requested_velocity.z).length_squared() > 1.0:
		heading = atan2(-requested_velocity.x, -requested_velocity.z) - atan2(-primary.x, -primary.z)
	var toward_target := (target.global_position - destination).normalized()
	var local_target := Basis(Vector3.UP, -heading) * toward_target
	var presentation: float = -1.0
	for candidate in _bearings:
		presentation = maxf(presentation, candidate.dot(local_target))
	var current_distance := ship.global_position.distance_to(target.global_position)
	var next_distance := destination.distance_to(target.global_position)
	var range_gain := (absf(current_distance - engagement_range) - absf(next_distance - engagement_range)) / maxf(1.0, course.length())
	# Distant entry favors approach; nearby maneuvers favor usable firing bearings.
	var presentation_weight := 3.0 if current_distance < engagement_range * 2.0 else 1.0
	return presentation * presentation_weight + range_gain * 2.0
