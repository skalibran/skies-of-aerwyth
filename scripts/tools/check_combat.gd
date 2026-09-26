extends SceneTree

const KESTREL := preload("res://scenes/ships/kestrel.tscn")
const JOURNEY := preload("res://scenes/world/journey.tscn")
const CANNON := preload("res://resources/weapons/rusty_cannon.tres")
const CANNON_SCENE := preload("res://scenes/weapons/rusty_cannon.tscn")
const SLOT_SCENE := preload("res://scenes/ships/mounted_slot.tscn")

var _rate: int = Engine.physics_ticks_per_second
var _delta: float = 1.0 / _rate
var _failures: Array[String] = []
var _fixture: Node3D
var _fleet: FleetController
var _projectiles: ProjectileController
var _origin: FloatingOrigin
var _next_id: int = 5000
var _visual: bool = false
var _extended: bool = false
var _perception := CombatPerception.new()


func _initialize() -> void:
	_visual = "--visual" in OS.get_cmdline_user_args()
	_extended = _visual or "--extended" in OS.get_cmdline_user_args()
	_run.call_deferred()


func _run() -> void:
	_check_ballistics()
	_fixture = Node3D.new()
	root.add_child(_fixture)
	_fleet = FleetController.new()
	_fleet.anchor = Node3D.new()
	_fixture.add_child(_fleet)
	_fixture.add_child(_fleet.anchor)
	_projectiles = ProjectileController.new()
	_fixture.add_child(_projectiles)
	_origin = FloatingOrigin.new()
	_fixture.add_child(_origin)
	_origin.register_root(_projectiles)
	await _check_neighbor_filter()
	await _check_mounts_and_health()
	await _check_search_budget()
	await _check_equipment_assignment()
	await _check_impacts()
	_fixture.queue_free()
	await process_frame
	if _extended:
		await _check_journey()
	for failure in _failures:
		printerr("FAIL: ", failure)
	if _failures.is_empty():
		print("PASS: combat fixtures%s." % (" and journey lifecycle" if _extended else ""))
	quit(0 if _failures.is_empty() else 1)


func _check_ballistics() -> void:
	for distance in [600.0, 1000.0]:
		var relative := Vector3(distance, 0, 0)
		var time := Ballistics.intercept_time(relative, Vector3.ZERO, 200, 30, 8)
		var expected := 3.083597 if distance == 600.0 else 5.485838
		_check(absf(time - expected) < 0.0001, "Stationary low arcs have the expected flight time at %s units." % distance)
		var launch := Ballistics.launch_velocity(relative, Vector3.ZERO, 30, time)
		_check(absf(launch.length() - 200) < 0.01, "Launch speed remains 200 m/s.")
		_check(Ballistics.displacement(launch, 30, time).distance_to(relative) < 0.01, "Aiming and flight agree.")
	for relative in [Vector3(600, 200, 0), Vector3(600, -200, 0), Vector3(0, 300, 0), Vector3(0, -300, 0), Vector3(0.1, 0, 0)]:
		for movement in [Vector3.ZERO, Vector3(10, 2.0, -20)]:
			var time := Ballistics.intercept_time(relative, movement, 200, 30, 8)
			_check(time > 0.0, "Reachable elevated, vertical, close, and moving targets have solutions.")
			if time > 0.0:
				var launch := Ballistics.launch_velocity(relative, movement, 30, time)
				_check(Ballistics.displacement(launch, 30, time).distance_to(relative + movement * time) < 0.02, "Moving-target lead intercepts predicted motion.")
	_check(Ballistics.intercept_time(Vector3(600, 0, 0), Vector3(300, 0, 0), 200, 30, 8) < 0, "A faster receding target is unreachable.")
	_check(Ballistics.intercept_time(Vector3(0, 800, 0), Vector3.ZERO, 200, 30, 8) < 0, "In-range targets can exceed maximum ballistic height.")
	_check(Ballistics.intercept_time(Vector3(1000, 0, 0), Vector3.ZERO, 200, 30, 5) < 0, "A short lifetime cannot support the 1000-meter shot.")
	_check(Ballistics.intercept_time(Vector3(0, 2000.0 / 3.0, 0), Vector3.ZERO, 200, 30, 8) > 0, "A tangent root at maximum height is found.")
	_check(Ballistics.intercept_time(Vector3.ZERO, Vector3.ZERO, 200, 30, 8) < 0, "Coincident targets do not produce invalid division.")
	_check(Ballistics.intercept_time(Vector3.INF, Vector3.ZERO, 200, 30, 8) < 0, "Invalid inputs are rejected.")
	_check(Ballistics.intercept_time(Vector3.ONE, Vector3.ZERO, 0, 30, 8) < 0, "Invalid speed is rejected.")
	_check(ShipCombat.DIRECTIONS.size() == 14, "All fourteen authorable bearings exist.")
	for name in ShipCombat.DIRECTIONS:
		_check(is_equal_approx(ShipCombat.direction(name).length(), 1.0), "Combat directions are normalized.")
	_check(ShipCombat.direction("front") == Vector3.FORWARD and ShipCombat.direction("up") == Vector3.UP, "Bearings use ship-local forward and altitude.")


func _add_ship(faction: StringName, position: Vector3) -> Airship:
	var ship := KESTREL.instantiate() as Airship
	ship.entity_id = _next_id
	_next_id += 1
	ship.faction = faction
	# Isolated ballistic/mount fixtures use explicit target trajectories.
	ship.freeze = true
	_fixture.add_child(ship)
	ship.global_position = position
	_origin.register_root(ship)
	return ship


func _check_neighbor_filter() -> void:
	var ships: Array[Airship] = []
	var positions := PackedVector3Array()
	var velocities := PackedVector3Array()
	var axes := PackedVector3Array()
	var corrections := PackedVector3Array()
	var rng := RandomNumberGenerator.new()
	rng.seed = 651
	for index in range(24):
		var ship := _add_ship(Factions.NEUTRAL, Vector3.ZERO)
		ship.hull_radius = rng.randf_range(10.0, 40.0)
		ship.hull_half_segment = rng.randf_range(0.0, 60.0)
		ships.append(ship)
	var avoidance := ShipAvoidance.new()
	for layout in range(5):
		positions.clear()
		velocities.clear()
		axes.clear()
		for index in range(ships.size()):
			@warning_ignore("integer_division")
			var position := Vector3((index / 2 - 6) * 350, (index % 3) * 20, 0) + Vector3.RIGHT * (index % 2) * 40
			var velocity := Vector3(rng.randf_range(-180, 180), rng.randf_range(-20, 20), rng.randf_range(-180, 180))
			if layout == 1:
				position = Vector3(rng.randf_range(-80, 80), rng.randf_range(-30, 30), rng.randf_range(-80, 80))
			elif layout == 2:
				position = Vector3.ZERO
				velocity = Vector3.ZERO
			elif layout == 3:
				position = Vector3(index * 20 - 240, 0, 0)
				velocity = -position.normalized() * 180
			elif layout == 4:
				position *= 10
				velocity = Vector3.FORWARD * 120
			positions.append(position)
			velocities.append(velocity)
			axes.append(Vector3.FORWARD.rotated(Vector3.UP, rng.randf_range(-PI, PI)))
		for reversed_order in [false, true]:
			if reversed_order:
				ships.reverse()
				positions.reverse()
				velocities.reverse()
				axes.reverse()
			for shift in [Vector3.ZERO, Vector3(0, 0, -10240)]:
				for index in range(positions.size()):
					positions[index] += shift
				avoidance.calculate(ships, positions, velocities, axes, corrections)
				for index in range(ships.size()):
					var expected := _reference_avoidance(index, ships, positions, velocities, axes)
					_check(expected.distance_to(corrections[index]) < 0.001, "Shared avoidance pairs preserve the directed reference across hulls, overlaps, order changes, and rebases.")
	avoidance.calculate([ships[0]], PackedVector3Array([Vector3.ZERO]), PackedVector3Array([Vector3.ZERO]), PackedVector3Array([Vector3.FORWARD]), corrections)
	_check(corrections.size() == 1 and corrections[0] == Vector3.ZERO, "A resized singleton snapshot has no stale correction.")
	avoidance.calculate([], PackedVector3Array(), PackedVector3Array(), PackedVector3Array(), corrections)
	_check(corrections.is_empty(), "An empty avoidance snapshot clears its output.")
	for ship in ships:
		ship.queue_free()
	await process_frame


func _check_mounts_and_health() -> void:
	var player := _add_ship(Factions.PLAYER, Vector3.ZERO)
	var enemy := _add_ship(Factions.ENEMY, Vector3(600, 0, 0))
	var far_enemy := _add_ship(Factions.ENEMY, Vector3(10000, 0, 0))
	_check(player.maximum_health == 500 and player.current_health == 500 and enemy.current_health == 500, "Both factions start with 500 health.")
	await physics_frame
	_check(Factions.are_hostile(player.faction, enemy.faction) and not Factions.are_hostile(player.faction, &"visitors"), "String factions share one hostility rule.")
	_check(player.mounted_slots.size() == 2 and player.maximum_speed == 50 and is_equal_approx(player.hull_radius, 10.5), "Kestrel uses its authored flight tuning and two mounts with its fitted model collider.")
	_check(player.preferred_combat_positions == PackedStringArray(["front_left", "left_back", "back", "back_right", "right", "front_right"]), "Kestrel preserves the specified enabled bearings.")
	var left := player.mounted_slots[0]
	var right := player.mounted_slots[1]
	var left_weapon := left.equipment as MountedWeapon
	var right_weapon := right.equipment as MountedWeapon
	_check(left_weapon.weapon == right_weapon.weapon and right_weapon.weapon == enemy.mounted_slots[0].equipment.definition, "Weapons share immutable authored definitions.")
	_check(left.tier == 1 and left_weapon.weapon.tier == 1, "Rusty cannon fits tier one.")
	_check(left_weapon.weapon.display_name == "Rusty cannon", "The authored weapon exposes its own equipment name.")
	_check((enemy.visual_root.get_node("Envelope") as MeshInstance3D).material_overlay != null, "Enemies have a tint.")
	_check((player.visual_root.get_node("Envelope") as MeshInstance3D).material_overlay == null, "Enemy tint does not leak to players.")
	var axis := -right.global_basis.z
	_check(right.accepts_direction(axis.rotated(Vector3.UP, deg_to_rad(right.cone_half_angle))) and not right.accepts_direction(axis.rotated(Vector3.UP, deg_to_rad(right.cone_half_angle + 1))), "Authored cone boundaries are respected.")
	_check(right_weapon.launch_for(enemy) != Vector3.ZERO and left_weapon.launch_for(enemy) == Vector3.ZERO, "Only the eligible broadside fires toward a target.")
	enemy.global_position.x = -600
	_check(left_weapon.launch_for(enemy) != Vector3.ZERO and right_weapon.launch_for(enemy) == Vector3.ZERO, "The opposite broadside can fire independently.")
	enemy.global_position.x = 600
	enemy.linear_velocity = Vector3(0, 0, right_weapon.weapon.launch_speed * 1.5)
	player.combat.prepare(2.1, player, [player, enemy], _fleet)
	player.combat.prepare(0.0, player, [player, enemy], _fleet)
	_check(player.combat.stand_off_distance < player.engagement_distance, "Ballistically unreachable moving targets cause a closer approach.")
	enemy.linear_velocity = Vector3.ZERO
	player.combat.target = far_enemy
	right.fire_at_targets_in_range = false
	right.step(1.0, player, _observe([player, enemy, far_enemy]), _projectiles)
	_check(right_weapon.shots_fired == 0, "Main-target-only mode does not fire at a pass-by target.")
	right.fire_at_targets_in_range = true
	right.step(1.0, player, _observe([player, enemy, far_enemy]), _projectiles)
	_check(right_weapon.shots_fired == 1 and player.combat.target == far_enemy, "Pass-by fire does not change pursuit target.")
	_check(left_weapon.cooldown == 0 and right_weapon.cooldown == 2 and right_weapon.weapon.reload_seconds == 2, "Cooldowns belong to independent equipped weapons.")
	player.take_damage(5, Factions.PLAYER)
	_check(player.current_health == player.maximum_health, "Friendly damage is rejected at the health owner.")
	player.take_damage(5, Factions.ENEMY)
	_check(player.current_health == player.maximum_health - 5 and enemy.current_health == enemy.maximum_health, "Health is per instance.")
	var deaths: Array[int] = []
	player.died.connect(func(_ship: Airship) -> void: deaths.append(1))
	player.take_damage(player.maximum_health, Factions.ENEMY)
	player.take_damage(player.maximum_health, Factions.ENEMY)
	_check(not player.alive and player.current_health == 0 and deaths.size() == 1, "Death is immediate and emitted once.")
	var nested_deaths: Array[int] = []
	enemy.died.connect(func(_ship: Airship) -> void: nested_deaths.append(1))
	enemy.health_changed.connect(func(current: float, maximum: float) -> void:
		if current > 0.0:
			enemy.take_damage(maximum, Factions.PLAYER)
	)
	enemy.take_damage(5, Factions.PLAYER)
	_check(not enemy.alive and nested_deaths.size() == 1, "Damage triggered by a health listener cannot emit death twice.")
	_projectiles.clear()
	player.queue_free()
	enemy.queue_free()
	far_enemy.queue_free()
	await process_frame


func _check_search_budget() -> void:
	var player := _add_ship(Factions.PLAYER, Vector3.ZERO)
	var ships: Array[Airship] = [player]
	# Five nearer targets pass the cheap cone bound but cannot be intercepted.
	# Failed attempts must not starve the sixth, reachable target.
	for index in range(5):
		var fleeing := _add_ship(Factions.ENEMY, Vector3(100 + index * 80, 0, 0))
		fleeing.linear_velocity = Vector3.RIGHT * 3000
		ships.append(fleeing)
	var eligible := _add_ship(Factions.ENEMY, Vector3(600, 0, 0))
	ships.append(eligible)
	var slot := player.mounted_slots[1]
	var weapon := slot.equipment as MountedWeapon
	for search in range(2):
		var solves := weapon.solve_count
		slot.step(1.0, player, _observe(ships), _projectiles)
		_check(weapon.solve_count - solves <= MountedWeapon.SOLVE_BUDGET, "Every ready weapon search respects its ballistic solve budget.")
		if search == 0:
			_check(weapon.shots_fired == 0, "The first bounded search skips only ineligible nearby targets.")
	_check(weapon.shots_fired == 1 and player.combat.target == null, "Remembered fallback attempts reach a farther eligible opponent without changing pursuit.")
	_projectiles.clear()
	for ship in ships:
		ship.queue_free()
	await process_frame


func _check_equipment_assignment() -> void:
	var player := _add_ship(Factions.PLAYER, Vector3.ZERO)
	var enemy := _add_ship(Factions.ENEMY, Vector3(600, 0, 0))
	var slot := player.mounted_slots[1]
	var original := slot.equipment as MountedWeapon
	var original_transform := slot.transform
	var original_cone := slot.cone_half_angle
	original.cooldown = 1.0
	var utility := MountedEquipment.new()
	utility.definition = EquipmentDefinition.new()
	utility.definition.display_name = "Utility assignment fixture"
	var utility_scene := PackedScene.new()
	_check(utility_scene.pack(utility) == OK, "A utility can use the shared equipment contract without weapon statistics.")
	utility.free()
	var wrong_tier := MountedEquipment.new()
	wrong_tier.definition = EquipmentDefinition.new()
	wrong_tier.definition.tier = 2
	var tier_two_scene := PackedScene.new()
	_check(tier_two_scene.pack(wrong_tier) == OK, "A higher tier equipment fixture can be authored.")
	wrong_tier.free()
	_check(not slot.assign_equipment(tier_two_scene) and slot.equipment == original and original.cooldown == 1.0, "Rejected equipment leaves the installed weapon and its state intact.")
	_check(not slot.assign_equipment(SLOT_SCENE) and slot.equipment == original, "Scenes without an equipment root are rejected.")
	_check(not slot.assign_equipment(PackedScene.new()) and slot.equipment == original, "Empty scene resources are rejected without disturbing equipment.")
	player.combat.prepare(1.0, player, [player, enemy], _fleet)
	_check(player.combat.has_target(), "An armed platform can acquire a target.")
	_check(slot.assign_equipment(utility_scene) and not slot.equipment is MountedWeapon, "A tier-one slot accepts non-weapon equipment.")
	_check(not player.combat.has_target(), "Changing equipment invalidates the old combat bearing and target.")
	player.mounted_slots[0].assign_equipment(null)
	slot.step(1.0, player, _observe([player, enemy]), _projectiles)
	_check(not player.combat.prepare(1.0, player, [player, enemy], _fleet) and not player.combat.has_target(), "Empty and utility-only platforms continue travel instead of pursuing enemies.")
	_check(slot.assign_equipment(null) and slot.equipment == null and slot.equipment_scene == null, "A slot can be explicitly left empty.")
	_check(slot.assign_equipment(CANNON_SCENE), "An empty platform slot can be armed again.")
	var replacement := slot.equipment as MountedWeapon
	_check(replacement != original and replacement.cooldown == 0.0 and replacement.weapon == CANNON, "New equipment has fresh instance state and shares its authored definition.")
	_check(slot.transform == original_transform and slot.cone_half_angle == original_cone and replacement.transform == Transform3D.IDENTITY, "Equipment replacement preserves the ship's authored slot and cone.")
	_check(player.combat.prepare(1.0, player, [player, enemy], _fleet), "Rearming restores combat acquisition.")
	var empty_slot := SLOT_SCENE.instantiate() as MountedSlot
	_fixture.add_child(empty_slot)
	_check(empty_slot.equipment == null and empty_slot.get_child_count() == 0, "Reusable slots have no default cannon or runtime preview geometry.")
	empty_slot.tier = 2
	_check(empty_slot.assign_equipment(tier_two_scene) and not empty_slot.assign_equipment(CANNON_SCENE), "Tier two slots use the same compatibility rule as tier one.")
	empty_slot.tier = 1
	_check(empty_slot.equipment == null, "Changing a slot tier removes incompatible equipment.")
	enemy.mounted_slots[0].assign_equipment(CANNON_SCENE)
	var enemy_cannon := enemy.mounted_slots[0].equipment as MountedWeapon
	_check((enemy_cannon.aim_pivot.get_child(0) as MeshInstance3D).material_overlay != null, "Replacement enemy equipment inherits faction tint.")
	_check((replacement.aim_pivot.get_child(0) as MeshInstance3D).material_overlay == null, "Replacement enemy tint does not leak to other equipment.")
	empty_slot.queue_free()
	player.queue_free()
	enemy.queue_free()
	await process_frame
	_check(not is_instance_valid(original), "Removed equipment is freed with its transient state.")


func _check_impacts() -> void:
	var player := _add_ship(Factions.PLAYER, Vector3.ZERO)
	var enemy := _add_ship(Factions.ENEMY, Vector3(600, 0, 0))
	await physics_frame
	enemy.current_health = enemy.maximum_health
	_fire_at(player, Vector3.ZERO, enemy.global_position)
	await _advance_projectiles(8.1)
	_check(enemy.current_health == enemy.maximum_health - 5, "Swept ballistic hit deals exactly five damage at the project physics rate.")
	# The collision target moves independently after launch; prediction must lead it.
	enemy.linear_velocity = Vector3(0, 0, 50)
	var moving_time := Ballistics.intercept_time(enemy.global_position, enemy.linear_velocity, 200, 30, 8)
	_projectiles.fire(player, Vector3.ZERO, Ballistics.launch_velocity(enemy.global_position, enemy.linear_velocity, 30, moving_time), CANNON)
	var moving_health := enemy.current_health
	for tick in range(8 * _rate):
		await physics_frame
		enemy.global_position += enemy.linear_velocity * _delta
		_projectiles.step(_delta)
		if _projectiles.shots.is_empty():
			break
	_check(enemy.current_health == moving_health - 5, "Lead fire hits a moving crossing target.")
	enemy.linear_velocity = Vector3.ZERO
	enemy.global_position = Vector3(600, 0, 0)
	await physics_frame
	var time := Ballistics.intercept_time(Vector3(600, 0, 0), Vector3.ZERO, 200, 30, 8)
	var launch := Ballistics.launch_velocity(Vector3(600, 0, 0), Vector3.ZERO, 30, time)
	var blocker_position := Ballistics.displacement(launch, 30, time * 0.5)
	var ally := _add_ship(Factions.PLAYER, blocker_position)
	await physics_frame
	var health_before := enemy.current_health
	var friendly_before := _projectiles.friendly_hits
	_fire_at(player, Vector3.ZERO, enemy.global_position)
	await _advance_projectiles(8.1)
	_check(ally.current_health == ally.maximum_health and enemy.current_health == health_before and _projectiles.friendly_hits == friendly_before + 1, "An ally on the curved path consumes the shot without damage.")
	ally.queue_free()
	await process_frame
	var island := StaticBody3D.new()
	island.collision_layer = 2
	var collider := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 10.0
	collider.shape = sphere
	island.add_child(collider)
	_fixture.add_child(island)
	island.global_position = blocker_position
	await physics_frame
	_fire_at(player, Vector3.ZERO, enemy.global_position)
	await _advance_projectiles(8.1)
	_check(enemy.current_health == health_before, "Collidable scenery intercepts the curve.")
	island.queue_free()
	await process_frame
	enemy.global_position = Vector3(1000, 0, 0)
	await physics_frame
	_fire_at(player, Vector3.ZERO, enemy.global_position)
	for tick in range(5 * _rate):
		await physics_frame
		_projectiles.step(_delta)
	_check(_projectiles.shots.size() == 1, "A 1000-meter arc remains in flight beyond five seconds.")
	if not _projectiles.shots.is_empty():
		var shot := _projectiles.shots[0]
		var velocity_before := shot.velocity
		var lifetime_before := shot.remaining
		var relative_before := _projectiles.to_global(shot.position) - enemy.global_position
		_origin.shift_segments(1)
		_check(shot.velocity == velocity_before and shot.remaining == lifetime_before, "Rebasing preserves ballistic velocity and lifetime.")
		_check((_projectiles.to_global(shot.position) - enemy.global_position).distance_to(relative_before) < 0.01, "Rebasing preserves the shot's relative position.")
	player.queue_free()
	await process_frame
	await _advance_projectiles(3.1)
	_check(enemy.current_health == health_before - 5, "A rebased shot survives shooter removal and still hits.")
	var expiry_before := _projectiles.expired_count
	var short_weapon := CANNON.duplicate() as WeaponDefinition
	short_weapon.lifetime = 0.15
	_projectiles.fire(enemy, enemy.global_position, Vector3.UP * 200, short_weapon)
	await _advance_projectiles(0.3)
	_check(_projectiles.shots.is_empty() and _projectiles.expired_count == expiry_before + 1, "Misses expire with a clipped final step.")
	enemy.queue_free()
	await process_frame


func _fire_at(shooter: Airship, muzzle: Vector3, target: Vector3) -> void:
	var time := Ballistics.intercept_time(target - muzzle, Vector3.ZERO, 200, 30, 8)
	_check(time > 0, "Test shot has a valid intercept.")
	if time > 0:
		_projectiles.fire(shooter, muzzle, Ballistics.launch_velocity(target - muzzle, Vector3.ZERO, 30, time), CANNON)


func _advance_projectiles(seconds: float) -> void:
	for tick in range(ceili(seconds * _rate)):
		await physics_frame
		_projectiles.step(_delta)
		if _projectiles.shots.is_empty():
			break


func _check_journey() -> void:
	var journey := JOURNEY.instantiate() as Journey
	root.add_child(journey)
	var spawner := CombatSpawner.new()
	spawner.ship_scene = KESTREL
	journey.add_child(spawner)
	var starting_players := journey.ships.size()
	journey.set_physics_process(false)
	var stationary := journey.ships[0]
	stationary.linear_velocity = Vector3.FORWARD * 100.0
	var initial_position := stationary.global_position
	var initial_anchor := journey.fleet.anchor.global_position
	journey.step_simulation(0.0)
	_check(stationary.global_position == initial_position and journey.fleet.anchor.global_position == initial_anchor and journey.projectiles.fired_count == 0, "Zero-duration refreshes neither move bodies nor fire weapons.")
	stationary.linear_velocity = Vector3.ZERO
	var debug := journey.get_node("FleetAnchor/NavigationDebug") as ShipNavigationDebug
	_check(not debug.enabled and not debug.visible and not debug.is_processing(), "Ordinary combat starts with navigation debug disabled.")
	var maximum_enemies: int = 0
	var maximum_players: int = 0
	var maximum_anchor_distance: float = 0.0
	var maximum_mean_distance: float = 0.0
	var maximum_speed: float = 0.0
	var timings := PackedFloat64Array()
	for tick in range(180 * _rate):
		await physics_frame
		var start := Time.get_ticks_usec()
		spawner.step(_delta, journey)
		journey.step_simulation(_delta)
		timings.append(float(Time.get_ticks_usec() - start) / 1000.0)
		var enemies: int = 0
		var players: int = 0
		for ship in journey.ships:
			enemies += int(ship.faction == Factions.ENEMY)
			players += int(ship.faction == Factions.PLAYER)
			_check(ship.global_position.is_finite() and ship.linear_velocity.is_finite(), "Combat movement stays finite.")
			# Contacts and retained lateral momentum can exceed the propulsion target.
			# The isolated flight check verifies limits and recovery under known forces.
			maximum_speed = maxf(maximum_speed, ship.linear_velocity.length())
			maximum_anchor_distance = maxf(maximum_anchor_distance, ship.global_position.distance_to(journey.fleet.anchor.global_position))
		maximum_mean_distance = maxf(maximum_mean_distance, journey.fleet.average_position.distance_to(journey.fleet.anchor.global_position))
		maximum_enemies = maxi(maximum_enemies, enemies)
		maximum_players = maxi(maximum_players, players)
		_check(enemies <= 100 and players <= 100, "Scheduled spawns independently cap each faction at one hundred living ships.")
		if tick % (10 * _rate) == 0:
			for ship in journey.ships:
				var candidates := journey.island_spawner.navigation_candidates(ship)
				for island in journey.island_spawner.obstacles:
					var offset := island.global_position - ship.global_position
					var radius := ShipIslandNavigation.search_radius(ship, island.navigation_radius)
					if Vector2(offset.x, offset.z).length_squared() <= radius * radius:
						_check(island in candidates, "Spatial island filtering retains every potentially relevant obstacle through travel and rebasing.")
		if tick == _rate - 2:
			_check(enemies == 0 and players == starting_players, "The opt-in fixture waits one second before adding ships to the starting fleet.")
		if tick == _rate:
			_check(enemies == 10 and players == starting_players + 10, "Each scheduled fixture batch adds ten ships to each faction.")
		if tick == 20 * _rate:
			_check(journey.projectiles.fired_count > 0, "Both fleets close and begin firing.")
		if tick == 30 * _rate:
			if _visual:
				await _capture("combat-fleet")
			journey.origin.shift_segments(-1)
		if tick == 35 * _rate and _visual and not journey.ships.is_empty():
			journey.camera_rig.follow_ship(journey.ships[0])
			journey.camera_rig.zoom(270.0 - journey.camera_rig.camera.position.z)
			await _capture("combat-kestrel")
			journey.camera_rig.focus_fleet()
			journey.camera_rig.zoom(2200.0 - journey.camera_rig.camera.position.z)
	_check(journey.projectiles.damaging_hits > 0 and journey.destroyed_count > 0, "Combat causes damage and retires destroyed ships into falling wrecks.")
	_check(spawner.batches == 180, "Spawner continues on one-second cadence.")
	_check(maximum_players > starting_players and maximum_enemies > 0, "Both combat populations receive reinforcements despite ongoing casualties; controlled batches below verify the caps.")
	_check(maximum_anchor_distance < 4500.0 and maximum_mean_distance < 1800.0, "Three minutes of full-fleet combat stay near the anchor with room for turns and island detours.")
	if _visual:
		journey.camera_rig.focus_fleet()
		journey.camera_rig.zoom(4500.0 - journey.camera_rig.camera.position.z)
		await _capture("combat-cohesion")
	for ship in journey.fleet.members:
		_check(ship.faction == Factions.PLAYER and ship.alive, "Enemies and dead ships never enter the friendly fleet average.")
	timings.sort()
	var demo_result := {"seconds": 180, "shots": journey.projectiles.fired_count, "damage_hits": journey.projectiles.damaging_hits, "ally_hits": journey.projectiles.friendly_hits, "destroyed": journey.destroyed_count, "max_players": maximum_players, "max_enemies": maximum_enemies, "max_anchor_distance": maximum_anchor_distance, "max_mean_distance": maximum_mean_distance, "step_p50_ms": timings[timings.size() / 2], "step_p95_ms": timings[int(timings.size() * 0.95)]}
	demo_result["max_observed_speed"] = maximum_speed
	# Cap, partial refill, retargeting, and empty-fleet behavior use controlled state.
	spawner.enabled = false
	for ship in journey.ships.duplicate():
		journey.unregister_ship(ship)
		ship.queue_free()
	journey.projectiles.clear()
	await process_frame
	spawner.enabled = true
	spawner.spawn_radius = Vector2(1500, 2800)
	journey.fleet.average_focus.global_position = journey.fleet.anchor.global_position + Vector3(10000, 1000, 10000)
	for batch in range(10):
		await physics_frame
		if batch == 5:
			journey.origin.shift_segments(-1)
		spawner.step(1, journey)
	_check(_faction_count(journey, Factions.PLAYER) == 100 and _faction_count(journey, Factions.ENEMY) == 100, "Ten unobstructed batches fill both faction caps.")
	for ship in journey.ships:
		var offset := ship.global_position - journey.fleet.anchor.global_position
		var radius := Vector2(offset.x, offset.z).length()
		_check(radius >= 1499.9 and radius <= 2800.1 and absf(offset.y) <= spawner.altitude_spread + 0.1, "Both factions respect the authored anchor-relative spawn region despite a displaced fleet average and rebasing.")
	var spawned := spawner.spawned_count
	spawner.step(10, journey)
	_check(spawner.spawned_count == spawned, "Capped batches do not accumulate spawns.")
	var removed_players: int = 0
	var removed_enemies: int = 0
	for ship in journey.ships:
		if ship.faction == Factions.PLAYER and removed_players < 1:
			journey.camera_rig.follow_ship(ship)
			ship.take_damage(ship.maximum_health, Factions.ENEMY)
			removed_players += 1
		elif ship.faction == Factions.ENEMY and removed_enemies < 11:
			ship.take_damage(ship.maximum_health, Factions.PLAYER)
			removed_enemies += 1
	journey.step_simulation(0)
	await process_frame
	_check(journey.ships.size() == 188 and journey.camera_rig.mode == FleetCamera.Mode.FLEET, "Death removes membership and restores camera focus without immediate replenishment.")
	await physics_frame
	spawner.step(1, journey)
	_check(_faction_count(journey, Factions.PLAYER) == 100 and _faction_count(journey, Factions.ENEMY) == 99 and spawner.spawned_count == spawned + 11, "Each faction refills at most ten ships without exceeding its own capacity.")
	await physics_frame
	spawner.step(1, journey)
	_check(journey.ships.size() == 200 and spawner.spawned_count == spawned + 12, "The following second restores the remaining enemy vacancy.")
	var ids: Dictionary[int, bool] = {}
	for ship in journey.ships:
		_check(not ids.has(ship.entity_id), "Spawned ships have unique IDs.")
		ids[ship.entity_id] = true
	var blocker := StaticBody3D.new()
	blocker.collision_layer = 2
	var shape := SphereShape3D.new()
	shape.radius = 5000
	var collider := CollisionShape3D.new()
	collider.shape = shape
	blocker.add_child(collider)
	journey.add_child(blocker)
	blocker.global_position = journey.fleet.anchor.global_position
	var blocked_ship := journey.ships[0]
	blocked_ship.take_damage(blocked_ship.maximum_health, Factions.ENEMY if blocked_ship.faction == Factions.PLAYER else Factions.PLAYER)
	journey.step_simulation(0)
	await physics_frame
	spawner.step(1, journey)
	_check(journey.ships.size() == 199, "Blocked placement exhausts bounded attempts without overlapping a collider.")
	blocker.queue_free()
	await process_frame
	await physics_frame
	spawner.step(1, journey)
	_check(journey.ships.size() == 200, "Placement retries on a later scheduled batch.")
	spawner.enabled = false
	for ship in journey.ships:
		if ship.faction == Factions.PLAYER:
			ship.take_damage(ship.maximum_health, Factions.ENEMY)
	journey.step_simulation(0)
	_check(journey.fleet.speed == 0 and journey.fleet.velocity == Vector3.ZERO, "An empty player fleet stops the anchor until debug reinforcements arrive.")
	var survivor := KESTREL.instantiate() as Airship
	survivor.entity_id = journey.allocate_ship_id()
	journey.add_child(survivor)
	survivor.global_position = journey.fleet.anchor.global_position
	journey.register_ship(survivor)
	journey.step_simulation(_delta)
	_check(survivor.combat.has_target(), "New player ships acquire a main target.")
	if survivor.combat.has_target():
		var former := survivor.combat.target
		former.take_damage(former.maximum_health, Factions.PLAYER)
		journey.step_simulation(_delta)
		_check(survivor.combat.has_target() and survivor.combat.target != former, "Target death selects another living opponent.")
	for ship in journey.ships:
		if ship.faction == Factions.ENEMY:
			ship.take_damage(ship.maximum_health, Factions.PLAYER)
	journey.step_simulation(_delta)
	_check(not survivor.combat.has_target() and not survivor.combat_engaged and survivor.preferred_velocity != Vector3.ZERO, "The surviving player resumes travel when opponents disappear.")
	print("COMBAT_DEMO ", JSON.stringify(demo_result))
	journey.queue_free()
	await process_frame


func _faction_count(journey: Journey, faction: StringName) -> int:
	var count: int = 0
	for ship in journey.ships:
		count += int(ship.alive and ship.faction == faction)
	return count


func _capture(label: String) -> void:
	var directory := OS.get_environment("AERWYTH_CAPTURE_DIR")
	_check(not directory.is_empty(), "Visual checks require an external capture directory.")
	if directory.is_empty():
		return
	await RenderingServer.frame_post_draw
	_check(root.get_texture().get_image().save_png(directory.path_join(label + ".png")) == OK, "Combat capture was written.")


func _check(condition: bool, message: String) -> void:
	if not condition and message not in _failures:
		_failures.append(message)


# Independent directed oracle, retained only in validation.
static func _reference_avoidance(index: int, ships: Array[Airship], positions: PackedVector3Array, velocities: PackedVector3Array, axes: PackedVector3Array) -> Vector3:
	var ship := ships[index]
	var result := Vector3.ZERO
	for other_index in range(ships.size()):
		if index == other_index:
			continue
		var other := ships[other_index]
		var relative_position := positions[index] - positions[other_index]
		var relative_velocity := velocities[index] - velocities[other_index]
		var reach := ship.hull_half_segment + other.hull_half_segment + ship.hull_radius + other.hull_radius + 8.0
		if relative_position.length() > reach + relative_velocity.length() * 2.0:
			continue
		var approach_time: float = 0.0
		if relative_velocity.length_squared() > 0.1:
			approach_time = clampf(-relative_position.dot(relative_velocity) / relative_velocity.length_squared(), 0.0, 2.0)
		var first := positions[index] + velocities[index] * approach_time
		var second := positions[other_index] + velocities[other_index] * approach_time
		# The hull capsules cannot meet if their enclosing spheres are separated
		# at the same predicted instant used by the exact segment calculation.
		if first.distance_squared_to(second) >= reach * reach:
			continue
		var first_axis := axes[index] * ship.hull_half_segment
		var second_axis := axes[other_index] * other.hull_half_segment
		var closest := Geometry3D.get_closest_points_between_segments(first - first_axis, first + first_axis, second - second_axis, second + second_axis)
		var separation: Vector3 = closest[0] - closest[1]
		var clearance := ship.hull_radius + other.hull_radius + 8.0
		var distance := separation.length()
		if distance >= clearance:
			continue
		var direction := separation / distance if distance > 0.5 else (Vector3.RIGHT if ship.entity_id < other.entity_id else Vector3.LEFT)
		# Exact head-on approaches need lateral steering rather than mutual braking.
		if relative_velocity.length_squared() > 10.0 and absf(direction.dot(relative_velocity.normalized())) > 0.85:
			direction = (Vector3.RIGHT if ship.entity_id < other.entity_id else Vector3.LEFT)
		var urgency := (1.0 - distance / clearance) * (1.0 - 0.5 * approach_time / 2.0)
		result += direction * urgency * 50.0
	return result.limit_length(50.0)


func _observe(ships: Array[Airship]) -> CombatPerception:
	_perception.rebuild(ships)
	return _perception
