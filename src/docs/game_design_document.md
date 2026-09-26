# Skies of Aerwyth — Game Design Document

Status: Initial design draft based on the founding game concept. This document records intended behavior, not implementation progress. Details marked **TBD** remain open, especially incremental progression and meta systems.

## High concept

Skies of Aerwyth is an incremental steampunk fantasy airship autobattler with a voxel visual style. A fleet travels through a single continuous 3D space in one direction, fighting increasingly difficult enemy waves and liberating floating islands along the way.

The player sustains the fleet by expanding island production, preparing replacement airships, buying urgent reinforcements, and choosing vessels and weapons that counter the enemies ahead. Pre-made ships support the full game; custom weapon configurations reward experimentation and can help the fleet advance faster.

## Design pillars

- **Continuous journey:** The fleet advances while fighting, bringing new encounters as distance increases. Distance traveled brings greater danger and opportunities to expand production.
- **Preparation versus urgency:** Producing ships commits resources in advance and takes time. Buying ships with money provides quick support when prepared reserves are insufficient.
- **Composition and counters:** The right vessels and weapons matter alongside the size and strength of the fleet.
- **Accessible experimentation:** Players can rely entirely on pre-made ships or save custom configurations using existing hulls and their weapon mounting spots.
- **Growth across a journey:** Each liberated island increases production until a wipe. Wipes unlock further meta progression, whose mechanics remain TBD.

## Core loop

1. Automatically fight enemy waves and advance through the continuous 3D world while new waves arrive at distance milestones.
2. Reinforce the traveling fleet with purchased ships or ships drawn from prepared batches.
3. Pass floating islands to liberate them and gain places to build production facilities and access natural resources.
4. Expand production and use resources to produce airships over time, replenishing their respective batches.
5. Adjust fleet composition and optionally create custom ship configurations to counter harder encounters and push farther.
6. Continue growing production and advancing until a wipe, which opens further meta progression. The wipe trigger and subsequent restart rules are TBD.

These activities overlap during the journey. Reinforcement and island management support the fleet throughout combat and travel.

## World, travel, and encounters

One world unit is one meter. The tenfold [unit conversion](world_units.md) preserves the prototype's proportions, appearance, and timing.

The fleet's journey proceeds forward along Z- through one continuous 3D space; Z+ leads back toward previously passed locations. A persistent fleet marker acts as the journey's "main character." Its logical Z position determines progression, content placement, and increasing difficulty. Camera movement and changing fleet membership do not directly change progression.

Journey progression has a numeric value: forward distance traveled by the marker, in meters, starting at zero. Derive it from the marker's logical position relative to the journey start; floating-origin shifts and viewing another location do not add distance. Terrain is the first system to use it: start among grasslands and gradually transition into mountain ranges. Transition distances are authorable. Each location uses its own distance along the journey, so revisiting it restores the same landscape rather than applying the fleet's current biome everywhere.

The fleet travels around one persistent fleet marker. It advances linearly toward Z- during both travel and combat, with fixed X and altitude. Living enemies and pending reinforcements keep combat active while the marker continues forward. Clearing the encounter changes local destination selection without restarting marker motion. There is no return or regrouping state.

### Fleet marker and airship movement

Endgame play targets roughly seventy friendly ships and 150 enemies. The marker centers a sphere whose size grows with the hull footprints and maneuvering requirements of all living friendly and enemy ships. Only the friendly fleet governs travel pace. Growth is smooth; casualties do not shrink a battle around surviving ships. Terrain heights and supported fleet sizes are authored to keep terrain below this navigation volume; terrain avoidance is not part of ship navigation. The marker is independent of the ship average, so membership changes cannot move the camera or trigger a wave.

Ships choose nearby destinations inside this sphere, with meaningful vertical variation. Destinations move with the marker, and navigation includes its velocity. Combat and travel share one navigator. Combat scores feasible local maneuvers for weapon presentation and range, while target choice remains independent: a priority opponent across the sphere can be approached through successive nearby destinations. The target-priority system remains planned; the current selector retains its nearest eligible opponent.

Navigation anticipates braking, turning, hull clearance, obstacles and separation before requesting motion. Ships never intentionally choose destinations outside the sphere. Momentum or contacts may displace a body; the same navigator then guides it inward without a separate return state. Collision-free alternatives must also fit inside the sphere. Route selection first accounts for intended marker translation and tries slower viable paths when needed. If geometry blocks every available friendly route, ships brake and the marker waits.

Heavy airships retain forward propulsion, gradual yaw, limited lift and visual banking. Rigid-body physics owns momentum and contacts, with no contact damage. The marker's travel speed leaves maneuvering room for its slowest member and slows preventively when a trailing member cannot keep up. This does not delay travel after combat clears. Relative navigation carries the sphere and local destinations forward during combat.

The current runtime and tuning are described in [fleet movement](movement.md). Camera focus, scenery streaming, floating origin, and progression all use the persistent marker. Floating islands remain obstacles throughout the journey; the volume is a navigation constraint, not an invisible physical wall.

### Encounters

Enemy difficulty increases with distance through:

- Larger waves containing more enemy airships.
- Stronger individual enemy airships.
- Boss battles.

Threat increases every 500 meters of forward journey progress. Each increase currently schedules a wave whose budget follows an authorable threat curve. Ships have explicit loadout costs; weighted spawn entries contain either a ship or a complete fleet preset, with fleet cost equal to its members' sum. The generator selects affordable entries, allows leftover budget, and limits repeated selections. Costs and weights are independent. Optional authored wave overrides guarantee copies of these same ship/fleet entries: each guarantee either consumes budget or spawns on top, and random filling can be disabled for a wholly authored wave. Guaranteed entries remain guaranteed even when they exceed the budget. See [implemented encounter contracts](encounters.md).

Combat is automatic. The player's central decisions concern fleet composition, weapon configurations, production, and reinforcement timing.

The same targeting, engagement, and weapon-slot firing rules apply to friendly and enemy vessels. Enemy travel after eliminating the player's fleet has no gameplay role: when no friendly ships remain, the failure condition is reached. The failure response, recovery options, and relationship to a wipe remain TBD.

**TBD:** Travel speed, the marker slowdown curve, fleet spread and navigation distances, avoidance clearance, turn and acceleration limits, final threat/budget tuning, boss cadence, formations, and detailed combat movement.

### Continuous coordinates and persistence

The continuous journey uses logical world positions separately from the coordinates used for nearby rendering and physics. A floating origin periodically recenters the active scene without changing logical positions, progress, relative distances, or ongoing movement. Logical Z is represented by a signed segment index and a small offset within the segment, so a long journey does not require huge scene coordinates.

Only nearby content needs a loaded 3D scene. Passed islands retain their identity, route position, buildings, resources, and production state after their scenes unload. During normal fleet play, unloaded liberated islands continue participating in the economy. Loading or unloading a view must not start a second production simulation.

Savegames preserve versioned gameplay state: the marker's logical position, active ships and relevant simulation state, encounter and milestone state, island records, resources, and production queues. Stable entity IDs reconnect references on load. The scene origin and loaded visual nodes are replaceable presentation details. Loading restores the active region near a fresh local origin and must not repeat already completed encounters or island liberation. Persistent profile data and current-journey data remain distinct; what survives a wipe is still TBD.

## Camera and fleet controls

The player uses an orbit camera that can snap its focus to a selected ship or the persistent fleet marker, then follow that target while orbiting it. Fleet tracking uses the marker so spawning or losing ships does not shift the camera with the calculated ship average.

- Mouse clicking a ship selects it and snaps the camera focus to that ship. Controller ship selection remains **TBD**.
- WASD or the controller's left thumbstick releases tracking without a camera jump and enters free flight within the fleet viewing area. Free rotation turns around the camera's own position, as in an FPS camera; forward/back movement follows the view direction and left/right strafes.
- With keyboard and mouse, hold the right mouse button while moving the mouse to rotate the camera. Releasing the button stops mouse-driven rotation; this is a hold action, not a latched toggle.
- The controller's right thumbstick rotates the camera without a mouse-button modifier.
- Mouse scroll zooms toward or away from the tracked fleet/ship by changing orbit distance. Controller D-pad up/down provides continuous zoom. Zoom is inactive in free flight.
- Holding Shift or LT increases orbit zoom speed and free-flight movement speed. It does not change look sensitivity. Free flight permits looking above and below the horizon without flipping.
- A fleet-focus action restores fleet tracking. If a followed ship disappears, fall back to fleet tracking.

Ordinary fleet camera movement is constrained to a sphere centered on the persistent fleet marker. This includes released camera movement and ship tracking; the viewing area follows the marker without shifting when fleet membership changes. Ordinary panning, orbiting, or selecting a ship does not pause gameplay. The separate island-view transition described below can leave this viewing area.

In free movement, the camera retains an offset from the persistent fleet marker and inherits its translation, so the fleet does not leave the camera behind while the player looks around. Looking rotates at the camera's own position; movement input changes the offset. Both translation and viewing bounds use the marker, keeping the view stable as ships maneuver or membership changes.

The slowest member, trailing hull clearance, and blocked routes regulate the marker's travel speed. No ship average drives movement, camera tracking, or progression.

**TBD:** Camera distance and angle limits, pan/rotation speeds, viewing-sphere radius, controller ship selection, and keyboard/controller bindings for the fleet-focus action.

## Target priorities and pass-by fire

### Vessel target priority

Each vessel has a predefined ordered target priority. Its **main target** determines which opposing ship it pursues and engages. The priority model follows Dungeon Directive's party-member targeting:

1. Consider the available opposing vessels inside the marker's engagement area.
2. Select the nearest vessel in the highest-priority category that currently has candidates.
3. If no configured category has a candidate, select the nearest remaining opponent. Unlisted categories remain valid and rank after the configured categories.
4. Keep the current target while it remains valid, unless an opponent from a higher-priority category becomes available. A closer opponent of equal priority alone does not cause a switch.
5. Select again when the target is destroyed, leaves the engagement area, or otherwise becomes invalid. With no eligible opponents remaining, immediately choose a nearby ordinary navigation destination and continue forward travel.

Priority is a preference order, never a category exclusion rule. Every opposing vessel inside the engagement area remains a possible target, so a vessel continues fighting even when none of its preferred categories are present. Both fleets use this model, with predefined priorities appropriate to their vessels. The spatial pursuit boundary does not restrict weapon-slot pass-by fire.

**Reference:** Dungeon Directive's [party-member target controller](../../../dungeon-directive/scripts/party_members/target_controller.gd) implements category ordering, nearest-candidate selection, fallback targeting, and retention of a valid target within its priority category. Its [NPC target controller](../../../dungeon-directive/scripts/actors/actor_target_controller.gd) uses threat scoring; Aerwyth's rule above applies the vessel priority model to both sides.

**TBD:** The actual priority categories, each vessel's predefined order, and whether players can later edit those priorities.

### Preferred combat positions

Each ship has an authored set of enabled **preferred combat positions**: **front, front left, left, left back, back, back right, right, front right, front up, up, back up, back bottom, bottom, and front bottom**. These describe desired bearings to the main target relative to the engaging ship's own orientation during firing opportunities. Ships maneuver through those bearings while respecting weapon range, obstacle avoidance, forward propulsion, momentum, and limited pitch and banking; they need not hold an exact target-relative position throughout a pass. Up and bottom preferences use relative altitude rather than requiring the ship to roll over or perform a loop.

For the combat slice, author the enabled set within the ship scene. A later visual ship editor will show an arrow for each position so the player can toggle it as an allowed preference. Kestrel's intended role is left/right broadside combat; its exact enabled set is tracked in the [combat runtime notes](combat.md).

**TBD:** Final positioning distances, selection and retention of an enabled position, and how positioning balances that preference with available slot cones and obstacle avoidance.

### Weapon-slot pass-by fire

Each weapon slot has a configurable **fire at targets in range** option, enabled by default. With this option enabled, the mounted weapon can fire on opposing targets within its range while the vessel moves toward its main target. This allows pass-by fire against other ships encountered en route.

Weapons retain a usable firing target and reacquire at bounded intervals independently of reload. Acquisition prefers a shootable main target, then the retained passer, then nearby alternatives. Each shot uses current target motion and the actual slot cone. The weapon's firing target can differ from the vessel's main target. Pass-by fire does not itself change which ship the vessel pursues. Disabling the option makes that slot focus on the vessel's main target and wait until it can fire at that target within range.

Weapon range and the slot's authored firing cone still apply. The cone governs angular firing permission; the weapon governs distance. The ship's own hull and balloon do not impose an additional obstruction test. The option permits opportunistic attacks; it does not make every opposing ship simultaneously attackable. Friendly and enemy weapon slots follow the same rules and default.

**TBD:** Final acquisition cadence and detailed targeting rules for specialized weapons such as anti-projectile systems. Current fallback searches rank a bounded shortlist of nearest untried candidates and remember failures across searches.

## Floating islands and production

Floating islands appear occasionally along the route. Once the fleet has passed an island, it is taken over and becomes available for development. Liberated islands continue contributing to production after the fleet has moved onward, until a wipe.

Islands contain natural resources and support simple production buildings. Initial examples include farms, fields, shipyards, logging facilities, and masonries. These examples establish the economic direction; the complete building catalog and production recipes are TBD.

Each liberated island increases the production available during the current journey. Island development supports the ongoing need to prepare ships and keep the fleet advancing.

**TBD:** Island spacing, building costs, construction times, placement rules, island capacity, resource types and deposits, depletion, production chains, and storage limits.

### Revisiting and managing passed islands

An island overview provides access to liberated islands, including those far behind the fleet. Selecting an island opens its management view, where the player can inspect it and edit buildings and production according to the eventual building rules. Building placements are relative to the island. Both its journey appearance and its management view reflect the same persistent island state.

The camera transition creates the impression of traveling back through the continuous world:

1. Release fleet or ship tracking and accelerate backward along Z+ toward dense cloud.
2. Fully obscure the view inside the cloud, concealing the switch to the selected island's local viewing space.
3. Emerge from cloud with consistent apparent motion, decelerate, and center on the island.
4. To return, accelerate forward along Z-, repeat the cloud transition, and restore the previous fleet or ship tracking mode. If the previously followed ship is unavailable, use fleet tracking.

The camera travels a short distance at each end; the cloud conceals the skipped distance. The destination must be ready before the cloud clears. A short transition independent of the island's actual distance preserves the impression without requiring a long wait. Each viewing space remains close to its own origin.

Gameplay pauses when this island transition carries the view away from the fleet, stays paused throughout island management and the return transition, and resumes once the fleet view is restored. This pauses the whole gameplay simulation: marker movement, all simulated entity positioning, combat, spawning, production, construction, and other gameplay timers. No elapsed gameplay time is accumulated for catch-up on return. Camera controls, the transition, and management UI remain usable; edits can be made, but timed work does not advance. Future purely visual or atmosphere animations may continue independently.

This pause is specific to visiting an island. Ordinary fleet camera movement remains within its viewing sphere and never triggers it. Island management, cloud transitions, and their pause behavior belong to a later milestone, outside the initial movement prototype.

**TBD:** Island overview layout, editing controls, transition duration and presentation, and the precise departure point at which the island transition pauses gameplay.

## Economy and reinforcements

The player can call for reinforcements while the fleet travels through two routes:

| Route | Cost or preparation | Purpose |
| --- | --- | --- |
| Direct purchase | Spend in-game money to buy a ship. | Obtain quick support without waiting for a new production cycle. |
| Production batch | Commit resources to producing airships over time, then call ships from their respective batch of completed vessels. | Prepare reserves ahead of demand. |

A **batch** is the available stock of produced airships for the corresponding ship type or configuration. Production fills that stock over time; calling a ship from it consumes a produced vessel. How batches distinguish base hulls from saved configurations is TBD.

The ongoing economic tension is between spending resources ahead of need, spending money for quick support, and preparing the right counters. Stocking the wrong ships can leave the fleet poorly suited to an encounter even when reserves are available.

**TBD:** Money sources, prices, resource recipes, production durations, production queue rules, batch capacity, deployment timing, active fleet limits, and any additional cost for calling a produced ship.

## Vessels and weapon configurations

Vessel hulls are pre-built platforms. Each owns designated mounting spots labeled **S1, S2, S3, ...**. Mounted slots have tiers starting at **tier 1** and may be empty or assigned a weapon or utility of the matching tier. Slot labels identify individual mounts; their numbers are separate from tier. The ship owns each slot's position and firing cone, while assigned equipment owns its visuals and behavior. Pre-made ships provide a starting loadout of these reusable equipment pieces.

Each mounted slot has an authored **3D firing cone**. This cone alone governs angular shoot/no-shoot permission, replacing runtime obstruction checks against the firing ship's hull and balloon. Author the mount, muzzle, and cone to avoid visually firing through the model. The cone does not set distance; range belongs to the mounted weapon. These rules apply to both main-target fire and pass-by fire. Fired projectiles can still strike other ships or collidable scenery.

Each slot also exposes the default-enabled [pass-by fire option](#weapon-slot-pass-by-fire), independently of the vessel's predefined main-target priority.

Players can mount different compatible weapons and utilities on a vessel and save the resulting configuration as a new ship. Customization combines existing vessels and compatible equipment; the core concept does not require players to construct hulls themselves. Specific utility effects remain TBD.

Pre-made ships must be sufficient to play the entire game. Custom configurations provide room to discover useful combinations and advance faster without making ship design mandatory.

For example, a player could equip a fast, light vessel with anti-projectile weapons to push through a screen of projectile spam. This illustrates the intended interaction between hull properties, weapon choice, and enemy threats; its exact combat mechanics and balance are TBD.

**TBD:** Further hull and weapon catalogs, higher-tier compatibility rules, final authored cone angles, additional weapon statistics, refitting costs and timing, the configuration editor, and how saved ships become available for purchase and production.

## Wipes and incremental progression

Liberated islands accumulate production during a journey. That accumulated island production lasts until a wipe, and a wipe unlocks additional meta progression.

The incremental systems are intentionally **TBD**. No specific prestige currency, upgrade tree, permanent multiplier, or offline progression system is established by this draft.

Open decisions include:

- What triggers a wipe, and whether it is voluntary, forced, or both.
- How a wipe relates to fleet defeat.
- Which resources, vessels, islands, and unlocks reset or persist.
- Whether saved ship configurations persist across wipes.
- What meta progression unlocks and how it changes later journeys.
- Whether idle or offline progress exists and how it is calculated.
- What long-term milestones or completion goals exist, if any.

## Visual direction

The game uses a **voxel style** in a **steampunk fantasy** setting. The world, airships, floating islands, weapons, and production buildings should share that direction within the continuous 3D space.

Terrain currently trials **50-meter cubic voxels**, with 100-meter or 10-meter terrain available for comparison. Detailed assets use **1 meter per voxel**, with rough asset shapes ten times that size. Nearby terrain should reveal cubic steps; distant rendering may simplify geometry while keeping the source grid and logical landscape fixed.

The fleet travels above a noise-generated 3D voxel landscape with stepped hills and valleys. Terrain is primarily scenery, with basic collision on full-detail patches for downed ships; destruction and terrain editing are not required. Heights and elevation-based colors are authorable; a secondary noise layer varies the color-band boundaries so the same elevation can show neighboring bands instead of perfectly uniform contour stripes. The initial implementation uses FastNoiseLite and exposed voxel-column surfaces, with no need for caves or overhangs.

Downed ships descend slowly onto full-detail landscape, settle briefly, then freeze. Authorable smoke sources trigger on death, using growing and fading camera-facing square particles, and stop when the wreck first lands. Keep wrecks for 20?30 seconds after landing (current default: 25). Wrecks are visible only over source-grid terrain; hide them over coarse or unloaded patches without forcing detail or pinning chunks. Their coordinates remain stable across origin shifts. Behavior when falling into water remains TBD.

Terrain begins as rolling green grassland with a generous height range (currently -300 to 700 in 50-meter steps), then blends into taller mountain terrain with rocky elevation bands. Mountains should have broad bases, rising slopes, and sharp, tapered summits and crests rather than thin, wall-like noise ridges. Mountain valleys should stay above sea level, with exposed water confined to grassland and the transition. Use warped landforms with restrained local irregularity, and avoid excessive contrast that clips hilltops into large flat plateaus. Blend both landform heights and palettes smoothly across a long, authorable travel interval (currently 1500 to 10000 meters). Later scenery may place models using terrain height and noise, such as trees concentrated in valleys. Vegetation models, placement rules, and additional biomes remain TBD. Terrain stays at fixed logical world positions as nearby chunks load, unload, and follow floating-origin shifts.

Water sits at **Y = 0**. Terrain may extend below zero so low basins form ponds, bounded by the stepped voxel shoreline. Use a flat surface with authorable depth-color bands, lighter shallows, and restrained square-pattern animation that matches the voxel art direction. Water is scenery; water physics, destruction, and underwater gameplay are outside the current scope.

The current sky is blue, with subtle atmospheric haze to convey height and scale. Fog ramps up more strongly near the distant landscape edge to conceal its cutoff while preserving the visible blue sky. Terrain and water share the horizon treatment; see [horizon haze](terrain.md#horizon-haze) for the current authoring settings.

The current UI layout follows Dungeon Directive's master shell: a 1920 x 1080 logical canvas, uniform scaling, and three centered 1920-wide zones with 140/800/140 heights. Top and bottom follow the viewport edges while the center stays centered; ultrawide views reveal side space and taller views separate the zones. The zone hosts are invisible layout regions; their feature views supply the visible UI. The top region contains ship count and FPS. The bottom region has five size classes, smallest to largest: Skiffs, Corvettes, Frigates, Cruisers, and Dreadnoughts. Selecting a class filters a single horizontally scrollable row; Kestrel belongs to Skiffs. Clicking a ship currently creates one friendly vessel at a random clear position near the marker, without production or purchase costs. Plain shared-theme styling uses spacing in multiples of four logical pixels, with two-pixel borders allowed. See [UI layout and scaling](ui.md) for implemented ownership and aspect-ratio checks.

**TBD:** Final orbit-camera framing, palette, lighting, cloud-transition effects, UI style, animation, and audio direction.

## Initial movement prototype

The first implementation milestone establishes movement and camera behavior using primitive geometry:

- A reusable ship scene shared across factions, hulls, and weapon configurations, initially shown as two primitives forming a zeppelin envelope and gondola.
- An orbit camera with mouse ship selection, fleet/ship tracking, scroll/controller zoom, released FPS-style free flight, a Shift/LT speed boost, and a spherical fleet viewing boundary. Compare marker and average-position fleet tracking.
- A reusable floating-island scene, independent of its eventual resources and building spots, represented by primitives with approximate capsule collision. Islands spawn throughout the route at varied heights, and ships navigate around them.
- The persistent fleet marker, size-aware navigation sphere, local ship destinations, close-range avoidance, and sluggish airship movement.
- Toggleable in-world navigation debug showing the fleet sphere, local destinations, arrival radii, requested velocity, and actual velocity.
- Floating-origin travel along Z- with occasional island spawning and bounded loading of nearby scenery. Additional content, such as clouds, comes later.
- Streamed voxel ground scenery below the fleet, with noise-generated heights and authorable, varied color bands.

Combat systems, island management and travel transitions, their gameplay pause, production, on-screen UI, and a complete save/load system are outside this milestone. The coordinate and ownership choices must support the documented later systems. Implemented system contracts and validation are recorded in [movement runtime notes](movement.md) and [terrain notes](terrain.md). The gameplay rules in this document remain design intent unless their implementation is recorded there.

## Combat vertical slice

The combat milestone's implemented ownership, tuning, and validation are recorded in [combat runtime notes](combat.md). Use string-based player/enemy faction identities and a Kestrel derived from the shared ship scene, using its authored voxel model with the balanced palette at one meter per voxel and retaining its movement baseline. Tint enemy models reddish as a placeholder. Each Kestrel carries one tier-1 slot on either side of its hull, each mounting a **Rusty cannon** with **1000-meter range**, **5 damage**, and a converted reference baseline of **200 m/s projectile launch speed** (current authored trial: 1000 meters/second). Both sides have **500 health**, and use the same targeting, positioning, and firing rules.

Cannonballs follow gravity-driven ballistic arcs, with weapons calculating elevation and lead for moving targets before firing. Scripted flight and hit detection follow the same curve; Godot rigid bodies are not required. The slot cone constrains the initial launch direction, including elevation and lead. Rusty cannon favors the earliest intercept and a low arc, using authorable stylized gravity that permits its 1000-meter level shot at the specified launch speed. Range measures muzzle-to-target distance, while an independent lifetime allows the longer curved flight; targets within range can still be ballistically unreachable. Gravity and lifetime tuning are recorded in the combat plan.

The playable journey starts with three friendly Kestrels and adds threat-budget enemy waves every 500 meters, without automatic casualty replenishment. Swift (Skiff), Manta (Corvette), and Bastion (Frigate) use distinguishable primitive hulls with different health, flight tuning, and cannon counts. All are available to the enemy pool and friendly picker. The repeating capped debug encounter remains confined to opt-in combat validation tools with normal waves disabled. Friendly projectile impacts consume the projectile without damaging the ally. Rusty cannons emit brief muzzle-smoke bursts; the effect can be assigned to other selected cannon scenes. Impacts have no visual explosion effect. Destroyed ships stop flight control, retain their momentum and collider, and fall under 0.2-times project gravity (19.6 meters/s²) with native damping. Authored death-smoke emitters leave trails of camera-facing squares while airborne and stop on first ground contact. Wrecks continue rebasing, settle for three seconds before freezing while supported, and expire 25 seconds after first ground contact. Wrecks without ground contact expire after 45 seconds. Wrecks and smoke remain hidden over coarse terrain. Water-specific wreck behavior, production, production-backed or purchased reinforcements, and the visual ship editor remain later work. Journey progression continues during combat, allowing distance-based waves to overlap.

In the opt-in combat fixture, center both factions' spawn region on the persistent marker, independent of the ship average and camera: initially 1000–1500 horizontal meters away and within 1500 meters above or below its altitude. Reject overlaps with ships and loaded islands using bounded placement attempts.

Measure the combined combat workload at roughly **70 friendly ships and 150 enemy ships** as an endgame target for low-end hardware. This benchmark is independent of the playable three-ship starting fleet. Begin with ordinary readable optimizations; further low-level work depends on profiling. Ship health values, reload cadence, final cone angles, and engagement distances remain provisional authoring choices.

## Scope of this draft

The continuous journey governed by combat, escalating encounters, predefined vessel target priorities, optional pass-by fire enabled by default, shared combat behavior for both fleets, island takeover and production, two reinforcement routes, pre-built hulls with compatible weapon spots, saved custom ships, and voxel steampunk fantasy direction form the current design foundation.

Numerical balance and the open decisions above require further design. Update this document as those decisions are made; do not treat the TBD entries as approved implementation requirements.
