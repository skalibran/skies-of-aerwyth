# Threat and enemy encounters

Journey starts with three friendly Kestrels around the fleet marker at **Z = +100**. Its `Encounters` node reads the marker's [journey progress](terrain.md#progression) and schedules wave one after **100 meters of travel**, at **logical Z = 0**. Later waves are **1000 meters** apart: wave two at Z = -1000, wave three at Z = -2000, and so on. Each reached milestone schedules one enemy wave at the next physics boundary. Time alone, camera movement, and floating-origin shifts cannot trigger waves. A milestone is consumed once, including when its composition is empty. Traveling backward cannot repeat it.

[`journey_encounters.tres`](../../resources/encounters/journey_encounters.tres) owns the editable **First Wave Distance** (100 meters from the initial marker position), **Threat Distance** (1000 meters between waves), budget growth, random pool, and optional wave overrides. `wave_distance(number)` supplies the shared one-based milestone calculation for scheduling checks and rendered lines. There is no automatic casualty replenishment. The fleet marker keeps moving during encounters and crosses milestones at its normal travel pace. Each crossed milestone schedules once on the next physics tick, so a new wave may arrive while previous enemies remain alive or placement is pending. Empty plans also consume their milestone without interrupting movement. Friendly propulsion limits and obstacle-route safeguards still apply. Distant arrivals do not hold the marker.

## Budget and selection

The budget is `base_budget + budget_per_threat * threat_level ^ budget_growth`, rounded to an integer. The authored defaults are zero base, 15 points per level, and linear growth: wave 1 receives 15 points, wave 2 receives 30, and wave 8 receives 120. Each wave gets a fresh budget. Unused points do not carry over.

Each [`ShipDefinition`](../../scripts/ships/ship_definition.gd) has an explicit **Spawn Cost** for its complete loadout. Stats do not automatically change that cost. A [`FleetPreset`](../../scripts/encounters/fleet_preset.gd) contains ship/count members and costs their exact sum. A reusable [`SpawnEntry`](../../scripts/encounters/spawn_entry.gd) references exactly one ship definition or fleet preset. Entries live under `resources/encounters/entries/`. Presets live under `resources/encounters/fleets/`. Both the random pool and guaranteed overrides use these same entries.

An [`EncounterOption`](../../scripts/encounters/encounter_option.gd) adds **Weight** and **Maximum Selections** to a spawn entry in the pool. Weight is relative to other currently affordable options. It is independent of cost, and weights need not sum to 100. Zero weight disables a random option. A fleet is an indivisible selection: the whole bundle must fit, and every member enters the plan. Maximum Selections limits that pool option, not every occurrence of its ships through other presets or guarantees.

The planner first adds guaranteed entries, then chooses a random spending target between **75% and 100%** of the original budget. Charged guarantees count toward this target. Bonus entries do not. It repeatedly selects an affordable option by weight until the target is met or no eligible option remains. The final selection may cross the spending target but cannot cross the remaining budget. Leftover points are allowed, including when repetition limits exhaust the pool. There is no retry to force a nonempty composition.

## Authoring guaranteed waves

Add a [`WaveOverride`](../../scripts/encounters/wave_override.gd) resource to the profile's **Wave Overrides** array. **Wave Number** identifies its threat milestone: 2 means 1100 meters traveled, at logical Z = -1000, with the current first-wave offset and spacing. Only one override per number is allowed. Place all its guaranteed entries in that override.

Each [`GuaranteedSpawn`](../../scripts/encounters/guaranteed_spawn.gd) supplies:

- **Entry:** any reusable ship or fleet spawn entry, whether or not it also appears in the random pool.
- **Count:** complete copies of the entry. Two fleet copies include twice every member.
- **Charge Budget:** enabled deducts the full entry cost before random filling. Disabled adds the entry on top of the budget.

Guarantees always take precedence. If their charged cost exceeds the wave budget, they still spawn, with no random extras and no debt applied to later waves. Disable the override's **Fill Random Budget** to make that wave entirely authored. An override with random filling enabled adds to the ordinary generator. It does not replace the pool.

The supplied examples are:

| Wave | Travel distance | Logical Z | Guaranteed entry | Budget treatment |
| --- | ---: | ---: | --- | --- |
| 2 | 1100 m | -1000 m | Manta | Charges 24 points |
| 4 | 3100 m | -3000 m | Escort patrol: Manta + 2 Swifts | Charges 36 points |
| 8 | 7100 m | -7000 m | Battle group: Bastion + Manta + 2 Kestrels | Adds 104 points on top |

Other waves use the weighted pool alone. The pool includes all four individual ships, a two-Swift scout pair, the escort patrol, and the battle group. The authored sequence continues every 1000 meters beyond the example overrides.

The current pool's repetition limits cap random composition at 324 points and 20 ships. From wave 29 onward, the minimum spending target exceeds that cap, so ordinary waves exhaust every option regardless of their larger budget. This follows the authored per-option limits, not a planner failure. Increasing the budget alone cannot exceed them. Threat-pool tuning remains in the [navigation and encounter follow-ups](todo/navigation-encounters.txt).

Scheduling and blocked-placement retries have no session-wide population or pending-plan limit. This is accepted for the current gameplay: unhandled waves accumulate and overwhelm the player. No population cap, expiry, or guarantee-dropping policy is introduced. An empty friendly fleet stops further scheduling and placement. Release-build content validation and journey saves belong to whole-game work, separate from this refactor review.

## Ships and presentation

All four definitions are also available through the friendly ship picker. Spawn Cost is an enemy encounter cost, not a player purchase price.

| Ship | Class | Cost | Health | Cannons | Speed | Appearance |
| --- | --- | ---: | ---: | ---: | ---: | --- |
| Kestrel | Skiff | 10 | 500 | 2 broadside | 50 m/s | Existing authored voxel model |
| Swift | Skiff | 6 | 250 | 1 forward | 65 m/s | Small amber envelope, pointed nose and upright tail |
| Manta | Corvette | 24 | 800 | 4 downward/outward | 45 m/s | Twin teal envelopes and connecting beams |
| Bastion | Frigate | 60 | 1600 | 6 broadside | 38 m/s | Large blue envelope, armored gondola and side pods |

The three primitive scenes inherit `ship.tscn`, author their own capsule collider and flight tuning, and use tier-one Rusty cannons in ordinary mounted slots. They retain native flight/contact handling, faction tint, damage, death smoke, wreck cleanup, and floating-origin registration. Their composed visuals and mounted loadouts are editable in `scenes/ships/`. Tuning and broader combat acceptance remain in [COMBAT-02/04](todo/todo-combat.txt).

Manta's four muzzles sit just outside the gondola's lower corners at X = +/-7, Y = -10, Z = +/-15 meters. Each points diagonally outward and 45 degrees downward, retaining its 65-degree cone half-angle. Its preferred target bearings are `front_bottom`, `bottom`, and `back_bottom`, so navigation favors positions above opponents instead of broadside presentation.

## Runtime ownership

[`EncounterDirector`](../../scripts/encounters/encounter_director.gd) owns reached threat, consumed wave numbers, the composition RNG, and pending plans. [`EncounterPlanner`](../../scripts/encounters/encounter_planner.gd) builds each plan once without mutating shared resources. A nonzero director **Random Seed** reproduces compositions. Zero randomizes a new journey. Placement has a separate Journey-owned RNG, independent of both composition and the friendly picker.

Journey steps the director before movement and combat snapshots. Spawning assigns enemy faction and a unique ID before entering the tree. Each ship's authored Spawn Layer selects Lower Cloud, Upper Cloud, or Isle: Manta uses upper clouds. Kestrel, Swift, and Bastion use isles. Sources are ranked by 3D distance to the marker. Enemies and their source objects must remain at least 500 meters on Z- relative to the marker. The full hull plus eight meters must be concealed by the selected cloud or the isle's visible rock, with collision queries and same-tick hull checks rejecting overlaps. Isle concealment follows the current camera position, including when it is beyond the isle. Enemies initially face the marker, contribute to sphere size, and approach through the existing navigator and arrival boost. See [ship spawn rules](ship_spawning.md). The three starting Kestrels retain their authored positions.

At most eight ships are placed per tick, with at most 32 candidate positions per ship: one selected cloud, or four positions per isle across up to eight nearest isles. Missing concealment or blocked placement retains the selected ship and retries after 0.5 seconds of simulation time. It never rerolls or drops a guaranteed member. Each retry reevaluates sources against the current marker and camera without switching the authored source type. Pending fleets can therefore finish over several ticks. Large distance jumps catch up at most one crossed wave per tick, using each milestone's own budget and override. Empty plans consume their milestone normally. Existing plans and counters belong to the Journey instance and are released with it. Encounter persistence is not implemented.

Disabling the director or `Journey.combat_enabled`, stepping with zero duration, or having no living friendly fleet stops scheduling and placement. The separate `CombatSpawner` remains an opt-in stress fixture. Combat and scale checks disable authored encounters when managing their own populations. The top-center [wave announcement](ui.md#wave-announcement) displays the wave number and its full composition cost as a provisional difficulty score for four seconds. `wave_spawned` emits once when the first ship is successfully placed, independently of `wave_planned`. Empty or fully blocked waves do not announce. The score includes bonus fleet/ship costs and excludes unused budget.

## Threat boundary lines

[`threat_boundaries.tscn`](../../scenes/world/threat_boundaries.tscn) displays horizontal world-space lines at each wave milestone, starting at logical Z = 0, using the same **First Wave Distance** and **Threat Distance** as the encounter profile. Line levels are one-based wave numbers. The initial marker at Z = +100 has no extra milestone line. At the default spacing, the lines divide progress into 1000-meter sections. They follow the marker's rendered altitude while their logical Z positions stay fixed along the route. They have no collision and do not affect progression or spawning.

A single batched mesh extends each line beyond the camera's visible horizontal range, including far-plane corners. Only nearby geometry is retained and rebuilt when the covered milestone range or view coverage changes. Logical route coordinates determine its local transform after origin shifts. Camera movement can change coverage, but cannot move a milestone along the route. The material keeps depth testing and fades the lines between 2000 and 6000 meters of forward/backward separation from the camera, avoiding a dense band at the horizon while preserving each line's horizontal span. Color and fade distances are authored on its shader material.

## Validation

Use the isolated APPDATA and log setup in [AGENTS.md](../../AGENTS.md), then run `res://scripts/tools/check_encounters.gd` with `--headless --fixed-fps 30`. The check covers budget accounting, weighted ratios, affordable whole fleets, repetition limits, charged/bonus and over-budget guarantees, deterministic rolls, exact distance boundaries, skipped and empty milestones, blocked placement retries, no-fleet suppression, registration, authored cloud/isle concealment, camera exclusion, 500-meter Z- clearance, logical boundary placement and coverage, capsule coverage, mounted loadouts, firing, origin shifts, and announcement timing, full-cost scores, and expiry. After validating spawn locations, its firing fixture moves the generated roster into weapon range so arrival travel does not determine the check's duration.

For rendered inspection, omit `--headless`, set `AERWYTH_CAPTURE_DIR` to an external directory, and append `-- --visual`. It captures the moving combat marker and navigation sphere, threat boundaries, the wave announcement, Swift, Manta, Bastion, and a mixed encounter. This fixture advances across eight milestones to exercise the content quickly. It is not a normal pacing or balance playthrough. Cloud placement, retries, registration, firing, and origin checks passed at the project 30 Hz baseline. Three cost assertions fail because their Manta/Bastion expectations differ from the current authored resources. Scheduling, first-wave positioning, boundary rendering, and the other encounter checks pass. The content/check mismatch is recorded in the [encounter follow-ups](todo/navigation-encounters.txt). Scale and long-session performance were not measured for this change.
