class_name ShipTravel
extends RefCounted

var formation_extent: Vector3
var step_radius: float
var arrival_radius: float = 10.0
var correction_speed: float = 30.0
var goal_offset := Vector3.ZERO
var goals_reached: int = 0
var rng := RandomNumberGenerator.new()
var _retarget_time: float = 0.0


func initialize(initial_offset: Vector3, seed_value: int, extent: Vector3, wander_radius: float) -> void:
	formation_extent = extent
	step_radius = wander_radius
	rng.seed = seed_value
	goal_offset = initial_offset
	choose_nearby_goal(initial_offset)


func preferred_velocity(delta: float, relative_position: Vector3, anchor_velocity: Vector3) -> Vector3:
	_retarget_time = maxf(0.0, _retarget_time - delta)
	if relative_position.distance_to(goal_offset) <= arrival_radius and _retarget_time <= 0.0:
		goals_reached += 1
		choose_nearby_goal(relative_position)
	var correction := (goal_offset - relative_position) * 0.8
	return anchor_velocity + correction.limit_length(correction_speed)


func choose_nearby_goal(relative_position: Vector3) -> void:
	_retarget_time = 1.2
	for attempt in range(16):
		var offset := Vector3(rng.randf_range(-1.0, 1.0), rng.randf_range(-1.0, 1.0), rng.randf_range(-1.0, 1.0))
		if offset.length_squared() < 0.1:
			continue
		var candidate := relative_position + offset.normalized() * rng.randf_range(25.0, step_radius)
		if _inside_formation(candidate):
			goal_offset = candidate
			return
	# A displaced ship returns in small steps even when no sampled goal fits.
	goal_offset = relative_position.move_toward(Vector3.ZERO, step_radius)


func _inside_formation(offset: Vector3) -> bool:
	return (offset / formation_extent).length_squared() <= 1.0
