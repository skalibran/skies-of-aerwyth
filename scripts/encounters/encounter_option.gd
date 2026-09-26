class_name EncounterOption
extends Resource

@export var entry: SpawnEntry
@export_range(0.0, 100.0, 0.1, "or_greater") var weight: float = 1.0
## Maximum selections of this entry per wave, including repeated fleet bundles.
@export_range(1, 100) var maximum_selections: int = 4


func validate() -> void:
	assert(entry != null)
	entry.validate()
	assert(is_finite(weight) and weight >= 0.0 and maximum_selections > 0)
