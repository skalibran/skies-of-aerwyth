extends SceneTree

const KESTREL := preload("res://scenes/ships/kestrel.tscn")

var _failures: Array[String] = []
var _visual: bool = false
var _fixture: Node3D
var _origin: FloatingOrigin


func _initialize() -> void:
	_visual = "--visual" in OS.get_cmdline_user_args()
	_run.call_deferred()


func _run() -> void:
	var orphans := Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)
	_fixture = Node3D.new()
	root.add_child(_fixture)
	_origin = FloatingOrigin.new()
	_fixture.add_child(_origin)
	var projectiles := ProjectileController.new()
	_fixture.add_child(projectiles)
	_origin.register_root(projectiles)
	var player := _ship(Factions.PLAYER, Vector3.ZERO, 1)
	var enemy := _ship(Factions.ENEMY, Vector3.RIGHT * 600, 2)
	player.combat.target = enemy
	enemy.combat.target = player
	var gun := player.mounted_slots[1].equipment as MountedWeapon
	var other_gun := enemy.mounted_slots[0].equipment as MountedWeapon
	var smoke_scene := gun.shot_smoke_scene
	_check(smoke_scene != null and smoke_scene == other_gun.shot_smoke_scene, "Rusty cannons opt into the same reusable smoke scene.")
	var perception := CombatPerception.new()
	perception.rebuild([player, enemy])
	if _visual:
		_setup_view()
	await physics_frame
	await physics_frame
	enemy.position.x = 2000
	gun.step(1.0, player, perception, projectiles)
	_check(projectiles.shots.is_empty() and projectiles.smoke_batches.is_empty(), "Rejected firing solutions create neither shots nor smoke.")
	enemy.position.x = 600
	gun.step(1.0, player, perception, projectiles)
	_check(projectiles.fired_count == 1 and projectiles.smoke_batches.size() == 1, "A successful shot lazily creates one shared particle batch.")
	var batch := projectiles.smoke_batches[smoke_scene]
	gun.step(1.0 / Engine.physics_ticks_per_second, player, perception, projectiles)
	_check(batch.emitted_bursts == 1, "Reloading does not repeat the smoke burst.")
	other_gun.step(1.0, enemy, perception, projectiles)
	_check(batch.emitted_bursts == 2 and projectiles.smoke_batches.size() == 1, "Different ships and opposing cannon directions reuse one batch.")
	other_gun.shot_smoke_scene = null
	other_gun.cooldown = 0.0
	other_gun.step(1.0, enemy, perception, projectiles)
	_check(projectiles.fired_count == 3 and batch.emitted_bursts == 2, "Unselected cannons still fire without smoke.")
	for tick in range(ceili(0.2 * Engine.physics_ticks_per_second)):
		await physics_frame
		projectiles.step(1.0 / Engine.physics_ticks_per_second)
	if _visual:
		await _capture("cannon-shot-smoke")
		var bounds := batch.capture_aabb()
		_check(bounds.has_volume() and bounds.size.x > 500.0, "The GPU batch contains smoke from both distant muzzle positions.")
	var old_position := batch.global_position
	var local_bounds := batch.visibility_aabb
	_origin.shift_segments(-1)
	_check(batch.visibility_aabb == local_bounds and is_equal_approx(batch.global_position.z - old_position.z, RoutePosition.SEGMENT_LENGTH), "Rebasing translates existing smoke without changing local trails or restarting bursts.")
	if _visual:
		await _capture("cannon-smoke-rebased")
	player.mounted_slots[1].assign_equipment(null)
	player.queue_free()
	await process_frame
	_check(is_instance_valid(batch) and batch.visible and batch.get_parent() == projectiles, "Smoke completes independently after its cannon and ship are removed.")
	for tick in range(ceili((batch.lifetime + 0.2) * Engine.physics_ticks_per_second)):
		await physics_frame
	_check(not batch.visible and not batch.is_physics_processing(), "Expired smoke hides and stops its update callback.")
	# A small fixture budget proves cosmetic overload cannot suppress shots.
	batch.amount = batch.puffs_per_shot * 2
	var emitted_before := batch.emitted_bursts
	var fired_before := projectiles.fired_count
	for shot in range(3):
		projectiles.fire(enemy, enemy.global_position, Vector3.UP * 1000, other_gun.weapon, smoke_scene)
	_check(projectiles.fired_count == fired_before + 3 and batch.emitted_bursts == emitted_before + 2 and batch.dropped_bursts == 1, "The shared particle budget drops excess cosmetic bursts while every projectile still fires.")
	projectiles.clear()
	_check(not batch.visible and not batch.is_physics_processing(), "Clearing projectiles also clears their transient smoke.")
	projectiles.fire(enemy, enemy.global_position, Vector3.DOWN * 1000, other_gun.weapon, smoke_scene)
	_check(batch.emitted_bursts == emitted_before + 3 and batch.visible and projectiles.smoke_batches.size() == 1, "An idle batch restarts for another shot, including vertical firing directions.")
	_fixture.queue_free()
	await process_frame
	await process_frame
	_check(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT) == orphans, "Scene teardown releases all projectile and smoke nodes.")
	for failure in _failures:
		printerr("FAIL: ", failure)
	if _failures.is_empty():
		print("PASS: cannon smoke opt-in, successful-shot triggering, shared batching, cosmetic limits, expiry, rebasing, shooter removal, and cleanup.")
	quit(0 if _failures.is_empty() else 1)


func _ship(faction: StringName, position: Vector3, id: int) -> Airship:
	var ship := KESTREL.instantiate() as Airship
	ship.faction = faction
	ship.entity_id = id
	ship.freeze = true
	_fixture.add_child(ship)
	ship.position = position
	_origin.register_root(ship)
	return ship


func _setup_view() -> void:
	var camera := Camera3D.new()
	_fixture.add_child(camera)
	camera.position = Vector3(35, 16, 44)
	camera.look_at(Vector3(4, -2, 0))
	camera.near = 0.1
	camera.current = true
	_origin.register_root(camera)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color(0.18, 0.3, 0.35)
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color.WHITE
	environment.environment.ambient_light_energy = 0.8
	_fixture.add_child(environment)
	var light := DirectionalLight3D.new()
	_fixture.add_child(light)
	light.rotation_degrees = Vector3(-45, -20, 0)


func _capture(label: String) -> void:
	var directory := OS.get_environment("AERWYTH_CAPTURE_DIR")
	_check(not directory.is_empty(), "Cannon smoke captures require an external directory.")
	await RenderingServer.frame_post_draw
	if not directory.is_empty():
		_check(root.get_texture().get_image().save_png(directory.path_join(label + ".png")) == OK, "Cannon smoke capture was written.")


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
