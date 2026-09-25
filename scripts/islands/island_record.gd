class_name IslandRecord
extends RefCounted

var entity_id: int
var route_position: RoutePosition
var lateral_position: float
var altitude: float
var radius: float
var depth: float


func scene_position(origin_segment: int) -> Vector3:
	return Vector3(lateral_position, altitude, route_position.to_scene(origin_segment))
