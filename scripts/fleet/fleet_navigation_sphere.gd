class_name FleetNavigationSphere
extends MeshInstance3D

const RING_SEGMENTS: int = 64

@export var fleet: FleetController


func _ready() -> void:
	var lines := ImmediateMesh.new()
	lines.surface_begin(Mesh.PRIMITIVE_LINES)
	for latitude_degrees in [-60.0, -30.0, 0.0, 30.0, 60.0]:
		var latitude := deg_to_rad(latitude_degrees)
		var ring_radius := cos(latitude)
		_add_ring(lines, Vector3.UP * sin(latitude), Vector3.RIGHT * ring_radius, Vector3.BACK * ring_radius)
	for meridian in range(4):
		var angle := PI * float(meridian) / 4.0
		_add_ring(lines, Vector3.ZERO, Vector3(cos(angle), 0.0, sin(angle)), Vector3.UP)
	lines.surface_end()
	mesh = lines
	scale = Vector3.ONE * fleet.radius


func _physics_process(_delta: float) -> void:
	# Reuse the unit mesh; the marker parent supplies travel and origin shifts.
	scale = Vector3.ONE * fleet.radius


func _add_ring(lines: ImmediateMesh, center: Vector3, horizontal: Vector3, vertical: Vector3) -> void:
	for index in range(RING_SEGMENTS):
		var start := TAU * float(index) / RING_SEGMENTS
		var end := TAU * float(index + 1) / RING_SEGMENTS
		lines.surface_add_vertex(center + horizontal * cos(start) + vertical * sin(start))
		lines.surface_add_vertex(center + horizontal * cos(end) + vertical * sin(end))
