class_name IslandSpawner
extends Node

const NAVIGATION_CELL_SIZE: float = 2560.0

@export var island_scene: PackedScene
@export var container: Node3D
@export var origin: FloatingOrigin
@export var fleet: FleetController
@export var world_seed: int = 84317
@export_range(10.0, 3000.0) var minimum_spacing: float = 80.0
@export_range(10.0, 3000.0) var maximum_spacing: float = 200.0
@export_range(1000.0, 40000.0) var look_ahead: float = 15000.0
@export_range(1000.0, 40000.0) var keep_behind: float = 13000.0
@export_range(3000.0, 30000.0) var field_half_width: float = 16000.0
@export var altitude_range := Vector2(-1800.0, 1800.0)

var records: Array[IslandRecord] = []
var active: Dictionary[int, FloatingIsland] = {}
var obstacles: Array[FloatingIsland] = []
var next_position: RoutePosition
var rng := RandomNumberGenerator.new()
var _next_id: int = 1
var _navigation_cells: Dictionary[Vector2i, PackedInt32Array] = {}
var _navigation_dirty: bool = true
var _navigation_count: int = -1
var _navigation_segment: int = 0
var _maximum_navigation_radius: float = 0.0
var _candidate_indices := PackedInt32Array()
var _navigation_candidates: Array[FloatingIsland] = []


func initialize(start: RoutePosition) -> void:
	assert(minimum_spacing > 0.0)
	rng.seed = world_seed
	# Fill the visible surroundings before the first frame, including behind us.
	next_position = start.advanced(keep_behind)
	var initial_budget := ceili((keep_behind + look_ahead) / minimum_spacing) + 1
	_generate_through(start, initial_budget, true)


func update_region(anchor_position: RoutePosition) -> void:
	_generate_through(anchor_position, 32)
	var trailing_edge := anchor_position.advanced(keep_behind)
	for island_id in active.keys():
		var island: FloatingIsland = active[island_id]
		if island.record.route_position.compare(trailing_edge) > 0:
			obstacles.erase(island)
			origin.unregister_root(island)
			island.queue_free()
			active.erase(island_id)
			_navigation_dirty = true


func navigation_candidates(ship: Airship) -> Array[FloatingIsland]:
	if _navigation_dirty or _navigation_count != obstacles.size() or _navigation_segment != origin.segment:
		_rebuild_navigation_cells()
	var position := Vector2(ship.global_position.x, ship.global_position.z)
	var radius := ShipIslandNavigation.search_radius(ship, _maximum_navigation_radius)
	var minimum := Vector2i(((position - Vector2.ONE * radius) / NAVIGATION_CELL_SIZE).floor())
	var maximum := Vector2i(((position + Vector2.ONE * radius) / NAVIGATION_CELL_SIZE).floor())
	_candidate_indices.clear()
	_navigation_candidates.clear()
	for x in range(minimum.x, maximum.x + 1):
		for z in range(minimum.y, maximum.y + 1):
			var cell := Vector2i(x, z)
			if _navigation_cells.has(cell):
				_candidate_indices.append_array(_navigation_cells[cell])
	_candidate_indices.sort()
	for index in _candidate_indices:
		_navigation_candidates.append(obstacles[index])
	return _navigation_candidates


func _rebuild_navigation_cells() -> void:
	_navigation_cells.clear()
	_maximum_navigation_radius = 0.0
	for index in range(obstacles.size()):
		var island := obstacles[index]
		var position := Vector2(island.global_position.x, island.global_position.z)
		var cell := Vector2i((position / NAVIGATION_CELL_SIZE).floor())
		var indices: PackedInt32Array = _navigation_cells.get(cell, PackedInt32Array())
		indices.append(index)
		_navigation_cells[cell] = indices
		_maximum_navigation_radius = maxf(_maximum_navigation_radius, island.navigation_radius)
	_navigation_count = obstacles.size()
	_navigation_segment = origin.segment
	_navigation_dirty = false


func _generate_through(anchor_position: RoutePosition, budget: int, clear_starting_fleet: bool = false) -> void:
	var leading_edge := anchor_position.advanced(-look_ahead)
	var trailing_edge := anchor_position.advanced(keep_behind)
	# A bounded batch also handles several thresholds crossed in one step.
	for spawn_index in range(budget):
		if next_position.compare(leading_edge) < 0:
			break
		var record := _generate_record()
		next_position = next_position.advanced(-rng.randf_range(minimum_spacing, maxf(minimum_spacing, maximum_spacing)))
		if clear_starting_fleet and _overlaps_starting_fleet(record):
			continue
		records.append(record)
		if record.route_position.compare(trailing_edge) <= 0:
			_load_record(record)


func _overlaps_starting_fleet(record: IslandRecord) -> bool:
	var position := record.scene_position(origin.segment)
	for ship in fleet.members:
		var clearance := record.radius + record.depth + ship.hull_radius + ship.hull_half_segment + ship.island_clearance + 300.0
		if position.distance_squared_to(ship.global_position) < clearance * clearance:
			return true
	return false


func _generate_record() -> IslandRecord:
	var record := IslandRecord.new()
	record.entity_id = _next_id
	_next_id += 1
	record.route_position = next_position
	record.altitude = rng.randf_range(altitude_range.x, altitude_range.y)
	record.radius = rng.randf_range(130.0, 220.0)
	record.depth = rng.randf_range(160.0, 300.0)
	record.lateral_position = rng.randf_range(-field_half_width, field_half_width)
	return record


func _load_record(record: IslandRecord) -> void:
	var island := island_scene.instantiate() as FloatingIsland
	container.add_child(island)
	island.configure(record, origin.segment)
	origin.register_root(island)
	active[record.entity_id] = island
	obstacles.append(island)
	_navigation_dirty = true
