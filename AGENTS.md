# Skies of Aerwyth agent guidance

## Project baseline

Skies of Aerwyth is a new Godot project. Read the [game design document](src/game_design_document.md) for its gameplay concept and visual direction. Treat sections marked TBD as unresolved design decisions. Runtime architecture is not yet documented. Use the user's requirements, the design document, and the code that exists as the authority for implementation; the document describes intended systems, not implemented features.

Current technical baseline:

- `project.godot` declares Godot 4.7 and Forward Plus, with Jolt Physics and D3D12 on Windows.
- Display stretch uses `canvas_items` with `expand` aspect. No explicit design resolution is configured.
- The project starts with an icon and configuration. There is no main scene, gameplay script, autoload, test framework, configured linter, localization pipeline, or export preset yet.
- Use GDScript by default. Add languages, addons, and external dependencies only when the task justifies them.
- `.godot/` contains generated editor and import state. Do not edit or commit it.

Update this baseline when the corresponding systems are introduced. The comparison in `docs/dungeon-directive-notes.md` is background material, not a specification for this game's mechanics.

## Working rules

- Inspect `git status` before and after work. Preserve unrelated changes and hand-authored content.
- Push only when the user explicitly authorizes pushing the work. Editing, testing, staging, and committing do not independently authorize a push.
- Read the affected files and adjacent systems before choosing an implementation. Carry authorized work through implementation and appropriate verification.
- Keep edits scoped to the task. Avoid incidental renames, formatting churn, dependency changes, and cleanup of unrelated debug or temporary content.
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
| `src/` | The [game design document](src/game_design_document.md), editable art sources, and other authoring inputs. Keep `src/.gdignore` in place, and export runtime assets into `assets/`. Gameplay code belongs in `scripts/`. |
| `localization/` | Editable translation sources if localization is introduced. |
| `scripts/tools/`, `scenes/tools/` | Purposeful validation and content-generation tools. |
| `docs/` | Design decisions, technical notes, and reference material. |

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

- Use tabs in GDScript, `snake_case` for files, functions, and members, and `PascalCase` for global classes. Use typed declarations where practical.
- Keep engine callbacks such as `_ready()`, `_process()`, `_physics_process()`, and input callbacks focused on orchestration. Put substantive operations in clearly named functions.
- Write concise English comments for non-obvious intent, timing, and invariants. Use complete sentences and describe the code for a reader who has not seen the conversation.
- Use Input Map actions for gameplay controls. Add actions and their consumers together when controls are introduced.
- Keep UI layout in authored Control scenes and containers where practical. Give viewport layout a clear owner, use shared theme resources for common styling, and avoid scattered fixed screen coordinates.
- Preserve resource UIDs and serialized references when moving or editing scenes and resources. Keep engine-generated `.uid` sidecars and source-adjacent `.import` settings under version control. Do not fabricate or casually regenerate identifiers.
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

The runtime command requires a configured main scene. Until one exists, validate a specific scene when one is available, and do not claim the whole game is runnable.

Validation should match the change:

1. For scripts, scenes, resources, shaders, imported assets, project settings, or autoload changes, run the headless editor import/check. Inspect the log as well as the exit status. Parser errors, missing resources, invalid UIDs, and startup errors are failures.
2. Run relevant existing focused checks when available. Add meaningful regression coverage for substantial behavior or a bug where it earns its upkeep. Do not invent a test suite or permanent harness for a simple documentation or presentation edit.
3. Exercise affected runtime behavior. For UI or rendering changes, use a rendering-capable run and inspect the result. Check resizing and relevant input methods when layout or navigation changes. Headless import alone does not establish visual correctness.
4. If the engine crashes before producing a useful log, investigate the launch environment before retrying. Do not repeatedly spawn failing processes.
5. Review the final diff and status. Keep temporary logs and captures out of the commit. Report what changed, what was checked, and any remaining limitation.

Documentation-only edits require a consistency and diff review, not an engine launch. Maintain this guide as concise, current working guidance. Put detailed system contracts near their owners or under `docs/`, and link them here when needed.
