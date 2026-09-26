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
			var fill := zone.get_node("DebugFill") as ColorRect
			_check(fill.size.is_equal_approx(zone.size) and fill.color.a > 0.0 and fill.color.a < 1.0, "Each test fill covers its host with transparency.")
			_check_scroll_through(zone.get_global_rect().get_center())
		await _check_ship_pick()
		_check(root.gui_get_focus_owner() == null, "Decorative zones do not capture keyboard/controller focus.")
		print("UI_LAYOUT ", JSON.stringify({"window": [window_size.x, window_size.y], "canvas": [canvas.x, canvas.y], "scale": factor, "side_margin": left, "zone_gap": expected[1].position.y - 140.0}))
		if _visual:
			await _capture("ui-%dx%d" % [window_size.x, window_size.y])
	_journey.queue_free()
	await process_frame
	for failure in _failures:
		printerr("FAIL: ", failure)
	if _failures.is_empty():
		print("PASS: UI zones, aspect expansion, uniform scaling, live stats, and camera input through the overlay.")
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
	_check(is_equal_approx(rig.orbit_distance, distance - rig.zoom_step), "Scroll reaches the camera through each colored zone.")
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
