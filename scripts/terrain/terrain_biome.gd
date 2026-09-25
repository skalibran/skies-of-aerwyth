class_name TerrainBiome
extends Resource

@export var height_range := Vector2(-30.0, 70.0)
@export var height_noise: FastNoiseLite
@export_range(0.0, 4.0, 0.1) var height_contrast: float = 2.0
@export var palette: Gradient


func elevation(noise_value: float) -> float:
	# Soft contrast preserves peaks; below one, relief fades continuously to flat at zero.
	var fraction := 0.5 + 0.5 * tanh(noise_value * height_contrast) / tanh(maxf(1.0, height_contrast))
	return lerpf(height_range.x, height_range.y, clampf(fraction, 0.0, 1.0))


func validate() -> void:
	assert(height_range.y > height_range.x and height_noise != null and palette != null)
