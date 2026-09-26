class_name SpawnEntry
extends Resource

## Reusable payload for random choices and guaranteed spawns. Assign exactly one.
@export var ship: ShipDefinition
@export var fleet: FleetPreset


func cost() -> int:
	return ship.spawn_cost if ship != null else fleet.cost()


func append_ships(result: Array[ShipDefinition]) -> void:
	if ship != null:
		result.append(ship)
	else:
		for member in fleet.members:
			for index in range(member.count):
				result.append(member.ship)


func validate() -> void:
	assert((ship != null) != (fleet != null), "Select either a ship or a fleet preset.")
	if ship != null:
		assert(ship.scene != null and ship.spawn_cost > 0)
	else:
		fleet.validate()
