class_name FloatingOrigin
extends Node

signal shifted(displacement: Vector3)

@export_range(5120.0, 40960.0, 10.0) var shift_threshold: float = 7680.0

var segment: int = 0
var shift_count: int = 0
var _roots: Array[Node3D] = []


func register_root(root: Node3D) -> void:
	if root in _roots:
		return
	for existing in _roots:
		assert(not existing.is_ancestor_of(root) and not root.is_ancestor_of(existing), "Origin roots must not contain one another.")
	_roots.append(root)
	root.tree_exiting.connect(unregister_root.bind(root), CONNECT_ONE_SHOT)


func unregister_root(root: Node3D) -> void:
	_roots.erase(root)
	var callback := unregister_root.bind(root)
	if root.tree_exiting.is_connected(callback):
		root.tree_exiting.disconnect(callback)


func recenter_if_needed(reference_z: float) -> void:
	if absf(reference_z) > shift_threshold:
		shift_segments(roundi(reference_z / RoutePosition.SEGMENT_LENGTH))


func shift_segments(count: int) -> void:
	if count == 0:
		return
	var displacement := Vector3(0.0, 0.0, float(count) * RoutePosition.SEGMENT_LENGTH)
	segment += count
	for root in _roots:
		root.global_position -= displacement
		root.reset_physics_interpolation()
	shift_count += 1
	shifted.emit(displacement)
