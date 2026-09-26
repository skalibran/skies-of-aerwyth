class_name JourneyProgress
extends Node

## Forward distance in meters (one world unit per meter), derived from the anchor's logical position.
## Logical segment/offset coordinates remain authoritative for world placement.
var distance: float = 0.0
var start_position := RoutePosition.new()


func initialize(route: RoutePosition) -> void:
	start_position = RoutePosition.new(route.segment, route.offset)
	update(route)


func update(route: RoutePosition) -> void:
	distance = distance_at(route, start_position)


static func distance_at(route: RoutePosition, start: RoutePosition) -> float:
	return maxf(0.0, float(start.segment - route.segment) * RoutePosition.SEGMENT_LENGTH + start.offset - route.offset)
