class_name PerformanceOverlay
extends MarginContainer

@export var journey: Journey

@onready var stats_label: Label = %StatsLabel


func _ready() -> void:
	# Journey registers its initial ships after its children become ready.
	_update_label.call_deferred()


func _update_label() -> void:
	var ship_count := journey.ships.size() if is_instance_valid(journey) else 0
	stats_label.text = "Ships: %d  |  FPS: %d" % [ship_count, Engine.get_frames_per_second()]
