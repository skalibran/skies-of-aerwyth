extends SceneTree

const JOURNEY := preload("res://scenes/world/journey.tscn")
const KESTREL := preload("res://scenes/ships/kestrel.tscn")
const CANNON := preload("res://resources/weapons/rusty_cannon.tres")
const MISS_HEIGHT: float = 10000.0

var _journey: Journey
var _failures: Array[String] = []
var _profile: bool = false
var _visual: bool = false
var _phase: String = ""
var _frames: Array[float] = []
var _gpu: Array[float] = []
var _physics_ms: Array[float] = []
var _steps: Array[float] = []
var _results: Array[Dictionary] = []
var _previous_frame: int = 0
var _phase_started_usec: int = 0
var _peak_shots: int = 0
var _peak_nodes: int = 0
var _peak_memory: int = 0
var _component_totals := PackedInt64Array()
var _component_samples: int = 0


func _initialize() -> void:
	_component_totals.resize(Journey.StepPhase.size())
	_profile = "--profile" in OS.get_cmdline_user_args()
	_visual = "--visual" in OS.get_cmdline_user_args()
	_run.call_deferred()


func _run() -> void:
	if _profile:
		if DisplayServer.get_name() == "headless" or OS.get_environment("AERWYTH_PROFILE_DIR").is_empty():
			printerr("Combat profiling requires rendering and an external AERWYTH_PROFILE_DIR; omit --fixed-fps.")
			quit(1)
			return
		Engine.max_fps = 0
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
		root.content_scale_mode = Window.CONTENT_SCALE_MODE_VIEWPORT
		root.content_scale_size = Vector2i(1920, 1080)
		root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_IGNORE
		RenderingServer.viewport_set_measure_render_time(root.get_viewport_rid(), true)
		process_frame.connect(_sample_frame)
	_journey = JOURNEY.instantiate() as Journey
	root.add_child(_journey)
	_journey.set_physics_process(false)
	_journey.profile_steps = true
	_build_fleets()
	var debug := _journey.get_node("FleetAnchor/NavigationDebug") as ShipNavigationDebug
	debug.enabled = false
	_journey.camera_rig.orbit_distance = 3600
	_journey.camera_rig.focus_fleet()
	# Keep native and scripted time aligned with the project physics rate.
	var rate := Engine.physics_ticks_per_second
	var delta := 1.0 / rate
	for tick in range(60 * rate):
		await physics_frame
		if tick == 2 * rate:
			_begin_phase("combat_debug_off")
		if tick == 30 * rate:
			_finish_phase()
			debug.enabled = true
			_begin_phase("combat_debug_on")
		var start := Time.get_ticks_usec()
		_journey.step_simulation(delta)
		if not _phase.is_empty():
			_steps.append(float(Time.get_ticks_usec() - start) / 1000.0)
			for component in range(Journey.StepPhase.size()):
				_component_totals[component] += _journey.step_timings_usec[component]
			_component_samples += 1
		_sample_counts()
		if tick > 0 and tick % (10 * rate) == 0:
			_replace_casualty(Factions.PLAYER)
			_replace_casualty(Factions.ENEMY)
		if tick == 15 * rate or tick == 45 * rate:
			_journey.origin.shift_segments(-1)
		_journey.camera_rig.pan(Vector3(cos(tick * delta / 3.0), 0, sin(tick * delta / 3.0)) * (210.0 * delta))
		if _visual and tick == 25 * rate:
			await _capture("combat-220")
		_check(_journey.ships.size() == 220, "Both fleets remain at the benchmark population after replacements.")
	_finish_phase()
	_check(_journey.fleet.members.size() == 70, "Only seventy player ships contribute to the fleet average.")
	_check(_journey.projectiles.damaging_hits > 0 and _journey.destroyed_count >= 10, "Large-fleet combat and replacement lifecycle are exercised.")
	# A second phase isolates the documented full-rate miss workload alongside
	# movement, streaming, and rendering, without adding duplicate weapon fire.
	debug.enabled = false
	_journey.combat_enabled = false
	_journey.projectiles.clear()
	_begin_phase("miss_volleys_debug_off")
	for tick in range(12 * rate):
		await physics_frame
		var start := Time.get_ticks_usec()
		_journey.step_simulation(delta)
		_journey.projectiles.step(delta)
		if tick % (2 * rate) == 0:
			for ship in _journey.ships:
				for side in [-1, 1]:
					_journey.projectiles.fire(ship, ship.global_position + Vector3.UP * MISS_HEIGHT, Vector3(side * CANNON.launch_speed, 0, 0), CANNON)
		_steps.append(float(Time.get_ticks_usec() - start) / 1000.0)
		_sample_counts()
	_check(_peak_shots == 1760, "Synchronized miss volleys exercise the predicted 1,760-shot peak clear of scenery.")
	_finish_phase()
	_journey.projectiles.clear()
	await process_frame
	_check(_journey.projectiles.shots.is_empty() and _journey.projectiles.get_child_count() == 0, "Projectile cleanup releases all visual nodes.")
	var result := {"cpu": OS.get_processor_name(), "renderer": RenderingServer.get_current_rendering_method(), "gpu": RenderingServer.get_video_adapter_name(), "render_size": [root.get_texture().get_width(), root.get_texture().get_height()], "physics_hz": Engine.physics_ticks_per_second, "friendly": 70, "enemy": 150, "shots_fired": _journey.projectiles.fired_count, "damage_hits": _journey.projectiles.damaging_hits, "ally_hits": _journey.projectiles.friendly_hits, "destroyed": _journey.destroyed_count, "phases": _results}
	result["configuration"] = _configuration()
	print("COMBAT_SCALE ", JSON.stringify(result))
	if _profile:
		var file := FileAccess.open(OS.get_environment("AERWYTH_PROFILE_DIR").path_join("combat-220.json"), FileAccess.WRITE)
		_check(file != null, "Profile output is writable.")
		if file != null:
			file.store_string(JSON.stringify(result, "\t"))
		process_frame.disconnect(_sample_frame)
	_journey.queue_free()
	await process_frame
	for failure in _failures:
		printerr("FAIL: ", failure)
	if _failures.is_empty():
		print("PASS: 220-ship combat scale and projectile workload correctness. Performance budgets are reported separately.")
	quit(0 if _failures.is_empty() else 1)


func _build_fleets() -> void:
	# Preserve the benchmark's large-fleet volume independently of starter tuning.
	_journey.fleet.formation_extent = Vector3(1800, 1200, 1800)
	_journey.fleet.wander_step_radius = 160.0
	for ship in _journey.ships.duplicate():
		_journey.unregister_ship(ship)
		ship.queue_free()
	var center := _journey.fleet.anchor.global_position
	for index in range(70):
		_spawn(Factions.PLAYER, center + Vector3(-900 + (index % 7) * 120, (index % 3 - 1) * 140, (index / 7 - 4.5) * 150))
	for index in range(150):
		_spawn(Factions.ENEMY, center + Vector3(350 + (index % 10) * 120, (index % 3 - 1) * 140, (index / 10 - 7) * 150))
	var spawner := _journey.island_spawner
	for island in spawner.obstacles:
		_journey.origin.unregister_root(island)
		island.queue_free()
	spawner.obstacles.clear()
	spawner.active.clear()
	spawner.records.clear()
	spawner.initialize(_journey.anchor_route_position())


func _spawn(faction: StringName, position: Vector3) -> void:
	var ship := KESTREL.instantiate() as Airship
	ship.entity_id = _journey.allocate_ship_id()
	ship.faction = faction
	ship.maximum_health = 5000
	_journey.add_child(ship)
	ship.global_position = position
	_journey.register_ship(ship)
	ship.reset_physics_interpolation()


func _replace_casualty(faction: StringName) -> void:
	for ship in _journey.ships:
		if ship.faction != faction:
			continue
		var position := ship.global_position
		ship.take_damage(10000, Factions.ENEMY if faction == Factions.PLAYER else Factions.PLAYER)
		_journey._remove_dead_ships()
		_spawn(faction, position)
		return


func _begin_phase(name: String) -> void:
	_phase = name
	_previous_frame = Time.get_ticks_usec()
	_phase_started_usec = _previous_frame


func _sample_frame() -> void:
	if _phase.is_empty():
		return
	var now := Time.get_ticks_usec()
	_frames.append(float(now - _previous_frame) / 1000.0)
	_previous_frame = now
	_gpu.append(RenderingServer.viewport_get_measured_render_time_gpu(root.get_viewport_rid()))
	_physics_ms.append(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0)


func _sample_counts() -> void:
	_peak_shots = maxi(_peak_shots, _journey.projectiles.shots.size())
	_peak_nodes = maxi(_peak_nodes, int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)))
	_peak_memory = maxi(_peak_memory, int(Performance.get_monitor(Performance.MEMORY_STATIC)))


func _finish_phase() -> void:
	var result := {"name": _phase, "step_ms": _summary(_steps), "frame_ms": _summary(_frames), "gpu_ms": _summary(_gpu), "peak_shots": _peak_shots, "peak_nodes": _peak_nodes, "peak_memory_bytes": _peak_memory, "end_nodes": Performance.get_monitor(Performance.OBJECT_NODE_COUNT), "end_memory_bytes": Performance.get_monitor(Performance.MEMORY_STATIC)}
	result["engine_physics_ms"] = _summary(_physics_ms)
	result["step_scope"] = "Journey GDScript work; excludes subsequent native rigid-body integration/contact solving"
	result["simulated_seconds"] = float(_steps.size()) / Engine.physics_ticks_per_second
	result["elapsed_seconds"] = float(Time.get_ticks_usec() - _phase_started_usec) / 1000000.0
	result["script_ms_per_simulated_second"] = result.step_ms.mean * Engine.physics_ticks_per_second
	var budget_ms := 1000.0 / Engine.physics_ticks_per_second
	result["physics_budget_ms"] = budget_ms
	result["step_p95_within_budget"] = result.step_ms.p95 <= budget_ms
	print("PERFORMANCE %s: script step p95 %.3f ms / %.3f ms budget (%s); assess engine physics and wall frames too." % [_phase, result.step_ms.p95, budget_ms, "within" if result.step_p95_within_budget else "EXCEEDED"])
	if _component_samples > 0:
		var components := {}
		var names := Journey.StepPhase.keys()
		for index in range(Journey.StepPhase.size()):
			components[String(names[index]).to_lower()] = float(_component_totals[index]) / (1000.0 * _component_samples)
		result["component_mean_ms"] = components
	_results.append(result)
	print("COMBAT_PHASE ", JSON.stringify(result))
	_phase = ""
	_steps.clear()
	_frames.clear()
	_gpu.clear()
	_physics_ms.clear()
	_peak_shots = 0
	_peak_nodes = 0
	_peak_memory = 0
	_component_totals.fill(0)
	_component_samples = 0


func _configuration() -> Dictionary:
	var ship := _journey.ships[0]
	var slots: Array[Dictionary] = []
	for slot in ship.mounted_slots:
		slots.append({"tier": slot.tier, "half_angle_degrees": slot.cone_half_angle, "position": var_to_str(slot.position), "rotation": var_to_str(slot.rotation), "pass_by": slot.fire_at_targets_in_range})
	# Keep comparison inputs with the raw measurements; branches may change defaults.
	return {
		"engine": Engine.get_version_info().string,
		"controller": "RigidBody3D / force-controlled ShipFlight",
		"mass": ship.mass, "gravity_scale": ship.gravity_scale,
		"friction": ship.physics_material_override.friction, "bounce": ship.physics_material_override.bounce,
		"angular_xz_locked": ship.axis_lock_angular_x and ship.axis_lock_angular_z,
		"combat_seconds": 60, "miss_seconds": 12, "miss_height": MISS_HEIGHT,
		"health": ship.maximum_health, "speed": ship.maximum_speed,
		"acceleration": ship.acceleration, "braking": ship.braking,
		"climb_speed": ship.climb_speed, "yaw_speed_degrees": ship.yaw_speed_degrees,
		"yaw_acceleration_degrees": ship.yaw_acceleration_degrees,
		"lateral_drag": ship.lateral_drag,
		"primary_axis": var_to_str(ship.primary_movement_direction),
		"engagement_distance": ship.engagement_distance,
		"pass_seconds": ship.combat_pass_seconds, "combat_speed_ratio": ship.combat_speed_ratio,
		"combat_radii": var_to_str(_journey.fleet.combat_radii),
		"bearings": ship.preferred_combat_positions, "slots": slots,
		"weapon": {"speed": CANNON.launch_speed, "gravity": CANNON.gravity,
			"range": CANNON.range_units, "damage": CANNON.damage,
			"reload": CANNON.reload_seconds, "lifetime": CANNON.lifetime},
		"island_seed": _journey.island_spawner.world_seed,
		"terrain_voxel_size": _journey.terrain.profile.voxel_size,
	}


func _summary(values: Array[float]) -> Dictionary:
	if values.is_empty():
		return {}
	var sorted := values.duplicate()
	sorted.sort()
	var total: float = 0.0
	for value in values:
		total += value
	return {"mean": total / values.size(), "n": sorted.size(), "p50": sorted[sorted.size() / 2], "p95": sorted[int((sorted.size() - 1) * 0.95)], "max": sorted.back()}


func _capture(label: String) -> void:
	var directory := OS.get_environment("AERWYTH_CAPTURE_DIR")
	_check(not directory.is_empty(), "Visual scale checks require an external capture directory.")
	if directory.is_empty():
		return
	await RenderingServer.frame_post_draw
	_check(root.get_texture().get_image().save_png(directory.path_join(label + ".png")) == OK, "Scale capture was written.")


func _check(condition: bool, message: String) -> void:
	if not condition and message not in _failures:
		_failures.append(message)
