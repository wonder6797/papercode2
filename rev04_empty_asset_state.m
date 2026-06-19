function state = rev04_empty_asset_state(I)
% Empty province asset state for recursive path runs.

state.used_frac_by_site = zeros(numel(I.sites.prov_name),1);
state.fixed_profile_MW = zeros(I.T,1);
state.fixed_raw_profile_MW = zeros(I.T,1);
state.fixed_raw_MWh = 0;
state.fixed_project_curt_MWh = 0;
state.fixed_annual_cost_USDyr = 0;
state.fixed_wind_cap_MW = 0;
state.fixed_wind_annual_cost_USDyr = 0;
state.fixed_project_bess_annual_cost_USDyr = 0;
state.bess.P_MW = 0; state.bess.E_MWh = 0; state.bess.annual_cost_USDyr = 0;
state.vrb.P_MW = 0; state.vrb.E_MWh = 0; state.vrb.annual_cost_USDyr = 0;
state.h2.el_P_MW = 0; state.h2.gen_P_MW = 0; state.h2.store_MWh = 0; state.h2.annual_cost_USDyr = 0;
state.wind_cohorts = struct('build_year',{},'project_bess_replace_year',{}, ...
    'site_idx',{},'rdu_id',{},'turbine_idx',{},'package_idx',{},'share',{}, ...
    'area_dev_km2',{},'density_MW_per_km2',{},'cap_MW',{},'profile_MW',{},'raw_profile_MW',{}, ...
    'raw_MWh',{},'project_curt_MWh',{},'wind_annual_cost_USDyr',{}, ...
    'project_bess_P_MW',{},'project_bess_E_MWh',{},'project_bess_annual_cost_USDyr',{});
state.bess.cohorts = struct('build_year',{},'P_MW',{},'E_MWh',{},'annual_cost_USDyr',{});
state.vrb.cohorts = struct('build_year',{},'P_MW',{},'E_MWh',{},'annual_cost_USDyr',{});
state.h2.cohorts = struct('build_year',{},'el_P_MW',{},'gen_P_MW',{},'store_MWh',{},'annual_cost_USDyr',{});
state.addition_log = struct('year',{},'wind_MW',{},'project_bess_P_MW',{}, ...
    'system_bess_P_MW',{},'vrb_P_MW',{},'h2_store_MWh',{}, ...
    'selected_site_idx',{},'selected_fraction',{});
end
