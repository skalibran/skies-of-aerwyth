# Skies of Aerwyth agent guidance

## Project baseline

Skies of Aerwyth has a movement prototype and a combat vertical slice. Read the [game design document](src/docs/game_design_document.md) for its gameplay concept and visual direction, [movement runtime notes](src/docs/movement.md), and [combat runtime notes](src/docs/combat.md) for implemented ownership and validation contracts. Treat sections marked TBD as unresolved design decisions. Use the user's requirements, the design document, and the code that exists as the authority for implementation; the design document describes intended systems, not implementation status.

Current technical baseline:

- One world unit is one meter. The [meter conversion](src/docs/world_units.md) preserves the prototype's appearance and timing with lengths, linear speeds, and linear accelerations scaled tenfold. Mass, angles, durations, counts, and the 30 Hz physics rate are unchanged.
- `project.godot` declares Godot 4.7 and Forward Plus, with Jolt Physics and D3D12 on Windows.
- Display stretch uses `canvas_items` with `expand` aspect and a 1920 x 1080 logical design resolution; the initial window remains 1280 x 800. Physics runs at the accepted 30 Hz baseline, with interpolation enabled. Checks and benchmarks use the project physics rate; there is no alternate-rate test matrix or benchmark override.
- The main scene is `scenes/world/journey.tscn`: three player Kestrels using the authored voxel balloon/hull meshes and balanced palette, a moving fleet anchor, local avoidance, a bounded orbit/free camera, floating-origin travel along Z-, and streamed primitive islands. Fleet camera tracking and its viewing sphere use the persistent anchor, so membership changes cannot shift the view through the ship average. The top UI zone contains a performance label showing total living ships across both factions and FPS, refreshing twice per second.
- Journey instances `scenes/ui/master_ui.tscn`: a full-viewport CanvasLayer layout with three centered, 1920-wide zone scenes (top 140, center 800, bottom 140 logical pixels). Top/bottom pin to viewport edges; center stays centered. Ultrawide windows expose side space, taller aspects create gaps between zones. Zone hosts draw no background and ignore input; only hosted features draw UI. MasterUI owns viewport placement; feature views fill their hosts. The bottom host has five ship classes (Skiffs, Corvettes, Frigates, Cruisers, Dreadnoughts) above one horizontally scrollable row; Kestrel is a Skiff. Journey owns the ShipDefinition catalog and queues click requests for safe random spawning near the anchor on the next physics tick. The shared `resources/ui/main_theme.tres` governs plain styling with 4-pixel spacing steps and 2-pixel borders. UI focus reserves camera navigation; Cancel or world pointer input releases it. See [UI layout and aspect checks](src/docs/ui.md).
- Combat uses string factions, an inherited Kestrel scene, reddish enemy tint, 500 health, and two tier-one Rusty cannons with authored broadside cones (currently 65° half-angle). Scripted ballistic shots currently trial 1000 m/s launch speed, gravity 30 m/s², range 1000 meters, damage 5, and an eight-second lifetime; the slower 200 m/s trajectories remain solver reference fixtures. Allies intercept without damage. Rusty cannons opt into reusable 0.75-second muzzle smoke, batched per effect scene under the projectile root with a bounded cosmetic particle budget. Normal play starts with only the three friendly ships and has no automatic combat spawning or replenishment. CombatSpawner lives under scripts/tools/ and runs only when explicitly created and stepped by the extended combat check. Destroyed ships stop flight control, retain momentum, and fall with an authorable gravity multiplier (default 0.2, or 19.6 m/s²) and native damping. Airship creates one death-smoke GPU system from its selected effect scene on death; plain Marker3D children under DeathSmokePoints supply positions (Kestrel currently retains only HullSmoke). Removing markers is safe, including an empty container. Growing, fading camera-facing squares stop permanently on first ground contact. Smoke systems share an immutable process material, emit on the physics clock, and retain bounded recent-trail culling boxes. Wrecks settle for three seconds, freeze with collision disabled, and expire 25 seconds after ground contact (45-second airborne fallback). Wrecks and smoke remain hidden over coarse terrain and keep rebasing until cleanup. The model uses one-meter voxels (23-meter balloon), a fitted capsule, and resized cannon visuals. See [combat contracts and checks](src/docs/combat.md).
- CombatPerception supplies a tick-local shared spatial query for weapon candidates; Journey owns registration, ShipCombat owns pursuit, and MountedWeapon owns retained firing targets, acquisition, and fresh ballistic validation. Weapons reject impossible candidates before selecting bounded nearest-untried shortlists, with failed-attempt history to prevent starvation. See [combat contracts](src/docs/combat.md) and [performance measurements](src/docs/combat_performance.md).
- Ships own tiered MountedSlot nodes; optional equipment scenes own their visuals and behavior. EquipmentDefinition supports weapons and utilities with exact tier matching; utility effects are not implemented. Slots preview their authored firing cones in the editor using cone-shaped CylinderMesh geometry. See [slot authoring](src/docs/combat.md#authored-ships-and-weapons).
- `scripts/tools/check_movement.gd` provides focused simulation and rendered/input checks; `check_combat.gd` covers the combat slice. There is no general test framework, autoload, configured linter, localization pipeline, or export preset yet. Production, save files, and island management/transitions are not implemented.
- The camera starts at a 600-meter orbit, with 25-meter scroll steps and 300 meters/second D-pad zoom. It supports FPS-style free flight relative to the fleet anchor, and Shift/LT speed boosts. Free mode inherits anchor translation while keeping independent looking and movement within the anchor-centered viewing sphere. In-world ship navigation debug starts disabled; F3 toggles it. Controls and geometry colors are documented in the movement runtime notes.
- Endgame combat scale targets roughly 70 friendly ships and 150 enemies. The three-ship starter fleet uses 120/60/120-meter formation half-extents, 40-meter wander steps, and 75-90-meter initial spacing across nearby altitude levels. Its anchor debug cube is 4 meters wide. Scale checks explicitly retain 1800/1200/1800-meter half-extents and 160-meter steps; the camera sphere radius remains 9000 meters. Local wandering samples all three axes equally. `scripts/tools/check_fleet_scale.gd` exercises 128 ships without combat; `check_combat_scale.gd` measures 220 combat ships and a separate miss-volley workload. Both support rendered profiling with debug drawing off/on; low-end hardware suitability remains unproven.
- Journey owns the combat/travel choice and submits forces once per physics tick; Godot/Jolt integrates bodies and resolves contacts. Ship avoidance uses a conservative snapshot spatial grid and evaluates each pair once, with pair math inline and clamping after accumulation; IslandSpawner caches loaded-island navigation cells and refreshes them on loading, unloading, and rebasing. Exact steering/height tests remain with their existing owners.
- Both factions use FleetController's 1800/2600-meter combat radii: inward course bias starts at 1800, regrouping starts at 2600 and ends inside 1800, and pursuit excludes targets beyond 2600. Flight/avoidance and weapon fire remain active during return. Opt-in combat fixture spawns are centered on the persistent anchor, with 1000–1500-meter horizontal radius and ±1500-meter altitude spread. See [combat positioning](src/docs/combat.md#targeting-and-movement).
- RigidBody3D is the accepted ship controller after hands-on comparison. Stateless ShipFlight helpers submit mass-scaled thrust/lift/drag and inertia-scaled yaw torque; engine linear/angular velocity is authoritative. Living hull pitch/roll are locked, visual banking remains, gravity is disabled, and contacts transfer momentum without damage. Combat and travel share this controller. Kestrel authors a 50 m/s speed limit, 5 m/s climb, 4/6 m/s² acceleration/braking, 12°/s yaw, 10°/s² yaw acceleration, and 0.7/s lateral drag. The starter fleet cruises at 25 m/s with 3 m/s² anchor acceleration and 8 m/s relative travel correction; generic controller fixtures retain their reference tuning. See [flight tuning](src/docs/movement.md#forward-flight-and-momentum), the [rigid-body comparison and audit](src/docs/rigid_body_trial.md), and `scripts/tools/check_ship_flight.gd`.
- Islands populate a broad field around the fleet from startup, with varied heights and upright capsule collision. Ships use local lateral detours around loaded islands, with height checks against the capsules for clear over/underflight. `scripts/tools/check_island_navigation.gd` covers routing, collision, rebasing, and unloading; navigation debug marks detours in pink.
- Terrain currently trials a 50-meter cubic grid, with 10/50/100-meter choices in TerrainProfile. Merged surfaces and camera-dependent detail remain; bounded worker jobs build mesh arrays, with main-thread publication and cleanup. Broad, warped FastNoiseLite grassland spans -300 to 700 meters and gradually blends into mountains from 1500 to 10000 traveled meters. Mountains span 800–3400 meters, with broad ridged landforms, tapered crests, and elevated valleys above sea level; peaks reach into the lower floating-island band. JourneyProgress exposes the anchor's forward distance as `journey.progression.distance`; camera motion and rebasing do not advance it. See [terrain authoring and checks](src/docs/terrain.md). Full-detail patches own native static trimesh colliders for wrecks; coarse patches have none. Destruction and vegetation are not implemented.
- Water scenery sits at Y = 0; negative terrain forms ponds. Its shader uses depth-color bands and ten-meter square highlights that remain stable across origin shifts. The fleet starts at Y = 3800, above terrain and water. Water has no collision or simulation.
- Journey has a blue sky gradient excluded from fog. Shared depth fog uses a 2.2 curve for subtle nearer haze and a stronger edge ramp, fully concealing scenery by 28000 meters before the 30000-meter camera cutoff. Terrain, water, ships, and islands share this fog profile; fog and lower-sky colors match. See [horizon haze](src/docs/terrain.md#horizon-haze).
- `scripts/tools/profile_landscape.gd` measures isolated landscape rendering/streaming and compares 10/50/100-meter cells. See the [landscape measurements](src/docs/terrain_performance.md). `scripts/tools/check_wrecks.gd` covers impact, settling, LOD visibility, and cleanup.
- Use GDScript by default. Add languages, addons, and external dependencies only when the task justifies them.
- `.godot/` contains generated editor and import state. Do not edit or commit it.

Update this baseline when the corresponding systems are introduced.

See the [generation production review](src/docs/generation_review.md) for ownership and measured performance, and the [task lists](src/docs/todo/README.md) for outstanding work. The prototype pass does not imply save/revisit support or terrain collision.

The [combat and movement review](src/docs/combat_review.md) preserves the scripted-flight baseline at commit `644e50a`. The [rigid-body integration](src/docs/rigid_body_trial.md) records the accepted replacement and comparison. A functional scale-check PASS is separate from its reported performance result; Journey's script timer excludes native rigid-body integration/contact solving. Combat production gates are COMBAT-01–04 in the combat task list.

## Working rules

- Inspect `git status` before and after work. Preserve unrelated changes and hand-authored content.
- Push only when the user explicitly authorizes pushing the work. Editing, testing, staging, and committing do not independently authorize a push.
- Read the affected files and adjacent systems before choosing an implementation. Carry authorized work through implementation and appropriate verification.
- Keep edits scoped to the task. Avoid incidental renames, formatting churn, dependency changes, and cleanup of unrelated debug or temporary content.
- Keep all active TODOs, blockers, open decisions, implementation plans, and follow-up work in `src/docs/todo/`. The game design document is the sole exception. Other documentation describes implemented behavior, factual limitations, decisions, measurements, and repeatable procedures; link to the relevant task list instead of duplicating outstanding work.
- Resolve routine, reversible implementation choices using the request and existing conventions. Clarify material gameplay or scope decisions when the available information is insufficient, while continuing independent work.
- Do not add compatibility layers, migrations, or generalized frameworks for hypothetical future requirements.

## Folder organization and content flow

Use role-based top-level folders with consistent feature names beneath them. Create directories as content needs them. The following is a convention for growth, not a claim that these folders already exist.

| Location | Responsibility |
| --- | --- |
| `project.godot` | Startup scene, autoload registration, inputs, and project-wide settings. |
| `scenes/<feature>/` | Composed objects, screens, and levels. |
| `scripts/<feature>/` | Behavior, state, and custom Resource types for that feature. |
| `resources/<feature>/` | Authored `.tres` definitions and reusable configuration. |
| `assets/` | Runtime-ready models, textures, sprites, audio, and fonts, grouped by asset type and then feature where useful. |
| `materials/`, `shaders/`, `animations/` | Shared presentation resources when needed. Keep scene-specific subresources local when that is clearer. |
| `src/` | The [game design document](src/docs/game_design_document.md), editable art sources, and other authoring inputs. Keep `src/.gdignore` in place, and export runtime assets into `assets/`. Gameplay code belongs in `scripts/`. |
| `localization/` | Editable translation sources if localization is introduced. |
| `scripts/tools/`, `scenes/tools/` | Purposeful validation and content-generation tools. |
| `src/docs/` | Design decisions, technical notes, and reference material. |
| `src/docs/todo/` | Active task lists, blockers, open decisions, and implementation plans, except those in the GDD. |

A feature normally connects its composed scene, attached script, and authored resources. Keep their domain names aligned where practical without creating empty counterparts. Runtime flow begins at the configured main scene and any justified autoloads. Feature owners update state, and presentation reflects that state.

## Architecture and authoring

- Give each state change one clear owner. Keep UI and presentation dependent on the owning system instead of duplicating gameplay rules or maintaining a second authoritative state.
- Separate shared authored definitions from mutable instance state. Duplicate resources when per-instance mutation is intended so changes do not leak across instances.
- Prefer exported properties and typed Resources for content that should be tuned in the editor. Prefer composed scenes for reusable objects and UI. Use runtime construction where the content is actually dynamic.
- Use typed references and signals for explicit contracts. Within scenes, prefer exported references or scene-unique names over fragile paths through unrelated subtrees. Treat intentional groups and input actions as named contracts.
- Add an autoload only for a responsibility that needs project-wide access or cross-scene lifetime. Keep feature-local logic with its feature.
- Keep asynchronous work, signal subscriptions, timers, and transient children tied to their owner's lifetime. Account for cancellation and scene exit when those features are introduced.
- Inspect sibling cases before extracting shared behavior. Make small, behavior-preserving improvements when they clarify ownership. Keep broad redesigns within the authorized scope.
- Before handoff, review for duplicated transitions, string-based guesses about another object's API, and special cases caused by misplaced logic. Fix contained issues and explain any material compromise left in place.

## Godot code and content conventions

- Follow [Godot's GDScript style guide](https://docs.godotengine.org/en/stable/tutorials/scripting/gdscript/gdscript_styleguide.html) and its naming conventions by default: `snake_case` for files, functions, variables, and signals; `PascalCase` for classes; and `CONSTANT_CASE` for constants and enum members. Use tabs in GDScript and typed declarations where practical.
- Apply conventions pragmatically when they do not fit or would hinder readability. Prioritize clear code and local consistency over rigid formatting; do not force line breaks or reflow readable code solely to satisfy a fixed line-length limit.
- Keep engine callbacks such as `_ready()`, `_process()`, `_physics_process()`, and input callbacks focused on orchestration. Put substantive operations in clearly named functions.
- Write concise English comments for non-obvious intent, timing, and invariants. Use complete sentences and describe the code for a reader who has not seen the conversation.
- Use Input Map actions for gameplay controls. Add actions and their consumers together when controls are introduced.
- Keep UI layout in authored Control scenes and containers where practical. Use the shared master theme and author spacing in multiples of 4 logical pixels; 2-pixel exceptions are for details such as borders. Give viewport layout a clear owner, use shared theme resources for common styling, and avoid scattered fixed screen coordinates.
- Preserve resource UIDs and serialized references when moving or editing scenes and resources. Keep engine-generated `.uid` sidecars and source-adjacent `.import` settings under version control. Do not fabricate or casually regenerate identifiers.
- Terrain currently uses 50 meters per voxel as a visual trial; TerrainProfile also supports 100 and 10 meters. Detailed assets use 1 meter per voxel; rough asset shapes use ten times that size (10 meters). Keep source voxel scale separate from distant display simplification, and preserve grid alignment across 10240-meter origin shifts.
- Review `.tscn`, `.tres`, and project-setting diffs for accidental editor changes. Update all affected references when a rename is necessary.
- Store AI-generated placeholder art under `assets/_temp_ai_to_be_replaced/`, grouped by asset type as needed. Keep its temporary status clear. Procedural output generated by project tools follows its feature's normal asset organization.
- Keep editable authoring and localization sources authoritative. Regenerate derived outputs through the relevant tool when one exists.

## Performance

- Avoid repeated scene-tree scans, unnecessary per-frame work, and avoidable allocation in hot paths. Prefer cached references and event-driven updates where appropriate.
- Share immutable resources. Introduce pooling, batching, or background work when a demonstrated workload benefits, with explicit ownership and cleanup.
- If worker threads are introduced, keep live scene-tree mutation on the main thread and define how results are discarded after cancellation or scene exit.
- Preserve established performance mechanisms when changing behavior. Use profiling or focused measurements for optimization decisions.

## Running and validation

Use a Godot 4.7-compatible executable and prefer its console variant for logged checks. On this workstation, the installed console binary is `C:/Program Files/Godot/Godot_v4.7.1-stable_win64_console.exe`. Locate the appropriate binary on other machines.

For automated Godot launches:

- Use an absolute project path and an explicit, unique `--log-file` in a writable task-scoped temporary directory outside the repository.
- Isolate `user://` data from normal play sessions. On Windows, set `APPDATA` to a task-scoped directory in the validation process environment, inherited by its children. Do not change it machine-wide. For checks that write save data, verify that `OS.get_user_data_dir()` resolves inside that isolated location before writing.
- Run imports and runtime checks serially against this checkout. Leave the user's editor and game processes under their control.

After preparing that environment, these command shapes apply:

```powershell
& "<godot-console.exe>" --headless --path "<absolute-project-path>" --editor --quit --log-file "<absolute-import-log-path>"
& "<godot-console.exe>" --path "<absolute-project-path>" --log-file "<absolute-runtime-log-path>"
```

The runtime command starts the movement prototype. It does not yet implement the full game loop. For focused checks, use the commands and capture setup in [movement runtime notes](src/docs/movement.md).

Choose validation from the actual diff, not from the fact that a prompt arrived:

1. Questions, reviews without edits, documentation, and comment-only changes need no engine launch. Review consistency and the diff.
2. For executable scripts, scenes, resources, shaders, imported assets, project settings, or autoload changes, run one headless editor import/check after the edit batch. Inspect the log and exit status. Parser errors, missing resources, invalid UIDs, and startup errors are failures.
3. Run the smallest existing check that covers the changed behavior and its directly affected contracts. Use `check_combat_targeting.gd` for targeting/acquisition, the default `check_combat.gd` fixtures for weapons/impacts, `check_ship_flight.gd` for forces/contacts, `check_movement.gd` for fleet/camera behavior, `check_island_navigation.gd` for island routing, or `check_terrain.gd` for terrain generation. This is a selection guide, not a checklist to run in full. Add regression coverage only for substantial behavior or a bug where it earns its upkeep.
4. Long travel and the three-minute combat encounter require `-- --extended` on their respective checks (`--visual` also opts into the combat encounter for captures). Scale checks, profiling, extended runs, and a full regression sweep are opt-in: run them for an explicit request, a relevant scale/performance change, or a concrete unresolved regression that smaller checks cannot cover. Do not run them for routine edits. Physics validation uses the project's 30 Hz baseline; do not compare alternate rates.
5. For UI, input, camera, shader, or visible asset changes, use one focused rendering-capable run and inspect the affected result. Exercise resizing or input methods only when those contracts changed. Headless import alone does not establish visual correctness; unrelated changes do not require screenshots or a rendered encounter.
6. Once the selected checks pass, stop. Reuse successful results for unchanged code within the task; rerun only checks affected by subsequent edits or new failures. If the engine crashes before a useful log, investigate the launch environment before retrying.
7. Review the final diff and status. Keep temporary logs/captures outside the repository. Report what was checked and any material coverage left out, without expanding validation just to fill a standard list.

Maintain this guide as concise, current working guidance. Put detailed system contracts near their owners or under `src/docs/`, and link them here when needed.
