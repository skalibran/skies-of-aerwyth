class_name TerrainBiome
extends Resource

@export var height_range := Vector2(-300.0, 700.0)
@export var height_noise: FastNoiseLite
## Higher powers taper summits while retaining the full authored height range.
@export_range(1.0, 4.0, 0.1) var height_power: float = 1.0
@export_range(0.0, 4.0, 0.1) var height_contrast: float = 2.0
@export var palette: Gradient


func elevation(noise_value: float) -> float:
	if height_power != 1.0:
		noise_value = pow(clampf(noise_value * 0.5 + 0.5, 0.0, 1.0), height_power) * 2.0 - 1.0
	# Soft contrast preserves peaks; below one, relief fades continuously to flat at zero.
	var fraction := 0.5 + 0.5 * tanh(noise_value * height_contrast) / tanh(maxf(1.0, height_contrast))
	return lerpf(height_range.x, height_range.y, clampf(fraction, 0.0, 1.0))


func validate() -> void:
	assert(height_range.y > height_range.x and height_noise != null and palette != null)
	assert(height_power >= 1.0)
