extends SceneTree

const SHIP := preload("res://scenes/ships/ship.tscn")
const KESTREL := preload("res://scenes/ships/kestrel.tscn")

var _rate: int = Engine.physics_ticks_per_second
var _delta: float = 1.0 / _rate
var _failures: Array[String] = []
var _fixture: Node3D
var _fleet: FleetController
var _visual: bool = false
var _paths: Array[Dictionary] = []


func _initialize() -> void:
	_visual = "--visual" in OS.get_cmdline_user_args()
	_run.call_deferred()


func _run() -> void:
	_fixture = Node3D.new()
	root.add_child(_fixture)
	_fleet = FleetController.new()
	_fleet.anchor = Node3D.new()
	_fixture.add_child(_fleet)
	_fixture.add_child(_fleet.anchor)
	await _check_turn()
	await _check_braking_and_axis()
	await _check_cohesion()
	await _check_contacts()
	await _check_impulse_recovery()
	await _check_death()
	await _check_pass()
	_fixture.queue_free()
	await process_frame
	for failure in _failures:
		printerr("FAIL: ", failure)
	if _failures.is_empty():
		print("PASS: forward thrust, braking, authored axes, physical contacts, impulse recovery, passive wreck physics, rebasing, and broadside passes.")
	quit(0 if _failures.is_empty() else 1)


func _ship(scene: PackedScene = SHIP, faction: StringName = Factions.PLAYER) -> Airship:
	var ship := scene.instantiate() as Airship
	ship.faction = faction
	_fixture.add_child(ship)
	return ship


func _check_turn() -> void:
	var ship := _ship()
	await physics_frame
	await physics_frame
	ship.linear_velocity = Vector3.FORWARD * 120.0
	var original := ship.linear_velocity
	ShipFlight.apply_forces(ship, Vector3.RIGHT * 120.0, _delta)
	_check(ship.linear_velocity.distance_to(original) < 3.0 and absf(ship.rotation.y) < deg_to_rad(0.1), "A new course cannot instantly rotate heading or velocity.")
	_check(absf(ship.angular_velocity.y) <= deg_to_rad(ship.yaw_acceleration_degrees) * _delta + 0.00001, "Turn rate builds within angular acceleration.")
	for tick in range(12 * _rate):
		await physics_frame
		ShipFlight.apply_forces(ship, Vector3.RIGHT * 120.0, _delta)
		_check(absf(ship.angular_velocity.y) <= deg_to_rad(ship.yaw_speed_degrees) + 0.00001, "Turn rate stays bounded.")
		if tick == _rate:
			var forward := ship.global_basis * ShipFlight.primary_axis(ship)
			_check(ship.linear_velocity.z < -40.0 and forward.angle_to(ship.linear_velocity.normalized()) > deg_to_rad(3.0), "The hull turns while existing forward momentum carries it along the old course.")
	_check(ship.linear_velocity.distance_to(Vector3.RIGHT * 120.0) < 1.0, "A sustained course settles into forward flight without permanent sideways drift.")
	ship.free()


func _check_braking_and_axis() -> void:
	var ship := _ship()
	await physics_frame
	await physics_frame
	ship.linear_velocity = Vector3.FORWARD * 120.0
	ShipFlight.apply_forces(ship, Vector3.ZERO, _delta)
	_check(ship.linear_velocity.length() > 110.0, "Braking retains momentum on the first tick.")
	for tick in range(4 * _rate):
		await physics_frame
		ShipFlight.apply_forces(ship, Vector3.ZERO, _delta)
	_check(ship.linear_velocity.length() < 0.1, "An idle ship eventually brakes to rest.")
	ship.primary_movement_direction = Vector3.RIGHT
	for tick in range(10 * _rate):
		await physics_frame
		ShipFlight.apply_forces(ship, Vector3.FORWARD * 100.0 + Vector3.UP * 200.0, _delta)
	var horizontal := Vector3(ship.linear_velocity.x, 0.0, ship.linear_velocity.z)
	_check((ship.global_basis * Vector3.RIGHT).dot(horizontal.normalized()) > 0.99, "A ship can author a different primary propulsion axis.")
	_check(is_equal_approx(ship.linear_velocity.y, ship.climb_speed), "Lift control respects the climb speed independently of yaw.")
	var velocity := ship.linear_velocity
	var rotation := ship.rotation
	ShipFlight.apply_forces(ship, Vector3.BACK * 180.0, 0.0)
	_check(ship.linear_velocity == velocity and ship.rotation == rotation, "A zero-duration step changes neither attitude nor momentum.")
	ship.free()


func _check_cohesion() -> void:
	var ship := _ship(KESTREL)
	var nearby := _ship(KESTREL, Factions.ENEMY)
	var distant := _ship(KESTREL, Factions.ENEMY)
	var vessels: Array[Airship] = [ship, nearby, distant]
	ship.position = Vector3(2500, 0, 0)
	nearby.position = Vector3(2100, 0, 0)
	distant.position = Vector3(2800, 0, 0)
	ship.combat.prepare(1.0, ship, vessels, _fleet)
	_check(ship.combat.target == nearby, "Target selection ignores a closer opponent outside the engagement area.")
	_check(ship.combat.passing and ship.combat._pass_direction.x < -0.1 and ship.preferred_velocity.x < 0.0, "Near the boundary, an eligible broadside pass favors an inward course.")
	nearby.position.x = 3100.0
	ship.position.x = 2700.0
	ship.combat.prepare(1.0, ship, vessels, _fleet)
	_check(ship.combat.returning_to_anchor and not ship.combat.has_target() and ship.preferred_velocity.x < 0.0, "An outer-boundary crossing breaks off pursuit and returns toward the anchor.")
	var projectiles := ProjectileController.new()
	_fixture.add_child(projectiles)
	var perception := CombatPerception.new()
	perception.rebuild(vessels)
	ship.mounted_slots[1].step(1.0, ship, perception, projectiles)
	_check(projectiles.fired_count == 1, "Regrouping ships can still fire at nearby opponents outside the pursuit area.")
	projectiles.clear()
	projectiles.free()
	ship.position.x = 2200.0
	ship.combat.prepare(1.0, ship, vessels, _fleet)
	_check(ship.combat.returning_to_anchor, "Regrouping persists through the boundary band instead of oscillating.")
	ship.position.x = 1700.0
	nearby.position.x = 2100.0
	ship.combat.prepare(1.0, ship, vessels, _fleet)
	_check(not ship.combat.returning_to_anchor and ship.combat.has_target(), "Returning inside the inner radius resumes combat.")
	ship.free()
	nearby.free()
	distant.free()
	# Recover from an existing displaced battle, including altitude and a moving anchor.
	for faction in [Factions.PLAYER, Factions.ENEMY]:
		for displacement in [Vector3(3400, 0, 0), Vector3(0, 3000, 0)]:
			ship = _ship(KESTREL, faction)
			ship.position = displacement
			var recovery_speed := ship.climb_speed if displacement.y > 0.0 else ship.maximum_speed
			ship.linear_velocity = displacement.normalized() * recovery_speed * (2.0 / 3.0)
			ship.rotation.y = -PI * 0.5
			_fleet.velocity = Vector3.FORWARD * ship.maximum_speed * 0.5
			var resumed := false
			var peak_distance: float = displacement.length()
			var anchor_distance: float = 0.0
			var recovery_seconds := ceili((displacement.length() - _fleet.combat_radii.x) / recovery_speed + 60.0)
			for tick in range(recovery_seconds * _rate):
				await physics_frame
				_fleet.anchor.position += _fleet.velocity * _delta
				ship.combat.prepare(_delta, ship, [ship], _fleet)
				if not ship.combat.returning_to_anchor:
					resumed = true
					break
				ShipFlight.apply_forces(ship, ship.preferred_velocity, _delta)
				anchor_distance = ship.global_position.distance_to(_fleet.anchor.global_position)
				peak_distance = maxf(peak_distance, anchor_distance)
				if tick == 2 * _rate:
					ship.combat.prepare(0.0, ship, [ship], _fleet)
					var course := ship.preferred_velocity
					ship.global_position.z += 10240.0
					_fleet.anchor.global_position.z += 10240.0
					ship.reset_physics_interpolation()
					ship.combat.prepare(0.0, ship, [ship], _fleet)
					_check(ship.preferred_velocity.distance_to(course) < 0.01, "Regrouping remains relative to the anchor across an origin shift.")
			_check(resumed and anchor_distance <= 1810.0 and peak_distance < 3800.0, "Both factions recover from horizontal and vertical displacement with momentum and a moving anchor.")
			ship.free()
			_fleet.anchor.position = Vector3.ZERO
			_fleet.velocity = Vector3.ZERO
			_fixture.position = Vector3.ZERO


func _check_pass() -> void:
	var ship := _ship(KESTREL)
	var target := _ship(KESTREL, Factions.ENEMY)
	ship.entity_id = 1
	target.entity_id = 2
	target.freeze = true
	ship.global_position = Vector3(0, 0, 1500)
	target.global_position = Vector3.ZERO
	ship.preferred_combat_positions = PackedStringArray(["right"])
	if _visual:
		_setup_view()
	var vessels: Array[Airship] = [ship, target]
	var had_approach := false
	var had_pass := false
	var armed_ticks: int = 0
	var aligned_ticks: int = 0
	var moving_ticks: int = 0
	var nearest: float = INF
	var encounter_seconds := ceili(1500.0 / ship.maximum_speed + 30.0)
	for tick in range(encounter_seconds * _rate):
		await physics_frame
		ship.combat_engaged = ship.combat.prepare(_delta, ship, vessels, _fleet)
		ship.apply_movement_forces(_delta, Vector3.ZERO, [])
		had_approach = had_approach or not ship.combat.passing
		had_pass = had_pass or ship.combat.passing
		nearest = minf(nearest, ship.global_position.distance_to(target.global_position))
		if ship.linear_velocity.length() > ship.maximum_speed / 6.0:
			moving_ticks += 1
			if (ship.global_basis * ShipFlight.primary_axis(ship)).dot(ship.linear_velocity.normalized()) > cos(deg_to_rad(25.0)):
				aligned_ticks += 1
		if tick % int(0.2 * _rate) == 0:
			var weapon := ship.mounted_slots[1].equipment as MountedWeapon
			armed_ticks += int(weapon.launch_for(target) != Vector3.ZERO)
			if _visual:
				_paths.append({"position": ship.global_position - target.global_position, "forward": -ship.global_basis.z})
		if tick == roundi((50.0 / 3.0) * _rate):
			var before := target.position - ship.position
			var course := ship.preferred_velocity
			var yaw_rate := ship.angular_velocity.y
			ship.global_position.z += 10240.0
			target.global_position.z += 10240.0
			_fleet.anchor.global_position.z += 10240.0
			ship.reset_physics_interpolation()
			target.reset_physics_interpolation()
			_check((target.global_position - ship.global_position).distance_to(before) < 0.01 and ship.preferred_velocity == course and ship.angular_velocity.y == yaw_rate, "Rebasing preserves the pass course, relative target, and angular momentum.")
	_check(had_approach and had_pass and nearest < 900.0, "A bow-first approach transitions into a firing pass.")
	_check(armed_ticks > 20, "Broadside passes expose a working cannon to the target for repeated firing opportunities.")
	_check(aligned_ticks > moving_ticks * 0.85, "Combat spends most moving time aligned with the primary propulsion axis.")
	print("FLIGHT_PASS ", JSON.stringify({"nearest": nearest, "firing_samples": armed_ticks, "aligned_fraction": float(aligned_ticks) / maxi(1, moving_ticks)}))
	if _visual:
		await _capture_path()
	ship.queue_free()
	target.queue_free()
	await process_frame


func _check_contacts() -> void:
	# No steering/avoidance forces in this fixture: contact response comes from Jolt.
	for other_mass in [10.0, 30.0]:
		var first := _ship()
		var second := _ship()
		first.position = Vector3(-100, 0, 10.0)
		second.position = Vector3.ZERO
		second.mass = other_mass
		await physics_frame
		await physics_frame
		first.apply_central_impulse(Vector3.RIGHT * first.mass * 80.0)
		var peak_spin: float = 0.0
		for tick in range(3 * _rate):
			await physics_frame
			peak_spin = maxf(peak_spin, absf(first.angular_velocity.y) + absf(second.angular_velocity.y))
		_check(second.linear_velocity.x > 10.0 and first.linear_velocity.x < 70.0, "A ship contact transfers momentum into the other rigid body.")
		var momentum := first.linear_velocity * first.mass + second.linear_velocity * second.mass
		_check(momentum.distance_to(Vector3.RIGHT * 800.0) < 1.0, "Contacts preserve combined momentum for equal and unequal masses.")
		_check(peak_spin > 0.01 and absf(first.rotation.x) < 0.001 and absf(first.rotation.z) < 0.001, "Off-center contacts induce yaw while hulls remain upright.")
		_check(first.current_health == first.maximum_health and second.current_health == second.maximum_health, "Ship contacts do not introduce collision damage.")
		first.free()
		second.free()
	# Origin changes must update live physics bodies, not just their rendered nodes.
	var ship := _ship()
	var origin := FloatingOrigin.new()
	_fixture.add_child(origin)
	origin.register_root(ship)
	await physics_frame
	await physics_frame
	ship.linear_velocity = Vector3(30, 10, -40)
	ship.angular_velocity = Vector3(0, 0.1, 0)
	await physics_frame
	var before := ship.global_position
	var velocity := ship.linear_velocity
	var spin := ship.angular_velocity
	origin.shift_segments(-1)
	_check(ship.linear_velocity == velocity and ship.angular_velocity == spin, "Origin shifts preserve rigid-body linear and angular momentum.")
	await physics_frame
	await physics_frame
	_check(ship.global_position.distance_to(before + Vector3(0, 0, 10240) + velocity * (2.0 * _delta)) < 2.0, "The next physics updates retain the rebased transform without snapping back.")
	ship.free()
	origin.free()


func _check_impulse_recovery() -> void:
	var ship := _ship()
	await physics_frame
	await physics_frame
	ship.apply_central_impulse((Vector3.FORWARD * 300.0 + Vector3.RIGHT * 100.0 + Vector3.UP * 50.0) * ship.mass)
	ship.apply_torque_impulse(Vector3.UP / ship.get_inverse_inertia_tensor().y.y)
	await physics_frame
	var velocity := ship.linear_velocity
	var spin := ship.angular_velocity
	ShipFlight.apply_forces(ship, Vector3.FORWARD * 120.0, _delta)
	_check(ship.linear_velocity == velocity and ship.angular_velocity == spin, "Control submits forces without overwriting external linear or angular momentum.")
	await physics_frame
	_check(ship.linear_velocity.length() > ship.maximum_speed and ship.angular_velocity.y > deg_to_rad(ship.yaw_speed_degrees), "External impulses recover gradually instead of being hard-clamped to propulsion limits.")
	for tick in range(15 * _rate):
		ShipFlight.apply_forces(ship, Vector3.FORWARD * 120.0, _delta)
		await physics_frame
	# Settled yaw can oscillate within one tick of the bounded angular acceleration.
	var settled_spin := deg_to_rad(ship.yaw_acceleration_degrees) * _delta
	_check(ship.linear_velocity.distance_to(Vector3.FORWARD * 120.0) < 1.0 and absf(ship.rotation.y) < deg_to_rad(0.1) and absf(ship.angular_velocity.y) < settled_spin, "The controller recovers a stable course after a large impulse and spin.")
	for tick in range(10 * _rate):
		ShipFlight.apply_forces(ship, Vector3(0, 1000, -1000), _delta)
		await physics_frame
	_check(absf(ship.linear_velocity.length() - ship.maximum_speed) < 0.1 and absf(ship.linear_velocity.y - ship.climb_speed) < 0.1, "Unobstructed sustained propulsion respects the combined speed and lift limits.")
	ship.maximum_speed = 10.0
	for tick in range(10 * _rate):
		ShipFlight.apply_forces(ship, Vector3(0, 1000, -1000), _delta)
		await physics_frame
	_check(ship.linear_velocity.distance_to(Vector3.UP * 10.0) < 0.1, "Lift demand also respects a maximum speed authored below the climb speed.")
	ship.free()


func _check_death() -> void:
	var ship := _ship(KESTREL)
	# An ordinary body is the independent reference for gravity and native damping.
	var passive := RigidBody3D.new()
	passive.mass = ship.mass
	passive.gravity_scale = 0.2
	passive.add_child(ship.hull_collider.duplicate())
	_fixture.add_child(passive)
	passive.position = Vector3.RIGHT * 5000.0
	await physics_frame
	await physics_frame
	var momentum := Vector3(50, 0, -100)
	var spin := Vector3(0, 0.5, 0)
	ship.linear_velocity = momentum
	ship.angular_velocity = spin
	passive.linear_velocity = momentum
	passive.angular_velocity = spin
	ship.take_damage(ship.maximum_health - 5, Factions.ENEMY)
	_check(ship.alive and ship.gravity_scale == 0.0, "Nonlethal damage retains powered flight.")
	_check(ship.death_smoke == null, "Living ships do not create death smoke after nonlethal damage.")
	ship.take_damage(5, Factions.ENEMY)
	_check(is_equal_approx(ship.gravity_scale, 0.2), "Wrecks default to one fifth of project gravity without changing global gravity.")
	_check(is_instance_valid(ship.death_smoke) and ship.death_smoke.is_emitting(), "Lethal damage creates the ship-owned smoke effect at its markers.")
	_check(ship.linear_velocity == momentum and ship.angular_velocity == spin, "Death preserves existing linear and angular momentum.")
	var start := ship.position
	var passive_start := passive.position
	for tick in range(_rate):
		# Exercise both control entry points with demands that would change every axis.
		ship.set_preferred_velocity(Vector3(180, 20, 0))
		ship.apply_movement_forces(_delta, Vector3.RIGHT * 100, [])
		ShipFlight.apply_forces(ship, Vector3(180, 20, 0), _delta)
		await physics_frame
	_check(ship.linear_velocity.distance_to(passive.linear_velocity) < 0.001 and ship.angular_velocity.distance_to(passive.angular_velocity) < 0.001, "Dead ships ignore flight control, matching native damping and reduced gravity on an ordinary rigid body.")
	var fallen := start.y - ship.position.y
	_check((ship.position - start).distance_to(passive.position - passive_start) < 0.02 and fallen > 5.0 and fallen < 15.0, "A wreck follows the slower passive falling trajectory (about ten meters in its first second).")
	_check(ship.linear_velocity.x > 0.0 and ship.linear_velocity.x < momentum.x and ship.angular_velocity.y > 0.0 and ship.angular_velocity.y < spin.y, "Native damping gradually reduces retained horizontal momentum and spin.")
	ship.apply_torque_impulse(Vector3(1000, 0, 1000))
	passive.apply_torque_impulse(Vector3(1000, 0, 1000))
	await physics_frame
	await physics_frame
	_check(ship.angular_velocity.distance_to(passive.angular_velocity) < 0.001 and absf(ship.angular_velocity.x) > 0.01 and absf(ship.angular_velocity.z) > 0.01, "A wreck can tumble under physical impulses without upright control locks.")
	ship.free()
	passive.free()


func _setup_view() -> void:
	var camera := Camera3D.new()
	_fleet.anchor.add_child(camera)
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 2200.0
	camera.near = 0.5
	camera.far = 40000.0
	camera.position = Vector3(1000, 2200, 1800)
	camera.look_at(_fleet.anchor.global_position + Vector3(0, 0, 500))
	camera.current = true
	var light := DirectionalLight3D.new()
	_fixture.add_child(light)
	light.rotation_degrees = Vector3(-55, -25, 0)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color(0.04, 0.07, 0.12)
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color.WHITE
	environment.environment.ambient_light_energy = 0.5
	_fixture.add_child(environment)
	var caption := Label.new()
	caption.position = Vector2(20, 20)
	caption.text = "Forward flight / broadside pass\nGreen: travel path   Orange: bow direction   Red ship: stationary target"
	root.add_child(caption)


func _capture_path() -> void:
	var geometry := MeshInstance3D.new()
	var lines := ImmediateMesh.new()
	geometry.mesh = lines
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.vertex_color_use_as_albedo = true
	geometry.material_override = material
	_fleet.anchor.add_child(geometry)
	lines.surface_begin(Mesh.PRIMITIVE_LINES)
	for index in range(1, _paths.size()):
		lines.surface_set_color(Color(0.15, 0.9, 0.5))
		lines.surface_add_vertex(_paths[index - 1].position)
		lines.surface_add_vertex(_paths[index].position)
		if index % 5 == 0:
			lines.surface_set_color(Color(1.0, 0.6, 0.15))
			lines.surface_add_vertex(_paths[index].position)
			lines.surface_add_vertex(_paths[index].position + _paths[index].forward * 50.0)
	lines.surface_end()
	await RenderingServer.frame_post_draw
	var directory := OS.get_environment("AERWYTH_CAPTURE_DIR")
	_check(not directory.is_empty(), "Flight captures require an external directory.")
	if not directory.is_empty():
		_check(root.get_texture().get_image().save_png(directory.path_join("flight-pass.png")) == OK, "Flight trajectory capture is written.")


func _check(condition: bool, message: String) -> void:
	if not condition and message not in _failures:
		_failures.append(message)
