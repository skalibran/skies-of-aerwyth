# Movement prototype

Run the project to open [journey.tscn](../../scenes/world/journey.tscn). It starts with nine player Kestrels using the authored voxel model and balanced palette, a fleet anchor, an orbit camera, and floating islands. The [combat slice](combat.md) adds mounted cannons and debug spawning of two ships per faction each second, replenishing each side up to 100 living ships. There is no on-screen UI. Production, save files, island management, and cloud transitions are not implemented. Movement checks disable combat and spawning through Journey's validation setting.

The endgame combat target is roughly seventy player ships and 150 enemies. The starting nine ships are spaced farther apart; a separate 128-ship movement check exercises the larger fleet without changing the starting roster, including a solid island placed across its path. The separate combat-scale check includes both fleets and projectiles.

One world unit is one meter; see the [unit conversion and measurements](world_units.md).

## Space and camera scale

| Setting | Prototype value |
| --- | --- |
| Formation half-extents, X/Y/Z | 1800 / 1200 / 1800 meters (an ellipsoid spanning 3600 × 2400 × 3600) |
| Maximum nearby destination step | 160 meters |
| Camera viewing sphere radius | 9000 meters, centered on the persistent fleet anchor |
| Starting orbit distance | 1800 meters |
| Orbit distance setting limits | 100–12000 meters, further constrained by the viewing sphere |
| Free-flight speed | 1000 meters/second; 3000 with sprint |
| Zoom | 200 meters/scroll step; 1200 meters/second on controller, both boosted by sprint |
| Camera far plane | 30000 meters |
| Island streaming | 15000 meters ahead, 13000 behind the anchor |
| Island field width | 32000 meters, independent of fleet formation width |
| Island spacing along Z | 80–200 meters, with independent X/Y sampling across the field |
| Island altitude | 2000 to 5600 meters |
| Fleet starting altitude | 3800 meters |
| Voxel ground | 50-meter cubic source grid (trial); adaptive detail over 81 logical 12800-meter regions, Y = -600 to 1300 across biomes |
| Water | Flat scenery at Y = 0; negative terrain forms ponds |

Formation extents and destination step size are exported on FleetController and assigned when each ship joins. The large overall space does not make ships pick destinations across the entire fleet. The starting ships span heights from 3400 to 4200, centered on Y = 3800, and local destination sampling gives X/Y/Z equal weight. Climb speed and attitude limits still keep their motion sluggish. Islands fill a broad surrounding field: X ranges from -16000 to +16000 independently of the formation, and top-reference altitude ranges from 2000 to 5600. The initial field includes both sides, ahead, and behind the fleet. Width, spacing, and altitude are exported on IslandSpawner. If tuning the camera sphere or formation, keep the streaming distances above their combined Z reach with a margin.

The ground is stepped voxel scenery generated with FastNoiseLite, currently trialing 50-meter cubic voxels. TerrainProfile exposes 10/50/100-meter choices. Each patch stays at its logical world position; travel streams terrain rather than sliding it with the fleet. Nearby patches show individual voxels and distant ones simplify the surface. Grassland ranges from -300 to 700 meters, begins blending into broad mountain slopes at 15000 traveled meters, and reaches full mountain terrain at 50000. Settings live in a shared profile and separate biome resources. The default region covers the camera sphere plus far range, and maximum terrain height stays below the island field. There is no ground collision or terrain navigation; the free camera retains its existing spherical bounds and can pass through scenery. See [terrain authoring and checks](terrain.md).

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

The camera starts in fleet tracking and follows the persistent fleet anchor. Fleet focus and the viewing sphere both use that anchor, so ship spawns and deaths do not shift the view with the calculated average. The `camera_focus_fleet` action and `focus_fleet()` method are available without keyboard/controller bindings. Ship selection currently uses the mouse. Camera decisions and follow-up checks live in the [movement task list](todo/todo-movement.txt). Ordinary camera movement never pauses simulation. The final camera position, including its orbit arm, stays inside the moving viewing sphere.

Releasing focus preserves the camera's position and orientation, then removes the orbit arm. Free mode rotates around the camera itself and permits looking above the horizon. Forward/back follows the full view direction; left/right strafes. Zoom changes the orbit distance, with near/far limits and the fleet sphere providing an additional limit. It does nothing in free mode. Sprint changes movement and zoom speed; look sensitivity stays constant. The multiplier, speeds, zoom step, and distance limits are exported on OrbitCamera.

Free flight is relative to the persistent fleet anchor: without input, the camera travels with the anchor and retains its offset and viewing direction. The anchor provides steady translation without following changes in the ship average as ships maneuver or membership changes. The viewing sphere is also centered on the anchor, including while following an individual ship. Clamping a free camera at its boundary updates the retained anchor-relative offset.

## Navigation debug

A purple 40-meter cube at `FleetAnchor/AnchorMarker` marks the persistent anchor's exact position. It follows anchor movement and origin shifts, has no collision, and remains visible independently of the F3 navigation overlay.

Debug geometry starts disabled. Toggle it with F3 or `FleetAnchor/NavigationDebug`'s Enabled Inspector property. Cyan lines link each traveling fleet ship to its current moving destination; crosses and rings mark that destination and its arrival radius. Red goals show combat approach positions or a point three seconds along the current firing pass. Pink lines/crosses show temporary island-detour waypoints. Orange arrows show the intended velocity after island routing but before ship separation, and green arrows show actual velocity. Arrow length represents 0.7 seconds of motion, configurable in the Inspector. Non-fleet ships without a combat target show velocities and any detour.

The geometry is drawn in 3D and remains visible through ship hulls. It reads the registered ships and interpolated anchor/ship transforms without changing navigation or consuming random numbers. One reusable [ImmediateMesh](https://docs.godotengine.org/en/stable/classes/class_immediatemesh.html) rebuilds the simple lines each rendered frame while enabled; disabling debug stops rebuilding. It inherits origin shifts from the anchor and retains no absolute world-position history. No HUD or controls overlay is added.

## Ownership and update order

- Journey registers all physical ships and submits their control forces once per physics tick. Its reusable snapshot arrays supply the same completed physics positions, velocities, and hull axes to every avoidance calculation. Godot/Jolt owns body integration and contact solving.
- FleetController owns friendly membership, anchor motion, and the shared combat radii. It calculates the average before movement and advances the anchor. Journey chooses combat or formation travel intent; FleetController no longer overwrites ship intent during anchor advancement. A separate FleetAverage node stores that calculated center for travel slowdown. Camera focus, combat boundaries, and debug spawn placement use the persistent anchor.
- Airship is the rigid body; its engine `linear_velocity` and `angular_velocity` are authoritative. ShipFlight computes propulsion and yaw forces without assigning transforms or velocities; visual pitch/bank reflect physical motion. ShipTravel owns its anchor-relative goal and random state. ShipIslandNavigation owns a temporary waypoint relative to its island. ShipAvoidance uses predicted closest approach of capsule hulls and a stable passing side for degenerate approaches.
- FloatingOrigin owns the logical origin and explicitly registered scene roots. IslandSpawner owns island records, its RNG, the next route coordinate, and loaded island views. Records survive unloading.
- JourneyProgress exposes `journey.progression.distance`, a number in forward meters derived from the anchor relative to the logical journey start. Journey refreshes it after movement/rebasing. Terrain evaluates the same coordinate-to-distance rule for each sampled location, independently of when its view loads.
- VoxelTerrain owns adaptive patches and two bounded worker jobs. Journey requests the anchor's region and camera detail focus alongside island streaming. Coarse startup coverage builds synchronously; workers prepare replacement mesh arrays, published on the main thread. Old coverage stays visible until replacements are complete. Each patch is an independent origin root, positioned against the current origin when its job completes. Camera movement changes display detail, not source terrain or progression. Sampling never consumes island or ship RNG.
- WaterSurface owns a finite scenery plane at Y = 0. Journey registers it for origin shifts and recenters coverage around the anchor. Its world-aligned shader remains stable across shifts; submerged terrain shapes the visible ponds. It does not change navigation or progression.
- FleetCamera owns tracking, selection, free flight, zoom, and bounds. Its root represents the tracked focus in orbit mode and the camera eye in free mode. Free position is an anchor-relative offset; each rendered frame derives the eye from the interpolated anchor plus that offset. Input and sphere clamping update the offset. Rebasing shifts the rig along with the anchor but leaves the offset unchanged. It reads interpolated target transforms and manages its own rendered transform without another interpolation pass.

Journey's physics callback handles scheduled combat spawns, snapshots ships, advances the fleet controller, chooses combat/travel intent, computes ship separation, routes each ship around stationary islands, and submits forces. Existing projectiles then advance, surviving mounts fire, and destroyed ships are removed before rebasing/streaming. These decisions and ray queries use the latest completed body state; submitting forces does not immediately move a hull. The engine integrates living rigid bodies and resolves contacts for the next physics snapshot. See [combat ownership](combat.md#ownership-and-cleanup). Island streaming updates every quarter-second. Visual pitch/bank remain relative to each physical body. New travel goals are nearby offsets in the anchor's moving frame; anchor velocity is included when seeking them.

ShipAvoidance filters pairs with a conservative three-dimensional snapshot grid and evaluates each unordered pair once, adding opposite corrections before clamping. The existing capsule prediction and accumulation order are retained. IslandSpawner supplies nearby obstacle candidates from a cached two-dimensional grid, rebuilt when the loaded registry or origin changes. ShipIslandNavigation still owns exact clearance, height checks, and detour selection. Focused checks compare filtering against the original full scans and cover origin shifts and unloading.

## Island collision and navigation

Each island has one StaticBody3D on collision layer 2 with an upright CapsuleShape3D. The capsule is centered on the combined visual bounds, with a radius matching half their horizontal width and height at least 2.2 times that radius, preserving a short cylindrical middle. Shape dimensions are set directly; physics transforms remain unscaled. This intentionally approximates the island rather than matching the flat rim and tapered rock exactly. [Godot defines capsule height including both hemispherical caps](https://docs.godotengine.org/en/stable/classes/class_capsuleshape3d.html). Ships retain their hull capsules; their collision mask includes ships and islands. Mouse picking stops at an island instead of selecting a ship through it.

Navigation uses a conservative horizontal footprint and the capsule's vertical bounds, including caps extending beyond the visible mesh. Clear flight above or below an island continues directly. A blocked route triggers a small local visibility graph around padded island footprints, with enough look-ahead for the ship's speed and braking. The graph also considers neighboring islands so a detour does not simply aim into the next one. Only blocked routes build a graph; the next waypoint remains stable until reached, invalidated, or a direct route clears. Equal-cost choices use stable ship IDs, never per-frame randomness.

Ships slow into detour corners, keep their heavy acceleration/yaw limits, and resume their moving travel goal when clear. A travel goal temporarily inside a passing island is bypassed rather than treated as a reachable point inside its solid. Ship separation still applies, and physical collision provides the last contact safeguard. If no local path is available, the ship brakes and retries at a bounded interval. This is lateral routing for the open-air prototype, not a general volumetric maze or cave pathfinder; it does not actively choose an overflight climb to replace a blocked lateral route.

IslandSpawner maintains the loaded obstacle registry alongside its views. Initialization fills the finite streaming window before the first frame, rejecting candidates near the starting ships for hull clearance and approach room. That safety check applies only at startup; it does not carve an empty lane through the continuing field. Later generation extends ahead of the fleet in bounded batches. Detour points store an island reference and local offset, so origin shifts cannot stale their coordinates; unloading removes the obstacle and invalidates its waypoint safely. Navigation clearance is exported on each ship (initially 80 meters beyond its conservative hull footprint).

The anchor owns progression. Membership changes affect the mean and subsequent speed but never reposition the anchor. An empty friendly fleet stops it without inventing defeat or wipe behavior.

## Forward flight and momentum

Living ships use the accepted `RigidBody3D` controller. [`ShipFlight`](../../scripts/ships/ship_flight.gd) is a stateless helper receiving the desired velocity after island routing and ship avoidance. It applies yaw torque toward that course with bounded angular acceleration and a target yaw-rate limit. Propulsion acts along the ship's authored horizontal `primary_movement_direction`, normally local -Z. Changing heading does not rotate the existing velocity; sideways momentum decays with exponential drag. Forward thrust is reduced during sharp turns, and braking gradually lowers longitudinal speed. There is no random steering noise or unrestricted sideways thrust. Altitude remains a separate, climb-limited lift control; ships do not need to pitch vertically to climb.

Both combat and formation travel use this controller. Combat supplies an approach or firing-pass course and cannot set hull yaw independently. Acceleration is multiplied by body mass to obtain force; yaw acceleration is divided by the body's inverse yaw inertia to obtain torque. This preserves authored control response across mass changes while mass still affects contact momentum. Godot/Jolt integrates velocity and resolves capsule contacts, including pushing and off-center yaw. There is no collision damage. Speeds and spin can exceed propulsion targets after contact or while momentum changes direction; bounded control forces restore the requested course instead of overwriting the physics response.

Kestrel overrides the shared primitive visuals and capsule with its [authored model and fitted collider](combat.md#authored-ships-and-weapons). Its 31-meter-long capsule has a 10.5-meter radius, enclosing the balloon and hull through the authored pitch/bank range. Navigation reads these dimensions from the shape.

The shared ship scene authors mass 10, friction 0.2, bounce 0, gravity scale 0, and replacement linear/angular damping of 0. ShipFlight owns deliberate drag and lift; engine default damping must not add a second slowdown. Sleeping is disabled for continuously commanded ships. Angular X/Z locks keep the physical hull upright while the visual child retains limited pitch/bank. The current controller assumes that upright constraint. Changing the shape/mass updates the engine inertia; no duplicate inertia value is maintained.

Combat gradually biases courses toward the anchor beyond 1800 meters and requests regrouping beyond 2600 until the ship returns inside 1800. FleetController exposes these distances as Combat Radii for both factions. Ships retain their flight response and avoidance during regrouping; see [combat positioning](combat.md#targeting-and-movement).

Tune these exported Airship properties in the Inspector:

| Property | Default | Effect |
| --- | ---: | --- |
| `primary_movement_direction` | `(0, 0, -1)` | Local horizontal propulsion axis; normalized, with forward fallback for a zero horizontal vector. |
| `maximum_speed` / `climb_speed` | 180 / 20 meters/s | Combined propulsion target and separate lift target; neither erases contact impulses. |
| `acceleration` / `braking` | 30 / 40 meters/s² | Forward speed response; acceleration also controls lift response. |
| `yaw_speed_degrees` | 24°/s | Commanded yaw-rate limit; contact-induced spin recovers through bounded torque. |
| `yaw_acceleration_degrees` | 45°/s² | How quickly turning builds and brakes. |
| `lateral_drag` | 1.4/s | Higher values reduce sideways momentum sooner; lower values widen drifting turns. |
| `combat_speed_ratio` | 0.5 | Firing-pass cruise contribution relative to maximum speed; target velocity is added before limiting propulsion demand. |
| `combat_pass_seconds` | 6 s | Time before choosing a fresh firing-pass course, unless range/altitude requires an earlier approach. |

Floating-origin translation preserves engine linear/angular velocity and the current world-space pass direction. This occasional position assignment is a coordinate rebase, not flight integration; interpolation resets and the next engine steps retain the translated position. Initial placement and explicit validation fixtures likewise set transforms outside the normal force-control loop. The [rigid-body comparison and audit](rigid_body_trial.md) preserves the scripted baseline and records the user's choice to retain rigid-body movement.

Disabling Journey's physics callback stops new control decisions, but a live rigid body still moves under inertia and contacts. Stationary validation fixtures explicitly set `freeze = true`; checks that manually call `step_simulation()` submit one command per actual engine physics frame with bodies unfrozen. A zero-duration Journey refresh does not advance or pause engine physics. There is no gameplay pause feature in this slice.

## Coordinates and content

RoutePosition stores signed 64-bit segments and offsets in [0, 10240). Negative travel uses floor-based normalization. Only nearby segment differences become scene floats. Progression, generation, and comparisons use the logical segment/offset coordinates.

FloatingOrigin shifts registered roots by an integer number of segments at a physics boundary. The origin index changes by that same number. Registered roots must not contain one another. Velocities, relative goals, stable IDs, and RNG state remain unchanged; interpolation resets after translation. The average-focus node, camera rig, water plane, and terrain chunks shift along with ships and islands.

Islands use stable IDs and a dedicated RNG. The initial surroundings and subsequent generation both use logical Z thresholds; camera movement does not generate content or consume RNG. Islands may occupy the fleet's path and act as solid navigation obstacles; liberation and production remain unimplemented. Geometry and collision unload behind the camera's reachable region, while the logical record remains. Live geometry stays bounded; the record collection grows with travel. Only Z supports long-range travel; X/Y movement is local.

Tune anchor speed/slowdown and formation size on FleetController; ship acceleration, climb, turn, and attitude limits on the ship; camera motion and bounds on OrbitCamera; and spacing/loading distances on IslandSpawner. Keep the loading margins large enough for the viewing sphere and fleet spread. Collision shape size is read from the authored capsule rather than maintained as a second definition. With the current 7680-meter rebase threshold and streaming distances, live Z coordinates remain within a few tens of thousands of meters; enlarging the view does not construct enormous absolute transforms.

## Validation

Select checks using [AGENTS.md](../../AGENTS.md); these commands are available coverage, not a required suite for every edit. Use its process-local APPDATA isolation and unique external logs, and run launches serially. All physics fixtures use the project's 30 Hz baseline. These additional arguments run the focused movement check:

```text
--headless --fixed-fps 30 --script res://scripts/tools/check_movement.gd
```

For rendering and input checks, omit --headless and append the user argument --visual:

```text
--fixed-fps 30 --script res://scripts/tools/check_movement.gd -- --visual
```

Both commands also require the absolute --path and unique --log-file before the -- separator. For visual checks, set AERWYTH_CAPTURE_DIR in the validation process environment to an existing temporary directory outside the repository. The checker captures the fleet, a ship view, zoomed and free-camera views, a resized window, and a view after rebasing at a huge logical coordinate, then exits. Inspect those images as well as the log and exit status. It does not write save data.

Simulation checks cover signed boundaries and segment indices beyond 2^53, origin-shift invariants (including terrain alignment), initial scenery in all four horizontal directions, starting hull clearance, spawn uniqueness, recovery from lag, changing membership, a single/empty fleet, and head-on/crossing/overtaking/parallel encounters. Append `-- --extended` to the headless movement check to include four simulated minutes of travel, repeated goal arrivals, streaming bounds, and multiple origin crossings. Rendered checks also capture wide views ahead and behind the fleet. Input checks inject keyboard, mouse, and controller events through Godot; these do not establish physical controller feel.

Camera regression checks cover releasing either focus without a jump, rotation at the eye in free mode, movement along the pitched view direction, free-camera rebasing, scroll/controller zoom, Shift/LT speed boosts, release behavior, frame-rate independence, and sphere/zoom limits. Navigation debug toggling must leave goals and RNG state unchanged.

Camera tracking checks cover idle travel, retaining orientation, stopping with the anchor, keeping the anchor-relative offset after rebasing, and retaining sphere-clamped positions. Spawn/death fixtures shift the ship average while checking stable fleet, ship, and free views at the sphere boundary. Destroying a followed ship restores anchor tracking, including when the fleet becomes empty.

For an explicitly selected endgame scale check, substitute `res://scripts/tools/check_fleet_scale.gd` in the commands above. It builds 128 ships and a solid island across their path, simulates 30 seconds, checks detours, hull penetration, formation bounds, progression, rebasing, route-wide island placement, and streaming coverage, and prints median/p95 scripted simulation-step times. Its `--visual` mode also captures the fleet, maximum zoom, and an individual ship. These timings exclude native rigid-body integration/contact solving, debug drawing, and the rest of frame rendering; they are not an endgame frame-rate guarantee with combat and production. Endgame performance work is tracked under GEN-05 in the [generation task list](todo/blockers-terrain.txt).

`res://scripts/tools/check_ship_flight.gd` checks actual engine physics at the project's 30 Hz baseline: momentum through a turn, angular acceleration/rate limits, braking to rest, an alternate propulsion axis, lift limits, and zero-duration commands. Contacts without avoidance verify momentum transfer at equal/unequal masses, off-center yaw, upright constraints, and unchanged health. An external impulse/spin fixture checks gradual recovery and sustained propulsion limits. A live-body rebase check advances physics to rule out snapping back. Its stationary-target encounter checks approach-to-pass transitions, repeated broadside firing opportunities, forward alignment, and rebasing. Cohesion fixtures check inward pass selection, bounded pursuit, regrouping hysteresis, firing during return, and both factions recovering from horizontal/altitude drift around a moving anchor through a rebase. With `--visual` it captures `flight-pass.png`: green traces movement and orange marks the bow direction. Use the same launch and external capture directory as the other focused checks. `--fixed-fps 30` accelerates functional runs; it does not override the project physics rate.

For combined frame measurements, omit `--headless` and `--fixed-fps`, set an existing external `AERWYTH_PROFILE_DIR`, and append `-- --profile`. This mode renders at 1920 x 1080 with uncapped frames, pans within the fleet sphere to exercise streaming, and records separate navigation-debug off/on phases in `fleet-128.json`. Optional `--visual` captures still use `AERWYTH_CAPTURE_DIR`. The [generation review](generation_review.md) records the measured CPU headroom and the gap between island loading distances and the camera's full visible range.

Substitute `res://scripts/tools/check_island_navigation.gd` for focused head-on, clustered-island, capsule-cap clearance, overflight, underflight, blocked moving-goal, detour-rebase, collider, hull-penetration, and unloading checks. It also supports `--visual` and the same external capture directory.

Some accelerated runs emitted the engine's intermittent Jolt job-pool warning, without failing assertions or hanging. This warning is also tracked in [Godot issue 110724](https://github.com/godotengine/godot/issues/110724). The rendered check completed without it; retain visibility of this engine issue if it recurs rather than suppressing physics diagnostics.
