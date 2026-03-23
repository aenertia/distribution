# ADR: schedutil boost frequency selection fix

## Status: UNDER REVIEW (PR #2422 closed, options being weighed)

## Context

When cpufreq boost is toggled at runtime with schedutil as governor,
`capacity_freq_ref` remains stale at the non-boost maximum frequency.
This causes schedutil's `get_next_freq()` to never request boost OPPs
because `map_util_freq()` caps the target at `capacity_freq_ref`.

Result: schedutil with boost=1 never reaches boost frequencies.
Benchmarked on RK3566: 21% compress MIPS regression vs performance governor.

## Root Cause

Commit `dd016f379ebc` ("cpufreq: Introduce a more generic way to set
default per-policy boost flag") changed ordering so `policy->boost_enabled`
is set AFTER `cpufreq_frequency_table_cpuinfo()`, causing
`policy->cpuinfo.max_freq` (and thus `capacity_freq_ref`) to be set to
the highest non-boost OPP when the `CPUFREQ_CREATE_POLICY` notifier fires.

At runtime, `cpufreq_boost_set_sw()` updates `policy->max` but never
updates `capacity_freq_ref`.

## LKML References

### Primary RFC (Dietmar Eggemann, ARM)
- RFC patch: https://lore.kernel.org/all/20250626093018.106265-1-dietmar.eggemann@arm.com/T/
- Follow-up with regression detail: https://lore.kernel.org/all/e89b250a-7e9b-45fa-9e81-fc071487078b@arm.com/

### Discussion
- Vincent Guittot NAK (PELT invariance): https://lore.kernel.org/all/CAKfTPtAwy1ZFQ=-t7SbbDuHj6ZJPtB3pJS6fZxt=1robLwvXjg@mail.gmail.com/
- Christian Loehle response (smallest evil): https://lore.kernel.org/all/16b728e6-6fb9-48eb-8160-73c4ace229d2@arm.com/
- Vincent Guittot final reply: https://lore.kernel.org/all/CAKfTPtDXRKt8zOe7XTG8L037myS4DBr+4FXfLEeF2Ai42=s+8g@mail.gmail.com/

### Related patches
- Christian Loehle init fix: https://lore.kernel.org/all/3cc5b83b-f81c-4bd7-b7ff-4d02db4e25d8@arm.com/T/
- arch_scale_freq_ref introduction (v7, Vincent Guittot, merged for 6.8): https://lore.kernel.org/all/20231211104855.558096-2-vincent.guittot@linaro.org/
- capacity_freq_ref init to 0 (merged 6.15): https://patchwork.ozlabs.org/project/ubuntu-kernel/patch/20250701163531.23717-2-tim.whisonant@canonical.com/

## PELT Analysis

### What is PELT invariance?

PELT (Per-Entity Load Tracking) scales CPU time by a DVFS ratio to make
utilization comparable across frequencies:

```
scale_freq = arch_scale_freq_capacity(cpu) = cur_freq / capacity_freq_ref * 1024
```

This scales the virtual clock (`rq->clock_pelt`) in `update_rq_clock_pelt()`.
EWMA accumulates weighted sums with half-life = 32ms (y^32 = 0.5).

### Why runtime capacity_freq_ref changes "break" invariance

When `capacity_freq_ref` changes, accumulated EWMA history was computed with
the old scaling factor. The sum becomes a mix of two scales.

### The break is TRANSIENT and self-correcting

EWMA exponential decay means old samples contribute:
- 32ms:  50% old-scale
- 64ms:  25% old-scale
- 96ms:  12.5% old-scale
- 160ms: <3.1% old-scale

For boost ratio 1800→1992MHz (10.7%), worst-case util_avg error: ~10%
Decays to <1% within ~100ms (~6 frames at 60fps).

### Why this matters less for gaming handhelds

- RK3566: homogeneous quad-core A55 — no asymmetric load balancing
- RK3588: big.LITTLE but boost affects all clusters
- Boost toggles are infrequent (once at game launch)
- 160ms transient is imperceptible in gaming workloads
- No EAS energy model sensitivity (thermal framework handles power)

### PELT rescaling (theoretically possible, practically infeasible)

Could rescale `struct sched_avg` fields (`load_sum`, `runnable_sum`,
`util_sum`) by `old_ref / new_ref` at toggle time. Mathematically sound
but must walk ALL tasks including sleeping/blocked ones not on any runqueue.
No kernel precedent — even CPU hotplug doesn't rescale PELT.

## Proposed Solutions

### Option A: Update capacity_freq_ref on boost toggle (Dietmar's approach)

Patch: update `capacity_freq_ref` and frequency-invariance scale in
`policy_set_boost()` after successful boost toggle.

- PELT transient: ~10% for 160ms (quantified, acceptable)
- Single kernel patch, already written and benchmarked
- Matches upstream RFC direction
- Vincent Guittot NAK'd — not mergeable upstream without consensus

### Option B: Remove turbo-mode flags from DT OPPs

Make boost OPPs regular entries. `capacity_freq_ref` set to true max at
boot. Schedutil sees all OPPs as normal.

- Zero kernel code changes
- PELT invariance fully preserved
- Loses runtime boost toggle capability
- Already used on RG-DS (OPPs have no turbo flags)

### Option C: uclamp-based boost (supplementary)

With CONFIG_UCLAMP_TASK=y, `uclamp.min=1024` pushes schedutil via the
1.25x headroom multiplier:

```
freq = 1.25 * 1024 * capacity_freq_ref / 1024 = 1.25 * capacity_freq_ref
cpufreq_driver_resolve_freq → clamps to policy->max (includes boost)
```

Works at high utilization but NOT at moderate util (60-80%) where schedutil
still won't reach boost. Supplementary, not standalone fix.

### Option D: Capacity > 1024 (Vincent's preferred, long-term)

Allow `capacity_freq_ref` to stay at non-boost max. When running at boost
freq, effective capacity exceeds 1024. Requires auditing all scheduler code
that assumes capacity <= 1024:
- schedutil get_next_freq()
- sched_ext SCX_CPUPERF_ONE
- uclamp bitfield sizing
- EAS energy model calibration
- overutilized thresholds

Very invasive, not ready upstream.

## Decision

For ROCKNIX: **Option A** (Dietmar's patch) with clear documentation that
the PELT transient is quantified and acceptable for our use case. If
rejected upstream, **Option B** (DT approach) as fallback.

Options A and B are complementary with Option C (uclamp tiers from PR #2459).

## Benchmarks (RK3566, 7z LZMA, kernel 6.18.13)

### Without fix (schedutil never reaches 1992MHz):
| Governor | Boost | cur_freq | Compress MIPS | Decompress MIPS |
|----------|-------|----------|---------------|-----------------|
| performance | 1 | 1992000 | 1034 | 1996 |
| schedutil | 1 | 1416000 | 1015 | 1943 |

### With fix (schedutil reaches 1992MHz):
| Governor | Boost | cur_freq | Compress MIPS | Decompress MIPS |
|----------|-------|----------|---------------|-----------------|
| schedutil | 1 | 1992000 | 1231 | 2307 |

Compress: +21%, Decompress: +19% improvement.
