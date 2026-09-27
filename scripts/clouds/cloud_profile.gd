class_name CloudProfile
extends Resource

@export var world_seed: int = 71943
@export var types: Array[CloudType] = []
@export var layers: Array[CloudLayer] = []
## Longest horizontal side of each cloud's local bounds, in meters.
@export var span_range := Vector2(1000.0, 3000.0)
## Physical cube width, independent of terrain detail and cloud span.
@export_range(10.0, 100.0, 5.0) var voxel_size: float = 50.0
## Cached shapes also sample sizes evenly across Span Range.
@export_range(1, 8, 1) var variants_per_type: int = 4

@export_group("Distribution")
## Reference spacing for layer density. Actual slots also fit the cloud bounds.
@export_enum("640 m:640", "1280 m:1280", "2560 m:2560") var cell_size: int = 1280
## Horizontal clearance between neighboring cloud bounds in the same layer.
@export_range(0.0, 1000.0, 50.0) var cloud_gap: float = 200.0
@export_range(1280.0, 40000.0, 1280.0) var field_half_width: float = 24320.0
@export_range(1280.0, 40000.0, 1280.0) var look_ahead: float = 24320.0
@export_range(1280.0, 40000.0, 1280.0) var keep_behind: float = 24320.0
## Clouds close to the landscape are rejected before creating render nodes.
@export_range(0.0, 1000.0, 10.0) var ground_clearance: float = 100.0


## Find the nearest enabled cloud-base layer on the requested side of the marker.
func preferred_spawn_layer(marker_altitude: float, altitude_side: int) -> CloudLayer:
	var closest: CloudLayer
	var closest_distance: float = INF
	for layer in layers:
		if layer.density <= 0.0:
			continue
		var difference := layer.altitude - marker_altitude
		var on_side := difference * altitude_side > 0.0
		if not on_side:
			continue
		var distance := absf(difference)
		if distance < closest_distance:
			closest = layer
			closest_distance = distance
	return closest


func select_type(altitude: float, rng: RandomNumberGenerator) -> int:
	var total: float = 0.0
	for cloud_type in types:
		total += cloud_type.altitude_weight(altitude)
	if total <= 0.0:
		return -1
	var choice := rng.randf() * total
	for index in range(types.size()):
		choice -= types[index].altitude_weight(altitude)
		if choice < 0.0:
			return index
	return -1


func variant_span(variant: int) -> float:
	var fraction := float(variant) / (variants_per_type - 1) if variants_per_type > 1 else 0.5
	return snappedf(lerpf(span_range.x, span_range.y, fraction), voxel_size)


func validate() -> void:
	assert(not types.is_empty() and not layers.is_empty())
	assert(voxel_size > 0.0 and span_range.x >= maxf(100.0, voxel_size * 2.0) and span_range.y >= span_range.x)
	assert(is_equal_approx(span_range.x, snappedf(span_range.x, voxel_size)) and is_equal_approx(span_range.y, snappedf(span_range.y, voxel_size)), "Cloud spans must align with the voxel size.")
	assert(variants_per_type >= 1 and variants_per_type <= 8)
	assert(cell_size in [640, 1280, 2560])
	assert(cloud_gap >= 0.0)
	assert(span_range.y + cloud_gap <= RoutePosition.SEGMENT_LENGTH, "Clouds and their gap must fit within one origin segment.")
	assert(field_half_width > 0.0 and look_ahead > 0.0 and keep_behind > 0.0)
	for cloud_type in types:
		assert(cloud_type != null)
		cloud_type.validate()
	for layer in layers:
		assert(layer != null)
		layer.validate()
