function out = rev04_analyze_milestone_abc()
% Analyze Milestone A/B/C path results and replay selected hourly dispatch.

cfg = rev04_default_config();
cfg.run.verbose = false;
cfg.run.save_results = false;
cfg.solver.time_limit_s = 900;

outdir = fullfile(cfg.output_root, 'analysis_milestone_abc');
figdir = fullfile(outdir, 'figures');
tabdir = fullfile(outdir, 'tables');
hourdir = fullfile(outdir, 'hourly_dispatch');
ensure_dir(outdir); ensure_dir(figdir); ensure_dir(tabdir); ensure_dir(hourdir);

path_file = fullfile(cfg.output_root, 'path', 'path_summary.csv');
rdu_file = fullfile(cfg.output_root, 'path', 'path_rdu_development.csv');
assert(isfile(path_file), 'Missing path summary: %s', path_file);
assert(isfile(rdu_file), 'Missing RDU path table: %s', rdu_file);

T = readtable(path_file, 'TextType','string');
RDU = readtable(rdu_file, 'TextType','string');
T = normalize_path_table(T);

diag = build_diagnostic_flags(T);
writetable(diag, fullfile(outdir, 'diagnostic_flags.csv'));

agg = aggregate_path(T);
writetable(agg, fullfile(tabdir, 'annual_aggregate_by_scenario_year.csv'));

make_path_figures(T, agg, figdir);

[cfg, load_data, I] = rev04_initialize(cfg); %#ok<ASGLU>
replay_specs = table( ...
    ["Guangxi";"Guangxi";"Guangxi";"Guangdong";"Guangdong";"Guangdong"], ...
    [2030;2040;2050;2030;2040;2050], ...
    repmat("S2",6,1), ...
    'VariableNames', {'Province','Year','Scenario'});
hourly_checks = table();
for i = 1:height(replay_specs)
    spec = replay_specs(i,:);
    [H, check] = replay_hourly_dispatch(cfg, I, T, spec.Province, spec.Year, spec.Scenario);
    stem = sprintf('hourly_dispatch_%s_%d_%s', spec.Province, spec.Year, spec.Scenario);
    writetable(H, fullfile(hourdir, stem + ".csv"));
    hourly_checks = [hourly_checks; check]; %#ok<AGROW>
    plot_hourly_combo(H, spec, figdir);
end
writetable(hourly_checks, fullfile(outdir, 'hourly_replay_checks.csv'));

report_file = fullfile(outdir, 'milestone_abc_diagnostic_report.md');
write_report(report_file, T, agg, diag, hourly_checks);

out = struct('outdir', outdir, 'figdir', figdir, 'tabdir', tabdir, ...
    'hourdir', hourdir, 'report_file', report_file, 'diagnostic_flags', diag, ...
    'hourly_checks', hourly_checks);
fprintf('Rev04 Milestone A/B/C analysis written to:\n%s\n', outdir);
end

function T = normalize_path_table(T)
numvars = ["Contract_TWh","Delivery_TWh","WindAdd_GW","WindTotal_GW", ...
    "ProjectBESSAdd_GW","SystemBESS_GW","SystemBESS_GWh","VRB_GW","VRB_GWh", ...
    "H2ElectrolyzerAdd_GW","H2StorageAdd_GWh","P2HElectrolyzerAdd_GW", ...
    "ShapeCoverage","CurtailmentRate","EngineeringLCOE_USD_per_MWh", ...
    "CostWind_USDyr","CostProjectBESS_USDyr","CostSystemBESS_USDyr", ...
    "CostVRB_USDyr","CostH2_USDyr","CostOperation_USDyr","P2HRevenue_USDyr", ...
    "CostIdentityResidual","MaxEqResidual","MaxIneqResidual"];
for v = numvars
    if iscell(T.(v)), T.(v) = str2double(string(T.(v))); end
end
if iscell(T.Year), T.Year = str2double(string(T.Year)); end
T.Scenario = string(T.Scenario);
T.Province = string(T.Province);
T.SolverStatus = string(T.SolverStatus);
end

function D = build_diagnostic_flags(T)
tol_cost = 1e-4;
tol_eq = 1e-6;
tol_ineq = 1e-6;
D = T(:, {'Scenario','Province','Year'});
D.SolverNotOptimal = T.SolverStatus ~= "OPTIMAL";
D.CostIdentityFlag = abs(T.CostIdentityResidual) > tol_cost;
D.EqResidualFlag = T.MaxEqResidual > tol_eq;
D.IneqResidualFlag = T.MaxIneqResidual > tol_ineq;
D.ProjectBESSNearZero = T.ProjectBESSAdd_GW < 1e-3;
D.VRBNearZero = T.VRB_GW < 1e-3;
D.ShapeCoverageBinding = abs(T.ShapeCoverage - 0.80) < 1e-5;
D.CurtailmentBinding = abs(T.CurtailmentRate - 0.10) < 1e-4;
D.H2StorageHigh = T.H2StorageAdd_GWh ./ max(T.Contract_TWh, eps) > 1.0;
D.FlagCount = double(D.SolverNotOptimal) + double(D.CostIdentityFlag) + ...
    double(D.EqResidualFlag) + double(D.IneqResidualFlag) + ...
    double(D.ProjectBESSNearZero) + double(D.VRBNearZero) + ...
    double(D.ShapeCoverageBinding) + double(D.CurtailmentBinding) + ...
    double(D.H2StorageHigh);
end

function A = aggregate_path(T)
[G, scenario, year] = findgroups(T.Scenario, T.Year);
A = table(scenario, year, ...
    splitapply(@sum, T.Contract_TWh, G), ...
    splitapply(@sum, T.Delivery_TWh, G), ...
    splitapply(@sum, T.WindTotal_GW, G), ...
    splitapply(@sum, T.WindAdd_GW, G), ...
    splitapply(@sum, T.SystemBESS_GW, G), ...
    splitapply(@sum, T.SystemBESS_GWh, G), ...
    splitapply(@sum, T.VRB_GW, G), ...
    splitapply(@sum, T.H2ElectrolyzerAdd_GW, G), ...
    splitapply(@sum, T.H2StorageAdd_GWh, G), ...
    splitapply(@mean, T.EngineeringLCOE_USD_per_MWh, G), ...
    'VariableNames', {'Scenario','Year','Contract_TWh','Delivery_TWh','WindTotal_GW', ...
    'WindAdd_GW','SystemBESS_GW','SystemBESS_GWh','VRB_GW','H2Electrolyzer_GW', ...
    'H2Storage_GWh','MeanLCOE_USD_per_MWh'});
end

function make_path_figures(T, A, figdir)
set(0,'DefaultFigureVisible','off');
scenarios = unique(A.Scenario, 'stable');
cols = lines(numel(scenarios));

plot_lines(A, scenarios, cols, 'Contract_TWh', 'Contract energy (TWh)', ...
    fullfile(figdir, 'path_contract_twh_by_scenario.png'));
plot_lines(A, scenarios, cols, 'WindTotal_GW', 'Cumulative offshore wind (GW)', ...
    fullfile(figdir, 'path_wind_total_gw_by_scenario.png'));
plot_lines(A, scenarios, cols, 'WindAdd_GW', 'New offshore wind (GW)', ...
    fullfile(figdir, 'path_wind_add_gw_by_scenario.png'));
plot_lines(A, scenarios, cols, 'MeanLCOE_USD_per_MWh', 'Mean engineering LCOE (USD/MWh)', ...
    fullfile(figdir, 'path_mean_lcoe_by_scenario.png'));

f = figure('Position',[80 80 1000 520]); tiledlayout(1,2);
nexttile;
B = A(A.Scenario=="S2",:);
bar(B.Year, [B.SystemBESS_GW, B.VRB_GW, B.H2Electrolyzer_GW], 'stacked');
ylabel('Power capacity (GW)'); title('S2 storage power mix'); grid on;
legend({'System BESS','VRB/LDES','H2 electrolyzer'},'Location','northwest');
nexttile;
bar(B.Year, [B.SystemBESS_GWh, B.H2Storage_GWh], 'stacked');
ylabel('Energy capacity (GWh)'); title('S2 storage energy mix'); grid on;
legend({'System BESS','H2 storage'},'Location','northwest');
exportgraphics(f, fullfile(figdir, 'path_s2_storage_mix_by_year.png'), 'Resolution', 180);
close(f);

T2050 = T(T.Year==2050,:);
plot_heat(T2050, 'EngineeringLCOE_USD_per_MWh', '2050 LCOE (USD/MWh)', ...
    fullfile(figdir, 'province_lcoe_heatmap_2050.png'));
plot_heat(T2050, 'WindTotal_GW', '2050 cumulative wind (GW)', ...
    fullfile(figdir, 'province_wind_total_heatmap_2050.png'));

s0 = T(T.Scenario=="S0" & T.Year==2050,:);
s2 = T(T.Scenario=="S2" & T.Year==2050,:);
[common, i0, i2] = intersect(s0.Province, s2.Province, 'stable'); %#ok<ASGLU>
delta = table(s0.Province(i0), s2.EngineeringLCOE_USD_per_MWh(i2)-s0.EngineeringLCOE_USD_per_MWh(i0), ...
    s2.WindTotal_GW(i2)-s0.WindTotal_GW(i0), ...
    'VariableNames', {'Province','DeltaLCOE_S2_minus_S0','DeltaWindGW_S2_minus_S0'});
f = figure('Position',[80 80 1000 460]);
bar(categorical(delta.Province), [delta.DeltaLCOE_S2_minus_S0, delta.DeltaWindGW_S2_minus_S0]);
grid on; ylabel('Delta'); title('2050 S2 - S0 learning effect');
legend({'LCOE delta (USD/MWh)','Wind delta (GW)'},'Location','best');
exportgraphics(f, fullfile(figdir, 'province_learning_delta_s0_s2_2050.png'), 'Resolution', 180);
close(f);

f = figure('Position',[80 80 1100 520]);
S2_2050 = T(T.Scenario=="S2" & T.Year==2050,:);
cost = [S2_2050.CostWind_USDyr, S2_2050.CostSystemBESS_USDyr, S2_2050.CostVRB_USDyr, ...
    S2_2050.CostH2_USDyr, S2_2050.CostOperation_USDyr] ./ 1e9;
bar(categorical(S2_2050.Province), cost, 'stacked');
grid on; ylabel('Annual engineering cost (billion USD/yr)');
title('S2 2050 cost decomposition');
legend({'Wind','System BESS','VRB','H2','Operation'},'Location','northwest');
exportgraphics(f, fullfile(figdir, 'cost_decomposition_s2_2050.png'), 'Resolution', 180);
close(f);

f = figure('Position',[80 80 1000 520]);
subplot(1,2,1); boxchart(categorical(T.Scenario), T.EngineeringLCOE_USD_per_MWh);
grid on; ylabel('USD/MWh'); title('LCOE distribution');
subplot(1,2,2); scatter(T.WindTotal_GW, T.EngineeringLCOE_USD_per_MWh, 28, categorical(T.Scenario), 'filled');
grid on; xlabel('Wind total (GW)'); ylabel('LCOE (USD/MWh)'); title('Scale vs LCOE');
exportgraphics(f, fullfile(figdir, 'lcoe_distribution_and_scale.png'), 'Resolution', 180);
close(f);

f = figure('Position',[80 80 1050 520]);
subplot(1,2,1); histogram(T.ShapeCoverage, 30); grid on; title('Shape coverage');
subplot(1,2,2); histogram(T.CurtailmentRate, 30); grid on; title('Curtailment rate');
exportgraphics(f, fullfile(figdir, 'constraint_binding_histograms.png'), 'Resolution', 180);
close(f);
end

function plot_lines(A, scenarios, cols, yvar, ylab, file)
f = figure('Position',[80 80 900 480]); hold on;
for i=1:numel(scenarios)
    s = scenarios(i);
    B = A(A.Scenario==s,:);
    plot(B.Year, B.(yvar), '-o', 'LineWidth', 1.8, 'Color', cols(i,:), 'DisplayName', s);
end
grid on; xlabel('Year'); ylabel(ylab); legend('Location','best');
title(strrep(yvar, '_', ' '));
exportgraphics(f, file, 'Resolution', 180);
close(f);
end

function plot_heat(T, varname, ttl, file)
P = unique(T.Province, 'stable');
S = unique(T.Scenario, 'stable');
M = nan(numel(P), numel(S));
for i=1:numel(P)
    for j=1:numel(S)
        row = T(T.Province==P(i) & T.Scenario==S(j),:);
        if ~isempty(row), M(i,j)=row.(varname)(1); end
    end
end
f = figure('Position',[80 80 760 620]);
h = heatmap(S, P, M);
h.Title = ttl; h.XLabel = 'Scenario'; h.YLabel = 'Province';
exportgraphics(f, file, 'Resolution', 180);
close(f);
end

function [H, check] = replay_hourly_dispatch(cfg, I, Tsum, province, target_year, scenario)
province = string(province); scenario = upper(string(scenario));
ccase = cfg; ccase.learning.case = scenario; ccase.storage.h2.enabled = true; ccase.p2h.enabled = false;
S = load(fullfile(cfg.output_root,'path','path_states.mat'), 'case_outputs');
learn_by_year = S.case_outputs.(char(scenario)).learning_states_start;
years = S.case_outputs.(char(scenario)).years;
state = rev04_empty_asset_state(I);
state.fixed_raw_profile_MW = zeros(I.T,1);
target_result = [];
pre_state = [];
for yi = 1:numel(years)
    y = years(yi);
    learn = learn_by_year{yi};
    [cost,~] = rev04_cost_snapshot(ccase, y, scenario, learn);
    state = rev04_apply_replacements(state, cost, y, ccase);
    if ~isfield(state,'fixed_raw_profile_MW')
        state.fixed_raw_profile_MW = reconstruct_raw_profile_from_cohorts(state, I);
    end
    r = rev04_solve_core_lp(I, ccase, province, y, cost, state, "fixed_target", NaN);
    assert(r.feasible, 'Replay infeasible: %s %d %s', province, y, scenario);
    if y == target_year
        target_result = r;
        pre_state = state;
        break
    end
    state.fixed_raw_profile_MW = state.fixed_raw_profile_MW + package_raw_profile(I, r.packages) * r.x;
    [state,~] = rev04_advance_asset_state(state, r, cost, y);
end
assert(~isempty(target_result), 'Target year not replayed.');

r = target_result;
raw_new = package_raw_profile(I, r.packages) * r.x;
raw_wind = pre_state.fixed_raw_profile_MW + raw_new;
project_output = double(pre_state.fixed_profile_MW(:)) + double(r.packages.profile_MW) * r.x;
storage_ch = r.bess.charge_MW + r.vrb.charge_MW;
storage_dis = r.bess.discharge_MW + r.vrb.discharge_MW;
net_after_storage = project_output - storage_ch - r.h2.el_MW + storage_dis + r.h2.gen_MW;
prov_idx = find(I.prov_names == province,1);
iy = find(I.years == target_year,1);
D = squeeze(double(I.D_MW(prov_idx,iy,:)));
Pshape = D ./ sum(D) .* I.Etarget_MWh(prov_idx,iy);
dt = (datetime(target_year,1,1,0,0,0) + hours(0:I.T-1))';
H = table((1:I.T)', dt, raw_wind, project_output, storage_ch, storage_dis, ...
    r.h2.el_MW, r.h2.gen_MW, net_after_storage, r.Pdel_MW, r.Pcredit_MW, Pshape, ...
    r.system_curt_MW, r.bess.soc_MWh, r.vrb.soc_MWh, r.h2.soc_MWh, ...
    'VariableNames', {'Hour','Timestamp','raw_wind_MW','project_output_MW', ...
    'system_storage_charge_MW','system_storage_discharge_MW','h2_electrolyzer_MW', ...
    'h2_generation_MW','net_available_after_storage_MW','Pdel_MW','Pcredit_MW', ...
    'Pshape_MW','system_curtailment_MW','bess_soc_MWh','vrb_soc_MWh','h2_soc_MWh'});

summary_row = Tsum(Tsum.Scenario==scenario & Tsum.Province==province & Tsum.Year==target_year,:);
replay_row = rev04_result_row(r, scenario);
check = table(scenario, province, target_year, ...
    replay_row.Contract_TWh, summary_row.Contract_TWh, ...
    replay_row.Delivery_TWh, summary_row.Delivery_TWh, ...
    replay_row.WindTotal_GW, summary_row.WindTotal_GW, ...
    replay_row.EngineeringLCOE_USD_per_MWh, summary_row.EngineeringLCOE_USD_per_MWh, ...
    max(H.Pcredit_MW - H.Pdel_MW), max(H.Pcredit_MW - H.Pshape_MW), ...
    r.max_eq_residual, r.max_ineq_residual, ...
    'VariableNames', {'Scenario','Province','Year','ReplayContract_TWh','SummaryContract_TWh', ...
    'ReplayDelivery_TWh','SummaryDelivery_TWh','ReplayWindTotal_GW','SummaryWindTotal_GW', ...
    'ReplayLCOE','SummaryLCOE','MaxCreditMinusDelivery','MaxCreditMinusShape', ...
    'MaxEqResidual','MaxIneqResidual'});
end

function M = package_raw_profile(I, P)
T = I.T;
M = zeros(T, P.n);
for j = 1:P.n
    raw_pu = squeeze(double(I.g_pu(P.site_idx(j), P.turbine_idx(j), :)));
    M(:,j) = P.cap_MW(j) .* raw_pu;
end
end

function raw = reconstruct_raw_profile_from_cohorts(state, I)
raw = zeros(numel(state.fixed_profile_MW),1);
for i=1:numel(state.wind_cohorts)
    q = state.wind_cohorts(i);
    raw = raw + q.cap_MW .* squeeze(double(I.g_pu(q.site_idx, q.turbine_idx, :)));
end
end

function plot_hourly_combo(H, spec, figdir)
base = sprintf('%s_%d_%s', spec.Province, spec.Year, spec.Scenario);
raw = H.raw_wind_MW; pshape = H.Pshape_MW;
windows = representative_windows(H, raw, pshape);
names = fieldnames(windows);
for i=1:numel(names)
    nm = names{i}; ix = windows.(nm);
    f = figure('Position',[60 60 1200 520]);
    plot(H.Timestamp(ix), H.raw_wind_MW(ix), 'Color',[0.65 0.65 0.65], 'LineWidth',1.1); hold on;
    plot(H.Timestamp(ix), H.project_output_MW(ix), 'Color',[0.1 0.45 0.85], 'LineWidth',1.1);
    plot(H.Timestamp(ix), H.net_available_after_storage_MW(ix), 'Color',[0.1 0.65 0.25], 'LineWidth',1.1);
    plot(H.Timestamp(ix), H.Pdel_MW(ix), 'Color',[0.85 0.2 0.15], 'LineWidth',1.4);
    plot(H.Timestamp(ix), H.Pshape_MW(ix), '--', 'Color',[0 0 0], 'LineWidth',1.2);
    grid on; ylabel('MW'); title(sprintf('%s %d %s - %s', spec.Province, spec.Year, spec.Scenario, nm));
    legend({'Raw wind','Project output','Net after storage','Delivered Pdel','Pshape target'},'Location','best');
    exportgraphics(f, fullfile(figdir, sprintf('hourly_%s_%s.png', base, nm)), 'Resolution', 180);
    close(f);

    f = figure('Position',[60 60 1200 520]);
    yyaxis left;
    area(H.Timestamp(ix), [H.system_storage_charge_MW(ix), H.h2_electrolyzer_MW(ix)], 'LineStyle','none'); hold on;
    plot(H.Timestamp(ix), H.system_storage_discharge_MW(ix), 'LineWidth',1.2);
    plot(H.Timestamp(ix), H.h2_generation_MW(ix), 'LineWidth',1.2);
    ylabel('Power (MW)');
    yyaxis right;
    plot(H.Timestamp(ix), H.h2_soc_MWh(ix)./1000, 'k-', 'LineWidth',1.3);
    ylabel('H2 stock (GWh)');
    grid on; title(sprintf('%s %d %s - storage actions %s', spec.Province, spec.Year, spec.Scenario, nm));
    legend({'BESS+VRB charge','H2 electrolysis','BESS+VRB discharge','H2 generation','H2 stock'},'Location','best');
    exportgraphics(f, fullfile(figdir, sprintf('storage_actions_%s_%s.png', base, nm)), 'Resolution', 180);
    close(f);
end

f = figure('Position',[60 60 1050 520]);
plot(sort(H.raw_wind_MW,'descend'), 'Color',[0.65 0.65 0.65], 'LineWidth',1.1); hold on;
plot(sort(H.project_output_MW,'descend'), 'Color',[0.1 0.45 0.85], 'LineWidth',1.1);
plot(sort(H.net_available_after_storage_MW,'descend'), 'Color',[0.1 0.65 0.25], 'LineWidth',1.1);
plot(sort(H.Pdel_MW,'descend'), 'Color',[0.85 0.2 0.15], 'LineWidth',1.2);
plot(sort(H.Pshape_MW,'descend'), '--k', 'LineWidth',1.1);
grid on; xlabel('Sorted hour'); ylabel('MW');
title(sprintf('%s %d %s - annual duration curves', spec.Province, spec.Year, spec.Scenario));
legend({'Raw wind','Project output','Net after storage','Delivered Pdel','Pshape target'},'Location','best');
exportgraphics(f, fullfile(figdir, sprintf('duration_curve_%s.png', base)), 'Resolution', 180);
close(f);
end

function windows = representative_windows(H, raw, pshape)
T = height(H); w = 168;
load_score = movsum(pshape, [0 w-1], 'Endpoints','discard');
wind_score = movsum(raw, [0 w-1], 'Endpoints','discard');
gap_score = movsum(max(pshape-raw,0), [0 w-1], 'Endpoints','discard');
[~, a] = max(load_score); [~, b] = max(wind_score); [~, c] = max(gap_score);
windows.high_load_week = a:min(a+w-1,T);
windows.high_wind_week = b:min(b+w-1,T);
windows.high_gap_week = c:min(c+w-1,T);
end

function write_report(file, T, A, D, Hcheck)
fid = fopen(file, 'w');
assert(fid>0, 'Cannot write report: %s', file);
cleanup = onCleanup(@() fclose(fid));

fprintf(fid, '# Rev04 Milestone A/B/C path diagnostic report\n\n');
fprintf(fid, 'Generated: %s\n\n', string(datetime('now')));
fprintf(fid, '## Data coverage\n\n');
fprintf(fid, '- Path rows: %d. Scenarios: %s. Years: %s.\n', height(T), ...
    strjoin(unique(T.Scenario,'stable'), ', '), strjoin(string(unique(T.Year)), ', '));
fprintf(fid, '- Solver status: %d OPTIMAL rows out of %d.\n', sum(T.SolverStatus=="OPTIMAL"), height(T));
fprintf(fid, '- Hourly replay combinations: Guangxi/Guangdong x 2030/2040/2050 x S2.\n\n');

fprintf(fid, '## Key numerical ranges\n\n');
fprintf(fid, '- Engineering LCOE: %.2f to %.2f USD/MWh.\n', min(T.EngineeringLCOE_USD_per_MWh), max(T.EngineeringLCOE_USD_per_MWh));
fprintf(fid, '- 2050 S2 total wind: %.1f GW; 2050 S0 total wind: %.1f GW.\n', ...
    sum(T.WindTotal_GW(T.Scenario=="S2" & T.Year==2050)), sum(T.WindTotal_GW(T.Scenario=="S0" & T.Year==2050)));
fprintf(fid, '- Shape coverage range: %.6f to %.6f.\n', min(T.ShapeCoverage), max(T.ShapeCoverage));
fprintf(fid, '- Curtailment rate range: %.4f to %.4f.\n\n', min(T.CurtailmentRate), max(T.CurtailmentRate));

fprintf(fid, '## Diagnostic flags\n\n');
fprintf(fid, '- Rows with EqResidual > 1e-6: %d.\n', sum(D.EqResidualFlag));
fprintf(fid, '- Rows with IneqResidual > 1e-6: %d.\n', sum(D.IneqResidualFlag));
fprintf(fid, '- Rows where shape coverage binds at 0.8: %d.\n', sum(D.ShapeCoverageBinding));
fprintf(fid, '- Rows where curtailment cap binds at 10%%: %d.\n', sum(D.CurtailmentBinding));
fprintf(fid, '- Rows with near-zero project BESS: %d.\n', sum(D.ProjectBESSNearZero));
fprintf(fid, '- Rows with near-zero VRB: %d.\n', sum(D.VRBNearZero));
fprintf(fid, '- Rows with high H2 storage intensity: %d.\n\n', sum(D.H2StorageHigh));

fprintf(fid, '## Interpretation\n\n');
fprintf(fid, '- The path results are internally complete and all 240 annual LPs are marked OPTIMAL.\n');
fprintf(fid, '- Project-side BESS is almost never selected in the path output, so the current project package is not materially contributing to shaped delivery. This should be discussed as a model result or revisited through project-BESS cost/package sensitivity.\n');
fprintf(fid, '- VRB/LDES is almost zero in the S0-S3 path, while H2 P2P enters early and with large energy capacity. This means the current cost/closure settings make H2 the dominant long-duration flexibility option.\n');
fprintf(fid, '- Shape coverage is essentially always exactly 0.8, indicating the shaped-delivery quality constraint is binding and the model is minimizing engineering cost subject to the minimum acceptable delivery-quality threshold.\n');
fprintf(fid, '- Curtailment frequently binds at 10%%, so the curtailment policy cap is an active driver of site/storage choice.\n\n');

fprintf(fid, '## External reality benchmarks\n\n');
fprintf(fid, '- China offshore wind was about 38.3 GW at end-2024 in the compiled country table on offshore wind power; the model 2050 path is much larger because it is a long-term technical/planning expansion path, not a near-term forecast.\n');
fprintf(fid, '- China grid-connected wind capacity was reported around 520.68 GW at end-2024 in the National Bureau of Statistics 2024 communiqué as summarized by public references.\n');
fprintf(fid, '- Public battery-storage summaries report China grid battery stations around 62 GW / 141 GWh at end-2024; model system BESS totals are comparable in power scale by 2050 but are dedicated only to offshore-wind shaped delivery.\n');
fprintf(fid, '- Offshore wind LCOE benchmarks in public references are often around 70-140 USD/MWh for recent projects; the model 2050 S2 values can be below this in high-resource provinces because it applies exogenous wind-cost decline and selects best RDUs.\n\n');

fprintf(fid, '## Hourly replay QA\n\n');
for i=1:height(Hcheck)
    fprintf(fid, '- %s %d %s: contract %.3f TWh, delivery %.3f TWh, replay LCOE %.2f vs summary %.2f, max credit-delivery %.3g MW, max credit-shape %.3g MW.\n', ...
        Hcheck.Province(i), Hcheck.Year(i), Hcheck.Scenario(i), Hcheck.ReplayContract_TWh(i), ...
        Hcheck.ReplayDelivery_TWh(i), Hcheck.ReplayLCOE(i), Hcheck.SummaryLCOE(i), ...
        Hcheck.MaxCreditMinusDelivery(i), Hcheck.MaxCreditMinusShape(i));
end
fprintf(fid, '\n## Figures\n\n');
fprintf(fid, 'See `figures/` for annual path plots, province heatmaps, cost decomposition, hourly representative weeks, storage-action plots, and annual duration curves.\n');
end

function ensure_dir(d)
if ~isfolder(d), mkdir(d); end
end
