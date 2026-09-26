# Master UI layout

[`master_ui.tscn`](../../scenes/ui/master_ui.tscn) follows the three-zone layout in the sibling Dungeon Directive project. Journey instances one `MasterUI` CanvasLayer. Its full-viewport `ViewportLayout` owns zone sizes, centering, edge anchors, and draw order. Each zone is a separate MarginContainer scene that hosts complete feature views.

| Zone | Logical size | Placement | Test fill |
| --- | --- | --- | --- |
| TopContainer | 1920 x 140 | Horizontally centered, pinned to the top | Red, 28% opacity |
| CenterContainer | 1920 x 800 | Centered horizontally and vertically | Green, 20% opacity |
| BottomContainer | 1920 x 140 | Horizontally centered, pinned to the bottom | Blue, 28% opacity |

The project uses a 1920 x 1080 logical design resolution, `canvas_items` stretch, and `expand` aspect. The initial desktop window remains 1280 x 800. UI scales uniformly; 3D renders across the actual window. Extra aspect-ratio space exposes the world rather than stretching the zone shapes or adding black bars.

| Physical window | Logical canvas | UI scale | Extra space |
| --- | --- | --- | --- |
| 1920 x 1080 | 1920 x 1080 | 1 | Zones touch at y=140 and y=940 |
| 2560 x 1080 | 2560 x 1080 | 1 | 320 pixels on each side of all zones |
| 1440 x 1080 (4:3) | 1920 x 1440 | 0.75 | Two 180-logical-pixel gaps, each 135 physical pixels |
| 1280 x 800 (Steam Deck) | 1920 x 1200 | 2/3 | Two 60-logical-pixel gaps, each 40 physical pixels |
| 960 x 540 | 1920 x 1080 | 0.5 | Same contiguous layout as the design aspect |

Features fill their assigned host using local containers. Viewport anchors and design-width constraints belong only to the master scene. Full-screen presentation belongs directly under `ViewportLayout` so it can cover the expanded canvas. There is no global UI autoload or modal system in the current Journey-only implementation.

The top zone hosts `PerformanceOverlay`, now an ordinary Control scene. MasterUI supplies its typed Journey reference; its existing half-second timer reads ship count and FPS. Its font and padding use the new logical scale, preserving their physical size at 1280 x 800. The shell, colored fills, zone captions, and performance display ignore mouse input and take no focus, so ship picking, orbiting, scroll, and controller camera controls remain available.

Each zone's `DebugFill` owns its translucent color and caption. Change its Color or hide the node in the corresponding zone scene to adjust or remove the test presentation without hiding hosted features. The fill has no gameplay behavior or frame callback.

## Validation

Follow the isolated launch setup in [AGENTS.md](../../AGENTS.md). After a headless editor import, run `res://scripts/tools/check_ui_layout.gd` with `--fixed-fps 30`. For rendered inspection, omit `--headless`, set `AERWYTH_CAPTURE_DIR` to an external temporary directory, and append `-- --visual`.

The check resizes the composed Journey through all five table entries, checks actual zone rectangles and uniform scaling, confirms the live ship label, and injects scroll and ship-picking events through the UI after resizing. Visual mode writes one capture per size. `check_movement.gd` provides the existing keyboard, mouse, and controller camera checks; simulated input does not establish physical controller feel or Steam Deck hardware performance.
