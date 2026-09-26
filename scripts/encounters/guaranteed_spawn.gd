class_name GuaranteedSpawn
extends Resource

@export var entry: SpawnEntry
## Number of complete copies, including every member when the entry is a fleet.
@export_range(1, 100) var count: int = 1
## Guaranteed entries always spawn. Disable to add them on top of the random budget.
@export var charge_budget: bool = true


func validate() -> void:
	assert(entry != null and count > 0)
	entry.validate()
