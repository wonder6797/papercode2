function row = rev04_result_row(r, scenario)
% Compact path summary. Economics use Stage 1; display dispatch uses Stage 2.
s=struct();
s.Scenario=string(scenario); s.Province=r.province; s.Year=r.year;
s.Mode=string(r.mode); s.DeliveryMode=string(r.delivery_mode);
s.Contract_TWh=r.Econtract_MWh/1e6; s.Delivery_TWh=r.delivery_MWh/1e6;
s.Edel_to_Etarget=r.Edel_to_Etarget;
s.AnnualLowerBinding=logical(r.AnnualLowerBinding); s.AnnualUpperBinding=logical(r.AnnualUpperBinding);
s.MonthlyBandDelta=get_cost_param(r,'MonthlyBandDelta');
s.MonthlyBandBindingMonthsLow=r.MonthlyBandBindingMonthsLow;
s.MonthlyBandBindingMonthsHigh=r.MonthlyBandBindingMonthsHigh;
s.MonthlyBandMaxLowViolation_MWh=r.MonthlyBandMaxLowViolation_MWh;
s.MonthlyBandMaxHighViolation_MWh=r.MonthlyBandMaxHighViolation_MWh;
s.HourlyUpperDeltaUsed=get_cost_param(r,'HourlyUpperDeltaUsed');
s.HourlyUpperMultiplier=get_cost_param(r,'HourlyUpperMultiplier');
s.UpperBandBindingHours=r.UpperBandBindingHours;
s.EnableHourlyLower=logical(get_cost_param(r,'EnableHourlyLower'));
s.HourlyLowerDeltaUsed=get_cost_param(r,'HourlyLowerDeltaUsed');
s.HourlyLowerMultiplier=get_cost_param(r,'HourlyLowerMultiplier');
s.LowerBandBindingHours=r.LowerBandBindingHours;

s.WindAdd_GW=r.wind_cap_add_MW/1000; s.WindTotal_GW=r.wind_cap_total_MW/1000;
s.ProjectBESSAdd_GW=r.project_bess_P_add_MW/1000;
s.ProjectBESSAdd_GWh=r.project_bess_E_add_MWh/1000;
s.SystemBESS_GW=r.bess.P_total_MW/1000; s.SystemBESS_GWh=r.bess.E_total_MWh/1000;
s.VRB_GW=r.vrb.P_total_MW/1000; s.VRB_GWh=r.vrb.E_total_MWh/1000;
s.H2ElectrolyzerAdd_GW=r.h2.el_P_add_MW/1000;
s.H2StorageAdd_GWh=r.h2.store_add_MWh/1000;
s.H2ElectrolyzerTotal_GW=r.h2.el_P_total_MW/1000;
s.H2GeneratorTotal_GW=r.h2.gen_P_total_MW/1000;
s.H2StorageTotal_GWh=r.h2.store_total_MWh/1000;
s.H2ChargeFillHours_total=r.h2.ChargeFillHours_total;
s.H2DischargeHours_total=r.h2.DischargeHours_total;
s.H2Input_MWh=r.h2.Input_MWh; s.H2Output_MWh=r.h2.Output_MWh;
s.H2CostStock_USDyr=r.h2.CostStock_USDyr; s.H2CostNew_USDyr=r.h2.CostNew_USDyr;
s.P2HElectrolyzerAdd_GW=r.p2h.P_add_MW/1000;
s.ShapeCoverage=r.shape_coverage; s.CurtailmentRate=r.curtailment_rate;

s.EngineeringCost_USDyr=r.cost.net_total;
s.LCOE_contract_USD_per_MWh=r.LCOE_contract_USD_per_MWh;
s.LCOE_delivered_USD_per_MWh=r.LCOE_delivered_USD_per_MWh;
s.EngineeringLCOE_USD_per_MWh=r.engineering_LCOE_USD_per_MWh;
s.EngineeringLCOEDenominator=string(r.EngineeringLCOEDenominator);
s.CostWind_USDyr=r.cost.wind; s.CostProjectBESS_USDyr=r.cost.project_bess;
s.CostSystemBESS_USDyr=r.cost.system_bess; s.CostVRB_USDyr=r.cost.vrb;
s.CostH2_USDyr=r.cost.h2; s.CostOperation_USDyr=r.cost.operation;
s.P2HRevenue_USDyr=r.cost.p2h_revenue;
s.CostIdentityResidual=r.cost.identity_residual;

s.TiebreakMode=string(r.dispatch_tiebreak.mode);
s.C_tiebreak_USD=r.dispatch_tiebreak.C_tiebreak_USD;
s.C_tiebreak_share_of_engineering_cost=r.dispatch_tiebreak.share_of_engineering_cost;
s.TiebreakShareWarning=logical(r.dispatch_tiebreak.share_warning);
s.Stage1Cost_USD=r.smooth.stage1_cost_USD; s.Stage2Cost_USD=r.smooth.stage2_cost_USD;
s.Stage2CostChangeFrac=r.smooth.stage2_cost_change_frac;
s.Stage2CostWarning=logical(r.smooth.stage2_cost_warning);
s.Stage2Status=string(r.smooth.stage2_status); s.Stage2Used=logical(r.smooth.stage2_used);
s.Stage1_MAE_Pdel_Pshape_MW=r.smooth.stage1.MAE_Pdel_Pshape_MW;
s.Stage2_MAE_Pdel_Pshape_MW=r.smooth.stage2.MAE_Pdel_Pshape_MW;
s.Stage1_RMSE_Pdel_Pshape_MW=r.smooth.stage1.RMSE_Pdel_Pshape_MW;
s.Stage2_RMSE_Pdel_Pshape_MW=r.smooth.stage2.RMSE_Pdel_Pshape_MW;
s.Stage1_TrendMatchRate=r.smooth.stage1.TrendMatchRate;
s.Stage2_TrendMatchRate=r.smooth.stage2.TrendMatchRate;
s.Stage1_Corr_dPdel_dPshape=r.smooth.stage1.Corr_dPdel_dPshape;
s.Stage2_Corr_dPdel_dPshape=r.smooth.stage2.Corr_dPdel_dPshape;

s.SolverStatus=string(r.solver.status); s.SolverRuntime_s=r.solver_runtime_s;
s.SolverAttemptCount=r.solver_attempt_count; s.SolverMethodUsed=r.solver_method_used;
s.SolverCrossoverUsed=r.solver_crossover_used;
s.LP_nvar=r.performance.LP_nvar; s.LP_neq=r.performance.LP_neq;
s.LP_nineq=r.performance.LP_nineq; s.LP_nnz=r.performance.LP_nnz;
s.LP_assembly_time_s=r.performance.LP_assembly_time_s;
s.LP_solve_time_s=r.performance.LP_solve_time_s;
s.PackageBuildTime_s=r.performance.PackageBuildTime_s;
s.MaxEqualityResidual=r.max_eq_residual;
s.MaxInequalityViolation=r.max_ineq_residual;
s.AcceptedSuboptimalFlag=logical(r.accepted_suboptimal_flag);
s.RampCacheHit=r.performance.RampCacheHit; s.RampCacheMiss=r.performance.RampCacheMiss;
s.RampCacheNewFiles=r.performance.RampCacheNewFiles;
s.RampCacheReusedFiles=r.performance.RampCacheReusedFiles;
s.ProjectRampProfileCalls=r.performance.ProjectRampProfileCalls;
s.ProjectRampProfileTime_s=r.performance.ProjectRampProfileTime_s;
s.VRB_E_CAPEX_USD_per_MWh=get_cost_param(r,'VRB_E_CAPEX_USD_per_MWh');
row=struct2table(s);
end

function v=get_cost_param(r,name)
v=NaN;
if isfield(r,'cost_params') && isfield(r.cost_params,name), v=r.cost_params.(name); end
end
