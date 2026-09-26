extends SceneTree

const JOURNEY := preload("res://scenes/world/journey.tscn")
const DESIGN_SIZE := Vector2(1920, 1080)
const WINDOW_SIZES: Array[Vector2i] = [
	Vector2i(1920, 1080), Vector2i(2560, 1080), Vector2i(1440, 1080),
	Vector2i(1280, 800), Vector2i(960, 540),
]

var _failures: Array[String] = []
var _journey: Journey
var _visual: bool = false


func _initialize() -> void:
	_visual = "--visual" in OS.get_cmdline_user_args()
	_run.call_deferred()


func _run() -> void:
	_journey = JOURNEY.instantiate() as Journey
	root.add_child(_journey)
	await _frames(3)
	_journey.set_physics_process(false)
	for ship in _journey.ships:
		ship.freeze = true
	var master := _journey.get_node("MasterUI") as MasterUI
	var layout := master.get_node("ViewportLayout") as Control
	var zones: Array[Control] = [layout.get_node("TopContainer"), layout.get_node("CenterContainer"), layout.get_node("BottomContainer")]
	_check(root.content_scale_size == Vector2i(DESIGN_SIZE), "The logical design resolution is 1920x1080.")
	_check(root.content_scale_mode == Window.CONTENT_SCALE_MODE_CANVAS_ITEMS and root.content_scale_aspect == Window.CONTENT_SCALE_ASPECT_EXPAND, "Canvas items scale uniformly with expanded aspect.")
	_check(master.performance_overlay.journey == _journey and master.performance_overlay.stats_label.text.begins_with("Ships: 3"), "The top-zone performance display reads the live Journey.")
	for window_size in WINDOW_SIZES:
		root.size = window_size
		await _frames(8)
		var factor := minf(window_size.x / DESIGN_SIZE.x, window_size.y / DESIGN_SIZE.y)
		var canvas := Vector2(window_size) / factor
		_check(layout.size.is_equal_approx(canvas), "Expanded logical canvas matches window %s." % window_size)
		_check(root.get_final_transform().get_scale().is_equal_approx(Vector2.ONE * factor), "Uniform canvas scale matches window %s." % window_size)
		var left := (canvas.x - DESIGN_SIZE.x) * 0.5
		var expected: Array[Rect2] = [
			Rect2(left, 0, 1920, 140),
			Rect2(left, (canvas.y - 800.0) * 0.5, 1920, 800),
			Rect2(left, canvas.y - 140.0, 1920, 140),
		]
		for index in range(zones.size()):
			var zone := zones[index]
			_check(zone.get_global_rect().is_equal_approx(expected[index]), "%s remains centered with its fixed size at %s." % [zone.name, window_size])
			if index < 2:
				_check_scroll_through(zone.get_global_rect().get_center())
		_check(zones[2].get_global_rect().encloses(master.ship_picker.get_global_rect()), "The complete picker fits its bottom host after resizing.")
		_check_picker_scroll(master.ship_picker, false)
		await _check_ship_pick()
		_check(root.gui_get_focus_owner() == null, "Decorative zones do not capture keyboard/controller focus.")
		print("UI_LAYOUT ", JSON.stringify({"window": [window_size.x, window_size.y], "canvas": [canvas.x, canvas.y], "scale": factor, "side_margin": left, "zone_gap": expected[1].position.y - 140.0}))
		if _visual:
			await _capture("ui-%dx%d" % [window_size.x, window_size.y])
	await _check_ship_picker(master)
	_journey.queue_free()
	await process_frame
	for failure in _failures:
		printerr("FAIL: ", failure)
	if _failures.is_empty():
		print("PASS: UI aspect layout, ship categories, click spawning, safe placement/rebasing, overflow, focus, and camera input isolation.")
	quit(0 if _failures.is_empty() else 1)


func _check_scroll_through(point: Vector2) -> void:
	var rig := _journey.camera_rig
	rig.focus_fleet()
	var distance := rig.orbit_distance
	var wheel := InputEventMouseButton.new()
	wheel.button_index = MOUSE_BUTTON_WHEEL_UP
	wheel.position = point
	wheel.global_position = point
	wheel.pressed = true
	root.push_input(wheel, true)
	wheel.pressed = false
	root.push_input(wheel, true)
	_check(is_equal_approx(rig.orbit_distance, distance - rig.zoom_step), "Scroll reaches the camera through unoccupied UI zones.")
	rig.orbit_distance = distance
	rig.apply_view_bounds()


func _check_ship_pick() -> void:
	var rig := _journey.camera_rig
	var ship := _journey.ships[1]
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.position = rig.camera.unproject_position(ship.global_position)
	click.global_position = click.position
	click.pressed = true
	root.push_input(click, true)
	await _frames(3)
	click.pressed = false
	root.push_input(click, true)
	_check(rig.followed_ship == ship, "Ship picking works through the center zone after resizing.")
	rig.focus_fleet()


func _check_ship_picker(master: MasterUI) -> void:
	root.size = Vector2i(1280, 800)
	await _frames(4)
	var picker := master.ship_picker
	_check(picker.categories.get_child_count() == 5, "Five ship classes are available.")
	for index in range(1, 5):
		await _click(picker.categories.get_child(index) as Control)
		await _frames(2)
		_check(picker.selected_class == index and _choices(picker).is_empty() and picker.status_label.text == "No ships available", "An empty class filters out Kestrel and explains the empty row.")
	await _click(picker.categories.get_child(0) as Control)
	await _frames(2)
	_check(_choices(picker).size() == 1 and _choices(picker)[0].text == "Kestrel", "Kestrel belongs to the smallest class, Skiffs.")
	_journey._spawn_rng.seed = 71937
	var initial_count := _journey.ships.size()
	var spawned: Array[Airship] = []
	for index in range(3):
		if index == 1:
			_journey.origin.shift_segments(-1)
		var camera_mode := _journey.camera_rig.mode
		await _click(_choices(picker)[0])
		await _frames(2)
		_check(_journey.ships.size() == initial_count + index, "GUI activation queues spawning until the next simulation tick.")
		_journey.step_simulation(1.0 / Engine.physics_ticks_per_second)
		_check(_journey.ships.size() == initial_count + index + 1, "One ship-button activation spawns exactly one vessel.")
		var ship: Airship = _journey.ships.back()
		ship.freeze = true
		spawned.append(ship)
		_check(ship.faction == Factions.PLAYER and ship in _journey.fleet.members and ship in _journey.origin._roots, "Spawned ships join player flight and origin registries.")
		_check(((ship.global_position - _journey.fleet.anchor.global_position) / _journey.spawn_extent).length() <= 1.001, "Random placement stays near the live anchor, including after rebasing.")
		_check(_journey.camera_rig.mode == camera_mode and root.gui_get_focus_owner() == null, "Pointer spawning neither picks the world nor keeps camera controls locked.")
	_check(spawned[0].entity_id != spawned[1].entity_id and spawned[1].entity_id != spawned[2].entity_id, "Repeated spawning assigns independent stable IDs.")
	_check(spawned[1].position.distance_to(spawned[2].position) > 31.0, "Repeated random spawns do not stack hulls.")
	spawned[0].take_damage(5.0, Factions.ENEMY)
	_check(spawned[1].current_health == spawned[1].maximum_health, "Spawned ships have independent mutable health.")
	await _frames(20)
	_check(master.performance_overlay.stats_label.text.begins_with("Ships: 6"), "The performance display includes newly spawned ships.")
	if _visual:
		await _capture("ship-picker-spawned")
	await _check_blocked_spawn(picker)
	# Populate only the view with temporary definitions to exercise future catalog overflow.
	var many: Array[ShipDefinition] = []
	for index in range(24):
		var definition := _journey.available_ships[0].duplicate() as ShipDefinition
		definition.display_name = "Test Skiff %02d" % index
		many.append(definition)
	picker.set_catalog(many)
	await _frames(4)
	var choices := _choices(picker)
	_check(choices.size() == 24 and picker.ship_row.size.x > picker.ship_scroll.size.x, "Large categories overflow horizontally.")
	for choice in choices:
		_check(is_equal_approx(choice.position.y, choices[0].position.y), "All ship choices stay in one row.")
	_check_picker_scroll(picker, true)
	choices.back().grab_focus()
	await _frames(4)
	_check(picker.ship_scroll.scroll_horizontal > 0, "Keyboard/controller focus scrolls distant choices into view.")
	var distance := _journey.camera_rig.orbit_distance
	var pad := InputEventJoypadButton.new()
	pad.button_index = JOY_BUTTON_DPAD_UP
	pad.pressed = true
	Input.parse_input_event(pad)
	Input.flush_buffered_events()
	_journey.camera_rig._process(0.1)
	_check(is_equal_approx(_journey.camera_rig.orbit_distance, distance), "UI focus reserves directional controls instead of also zooming the camera.")
	pad.pressed = false
	Input.parse_input_event(pad.duplicate())
	Input.flush_buffered_events()
	if _visual:
		await _capture("ship-picker-overflow")
	var cancel := InputEventAction.new()
	cancel.action = "ui_cancel"
	cancel.pressed = true
	root.push_input(cancel, true)
	_check(root.gui_get_focus_owner() == null, "Cancel releases picker focus back to the camera.")
	choices[0].grab_focus()
	_check_scroll_through(Vector2(960, 400))
	_check(root.gui_get_focus_owner() == null, "Pointer input over the world releases keyboard/controller UI focus.")
	var before := _journey.ships.size()
	_journey.request_ship_spawn(many[0])
	_journey.step_simulation(1.0 / Engine.physics_ticks_per_second)
	_check(_journey.ships.size() == before, "Journey rejects definitions outside its available catalog.")
	picker.set_catalog(_journey.available_ships)
	picker.select_class(ShipDefinition.ShipClass.SKIFF)
	await _frames(3)
	_check_picker_scroll(picker, false)


func _check_blocked_spawn(picker: ShipPicker) -> void:
	var blocker := StaticBody3D.new()
	blocker.collision_layer = 2
	var collider := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3.ONE * 2000.0
	collider.shape = box
	blocker.add_child(collider)
	_journey.add_child(blocker)
	blocker.global_position = _journey.fleet.anchor.global_position
	await _frames(2)
	var before := _journey.ships.size()
	_journey.request_ship_spawn(_journey.available_ships[0])
	_journey.step_simulation(1.0 / Engine.physics_ticks_per_second)
	_check(_journey.ships.size() == before and picker.status_label.text.begins_with("No clear space"), "Blocked placement reports failure without spawning inside scenery.")
	blocker.queue_free()
	await _frames(2)


func _choices(picker: ShipPicker) -> Array[Button]:
	var result: Array[Button] = []
	for child in picker.ship_row.get_children():
		if child is Button:
			result.append(child)
	return result


func _click(control: Control) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.position = control.get_global_rect().get_center()
	event.global_position = event.position
	event.pressed = true
	root.push_input(event, true)
	# Real pointer gestures span frames; focus must survive until release activates the button.
	await _frames(2)
	event.pressed = false
	root.push_input(event, true)


func _check_picker_scroll(picker: ShipPicker, overflow: bool) -> void:
	_check(picker.ship_scroll.get_h_scroll_bar().visible == overflow, "The ship scrollbar appears only when its entries overflow.")
	var distance := _journey.camera_rig.orbit_distance
	var wheel := InputEventMouseButton.new()
	wheel.button_index = MOUSE_BUTTON_WHEEL_DOWN
	wheel.position = picker.ship_scroll.get_global_rect().get_center()
	wheel.global_position = wheel.position
	wheel.pressed = true
	root.push_input(wheel, true)
	wheel.pressed = false
	root.push_input(wheel, true)
	_check(is_equal_approx(_journey.camera_rig.orbit_distance, distance), "Scrolling the picker never zooms the camera, including without overflow.")
	if overflow:
		_check(picker.ship_scroll.scroll_horizontal > 0, "Mouse wheel scrolls the single ship row sideways.")


func _frames(count: int) -> void:
	for frame in range(count):
		await physics_frame


func _capture(label: String) -> void:
	var directory := OS.get_environment("AERWYTH_CAPTURE_DIR")
	_check(not directory.is_empty(), "Visual checks require an external capture directory.")
	if directory.is_empty():
		return
	await RenderingServer.frame_post_draw
	_check(root.get_texture().get_image().save_png(directory.path_join(label + ".png")) == OK, "Capture saved: " + label)


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
