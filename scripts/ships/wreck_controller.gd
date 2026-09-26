class_name WreckController
extends Node

@export var terrain: VoxelTerrain
@export var origin: FloatingOrigin

var wrecks: Array[Airship] = []


func _ready() -> void:
	terrain.layout_changed.connect(_refresh_visibility)
	origin.shifted.connect(_shift_smoke)
	set_process(false)


func register_wreck(ship: Airship) -> void:
	if ship in wrecks:
		return
	wrecks.append(ship)
	ship.collision_mask |= VoxelTerrain.COLLISION_LAYER
	ship.tree_exiting.connect(_forget_wreck.bind(ship), CONNECT_ONE_SHOT)
	_update_visibility(ship)
	set_process(true)


func _forget_wreck(ship: Airship) -> void:
	wrecks.erase(ship)
	if wrecks.is_empty():
		set_process(false)


func _process(_delta: float) -> void:
	for ship in wrecks:
		if not ship.freeze:
			_update_visibility(ship)


func _refresh_visibility() -> void:
	for ship in wrecks:
		_update_visibility(ship)


func _update_visibility(ship: Airship) -> void:
	var position_in_world := ship.get_global_transform_interpolated().origin
	ship.visual_root.visible = terrain.has_source_detail(position_in_world, ship.hull_radius + ship.hull_half_segment)


func _shift_smoke(displacement: Vector3) -> void:
	for ship in wrecks:
		if is_instance_valid(ship.death_smoke):
			ship.death_smoke.shift_origin(displacement)


func _exit_tree() -> void:
	terrain.layout_changed.disconnect(_refresh_visibility)
	origin.shifted.disconnect(_shift_smoke)
	for ship in wrecks:
		ship.tree_exiting.disconnect(_forget_wreck.bind(ship))
	wrecks.clear()
