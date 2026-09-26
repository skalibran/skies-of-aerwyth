# World units and tenfold conversion

As of 2026-09-26, **one world unit is one meter**. The prototype was enlarged tenfold while preserving its camera framing, proportions, motion timing, and workload. Values are authored directly in meters; no runtime conversion layer or scaled physics parent is involved.

## Dimensional rules

Lengths, positions, linear velocities, linear accelerations, and absolute distance tolerances were multiplied by ten. Squared-distance and squared-speed thresholds were multiplied by one hundred. Noise frequencies and fog density were divided by ten. Durations, angles, angular rates, mass, friction, drag coefficients, health, damage, entity counts, mesh subdivisions, and the 30 Hz physics rate retain their previous values.

Collision shapes are sized directly. ShipFlight still computes mass-scaled linear forces and inertia-scaled yaw torque, so larger hull inertia preserves the authored turning response. Jolt contact distances and linear velocity thresholds are converted in `project.godot`. Existing stylized gravity is retained: project gravity is 98 m/s², living ships disable it, and cannonballs use their independent 30 m/s² acceleration.

| Quantity | Previous prototype value | Current value |
| --- | ---: | ---: |
| Ship collision capsule height | 10 units | 100 m |
| Ship propulsion target | 18 units/s | 180 m/s |
| Ship acceleration / braking | 3 / 4 units/s² | 30 / 40 m/s² |
| Cannon launch speed / range | 100 units/s / 100 units | 1000 m/s / 1000 m |
| Initial camera orbit distance | 180 units | 1800 m |
| Camera sphere / far plane | 900 / 3000 units | 9000 / 30000 m |
| Terrain voxel choices | 1 / 5 / 10 units | 10 / 50 / 100 m |
| Default terrain voxel | 5 units | 50 m |
| Detailed / rough asset voxel | 0.1 / 1 units | 1 / 10 m |
| Floating-origin segment | 1024 units | 10240 m |
| Origin shift threshold | 768 units | 7680 m |

Camera near/far planes, shadow distances, island generation/loading, navigation and targeting grids, formation dimensions, spawn regions, and debug geometry follow the same conversion. Terrain keeps the same patch counts, sample resolution, noise seeds, and worker limits. Noise wavelengths, warp amplitudes, progression distances, water depth bands, and square highlights scale together. The 2560-meter water pattern period divides each origin shift exactly.

The unused Kestrel OBJ meshes import at tenfold scale while the OBJ/VOX source geometry remains intact. Missing OBJ material companions were restored using the existing palette so reimport succeeds. Runtime ships still use their primitive scenes.

## Validation and appearance

Headless editor import and the existing targeting, combat, flight/contact, movement/input, island navigation, and 128-ship checks passed. The converted ballistic reference fixtures retain their original 3.083597 / 5.485838-second flight times at 600 / 1000 meters. Rendered terrain validation passed all three grids, progression, meshing, background streaming, cancellation, and rebasing. Frozen water animation gave a mean summed RGB rebase difference of 0.0000468.

The rendered three-minute combat encounter reached both 100-ship caps, fired 28,293 shots, and recorded 192 destructions. The separate 220-ship benchmark passed registration/replacement, rebase, and projectile cleanup checks; synchronized misses still peaked at 1,760 live shots. Close ship views and before/after fleet, terrain, and pond captures were inspected. Framing, proportions, shorelines, fog, and visible terrain detail match closely.

This is visual and behavioral equivalence, not bit-for-bit simulation identity. Floating-point rounding can change contact trajectories and a few terrain quads near quantization thresholds. For example, the transition landscape's detailed mesh contained 857,952 triangles before conversion and 857,946 afterward; both used 246 patches.

## Performance comparison

The immediate baseline was commit `dd54f87`. Before/after runs used Godot 4.7.1, Windows D3D12 Forward+, Ryzen 7 9800X3D / RTX 4090, 1920 × 1080, uncapped rendering, and the same 30 Hz project physics rate. Each configuration was measured once with the existing benchmarks.

| 220-ship phase | Script step p95 before / after | Wall-frame p95 before / after |
| --- | ---: | ---: |
| Combat, debug off | 18.699 / 18.049 ms | 16.748 / 16.494 ms |
| Combat, debug on | 14.058 / 12.873 ms | 17.798 / 16.851 ms |
| Synchronized misses | 7.201 / 6.978 ms | 7.881 / 8.457 ms |

The script timer excludes subsequent native rigid-body integration/contact solving. Whole-frame timings include that work. Combat phase GPU p95 was 1.039 / 1.099 ms with debug off and 2.132 / 2.167 ms with debug on. Changing contact histories and workstation timing noise prevent interpreting small differences as an optimization.

The isolated landscape benchmark retained matching patch counts and built-patch counts in every corresponding phase. Stationary grassland, transition, and mountain GPU p95 values were respectively 0.228 / 0.228, 0.254 / 0.256, and 0.273 / 0.273 ms. Their draw counts remained 82, 91, and 87. Coarse startup stayed approximately 0.85–1.10 seconds. These runs show **no material performance regression from the unit conversion**; hardware/release coverage remains as recorded in the [combat](todo/todo-combat.txt) and [generation](todo/blockers-terrain.txt) task lists.

Raw logs, JSON, and PNGs are outside the repository at `C:/Users/lukas/AppData/Local/Temp/aerwyth-meters-554f4199`, under `before/` and `after/`. Reproduce with `profile_landscape.gd` and `check_combat_scale.gd -- --profile --visual`, using the isolated environment and serial launch procedure in [AGENTS.md](../../AGENTS.md), `AERWYTH_PROFILE_DIR`, and `AERWYTH_CAPTURE_DIR`. Older performance documents retain their original units and measurements.
