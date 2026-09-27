class_name CloudLayer
extends Resource

@export var display_name: String = "Middle"
## Cloud-base altitude above sea level, in meters.
@export_range(0.0, 20000.0, 10.0) var altitude: float = 4500.0
## Random offset above or below the base altitude. Zero gives an exact Y level.
@export_range(0.0, 2000.0, 10.0) var height_variation: float = 300.0
## Target clouds per reference cell area. Spacing limits density. Zero disables it.
@export_range(0.0, 1.0, 0.01) var density: float = 0.3


func validate() -> void:
	assert(height_variation >= 0.0 and altitude >= height_variation)
	assert(density >= 0.0 and density <= 1.0)
