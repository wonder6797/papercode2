function qa = rev04_validate_result(r, cfg)
% Mathematical acceptance checks for a solved core LP.

assert(r.feasible,'Result is infeasible.');
qa=struct();
qa.project_bess_ratio=r.project_bess_P_add_MW/max(r.wind_cap_add_MW,eps);
qa.system_storage_power_ratio=(r.bess.P_total_MW+r.vrb.P_total_MW)/max(r.wind_cap_add_MW,eps);
qa.cost_identity_abs=abs(r.cost.identity_residual);
qa.shape_coverage=r.shape_coverage;
qa.curtailment_rate=r.curtailment_rate;
qa.max_eq_residual=r.max_eq_residual;
qa.max_ineq_residual=r.max_ineq_residual;
qa.pass_project_bess=qa.project_bess_ratio <= max(cfg.project_bess.power_frac)+1e-7;
qa.pass_system_storage_power=qa.system_storage_power_ratio <= cfg.run.max_system_storage_power_to_wind_ratio+1e-7;
qa.pass_cost_identity=qa.cost_identity_abs <= 1e-4;
qa.pass_shape=qa.shape_coverage >= cfg.delivery.min_shape_coverage-1e-6;
qa.pass_curtail=qa.curtailment_rate <= cfg.delivery.max_curtailment_frac+1e-6;
qa.pass_residual=qa.max_eq_residual < 1e-6 && qa.max_ineq_residual < 1e-6;
qa.pass=qa.pass_project_bess && qa.pass_system_storage_power && qa.pass_cost_identity && qa.pass_shape && qa.pass_curtail && qa.pass_residual;
end
