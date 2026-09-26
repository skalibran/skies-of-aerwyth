class_name FleetPreset
extends Resource

@export var display_name: String = ""
@export var members: Array[FleetMember] = []


func cost() -> int:
	var total: int = 0
	for member in members:
		total += member.cost()
	return total


func validate() -> void:
	assert(not members.is_empty(), "Fleet presets must contain ships.")
	for member in members:
		assert(member != null)
		member.validate()
