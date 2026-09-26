class_name FleetController
extends Node

@export var anchor: Node3D
@export var average_focus: Node3D
@export var formation_extent := Vector3(1800.0, 1200.0, 1800.0)
## X starts inward combat steering and ends regrouping; Y breaks off pursuit.
@export var combat_radii := Vector2(1800.0, 2600.0)
@export_range(30.0, 400.0) var wander_step_radius: float = 160.0
## Maximum travel correction relative to the moving anchor, in meters per second.
@export_range(1.0, 100.0) var wander_speed: float = 30.0
@export_range(1.0, 300.0) var cruise_speed: float = 90.0
@export_range(1.0, 100.0) var acceleration: float = 15.0
@export_range(0.0, 1000.0) var comfortable_gap: float = 80.0
@export_range(1.0, 1000.0) var slowdown_distance: float = 160.0

var members: Array[Airship] = []
var average_position: Vector3:
	get:
		return average_focus.global_position
var velocity := Vector3.ZERO
var speed: float = 0.0
var _anchor_initialized: bool = false


func register_ship(ship: Airship) -> void:
	if ship.faction != Factions.PLAYER or not ship.alive or ship in members:
		return
	members.append(ship)
	ship.tree_exiting.connect(unregister_ship.bind(ship), CONNECT_ONE_SHOT)
	if _anchor_initialized:
		_initialize_travel(ship)


func unregister_ship(ship: Airship) -> void:
	members.erase(ship)
	var callback := unregister_ship.bind(ship)
	if ship.tree_exiting.is_connected(callback):
		ship.tree_exiting.disconnect(callback)


func initialize_anchor() -> void:
	assert(combat_radii.x > 0.0 and combat_radii.y > combat_radii.x)
	_update_average()
	anchor.global_position = average_position
	for ship in members:
		_initialize_travel(ship)
	_anchor_initialized = true


func advance(delta: float) -> void:
	_update_average()
	if members.is_empty():
		speed = 0.0
		velocity = Vector3.ZERO
		return
	var excess := maxf(0.0, anchor.global_position.distance_to(average_position) - comfortable_gap)
	var ratio := excess / maxf(slowdown_distance, 1.0)
	var target_speed := cruise_speed / (1.0 + ratio * ratio)
	speed = move_toward(speed, target_speed, acceleration * delta)
	velocity = Vector3.FORWARD * speed
	anchor.global_position += velocity * delta


func _update_average() -> void:
	if members.is_empty():
		return
	var total := Vector3.ZERO
	for ship in members:
		total += ship.global_position
	average_focus.global_position = total / float(members.size())


func _initialize_travel(ship: Airship) -> void:
	assert(formation_extent.x > 0.0 and formation_extent.y > 0.0 and formation_extent.z > 0.0)
	ship.travel.correction_speed = wander_speed
	ship.travel.initialize(ship.global_position - anchor.global_position, ship.entity_id * 104729, formation_extent, wander_step_radius)
