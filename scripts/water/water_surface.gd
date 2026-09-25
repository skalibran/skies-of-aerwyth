class_name WaterSurface
extends MeshInstance3D


func recenter(anchor_position: Vector3) -> void:
	# Move only the finite scenery coverage. Shading uses world coordinates.
	var center := Vector3(
		snappedf(anchor_position.x, RoutePosition.SEGMENT_LENGTH),
		0.0,
		snappedf(anchor_position.z, RoutePosition.SEGMENT_LENGTH)
	)
	if global_position != center:
		global_position = center

