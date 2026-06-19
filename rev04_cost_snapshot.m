function [cost, diag] = rev04_cost_snapshot(cfg, year, learning_case, learning_state)
% Component-level costs using counterfactual incremental Wright learning.

if nargin < 4 || isempty(learning_state)
    learning_state = rev04_init_learning_state(cfg);
end
case_name = upper(string(learning_case));
assert(any(case_name == ["S0","S1","S2","S3","S4"]), 'Unsupported learning case.');
theta = cfg.learning.theta_by_case.(char(case_name));

[fbp,dbp] = component_factor(cfg,"BESS","BESS_power_MW",year,case_name,theta,learning_state);
[fbe,dbe] = component_factor(cfg,"BESS","BESS_energy_MWh",year,case_name,theta,learning_state);
[fvp,dvp] = component_factor(cfg,"VRB","VRB_power_MW",year,case_name,theta,learning_state);
[fve,dve] = component_factor(cfg,"VRB","VRB_energy_MWh",year,case_name,theta,learning_state);
[fhe,dhe] = component_factor(cfg,"H2","H2_el_MW",year,case_name,theta,learning_state);
[fhs,dhs] = component_factor(cfg,"H2","H2_storage_MWh",year,case_name,theta,learning_state);
[fhg,dhg] = component_factor(cfg,"H2","H2_gen_MW",year,case_name,theta,learning_state);

cost = cfg.storage;
cost.bess.power_capex_USD_per_MW = cost.bess.power_capex_2025_USD_per_MW * fbp;
cost.bess.energy_capex_USD_per_MWh = cost.bess.energy_capex_2025_USD_per_MWh * fbe;
cost.vrb.power_capex_USD_per_MW = cost.vrb.power_capex_2025_USD_per_MW * fvp;
cost.vrb.energy_capex_USD_per_MWh = cost.vrb.energy_capex_2025_USD_per_MWh * fve;
cost.h2.electrolyzer_capex_USD_per_MW = cost.h2.electrolyzer_capex_2025_USD_per_MW * fhe;
cost.h2.storage_capex_USD_per_MWh_H2 = cost.h2.storage_capex_2025_USD_per_MWh_H2 * fhs;
cost.h2.generator_capex_USD_per_MW = cost.h2.generator_capex_2025_USD_per_MW * fhg;

cost.bess = annualize(cost.bess,cfg.storage.discount_rate);
cost.vrb = annualize(cost.vrb,cfg.storage.discount_rate);
cost.h2 = annualize_h2(cost.h2,cfg.storage.discount_rate);
diag = struct('Year',year,'Case',case_name,'BESS_power',dbp,'BESS_energy',dbe, ...
    'VRB_power',dvp,'VRB_energy',dve,'H2_el',dhe,'H2_storage',dhs,'H2_gen',dhg);
end

function [f,d] = component_factor(cfg,tech,component,y,case_name,theta,state)
spec = cfg.learning.(char(tech));
if case_name == "S0"
    fext = 1;
    theta = 0;
else
    fext = interp1(spec.external_years,spec.external_factors,y,'linear','extrap');
end
b = -log2(1-spec.LR);
q0 = cfg.learning.component_Q0.(char(component));
qext = q0 * fext^(-1/b);
qmodel = state.Qmodel.(char(component));
qtotal = qext + theta*qmodel;
f = max(cfg.learning.cost_floor_factor,(qtotal/q0)^(-b));
d = struct('LR',spec.LR,'beta',b,'Q0',q0,'Qext',qext,'Qmodel',qmodel, ...
    'theta',theta,'Qtotal',qtotal,'ExternalFactor',fext,'FinalFactor',f);
end

function s = annualize(s,r)
crf = r*(1+r)^s.life_year/((1+r)^s.life_year-1);
s.CRF = crf;
s.power_annual_USD_per_MWyr = s.power_capex_USD_per_MW*crf + s.FOM_USD_per_MWyr;
s.energy_annual_USD_per_MWhyr = s.energy_capex_USD_per_MWh*crf;
if isfield(s,'energy_FOM_USD_per_MWhyr')
    s.energy_annual_USD_per_MWhyr = s.energy_annual_USD_per_MWhyr + s.energy_FOM_USD_per_MWhyr;
end
end

function s = annualize_h2(s,r)
crf = r*(1+r)^s.life_year/((1+r)^s.life_year-1);
s.CRF = crf;
s.electrolyzer_annual_USD_per_MWyr = s.electrolyzer_capex_USD_per_MW*(crf+s.electrolyzer_FOM_frac);
s.storage_annual_USD_per_MWhyr = s.storage_capex_USD_per_MWh_H2*(crf+s.storage_FOM_frac);
s.generator_annual_USD_per_MWyr = s.generator_capex_USD_per_MW*(crf+s.generator_FOM_frac);
end
