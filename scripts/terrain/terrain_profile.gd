class_name TerrainProfile
extends Resource

## The source grid is cubic and independent of display level of detail.
const CELLS_PER_PATCH: int = 32

@export_enum("1 unit:1", "5 units:5", "10 units:10") var voxel_size: int = 5
@export var grassland: TerrainBiome
@export var mountains: TerrainBiome
@export_range(0.0, 100000.0, 100.0) var mountain_start_distance: float = 1500.0
@export_range(100.0, 100000.0, 100.0) var mountain_full_distance: float = 5000.0
@export var band_noise: FastNoiseLite
## Noise shifts palette thresholds without changing the surface.
@export_range(0.0, 100.0, 1.0) var band_warp_height: float = 12.0
@export_range(0.0, 0.8, 0.01) var cliff_darkening: float = 0.18


func minimum_height() -> float:
	return minf(grassland.height_range.x, mountains.height_range.x)


func maximum_height() -> float:
	return maxf(grassland.height_range.y, mountains.height_range.y)


func validate() -> void:
	assert(voxel_size in [1, 5, 10])
	assert(grassland != null and mountains != null and band_noise != null)
	assert(mountain_full_distance > mountain_start_distance)
	grassland.validate()
	mountains.validate()
	for biome: TerrainBiome in [grassland, mountains]:
		assert(is_zero_approx(fmod(biome.height_range.x, voxel_size)) and is_zero_approx(fmod(biome.height_range.y, voxel_size)), "Biome limits must align with the selected voxel grid.")


func root_size() -> int:
	var size := CELLS_PER_PATCH * voxel_size
	while size < int(RoutePosition.SEGMENT_LENGTH):
		size *= 2
	return size
