# Rev04 Input Data

This repository stores the input data needed to run the current Rev04 code in
Git LFS. Generated solver outputs, cache files, figures, logs, and QA tables are
not versioned.

## Current Rev04 main-path inputs

- `01_core_code/inner_inputs_2016_v3.mat`
  - Required by `rev04_build_inputs.m` through `cfg.input_mat`.
  - Contains the assembled offshore wind RDU, turbine, hourly profile, and cost
    input structure used by Rev04.
- `Data output.xlsx`
  - Required by `rev04_prepare_hourly_load.m` through `cfg.load_xlsx`.
  - Contains the provincial hourly load data used to construct shaped-delivery
    targets.

With these two files present, `rev04_default_config.m` resolves the current
main-path inputs without local path edits.

## Legacy/reference reconstruction inputs

- `08_legacy_reference/prep_inner_inputs_2016_v3_0511.m`
  - Legacy/reference script that assembles `inner_inputs_2016_v3.mat` from the
    upstream wind-resource base, province QA files, and legacy load inputs.
- `08_legacy_reference/build_wind_storage_localmodel_v2.m`
  - Upstream base-data builder used to generate `wind_CF_storage_base_v2.mat`
    from ArcGIS-derived site tables and real-year netCDF wind profiles.
- `08_legacy_reference/wind_CF_storage_base_v2.mat`
  - Upstream static wind-resource and cost base used by the legacy input
    preparation script.
- `08_legacy_reference/level1_inputs.mat`
  - Legacy/reference support input retained with the old scripts.
- `08_legacy_reference/province_assignment_QA/`
  - Province assignment QA tables and map used by the legacy input-preparation
    workflow.
- `data/raw_arcgis_025deg/derived/`
  - ArcGIS-derived masked offshore wind site table and real-year netCDF wind
    profile files used by upstream base-data reconstruction scripts.
- `data/legacy_load_preprocessed/`
  - Small legacy load preprocessing workbooks referenced by the older
    input-preparation workflow.

## Git LFS

Large binary files are tracked with Git LFS:

- `*.mat`
- `*.xlsx`
- `*.nc`

After cloning, run:

```bash
git lfs pull
```

before running MATLAB scripts that load these files.
