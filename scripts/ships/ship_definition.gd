class_name ShipDefinition
extends Resource

enum ShipClass { SKIFF, CORVETTE, FRIGATE, CRUISER, DREADNOUGHT }

const CLASS_NAMES: Array[String] = ["Skiffs", "Corvettes", "Frigates", "Cruisers", "Dreadnoughts"]

@export var display_name: String = ""
@export var ship_class: ShipClass = ShipClass.SKIFF
@export var scene: PackedScene
## Authored encounter cost for this complete loadout, independent of selection weight.
@export_range(1, 10000, 1, "or_greater") var spawn_cost: int = 10
