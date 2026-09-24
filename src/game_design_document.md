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

The fleet's journey proceeds in one direction through one continuous 3D space. Progress is associated with how far it has traveled, and combat determines the opportunity to advance.

Each vessel pursues and engages its selected opponent while opponents remain. When there are no opponents, it travels forward. Clearing enemies faster than they spawn therefore creates time to make progress; sustained opposition keeps ships occupied with combat and can slow or halt that progress. Individual ships can move toward combat targets and fire while moving, so battle and movement can overlap.

Every active ship is fighting, moving to engage an opponent, or traveling onward. A ship never waits merely because its preferred target category is absent: target priority orders opponents without excluding any of them.

Enemy difficulty increases with distance through:

- Larger waves containing more enemy airships.
- Stronger individual enemy airships.
- Boss battles.

Combat is automatic. The player's central decisions concern fleet composition, weapon configurations, production, and reinforcement timing.

The same targeting, engagement, and weapon-slot firing rules apply to friendly and enemy vessels. Enemy travel after eliminating the player's fleet has no gameplay role: when no friendly ships remain, the failure condition is reached. The failure response, recovery options, and relationship to a wipe remain TBD.

**TBD:** Travel speed, wave spacing and spawning rules, boss cadence, formations, detailed combat movement, and how fleet distance is measured when vessels are spread out. Camera and controls are also undecided.

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

**TBD:** Building costs, construction times, placement rules, island capacity, resource types and deposits, depletion, production chains, storage limits, and the interface for managing islands already passed.

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

**TBD:** Camera perspective, voxel scale, palette, lighting, effects, UI style, animation, and audio direction.

## Scope of this draft

The continuous journey governed by combat, escalating encounters, predefined vessel target priorities, optional pass-by fire enabled by default, shared combat behavior for both fleets, island takeover and production, two reinforcement routes, pre-built hulls with compatible weapon spots, saved custom ships, and voxel steampunk fantasy direction form the current design foundation.

Numerical balance and the open decisions above require further design. Update this document as those decisions are made; do not treat the TBD entries as approved implementation requirements.
