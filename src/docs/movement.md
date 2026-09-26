# Fleet movement

## Persistent marker

`FleetController` owns one authored `FleetMarker` in [Journey](../../scenes/world/journey.tscn). The purple four-meter cube marks the center of the fleet's navigation sphere. It starts at `(0, 3800, 0)`. Its X and Y never follow ship positions; ordinary travel changes only Z, toward Z-. There is no averaged fleet-center node, jumping destination anchor, or regrouping state.

Journey progression, camera tracking and viewing bounds, scenery streaming, water coverage, and origin rebasing all reference this same marker. Membership changes cannot teleport it or advance progression. A next encounter is a route milestone, not another movement owner.

`EncounterDirector.is_combat_active()` supplies fleet-wide combat state: enabled pending spawn plans or any living hostile hold combat active. Disabling Journey combat bypasses that state. The marker continues moving during combat, blocked placement, and partly spawned waves. Combat state still prevents sphere contraction and refreshes navigation when the encounter clears; it does not change travel speed. An empty friendly fleet stops.

Forward steps cross wave milestones without capping speed. The director consumes each crossed milestone on the next physics tick. Waves can overlap while previous enemies remain alive. See [encounters](encounters.md) for scheduling and guarantees.

## Sphere size and travel pace

The starter minimum radius is 180 meters. `required_radius()` takes the larger of that minimum, maneuvering room for the least agile hull, and a footprint-based size: 1.5 times the square root of the sum of `(enclosing hull radius + spacing)^2` for every living ship. Default spacing is 35 meters. Large ships need more room than small ships; both friendly and enemy hulls contribute through `FleetController.occupants`. The separate `members` registry contains only friendlies and governs travel pace and whether the player fleet is empty.

Radius changes at 30 meters/second. Growth is permitted during combat. Contraction waits until combat has ended and every surviving hull fits within the requested smaller sphere, including its safety margin. Goals reserve the ship's enclosing hull radius plus eight meters inside the fleet boundary.

Cruise speed is 25 m/s with 3 m/s^2 acceleration. It is limited by the slowest member's maximum speed minus the 12 m/s local maneuver allowance. A trailing friendly ship near the boundary reduces travel speed. Each friendly navigator also reports a safe marker speed for its obstacle route; the smallest allowance limits travel. An enemy route cannot slow the marker. These are continuous preventive constraints, not a return phase or an out-of-combat speed bonus. The marker has no simulated inertia and can stop immediately without changing ship momentum.

## Navigation

Each Airship owns one [ShipNavigation](../../scripts/ships/ship_navigation.gd). Its destination is an offset from the marker. The same navigator handles travel, combat, island clearance, separation corrections, and containment. ShipTravel and the separate island-detour controller have been removed.

A ship samples up to 32 nearby candidate destinations, normally one 50-meter step from its local sampling center, including explicit lateral, vertical, forward and inward choices plus its retained goal. Candidates must fit inside the sphere with hull clearance. Both the short waypoint segment and its combined world-motion lookahead must clear nearby island capsules before scoring. Lookahead reserves braking/turn time and the time local movement needs to clear an island's inflated radius, so a broad detour begins before slowing is necessary; lift is limited to the actual climb speed. Scoring favors manageable turns and inward movement when predicted momentum approaches the edge. On arrival, a fresh destination produces natural movement within the fleet. Changing combat state or selected target also refreshes the destination. While moving, combat destinations are reconsidered every three seconds, or sooner on arrival or a target change. Displaced ships and enemies entering from outside sample inside the sphere and approach it through this same controller.

Combat adds target-relative range and weapon-presentation scores. Its nominal engagement range is limited to 75% of the fleet radius. Distant targets favor approach; nearby targets favor a usable authored firing bearing. Presentation scores and turn prediction use the requested world velocity, including marker travel, rather than treating a local waypoint as the ship's heading. A rearward local destination can slow forward travel without turning the hull backward. Target selection remains separate from local destination choice. The current selector retains the nearest eligible opponent it acquired; a future priority selector can supply an opponent anywhere in the sphere, and the navigator advances toward it through successive nearby goals. Local step distance never filters targets. Opponents within the sphere plus the 600-meter entry band can influence combat; firing permissions remain with mounted weapons.

Desired velocity combines marker velocity with local movement. Ship separation is considered before final containment and island clearance. Containment predicts using current relative speed, braking, and yaw response, then limits the requested relative endpoint to the sphere. This anticipates turns and reduces outward commands before reaching its edge. The marker translates during combat, carrying the sphere and every local destination forward.

**The guarantee concerns intentional navigation.** Every authored destination is inside the sphere, including obstacle alternatives. Momentum and contacts may carry a physical hull outside; its navigator then requests inward movement. No body positions or velocities are clamped to the boundary. Planning first tries the intended marker pace, independently of its current stopped or reduced speed. If needed, it retries at 75%, 50%, 25%, then zero of that pace. A viable slower route permits continued local movement; if no candidate route is available, the ship brakes. A friendly route with zero travel allowance holds the marker, and a later clear route releases that constraint through normal marker acceleration. The local sampler is not a global route solver; geometry that blocks every route within the sphere can halt travel.

Island candidate filtering covers the full sampled goal segment and the maximum steering lookahead. Its braking bound includes actual world and relative momentum plus intended travel, including contact speeds above the propulsion limit; displaced hulls also reserve the distance back to their local sampling center. This preserves the spatial cache while keeping relevant islands available for exact path checks. The exact island check intersects horizontal clearance with the segment's overlapping height interval, allowing a climb or descent that clears the island before reaching it. Terrain is outside navigation by design: authored terrain heights and supported fleet sizes keep it below the navigation volume. Large scale fixtures deliberately exceed normal content bounds. The runtime does not enforce terrain separation.

## Forward flight and momentum

Airships remain upright `RigidBody3D` hulls. Godot/Jolt owns position, linear/angular velocity, and contacts. [ShipFlight](../../scripts/ships/ship_flight.gd) submits mass-scaled propulsion, lift and lateral drag, plus inertia-scaled yaw torque. Turning builds and brakes gradually; poor alignment reduces forward thrust. Altitude has separate lift control. The navigator uses the same yaw and braking tuning to anticipate boundary maneuvers.

Kestrel's authored limits are 50 m/s speed, 5 m/s climb, 4/6 m/s^2 acceleration/braking, 12?/s yaw, 10?/s? yaw acceleration, and 0.7/s lateral drag. Contacts can exceed commanded limits temporarily and transfer momentum without damage. Death removes all flight control and restores passive wreck physics, as described in [combat](combat.md). Scene placement and floating-origin translation are the only routine transform assignments.

## Ownership and tick order

1. Journey removes queued deaths, processes friendly spawn requests, and steps authored encounters.
2. FleetController prepares sphere size, combat state, and intended travel speed from friendly propulsion and trailing clearance. It does not move the marker yet.
3. Airship evaluates its selected opponent and prepares navigation. Shared separation reads one completed physics snapshot for all ships.
4. Each navigator plans its bounded obstacle route against intended travel and reports a safe speed. FleetController takes the friendly minimum and advances the marker once.
5. Projectiles resolve lethal impacts. Each living navigator revalidates its goal for the actual marker motion, applies separation, and checks the final contained course. Invalid separation is discarded; another bounded goal is tried when the base route is blocked. ShipFlight submits control once; mounted weapons validate and fire independently.
6. Journey removes casualties, shifts registered roots when needed, and refreshes progression and scenery. Native physics integrates the submitted forces.

IslandSpawner retains its cached spatial query. Ships keep no island waypoint references; unloading geometry cannot strand an old route. Relative goals survive a 10240-meter origin shift unchanged, as do physical velocities and RNG state.

## Camera and debug

Fleet camera focus and its 9000-meter viewing sphere use FleetMarker. Free flight inherits marker translation while preserving its offset and independent view. Following an individual ship also remains inside that viewing sphere. The initial orbit is 600 meters; wheel zoom changes by 25 meters and controller zoom uses 300 m/s.

| Input | Behavior |
| --- | --- |
| Left click a living ship | Follow that ship. |
| WASD / left stick | Free flight; forward follows view elevation. |
| RMB + mouse / right stick | Orbit a tracked target or look in free mode. |
| Wheel / D-pad up/down | Zoom while tracking. |
| Shift / LT | Triple movement and zoom speed. |
| F3 | Toggle the navigation sphere, ship goals, and velocity arrows. |

UI focus reserves camera input; Cancel or world pointer input releases it. Losing application focus releases mouse capture. `focus_fleet()` and the `camera_focus_fleet` action exist without a default keyboard/controller binding. Mouse selection is the current ship-selection input.

The marker cube stays visible independently of F3. Navigation debug starts hidden; F3 toggles the purple sphere together with travel goals in cyan, combat goals in red, the final requested velocity in orange, and actual velocity in green. [FleetNavigationSphere](../../scripts/fleet/fleet_navigation_sphere.gd) draws a sparse wireframe of latitude and meridian rings, centered on the marker and scaled to FleetController's current radius. Its unit mesh is built once and inherits marker travel, physics interpolation, and origin shifts. These visuals only read navigation state and consume no randomness.

## Validation

Use the absolute paths, isolated process APPDATA, and external logs required by [AGENTS.md](../../AGENTS.md). Focused scripts run with `--headless --fixed-fps 30 --script res://scripts/tools/<check>.gd`; physics remains at the project's 30 Hz.

- `check_movement`: fixed marker axes, continuous combat travel, uninterrupted milestone crossing, growth from both factions, friendly-only pace, safe contraction, trailing/empty-fleet stopping, camera input, UI focus, debug, and rebasing.
- `check_ship_flight`: physical thrust/turning/braking, contacts, impulse recovery, passive wrecks, bounded combat and separation, inward recovery, and approaching a selected far-side target despite a nearer opponent.
- `check_island_navigation`: bounded obstacle choices, world-motion detours, safe slowing at intended pace, same-tick blockage/recovery, clear over/underflight, rebase stability, and unloading.
- `check_encounters`: normal travel through two milestones, overlapping waves, bounded goals during moving combat, pending-spawn combat state, plus encounter content and scheduling.

For rendered inspection, run `check_encounters` without `--headless`, set an external `AERWYTH_CAPTURE_DIR`, and append `-- --visual`. `marker-battle.png` shows the marker, navigation sphere and combat destinations. Scale/performance and long travel are separate opt-in checks; earlier measurements do not validate this navigation implementation.
