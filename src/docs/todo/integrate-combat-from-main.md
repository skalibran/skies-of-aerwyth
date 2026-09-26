# Combat integration prompt

Status, 2026-09-25: the measured performance subset in steps 1-4 and 6-7 is implemented and validated. Category priorities, guiding mounts, and the broader loadout planner in step 5 remain a separate gameplay pass (COMBAT-02); their experimental implementation has not been restored. Current results and the acquisition-staggering fix are recorded in [combat_performance.md](../combat_performance.md). The brief below preserves the integration rationale; completed work is checked in [todo-combat.txt](todo-combat.txt). Its rate comparisons and full validation pass are historical instructions: 30 Hz is now the accepted baseline, alternate-rate tests/overrides have been removed, and [AGENTS.md](../../../AGENTS.md) selects validation from the current diff.

The [2026-09-26 integration audit](../combat.md#integration-audit-2026-09-26) also fixed spatial-cell cleanup, target-loss staggering, and queued-deletion eligibility. Its regression and rendered 30 Hz scale checks passed; release gates remain in the combat task list.

Starting from current local `main`, integrate the useful combat experiments into clear, maintainable code. Read AGENTS.md and the GDD. The assessed main was `5b26406`; inspect later changes. Preserve the dirty working tree and untracked files before using an isolated checkout: the experiments are uncommitted. Integrate selectively.

Main already has RigidBody3D flight, live ballistic projectiles, tiered slots, anchor cohesion, a spatial avoidance grid, and cached island navigation. Preserve those systems and the authored cannon, hull, spawn, and bearing settings. The added Kestrel model remains unused.

Prior full-experiment evidence from the 220-ship desktop workload, at matched 60 Hz (the fresh selective-integration measurements are linked above):

| Early combat metric | Main | Optimized |
| --- | ---: | ---: |
| Script step median | 17.46 ms | 12.35 ms |
| Avoidance mean per tick | 7.85 ms | 4.58 ms |
| Weapon processing mean per tick | 4.55 ms | 2.78 ms |

These whole-branch results include different encounter outcomes. Shared perception/retention alone barely changed weapon cost (4.55 to 4.50 ms). Filtering before ranking reduced candidate work from 3.75 to 2.46 ms; shortlists subsequently reduced it to 1.90 ms. The separate 60/30 Hz trial saved 42–46% of combat script work per simulated second. These percentages are not additive; Steam Deck performance remains unverified.

Integrate in reviewable stages:

1. Preserve opt-in component timings. Benchmark main at 60 Hz with 70/150 ships, 5,000 health, two-second reload, sixty-second combat, and twelve-second miss volleys. Keep native physics, scripted delta, event times, and camera speed consistent. Separate script cost, overlapping engine monitors, and wall frames.

2. Calculate each avoidance pair once, adding opposite corrections and clamping afterward. Preserve the grid, predictive capsule tests, ordering, and passing side. Keep pair math inline: the per-pair helper version regressed. Keep the old formula only as an independent test oracle.

3. Journey owns the registry; a derived perception helper shares nearby-hostile queries among mounts, including muzzle offsets. ShipCombat owns pursuit policy; MountedWeapon owns firing policy. Invalidate removed ships and handle origin shifts. Perception should provide queries and validity checks, without owning tactical decisions.

4. Retain firing targets independently of pursuit; separate acquisition/reload clocks and validate every shot. Filter range and a conservative gravity/lead-aware cone before selecting a nearest-untried shortlist bounded by four total attempts. Preserve stable ties, attempt history, wraparound, and cleanup to prevent starvation. Remove the old full sort/cursor; retain exact ballistics and live swept projectiles.

5. Integrate agreed category priorities and guiding/secondary mounts separately as gameplay features. Retain equal-priority targets, switch for higher priorities, and preserve pass-by fire. Keep the short-range approach fix, authored bearings, unbanked planning, and unusable-loadout fallback. Use bounded loadout planning, named tuning constants, and clear cache invalidation; avoid a general tactical planner.

6. Retain 30 Hz with interpolation as the user's playtest setting; rendering stays uncapped. Fix legacy 1/60-delta checks, notably check_combat.gd and check_fleet_scale.gd, by selecting a matching native rate or parameterizing their schedules. Fixed render FPS alone does not align clocks. Track rapid-fire quantization and moving-body crossing coverage.

7. Validate import, avoidance equivalence, shortlist fairness/conservative rejection, target/loadout lifecycle, flight, contacts, rebasing, and the 1,760-shot cleanup workload. Compare integration at 60 Hz, then 30 Hz. Keep temporary diagnostics outside the repository and active work in src/docs/todo. Report regressions and unresolved gates. Do not push without authorization.

Reference when available: [integration measurements](../combat_performance.md) and [combat gates](todo-combat.txt). No fake-projectile, solver replacement, pooling, threading, or additional navigation-cadence experiment is justified by this comparison.
