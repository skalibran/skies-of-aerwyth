@tool
class_name EquipmentDefinition
extends Resource

@export var display_name: String = "Equipment"
@export_range(1, 10, 1, "or_greater") var tier: int = 1


func is_valid() -> bool:
	return tier >= 1
