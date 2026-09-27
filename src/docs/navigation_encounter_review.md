# Navigation and encounter audit

Reviewed 2026-09-26 after the persistent-marker refactor, continuous combat travel,
budget encounters, and F3 sphere integration. This review covers those changes,
not whole-game release readiness. Ownership and content layout are coherent. The
initial large-fleet obstacle regression was reproduced and resolved in the route
follow-up below; living enemies now contribute to navigation space.

Remaining movement-feel and threat-pool decisions live in the
[navigation and encounter follow-ups](todo/navigation-encounters.txt). Hardware,
release reliability and broader combat acceptance belong to the separate
[combat task list](todo/todo-combat.txt). Unhandled enemies accumulating until player
defeat is accepted gameplay. Terrain heights and supported fleet sizes keep terrain
below the navigation volume by content design; terrain avoidance is outside this
refactor. Journey saves and export readiness are whole-game work.

## Ownership and wiring

| Responsibility | Owner |
| --- | --- |
| Living ships, physics tick order, collision-safe placement and registration | Journey |
| Persistent marker, all-faction occupants, friendly members, radius and travel pace | FleetController |
| Bounded local goals, separation, containment and island route checks | ShipNavigation |
| Retained pursuit target and preferred firing-bearing scores | ShipCombat |
| Forces and yaw torque; physical momentum and contacts | ShipFlight; Godot/Jolt |
| Distance-derived progress | JourneyProgress |
| Consumed milestones, composition RNG and queued placement | EncounterDirector |
| Pure budget selection and guaranteed ship/fleet expansion | EncounterPlanner |
| Authored costs, options, presets and overrides | Typed resources under resources/ships and resources/encounters |
| Announcements, threat lines and F3 geometry | UI/world/fleet presentation reading the above owners |

Both factions use the same navigator and flight controller and contribute to sphere
size. Only friendlies govern marker speed or whether the player fleet is empty. Wave placement uses Journey's existing
spawn path, setting faction and identity before readiness and registering navigation,
combat, death and origin behavior once. The composition RNG is independent of
placement. The director does not mutate authored resources. Wave UI listens to the
first successful spawn, while threat boundaries use the profile's milestone spacing.
F3 has one enabled state shared by the sphere and per-ship geometry.

No retired ShipTravel, ShipIslandNavigation, FleetAnchor, FleetAverage, return-state,
or wave-destination runtime path remains. Static resource paths resolve, script UID
sidecars have corresponding sources, and local documentation targets/anchors were
checked. EncounterPlanner and ShipNavigation are referenced by their registered
class names, not scene resources. CombatSpawner remains deliberately isolated under
scripts/tools as an explicitly stepped stress fixture. Plan selections, goal counts,
wave_planned and spawn counters have validation/profiling consumers and were retained.

## Contained fixes

- Combat presentation previously predicted heading from the local waypoint alone.
  A rearward waypoint could be scored as a backward-facing hull even while the
  marker's forward velocity made flight retain its forward heading. Scoring and
  turn prediction now use the same world-velocity request as navigation.
- Island filtering previously bounded lookahead by propulsion speed alone.
  The bound now includes actual relative momentum after contacts, the route back
  into the sphere, and the retained goal as well as newly sampled goals.
- Named navigation cadence/clearance constants replace repeated magic values.
  Friendly spawning and safe sphere contraction use the same hull margin.
- Removed the unconsumed threat_changed signal and a no-op zero-duration fleet call.
  Renamed the old island-navigation profiler phase to navigation because it now
  measures the shared navigator.
- Removed the completed combat integration brief from active TODOs, corrected
  obsolete average/2600-meter descriptions, and repaired stale documentation links.
- The combat-scale cleanup assertion now accepts only idle reusable smoke batches
  after all shot visuals are freed. The old assertion incorrectly required zero
  children, conflicting with the implemented smoke cache.
- The fleet-scale diagnostic counts blocked ships every tick and labels that count
  accurately; its old two-second sampling missed brief stops and called them detours.
  Its travel-progress requirement was preserved.

## Initial audit verification

Godot 4.7.1, project physics rate 30 Hz. All engine launches used isolated APPDATA,
absolute project paths and separate external logs. Focused passing checks:
ship flight (including moving-heading regression), island navigation (including
displaced/high-momentum query bounds), movement/input, encounter planning and
placement, combat fixtures, target/equipment lifecycle, and UI catalog/spawning.
Final editor import and resource/documentation consistency checks passed.

The initial 128-ship check failed its retained progress requirement: **488.82 meters in
30 seconds, required more than 1800**. Eight ships report blockage at least once;
736 local goals are reached. Repeated brief obstruction stops reset marker speed
near the authored route island. The diagnostic script-step median/p95 were
4.82/7.42 ms in the final headless run; low CPU cost does not resolve this gameplay
failure. This was NAV-01; the follow-up below resolves it without lowering the threshold.

The 220-ship combat/miss-volley workload passed its final headless functional run:
70 friendlies, 150 enemies, ten replacements, origin shifts, 4679 damaging impacts,
and the 1760-projectile peak with cleanup. Its rendered run used the same runtime
and completed the gameplay workload; it exposed the stale smoke cleanup assertion,
which was then corrected and rerun. The rendered capture was inspected.

One rendered desktop sample, Ryzen 7 9800X3D / RTX 4090, Forward Plus, 1920 x 1080:

| Phase | Script step p95 | Wall frame p95 | GPU p95 |
| --- | ---: | ---: | ---: |
| Combat, debug off | 14.13 ms | 12.82 ms | 1.04 ms |
| Combat, debug on | 15.07 ms | 18.68 ms | 1.82 ms |
| Miss volleys, debug off | 10.38 ms | 11.24 ms | 1.21 ms |

These script percentiles fit the 33.33 ms physics budget, but exclude native
integration/contact solving. The engine physics monitor also reported higher
tails (about 53-55 ms during combat); it overlaps script work and is not additive.
Debug phases occur at different battle stages. A single desktop sample, including
one capture, does not establish release, long-session, or Steam Deck acceptance.
The later retained-goal query-bound addition was verified with the focused island
and movement checks; these scale timings are not a separate measurement of that addition.

The authored random pool was independently evaluated at waves 29 and 100: both
spend 324 points on 20 ships, despite budgets of 435 and 1500. This is the exact
consequence of current repetition limits, not a random-selection failure.

Local audit logs, diagnostics, the rendered capture and combat-220.json:
`C:/Users/lukas/AppData/Local/Temp/aerwyth-navigation-threat-audit-1790453421455/`.

## Route and sphere follow-up

Journey now separates marker preparation from advancement. Navigators plan against
intended travel and report a safe marker speed; FleetController applies the friendly
minimum before moving on that same tick. This removes the dependency on whether the
marker happened to be stopped on the previous tick. Final steering validates again
at the actual resulting pace and discards unsafe separation corrections.

Selection checks both the nearby goal segment and the combined world-motion course
before scoring. Explicit lateral and vertical choices supplement random samples.
Lookahead includes braking, turning and time to clear an island's inflated radius
at local movement speed. That last term starts broad detours early enough to avoid
repeated late slowdowns. Slower viable routes allow continued local flight; complete
blockage stops travel and clears automatically when geometry permits movement.
Height checks use only the portion of the segment overlapping an island's vertical
bounds, so a rising or descending course can clear its footprint. Queries still use
the cached island grid and cover the longer lookahead, contact momentum and displaced
hulls. No global route planner, terrain avoidance, or out-of-combat speed boost was
introduced.

FleetController keeps all living ships in `occupants` for footprint and maneuvering
room, and friendlies in `members` for propulsion and route pace. The later
[arrival boost](movement.md#arrival-boost) replaces the trailing-clearance slowdown,
allowing distant ships to catch up while the marker continues moving.
Enemy registration cannot shift the marker; enemy deaths remove their footprint via
Journey's existing lifecycle. Growth remains gradual, combat prevents contraction,
and an empty friendly fleet stops even if enemies remain.

At 30 Hz the unchanged 128-ship fixture now advances **2431.50 meters in 30 seconds**
against the retained requirement of more than 1800. It reaches 858 local goals and
reports no completely blocked ship. Existing bounded-goal, hull-clearance, camera,
streaming and rebase assertions pass. Headless script-step median/p95 are
16.77/22.65 ms; the additional routing work costs more CPU than the initial failing
implementation. These timings exclude native physics and rendering.

The focused flight, movement, island and encounter checks pass, including same-tick
complete blockage, nonzero slower routes while the marker is stopped, clearance
recovery, over/underflight, rebase stability, enemy growth without pace influence,
and removal of enemy footprints on death. The editor import is clean. A rendered
encounter run also passes; marker-battle and mixed-fleet captures were inspected.

The final 220-ship combat/miss-volley check passes with all 220 occupants registered,
70 friendly pace members, ten replacements, 4719 damaging impacts and the
1760-projectile peak. Headless script-step p95 is 26.11 ms with debug off, 27.62 ms
with debug on, and 18.74 ms for miss volleys, against the 33.33 ms physics interval.
These are desktop script measurements, not whole-frame or low-end hardware approval.
The earlier rendered performance table is historical and does not measure this
follow-up's route planner.

Follow-up logs, diagnostic route traces and inspected captures:
`C:/Users/lukas/AppData/Local/Temp/aerwyth-route-recovery-1790454804601/`.
