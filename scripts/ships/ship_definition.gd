class_name ShipDefinition
extends Resource

enum ShipClass { SKIFF, CORVETTE, FRIGATE, CRUISER, DREADNOUGHT }

const CLASS_NAMES: Array[String] = ["Skiffs", "Corvettes", "Frigates", "Cruisers", "Dreadnoughts"]

@export var display_name: String = ""
@export var ship_class: ShipClass = ShipClass.SKIFF
@export var scene: PackedScene
