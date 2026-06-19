function out = rev04_compile_tiebreak_monthlyband_summary()
%REV04_COMPILE_TIEBREAK_MONTHLYBAND_SUMMARY Summarize tie-break monthly-band runs.

root = fileparts(mfilename('fullpath'));
od = fullfile(root,'outputs_monthlyband_01');
sumdir = fullfile(od,'summary_tiebreak_monthlyband');
if ~isfolder(sumdir), mkdir(sumdir); end

runs = {
    0.40, 'step4_monthlyband040_formal_tiebreak_path__Guangxi_Guangdong'
    0.30, 'step3_monthlyband030_formal_tiebreak_path__Guangxi_Guangdong'
    0.20, 'step4_monthlyband020_formal_tiebreak_path__Guangxi_Guangdong'
    };

Tall = table(); Qall = table(); Hall = table(); Sall = table(); Rall = table();
for i = 1:size(runs,1)
    delta = runs{i,1};
    d = fullfile(od,runs{i,2});
    T = readtable(fullfile(d,'path_summary.csv'),'TextType','string');
    T.monthly_band_delta = repmat(delta,height(T),1);
    M = readtable(fullfile(d,'qa_monthly_delivery_band.csv'),'TextType','string');
    M.monthly_band_delta_run = repmat(delta,height(M),1);
    H = readtable(fullfile(d,'qa_h2_role.csv'),'TextType','string');
    H.monthly_band_delta = repmat(delta,height(H),1);
    S = readtable(fullfile(d,'qa_smooth_dispatch.csv'),'TextType','string');
    S.monthly_band_delta = repmat(delta,height(S),1);
    R = readtable(fullfile(d,'qa_storage_roles.csv'),'TextType','string');
    R.monthly_band_delta = repmat(delta,height(R),1);
    Tall = [Tall; T]; %#ok<AGROW>
    Qall = [Qall; M]; %#ok<AGROW>
    Hall = [Hall; H]; %#ok<AGROW>
    Sall = [Sall; S]; %#ok<AGROW>
    Rall = [Rall; R]; %#ok<AGROW>
end

comp = table();
for i = 1:height(Tall)
    tt = Tall(i,:);
    ix = Qall.province == tt.Province & Qall.scenario == tt.Scenario & ...
        Qall.year == tt.Year & abs(Qall.monthly_band_delta_run-tt.monthly_band_delta) < 1e-9;
        bind = sum(Qall.binding_low(ix) | Qall.binding_high(ix));
    sm = Sall(Sall.province == tt.Province & Sall.scenario == tt.Scenario & ...
        Sall.year == tt.Year & abs(Sall.monthly_band_delta-tt.monthly_band_delta) < 1e-9,:);
    h2 = Hall(Hall.province == tt.Province & Hall.scenario == tt.Scenario & ...
        Hall.year == tt.Year & abs(Hall.monthly_band_delta-tt.monthly_band_delta) < 1e-9,:);
    role = Rall(Rall.province == tt.Province & Rall.scenario == tt.Scenario & ...
        Rall.year == tt.Year & abs(Rall.monthly_band_delta-tt.monthly_band_delta) < 1e-9,:);
    row = table(tt.Province,tt.Scenario,tt.Year,tt.monthly_band_delta, ...
        tt.EngineeringLCOE_USD_per_MWh,tt.WindTotal_GW,tt.ProjectBESSAdd_GW, ...
        role.SystemBESS_GWh,role.VRB_GWh,role.H2_storage_GWh,tt.H2StorageAdd_GWh, ...
        tt.CurtailmentRate,sm.TrendMatchRate,bind, ...
        tt.TiebreakShareOfEngineeringCost,tt.TiebreakShareWarning, ...
        h2.H2_charge_fill_hours,h2.H2_discharge_hours, ...
        'VariableNames',{'province','scenario','year','monthly_band_delta','LCOE', ...
        'WindCap_GW','ProjectBESSAdd_GW','BESS_sys_GWh','VRB_GWh','H2_total_GWh', ...
        'H2_add_GWh','CurtailmentRate','TrendMatchRate','MonthlyBandBindingCount', ...
        'TiebreakShareOfEngineeringCost','TiebreakShareWarning', ...
        'H2ChargeFillHours','H2DischargeHours'});
    comp = [comp; row]; %#ok<AGROW>
end

writetable(comp,fullfile(sumdir,'monthly_band_sensitivity_comparison.csv'));
writetable(Tall,fullfile(sumdir,'formal_path_summary_all_deltas.csv'));
writetable(Qall,fullfile(sumdir,'formal_monthly_band_qa_all_deltas.csv'));
writetable(Hall,fullfile(sumdir,'formal_h2_qa_all_deltas.csv'));
writetable(Sall,fullfile(sumdir,'formal_dispatch_smooth_metrics_all_deltas.csv'));
writetable(Rall,fullfile(sumdir,'formal_storage_roles_all_deltas.csv'));

status_ok = all(Tall.SolverStatus == "OPTIMAL");
slack_zero = max([max(abs(Qall.slack_low_MWh)), max(abs(Qall.slack_high_MWh))]);
    low_violation = max(max(Qall.lower_bound_MWh-Qall.Edel_month_MWh,0));
    high_violation = max(max(Qall.Edel_month_MWh-Qall.upper_bound_MWh,0));
max_identity = max(abs(Tall.CostIdentityResidual));
max_tie = max(Tall.TiebreakShareOfEngineeringCost);
max_eq = max(abs(Tall.MaxEqResidual));
max_ineq = max(Tall.MaxIneqResidual);
hsig = Hall.Cap_H2_MWh_LHV > 1e-3 & Hall.year >= 2035;
if any(hsig)
    h2_min_charge = min(Hall.H2_charge_fill_hours(hsig));
    h2_min_dis = min(Hall.H2_discharge_hours(hsig));
else
    h2_min_charge = NaN;
    h2_min_dis = NaN;
end
qa = table(status_ok,slack_zero,low_violation,high_violation,max_identity, ...
    max_tie,max_eq,max_ineq,h2_min_charge,h2_min_dis, ...
    'VariableNames',{'AllFormalOptimal','MaxFormalSlack_MWh', ...
    'MaxMonthlyLowViolation_MWh','MaxMonthlyHighViolation_MWh', ...
    'MaxCostIdentityResidual_USD','MaxTiebreakShare','MaxEqResidual', ...
    'MaxIneqResidual','MinH2ChargeFillHours_significant', ...
    'MinH2DischargeHours_significant'});
writetable(qa,fullfile(sumdir,'formal_qa_summary.csv'));

out = struct('comparison',comp,'qa',qa,'output_dir',sumdir);
end
