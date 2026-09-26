class_name CombatSpawner
extends Node

const FACTIONS: Array[StringName] = [Factions.PLAYER, Factions.ENEMY]

@export var ship_scene: PackedScene
@export var enabled: bool = true
@export_range(1.0, 60.0) var interval: float = 1.0
@export_range(1, 30) var batch_size: int = 10
@export_range(1, 300) var faction_limit: int = 100
@export var spawn_radius := Vector2(1000.0, 1500.0)
@export_range(0.0, 5000.0) var altitude_spread: float = 1500.0
@export var random_seed: int = 148931

var remaining: float = 1.0
var spawned_count: int = 0
var batches: int = 0
var rng := RandomNumberGenerator.new()
var _probe := SphereShape3D.new()
var _query := PhysicsShapeQueryParameters3D.new()


func _ready() -> void:
	remaining = interval
	rng.seed = random_seed
	# A conservative sphere covers the 100-meter hull in any initial orientation.
	_probe.radius = 90.0
	_query.shape = _probe
	_query.collision_mask = 3


func step(delta: float, journey: Journey) -> void:
	if not enabled:
		return
	remaining -= delta
	if remaining > 0.000001:
		return
	remaining = interval
	batches += 1
	var living: Dictionary[StringName, int] = {Factions.PLAYER: 0, Factions.ENEMY: 0}
	for ship in journey.ships:
		if ship.alive and living.has(ship.faction):
			living[ship.faction] += 1
	for faction in FACTIONS:
		for index in range(mini(batch_size, maxi(0, faction_limit - living[faction]))):
			_spawn_one(journey, faction)


func _spawn_one(journey: Journey, faction: StringName) -> void:
	var center := journey.fleet.anchor.global_position
	var space := journey.get_world_3d().direct_space_state
	for attempt in range(16):
		var angle := rng.randf_range(0.0, TAU)
		var radius := rng.randf_range(spawn_radius.x, spawn_radius.y)
		var position := center + Vector3(cos(angle) * radius, rng.randf_range(-altitude_spread, altitude_spread), sin(angle) * radius)
		_query.transform = Transform3D(Basis.IDENTITY, position)
		if not space.intersect_shape(_query, 1).is_empty():
			continue
		var clear := true
		for other in journey.ships:
			if position.distance_squared_to(other.global_position) < 180.0 * 180.0:
				clear = false
				break
		if not clear:
			continue
		var ship := ship_scene.instantiate() as Airship
		ship.entity_id = journey.allocate_ship_id()
		ship.faction = faction
		journey.add_child(ship)
		ship.global_position = position
		journey.register_ship(ship)
		ship.reset_physics_interpolation()
		spawned_count += 1
		return
