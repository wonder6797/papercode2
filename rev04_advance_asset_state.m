function [state, add] = rev04_advance_asset_state(state, result, cost, year)
% Add x_new(u,tau,b,y) as physical area-development-share vintage cohorts.

assert(result.feasible,'Cannot advance an infeasible result.');
x=result.x; P=result.packages; take=find(x>1e-7);
x=cap_new_share_to_remaining_area(x,P,state,take);
for jj=reshape(take,1,[])
    share=x(jj);
    state.wind_cohorts(end+1)=struct( ...
        'build_year',year,'project_bess_replace_year',year, ...
        'site_idx',P.site_idx(jj),'rdu_id',P.rdu_id(jj), ...
        'turbine_idx',P.turbine_idx(jj),'package_idx',P.package_idx(jj),'share',share, ...
        'area_dev_km2',share*P.area_dev_km2(jj), ...
        'density_MW_per_km2',P.density_MW_per_km2(jj), ...
        'cap_MW',share*P.cap_MW(jj),'profile_MW',share*double(P.profile_MW(:,jj)), ...
        'raw_profile_MW',share*double(P.raw_profile_MW(:,jj)), ...
        'raw_MWh',share*P.raw_MWh(jj),'project_curt_MWh',share*P.project_curt_MWh(jj), ...
        'wind_annual_cost_USDyr',share*P.wind_annual_cost_USDyr(jj), ...
        'project_bess_P_MW',share*P.project_bess_P_MW(jj), ...
        'project_bess_E_MWh',share*P.project_bess_E_MWh(jj), ...
        'project_bess_annual_cost_USDyr',share*P.project_bess_annual_cost_USDyr(jj));
end

state=rev04_refresh_rdu_state(state);

pP=P.project_bess_P_MW'*x; pE=P.project_bess_E_MWh'*x;
state.bess.P_MW=state.bess.P_MW+result.bess.P_add_MW;
state.bess.E_MWh=state.bess.E_MWh+result.bess.E_add_MWh;
state.bess.annual_cost_USDyr=state.bess.annual_cost_USDyr+ ...
    result.bess.P_add_MW*cost.bess.power_annual_USD_per_MWyr+result.bess.E_add_MWh*cost.bess.energy_annual_USD_per_MWhyr;
if result.bess.E_add_MWh>1e-7
    state.bess.cohorts(end+1)=struct('build_year',year,'P_MW',result.bess.P_add_MW,'E_MWh',result.bess.E_add_MWh, ...
        'annual_cost_USDyr',result.bess.P_add_MW*cost.bess.power_annual_USD_per_MWyr+result.bess.E_add_MWh*cost.bess.energy_annual_USD_per_MWhyr);
end

state.vrb.P_MW=state.vrb.P_MW+result.vrb.P_add_MW;
state.vrb.E_MWh=state.vrb.E_MWh+result.vrb.E_add_MWh;
state.vrb.annual_cost_USDyr=state.vrb.annual_cost_USDyr+ ...
    result.vrb.P_add_MW*cost.vrb.power_annual_USD_per_MWyr+result.vrb.E_add_MWh*cost.vrb.energy_annual_USD_per_MWhyr;
if result.vrb.E_add_MWh>1e-7
    state.vrb.cohorts(end+1)=struct('build_year',year,'P_MW',result.vrb.P_add_MW,'E_MWh',result.vrb.E_add_MWh, ...
        'annual_cost_USDyr',result.vrb.P_add_MW*cost.vrb.power_annual_USD_per_MWyr+result.vrb.E_add_MWh*cost.vrb.energy_annual_USD_per_MWhyr);
end

state.h2.el_P_MW=state.h2.el_P_MW+result.h2.el_P_add_MW;
state.h2.gen_P_MW=state.h2.gen_P_MW+result.h2.gen_P_add_MW;
state.h2.store_MWh=state.h2.store_MWh+result.h2.store_add_MWh;
state.h2.annual_cost_USDyr=state.h2.annual_cost_USDyr+ ...
    result.h2.el_P_add_MW*cost.h2.electrolyzer_annual_USD_per_MWyr+ ...
    result.h2.gen_P_add_MW*cost.h2.generator_annual_USD_per_MWyr+ ...
    result.h2.store_add_MWh*cost.h2.storage_annual_USD_per_MWhyr;
if result.h2.store_add_MWh>1e-7
    state.h2.cohorts(end+1)=struct('build_year',year,'el_P_MW',result.h2.el_P_add_MW, ...
        'gen_P_MW',result.h2.gen_P_add_MW,'store_MWh',result.h2.store_add_MWh, ...
        'annual_cost_USDyr',result.h2.el_P_add_MW*cost.h2.electrolyzer_annual_USD_per_MWyr+ ...
        result.h2.gen_P_add_MW*cost.h2.generator_annual_USD_per_MWyr+result.h2.store_add_MWh*cost.h2.storage_annual_USD_per_MWhyr);
end

add=struct('BESS_power_MW',pP+result.bess.P_add_MW,'BESS_energy_MWh',pE+result.bess.E_add_MWh, ...
    'VRB_power_MW',result.vrb.P_add_MW,'VRB_energy_MWh',result.vrb.E_add_MWh, ...
    'H2_el_MW',result.h2.el_P_add_MW,'H2_storage_MWh',result.h2.store_add_MWh,'H2_gen_MW',result.h2.gen_P_add_MW);
state.addition_log(end+1)=struct('year',year,'wind_MW',result.wind_cap_add_MW, ...
    'project_bess_P_MW',pP,'system_bess_P_MW',result.bess.P_add_MW,'vrb_P_MW',result.vrb.P_add_MW, ...
    'h2_store_MWh',result.h2.store_add_MWh,'selected_site_idx',P.site_idx(take),'selected_fraction',x(take));
end

function x = cap_new_share_to_remaining_area(x,P,state,take)
% Gurobi may return tiny multi-vintage area-share excesses near binding RDU
% constraints. Store physically valid cohorts by scaling only the current
% year's selected shares on the affected RDU.
if isempty(take)
    return
end
for s = reshape(unique(P.site_idx(take)),1,[])
    ix = take(P.site_idx(take)==s);
    cur = sum(x(ix));
    old = 0;
    for kk = 1:numel(state.wind_cohorts)
        if state.wind_cohorts(kk).site_idx == s
            old = old + state.wind_cohorts(kk).share;
        end
    end
    remaining = max(0, 1-old);
    if cur > remaining
        x(ix) = x(ix) * (remaining / max(cur, eps));
    end
end
end
