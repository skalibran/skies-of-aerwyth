class_name Journey
extends Node3D

enum StepPhase { DECISIONS, AVOIDANCE, ISLAND_NAVIGATION, FORCE_SUBMISSION, PROJECTILES, WEAPONS, CLEANUP_STREAMING }

@export var initial_ships: Array[Airship] = []
@export var fleet: FleetController
@export var origin: FloatingOrigin
@export var island_spawner: IslandSpawner
@export var camera_rig: FleetCamera
@export var terrain: VoxelTerrain
@export var water: WaterSurface
@export var progression: JourneyProgress
@export var projectiles: ProjectileController
@export var combat_spawner: CombatSpawner
@export var combat_enabled: bool = true

var ships: Array[Airship] = []
var _positions := PackedVector3Array()
var _velocities := PackedVector3Array()
var _axes := PackedVector3Array()
var _corrections := PackedVector3Array()
var _stream_timer: float = 0.0
var _next_ship_id: int = 1
var _dead_ships: Array[Airship] = []
var destroyed_count: int = 0
var profile_steps: bool = false
var step_timings_usec := PackedInt64Array()
var _avoidance := ShipAvoidance.new()
var combat_perception := CombatPerception.new()


func _ready() -> void:
	step_timings_usec.resize(StepPhase.size())
	for ship in initial_ships:
		register_ship(ship)
	fleet.initialize_anchor()
	progression.initialize(anchor_route_position())
	origin.register_root(fleet.anchor)
	origin.register_root(fleet.average_focus)
	origin.register_root(camera_rig)
	origin.register_root(water)
	origin.register_root(projectiles)
	water.recenter(fleet.anchor.global_position)
	camera_rig.focus_fleet()
	terrain.update_region(fleet.anchor.global_position.x, anchor_route_position(), camera_rig.camera.global_position)
	island_spawner.initialize(anchor_route_position())
	island_spawner.update_region(anchor_route_position())


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
		fleet.advance(0.0)
		return
	if combat_enabled:
		combat_spawner.step(delta, self)
	_snapshot_ships()
	fleet.advance(delta)
	if combat_enabled:
		combat_perception.rebuild(ships)
	for ship in ships:
		ship.combat_engaged = combat_enabled and ship.combat.prepare(delta, ship, ships, fleet)
		if not ship.combat_engaged:
			if ship in fleet.members:
				ship.prepare_travel(delta, fleet.anchor.global_position, fleet.velocity)
			elif ship.faction == Factions.ENEMY:
				ship.set_preferred_velocity(Vector3.ZERO)
	if profile_steps:
		step_timings_usec[StepPhase.DECISIONS] = Time.get_ticks_usec() - measured_at
		measured_at = Time.get_ticks_usec()
	_avoidance.calculate(ships, _positions, _velocities, _axes, _corrections)
	if profile_steps:
		step_timings_usec[StepPhase.AVOIDANCE] = Time.get_ticks_usec() - measured_at
		measured_at = Time.get_ticks_usec()
		step_timings_usec[StepPhase.ISLAND_NAVIGATION] = 0
	# Submit control once per engine tick. Hull motion/contact solving happens in
	# native physics; queries below still use the latest completed body state.
	for index in range(ships.size()):
		ships[index].apply_movement_forces(delta, _corrections[index], island_spawner.navigation_candidates(ships[index]), profile_steps)
		if profile_steps:
			step_timings_usec[StepPhase.ISLAND_NAVIGATION] += ships[index].navigation_time_usec
	if profile_steps:
		step_timings_usec[StepPhase.FORCE_SUBMISSION] = Time.get_ticks_usec() - measured_at - step_timings_usec[StepPhase.ISLAND_NAVIGATION]
		measured_at = Time.get_ticks_usec()
	if combat_enabled:
		projectiles.step(delta)
	if profile_steps:
		step_timings_usec[StepPhase.PROJECTILES] = Time.get_ticks_usec() - measured_at
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
	origin.recenter_if_needed(fleet.anchor.global_position.z)
	water.recenter(fleet.anchor.global_position)
	progression.update(anchor_route_position())
	_stream_timer -= delta
	if _stream_timer <= 0.0:
		_stream_timer = 0.25
		island_spawner.update_region(anchor_route_position())
		terrain.update_region(fleet.anchor.global_position.x, anchor_route_position(), camera_rig.camera.global_position)
	if profile_steps:
		step_timings_usec[StepPhase.CLEANUP_STREAMING] = Time.get_ticks_usec() - measured_at


func allocate_ship_id() -> int:
	var result := _next_ship_id
	_next_ship_id += 1
	return result


func _on_ship_died(ship: Airship) -> void:
	_dead_ships.append(ship)


func _remove_dead_ships() -> void:
	while not _dead_ships.is_empty():
		var ship: Airship = _dead_ships.back()
		unregister_ship(ship)
		ship.collision_layer = 0
		ship.collision_mask = 0
		ship.queue_free()
		destroyed_count += 1


func anchor_route_position() -> RoutePosition:
	return RoutePosition.from_scene(fleet.anchor.global_position.z, origin.segment)


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
