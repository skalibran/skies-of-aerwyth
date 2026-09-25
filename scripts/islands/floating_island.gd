class_name FloatingIsland
extends Node3D

@export var visual_root: Node3D
@export var surface_mesh: MeshInstance3D
@export var underside_mesh: MeshInstance3D
@export var collider: CollisionShape3D

var record: IslandRecord
var navigation_radius: float = 0.0
var bottom_offset: float = 0.0
var top_offset: float = 0.0


func configure(island_record: IslandRecord, origin_segment: int) -> void:
	record = island_record
	global_position = record.scene_position(origin_segment)
	visual_root.scale = Vector3(record.radius, record.depth, record.radius)
	_build_collision()
	reset_physics_interpolation()


func overlaps_height(minimum_y: float, maximum_y: float, clearance: float) -> bool:
	return minimum_y <= global_position.y + top_offset + clearance and maximum_y >= global_position.y + bottom_offset - clearance


func _build_collision() -> void:
	var bounds := (visual_root.transform * surface_mesh.transform) * surface_mesh.mesh.get_aabb()
	bounds = bounds.merge((visual_root.transform * underside_mesh.transform) * underside_mesh.mesh.get_aabb())
	# Approximate the island with one upright capsule. Keep a short cylindrical
	# middle even for wide islands, and leave the physics transforms unscaled.
	var hull := CapsuleShape3D.new()
	hull.radius = maxf(bounds.size.x, bounds.size.z) * 0.5
	hull.height = maxf(bounds.size.y, hull.radius * 2.2)
	collider.position = bounds.get_center()
	collider.shape = hull
	# Steering must clear the collider, including caps that extend past the mesh.
	navigation_radius = hull.radius
	bottom_offset = collider.position.y - hull.height * 0.5
	top_offset = collider.position.y + hull.height * 0.5
