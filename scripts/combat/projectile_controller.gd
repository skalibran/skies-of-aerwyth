class_name ProjectileController
extends Node3D

const MAX_CHORD_ERROR: float = 0.01

enum HitModel { LIVE_SWEEP, PREDICTED_IMPACT }

## Captured per shot. Live sweeps remain available for the performance comparison.
@export var hit_model: HitModel = HitModel.PREDICTED_IMPACT
## Extra distance around the intended target's capsule at the scheduled impact.
@export_range(0.0, 5.0, 0.1) var impact_tolerance: float = 0.5

class Shot extends RefCounted:
	var position: Vector3
	var velocity: Vector3
	var gravity: float
	var remaining: float
	var damage: float
	var faction: StringName
	var source: WeakRef
	var visual: MeshInstance3D
	var hit_model: HitModel
	var target: WeakRef
	var expected_position: Vector3
	var impact_remaining: float = -1.0
	var impact_pending: bool = false
	var impact_tolerance: float

var shots: Array[Shot] = []
var fired_count: int = 0
var damaging_hits: int = 0
var friendly_hits: int = 0
var expired_count: int = 0
var ray_query_count: int = 0
var predicted_check_count: int = 0
var _mesh := SphereMesh.new()
var _query := PhysicsRayQueryParameters3D.new()


func _ready() -> void:
	_mesh.radius = 0.3
	_mesh.height = 0.6
	_mesh.radial_segments = 8
	_mesh.rings = 4
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.85, 0.64, 0.24)
	material.roughness = 0.9
	_mesh.material = material
	_query.collision_mask = 3
	_query.hit_from_inside = true


func fire(shooter: Airship, muzzle: Vector3, velocity: Vector3, weapon: WeaponDefinition, target: Airship = null, impact_time: float = -1.0) -> void:
	var shot := Shot.new()
	shot.position = to_local(muzzle)
	shot.velocity = velocity
	shot.gravity = weapon.gravity
	shot.remaining = weapon.lifetime
	shot.damage = weapon.damage
	shot.faction = shooter.faction
	shot.source = weakref(shooter)
	shot.hit_model = hit_model
	if hit_model == HitModel.PREDICTED_IMPACT and is_instance_valid(target) and is_finite(impact_time) and impact_time > 0.0 and impact_time <= weapon.lifetime:
		shot.target = weakref(target)
		# Both points are local to this translation-only, floating-origin root.
		shot.expected_position = to_local(muzzle + Ballistics.displacement(velocity, weapon.gravity, impact_time))
		shot.impact_remaining = impact_time
		shot.impact_pending = true
		shot.impact_tolerance = impact_tolerance
	shot.visual = MeshInstance3D.new()
	shot.visual.mesh = _mesh
	shot.visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(shot.visual)
	shot.visual.position = shot.position
	shot.visual.reset_physics_interpolation()
	shots.append(shot)
	fired_count += 1


func step(delta: float) -> void:
	if delta <= 0.0:
		return
	var space := get_world_3d().direct_space_state
	for index in range(shots.size() - 1, -1, -1):
		var shot := shots[index]
		var duration := minf(delta, shot.remaining)
		var impacted := _step_predicted(shot, duration) if shot.hit_model == HitModel.PREDICTED_IMPACT else _step_live(shot, duration, space)
		if impacted or shot.remaining <= 0.000001:
			if not impacted:
				expired_count += 1
			shot.visual.queue_free()
			shots.remove_at(index)
		else:
			shot.visual.position = shot.position


func _step_live(shot: Shot, remaining_step: float, space: PhysicsDirectSpaceState3D) -> bool:
	var source := shot.source.get_ref() as Airship
	_query.exclude = [source.get_rid()] if is_instance_valid(source) else []
	var maximum_step := sqrt(8.0 * MAX_CHORD_ERROR / maxf(shot.gravity, 0.001))
	while remaining_step > 0.0000001:
		var duration := minf(remaining_step, maximum_step)
		var next := shot.position + Ballistics.displacement(shot.velocity, shot.gravity, duration)
		_query.from = to_global(shot.position)
		_query.to = to_global(next)
		ray_query_count += 1
		var hit := space.intersect_ray(_query)
		if not hit.is_empty():
			_resolve_hit(shot, hit.collider)
			return true
		shot.position = next
		shot.velocity += Vector3.DOWN * shot.gravity * duration
		shot.remaining -= duration
		remaining_step -= duration
	return false


func _step_predicted(shot: Shot, duration: float) -> bool:
	shot.position += Ballistics.displacement(shot.velocity, shot.gravity, duration)
	shot.velocity += Vector3.DOWN * shot.gravity * duration
	shot.remaining -= duration
	if not shot.impact_pending:
		return false
	shot.impact_remaining -= duration
	if shot.impact_remaining > 0.000001:
		return false
	# One attempt at the first physics tick reaching the captured arrival time.
	# A miss never retargets or checks again, even if the target returns later.
	shot.impact_pending = false
	predicted_check_count += 1
	var target := shot.target.get_ref() as Airship
	if not is_instance_valid(target) or not target.is_inside_tree() or target.is_queued_for_deletion() or not target.alive or not Factions.are_hostile(shot.faction, target.faction):
		return false
	var point := target.hull_collider.to_local(to_global(shot.expected_position))
	var closest := Vector3(0, clampf(point.y, -target.hull_half_segment, target.hull_half_segment), 0)
	var radius := target.hull_radius + shot.impact_tolerance
	if point.distance_squared_to(closest) > radius * radius:
		return false
	_resolve_hit(shot, target)
	return true


func clear() -> void:
	for shot in shots:
		shot.visual.queue_free()
	shots.clear()


func _resolve_hit(shot: Shot, collider: Object) -> void:
	var ship := collider as Airship
	if not is_instance_valid(ship) or not ship.alive:
		return
	if Factions.are_hostile(shot.faction, ship.faction):
		ship.take_damage(shot.damage, shot.faction)
		damaging_hits += 1
	elif ship.faction == shot.faction:
		friendly_hits += 1
