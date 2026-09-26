# Voxel terrain and journey progression

One world unit is one meter; see the [unit conversion](world_units.md). Terrain is scenery generated with [FastNoiseLite](https://docs.godotengine.org/en/stable/classes/class_fastnoiselite.html). Its authoritative grid currently uses **50-meter cubic voxels** as a visual trial. TerrainProfile also supports 100-meter and 10-meter grids. Detailed assets use 1 meter per voxel; rough asset shapes use ten times that size. Full-detail patches have static collision for wrecks. Destruction, caves, and vegetation are not implemented. Default heights remain below the fleet's cruising altitude; mountain peaks reach into the lower floating-island altitude band.

The [landscape performance investigation](terrain_performance.md) identified CPU meshing stalls. Mesh merging and adaptive detail remain, with background array generation added for this trial. Active generation work and remaining contact/placement requirements live in the [generation task list](todo/blockers-terrain.txt).

## Progression

Read `journey.progression.distance` for forward distance in meters, starting at zero. JourneyProgress records the starting logical RoutePosition and derives the number from the anchor after each movement step. Camera movement, membership changes, and origin shifts do not add distance. A stopped anchor means stopped progression. This is journey distance, not meta progression or a frame/time counter.

The scalar is convenient for thresholds and presentation. Signed segment/offset coordinates remain authoritative for exact long-range placement. The journey start and anchor position together define progression; neither is persisted by the current runtime.

Terrain is the first progression-dependent content. Every ground sample evaluates the same distance formula for **its own logical Z**, relative to the journey start. It does not use the fleet's current distance as a global terrain modifier. Distant mountains can be seen ahead before reaching them; passed grasslands retain their original shape and colors when revisited.

Authored Journey distances:

| Travel distance | Terrain |
| --- | --- |
| 0–1500 meters | Rolling grassland. |
| 1500–10000 meters | Smooth transition in landform height and palette. |
| 10000+ meters | Mountain peaks with broad slopes and dry valleys. |

At 5750 meters the blend is 50%. At the fleet's 25 m/s cruise speed, blending begins after about one minute and reaches full mountains after about six minutes forty seconds, excluding acceleration and slowdowns. The 8500-meter smoothstep transition has a gentle start and finish. Biome definitions and transition distances are tuning choices, not final balance.

## Authoring

Open [journey_terrain.tres](../../resources/terrain/journey_terrain.tres), or Journey → VoxelTerrain → Profile. Its Grassland and Mountains references point to [grassland.tres](../../resources/terrain/grassland.tres) and [mountain_range.tres](../../resources/terrain/mountain_range.tres). Restart the running scene after changes; runtime meshes are not an editor preview.

| Setting | Effect |
| --- | --- |
| Voxel Size | Cubic source grid: 50 meters for this trial, or 100/10 meters for comparison. Restart after changing it; patch extents and height quantization adapt together. |
| Mountain Start / Full Distance | Beginning and end of the progression interval. Full must exceed Start. |
| Biome Height Range | Surface Y limits, divisible by Voxel Size. Grassland defaults to -300…700 (21 possible levels at size 50); mountains to 800…3400. Negative heights lie below the water surface. |
| Biome Height Noise | Seed, frequency, octaves, gain, and domain warp. Lower frequency makes broader landforms; higher-frequency octaves roughen edges, while domain warp bends regular contours. |
| Biome Height Power | Tapers the normalized noise before contrast: 1 preserves its shape; higher powers narrow the upper slopes and summits. Mountains use 2, grassland 1. |
| Biome Height Contrast | Smooth contrast within the height range. Higher values emphasize relief; a soft response avoids abruptly clipping high noise into flat plateaus. Values below one reduce relief continuously to a flat midpoint at zero. |
| Biome Palette | Gradient stops map the biome height range to 0…1. Keep Constant interpolation for discrete elevation bands. |
| Band Noise / Band Warp Height | Independent noise shifts color boundaries so equal heights need not share a color. |
| Cliff Darkening | Darkens vertical faces while preserving elevation bands. |

The sampler blends the two unquantized elevations first, then rounds to the nearest selected voxel height. Color lookup uses the blended height range and noise-varied bands, with a gradual palette blend along the route. This preserves cubic steps while removing an abrupt biome boundary. One setting controls both horizontal and vertical voxel size. Current height limits are compatible with all three supported sizes, so changing Voxel Size alone is enough for a comparison.

Grassland uses green bands and a wider -300…700 height range, replacing the previous four-level terraces. Lower contrast (1.6) and a normalized tanh response avoid hard-clipped hilltops; five octaves with gain 0.45 keep irregular edges without dominating the broad hills.

Mountains use ridged OpenSimplex2 noise at frequency 0.000075, with four octaves, gain 0.45, weighted strength 0.4, and broad domain warping. The larger base scale spreads out the ranges; Height Power 2 tapers the upper slopes into narrower crests. Contrast 1 keeps summit heights varied without flattening them into plateaus. Mountain height limits are 800…3400, giving elevated valleys and taller peaks while keeping full mountain terrain above sea level; ponds can remain in the grassland and early blend. Peaks remain below the fleet's 3800-meter cruising altitude but can intersect low floating islands, whose placement is independent of terrain height. Ships currently navigate only around floating islands; terrain avoidance is not implemented.

## Water and sea level

Water is a flat scenery surface at **Y = 0**. Negative terrain heights form submerged basins; dry voxel columns naturally divide them into ponds. Heights are not clamped to sea level. The fleet starts at Y = 3800 and island reference heights span 2000…5600. The fleet starts above the landscape, while the lower island band overlaps mountain elevations. These flight-space heights do not change route progression, formation offsets, or island avoidance.

[water.tscn](../../scenes/water/water.tscn) contains one plane and its ShaderMaterial. Edit its shader parameters in the Inspector to tune shallow/deep/shore/highlight colors, depth-band size, shore depth, ripple strength, and animation speed. The [voxel water shader](../../shaders/water/voxel_water.gdshader) uses stepped depth colors and slowly changing ten-meter square highlights; it never displaces vertices or rounds the blocky shoreline. Fine highlights fade at a distance to reduce shimmer.

The shader reconstructs opaque terrain depth using Forward+'s reverse-Z depth buffer. Shallow regions are lighter and slightly translucent; deeper water becomes darker and nearly opaque. Zero-height terrain stays dry. This is a visual depth effect, not a stored water volume. Transparent objects are not part of the sampled depth buffer. See Godot's [depth reconstruction](https://docs.godotengine.org/en/stable/tutorials/shaders/advanced_postprocessing.html) and [spatial shader reference](https://docs.godotengine.org/en/stable/tutorials/shaders/shader_reference/spatial_shader.html).

WaterSurface recenters the 122880-meter plane in whole route segments around the anchor, always at Y = 0. Journey registers it as one independent origin root. The shader uses world X/Z rather than plane UVs; its 2560-meter pattern period divides the 10240-meter origin shift, keeping the pattern fixed through coverage movement and rebasing without giant float coordinates. Its coverage exceeds the camera sphere plus far range. Keep these extents in sync if expanding the camera range.

Water has no collision, buoyancy, destruction, or underwater rendering. The free camera can pass through it as it can through terrain; the water surface is visible from above. No water simulation or model-placement system is introduced here.

## Source sampling

TerrainBiome owns each immutable landform and palette definition. TerrainProfile owns the biome references, transition interval, and shared color variation. TerrainSampler owns deterministic coordinate sampling. Mesh construction and streaming consume these definitions without mutating them.

`sample(world_x, segment, offset_z)` returns continuous grassland noise in X, mountain noise in Y, and band noise in Z. `mountain_weight()` resolves location-based progression. `height_from_noise()` and `color_at()` produce the blended terrain. `surface_height(world_x, route)` returns the exact source column top on the selected grid, regardless of rendering detail.

No model catalog or placement framework is implemented. Sampling never consumes island or ship RNG. Placement requirements are recorded under GEN-02 in the [generation task list](todo/blockers-terrain.txt).

## Horizon haze

Journey's WorldEnvironment owns shared depth fog for terrain, water, ships, and islands. It begins at the camera with a 2.2 depth curve: haze is subtle across the nearer landscape and ramps up more strongly toward the edge. It reaches full opacity at 28000 meters, before the camera's 30000-meter far clipping plane. This single curved fog profile supplies both atmospheric depth and horizon concealment. Tune these values on Journey → WorldEnvironment → Environment → Fog.

The procedural sky grades from blue overhead to pale blue at the horizon, with Sky Curve 0.3. Fog Sky Affect is 0, keeping that gradient visible. Fog uses density 1 and the same pale blue as the sky's horizon and both ground colors; the uniform lower sky hemisphere matches fully obscured terrain and water. Keep those colors aligned when authoring the sky or fog. Aerial perspective remains disabled. This is ordinary depth fog, with no volumetric fog or extra terrain coverage.

Forward mountain and backward grassland/water captures were compared at 30000- and 40000-meter camera far distances. Mean summed RGB differences were 0.000020 and 0.000072, respectively, confirming that extending the clipping plane exposed no visible horizon seam in those views. The blue sky and lighter nearer haze were inspected against the previous linear-fog profile. Close water, biome views, and rendered water rebasing also passed. These are visual checks, not performance measurements. Islands still stream inside the visible range; their separate visibility work remains in [GEN-03](todo/blockers-terrain.txt).

## Meshing, detail, and precision

Each patch samples a 32 × 32 display grid. At the current 50-meter resolution, the smallest patches span 1600 meters; root patches span 12800 meters, with 3200/6400-meter patches between them. For 100-meter voxels the minimum is 3200 meters and roots remain 12800; for 10-meter voxels the minimum is 320 and roots are 10240. **Distant meshes are approximations**, while source terrain height queries retain the selected voxel resolution.

Flat neighboring tops merge into rectangles only when height and color match. Matching vertical colors also merge. This removes unnecessary triangles without smoothing silhouettes or erasing nearby voxel steps. Vertical edge skirts close joins between patches at different detail levels. Looking beneath the scenery can reveal these skirts; underground views are not a terrain feature.

VoxelTerrain covers 9 × 9 root regions around the anchor, extending at least 51200 meters to each outer edge with 50/100-meter voxels (40960 at size 10). This covers the 9000-meter camera sphere plus its 30000-meter far range. Detail follows the camera, quantized to 400-meter intervals at size 50, and includes its altitude above the maximum terrain height. Flying high avoids generating unnecessary fine detail. Camera movement changes display detail only. The exported Detail Distance controls how far fine patches extend.

Initial coarse coverage builds before play. Two WorkerThreadPool jobs then build plain vertex/index/color arrays, each with its own sampler/noise state and immutable profile snapshot. Live scene-tree changes and ArrayMesh creation happen on the main thread, under a soft three-millisecond publication budget. One upload or layout commit can still exceed that budget; it is not a hard frame-time guarantee. `build_pending()` remains a synchronous drain for checks/offline tools, not the runtime path.

Existing coverage stays visible until its replacement layout is complete. Requests retain useful in-flight jobs and discard obsolete queued/staged work. A completed obsolete result is dropped before creating GPU resources. A finished layout commits once, even if obsolete jobs still need draining. Scene exit joins outstanding jobs, frees owned meshes, and clears sampling/layout state; removing and reattaching the node starts fresh generation. Child exit unregisters mesh roots from the floating origin. Workers never reference live nodes. Continuous rapid camera movement may delay refinement until generation catches up. Geometry, jobs, and noise caches remain bounded. The recorded measurements cover the current camera range and Detail Distance. See Godot's [thread-safety guidance](https://docs.godotengine.org/en/stable/tutorials/performance/thread_safe_apis.html).

Neither fifty nor one hundred divides the 10240-meter origin segment. TerrainGrid therefore uses exact integer tile identities and quotient/remainder conversions to keep source cells aligned across route boundaries, including negative and huge segment indices. Patch keys retain signed int64 route segments plus normalized small offsets. Only nearby segment differences become scene floats. Each mesh is registered as an independent FloatingOrigin root. Rebasing translates it once and resets interpolation without changing mesh data, progression, or the biome. A job completing after a shift resolves its transform against the current origin.

FastNoiseLite also needs small input coordinates. TerrainSampler groups eight route segments into an 81920-meter noise region, derives seeds from exact integer identities, and blends neighboring fields across that region. This lets broad landforms span multiple origin segments without a short seed cadence. Boundary samples and continuous slopes match before quantization. The mesh sampler reads a neighbor halo even when adjoining meshes are unloaded. Authored noise resources remain unchanged, and the region cache is pruned alongside streaming.

## Wreck collision and visibility

Each full-detail patch owns one StaticBody3D and a shape made by the engine's `ArrayMesh.create_trimesh_shape()`. It reuses the visible voxel geometry, including exact tops and cliff faces. Coarse patches have no collider. Source colliders are created during the existing main-thread publication step, enabled when that layout becomes visible, and removed with their chunk. Parenting them to the chunk makes streaming, scene cleanup, and origin shifts follow the existing terrain lifecycle. No separate sampling, prediction, collision tile cache, or worker queue is used.

Collision layer 4 (mask value 8) is reserved for this terrain; only registered wrecks add it to their mask. Living ships, projectiles, and camera navigation retain their previous masks. Wreck capsules use continuous collision detection. Jolt's CCD movement threshold is 0.05 and maximum penetration is 0.01; these fractions reduce transient ground penetration at the accepted 30 Hz rate and apply to bodies with CCD enabled.

WreckController hides wreck visuals, including their smoke emitters, unless every displayed patch under the hull footprint uses the source grid. It checks moving wrecks at their interpolated position and refreshes all wrecks when a terrain layout commits. Requested detail does not count until it is published. Frozen wrecks reappear when source detail returns, provided they have not expired. Wrecks never force terrain refinement or pin chunks. Coarse terrain has no physical ground support; hidden airborne wrecks expire under their fallback lifetime.

Airship owns settling and cleanup: after first upward contact with static ground, it allows three seconds of settling, then freezes while supported and disables its hull collision. The wreck remains for 25 seconds from first ground contact. A wreck that never lands expires 45 seconds after death. These durations are exported on Airship. Grounded frozen wrecks retain their origin registration until cleanup. Water has no buoyancy or surface collider; full-detail submerged terrain can catch a wreck on the bottom. Ground props, permanent support, and water-specific behavior remain tracked under [GEN-02](todo/blockers-terrain.txt).

`check_wrecks.gd` checks source-grid tops/cliffs, fast and rotated falls, native settling, smoke activation and independent emitter state, coarse/full-detail visibility changes, picking through wrecks while respecting islands, rebasing, expiry, and teardown. Its `--visual` mode captures falling, settled, and hidden wrecks in an external `AERWYTH_CAPTURE_DIR`; it also checks actual GPU particle bounds after hiding longer than their lifetime and moving the source. `--profile` selects a 32-wreck fixture; its accelerated headless frame timings are a focused workload, not a full-game FPS measurement. The landscape profiler includes collider construction in mesh publication costs and reports source collider counts.

## Validation

Follow AGENTS.md's isolated APPDATA, absolute project path, unique external log-file, and serial-launch requirements. After importing, use:

```text
--headless --fixed-fps 30 --script res://scripts/tools/check_terrain.gd
```

The check covers exact grid conversion beyond 2^53 for 10/50/100-meter voxels, progression endpoints/midpoint, deterministic noise, biome relief and continuous contrast near zero, cubic vertices, merged surface coverage, shared-border cliffs, winding, reloads, bounded layouts, background completion after a rebase, obsolete-job discard, and exit with outstanding jobs. It removes and reattaches terrain to check fresh generation and origin registration. It also checks that grassland uses its expanded height range, sea-level placement, water coverage/recentering, and both submerged and dry starting land.

For close and wide rendered grassland/transition/mountain views, omit `--headless`, append `-- --visual`, and provide an existing external directory through AERWYTH_CAPTURE_DIR. This also captures close pond views and compares the rendered water before/after rebasing with animation frozen. The existing [movement checks](movement.md) additionally exercise ordinary camera controls and long travel. Numeric progression is also checked across origin shifts. Rendering/input checks are sensitive to application focus while the workstation is being used.

The pre-conversion five-unit terrain checks passed in D3D12, including grid conversion, meshing, streaming, cancellation, and rebasing. The headless movement/input check also passed, including long travel across eight origin shifts. Close/wide grassland, transition, mountain, and pond views were inspected. The final grassland sample used 19 of the 21 possible height levels, with 809 submerged and 5752 dry columns in the starting-water check. Freezing water animation and rebasing produced a 0.000051 mean summed RGB difference. See the performance notes for measured streaming costs and the limits of the isolated landscape benchmark.

The [generation review](generation_review.md) records the subsequent lifecycle/cleanup fixes, expanded performance coverage, and factual limitations. The source grid is deterministic for the current generator and profile; persistent generation versioning, old-island reconstruction, and physics support are not implemented. Their active requirements live in the generation task list.
