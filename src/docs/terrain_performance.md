# Landscape performance and voxel-size decision

The measurements and spatial values below retain the units used when recorded. The subsequent [meter conversion](world_units.md) scales lengths, linear speeds, and linear accelerations by ten; its before/after measurements are recorded separately.

Measured on 2026-09-25 using the workstation's Ryzen 7 9800X3D and RTX 4090, Godot 4.7.1, D3D12 Forward+, and NVIDIA driver 610.47.

## Current trial: five-unit voxels

The current visual trial uses **5 × 5 × 5 world-unit source voxels**, with 1/5/10-unit choices in TerrainProfile. Grassland now spans -30 to 70 units rather than four fixed terraces. Mountain noise no longer folds zero crossings into sharp crests: ordinary height noise, reduced fine-detail strength, and gentler warping form broader slopes. Both biomes use soft contrast to reduce clipped hilltops. Detailed-asset scale is unchanged.

Merged surfaces, adaptive detail, and background generation are retained from the ten-unit trial. Two bounded worker jobs generate mesh arrays with owned sampler/noise state. The main thread publishes meshes, retains visible coverage until replacements are ready, and discards obsolete results. Initial coarse coverage remains synchronous; fine detail loads afterward. LOD accounts for camera altitude, and exact integer terrain-grid conversions keep five-unit cells aligned across 1024-unit origin shifts.

The historical measurements below predate terrain collision and retain the previous ten-unit and one-unit baselines. Current collider measurements are recorded separately below.

The subsequent [generation production review](generation_review.md#measured-performance) adds the transition biome, a close-camera stress pass, and combined rendered 128-ship measurements. It records fixes and limitations; active work lives in the [generation task list](todo/blockers-terrain.txt). The earlier trial tables below remain historical measurements.

## Method and scope

[profile_landscape.gd](../../scripts/tools/profile_landscape.gd) reuses the production terrain sampler, mesh builder, streaming, water, lighting, and environment. It isolates the landscape by omitting ships, islands, and navigation debug. It fixes the actual render target at 1920 × 1080, disables V-Sync/frame limiting, waits for initial detail, warms each view for 90 frames, and records render CPU/GPU time, wall frame times, terrain build/upload time, draw/triangle counts, and queued/in-flight work.

Stationary phases last two seconds. A separate sky-only phase and a water-disabled phase provide comparison points. Travel runs at nine units/second for eight seconds; camera passes run at 100 and 300 units/second for five seconds each, reversing within the fleet viewing sphere. The expanded tool also runs a 300-unit/s pass at Y = maximum terrain height + 30, then waits up to 15 seconds for remaining streaming work. Streaming requests occur every 0.25 seconds, matching Journey. Grassland starts at journey distance zero, transition at 3250, and mountains at 6000. Biome labels refer to the anchor location; ahead-loaded chunks can already contain later terrain. This is an isolated development-build benchmark, not a whole-game/endgame FPS claim, nor a lower-end hardware guarantee. The user's editor remains open and desktop activity can affect timings.

Render timings use Godot's [viewport measurements](https://docs.godotengine.org/en/stable/classes/class_renderingserver.html#class-renderingserver-method-viewport-get-measured-render-time-gpu). They distinguish render work from scripts. GPU power-state changes can affect readings during CPU stalls. Frame-time percentiles from an uncapped run contain many cheap idle frames, so the report also includes maxima and the time spent specifically generating terrain.

## Initial five-unit trial measurements

The same isolated 1920 × 1080 benchmark was rerun with the expanded grassland range and softened mountain landforms. Source size, relief, and noise all changed, so these are whole-configuration results rather than a pure voxel-size comparison.

| Measurement | Grassland | Mountains |
| --- | ---: | ---: |
| Synchronous coarse startup | 0.89 s | 1.14 s |
| Full initial detail ready, total elapsed | 2.00 s | 2.53 s |
| Stationary GPU time, median | 0.235 ms | 0.261 ms |
| Camera at 300 units/s, largest terrain main-thread update | 0.86 ms | 1.18 ms |
| Pending/in-flight patches after sprint | 0 | 0 |
| Loaded triangles after initial refinement | 644,734 | 1,080,518 |

Across the travel/camera phases, terrain main-thread updates stayed below 1.8 ms and individual mesh uploads below 1 ms. No measured wall frame exceeded 16.67 ms. Desktop scheduling affected early grassland phases, including sky-only frames, so these uncapped measurements are not a full-game FPS claim. Background generation, merging, and adaptive detail are unchanged from the ten-unit trial. Logs and captures are in the external `aw-terrain5-16408b55` task directory.

## Historical ten-unit trial measurements

Same workstation and fixed 1920 × 1080 render target. New landforms and the larger 1280-unit root tiles change the workload, so this compares complete implementations rather than isolating voxel size alone.

| Measurement | Grassland | Mountains |
| --- | ---: | ---: |
| Synchronous coarse startup coverage | 0.88 s | 1.23 s |
| Full initial detail ready, total elapsed | 1.61 s | 2.47 s |
| Stationary GPU render time, median | 0.215 ms | 0.249 ms |
| Normal travel, largest terrain main-thread update | 1.90 ms | 1.59 ms |
| Camera at 100 units/s, p95 wall frame | 0.71 ms | 0.81 ms |
| Camera at 300 units/s, p95 wall frame | 0.69 ms | 0.80 ms |
| Camera at 300 units/s, largest terrain main-thread update | 1.01 ms | 1.84 ms |
| Pending/in-flight patches after sprint | 0 | 0 |
| Loaded triangles after initial refinement | 379,812 | 1,277,620 |

Worker generation still takes tens of milliseconds for some patches, but no longer blocks that frame's main thread. Measured individual uploads stayed below 1.3 ms during travel/camera passes. The main-thread terrain timings include completion, publication, scheduling, and layout commits; region selection is measured separately. The three-millisecond publication budget remains soft. There were no wall frames over 16.67 ms in the measured phases, but startup still blocks while coarse coverage builds.

The early grassland stationary phases showed more desktop/scheduling variation than later phases, including sky-only frames. Prefer the directly measured terrain/GPU costs over inferring a general FPS increase from this uncapped run. These results do not predict full-game performance with combat, vegetation, or falling wrecks.

Headless and rendered terrain checks passed, including all three grid sizes, background cancellation, scene exit with jobs pending, and rebasing during a build. Movement/input, long-travel, 128-ship, and island-navigation checks also passed. Grassland, transition, mountain, pond, and fleet views were inspected. Results and captures were written outside the repository under the task-scoped `aw-terrain10-1a92a656` temporary directory.

The updated equal-area tool also passed for 1/5/10-unit voxels. On the new landforms, generating the same 320-unit square took approximately 660/27/7 ms in grassland and 1264/51/12 ms in mountains. Those are synchronous whole-area mesh costs, not frame times. That small grassland square contains three of the four possible ten-unit heights; the larger grassland sampling check verifies all four.

## Historical one-unit terrain results

Original fixed-resolution run before the ten-unit trial and background generation; values are rounded:

| Measurement | Grassland | Mountains |
| --- | ---: | ---: |
| Synchronous initial terrain build | 3.45 s | 9.92 s |
| Stationary GPU render time, median | 0.25 ms | 0.30 ms |
| GPU time with water hidden, median | 0.22 ms | 0.27 ms |
| Normal travel, worst wall frame | 65 ms | 46 ms |
| Camera at 100 units/s, p95 wall frame | 5.7 ms | 17.2 ms |
| Camera at 100 units/s, worst wall frame | 22 ms | 45 ms |
| Camera at 300 units/s, p95 wall frame | 9.5 ms | 19.9 ms |
| Pending patches after sprint phase | 139 | 191 |
| Loaded triangles immediately after startup | 1.22 million | 2.74 million |

Loaded triangles include off-camera terrain. Stationary GPU draw work sees only part of that coverage. Water adds roughly 0.03 ms to the median in these views; it is not the observed bottleneck.

In the original mountain camera pass, individual near patches took roughly 11–18 ms, with larger patches reaching about 50 ms. The nominal three-millisecond build budget was checked **between complete patches**. A single call to `TerrainMeshBuilder.build()` could not yield midway, so the budget was not a hard frame-time limit. Full initial coverage also built synchronously.

Original code inspection identified these costs: `_wall()` examined every one-unit vertical step even on distant cliffs; each mesh resampled a 34 × 34 halo; and a pending layout had to finish completely before replacing the visible layout. Camera movement could cancel staging and postpone detail, while LOD used horizontal distance only even when the camera was hundreds of units above the ground. The current trial moves generation to workers, uses the selected voxel height for cliff steps, and includes altitude in LOD; halo sampling and whole-layout replacement remain.

## Historical equal-area 1-unit versus 10-unit experiment

The profiler's `--cells` mode generates the same **320 × 320 world-unit area** at full resolution for each scale. Height/noise definitions and world coverage stay fixed within a comparison. Vertical quantization and cliff steps change along with horizontal cell size. Both variants use merged exposed surfaces, with no edge skirts. Each mesh still samples 32 × 32 cells: the fine variant needs 100 meshes and the coarse variant one. The following measurements used the original smoother landforms; rerunning the tool now uses the current authored terrain and also includes five-unit voxels.

| Region and voxel size | Total mesh build | Triangles | Distinct mesh height levels |
| --- | ---: | ---: | ---: |
| Grassland, 1 unit | 559 ms | 48,506 | 24 |
| Grassland, 10 units | 5.9 ms | 590 | 3 |
| Mountains, 1 unit | 1,121 ms | 479,368 | 192 |
| Mountains, 10 units | 11.9 ms | 5,814 | 20 |

The savings are real. Increasing cell width tenfold reduces this heightfield's sampled surface columns about 100-fold, rather than implying a 1000-fold volumetric saving: the implementation does not store solid voxel volumes. These local results **cannot be multiplied into an equivalent whole-game speedup**. The production landscape already uses much coarser samples outside the camera's fine-detail area, and GPU rendering is already inexpensive on this machine. The experiment is not a replacement streaming implementation for ten-unit cells.

Rendered comparisons show substantially flatter grassland, enlarged shoreline steps, and most shallow water bands disappearing at ten-unit resolution. The tool saves matching `cells-0-1.png` / `cells-0-10.png` and `cells-6400-1.png` / `cells-6400-10.png` views outside the repository.

## Collision construction estimate

In the original one-unit experiment, converting already-built 32-unit fine meshes into trimesh shape resources averaged about 0.48 ms per grass tile and 1.96 ms per mountain tile. Across the whole 320-unit square that was 48 / 196 ms. This measures shape-resource creation only, including render color subdivisions. It does **not** measure world insertion, contact solving, many simultaneous wrecks, CCD, or sleeping. This historical experiment did not implement runtime collision. Full-detail native colliders are now implemented; ground props, water behavior, and hardware coverage remain under GEN-02/GEN-05 in the [generation task list](todo/blockers-terrain.txt).

The original investigation changed only tools and notes. The ten-unit trial introduced background streaming; the current five-unit trial tunes scale and landforms while preserving that implementation. Those historical runs did not include collision.

## Full-detail terrain colliders (2026-09-26)

The current 50-meter grid adds one native static trimesh collider to each source-detail
patch using its existing mesh. Coarse patches have no collision. The table below
comes from a fresh D3D12 Forward+ landscape run at 1920 ? 1080, uncapped rendering,
and the project's 30 Hz physics baseline on the development workstation (Ryzen 7
9800X3D / RTX 4090). It covers stationary views, travel, camera movement, and close
camera movement through grassland, transition, and mountain regions.

| Region | Source colliders at sampled phase ends | Worst collider creation + insertion | Worst terrain process | Worst measured wall frame |
| --- | ---: | ---: | ---: | ---: |
| Grassland | 64?92 | 2.592 ms | 4.564 ms | 5.046 ms |
| Transition | 64?84 | 3.982 ms | 5.983 ms | 6.422 ms |
| Mountains | 64?92 | 4.760 ms | 6.340 ms | 6.761 ms |

No sampled measurement-phase frame exceeded 16.67 ms. Startup/refinement is reported
separately by the profiler and is not included in those frame maxima. Collider
creation is paid when a new source patch is published, not every simulation tick.
It can exceed the existing soft three-millisecond publication budget. The profiler's
mesh-publication timer includes collider construction/insertion; its collider timer
isolates that portion. This run has no combat ships and is not an on/off comparison
or a whole-game frame-rate guarantee.

A separate accelerated headless check dropped 32 Kestrel wrecks onto flat source
terrain before the later reduced-gravity and death-smoke changes. All landed,
froze while supported, hid/reappeared with terrain detail,
rebased, and expired. It retained 72 source colliders and reported 0.425 ms p95
between physics frames, including engine work in that isolated fixture. Flat test
terrain understates collider complexity; use the landscape measurements for actual
terrain publication cost. A rendered six-wreck check confirmed the visibility and
settling result. Terrain streaming/cancellation, composed targeting/lifecycle, and
native flight/contact checks passed as well.

Logs, JSON, and captures are under the external task directory
`aerwyth-wrecks-d729a05d`; the landscape run writes `landscape/landscape.json`.

## Reproduce

Follow AGENTS.md's serial Godot launches, isolated process-local APPDATA, absolute project path, and unique external log-file rules. Set `AERWYTH_PROFILE_DIR` to an existing writable directory outside the repository. Use the console executable with:

```text
--path <absolute-project-path> --script res://scripts/tools/profile_landscape.gd --log-file <external-log-file>
```

Append `-- --cells` for the equal-area comparison. Do not use `--headless` or `--fixed-fps`: GPU timing requires rendering, and streaming should advance with actual elapsed time. Results are written as `landscape.json` or `cells.json`, plus PNG captures. The tool operates on separate runtime instances and does not modify authored resources or project settings.

For combined fleet/terrain/debug measurements, use `check_fleet_scale.gd` with `-- --profile` instead. The same environment and rendering requirements apply; it writes `fleet-128.json`. See the [review](generation_review.md#verification-and-reproduction) for the command and interpretation limits.
