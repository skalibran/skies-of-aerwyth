class_name WaveOverride
extends Resource

## Wave 1 follows the first threat increase; default spacing is 500 meters.
@export_range(1, 10000, 1, "or_greater") var wave_number: int = 1
@export var guaranteed: Array[GuaranteedSpawn] = []
## Disable for an entirely authored encounter.
@export var fill_random_budget: bool = true


func validate() -> void:
	assert(wave_number > 0)
	for entry in guaranteed:
		assert(entry != null)
		entry.validate()
