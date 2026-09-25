class_name Airship
extends CharacterBody3D

enum Faction { FRIENDLY, HOSTILE, NEUTRAL }

@export var entity_id: int = 0
@export var faction: Faction = Faction.FRIENDLY
@export var visual_root: Node3D
@export var hull_collider: CollisionShape3D
@export_range(1.0, 40.0) var maximum_speed: float = 18.0
@export_range(0.1, 15.0) var acceleration: float = 3.0
@export_range(0.1, 15.0) var braking: float = 4.0
@export_range(0.1, 10.0) var climb_speed: float = 2.0
@export_range(1.0, 90.0) var yaw_speed_degrees: float = 24.0
@export_range(0.0, 20.0) var pitch_limit_degrees: float = 8.0
@export_range(0.0, 20.0) var bank_limit_degrees: float = 7.0
@export_range(2.0, 20.0) var island_clearance: float = 8.0

var travel := ShipTravel.new()
var island_navigation := ShipIslandNavigation.new()
var preferred_velocity := Vector3.ZERO
var navigation_velocity := Vector3.ZERO
var hull_radius: float = 2.2
var hull_half_segment: float = 2.8


func _ready() -> void:
	var capsule := hull_collider.shape as CapsuleShape3D
	assert(capsule != null, "The movement prototype expects a capsule hull.")
	hull_radius = capsule.radius
	hull_half_segment = maxf(0.0, capsule.height * 0.5 - capsule.radius)


func prepare_travel(delta: float, anchor_position: Vector3, anchor_velocity: Vector3) -> void:
	set_preferred_velocity(travel.preferred_velocity(delta, global_position - anchor_position, anchor_velocity))


func set_preferred_velocity(value: Vector3) -> void:
	preferred_velocity = value


func move_ship(delta: float, avoidance: Vector3, islands: Array[FloatingIsland]) -> void:
	navigation_velocity = island_navigation.steer(self, islands, delta)
	var desired := (navigation_velocity + avoidance).limit_length(maximum_speed)
	desired.y = clampf(desired.y, -climb_speed, climb_speed)
	var rate := braking if desired.length_squared() < velocity.length_squared() else acceleration
	velocity = velocity.move_toward(desired, rate * delta)
	move_and_slide()
	velocity = get_real_velocity().limit_length(maximum_speed)
	_update_attitude(delta)


func _update_attitude(delta: float) -> void:
	var horizontal_speed := Vector2(velocity.x, velocity.z).length()
	var yaw_step: float = 0.0
	if horizontal_speed > 0.1:
		var desired_yaw := atan2(-velocity.x, -velocity.z)
		var limit := deg_to_rad(yaw_speed_degrees) * delta
		yaw_step = clampf(wrapf(desired_yaw - rotation.y, -PI, PI), -limit, limit)
		rotation.y += yaw_step
	var pitch_limit := deg_to_rad(pitch_limit_degrees)
	var desired_pitch := clampf(atan2(velocity.y, maxf(horizontal_speed, 0.1)), -pitch_limit, pitch_limit)
	var turn_fraction := yaw_step / maxf(deg_to_rad(yaw_speed_degrees) * delta, 0.0001)
	var desired_bank := turn_fraction * deg_to_rad(bank_limit_degrees)
	visual_root.rotation.x = move_toward(visual_root.rotation.x, desired_pitch, deg_to_rad(12.0) * delta)
	visual_root.rotation.z = move_toward(visual_root.rotation.z, desired_bank, deg_to_rad(12.0) * delta)
