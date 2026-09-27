class_name CloudDissolve
extends Node

@export var clouds: CloudSpawner
## Duration of a complete dissolve, matching Dungeon Directive's mesh fade.
@export_range(0.01, 2.0, 0.01, "suffix:s") var fade_duration: float = 0.25

var _occupied: Array[MeshInstance3D] = []
var _coverage: Dictionary[MeshInstance3D, float] = {}


func _process(delta: float) -> void:
	update_effect(delta)


func update_effect(delta: float) -> void:
	var eye := clouds.camera
	_occupied.clear()
	if is_instance_valid(eye) and eye.is_current():
		clouds.query_clouds(eye.global_position, _occupied, clouds.camera_proximity_distance)
	for cloud in _occupied:
		if not _coverage.has(cloud):
			_coverage[cloud] = 1.0
	# Only nearby clouds and those returning to visibility need updates.
	for cloud in _coverage.keys():
		if not is_instance_valid(cloud) or cloud.is_queued_for_deletion():
			_coverage.erase(cloud)
			continue
		var target: float = 0.0 if cloud in _occupied else 1.0
		var coverage := move_toward(_coverage[cloud], target, delta / maxf(fade_duration, 0.001))
		if coverage != _coverage[cloud]:
			cloud.set_instance_shader_parameter(&"camera_fade_coverage", coverage)
			_coverage[cloud] = coverage
		if coverage == 1.0:
			_coverage.erase(cloud)


func _exit_tree() -> void:
	for cloud in _coverage:
		if is_instance_valid(cloud):
			cloud.set_instance_shader_parameter(&"camera_fade_coverage", 1.0)
	_coverage.clear()
	_occupied.clear()
