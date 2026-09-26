# Generation production review

The measurements and spatial values below retain the units used when recorded. The subsequent [meter conversion](world_units.md) scales lengths, linear speeds, and linear accelerations by ten; its before/after measurements are recorded separately.

Reviewed 2026-09-25 against the current five-unit terrain, water, progression, island streaming, and fleet integration. **The architecture is coherent and suitable for the current scenery prototype. This review does not establish production readiness.** Active blockers and completion criteria live in the [generation task list](todo/blockers-terrain.txt). A terrain rewrite is not justified by this pass.

Subsequent combat work added spatial filtering for ship avoidance and loaded-island navigation. The measurements below preserve the pre-combat review baseline; see [combat runtime notes](combat.md#recorded-validation-and-limits) for the 220-ship workload and its measured CPU limits.

## Ownership and wiring

| Owner | Contract |
| --- | --- |
| [Journey](../../scripts/world/journey.gd) / [JourneyProgress](../../scripts/world/journey_progress.gd) | Initialize the journey start once, derive progression from the anchor, and request scenery every 0.25 seconds. Camera motion and rebasing do not advance progression. |
| [RoutePosition](../../scripts/world/route_position.gd) / [FloatingOrigin](../../scripts/world/floating_origin.gd) / [TerrainGrid](../../scripts/terrain/terrain_grid.gd) | Keep logical coordinates separate from small scene coordinates. Exact integer tile identities preserve five-unit alignment across 1024-unit shifts. Registered roots shift once. |
| [TerrainProfile](../../scripts/terrain/terrain_profile.gd) / [TerrainBiome](../../scripts/terrain/terrain_biome.gd) | Own authored voxel size, noise, height limits, palettes, and transition distances. Runtime state does not mutate the authored resources. |
| [TerrainSampler](../../scripts/terrain/terrain_sampler.gd) | Derive shape and color from logical location and journey start. Blend grassland/mountain heights before voxel quantization. Bound noise inputs through seeded regions; never consume island/ship RNG. |
| [TerrainMeshBuilder](../../scripts/terrain/terrain_mesh_builder.gd) | Generate merged exposed top/cliff surfaces and visual skirts. This is a heightfield mesher, not a stored solid voxel volume. |
| [VoxelTerrain](../../scripts/terrain/voxel_terrain.gd) | Select camera-dependent detail, schedule bounded jobs with private sampling resources, publish meshes on the main thread, and retain complete coverage until replacement is ready. Resolve the current origin when publishing a completed job. |
| [WaterSurface](../../scripts/water/water_surface.gd) | Keep scenery water at Y = 0, recenter its finite coverage, and preserve shader alignment through origin shifts. There is no water physics. |
| [IslandSpawner](../../scripts/islands/island_spawner.gd) | Generate logical island records from a dedicated RNG, maintain loaded views and navigation obstacles, and unload trailing views. Records currently remain in memory. |

The main scene supplies explicit references to these owners. Terrain coverage includes the permitted camera position plus its far plane; water coverage also covers that view. Default terrain remains below ship/island flight space. Terrain detail changes do not alter progression, source sampling, or island placement. Island visibility has a different coverage limitation, described below.

There were no missing static resource paths or orphan script/shader UID sidecars in the reviewed files. The former flat-ground implementation is no longer a parallel runtime path. Existing model authoring files were preserved. `surface_height()`, synchronous `build_pending()`, the mesh-returning builder wrapper, and build timing hooks have deliberate query/check/profiling uses; they are not abandoned generation code.

## Contained fixes completed

- Cleared all owned terrain generation state on scene exit, after joining outstanding jobs. Removing and reattaching terrain now rebuilds and registers fresh mesh roots instead of retaining stale queues and views.
- Added an explicit dirty-layout flag so an already committed layout is not repeatedly traversed while obsolete jobs finish.
- Removed the unused biome ridge mode and the floating-origin signal with no subscribers. Current authored biomes already used ordinary height noise; root registration remains the origin-shift contract.
- Made height contrast approach flat terrain continuously at zero. Previously a tiny positive contrast could restore almost full relief. Current authored contrast values retain their output.
- Avoided sampling an unused palette outside the biome transition. Replaced the duplicated segment-length literal and asserted positive grid divisors.
- Cached navigation-debug circle points and one inverse transform per redraw. The overlay no longer repeats trigonometry and transform inversion for every ship/vertex.
- Extended existing tools to measure the biome transition, close fast camera movement, settled streaming backlog, and a rendered 128-ship scene with debug off/on. Fleet captures restore fleet focus after the profiling camera pass.
- Corrected stale documentation paths and removed documentation for the deleted ridge option. Added lifecycle and contrast regression coverage.

## Measured performance

Development executable, Godot 4.7.1, D3D12 Forward+, Ryzen 7 9800X3D / RTX 4090. Actual render target 1920 x 1080, V-Sync and frame limit disabled, editor left open. These are samples on this workstation, not release-build or lower-end guarantees. Uncapped wall-frame percentiles include frames without a physics tick; simulation-step time is reported separately.

The expanded isolated landscape run uses the production terrain/water/environment and excludes ships, islands, and navigation drawing:

| Measurement | Grassland, distance 0 | Transition, distance 3250 | Mountains, distance 6000 |
| --- | ---: | ---: | ---: |
| Synchronous coarse startup | 895 ms | 991 ms | 1090 ms |
| Full initial detail ready, total elapsed | 2080 ms | 2091 ms | 2343 ms |
| Stationary GPU time, median | 0.220 ms | 0.244 ms | 0.263 ms |
| Close camera at 300 units/s, p95 wall frame | 0.697 ms | 0.692 ms | 0.713 ms |
| Close camera at 300 units/s, maximum wall frame | 2.176 ms | 2.019 ms | 2.621 ms |
| Pending/in-flight patches after each travel/camera phase | 0 | 0 | 0 |

All three regions also settled with zero backlog. Across travel/camera phases, the largest terrain processing update was 1.882 ms, the largest region-selection update 1.840 ms, and the largest individual upload 0.967 ms. **Those are separate measurements, not a total terrain frame budget.** Selection and publication can occur in the same frame. One stationary water-disabled grassland frame took 35.304 ms without a mesh build; the cause was not established. Startup remains a visible blocking cost.

The combined 128-ship check runs real simulation, island detours, terrain streaming, water, and rendering. Its camera moves within the fleet sphere, so ships are not all visible in every view. The measured final run produced:

| Measurement | Navigation debug off | Navigation debug on |
| --- | ---: | ---: |
| Wall frame p95 | 8.531 ms | 13.014 ms |
| Wall frame p99 | 9.824 ms | 15.817 ms |
| Maximum wall frame | 20.597 ms | 18.445 ms |
| Frames over 16.67 ms / measured frames | 3 / 10,798 | 9 / 2,639 |
| GPU time, median | 0.261 ms | 0.696 ms |
| Peak queued/in-flight patches | 24 | 26 |

The script simulation step was 8.283 ms median / 10.149 ms p95. All 128 ships remained registered; 752 travel goals were reached and 38 ships detoured. The debug-on p95 wall frame improved from 15.931 to 13.014 ms after caching debug geometry calculations, about 18% in these two runs. Occasional spikes remain; this is not a locked-60-FPS claim. The moving phases ended with 2/4 patches still in progress, unlike the separately settled landscape run.

Verdict: landscape generation/streaming passes the measured prototype workload and does not justify discarding the existing merging, adaptive detail, or worker implementation. The complete endgame budget is not yet proven: the 128-ship script step already consumes substantial CPU time before combat, production assets, vegetation, or wreck physics.

## Recorded limitations

The reviewed runtime supports forward travel without saved generator/profile identity or a world snapshot. Island records grow with travel and survive unloading, but `update_region()` does not reconstruct unloaded records for revisits. Terrain has no colliders. Its source height queries are stable while distant display patches approximate the source, so display detail alone does not establish stable support for physics or placed models.

Islands load 1500 units ahead, remain 1300 behind, and occupy a field with 1600-unit half-width. A camera up to 900 units from the fleet can look another 3000 units. Islands can therefore appear or disappear inside a permitted view; current fog does not establish an opaque cutoff at the streaming edge. Terrain and water cover a wider area.

Coarse startup builds all 81 root patches synchronously, blocking for roughly one second here. Later publication has a soft budget and whole-layout swaps, not a hard maximum frame cost. Configuration validation relies on assertions, and worker completion assumes valid mesh results without a recoverable generation-failure path. No loading UI was added during this review.

The pre-combat measurements above expose limited CPU headroom despite small terrain/GPU costs. The subsequent spatial filters are documented with their results in the combat notes; neither set of measurements establishes whole-game performance with production assets, vegetation, and wreck physics. The corresponding work and acceptance criteria are maintained only in [GEN-01 through GEN-05](todo/blockers-terrain.txt).

## Verification and reproduction

Headless editor imports, headless and rendered terrain checks, movement/input and eight-origin-shift travel checks, island navigation checks, and the rendered 128-ship check passed. Rendered terrain, water/rebase, and fleet/navigation-debug captures were inspected. Resource paths, documentation links, sidecars, and final diffs were reviewed. Temporary logs, JSON reports, and captures remain outside the repository in `aw-generation-review-e3cd31da` under the workstation's temporary directory.

Follow [AGENTS.md](../../AGENTS.md) for serial engine launches, absolute paths, unique logs, and process-local APPDATA isolation. Existing [terrain checks](terrain.md#validation) and [movement checks](movement.md#validation) reproduce correctness coverage. The [landscape profiler instructions](terrain_performance.md#reproduce) reproduce the isolated benchmark. For the combined measurement, set `AERWYTH_PROFILE_DIR` to an existing external directory and run:

```text
--path <absolute-project-path> --script res://scripts/tools/check_fleet_scale.gd --log-file <external-log-file> -- --profile
```

Omit `--headless` and `--fixed-fps` for profiling. This writes `fleet-128.json`; append `--visual` and set external `AERWYTH_CAPTURE_DIR` for captures. The tool uses separate runtime instances and leaves authored scenes/settings unchanged.
