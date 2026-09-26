extends SceneTree

const JOURNEY := preload("res://scenes/world/journey.tscn")
const PROFILE := preload("res://resources/encounters/journey_encounters.tres")
const KESTREL := preload("res://resources/encounters/entries/kestrel.tres")
const SWIFT := preload("res://resources/encounters/entries/swift.tres")
const MANTA := preload("res://resources/encounters/entries/manta.tres")
const BASTION := preload("res://resources/encounters/entries/bastion.tres")
const PAIR := preload("res://resources/encounters/entries/scout_pair.tres")
const PATROL := preload("res://resources/encounters/entries/escort_patrol.tres")

class PlacementFixture extends Journey:
	var blocked: bool = true
	var placed: Array[ShipDefinition] = []

	func try_spawn_enemy(definition: ShipDefinition) -> bool:
		if blocked:
			return false
		placed.append(definition)
		return true

var _failures: Array[String] = []
var _rate: int = Engine.physics_ticks_per_second
var _visual: bool = false


func _initialize() -> void:
	_visual = "--visual" in OS.get_cmdline_user_args()
	_run.call_deferred()


func _run() -> void:
	_check_planner()
	_check_scheduler()
	await _check_travel_battle_cycle()
	await _check_journey()
	for failure in _failures:
		printerr("FAIL: ", failure)
	if _failures.is_empty():
		print("PASS: threat budgets, weighted entries, fleet guarantees, scheduling/retries, new ship loadouts, combat, and origin lifecycle.")
	quit(0 if _failures.is_empty() else 1)


func _option(entry: SpawnEntry, weight: float = 1.0, limit: int = 4) -> EncounterOption:
	var option := EncounterOption.new()
	option.entry = entry
	option.weight = weight
	option.maximum_selections = limit
	return option


func _profile(budget: int) -> EncounterProfile:
	var profile := EncounterProfile.new()
	profile.base_budget = budget - 1
	profile.budget_per_threat = 1.0
	profile.minimum_spend_ratio = 1.0
	return profile


func _guarantee(entry: SpawnEntry, count: int, charge: bool) -> GuaranteedSpawn:
	var guarantee := GuaranteedSpawn.new()
	guarantee.entry = entry
	guarantee.count = count
	guarantee.charge_budget = charge
	return guarantee


func _check_planner() -> void:
	PROFILE.validate()
	_check(PROFILE.threat_at(499.99) == 0 and PROFILE.threat_at(500.0) == 1 and PROFILE.threat_at(1000.0) == 2, "Threat increases exactly at distance boundaries.")
	_check(PROFILE.budget_at(1) == 15 and PROFILE.budget_at(8) == 120, "Authored linear budget growth is 15 points per threat.")
	_check(PAIR.cost() == 12 and PATROL.cost() == 36, "Fleet costs sum complete member counts.")
	var rng := RandomNumberGenerator.new()
	rng.seed = 7919
	var seen_entries: Array[SpawnEntry] = []
	var saw_remainder: bool = false
	for index in range(3000):
		var wave := 1 + index % 12
		var plan := EncounterPlanner.build(PROFILE, wave, rng)
		var total: int = 0
		for ship in plan.ships:
			total += ship.spawn_cost
		_check(total == plan.spent + plan.bonus_cost and plan.spent <= plan.budget, "Default waves account for all ships and only bonus entries exceed the budget.")
		for option in plan.selections:
			_check(plan.selections.count(option) <= option.maximum_selections, "Random entry repetition respects authored limits.")
			if option.entry not in seen_entries:
				seen_entries.append(option.entry)
		saw_remainder = saw_remainder or plan.spent < plan.budget
	_check(seen_entries.size() == PROFILE.options.size() and saw_remainder, "The authored pool produces every entry and permits unspent budget.")
	var profile := _profile(10)
	profile.options = [_option(PAIR)]
	_check(EncounterPlanner.build(profile, 1, rng).ships.is_empty(), "Unaffordable fleets are never partially selected.")
	profile.base_budget = 11
	_check(EncounterPlanner.build(profile, 1, rng).ships == [SWIFT.ship, SWIFT.ship], "A fleet option spawns its complete authored composition.")
	profile = _profile(30)
	profile.options = [_option(SWIFT)]
	var authored := WaveOverride.new()
	authored.guaranteed = [_guarantee(PAIR, 2, true)]
	profile.wave_overrides = [authored]
	var charged := EncounterPlanner.build(profile, 1, rng)
	_check(charged.ships.size() == 5 and charged.spent == 30 and charged.bonus_cost == 0, "Two guaranteed fleets debit their full 24-point cost before random filling.")
	authored.guaranteed[0].charge_budget = false
	var bonus := EncounterPlanner.build(profile, 1, rng)
	_check(bonus.ships.size() == 8 and bonus.spent == 24 and bonus.bonus_cost == 24, "On-top fleets leave the random budget intact, with selection limits still applied.")
	authored.guaranteed = [_guarantee(BASTION, 2, true)]
	var oversized := EncounterPlanner.build(profile, 1, rng)
	_check(oversized.ships == [BASTION.ship, BASTION.ship] and oversized.spent == 120 and oversized.selections.is_empty(), "Over-budget guarantees remain guaranteed and suppress random extras.")
	authored.fill_random_budget = false
	authored.guaranteed = [_guarantee(PATROL, 1, false)]
	var fixed := EncounterPlanner.build(profile, 1, rng)
	_check(fixed.ships == [MANTA.ship, SWIFT.ship, SWIFT.ship] and fixed.spent == 0, "Fully authored waves honor guaranteed fleets without random fill.")
	# Equal-cost options isolate weight from affordability; only one fits per wave.
	profile = _profile(10)
	var alternate := SpawnEntry.new()
	alternate.ship = KESTREL.ship.duplicate() as ShipDefinition
	profile.options = [_option(KESTREL, 1.0), _option(alternate, 3.0)]
	var selected: int = 0
	for index in range(10000):
		selected += int(EncounterPlanner.build(profile, 1, rng).ships[0] == alternate.ship)
	_check(absf(float(selected) / 10000.0 - 0.75) < 0.02, "Weighted selection follows the authored 1:3 ratio.")
	profile.options[0].weight = 0.0
	profile.options[1].maximum_selections = 1
	profile.base_budget = 9999
	_check(EncounterPlanner.build(profile, 1, rng).ships == [alternate.ship], "Disabled options and exhausted caps terminate filling even with a large remainder.")
	var repeat_rng := RandomNumberGenerator.new()
	rng.seed = 104729
	repeat_rng.seed = 104729
	for wave in range(1, 20):
		_check(EncounterPlanner.build(PROFILE, wave, rng).ships == EncounterPlanner.build(PROFILE, wave, repeat_rng).ships, "A fixed composition seed reproduces waves without mutating definitions.")


func _check_scheduler() -> void:
	var fixture := PlacementFixture.new()
	fixture.fleet = FleetController.new()
	fixture.progression = JourneyProgress.new()
	fixture.add_child(fixture.fleet)
	fixture.add_child(fixture.progression)
	var friendly := Airship.new()
	fixture.add_child(friendly)
	fixture.fleet.members.append(friendly)
	var director := EncounterDirector.new()
	director.profile = _profile(10)
	var first := WaveOverride.new()
	first.guaranteed = [_guarantee(PAIR, 1, true)]
	var third := WaveOverride.new()
	third.wave_number = 3
	third.guaranteed = [_guarantee(MANTA, 1, false)]
	director.profile.wave_overrides = [first, third]
	director.random_seed = 37
	director.spawns_per_tick = 1
	root.add_child(director)
	var announcements: Array[Vector2i] = []
	director.wave_spawned.connect(func(number: int, score: int) -> void: announcements.append(Vector2i(number, score)))
	fixture.progression.distance = 499.99
	director.step(1000.0, fixture)
	_check(director.planned_waves == 0, "Elapsed time cannot substitute for travel.")
	fixture.progression.distance = 500.0
	director.step(0.0, fixture)
	fixture.combat_enabled = false
	director.step(1.0, fixture)
	fixture.combat_enabled = true
	director.enabled = false
	director.step(1.0, fixture)
	_check(director.planned_waves == 0, "Zero-duration refreshes and disabled encounter/combat checks cannot spawn.")
	director.enabled = true
	director.step(1.0 / _rate, fixture)
	var roll_state := director._rng.state
	for index in range(10):
		director.step(0.5, fixture)
	_check(director.planned_waves == 1 and fixture.placed.is_empty() and director._rng.state == roll_state, "Blocked placement retains the rolled plan without consuming new randomness.")
	_check(director.is_combat_active(fixture), "Pending placement holds combat active before the first successful spawn.")
	_check(announcements.is_empty(), "Blocked waves do not announce a spawn before placement succeeds.")
	fixture.blocked = false
	director.step(0.5, fixture)
	_check(fixture.placed.size() == 1, "Placement obeys the per-tick work limit.")
	director.step(1.0 / _rate, fixture)
	_check(fixture.placed == [SWIFT.ship, SWIFT.ship], "Retried guaranteed fleets eventually spawn every member exactly once.")
	_check(announcements == [Vector2i(1, 12)], "A wave announces once on its first ship, including over-budget guaranteed cost.")
	fixture.progression.distance = 0.0
	director.step(1.0, fixture)
	fixture.progression.distance = 2000.0
	director.step(1.0 / _rate, fixture)
	_check(director.threat_level == 4 and director.planned_waves == 2, "A distance jump updates threat and catches up at most one wave per tick.")
	director.step(1.0 / _rate, fixture)
	director.step(1.0 / _rate, fixture)
	_check(director.planned_waves == 4 and fixture.placed.size() == 3 and fixture.placed.back() == MANTA.ship, "Crossed milestones include empty waves and keep each milestone's authored override.")
	_check(announcements == [Vector2i(1, 12), Vector2i(3, 24)], "Empty waves stay silent and bonus entries contribute their full difficulty score.")
	fixture.fleet.members.clear()
	fixture.progression.distance = 2500.0
	director.step(1.0, fixture)
	_check(director.planned_waves == 4, "No new encounters are scheduled without living friendlies.")
	director.free()
	fixture.free()


func _check_travel_battle_cycle() -> void:
	var journey := JOURNEY.instantiate() as Journey
	journey.encounters.random_seed = 101
	var wave_distances: Array[float] = []
	journey.encounters.wave_planned.connect(func(_number: int, _plan: EncounterPlanner.Plan) -> void: wave_distances.append(journey.progression.distance))
	# Keep both sides alive to verify overlapping waves independently of balance.
	journey.ship_spawned.connect(func(ship: Airship) -> void:
		ship.maximum_health = 100000.0
		ship.current_health = ship.maximum_health
	)
	root.add_child(journey)
	for ship in journey.ships:
		ship.maximum_health = 100000.0
		ship.current_health = ship.maximum_health
	for tick in range(45 * _rate):
		await physics_frame
		if journey.fleet.in_combat:
			break
	_check(journey.encounters.planned_waves == 1 and journey.fleet.in_combat, "Normal travel reaches the first wave and enters fleet-wide combat.")
	var battle_start := journey.fleet.marker.global_position
	for tick in range(45 * _rate):
		await physics_frame
		for ship in journey.ships:
			_check(ship.navigation.goal_offset.length() <= ship.navigation.usable_radius(ship) + 0.01, "Combat goals remain inside the translating fleet sphere.")
		if journey.encounters.planned_waves >= 2:
			break
	_check(journey.fleet.in_combat and journey.fleet.marker.global_position.z < battle_start.z - 100.0, "The marker makes forward progress throughout an active battle.")
	_check(wave_distances.size() == 2, "The next distance milestone can spawn a wave while previous enemies remain alive.")
	for index in range(wave_distances.size()):
		var milestone := (index + 1) * journey.encounters.profile.threat_distance
		_check(wave_distances[index] >= milestone and wave_distances[index] < milestone + journey.fleet.cruise_speed / _rate + 0.01, "Continuous travel triggers each crossed milestone once within one physics step.")
	if _visual:
		var debug := journey.get_node("FleetMarker/NavigationDebug") as ShipNavigationDebug
		debug.enabled = true
		await _capture("marker-battle")
	var before_clear := journey.fleet.marker.global_position
	for ship in journey.ships.duplicate():
		if ship.faction == Factions.ENEMY:
			ship.take_damage(ship.maximum_health, Factions.PLAYER)
	await physics_frame
	await physics_frame
	_check(not journey.fleet.in_combat and journey.fleet.marker.global_position.z < before_clear.z, "Clearing the encounter preserves continuous forward travel.")
	_check(journey.fleet.occupants.size() == journey.fleet.members.size(), "Enemy deaths remove their navigation footprints through Journey's lifecycle.")
	var distance := journey.progression.distance
	journey.set_physics_process(false)
	journey.origin.shift_segments(-1)
	journey.progression.update(journey.marker_route_position())
	_check(absf(journey.progression.distance - distance) < 0.01, "A route rebase cannot advance a milestone.")
	journey.queue_free()
	await process_frame


func _check_journey() -> void:
	var journey := JOURNEY.instantiate() as Journey
	journey.encounters.random_seed = 101
	root.add_child(journey)
	journey.set_physics_process(false)
	journey._enemy_spawn_rng.seed = 71937
	var announcement := (journey.get_node("MasterUI") as MasterUI).wave_announcement
	_check(not announcement.visible, "The wave announcement starts hidden.")
	for ship in journey.ships:
		ship.freeze = true
	# A leading, sideways hull must determine clearance instead of the marker alone.
	journey.ships[0].position.z -= 200.0
	journey.ships[0].rotation.y = PI * 0.5
	journey.ships[0].reset_physics_interpolation()
	_check_boundaries(journey)
	var planned: Array[EncounterPlanner.Plan] = []
	journey.encounters.wave_planned.connect(func(_number: int, plan: EncounterPlanner.Plan) -> void: planned.append(plan))
	journey.ship_spawned.connect(func(ship: Airship) -> void: _check_spawn(ship, journey))
	journey.camera_rig.pan(Vector3(0, 0, -2000))
	journey.origin.shift_segments(-1)
	journey.progression.update(journey.marker_route_position())
	_check_boundaries(journey)
	journey.step_simulation(1.0 / _rate)
	_check(journey.encounters.planned_waves == 0, "Camera movement and rebasing cannot advance threat.")
	# A real physics blocker covers the entire forward region and all candidate hulls.
	var blocker := StaticBody3D.new()
	blocker.collision_layer = 2
	var collider := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(4000, 1000, 4000)
	collider.shape = box
	blocker.add_child(collider)
	journey.add_child(blocker)
	blocker.global_position = journey.fleet.marker.global_position
	await _frames(2)
	_move_to_distance(journey, 500.0)
	journey.step_simulation(1.0 / _rate)
	_check(journey.encounters.planned_waves == 1 and journey.encounters.spawned_count == 0, "A distance milestone plans a wave but rejects positions blocked by scenery.")
	_check(not announcement.visible, "Planning a blocked wave leaves the composed UI hidden.")
	blocker.free()
	await _frames(2)
	for tick in range(_rate):
		journey.encounters.step(1.0 / _rate, journey)
	_check(journey.encounters.spawned_count == planned[0].ships.size(), "Clearing a blocker releases the original wave without losing ships.")
	_check(announcement.visible and announcement.wave_label.text == "Wave 1  |  Difficulty: %d" % (planned[0].spent + planned[0].bonus_cost), "Successful spawning updates the composed wave number and full difficulty score.")
	_check_boundaries(journey)
	if _visual:
		journey.camera_rig.focus_fleet()
		journey.camera_rig.orbit_distance = 1400.0
		journey.camera_rig.yaw = 0.0
		journey.camera_rig.pitch = -0.55
		await _capture("threat-boundaries")
	var first_count := journey.encounters.spawned_count
	_move_to_distance(journey, 1000.0)
	journey.step_simulation(1.0 / _rate)
	_check(planned.size() == 2 and MANTA.ship in planned[1].ships, "Wave two guarantees the authored corvette through Journey orchestration.")
	_move_to_distance(journey, 4000.0)
	for tick in range(20):
		journey.encounters.step(1.0 / _rate, journey)
	var total: int = 0
	for plan in planned:
		total += plan.ships.size()
	_check(planned.size() == 8 and journey.encounters.spawned_count == total and first_count > 0, "Skipped distance milestones and guaranteed fleets spawn all planned ships exactly once.")
	_check(journey.fleet.members.size() == 3, "Enemy waves never join friendly fleet membership.")
	_check(journey.fleet.occupants.size() == journey.ships.size() and journey.fleet.required_radius() > journey.fleet.minimum_radius, "Authored waves contribute every living enemy hull to the shared sphere size.")
	_check(announcement.visible and announcement.wave_label.text == "Wave 8  |  Difficulty: %d" % (planned[7].spent + planned[7].bonus_cost), "A later wave replaces the announcement and includes its on-top fleet cost.")
	if _visual:
		await _capture("wave-announcement")
	await _frames(ceili(announcement.display_seconds * _rate) + 2)
	_check(not announcement.visible, "Wave announcements expire after their authored duration.")
	# Inspect every composed hull, native collision, equipped slot, and presentation.
	for entry: SpawnEntry in [SWIFT, MANTA, BASTION]:
		var ship := entry.ship.scene.instantiate() as Airship
		ship.entity_id = journey.allocate_ship_id()
		ship.position = journey.fleet.marker.position + Vector3(0, 400, 0)
		ship.freeze = true
		journey.add_child(ship)
		journey.register_ship(ship)
		var expected_slots: int = 1 if entry == SWIFT else (4 if entry == MANTA else 6)
		_check(ship.mounted_slots.size() == expected_slots and ship.current_health == ship.maximum_health, "Primitive ships initialize their authored health and loadouts.")
		for slot in ship.mounted_slots:
			_check(slot.equipment is MountedWeapon and slot.equipment.definition.tier == slot.tier, "Every new cannon is equipped in a compatible slot.")
		_check_hull(ship)
		if _visual:
			journey.camera_rig.follow_ship(ship)
			journey.camera_rig.orbit_distance = 120.0 if entry == SWIFT else 180.0
			journey.camera_rig.yaw = 0.7
			journey.camera_rig.pitch = -0.25
			await _capture(entry.ship.display_name.to_lower())
		ship.free()
	# Run native movement and weapons together with the generated mixed roster.
	for ship in journey.ships:
		ship.freeze = false
	journey.camera_rig.orbit_distance = 1700.0
	journey.camera_rig.focus_fleet()
	journey.set_physics_process(true)
	await _frames(35 * _rate)
	_check(journey.projectiles.fired_count > 0, "Budget-generated enemies acquire opponents and fire live weapons.")
	if _visual:
		await _capture("encounter")
	journey.set_physics_process(false)
	journey.encounters.step(1.0 / _rate, journey)
	var completed := journey.encounters.planned_waves
	var spawned := journey.encounters.spawned_count
	var logical_distance := journey.progression.distance
	journey.origin.shift_segments(-1)
	journey.progression.update(journey.marker_route_position())
	journey.encounters.step(1.0 / _rate, journey)
	_check_boundaries(journey)
	_check(is_equal_approx(logical_distance, journey.progression.distance) and completed == journey.encounters.planned_waves and spawned == journey.encounters.spawned_count, "Rebasing an active encounter neither replays nor adds a wave.")
	journey.queue_free()
	await process_frame


func _move_to_distance(journey: Journey, distance: float) -> void:
	var route := journey.progression.start_position.advanced(-distance)
	var displacement := Vector3(0, 0, route.to_scene(journey.origin.segment) - journey.fleet.marker.global_position.z)
	journey.fleet.marker.global_position += displacement
	for ship in journey.ships:
		ship.global_position += displacement
		ship.reset_physics_interpolation()
	journey.progression.update(journey.marker_route_position())


func _check_spawn(ship: Airship, journey: Journey) -> void:
	if ship.faction != Factions.ENEMY:
		return
	ship.freeze = true
	var offset := ship.global_position - journey.fleet.marker.global_position
	_check(absf(offset.x) <= Journey.ENEMY_SPAWN_HALF_WIDTH + 0.1 and absf(offset.y) <= Journey.ENEMY_SPAWN_ALTITUDE_SPREAD + 0.1, "Enemy placement stays within the forward region's width and altitude band.")
	var rear_z := ship.global_position.z + ship.hull_radius + ship.hull_half_segment * absf(ship.global_basis.z.z)
	for friendly in journey.fleet.members:
		var front_z := friendly.global_position.z - friendly.hull_radius - friendly.hull_half_segment * absf(friendly.global_basis.z.z)
		_check(front_z - rear_z >= Journey.ENEMY_SPAWN_GAP - 0.1, "Enemy hulls spawn at least 100 meters ahead of every friendly hull, including yawed leaders.")
	var toward_party := journey.fleet.marker.global_position - ship.global_position
	toward_party.y = 0.0
	_check((-ship.global_basis.z).dot(toward_party.normalized()) > 0.999, "Incoming enemies face the party at placement.")
	_check(ship in journey.fleet.occupants and ship not in journey.fleet.members and ship in journey.origin._roots, "Enemy registration includes sphere occupancy and rebasing while excluding friendly fleet membership.")
	for other in journey.ships:
		if other == ship:
			continue
		var clearance := ship.hull_radius + ship.hull_half_segment + other.hull_radius + other.hull_half_segment
		_check(ship.entity_id != other.entity_id and ship.global_position.distance_to(other.global_position) >= clearance, "New ships have unique IDs and clear same-tick placement.")


func _check_boundaries(journey: Journey) -> void:
	var boundaries := journey.get_node("ThreatBoundaries") as ThreatBoundaries
	boundaries.update_boundaries()
	var vertices: PackedVector3Array = boundaries.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var spacing := journey.encounters.profile.threat_distance
	_check(vertices.size() == 2 * (boundaries.last_level - boundaries.first_level + 1), "One horizontal line sections each visible threat milestone.")
	for index in range(0, vertices.size(), 2):
		var left := boundaries.to_global(vertices[index])
		var right := boundaries.to_global(vertices[index + 1])
		var level: int = boundaries.first_level + index / 2
		var route := RoutePosition.from_scene(left.z, journey.origin.segment)
		var distance := JourneyProgress.distance_at(route, journey.progression.start_position)
		_check(absf(distance - float(level) * spacing) < 0.1, "Boundary positions stay at logical threat milestones through travel, camera movement, and rebasing.")
		_check(is_equal_approx(left.y, journey.fleet.marker.global_position.y) and left.y == right.y and left.z == right.z, "Threat lines extend horizontally at marker height.")
		var camera := journey.camera_rig.camera
		_check(left.x < camera.global_position.x - camera.far and right.x > camera.global_position.x + camera.far, "Threat line endpoints extend beyond the camera's visible range.")


func _check_hull(ship: Airship) -> void:
	for node in ship.visual_root.get_children():
		if not node is MeshInstance3D:
			continue
		var mesh := node as MeshInstance3D
		for surface in range(mesh.mesh.get_surface_count()):
			var vertices: PackedVector3Array = mesh.mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]
			for vertex in vertices:
				var point := ship.to_local(mesh.to_global(vertex))
				point.z -= clampf(point.z, -ship.hull_half_segment, ship.hull_half_segment)
				_check(point.length() <= ship.hull_radius + 0.1, "Primitive visual hulls fit inside their authored capsule.")


func _frames(count: int) -> void:
	for index in range(count):
		await physics_frame


func _capture(label: String) -> void:
	var directory := OS.get_environment("AERWYTH_CAPTURE_DIR")
	if directory.is_empty():
		return
	await _frames(3)
	await RenderingServer.frame_post_draw
	_check(root.get_texture().get_image().save_png(directory.path_join(label + ".png")) == OK, "Rendered encounter capture saved.")


func _check(condition: bool, message: String) -> void:
	if not condition and message not in _failures:
		_failures.append(message)
