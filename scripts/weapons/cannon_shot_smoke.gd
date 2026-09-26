class_name CannonShotSmoke
extends GPUParticles3D

@export_range(1, 32) var puffs_per_shot: int = 6
@export var speed_range := Vector2(20.0, 38.0)
@export_range(0.0, 80.0) var spread_degrees: float = 22.0
## Covers puff travel and expansion during the authored particle lifetime.
@export_range(1.0, 200.0) var plume_extent: float = 40.0

var emitted_bursts: int = 0
var dropped_bursts: int = 0
var _clock: float = 0.0
var _expires: Array[float] = []
var _bounds: Array[AABB] = []
var _rng := RandomNumberGenerator.new()
var _pending: Array[Transform3D] = []
var _warming_up: bool = false


func _ready() -> void:
	_rng.randomize()
	emitting = false
	hide()
	set_physics_process(false)


func burst(muzzle: Vector3, direction: Vector3) -> void:
	# The cosmetic budget never prevents the owning weapon from firing.
	if (_expires.size() + 1) * puffs_per_shot > amount:
		dropped_bursts += 1
		return
	var offset := to_local(muzzle)
	var forward := (global_basis.inverse() * direction).normalized()
	var up := Vector3.RIGHT if absf(forward.y) > 0.99 else Vector3.UP
	var side := forward.cross(up).normalized()
	up = side.cross(forward)
	if _expires.is_empty():
		# Clear GPU particles suspended while the entire batch was off screen.
		restart()
		emitting = false
		show()
		set_physics_process(true)
		# Initialize GPU buffers before submitting the first manual burst.
		_warming_up = RenderingServer.get_rendering_device() != null
		if _warming_up:
			RenderingServer.particles_request_process(get_base())
			RenderingServer.frame_post_draw.connect(_finish_warmup, CONNECT_ONE_SHOT)
	var bounds := AABB(offset, Vector3.ZERO).grow(plume_extent)
	visibility_aabb = bounds if _bounds.is_empty() else visibility_aabb.merge(bounds)
	_bounds.append(bounds)
	_expires.append(_clock + lifetime + 1.0 / Engine.physics_ticks_per_second)
	if _warming_up:
		_pending.append(Transform3D(Basis(side, up, -forward), offset))
	else:
		_emit_puffs(offset, forward, side, up)
	emitted_bursts += 1


func _finish_warmup() -> void:
	_warming_up = false
	for index in range(_pending.size()):
		var source := _pending[index]
		_emit_puffs(source.origin, -source.basis.z, source.basis.x, source.basis.y)
		_expires[index] = _clock + lifetime + 1.0 / Engine.physics_ticks_per_second
	_pending.clear()


func _emit_puffs(offset: Vector3, forward: Vector3, side: Vector3, up: Vector3) -> void:
	var cone_cosine := cos(deg_to_rad(spread_degrees))
	for puff in range(puffs_per_shot):
		var cosine := _rng.randf_range(cone_cosine, 1.0)
		var sine := sqrt(1.0 - cosine * cosine)
		var angle := _rng.randf_range(0.0, TAU)
		var velocity := (forward * cosine + (side * cos(angle) + up * sin(angle)) * sine) * _rng.randf_range(speed_range.x, speed_range.y)
		emit_particle(Transform3D(Basis.IDENTITY, offset), velocity, Color.WHITE, Color(), EMIT_FLAG_POSITION | EMIT_FLAG_VELOCITY)


func _physics_process(delta: float) -> void:
	_clock += delta * speed_scale
	if _warming_up:
		return
	var expired := false
	while not _expires.is_empty() and _expires.front() <= _clock:
		_expires.pop_front()
		_bounds.pop_front()
		expired = true
	if _expires.is_empty():
		clear()
	elif expired:
		var bounds := _bounds[0]
		for index in range(1, _bounds.size()):
			bounds = bounds.merge(_bounds[index])
		visibility_aabb = bounds


func clear() -> void:
	if RenderingServer.frame_post_draw.is_connected(_finish_warmup):
		RenderingServer.frame_post_draw.disconnect(_finish_warmup)
	_warming_up = false
	_pending.clear()
	_expires.clear()
	_bounds.clear()
	_clock = 0.0
	hide()
	set_physics_process(false)


func _exit_tree() -> void:
	clear()
