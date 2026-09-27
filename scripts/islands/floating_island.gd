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
## A sphere wholly inside the visible rock mesh, in island-local coordinates.
var spawn_occlusion_center := Vector3.ZERO
var spawn_occlusion_radius: float = 0.0


func configure(island_record: IslandRecord, origin_segment: int) -> void:
	record = island_record
	global_position = record.scene_position(origin_segment)
	visual_root.scale = Vector3(record.radius, record.depth, record.radius)
	_build_collision()
	_build_spawn_occluder()
	reset_physics_interpolation()


func overlaps_height(minimum_y: float, maximum_y: float, clearance: float) -> bool:
	return minimum_y <= global_position.y + top_offset + clearance and maximum_y >= global_position.y + bottom_offset - clearance


func hides_sphere(camera_position: Vector3, position: Vector3, radius: float) -> bool:
	if not is_visible_in_tree() or not underside_mesh.is_visible_in_tree() or spawn_occlusion_radius <= 0.0:
		return false
	var to_island := to_global(spawn_occlusion_center) - camera_position
	var distance := to_island.length()
	if distance <= spawn_occlusion_radius:
		return false
	var axis := to_island / distance
	var to_ship := position - camera_position
	var along := to_ship.dot(axis)
	if along - radius <= distance + spawn_occlusion_radius:
		return false
	var sideways := (to_ship - axis * along).length()
	var sine := spawn_occlusion_radius / distance
	# Keep the entire hull sphere inside the rock sphere's camera-shadow cone.
	return along * sine - sideways * sqrt(1.0 - sine * sine) >= radius


func sample_hidden_position(camera_position: Vector3, radius: float, clearance: float, rng: RandomNumberGenerator) -> Vector3:
	var center := to_global(spawn_occlusion_center)
	var to_island := center - camera_position
	var distance := to_island.length()
	if spawn_occlusion_radius <= 0.0 or distance <= spawn_occlusion_radius:
		return Vector3.INF
	var axis := to_island / distance
	var hull := collider.shape as CapsuleShape3D
	# A bounding sphere clears the actual collider from any viewing direction.
	var offset := center.distance_to(collider.global_position) + hull.height * 0.5 + radius + clearance
	offset += rng.randf_range(20.0, 300.0)
	var position := center + axis * offset
	var sideways := axis.cross(Vector3.UP)
	if sideways.length_squared() < 0.01:
		sideways = axis.cross(Vector3.RIGHT)
	sideways = sideways.normalized()
	var upright := axis.cross(sideways).normalized()
	position += (sideways * rng.randf_range(-1.0, 1.0) + upright * rng.randf_range(-1.0, 1.0)) * spawn_occlusion_radius * 0.25
	return position if hides_sphere(camera_position, position, radius) else Vector3.INF


func _build_spawn_occluder() -> void:
	spawn_occlusion_radius = 0.0
	# Current islands use a closed convex nine-sided rock frustum. Its planes,
	# not the deliberately oversized navigation capsule, determine concealment.
	var rock := underside_mesh.mesh as CylinderMesh
	if rock == null or not rock.cap_top or not rock.cap_bottom:
		return
	var transform_to_island := visual_root.transform * underside_mesh.transform
	var faces := rock.get_faces()
	var bounds := rock.get_aabb()
	var planes: Array[Plane] = []
	for index in range(0, faces.size(), 3):
		planes.append(Plane(transform_to_island * faces[index], transform_to_island * faces[index + 1], transform_to_island * faces[index + 2]))
	for fraction: float in [0.25, 0.4, 0.55, 0.7]:
		var center := bounds.get_center()
		center.y = bounds.position.y + bounds.size.y * fraction
		# Points on the rock's local axis stay inside its convex mesh after transformation.
		center = transform_to_island * center
		var radius: float = INF
		for plane in planes:
			radius = minf(radius, absf(plane.distance_to(center)))
		radius *= 0.95
		if radius > spawn_occlusion_radius:
			spawn_occlusion_center = center
			spawn_occlusion_radius = radius


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
