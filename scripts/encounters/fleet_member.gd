class_name FleetMember
extends Resource

@export var ship: ShipDefinition
@export_range(1, 100) var count: int = 1


func cost() -> int:
	return ship.spawn_cost * count


func validate() -> void:
	assert(ship != null and ship.scene != null and ship.spawn_cost > 0)
	assert(count > 0)
