class_name MasterUI
extends CanvasLayer

@export var journey: Journey

@onready var performance_overlay: PerformanceOverlay = %PerformanceOverlay


func _ready() -> void:
	performance_overlay.journey = journey
