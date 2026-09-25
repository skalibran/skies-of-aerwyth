# Predicted projectile comparison

Implemented on `combat-predicted-projectiles`, starting from `5b26406`, on 2026-09-25. The live-projectile benchmark ran **before** implementing delayed hits. Both models use the accepted RigidBody3D ships; this changes projectile hit rules and demonstration cadence, not ship physics. Runtime contracts and Inspector controls are in [combat notes](combat.md). Active performance and tuning work remains in [COMBAT-01–04](todo/todo-combat.txt).

The delayed model reduces projectile processing, especially for long-lived misses. **It does not establish a meaningful overall speedup in dense combat or meet the 60 Hz budget.** Avoidance and ballistic weapon aiming still dominate. A second run of the retained live mode puts the small whole-battle difference within observed run variation.

## Implemented behavior

Rusty cannon's reload is now **0.2 seconds**, giving each eligible cannon up to five shots per simulation second, ten times its previous cadence. Both factions share that definition. Weapon search/cooldown comparisons tolerate floating-point residue at the cadence boundary. Range 100, speed 100, damage 5, gravity 3, lifetime eight seconds, and ordinary ship health 500 remain unchanged.

`Predicted Impact`, the default on `ProjectileController`, captures the intended target, ballistic arrival time, and expected position when firing. The visual follows the same gravity arc. At arrival, one check tests whether the snapshot point is inside the target's current oriented hull capsule plus 0.5 units of tolerance. A valid hostile hit deals damage and removes the ball. A miss, unavailable target, or changed faction leaves the visual flying until expiry, with no later hit attempts. Other ships and scenery cannot intercept it. The target reference is weak; root-local snapshots survive origin shifts. No per-shot timers or physics bodies are introduced.

`Live Sweep` preserves the previous per-tick ballistic chord queries, including allied/scenery interception. The selected mode is captured per shot, so changing the Inspector setting affects subsequent shots. Aiming returns velocity and travel time together; both modes use the same solve. Both also retain the same shared sphere mesh with one MeshInstance3D per shot. This comparison includes no burst aggregation, pooling, or GPU batching.

## Workload and measurement

Godot 4.7.1 console/editor build, Windows D3D12 Forward+, Ryzen 7 9800X3D, RTX 4090, 1920 × 1080, 60 Hz physics, uncapped rendering with V-Sync disabled. Runs were serial with isolated APPDATA. This is a development-workstation result, not a Steam Deck or release-export measurement.

`check_combat_scale.gd` uses the same 70-player/150-enemy layout, two cannons per Kestrel, seed 84317, terrain, camera motion, origin shifts, and ten scheduled deaths/replacements in each run. Benchmark-only health is 1,000,000 in **all three runs**, preventing differing hit rules from reducing the population. The ordinary spawner is disabled. The first two seconds warm up; the next 28 seconds measure debug off, followed by 30 seconds with debug on. These phases have different battle states and do not isolate the cost of debug drawing.

The final twelve-second miss phase retains the historical fixed workload: 440 untargeted shots every two seconds, launched 1,000 units above ships, reaching 1,760 concurrent balls. Movement and rendering continue, automatic combat fire stops. It measures live empty-space sweeps versus visual-only ballistic movement, **not** five shots/s per cannon or delayed target-check cost. Its projectile component excludes volley creation; total script-step time includes creation. The combat phase includes normal weapon aiming and firing at the new demonstration rate.

Journey's per-tick script timer excludes subsequent native body integration/contact solving. Projectile and weapon search/aim/fire timers are now separate. Wall-frame intervals include engine/rendering work and physics catch-up. Godot's sampled physics-time monitor is not an isolated solver timer and must not be added to script time. Uncapped rendering also produces frames without a physics step.

## Results

`Initial live` is the pre-implementation baseline; `live control` exercises the retained mode after implementation. The initial live and predicted runs include one fleet capture; the live control has no capture. Ship simulation is not a recorded replay. All runs retained 220 ships, exercised ten replacements and rebases, and cleared every projectile record and visual. Population invariants passed; performance is assessed separately.

| Metric | Initial live | Live control | Predicted |
| --- | ---: | ---: | ---: |
| Debug-off projectile mean/tick | 0.616 ms | 0.672 ms | 0.538 ms |
| Debug-off whole script median / p95 | 20.476 / 26.976 ms | 19.449 / 25.509 ms | 19.414 / 26.160 ms |
| Debug-off wall-frame median / p95 | 20.704 / 201.113 ms | 17.257 / 192.639 ms | 37.804 / 198.367 ms |
| Debug-off engine physics median / p95 | 21.220 / 37.667 ms | 19.283 / 34.559 ms | 21.988 / 36.489 ms |
| Debug-off GPU median / p95 | 1.378 / 3.453 ms | 1.480 / 3.456 ms | 1.634 / 3.386 ms |
| Debug-off peak shots | 470 | 470 | 690 |
| Debug-on projectile mean/tick | 0.904 ms | 1.043 ms | 0.627 ms |
| Debug-on whole script median / p95 | 20.011 / 26.484 ms | 19.336 / 25.149 ms | 18.876 / 24.699 ms |
| Debug-on wall-frame median / p95 | 173.434 / 197.283 ms | 166.013 / 191.838 ms | 162.895 / 189.401 ms |
| Debug-on peak shots | 609 | 642 | 775 |
| Miss projectile mean/tick | 1.946 ms | 2.216 ms | 0.938 ms |
| Miss whole script median / p95 | 6.795 / 8.829 ms | 6.894 / 9.374 ms | 5.346 / 8.835 ms |
| Miss wall-frame median / p95 | 2.075 / 10.096 ms | 2.037 / 10.041 ms | 1.988 / 8.296 ms |
| Miss peak shots | 1,760 | 1,760 | 1,760 |

Compared with the initial baseline, projectile processing fell about **13%** in the early battle, **31%** in the later battle, and **52%** in the fixed miss workload. The respective absolute savings are only 0.077, 0.276, and 1.008 ms per tick. Compared with the retained live control, projectile savings are 20%, 40%, and 58%. Whole-combat timing does not show the same dependable gain: debug-off script p95 is 26.16 ms predicted versus 25.51–26.98 ms live. All exceed 16.67 ms before native integration/rendering. The severe wall-frame stalls persist.

In the predicted debug-off battle, avoidance averaged **7.85 ms**, weapon searches/aim/fire **6.57 ms**, force submission/candidate lookup **2.10 ms**, island navigation **1.89 ms**, decisions **0.73 ms**, and projectiles **0.54 ms**. Eliminating all remaining projectile work would still leave the main CPU cost.

| Work/result | Initial live | Live control | Predicted |
| --- | ---: | ---: | ---: |
| Early battle shots fired | 27,162 | 27,212 | 27,212 |
| Early battle ray queries | 565,922 | 565,979 | 0 |
| Early battle delayed checks | 0 | 0 | 27,117 |
| Later battle ray queries | 874,746 | 931,739 | 0 |
| Later battle delayed checks | 0 | 0 | 48,448 |
| Miss-phase ray queries | 948,640 | 948,640 | 0 |
| Total shots, including warm-up/misses | 79,055 | 79,502 | 79,502 |
| Damaging hits | 54,750 | 54,236 | 76,132 |
| Allied interceptions | 21,205 | 22,190 | 0 |
| Early battle peak tracked static memory | 115.65 MiB | 115.94 MiB | 117.67 MiB |
| Early battle peak nodes | 5,236 | 5,236 | 5,456 |
| Overall peak tracked static memory | 128.51 MiB | 129.30 MiB | 129.29 MiB |
| Overall peak nodes | 6,936 | 6,942 | 6,942 |

Ignoring blockers increases damaging hits and keeps more balls visible until the predicted point or expiry. Fewer collision queries therefore do not imply fewer visual nodes or identical gameplay. The miss workload makes the collision saving clear, while the battle's extra visual lifetime offsets some benefit. Static-memory values are Godot's tracked allocation monitor, not total process or GPU memory. These finite runs do not establish long-session stability or a statistical confidence interval.

## Reproduction and evidence

Follow [AGENTS.md](../../AGENTS.md) for isolated process-local APPDATA, serial launches, and absolute external logs. Set `AERWYTH_PROFILE_DIR` to a separate existing external directory for each run, then use:

```text
--path <absolute-project-path> --script res://scripts/tools/check_combat_scale.gd --log-file <external-log-file> -- --profile
--path <absolute-project-path> --script res://scripts/tools/check_combat_scale.gd --log-file <external-log-file> -- --profile --live-projectiles
```

Do not use `--headless` or `--fixed-fps` for these performance runs. Append `--visual` and set an external `AERWYTH_CAPTURE_DIR` for the fleet image. Each run writes `combat-220.json` with effective configuration, phase samples, counts, and timing summaries.

Raw logs, JSON, captures, and `live-baseline.patch` are under the external temporary directory `aerwyth-projectile-trial-4a541aa6d8ed47ae80bdfff9c750fc37`, in `live`, `predicted`, and `live-control`. The patch preserves the instrumentation and tuning used before implementing the new model. The compared fleet captures were inspected; the same primitive fleet and environment are rendered in both modes.

The focused predicted-projectile check passed gravity/lead at 20 and 100 units/s with 30/60/120 Hz projectile steps, elevated moving targets, single delayed damage, continuing misses, rotated hull boundaries, intervening colliders being ignored, lifetime clipping, zero/large steps, target removal/death/faction changes, simultaneous lethal arrivals, shooter removal, rebasing, and cleanup. Final editor import and the existing flight check passed, including its 109 eligible broadside firing samples.

The existing rendered combat check passed its live-sweep fixtures and three-minute ordinary predicted-impact journey at 500 health. It fired 61,720 shots, registered 49,871 damaging hits, and despawned 443 ships. Peak populations were 100 players and 36 enemies: higher fire rate and unblocked damage materially change encounter balance. The controlled unobstructed refill checks still reached both 100-ship caps. Maximum anchor distance was 328.36 units and player-mean distance 153.59 units; the cohesion assertions passed. Script median/p95 was 5.304/8.268 ms, but this accelerated `--fixed-fps 60` validation has fewer combatants and is **not** a replacement for the dense uncapped benchmark. The close ship and final fleet captures were inspected for visible balls, faction tint, primitive equipment, and continued combat. Final validation logs contain no parser/runtime errors or warnings. Logs and captures are in the same external task directory under `demo`.
