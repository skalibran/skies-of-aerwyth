class_name TerrainSampler
extends RefCounted

const SEGMENTS_PER_NOISE_REGION: int = 8
const NOISE_REGION_LENGTH: float = RoutePosition.SEGMENT_LENGTH * SEGMENTS_PER_NOISE_REGION

class NoiseRegion:
	var grass: FastNoiseLite
	var mountains: FastNoiseLite
	var bands: FastNoiseLite

var profile: TerrainProfile
var journey_start: RoutePosition
var _regions: Dictionary[int, NoiseRegion] = {}


func _init(settings: TerrainProfile, start: RoutePosition) -> void:
	profile = settings
	profile.validate()
	journey_start = RoutePosition.new(start.segment, start.offset)


## X/Y/Z contain continuous grassland, mountain, and color-band noise.
## Integer segment seeds keep FastNoiseLite inputs small throughout a long journey.
func sample(world_x: float, segment: int, offset_z: float) -> Vector3:
	var route := RoutePosition.new(segment, offset_z)
	var region := TerrainGrid.floor_divide(route.segment, SEGMENTS_PER_NOISE_REGION)
	var local_z := posmod(route.segment, SEGMENTS_PER_NOISE_REGION) * RoutePosition.SEGMENT_LENGTH + route.offset
	var first := _region(region)
	var second := _region(region + 1)
	var weight := smoothstep(0.0, NOISE_REGION_LENGTH, local_z)
	var x := world_x + 317.0
	var z := local_z + 791.0
	var next_z := z - NOISE_REGION_LENGTH
	# Both sides of a boundary use identical noise and matching continuous slopes.
	return Vector3(
		lerpf(first.grass.get_noise_2d(x, z), second.grass.get_noise_2d(x, next_z), weight),
		lerpf(first.mountains.get_noise_2d(x, z), second.mountains.get_noise_2d(x, next_z), weight),
		lerpf(first.bands.get_noise_2d(x, z), second.bands.get_noise_2d(x, next_z), weight)
	)


func mountain_weight(segment: int, offset_z: float) -> float:
	var distance := JourneyProgress.distance_at(RoutePosition.new(segment, offset_z), journey_start)
	return smoothstep(profile.mountain_start_distance, profile.mountain_full_distance, distance)


func height_from_noise(noise: Vector3, mountain_blend: float) -> float:
	# Blend landforms before quantization to avoid two competing stair grids.
	var height := lerpf(profile.grassland.elevation(noise.x), profile.mountains.elevation(noise.y), mountain_blend)
	return snappedf(height, profile.voxel_size)


func color_at(height: float, band_noise: float, mountain_blend: float) -> Color:
	var limits := profile.grassland.height_range.lerp(profile.mountains.height_range, mountain_blend)
	var warped_height := height + clampf(band_noise, -1.0, 1.0) * profile.band_warp_height
	var fraction := clampf(inverse_lerp(limits.x, limits.y, warped_height), 0.0, 1.0)
	if mountain_blend <= 0.0:
		return profile.grassland.palette.sample(fraction)
	if mountain_blend >= 1.0:
		return profile.mountains.palette.sample(fraction)
	return profile.grassland.palette.sample(fraction).lerp(profile.mountains.palette.sample(fraction), mountain_blend)


## Returns the source column top, independent of display simplification.
func surface_height(world_x: float, route: RoutePosition) -> float:
	var x := floorf(world_x / profile.voxel_size) * profile.voxel_size + profile.voxel_size * 0.5
	var center := TerrainGrid.cell_center(route, profile.voxel_size)
	return height_from_noise(sample(x, center.segment, center.offset), mountain_weight(center.segment, center.offset))


func retain_segments(first: int, last: int) -> void:
	first = TerrainGrid.floor_divide(first, SEGMENTS_PER_NOISE_REGION)
	last = TerrainGrid.floor_divide(last, SEGMENTS_PER_NOISE_REGION) + 1
	for segment in _regions.keys():
		if segment < first or segment > last:
			_regions.erase(segment)


func _region(segment: int) -> NoiseRegion:
	if not _regions.has(segment):
		var region := NoiseRegion.new()
		region.grass = _seeded_noise(profile.grassland.height_noise, segment)
		region.mountains = _seeded_noise(profile.mountains.height_noise, segment)
		region.bands = _seeded_noise(profile.band_noise, segment)
		_regions[segment] = region
	return _regions[segment]


func _seeded_noise(definition: FastNoiseLite, segment: int) -> FastNoiseLite:
	var noise := definition.duplicate() as FastNoiseLite
	# Hash the exact signed integer text, including its high bits, once per region.
	noise.seed = ("%d:%d" % [definition.seed, segment]).hash() & 0x7fffffff
	return noise
