class_name CloudType
extends Resource

@export var display_name: String = "Cumulus"
## Preferred cloud-base altitude above sea level, in meters.
@export var altitude_range := Vector2(700.0, 2600.0)
@export_range(0.0, 10.0, 0.1) var weight: float = 1.0

@export_group("Shape")
@export_range(0.1, 1.0, 0.01) var depth_ratio: float = 0.55
@export_range(0.08, 1.0, 0.01) var height_ratio: float = 0.38
@export_range(1, 20, 1) var puff_count: int = 7
## Lobe radius relative to the sampling width. Smaller values open gaps.
@export_range(0.15, 0.65, 0.01) var puff_size: float = 0.3
@export_range(0.0, 0.5, 0.01) var erosion: float = 0.1
## Cut the normalized shape below this height. -1 retains a rounded underside.
@export_range(-1.0, 0.0, 0.05) var base_cut: float = -0.7
@export_range(0.0, 0.6, 0.01) var curl: float = 0.0

@export_group("Color")
@export var top_color := Color(0.98, 0.98, 0.96)
@export var base_color := Color(0.67, 0.73, 0.8)


func altitude_weight(altitude: float) -> float:
	if altitude < altitude_range.x or altitude > altitude_range.y or weight <= 0.0:
		return 0.0
	var middle := (altitude_range.x + altitude_range.y) * 0.5
	var half_width := maxf((altitude_range.y - altitude_range.x) * 0.5, 1.0)
	# Overlapping ranges blend their likelihood instead of switching at one height.
	return weight * lerpf(0.15, 1.0, 1.0 - absf(altitude - middle) / half_width)


func validate() -> void:
	assert(altitude_range.y > altitude_range.x and weight >= 0.0)
	assert(depth_ratio >= 0.1 and depth_ratio <= 1.0)
	assert(height_ratio >= 0.08 and height_ratio <= 1.0)
	assert(puff_count >= 1 and puff_count <= 20 and puff_size > 0.0)
	assert(base_cut >= -1.0 and base_cut <= 0.0 and erosion >= 0.0)
