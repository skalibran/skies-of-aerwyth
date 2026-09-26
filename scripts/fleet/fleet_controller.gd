class_name FleetController
extends Node

## Persistent route center. Membership never changes its authored position.
@export var marker: Node3D
@export_range(60.0, 3000.0) var minimum_radius: float = 180.0
@export_range(10.0, 200.0) var ship_spacing: float = 35.0
@export_range(1.0, 200.0) var radius_change_speed: float = 30.0
@export_range(10.0, 400.0) var local_step: float = 50.0
@export_range(1.0, 100.0) var local_speed: float = 12.0
@export_range(1.0, 300.0) var cruise_speed: float = 25.0
@export_range(1.0, 100.0) var acceleration: float = 3.0
## Opponents approaching from outside can influence combat destinations inside.
@export_range(100.0, 2000.0) var entry_range: float = 600.0

var members: Array[Airship] = []
## Both factions share navigation space; only player members set travel pace.
var occupants: Array[Airship] = []
var radius: float = 180.0
var velocity := Vector3.ZERO
var speed: float = 0.0
var requested_speed: float = 0.0
var in_combat: bool = false


func register_ship(ship: Airship) -> void:
	if not ship.alive or ship in occupants:
		return
	occupants.append(ship)
	if ship.faction == Factions.PLAYER:
		members.append(ship)
	ship.tree_exiting.connect(unregister_ship.bind(ship), CONNECT_ONE_SHOT)


func unregister_ship(ship: Airship) -> void:
	members.erase(ship)
	occupants.erase(ship)
	var callback := unregister_ship.bind(ship)
	if ship.tree_exiting.is_connected(callback):
		ship.tree_exiting.disconnect(callback)


func initialize() -> void:
	radius = required_radius()


func required_radius() -> float:
	var footprint: float = 0.0
	var turn_room := minimum_radius
	for ship in occupants:
		var hull := ship.hull_radius + ship.hull_half_segment
		footprint += pow(hull + ship_spacing, 2.0)
		turn_room = maxf(turn_room, hull + local_speed / deg_to_rad(ship.yaw_speed_degrees) + local_speed * local_speed / (2.0 * ship.braking))
	return maxf(turn_room, sqrt(footprint) * 1.5)


func prepare_step(delta: float, combat_active: bool = false) -> void:
	if delta <= 0.0:
		return
	in_combat = combat_active
	var desired_radius := required_radius()
	if desired_radius >= radius or not in_combat:
		var fits := true
		for ship in occupants:
			if ship.global_position.distance_to(marker.global_position) + ship.hull_radius + ship.hull_half_segment + ShipNavigation.HULL_CLEARANCE > desired_radius:
				fits = false
		if desired_radius >= radius or fits:
			radius = move_toward(radius, desired_radius, radius_change_speed * delta)
	if members.is_empty():
		requested_speed = 0.0
		return
	requested_speed = cruise_speed
	for ship in members:
		requested_speed = minf(requested_speed, maxf(0.0, ship.maximum_speed - local_speed))
		var relative := ship.global_position - marker.global_position
		var room := radius - ship.hull_radius - ship.hull_half_segment - relative.length()
		if relative.z > 0.0:
			requested_speed = minf(requested_speed, cruise_speed * clampf(room / (radius * 0.25), 0.0, 1.0))


func advance(delta: float) -> void:
	if delta <= 0.0:
		return
	var sustainable := requested_speed
	for ship in members:
		sustainable = minf(sustainable, ship.navigation.safe_marker_speed)
	# Combat uses the same travel pace. Only fleet clearance can slow the marker.
	speed = minf(move_toward(speed, sustainable, acceleration * delta), sustainable)
	velocity = Vector3.FORWARD * speed
	marker.global_position += velocity * delta
