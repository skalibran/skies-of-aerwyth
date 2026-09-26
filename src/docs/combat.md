# Combat slice

Run `scenes/world/journey.tscn` for nine starting player Kestrels and continuous debug spawning for both factions. [`CombatSpawner`](../../scripts/combat/combat_spawner.gd) adds up to two player ships and two enemy ships every simulation second, starting after one second. Each faction has its own cap of 100 living ships; starting ships count toward it. Casualties open capacity that is replenished at the same rate on subsequent ticks, including after either side is wiped out. Partial batches never exceed the cap, and capped or blocked ticks do not accumulate a later burst. Placement retries use the existing bounded ship/island clearance checks. Destroyed ships despawn. This is a debug population driver; production, purchased reinforcements, difficulty progression, defeat screens, wreck behavior, and combat UI remain unimplemented. The added Kestrel model is not used.

The [combat and movement review](combat_review.md) preserves the CharacterBody3D baseline; the [rigid-body integration](rigid_body_trial.md) records the accepted controller, comparison, and replacement audit. Outstanding combat work lives in the [combat task list](todo/todo-combat.txt); controller acceptance is recorded in the [movement task list](todo/todo-movement.txt).

Both factions spawn 100–150 horizontal units from the persistent fleet anchor, within 150 units above or below its altitude (a 300-unit vertical band). Tune **Altitude Spread** on CombatSpawner. The ship average and camera position do not move this spawn region. Origin shifts preserve its position relative to the anchor. Default spawn positions remain inside the 260-unit combat radius.

## Authored ships and weapons

[`kestrel.tscn`](../../scenes/ships/kestrel.tscn) inherits the primitive [`ship.tscn`](../../scenes/ships/ship.tscn). It retains movement values and capsule collision, owns two tier-one slots, assigns their starting equipment, and authors its combat directions. Both factions instantiate the same scene. Set `entity_id` and `faction` **before adding the ship to the tree**, because readiness initializes weapon phases and tint. Then position the ship and register it with Journey. `player` and `enemy` are hostile to each other; matching identifiers are allied, and other strings are non-hostile. The existing neutral navigation fixtures remain supported. Live faction switching is not part of this slice.

[`Factions`](../../scripts/combat/factions.gd) owns that relationship rule. Enemy geometry uses a shared translucent reddish material overlay; the original meshes/materials remain shared and unmodified. Player tint, instance health, and mount cooldowns cannot leak between ships.

Each ship-owned [`MountedSlot`](../../scripts/ships/mounted_slot.gd) has a tier, authored orientation, cone half-angle, pass-by targeting preference, and an optional `equipment_scene`. The reusable [`mounted_slot.tscn`](../../scenes/ships/mounted_slot.tscn) starts empty. A scene assigned to it must have a [`MountedEquipment`](../../scripts/equipment/mounted_equipment.gd) root with a valid [`EquipmentDefinition`](../../scripts/equipment/equipment_definition.gd) of exactly the same tier. This contract supports weapons and utility equipment; utility effects themselves are not implemented in this slice.

Kestrel's `LeftSlot` and `RightSlot` each assign [`rusty_cannon.tscn`](../../scenes/weapons/rusty_cannon.tscn) as their initial equipment. Its [`MountedWeapon`](../../scripts/weapons/mounted_weapon.gd) owns the cannon model, aim pivot, ballistic targeting, and independent reload/search state. It references the shared weapon definition and asks its slot whether the launch direction is allowed. The cannon scene has no Kestrel reference and can be assigned to any matching slot.

In the Godot Inspector, select either slot in `kestrel.tscn` to edit **Tier**, **Equipment Scene**, and **Cone Half Angle**. Clear Equipment Scene to leave a slot empty, or assign a compatible equipment scene. At runtime, `assign_equipment(scene)` returns false for incompatible equipment and preserves the current assignment. Replacement creates fresh equipment state, reapplies faction tint, and resets combat positioning. Empty and utility-only ships continue travel. Changing a slot's tier clears incompatible equipment.

The editor-only **Show Cone Preview** draws a translucent `CylinderMesh` with its top radius set to zero. Adjust Cone Half Angle or rotate the slot to author the firing angle. **Cone Preview Size** controls its side length for readability, not weapon range. Preview geometry is generated from the same angle as the firing test, is not saved into the scene, and is absent at runtime.

The slot origin is the equipment origin, muzzle, and cone apex. The current authored Kestrel tuning places cannons beside the gondola at local X = +/-1.4, Y = -1.3, Z = 0.3, with a **65-degree half-angle (130-degree opening)**. The visual barrel pivots around the muzzle without rotating the allowed cone. Visual pitch/bank carries both slots with the ship.

[`rusty_cannon.tres`](../../resources/weapons/rusty_cannon.tres) is the shared, immutable tier-one definition:

| Setting | Current value |
| --- | ---: |
| Targeting range | 100 units |
| Damage | 5 |
| Launch speed | 100 units/s (current authored trial; original slice baseline was 20) |
| Downward acceleration | 3 units/s² |
| Maximum projectile lifetime | 8 seconds |
| Reload per cannon | 2 seconds |
| Kestrel health | 500 (ten times the initial 50) |

Health, reload, gravity, lifetime, and engagement distance are provisional tuning. Tier compatibility requires exact matching for any positive tier; lower-tier equipment in higher-tier slots is not currently allowed.

## Aiming and impact

[`Ballistics`](../../scripts/combat/ballistics.gd) solves for the earliest positive interception time, assuming the target continues at its current world velocity. It partitions the scalar interception polynomial using derivative roots, then performs bounded bisection within monotonic intervals. Boundary residual checks include tangent solutions. It rejects invalid inputs and solutions whose launch speed fails its residual check.

The current target and predicted intercept must both be within 100 units of the muzzle. The **initial launch vector**, including elevation and lead, must fit the slot cone. The weapon does not test obstruction by its own hull or balloon. It does not switch to a high lob when the earliest solution fails range or cone checks. Barrel aim and projectile motion use the same launch vector.

At the original 20-unit/s reference speed, a stationary equal-height 60-unit target takes about 3.08 seconds to reach, with a 3.57-unit rise. A 100-unit target takes about 5.49 seconds, rising 11.29 units. These reference trajectories remain solver fixtures; the current authored 100-unit/s trial produces substantially flatter, faster shots. Launch speed is not constant speed along the arc. The cannonball has no drag, homing, inherited shooter velocity, or speed-dependent damage. Target acceleration after launch can cause misses.

[`ProjectileController`](../../scripts/combat/projectile_controller.gd) advances all shots in one physics step using the constant-acceleration equation. Each shot owns local position, velocity, gravity, lifetime, captured source faction, a weak shooter reference for collision exclusion, and one shared-mesh visual. No rigid bodies, projectile areas, or per-shot timers are used.

Each physics step sweeps its short arc chord through Godot's physics space. A curvature bound of `gravity * dt² / 8` subdivides unusually long steps to keep chord error below 0.01 units. At the current 30 Hz rate and authored gravity, one ray per shot suffices. The first collision consumes the shot. An opposing ship takes five damage; allied ships and island colliders consume it without damage. Only the firing ship is excluded. A shot remains independent after its shooter or target disappears.

Range is targeting distance, not arc length. Misses continue falling until impact or the eight-second lifetime, and can hit another ship beyond targeting range. Terrain and water have no colliders. The visible ball uses point collision, and chords test against the current physics snapshot; this is not continuous collision between arbitrary-speed moving shapes. Supported ship speeds and crossing targets are covered by the focused check.

## Targeting and movement

[`ShipCombat`](../../scripts/ships/ship_combat.gd) selects the nearest living opponent inside the anchor's combat area and retains it until invalid or outside that area. The slice has one vessel category. It chooses an enabled ship-local firing bearing that a mounted weapon can present. Outside engagement distance it approaches a target-relative stand-off goal. Near the engagement band it requests a firing-pass course that would present the selected bearing. The course is retained for six seconds by default, then recomputed; excessive separation or altitude error returns the ship to its approach. The nominal engagement distance is sixty units. Altitude preferences change relative height; they never roll the hull over.

FleetController's **Combat Radii** property defines a shared three-dimensional area around the persistent anchor for both factions. X defaults to **180 units**, where inward steering starts; Y defaults to **260 units**, where a ship breaks off pursuit and returns until inside X again. Keep `0 < X < Y`. Within the band, a smooth weight blends combat velocity toward the anchor and biases newly selected firing passes toward inward courses using only enabled, usable bearings. The return state persists across target loss or equipment changes, preventing immediate pursuit from undoing regrouping. Targets outside Y cannot be selected for pursuit.

Regrouping follows the anchor's velocity and uses the same island routing, ship avoidance, thrust, turn limits, and momentum as other movement. It does not clamp positions or velocity, so turns and obstacle detours can temporarily carry ships past the outer radius. Mounted weapons continue their normal range/cone/ballistic checks, including pass-by shots outside the pursuit area. Red debug lines point to the anchor during regrouping. All boundary calculations use current anchor-relative positions, including after rebasing.

The authored Kestrel set follows the literal request: `front_left`, `left_back`, `back`, `back_right`, `right`, `front_right`. This remains asymmetric: `left` is absent and `back` is present. The aft bearing is kept in the authored set but cannot be selected for these two outward cones, because neither cannon can fire from it.

Combat supplies only preferred movement. [`ShipFlight`](../../scripts/ships/ship_flight.gd) applies thrust and yaw torque to the rigid hull along its primary movement axis while retaining momentum, after island detours and ship separation modify the course. Combat cannot independently turn the hull broadside while continuing sideways pursuit. Passes contribute half the ship's maximum speed by default and add the target's engine `linear_velocity`; propulsion demand is then limited by the flight controller. Contacts can transiently exceed commanded speeds and transfer momentum without damage. Preferred bearings are firing opportunities, not rigid poses maintained throughout a turn; weapons still apply their actual cone and ballistic tests.

Near engagement range, a ballistic reachability check can reduce stand-off distance every two seconds, down to twelve units; that reduced distance remains until the target changes. Relative-height goals shrink with it. This makes ships try to close when a nominally in-range target cannot be intercepted; it cannot guarantee catching a faster fleeing target. Without an eligible opponent, players resume anchor-relative travel and enemies brake; any active regrouping finishes first. The capped spawner continues. The player fleet alone controls the average and anchor slowdown. See [flight tuning and checks](movement.md#forward-flight-and-momentum).

Mounted weapons own a firing target independently of ship pursuit. Pursuit changes and target removal preserve each weapon's staggered search deadline, avoiding fleet-wide search bursts. At a staggered 0.2-second acquisition check they prefer a shootable main target, then a retained passer, then nearby alternatives. Reload runs independently: a ready weapon can keep firing at its retained target between acquisition checks. Every shot validates current range, target velocity, and the actual mount cone with a fresh ballistic solution. A closer passer alone does not replace a usable retained target. Disabling pass-by fire permits only the main target. Cooldowns remain per weapon, with no catch-up burst after a stall.

Fallback searches reject out-of-range candidates and those outside a conservative cone expanded for gravity and target lead before ranking. They keep only the nearest untried candidates needed by the remaining four-attempt budget, including main/retained attempts in that budget. Equal distances use stable ship IDs. Failed-attempt IDs persist across searches so moving, unreachable nearby targets cannot starve farther candidates; exhaustion, successful shots, main-target changes, and removals clear the appropriate state. The search may rescan once if its remaining candidates disappeared or left range/cone. It never sorts the full candidate set. The cone filter can only reject impossible shots; exact firing permission still belongs to the ballistic solution and MountedSlot.

## Ownership and cleanup

[`Journey`](../../scripts/world/journey.gd) orchestrates each physics step:

1. Remove previously queued deaths, spawn the scheduled batch, snapshot ships, and advance the player anchor.
2. Rebuild the derived combat-query snapshot, choose combat or travel intent, and calculate ship separation from the common movement snapshot.
3. Route around islands and submit each ship's thrust/lift/drag forces and yaw torque once.
4. Advance existing projectiles, resolve damage, and let surviving weapons fire. New shots begin traveling on the following tick.
5. Unregister and free destroyed ships, then rebase and update scenery/progression.

Force submission does not immediately move the hull. Godot/Jolt integrates rigid-body motion and resolves contacts for the next physics snapshot. Avoidance, aiming, and projectile queries read the latest completed body state; aiming and debug velocity use the body's `linear_velocity`. Hull X/Z rotation is locked while the visual child banks/pitches. Ship control does not overwrite physical transforms or velocities each frame, and projectiles remain scripted point sweeps.

Airship owns health and emits one death signal. Death immediately prevents targeting/firing; Journey removes list entries after active loops, updates all registries, invalidates pursuit, firing-target, and query references, disables collision, and queues deletion. The existing camera falls back to fleet focus when its selected ship exits. IDs are allocated monotonically through Journey. Spawning uses a dedicated RNG and bounded attempts against ship/island clearance.

`health_changed` is the health owner's notification contract, including for later presentation; the slice has no health UI. Synchronous damage from a listener cannot repeat the death notification. `ShipCombat.clear_target()` clears pursuit/pass state while preserving anchor regrouping. A zero-duration Journey step only drains queued deaths and refreshes the fleet average/speed; it does not submit forces, fire weapons, spawn, or stream. It does not pause native physics. Disabling Journey callbacks also leaves inertia active; stationary test fixtures freeze their bodies explicitly.

The projectile root is registered once with FloatingOrigin. Shots store positions relative to that root; both ray endpoints use its current transform. A rebase changes neither velocity nor gravity/lifetime and never creates a long sweep between old and new world coordinates. Scene ownership releases projectiles, visuals, and subscriptions on exit.

`Journey.combat_enabled = false` isolates the existing movement checks from combat and spawning. It is a validation setting, not an in-game pause feature. Navigation debug starts disabled; F3 toggles it. It uses red goals for combat, cyan for ordinary travel, and the existing pink island detours. The purple anchor marker remains visible independently.

## Spatial filtering and measurement

[`CombatPerception`](../../scripts/combat/combat_perception.gd) is a Journey-owned, derived spatial view of living registered ships. It supplies nearby-hostile queries and validity checks; it neither owns ships nor selects pursuit or firing targets. Its 100-unit cells are rebuilt each combat tick. Each searching ship lazily shares one nearby-candidate query among its mounts, with a radius covering the longest equipped range plus muzzle offsets. Individual mounts still filter exact range/cone. Death is checked immediately; unregistering removes membership, the stored cell entry, and cached queries before deletion. The snapshot records each ship's cell so removal remains correct if its position changes afterward. Subsequent rebuilding incorporates spawns, loadout changes, and origin shifts. Snapshot reuse is limited to one combat tick.

ShipAvoidance evaluates each unordered candidate pair once and adds opposite corrections to the two ships. Sorted index traversal preserves accumulation order, and clamping happens after all contributions. The predictive capsule math stays inside the traversal loop because the measured per-pair helper overhead erased the first trial's saving. The old directed calculation exists only as an independent regression oracle in check_combat.gd.

Profiling the 220-ship scene justified two ordinary spatial filters. ShipAvoidance builds a three-dimensional cell map from each physics snapshot. Cell size conservatively covers the largest hull and relative speed over the existing two-second avoidance horizon. Neighbor indices are sorted to preserve the original accumulation order. Before calculating the closest capsule segments, an enclosing-sphere check rejects pairs that cannot interact at the predicted instant. The full-scan calculation remains available as a regression oracle for neighbor filtering.

IslandSpawner owns a two-dimensional cell map of loaded island centers. Its conservative search radius comes from ShipIslandNavigation's existing look-ahead and hull/island clearance. It rebuilds after loading, unloading, or rebasing; the navigation algorithm still performs its exact height and segment tests. Neither filter changes the steering rules or creates another authoritative ship/island registry.

In a short headless 220-ship component sample on the development workstation, ship avoidance decreased from 7.74 to 4.67 ms and island navigation from 8.57 to 1.17 ms per step. These historical scripted-flight samples explain the optimization, not an endgame frame-rate guarantee. `Journey.profile_steps` enables separate decision/query, avoidance, island-navigation, force-submission/candidate-query, projectile, weapon, and cleanup/streaming timings. The `Journey.StepPhase` enum defines the timing slots shared by runtime and benchmark. The [combat performance integration](combat_performance.md) records the current comparison. Native rigid-body integration/contact solving happens outside this script timer. Normal play does not enable these timers.

## Validation

Select checks using [AGENTS.md](../../AGENTS.md); these commands are available coverage, not a required suite for every edit. Follow its serial launches, process-local APPDATA isolation, absolute project paths, and unique external logs. For weapon/impact changes, run the default fixtures:

```text
--headless --path <absolute-project-path> --fixed-fps 30 --script res://scripts/tools/check_combat.gd --log-file <external-log-file>
```

All physics checks and benchmarks use the project's accepted 30 Hz baseline. Scripted deltas and timed scenarios follow that rate; there are no alternate-rate loops or physics overrides. `--fixed-fps 30` accelerates functional runs without changing the physics setting. `check_combat_targeting.gd` checks spatial queries against full scans, shortlist ordering/fairness, removed targets, independent firing/acquisition clocks, and conservative cone rejection against the full solver. It also exercises the composed Journey through death, unregistering, external deletion, equipment replacement, and repeated teardown with live shots. Run it headless with the same isolated environment. The default `check_combat.gd` run ends after its fixtures. Append `-- --extended` only when the three-minute Journey encounter and its spawning/lifecycle checks are relevant.

For rendered inspection, omit `--headless`, append `-- --visual`, and set `AERWYTH_CAPTURE_DIR` to an existing external directory. This explicitly enables the extended encounter and captures a mixed-fleet fight, a close Kestrel view, and `combat-cohesion.png` after three simulated minutes. It covers ballistic reference trajectories, moving/elevated/unreachable targets, tangent roots, cone boundaries, independent instance state, empty and utility-only slots, tier validation, equipment replacement/cleanup, rearming, pass-by fire, ally/scenery interception, shooter removal, expiry, rebasing, capped waves, deaths, camera fallback, and spatial-filter coverage. It also measures ship/mean distances from the anchor and verifies anchor-relative spawns with a displaced average and an origin shift. Select additional movement, island-navigation, or scale checks only when the changed contracts require them.

The opt-in [`check_combat_scale.gd`](../../scripts/tools/check_combat_scale.gd) benchmark runs seventy player Kestrels and 150 enemies, with higher benchmark-only health and scheduled deaths/replacements to sustain the workload. It disables the ordinary debug spawner and includes debug-off/on phases, streaming/camera movement, origin shifts, and a separate synchronized miss-volley phase reaching 1,760 live shots. Misses use the authored launch speed and start 1,000 units above ships to clear scenery. These settings are independent of the ordinary scene's 100-per-faction caps.

For combined rendering/simulation measurements, omit `--headless` and `--fixed-fps`, set `AERWYTH_PROFILE_DIR` to an existing external directory, and run:

```text
--path <absolute-project-path> --script res://scripts/tools/check_combat_scale.gd --log-file <external-log-file> -- --profile
```

The benchmark uses the project physics rate without an override. Native physics, scripted deltas, phase duration, event times, and camera speed stay aligned. Mean script cost per simulated second and elapsed versus simulated durations are recorded alongside percentiles.

This writes `combat-220.json` with hardware, renderer, frame/script-step/GPU percentiles, the sampled engine physics-time monitor, component timings, shot counts, memory/node counts, and effective flight/weapon/rigid-body settings for comparison. It reports the p95 script-step budget separately from functional assertions: a correctness PASS does not mean performance passed. `engine_physics_ms` samples Godot's `Performance.TIME_PHYSICS_PROCESS` monitor, whose reporting is coarser than the per-step script timer; it is not an isolated solver timer and must not be added to script time. Whole-frame measurements include the native integration cost. Debug-off/on phases occur at different stages of the battle, so their difference does not isolate debug drawing cost. Append `--visual` with an external capture directory for a fleet image. Measurements on the development machine do not establish low-end hardware performance.

## Integration audit (2026-09-26)

The audit retained the existing ownership boundaries: Journey registers and sequences ships, ShipCombat chooses pursuit/course, CombatPerception supplies derived queries, mounted equipment owns firing state, and Godot/Jolt owns physical integration. The current Kestrel composition connects those owners correctly. There is no active CharacterBody3D declaration, legacy movement call, alternate integration path, or duplicate linear/angular velocity state. Avoidance, island detours, and desired velocities are still necessary inputs to force control; physical contact response does not replace them.

The audit reproduced and corrected three lifecycle issues:

- Unregistering cleared perception membership but left the object in its spatial cell. A query after deletion could fail while assigning a freed object to the typed iteration variable, before reaching its validity check. The snapshot now records each ship's cell and removes that entry before deletion, even if the ship moved after the snapshot.
- Losing a retained firing target reset its search timer, allowing many ready weapons to search together. Removal now preserves the acquisition phase, as pursuit changes already do.
- Pursuit selection and direct launch validation could still consider a live target queued for deletion. Both now exclude it consistently with perception and retained-target validation.

The regression uses the composed Journey for lethal damage, explicit unregistering, and external deletion; it queries afterward without hiding cleanup errors behind a new snapshot. It also replaces equipped weapons and tears down/recreates Journey with live projectiles, checking for orphan Nodes. These checks, headless import, the existing flight/contact check, and the full three-minute combat/lifecycle check passed. The ordinary encounter reached both 100-ship caps and completed 194 destructions with 28,379 shots. This finite run does not establish session-length stability.

Static reference and UID checks found no missing runtime resource paths, orphan script/shader sidecars, or unreferenced runtime scripts/scenes/resources. The health notification signal, equipment base hooks, and diagnostic counters have deliberate API/test consumers; they are not abandoned controller remnants. The unused Kestrel model remains an intentionally excluded authoring source. Runtime files retain their feature folders, checks stay under `scripts/tools`, and active plans/gates remain under `src/docs/todo`. The benchmark reproduction instructions now name the required `AERWYTH_PROFILE_DIR` correctly.

This is an integration audit of the current slice, not release sign-off. Current measurements are in [combat performance](combat_performance.md); hardware validation, broader loadout planning, release/reliability coverage, and tuning remain tracked in [COMBAT-01–04](todo/todo-combat.txt). The following sections preserve earlier measurements.

## Anchor cohesion validation

These measurements used the earlier ±25-unit spawn altitude spread, before the ±150-unit trial.

The three-minute rendered check with 500-health ships reached 100 players and 100 enemies, fired 28,585 shots, recorded 27,239 damaging impacts, and despawned 184 destroyed ships. Across that run, the farthest ship was 289.36 units from the anchor and the player mean remained within 96.03 units. This includes ordinary island avoidance and an origin shift; the outer 260-unit threshold permits maneuvering overshoot. The focused flight check also passed both factions recovering from horizontal and vertical displacement, pursuit rejection outside the area, inward pass choice, regrouping hysteresis, firing during return, and moving-anchor/rebase behavior.

The run used Godot 4.7.1, D3D12 Forward+, the development workstation below, a 1280 × 800 render target, fixed 60 Hz simulation, and debug drawing off. Scripted steps measured 12.72 ms median / 18.92 ms p95; the p95 exceeds a 60 Hz step budget. These are accelerated check timings, not a real-time FPS guarantee or a controlled performance comparison with earlier encounters. Logs and the inspected `combat-cohesion.png` capture are in the external `aerwyth-cohesion-058f7b1301804de99285f1a7e6342d75` task directory. Performance follow-up remains in the [combat task list](todo/todo-combat.txt).

## Forward-flight trial validation

These measurements precede the 500-health, 100-per-faction debug spawning update.

The scripted flight trial passed headless imports; focused 30/60/120 Hz flight checks; rendered flight and combat inspection; the existing movement/input, island-navigation, and 128-ship checks; and the headless 220-ship combat workload. A stationary-target pass produced 109 eligible firing samples over forty simulated seconds while keeping movement within 25 degrees of the propulsion axis for every sampled tick above 3 units/s. That scenario verifies approach/pass behavior, not a guarantee about all encounters. Its trajectory capture shows the curved course with bow directions overlaid.

With the current authored 100-unit/s cannon and 65-degree cones, the rendered ninety-second encounter produced 191 shots, 186 damaging impacts, one allied interception, and sixteen ship deaths. Its scripted step measured 0.50 ms median / 0.82 ms p95. The 128-ship travel check reached 742 goals, routed forty ships around the fixture island, and measured 3.57 / 4.88 ms median/p95.

The headless fixed-60-Hz 220-ship trial measured scripted steps of 17.31 / 22.69 ms median/p95 in its first combat phase, 13.71 / 17.45 ms in the later phase, and 6.59 / 8.44 ms for synchronized miss volleys. All 220 ships remained registered through replacements; the miss workload peaked at 1,760 shots and cleared completely. These are simulation measurements without rendering, not FPS measurements, and the changing encounter state prevents treating phases as a controlled debug-cost comparison. Dense-combat steps exceeded a 60 Hz CPU budget on this workstation.

Logs and captures from this trial use the external `aerwyth-flight-*` task directory; the corresponding executable is Godot 4.7.1 on the same development workstation as below.

## Recorded validation and limits

The initial measurements below predate the forward-flight trial and later authored cannon/cone tuning. They are historical baselines, not a controlled comparison of the new controller.

Measured on 2026-09-25 with Godot 4.7.1, D3D12 Forward+, Ryzen 7 9800X3D / RTX 4090, a 1920 x 1080 render target, 60 Hz physics, and uncapped rendering. The final rendered ninety-second ordinary encounter produced 377 shots, 170 damaging impacts, three allied interceptions, and fifteen ship deaths. Its scripted simulation step measured 0.50 ms median / 1.02 ms p95. The enemy cap held at thirty. This check's fixed simulation rate makes those step timings useful, but its accelerated rendering is not a real-time frame-rate measurement.

The separate uncapped 220-ship run produced:

| Phase | Step median / p95 | Wall-frame median / p95 | GPU median | Peak shots |
| --- | ---: | ---: | ---: | ---: |
| Combat, debug off | 16.56 / 21.18 ms | 11.99 / 151.09 ms | 0.66 ms | 523 |
| Combat, debug on | 13.68 / 15.79 ms | 31.95 / 50.97 ms | 1.57 ms | 190 |
| Synchronized misses, debug off | 6.11 / 7.15 ms | 1.52 / 8.56 ms | 0.38 ms | 1,760 |

The two combat phases occur sequentially and have different positions and projectile counts; their difference is not an isolated measurement of debug overhead. Uncapped rendering includes frames without a physics step. Conversely, over-budget physics causes multiple catch-up steps before a rendered frame, accounting for severe stalls during dense fighting. **The 220-ship fight does not meet a stable 60-FPS budget on this machine, and the low-end endgame target is not signed off.**

In the debug-off combat phase, mean component times were 7.07 ms for ship avoidance, 4.22 ms for weapons/projectiles, 2.03 ms for island routing, 2.36 ms for body movement and candidate lookup, and 0.57 ms for decisions. Dense neighboring ships and weapon search/aiming remain the main CPU work. The isolated miss-volley result shows that high cannonball count alone does not explain the combat stalls. GPU batching or a physics-body rewrite is not justified by these measurements.

The scale run included ten explicit deaths/replacements, origin shifts, 4,316 damaging impacts, and 3,125 allied interceptions. Godot's tracked static-memory peak was approximately 126 MiB and the node-count peak 6,498, including queued visual cleanup; this is not total process or GPU memory. Clearing projectiles left zero projectile records and zero visual children. This finite run does not establish long-duration stability or performance on other hardware/export configurations.

Headless editor imports, rendered combat checks, movement/input checks, island routing/collision/rebase/unload checks, the 128-ship movement check, and the rendered 220-ship workload passed. The 128-ship movement step measured 3.25 ms median / 3.79 ms p95 after spatial filtering, with the same 752 reached goals and 38 detouring ships as the prior baseline. Captures were inspected for mixed-faction tint, mounted primitive cannons, projectiles, and the large fleet. Logs, captures, and raw JSON remain outside the repository in the task's `aerwyth-combat-493711388e9d44f8ab791834214fe794` temporary directory.
