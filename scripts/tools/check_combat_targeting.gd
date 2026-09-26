extends SceneTree

const KESTREL := preload("res://scenes/ships/kestrel.tscn")
const JOURNEY := preload("res://scenes/world/journey.tscn")
const CANNON := preload("res://resources/weapons/rusty_cannon.tres")

class ProbeWeapon extends MountedWeapon:
	var attempts: Array[int] = []
	var reachable_id: int = -1

	func launch_for(target: Airship) -> Vector3:
		attempts.append(target.entity_id)
		return Vector3.RIGHT if target.entity_id == reachable_id else Vector3.ZERO

var _rate: int = Engine.physics_ticks_per_second
var _delta: float = 1.0 / _rate
var _failures: Array[String] = []
var _fixture: Node3D
var _projectiles: ProjectileController
var _perception := CombatPerception.new()
var _ships: Array[Airship] = []
var _next_id: int = 1


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_fixture = Node3D.new()
	root.add_child(_fixture)
	_projectiles = ProjectileController.new()
	_fixture.add_child(_projectiles)
	_check_perception()
	_clear_ships()
	_check_pending_deletion()
	_clear_ships()
	_check_shortlists()
	_clear_ships()
	_check_search_fairness()
	_clear_ships()
	_check_firing()
	_clear_ships()
	_check_staggering()
	_clear_ships()
	_check_conservative_cone()
	_clear_ships()
	await _check_journey_cleanup()
	_fixture.queue_free()
	await process_frame
	for failure in _failures:
		printerr("FAIL: ", failure)
	if _failures.is_empty():
		print("PASS: shared combat queries, bounded ranking, search fairness, firing cadence, cone rejection, and Journey target/equipment cleanup.")
	quit(0 if _failures.is_empty() else 1)


func _ship(position: Vector3, faction: StringName = Factions.ENEMY) -> Airship:
	var ship := KESTREL.instantiate() as Airship
	ship.entity_id = _next_id
	_next_id += 1
	ship.faction = faction
	ship.freeze = true
	_fixture.add_child(ship)
	ship.global_position = position
	_ships.append(ship)
	return ship


func _clear_ships() -> void:
	_projectiles.clear()
	for ship in _ships:
		ship.free()
	_ships.clear()
	_perception.rebuild(_ships)


func _check_perception() -> void:
	var player := _ship(Vector3.ZERO, Factions.PLAYER)
	for index in range(48):
		@warning_ignore("integer_division")
		var row := index / 4
		_ship(Vector3((index % 4) * 650 - 1000, (index % 3) * 800 - 800, row * 250 - 1500), Factions.PLAYER if index % 5 == 0 else Factions.ENEMY)
	for shift in [Vector3.ZERO, Vector3(0, 0, 10240)]:
		for ship in _ships:
			ship.position += shift
		_perception.rebuild(_ships)
		for radius in [10.0, 1000.0, 2300.0]:
			var nearby: Array[Airship] = []
			_perception.nearby_hostiles(player.global_position, radius, player.faction, nearby)
			var expected: Array[Airship] = []
			for other in _ships:
				if Factions.are_hostile(player.faction, other.faction) and other.global_position.distance_squared_to(player.global_position) <= radius * radius:
					expected.append(other)
			_check(nearby.size() == expected.size(), "Spatial query count matches the full scan at altitude/cell boundaries and after rebasing.")
			for other in expected:
				_check(other in nearby, "Spatial queries do not omit eligible opponents.")
	var slot := player.mounted_slots[1]
	slot.position.x = 250.0
	var edge := _ship(player.global_position + Vector3.RIGHT * 1200)
	_perception.rebuild(_ships)
	var queries := _perception.query_count
	var candidates := _perception.weapon_candidates(player)
	_perception.weapon_candidates(player)
	_check(edge in candidates and _perception.query_count == queries + 1, "Mounts share one query including muzzle offset reach.")
	_perception.forget(edge)
	_check(not _perception.is_hostile(player, edge) and edge not in _perception.weapon_candidates(player), "Removal immediately invalidates membership and cached queries.")
	_perception.rebuild(_ships)
	_check(_perception.is_hostile(player, edge), "Re-registration in a new snapshot restores eligibility.")
	edge.alive = false
	_check(not _perception.is_hostile(player, edge), "Death invalidates a target before the next registry rebuild.")
	edge.alive = true
	edge.queue_free()
	_check(not _perception.is_hostile(player, edge), "Queued deletion immediately invalidates a target.")


func _check_shortlists() -> void:
	var player := _ship(Vector3.ZERO, Factions.PLAYER)
	var weapon := player.mounted_slots[1].equipment as MountedWeapon
	for index in range(12):
		# Coincident pairs exercise the stable-ID tie break exactly.
		@warning_ignore("integer_division")
		var pair := index / 2
		_ship(Vector3(200 + pair * 50, 0, 0))
	for shift in [Vector3.ZERO, Vector3(0, 0, -10240)]:
		for ship in _ships:
			ship.position += shift
		_ships.reverse()
		_perception.rebuild(_ships)
		var expected: Array[Airship] = []
		for other in _ships:
			if other != player:
				expected.append(other)
		expected.sort_custom(func(first: Airship, second: Airship) -> bool:
			var a := weapon.global_position.distance_squared_to(first.global_position)
			var b := weapon.global_position.distance_squared_to(second.global_position)
			return first.entity_id < second.entity_id if a == b else a < b
		)
		for budget in range(1, 5):
			var remaining := weapon._collect_shortlist(player, _perception, null, null, budget)
			_check(remaining == expected.size() and weapon._shortlist.size() == budget, "Shortlists stay bounded by the remaining attempt budget.")
			for index in range(budget):
				_check(weapon._shortlist[index] == expected[index], "Bounded ranking matches full sorting, including ties, input order, and rebasing.")


func _check_pending_deletion() -> void:
	var player := _ship(Vector3.ZERO, Factions.PLAYER)
	var removed := _ship(Vector3.RIGHT * 300)
	var alternative := _ship(Vector3.RIGHT * 600)
	var fleet := FleetController.new()
	fleet.anchor = Node3D.new()
	_fixture.add_child(fleet.anchor)
	_fixture.add_child(fleet)
	removed.queue_free()
	var weapon := player.mounted_slots[1].equipment as MountedWeapon
	_check(weapon.launch_for(removed) == Vector3.ZERO, "Direct launch validation rejects a target queued for deletion.")
	_check(player.combat.prepare(0.2, player, _ships, fleet) and player.combat.target == alternative, "Pursuit skips queued deletion and selects the next living opponent in the same tick.")
	fleet.anchor.free()
	fleet.free()


func _check_search_fairness() -> void:
	var player := _ship(Vector3.ZERO, Factions.PLAYER)
	var slot := player.mounted_slots[1]
	slot.assign_equipment(null)
	var probe := ProbeWeapon.new()
	probe.definition = CANNON
	probe.aim_pivot = Node3D.new()
	probe.add_child(probe.aim_pivot)
	probe.slot = slot
	slot.equipment = probe
	slot.add_child(probe)
	for index in range(10):
		_ship(Vector3(150 + index * 50, 0, 0))
	var farthest: Airship = _ships.back()
	probe.reachable_id = farthest.entity_id
	for search in range(3):
		_perception.rebuild(_ships)
		var before := probe.attempts.size()
		probe.step(0.2, player, _perception, _projectiles)
		_check(probe.attempts.size() - before <= MountedWeapon.SOLVE_BUDGET, "Each search keeps the total target-attempt budget.")
		# Change distance order between searches. A list cursor would repeat work.
		for index in range(1, _ships.size() - 1):
			_ships[index].position.x = 150 + ((index + search * 3) % 8) * 50
	_check(probe.shots_fired == 1 and probe.firing_target == farthest and probe.attempts.size() == 10, "Failed-attempt history reaches a farther target despite reordered distances.")
	probe.forget(farthest)
	_perception.forget(farthest)
	_check(probe.firing_target == null and farthest not in probe._shortlist, "Removed targets leave retention and shortlist state.")
	# Exhaustion restarts fairly; vanished remaining targets cannot stall a sweep.
	probe.cooldown = 0
	probe.attempts.clear()
	probe.reachable_id = _ships[1].entity_id
	_ships[1].position.x = 100.0
	for index in range(1, _ships.size() - 1):
		probe._searched_candidates[_ships[index].get_instance_id()] = true
	probe.step(0.2, player, _perception, _projectiles)
	_check(probe.firing_target == _ships[1] and probe.attempts.size() <= MountedWeapon.SOLVE_BUDGET, "An exhausted or vanished remainder wraps to newly reachable candidates.")
	for ship in _ships:
		if ship != player:
			_perception.forget(ship)
	probe.forget(_ships[1])
	probe.cooldown = 0
	probe.step(0.2, player, _perception, _projectiles)
	_check(probe.firing_target == null and probe._shortlist.is_empty() and probe._searched_candidates.is_empty(), "Empty searches release transient candidate state.")


func _check_firing() -> void:
	var player := _ship(Vector3.ZERO, Factions.PLAYER)
	var target := _ship(Vector3(600, 0, 0))
	var slot := player.mounted_slots[1]
	var weapon := slot.equipment as MountedWeapon
	weapon.definition = CANNON.duplicate()
	weapon.weapon.reload_seconds = 0.1
	weapon.cooldown = 0
	weapon._search_time = 0
	weapon.firing_target = null
	var shots := weapon.shots_fired
	var searches := weapon.search_count
	for tick in range(_rate):
		_perception.rebuild(_ships)
		weapon.step(_delta, player, _perception, _projectiles)
	_check(weapon.shots_fired - shots == 10 and weapon.search_count - searches == 5, "Ten-shot/s firing is independent of five acquisitions/s at the project physics rate.")
	_projectiles.clear()
	var closer := _ship(Vector3(400, 0, 0))
	_perception.rebuild(_ships)
	weapon.step(1.0, player, _perception, _projectiles)
	_check(weapon.firing_target == target, "A closer passer alone does not replace a usable firing target.")
	player.combat.target = closer
	weapon.step(1.0, player, _perception, _projectiles)
	_check(weapon.firing_target == closer and player.combat.target == closer, "A shootable main target takes preference without weapon-side pursuit changes.")
	shots = weapon.shots_fired
	closer.linear_velocity = Vector3.RIGHT * 3000
	weapon.cooldown = 0
	weapon._search_time = 1.0
	weapon.step(0.1, player, _perception, _projectiles)
	_check(weapon.shots_fired == shots and weapon.firing_target == null, "Retained targets use fresh motion and a fresh ballistic solution before each shot.")
	slot.fire_at_targets_in_range = false
	weapon.step(1.0, player, _perception, _projectiles)
	_check(weapon.shots_fired == shots, "Main-target-only mode rejects passers when its main target is unreachable.")
	weapon.step(0.0, player, _perception, _projectiles)
	_check(weapon.shots_fired == shots, "Zero-duration steps cannot fire.")


func _check_staggering() -> void:
	var players: Array[Airship] = []
	for index in range(12):
		players.append(_ship(Vector3.ZERO, Factions.PLAYER))
	var target := _ship(Vector3.RIGHT * 600)
	var peak_searches: int = 0
	var total_searches: int = 0
	for player in players:
		var weapon := player.mounted_slots[1].equipment as MountedWeapon
		weapon.cooldown = 0
		weapon._previous_main = null
		weapon.firing_target = null
		weapon.initialize_phase(player.entity_id, 1)
		player.combat.target = target
	for tick in range(int(0.2 * _rate)):
		_perception.rebuild(_ships)
		var searches: int = 0
		for player in players:
			var weapon := player.mounted_slots[1].equipment as MountedWeapon
			var before := weapon.search_count
			weapon.step(_delta, player, _perception, _projectiles)
			searches += weapon.search_count - before
		peak_searches = maxi(peak_searches, searches)
		total_searches += searches
	_check(total_searches == 12 and peak_searches <= 3, "Simultaneous pursuit acquisition preserves staggered weapon searches at the project physics rate.")
	_projectiles.clear()
	# Removing a shared firing target must preserve the same phase guarantees.
	for player in players:
		var weapon := player.mounted_slots[1].equipment as MountedWeapon
		weapon.initialize_phase(player.entity_id, 1)
		var deadline := weapon._search_time
		weapon.forget(target)
		_check(weapon.firing_target == null and weapon._search_time == deadline, "Target removal preserves staggered acquisition instead of synchronizing ready weapons.")


func _check_conservative_cone() -> void:
	var player := _ship(Vector3.ZERO, Factions.PLAYER)
	var target := _ship(Vector3.RIGHT * 500)
	var slot := player.mounted_slots[1]
	var weapon := slot.equipment as MountedWeapon
	weapon.definition = CANNON.duplicate()
	var rng := RandomNumberGenerator.new()
	rng.seed = 92017
	var accepted: int = 0
	for sample in range(900):
		weapon.weapon.launch_speed = [200.0, 400.0, 1000.0][sample % 3]
		weapon.weapon.gravity = rng.randf_range(10.0, 120.0)
		slot.rotation = Vector3(rng.randf_range(-0.6, 0.6), rng.randf_range(-PI, PI), 0)
		target.position = Vector3(rng.randf_range(-900, 900), rng.randf_range(-300, 300), rng.randf_range(-900, 900))
		target.linear_velocity = Vector3(rng.randf_range(-80, 80), rng.randf_range(-30, 30), rng.randf_range(-80, 80))
		var relative := target.global_position - weapon.global_position
		var time := Ballistics.intercept_time(relative, target.linear_velocity, weapon.weapon.launch_speed, weapon.weapon.gravity, weapon.weapon.lifetime)
		if time <= 0 or relative.length() > weapon.weapon.range_units or (relative + target.linear_velocity * time).length() > weapon.weapon.range_units:
			continue
		var launch := Ballistics.launch_velocity(relative, target.linear_velocity, weapon.weapon.gravity, time)
		if slot.accepts_direction(launch):
			accepted += 1
			_check(weapon.launch_for(target) != Vector3.ZERO, "Cheap cone rejection never excludes a shot accepted by the independent full solver.")
	_check(accepted > 30, "The seeded cone comparison covers reachable moving/elevated shots.")


func _check_journey_cleanup() -> void:
	# Earlier isolated fixtures may still have detached equipment queued for deletion.
	await process_frame
	var orphans := Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)
	for cycle in range(2):
		var journey := JOURNEY.instantiate() as Journey
		root.add_child(journey)
		journey.set_physics_process(false)
		for ship in journey.ships:
			ship.freeze = true
		var player := journey.ships[0]
		var slot := player.mounted_slots[1]
		for removal in range(3):
			var enemy := KESTREL.instantiate() as Airship
			enemy.entity_id = journey.allocate_ship_id()
			enemy.faction = Factions.ENEMY
			enemy.freeze = true
			enemy.wreck_airborne_lifetime = 0.25
			journey.add_child(enemy)
			enemy.global_position = player.global_position + Vector3.RIGHT * 600
			journey.register_ship(enemy)
			journey.combat_perception.rebuild(journey.ships)
			player.combat.target = enemy
			var weapon := slot.equipment as MountedWeapon
			weapon.cooldown = 0.0
			slot.step(1.0, player, journey.combat_perception, journey.projectiles)
			_check(weapon.firing_target == enemy, "Composed Journey wires registered targets into mounted firing.")
			journey.combat_perception.weapon_candidates(player)
			# Removal must use the recorded cell, not a potentially changed position.
			enemy.global_position += Vector3.RIGHT * 5000
			if removal == 0:
				journey.camera_rig.follow_ship(enemy)
				enemy.take_damage(enemy.maximum_health, Factions.PLAYER)
				_check(not journey.combat_perception.is_hostile(player, enemy), "Lethal damage invalidates perception before deferred unregistering.")
				journey.step_simulation(0.0)
				_check(not enemy.is_queued_for_deletion() and enemy.collision_layer == 1 and enemy.collision_mask == (3 | VoxelTerrain.COLLISION_LAYER), "Death retains the wreck's physical hull after unregistering combat membership.")
				journey.camera_rig.follow_ship(enemy)
				_check(journey.camera_rig.mode == FleetCamera.Mode.FLEET, "Death restores fleet focus immediately and wrecks cannot be selected again.")
				var relative_position := enemy.global_position - journey.fleet.anchor.global_position
				journey.origin.shift_segments(-1)
				_check((enemy.global_position - journey.fleet.anchor.global_position).distance_to(relative_position) < 0.001, "Unregistered wrecks still move with the floating origin.")
				journey.origin.shift_segments(1)
				var roots_with_wreck := journey.origin._roots.size()
				for tick in range(ceili(0.4 * _rate)):
					await physics_frame
				await process_frame
				_check(not is_instance_valid(enemy) and journey.origin._roots.size() == roots_with_wreck - 1, "Wreck expiry frees its body and origin subscription.")
			elif removal == 1:
				journey.unregister_ship(enemy)
				_check(not journey.combat_perception.is_hostile(player, enemy), "Explicit unregistering invalidates an otherwise living target.")
				enemy.queue_free()
			else:
				enemy.queue_free()
			await process_frame
			_check(journey.ships.size() == 3 and not player.combat.has_target() and weapon.firing_target == null, "Death, explicit unregistering, and external deletion clear registry, pursuit, and firing references.")
			_check(weapon._shortlist.is_empty() and journey.combat_perception.weapon_candidates(player).is_empty(), "Removed targets cannot survive in shortlist or query caches.")
			_check(slot.assign_equipment(slot.equipment_scene), "A mounted weapon can be replaced after target cleanup.")
			await process_frame
			_check(not is_instance_valid(weapon), "Replacing equipment releases the former weapon instance.")
		# Leave live projectiles present to exercise owner-driven scene teardown.
		_check(journey.projectiles.shots.size() == 3, "Shots survive their target's removal until impact, expiry, or owner exit.")
		journey.queue_free()
		await process_frame
		await process_frame
		_check(not is_instance_valid(journey) and Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT) == orphans, "Repeated Journey teardown releases ships, equipment, projectile visuals, and subscriptions without orphan nodes.")


func _check(condition: bool, message: String) -> void:
	if not condition and message not in _failures:
		_failures.append(message)
