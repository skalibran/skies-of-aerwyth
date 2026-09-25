extends SceneTree

const SHIP := preload("res://scenes/ships/ship.tscn")
const KESTREL := preload("res://scenes/ships/kestrel.tscn")

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
	var endings: Array[Vector3] = []
	for rate in [30, 60, 120]:
		endings.append(_check_turn(rate))
	_check(endings[0].distance_to(endings[2]) < 1.0 and endings[1].distance_to(endings[2]) < 0.5, "Turning trajectories stay close across 30/60/120 Hz integration.")
	_check_braking_and_axis()
	_check_cohesion()
	await _check_pass()
	_fixture.queue_free()
	await process_frame
	for failure in _failures:
		printerr("FAIL: ", failure)
	if _failures.is_empty():
		print("PASS: forward thrust, momentum, angular acceleration, braking, authored axes, and broadside passes.")
	quit(0 if _failures.is_empty() else 1)


func _ship(scene: PackedScene = SHIP, faction: StringName = Factions.PLAYER) -> Airship:
	var ship := scene.instantiate() as Airship
	ship.faction = faction
	_fixture.add_child(ship)
	return ship


func _check_turn(rate: int) -> Vector3:
	var ship := _ship()
	ship.velocity = Vector3.FORWARD * 12.0
	var delta := 1.0 / rate
	var original := ship.velocity
	ship.velocity = ship.flight.integrate(ship, Vector3.RIGHT * 12.0, delta)
	_check(ship.velocity.distance_to(original) < 0.3 and absf(ship.rotation.y) < deg_to_rad(0.1), "A new course cannot instantly rotate heading or velocity.")
	_check(absf(ship.flight.yaw_velocity) <= deg_to_rad(ship.yaw_acceleration_degrees) * delta + 0.00001, "Turn rate builds within angular acceleration.")
	for tick in range(rate * 12):
		ship.velocity = ship.flight.integrate(ship, Vector3.RIGHT * 12.0, delta)
		ship.position += ship.velocity * delta
		_check(absf(ship.flight.yaw_velocity) <= deg_to_rad(ship.yaw_speed_degrees) + 0.00001, "Turn rate stays bounded.")
		if tick == rate:
			var forward := ship.global_basis * ship.flight.primary_axis(ship)
			_check(ship.velocity.z < -4.0 and forward.angle_to(ship.velocity.normalized()) > deg_to_rad(3.0), "The hull turns while existing forward momentum carries it along the old course.")
	_check(ship.velocity.distance_to(Vector3.RIGHT * 12.0) < 0.1, "A sustained course settles into forward flight without permanent sideways drift.")
	var end := ship.position
	ship.free()
	return end


func _check_braking_and_axis() -> void:
	var ship := _ship()
	ship.velocity = Vector3.FORWARD * 12.0
	ship.velocity = ship.flight.integrate(ship, Vector3.ZERO, 1.0 / 60.0)
	_check(ship.velocity.length() > 11.0, "Braking retains momentum on the first tick.")
	for tick in range(240):
		ship.velocity = ship.flight.integrate(ship, Vector3.ZERO, 1.0 / 60.0)
	_check(ship.velocity.length() < 0.01, "An idle ship eventually brakes to rest.")
	ship.primary_movement_direction = Vector3.RIGHT
	for tick in range(600):
		ship.velocity = ship.flight.integrate(ship, Vector3.FORWARD * 10.0 + Vector3.UP * 20.0, 1.0 / 60.0)
	var horizontal := Vector3(ship.velocity.x, 0.0, ship.velocity.z)
	_check((ship.global_basis * Vector3.RIGHT).dot(horizontal.normalized()) > 0.99, "A ship can author a different primary propulsion axis.")
	_check(is_equal_approx(ship.velocity.y, ship.climb_speed), "Lift control respects the climb speed independently of yaw.")
	var velocity := ship.velocity
	var rotation := ship.rotation
	ship.velocity = ship.flight.integrate(ship, Vector3.BACK * 18.0, 0.0)
	_check(ship.velocity == velocity and ship.rotation == rotation, "A zero-duration step changes neither attitude nor momentum.")
	ship.free()


func _check_cohesion() -> void:
	var ship := _ship(KESTREL)
	var nearby := _ship(KESTREL, Factions.ENEMY)
	var distant := _ship(KESTREL, Factions.ENEMY)
	var vessels: Array[Airship] = [ship, nearby, distant]
	ship.position = Vector3(250, 0, 0)
	nearby.position = Vector3(210, 0, 0)
	distant.position = Vector3(280, 0, 0)
	ship.combat.prepare(1.0, ship, vessels, _fleet)
	_check(ship.combat.target == nearby, "Target selection ignores a closer opponent outside the engagement area.")
	_check(ship.combat.passing and ship.combat._pass_direction.x < -0.1 and ship.preferred_velocity.x < 0.0, "Near the boundary, an eligible broadside pass favors an inward course.")
	nearby.position.x = 310.0
	ship.position.x = 270.0
	ship.combat.prepare(1.0, ship, vessels, _fleet)
	_check(ship.combat.returning_to_anchor and not ship.combat.has_target() and ship.preferred_velocity.x < 0.0, "An outer-boundary crossing breaks off pursuit and returns toward the anchor.")
	var projectiles := ProjectileController.new()
	_fixture.add_child(projectiles)
	ship.mounted_slots[1].step(1.0, ship, vessels, projectiles)
	_check(projectiles.fired_count == 1, "Regrouping ships can still fire at nearby opponents outside the pursuit area.")
	projectiles.clear()
	projectiles.free()
	ship.position.x = 220.0
	ship.combat.prepare(1.0, ship, vessels, _fleet)
	_check(ship.combat.returning_to_anchor, "Regrouping persists through the boundary band instead of oscillating.")
	ship.position.x = 170.0
	nearby.position.x = 210.0
	ship.combat.prepare(1.0, ship, vessels, _fleet)
	_check(not ship.combat.returning_to_anchor and ship.combat.has_target(), "Returning inside the inner radius resumes combat.")
	ship.free()
	nearby.free()
	distant.free()
	# Recover from an existing displaced battle, including altitude and a moving anchor.
	for faction in [Factions.PLAYER, Factions.ENEMY]:
		for displacement in [Vector3(340, 0, 0), Vector3(0, 300, 0)]:
			ship = _ship(KESTREL, faction)
			ship.position = displacement
			ship.velocity = displacement.normalized() * 12.0
			ship.rotation.y = -PI * 0.5
			_fleet.velocity = Vector3.FORWARD * 4.0
			var resumed := false
			var peak_distance: float = displacement.length()
			var anchor_distance: float = 0.0
			for tick in range(4800):
				_fleet.anchor.position += _fleet.velocity / 60.0
				ship.combat.prepare(1.0 / 60.0, ship, [ship], _fleet)
				if not ship.combat.returning_to_anchor:
					resumed = true
					break
				ship.velocity = ship.flight.integrate(ship, ship.preferred_velocity, 1.0 / 60.0)
				ship.position += ship.velocity / 60.0
				anchor_distance = ship.global_position.distance_to(_fleet.anchor.global_position)
				peak_distance = maxf(peak_distance, anchor_distance)
				if tick == 120:
					ship.combat.prepare(0.0, ship, [ship], _fleet)
					var course := ship.preferred_velocity
					_fixture.position.z += 1024.0
					ship.combat.prepare(0.0, ship, [ship], _fleet)
					_check(ship.preferred_velocity.distance_to(course) < 0.001, "Regrouping remains relative to the anchor across an origin shift.")
			_check(resumed and anchor_distance <= 181.0 and peak_distance < 380.0, "Both factions recover from horizontal and vertical displacement with momentum and a moving anchor.")
			ship.free()
			_fleet.anchor.position = Vector3.ZERO
			_fleet.velocity = Vector3.ZERO
			_fixture.position = Vector3.ZERO


func _check_pass() -> void:
	var ship := _ship(KESTREL)
	var target := _ship(KESTREL, Factions.ENEMY)
	ship.entity_id = 1
	target.entity_id = 2
	ship.global_position = Vector3(0, 0, 150)
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
	for tick in range(2400):
		await physics_frame
		ship.combat_engaged = ship.combat.prepare(1.0 / 60.0, ship, vessels, _fleet)
		ship.move_ship(1.0 / 60.0, Vector3.ZERO, [])
		had_approach = had_approach or not ship.combat.passing
		had_pass = had_pass or ship.combat.passing
		nearest = minf(nearest, ship.global_position.distance_to(target.global_position))
		if ship.velocity.length() > 3.0:
			moving_ticks += 1
			if (ship.global_basis * ship.flight.primary_axis(ship)).dot(ship.velocity.normalized()) > cos(deg_to_rad(25.0)):
				aligned_ticks += 1
		if tick % 12 == 0:
			var weapon := ship.mounted_slots[1].equipment as MountedWeapon
			armed_ticks += int(weapon.launch_for(target) != Vector3.ZERO)
			if _visual:
				_paths.append({"position": ship.position, "forward": -ship.basis.z})
		if tick == 1000:
			var before := target.position - ship.position
			var course := ship.preferred_velocity
			var yaw_rate := ship.flight.yaw_velocity
			_fixture.position.z += 1024.0
			_check((target.global_position - ship.global_position).distance_to(before) < 0.001 and ship.preferred_velocity == course and ship.flight.yaw_velocity == yaw_rate, "Rebasing preserves the pass course, relative target, and angular momentum.")
	_check(had_approach and had_pass and nearest < 90.0, "A bow-first approach transitions into a firing pass.")
	_check(armed_ticks > 20, "Broadside passes expose a working cannon to the target for repeated firing opportunities.")
	_check(aligned_ticks > moving_ticks * 0.85, "Combat spends most moving time aligned with the primary propulsion axis.")
	print("FLIGHT_PASS ", JSON.stringify({"nearest": nearest, "firing_samples": armed_ticks, "aligned_fraction": float(aligned_ticks) / maxi(1, moving_ticks)}))
	if _visual:
		await _capture_path()
	ship.queue_free()
	target.queue_free()
	await process_frame


func _setup_view() -> void:
	var camera := Camera3D.new()
	_fixture.add_child(camera)
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 220.0
	camera.position = Vector3(100, 220, 180)
	camera.look_at(Vector3(0, 0, 50))
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
	_fixture.add_child(geometry)
	lines.surface_begin(Mesh.PRIMITIVE_LINES)
	for index in range(1, _paths.size()):
		lines.surface_set_color(Color(0.15, 0.9, 0.5))
		lines.surface_add_vertex(_paths[index - 1].position)
		lines.surface_add_vertex(_paths[index].position)
		if index % 5 == 0:
			lines.surface_set_color(Color(1.0, 0.6, 0.15))
			lines.surface_add_vertex(_paths[index].position)
			lines.surface_add_vertex(_paths[index].position + _paths[index].forward * 5.0)
	lines.surface_end()
	await RenderingServer.frame_post_draw
	var directory := OS.get_environment("AERWYTH_CAPTURE_DIR")
	_check(not directory.is_empty(), "Flight captures require an external directory.")
	if not directory.is_empty():
		_check(root.get_texture().get_image().save_png(directory.path_join("flight-pass.png")) == OK, "Flight trajectory capture is written.")


func _check(condition: bool, message: String) -> void:
	if not condition and message not in _failures:
		_failures.append(message)
