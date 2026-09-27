extends SceneTree

const JOURNEY := preload("res://scenes/world/journey.tscn")
const BATTLE := preload("res://scenes/world/staged_battle.tscn")
var failures: Array[String] = []
var journey: StagedBattle
var types: Dictionary = {}
var replacement_types: Dictionary = {}
var visual: bool = false
var expected_ids: Dictionary = {}


func _initialize() -> void:
	visual = "--visual" in OS.get_cmdline_user_args()
	_run.call_deferred()


func _run() -> void:
	var ordinary := JOURNEY.instantiate() as Journey
	root.add_child(ordinary)
	ordinary.set_physics_process(false)
	_check(ordinary.ships.size() == 3 and ordinary.encounters.enabled, "Ordinary Journey retains its three starting ships and enabled encounters.")
	_check(is_equal_approx(ordinary.fleet.minimum_radius, 180.0) and is_equal_approx(ordinary.camera_rig.orbit_distance, 600.0), "Battle sphere and camera overrides do not leak into Journey.")
	ordinary.queue_free()
	await process_frame
	journey = BATTLE.instantiate() as StagedBattle
	root.add_child(journey)
	journey.set_physics_process(false)
	_check(journey.terrain != null and journey.clouds != null and journey.water != null and journey.island_spawner != null, "The battle retains Journey's complete terrain, clouds, water, and islands.")
	_check(journey.get_node_or_null("WorldEnvironment") != null and journey.get_node_or_null("Sun") != null and journey.get_node_or_null("MasterUI") != null, "The battle inherits the environment, lighting, and full UI.")
	_check(journey.wreck_controller != null and journey.projectiles != null and journey.origin != null, "The battle retains projectiles, wrecks, and floating origin.")
	_check(journey.faction_limit == 100 and journey.battle_seed == 715932, "The reference authors 100 per faction and a stable comparison seed.")
	_check(is_equal_approx(journey.fleet.minimum_radius, 1400.0) and is_equal_approx(journey.camera_rig.orbit_distance, 2800.0), "The inherited scene supplies its battle sphere and camera settings.")
	journey.ship_spawned.connect(_spawned)
	var rate := Engine.physics_ticks_per_second
	var dt := 1.0 / rate
	var before_replacements: int = 0
	for tick in range(15 * rate):
		await physics_frame
		journey.step_simulation(dt)
		var counts := _counts()
		_check(counts[0] <= 100 and counts[1] <= 100, "Automatic top-ups never exceed either faction cap.")
		if tick == 3 * rate:
			_check(counts == [100, 100], "Both factions reach 100 after startup.")
			_check(types.size() == 4, "The random battle contains all four catalog ships.")
			_check(not journey.encounters.enabled and journey.encounters.spawned_count == 0, "Ordinary waves stay disabled.")
			print("STAGED_POPULATION ", counts, " TYPES ", types)
		if tick == 5 * rate:
			journey.combat_enabled = false
			before_replacements = journey.destroyed_count
			for faction in [Factions.PLAYER, Factions.ENEMY]:
				var removed: int = 0
				for ship in journey.ships.duplicate():
					if ship.faction == faction and removed < 6:
						expected_ids[ship.entity_id] = true
						ship.take_damage(ship.maximum_health, Factions.ENEMY if faction == Factions.PLAYER else Factions.PLAYER)
						removed += 1
		if tick == 6 * rate:
			_check(counts == [100, 100], "Both factions refill after six forced casualties each.")
			_check(journey.destroyed_count >= before_replacements + 12, "Forced casualties pass through normal wreck registration.")
			for ship in journey.ships:
				_check(not expected_ids.has(ship.entity_id), "Replacement ships receive new IDs.")
			print("STAGED_TOP_UP ", counts, " REPLACEMENT_TYPES ", replacement_types)
			journey.combat_enabled = true
		if tick == 9 * rate:
			journey.origin.shift_segments(-1)
		if visual and tick == 12 * rate:
			var directory := OS.get_environment("AERWYTH_CAPTURE_DIR")
			_check(not directory.is_empty(), "Rendered battle checks need an external capture directory.")
			if not directory.is_empty():
				await RenderingServer.frame_post_draw
				_check(root.get_texture().get_image().save_png(directory.path_join("staged-battle.png")) == OK, "The inherited battle view is captured.")
	_check(journey.projectiles.fired_count > 0 and journey.projectiles.damaging_hits > 0, "Mixed fleets acquire and damage opponents.")
	print("STAGED_RESULT ", JSON.stringify({"population":_counts(),"types":types,"replacement_types":replacement_types,"shots":journey.projectiles.fired_count,"damage_hits":journey.projectiles.damaging_hits,"destroyed":journey.destroyed_count,"marker_speed":journey.fleet.speed,"radius":journey.fleet.radius}))
	journey.queue_free()
	await process_frame
	for failure in failures:
		printerr("FAIL: ", failure)
	if failures.is_empty():
		print("PASS: ordinary Journey isolation, inherited scenery, staged random fleets, caps, top-ups, clear placement, rebasing, and live combat.")
	quit(0 if failures.is_empty() else 1)


func _counts() -> Array[int]:
	var counts: Array[int] = [0, 0]
	for ship in journey.ships:
		if ship.alive and not ship.is_queued_for_deletion():
			counts[0 if ship.faction == Factions.PLAYER else 1] += 1
	return counts


func _spawned(ship: Airship) -> void:
	var name := ship.scene_file_path.get_file().get_basename()
	types[name] = int(types.get(name, 0)) + 1
	if not expected_ids.is_empty():
		replacement_types[name] = int(replacement_types.get(name, 0)) + 1
	_check(ship.current_health == ship.maximum_health, "Spawned ships begin with full authored health.")
	for other in journey.ships:
		if other == ship:
			continue
		var clearance := ship.hull_radius + ship.hull_half_segment + other.hull_radius + other.hull_half_segment + ShipNavigation.HULL_CLEARANCE
		_check(ship.global_position.distance_to(other.global_position) >= clearance - 0.01, "Spawned hulls do not overlap existing or same-tick ships.")


func _check(condition: bool, message: String) -> void:
	if not condition and message not in failures:
		failures.append(message)
