@tool
class_name MountedSlot
extends Node3D

signal equipment_changed

@export_range(1, 10, 1, "or_greater") var tier: int = 1:
	set(value):
		tier = maxi(1, value)
		if is_node_ready() and equipment != null and equipment.definition.tier != tier:
			assign_equipment(null)
@export_range(1.0, 89.0) var cone_half_angle: float = 85.0:
	set(value):
		cone_half_angle = clampf(value, 1.0, 89.0)
		_cone_cosine = cos(deg_to_rad(cone_half_angle))
		_update_cone_preview()
## Assign a scene rooted in MountedEquipment. A null scene leaves the slot empty.
@export var equipment_scene: PackedScene:
	get:
		return _equipment_scene
	set(value):
		if not is_node_ready():
			_equipment_scene = value
		elif not assign_equipment(value):
			push_warning("Equipment must have a valid MountedEquipment root and match slot tier %s." % tier)
## Weapon targeting preference. Utility equipment can ignore this setting.
@export var fire_at_targets_in_range: bool = true
@export_group("Editor Cone Preview")
@export var show_cone_preview: bool = true:
	set(value):
		show_cone_preview = value
		_update_cone_preview()
## Length along the cone's side. This only scales the preview, never weapon range.
@export_range(10.0, 300.0) var cone_preview_size: float = 80.0:
	set(value):
		cone_preview_size = maxf(10.0, value)
		_update_cone_preview()

var equipment: MountedEquipment
var _equipment_scene: PackedScene
var _cone_cosine: float = cos(deg_to_rad(85.0))
var _cone_preview: MeshInstance3D
var _entity_id: int = 0
var _slot_index: int = 0


func _ready() -> void:
	if not assign_equipment(_equipment_scene):
		push_warning("Invalid equipment in slot %s; leaving it empty." % name)
	_update_cone_preview()


func assign_equipment(scene: PackedScene) -> bool:
	var next: MountedEquipment
	if scene != null:
		if not scene.can_instantiate():
			return false
		var instance := scene.instantiate()
		next = instance as MountedEquipment
		if next == null or not next.is_valid() or next.definition.tier != tier:
			instance.free()
			return false
	if equipment != null:
		remove_child(equipment)
		equipment.queue_free()
	_equipment_scene = scene
	equipment = next
	if equipment != null:
		# Equipment origins coincide with the slot's authored muzzle/cone apex.
		equipment.transform = Transform3D.IDENTITY
		equipment.slot = self
		add_child(equipment)
		equipment.initialize_phase(_entity_id, _slot_index)
	update_configuration_warnings()
	equipment_changed.emit()
	return true


func initialize_phase(entity_id: int, slot_index: int) -> void:
	_entity_id = entity_id
	_slot_index = slot_index
	if equipment != null:
		equipment.initialize_phase(entity_id, slot_index)


func accepts_direction(direction: Vector3) -> bool:
	return direction.length_squared() > 0.000001 and (-global_basis.z).normalized().dot(direction.normalized()) >= _cone_cosine - 0.000001


func step(delta: float, ship: Airship, perception: CombatPerception, projectiles: ProjectileController) -> void:
	if equipment != null:
		equipment.step(delta, ship, perception, projectiles)


func _get_configuration_warnings() -> PackedStringArray:
	if _equipment_scene != null and equipment == null:
		return PackedStringArray(["Assigned equipment must have a valid MountedEquipment root and match this slot's tier."])
	return PackedStringArray()


func _update_cone_preview() -> void:
	if not Engine.is_editor_hint() or not is_node_ready():
		return
	if _cone_preview == null:
		_cone_preview = MeshInstance3D.new()
		_cone_preview.name = "FiringConePreview"
		_cone_preview.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_cone_preview.set_meta("_edit_lock_", true)
		var material := StandardMaterial3D.new()
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.cull_mode = BaseMaterial3D.CULL_DISABLED
		material.albedo_color = Color(1.0, 0.65, 0.12, 0.18)
		_cone_preview.material_override = material
		add_child(_cone_preview)
	var cone := CylinderMesh.new()
	cone.top_radius = 0.0
	cone.bottom_radius = cone_preview_size * sin(deg_to_rad(cone_half_angle))
	cone.height = cone_preview_size * _cone_cosine
	cone.radial_segments = 48
	cone.cap_bottom = false
	_cone_preview.mesh = cone
	_cone_preview.rotation.x = PI / 2.0
	_cone_preview.position.z = -cone.height / 2.0
	_cone_preview.visible = show_cone_preview
