# rev04_mechanism_runtime_fix_01

Independent Rev04 mechanism/runtime revision based on `papercode2`. See
`VALIDATION_MECHANISM_RUNTIME_FIX_01.md` for product definitions, staged runs,
and validation results.

This repository contains the MATLAB code scripts for the Rev04 offshore-wind shaped-delivery and storage-learning model.

Only source scripts are synchronized here. Large input datasets, `.mat` files, solver outputs, figures, CSV result folders, and cache files are intentionally excluded.

## 01_core_code

核心代码。优先检查当前主模型逻辑、LP 约束、候选包构建、资产递推和主实验运行器。

- `rev04_default_config.m`
- `rev04_run_monthlyband_experiment.m`
- `rev04_solve_core_lp.m`
- `rev04_build_site_packages.m`
- `rev04_advance_asset_state.m`
- `rev04_refresh_rdu_state.m`

## 02_inputs_initialization

输入与初始化。负责读取/构建输入、小时负荷、初始化资产状态和路径 RDU 输出表。

- `rev04_initialize.m`
- `rev04_build_inputs.m`
- `rev04_prepare_hourly_load.m`
- `rev04_empty_asset_state.m`
- `rev04_path_rdu_table.m`

## 03_cost_learning

成本与学习。负责年度成本快照、学习状态初始化/更新和资产替换。

- `rev04_cost_snapshot.m`
- `rev04_init_learning_state.m`
- `rev04_update_learning_state.m`
- `rev04_apply_replacements.m`

## 04_project_bess_ramp_service

项目侧 BESS / ramp service。负责原始风电爬坡审计、项目侧 ramp limit 和单位容量平滑 profile 预处理。

- `rev04_audit_raw_wind_ramp.m`
- `rev04_project_ramp_limit.m`
- `rev04_smooth_project_profile_ramp_lp.m`
- `rev04_smooth_project_profile.m`

## 05_results_qa

结果表与 QA。负责结果行、诊断、校验和里程碑分析汇总。

- `rev04_result_row.m`
- `rev04_validate_result.m`
- `rev04_diagnose_infeasibility.m`
- `rev04_analyze_milestone_abc.m`
- `rev04_compile_tiebreak_monthlyband_summary.m`

## 06_other_runners

其他运行器。用于旧里程碑、ramp calibration、常规 path runner 等。

- `rev04_main.m`
- `rev04_run_path.m`
- `rev04_run_rampcalib_experiment.m`
- `rev04_run_milestone_a.m`
- `rev04_run_milestone_b.m`

## 07_economic_frontier_milestone_d

经济边界 / Milestone D 相关。用于 frontier 阈值模型、分批求解和省份结果合并。

- `rev04_run_frontier.m`
- `rev04_run_frontier_batch.m`
- `rev04_run_frontier_province_batch.m`
- `rev04_merge_frontier_provinces.m`

## 08_legacy_reference

旧版/参考脚本，不是当前主路径优先检查对象。保留用于追溯 Rev01-Rev03 或旧模型逻辑。

- `main_v1.m`
- `run_coastal_2025_2050_ramp_learning_lp_v2_0512.m`
- `build_wind_storage_localmodel_v2.m`
- `prep_inner_inputs_2016_v3_0511.m`
- `CF_hourly.m`
- `StorageLearningUtils.m`
- `plot_storage_learning_results_rev02.m`

## Current Working Source

The synchronized source came from:

```text
D:\CodexWork\ThesisCode_Review\src_rev04_priority_core_20260617_monthlyband_01
```

## Notes

- The code expects local input files such as `inner_inputs_2016_v3.mat` and `Data output.xlsx`; these are not stored in this repository.
- Output folders such as `outputs_monthlyband_01/` are excluded.
- Project-side ramp profile caches are excluded.
