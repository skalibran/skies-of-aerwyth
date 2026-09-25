extends SceneTree

const KESTREL := preload("res://scenes/ships/kestrel.tscn")
const CANNON := preload("res://resources/weapons/rusty_cannon.tres")

var _failures: Array[String] = []
var _fixture: Node3D
var _projectiles: ProjectileController
var _origin: FloatingOrigin
var _shooter: Airship
var _target: Airship
var _weapon: WeaponDefinition


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	for rate in [30, 60, 120]:
		for speed in [20.0, 100.0]:
			for offset in [Vector3(60, 0, 0), Vector3(60, 20, 0), Vector3(60, -20, 0)]:
				_setup()
				_weapon.launch_speed = speed
				_target.position = offset
				var velocity := Vector3(1, 0.2, -2)
				var time := _fire(velocity)
				var initial_velocity := _projectiles.shots[0].velocity
				var expected := _projectiles.shots[0].expected_position
				var half := time * 0.5
				_advance(half, rate, velocity)
				_check(_target.current_health == 500 and _projectiles.shots.size() == 1, "Damage waits for the scheduled arrival.")
				_check(_projectiles.shots[0].position.distance_to(Ballistics.displacement(initial_velocity, _weapon.gravity, half)) < 0.002, "Visuals follow the solved gravity arc at both launch speeds and all step rates.")
				_check(_projectiles.shots[0].expected_position == expected, "The impact snapshot is immutable during flight.")
				_advance(half + 1.0 / rate, rate, velocity)
				_check(_target.current_health == 495 and _projectiles.shots.is_empty() and _projectiles.predicted_check_count == 1, "Elevated moving targets receive exactly one delayed hit.")
				await _teardown()
	await _check_miss_and_tolerance()
	await _check_interception_and_lifetime()
	await _check_lifecycle_and_rebase()
	for failure in _failures:
		printerr("FAIL: ", failure)
	if _failures.is_empty():
		print("PASS: predicted projectile arcs, timing, hull tolerance, misses, filtering, lifetime, and rebasing.")
	quit(0 if _failures.is_empty() else 1)


func _setup() -> void:
	_fixture = Node3D.new()
	root.add_child(_fixture)
	_projectiles = ProjectileController.new()
	_fixture.add_child(_projectiles)
	_origin = FloatingOrigin.new()
	_fixture.add_child(_origin)
	_origin.register_root(_projectiles)
	_shooter = _ship(Factions.PLAYER, Vector3.ZERO)
	_target = _ship(Factions.ENEMY, Vector3(60, 0, 0))
	_weapon = CANNON.duplicate() as WeaponDefinition


func _ship(faction: StringName, position: Vector3) -> Airship:
	var ship := KESTREL.instantiate() as Airship
	ship.freeze = true
	ship.faction = faction
	_fixture.add_child(ship)
	ship.position = position
	_origin.register_root(ship)
	return ship


func _fire(velocity: Vector3 = Vector3.ZERO) -> float:
	var relative := _target.global_position - _shooter.global_position
	var time := Ballistics.intercept_time(relative, velocity, _weapon.launch_speed, _weapon.gravity, _weapon.lifetime)
	assert(time > 0.0)
	var launch := Ballistics.launch_velocity(relative, velocity, _weapon.gravity, time)
	_projectiles.fire(_shooter, _shooter.global_position, launch, _weapon, _target, time)
	return time


func _advance(seconds: float, rate: int = 60, velocity: Vector3 = Vector3.ZERO) -> void:
	while seconds > 0.0000001:
		var duration := minf(seconds, 1.0 / rate)
		if is_instance_valid(_target):
			_target.position += velocity * duration
		_projectiles.step(duration)
		seconds -= duration


func _check_miss_and_tolerance() -> void:
	_setup()
	var time := _fire()
	_target.position.z += 20.0
	_advance(time + 0.01)
	_check(_target.current_health == 500 and _projectiles.shots.size() == 1 and _projectiles.predicted_check_count == 1, "A dodging target is missed and its visual keeps flying.")
	var position := _projectiles.shots[0].position
	_target.position.z -= 20.0
	_advance(0.5)
	_check(_target.current_health == 500 and _projectiles.predicted_check_count == 1 and _projectiles.shots[0].position != position, "Returning after arrival cannot cause a second hit check.")
	_advance(8.0)
	_check(_projectiles.shots.is_empty() and _projectiles.expired_count == 1, "Missed visuals expire at the weapon lifetime.")
	await _teardown()
	# Rotation makes the capsule's long axis horizontal along X. These offsets
	# distinguish the actual capsule from a bounding sphere or a center-only test.
	for offset in [Vector3(0, 2.69, 0), Vector3(0, 2.71, 0), Vector3(5.49, 0, 0), Vector3(5.51, 0, 0)]:
		_setup()
		_target.rotation.y = PI * 0.5
		time = _fire()
		_target.position += offset
		_advance(time + 0.001)
		var should_hit: bool = offset.length() < 2.7 or (offset.x > 0 and offset.x < 5.5)
		_check((_target.current_health == 495) == should_hit, "Impact tolerance follows the rotated capsule boundary.")
		await _teardown()


func _check_interception_and_lifetime() -> void:
	_setup()
	var ally := _ship(Factions.PLAYER, Vector3(20, 0, 0))
	var other_enemy := _ship(Factions.ENEMY, Vector3(40, 0, 0))
	var obstacle := StaticBody3D.new()
	obstacle.collision_layer = 2
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(5, 20, 20)
	shape.shape = box
	obstacle.add_child(shape)
	_fixture.add_child(obstacle)
	obstacle.position.x = 30
	await physics_frame
	_advance(_fire() + 0.01)
	_check(_target.current_health == 495 and ally.current_health == 500 and other_enemy.current_health == 500, "Only the intended target takes damage through intervening allies, enemies, and scenery.")
	_check(_projectiles.ray_query_count == 0 and _projectiles.friendly_hits == 0, "Predicted shots issue no collision queries or friendly impacts.")
	await _teardown()
	for deadline in [0.5, 0.51]:
		_setup()
		_weapon.lifetime = 0.5
		var launch := Vector3(100, 0, 0)
		_target.position = Ballistics.displacement(launch, _weapon.gravity, deadline)
		_projectiles.fire(_shooter, Vector3.ZERO, launch, _weapon, _target, deadline)
		_projectiles.step(0.0)
		_check(_projectiles.shots[0].position == Vector3.ZERO and _target.current_health == 500, "Zero time never advances or resolves a projectile.")
		_projectiles.step(10.0)
		_check(_projectiles.shots.is_empty() and (_target.current_health == 495) == (deadline == 0.5), "A large step honors the lifetime and a hit scheduled exactly at expiry.")
		await _teardown()


func _check_lifecycle_and_rebase() -> void:
	_setup()
	var time := _fire()
	_advance(time * 0.5)
	var local_expected := _projectiles.shots[0].expected_position
	_origin.shift_segments(-1)
	_shooter.queue_free()
	await process_frame
	_check(_projectiles.shots[0].expected_position == local_expected, "Rebasing translates the snapshot through its root.")
	_advance(time * 0.5 + 0.01)
	_check(_target.current_health == 495 and _projectiles.shots.is_empty(), "Shooter removal and rebasing preserve the pending hit and captured faction.")
	await _teardown()
	for invalidation in ["freed", "removed", "queued", "dead", "friendly"]:
		_setup()
		time = _fire()
		if invalidation == "freed":
			_target.queue_free()
			await process_frame
		elif invalidation == "removed":
			_fixture.remove_child(_target)
		elif invalidation == "queued":
			_target.queue_free()
		elif invalidation == "dead":
			_target.take_damage(500, Factions.PLAYER)
		else:
			_target.faction = Factions.PLAYER
		_advance(time + 0.01)
		_check(_projectiles.damaging_hits == 0 and _projectiles.shots.size() == 1 and _projectiles.predicted_check_count == 1, "Unavailable or newly friendly targets turn into one-time misses.")
		if invalidation == "removed":
			_target.free()
		await _teardown()
	_setup()
	_target.current_health = 5
	time = _fire()
	_fire()
	var deaths: Array[int] = []
	_target.died.connect(func(_ship: Airship) -> void: deaths.append(1))
	_advance(time + 0.01)
	_check(deaths.size() == 1 and _projectiles.damaging_hits == 1 and _projectiles.shots.size() == 1, "Simultaneous lethal arrivals cannot damage or kill the target twice.")
	await _teardown()


func _teardown() -> void:
	_check(_projectiles.ray_query_count == 0, "The predicted path never uses physics collision queries.")
	_projectiles.clear()
	await process_frame
	_check(_projectiles.shots.is_empty() and _projectiles.get_child_count() == 0, "Clearing releases every shot and visual, including pending impacts.")
	_fixture.queue_free()
	await process_frame


func _check(condition: bool, message: String) -> void:
	if not condition and message not in _failures:
		_failures.append(message)
