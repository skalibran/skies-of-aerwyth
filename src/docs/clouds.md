# Voxel clouds

Journey streams decorative clouds around the persistent fleet marker in three configurable height layers. Every cloud uses **fixed 50-meter cubic voxels** and a randomly selected cached shape with a **1000–3000 meter horizontal span**. Span means the longest horizontal side of the mesh's bounds, not its diagonal or vertical thickness. Meshes are generated at their final dimensions: larger clouds contain more voxels. Instances have unit scale and retain their generated orientation on the world axes without rotation. Clouds have no collision, navigation, targeting, weather simulation, or island-transition behavior.

## Authoring

Open [journey_clouds.tres](../../resources/clouds/journey_clouds.tres) or the Profile on [clouds.tscn](../../scenes/clouds/clouds.tscn). Profile edits apply on the next run.

| Parameter | Effect |
| --- | --- |
| World Seed | Reproducible random positions, types, shapes, and sizes. Change it for another field. |
| Types | Array of editable `CloudType` resources. Duplicate a preset and add it here to introduce a type. |
| Layers | Array of editable `CloudLayer` resources controlling cloud-base altitude, height variation, and independent density. |
| Span Range | Minimum and maximum horizontal size, default 1000–3000 meters. Both endpoints must be multiples of Voxel Size, at least 100 meters and two voxels. Equal endpoints give a fixed size. Maximum span plus Cloud Gap must fit within the 10240-meter origin segment. |
| Voxel Size | Physical cube width, default 50 meters. This is a cloud setting independent of terrain resolution and LOD. |
| Variants Per Type | Number of generated meshes shared by instances of each type, default four. Each variant has a different shape seed and samples a size across Span Range. |
| Cell Size | Reference spacing for density: 640, 1280 (default), or 2560 meters. Actual placement slots also accommodate cloud bounds and clearance. |
| Cloud Gap | Minimum horizontal clearance between cloud bounds in the same layer, default 200 meters. |
| Field Half Width / Look Ahead / Keep Behind | Bounded coverage around the marker, each defaulting to 24320 meters. |
| Ground Clearance | Reject bases below nine landscape samples across the cloud footprint plus this margin, default 100 meters. |

Each layer exposes **Altitude**, **Height Variation**, and **Density**. Altitude refers to the cloud base above sea level. Height variation randomly offsets each base above or below that level; set it to zero for exact fixed Y. Density sets the target clouds per reference cell area, with zero disabling the layer. It controls placement spacing instead of randomly leaving individual cells empty. Actual density is capped by the room needed for the largest eligible cloud and its clearance. Each layer has its own layout and seeded choices.

| Layer | Base altitude | Density | Eligible types at the default height |
| --- | --- | --- | --- |
| Low | 2100 ± 200 m | 0.3 | Stratus, Cumulus |
| Middle | 5200 ± 300 m | 0.3 | Altocumulus |
| High | 8200 ± 400 m | 0.2 | Cirrus |

The fleet's 3800-meter travel altitude sits roughly midway in the clear gap between the low layer's tops and the middle layer's bases. All layers and type altitude preferences were raised together by 700 meters, preserving their spacing and type mix. Within nine horizontal kilometers of the starting marker, the median low-layer top is about 2452 meters and the median middle-layer base is about 5198 meters, centering the gap near 3825 meters. Cloud tops vary with shape and size while bases remain within their layer. Terrain rejection can leave gaps in the low layer over mountains; it never pushes those clouds into a different height band.

Every placement slot receives one cloud when its altitude has an eligible type and clears terrain. Rows have seeded horizontal offsets; clouds have bounded random movement inside their slots, capped at 20% of slot width/depth. The actual mesh bounds, including an off-center pivot, stay inside the slot with half of Cloud Gap reserved at each edge. This spreads clouds evenly without merging adjacent footprints. Clearance applies within each layer; clouds in different height layers may overlap in an overhead view.

Cloud types expose their altitude range and selection weight, depth and height ratios, puff count and size, erosion, base cut, curl, and top/base colors. Voxel size belongs to CloudProfile and is shared by every type. The default spans contain 20–60 voxels across their longest horizontal side. The cube width stays 50 meters across all cloud sizes and terrain detail levels. Vertices sit on an integer local voxel grid; placement retains each layer's random base height and X/Z position.

Shapes consist entirely of overlapping lobes, distributed across the horizontal footprint with varied radii and depth offsets. Larger lobes rise higher from a shared base, producing an uneven skyline and scalloped edges. There is no solid central ellipsoid filling the footprint. **Puff Size** controls overlap, **Puff Count** controls the number of lobes, and **Height Ratio** controls overall thickness. Cumulus and altocumulus each use five broad lobes so they read as coherent clouds; their height ratios are 0.38 and 0.18 respectively. Cirrus uses four lobes along a thin curled shape.

To preserve mesh sharing, size varies through the cache instead of instance scaling. The four default variants per type span **1000, 1650, 2350, and 3000 meters**. Sizes are evenly distributed through the range and snapped to the voxel grid; one variant uses the midpoint. Spawns randomly select a variant for their altitude-appropriate type. Changing the range or voxel size rebuilds the meshes on the next run.

| Preset | Preferred base altitude | Shape |
| --- | --- | --- |
| [Stratus](../../resources/clouds/stratus.tres) | 1300–2700 m | Broad, thin layer with a muted underside. |
| [Cumulus](../../resources/clouds/cumulus.tres) | 1500–3700 m | Uneven rounded lobes, scalloped edges, and a flatter base. |
| [Altocumulus](../../resources/clouds/altocumulus.tres) | 2700–7200 m | Shallow patches with broad, overlapping lobes and scalloped outlines. |
| [Cirrus](../../resources/clouds/cirrus.tres) | 6200–10700 m | Thin, curled streaks. |

These are stylized type preferences inspired by the [Met Office cloud classification](https://weather.metoffice.gov.uk/learn-about/weather/types-of-weather/clouds). They use sea-level height for this world's content rather than simulating meteorological cloud formation or local cloud ceilings. Altitude is sampled within the selected layer first. Eligible types are weighted toward the middle of their preferred bands, and overlapping preferences mix naturally. An altitude with no eligible type remains empty.

The shared ShaderMaterial lives in the cloud scene. Vertex colors shade the base; scene lighting and the existing horizon fog affect the surface. A blue-noise cutout fades clouds out between 8000 and 10000 meters from the camera. Default coverage includes the 9000-meter camera viewing sphere, the fade distance, the cloud half-span, and a cell of placement/boundary margin; retain those margins when adjusting coverage. Cloud meshes cast shadows within the sun's configured shadow range (currently 2500 meters from the camera). Dissolving fragments also stop casting shadows.

## Ship spawning

Each Airship authors **Spawn Layer** as Lower Cloud, Upper Cloud, or Isle, independently of combat bias. Manta uses Upper Cloud; the other catalog ships use Isle. Lower and upper choose the nearest enabled cloud-base layer on that side of the fleet marker, currently 2100 and 5200 meters. See [ship spawning](ship_spawning.md) for source selection, camera-relative isle concealment, faction sides, 500-meter Z clearance, retries, and registration.

For cloud spawns, the closest eligible cloud within the authored layer wins by 3D bounds-center distance. There is no fallback to another layer. `CloudProfile.preferred_spawn_layer(marker_altitude, side)` returns the nearest enabled layer on that side, or null when none exists. CloudSpawner records each live cloud's layer in `cloud_layers` and removes those references on unloading; randomized heights and node names do not determine membership.

CloudSpawner excludes hidden clouds, bounds too thin for the incoming hull, and every cloud within the camera's **Camera Proximity Distance** (100 meters by default). It uses the same voxel query as the dissolve, including the occupancy sample's half-voxel feather. Empty spaces only exclude the cloud when a nearby filled voxel lies within that distance. Dissolved clouds remain excluded until coverage has fully restored, and the entire cloud bounds must precede the material's distance fade. The entire conservative hull sphere plus eight meters must fit inside occupied voxels. Clouds remain non-colliding scenery.

## Camera inside a cloud

The `Dissolve` node in [clouds.tscn](../../scenes/clouds/clouds.tscn) controls each nearby cloud's per-instance coverage in the [cloud surface shader](../../shaders/clouds/cloud_surface.gdshader). Coming within **100 meters** of a filled cloud voxel dissolves its entire mesh over **0.25 seconds**; moving beyond that distance restores it over the same duration. Other clouds retain their coverage, even when they share a mesh and material. Ships, terrain, and the HUD receive no full-screen mist filter.

[CloudVolume](../../scripts/clouds/cloud_volume.gd) retains the exact occupancy grid used to build each cached mesh. `intersects_sphere` checks a camera-centered proximity sphere against nearby filled voxel boxes, including vertical distance and corners. The volume bounds reject distant queries before checking cells. Cloud gaps stay clear when their nearest filled voxels are beyond proximity; a capsule or full cloud bounding box would also cover those gaps. No physics collider is created. Trilinear occupancy sampling retains the original half-voxel fringe; setting proximity to zero restores this entry-only behavior.

CloudSpawner's `query_clouds` fills a reused array by visiting only the placement slots touched by the query radius, using cached row offsets. This includes neighboring staggered rows and slots across route-segment boundaries. Origin shifts preserve these queries. CloudSpawner owns the proximity distance so dissolution and camera exclusion from ship spawning use the same geometry and tuning.

[CloudDissolve](../../scripts/clouds/cloud_dissolve.gd) updates after camera movement and tracks only nearby clouds and those restoring their coverage. Coverage moves linearly toward zero or one, matching Dungeon Directive's `CameraProximityFade` behavior. Shader parameters are written only when coverage changes. Cloud nodes remain visible and registered while dissolved, preserving camera exclusion, spawning, and streaming contracts. A missing or inactive camera restores coverage; unloaded instances leave the active set. There is no per-cloud process callback or full-screen rendering pass.

The shader adapts Dungeon Directive's `world_noise_fade.gdshaderinc`: nearest-filtered blue noise is projected onto the dominant face axis, then fragments below the coverage threshold are discarded. Centered 8-bit thresholds make zero and full coverage exact. The texture is a byte-for-byte standalone copy of that project's `assets/textures/environment/trees/crown_fade_blue_noise.png`, stored here as [camera_fade_blue_noise.png](../../assets/textures/clouds/camera_fade_blue_noise.png), with its own generated import UID, lossless compression, and no mipmaps. Runtime references remain inside this project.

Clouds stay world-aligned, so sampling the pattern in mesh-local coordinates keeps it attached to their surfaces through every origin shift. This shader remains opaque with cutout holes, preserving depth testing, lighting, and shadows. Its far-distance fade uses the main camera in both surface and shadow passes, using Godot's [spatial shader built-ins](https://docs.godotengine.org/en/4.7/tutorials/shaders/shader_reference/spatial_shader.html).

Select `Clouds` for proximity distance, `Dissolve` for timing, and `Clouds > Material > Shader Parameters` for surface tuning:

| Parameter | Default | Effect |
| --- | --- | --- |
| Camera Proximity Distance | 100 m | Distance from filled voxels that triggers dissolution and excludes ship spawning; zero retains the original surface fringe. |
| Fade Duration | 0.25 s | Duration of a complete dissolve or restoration. |
| Camera Fade Noise Density | 0.2 samples/m | Five-meter grains; increasing density gives a finer pattern. |
| Distance Fade Start / End | 8000 / 10000 m | Far-distance cloud disappearance. |
| Emission Color | (0.12, 0.14, 0.17) | Existing subtle cloud surface fill. |

## Ownership and cost

[CloudMeshBuilder](../../scripts/clouds/cloud_mesh_builder.gd) samples unions of ellipsoidal puffs with seeded noise at a resolution derived from span divided by voxel size. It trims empty margins and resamples occupancy onto an integer grid with the requested horizontal extent, then emits cubes at their physical voxel size. It removes internal faces and merges coplanar exposed faces into rectangles. The pivot lies on a voxel boundary and the bottom of the geometry remains at local Y = 0. No generated vertices are normalized or stretched to set instance size.

Each cached shape is one ArrayMesh surface plus one shared occupancy byte array; each cloud is one MeshInstance3D with no voxel children or collider. Four types and four variants produce 16 shared meshes and volumes at startup. CloudType, CloudLayer, CloudProfile, and the surface material remain immutable during play. Larger spans or smaller voxels increase generation, geometry, and occupancy storage cost, while streaming reuses the shapes without rebuilding them. Terrain clearance reads the selected mesh's actual span. Dissolving uses per-instance shader coverage with no additional draw pass. Scene exit releases the volumes, row lookup, meshes, and dissolve tracking together.

[CloudSpawner](../../scripts/clouds/cloud_spawner.gd) owns these meshes and a bounded map of active placement slots, including slots rejected by terrain or altitude selection. Journey initializes it after terrain sampling is available and calls it with the marker position during its existing 0.25-second scenery update. Region work occurs only when the marker crosses a placement boundary. Slot dimensions derive from the largest eligible cached footprint, Cloud Gap, and the target area `Cell Size² / Density`. Row spacing rounds up to fit an integer number of rows in each 10240-meter segment; width then adjusts toward the target density while preserving clearance. Disabled or wholly ineligible layers allocate no slots.

The seed combines the profile seed, layer index, and logical slot identity, so unloading and reloading a region restores the same content without retaining route history. Placement needs no loaded-neighbor query and is independent of streaming order. Changing one layer's density or variation does not reseed the other layers; reordering the layer array changes their seeds. Segment indices stay int64 and row normalization uses small local indices; local Z coordinates are computed through RoutePosition. The authored startup field contains 1049 clouds; raising the layers allows 41 additional low-layer slots to clear terrain compared with the previous heights.

Each live cloud registers with FloatingOrigin. Rebasing translates the existing instance without rebuilding its shape or changing its random choices. Unloading unregisters and deletes the instance. Scene exit clears the mesh cache and children. Terrain clearance samples the existing sampler without requiring terrain colliders or extra detail; this is a sampled placement check, not continuous collision avoidance. Cloud placement does not reject floating islands.

## Validation

Follow [AGENTS.md](../../AGENTS.md) for isolated process APPDATA, absolute project paths, and unique external logs. Run `--headless --fixed-fps 30 --script res://scripts/tools/check_clouds.gd` after the editor import. The check covers seed reproducibility, shape variation, triangle orientation, fixed 50-meter vertex grids and single-voxel steps, additional detail in larger meshes, exact generated spans, 1000–3000 meter spawned bounds, unscaled and unrotated instances, same-layer footprint clearance across row and segment boundaries, populated upper-layer slots, all three height bands, exact Y with zero variation, independent layer density, fixed-size authoring, eligible altitude selection, sampled terrain clearance, mesh sharing, bounded streaming, revisiting, very large signed route indices, rebasing, zero density, origin registration cleanup, and teardown.

Dissolve fixtures also cover occupied and empty voxels, partial surface density, proximity before entry, exact face distance, vertical and diagonal distance, empty gaps, neighboring staggered slots across segment boundaries, entry/exit coverage, independent instances sharing one material, missing-camera restoration, rebase stability, and occupancy removal after unloading.

Spawn fixtures cover nearest-cloud ordering in 3D, strict authored layers, disabled and reordered layers, 500-meter source Z clearance, both faction sides, camera occupancy and proximity, disabling proximity, empty pockets, hidden/thin clouds, and whole-hull voxel containment. Live fixtures exercise both factions and both cloud choices independently of combat bias. See [ship spawn validation](ship_spawning.md#validation) for isle concealment and the composed picker/encounter checks.

For rendering, omit `--headless`, set `AERWYTH_CAPTURE_DIR` to an existing external directory, and append `-- --visual`. Captures include the fleet, sky, a wider layer view, and separate 3000-meter views of all four presets from the side and above. Use `-- --dissolve-visual` for the focused dissolve captures: full, half, and zero cloud coverage from 75 meters outside the surface, interior views with ships at 75, 250, and 600 meters, a half-dissolved view after rebasing, and restored exterior views. This is a functional and visual check; it is not an endgame performance measurement.
