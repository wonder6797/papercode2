function out = rev04_run_monthlyband_experiment(provinces, cases, years, opts)
%REV04_RUN_MONTHLYBAND_EXPERIMENT Limited delivery-mode experiment runner.

if nargin < 1 || isempty(provinces), provinces = "Guangxi"; end
if nargin < 2 || isempty(cases), cases = ["S0","S2"]; end
if nargin < 3 || isempty(years), years = [2025 2030 2035 2040 2045 2050]; end
if nargin < 4 || isempty(opts), opts = struct(); end

cfg = rev04_default_config();
cfg.input_mat = string(get_opt(opts,'input_mat',cfg.input_mat));
cfg.load_xlsx = string(get_opt(opts,'load_xlsx',cfg.load_xlsx));
cfg.output_root = string(get_opt(opts,'output_root',cfg.output_root));
cfg.project_bess.ramp_cache_dir = string(get_opt(opts,'ramp_cache_dir', ...
    fullfile(cfg.output_root,'cache_project_ramp_profiles')));
cfg.run.verbose = get_opt(opts,'verbose',true);
cfg.delivery.mode = string(get_opt(opts,'delivery_mode',cfg.delivery.mode));
cfg.delivery.diagnostic_slack = logical(get_opt(opts,'diagnostic_slack',cfg.delivery.diagnostic_slack));
cfg.delivery.smooth_second_stage = logical(get_opt(opts,'smooth_second_stage',cfg.delivery.smooth_second_stage));
cfg.delivery.monthly_band_delta = double(get_opt(opts,'monthly_band_delta',cfg.delivery.monthly_band_delta));
cfg.delivery.max_curtailment_frac = double(get_opt(opts,'curtailment_cap',cfg.delivery.max_curtailment_frac));
cfg.delivery.hourly_upper_years = double(get_opt(opts,'hourly_upper_years',cfg.delivery.hourly_upper_years));
cfg.delivery.hourly_upper_delta = double(get_opt(opts,'hourly_upper_delta',cfg.delivery.hourly_upper_delta));
cfg.delivery.enable_hourly_lower = logical(get_opt(opts,'enable_hourly_lower',cfg.delivery.enable_hourly_lower));
cfg.delivery.hourly_band_delta = double(get_opt(opts,'hourly_band_delta',cfg.delivery.hourly_band_delta));
if isfield(opts,'hourly_band_delta_years') || isfield(opts,'hourly_band_delta_values')
    cfg.delivery.hourly_band_delta_years = double(get_opt(opts,'hourly_band_delta_years',cfg.delivery.hourly_band_delta_years));
    cfg.delivery.hourly_band_delta_values = double(get_opt(opts,'hourly_band_delta_values',cfg.delivery.hourly_band_delta_values));
elseif isfield(opts,'hourly_band_delta')
    cfg.delivery.hourly_band_delta_years = [];
    cfg.delivery.hourly_band_delta_values = [];
end
cfg.delivery.hourly_band_delta_up = double(get_opt(opts,'hourly_band_delta_up',cfg.delivery.hourly_band_delta_up));
cfg.delivery.hourly_band_delta_low = double(get_opt(opts,'hourly_band_delta_low',cfg.delivery.hourly_band_delta_low));
if isfield(opts,'hourly_band_delta_up_years') || isfield(opts,'hourly_band_delta_up_values')
    cfg.delivery.hourly_band_delta_up_years = double(get_opt(opts,'hourly_band_delta_up_years',cfg.delivery.hourly_band_delta_up_years));
    cfg.delivery.hourly_band_delta_up_values = double(get_opt(opts,'hourly_band_delta_up_values',cfg.delivery.hourly_band_delta_up_values));
elseif isfield(opts,'hourly_band_delta_up')
    cfg.delivery.hourly_band_delta_up_years = [];
    cfg.delivery.hourly_band_delta_up_values = [];
end
if isfield(opts,'hourly_band_delta_low_years') || isfield(opts,'hourly_band_delta_low_values')
    cfg.delivery.hourly_band_delta_low_years = double(get_opt(opts,'hourly_band_delta_low_years',cfg.delivery.hourly_band_delta_low_years));
    cfg.delivery.hourly_band_delta_low_values = double(get_opt(opts,'hourly_band_delta_low_values',cfg.delivery.hourly_band_delta_low_values));
elseif isfield(opts,'hourly_band_delta_low')
    cfg.delivery.hourly_band_delta_low_years = [];
    cfg.delivery.hourly_band_delta_low_values = [];
end
cfg.delivery.annual_energy_tolerance = double(get_opt(opts,'annual_energy_tolerance',cfg.delivery.annual_energy_tolerance));
cfg.solver.time_limit_s = double(get_opt(opts,'solver_time_limit_s',cfg.solver.time_limit_s));
cfg.solver.method = double(get_opt(opts,'solver_method',cfg.solver.method));
cfg.solver.crossover = double(get_opt(opts,'solver_crossover',cfg.solver.crossover));
cfg.solver.allow_suboptimal_with_x = logical(get_opt(opts,'allow_suboptimal_with_x',cfg.solver.allow_suboptimal_with_x));
cfg.screen.max_packages_per_province_year = double(get_opt(opts,'max_packages_per_province_year',cfg.screen.max_packages_per_province_year));
cfg.screen.max_packages_years = double(get_opt(opts,'max_packages_years',cfg.screen.max_packages_years));
cfg.packages.pre_screen_before_ramp = logical(get_opt(opts,'pre_screen_before_ramp',cfg.packages.pre_screen_before_ramp));
cfg.packages.pre_screen_max_packages = double(get_opt(opts,'pre_screen_max_packages',cfg.packages.pre_screen_max_packages));
cfg.project_bess.ramp_quantile = double(get_opt(opts,'project_ramp_quantile',cfg.project_bess.ramp_quantile));
if isfield(opts,'province_hourly_band')
    cfg.delivery.province_hourly_band = opts.province_hourly_band;
end
resume_completed_lp = logical(get_opt(opts,'resume_completed_lp',true));
cfg.dispatch_tiebreak.enable = logical(get_opt(opts,'dispatch_tiebreak_enable',cfg.dispatch_tiebreak.enable));
cfg.dispatch_tiebreak.mode = string(get_opt(opts,'dispatch_tiebreak_mode',cfg.dispatch_tiebreak.mode));
cfg.dispatch_tiebreak.system_curtailment_cost_USD_per_MWh = double(get_opt(opts,'dispatch_tiebreak_system_curtailment_cost_USD_per_MWh',cfg.dispatch_tiebreak.system_curtailment_cost_USD_per_MWh));
cfg.dispatch_tiebreak.pdel_level_cost_USD_per_MWh = double(get_opt(opts,'dispatch_tiebreak_pdel_level_cost_USD_per_MWh',cfg.dispatch_tiebreak.pdel_level_cost_USD_per_MWh));
cfg.dispatch_tiebreak.pdel_delta_cost_USD_per_MW = double(get_opt(opts,'dispatch_tiebreak_pdel_delta_cost_USD_per_MW',cfg.dispatch_tiebreak.pdel_delta_cost_USD_per_MW));
cfg.dispatch_tiebreak.system_curtailment_delta_cost_USD_per_MW = double(get_opt(opts,'dispatch_tiebreak_system_curtailment_delta_cost_USD_per_MW',cfg.dispatch_tiebreak.system_curtailment_delta_cost_USD_per_MW));
cfg.dispatch_tiebreak.max_share_of_engineering_cost = double(get_opt(opts,'dispatch_tiebreak_max_share_of_engineering_cost',cfg.dispatch_tiebreak.max_share_of_engineering_cost));
cfg.dispatch_tiebreak.compare_no_tiebreak = logical(get_opt(opts,'compare_no_tiebreak',cfg.dispatch_tiebreak.compare_no_tiebreak));
cfg.dispatch_smoothing.cost_tolerance_frac = double(get_opt(opts,'smoothing_cost_tolerance_frac',cfg.dispatch_smoothing.cost_tolerance_frac));
cfg.dispatch_smoothing.weight_level_error = double(get_opt(opts,'smoothing_weight_level_error',cfg.dispatch_smoothing.weight_level_error));
cfg.dispatch_smoothing.weight_slope_error = double(get_opt(opts,'smoothing_weight_slope_error',cfg.dispatch_smoothing.weight_slope_error));
cfg.dispatch_smoothing.weight_curtailment_variation = double(get_opt(opts,'smoothing_weight_curtailment_variation',cfg.dispatch_smoothing.weight_curtailment_variation));
run_label = string(get_opt(opts,'run_label',sprintf('%s_%s', cfg.delivery.mode, datestr(now,'yyyymmdd_HHMMSS'))));

[cfg,~,I] = rev04_initialize(cfg);
provinces = string(provinces);
cases = string(cases);
years = double(years);

run_name = sprintf('%s__%s', char(run_label), strjoin(cellstr(provinces), "_"));
od = fullfile(cfg.output_root, run_name);
if ~isfolder(od), mkdir(od); end
figdir = fullfile(od, 'figures'); if ~isfolder(figdir), mkdir(figdir); end
hourdir = fullfile(od, 'hourly'); if ~isfolder(hourdir), mkdir(hourdir); end
lpdir = fullfile(od, 'lp_results'); if ~isfolder(lpdir), mkdir(lpdir); end

rev04_audit_raw_wind_ramp(I, cfg, fullfile(od, 'qa_raw_wind_ramp_distribution.csv'));
write_manifest(cfg, provinces, cases, years, opts, od);

summary = table();
qa_project = table();
qa_h2 = table();
qa_roles = table();
qa_monthly = table();
qa_hourly_top = table();
qa_smooth = table();
qa_shape = table();
qa_tiebreak = table();
case_outputs = struct();

for ci = 1:numel(cases)
    sc = upper(string(cases(ci)));
    ccase = cfg;
    ccase.learning.case = sc;
    ccase.p2h.enabled = false;
    ccase.storage.h2.enabled = true;
    learn = rev04_init_learning_state(ccase);
    assets = cell(numel(provinces),1);
    for p = 1:numel(provinces), assets{p}=rev04_empty_asset_state(I); end
    cost_diags = cell(numel(years),1);
    learning_states_start = cell(numel(years),1);
    for yi = 1:numel(years)
        year = years(yi);
        learning_states_start{yi}=learn;
        [cost,cost_diags{yi}] = rev04_cost_snapshot(ccase,year,sc,learn);
        annual_add = zero_additions();
        for p = 1:numel(provinces)
            assets{p}=rev04_apply_replacements(assets{p},cost,year,ccase);
            cprov = apply_province_hourly_band_override(ccase, provinces(p));
            result_file = fullfile(lpdir, sprintf('result_%s_%s_%d.mat', char(sc), char(provinces(p)), year));
            current_hashes=rev04_result_hashes(cprov,I,cost,assets{p},provinces(p),year,sc);
            hashes=current_hashes; %#ok<NASGU>
            config_hash=hashes.config_hash; input_hash=hashes.input_hash; %#ok<NASGU>
            code_version_hash=hashes.code_version_hash; solver_setting_hash=hashes.solver_setting_hash; %#ok<NASGU>
            resume_valid=false;
            if resume_completed_lp && isfile(result_file)
                S=load(result_file,'r','config_hash','input_hash','code_version_hash','solver_setting_hash');
                resume_valid=isfield(S,'r') && isfield(S,'config_hash') && isfield(S,'input_hash') && ...
                    isfield(S,'code_version_hash') && isfield(S,'solver_setting_hash') && ...
                    string(S.config_hash)==current_hashes.config_hash && ...
                    string(S.input_hash)==current_hashes.input_hash && ...
                    string(S.code_version_hash)==current_hashes.code_version_hash && ...
                    string(S.solver_setting_hash)==current_hashes.solver_setting_hash;
                if resume_valid
                    r=S.r;
                    if ccase.run.verbose
                        fprintf('[ResumeLP] loaded %s %s %d\n',char(sc),char(provinces(p)),year);
                    end
                elseif ccase.run.verbose
                    fprintf('[Resume] hash mismatch, rerun.\n');
                end
            end
            if ~resume_valid
                r=rev04_solve_core_lp(I,cprov,provinces(p),year,cost,assets{p},"fixed_target",NaN);
                save(result_file,'r','hashes','config_hash','input_hash','code_version_hash','solver_setting_hash','-v7.3');
            end
            if ~r.feasible
                write_partial_outputs(od,summary,qa_project,qa_h2,qa_roles,qa_monthly,qa_hourly_top,qa_smooth,qa_shape,qa_tiebreak);
                error('Monthlyband experiment infeasible: %s %s %d. SolverStatus=%s', sc, provinces(p), year, string(r.solver.status));
            end
            if ccase.dispatch_tiebreak.enable && ccase.dispatch_tiebreak.compare_no_tiebreak
                r=attach_no_tiebreak_comparison(r,I,cprov,provinces(p),year,cost,assets{p});
                save(result_file,'r','hashes','config_hash','input_hash','code_version_hash','solver_setting_hash','-v7.3');
            end
            summary=[summary;rev04_result_row(r,sc)]; %#ok<AGROW>
            qa_project=[qa_project;project_qa_row(r,sc)]; %#ok<AGROW>
            qa_h2=[qa_h2;h2_qa_row(r,sc,cost)]; %#ok<AGROW>
            qa_roles=[qa_roles;storage_role_row(r,sc,cprov)]; %#ok<AGROW>
            qa_monthly=[qa_monthly;monthly_qa_rows(r,sc)]; %#ok<AGROW>
            qa_hourly_top=[qa_hourly_top;hourly_top_qa_rows(r,sc,100)]; %#ok<AGROW>
            qa_smooth=[qa_smooth;smooth_qa_row(r,sc)]; %#ok<AGROW>
            qa_shape=[qa_shape;shape_tracking_rows(r,sc)]; %#ok<AGROW>
            qa_tiebreak=[qa_tiebreak;tiebreak_qa_row(r,sc)]; %#ok<AGROW>
            if sc=="S2" && year==max(years)
                write_hourly_and_plot(r,I,cprov,hourdir,figdir);
            end
            [assets{p},add]=rev04_advance_asset_state(assets{p},r,cost,year);
            annual_add=sum_additions(annual_add,add);
            write_partial_outputs(od,summary,qa_project,qa_h2,qa_roles,qa_monthly,qa_hourly_top,qa_smooth,qa_shape,qa_tiebreak);
        end
        learn=rev04_update_learning_state(learn,annual_add,year);
    end
    case_outputs.(char(sc))=struct('learning_state',learn,'learning_states_start',{learning_states_start}, ...
        'years',years,'assets',{assets},'cost_diags',{cost_diags});
end

rdu_development=rev04_path_rdu_table(case_outputs,provinces);
writetable(summary,fullfile(od,'path_summary.csv'));
writetable(rdu_development,fullfile(od,'path_rdu_development.csv'));
writetable(qa_project,fullfile(od,'qa_project_bess_ramp.csv'));
writetable(qa_h2,fullfile(od,'qa_h2_role.csv'));
writetable(qa_roles,fullfile(od,'qa_storage_roles.csv'));
writetable(qa_monthly,fullfile(od,'qa_monthly_delivery_band.csv'));
writetable(qa_hourly_top,fullfile(od,'qa_hourly_delivery_band_top.csv'));
writetable(qa_smooth,fullfile(od,'qa_smooth_dispatch.csv'));
writetable(qa_shape,fullfile(od,'qa_delivery_shape_tracking.csv'));
writetable(qa_tiebreak,fullfile(od,'qa_dispatch_tiebreak.csv'));
save(fullfile(od,'path_states.mat'),'case_outputs','-v7.3');

out=struct('summary',summary,'rdu_development',rdu_development, ...
    'qa_project_bess_ramp',qa_project,'qa_h2_role',qa_h2, ...
    'qa_storage_roles',qa_roles,'qa_monthly_delivery_band',qa_monthly, ...
    'qa_hourly_delivery_band_top',qa_hourly_top, ...
    'qa_smooth_dispatch',qa_smooth,'qa_delivery_shape_tracking',qa_shape, ...
    'qa_dispatch_tiebreak',qa_tiebreak,'output_dir',od);
fprintf('Monthlyband experiment outputs written to:\n%s\n', od);
end

function v = get_opt(opts,name,default)
v = default;
if isfield(opts,name), v = opts.(name); end
end

function write_manifest(cfg, provinces, cases, years, opts, od)
fid = fopen(fullfile(od,'run_manifest.txt'),'w');
fprintf(fid,'revision=%s\n',cfg.revision);
fprintf(fid,'delivery_mode=%s\n',cfg.delivery.mode);
fprintf(fid,'diagnostic_slack=%d\n',cfg.delivery.diagnostic_slack);
fprintf(fid,'smooth_second_stage=%d\n',cfg.delivery.smooth_second_stage);
fprintf(fid,'dispatch_tiebreak_enable=%d\n',cfg.dispatch_tiebreak.enable);
fprintf(fid,'dispatch_tiebreak_mode=%s\n',cfg.dispatch_tiebreak.mode);
fprintf(fid,'dispatch_tiebreak_system_curtailment_cost_USD_per_MWh=%.6g\n',cfg.dispatch_tiebreak.system_curtailment_cost_USD_per_MWh);
fprintf(fid,'dispatch_tiebreak_pdel_level_cost_USD_per_MWh=%.6g\n',cfg.dispatch_tiebreak.pdel_level_cost_USD_per_MWh);
fprintf(fid,'dispatch_tiebreak_pdel_delta_cost_USD_per_MW=%.6g\n',cfg.dispatch_tiebreak.pdel_delta_cost_USD_per_MW);
fprintf(fid,'dispatch_tiebreak_system_curtailment_delta_cost_USD_per_MW=%.6g\n',cfg.dispatch_tiebreak.system_curtailment_delta_cost_USD_per_MW);
fprintf(fid,'dispatch_tiebreak_max_share_of_engineering_cost=%.6g\n',cfg.dispatch_tiebreak.max_share_of_engineering_cost);
fprintf(fid,'dispatch_tiebreak_compare_no_tiebreak=%d\n',cfg.dispatch_tiebreak.compare_no_tiebreak);
fprintf(fid,'monthly_band_delta=%.6g\n',cfg.delivery.monthly_band_delta);
fprintf(fid,'curtailment_cap=%.6g\n',cfg.delivery.max_curtailment_frac);
fprintf(fid,'hourly_upper_years=%s\n',mat2str(cfg.delivery.hourly_upper_years));
fprintf(fid,'hourly_upper_delta=%s\n',mat2str(cfg.delivery.hourly_upper_delta));
fprintf(fid,'enable_hourly_lower=%d\n',cfg.delivery.enable_hourly_lower);
fprintf(fid,'hourly_band_delta=%.6g\n',cfg.delivery.hourly_band_delta);
fprintf(fid,'hourly_band_delta_years=%s\n',mat2str(cfg.delivery.hourly_band_delta_years));
fprintf(fid,'hourly_band_delta_values=%s\n',mat2str(cfg.delivery.hourly_band_delta_values));
fprintf(fid,'hourly_band_delta_up=%.6g\n',cfg.delivery.hourly_band_delta_up);
fprintf(fid,'hourly_band_delta_low=%.6g\n',cfg.delivery.hourly_band_delta_low);
fprintf(fid,'hourly_band_delta_up_years=%s\n',mat2str(cfg.delivery.hourly_band_delta_up_years));
fprintf(fid,'hourly_band_delta_up_values=%s\n',mat2str(cfg.delivery.hourly_band_delta_up_values));
fprintf(fid,'hourly_band_delta_low_years=%s\n',mat2str(cfg.delivery.hourly_band_delta_low_years));
fprintf(fid,'hourly_band_delta_low_values=%s\n',mat2str(cfg.delivery.hourly_band_delta_low_values));
fprintf(fid,'annual_energy_tolerance=%.6g\n',cfg.delivery.annual_energy_tolerance);
fprintf(fid,'solver_time_limit_s=%.6g\n',cfg.solver.time_limit_s);
fprintf(fid,'solver_method=%.6g\n',cfg.solver.method);
fprintf(fid,'solver_crossover=%.6g\n',cfg.solver.crossover);
fprintf(fid,'solver_allow_suboptimal_with_x=%d\n',cfg.solver.allow_suboptimal_with_x);
fprintf(fid,'pre_screen_before_ramp=%d\n',cfg.packages.pre_screen_before_ramp);
fprintf(fid,'pre_screen_max_packages=%.6g\n',cfg.packages.pre_screen_max_packages);
fprintf(fid,'project_ramp_quantile=%.6g\n',cfg.project_bess.ramp_quantile);
fprintf(fid,'max_packages_per_province_year=%.6g\n',cfg.screen.max_packages_per_province_year);
fprintf(fid,'max_packages_years=%s\n',mat2str(cfg.screen.max_packages_years));
fprintf(fid,'package_score_metric=%s\n',cfg.screen.package_score_metric);
fprintf(fid,'province_hourly_band=%s\n',evalc('disp(cfg.delivery.province_hourly_band)'));
fprintf(fid,'provinces=%s\n',strjoin(cellstr(provinces),','));
fprintf(fid,'cases=%s\n',strjoin(cellstr(cases),','));
fprintf(fid,'years=%s\n',mat2str(years));
fprintf(fid,'opts=%s\n',evalc('disp(opts)'));
fclose(fid);
save(fullfile(od,'config_snapshot.mat'),'cfg');
end

function write_partial_outputs(od,summary,qa_project,qa_h2,qa_roles,qa_monthly,qa_hourly_top,qa_smooth,qa_shape,qa_tiebreak)
writetable(summary,fullfile(od,'path_summary.csv'));
writetable(qa_project,fullfile(od,'qa_project_bess_ramp.csv'));
writetable(qa_h2,fullfile(od,'qa_h2_role.csv'));
writetable(qa_roles,fullfile(od,'qa_storage_roles.csv'));
writetable(qa_monthly,fullfile(od,'qa_monthly_delivery_band.csv'));
writetable(qa_hourly_top,fullfile(od,'qa_hourly_delivery_band_top.csv'));
writetable(qa_smooth,fullfile(od,'qa_smooth_dispatch.csv'));
writetable(qa_shape,fullfile(od,'qa_delivery_shape_tracking.csv'));
writetable(qa_tiebreak,fullfile(od,'qa_dispatch_tiebreak.csv'));
end

function cfgp = apply_province_hourly_band_override(cfg, province)
cfgp = cfg;
if ~isfield(cfg.delivery,'province_hourly_band') || isempty(fieldnames(cfg.delivery.province_hourly_band))
    return
end
key = matlab.lang.makeValidName(char(province));
if ~isfield(cfg.delivery.province_hourly_band, key)
    return
end
ov = cfg.delivery.province_hourly_band.(key);
if isfield(ov,'delta_up'), cfgp.delivery.hourly_band_delta_up = double(ov.delta_up); end
if isfield(ov,'delta_low'), cfgp.delivery.hourly_band_delta_low = double(ov.delta_low); end
if isfield(ov,'delta_up_years'), cfgp.delivery.hourly_band_delta_up_years = double(ov.delta_up_years); end
if isfield(ov,'delta_up_values'), cfgp.delivery.hourly_band_delta_up_values = double(ov.delta_up_values); end
if isfield(ov,'delta_low_years'), cfgp.delivery.hourly_band_delta_low_years = double(ov.delta_low_years); end
if isfield(ov,'delta_low_values'), cfgp.delivery.hourly_band_delta_low_values = double(ov.delta_low_values); end
end

function T = monthly_qa_rows(r, scenario)
T = r.monthly_delivery;
T.scenario = repmat(string(scenario),height(T),1);
end

function T = hourly_top_qa_rows(r, scenario, n)
H = r.hourly_delivery;
score = H.slack_low_MW + H.slack_high_MW + H.violation_low_MW + H.violation_high_MW;
if all(score <= 0)
    [~,ord] = maxk(abs(H.Pdel_MW - H.Pshape_MW), min(n,height(H)));
else
    [~,ord] = maxk(score, min(n,height(H)));
end
T = H(ord,:);
T.province = repmat(r.province,height(T),1);
T.scenario = repmat(string(scenario),height(T),1);
T.year = repmat(r.year,height(T),1);
T.slack_score_MW = score(ord);
T = movevars(T,{'province','scenario','year'},'Before','hour');
end

function r = attach_no_tiebreak_comparison(r,I,cfg,province,year,cost,state)
cfg0 = cfg;
cfg0.dispatch_tiebreak.enable = false;
cfg0.run.verbose = false;
r0 = rev04_solve_core_lp(I,cfg0,province,year,cost,state,"fixed_target",NaN);
if r0.feasible
    base = r0.engineering_LCOE_USD_per_MWh;
    delta = (r.engineering_LCOE_USD_per_MWh-base)/max(abs(base),eps);
    r.dispatch_tiebreak.engineering_lcoe_no_tiebreak_USD_per_MWh = base;
    r.dispatch_tiebreak.engineering_lcoe_delta_vs_no_tiebreak_frac = delta;
    r.dispatch_tiebreak.engineering_lcoe_delta_warning = abs(delta) > r.dispatch_tiebreak.engineering_lcoe_delta_warning_frac;
    if r.dispatch_tiebreak.engineering_lcoe_delta_warning && cfg.run.verbose
        fprintf('[DispatchTiebreakWarning] %s %d engineering LCOE delta vs no-tiebreak = %.4g\n', ...
            char(province),year,delta);
    end
end
end

function row = tiebreak_qa_row(r, scenario)
tb = r.dispatch_tiebreak;
row = table(r.province,r.year,string(scenario),string(tb.mode),logical(tb.enabled), ...
    tb.system_curtailment_cost_USD_per_MWh,tb.C_tiebreak_USD, ...
    tb.C_tiebreak_system_curtailment_USD,tb.C_tiebreak_pdel_level_USD, ...
    tb.C_tiebreak_pdel_delta_USD,tb.C_tiebreak_system_curtailment_delta_USD, ...
    tb.share_of_engineering_cost,tb.max_share_of_engineering_cost, ...
    logical(tb.share_warning),tb.engineering_lcoe_no_tiebreak_USD_per_MWh, ...
    tb.engineering_lcoe_delta_vs_no_tiebreak_frac, ...
    tb.engineering_lcoe_delta_warning_frac,logical(tb.engineering_lcoe_delta_warning), ...
    'VariableNames',{'province','year','scenario','TiebreakMode','dispatch_tiebreak_enabled', ...
    'system_curtailment_cost_USD_per_MWh','C_tiebreak_USD', ...
    'C_tiebreak_system_curtailment_USD','C_tiebreak_pdel_level_USD', ...
    'C_tiebreak_pdel_delta_USD','C_tiebreak_system_curtailment_delta_USD', ...
    'TiebreakShareOfEngineeringCost','TiebreakMaxShareOfEngineeringCost', ...
    'TiebreakShareWarning','EngineeringLCOENoTiebreak_USD_per_MWh', ...
    'EngineeringLCOEDeltaVsNoTiebreakFrac', ...
    'EngineeringLCOEDeltaWarningFrac','EngineeringLCOEDeltaWarning'});
end

function row = smooth_qa_row(r, scenario)
s = r.smooth;
row = table(r.province,string(scenario),r.year,logical(s.smooth_second_stage_enabled), ...
    s.stage1_cost_USD,s.stage2_cost_USD,s.stage2_cost_change_frac, ...
    s.sum_abs_Pdel_minus_Pshape_MWh, ...
    s.sum_abs_delta_Pdel_minus_delta_Pshape_MW, ...
    s.sum_abs_delta_curt_MW,s.TrendMatchRate,s.TrendMismatchRate, ...
    s.Corr_dPdel_dPshape,s.Pdel_total_variation,s.Curt_total_variation, ...
    logical(s.stage2_used),string(s.stage2_status), ...
    'VariableNames',{'province','scenario','year','smooth_second_stage_enabled', ...
    'stage1_cost_USD','stage2_cost_USD','stage2_cost_change_frac', ...
    'sum_abs_Pdel_minus_Pshape_MWh','sum_abs_delta_Pdel_minus_delta_Pshape_MW', ...
    'sum_abs_delta_curt_MW','TrendMatchRate','TrendMismatchRate', ...
    'Corr_dPdel_dPshape','Pdel_total_variation','Curt_total_variation', ...
    'stage2_used','stage2_status'});
end

function rows=shape_tracking_rows(r,scenario)
names=["Stage1";"Stage2"];
metrics={r.smooth.stage1;r.smooth.stage2};
pdel={r.stage1.Pdel_MW;r.Pdel_MW};
upper=zeros(2,1); lower=zeros(2,1);
for k=1:2
    ps=r.Pshape_MW(:); pd=pdel{k}(:);
    if isfinite(r.cost_params.HourlyUpperDeltaUsed)
        hi=(1+r.cost_params.HourlyUpperDeltaUsed)*ps;
        tol=max(1e-6,1e-6*max(1,max(hi)));
        upper(k)=nnz(abs(pd-hi)<=tol);
    end
    if r.cost_params.EnableHourlyLower && isfinite(r.cost_params.HourlyLowerDeltaUsed)
        lo=(1-r.cost_params.HourlyLowerDeltaUsed)*ps;
        tol=max(1e-6,1e-6*max(1,max(lo)));
        lower(k)=nnz(abs(pd-lo)<=tol);
    end
end
rows=table(repmat(r.province,2,1),repmat(string(scenario),2,1),repmat(r.year,2,1),names, ...
    cellfun(@(x)x.MAE_Pdel_Pshape_MW,metrics),cellfun(@(x)x.RMSE_Pdel_Pshape_MW,metrics), ...
    cellfun(@(x)x.MAE_ratio_to_mean_Pshape,metrics),cellfun(@(x)x.TrendMatchRate,metrics), ...
    cellfun(@(x)x.Corr_dPdel_dPshape,metrics),cellfun(@(x)x.Pdel_ramp_p95_MW_per_h,metrics), ...
    cellfun(@(x)x.Pshape_ramp_p95_MW_per_h,metrics), ...
    cellfun(@(x)x.SystemCurtailment_ramp_p95_MW_per_h,metrics),upper,lower, ...
    'VariableNames',{'province','scenario','year','Stage','MAE_Pdel_Pshape_MW', ...
    'RMSE_Pdel_Pshape_MW','MAE_ratio_to_mean_Pshape','TrendMatchRate','Corr_dPdel_dPshape', ...
    'Pdel_ramp_p95_MW_per_h','Pshape_ramp_p95_MW_per_h', ...
    'SystemCurtailment_ramp_p95_MW_per_h','UpperBandBindingHours','LowerBandBindingHours'});
end

function row = project_qa_row(r, scenario)
take=find(r.x>1e-7); P=r.packages;
if isempty(take) || r.wind_cap_add_MW<=1e-9
    ramp_limit=NaN; raw50=NaN; raw85=NaN; raw90=NaN; raw95=NaN; raw99=NaN; postmax=NaN; post95=NaN; ratio=NaN;
else
    w=P.cap_MW(take).*r.x(take);
    ramp_limit=max(P.ramp_limit_pu_per_h(take));
    raw50=wavg(P.raw_ramp_p50(take),w); raw85=wavg(P.raw_ramp_p85(take),w);
    raw90=wavg(P.raw_ramp_p90(take),w); raw95=wavg(P.raw_ramp_p95(take),w);
    raw99=wavg(P.raw_ramp_p99(take),w);
    postmax=max(P.post_ramp_max(take)); post95=wavg(P.post_ramp_p95(take),w);
    ratio=r.project_bess_P_add_MW/r.wind_cap_add_MW;
end
flag="ok";
if isfinite(ratio) && ratio>1.0, flag="critical"; elseif isfinite(ratio) && ratio>0.5, flag="warning"; end
cost_share=r.cost.project_bess/max(r.cost.net_total,eps);
pf=r.performance;
row=table(r.province,r.year,string(scenario),ramp_limit,raw50,raw85,raw90,raw95,raw99, ...
    postmax,post95,r.project_bess_P_add_MW,r.project_bess_E_add_MWh,ratio,cost_share, ...
    r.project_curt_MWh/1000,pf.RampCacheHit,pf.RampCacheMiss,pf.RampCacheNewFiles, ...
    pf.RampCacheReusedFiles,pf.ProjectRampProfileCalls,pf.ProjectRampProfileTime_s,string(flag), ...
    'VariableNames',{'province','year','scenario','ramp_limit_pu_per_h', ...
    'raw_ramp_p50','raw_ramp_p85','RawRampP90','RawRampP95','RawRampP99', ...
    'PostRampMax','post_ramp_p95','project_bess_P_MW','project_bess_E_MWh', ...
    'ProjectBESS_P_over_W','ProjectBESSCostShare','project_curtailment_GWh', ...
    'RampCacheHit','RampCacheMiss','RampCacheNewFiles','RampCacheReusedFiles', ...
    'ProjectRampProfileCalls','ProjectRampProfileTime_s','warning_level'});
end

function row = h2_qa_row(r, scenario, cost)
cap_el=r.h2.el_P_total_MW; cap_gen=r.h2.gen_P_total_MW; cap_h2=r.h2.store_total_MWh;
h2in=sum(r.h2.el_MW); h2out=sum(r.h2.gen_MW);
fill_h=NaN; dis_h=NaN; rte=NaN; elcf=NaN; gencf=NaN;
if cap_el>1e-9, fill_h=cap_h2/(cost.h2.eta_el*cap_el); elcf=h2in/(8760*cap_el); end
if cap_gen>1e-9, dis_h=cap_h2*cost.h2.eta_gen/cap_gen; gencf=h2out/(8760*cap_gen); end
if h2in>1e-9, rte=h2out/h2in; end
row=table(r.province,r.year,string(scenario),cap_el/1000,cap_gen/1000,cap_h2/1000,fill_h,dis_h,h2in,h2out, ...
    r.h2.CostStock_USDyr,r.h2.CostNew_USDyr,rte,elcf,gencf, ...
    'VariableNames',{'province','year','scenario','H2ElectrolyzerTotal_GW','H2GeneratorTotal_GW', ...
    'H2StorageTotal_GWh','H2ChargeFillHours_total','H2DischargeHours_total', ...
    'H2Input_MWh','H2Output_MWh','H2CostStock_USDyr','H2CostNew_USDyr','H2_roundtrip_eff_implied', ...
    'H2_el_capacity_factor','H2_gen_capacity_factor'});
end

function row = storage_role_row(r, scenario, cfg)
delivery_ratio=r.delivery_MWh/max(r.Econtract_MWh,eps);
row=table(r.province,r.year,string(scenario),r.wind_cap_add_MW/1000,r.wind_cap_total_MW/1000, ...
    r.project_bess_P_add_MW/1000,r.project_bess_E_add_MWh/1000, ...
    r.bess.P_total_MW/1000,r.bess.E_total_MWh/1000, ...
    r.vrb.P_total_MW/1000,r.vrb.E_total_MWh/1000, ...
    r.h2.el_P_total_MW/1000,r.h2.gen_P_total_MW/1000,r.h2.store_total_MWh/1000, ...
    r.shape_coverage,r.curtailment_rate,delivery_ratio, ...
    r.cost_params.MonthlyBandDelta,r.cost_params.HourlyBandDelta, ...
    r.cost_params.HourlyBandDeltaUp,r.cost_params.HourlyBandDeltaLow, ...
    abs(r.shape_coverage-cfg.delivery.min_shape_coverage)<=1e-5, ...
    abs(r.curtailment_rate-cfg.delivery.max_curtailment_frac)<=1e-5, ...
    delivery_ratio>=1+cfg.delivery.max_excess_frac-1e-5, ...
    r.engineering_LCOE_USD_per_MWh,r.max_eq_residual,r.max_ineq_residual,string(r.solver.status), ...
    r.cost_params.VRB_E_CAPEX_USD_per_MWh,r.dispatch_tiebreak.C_tiebreak_USD, ...
    r.dispatch_tiebreak.share_of_engineering_cost,logical(r.dispatch_tiebreak.share_warning), ...
    'VariableNames',{'province','year','scenario','WindAdd_GW','WindTotal_GW', ...
    'ProjectBESSAdd_GW','ProjectBESSAdd_GWh','SystemBESS_GW','SystemBESS_GWh', ...
    'VRB_GW','VRB_GWh','H2_el_GW','H2_gen_GW','H2_storage_GWh', ...
    'ShapeCoverage','CurtailmentRate','DeliveryToContract', ...
    'MonthlyBandDelta','HourlyBandDelta','HourlyBandDeltaUp','HourlyBandDeltaLow', ...
    'ShapeBinding','CurtailmentBinding','DeliveryUpperBinding', ...
    'EngineeringLCOE_USD_per_MWh','MaxEqResidual','MaxIneqResidual','SolverStatus', ...
    'VRB_E_CAPEX_USD_per_MWh','C_tiebreak_USD','TiebreakShareOfEngineeringCost', ...
    'TiebreakShareWarning'});
end

function write_hourly_and_plot(r,I,cfg,hourdir,figdir)
mid = month_index_local(I,numel(r.Pdel_MW));
T = table((1:numel(r.Pdel_MW))',mid,r.Pshape_MW,r.stage1.Pdel_MW,r.Pdel_MW, ...
    r.raw_wind_profile_MW,r.project_output_profile_MW, ...
    r.stage1.SystemCurtailment_MW,r.system_curt_MW, ...
    r.stage1.BESSCharge_MW,r.stage1.BESSDischarge_MW,r.bess.charge_MW,r.bess.discharge_MW, ...
    r.stage1.VRBCharge_MW,r.stage1.VRBDischarge_MW,r.vrb.charge_MW,r.vrb.discharge_MW, ...
    r.stage1.H2Input_MW,r.stage1.H2Output_MW,r.h2.el_MW,r.h2.gen_MW,r.h2.soc_MWh, ...
    'VariableNames',{'hour','month','Pshape_MW','Pdel_stage1_MW','Pdel_stage2_MW', ...
    'RawWind_MW','AfterProjectBESS_MW','SystemCurtailment_stage1_MW','SystemCurtailment_stage2_MW', ...
    'BESS_ch_stage1_MW','BESS_dis_stage1_MW','BESS_ch_stage2_MW','BESS_dis_stage2_MW', ...
    'VRB_ch_stage1_MW','VRB_dis_stage1_MW','VRB_ch_stage2_MW','VRB_dis_stage2_MW', ...
    'H2_el_stage1_MW','H2_gen_stage1_MW','H2_el_stage2_MW','H2_gen_stage2_MW','H2_soc_stage2_MWh_LHV'});
stem=sprintf('%s_%s_%d',char(r.province),'S2',r.year);
writetable(T,fullfile(hourdir,sprintf('dispatch_hourly_%s.csv',stem)));
plot_dispatch(r,figdir,stem,"stage1");
plot_dispatch(r,figdir,stem,"stage2");
end

function plot_dispatch(r,figdir,stem,stage)
if stage=="stage1"
    pdel=r.stage1.Pdel_MW; curt=r.stage1.SystemCurtailment_MW;
    netstore=r.stage1.BESSDischarge_MW-r.stage1.BESSCharge_MW+ ...
        r.stage1.VRBDischarge_MW-r.stage1.VRBCharge_MW+ ...
        r.stage1.H2Output_MW-r.stage1.H2Input_MW; suffix="stage1";
else
    pdel=r.Pdel_MW; curt=r.system_curt_MW;
    netstore=r.bess.discharge_MW-r.bess.charge_MW+r.vrb.discharge_MW-r.vrb.charge_MW+ ...
        r.h2.gen_MW-r.h2.el_MW; suffix="stage2";
end
ts=datetime(2025,1,1,0,0,0)+hours(0:(numel(pdel)-1));
starts=representative_week_starts(ts,r.raw_wind_profile_MW);
f=figure('Visible','off','Color','w','Position',[100 100 1500 2200]);
tl=tiledlayout(7,1,'TileSpacing','compact','Padding','compact');
names=["Winter","Spring","Summer","Autumn"];
for k=1:4
    nexttile; ix=starts(k):(starts(k)+167);
    plot(1:168,r.raw_wind_profile_MW(ix),'Color',[0.75 0.75 0.75],'LineWidth',1); hold on;
    plot(1:168,r.project_output_profile_MW(ix),'Color',[0.2 0.45 0.9],'LineWidth',1);
    plot(1:168,pdel(ix),'Color',[0.1 0.55 0.2],'LineWidth',1.2);
    plot(1:168,r.Pshape_MW(ix),'--','Color',[0.85 0.2 0.2],'LineWidth',1);
    grid on; ylabel('MW'); title(sprintf('%s typical week - %s',names(k),suffix));
    if k==1, legend({'Raw wind','After project BESS','Delivered Pdel','Pshape'},'Location','best'); end
end
nexttile;
plot(1:numel(pdel),pdel-r.Pshape_MW,'Color',[0.35 0.35 0.35],'LineWidth',0.8);
grid on; ylabel('MW'); title('Pdel - Pshape');
nexttile;
plot(sort(r.raw_wind_profile_MW,'descend'),'Color',[0.75 0.75 0.75],'LineWidth',1); hold on;
plot(sort(r.project_output_profile_MW,'descend'),'Color',[0.2 0.45 0.9],'LineWidth',1);
plot(sort(pdel,'descend'),'Color',[0.1 0.55 0.2],'LineWidth',1.2);
plot(sort(r.Pshape_MW,'descend'),'--','Color',[0.85 0.2 0.2],'LineWidth',1);
grid on; xlabel('Sorted hour'); ylabel('MW'); title('8760-hour duration comparison');
nexttile; ix=starts(1):(starts(1)+167);
plot(1:168,netstore(ix),'Color',[0.45 0.2 0.65],'LineWidth',1); hold on;
plot(1:168,curt(ix),'Color',[0.9 0.55 0.1],'LineWidth',1);
grid on; xlabel('Hour'); ylabel('MW'); title('Winter-week storage net output and system curtailment');
legend({'Storage net output','System curtailment'},'Location','best');
title(tl,sprintf('Dispatch comparison %s %s',stem,suffix));
exportgraphics(f,fullfile(figdir,sprintf('dispatch_comparison_%s_%s.png',stem,suffix)),'Resolution',180);
savefig(f,fullfile(figdir,sprintf('dispatch_comparison_%s_%s.fig',stem,suffix)));
close(f);
end

function starts=representative_week_starts(ts,raw)
season_months={[12 1 2],[3 4 5],[6 7 8],[9 10 11]};
week_starts=1:168:(numel(raw)-167);
starts=zeros(4,1);
for s=1:4
    ok=false(size(week_starts)); vals=zeros(size(week_starts));
    for i=1:numel(week_starts)
        m=month(ts(week_starts(i)+84));
        ok(i)=any(m==season_months{s});
        vals(i)=mean(raw(week_starts(i):(week_starts(i)+167)));
    end
    cand=week_starts(ok); cval=vals(ok); med=median(cval);
    [~,j]=min(abs(cval-med)); starts(s)=cand(j);
end
end

function mid=month_index_local(I,T)
if isfield(I,'month_id'), mid=double(I.month_id(:)); else, mid=month((datetime(2025,1,1,0,0,0)+hours(0:(T-1)))'); end
end

function y=wavg(x,w)
x=double(x(:)); w=double(w(:));
if isempty(x) || sum(w)<=0, y=NaN; else, y=sum(x.*w)/sum(w); end
end

function a=zero_additions()
n={'BESS_power_MW','BESS_energy_MWh','VRB_power_MW','VRB_energy_MWh','H2_el_MW','H2_storage_MWh','H2_gen_MW'};
for i=1:numel(n), a.(n{i})=0; end
end

function a=sum_additions(a,b)
n=fieldnames(a);
for i=1:numel(n)
    if isfield(b,n{i}), a.(n{i})=a.(n{i})+b.(n{i}); end
end
end
