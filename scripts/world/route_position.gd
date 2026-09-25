class_name RoutePosition
extends RefCounted

const SEGMENT_LENGTH: float = 1024.0

var segment: int
var offset: float


func _init(segment_index: int = 0, segment_offset: float = 0.0) -> void:
	var carry := floori(segment_offset / SEGMENT_LENGTH)
	segment = segment_index + carry
	offset = segment_offset - float(carry) * SEGMENT_LENGTH


static func from_scene(scene_z: float, origin_segment: int) -> RoutePosition:
	return RoutePosition.new(origin_segment, scene_z)


func to_scene(origin_segment: int) -> float:
	# Subtract integers before converting to the local floating-point coordinate.
	return float(segment - origin_segment) * SEGMENT_LENGTH + offset


func advanced(distance: float) -> RoutePosition:
	return RoutePosition.new(segment, offset + distance)


func compare(other: RoutePosition) -> int:
	if segment != other.segment:
		return -1 if segment < other.segment else 1
	if offset == other.offset:
		return 0
	return -1 if offset < other.offset else 1
