class_name MasterUI
extends CanvasLayer

@export var journey: Journey

@onready var performance_overlay: PerformanceOverlay = %PerformanceOverlay
@onready var ship_picker: ShipPicker = %ShipPicker


func _ready() -> void:
	performance_overlay.journey = journey
	if journey != null:
		ship_picker.set_catalog(journey.available_ships)
		ship_picker.spawn_requested.connect(journey.request_ship_spawn)
		journey.ship_spawn_failed.connect(ship_picker.show_spawn_failure)
