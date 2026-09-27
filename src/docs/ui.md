# Master UI layout

[`master_ui.tscn`](../../scenes/ui/master_ui.tscn) follows the three-zone layout in the sibling Dungeon Directive project. Journey instances one `MasterUI` CanvasLayer. Its full-viewport `ViewportLayout` owns zone sizes, centering, edge anchors, and draw order. Each zone is a separate MarginContainer scene that hosts complete feature views.

| Zone | Logical size | Placement |
| --- | --- | --- |
| TopContainer | 1920 x 140 | Horizontally centered, pinned to the top |
| CenterContainer | 1920 x 800 | Centered horizontally and vertically |
| BottomContainer | 1920 x 140 | Horizontally centered, pinned to the bottom |

The project uses a 1920 x 1080 logical design resolution, `canvas_items` stretch, and `expand` aspect. The initial desktop window remains 1280 x 800. UI scales uniformly. 3D renders across the actual window. Extra aspect-ratio space exposes the world rather than stretching the zone shapes or adding black bars.

| Physical window | Logical canvas | UI scale | Extra space |
| --- | --- | --- | --- |
| 1920 x 1080 | 1920 x 1080 | 1 | Zones touch at y=140 and y=940 |
| 2560 x 1080 | 2560 x 1080 | 1 | 320 pixels on each side of all zones |
| 1440 x 1080 (4:3) | 1920 x 1440 | 0.75 | Two 180-logical-pixel gaps, each 135 physical pixels |
| 1280 x 800 (Steam Deck) | 1920 x 1200 | 2/3 | Two 60-logical-pixel gaps, each 40 physical pixels |
| 960 x 540 | 1920 x 1080 | 0.5 | Same contiguous layout as the design aspect |

Features fill their assigned host using local containers. Viewport anchors and design-width constraints belong only to the master scene. Full-screen presentation belongs directly under `ViewportLayout` so it can cover the expanded canvas. There is no global UI autoload or modal system in the current Journey-only implementation.

The top zone hosts `PerformanceOverlay`, an ordinary Control scene. MasterUI supplies its typed Journey reference. Its half-second timer reads ship count and FPS. Font and padding come from the shared theme. The empty zone hosts and performance display ignore mouse input and take no focus. Interactive features consume input within their own bounds.

Zone hosts have no background or debug captions. Only their feature views draw UI. The world stays unobscured elsewhere.

## Wave announcement

The top zone also hosts `wave_announcement.tscn`, centered horizontally. MasterUI connects the encounter director's `wave_spawned` signal to this view. It shows **Wave N | Difficulty: X** for four seconds from the first successfully placed ship, replacing the previous announcement and restarting its timer when another wave arrives. Blocked and empty waves remain silent. Difficulty is the total spawn cost of the planned composition, including guaranteed entries charged to the budget and those added on top. Unused budget is excluded.

The scene owns an authorable **Display Seconds** value and a one-shot Timer, released with the view. Its controls ignore mouse input and do not take focus. Colors, type size, panel styling, and margins come from the shared main theme. The encounter check covers announcement timing, scores, expiry, and a rendered capture.

## Ship picker

The bottom host contains [`ship_picker.tscn`](../../scenes/ui/ship_picker.tscn). Five equal-width category buttons sit above a single horizontal row of ship choices. The categories, ordered smallest to largest, are **Skiffs, Corvettes, Frigates, Cruisers, and Dreadnoughts**. Skiffs contain Kestrel and Swift, Corvettes contain Manta, and Frigates contain Bastion. Cruisers and Dreadnoughts currently show "No ships available".

The row never wraps. The scrollbar appears only when entries exceed the available width and hides again when they fit. Its scrollbar, mouse wheel, and focus-follow behavior reveal additional choices horizontally. Buttons use the composed `ship_choice.tscn`. The available catalog determines which instances exist. Clicking a choice requests one friendly ship. There is no cost, production timer, or automatic replenishment.

[`ShipDefinition`](../../scripts/ships/ship_definition.gd) resources hold display name, class, Airship scene, and enemy encounter Spawn Cost. Spawn Cost does not charge the player for picker use. Journey's exported `available_ships` array is the catalog authority, containing Kestrel, Swift, Manta, and Bastion definitions from `resources/ships/`. Add an authored definition to that array to expose another ship. MasterUI supplies the catalog to the picker and connects its typed request signal to Journey. UI code never creates or registers world ships. These classes categorize the picker. Combat category priorities are not implemented.

Journey begins processing requested spawns at the next physics tick before taking its ship snapshot. Its authored **Friendly Spawns Per Tick** budget defaults to two, with excess requests retained in order. The ship's authored Spawn Layer selects Lower Cloud, Upper Cloud, or Isle. Manta uses upper clouds and the other catalog ships use isles. The closest eligible source conceals the complete hull from the camera. Both the source and hull stay at least 500 meters on Z+ relative to the fleet marker. Up to 32 candidate positions must clear ships and loaded islands, including ships placed in the same tick. See [ship spawn rules](ship_spawning.md). Successful ships receive a unique ID and player faction before entering the tree, face the marker, inherit fleet velocity, and join the existing movement, combat, death, and floating-origin registries. Unavailable concealment or blocked placement displays a brief inline explanation and creates no ship. Position sampling has its own RNG and does not alter terrain or travel randomness. The three starting Kestrels retain their authored positions.

The picker consumes clicks and wheel events inside the bottom bar, including empty categories and scroll limits. Pointer button use releases incidental focus after mouse-up activates the button. Retaining focus across the press prevents real clicks from being canceled. Camera movement is available again after release. Tab and directional UI navigation use ordinary button focus. Focused UI reserves camera navigation controls, and Cancel or pointer input over the world returns control to the camera. Focus on an offscreen ship scrolls it into view.

## Theme and spacing

[`main_theme.tres`](../../resources/ui/main_theme.tres) is assigned once to `ViewportLayout` and inherited by its features. It owns flat panel/button colors, hover/pressed/focus styles, fonts, scrollbar visuals, and spacing constants. It contains no ornaments or decorative assets.

Use multiples of **4 logical pixels** for authored padding, gaps, and control dimensions. The picker uses 32-pixel side padding, 8-pixel vertical padding and gaps, 44-pixel category buttons, and ship buttons with a 200 x 56 minimum size. Theme type variations (`DockMargin`, `HUDMargin`, `CategoryButton`, `ShipButton`, and the performance styles) keep these values centralized. Borders use the permitted 2-pixel exception. Container division and uniform display scaling may produce fractional physical positions. The spacing rule applies to authored logical values.

## Validation

Follow the isolated launch setup in [AGENTS.md](../../AGENTS.md). After a headless editor import, run `res://scripts/tools/check_ui_layout.gd` with `--fixed-fps 30`. For rendered inspection, omit `--headless`, set `AERWYTH_CAPTURE_DIR` to an external temporary directory, and append `-- --visual`.

The check disables automatic encounters, resizes the composed Journey through all five table entries, checks actual zone rectangles and uniform scaling, and exercises world input outside the picker. It clicks every category with mouse-down and mouse-up on separate frames, requests repeated spawns, verifies registration/unique IDs/independent health and placement after rebasing, rejects blocked placement, and confirms the updated ship label. A temporary 24-definition view checks one-row overflow, wheel input, focus scrolling, Cancel, and camera input isolation. Visual mode captures each window size plus spawning and overflow. `check_movement.gd` provides the existing keyboard, mouse, and controller camera checks. Simulated input does not establish physical controller feel or Steam Deck hardware performance.
