function state = rev04_apply_replacements(state, cost, year, cfg)
% Keep wind RDU vintages active through 2050; replace storage at lifetime.

% A wind-retirement switch is retained for post-2050 extensions, but the
% current 2025-2050 planning horizon does not release or redevelop RDU shares.
keep=true(1,numel(state.wind_cohorts));
for i=1:numel(state.wind_cohorts)
    q=state.wind_cohorts(i);
    if cfg.wind.retire_within_horizon && year-q.build_year>=cfg.wind.life_year
        keep(i)=false;
    elseif year-q.project_bess_replace_year>=cfg.storage.bess.life_year
        state.wind_cohorts(i).project_bess_replace_year=year;
        state.wind_cohorts(i).project_bess_annual_cost_USDyr= ...
            q.project_bess_P_MW*cost.bess.power_annual_USD_per_MWyr+q.project_bess_E_MWh*cost.bess.energy_annual_USD_per_MWhyr;
    end
end
state.wind_cohorts=state.wind_cohorts(keep);
state=rev04_refresh_rdu_state(state);

[state.bess.cohorts,state.bess.annual_cost_USDyr]=renew_pe(state.bess.cohorts,cost.bess,year,cfg.storage.bess.life_year);
[state.vrb.cohorts,state.vrb.annual_cost_USDyr]=renew_pe(state.vrb.cohorts,cost.vrb,year,cfg.storage.vrb.life_year);
total=0;
for i=1:numel(state.h2.cohorts)
    if year-state.h2.cohorts(i).build_year>=cfg.storage.h2.life_year
        state.h2.cohorts(i).build_year=year; q=state.h2.cohorts(i);
        state.h2.cohorts(i).annual_cost_USDyr=q.el_P_MW*cost.h2.electrolyzer_annual_USD_per_MWyr+ ...
            q.gen_P_MW*cost.h2.generator_annual_USD_per_MWyr+q.store_MWh*cost.h2.storage_annual_USD_per_MWhyr;
    end
    total=total+state.h2.cohorts(i).annual_cost_USDyr;
end
state.h2.annual_cost_USDyr=total;
end

function [cohorts,total]=renew_pe(cohorts,cost,year,life)
total=0;
for i=1:numel(cohorts)
    if year-cohorts(i).build_year>=life
        cohorts(i).build_year=year;
        cohorts(i).annual_cost_USDyr=cohorts(i).P_MW*cost.power_annual_USD_per_MWyr+cohorts(i).E_MWh*cost.energy_annual_USD_per_MWhyr;
    end
    total=total+cohorts(i).annual_cost_USDyr;
end
end
