class_name Airship
extends RigidBody3D

signal health_changed(current: float, maximum: float)
signal died(ship: Airship)

const ENEMY_TINT := preload("res://materials/ships/enemy_tint.tres")

@export var entity_id: int = 0
@export var faction: StringName = Factions.PLAYER
@export var visual_root: Node3D
@export var hull_collider: CollisionShape3D
@export var mounted_slots: Array[MountedSlot] = []
@export var preferred_combat_positions := PackedStringArray()
@export_range(1.0, 10000.0) var maximum_health: float = 500.0
@export_range(10.0, 90.0) var engagement_distance: float = 60.0
@export_range(0.1, 1.0) var combat_speed_ratio: float = 0.5
@export_range(2.0, 15.0) var combat_pass_seconds: float = 6.0
## Primary horizontal propulsion axis in ship-local space. Altitude uses lift control.
@export var primary_movement_direction := Vector3.FORWARD
## Propulsion target limit. Contact impulses and retained lateral momentum can exceed it.
@export_range(1.0, 40.0) var maximum_speed: float = 18.0
@export_range(0.1, 15.0) var acceleration: float = 3.0
@export_range(0.1, 15.0) var braking: float = 4.0
@export_range(0.1, 10.0) var climb_speed: float = 2.0
@export_range(1.0, 90.0) var yaw_speed_degrees: float = 24.0
@export_range(1.0, 180.0) var yaw_acceleration_degrees: float = 45.0
## Sideways momentum decay per second, independent of forward acceleration/braking.
@export_range(0.1, 5.0) var lateral_drag: float = 1.4
@export_range(0.0, 20.0) var pitch_limit_degrees: float = 8.0
@export_range(0.0, 20.0) var bank_limit_degrees: float = 7.0
@export_range(2.0, 20.0) var island_clearance: float = 8.0

var travel := ShipTravel.new()
var island_navigation := ShipIslandNavigation.new()
var combat := ShipCombat.new()
var current_health: float = 500.0
var alive: bool = true
var combat_engaged: bool = false
var navigation_time_usec: int = 0
var preferred_velocity := Vector3.ZERO
var navigation_velocity := Vector3.ZERO
var hull_radius: float = 2.2
var hull_half_segment: float = 2.8


func _ready() -> void:
	var capsule := hull_collider.shape as CapsuleShape3D
	assert(capsule != null, "The movement prototype expects a capsule hull.")
	hull_radius = capsule.radius
	hull_half_segment = maxf(0.0, capsule.height * 0.5 - capsule.radius)
	current_health = maximum_health
	for index in range(mounted_slots.size()):
		mounted_slots[index].initialize_phase(entity_id, index)
		mounted_slots[index].equipment_changed.connect(_on_equipment_changed.bind(mounted_slots[index]))
	_apply_faction_tint(visual_root)


func _apply_faction_tint(root: Node3D) -> void:
	if faction == Factions.ENEMY:
		for mesh in root.find_children("*", "MeshInstance3D", true, false):
			(mesh as MeshInstance3D).material_overlay = ENEMY_TINT


func _on_equipment_changed(slot: MountedSlot) -> void:
	combat.clear_target()
	combat_engaged = false
	_apply_faction_tint(slot)


func take_damage(amount: float, source_faction: StringName) -> void:
	if not alive or not is_finite(amount) or amount <= 0.0 or not Factions.are_hostile(source_faction, faction):
		return
	current_health = maxf(0.0, current_health - amount)
	alive = current_health > 0.0
	# A health listener can apply more damage synchronously. Only the call that
	# crosses zero owns the death notification.
	var died_now := not alive
	health_changed.emit(current_health, maximum_health)
	if died_now:
		died.emit(self)


func prepare_travel(delta: float, anchor_position: Vector3, anchor_velocity: Vector3) -> void:
	set_preferred_velocity(travel.preferred_velocity(delta, global_position - anchor_position, anchor_velocity))


func set_preferred_velocity(value: Vector3) -> void:
	preferred_velocity = value


func apply_movement_forces(delta: float, avoidance: Vector3, islands: Array[FloatingIsland], measure: bool = false) -> void:
	if not alive or freeze or delta <= 0.0:
		return
	var started: int = Time.get_ticks_usec() if measure else 0
	navigation_velocity = island_navigation.steer(self, islands, delta)
	if measure:
		navigation_time_usec = Time.get_ticks_usec() - started
	ShipFlight.apply_forces(self, navigation_velocity + avoidance, delta)
	_update_attitude(delta)


func _update_attitude(delta: float) -> void:
	var horizontal_speed := Vector2(linear_velocity.x, linear_velocity.z).length()
	var pitch_limit := deg_to_rad(pitch_limit_degrees)
	var desired_pitch := clampf(atan2(linear_velocity.y, maxf(horizontal_speed, 0.1)), -pitch_limit, pitch_limit)
	var turn_fraction := clampf(angular_velocity.y / deg_to_rad(yaw_speed_degrees), -1.0, 1.0)
	var desired_bank := turn_fraction * deg_to_rad(bank_limit_degrees)
	visual_root.rotation.x = move_toward(visual_root.rotation.x, desired_pitch, deg_to_rad(12.0) * delta)
	visual_root.rotation.z = move_toward(visual_root.rotation.z, desired_bank, deg_to_rad(12.0) * delta)
