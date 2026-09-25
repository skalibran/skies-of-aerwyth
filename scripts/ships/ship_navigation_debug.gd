class_name ShipNavigationDebug
extends MeshInstance3D

const GOAL_COLOR := Color(0.1, 0.85, 1.0)
const DESIRED_COLOR := Color(1.0, 0.55, 0.1)
const VELOCITY_COLOR := Color(0.3, 1.0, 0.25)
const DETOUR_COLOR := Color(1.0, 0.3, 0.85)
const GOAL_RING_SEGMENTS: int = 24

@export var journey: Journey
@export var enabled: bool = false:
	set(value):
		enabled = value
		visible = value
		set_process(value)
@export_range(0.1, 2.0) var velocity_seconds: float = 0.7

var _lines := ImmediateMesh.new()
var _vertex_count: int = 0
var _goal_ring := PackedVector3Array()
var _world_to_local := Transform3D.IDENTITY


func _ready() -> void:
	_goal_ring.resize(GOAL_RING_SEGMENTS)
	for index in range(GOAL_RING_SEGMENTS):
		var angle := TAU * float(index) / GOAL_RING_SEGMENTS
		_goal_ring[index] = Vector3(cos(angle), 0.0, sin(angle))
	mesh = _lines
	var line_material := StandardMaterial3D.new()
	line_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	line_material.vertex_color_use_as_albedo = true
	line_material.no_depth_test = true
	line_material.disable_fog = true
	material_override = line_material
	visible = enabled
	set_process(enabled)


func _process(_delta: float) -> void:
	redraw()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("debug_navigation") and not event.is_echo():
		enabled = not enabled
		get_viewport().set_input_as_handled()


func redraw() -> void:
	_lines.clear_surfaces()
	_vertex_count = 0
	if not enabled or journey.ships.is_empty():
		return
	# All lines share this mesh transform; avoid inverting it for every vertex.
	_world_to_local = global_transform.affine_inverse()
	var anchor_position := journey.fleet.anchor.get_global_transform_interpolated().origin
	for ship in journey.ships:
		var ship_position := ship.get_global_transform_interpolated().origin
		if ship.combat_engaged and ship.combat.returning_to_anchor:
			_line(ship_position, anchor_position, Color(1.0, 0.25, 0.12))
		elif ship.combat_engaged and ship.combat.has_target():
			var goal := ship.combat.target.get_global_transform_interpolated().origin + ship.combat.goal_offset
			_line(ship_position, goal, Color(1.0, 0.25, 0.12))
			_draw_goal(goal, 1.5)
		elif ship in journey.fleet.members:
			var goal := anchor_position + ship.travel.goal_offset
			_line(ship_position, goal, GOAL_COLOR)
			_draw_goal(goal, ship.travel.arrival_radius)
		if ship.island_navigation.has_waypoint():
			var detour := ship.island_navigation.waypoint_position()
			_line(ship_position, detour, DETOUR_COLOR)
			for axis in [Vector3.RIGHT, Vector3.UP, Vector3.BACK]:
				_line(detour - axis, detour + axis, DETOUR_COLOR)
		_draw_arrow(ship_position, ship.navigation_velocity * velocity_seconds, DESIRED_COLOR)
		_draw_arrow(ship_position, ship.linear_velocity * velocity_seconds, VELOCITY_COLOR)
	if _vertex_count > 0:
		_lines.surface_end()


func _draw_goal(goal: Vector3, radius: float) -> void:
	for axis in [Vector3.RIGHT, Vector3.UP, Vector3.BACK]:
		_line(goal - axis * 0.6, goal + axis * 0.6, GOAL_COLOR)
	for index in range(GOAL_RING_SEGMENTS):
		var ring_start := _goal_ring[index] * radius
		var ring_end := _goal_ring[(index + 1) % GOAL_RING_SEGMENTS] * radius
		_line(goal + ring_start, goal + ring_end, GOAL_COLOR)
		_line(goal + Vector3(ring_start.x, ring_start.z, 0.0), goal + Vector3(ring_end.x, ring_end.z, 0.0), GOAL_COLOR)


func _draw_arrow(start: Vector3, displacement: Vector3, color: Color) -> void:
	if displacement.length_squared() < 0.001:
		return
	var direction := displacement.normalized()
	var side := direction.cross(Vector3.UP)
	if side.length_squared() < 0.001:
		side = direction.cross(Vector3.RIGHT)
	side = side.normalized()
	var tip := start + displacement
	var head_size := minf(0.9, displacement.length() * 0.3)
	_line(start, tip, color)
	_line(tip, tip - direction * head_size + side * head_size * 0.5, color)
	_line(tip, tip - direction * head_size - side * head_size * 0.5, color)


func _line(start: Vector3, end: Vector3, color: Color) -> void:
	if _vertex_count == 0:
		_lines.surface_begin(Mesh.PRIMITIVE_LINES)
	_lines.surface_set_color(color)
	_lines.surface_add_vertex(_world_to_local * start)
	_lines.surface_add_vertex(_world_to_local * end)
	_vertex_count += 2
