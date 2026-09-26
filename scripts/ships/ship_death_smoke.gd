class_name ShipDeathSmoke
extends Node3D

enum State { IDLE, SMOKING, STOPPED }

@export var particles: GPUParticles3D
## Bounds around each emission point, including the plume's rise and expansion.
@export_range(1.0, 500.0) var plume_extent: float = 100.0

var _points: Array[Marker3D] = []
var _particles_per_point: int = 0
var _state: State = State.IDLE
var _emission_credit: float = 0.0
var _bounds_age: float = 0.0
var _recent_bounds: Array[AABB] = []
var _current_bounds := AABB()
var _emission_bounds := AABB()


func _ready() -> void:
	set_physics_process(false)
	_particles_per_point = particles.amount
	visibility_changed.connect(_on_visibility_changed)


func start(points: Array[Marker3D]) -> void:
	if _state != State.IDLE:
		return
	for point in points:
		if is_instance_valid(point) and point.is_inside_tree() and not point.is_queued_for_deletion():
			_points.append(point)
			point.tree_exiting.connect(_on_point_exiting.bind(point), CONNECT_ONE_SHOT)
	if _points.is_empty():
		stop()
		return
	# Amount authors density per source; one GPU system holds all source trails.
	particles.amount = _particles_per_point * _points.size()
	# A fixed, world-aligned local frame leaves old puffs behind the moving hull.
	# Local particles can then move together during an origin shift without reset.
	particles.top_level = true
	_state = State.SMOKING
	_on_visibility_changed()


func stop() -> void:
	_state = State.STOPPED
	set_physics_process(false)
	particles.emitting = false
	particles.hide()
	_recent_bounds.clear()
	_disconnect_points()


func _on_point_exiting(point: Marker3D) -> void:
	_points.erase(point)
	if _points.is_empty():
		stop()


func _disconnect_points() -> void:
	for point in _points:
		if is_instance_valid(point) and point.tree_exiting.is_connected(_on_point_exiting.bind(point)):
			point.tree_exiting.disconnect(_on_point_exiting.bind(point))
	_points.clear()


func _exit_tree() -> void:
	_disconnect_points()


func is_emitting() -> bool:
	return _state == State.SMOKING and is_visible_in_tree()


func _on_visibility_changed() -> void:
	if _state != State.SMOKING:
		return
	var shown := is_visible_in_tree()
	set_physics_process(shown)
	if not shown:
		return
	# Hidden GPU particles do not age. Clear them before revealing a fresh plume.
	particles.global_transform = Transform3D(Basis.IDENTITY, global_position)
	particles.reset_physics_interpolation()
	_emission_credit = 0.0
	_bounds_age = 0.0
	_recent_bounds.clear()
	_current_bounds = AABB()
	_emission_bounds = AABB()
	particles.visibility_aabb = _emission_bounds.grow(plume_extent)
	particles.restart()
	# Manual emission supplies positions without changing a material per frame.
	# All emitters can share the authored GPU motion, growth, and color material.
	particles.emitting = false


func _physics_process(delta: float) -> void:
	var particle_delta := delta * particles.speed_scale
	_bounds_age += particle_delta
	_emission_credit += particle_delta * _particles_per_point * particles.amount_ratio / particles.lifetime
	if _emission_credit < 1.0:
		return
	var count := int(_emission_credit)
	_emission_credit -= count
	for point in _points:
		var offset := particles.to_local(point.global_position)
		_update_bounds(offset)
		for puff in range(count):
			particles.emit_particle(Transform3D(Basis.IDENTITY, offset), Vector3.ZERO, Color.WHITE, Color(), GPUParticles3D.EMIT_FLAG_POSITION)
	particles.visibility_aabb = _emission_bounds.grow(plume_extent)


func _update_bounds(offset: Vector3) -> void:
	# Retain only the living trail plus at most one second of conservative padding.
	if _bounds_age >= 1.0:
		_bounds_age = fmod(_bounds_age, 1.0)
		_recent_bounds.append(_current_bounds)
		if _recent_bounds.size() > ceili(particles.lifetime):
			_recent_bounds.pop_front()
		_current_bounds = AABB(offset, Vector3.ZERO)
		_emission_bounds = _current_bounds
		for bounds in _recent_bounds:
			_emission_bounds = _emission_bounds.merge(bounds)
	_current_bounds = _current_bounds.expand(offset)
	_emission_bounds = _emission_bounds.expand(offset)


func shift_origin(displacement: Vector3) -> void:
	if _state != State.SMOKING:
		return
	particles.global_position -= displacement
	particles.reset_physics_interpolation()
