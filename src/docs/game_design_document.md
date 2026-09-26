# Skies of Aerwyth — Game Design Document

Status: Initial design draft based on the founding game concept. This document records intended behavior, not implementation progress. Details marked **TBD** remain open, especially incremental progression and meta systems.

## High concept

Skies of Aerwyth is an incremental steampunk fantasy airship autobattler with a voxel visual style. A fleet travels through a single continuous 3D space in one direction, fighting increasingly difficult enemy waves and liberating floating islands along the way.

The player sustains the fleet by expanding island production, preparing replacement airships, buying urgent reinforcements, and choosing vessels and weapons that counter the enemies ahead. Pre-made ships support the full game; custom weapon configurations reward experimentation and can help the fleet advance faster.

## Design pillars

- **Continuous journey:** Clearing enemies faster than they spawn allows forward progress. Distance traveled brings greater danger and opportunities to expand production.
- **Preparation versus urgency:** Producing ships commits resources in advance and takes time. Buying ships with money provides quick support when prepared reserves are insufficient.
- **Composition and counters:** The right vessels and weapons matter alongside the size and strength of the fleet.
- **Accessible experimentation:** Players can rely entirely on pre-made ships or save custom configurations using existing hulls and their weapon mounting spots.
- **Growth across a journey:** Each liberated island increases production until a wipe. Wipes unlock further meta progression, whose mechanics remain TBD.

## Core loop

1. Automatically fight enemy waves and advance through the continuous 3D world as the fleet clears enemies faster than they spawn.
2. Reinforce the traveling fleet with purchased ships or ships drawn from prepared batches.
3. Pass floating islands to liberate them and gain places to build production facilities and access natural resources.
4. Expand production and use resources to produce airships over time, replenishing their respective batches.
5. Adjust fleet composition and optionally create custom ship configurations to counter harder encounters and push farther.
6. Continue growing production and advancing until a wipe, which opens further meta progression. The wipe trigger and subsequent restart rules are TBD.

These activities overlap during the journey. Reinforcement and island management support the fleet throughout combat and travel.

## World, travel, and encounters

The fleet's journey proceeds forward along Z- through one continuous 3D space; Z+ leads back toward previously passed locations. A persistent fleet anchor acts as the journey's "main character." Its logical Z position determines progression, content placement, and increasing difficulty. Camera movement and changing fleet membership do not directly change progression.

Journey progression has a numeric value: forward distance traveled by the anchor, in world units, starting at zero. Derive it from the anchor's logical position relative to the journey start; floating-origin shifts and viewing another location do not add distance. Terrain is the first system to use it: start among grasslands and gradually transition into mountain ranges. Transition distances are authorable. Each location uses its own distance along the journey, so revisiting it restores the same landscape rather than applying the fleet's current biome everywhere.

Each vessel pursues and engages its selected opponent while opponents remain. When there are no opponents, it travels with the fleet by navigating around the advancing anchor. Clearing enemies faster than they spawn therefore creates time to make progress; sustained opposition keeps ships occupied with combat and can slow or effectively halt that progress as the fleet falls behind its anchor. Individual ships can move toward combat targets and fire while moving, so battle and movement can overlap.

Every active ship is fighting, moving to engage an opponent, or traveling onward. A ship never waits merely because its preferred target category is absent: target priority orders opponents without excluding any of them.

### Fleet anchor and airship movement

Endgame play should support roughly seventy friendly ships and 150 enemy ships together. Navigation space and camera range must accommodate those fleets while preserving nearby individual maneuvers. This is a scale target, not a new starting fleet size or a fixed ship cap.

The anchor advances continuously along Z- while the journey simulation is running and friendly ships remain. Calculate the average position of the active friendly ships separately. The farther the anchor moves from that average, the more its forward speed decreases; as the ships catch up, it recovers speed. The average regulates the anchor's movement without replacing its position. Adding or losing a ship can affect the speed response, but must not teleport the anchor or advance milestones immediately.

Each ship generates its own navigation destination around the anchor. These destinations move with the anchor. Ships occupy a volume with meaningful vertical spread, and nearby destinations may move up or down as well as sideways and forward/back. On reaching its destination, the ship chooses another within a limited nearby area, producing gentle movement within the fleet. Routine destination changes must not send a ship from the front to the back of the entire fleet. Combat pursuit takes priority over this travel behavior when opponents are present.

Ships avoid one another while allowing fairly close pass-bys. Their movement should convey heavy, sluggish airships: gradual acceleration, braking, and turns, with limited pitch and banking. They must not perform loops, flips, or abrupt model rotations.

Each ship has a primary propulsion direction, normally forward. Heading redirects thrust while existing velocity retains momentum; sideways drift gradually decays. Turning builds and brakes gradually, and sharp course changes reduce forward thrust. Altitude uses separate lift control. Combat and travel use the same flight controller, so a broadside ship approaches and turns into firing passes instead of sustaining sideways pursuit while facing its guns at the target. Momentum should create imperfect, weighty maneuvers without random steering noise. RigidBody3D is the accepted movement implementation after hands-on comparison: thrust and yaw torque guide flight while physics resolves motion and contact momentum. Hulls stay upright with visual pitch/bank, living ships have no gravity, and contacts cause no damage. The earlier scripted controller remains a historical performance baseline; see the [comparison and acceptance record](rigid_body_trial.md).

Combat remains near the persistent fleet anchor. Both factions use an authorable soft engagement boundary: near its edge, favor inward firing passes and gradually steer toward the anchor. Beyond the outer radius, break off pursuit and return inside a smaller radius before resuming combat. Do not pursue opponents outside the engagement area. Weapons may still fire at eligible targets while regrouping, and island avoidance and momentum remain active. The initial inner/outer radii are 180/260 units in three dimensions; these are steering thresholds, not an invisible collision wall or position clamp.

Floating islands occupy a broad surrounding landscape at varied heights above, through, and below the fleet, including directly in its path. The journey should feel like crossing an open world, with scenery beside and behind the fleet as well as ahead. Ships steer around solid islands, temporarily departing from their travel destinations as needed, then resume formation travel. Clear routes above or below an island remain usable. The anchor continues to drive progression and slows according to the existing fleet-average feedback while ships maneuver around obstacles.

### Encounters

Enemy difficulty increases with distance through:

- Larger waves containing more enemy airships.
- Stronger individual enemy airships.
- Boss battles.

Combat is automatic. The player's central decisions concern fleet composition, weapon configurations, production, and reinforcement timing.

The same targeting, engagement, and weapon-slot firing rules apply to friendly and enemy vessels. Enemy travel after eliminating the player's fleet has no gameplay role: when no friendly ships remain, the failure condition is reached. The failure response, recovery options, and relationship to a wipe remain TBD.

**TBD:** Travel speed, the anchor slowdown curve, fleet spread and navigation distances, avoidance clearance, turn and acceleration limits, wave spacing and spawning rules, boss cadence, formations, and detailed combat movement.

### Continuous coordinates and persistence

The continuous journey uses logical world positions separately from the coordinates used for nearby rendering and physics. A floating origin periodically recenters the active scene without changing logical positions, progress, relative distances, or ongoing movement. Logical Z is represented by a signed segment index and a small offset within the segment, so a long journey does not require huge scene coordinates.

Only nearby content needs a loaded 3D scene. Passed islands retain their identity, route position, buildings, resources, and production state after their scenes unload. During normal fleet play, unloaded liberated islands continue participating in the economy. Loading or unloading a view must not start a second production simulation.

Savegames preserve versioned gameplay state: the anchor's logical position, active ships and relevant simulation state, encounter and milestone state, island records, resources, and production queues. Stable entity IDs reconnect references on load. The scene origin and loaded visual nodes are replaceable presentation details. Loading restores the active region near a fresh local origin and must not repeat already completed encounters or island liberation. Persistent profile data and current-journey data remain distinct; what survives a wipe is still TBD.

## Camera and fleet controls

The player uses an orbit camera that can snap its focus to a selected ship or the persistent fleet anchor, then follow that target while orbiting it. Fleet tracking uses the anchor so spawning or losing ships does not shift the camera with the calculated ship average.

- Mouse clicking a ship selects it and snaps the camera focus to that ship. Controller ship selection remains **TBD**.
- WASD or the controller's left thumbstick releases tracking without a camera jump and enters free flight within the fleet viewing area. Free rotation turns around the camera's own position, as in an FPS camera; forward/back movement follows the view direction and left/right strafes.
- With keyboard and mouse, hold the right mouse button while moving the mouse to rotate the camera. Releasing the button stops mouse-driven rotation; this is a hold action, not a latched toggle.
- The controller's right thumbstick rotates the camera without a mouse-button modifier.
- Mouse scroll zooms toward or away from the tracked fleet/ship by changing orbit distance. Controller D-pad up/down provides continuous zoom. Zoom is inactive in free flight.
- Holding Shift or LT increases orbit zoom speed and free-flight movement speed. It does not change look sensitivity. Free flight permits looking above and below the horizon without flipping.
- A fleet-focus action restores fleet tracking. If a followed ship disappears, fall back to fleet tracking.

Ordinary fleet camera movement is constrained to a sphere centered on the persistent fleet anchor. This includes released camera movement and ship tracking; the viewing area follows the anchor without shifting when fleet membership changes. Ordinary panning, orbiting, or selecting a ship does not pause gameplay. The separate island-view transition described below can leave this viewing area.

In free movement, the camera retains an offset from the persistent fleet anchor and inherits its translation, so the fleet does not leave the camera behind while the player looks around. Looking rotates at the camera's own position; movement input changes the offset. Both translation and viewing bounds use the anchor, keeping the view stable as ships maneuver or membership changes.

The ship average regulates the anchor's travel speed without becoming a camera target or boundary center. This camera choice preserves the anchor's ownership of progression.

**TBD:** Camera distance and angle limits, pan/rotation speeds, viewing-sphere radius, controller ship selection, and keyboard/controller bindings for the fleet-focus action.

## Target priorities and pass-by fire

### Vessel target priority

Each vessel has a predefined ordered target priority. Its **main target** determines which opposing ship it pursues and engages. The priority model follows Dungeon Directive's party-member targeting:

1. Consider the available opposing vessels inside the anchor's engagement area.
2. Select the nearest vessel in the highest-priority category that currently has candidates.
3. If no configured category has a candidate, select the nearest remaining opponent. Unlisted categories remain valid and rank after the configured categories.
4. Keep the current target while it remains valid, unless an opponent from a higher-priority category becomes available. A closer opponent of equal priority alone does not cause a switch.
5. Select again when the target is destroyed, leaves the engagement area, or otherwise becomes invalid. Finish any active regrouping before resuming pursuit. With no eligible opponents remaining, player ships resume forward travel.

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

Gameplay pauses when this island transition carries the view away from the fleet, stays paused throughout island management and the return transition, and resumes once the fleet view is restored. This pauses the whole gameplay simulation: anchor movement, all simulated entity positioning, combat, spawning, production, construction, and other gameplay timers. No elapsed gameplay time is accumulated for catch-up on return. Camera controls, the transition, and management UI remain usable; edits can be made, but timed work does not advance. Future purely visual or atmosphere animations may continue independently.

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

Terrain currently trials **5 × 5 × 5 world-unit voxels**, with 10-unit or 1-unit terrain available for comparison. Detailed assets remain **0.1 world units per voxel**, with rough asset shapes ten times that size. Nearby terrain should reveal cubic steps; distant rendering may simplify geometry while keeping the source grid and logical landscape fixed.

The fleet travels above a noise-generated 3D voxel landscape with stepped hills and valleys. Terrain is primarily scenery, with basic collision planned for downed ships; destruction and terrain editing are not required. Heights and elevation-based colors are authorable; a secondary noise layer varies the color-band boundaries so the same elevation can show neighboring bands instead of perfectly uniform contour stripes. The initial implementation uses FastNoiseLite and exposed voxel-column surfaces, with no need for caves or overhangs.

Downed ships should fall onto the landscape, settle, and remain for a few seconds before cleanup. Their supporting ground must remain stable while terrain streams and the origin shifts. Exact wreck lifetime and behavior when falling into water remain TBD.

Terrain begins as rolling green grassland with a generous height range (currently -30 to 70 in five-unit steps), then blends into taller mountain terrain with rocky elevation bands. Mountains should have broad bases, rising slopes, and distinct summits rather than thin, wall-like noise ridges. Use warped landforms with restrained local irregularity, and avoid excessive contrast that clips hilltops into large flat plateaus. Blend both landform heights and palettes smoothly across an authorable travel interval. Later scenery may place models using terrain height and noise, such as trees concentrated in valleys. Vegetation models, placement rules, and additional biomes remain TBD. Terrain stays at fixed logical world positions as nearby chunks load, unload, and follow floating-origin shifts.

Water sits at **Y = 0**. Terrain may extend below zero so low basins form ponds, bounded by the stepped voxel shoreline. Use a flat surface with authorable depth-color bands, lighter shallows, and restrained square-pattern animation that matches the voxel art direction. Water is scenery; water physics, destruction, and underwater gameplay are outside the current scope.

**TBD:** Final orbit-camera framing, palette, lighting, cloud-transition effects, UI style, animation, and audio direction.

## Initial movement prototype

The first implementation milestone establishes movement and camera behavior using primitive geometry:

- A reusable ship scene shared across factions, hulls, and weapon configurations, initially shown as two primitives forming a zeppelin envelope and gondola.
- An orbit camera with mouse ship selection, fleet/ship tracking, scroll/controller zoom, released FPS-style free flight, a Shift/LT speed boost, and a spherical fleet viewing boundary. Compare anchor and average-position fleet tracking.
- A reusable floating-island scene, independent of its eventual resources and building spots, represented by primitives with approximate capsule collision. Islands spawn throughout the route at varied heights, and ships navigate around them.
- The advancing fleet anchor, average-position feedback, local ship destinations, close-range avoidance, and sluggish airship movement.
- Toggleable in-world navigation debug showing ship destinations, arrival radii, island detours, desired velocity, and actual velocity.
- Floating-origin travel along Z- with occasional island spawning and bounded loading of nearby scenery. Additional content, such as clouds, comes later.
- Streamed voxel ground scenery below the fleet, with noise-generated heights and authorable, varied color bands.

Combat systems, island management and travel transitions, their gameplay pause, production, on-screen UI, and a complete save/load system are outside this milestone. The coordinate and ownership choices must support the documented later systems. Implemented system contracts and validation are recorded in [movement runtime notes](movement.md) and [terrain notes](terrain.md). The gameplay rules in this document remain design intent unless their implementation is recorded there.

## Combat vertical slice

The combat milestone's implemented ownership, tuning, and validation are recorded in [combat runtime notes](combat.md). Use string-based player/enemy faction identities and a Kestrel derived from the primitive ship scene, retaining its current model and movement baseline. Tint enemy models reddish as a placeholder. Each Kestrel carries one tier-1 slot on either side of its hull, each mounting a **Rusty cannon** with **100-unit range**, **5 damage**, and an original baseline of **20-unit/second projectile launch speed** (current authored trial: 100 units/second). Both sides have **500 health**, ten times the initial value, and use the same targeting, positioning, and firing rules.

Cannonballs follow gravity-driven ballistic arcs, with weapons calculating elevation and lead for moving targets before firing. Scripted flight and hit detection follow the same curve; Godot rigid bodies are not required. The slot cone constrains the initial launch direction, including elevation and lead. Rusty cannon favors the earliest intercept and a low arc, using authorable stylized gravity that permits its 100-unit level shot at the specified launch speed. Range measures muzzle-to-target distance, while an independent lifetime allows the longer curved flight; targets within range can still be ballistically unreachable. Gravity and lifetime tuning are recorded in the combat plan.

The current debug spawner adds two ships every simulation second for each faction, independently capped at one hundred living player ships and one hundred living enemies. Count the starting ships toward their faction's cap. Replenish casualties on later scheduled ticks at the same rate, filling only available capacity; debug spawning continues after a faction is wiped out. There is no encounter difficulty curve or combat progression in this slice. Friendly projectile impacts consume the projectile without damaging the ally. Impacts have no visual explosion effect, and destroyed ships simply despawn. Wrecks, production, player-directed reinforcements, and the visual ship editor remain later work. Existing journey and terrain progression continues independently.

Center both factions' debug spawn region on the persistent anchor, independent of the ship average and camera: initially 100–150 horizontal units away and within 150 units above or below its altitude. Reject overlaps with ships and loaded islands using bounded placement attempts.

Measure the combined combat workload at roughly **70 friendly ships and 150 enemy ships** as an endgame target for low-end hardware. This is separate from the current debug scene's one-hundred-per-faction caps. Begin with ordinary readable optimizations; further low-level work depends on profiling. Ship health values, reload cadence, final cone angles, and engagement distances remain provisional authoring choices.

## Scope of this draft

The continuous journey governed by combat, escalating encounters, predefined vessel target priorities, optional pass-by fire enabled by default, shared combat behavior for both fleets, island takeover and production, two reinforcement routes, pre-built hulls with compatible weapon spots, saved custom ships, and voxel steampunk fantasy direction form the current design foundation.

Numerical balance and the open decisions above require further design. Update this document as those decisions are made; do not treat the TBD entries as approved implementation requirements.
