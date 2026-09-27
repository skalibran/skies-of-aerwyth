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
var positions := PackedStringArray()
var _search_time: float = 0.0
var _authored_positions := PackedStringArray()
var _armed: bool = false


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
	positions.clear()
	_authored_positions.clear()
	_armed = false
	_search_time = 0.0


func prepare(delta: float, ship: Airship, ships: Array[Airship], fleet: FleetController) -> bool:
	var reach := fleet.radius + fleet.entry_range
	if has_target() and (not Factions.are_hostile(ship.faction, target.faction) or target.global_position.distance_to(fleet.marker.global_position) > reach):
		clear_target()
	if positions.is_empty() or _authored_positions != ship.preferred_combat_positions:
		_collect_positions(ship)
	if not _armed or positions.is_empty():
		target = null
		return false
	_search_time -= delta
	if not has_target() and _search_time <= 0.0:
		_search_time = 0.2
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
	return has_target()


func _collect_positions(ship: Airship) -> void:
	_authored_positions = ship.preferred_combat_positions.duplicate()
	positions.clear()
	_armed = false
	for slot in ship.mounted_slots:
		if slot.equipment is MountedWeapon:
			_armed = true
	# Movement follows authored positions. Equipment cones only govern firing.
	for name in _authored_positions:
		if direction(name) != Vector3.ZERO and name not in positions:
			positions.append(name)
