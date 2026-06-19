# Rev04 mechanism and runtime fix 01

This directory is an independent copy based on `papercode2`. The current main
source was not overwritten.

## Product definitions

- Main: `monthly_upper_smooth`
  - annual delivery: `Etarget <= Edel <= 1.02 * Etarget`
  - monthly shaped-delivery band: +/-30%
  - year-specific hourly upper bound
  - no hourly lower bound
  - Stage 2 dispatch smoothing enabled
- Sensitivity: `monthly_hourly_band_asymmetric`
  - the hourly lower bound is only added when `enable_hourly_lower=true`
- Formal tiebreak: `light`; `full` remains available for diagnostics.
- Main project-ramp quantile: P95 after the P90/P95/P99 sensitivity run.

## Staged runner

Use `rev04_run_mechanism_runtime_fix_01(step, opts)` with one of:

- `ramp_quantile`
- `step1`
- `step2`
- `step3`

`opts.input_mat`, `opts.load_xlsx`, and `opts.output_root` can point to local
hydrated inputs and a new output directory.

## Validation completed on 2026-06-19

- Project-ramp LP unit smoke: OPTIMAL.
- Main Step 1, Guangxi/Guangdong S2 2050: 2/2 Stage 1 OPTIMAL and 2/2 Stage 2 OPTIMAL.
- Main Step 2, Guangxi/Guangdong, S0/S2, 2025-2050: 24/24 Stage 1 OPTIMAL and 24/24 Stage 2 OPTIMAL; no accepted suboptimal result.
- Hourly-corridor Step 3, Guangxi/Guangdong S2 2050: 2/2 Stage 1 OPTIMAL and 2/2 Stage 2 OPTIMAL.
- Step 2 Stage 2 cost change maximum: 0.00100000077; no 0.0015 warning.
- Step 2 shape MAE and Pdel ramp P95 improved in all 24 points.
- Step 2 warm-cache package-build time: 34.2 s for S2 versus 979.7 s for the S0 cold path.
- H2 720-hour constraints were verified from total stock at the Step 1 points.
- Hash-matched resume was verified for both Step 1 result files.

The 10% total-curtailment constraint binds at all 24 Step 2 points. This is a
model result to discuss, not a reported constraint violation.

## Key generated QA files

- `qa_project_bess_ramp_quantile_sensitivity_20260619.csv`
- `qa_main_vs_hourly_corridor_2050.csv`
- Step-run `path_summary.csv`
- Step-run `qa_monthly_delivery_band.csv`
- Step-run `qa_delivery_shape_tracking.csv`
- Step-run `qa_project_bess_ramp.csv`
- Step-run `qa_h2_role.csv`
- Step-run `qa_dispatch_tiebreak.csv`
