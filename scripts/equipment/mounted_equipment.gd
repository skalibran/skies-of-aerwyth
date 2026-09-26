@tool
class_name MountedEquipment
extends Node3D

@export var definition: EquipmentDefinition

var slot: MountedSlot


func is_valid() -> bool:
	return definition != null and definition.is_valid()


func initialize_phase(_entity_id: int, _slot_index: int) -> void:
	pass


func step(_delta: float, _ship: Airship, _perception: CombatPerception, _projectiles: ProjectileController) -> void:
	pass
