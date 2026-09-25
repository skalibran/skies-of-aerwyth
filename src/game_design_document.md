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

Each vessel pursues and engages its selected opponent while opponents remain. When there are no opponents, it travels with the fleet by navigating around the advancing anchor. Clearing enemies faster than they spawn therefore creates time to make progress; sustained opposition keeps ships occupied with combat and can slow or effectively halt that progress as the fleet falls behind its anchor. Individual ships can move toward combat targets and fire while moving, so battle and movement can overlap.

Every active ship is fighting, moving to engage an opponent, or traveling onward. A ship never waits merely because its preferred target category is absent: target priority orders opponents without excluding any of them.

### Fleet anchor and airship movement

The anchor advances continuously along Z- while the journey simulation is running and friendly ships remain. Calculate the average position of the active friendly ships separately. The farther the anchor moves from that average, the more its forward speed decreases; as the ships catch up, it recovers speed. The average regulates the anchor's movement without replacing its position. Adding or losing a ship can affect the speed response, but must not teleport the anchor or advance milestones immediately.

Each ship generates its own navigation destination around the anchor. These destinations move with the anchor. On reaching its destination, the ship chooses another within a limited nearby area, producing gentle movement within the fleet. Routine destination changes must not send a ship from the front to the back of the entire fleet. Combat pursuit takes priority over this travel behavior when opponents are present.

Ships avoid one another while allowing fairly close pass-bys. Their movement should convey heavy, sluggish airships: gradual acceleration, braking, and turns, with limited pitch and banking. They must not perform loops, flips, or abrupt model rotations.

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

The player uses an orbit camera that can snap its focus to a selected ship or the fleet, then follow that target while orbiting it.

- Mouse clicking a ship selects it and snaps the camera focus to that ship. Controller ship selection remains **TBD**.
- WASD or the controller's left thumbstick releases tracking and pans the camera freely within the fleet viewing area.
- With keyboard and mouse, hold the right mouse button while moving the mouse to rotate the camera. Releasing the button stops mouse-driven rotation; this is a hold action, not a latched toggle.
- The controller's right thumbstick rotates the camera without a mouse-button modifier.
- A fleet-focus action restores fleet tracking. If a followed ship disappears, fall back to fleet tracking.

Ordinary fleet camera movement is constrained to a sphere around the fleet. This includes released camera movement; the viewing area follows the traveling fleet. Ordinary panning, orbiting, or selecting a ship does not pause gameplay. The separate island-view transition described below can leave this viewing area.

**To evaluate:** Fleet tracking may follow the calculated average ship position, keeping the fleet visually centered, or the persistent anchor, providing a steadier focus slightly ahead of the ships. Compare both during the movement prototype before choosing. This camera choice does not change the anchor's ownership of progression.

**TBD:** The final fleet tracking target, camera distance and angle limits, pan/rotation speeds, viewing-sphere radius, controller ship selection, and keyboard/controller bindings for the fleet-focus action.

## Target priorities and pass-by fire

### Vessel target priority

Each vessel has a predefined ordered target priority. Its **main target** determines which opposing ship it pursues and engages. The priority model follows Dungeon Directive's party-member targeting:

1. Consider the available opposing vessels.
2. Select the nearest vessel in the highest-priority category that currently has candidates.
3. If no configured category has a candidate, select the nearest remaining opponent. Unlisted categories remain valid and rank after the configured categories.
4. Keep the current target while it remains valid, unless an opponent from a higher-priority category becomes available. A closer opponent of equal priority alone does not cause a switch.
5. Select again when the target is destroyed or otherwise becomes invalid. With no opponents remaining, resume forward travel.

Priority is a preference order, never an exclusion rule. Every opposing vessel remains a possible target, so a vessel continues fighting even when none of its preferred categories are present. Both fleets use this model, with predefined priorities appropriate to their vessels.

**Reference:** Dungeon Directive's [party-member target controller](../../dungeon-directive/scripts/party_members/target_controller.gd) implements category ordering, nearest-candidate selection, fallback targeting, and retention of a valid target within its priority category. Its [NPC target controller](../../dungeon-directive/scripts/actors/actor_target_controller.gd) uses threat scoring; Aerwyth's rule above applies the vessel priority model to both sides.

**TBD:** The actual priority categories, each vessel's predefined order, and whether players can later edit those priorities.

### Weapon-slot pass-by fire

Each weapon slot has a configurable **fire at targets in range** option, enabled by default. With this option enabled, the mounted weapon can fire on opposing targets within its range while the vessel moves toward its main target. This allows pass-by fire against other ships encountered en route.

The weapon's firing target can differ from the vessel's main target. Pass-by fire does not itself change which ship the vessel pursues. Disabling the option makes that slot focus on the vessel's main target and wait until it can fire at that target within range.

Weapon range and normal firing constraints still apply. The option permits opportunistic attacks; it does not make every opposing ship simultaneously attackable. Friendly and enemy weapon slots follow the same rules and default.

**TBD:** Selection among multiple targets in range, preference when the main target is also in range, and detailed targeting rules for specialized weapons such as anti-projectile systems.

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

Vessel hulls are pre-built. Each has designated mounting spots labeled **S1, S2, S3, ...**. A spot determines which cannons or other weapons it can accept.

Each slot also exposes the default-enabled [pass-by fire option](#weapon-slot-pass-by-fire), independently of the vessel's predefined main-target priority.

Players can mount different compatible weapons on a vessel and save the resulting configuration as a new ship. Customization combines existing vessels and compatible armaments; the core concept does not require players to construct hulls themselves.

Pre-made ships must be sufficient to play the entire game. Custom configurations provide room to discover useful combinations and advance faster without making ship design mandatory.

For example, a player could equip a fast, light vessel with anti-projectile weapons to push through a screen of projectile spam. This illustrates the intended interaction between hull properties, weapon choice, and enemy threats; its exact combat mechanics and balance are TBD.

**TBD:** Hull and weapon catalogs, spot compatibility rules, firing arcs, weapon statistics, refitting costs and timing, the configuration editor, and how saved ships become available for purchase and production.

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

Voxel style describes the intended appearance. It does not yet specify a voxel engine, destructible terrain, or a technical asset pipeline.

**TBD:** Final orbit-camera framing, voxel scale, palette, lighting, cloud-transition effects, UI style, animation, and audio direction.

## Initial movement prototype

The first implementation milestone establishes movement and camera behavior using primitive geometry:

- A reusable ship scene shared across factions, hulls, and weapon configurations, initially shown as two primitives forming a zeppelin envelope and gondola.
- An orbit camera with mouse ship selection, fleet/ship tracking, keyboard/controller panning and rotation, and a spherical fleet viewing boundary. Compare anchor and average-position fleet tracking.
- A reusable floating-island scene, independent of its eventual resources and building spots, represented by primitives.
- The advancing fleet anchor, average-position feedback, local ship destinations, close-range avoidance, and sluggish airship movement.
- Floating-origin travel along Z- with occasional island spawning and bounded loading of nearby scenery. Additional content, such as clouds, comes later.

Combat systems, island management and travel transitions, their gameplay pause, production, and a complete save/load system are outside this milestone. The coordinate and ownership choices must support the documented later systems. Technical implementation tasks and validation criteria are recorded in [todo-movement.txt](../todo-movement.txt); this list describes planned work, not implemented features.

## Scope of this draft

The continuous journey governed by combat, escalating encounters, predefined vessel target priorities, optional pass-by fire enabled by default, shared combat behavior for both fleets, island takeover and production, two reinforcement routes, pre-built hulls with compatible weapon spots, saved custom ships, and voxel steampunk fantasy direction form the current design foundation.

Numerical balance and the open decisions above require further design. Update this document as those decisions are made; do not treat the TBD entries as approved implementation requirements.
