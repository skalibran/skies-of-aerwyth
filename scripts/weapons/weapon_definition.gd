@tool
class_name WeaponDefinition
extends EquipmentDefinition

@export_range(1.0, 1000.0) var range_units: float = 100.0
@export_range(0.1, 1000.0) var damage: float = 5.0
@export_range(0.1, 1000.0) var launch_speed: float = 20.0
@export_range(0.1, 100.0) var gravity: float = 3.0
@export_range(0.1, 30.0) var lifetime: float = 8.0
@export_range(0.1, 30.0) var reload_seconds: float = 2.0


func is_valid() -> bool:
	for value in [range_units, damage, launch_speed, gravity, lifetime, reload_seconds]:
		if not is_finite(value) or value <= 0.0:
			return false
	return super.is_valid()
