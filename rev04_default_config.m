function cfg = rev04_default_config()
%REV04_DEFAULT_CONFIG Decision-complete configuration for the Rev04 model.

root = fileparts(mfilename('fullpath'));
cfg = struct();
cfg.revision = "rev04_mechanism_runtime_fix_01";
cfg.root = root;
cfg.input_mat = fullfile(root, 'inner_inputs_2016_v3.mat');
cfg.load_xlsx = fullfile(fileparts(root), 'Data output.xlsx');
cfg.output_root = fullfile(root, 'outputs_rev04_mechanism_runtime_fix_01');

cfg.years = [2025 2030 2035 2040 2045 2050];
cfg.provinces = ["Liaoning","Hebei","Shandong","Jiangsu","Shanghai", ...
    "Zhejiang","Fujian","Guangdong","Guangxi","Hainan"];
cfg.turbine_names = ["8MW","15MW","25MW"];
cfg.turbine_first_year = [2025 2035 2050];
cfg.wind = struct('life_year',25,'retire_within_horizon',false);

cfg.load = struct();
cfg.load.history_years = 2015:2024;
cfg.load.shape_years = 2021:2024;
cfg.load.trend_years = 2019:2024;
cfg.load.trend_floor = -0.02;
cfg.load.trend_ceiling = 0.10;
cfg.load.unit_GWh_to_MWh = 1000;
cfg.load.provenance_status = "source_pending";
cfg.load.future_growth_2025_2030 = 0.03;
cfg.load.future_growth_2030_2040 = 0.02;
cfg.load.future_growth_2040_2050 = 0.01;

cfg.delivery = struct();
cfg.delivery.mode = "monthly_upper_smooth";
cfg.delivery.target_share_years = cfg.years;
cfg.delivery.target_share_values = [0.04 0.072 0.104 0.136 0.168 0.20];
cfg.delivery.shape_type = "load_following";
cfg.delivery.min_shape_coverage = 0.80;
cfg.delivery.max_excess_frac = 0.25;
cfg.delivery.max_curtailment_frac = 0.10;
cfg.delivery.monthly_band_delta = 0.30;
cfg.delivery.monthly_band_sensitivity = [0.40 0.30 0.20];
cfg.delivery.hourly_upper_years = [2025 2030 2035 2040 2045 2050];
cfg.delivery.hourly_upper_delta = [0.90 0.85 0.80 0.75 0.70 0.65];
cfg.delivery.enable_hourly_lower = false;
cfg.delivery.hourly_band_delta = 0.65;
cfg.delivery.hourly_band_delta_years = cfg.years;
cfg.delivery.hourly_band_delta_values = [1.00 0.90 0.80 0.75 0.70 0.65];
cfg.delivery.hourly_band_delta_up = 0.65;
cfg.delivery.hourly_band_delta_low = 0.70;
cfg.delivery.hourly_band_delta_up_years = cfg.years;
cfg.delivery.hourly_band_delta_up_values = [1.00 0.90 0.85 0.80 0.75 0.65];
cfg.delivery.hourly_band_delta_low_years = cfg.years;
cfg.delivery.hourly_band_delta_low_values = [1.00 1.00 0.95 0.90 0.80 0.70];
cfg.delivery.province_hourly_band = struct();
cfg.delivery.annual_energy_tolerance = 0.02;
cfg.delivery.annual_energy_tolerance_sensitivity = [0.05 0.02 0.01];
cfg.delivery.keep_shape_coverage_as_diagnostic = true;
cfg.delivery.enforce_shape_coverage_in_monthly_band = false;
% Fixed-target runs cannot contract the full raw potential because shaped
% delivery, storage losses, and the curtailment cap require headroom.
% Requested targets above this reduced-form deliverable-potential ceiling
% are explicitly flagged and truncated, never silently treated as achieved.
cfg.delivery.max_target_fraction_of_raw_potential = 0.65;
cfg.delivery.diagnostic_slack = false;
cfg.delivery.slack_cost_USD_per_MWh = 1e6;
cfg.delivery.slack_penalty = 1e6;
cfg.delivery.smooth_second_stage = true;
cfg.delivery.trend_diagnostic_enable = true;
cfg.delivery.trend_eps_MW = 1e-6;
cfg.delivery.use_tiny_curtailment_tiebreak = false;
cfg.delivery.tiny_curtailment_cost_USD_per_MWh = 0.1;

cfg.dispatch_smoothing = struct();
cfg.dispatch_smoothing.cost_tolerance_frac = 0.001;
cfg.dispatch_smoothing.weight_level_error = 1.0;
cfg.dispatch_smoothing.weight_slope_error = 0.1;
cfg.dispatch_smoothing.weight_curtailment_variation = 0.1;
cfg.dispatch_smoothing.cost_change_warning_frac = 0.0015;

cfg.dispatch_tiebreak = struct();
cfg.dispatch_tiebreak.enable = true;
cfg.dispatch_tiebreak.mode = "light";
cfg.dispatch_tiebreak.system_curtailment_cost_USD_per_MWh = 0.02;
cfg.dispatch_tiebreak.pdel_level_cost_USD_per_MWh = 0.02;
cfg.dispatch_tiebreak.pdel_delta_cost_USD_per_MW = 0.01;
cfg.dispatch_tiebreak.system_curtailment_delta_cost_USD_per_MW = 0.004;
cfg.dispatch_tiebreak.max_share_of_engineering_cost = 0.005;
cfg.dispatch_tiebreak.engineering_lcoe_delta_warning_frac = 0.01;
cfg.dispatch_tiebreak.compare_no_tiebreak = false;

cfg.project_bess = struct();
cfg.project_bess.mode = "ramp_lp";
cfg.project_bess.duration_h = 2;
cfg.project_bess.package_names = "Ramp2h";
cfg.project_bess.ramp_mode = "quantile";
cfg.project_bess.ramp_quantile = 0.95;
cfg.project_bess.ramp_scope = "province";
cfg.project_bess.ramp_rate_per_hour = 0.02;
cfg.project_bess.daily_closure_h = 24;
cfg.project_bess.max_cycles_per_day = 1.0;
cfg.project_bess.ramp_slack_penalty = 1e7;
cfg.project_bess.flow_penalty = 1e-3;
cfg.project_bess.ramp_cache_enable = true;
cfg.project_bess.ramp_cache_dir = fullfile(cfg.output_root, 'cache_project_ramp_profiles');
cfg.project_bess.smoothing_version = "ramp_lp_v2_prescreen_cachekey";

cfg.packages = struct();
cfg.packages.pre_screen_before_ramp = true;
cfg.packages.pre_screen_max_packages = 300;

cfg.storage = struct();
cfg.storage.discount_rate = 0.07;
cfg.storage.bess = struct( ...
    'power_capex_2025_USD_per_MW', 150000, ...
    'energy_capex_2025_USD_per_MWh', 120000, ...
    'FOM_USD_per_MWyr', 2500, ...
    'VOM_USD_per_MWh', 0.5, ...
    'eta_ch', sqrt(0.90), 'eta_dis', sqrt(0.90), ...
    'duration_min_h', 2, 'duration_max_h', 4, 'closure_h', 24, 'life_year', 15);
cfg.storage.vrb = struct( ...
    'power_capex_2025_USD_per_MW', 200000, ...
    'energy_capex_2025_USD_per_MWh', 150000, ...
    'FOM_USD_per_MWyr', 20000, ...
    'energy_FOM_USD_per_MWhyr', 0, ...
    'VOM_USD_per_MWh', 1.5, ...
    'eta_ch', sqrt(0.75), 'eta_dis', sqrt(0.75), ...
    'duration_min_h', 6, 'duration_max_h', 72, 'closure_h', 72, 'life_year', 20);
cfg.storage.h2 = struct( ...
    'enabled', false, ...
    'electrolyzer_capex_2025_USD_per_MW', 800000, ...
    'storage_capex_2025_USD_per_MWh_H2', 25000, ...
    'generator_capex_2025_USD_per_MW', 800000, ...
    'electrolyzer_FOM_frac', 0.03, ...
    'storage_FOM_frac', 0.01, ...
    'generator_FOM_frac', 0.03, ...
    'VOM_USD_per_MWh_gen', 8, ...
    'eta_el', 0.70, 'eta_gen', 0.54, 'closure_h', 8760, 'life_year', 20);

cfg.p2h = struct();
cfg.p2h.enabled = false;
cfg.p2h.price_CNY_per_kg = 20;
cfg.p2h.logistics_CNY_per_kg = 3;
cfg.p2h.electricity_kWh_per_kg = 52.5;
cfg.p2h.FX_CNY_per_USD = 7.2;
cfg.p2h.market_cap_frac_of_target = 0.20;

cfg.h2_p2p = struct();
cfg.h2_p2p.start_year = 2035;
cfg.h2_p2p.min_duration_h = 720;
cfg.h2_p2p.enforce_min_charge_duration = true;
cfg.h2_p2p.enforce_min_discharge_duration = true;

cfg.learning = struct();
cfg.learning.case = "S0";
cfg.learning.theta_by_case = struct('S0',0,'S1',0,'S2',0.10,'S3',0.30,'S4',0.10);
cfg.learning.cost_floor_factor = 0.35;
cfg.learning.BESS = struct('LR',0.18,'Q0',160000, ...
    'external_years',cfg.years,'external_factors',rev04_bess_external_factors());
cfg.learning.VRB = struct('LR',0.12,'Q0',3000, ...
    'external_years',cfg.years,'external_factors',[1.00 0.97 0.94 0.90 0.87 0.85]);
cfg.learning.H2 = struct('LR',0.10,'Q0',1000, ...
    'external_years',cfg.years,'external_factors',[1.00 0.80 0.68 0.58 0.50 0.45]);
cfg.learning.component_Q0 = struct( ...
    'BESS_power_MW',40000,'BESS_energy_MWh',160000, ...
    'VRB_power_MW',500,'VRB_energy_MWh',3000, ...
    'H2_el_MW',1000,'H2_storage_MWh',100000,'H2_gen_MW',500);

cfg.screen = struct();
cfg.screen.max_sites_per_province = inf;
cfg.screen.min_capacity_MW = 1;
cfg.screen.sort_metric = "raw_wind_lcoe";
cfg.screen.max_packages_per_province_year = 200;
cfg.screen.max_packages_years = 2050;
cfg.screen.package_score_metric = "unit_engineering_cost";

cfg.solver = struct();
cfg.solver.name = "gurobi";
cfg.solver.output_flag = 0;
cfg.solver.threads = 4;
cfg.solver.time_limit_s = 600;
cfg.solver.feasibility_tol = 1e-7;
cfg.solver.optimality_tol = 1e-7;
cfg.solver.method = 2;       % Barrier is substantially faster for the hourly LP.
cfg.solver.crossover = 0;    % An interior solution is sufficient; residuals are checked explicitly.
cfg.solver.allow_suboptimal_with_x = true;

cfg.run = struct();
cfg.run.mode = "milestone_a";
cfg.run.save_results = true;
cfg.run.verbose = true;
cfg.run.acceptance_provinces = ["Guangxi","Guangdong"];
cfg.run.acceptance_years = [2025 2050];
cfg.run.max_system_storage_power_to_wind_ratio = 2.0;

cfg.frontier = struct();
cfg.frontier.thresholds_USD_per_MWh = [60 80 100 120 150];
cfg.frontier.years = [2030 2040 2050];
cfg.frontier.year = 2050; % compatibility alias
cfg.frontier.cases = ["S0","S2","S4"];

cfg.sensitivity = struct();
cfg.sensitivity.curtailment_caps = [0.05 0.10 0.15];
cfg.sensitivity.shape_coverage = [0.70 0.80 0.90];
cfg.sensitivity.year = 2050;
end

function f = rev04_bess_external_factors()
ev = [1.00 2.50 3.75 4.60 5.30 6.00];
theta = 0.5;
lr = 0.18;
b = -log2(1-lr);
f = (1 + theta .* (ev - 1)).^(-b);
end
