extends SceneTree

const SHIP := preload("res://scenes/ships/ship.tscn")
const KESTREL := preload("res://scenes/ships/kestrel.tscn")
const MANTA := preload("res://scenes/ships/manta.tscn")

var _rate: int = Engine.physics_ticks_per_second
var _delta: float = 1.0 / _rate
var _failures: Array[String] = []
var _fixture: Node3D
var _fleet: FleetController


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_fixture = Node3D.new()
	root.add_child(_fixture)
	_fleet = FleetController.new()
	# Fixed-limit flight fixtures isolate authored tuning from outside-sphere assistance.
	_fleet.arrival_max_multiplier = 1.0
	_fleet.marker = Node3D.new()
	_fixture.add_child(_fleet)
	_fixture.add_child(_fleet.marker)
	await _check_turn()
	await _check_braking_and_axis()
	_check_attack_positions()
	_check_moving_navigation_heading()
	await _check_fleet_spread()
	await _check_arrival_boost()
	await _check_navigation()
	await _check_vertical_pursuit()
	await _check_contacts()
	await _check_impulse_recovery()
	await _check_death()
	_fixture.queue_free()
	await process_frame
	for failure in _failures:
		printerr("FAIL: ", failure)
	if _failures.is_empty():
		print("PASS: forward thrust, braking, authored axes, fleet spread, physical contacts, impulse recovery, passive wreck physics, rebasing, and bounded priority-target navigation.")
	quit(0 if _failures.is_empty() else 1)


func _ship(scene: PackedScene = SHIP, faction: StringName = Factions.PLAYER) -> Airship:
	var ship := scene.instantiate() as Airship
	ship.faction = faction
	_fixture.add_child(ship)
	_fleet.register_ship(ship)
	ship.navigation.initialize(_fleet, ship)
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


func _check_attack_positions() -> void:
	var ship := _ship(KESTREL)
	var target := _ship(KESTREL, Factions.ENEMY)
	ship.freeze = true
	target.freeze = true
	target.position = Vector3.RIGHT * 400.0
	_fleet.radius = 1000.0
	ship.preferred_combat_positions = PackedStringArray(["right"])
	ship.prepare_navigation(_delta, [ship, target], _fleet)
	ship.navigation.plan(ship, [])
	_check(ship.combat.target == target and ship.navigation.attack_position == "right", "A target beyond weapon range is approached from its authored side.")
	_check(is_equal_approx(ship.navigation.attack_offset.length(), 150.0), "Attack spacing defaults to the authored 150 meters.")
	var offset := ship.navigation.attack_offset
	for slot in ship.mounted_slots:
		slot.rotation.y += PI
		var weapon := slot.equipment as MountedWeapon
		weapon.definition = weapon.weapon.duplicate()
		weapon.weapon.range_units = 50.0
	ship.rotation.y = PI * 0.5
	target.rotation.y = -PI * 0.5
	ship.prepare_navigation(3.1, [ship, target], _fleet)
	ship.navigation.plan(ship, [])
	_check(ship.navigation.attack_offset == offset, "Hull yaw, target yaw, gun cones, and gun range cannot redirect an available attack position.")
	var goal := ship.navigation.goal_offset
	target.position += Vector3(10, 15, 20)
	ship.prepare_navigation(_delta, [ship, target], _fleet)
	_check(ship.navigation.goal_offset.is_equal_approx(goal + Vector3(10, 15, 20)), "An attack waypoint follows target translation.")
	goal = ship.navigation.goal_offset
	ship.position.z += 10240.0
	target.position.z += 10240.0
	_fleet.marker.position.z += 10240.0
	ship.prepare_navigation(0.0, [ship, target], _fleet)
	_check(ship.navigation.goal_offset.distance_to(goal) < 0.01 and ship.navigation.attack_offset == offset, "Rebasing preserves the retained target-relative attack position.")
	ship.position = Vector3.ZERO
	_fleet.marker.position = Vector3.ZERO
	ship.rotation = Vector3.ZERO
	target.position = Vector3.ZERO
	# The nominal distance lies outside this sphere, but the closer alternative fits.
	_fleet.radius = ship.hull_radius + ship.hull_half_segment + ShipNavigation.HULL_CLEARANCE + 140.0
	ship.position.x = -100.0
	ship.navigation.attack_position = ""
	ship.prepare_navigation(3.1, [ship, target], _fleet)
	ship.navigation.plan(ship, [])
	_check(ship.navigation.attack_position == "right" and is_equal_approx(ship.navigation.attack_offset.length(), 120.0), "Distance yields within its tolerance while the authored side remains mandatory.")
	_fleet.radius = 230.0
	ship.position = Vector3.ZERO
	target.position = Vector3(150, 0, 0)
	ship.preferred_combat_positions = PackedStringArray(["left", "right"])
	ship.prepare_navigation(3.1, [ship, target], _fleet)
	ship.navigation.plan(ship, [])
	_check(ship.navigation.attack_position == "right", "An out-of-sphere broadside option does not block the opposite broadside.")
	target.position.x = -150.0
	ship.prepare_navigation(_delta, [ship, target], _fleet)
	ship.navigation.plan(ship, [])
	_check(ship.navigation.attack_position == "left", "A retained position becoming invalid immediately tries the other enabled side.")
	# Scenery can invalidate an endpoint independently of sphere containment.
	var island := preload("res://scenes/islands/island.tscn").instantiate() as FloatingIsland
	_fixture.add_child(island)
	island.navigation_radius = 30.0
	island.bottom_offset = -100.0
	island.top_offset = 100.0
	island.position = Vector3(150, 0, 0)
	_fleet.radius = 500.0
	target.position = Vector3.ZERO
	ship.position = Vector3(0, 0, 150)
	ship.prepare_navigation(3.1, [ship, target], _fleet)
	ship.navigation.plan(ship, [island])
	_check(ship.navigation.attack_position == "right", "An island covering one broadside's attack points selects the other side.")
	island.free()
	# No allowed endpoint fits. Keep the enemy, wander, and allow pass-by firing.
	_fleet.radius = 230.0
	ship.position = Vector3.ZERO
	target.position = Vector3(-150, 0, 0)
	ship.preferred_combat_positions = PackedStringArray(["right"])
	ship.prepare_navigation(3.1, [ship, target], _fleet)
	ship.navigation.plan(ship, [])
	_check(ship.navigation.attack_position.is_empty() and not ship.navigation.blocked and ship.navigation.goal_offset.length() > 1.0, "Exhausting attack options chooses an ordinary bounded navigation coordinate.")
	_check(ship.combat.target == target, "Wandering retains the selected enemy for firing and later attack retries.")
	var passer := _ship(KESTREL, Factions.ENEMY)
	passer.freeze = true
	passer.position = Vector3(100, 0, 0)
	for slot in ship.mounted_slots:
		slot.rotation.y -= PI
		var weapon := slot.equipment as MountedWeapon
		weapon.weapon.range_units = 200.0
		weapon.shot_smoke_scene = null
		weapon._search_time = 0.0
	var perception := CombatPerception.new()
	perception.rebuild([ship, target, passer])
	var projectiles := ProjectileController.new()
	_fixture.add_child(projectiles)
	var right := ship.mounted_slots[1].equipment as MountedWeapon
	right.step(_delta, ship, perception, projectiles)
	_check(right.shots_fired == 1 and right.firing_target == passer and ship.combat.target == target, "A wandering ship fires at a reachable passer without changing its selected enemy.")
	projectiles.free()
	passer.free()
	target.position.x = 150.0
	ship.prepare_navigation(3.1, [ship, target], _fleet)
	ship.navigation.plan(ship, [])
	_check(ship.navigation.attack_position == "right", "A waiting ship retries and resumes attack when an allowed position becomes available.")
	for slot in ship.mounted_slots:
		slot.assign_equipment(null)
	ship.prepare_navigation(_delta, [ship, target], _fleet)
	ship.navigation.plan(ship, [])
	_check(not ship.combat_engaged and not ship.combat.has_target() and ship.navigation.attack_position.is_empty(), "Removing all weapons resumes ordinary travel.")
	ship.free()
	target.free()
	_fleet.initialize()


func _check_moving_navigation_heading() -> void:
	var ship := _ship(preload("res://scenes/ships/swift.tscn"))
	var target := _ship(KESTREL, Factions.ENEMY)
	ship.engagement_distance = 120.0
	target.position.z = -120.0
	_fleet.radius = 400.0
	_fleet.velocity = Vector3.FORWARD * 25.0
	ship.prepare_navigation(_delta, [ship, target], _fleet)
	ship.navigation.goal_offset = Vector3.BACK * 20.0
	ship.navigation._goal_age = 0.0
	# A destination behind the ship slows forward travel. It cannot reverse it.
	var request := ship.navigation.steer(ship, Vector3.ZERO, [])
	_check(request.is_equal_approx(Vector3.FORWARD * 13.0), "A rearward local goal retains the moving marker's forward translation.")
	_check(is_zero_approx(ShipFlight._yaw_acceleration(ship, request, _delta)), "Flight holds its forward heading for that rearward local goal.")
	_fleet.velocity = Vector3.ZERO
	request = ship.navigation.steer(ship, Vector3.ZERO, [])
	_check(request.z > 0.0, "A stationary marker allows the same rearward waypoint to request backward travel.")
	ship.free()
	target.free()
	_fleet.initialize()


func _check_fleet_spread() -> void:
	# A dispersed fleet at cruise must not collapse into a forward wall even
	# without combat, scenery, or spawning to influence its destinations.
	var ships: Array[Airship] = []
	for x in range(4):
		for y in range(3):
			for z in range(4):
				var ship := KESTREL.instantiate() as Airship
				ship.entity_id = ships.size() + 1
				ship.position = Vector3((x - 1.5) * 80.0, (y - 1.0) * 80.0, (z - 1.5) * 80.0)
				_fixture.add_child(ship)
				_fleet.register_ship(ship)
				ships.append(ship)
	_fleet.initialize()
	_fleet.speed = _fleet.cruise_speed
	_fleet.velocity = Vector3.FORWARD * _fleet.speed
	for ship in ships:
		ship.navigation.initialize(_fleet, ship)
		ship.linear_velocity = _fleet.velocity
	var avoidance := ShipAvoidance.new()
	var positions := PackedVector3Array()
	var velocities := PackedVector3Array()
	var axes := PackedVector3Array()
	var corrections := PackedVector3Array()
	positions.resize(ships.size())
	velocities.resize(ships.size())
	axes.resize(ships.size())
	for tick in range(60 * _rate):
		await physics_frame
		_fleet.prepare_step(_delta)
		for index in range(ships.size()):
			var ship := ships[index]
			positions[index] = ship.global_position
			velocities[index] = ship.linear_velocity
			axes[index] = ship.global_basis.z
			ship.prepare_navigation(_delta, ships, _fleet, false)
		avoidance.calculate(ships, positions, velocities, axes, corrections)
		for ship in ships:
			ship.navigation.plan(ship, [])
		_fleet.advance(_delta)
		for index in range(ships.size()):
			ships[index].apply_movement_forces(_delta, corrections[index], [])
			_check(ships[index].navigation.goal_offset.length() <= ships[index].navigation.usable_radius(ships[index]) + 0.01, "Dispersed travel retains contained navigation goals.")
	var mean := Vector3.ZERO
	for ship in ships:
		mean += ship.global_position - _fleet.marker.global_position
	mean /= ships.size()
	var variance := Vector3.ZERO
	for ship in ships:
		var offset := ship.global_position - _fleet.marker.global_position - mean
		variance += offset * offset
	variance /= ships.size()
	var spread := Vector3(sqrt(variance.x), sqrt(variance.y), sqrt(variance.z))
	_check(mean.length() < _fleet.radius * 0.35, "Travel does not herd the fleet toward one side of the sphere.")
	_check(minf(spread.x, minf(spread.y, spread.z)) > _fleet.radius * 0.12, "A fleet retains depth on every axis instead of collapsing to a wall.")
	print("FLEET_SPREAD: radius=", _fleet.radius, ", mean=", mean, ", standard_deviation=", spread)
	for ship in ships:
		ship.free()
	_fleet.marker.position = Vector3.ZERO
	_fleet.speed = 0.0
	_fleet.velocity = Vector3.ZERO
	_fleet.initialize()


func _check_arrival_boost() -> void:
	_fleet.arrival_max_multiplier = 10.0
	var ship := _ship(KESTREL)
	ship.freeze = true
	for direction: Vector3 in [Vector3.FORWARD, Vector3.BACK, Vector3.UP, Vector3.DOWN]:
		ship.position = direction * (_fleet.radius - 1.0)
		_check(ShipFlight.speed_multiplier(ship) == 1.0, "Ships inside the sphere retain normal flight limits on every axis.")
		ship.position = direction * (_fleet.radius + 500.0)
		_check(is_equal_approx(ShipFlight.speed_multiplier(ship), 5.5), "Arrival assistance grows with 3D distance from the sphere surface.")
		ship.position = direction * (_fleet.radius + 2000.0)
		_check(ShipFlight.speed_multiplier(ship) == 10.0, "Arrival assistance remains capped for distant ships.")
	ship.position = Vector3.BACK * (_fleet.radius + 1500.0)
	ship.navigation.plan(ship, [])
	var request := ship.navigation.steer(ship, Vector3.ZERO, [])
	_check(request.z < -ship.maximum_speed, "Outside-sphere navigation can request faster approach than normal cruise.")
	var acceleration := ShipFlight._acceleration(ship, request, _delta)
	_check(acceleration.z < -ship.acceleration, "Boosted approach uses stronger propulsion instead of only raising a speed cap.")
	ship.position = Vector3.UP * (_fleet.radius + 1500.0)
	ship.navigation.plan(ship, [])
	request = ship.navigation.steer(ship, Vector3.ZERO, [])
	_check(request.y < -ship.climb_speed, "Vertical arrivals receive the same distance-based assistance.")
	var multiplier := ShipFlight.speed_multiplier(ship)
	ship.position.z += 10240.0
	_fleet.marker.position.z += 10240.0
	_check(ShipFlight.speed_multiplier(ship) == multiplier, "Origin rebasing preserves arrival assistance.")
	ship.free()
	_fleet.marker.position = Vector3.ZERO
	for faction: StringName in [Factions.PLAYER, Factions.ENEMY]:
		var ordinary := await _arrival_trial(faction, 1.0)
		var boosted := await _arrival_trial(faction, 10.0)
		_check(boosted.y <= 0.0 and ordinary.y > 500.0, "Both factions reach the sphere quickly while the ordinary-speed reference is still distant.")
		_check(boosted.z > 50.0, "Native flight exceeds normal Kestrel speed during a distant arrival.")
		print("ARRIVAL ", faction, ": boosted_seconds=", boosted.x, ", ordinary_remaining=", ordinary.y, ", peak_speed=", boosted.z)
	_fleet.arrival_max_multiplier = 1.0
	_fleet.initialize()


func _arrival_trial(faction: StringName, multiplier: float) -> Vector3:
	_fleet.arrival_max_multiplier = multiplier
	_fleet.marker.position = Vector3.ZERO
	_fleet.speed = 0.0
	_fleet.velocity = Vector3.ZERO
	var anchor := _ship(KESTREL)
	anchor.freeze = true
	var ship := _ship(KESTREL, faction)
	ship.navigation.rng.seed = 31337
	ship.position = Vector3(0.0, 1200.0, 1600.0 if faction == Factions.PLAYER else -1600.0)
	ship.rotation.y = 0.0 if faction == Factions.PLAYER else PI
	ship.reset_physics_interpolation()
	_fleet.initialize()
	var authored := Vector4(ship.maximum_speed, ship.climb_speed, ship.acceleration, ship.braking)
	var elapsed: float = 0.0
	var peak_speed: float = 0.0
	var remaining: float = INF
	for tick in range(75 * _rate):
		await physics_frame
		_fleet.prepare_step(_delta)
		ship.prepare_navigation(_delta, [anchor, ship], _fleet, false)
		ship.navigation.plan(ship, [])
		var marker_before := _fleet.marker.position
		_fleet.advance(_delta)
		_check(_fleet.marker.position.z < marker_before.z, "The marker keeps moving while ships approach from outside the sphere.")
		if elapsed > _fleet.cruise_speed / _fleet.acceleration:
			_check(_fleet.speed == _fleet.cruise_speed, "Arriving ships preserve full marker cruise after initial acceleration.")
		anchor.position = _fleet.marker.position
		ship.apply_movement_forces(_delta, Vector3.ZERO, [])
		elapsed += _delta
		peak_speed = maxf(peak_speed, ship.linear_velocity.length())
		remaining = ship.position.distance_to(_fleet.marker.position) - _fleet.radius
		_check(ship.navigation.goal_offset.length() <= ship.navigation.usable_radius(ship) + 0.01, "Boosted arrivals retain destinations inside the fleet sphere.")
		if remaining <= 0.0:
			_check(ShipFlight.speed_multiplier(ship) == 1.0, "The arrival boost expires automatically at the sphere boundary.")
			_check(ship.linear_velocity.length() <= ship.maximum_speed + 1.0, "The approach tapers back to normal flight speed before entering.")
			break
	_check(Vector4(ship.maximum_speed, ship.climb_speed, ship.acceleration, ship.braking) == authored, "Arrival assistance never mutates shared authored flight tuning.")
	ship.free()
	anchor.free()
	_fleet.marker.position = Vector3.ZERO
	_fleet.speed = 0.0
	_fleet.velocity = Vector3.ZERO
	return Vector3(elapsed, remaining, peak_speed)


func _check_navigation() -> void:
	var ship := _ship(KESTREL)
	# Keep this regression sensitive to spacing beyond a short-range loadout.
	for slot in ship.mounted_slots:
		var weapon := slot.equipment as MountedWeapon
		weapon.definition = weapon.weapon.duplicate()
		weapon.weapon.range_units = 200.0
		weapon.weapon.launch_speed = 500.0
	var priority := _ship(KESTREL, Factions.ENEMY)
	var nearby := _ship(KESTREL, Factions.ENEMY)
	priority.freeze = true
	nearby.freeze = true
	_fleet.minimum_radius = 400.0
	_fleet.initialize()
	_fleet.in_combat = true
	ship.position = Vector3(-270, 0, 0)
	priority.position = Vector3(270, 0, 0)
	nearby.position = Vector3(-240, 80, -30)
	_fleet.velocity = Vector3.FORWARD * 25.0
	ship.linear_velocity = _fleet.velocity
	ship.prepare_navigation(_delta, [ship, priority, nearby], _fleet)
	# A future priority selector can replace the target without changing navigation.
	ship.combat.target = priority
	var start_distance := ship.position.distance_to(priority.position)
	var firing_samples: int = 0
	var peak_extent: float = 0.0
	for tick in range(45 * _rate):
		await physics_frame
		_fleet.marker.position += _fleet.velocity * _delta
		priority.position += _fleet.velocity * _delta
		nearby.position += _fleet.velocity * _delta
		ship.prepare_navigation(_delta, [ship, priority, nearby], _fleet)
		ship.apply_movement_forces(_delta, Vector3.ZERO, [])
		_check(ship.combat.target == priority, "A selected distant target is retained despite a nearer opponent.")
		_check(ship.navigation.goal_offset.length() <= ship.navigation.usable_radius(ship) + 0.001, "Every combat destination remains inside the sphere.")
		peak_extent = maxf(peak_extent, ship.position.distance_to(_fleet.marker.position) / _fleet.radius)
		for slot in ship.mounted_slots:
			var weapon := slot.equipment as MountedWeapon
			if tick % 6 == 0 and weapon.launch_for(priority) != Vector3.ZERO:
				firing_samples += 1
	_check(ship.position.distance_to(priority.position) < start_distance - 120.0, "Successive nearby goals cross the sphere toward a distant priority target.")
	_check(firing_samples > 20, "Bounded maneuvers provide repeated firing opportunities against the selected target.")
	_check(peak_extent < 1.1, "Ordinary combat turns stay close to the intended sphere.")
	var old_goal := ship.navigation.goal_offset
	var old_position := ship.position
	var old_velocity := ship.linear_velocity
	ship.combat.clear_target()
	_fleet.in_combat = false
	_fleet.velocity = Vector3.FORWARD * 0.1
	ship.prepare_navigation(_delta, [ship], _fleet, false)
	ship.apply_movement_forces(_delta, Vector3.ZERO, [])
	_check(ship.navigation.goal_offset != old_goal and not ship.combat_engaged, "Combat completion selects a fresh ordinary destination immediately.")
	_check(ship.position == old_position and ship.linear_velocity == old_velocity, "The handoff never snaps a hull or overwrites momentum.")
	_fleet.velocity = Vector3.ZERO
	# Test final containment after a deliberately outward separation request.
	ship.position = _fleet.marker.position + Vector3(_fleet.radius - 25, 0, 0)
	ship.linear_velocity = Vector3.RIGHT * 40
	ship.prepare_navigation(_delta, [ship], _fleet, false)
	ship.apply_movement_forces(_delta, Vector3.RIGHT * 1000, [])
	var endpoint := ship.position + ship.navigation_velocity * ship.navigation._horizon(ship)
	_check(endpoint.distance_to(_fleet.marker.position) <= ship.navigation.usable_radius(ship) + 0.01, "Even separation cannot deliberately steer beyond the boundary.")
	ship.position.x = _fleet.radius + 80
	ship.prepare_navigation(_delta, [ship], _fleet, false)
	ship.apply_movement_forces(_delta, Vector3.RIGHT * 1000, [])
	_check(ship.navigation_velocity.x < 0.0 and ship.navigation.goal_offset.length() < _fleet.radius, "Momentum displacement requests an inward goal through the same navigator.")
	var goal := ship.navigation.goal_offset
	var request := ship.navigation_velocity
	ship.position.z += 10240
	_fleet.marker.position.z += 10240
	ship.prepare_navigation(0.0, [ship], _fleet, false)
	ship.apply_movement_forces(_delta, Vector3.RIGHT * 1000, [])
	_check(ship.navigation.goal_offset == goal and ship.navigation_velocity.distance_to(request) < 0.01, "Relative navigation survives rebasing without consuming a new goal.")
	print("NAVIGATION: priority approach=", start_distance - old_position.distance_to(priority.position), ", firing samples=", firing_samples, ", peak radius=", peak_extent)
	ship.free()
	priority.free()
	nearby.free()
	_fleet.marker.position = Vector3.ZERO
	_fleet.minimum_radius = 180.0
	_fleet.initialize()


func _check_vertical_pursuit() -> void:
	for faction in [Factions.PLAYER, Factions.ENEMY]:
		var ship := _ship(MANTA, faction)
		var opposing: StringName = Factions.ENEMY if faction == Factions.PLAYER else Factions.PLAYER
		var target := _ship(KESTREL, opposing)
		var passer := _ship(KESTREL, opposing)
		target.freeze = true
		passer.freeze = true
		ship.entity_id = 37
		ship.position = Vector3(-150, -100, 0) if faction == Factions.PLAYER else Vector3(0, -100, 0)
		var passer_offset := ship.position + Vector3.DOWN * 100.0
		passer.position = passer_offset
		_fleet.minimum_radius = 400.0
		_fleet.initialize()
		_fleet.speed = _fleet.cruise_speed
		_fleet.velocity = Vector3.FORWARD * _fleet.speed
		ship.linear_velocity = _fleet.velocity
		target.linear_velocity = _fleet.velocity
		passer.linear_velocity = _fleet.velocity
		ship.navigation.initialize(_fleet, ship)
		var ships: Array[Airship] = [ship, target, passer]
		ship.combat.target = target
		for slot in ship.mounted_slots:
			var weapon := slot.equipment as MountedWeapon
			weapon.definition = weapon.weapon.duplicate()
			weapon.weapon.range_units = 200.0
			weapon.weapon.launch_speed = 500.0
			weapon.shot_smoke_scene = null
			weapon._search_time = 0.0
		ship.prepare_navigation(_delta, ships, _fleet)
		ship.navigation.plan(ship, [])
		_check(not ship.navigation.attack_position.is_empty() and ship.navigation.attack_offset.y > 0.0, "Authored lower bearings place the attack objective above the designated target.")
		var projectiles := ProjectileController.new()
		_fixture.add_child(projectiles)
		var perception := CombatPerception.new()
		var main_shots := 0
		var pass_by_shots := 0
		for tick in range(40 * _rate):
			await physics_frame
			_fleet.prepare_step(_delta, true)
			ship.prepare_navigation(_delta, ships, _fleet)
			ship.navigation.plan(ship, [])
			_fleet.advance(_delta)
			target.position = _fleet.marker.position
			passer.position = _fleet.marker.position + passer_offset
			ship.apply_movement_forces(_delta, Vector3.ZERO, [])
			perception.rebuild(ships)
			for slot in ship.mounted_slots:
				var weapon := slot.equipment as MountedWeapon
				var previous := weapon.shots_fired
				weapon.step(_delta, ship, perception, projectiles)
				if weapon.shots_fired > previous:
					if weapon.firing_target == target:
						main_shots += 1
					elif weapon.firing_target == passer:
						pass_by_shots += 1
			# Exercise real acquisition and launches without casualties changing the fixture.
			projectiles.clear()
			_check(ship.combat.target == target, "Pass-by fire does not replace the designated pursuit target.")
			_check(ship.navigation.goal_offset.length() <= ship.navigation.usable_radius(ship) + 0.01, "Vertical pursuit keeps its destinations inside the fleet sphere.")
			if tick == 30 * _rate - 1:
				_check(ship.position.y - target.position.y > ship.engagement_distance * 0.5, "A Manta starting below its target establishes firing altitude within thirty seconds of moving combat.")
		_check(main_shots > 5 and pass_by_shots > 0, "Manta climbs to fire on its main target while retaining opportunistic shots during approach.")
		print("VERTICAL_PURSUIT: faction=", faction, ", height=", ship.position.y - target.position.y, ", main_shots=", main_shots, ", pass_by_shots=", pass_by_shots)
		# The same rule handles upper bearings, independently of mounted gun directions.
		ship.preferred_combat_positions = PackedStringArray(["front_up", "up", "back_up"])
		ship.combat.clear_target()
		ship.combat.target = target
		ship.prepare_navigation(_delta, ships, _fleet)
		ship.navigation.attack_position = ""
		ship.navigation._goal_age = INF
		ship.navigation.plan(ship, [])
		_check(not ship.navigation.attack_position.is_empty() and ship.navigation.attack_offset.y < 0.0, "Authored upper bearings place the attack objective below the target even with downward guns.")
		ship.free()
		target.free()
		passer.free()
		projectiles.free()
		_fleet.marker.position = Vector3.ZERO
		_fleet.minimum_radius = 180.0
		_fleet.speed = 0.0
		_fleet.velocity = Vector3.ZERO
		_fleet.in_combat = false
		_fleet.initialize()


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
		ship.navigation_velocity = Vector3(180, 20, 0)
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


func _check(condition: bool, message: String) -> void:
	if not condition and message not in _failures:
		_failures.append(message)
