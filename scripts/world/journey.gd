class_name Journey
extends Node3D

@export var initial_ships: Array[Airship] = []
@export var fleet: FleetController
@export var origin: FloatingOrigin
@export var island_spawner: IslandSpawner
@export var camera_rig: FleetCamera
@export var ground: MeshInstance3D

var ships: Array[Airship] = []
var _positions := PackedVector3Array()
var _velocities := PackedVector3Array()
var _axes := PackedVector3Array()
var _corrections := PackedVector3Array()
var _stream_timer: float = 0.0


func _ready() -> void:
	for ship in initial_ships:
		register_ship(ship)
	fleet.initialize_anchor()
	origin.register_root(fleet.anchor)
	origin.register_root(fleet.average_focus)
	origin.register_root(camera_rig)
	origin.register_root(ground)
	_center_ground()
	island_spawner.initialize(anchor_route_position())
	island_spawner.update_region(anchor_route_position())
	camera_rig.focus_fleet()


func _physics_process(delta: float) -> void:
	step_simulation(delta)


func register_ship(ship: Airship) -> void:
	if ship in ships:
		return
	for other in ships:
		assert(other.entity_id != ship.entity_id, "Each ship needs a unique stable ID.")
	ships.append(ship)
	origin.register_root(ship)
	fleet.register_ship(ship)
	ship.tree_exiting.connect(unregister_ship.bind(ship), CONNECT_ONE_SHOT)
	_resize_snapshots()


func unregister_ship(ship: Airship) -> void:
	ships.erase(ship)
	var callback := unregister_ship.bind(ship)
	if ship.tree_exiting.is_connected(callback):
		ship.tree_exiting.disconnect(callback)
	fleet.unregister_ship(ship)
	origin.unregister_root(ship)
	_resize_snapshots()


func step_simulation(delta: float) -> void:
	_snapshot_ships()
	fleet.advance(delta)
	for index in range(ships.size()):
		_corrections[index] = ShipAvoidance.correction(index, ships, _positions, _velocities, _axes)
	for index in range(ships.size()):
		ships[index].move_ship(delta, _corrections[index], island_spawner.obstacles)
	_center_ground()
	origin.recenter_if_needed(fleet.anchor.global_position.z)
	_stream_timer -= delta
	if _stream_timer <= 0.0:
		_stream_timer = 0.25
		island_spawner.update_region(anchor_route_position())


func anchor_route_position() -> RoutePosition:
	return RoutePosition.from_scene(fleet.anchor.global_position.z, origin.segment)


func _center_ground() -> void:
	# This uniform visual placeholder can follow travel without visible scrolling.
	# Keep its altitude fixed; future terrain will own persistent surface geometry.
	ground.global_position.x = fleet.anchor.global_position.x
	ground.global_position.z = fleet.anchor.global_position.z


func _snapshot_ships() -> void:
	for index in range(ships.size()):
		_positions[index] = ships[index].global_position
		_velocities[index] = ships[index].velocity
		_axes[index] = ships[index].global_basis.z


func _resize_snapshots() -> void:
	_positions.resize(ships.size())
	_velocities.resize(ships.size())
	_axes.resize(ships.size())
	_corrections.resize(ships.size())
