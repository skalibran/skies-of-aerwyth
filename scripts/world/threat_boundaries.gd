class_name ThreatBoundaries
extends MeshInstance3D

@export var journey: Journey

var first_level: int = -1
var last_level: int = -1
var _spacing: float = 0.0
var _half_span: float = 0.0
var _lines := ImmediateMesh.new()


func _ready() -> void:
	mesh = _lines


func _process(_delta: float) -> void:
	update_boundaries()


func update_boundaries() -> void:
	var camera := journey.camera_rig.camera
	var spacing := journey.encounters.profile.threat_distance
	var viewport_size := camera.get_viewport().get_visible_rect().size
	var aspect := maxf(1.0, viewport_size.x) / maxf(1.0, viewport_size.y)
	# Cover even far-plane corners, so horizontal endpoints stay outside the view.
	var tangent := tan(deg_to_rad(camera.fov * 0.5)) * maxf(aspect, 1.0 / aspect)
	var reach := camera.far * sqrt(1.0 + 2.0 * tangent * tangent)
	var half_span := ceilf(reach / spacing) * spacing + spacing
	var camera_route := RoutePosition.from_scene(camera.global_position.z, journey.origin.segment)
	var distance := JourneyProgress.distance_at(camera_route, journey.progression.start_position)
	var first := maxi(0, floori((distance - half_span) / spacing))
	var last := ceili((distance + half_span) / spacing)
	if first != first_level or last != last_level or spacing != _spacing or half_span != _half_span:
		_rebuild(first, last, spacing, half_span)
	var first_route := journey.progression.start_position.advanced(-float(first_level) * spacing)
	# Derive the local transform from logical coordinates after every origin shift.
	global_position = Vector3(
		camera.global_position.x,
		journey.fleet.marker.get_global_transform_interpolated().origin.y,
		first_route.to_scene(journey.origin.segment)
	)


func _rebuild(first: int, last: int, spacing: float, half_span: float) -> void:
	first_level = first
	last_level = last
	_spacing = spacing
	_half_span = half_span
	_lines.clear_surfaces()
	_lines.surface_begin(Mesh.PRIMITIVE_LINES)
	for level in range(first, last + 1):
		var z := -float(level - first) * spacing
		_lines.surface_add_vertex(Vector3(-half_span, 0.0, z))
		_lines.surface_add_vertex(Vector3(half_span, 0.0, z))
	_lines.surface_end()
