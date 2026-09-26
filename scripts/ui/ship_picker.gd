class_name ShipPicker
extends PanelContainer

signal spawn_requested(definition: ShipDefinition)

const SHIP_BUTTON := preload("res://scenes/ui/ship_choice.tscn")

var selected_class: ShipDefinition.ShipClass = ShipDefinition.ShipClass.SKIFF
var _definitions: Array[ShipDefinition] = []

@onready var categories: HBoxContainer = %Categories
@onready var ship_scroll: ScrollContainer = %ShipScroll
@onready var ship_row: HBoxContainer = %ShipRow
@onready var status_label: Label = %StatusLabel


func _ready() -> void:
	for index in range(categories.get_child_count()):
		var button := categories.get_child(index) as Button
		button.text = ShipDefinition.CLASS_NAMES[index]
		button.pressed.connect(select_class.bind(index))
		button.gui_input.connect(_release_pointer_focus.bind(button))
	ship_scroll.gui_input.connect(_scroll_ships)
	_rebuild_choices()


func set_catalog(definitions: Array[ShipDefinition]) -> void:
	_definitions.assign(definitions)
	_rebuild_choices()


func select_class(ship_class: ShipDefinition.ShipClass) -> void:
	selected_class = ship_class
	for index in range(categories.get_child_count()):
		(categories.get_child(index) as Button).set_pressed_no_signal(index == ship_class)
	_rebuild_choices()


func show_spawn_failure(definition: ShipDefinition) -> void:
	status_label.text = "No clear space for %s. Try again." % definition.display_name


func _unhandled_input(event: InputEvent) -> void:
	var focus := get_viewport().gui_get_focus_owner()
	if event.is_action_pressed("ui_cancel") and focus != null and is_ancestor_of(focus):
		focus.release_focus()
		get_viewport().set_input_as_handled()


func _rebuild_choices() -> void:
	for child in ship_row.get_children():
		if child != status_label:
			ship_row.remove_child(child)
			child.queue_free()
	var first_choice: Button
	for definition in _definitions:
		if definition.ship_class != selected_class:
			continue
		var button := SHIP_BUTTON.instantiate() as Button
		button.text = definition.display_name
		button.tooltip_text = "Spawn " + definition.display_name
		ship_row.add_child(button)
		button.pressed.connect(_request_spawn.bind(definition))
		button.gui_input.connect(_release_pointer_focus.bind(button))
		button.focus_neighbor_top = button.get_path_to(categories.get_child(selected_class))
		if first_choice == null:
			first_choice = button
	ship_row.move_child(status_label, -1)
	status_label.text = "No ships available" if first_choice == null else ""
	for category: Button in categories.get_children():
		category.focus_neighbor_bottom = category.get_path_to(first_choice) if first_choice != null else NodePath()
	ship_scroll.set_deferred("scroll_horizontal", 0)


func _request_spawn(definition: ShipDefinition) -> void:
	status_label.text = ""
	spawn_requested.emit(definition)


func _scroll_ships(event: InputEvent) -> void:
	if not event is InputEventMouseButton or not event.pressed:
		return
	var direction: int = 0
	match event.button_index:
		MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_LEFT:
			direction = -1
		MOUSE_BUTTON_WHEEL_DOWN, MOUSE_BUTTON_WHEEL_RIGHT:
			direction = 1
	if direction != 0:
		ship_scroll.scroll_horizontal += roundi(direction * event.factor * get_theme_constant("scroll_step", "ShipPicker"))
		ship_scroll.accept_event()


func _release_pointer_focus(event: InputEvent, button: Button) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		# Releasing focus on mouse-down cancels the gesture before mouse-up can activate it.
		button.release_focus.call_deferred()
