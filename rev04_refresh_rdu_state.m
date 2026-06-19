function state = rev04_refresh_rdu_state(state)
% Rebuild active RDU aggregates from vintage cohorts.

state.used_frac_by_site(:)=0;
state.fixed_profile_MW(:)=0;
if ~isfield(state,'fixed_raw_profile_MW') || numel(state.fixed_raw_profile_MW) ~= numel(state.fixed_profile_MW)
    state.fixed_raw_profile_MW = zeros(size(state.fixed_profile_MW));
end
state.fixed_raw_profile_MW(:)=0;
state.fixed_raw_MWh=0;
state.fixed_project_curt_MWh=0;
state.fixed_wind_cap_MW=0;
state.fixed_wind_annual_cost_USDyr=0;
state.fixed_project_bess_annual_cost_USDyr=0;
for i=1:numel(state.wind_cohorts)
    q=state.wind_cohorts(i);
    state.used_frac_by_site(q.site_idx)=state.used_frac_by_site(q.site_idx)+q.share;
    state.fixed_profile_MW=state.fixed_profile_MW+q.profile_MW;
    if isfield(q,'raw_profile_MW')
        state.fixed_raw_profile_MW=state.fixed_raw_profile_MW+q.raw_profile_MW;
    end
    state.fixed_raw_MWh=state.fixed_raw_MWh+q.raw_MWh;
    state.fixed_project_curt_MWh=state.fixed_project_curt_MWh+q.project_curt_MWh;
    state.fixed_wind_cap_MW=state.fixed_wind_cap_MW+q.cap_MW;
    state.fixed_wind_annual_cost_USDyr=state.fixed_wind_annual_cost_USDyr+q.wind_annual_cost_USDyr;
    state.fixed_project_bess_annual_cost_USDyr=state.fixed_project_bess_annual_cost_USDyr+q.project_bess_annual_cost_USDyr;
end
assert(all(state.used_frac_by_site<=1+1e-6),'Active RDU development share exceeds one.');
state.used_frac_by_site=min(1,state.used_frac_by_site);
end
