function diagnostic = rev04_diagnose_infeasibility(I,cfg,province,year,cost,state)
% Solve a separate high-penalty slack model only for diagnosing infeasibility.

cfg.delivery.diagnostic_slack=true;
diagnostic=rev04_solve_core_lp(I,cfg,province,year,cost,state,"fixed_target",NaN);
assert(diagnostic.feasible,'Even the diagnostic slack model is infeasible.');
end
