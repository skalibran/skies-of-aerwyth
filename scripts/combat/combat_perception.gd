class_name CombatPerception
extends RefCounted

const CELL_SIZE: float = 100.0

# Derived from Journey's registry each combat tick. This helper supplies nearby
# candidates and membership checks; pursuit and firing policy stay with callers.
var _cells: Dictionary[Vector3i, Array] = {}
var _ship_cells: Dictionary[int, Vector3i] = {}
var _weapon_neighbors: Dictionary[int, Array] = {}
var query_count: int = 0


func rebuild(ships: Array[Airship]) -> void:
	_cells.clear()
	_ship_cells.clear()
	_weapon_neighbors.clear()
	for ship in ships:
		if not is_instance_valid(ship) or not ship.alive or ship.is_queued_for_deletion():
			continue
		var cell := Vector3i((ship.global_position / CELL_SIZE).floor())
		_ship_cells[ship.get_instance_id()] = cell
		if not _cells.has(cell):
			_cells[cell] = []
		_cells[cell].append(ship)


func forget(ship: Airship) -> void:
	var id := ship.get_instance_id()
	if _ship_cells.has(id):
		# Remove from its snapshot cell even if it moved or rebased afterward.
		# Typed cell iteration cannot safely assign a previously freed Node.
		var cell := _ship_cells[id]
		_cells[cell].erase(ship)
		if _cells[cell].is_empty():
			_cells.erase(cell)
		_ship_cells.erase(id)
	_weapon_neighbors.clear()


func is_hostile(ship: Airship, other: Airship) -> bool:
	return is_instance_valid(other) and _ship_cells.has(other.get_instance_id()) and other.alive and not other.is_queued_for_deletion() and Factions.are_hostile(ship.faction, other.faction)


func nearby_hostiles(position: Vector3, radius: float, faction: StringName, result: Array[Airship]) -> void:
	result.clear()
	query_count += 1
	var radius_squared := radius * radius
	var low := Vector3i(((position - Vector3.ONE * radius) / CELL_SIZE).floor())
	var high := Vector3i(((position + Vector3.ONE * radius) / CELL_SIZE).floor())
	for x in range(low.x, high.x + 1):
		for y in range(low.y, high.y + 1):
			for z in range(low.z, high.z + 1):
				var cell := Vector3i(x, y, z)
				if not _cells.has(cell):
					continue
				for other: Airship in _cells[cell]:
					if is_instance_valid(other) and _ship_cells.has(other.get_instance_id()) and other.alive and not other.is_queued_for_deletion() and Factions.are_hostile(faction, other.faction) and position.distance_squared_to(other.global_position) <= radius_squared:
						result.append(other)


func weapon_candidates(ship: Airship) -> Array[Airship]:
	var id := ship.get_instance_id()
	if not _weapon_neighbors.has(id):
		# One broad-phase query serves every mount on this ship for this tick.
		# Include muzzle offsets; mounts still check their own exact range/cone.
		var radius: float = 0.0
		for slot in ship.mounted_slots:
			var mounted := slot.equipment as MountedWeapon
			if mounted != null:
				radius = maxf(radius, mounted.weapon.range_units + ship.global_position.distance_to(slot.global_position))
		var candidates: Array[Airship] = []
		nearby_hostiles(ship.global_position, radius, ship.faction, candidates)
		_weapon_neighbors[id] = candidates
	return _weapon_neighbors[id]
