class_name TerrainGrid
extends RefCounted


static func floor_divide(value: int, divisor: int) -> int:
	assert(divisor > 0)
	var quotient := value / divisor
	if value < 0 and value % divisor != 0:
		quotient -= 1
	return quotient


## Convert without first multiplying a potentially huge route segment into a float.
static func tile_at(route: RoutePosition, width: int) -> int:
	var segment_length := int(RoutePosition.SEGMENT_LENGTH)
	var quotient := floor_divide(route.segment, width)
	var remainder := posmod(route.segment, width) * segment_length + floori(route.offset)
	return quotient * segment_length + remainder / width


static func tile_start(tile: int, width: int) -> RoutePosition:
	assert(width > 0)
	var segment_length := int(RoutePosition.SEGMENT_LENGTH)
	var remainder := posmod(tile, segment_length) * width
	return RoutePosition.new(floor_divide(tile, segment_length) * width + remainder / segment_length, posmod(remainder, segment_length))


static func cell_center(route: RoutePosition, width: int) -> RoutePosition:
	assert(width > 0)
	# Segment origins need not lie on the source grid (1024 is not divisible by 5/10).
	var phase := posmod(route.segment, width) * (int(RoutePosition.SEGMENT_LENGTH) % width) % width
	return RoutePosition.new(route.segment, floorf((route.offset + phase) / width) * width + width * 0.5 - phase)
