# Ship spawning

Ships added during play use the **Spawn Layer** exported on the root Airship in each ship scene. The same authored choice applies to friendly picker requests and enemy encounters:

| Choice | Placement | Current ships |
| --- | --- | --- |
| Lower Cloud | Nearest enabled cloud-base layer below the fleet marker. | None |
| Upper Cloud | Nearest enabled cloud-base layer above the fleet marker. | Manta |
| Isle | Concealed behind a loaded isle from the current camera position. | Kestrel, Swift, Bastion |

At the marker's 3800-meter altitude, lower and upper mean the 2100-meter and 5200-meter layers. Upper does not mean the highest layer in the world. The setting is independent of the ship's [vertical combat role](combat.md#queryable-vertical-role). Other scripts can query `ship.spawn_layer` and compare it with `Airship.SpawnLayer.LOWER_CLOUD`, `UPPER_CLOUD`, or `ISLE`, including before adding the instance to the tree. The three starting Kestrels keep their authored positions.

## Shared placement rules

[`ShipSpawnPlacement`](../../scripts/world/ship_spawn_placement.gd) owns position selection. Friendlies use Z+ and enemies Z- relative to the persistent fleet marker. The source object's Z position must be at least **500 meters** from the marker on the appropriate side: the isle root or cloud bounds center. The complete enclosing hull sphere, including eight meters of clearance, also stays outside this 500-meter exclusion zone. This is an along-Z constraint, independent of altitude and lateral distance.

Eligible sources are ranked by 3D distance to the marker. Placement is bounded to 32 candidate positions per request. Native shape queries reject overlapping ships and loaded island colliders; an additional hull check covers ships registered earlier in the same tick. A failed picker request reports no clear space. An encounter retains the selected ship and retries after 0.5 seconds using the current marker, camera, and scenery. No failure switches the authored source type or creates a visible fallback spawn.

Journey owns spawning at physics boundaries, faction-specific placement RNGs, IDs, and registration. **Friendly Spawns Per Tick** defaults to two; excess picker requests stay queued in order, limiting instantiation spikes. Encounters retain their separate eight-per-tick budget. Both factions initially face the marker; friendlies inherit fleet velocity. Ships outside the navigation sphere use its [arrival boost](movement.md#arrival-boost) and the navigator's cached approach legs around obstructing isles. Their final destinations stay inside the sphere, while their external detours do not stop the fleet marker. Source geometry, camera-relative concealment, and marker-relative clearance survive floating-origin shifts.

## Isle concealment

Behind an isle is defined by the **camera-to-isle direction**, not a fixed Z offset. If the camera is farther behind the fleet than a friendly spawn isle, the ship appears on the isle's side nearer the marker, while remaining at least 500 meters on Z+.

[`FloatingIsland`](../../scripts/islands/floating_island.gd) caches a sphere wholly inside its visible rock mesh when configured. The current rock is a closed convex nine-sided `CylinderMesh` frustum. Triangle planes bound the sphere, with a small inset; the larger navigation capsule is used only for physical clearance. Candidate ship spheres must lie completely inside the camera's shadow cone behind the rock sphere. This conceals the whole hull from any viewing direction, rather than only covering its center. Hidden isles or unsupported/open rock meshes cannot serve as spawn sources.

Placement samples beyond the island collider along that camera-relative axis, with bounded depth and lateral variation. It tries four positions per isle, visiting up to eight nearest isles within the shared 32-attempt budget. The conservative interior sphere can reject positions that a wider part of the visible mesh could conceal. Concealment is checked at placement; ordinary movement lets ships emerge afterward. Isles need no per-frame spawn processing or additional physics shape.

## Cloud concealment

`CloudProfile.preferred_spawn_layer(marker_altitude, side)` returns the nearest enabled cloud-base layer on the requested side (-1 below, +1 above), or null if none exists. Within it, `CloudSpawner.closest_spawn_cloud` selects the closest eligible cloud by bounds-center distance, enforcing the source's Z clearance. It does not fall back to another layer if that layer has no eligible cloud.

Hidden clouds, clouds too thin for the hull, and clouds within the camera's [dissolve proximity](clouds.md#camera-inside-a-cloud) are excluded. Clouds remain ineligible until their dissolve has fully restored after the camera leaves. Their entire bounds must also lie within the material's opaque distance, before distance fading starts. The complete conservative hull sphere plus clearance must fit inside occupied voxels. All 32 attempts use the selected cloud; an encounter retry reevaluates selection. Clouds remain non-colliding scenery.

## Validation

Use the isolated process environment and Godot executable described in [AGENTS.md](../../AGENTS.md). After the editor import, run:

```text
--headless --path <absolute-project-path> --fixed-fps 30 --script res://scripts/tools/check_ship_spawning.gd --log-file <external-log-file>
```

The check covers the catalog choices, both factions, cameras on either side of an isle, full-hull concealment against independent rays through the visible triangles, 500-meter source/hull separation, rebasing, and unavailable sources. For rendered hidden/revealed comparisons, omit `--headless`, set `AERWYTH_CAPTURE_DIR` to an existing external directory, and append `-- --visual`.

`check_clouds.gd` covers strict lower/upper selection independent of combat bias, cloud source Z clearance, and camera exclusion. `check_ui_layout.gd` and `check_encounters.gd` cover registration, same-tick placement, blocked placement, picker feedback, and encounter retries through the composed Journey.

`check_ship_arrival.gd` runs a 120-second native-physics journey with twelve queued friendly and twelve enemy Kestrels. It requires every spawned ship to reach the moving sphere, verifies the per-tick picker budget, and reports script timing distributions. It also checks cached approach legs across rebasing and island removal. Use the same command shape and optional visual arguments as above. Measurements from the spawn-stall regression are recorded in [combat performance](combat_performance.md#concealed-spawn-arrival-regression-2026-09-27).
