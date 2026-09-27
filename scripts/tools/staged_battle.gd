class_name StagedBattle
extends Journey

const FACTIONS: Array[StringName] = [Factions.PLAYER, Factions.ENEMY]

@export_group("Battle Setup")
@export_range(1, 300) var faction_limit: int = 100
@export_range(1, 8) var spawns_per_faction_per_tick: int = 2
## Reuses composition and placement randomness for comparisons. Zero varies each run.
@export var battle_seed: int = 715932

var _battle_rng := RandomNumberGenerator.new()
var _battle_probe := SphereShape3D.new()
var _battle_query := PhysicsShapeQueryParameters3D.new()
var _battle_retry: float = 0.0


func _ready() -> void:
	super._ready()
	for ship in ships.duplicate():
		unregister_ship(ship)
		ship.queue_free()
	initial_ships.clear()
	if battle_seed == 0:
		_battle_rng.randomize()
	else:
		_battle_rng.seed = battle_seed
	_battle_query.shape = _battle_probe
	_battle_query.collision_mask = 3


func step_simulation(delta: float) -> void:
	if delta > 0.0:
		_battle_retry = maxf(0.0, _battle_retry - delta)
		if is_zero_approx(_battle_retry):
			_top_up_battle()
	super.step_simulation(delta)


func _top_up_battle() -> void:
	if available_ships.is_empty():
		return
	var living: Dictionary[StringName, int] = {Factions.PLAYER: 0, Factions.ENEMY: 0}
	for ship in ships:
		if ship.alive and not ship.is_queued_for_deletion() and living.has(ship.faction):
			living[ship.faction] += 1
	for faction in FACTIONS:
		for index in range(mini(spawns_per_faction_per_tick, maxi(0, faction_limit - living[faction]))):
			if not _spawn_battle_ship(faction):
				_battle_retry = 0.5
				break


func _spawn_battle_ship(faction: StringName) -> bool:
	var definition := available_ships[_battle_rng.randi_range(0, available_ships.size() - 1)]
	var ship := definition.scene.instantiate() as Airship
	var capsule := ship.hull_collider.shape as CapsuleShape3D
	var hull := capsule.height * 0.5
	_battle_probe.radius = hull + ShipNavigation.HULL_CLEARANCE
	var extent := fleet.radius * 0.7
	for attempt in range(32):
		var offset := Vector3(_battle_rng.randf_range(-extent, extent), _battle_rng.randf_range(-extent * 0.5, extent * 0.5), _battle_rng.randf_range(-extent, extent))
		if offset.length() > extent:
			continue
		var location := fleet.marker.global_position + offset
		_battle_query.transform = Transform3D(Basis.IDENTITY, location)
		if not get_world_3d().direct_space_state.intersect_shape(_battle_query, 1).is_empty():
			continue
		# Newly registered hulls also reserve space before the next native physics tick.
		var clear := true
		for other in ships:
			var clearance := hull + other.hull_radius + other.hull_half_segment + ShipNavigation.HULL_CLEARANCE
			if location.distance_squared_to(other.global_position) < clearance * clearance:
				clear = false
				break
		if not clear:
			continue
		ship.entity_id = allocate_ship_id()
		ship.faction = faction
		ship.position = to_local(location)
		add_child(ship)
		ship.linear_velocity = fleet.velocity
		register_ship(ship)
		ship.reset_physics_interpolation()
		ship_spawned.emit(ship)
		return true
	ship.free()
	return false
