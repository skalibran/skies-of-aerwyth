class_name WaveAnnouncement
extends MarginContainer

@export_range(1.0, 15.0, 0.5) var display_seconds: float = 4.0

@onready var wave_label: Label = %WaveLabel
@onready var display_timer: Timer = $DisplayTimer


func show_wave(wave_number: int, difficulty_score: int) -> void:
	wave_label.text = "Wave %d  |  Difficulty: %d" % [wave_number, difficulty_score]
	show()
	display_timer.start(display_seconds)
