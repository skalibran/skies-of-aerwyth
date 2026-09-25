# Rigid-body integration and comparison

Implemented on `combat-rigid-body-3d`, compared with CharacterBody3D commit `644e50a`. The [scripted-flight review](combat_review.md) retains its original measurements. This trial changes motion/contact ownership while preserving the authored flight response, combat rules, ships, equipment, spawn layout, terrain, and camera/anchor behavior. Active acceptance work lives in [movement tasks](todo/todo-movement.txt) and [combat gates](todo/todo-combat.txt).

**Accepted on 2026-09-25:** the user chose rigid-body movement after playtesting because it feels much better. RigidBody3D is the maintained controller. The historical comparison below does not imply a runtime controller toggle or a retained CharacterBody implementation. Performance acceptance remains separate.

These measurements precede the [predicted-projectile comparison](projectile_comparison.md), which increases the cannon demonstration rate from 0.5 to 5 shots per second and changes projectile hit rules. Its results use a different benchmark-only health value and separate projectile/weapon timers; the tables below remain the original controller comparison.

## Controller and contact behavior

[`ship.tscn`](../../scenes/ships/ship.tscn) now supplies a RigidBody3D hull, inherited by Kestrel. [`ShipFlight`](../../scripts/ships/ship_flight.gd) computes primary-axis thrust, separate lift, lateral drag, and yaw torque. Forces are scaled by mass and yaw torque by actual inertia to retain the existing acceleration and turning units. Godot/Jolt owns integration, velocity, and capsule contact response. There is one controller and no per-frame position/yaw/velocity assignment or retained copy of angular velocity.

The shared hull has mass 10, friction 0.2, bounce 0, gravity scale 0, and replacement damping of 0. Sleeping is disabled for actively commanded ships. Pitch/roll are physically locked; the visual child still pitches and banks within its existing limits. Off-center impacts can turn the hull about Y. Contacts exchange momentum between ships without damage, and solid islands remain static obstacles. Speed/rate settings limit propulsion demand; external impulses and retained sideways momentum can exceed them while control forces recover the requested course.

Journey submits forces once per physics tick. Navigation, aiming, and projectile queries consume the latest completed engine state. Engine integration/contact solving happens outside Journey's script timer. Disabling Journey callbacks alone leaves inertia active; isolated stationary fixtures explicitly freeze their bodies. Floating-origin shifts are occasional coordinate translations with interpolation resets, and preserve both linear and angular velocity. [Movement notes](movement.md#ownership-and-update-order) and [combat notes](combat.md#ownership-and-cleanup) describe the runtime order.

| Comparison point | Result of this trial |
| --- | --- |
| Feel/result | Forward propulsion, gradual turns, momentum, lift, and firing passes remain. Contacts now push and induce yaw; hulls stay upright. Automated checks establish behavior, not a preferred hands-on feel. |
| Maintainability | Flight computes forces; the engine resolves integration and contact momentum. No custom collision response or duplicate velocity state. Tests must advance engine physics and freeze fixtures explicitly when needed. |
| Intent | Preserves controllable, sluggish airborne ships while allowing physical interactions. Gravity-free upright hulls are deliberate constraints, rather than a full buoyancy/aerodynamics simulation. |
| Performance | Dense combat remains CPU-limited. The measured workload is slightly slower in its early phase and has substantially longer catch-up stalls in its later phase. This refactor is not a performance optimization. |

## Replacement audit

The acceptance audit found no CharacterBody3D declarations, legacy movement calls (`move_and_slide`, `move_and_collide`, `get_real_velocity`), old `move_ship`/`flight.integrate` entry points, or duplicated yaw-velocity state in active scripts/scenes/resources. Kestrel inherits the rigid base scene; Journey has one force-submission path. Runtime ship linear/angular velocity is read from the engine, with no controller assignments to either property. Transform writes affecting physical hulls are initial placement and floating-origin translation; the regular attitude writes affect only the visual child. Explicit velocity/transform assignments in checks set up controlled fixtures.

One structural remnant was removed: Airship still allocated a ShipFlight instance after its only state, scripted yaw velocity, had disappeared. ShipFlight now exposes static helpers, preserving the force calculations without an otherwise empty object per ship.

The remaining navigation/control code has distinct responsibilities:

- Preferred velocity is travel/combat intent; navigation velocity records island routing for control/debug. Neither is a second physical velocity.
- Ship avoidance predicts close approaches, and island routing plans detours. Physical contacts handle actual impacts; they do not choose a route or a passing side.
- Thrust, braking, directional drag, lift, and yaw feedback define the flight response. Native damping is explicitly disabled so it does not duplicate the authored drag.
- Snapshot arrays and hull extents support avoidance; full scans are exercised as a spatial-filter regression oracle. They do not integrate or resolve body contacts.
- Visual pitch/bank remains presentation while hull pitch/roll are locked. The persistent anchor has its own scripted translation because it is not a physical ship.

The older CharacterBody references in review documents and completed task history preserve measurements and decisions; there is no legacy controller kept for execution. The accepted controller still assumes upright capsule hulls, as documented in [movement notes](movement.md#forward-flight-and-momentum).

After removing the per-ship helper allocation, headless import, flight/contact checks, and the long movement/input simulation passed. The broadside fixture retained 109 firing samples and the same trajectory result; the four encounter clearances were unchanged. The accelerated flight check emitted the intermittent Jolt job-pool warning already documented in the movement notes, then completed successfully. Cleanup logs are under `%TEMP%/aerwyth-rigid-cleanup-3f8d4f6c15104cacb773afff06ba1d7d`; this structural cleanup was not separately performance-benchmarked.

## Performance comparison

Godot 4.7.1 development executable, D3D12 Forward+, Ryzen 7 9800X3D / RTX 4090, 1920 × 1080, 60 Hz physics, uncapped rendering. The fixture uses 70 players and 150 enemies, 5,000 benchmark health, fixed initial positions, ten scheduled replacements, camera movement, origin shifts, and an isolated 1,760-shot miss phase. It is deliberately denser than ordinary spawning.

Every configuration key present in the saved baseline JSON matches this run except the controller identity. New keys additionally record mass, friction, bounce, gravity, and angular locks. These are paired workload measurements, not identical simulated trajectories: the changed contact/integration behavior changes positions and firing outcomes. One run per controller does not establish a statistical cost difference or isolate the native solver's cost.

| Phase | Character script median / p95 | Rigid script median / p95 | Character wall-frame p95 | Rigid wall-frame p95 |
| --- | ---: | ---: | ---: | ---: |
| Early combat, debug off | 17.65 / 21.16 ms | 18.15 / 22.31 ms | 158.90 ms | 164.60 ms |
| Later combat, debug on | 11.28 / 16.43 ms | 13.44 / 17.70 ms | 35.42 ms | 136.35 ms |
| Isolated miss volleys | 6.48 / 8.09 ms | 6.72 / 8.76 ms | 9.68 ms | 9.82 ms |

The Character timer included synchronous `move_and_slide()` work. The rigid timer covers force submission but excludes subsequent native body integration/contact solving. It must not be read as total physics cost. The rigid run also records Godot's sampled `Performance.TIME_PHYSICS_PROCESS` monitor: median/p95 20.02/26.26 ms in early combat, 16.34/21.14 ms later, and 9.79/14.72 ms in the miss phase. This monitor is coarse, includes broader physics-frame work, and must not be added to the script timer or used as an isolated solver timer.

Wall frames include engine integration, rendering, and catch-up batches. Crossing the 16.67 ms physics budget creates disproportionate frame stalls, especially in the later combat phase where the prior controller was nearer the threshold. Uncapped rendering also includes frames without a physics tick. Sequential debug phases have different encounter states and cannot measure overlay overhead in isolation. GPU p95 was 2.92 / 3.56 / 0.72 ms across the three phases.

Early-combat mean script components were 8.04 ms avoidance, 4.79 ms weapons/projectiles, 2.16 ms force submission plus candidate queries, 1.94 ms island routing, and 0.75 ms decisions. Existing dense-fleet CPU costs remain. COMBAT-01 stays open; the low-end target and release export are not signed off.

The run fired 11,371 shots, recorded 6,278 damaging hits and 2,408 allied interceptions, and completed ten scheduled deaths/replacements. Peak live shots were 131 / 87 / 1,760. Peak tracked static memory was about 129.1 MiB; peak node count was 6,936, including pending visual cleanup. Clearing projectiles left no shot records or projectile children. These finite checks do not establish session-length stability or total process/GPU memory usage.

## Validation and reproduction

- Headless editor import completed without script/resource errors.
- Rendered movement/input checks passed, including stable anchor views, F3, selection, zoom, bounds, travel, and rebasing.
- Headless movement simulation passed long travel through eight origin shifts, slowdown/recovery, membership changes, and four crossing/overtaking encounters. The worst sampled hull overlap in those encounters was 0.067 units, within the existing 0.3-unit tolerance.
- Island checks passed: blocking capsule queries, routing, penetration checks, cap clearance, over/underflight, moving goals, rebasing, and unloading.
- Actual-physics flight checks passed at 30/60/120 Hz. Equal/unequal mass contacts conserve combined momentum, off-center contact induces yaw, hulls remain upright, and health remains unchanged. Large external impulse/spin recovers through forces; unobstructed propulsion settles to its speed/lift limits. Live-body rebasing survives subsequent physics updates.
- The stationary-target broadside pass retained 109 eligible firing samples and full measured forward alignment, with closest approach 60.62 units (scripted baseline 60.75).
- The 128-ship travel check reached 733 goals with 40 detouring ships; script time was 3.40 ms median / 4.16 ms p95. The scripted baseline reached 742 goals with 40 detours at 3.46 / 4.12 ms; rigid timings exclude native integration.
- The rendered 220-ship workload and 1,760-shot miss/cleanup assertions passed. Its functional PASS does not indicate that its performance budget passed.

The rendered three-minute ordinary battle also passed ballistic, equipment, faction, spawning, lifecycle, camera fallback, and cohesion checks. It reached 100 ships per faction, fired 26,953 shots, recorded 25,789 damaging hits and 879 allied interceptions, and removed 181 destroyed ships. Maximum anchor distance was 315.01 units; maximum player-mean distance was 120.46. Script time was 8.46 ms median / 10.22 ms p95, compared with the baseline's 8.30 / 10.06 ms; native integration is outside the rigid script timer. Peak observed speed was 19.24 units/s with an 18-unit/s propulsion target. The old absolute speed-cap assertion was replaced by isolated impulse-recovery and sustained-propulsion checks, since hard-clamping collision velocity would defeat this trial's contact behavior.

The configured main scene also completed a rendered startup run without errors. Inspected captures show the curved forward-flight pass, mounted primitive cannons, distinct faction tint, the persistent anchor marker, and a vertically spread battle with debug hidden.

Use the serial launch, isolated APPDATA, and external log requirements in [AGENTS.md](../../AGENTS.md). The existing [combat profile command](combat.md#validation) reproduces the dense workload; omit `--fixed-fps` for performance measurements. Flight/contact checks use `--script res://scripts/tools/check_ship_flight.gd --fixed-fps 60`, with `-- --visual` and external `AERWYTH_CAPTURE_DIR` for the trajectory capture.

Trial logs, captures, and `combat-220.json` are outside the repository under `%TEMP%/aerwyth-rigid-trial-f876138993d647298061478415676881`. The baseline remains under `%TEMP%/aerwyth-combat-review-fce53ca8070742aaaaee805db87decad`. [Godot's RigidBody3D documentation](https://docs.godotengine.org/en/stable/classes/class_rigidbody3d.html) describes force-driven integration; [Performance documentation](https://docs.godotengine.org/en/stable/classes/class_performance.html) describes the engine monitor and its sampling limitations.
