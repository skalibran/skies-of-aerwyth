extends SceneTree

const KESTREL := preload("res://scenes/ships/kestrel.tscn")
const TERRAIN := preload("res://scenes/terrain/voxel_terrain.tscn")
const PROFILE := preload("res://resources/terrain/journey_terrain.tres")
const CAMERA := preload("res://scenes/camera/orbit_camera.tscn")
const SMOKE := preload("res://scenes/ships/ship_death_smoke.tscn")

var _rate: int = Engine.physics_ticks_per_second
var _failures: Array[String] = []
var _fixture: Node3D
var _origin: FloatingOrigin
var _terrain: VoxelTerrain
var _wrecks: WreckController
var _visual: bool = false
var _profile: bool = false


func _initialize() -> void:
	_visual = "--visual" in OS.get_cmdline_user_args()
	_profile = "--profile" in OS.get_cmdline_user_args()
	_run.call_deferred()


func _run() -> void:
	var orphans := Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)
	await _check_surfaces()
	await _check_lifecycle()
	await _check_picking()
	await _check_smoke_markers()
	await _check_smoke_visibility()
	await process_frame
	_check(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT) == orphans, "Wrecks, terrain colliders, and scene teardown leave no orphan nodes.")
	for failure in _failures:
		printerr("FAIL: ", failure)
	if _failures.is_empty():
		print("PASS: source-grid terrain collision, wreck impacts, picking through wrecks, ship-owned smoke with removable markers, shared materials, hide/reveal and impact shutdown, bounded trails, settling, LOD visibility, rebasing, and expiry.")
	quit(0 if _failures.is_empty() else 1)


func _check_surfaces() -> void:
	var space := root.world_3d.direct_space_state
	var wall_samples := 0
	for width: int in [10, 50, 100]:
		var profile := PROFILE.duplicate(true) as TerrainProfile
		profile.voxel_size = width
		var sampler := TerrainSampler.new(profile, RoutePosition.new())
		var route := TerrainGrid.tile_start(TerrainGrid.tile_at(RoutePosition.new(-9007199254740995, 123.0), width * 8), width * 8)
		var mesh := TerrainMeshBuilder.new().build(sampler, 0, route.segment, int(route.offset), width * TerrainProfile.CELLS_PER_PATCH)
		var body := StaticBody3D.new()
		body.collision_layer = VoxelTerrain.COLLISION_LAYER
		var collider := CollisionShape3D.new()
		var shape := mesh.create_trimesh_shape()
		collider.shape = shape
		body.add_child(collider)
		root.add_child(body)
		await physics_frame
		await physics_frame
		for z in range(8):
			for x in range(8):
				var sample_route := route.advanced((z + 0.5) * width)
				var point := Vector3((x + 0.5) * width, 0, (z + 0.5) * width)
				var expected := sampler.surface_height(point.x, sample_route)
				var ray := PhysicsRayQueryParameters3D.create(point + Vector3.UP * 2000, point + Vector3.DOWN * 2000, VoxelTerrain.COLLISION_LAYER)
				var hit := space.intersect_ray(ray)
				_check(not hit.is_empty() and absf(hit.position.y - expected) < 0.001, "Collision tops match exact source columns at all voxel sizes and huge signed route indices.")
				if x == 7:
					continue
				var next := sampler.surface_height(point.x + width, sample_route)
				if next == expected:
					continue
				point.y = (expected + next) * 0.5
				var other := point + Vector3.RIGHT * width
				ray.from = point if expected < next else other
				ray.to = other if expected < next else point
				hit = space.intersect_ray(ray)
				_check(not hit.is_empty() and absf(hit.position.x - (x + 1) * width) < 0.001, "Cliff collision preserves vertical steps without smoothing them into ramps.")
				wall_samples += 1
		body.free()
	_check(wall_samples > 0, "Surface fixtures include vertical cliff contacts.")


func _check_lifecycle() -> void:
	_fixture = Node3D.new()
	root.add_child(_fixture)
	_origin = FloatingOrigin.new()
	_fixture.add_child(_origin)
	var progression := JourneyProgress.new()
	_fixture.add_child(progression)
	progression.initialize(RoutePosition.new())
	_terrain = TERRAIN.instantiate() as VoxelTerrain
	_terrain.profile = PROFILE.duplicate(true)
	_terrain.profile.grassland.height_range = Vector2(100, 300)
	_terrain.profile.mountains.height_range = Vector2(100, 300)
	_terrain.profile.grassland.height_contrast = 0
	_terrain.profile.mountains.height_contrast = 0
	_terrain.origin = _origin
	_terrain.progression = progression
	_terrain.chunk_radius = 1
	_fixture.add_child(_terrain)
	_terrain.set_process(false)
	_terrain.update_region(0, RoutePosition.new(), Vector3(0, 10000, 0))
	_terrain.build_pending(10000)
	_wrecks = WreckController.new()
	_wrecks.terrain = _terrain
	_wrecks.origin = _origin
	_fixture.add_child(_wrecks)
	var ships: Array[Airship] = []
	var count := 32 if _profile else 6
	for index in range(count):
		var ship := KESTREL.instantiate() as Airship
		_fixture.add_child(ship)
		ship.position = Vector3(250 + (index % 8) * 60, 320 + index * 20, 200 + (index / 8) * 80)
		if _profile:
			ship.position.y = 3500
		_origin.register_root(ship)
		ships.append(ship)
		_check(ship.death_smoke == null, "Living ships have positioning markers without an instantiated smoke effect.")
	await physics_frame
	await physics_frame
	for index in range(count):
		var ship := ships[index]
		ship.linear_velocity = Vector3(0, -300 if _profile else (-900 if index == 0 else 0), 0)
		ship.take_damage(ship.maximum_health, Factions.ENEMY)
		_check(is_instance_valid(ship.death_smoke) and ship.death_smoke.particles.amount == 48, "Kestrel creates one GPU system for its remaining hull marker.")
		_wrecks.register_wreck(ship)
		_check(not ship.visual_root.visible, "Wrecks are hidden immediately over coarse terrain.")
		var smoke := ship.death_smoke
		_check(not smoke.is_emitting() and not smoke.is_physics_processing() and not smoke.particles.is_visible_in_tree(), "Hidden wreck smoke suspends emission and script processing.")
		_check(ship.wreck_lifetime == 25.0, "The authored cleanup delay is 25 seconds after first ground contact.")
	_check(ships[0].death_smoke.particles.process_material == ships[1].death_smoke.particles.process_material, "Emitters share their immutable process material across ships.")
	ships[1].rotation.z = PI * 0.5
	# The running mesh remains coarse while fine replacement work is pending.
	_terrain.update_region(0, RoutePosition.new(), Vector3(400, 220, 300))
	_check(not ships[0].visual_root.visible, "Requested full detail alone cannot reveal a wreck over the old coarse layout.")
	_terrain.build_pending(10000)
	_check(ships[0].visual_root.visible, "Publishing source detail reveals the wreck without changing camera-driven selection.")
	_check(ships[0].death_smoke.particles.is_visible_in_tree(), "Published source detail reveals the smoke with its wreck.")
	_check(ships[0].death_smoke.is_emitting(), "A wreck first hidden by LOD starts emitting when source detail is published.")
	if _visual:
		_setup_view()
		await _capture("wreck-falling")
	var timings := PackedFloat64Array()
	for tick in range((45 if _profile else 36) * _rate):
		var before := Time.get_ticks_usec()
		await physics_frame
		timings.append((Time.get_ticks_usec() - before) / 1000.0)
		if tick == 0:
			var velocity := ships[0].linear_velocity
			var position_before := ships[0].global_position
			var smoke := ships[0].death_smoke
			var smoke_before := smoke.particles.global_position
			_origin.shift_segments(-1)
			_check(ships[0].linear_velocity == velocity and is_equal_approx(ships[0].global_position.z - position_before.z, RoutePosition.SEGMENT_LENGTH), "Rebasing during a fall preserves momentum and relative collision coverage.")
			_check((smoke.particles.global_position - smoke_before).is_equal_approx(ships[0].global_position - position_before), "An origin shift moves existing smoke and the wreck together without restarting emission.")
		if tick == 2 * _rate:
			var smoke := ships[1].death_smoke
			var material := smoke.particles.process_material as ParticleProcessMaterial
			_check(smoke.particles.global_basis.is_equal_approx(Basis.IDENTITY) and smoke.global_position.distance_to(smoke.particles.global_position) > 10.0 and material.emission_shape_offset == Vector3.ZERO, "A tumbling wreck moves the emission point while its smoke frame remains upright and stationary.")
			if _visual:
				await _capture("wreck-smoke-falling")
		for ship in ships:
			if is_instance_valid(ship):
				if ship.wreck_landed:
					_check(not ship.death_smoke.is_emitting() and not ship.death_smoke.is_physics_processing(), "Smoke stops on first ground contact, before settling or cleanup.")
				var axis := ship.hull_collider.global_basis.y
				var bottom := ship.hull_collider.global_position.y - absf(axis.y) * ship.hull_half_segment - ship.hull_radius
				_check(bottom > 199.0, "Fast and rotated wrecks never tunnel below the source terrain.")
		if tick == (20 if _profile else 12) * _rate:
			for ship in ships:
				_check(is_instance_valid(ship) and ship.wreck_landed and ship.freeze and ship.hull_collider.disabled, "Grounded wrecks settle, freeze, and leave collision while remaining visible scenery.")
				var smoke := ship.death_smoke
				_check(not smoke.is_emitting() and not smoke.is_physics_processing() and not smoke.particles.is_visible_in_tree(), "Landed wrecks retain no active or visible smoke.")
			_check(not _terrain.colliders.is_empty(), "Settled wrecks share the existing source terrain colliders.")
			var position_before := ships[0].global_position
			_origin.shift_segments(1)
			_check(is_equal_approx(position_before.z - ships[0].global_position.z, RoutePosition.SEGMENT_LENGTH), "Frozen wrecks still rebase.")
			if _visual:
				await _capture("wreck-settled")
			_terrain.update_region(0, RoutePosition.new(), Vector3(0, 10000, 0))
			_terrain.build_pending(10000)
			_check(not ships[0].visual_root.visible and ships[0].freeze, "Switching to coarse terrain hides frozen wrecks without resuming physics.")
			_check(not ships[0].death_smoke.particles.is_visible_in_tree(), "Settled smoke cannot remain visible over LOD terrain.")
			if _visual:
				await _capture("wreck-hidden-on-lod")
			_terrain.update_region(0, RoutePosition.new(), Vector3(400, 220, 300))
			_terrain.build_pending(10000)
			_check(ships[0].visual_root.visible, "Returning to source detail restores an unexpired frozen wreck.")
			for ship in ships:
				_check(not ship.death_smoke.is_emitting() and not ship.death_smoke.particles.is_visible_in_tree(), "LOD reveal cannot restart a landed wreck's smoke.")
		if tick == 20 * _rate:
			_check(is_instance_valid(ships[0]), "Wreck cleanup does not use the previous 15-second death timer.")
	_check(_wrecks.wrecks.is_empty() and not _wrecks.is_processing(), "Expired wrecks release membership and leave the controller idle.")
	timings.sort()
	print("WRECK_CHECK ", JSON.stringify({"wrecks": count, "source_colliders": _terrain.colliders.size(), "collider_build_max_ms": _terrain.maximum_collider_build_usec / 1000.0, "headless_frame_p95_ms": timings[int(timings.size() * 0.95)]}))
	_fixture.queue_free()
	await process_frame
	await process_frame


func _check_picking() -> void:
	var fixture := Node3D.new()
	root.add_child(fixture)
	var fleet := FleetController.new()
	fleet.anchor = Node3D.new()
	fixture.add_child(fleet.anchor)
	fixture.add_child(fleet)
	var rig := CAMERA.instantiate() as FleetCamera
	rig.fleet = fleet
	fixture.add_child(rig)
	rig.set_process(false)
	rig.set_physics_process(false)
	var ships: Array[Airship] = []
	for index in range(3):
		var ship := KESTREL.instantiate() as Airship
		ship.freeze = true
		fixture.add_child(ship)
		ship.position = Vector3.FORWARD * (index * 60)
		ships.append(ship)
	await physics_frame
	await physics_frame
	_pick_from_front(rig, ships[2].global_position)
	_check(rig.followed_ship == ships[0], "Picking still selects the closest living ship.")
	for ship in [ships[0], ships[1]]:
		ship.take_damage(ship.maximum_health, Factions.ENEMY)
	ships[0].visual_root.hide()
	_pick_from_front(rig, ships[2].global_position)
	_check(rig.followed_ship == ships[2], "Picking passes through multiple wrecks, including a hidden hull, to the living ship behind them.")
	_check(ships[0].collision_layer == 1 and ships[0].collision_mask == 3 and not ships[0].hull_collider.disabled, "Picking never changes a wreck's physical collision.")
	var island := StaticBody3D.new()
	island.collision_layer = 2
	var collider := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(30, 30, 10)
	collider.shape = shape
	island.add_child(collider)
	fixture.add_child(island)
	island.position = Vector3(0, 0, -90)
	await physics_frame
	await physics_frame
	_pick_from_front(rig, ships[2].global_position)
	_check(rig.mode == FleetCamera.Mode.FLEET, "Picking through wrecks still stops at an island before the living ship.")
	island.free()
	ships[2].take_damage(ships[2].maximum_health, Factions.ENEMY)
	_pick_from_front(rig, ships[2].global_position)
	_check(rig.mode == FleetCamera.Mode.FLEET, "A ray containing only wrecks finishes without selecting one.")
	fixture.queue_free()
	await process_frame
	await process_frame


func _pick_from_front(rig: FleetCamera, target: Vector3) -> void:
	rig.focus_fleet()
	rig.camera.global_transform = Transform3D(Basis.IDENTITY, Vector3(0, 0, 200))
	rig.pick_ship(rig.camera.unproject_position(target))


func _check_smoke_markers() -> void:
	var fixture := Node3D.new()
	root.add_child(fixture)
	# Removing a marker in the editor must not remove the effect's owner.
	var ship := KESTREL.instantiate() as Airship
	var removed := Marker3D.new()
	ship.death_smoke_points.add_child(removed)
	removed.free()
	ship.freeze = true
	fixture.add_child(ship)
	ship.take_damage(ship.maximum_health, Factions.ENEMY)
	_check(not ship.alive and is_instance_valid(ship.death_smoke) and ship.death_smoke.is_emitting(), "Removing a marker before readiness preserves destruction and smoke from the remaining marker.")
	_check(ship.death_smoke.get_parent() == ship.visual_root and ship.death_smoke.particles.amount == 48, "The ship owns one effect, with capacity based on surviving markers.")
	var hull_marker := ship.death_smoke_points.get_child(0) as Marker3D
	_check(hull_marker != null and hull_marker.get_script() == null and hull_marker.get_child_count() == 0, "Smoke markers contain only positioning, without scripts or particle children.")
	for remove_container in [false, true]:
		var empty_ship := KESTREL.instantiate() as Airship
		if remove_container:
			empty_ship.death_smoke_points.free()
		else:
			for marker in empty_ship.death_smoke_points.get_children():
				marker.free()
		empty_ship.freeze = true
		fixture.add_child(empty_ship)
		empty_ship.take_damage(empty_ship.maximum_health, Factions.ENEMY)
		_check(not empty_ship.alive and empty_ship.is_physics_processing() and empty_ship.death_smoke == null, "Removing all markers or their container still creates a wreck without smoke or an implicit origin source.")
	# Live marker removal uses lifetime signals, without per-frame tree scans.
	var multi := KESTREL.instantiate() as Airship
	var extra := Marker3D.new()
	extra.position.x = 100.0
	multi.death_smoke_points.add_child(extra)
	multi.freeze = true
	fixture.add_child(multi)
	multi.position = Vector3(0, 500, 0)
	multi.take_damage(multi.maximum_health, Factions.ENEMY)
	var effect := multi.death_smoke
	_check(effect.particles.amount == 96 and effect.particles.process_material == ship.death_smoke.particles.process_material, "Multiple markers share one system at full density and the same immutable material across ships.")
	extra.free()
	for tick in range(ceili(0.3 * _rate)):
		await physics_frame
	_check(multi.death_smoke == effect and effect.is_emitting() and effect.is_physics_processing(), "Removing one active marker leaves the ship-owned effect running at the other source.")
	multi.death_smoke_points.get_child(0).free()
	await physics_frame
	_check(not effect.is_emitting() and not effect.is_physics_processing() and not effect.particles.is_visible_in_tree(), "Removing the last active marker stops its effect safely.")
	fixture.queue_free()
	await process_frame
	await process_frame


func _check_smoke_visibility() -> void:
	var fixture := Node3D.new()
	root.add_child(fixture)
	var visual := Node3D.new()
	fixture.add_child(visual)
	var smoke := SMOKE.instantiate() as ShipDeathSmoke
	var first_point := Marker3D.new()
	visual.add_child(first_point)
	var other_point := Marker3D.new()
	other_point.position.x = 100.0
	visual.add_child(other_point)
	visual.add_child(smoke)
	visual.position = Vector3(0, 500, 0)
	visual.hide()
	visual.show()
	_check(not smoke.is_emitting() and not smoke.is_physics_processing(), "Visibility changes cannot start an emitter before death.")
	if _visual:
		var camera := Camera3D.new()
		fixture.add_child(camera)
		camera.position = Vector3(0, 400, 350)
		camera.look_at(Vector3(0, 400, 0))
		camera.current = true
		var environment := WorldEnvironment.new()
		environment.environment = Environment.new()
		environment.environment.background_mode = Environment.BG_COLOR
		environment.environment.background_color = Color(0.5, 0.7, 0.75)
		fixture.add_child(environment)
	smoke.start([first_point, other_point])
	for tick in range(3 * _rate):
		await physics_frame
	if _visual:
		await _capture("smoke-before-hidden")
		_check(smoke.particles.capture_aabb().size.y > 5.0, "The rendered regression begins with a live plume before hiding.")
		_check(smoke.particles.capture_aabb().size.x > 80.0, "One GPU system emits visible particles from both separate source positions.")
	visual.hide()
	_check(not smoke.is_emitting() and not smoke.is_physics_processing(), "Hiding a plume suspends emission and source updates.")
	visual.position.y -= 200
	visual.reset_physics_interpolation()
	for tick in range(ceili((smoke.particles.lifetime + 2.0) * _rate)):
		await physics_frame
	visual.show()
	_check(smoke.is_emitting() and smoke.is_physics_processing(), "Revealing an airborne wreck resumes its smoke.")
	_check(smoke.particles.global_position.is_equal_approx(smoke.global_position), "Revealed smoke starts at the current source, not its old position.")
	if _visual:
		for tick in range(ceili(0.3 * _rate)):
			await physics_frame
		await _capture("smoke-after-hidden")
		var bounds := smoke.particles.global_transform * smoke.particles.capture_aabb()
		_check(bounds.has_volume() and bounds.end.y < smoke.global_position.y + smoke.plume_extent, "Rendered smoke contains new puffs near the moved source and no expired puffs at its former position.")
	# Old trail positions must leave the culling bounds while the source travels.
	for tick in range(12 * _rate):
		visual.position.x += 100.0 / _rate
		await physics_frame
	var trail_bounds := smoke.particles.global_transform * smoke.particles.visibility_aabb
	_check(trail_bounds.position.x > 300.0 and trail_bounds.has_point(smoke.global_position) and trail_bounds.has_point(other_point.global_position), "Smoke bounds discard expired trail positions while retaining both moving sources.")
	smoke.stop()
	smoke.stop()
	visual.hide()
	visual.show()
	smoke.start([first_point, other_point])
	_check(not smoke.is_emitting() and not smoke.is_physics_processing() and not smoke.particles.is_visible_in_tree(), "Stopping is permanent and idempotent, including hide/reveal and repeated start calls.")
	var unstarted := SMOKE.instantiate() as ShipDeathSmoke
	visual.add_child(unstarted)
	unstarted.stop()
	unstarted.start([first_point])
	_check(not unstarted.is_emitting() and not unstarted.is_physics_processing(), "Stopping before smoke starts cannot activate it later.")
	fixture.queue_free()
	await process_frame
	await process_frame


func _setup_view() -> void:
	var camera := Camera3D.new()
	_fixture.add_child(camera)
	camera.position = Vector3(500, 340, 500)
	camera.look_at(Vector3(400, 220, 200))
	camera.near = 0.5
	camera.far = 20000
	camera.current = true
	_origin.register_root(camera)
	var light := DirectionalLight3D.new()
	_fixture.add_child(light)
	light.rotation_degrees = Vector3(-55, -30, 0)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color(0.5, 0.7, 0.75)
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color.WHITE
	environment.environment.ambient_light_energy = 0.7
	_fixture.add_child(environment)


func _capture(label: String) -> void:
	var directory := OS.get_environment("AERWYTH_CAPTURE_DIR")
	_check(not directory.is_empty(), "Wreck captures require an external directory.")
	await RenderingServer.frame_post_draw
	if not directory.is_empty():
		_check(root.get_texture().get_image().save_png(directory.path_join(label + ".png")) == OK, "Wreck capture was written.")


func _check(condition: bool, message: String) -> void:
	if not condition and message not in _failures:
		_failures.append(message)
