# Master UI layout

[`master_ui.tscn`](../../scenes/ui/master_ui.tscn) follows the three-zone layout in the sibling Dungeon Directive project. Journey instances one `MasterUI` CanvasLayer. Its full-viewport `ViewportLayout` owns zone sizes, centering, edge anchors, and draw order. Each zone is a separate MarginContainer scene that hosts complete feature views.

| Zone | Logical size | Placement |
| --- | --- | --- |
| TopContainer | 1920 x 140 | Horizontally centered, pinned to the top |
| CenterContainer | 1920 x 800 | Centered horizontally and vertically |
| BottomContainer | 1920 x 140 | Horizontally centered, pinned to the bottom |

The project uses a 1920 x 1080 logical design resolution, `canvas_items` stretch, and `expand` aspect. The initial desktop window remains 1280 x 800. UI scales uniformly; 3D renders across the actual window. Extra aspect-ratio space exposes the world rather than stretching the zone shapes or adding black bars.

| Physical window | Logical canvas | UI scale | Extra space |
| --- | --- | --- | --- |
| 1920 x 1080 | 1920 x 1080 | 1 | Zones touch at y=140 and y=940 |
| 2560 x 1080 | 2560 x 1080 | 1 | 320 pixels on each side of all zones |
| 1440 x 1080 (4:3) | 1920 x 1440 | 0.75 | Two 180-logical-pixel gaps, each 135 physical pixels |
| 1280 x 800 (Steam Deck) | 1920 x 1200 | 2/3 | Two 60-logical-pixel gaps, each 40 physical pixels |
| 960 x 540 | 1920 x 1080 | 0.5 | Same contiguous layout as the design aspect |

Features fill their assigned host using local containers. Viewport anchors and design-width constraints belong only to the master scene. Full-screen presentation belongs directly under `ViewportLayout` so it can cover the expanded canvas. There is no global UI autoload or modal system in the current Journey-only implementation.

The top zone hosts `PerformanceOverlay`, an ordinary Control scene. MasterUI supplies its typed Journey reference; its half-second timer reads ship count and FPS. Font and padding come from the shared theme. The empty zone hosts and performance display ignore mouse input and take no focus. Interactive features consume input within their own bounds.

Zone hosts have no background or debug captions. Only their feature views draw UI; the world stays unobscured elsewhere.

## Ship picker

The bottom host contains [`ship_picker.tscn`](../../scenes/ui/ship_picker.tscn). Five equal-width category buttons sit above a single horizontal row of ship choices. The categories, ordered smallest to largest, are **Skiffs, Corvettes, Frigates, Cruisers, and Dreadnoughts**. Kestrel is currently the only available ship, under Skiffs. The other categories show "No ships available".

The row never wraps. The scrollbar appears only when entries exceed the available width and hides again when they fit. Its scrollbar, mouse wheel, and focus-follow behavior reveal additional choices horizontally. Buttons use the composed `ship_choice.tscn`; the available catalog determines which instances exist. Clicking a choice requests one friendly ship. There is no cost, production timer, or automatic replenishment.

[`ShipDefinition`](../../scripts/ships/ship_definition.gd) resources hold display name, class, and Airship scene. Journey's exported `available_ships` array is the catalog authority, initially [`kestrel.tres`](../../resources/ships/kestrel.tres). Add an authored definition to that array to expose another ship. MasterUI supplies the catalog to the picker and connects its typed request signal to Journey; UI code never creates or registers world ships. These classes categorize the picker; combat category priorities are not implemented.

Journey processes requested spawns at the next physics tick before taking its ship snapshot. It samples a random point in an anchor-relative ellipsoid with 240/80/240-meter half-extents (`spawn_extent`), tries at most 32 candidates, and rejects overlaps with ships and scenery using a conservative hull sphere plus a same-tick ship check. Successful ships receive a unique ID and player faction before entering the tree, inherit fleet velocity, and join the existing movement, combat, death, and floating-origin registries. A blocked request displays a brief inline explanation and creates no ship. Position sampling has its own RNG and does not alter terrain or travel randomness.

The picker consumes clicks and wheel events inside the bottom bar, including empty categories and scroll limits. Pointer button use releases incidental focus after mouse-up activates the button; retaining focus across the press prevents real clicks from being canceled. Camera movement is available again after release. Tab and directional UI navigation use ordinary button focus; focused UI reserves camera navigation controls, and Cancel or pointer input over the world returns control to the camera. Focus on an offscreen ship scrolls it into view.

## Theme and spacing

[`main_theme.tres`](../../resources/ui/main_theme.tres) is assigned once to `ViewportLayout` and inherited by its features. It owns flat panel/button colors, hover/pressed/focus styles, fonts, scrollbar visuals, and spacing constants. It contains no ornaments or decorative assets.

Use multiples of **4 logical pixels** for authored padding, gaps, and control dimensions. The picker uses 32-pixel side padding, 8-pixel vertical padding and gaps, 44-pixel category buttons, and ship buttons with a 200 x 56 minimum size. Theme type variations (`DockMargin`, `HUDMargin`, `CategoryButton`, `ShipButton`, and the performance styles) keep these values centralized. Borders use the permitted 2-pixel exception. Container division and uniform display scaling may produce fractional physical positions; the spacing rule applies to authored logical values.

## Validation

Follow the isolated launch setup in [AGENTS.md](../../AGENTS.md). After a headless editor import, run `res://scripts/tools/check_ui_layout.gd` with `--fixed-fps 30`. For rendered inspection, omit `--headless`, set `AERWYTH_CAPTURE_DIR` to an external temporary directory, and append `-- --visual`.

The check resizes the composed Journey through all five table entries, checks actual zone rectangles and uniform scaling, and exercises world input outside the picker. It clicks every category with mouse-down and mouse-up on separate frames, requests repeated spawns, verifies registration/unique IDs/independent health and placement after rebasing, rejects blocked placement, and confirms the updated ship label. A temporary 24-definition view checks one-row overflow, wheel input, focus scrolling, Cancel, and camera input isolation. Visual mode captures each window size plus spawning and overflow. `check_movement.gd` provides the existing keyboard, mouse, and controller camera checks; simulated input does not establish physical controller feel or Steam Deck hardware performance.
