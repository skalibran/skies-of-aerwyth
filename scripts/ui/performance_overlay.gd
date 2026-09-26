extends CanvasLayer

@export var journey: Journey

@onready var stats_label: Label = %StatsLabel


func _ready() -> void:
	# Journey registers its initial ships after its children become ready.
	_update_label.call_deferred()


func _update_label() -> void:
	stats_label.text = "Ships: %d  |  FPS: %d" % [journey.ships.size(), Engine.get_frames_per_second()]
