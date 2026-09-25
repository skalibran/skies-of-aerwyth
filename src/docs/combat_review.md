# Combat and movement production review

Historical CharacterBody3D baseline at commit `644e50a`. The measurements and ownership descriptions below describe that revision; the [rigid-body trial](rigid_body_trial.md) records the subsequent refactor and comparison.

Reviewed 2026-09-25 after the forward-flight, anchor-cohesion, 500-health, and vertical-spawn changes. **The current Kestrel slice is coherent and understandable as a scripted-flight baseline. It is not signed off for production or endgame performance.** Active blockers and acceptance criteria live under COMBAT-01–04 in the [combat task list](todo/todo-combat.txt). The [movement task list](todo/todo-movement.txt) owns the rigid-body comparison.

## Ownership and integration

| Owner | Responsibility and boundary |
| --- | --- |
| [Journey](../../scripts/world/journey.gd) | Registers ships and orchestrates one ordered physics step: spawns, snapshot/anchor, intent, avoidance/movement, existing shots, new shots, death cleanup, rebase/streaming. Only this owner chooses combat versus travel. |
| [FleetController](../../scripts/fleet/fleet_controller.gd) | Owns player membership, the moving anchor, average-based slowdown, and shared combat radii. The average changes anchor speed; it cannot reposition the camera or spawn region. |
| [ShipCombat](../../scripts/ships/ship_combat.gd) / [ShipTravel](../../scripts/ships/ship_travel.gd) | Supply preferred velocity. Combat owns its target, firing-pass state, and regrouping hysteresis; travel owns anchor-relative goals and its RNG. Neither moves the body directly. |
| [Airship](../../scripts/ships/airship.gd) / [ShipFlight](../../scripts/ships/ship_flight.gd) | Airship owns health and physical velocity. Flight integrates forward thrust, lift, momentum, and yaw. Island routing and ship separation adjust intent before one `move_and_slide()` call; post-contact velocity feeds the next step. |
| [MountedSlot](../../scripts/ships/mounted_slot.gd) / [MountedWeapon](../../scripts/weapons/mounted_weapon.gd) | The ship owns slot placement/tier/cone; assigned equipment owns its model, aim, cooldown, and bounded searches. A weapon may shoot at a passing opponent without changing the ship's target. |
| [Ballistics](../../scripts/combat/ballistics.gd) / [ProjectileController](../../scripts/combat/projectile_controller.gd) | Shared trajectory math connects aim and flight. Projectiles own captured damage/faction and swept point collisions; the weak shooter reference is only for collision exclusion. A shot survives shooter removal. |
| [CombatSpawner](../../scripts/combat/combat_spawner.gd) | Debug-only population driver: two ships per faction per simulation second, separately capped at 100, with bounded clearance attempts around the anchor. No defeated-side shutdown or progression is implied. |
| [FleetCamera](../../scripts/camera/fleet_camera.gd) / [FloatingOrigin](../../scripts/world/floating_origin.gd) | Fleet tracking/bounds use the persistent anchor. Explicit root registration shifts ships, scenery, camera, and the projectile root once; target references, local goals, and shot-local positions survive translation. |

The main scene connects these owners through typed exported references. Kestrel inherits the base ship and equips two otherwise empty reusable slots; the cannon has no Kestrel dependency. Equipment definitions and meshes are shared while health, targeting, cooldowns, and projectile state remain per instance. Faction, ID, and health configuration precede tree entry; position and Journey registration follow readiness. Live faction switching is outside the implemented contract.

The code retains a few deliberate seams: the health signal is the requested health notification API, the base equipment no-op methods support utility assignments, the full avoidance scan supports spatial-filter checks, and the timing/search counters have profiling or regression consumers. These are distinct from abandoned state. No parallel legacy facing controller or fleet-average camera selector remains.

The audit found no missing static resource paths across 55 runtime/check/scene/resource files, no orphan script/shader UID sidecars, and no missing script/shader sidecars. The root `todo-combat.txt` no longer exists; the active file is under `src/docs/todo`. Unused Kestrel model sources/import settings and existing authored scene/terrain values were preserved.

## Contained fixes completed

- Prevented duplicate death signals when a `health_changed` listener applies lethal damage during another damage call. Only the call that crosses zero emits death.
- Made zero-duration Journey steps drain deaths and refresh fleet state without moving bodies or firing. `move_and_slide()` otherwise uses the engine's nonzero physics delta even when the caller supplies zero.
- Renamed combat's misleading `reset_loadout()` to `clear_target()`: it clears pursuit/pass state and deliberately retains regrouping, without changing installed equipment.
- Removed the unused projectile source ID, aggregate impact counter, and weapon last-launch vector. Retained and exercised the solve counter to check bounded searches and fallback candidate rotation.
- Restored the shared cannon's display name from the generic `Equipment` default to `Rusty cannon`.
- Added a conservative sphere rejection before the exact predicted capsule-segment calculation. It does not change the prediction time or steering rule.
- Updated the scale tool to capture effective flight/weapon/mount settings and report performance separately from functional correctness. Its miss workload uses the authored launch speed and clears scenery; the previous 20-unit/s, lower-altitude fixture did not represent the current weapon speed and occasionally hit islands.
- Corrected the documented spawn lifecycle ordering and kept active production work in the task directory.

## Validation

Godot 4.7.1 headless editor imports and the following checks passed, with isolated APPDATA and serial launches:

- Rendered combat checks, including the new nested-damage, zero-duration, search-budget, and candidate-rotation regressions; equipment replacement, ballistics, friendly interception, deaths/refills, camera fallback, and rebasing.
- Rendered movement/input checks, including F3 default/toggle behavior and stable anchor-based views through membership changes.
- Flight checks at 30/60/120 Hz, broadside firing passes, and regrouping recovery. The stationary-target pass retained 109 firing samples and full measured forward alignment.
- Island navigation, contacts, capsule-cap clearance, over/underflight, detour rebasing, and unloading.
- The 128-ship movement workload: 3.46 ms median / 4.12 ms p95 scripted step, 742 reached goals, and 40 detouring ships.
- The rendered 220-ship combat workload, scheduled deaths/replacements, and 1,760-shot miss/cleanup workload. Its functional assertions passed; its dense-combat performance budget did not.

A temporary comparison against the prior exact avoidance implementation checked 4,608 randomized ship cases, including varied capsule sizes, headings, velocities, density, and rebasing. Of these, 2,713 produced nonzero steering; maximum difference was zero. The dense combat runs before/after retained identical shot, damage, friendly-hit, and death counts.

A separate temporary content probe reproduced COMBAT-02: a valid weapon with speed 4 and gravity 3 on a ship with engagement distance 60 selected a target but produced an empty bearing and no combat movement. This is a planner limitation for other authored loadouts, not a failure of the current 100-unit/s Kestrel configuration.

The ordinary three-minute, 500-health encounter reached 100 ships per faction, fired 26,835 shots, recorded 25,777 damaging hits and 758 friendly interceptions, and removed 175 destroyed ships. Its scripted step measured 8.30 ms median / 10.06 ms p95. Maximum ship distance from the anchor was 409.56 units; maximum player-average distance was 121.41. The 260-unit outer combat radius requests regrouping rather than clamping position, so detours and momentum can overshoot it. These finite observations do not establish a hard maximum distance for every obstacle layout.

Captures of the mixed fight, close ships/equipment, final battle distribution, and movement view were inspected. Debug starts hidden, enemy tint remains distinct, the anchor cube remains visible, and spawn/flight activity occupies multiple altitudes. The current 100-unit/s cannon remains much flatter than the original 20-unit/s reference arc.

## Performance results

Development executable, Godot 4.7.1, D3D12 Forward+, Ryzen 7 9800X3D / RTX 4090, actual render target 1920 × 1080, 60 Hz physics, uncapped rendering. The dense fixture contains 70 players and 150 enemies with 5,000 benchmark health, fixed initial positions, ten scheduled deaths/replacements, camera movement, and origin shifts. It differs deliberately from the ordinary 100-per-faction spawner and its wider altitude distribution.

| Workload after fixes | Step median / p95 | Wall-frame p95 | GPU p95 | Peak live shots |
| --- | ---: | ---: | ---: | ---: |
| Dense combat, debug off | 17.65 / **21.16 ms** | 158.90 ms | 2.88 ms | 131 |
| Later combat, debug on | 11.28 / 16.43 ms | 35.42 ms | 2.49 ms | 92 |
| Synchronized misses, debug off | 6.48 / 8.09 ms | 9.68 ms | 0.74 ms | 1,760 |

The debug-off stage is the congested early battle; the debug-on stage runs later after ships spread. Their difference does **not** measure overlay overhead. Uncapped frame percentiles include frames without physics ticks. When steps exceed the 16.67 ms budget, physics catch-up batches produce much longer wall frames; simulation-step time alone is not an FPS estimate. GPU timings are viewport measurements, not complete machine GPU utilization.

The small avoidance change reduced dense-stage mean avoidance time from 8.55 to 7.55 ms and step p95 from 22.45 to 21.16 ms in this paired run. Other dense-stage means were 4.67 ms for weapons/projectiles, 2.46 ms for body movement plus island-candidate queries, 1.89 ms for island routing, and 0.75 ms for decisions. This remains a CPU-limited workload. The isolated miss phase is not evidence that the whole encounter meets the endgame target.

The final scale run recorded 11,315 shots, 6,261 damaging hits, 2,322 friendly interceptions, and ten deaths. Peak tracked static memory was about 128.8 MiB and peak node count 6,942, including queued visual cleanup. Clearing projectiles left zero shot records and zero projectile children. These measurements are not total process/GPU memory, release-export results, low-end measurements, or a session-length leak test.

Logs, captures, the temporary comparison script, and before/after `combat-220.json` files are outside the repository in `%TEMP%/aerwyth-combat-review-fce53ca8070742aaaaee805db87decad` (`baseline/` contains the before sample). The final JSON stores the effective controller, mount, weapon, population, seed, and timing inputs; [combat notes](combat.md#validation) document the repeatable command. No rigid-body implementation or branch comparison is included in these results.
