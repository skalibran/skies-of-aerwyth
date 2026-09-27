class_name Journey
extends Node3D

signal ship_spawned(ship: Airship)
signal ship_spawn_failed(definition: ShipDefinition)

enum StepPhase { DECISIONS, AVOIDANCE, NAVIGATION, FORCE_SUBMISSION, PROJECTILES, WEAPONS, CLEANUP_STREAMING }

@export var initial_ships: Array[Airship] = []
@export var available_ships: Array[ShipDefinition] = []
@export var fleet: FleetController
@export var origin: FloatingOrigin
@export var island_spawner: IslandSpawner
@export var clouds: CloudSpawner
@export var camera_rig: FleetCamera
@export var terrain: VoxelTerrain
@export var water: WaterSurface
@export var progression: JourneyProgress
@export var projectiles: ProjectileController
@export var wreck_controller: WreckController
@export var encounters: EncounterDirector
@export var combat_enabled: bool = true
## Bound picker instantiation work. Excess requests remain queued in order.
@export_range(1, 8, 1) var friendly_spawns_per_tick: int = 2

var ships: Array[Airship] = []
var _positions := PackedVector3Array()
var _velocities := PackedVector3Array()
var _axes := PackedVector3Array()
var _corrections := PackedVector3Array()
var _stream_timer: float = 0.0
var _next_ship_id: int = 1
var _dead_ships: Array[Airship] = []
var _spawn_requests: Array[ShipDefinition] = []
var _spawn_rng := RandomNumberGenerator.new()
var _enemy_spawn_rng := RandomNumberGenerator.new()
var destroyed_count: int = 0
var profile_steps: bool = false
var step_timings_usec := PackedInt64Array()
var _avoidance := ShipAvoidance.new()
var combat_perception := CombatPerception.new()


func _ready() -> void:
	_spawn_rng.randomize()
	_enemy_spawn_rng.randomize()
	step_timings_usec.resize(StepPhase.size())
	for ship in initial_ships:
		register_ship(ship)
	fleet.initialize()
	progression.initialize(marker_route_position())
	origin.register_root(fleet.marker)
	origin.register_root(camera_rig)
	origin.register_root(water)
	origin.register_root(projectiles)
	water.recenter(fleet.marker.global_position)
	camera_rig.focus_fleet()
	terrain.update_region(fleet.marker.global_position.x, marker_route_position(), camera_rig.camera.global_position)
	island_spawner.initialize(marker_route_position())
	island_spawner.update_region(marker_route_position())
	if clouds != null:
		clouds.initialize(fleet.marker.global_position.x, marker_route_position())


func _physics_process(delta: float) -> void:
	step_simulation(delta)


func register_ship(ship: Airship) -> void:
	if ship in ships:
		return
	for other in ships:
		assert(other.entity_id != ship.entity_id, "Each ship needs a unique stable ID.")
	ships.append(ship)
	_next_ship_id = maxi(_next_ship_id, ship.entity_id + 1)
	origin.register_root(ship)
	fleet.register_ship(ship)
	ship.navigation.initialize(fleet, ship)
	ship.tree_exiting.connect(unregister_ship.bind(ship), CONNECT_ONE_SHOT)
	ship.died.connect(_on_ship_died)
	_resize_snapshots()


func unregister_ship(ship: Airship) -> void:
	ships.erase(ship)
	combat_perception.forget(ship)
	_dead_ships.erase(ship)
	for other in ships:
		other.combat.forget(ship)
		for slot in other.mounted_slots:
			var mounted := slot.equipment as MountedWeapon
			if mounted != null:
				mounted.forget(ship)
	if ship.died.is_connected(_on_ship_died):
		ship.died.disconnect(_on_ship_died)
	var callback := unregister_ship.bind(ship)
	if ship.tree_exiting.is_connected(callback):
		ship.tree_exiting.disconnect(callback)
	fleet.unregister_ship(ship)
	origin.unregister_root(ship)
	_resize_snapshots()


func step_simulation(delta: float) -> void:
	var measured_at: int = Time.get_ticks_usec() if profile_steps else 0
	_remove_dead_ships()
	if delta <= 0.0:
		# Refresh registries without submitting forces or firing ready weapons.
		return
	_spawn_requested_ships()
	if encounters != null:
		encounters.step(delta, self)
	_snapshot_ships()
	var battle := encounters.is_combat_active(self) if encounters != null else false
	fleet.prepare_step(delta, battle)
	if combat_enabled:
		combat_perception.rebuild(ships)
	for ship in ships:
		ship.prepare_navigation(delta, ships, fleet, combat_enabled)
	if profile_steps:
		step_timings_usec[StepPhase.DECISIONS] = Time.get_ticks_usec() - measured_at
		measured_at = Time.get_ticks_usec()
	_avoidance.calculate(ships, _positions, _velocities, _axes, _corrections)
	if profile_steps:
		step_timings_usec[StepPhase.AVOIDANCE] = Time.get_ticks_usec() - measured_at
		measured_at = Time.get_ticks_usec()
		step_timings_usec[StepPhase.NAVIGATION] = 0
	# Plan against intended travel, then let friendly route limits set this tick's
	# marker speed. A stopped marker must not make its obstructed route look clear.
	for ship in ships:
		ship.navigation.plan(ship, island_spawner.navigation_candidates(ship))
	fleet.advance(delta)
	if profile_steps:
		step_timings_usec[StepPhase.NAVIGATION] = Time.get_ticks_usec() - measured_at
		measured_at = Time.get_ticks_usec()
	# Resolve lethal hits before submitting this tick's control forces.
	if combat_enabled:
		projectiles.step(delta)
	if profile_steps:
		step_timings_usec[StepPhase.PROJECTILES] = Time.get_ticks_usec() - measured_at
		measured_at = Time.get_ticks_usec()
	# Submit control once per engine tick. Hull motion/contact solving happens in
	# native physics. Queries below still use the latest completed body state.
	var steering_usec: int = 0
	for index in range(ships.size()):
		ships[index].apply_movement_forces(delta, _corrections[index], island_spawner.navigation_candidates(ships[index]), profile_steps)
		if profile_steps:
			steering_usec += ships[index].navigation_time_usec
	if profile_steps:
		step_timings_usec[StepPhase.NAVIGATION] += steering_usec
		step_timings_usec[StepPhase.FORCE_SUBMISSION] = Time.get_ticks_usec() - measured_at - steering_usec
		measured_at = Time.get_ticks_usec()
	if combat_enabled:
		for ship in ships:
			if ship.alive:
				for slot in ship.mounted_slots:
					slot.step(delta, ship, combat_perception, projectiles)
	if profile_steps:
		step_timings_usec[StepPhase.WEAPONS] = Time.get_ticks_usec() - measured_at
		measured_at = Time.get_ticks_usec()
	_remove_dead_ships()
	origin.recenter_if_needed(fleet.marker.global_position.z)
	water.recenter(fleet.marker.global_position)
	progression.update(marker_route_position())
	_stream_timer -= delta
	if _stream_timer <= 0.0:
		_stream_timer = 0.25
		island_spawner.update_region(marker_route_position())
		terrain.update_region(fleet.marker.global_position.x, marker_route_position(), camera_rig.camera.global_position)
		if clouds != null:
			clouds.update_region(fleet.marker.global_position.x, marker_route_position())
	if profile_steps:
		step_timings_usec[StepPhase.CLEANUP_STREAMING] = Time.get_ticks_usec() - measured_at


func allocate_ship_id() -> int:
	var result := _next_ship_id
	_next_ship_id += 1
	return result


func request_ship_spawn(definition: ShipDefinition) -> void:
	if definition != null and definition in available_ships and definition.scene != null:
		_spawn_requests.append(definition)


func _spawn_requested_ships() -> void:
	# GUI requests enter the world at a physics boundary before snapshots are built.
	for index in range(mini(friendly_spawns_per_tick, _spawn_requests.size())):
		var definition: ShipDefinition = _spawn_requests.pop_front()
		if not _spawn_ship(definition, Factions.PLAYER):
			ship_spawn_failed.emit(definition)


func try_spawn_enemy(definition: ShipDefinition) -> bool:
	return _spawn_ship(definition, Factions.ENEMY)


func _spawn_ship(definition: ShipDefinition, faction: StringName) -> bool:
	var instance := definition.scene.instantiate()
	var ship := instance as Airship
	if ship == null:
		instance.free()
		push_error("Ship definitions must reference an Airship scene: " + definition.display_name)
		return false
	var rng := _enemy_spawn_rng if faction == Factions.ENEMY else _spawn_rng
	var location := ShipSpawnPlacement.find_position(self, ship, faction, rng)
	if not location.is_finite():
		ship.free()
		return false
	ship.entity_id = allocate_ship_id()
	ship.faction = faction
	ship.position = to_local(location)
	var from_party := location - fleet.marker.global_position
	ship.rotation.y = atan2(from_party.x, from_party.z)
	add_child(ship)
	if faction == Factions.PLAYER:
		ship.linear_velocity = fleet.velocity
	register_ship(ship)
	ship.reset_physics_interpolation()
	ship_spawned.emit(ship)
	return true


func _on_ship_died(ship: Airship) -> void:
	_dead_ships.append(ship)


func _remove_dead_ships() -> void:
	while not _dead_ships.is_empty():
		var ship: Airship = _dead_ships.back()
		unregister_ship(ship)
		# Wrecks leave gameplay registries but still collide and rebase until expiry.
		origin.register_root(ship)
		wreck_controller.register_wreck(ship)
		destroyed_count += 1


func marker_route_position() -> RoutePosition:
	return RoutePosition.from_scene(fleet.marker.global_position.z, origin.segment)


func _snapshot_ships() -> void:
	for index in range(ships.size()):
		_positions[index] = ships[index].global_position
		_velocities[index] = ships[index].linear_velocity
		_axes[index] = ships[index].global_basis.z


func _resize_snapshots() -> void:
	_positions.resize(ships.size())
	_velocities.resize(ships.size())
	_axes.resize(ships.size())
	_corrections.resize(ships.size())
