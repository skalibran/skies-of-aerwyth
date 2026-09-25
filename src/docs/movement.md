# Movement prototype

Run the project to open [journey.tscn](../../scenes/world/journey.tscn). It contains nine primitive airships, a fleet anchor, an orbit camera, and floating islands. There is no on-screen UI in this milestone. Combat, production, save files, island management, and cloud transitions are not implemented.

The endgame target is 100+ ships. The starting nine ships are spaced farther apart; a separate 128-ship check exercises the larger fleet without changing the starting roster, including a solid island placed across its path.

## Space and camera scale

| Setting | Prototype value |
| --- | --- |
| Formation half-extents, X/Y/Z | 180 / 120 / 180 units (an ellipsoid spanning 360 × 240 × 360) |
| Maximum nearby destination step | 16 units |
| Camera viewing sphere radius | 900 units |
| Starting orbit distance | 180 units |
| Orbit distance setting limits | 10–1200 units, further constrained by the viewing sphere |
| Free-flight speed | 100 units/second; 300 with sprint |
| Zoom | 20 units/scroll step; 120 units/second on controller, both boosted by sprint |
| Camera far plane | 3000 units |
| Island streaming | 1500 units ahead, 1300 behind the anchor |
| Island field width | 3200 units, independent of fleet formation width |
| Island spacing along Z | 8–20 units, with independent X/Y sampling across the field |
| Island altitude | -180 to +180 units |
| Placeholder ground | Green 8000 × 8000 plane at Y = -320 |

Formation extents and destination step size are exported on FleetController and assigned when each ship joins. The large overall space does not make ships pick destinations across the entire fleet. The starting ships span heights from -40 to +40, and local destination sampling gives X/Y/Z equal weight. Climb speed and attitude limits still keep their motion sluggish. Islands fill a broad surrounding field: X ranges from -1600 to +1600 independently of the formation, and top-reference altitude ranges from -180 to +180. The initial field includes both sides, ahead, and behind the fleet. Width, spacing, and altitude are exported on IslandSpawner. If tuning the camera sphere or formation, keep the streaming distances above their combined Z reach with a margin.

The green ground is a visual placeholder for the later noise-generated 3D voxel landscape. Its uniform, two-sided PlaneMesh stays at a fixed altitude while Journey centers it on the anchor in X/Z and registers it for origin shifts. Its edges extend beyond the camera's far range throughout the viewing sphere. The lighter scene fog keeps the surface and distant islands readable. There is no ground collision or terrain navigation yet; the free camera retains its existing spherical bounds.

## Controls

| Input | Behavior |
| --- | --- |
| Left mouse click on a ship | Snap to and follow that ship. |
| WASD / left thumbstick | Release tracking and fly in the view direction within the fleet viewing sphere. |
| Hold RMB and move the mouse | Orbit the tracked target, or look from the current position in free mode. Releasing RMB or losing application focus releases the mouse. |
| Right thumbstick | Rotate without releasing tracking. |
| Mouse wheel up/down | Zoom in/out while tracking the fleet or a ship. |
| Hold D-pad up/down | Continuously zoom in/out while tracking. |
| Hold Shift / LT | Triple orbit zoom speed and free-camera movement speed. |
| F3 | Toggle every ship's navigation debug geometry. |

The camera starts in fleet tracking. Compare the calculated ship center with the persistent anchor using OrbitCamera's exported Fleet Focus Source property in the Inspector. The final choice remains open. The `camera_focus_fleet` action and `focus_fleet()` method remain available, but keyboard/controller bindings are still TBD; no replacement shortcut has been chosen. Controller ship selection also remains TBD. Ordinary camera movement never pauses simulation. The final camera position, including its orbit arm, stays inside the moving viewing sphere.

Releasing focus preserves the camera's position and orientation, then removes the orbit arm. Free mode rotates around the camera itself and permits looking above the horizon. Forward/back follows the full view direction; left/right strafes. Zoom changes the orbit distance, with near/far limits and the fleet sphere providing an additional limit. It does nothing in free mode. Sprint changes movement and zoom speed; look sensitivity stays constant. The multiplier, speeds, zoom step, and distance limits are exported on OrbitCamera.

Free flight is relative to the persistent fleet anchor: without input, the camera travels with the anchor and retains its offset and viewing direction. The anchor provides steady translation without following changes in the ship average as ships maneuver or membership changes. This is independent of the orbit mode's Fleet Focus Source setting. The existing viewing sphere remains centered on the ship average and may adjust the offset at its boundary.

## Navigation debug

Debug geometry starts enabled and can also be switched with `FleetAnchor/NavigationDebug`'s Enabled Inspector property. Cyan lines link each fleet ship to its current moving destination; crosses and rings mark that destination and its arrival radius. Pink lines/crosses show temporary island-detour waypoints. Orange arrows show the intended velocity after island routing but before ship separation, and green arrows show actual velocity. Arrow length represents 0.7 seconds of motion, configurable in the Inspector. Non-fleet ships show velocities and any detour, without a fleet travel destination.

The geometry is drawn in 3D and remains visible through ship hulls. It reads the registered ships and interpolated anchor/ship transforms without changing navigation or consuming random numbers. One reusable [ImmediateMesh](https://docs.godotengine.org/en/stable/classes/class_immediatemesh.html) rebuilds the simple lines each rendered frame while enabled; disabling debug stops rebuilding. It inherits origin shifts from the anchor and retains no absolute world-position history. No HUD or controls overlay is added.

## Ownership and update order

- Journey registers all physical ships and orchestrates their single physics update. Its reusable snapshot arrays supply the same positions, velocities, and hull axes to every avoidance calculation.
- FleetController owns friendly membership and anchor motion. It calculates the average before movement, advances the anchor, and supplies moving travel destinations. A separate FleetAverage node exposes that calculated center to interpolated camera presentation.
- Airship owns physical velocity and constrained attitude. ShipTravel owns its anchor-relative goal and random state. ShipIslandNavigation owns a temporary waypoint relative to its island. ShipAvoidance uses predicted closest approach of capsule hulls and a stable passing side for degenerate approaches.
- FloatingOrigin owns the logical origin and explicitly registered scene roots. IslandSpawner owns island records, its RNG, the next route coordinate, and loaded island views. Records survive unloading.
- FleetCamera owns tracking, selection, free flight, zoom, and bounds. Its root represents the tracked focus in orbit mode and the camera eye in free mode. Free position is an anchor-relative offset; each rendered frame derives the eye from the interpolated anchor plus that offset. Input and sphere clamping update the offset. Rebasing shifts the rig along with the anchor but leaves the offset unchanged. It reads interpolated target transforms and manages its own rendered transform without another interpolation pass.

One physics step snapshots ships, advances the fleet controller, computes ship separation, routes each ship around stationary islands, moves each body once, and recenters if needed. Island streaming updates every quarter-second. Visual pitch/bank remain relative to each physical body. New travel goals are nearby offsets in the anchor's moving frame; anchor velocity is included when seeking them.

## Island collision and navigation

Each island has one StaticBody3D on collision layer 2 with an upright CapsuleShape3D. The capsule is centered on the combined visual bounds, with a radius matching half their horizontal width and height at least 2.2 times that radius, preserving a short cylindrical middle. Shape dimensions are set directly; physics transforms remain unscaled. This intentionally approximates the island rather than matching the flat rim and tapered rock exactly. [Godot defines capsule height including both hemispherical caps](https://docs.godotengine.org/en/stable/classes/class_capsuleshape3d.html). Ships retain their hull capsules; their collision mask includes ships and islands. Mouse picking stops at an island instead of selecting a ship through it.

Navigation uses a conservative horizontal footprint and the capsule's vertical bounds, including caps extending beyond the visible mesh. Clear flight above or below an island continues directly. A blocked route triggers a small local visibility graph around padded island footprints, with enough look-ahead for the ship's speed and braking. The graph also considers neighboring islands so a detour does not simply aim into the next one. Only blocked routes build a graph; the next waypoint remains stable until reached, invalidated, or a direct route clears. Equal-cost choices use stable ship IDs, never per-frame randomness.

Ships slow into detour corners, keep their heavy acceleration/yaw limits, and resume their moving travel goal when clear. A travel goal temporarily inside a passing island is bypassed rather than treated as a reachable point inside its solid. Ship separation still applies, and physical collision provides the last contact safeguard. If no local path is available, the ship brakes and retries at a bounded interval. This is lateral routing for the open-air prototype, not a general volumetric maze or cave pathfinder; it does not actively choose an overflight climb to replace a blocked lateral route.

IslandSpawner maintains the loaded obstacle registry alongside its views. Initialization fills the finite streaming window before the first frame, rejecting candidates near the starting ships for hull clearance and approach room. That safety check applies only at startup; it does not carve an empty lane through the continuing field. Later generation extends ahead of the fleet in bounded batches. Detour points store an island reference and local offset, so origin shifts cannot stale their coordinates; unloading removes the obstacle and invalidates its waypoint safely. Navigation clearance is exported on each ship (initially 8 units beyond its conservative hull footprint).

The anchor owns progression. Membership changes affect the mean and subsequent speed but never reposition the anchor. An empty friendly fleet stops it without inventing defeat or wipe behavior.

## Coordinates and content

RoutePosition stores signed 64-bit segments and offsets in [0, 1024). Negative travel uses floor-based normalization. Only nearby segment differences become scene floats. Progression, generation, and comparisons use the logical segment/offset coordinates.

FloatingOrigin shifts registered roots by an integer number of segments at a physics boundary. The origin index changes by that same number. Registered roots must not contain one another. Velocities, relative goals, stable IDs, and RNG state remain unchanged; interpolation resets after translation. The average-focus node, camera rig, and placeholder ground shift along with ships and islands.

Islands use stable IDs and a dedicated RNG. The initial surroundings and subsequent generation both use logical Z thresholds; camera movement does not generate content or consume RNG. Islands may occupy the fleet's path and act as solid navigation obstacles; liberation and production remain unimplemented. Geometry and collision unload behind the camera's reachable region, while the logical record remains. Live geometry stays bounded; the record collection grows with travel. Only Z supports long-range travel; X/Y movement is local.

Tune anchor speed/slowdown and formation size on FleetController; ship acceleration, climb, turn, and attitude limits on the ship; camera motion and bounds on OrbitCamera; and spacing/loading distances on IslandSpawner. Keep the loading margins large enough for the viewing sphere and fleet spread. Collision shape size is read from the authored capsule rather than maintained as a second definition. With the current 768-unit rebase threshold and streaming distances, live Z coordinates remain within a few thousand units; enlarging the view does not construct enormous absolute transforms.

## Validation

Follow AGENTS.md's process-local APPDATA isolation and unique external log-file requirements. Run launches serially. After the headless editor import, these additional arguments run the focused checks:

```text
--headless --fixed-fps 60 --script res://scripts/tools/check_movement.gd
```

For rendering and input checks, omit --headless and append the user argument --visual:

```text
--fixed-fps 60 --script res://scripts/tools/check_movement.gd -- --visual
```

Both commands also require the absolute --path and unique --log-file before the -- separator. For visual checks, set AERWYTH_CAPTURE_DIR in the validation process environment to an existing temporary directory outside the repository. The checker captures the fleet, a ship view, zoomed and free-camera views, a resized window, and a view after rebasing at a huge logical coordinate, then exits. Inspect those images as well as the log and exit status. It does not write save data.

Simulation checks cover signed boundaries and segment indices beyond 2^53, origin-shift invariants (including the ground), initial scenery in all four horizontal directions, starting hull clearance, spawn uniqueness, several minutes of accelerated travel, recovery from lag, changing membership, a single/empty fleet, and head-on/crossing/overtaking/parallel encounters. Rendered checks also capture wide views ahead and behind the fleet. Input checks inject keyboard, mouse, and controller events through Godot; physical controller feel still needs hands-on evaluation.

Camera regression checks cover releasing either focus without a jump, rotation at the eye in free mode, movement along the pitched view direction, free-camera rebasing, scroll/controller zoom, Shift/LT speed boosts, release behavior, frame-rate independence, and sphere/zoom limits. Navigation debug toggling must leave goals and RNG state unchanged.

Free-camera tracking checks cover idle travel with either orbit-focus setting, retaining orientation, stopping with the anchor, membership changes without shifting an interior camera, keeping the anchor-relative offset after rebasing, and retaining sphere-clamped positions.

For the endgame scale check, substitute `res://scripts/tools/check_fleet_scale.gd` in the commands above. It builds 128 ships and a solid island across their path, simulates 30 seconds, checks detours, hull penetration, formation bounds, progression, rebasing, route-wide island placement, and streaming coverage, and prints median/p95 scripted simulation-step times. Its `--visual` mode also captures the fleet, maximum zoom, and an individual ship. These timings exclude debug drawing and the rest of frame rendering; they are not an endgame frame-rate guarantee with combat and production. Re-profile with denser formations, larger counts, and the later combat workload before choosing further optimization.

Substitute `res://scripts/tools/check_island_navigation.gd` for focused head-on, clustered-island, capsule-cap clearance, overflight, underflight, blocked moving-goal, detour-rebase, collider, hull-penetration, and unloading checks. It also supports `--visual` and the same external capture directory.

Some accelerated runs emitted the engine's intermittent Jolt job-pool warning, without failing assertions or hanging. This warning is also tracked in [Godot issue 110724](https://github.com/godotengine/godot/issues/110724). The rendered check completed without it; retain visibility of this engine issue if it recurs rather than suppressing physics diagnostics.
