class_name ProjectileController
extends Node3D

const MAX_CHORD_ERROR: float = 0.1

class Shot extends RefCounted:
	var position: Vector3
	var velocity: Vector3
	var gravity: float
	var remaining: float
	var damage: float
	var faction: StringName
	var source: WeakRef
	var visual: MeshInstance3D

var shots: Array[Shot] = []
var fired_count: int = 0
var damaging_hits: int = 0
var friendly_hits: int = 0
var expired_count: int = 0
var _mesh := SphereMesh.new()
var _query := PhysicsRayQueryParameters3D.new()


func _ready() -> void:
	_mesh.radius = 3.0
	_mesh.height = 6.0
	_mesh.radial_segments = 8
	_mesh.rings = 4
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.85, 0.64, 0.24)
	material.roughness = 0.9
	_mesh.material = material
	_query.collision_mask = 3
	_query.hit_from_inside = true


func fire(shooter: Airship, muzzle: Vector3, velocity: Vector3, weapon: WeaponDefinition) -> void:
	var shot := Shot.new()
	shot.position = to_local(muzzle)
	shot.velocity = velocity
	shot.gravity = weapon.gravity
	shot.remaining = weapon.lifetime
	shot.damage = weapon.damage
	shot.faction = shooter.faction
	shot.source = weakref(shooter)
	shot.visual = MeshInstance3D.new()
	shot.visual.mesh = _mesh
	shot.visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(shot.visual)
	shot.visual.position = shot.position
	shot.visual.reset_physics_interpolation()
	shots.append(shot)
	fired_count += 1


func step(delta: float) -> void:
	var space := get_world_3d().direct_space_state
	for index in range(shots.size() - 1, -1, -1):
		var shot := shots[index]
		var source := shot.source.get_ref() as Airship
		_query.exclude = [source.get_rid()] if is_instance_valid(source) else []
		var remaining_step := minf(delta, shot.remaining)
		var maximum_step := sqrt(8.0 * MAX_CHORD_ERROR / maxf(shot.gravity, 0.01))
		var impacted := false
		while remaining_step > 0.0000001:
			var duration := minf(remaining_step, maximum_step)
			var next := shot.position + Ballistics.displacement(shot.velocity, shot.gravity, duration)
			_query.from = to_global(shot.position)
			_query.to = to_global(next)
			var hit := space.intersect_ray(_query)
			if not hit.is_empty():
				_resolve_hit(shot, hit.collider)
				impacted = true
				break
			shot.position = next
			shot.velocity += Vector3.DOWN * shot.gravity * duration
			shot.remaining -= duration
			remaining_step -= duration
		if impacted or shot.remaining <= 0.000001:
			if not impacted:
				expired_count += 1
			shot.visual.queue_free()
			shots.remove_at(index)
		else:
			shot.visual.position = shot.position


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
