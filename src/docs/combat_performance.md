# Combat performance integration

The measurements and spatial values below retain the units used when recorded. The subsequent [meter conversion](world_units.md) scales lengths, linear speeds, and linear accelerations by ten; its before/after measurements are recorded separately.

Measured 2026-09-25 against `main` at `5b26406`. The selective integration reduces early-combat mean script cost by 30.1% at matched 60 Hz. Avoidance and weapon candidate work account for most of the saving. The 30 Hz playtest setting further reduces script work per simulated second, independently of the algorithm changes. These desktop measurements do not establish Steam Deck performance.

## Implemented changes

- `ShipAvoidance` evaluates each unordered pair once, accumulating opposite corrections before clamping. Predictive capsule geometry, conservative neighbors, passing side, and accumulation order remain equivalent to the directed reference. Pair math stays inline because the earlier per-pair helper trial erased the saving.
- `CombatPerception` provides a tick-local spatial view derived from Journey's registry. Searching mounts on a ship share nearby-hostile candidates, including muzzle offsets. It owns no pursuit or firing decisions.
- `MountedWeapon` filters range and a conservative gravity/lead-expanded cone before selecting a tiny nearest-untried shortlist. Four total target attempts bound each ready step. Failed-attempt history prevents starvation when distance order changes; successful shots retain a firing target independently of pursuit. Every shot still calculates exact ballistics.
- Acquisition and reload have separate clocks. Changing pursuit preserves the staggered acquisition deadline. Journey retains coarse, opt-in component timings with named phases; the benchmark aligns native physics, script delta, and event schedules at the selected rate.

Journey remains the registry/orchestration owner, ShipCombat owns pursuit and movement intent, and MountedWeapon owns firing. Live swept projectiles, ShipFlight, ship definitions, authored bearings, and ordinary spawns retain their existing implementations/settings. Category priorities and guiding-loadout planning were not imported from the larger experiment. Their status is tracked in [combat gates](todo/todo-combat.txt).

## Method

Godot 4.7.1 stable, Jolt, Forward Plus through D3D12, Windows, Ryzen 7 9800X3D, RTX 4090, 1920 x 1080. Render rate was uncapped; profiling launches used neither `--fixed-fps` nor screenshot capture. The project baseline is 30 physics Hz with interpolation; the now-removed process-local overrides supplied the historical 60 Hz comparison.

`check_combat_scale.gd` uses 70 player ships and 150 enemies, 5,000 health, two cannons per ship, two-second reload, launch speed 100, gravity 3, range 100, and eight-second projectile lifetime. All serialized benchmark configuration values match across the three final comparison runs. The encounter lasts 60 simulated seconds: two warm-up seconds, 28 debug-off seconds, then 30 debug-on seconds. Ten scheduled casualties are replaced, two origin shifts occur, and the camera/landscape keep moving. A separate twelve-second phase fires synchronized miss volleys above the scenery, reaching 1,760 simultaneous shots before cleanup.

One fresh main run and one final integration run at each rate are reported here. They are paired scenario measurements, not repeated statistical trials. Main used the same rate-aware benchmark and split component instrumentation. Retained firing targets alter encounter outcomes, so these results cannot isolate each optimization's contribution. Debug-off and debug-on occur at different battle stages; their difference cannot isolate debug drawing cost.

Script timings cover the Journey call, excluding subsequent native body integration/contact solving. Godot's physics monitor overlaps this work and is sampled at a coarser cadence; do not add it to script time. Uncapped wall-frame distributions contain frames without a physics tick. Script CPU milliseconds per simulated second, phase elapsed time, and wall frames together describe the workload better than a single inferred FPS number.

## Matched 60 Hz result

| Script metric | Main | Integration | Reduction |
| --- | ---: | ---: | ---: |
| Early combat mean | 17.172 ms | 12.008 ms | 30.1% |
| Early combat median / p95 | 17.480 / 21.066 ms | 12.095 / 14.405 ms | 31.6% p95 |
| Early avoidance mean | 7.858 ms | 4.518 ms | 42.5% |
| Early weapons mean | 4.512 ms | 2.649 ms | 41.3% |
| Later combat mean | 13.259 ms | 9.864 ms | 25.6% |
| Later combat median / p95 | 12.750 / 16.809 ms | 9.771 / 11.566 ms | 31.2% p95 |
| Miss-volley median / p95 | 6.556 / 9.357 ms | 5.879 / 6.910 ms | 26.2% p95 |

Early decision/query work rose slightly, from 0.731 to 0.815 ms per tick, including the new spatial snapshot. Projectile processing remained small: 0.082 versus 0.086 ms. Sharing a perception query is an ownership improvement and supports cheaper candidate work; this comparison does not claim that the helper alone produced the weapon saving.

| Whole-run evidence | Main 60 Hz | Integration 60 Hz | Integration 30 Hz |
| --- | ---: | ---: | ---: |
| Early wall-frame p95 | 156.297 ms | 16.204 ms | 15.716 ms |
| Later wall-frame p95 | 97.969 ms | 16.883 ms | 16.344 ms |
| Early engine physics monitor p95 | 23.940 ms | 18.096 ms | 19.886 ms |
| Later engine physics monitor p95 | 17.595 ms | 13.969 ms | 14.854 ms |
| Early GPU p95 | 2.806 ms | 1.455 ms | 1.220 ms |
| Later GPU p95 | 3.367 ms | 3.156 ms | 2.243 ms |
| Wall time for 28 early simulated seconds | 30.953 s | 28.001 s | 28.002 s |
| Shots fired, including miss volleys | 11,449 | 12,123 | 12,164 |
| Hostile / allied impacts | 6,227 / 2,534 | 6,640 / 2,777 | 6,692 / 2,757 |

Main exceeded the 16.67 ms scripted-step budget and accumulated physics catch-up frames. The final integration's script p95 is inside that budget; native physics/render work still applies, and later wall-frame p95 remains slightly above 16.67 ms. This is not a claim of locked 60 FPS.

The first integration run exposed a scheduling regression: early script median was 10.167 ms but p95 reached 33.948 ms. Resetting each weapon's acquisition timer when pursuit changed synchronized searches across the fleet. Preserving its existing deadline reduced final early p95 to 14.405 ms. A focused regression made twelve ships acquire pursuit together and verified their searches remained spread at 30 and 60 Hz. The maintained fixture now runs once at the 30 Hz project baseline.

## 30 Hz result

| Phase | Integrated script CPU ms / simulated second, 60 Hz | At 30 Hz | Reduction | Script p95 at 30 Hz |
| --- | ---: | ---: | ---: | ---: |
| Early combat | 720.45 | 419.44 | 41.8% | 17.047 ms |
| Later combat | 591.84 | 306.72 | 48.2% | 12.293 ms |
| Miss volleys | 350.49 | 169.01 | 51.8% | 6.274 ms |

Fewer ticks reduce repeated avoidance, movement, and projectile work. Time-based acquisition/firing work is concentrated into fewer ticks, and the encounter evolves differently, so per-tick cost does not halve: early mean script time rises from 12.008 to 13.981 ms. The 30 Hz scripted-step budget is 33.33 ms. Physics rate does not cap rendering or establish hands-on movement acceptance.

## Correctness and resource observations

All three scale runs passed functional assertions, including casualties/replacements, population, damage, allied interception, rebasing, the 1,760-shot workload, and projectile cleanup. Peak combat nodes stayed between 4,835 and 4,875; all miss phases peaked at 6,942. Godot's reported static memory peaked at 119.64 / 120.94 MB in main's early/later combat, 120.22 / 121.56 MB after integration at 60 Hz, and 120.64 / 121.76 MB at 30 Hz. Miss peaks were 134.73 / 135.25 / 135.37 MB respectively. These are short-run observations, not a leak or session-lifetime certification.

Focused validation covers the directed avoidance oracle over mixed hulls, dense/coincident/head-on layouts, reordered registries and rebasing; spatial-query/full-scan agreement; exact shortlist ties and fairness; removal/exhaustion; retained-target validation; ten-shot/s firing at 30/60/120 Hz; staggered acquisition; and 900 seeded cone comparisons against the full ballistic solver. Existing ship-flight, movement/input, island-navigation, and 128-ship travel checks also passed. The combat runtime notes describe [repeatable validation](combat.md#validation).

The final headless editor import passed. A separate rendered ordinary encounter passed all fixtures and three simulated minutes of lifecycle checks at its 60 Hz reference rate: both faction caps reached 100, 189 ships were destroyed/replaced, and 27,895 shots were fired. Captures confirmed mixed-faction tint, mounted primitives, visible cannonballs, vertical spread, and the cohesive fleet after three minutes. This accelerated functional run is not an FPS benchmark or a hands-on assessment of the 30 Hz default.

The accepted hardware target remains sustained 30 FPS on Steam Deck. This high-end workstation cannot establish its CPU, GPU, thermal, or release-export margins. Current desktop results and automated checks leave that gate, broader loadout behavior, arbitrary rapid-fire quantization, adversarial moving-body crossing coverage, and hands-on tuning in [COMBAT-01 through COMBAT-04](todo/todo-combat.txt).

## Audit confirmation (2026-09-26)

After the [lifecycle audit fixes](combat.md#integration-audit-2026-09-26), the same rendered 30 Hz scale workload passed again with identical authored configuration, 12,164 shots, 6,692 damaging impacts, 2,757 allied impacts, ten replacements, and the same peak ship/projectile node counts. This is a follow-up check, not a replacement for the paired baseline above.

| Phase | Previous script mean / p95 | Audit script mean / p95 | Audit wall-frame p95 |
| --- | ---: | ---: | ---: |
| Early combat | 13.981 / 17.047 ms | 13.935 / 16.989 ms | 14.988 ms |
| Later combat | 10.224 / 12.293 ms | 10.207 / 12.455 ms | 16.085 ms |
| Miss volleys | 5.634 / 6.274 ms | 5.873 / 8.690 ms | 7.473 ms |

Combat mean cost stayed within 0.4% of the prior run. The miss phase had a higher timing tail, despite virtually unchanged median (5.702 versus 5.714 ms) and lower wall-frame p95. Its combat/query work is disabled and projectile code is unchanged; this single repeat does not establish the cause of the tail difference. All script p95 values stayed within the 33.33 ms step budget. Engine physics monitor p95 was 20.386 / 17.669 / 12.933 ms; as above, it overlaps script work. Peak reported static memory was 120.17 / 121.42 / 135.03 MB. No on-device or release-export claim follows from this desktop check.

Audit logs and the new JSON are under `C:/Users/lukas/AppData/Local/Temp/aerwyth-combat-audit-18086b2c5e0a4d6a905eda7af3be289f/`, with the rendered comparison in `profile30/`. `targeting-before.log` preserves the intentionally failing reproductions; the final targeting, flight, combat, import, and scale logs are clean.

## Reproduction and local evidence

The measurements above preserve the historical rate comparison. Current checks use the accepted 30 Hz baseline and no longer expose a rate override. Follow AGENTS.md to select profiling only when relevant, with serial launches, isolated process-local APPDATA, and unique external logs. Set `AERWYTH_PROFILE_DIR` to a different external directory for each run, then run the console executable with these arguments:

```text
--path <absolute-project-path> --script res://scripts/tools/check_combat_scale.gd --log-file <external-log-file> -- --profile
```

`combat-220.json` records the effective configuration, phase timings, counters, and resource samples at the project physics rate. Do not use fixed render FPS for performance runs. Functional fixtures also use the project rate; alternate-rate comparisons are no longer part of validation.

Local evidence for this pass is under `C:/Users/lukas/AppData/Local/Temp/aerwyth-clean-combat-13b851f876214525a2cead4cd18e302c/`: `baseline60/`, `final60/`, and `optimized30/` contain the reported JSON/logs. `optimized60/` retains the intermediate scheduling regression. Temporary captures/logs are not repository artifacts; the measurements above preserve the findings if those files are removed.

## Death-smoke optimization (2026-09-26)

The ordinary fleet view was CPU-limited by accumulated death effects. Smoke now stops and hides permanently on first ground contact. Kestrel's two authored points feed one GPU system, preserving 48 particles per point and the five-second lifetime. Systems share an immutable process material; physics-clock manual emission replaces per-render-frame material updates. Culling bounds discard expired trail positions using one-second buckets. See [smoke authoring](combat.md#death-smoke-authoring).

Compared the earlier FPS investigation with one fresh 90-second encounter after the final changes: Godot 4.7.1 development executable, Ryzen 7 9800X3D / RTX 4090, D3D12 Forward+, actual 1280 x 800 rendering, uncapped FPS, 30 Hz project physics, normal fleet camera, ten spawns per faction per second and 100 living ships per faction cap. Physics, combat, terrain, and wreck retention remained active. External scripts instantiate Journey, submit its step once per native physics frame, and collect wall-frame/render timings; launches ran serially with isolated APPDATA. No fixed render FPS was used for profiling.

| Encounter window | Before FPS | After FPS | Living, before / after | Wrecks, before / after | Active GPU smoke systems, before / after |
| --- | ---: | ---: | ---: | ---: | ---: |
| 30-40 s | 64.8 | 109.2 | 194 / 195 | 460 / 459 | 920 / 379 |
| 40-50 s | 41.8 | 95.0 | 189 / 191 | 579 / 577 | 1158 / 358 |
| 50-60 s | 38.7 | 97.4 | 200 / 191 | 647 / 648 | 1294 / 314 |
| 80-90 s | 52.2 | 117.5 | 196 / 200 | 497 / 502 | 994 / 227 |

In the 50-60 second window, mean wall-frame time fell from 25.83 to 10.26 ms (2.52 times the FPS), and p95 fell from 34.93 to 19.41 ms. Render CPU mean fell from 4.70 to 2.24 ms. The unchanged WreckController visibility callback still cost about 2.13 ms per rendered frame. These are separate evolving encounters with close wreck populations, not identical-state trials or a guaranteed minimum FPS. They do not establish Steam Deck performance.

The final headless editor import, ship-flight check, and rendered wreck check passed. The wreck check verifies first-contact shutdown, no revival on LOD reveal, shared materials, multiple emission points in one GPU system, bounded trails, native settling, rebasing, expiry, and orphan-free teardown. Captures were inspected for falling trails, smoke-free settled wrecks, both source points, and fresh smoke after hiding/revealing an airborne source.

Baseline evidence: `C:/Users/lukas/AppData/Local/Temp/aerwyth-fps-audit-qxzz0f57/current.json`. Final evidence: `C:/Users/lukas/AppData/Local/Temp/aerwyth-smoke-opt-c3o096_v/`, including `profile_batched.gd`, `batched.json`, `batched.log`, `wrecks-batched-visual.log`, `flight.log`, and captures. To repeat while the external harness is available, prepare isolated APPDATA and a unique external log as required by AGENTS.md, then run the console binary with `--path <absolute-project-path> --script <external-profile_batched.gd> --log-file <external-log>`; update the harness's output directory for each run. The prior pass with separate systems is retained as `first-pass-optimized.json`; the table reports the final batched implementation.

## Cannon smoke and 500 health (2026-09-26)

A new 90-second ordinary encounter used the same workstation, renderer, resolution, physics rate, camera, and spawn limits above, with health increased from 50 to 500 and reusable Rusty cannon muzzle smoke enabled. Each shot emits six 0.75-second puffs into one shared GPU batch, capped at 2048 particles. Native physics, terrain, projectiles, and death effects remained active.

| Encounter window | Mean FPS | Wall-frame p95 | Living ships | Wrecks | Active death-smoke systems |
| --- | ---: | ---: | ---: | ---: | ---: |
| 30-40 s | 492.3 | 9.66 ms | 200 | 1 | 1 |
| 50-60 s | 481.2 | 9.26 ms | 199 | 10 | 10 |
| 80-90 s | 386.8 | 10.38 ms | 198 | 53 | 41 |

All 15,482 shots emitted muzzle smoke through one shared batch, with no bursts dropped by its cosmetic budget. At 80-90 seconds, render CPU mean was 0.76 ms, GPU mean 0.35 ms, and Journey script mean 7.96 ms per physics tick. The much smaller wreck population accompanies higher health; this combined gameplay/presentation change does not isolate the cost of muzzle smoke or establish Steam Deck FPS.

The editor import, default combat fixtures, and focused headless/rendered cannon-smoke checks passed. Inspected captures show the plume and preservation across rebasing. The focused check also covers opt-in, successful-shot triggering, opposite muzzle directions, shared batching, cosmetic overload without lost projectiles, expiry, shooter removal, and teardown. Local evidence is under `C:/Users/lukas/AppData/Local/Temp/aerwyth-cannon-smoke-75phphyu/`, including `profile_cannon_smoke.gd`, `cannon-smoke.json`, `profile.log`, and `cannon-smoke-final.log`. The external harness uses the same invocation procedure as above.
