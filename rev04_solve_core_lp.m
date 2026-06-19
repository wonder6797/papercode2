function result = rev04_solve_core_lp(I, cfg, prov_name, year, cost, state, mode, threshold)
% Shared Rev04 hourly LP for fixed-target paths and greenfield cost frontiers.
% Power variables are MW, energy/capacity variables are MWh, annual costs are USD/yr.

if nargin < 6 || isempty(state), state = rev04_empty_asset_state(I); end
if nargin < 7 || isempty(mode), mode = "fixed_target"; end
if nargin < 8, threshold = NaN; end
mode = string(mode);
clock0 = tic;
prov_idx = find(I.prov_names == string(prov_name),1);
iy = find(I.years == year,1);
assert(~isempty(prov_idx) && ~isempty(iy),'Unknown province or year.');
is_frontier = mode == "frontier";
delivery_mode = "coverage";
if isfield(cfg.delivery,'mode')
    delivery_mode = string(cfg.delivery.mode);
end
assert(any(delivery_mode == ["coverage","monthly_band","hourly_band","monthly_hourly_band", ...
    "monthly_hourly_band_asymmetric","monthly_upper_smooth"]), ...
    'Unsupported delivery mode: %s', delivery_mode);
h2_start_year = -inf;
if isfield(cfg,'h2_p2p') && isfield(cfg.h2_p2p,'start_year')
    h2_start_year = cfg.h2_p2p.start_year;
end
h2_available = cfg.storage.h2.enabled && year >= h2_start_year;

package_clock = tic;
P = rev04_build_site_packages(I,cfg,prov_idx,year,cost,state.used_frac_by_site);
package_build_time_s = toc(package_clock);
logstage("packages");
assembly_clock = tic;
T = I.T;
D = squeeze(double(I.D_MW(prov_idx,iy,:)));
shape_unit = D / sum(D);
fixed_target = I.Etarget_MWh(prov_idx,iy);
fixed_profile = double(state.fixed_profile_MW(:));
annual_scale = max([fixed_target; state.fixed_raw_MWh+sum(P.raw_MWh); 1e6]);
cost_scale = 1e6;
hourly_band_delta_this_year = hourly_band_delta_for_year(year);
hourly_band_delta_up_this_year = hourly_band_delta_side_for_year(year, "up");
hourly_band_delta_low_this_year = hourly_band_delta_side_for_year(year, "low");
hourly_upper_delta_this_year = hourly_upper_delta_for_year(year);
monthly_mode = any(delivery_mode == ["monthly_band","monthly_hourly_band", ...
    "monthly_hourly_band_asymmetric","monthly_upper_smooth"]);
hourly_upper_enabled = any(delivery_mode == ["hourly_band","monthly_hourly_band", ...
    "monthly_hourly_band_asymmetric","monthly_upper_smooth"]);
hourly_lower_enabled = any(delivery_mode == ["hourly_band","monthly_hourly_band"]);
if delivery_mode == "monthly_hourly_band_asymmetric"
    hourly_lower_enabled = isfield(cfg.delivery,'enable_hourly_lower') && logical(cfg.delivery.enable_hourly_lower);
end
if delivery_mode == "monthly_upper_smooth"
    hourly_lower_enabled = false;
end
if delivery_mode == "monthly_upper_smooth"
    hourly_delta_up_used = hourly_upper_delta_this_year;
elseif delivery_mode == "monthly_hourly_band_asymmetric"
    hourly_delta_up_used = hourly_band_delta_up_this_year;
else
    hourly_delta_up_used = hourly_band_delta_this_year;
end
if delivery_mode == "monthly_hourly_band_asymmetric"
    hourly_delta_low_used = hourly_band_delta_low_this_year;
else
    hourly_delta_low_used = hourly_band_delta_this_year;
end
hourly_delta_low_report = hourly_delta_low_used;
hourly_lower_multiplier_report = 1-hourly_delta_low_used;
if ~hourly_lower_enabled
    hourly_delta_low_report = NaN;
    hourly_lower_multiplier_report = NaN;
end

dispatch_tiebreak_enable = false;
dispatch_tiebreak_mode = "off";
dispatch_tiebreak_cost_USD_per_MWh = 0;
dispatch_tiebreak_pdel_level_cost_USD_per_MWh = 0;
dispatch_tiebreak_pdel_delta_cost_USD_per_MW = 0;
dispatch_tiebreak_curt_delta_cost_USD_per_MW = 0;
dispatch_tiebreak_max_share = 0.005;
dispatch_tiebreak_lcoe_delta_warn_frac = 0.01;
if isfield(cfg,'dispatch_tiebreak')
    if isfield(cfg.dispatch_tiebreak,'enable')
        dispatch_tiebreak_enable = logical(cfg.dispatch_tiebreak.enable);
    end
    if isfield(cfg.dispatch_tiebreak,'mode')
        dispatch_tiebreak_mode = lower(string(cfg.dispatch_tiebreak.mode));
    elseif dispatch_tiebreak_enable
        dispatch_tiebreak_mode = "full";
    end
    if isfield(cfg.dispatch_tiebreak,'system_curtailment_cost_USD_per_MWh')
        dispatch_tiebreak_cost_USD_per_MWh = double(cfg.dispatch_tiebreak.system_curtailment_cost_USD_per_MWh);
    end
    if isfield(cfg.dispatch_tiebreak,'pdel_level_cost_USD_per_MWh')
        dispatch_tiebreak_pdel_level_cost_USD_per_MWh = double(cfg.dispatch_tiebreak.pdel_level_cost_USD_per_MWh);
    end
    if isfield(cfg.dispatch_tiebreak,'pdel_delta_cost_USD_per_MW')
        dispatch_tiebreak_pdel_delta_cost_USD_per_MW = double(cfg.dispatch_tiebreak.pdel_delta_cost_USD_per_MW);
    end
    if isfield(cfg.dispatch_tiebreak,'system_curtailment_delta_cost_USD_per_MW')
        dispatch_tiebreak_curt_delta_cost_USD_per_MW = double(cfg.dispatch_tiebreak.system_curtailment_delta_cost_USD_per_MW);
    end
    if isfield(cfg.dispatch_tiebreak,'max_share_of_engineering_cost')
        dispatch_tiebreak_max_share = double(cfg.dispatch_tiebreak.max_share_of_engineering_cost);
    end
    if isfield(cfg.dispatch_tiebreak,'engineering_lcoe_delta_warning_frac')
        dispatch_tiebreak_lcoe_delta_warn_frac = double(cfg.dispatch_tiebreak.engineering_lcoe_delta_warning_frac);
    end
end
if ~dispatch_tiebreak_enable
    dispatch_tiebreak_mode = "off";
end
assert(any(dispatch_tiebreak_mode == ["off","light","full"]), ...
    'dispatch_tiebreak.mode must be off, light, or full.');

cursor = 0;
idx.x = alloc(P.n);
idx.pdel = alloc(T); idx.credit = alloc(T); idx.curt = alloc(T);
idx.bch = alloc(T); idx.bdis = alloc(T); idx.bsoc = alloc(T); idx.bP = alloc(1); idx.bE = alloc(1);
idx.vch = alloc(T); idx.vdis = alloc(T); idx.vsoc = alloc(T); idx.vP = alloc(1); idx.vE = alloc(1);
idx.hel=[]; idx.hgen=[]; idx.hsoc=[]; idx.helP=[]; idx.hgenP=[]; idx.hE=[];
idx.p2h=[]; idx.p2hP=[]; idx.contract=[];
idx.slack_delivery=[]; idx.slack_credit=[]; idx.slack_excess=[]; idx.slack_curtail=[];
idx.slack_annual_low=[]; idx.slack_annual_high=[];
idx.slack_month_low=[]; idx.slack_month_high=[];
idx.slack_hour_low=[]; idx.slack_hour_high=[];
idx.tb_level=[]; idx.tb_delta=[]; idx.tb_curt_delta=[];
if h2_available
    idx.hel=alloc(T); idx.hgen=alloc(T); idx.hsoc=alloc(T);
    idx.helP=alloc(1); idx.hgenP=alloc(1); idx.hE=alloc(1);
end
if cfg.p2h.enabled
    idx.p2h=alloc(T); idx.p2hP=alloc(1);
end
if is_frontier
    idx.contract=alloc(1);
end
if dispatch_tiebreak_enable && dispatch_tiebreak_mode == "full"
    if dispatch_tiebreak_pdel_level_cost_USD_per_MWh > 0
        idx.tb_level=alloc(T);
    end
    if dispatch_tiebreak_pdel_delta_cost_USD_per_MW > 0
        idx.tb_delta=alloc(T-1);
    end
    if dispatch_tiebreak_curt_delta_cost_USD_per_MW > 0
        idx.tb_curt_delta=alloc(T-1);
    end
end
if cfg.delivery.diagnostic_slack
    idx.slack_delivery=alloc(1); idx.slack_credit=alloc(1);
    idx.slack_excess=alloc(1); idx.slack_curtail=alloc(1);
    if monthly_mode || delivery_mode == "hourly_band"
        idx.slack_annual_low=alloc(1); idx.slack_annual_high=alloc(1);
    end
    if monthly_mode
        idx.slack_month_low=alloc(12); idx.slack_month_high=alloc(12);
    end
    if hourly_lower_enabled, idx.slack_hour_low=alloc(T); end
    if hourly_upper_enabled, idx.slack_hour_high=alloc(T); end
end
nvar = cursor;
logstage("variables");

lb = zeros(nvar,1); ub = inf(nvar,1);
ub(idx.x) = 1;
if is_frontier
    ub(idx.contract) = state.fixed_raw_MWh + sum(P.raw_MWh);
end

f = zeros(nvar,1);
f(idx.x) = P.annual_cost_USDyr;
f(idx.bP) = cost.bess.power_annual_USD_per_MWyr;
f(idx.bE) = cost.bess.energy_annual_USD_per_MWhyr;
f(idx.bdis) = cost.bess.VOM_USD_per_MWh;
f(idx.vP) = cost.vrb.power_annual_USD_per_MWyr;
f(idx.vE) = cost.vrb.energy_annual_USD_per_MWhyr;
f(idx.vdis) = cost.vrb.VOM_USD_per_MWh;
if h2_available
    f(idx.helP)=cost.h2.electrolyzer_annual_USD_per_MWyr;
    f(idx.hgenP)=cost.h2.generator_annual_USD_per_MWyr;
    f(idx.hE)=cost.h2.storage_annual_USD_per_MWhyr;
    f(idx.hgen)=cost.h2.VOM_USD_per_MWh_gen;
end
p2h_revenue_USD_per_MWh = 0;
if cfg.p2h.enabled
    f(idx.p2hP)=cost.h2.electrolyzer_annual_USD_per_MWyr;
    p2h_revenue_USD_per_MWh = (1000/cfg.p2h.electricity_kWh_per_kg) * ...
        (cfg.p2h.price_CNY_per_kg-cfg.p2h.logistics_CNY_per_kg) / cfg.p2h.FX_CNY_per_USD;
    f(idx.p2h)=-p2h_revenue_USD_per_MWh;
end
if cfg.delivery.diagnostic_slack
    f([idx.slack_delivery idx.slack_credit idx.slack_excess idx.slack_curtail])=cfg.delivery.slack_cost_USD_per_MWh;
    if monthly_mode
        slack_penalty = cfg.delivery.slack_penalty;
        if ~isfield(cfg.delivery,'slack_penalty'), slack_penalty = cfg.delivery.slack_cost_USD_per_MWh; end
        f([idx.slack_annual_low idx.slack_annual_high idx.slack_month_low idx.slack_month_high]) = slack_penalty;
    end
    if hourly_lower_enabled || hourly_upper_enabled
        slack_penalty = cfg.delivery.slack_penalty;
        if ~isfield(cfg.delivery,'slack_penalty'), slack_penalty = cfg.delivery.slack_cost_USD_per_MWh; end
        f([idx.slack_hour_low idx.slack_hour_high]) = slack_penalty;
    end
end
f_engineering = f;
if cfg.delivery.diagnostic_slack
    f_engineering([idx.slack_delivery idx.slack_credit idx.slack_excess idx.slack_curtail ...
        idx.slack_annual_low idx.slack_annual_high idx.slack_month_low idx.slack_month_high ...
        idx.slack_hour_low idx.slack_hour_high]) = 0;
end
f_objective = f;
if dispatch_tiebreak_enable && dispatch_tiebreak_cost_USD_per_MWh > 0
    f_objective(idx.curt) = f_objective(idx.curt) + dispatch_tiebreak_cost_USD_per_MWh;
end
if ~isempty(idx.tb_level)
    f_objective(idx.tb_level) = dispatch_tiebreak_pdel_level_cost_USD_per_MWh;
end
if ~isempty(idx.tb_delta)
    f_objective(idx.tb_delta) = dispatch_tiebreak_pdel_delta_cost_USD_per_MW;
end
if ~isempty(idx.tb_curt_delta)
    f_objective(idx.tb_curt_delta) = dispatch_tiebreak_curt_delta_cost_USD_per_MW;
end
logstage("objective");

% Hourly electricity balance.
Aeq = sparse(T,nvar);
Aeq(:,idx.x) = -sparse(double(P.profile_MW));
Aeq(:,idx.pdel)=speye(T); Aeq(:,idx.curt)=speye(T);
Aeq(:,idx.bch)=speye(T); Aeq(:,idx.bdis)=-speye(T);
Aeq(:,idx.vch)=speye(T); Aeq(:,idx.vdis)=-speye(T);
if h2_available
    Aeq(:,idx.hel)=speye(T); Aeq(:,idx.hgen)=-speye(T);
end
if cfg.p2h.enabled
    Aeq(:,idx.p2h)=speye(T);
end
beq = fixed_profile;
logstage("balance");

% Annual cyclic storage inventories.
[Ab,bb] = block_soc(idx.bch,idx.bdis,idx.bsoc,cost.bess.eta_ch,cost.bess.eta_dis,cost.bess.closure_h);
[Av,bv] = block_soc(idx.vch,idx.vdis,idx.vsoc,cost.vrb.eta_ch,cost.vrb.eta_dis,cost.vrb.closure_h);
Aeq=[Aeq;Ab;Av]; beq=[beq;bb;bv];
if h2_available
    [Ah,bh] = block_soc(idx.hel,idx.hgen,idx.hsoc,cost.h2.eta_el,cost.h2.eta_gen,cost.h2.closure_h);
    Aeq=[Aeq;Ah]; beq=[beq;bh];
end
logstage("equalities");

A_blocks = {}; b_blocks = {};
% Credited delivery must be both physically delivered and under the shaped target.
R=sparse(T,nvar); R(:,idx.credit)=speye(T); R(:,idx.pdel)=-speye(T); append(R,zeros(T,1));
R=sparse(T,nvar); R(:,idx.credit)=speye(T);
if is_frontier
    R(:,idx.contract)=-shape_unit;
    append(R,zeros(T,1));
else
    append(R,shape_unit*fixed_target);
end

% Optional single-stage dispatch tie-breaks. These variables are excluded
% from engineering cost and LCOE; they only select a cleaner dispatch among
% otherwise near-equivalent LP optima.
if ~isempty(idx.tb_level)
    R=sparse(T,nvar); R(:,idx.pdel)=speye(T); R(:,idx.tb_level)=-speye(T);
    if is_frontier
        R(:,idx.contract)=-shape_unit;
        append(R,zeros(T,1));
    else
        append(R,shape_unit*fixed_target);
    end
    R=sparse(T,nvar); R(:,idx.pdel)=-speye(T); R(:,idx.tb_level)=-speye(T);
    if is_frontier
        R(:,idx.contract)=shape_unit;
        append(R,zeros(T,1));
    else
        append(R,-shape_unit*fixed_target);
    end
end
if ~isempty(idx.tb_delta)
    dshape_unit = diff(shape_unit);
    R=sparse(T-1,nvar);
    R(:,idx.pdel(2:end))=speye(T-1);
    R(:,idx.pdel(1:end-1))=R(:,idx.pdel(1:end-1))-speye(T-1);
    R(:,idx.tb_delta)=-speye(T-1);
    if is_frontier
        R(:,idx.contract)=-dshape_unit;
        append(R,zeros(T-1,1));
    else
        append(R,dshape_unit*fixed_target);
    end
    R=sparse(T-1,nvar);
    R(:,idx.pdel(2:end))=-speye(T-1);
    R(:,idx.pdel(1:end-1))=R(:,idx.pdel(1:end-1))+speye(T-1);
    R(:,idx.tb_delta)=-speye(T-1);
    if is_frontier
        R(:,idx.contract)=dshape_unit;
        append(R,zeros(T-1,1));
    else
        append(R,-dshape_unit*fixed_target);
    end
end
if ~isempty(idx.tb_curt_delta)
    R=sparse(T-1,nvar);
    R(:,idx.curt(2:end))=speye(T-1);
    R(:,idx.curt(1:end-1))=R(:,idx.curt(1:end-1))-speye(T-1);
    R(:,idx.tb_curt_delta)=-speye(T-1);
    append(R,zeros(T-1,1));
    R=sparse(T-1,nvar);
    R(:,idx.curt(2:end))=-speye(T-1);
    R(:,idx.curt(1:end-1))=R(:,idx.curt(1:end-1))+speye(T-1);
    R(:,idx.tb_curt_delta)=-speye(T-1);
    append(R,zeros(T-1,1));
end

% Storage charge/discharge power and energy bounds include existing assets.
storage_bounds(idx.bch,idx.bdis,idx.bsoc,idx.bP,idx.bE,state.bess.P_MW,state.bess.E_MWh, ...
    cost.bess.duration_min_h,cost.bess.duration_max_h);
storage_bounds(idx.vch,idx.vdis,idx.vsoc,idx.vP,idx.vE,state.vrb.P_MW,state.vrb.E_MWh, ...
    cost.vrb.duration_min_h,cost.vrb.duration_max_h);
if h2_available
    simple_cap(idx.hel,idx.helP,state.h2.el_P_MW);
    simple_cap(idx.hgen,idx.hgenP,state.h2.gen_P_MW);
    simple_cap(idx.hsoc,idx.hE,state.h2.store_MWh);
    if isfield(cfg,'h2_p2p') && isfield(cfg.h2_p2p,'min_duration_h')
        mh = cfg.h2_p2p.min_duration_h;
        if isfield(cfg.h2_p2p,'enforce_min_charge_duration') && cfg.h2_p2p.enforce_min_charge_duration
            row=sparse(1,nvar);
            row(idx.helP)=mh*cost.h2.eta_el;
            row(idx.hE)=-1;
            append(row,state.h2.store_MWh-mh*cost.h2.eta_el*state.h2.el_P_MW);
        end
        if isfield(cfg.h2_p2p,'enforce_min_discharge_duration') && cfg.h2_p2p.enforce_min_discharge_duration
            row=sparse(1,nvar);
            row(idx.hgenP)=mh;
            row(idx.hE)=-cost.h2.eta_gen;
            append(row,cost.h2.eta_gen*state.h2.store_MWh-mh*state.h2.gen_P_MW);
        end
    end
end
if cfg.p2h.enabled
    simple_cap(idx.p2h,idx.p2hP,0);
end
logstage("bounds");

% Mutually exclusive site/turbine/package development fractions.
for s = reshape(P.site_rows,1,[])
    row=sparse(1,nvar);
    row(idx.x(P.site_idx==s))=1;
    append(row,1-state.used_frac_by_site(s));
end

% Delivery-quality constraints.
if delivery_mode == "coverage"
    row=sparse(1,nvar); row(idx.pdel)=-1/annual_scale;
    if cfg.delivery.diagnostic_slack, row(idx.slack_delivery)=-1/annual_scale; end
    if is_frontier, row(idx.contract)=1/annual_scale; append(row,0); else, append(row,-fixed_target/annual_scale); end
    row=sparse(1,nvar); row(idx.pdel)=1/annual_scale;
    if cfg.delivery.diagnostic_slack, row(idx.slack_excess)=-1/annual_scale; end
    if is_frontier, row(idx.contract)=(-1-cfg.delivery.max_excess_frac)/annual_scale; append(row,0);
    else, append(row,(1+cfg.delivery.max_excess_frac)*fixed_target/annual_scale); end
    row=sparse(1,nvar); row(idx.credit)=-1/annual_scale;
    if cfg.delivery.diagnostic_slack, row(idx.slack_credit)=-1/annual_scale; end
    if is_frontier, row(idx.contract)=cfg.delivery.min_shape_coverage/annual_scale; append(row,0);
    else, append(row,-cfg.delivery.min_shape_coverage*fixed_target/annual_scale); end
elseif monthly_mode
    epsE = cfg.delivery.annual_energy_tolerance;
    deltaM = cfg.delivery.monthly_band_delta;
    month_id = month_index();

    % The smooth main product must deliver at least the annual target. Legacy
    % monthly modes retain their symmetric annual tolerance for compatibility.
    annual_lower_multiplier = 1-epsE;
    if delivery_mode == "monthly_upper_smooth"
        annual_lower_multiplier = 1;
    end
    row=sparse(1,nvar); row(idx.pdel)=-1/annual_scale;
    if cfg.delivery.diagnostic_slack, row(idx.slack_annual_low)=-1/annual_scale; end
    if is_frontier, row(idx.contract)=annual_lower_multiplier/annual_scale; append(row,0);
    else, append(row,-annual_lower_multiplier*fixed_target/annual_scale); end

    row=sparse(1,nvar); row(idx.pdel)=1/annual_scale;
    if cfg.delivery.diagnostic_slack, row(idx.slack_annual_high)=-1/annual_scale; end
    if is_frontier, row(idx.contract)=-(1+epsE)/annual_scale; append(row,0);
    else, append(row,(1+epsE)*fixed_target/annual_scale); end

    % Monthly shaped-delivery energy band.
    for mm = 1:12
        ixm = find(month_id == mm);
        shape_share_m = sum(shape_unit(ixm));

        row=sparse(1,nvar); row(idx.pdel(ixm))=-1/annual_scale;
        if cfg.delivery.diagnostic_slack, row(idx.slack_month_low(mm))=-1/annual_scale; end
        if is_frontier, row(idx.contract)=(1-deltaM)*shape_share_m/annual_scale; append(row,0);
        else, append(row,-(1-deltaM)*shape_share_m*fixed_target/annual_scale); end

        row=sparse(1,nvar); row(idx.pdel(ixm))=1/annual_scale;
        if cfg.delivery.diagnostic_slack, row(idx.slack_month_high(mm))=-1/annual_scale; end
        if is_frontier, row(idx.contract)=-(1+deltaM)*shape_share_m/annual_scale; append(row,0);
        else, append(row,(1+deltaM)*shape_share_m*fixed_target/annual_scale); end
    end

    % Keep shape coverage as a diagnostic by default; enforce only when requested.
    if isfield(cfg.delivery,'enforce_shape_coverage_in_monthly_band') && cfg.delivery.enforce_shape_coverage_in_monthly_band
        row=sparse(1,nvar); row(idx.credit)=-1/annual_scale;
        if cfg.delivery.diagnostic_slack, row(idx.slack_credit)=-1/annual_scale; end
        if is_frontier, row(idx.contract)=cfg.delivery.min_shape_coverage/annual_scale; append(row,0);
        else, append(row,-cfg.delivery.min_shape_coverage*fixed_target/annual_scale); end
    end

    if hourly_upper_enabled || hourly_lower_enabled
        deltaLow = hourly_delta_low_used;
        deltaUp = hourly_delta_up_used;
        hourly_scale = max(max(fixed_target*shape_unit),1);

        if hourly_lower_enabled
            R=sparse(T,nvar); R(:,idx.pdel)=-speye(T)/hourly_scale;
            if cfg.delivery.diagnostic_slack, R(:,idx.slack_hour_low)=-speye(T)/hourly_scale; end
            if is_frontier
                R(:,idx.contract)=(1-deltaLow)*shape_unit/hourly_scale;
                append(R,zeros(T,1));
            else
                append(R,-(1-deltaLow)*fixed_target*shape_unit/hourly_scale);
            end
        end

        if hourly_upper_enabled
            R=sparse(T,nvar); R(:,idx.pdel)=speye(T)/hourly_scale;
            if cfg.delivery.diagnostic_slack, R(:,idx.slack_hour_high)=-speye(T)/hourly_scale; end
            if is_frontier
                R(:,idx.contract)=-(1+deltaUp)*shape_unit/hourly_scale;
                append(R,zeros(T,1));
            else
                append(R,(1+deltaUp)*fixed_target*shape_unit/hourly_scale);
            end
        end
    end
elseif delivery_mode == "hourly_band"
    epsE = cfg.delivery.annual_energy_tolerance;
    deltaH = hourly_band_delta_this_year;
    hourly_scale = max(max(fixed_target*shape_unit),1);

    % Annual energy remains close to the contract target.
    row=sparse(1,nvar); row(idx.pdel)=-1/annual_scale;
    if cfg.delivery.diagnostic_slack, row(idx.slack_annual_low)=-1/annual_scale; end
    if is_frontier, row(idx.contract)=(1-epsE)/annual_scale; append(row,0);
    else, append(row,-(1-epsE)*fixed_target/annual_scale); end

    row=sparse(1,nvar); row(idx.pdel)=1/annual_scale;
    if cfg.delivery.diagnostic_slack, row(idx.slack_annual_high)=-1/annual_scale; end
    if is_frontier, row(idx.contract)=-(1+epsE)/annual_scale; append(row,0);
    else, append(row,(1+epsE)*fixed_target/annual_scale); end

    % Hourly shaped-delivery band: Pdel(t) within Pshape(t)*(1 +/- deltaH).
    R=sparse(T,nvar); R(:,idx.pdel)=-speye(T)/hourly_scale;
    if cfg.delivery.diagnostic_slack, R(:,idx.slack_hour_low)=-speye(T)/hourly_scale; end
    if is_frontier
        R(:,idx.contract)=(1-deltaH)*shape_unit/hourly_scale;
        append(R,zeros(T,1));
    else
        append(R,-(1-deltaH)*fixed_target*shape_unit/hourly_scale);
    end
    R=sparse(T,nvar); R(:,idx.pdel)=speye(T)/hourly_scale;
    if cfg.delivery.diagnostic_slack, R(:,idx.slack_hour_high)=-speye(T)/hourly_scale; end
    if is_frontier
        R(:,idx.contract)=-(1+deltaH)*shape_unit/hourly_scale;
        append(R,zeros(T,1));
    else
        append(R,(1+deltaH)*fixed_target*shape_unit/hourly_scale);
    end
end

row=sparse(1,nvar); row(idx.curt)=1/annual_scale;
row(idx.x)=(P.project_curt_MWh-cfg.delivery.max_curtailment_frac*P.raw_MWh)/annual_scale;
if cfg.delivery.diagnostic_slack, row(idx.slack_curtail)=-1/annual_scale; end
append(row,(cfg.delivery.max_curtailment_frac*state.fixed_raw_MWh-state.fixed_project_curt_MWh)/annual_scale);

if cfg.p2h.enabled
    row=sparse(1,nvar); row(idx.p2h)=1/annual_scale;
    if is_frontier, row(idx.contract)=-cfg.p2h.market_cap_frac_of_target/annual_scale; append(row,0);
    else, append(row,cfg.p2h.market_cap_frac_of_target*fixed_target/annual_scale); end
end
logstage("annual constraints");

fixed_cost = state.fixed_wind_annual_cost_USDyr + state.fixed_project_bess_annual_cost_USDyr + ...
    state.bess.annual_cost_USDyr + state.vrb.annual_cost_USDyr + state.h2.annual_cost_USDyr;
if is_frontier
    assert(isfinite(threshold),'Frontier threshold is required.');
    row=sparse(1,nvar); row(:)=f_engineering/cost_scale; row(idx.contract)=row(idx.contract)-threshold/cost_scale;
    append(row,-fixed_cost/cost_scale);
    % Economic-boundary objective is strictly maximum contract energy.
    % Engineering cost appears only in the threshold constraint.
    fsolve = zeros(nvar,1); fsolve(idx.contract)=-1;
else
    fsolve=f_objective/cost_scale;
end

A = vertcat(A_blocks{:});
b = vertcat(b_blocks{:});
lp_assembly_time_s = toc(assembly_clock);
logstage("assembled");
cfgsolve=cfg;
if is_frontier
    cfgsolve.solver.method=2;
    cfgsolve.solver.crossover=1;
end
solve_clock = tic;
[z,solver] = solve_lp(fsolve,A,b,Aeq,beq,lb,ub,cfgsolve);
if is_frontier && isempty(z)
    cfgsolve.solver.method=1;
    cfgsolve.solver.crossover=0;
    [z,solver] = solve_lp(fsolve,A,b,Aeq,beq,lb,ub,cfgsolve);
end
lp_solve_time_s = toc(solve_clock);
stage1_z = z;
stage1_solver = solver;
stage1_cost_USD = NaN;
stage2_cost_USD = NaN;
stage2_cost_change_frac = NaN;
stage2_status = "not_run";
stage2_used = false;
stage2_cost_warning = false;
stage2_solve_time_s = 0;
if ~isempty(stage1_z)
    stage1_cost_USD = fixed_cost + f_engineering(:)'*stage1_z(:);
end
if ~isempty(stage1_z) && ~is_frontier && isfield(cfg.delivery,'smooth_second_stage') && cfg.delivery.smooth_second_stage
    stage2_clock = tic;
    [z2,solver2] = solve_smooth_stage(stage1_z, stage1_cost_USD);
    stage2_solve_time_s = toc(stage2_clock);
    stage2_status = solver2.status;
    if ~isempty(z2)
        z2_main = z2(1:nvar);
        stage2_cost_USD = fixed_cost + f_engineering(:)'*z2_main(:);
        stage2_cost_change_frac = (stage2_cost_USD-stage1_cost_USD)/max(stage1_cost_USD,eps);
        stage2_cost_warning = stage2_cost_change_frac > cfg.dispatch_smoothing.cost_change_warning_frac;
        if stage2_cost_change_frac <= cfg.dispatch_smoothing.cost_tolerance_frac + 1e-7
            z = z2_main;
            stage2_used = true;
        end
        if stage2_cost_warning && cfg.run.verbose
            fprintf('[Stage2Warning] %s %d Stage2CostChangeFrac=%.6g > %.6g\n', ...
                char(prov_name),year,stage2_cost_change_frac,cfg.dispatch_smoothing.cost_change_warning_frac);
        end
    end
end
logstage("solved");
result = package_result(z,stage1_solver);

    function r=alloc(n)
        r=(cursor+1):(cursor+n); cursor=cursor+n;
    end
    function logstage(label)
        if cfg.run.verbose
            fprintf('Rev04 %s %d: %s %.2fs\n',char(prov_name),year,label,toc(clock0));
        end
    end
    function append(R,rhs)
        A_blocks{end+1,1}=R;
        b_blocks{end+1,1}=rhs;
    end
    function m = month_index()
        if isfield(I,'month_id')
            m = double(I.month_id(:));
        else
            m = month((datetime(2025,1,1,0,0,0) + hours(0:(T-1)))');
        end
    end
    function [z2,sol2] = solve_smooth_stage(z1, cstar)
        z2 = [];
        sol2 = struct('name',"smooth_stage",'status',"not_run");
        if isempty(z1) || ~isfinite(cstar)
            sol2.status = "skipped_no_stage1";
            return
        end
        pshape = fixed_target * shape_unit;
        n_level = T;
        n_delta = T-1;
        n_curt_delta = T-1;
        off = nvar;
        id_level = (off+1):(off+n_level); off = off+n_level;
        id_delta = (off+1):(off+n_delta); off = off+n_delta;
        id_curt_delta = (off+1):(off+n_curt_delta); off = off+n_curt_delta;
        n2 = off;

        A2 = [A sparse(size(A,1), n2-nvar)];
        Aeq2 = [Aeq sparse(size(Aeq,1), n2-nvar)];
        b2 = b;
        beq2 = beq;
        lb2 = [lb; zeros(n2-nvar,1)];
        ub2 = [ub; inf(n2-nvar,1)];
        f2 = zeros(n2,1);
        f2(id_level) = cfg.dispatch_smoothing.weight_level_error;
        f2(id_delta) = cfg.dispatch_smoothing.weight_slope_error;
        f2(id_curt_delta) = cfg.dispatch_smoothing.weight_curtailment_variation;

        % Stage 2 is lexicographic: the cap is engineering cost only. Neither
        % the tie-break objective nor the smoothing objective enters LCOE.
        row = sparse(1,n2);
        row(1:nvar) = f_engineering(:)'/cost_scale;
        rhs = ((1+cfg.dispatch_smoothing.cost_tolerance_frac)*cstar - fixed_cost)/cost_scale;
        A2 = [A2; row]; b2 = [b2; rhs]; %#ok<AGROW>

        % Absolute hourly level mismatch.
        R = sparse(T,n2);
        R(:,idx.pdel) = speye(T);
        R(:,id_level) = -speye(T);
        A2 = [A2; R]; b2 = [b2; pshape]; %#ok<AGROW>
        R = sparse(T,n2);
        R(:,idx.pdel) = -speye(T);
        R(:,id_level) = -speye(T);
        A2 = [A2; R]; b2 = [b2; -pshape]; %#ok<AGROW>

        % Absolute difference between delivery ramp and shape ramp.
        dshape = diff(pshape);
        R = sparse(n_delta,n2);
        R(:,idx.pdel(2:end)) = speye(n_delta);
        R(:,idx.pdel(1:end-1)) = R(:,idx.pdel(1:end-1)) - speye(n_delta);
        R(:,id_delta) = -speye(n_delta);
        A2 = [A2; R]; b2 = [b2; dshape]; %#ok<AGROW>
        R = sparse(n_delta,n2);
        R(:,idx.pdel(2:end)) = -speye(n_delta);
        R(:,idx.pdel(1:end-1)) = R(:,idx.pdel(1:end-1)) + speye(n_delta);
        R(:,id_delta) = -speye(n_delta);
        A2 = [A2; R]; b2 = [b2; -dshape]; %#ok<AGROW>

        % Absolute system-curtailment variation.
        R = sparse(n_curt_delta,n2);
        R(:,idx.curt(2:end)) = speye(n_curt_delta);
        R(:,idx.curt(1:end-1)) = R(:,idx.curt(1:end-1)) - speye(n_curt_delta);
        R(:,id_curt_delta) = -speye(n_curt_delta);
        A2 = [A2; R]; b2 = [b2; zeros(n_curt_delta,1)]; %#ok<AGROW>
        R = sparse(n_curt_delta,n2);
        R(:,idx.curt(2:end)) = -speye(n_curt_delta);
        R(:,idx.curt(1:end-1)) = R(:,idx.curt(1:end-1)) + speye(n_curt_delta);
        R(:,id_curt_delta) = -speye(n_curt_delta);
        A2 = [A2; R]; b2 = [b2; zeros(n_curt_delta,1)]; %#ok<AGROW>

        cfg2 = cfgsolve;
        cfg2.solver.method = 2;
        cfg2.solver.crossover = 0;
        [z2,sol2] = solve_lp(f2,A2,b2,Aeq2,beq2,lb2,ub2,cfg2);
        sol2.stage = "smooth_second_stage";
    end
    function [R,rhs]=block_soc(ch,dis,soc,eta_ch,eta_dis,closure_h)
        R=sparse(T,nvar); rhs=zeros(T,1);
        R(:,soc)=speye(T); R(:,ch)=-eta_ch*speye(T); R(:,dis)=(1/eta_dis)*speye(T);
        prev=zeros(T,1);
        for bs=1:closure_h:T
            be=min(T,bs+closure_h-1);
            prev(bs)=be;
            if be>bs, prev(bs+1:be)=(bs:be-1)'; end
        end
        R(:,soc)=R(:,soc)-sparse(1:T,prev,ones(T,1),T,T);
    end
    function storage_bounds(ch,dis,soc,padd,eadd,p0,e0,dmin,dmax)
        R=sparse(T,nvar); R(:,ch)=speye(T); R(:,padd)=-ones(T,1); append(R,p0*ones(T,1));
        R=sparse(T,nvar); R(:,dis)=speye(T); R(:,padd)=-ones(T,1); append(R,p0*ones(T,1));
        R=sparse(T,nvar); R(:,soc)=speye(T); R(:,eadd)=-ones(T,1); append(R,e0*ones(T,1));
        row=sparse(1,nvar); row(padd)=dmin; row(eadd)=-1; append(row,e0-dmin*p0);
        row=sparse(1,nvar); row(eadd)=1; row(padd)=-dmax; append(row,dmax*p0-e0);
    end
    function simple_cap(flow,capadd,cap0)
        R=sparse(T,nvar); R(:,flow)=speye(T); R(:,capadd)=-ones(T,1); append(R,cap0*ones(T,1));
    end
    function out=package_result(zv,sol)
        out=struct(); out.solver=sol; out.mode=mode; out.province=string(prov_name); out.year=year;
        if isempty(zv), out.feasible=false; return; end
        out.feasible=true; out.x=zv(idx.x); out.packages=P; out.h2_available=h2_available;
        out.delivery_mode=delivery_mode;
        out.Pdel_MW=zv(idx.pdel); out.Pcredit_MW=zv(idx.credit); out.system_curt_MW=zv(idx.curt);
        out.bess=struct('charge_MW',zv(idx.bch),'discharge_MW',zv(idx.bdis),'soc_MWh',zv(idx.bsoc), ...
            'P_add_MW',zv(idx.bP),'E_add_MWh',zv(idx.bE),'P_total_MW',state.bess.P_MW+zv(idx.bP), ...
            'E_total_MWh',state.bess.E_MWh+zv(idx.bE));
        out.vrb=struct('charge_MW',zv(idx.vch),'discharge_MW',zv(idx.vdis),'soc_MWh',zv(idx.vsoc), ...
            'P_add_MW',zv(idx.vP),'E_add_MWh',zv(idx.vE),'P_total_MW',state.vrb.P_MW+zv(idx.vP), ...
            'E_total_MWh',state.vrb.E_MWh+zv(idx.vE));
        out.h2=struct('el_MW',zeros(T,1),'gen_MW',zeros(T,1),'soc_MWh',zeros(T,1), ...
            'el_P_add_MW',0,'gen_P_add_MW',0,'store_add_MWh',0, ...
            'el_P_total_MW',state.h2.el_P_MW,'gen_P_total_MW',state.h2.gen_P_MW,'store_total_MWh',state.h2.store_MWh);
        if h2_available
            out.h2=struct('el_MW',zv(idx.hel),'gen_MW',zv(idx.hgen),'soc_MWh',zv(idx.hsoc), ...
                'el_P_add_MW',zv(idx.helP),'gen_P_add_MW',zv(idx.hgenP),'store_add_MWh',zv(idx.hE), ...
                'el_P_total_MW',state.h2.el_P_MW+zv(idx.helP), ...
                'gen_P_total_MW',state.h2.gen_P_MW+zv(idx.hgenP), ...
                'store_total_MWh',state.h2.store_MWh+zv(idx.hE));
        end
        out.p2h=struct('input_MW',zeros(T,1),'P_add_MW',0,'revenue_USDyr',0);
        if cfg.p2h.enabled
            out.p2h=struct('input_MW',zv(idx.p2h),'P_add_MW',zv(idx.p2hP), ...
                'revenue_USDyr',sum(zv(idx.p2h))*p2h_revenue_USD_per_MWh);
        end
        if is_frontier, out.Econtract_MWh=zv(idx.contract); else, out.Econtract_MWh=fixed_target; end
        out.Pshape_MW=out.Econtract_MWh * shape_unit;
        out.stage1=struct('Pdel_MW',zeros(T,1),'Pcredit_MW',zeros(T,1), ...
            'SystemCurtailment_MW',zeros(T,1), ...
            'BESSCharge_MW',zeros(T,1),'BESSDischarge_MW',zeros(T,1),'BESSSOC_MWh',zeros(T,1), ...
            'VRBCharge_MW',zeros(T,1),'VRBDischarge_MW',zeros(T,1),'VRBSOC_MWh',zeros(T,1), ...
            'H2Input_MW',zeros(T,1),'H2Output_MW',zeros(T,1),'H2SOC_MWh',zeros(T,1), ...
            'Cost_USD',stage1_cost_USD,'SolverStatus',"not_run");
        if ~isempty(stage1_z)
            out.stage1.Pdel_MW=stage1_z(idx.pdel);
            out.stage1.Pcredit_MW=stage1_z(idx.credit);
            out.stage1.SystemCurtailment_MW=stage1_z(idx.curt);
            out.stage1.BESSCharge_MW=stage1_z(idx.bch);
            out.stage1.BESSDischarge_MW=stage1_z(idx.bdis);
            out.stage1.BESSSOC_MWh=stage1_z(idx.bsoc);
            out.stage1.VRBCharge_MW=stage1_z(idx.vch);
            out.stage1.VRBDischarge_MW=stage1_z(idx.vdis);
            out.stage1.VRBSOC_MWh=stage1_z(idx.vsoc);
            if h2_available
                out.stage1.H2Input_MW=stage1_z(idx.hel);
                out.stage1.H2Output_MW=stage1_z(idx.hgen);
                out.stage1.H2SOC_MWh=stage1_z(idx.hsoc);
            end
            out.stage1.SolverStatus=stage1_solver.status;
        end
        out.wind_cap_add_MW=P.cap_MW'*out.x;
        out.wind_cap_total_MW=state.fixed_wind_cap_MW+out.wind_cap_add_MW;
        out.raw_wind_profile_MW=state.fixed_raw_profile_MW+double(P.raw_profile_MW)*out.x;
        out.project_output_profile_MW=fixed_profile+double(P.profile_MW)*out.x;
        out.project_bess_P_add_MW=P.project_bess_P_MW'*out.x;
        out.project_bess_E_add_MWh=P.project_bess_E_MWh'*out.x;
        out.raw_wind_MWh=state.fixed_raw_MWh+P.raw_MWh'*out.x;
        out.project_curt_MWh=state.fixed_project_curt_MWh+P.project_curt_MWh'*out.x;
        out.system_curt_MWh=sum(out.system_curt_MW);
        out.total_curt_MWh=out.project_curt_MWh+out.system_curt_MWh;
        out.delivery_MWh=sum(out.Pdel_MW); out.credit_MWh=sum(out.Pcredit_MW);
        out.shape_coverage=out.credit_MWh/max(out.Econtract_MWh,eps);
        out.curtailment_rate=out.total_curt_MWh/max(out.raw_wind_MWh,eps);
        zecon = stage1_z;
        if isempty(zecon), zecon = zv; end
        C=struct();
        C.wind=state.fixed_wind_annual_cost_USDyr+P.wind_annual_cost_USDyr'*zecon(idx.x);
        C.project_bess=state.fixed_project_bess_annual_cost_USDyr+P.project_bess_annual_cost_USDyr'*zecon(idx.x);
        C.system_bess=state.bess.annual_cost_USDyr+zecon(idx.bP)*cost.bess.power_annual_USD_per_MWyr+zecon(idx.bE)*cost.bess.energy_annual_USD_per_MWhyr;
        C.vrb=state.vrb.annual_cost_USDyr+zecon(idx.vP)*cost.vrb.power_annual_USD_per_MWyr+zecon(idx.vE)*cost.vrb.energy_annual_USD_per_MWhyr;
        C.h2=state.h2.annual_cost_USDyr;
        if h2_available
            C.h2=C.h2+zecon(idx.helP)*cost.h2.electrolyzer_annual_USD_per_MWyr+zecon(idx.hgenP)*cost.h2.generator_annual_USD_per_MWyr+zecon(idx.hE)*cost.h2.storage_annual_USD_per_MWhyr;
        end
        if cfg.p2h.enabled, C.h2=C.h2+zecon(idx.p2hP)*cost.h2.electrolyzer_annual_USD_per_MWyr; end
        C.operation=sum(zecon(idx.bdis))*cost.bess.VOM_USD_per_MWh+sum(zecon(idx.vdis))*cost.vrb.VOM_USD_per_MWh;
        if h2_available, C.operation=C.operation+sum(zecon(idx.hgen))*cost.h2.VOM_USD_per_MWh_gen; end
        C.gross_total=C.wind+C.project_bess+C.system_bess+C.vrb+C.h2+C.operation;
        C.p2h_revenue=0;
        if cfg.p2h.enabled, C.p2h_revenue=sum(zecon(idx.p2h))*p2h_revenue_USD_per_MWh; end
        C.net_total=C.gross_total-C.p2h_revenue;
        C.tiebreak_system_curtailment=0;
        C.tiebreak_pdel_level=0;
        C.tiebreak_pdel_delta=0;
        C.tiebreak_system_curtailment_delta=0;
        if dispatch_tiebreak_enable && dispatch_tiebreak_cost_USD_per_MWh > 0
            C.tiebreak_system_curtailment=sum(zecon(idx.curt))*dispatch_tiebreak_cost_USD_per_MWh;
        end
        if ~isempty(idx.tb_level)
            C.tiebreak_pdel_level=sum(zecon(idx.tb_level))*dispatch_tiebreak_pdel_level_cost_USD_per_MWh;
        end
        if ~isempty(idx.tb_delta)
            C.tiebreak_pdel_delta=sum(zecon(idx.tb_delta))*dispatch_tiebreak_pdel_delta_cost_USD_per_MW;
        end
        if ~isempty(idx.tb_curt_delta)
            C.tiebreak_system_curtailment_delta=sum(zecon(idx.tb_curt_delta))*dispatch_tiebreak_curt_delta_cost_USD_per_MW;
        end
        C.tiebreak=C.tiebreak_system_curtailment+C.tiebreak_pdel_level+ ...
            C.tiebreak_pdel_delta+C.tiebreak_system_curtailment_delta;
        C.identity_residual=C.gross_total-(C.wind+C.project_bess+C.system_bess+C.vrb+C.h2+C.operation);
        out.cost=C;
        out.LCOE_contract_USD_per_MWh=C.net_total/max(out.Econtract_MWh,eps);
        out.LCOE_delivered_USD_per_MWh=C.net_total/max(sum(zecon(idx.pdel)),eps);
        out.engineering_LCOE_USD_per_MWh=out.LCOE_contract_USD_per_MWh;
        out.EngineeringLCOEDenominator="Econtract_MWh";
        out.h2.CostStock_USDyr=state.h2.annual_cost_USDyr;
        out.h2.CostNew_USDyr=C.h2-state.h2.annual_cost_USDyr;
        out.h2.Input_MWh=sum(out.h2.el_MW);
        out.h2.Output_MWh=sum(out.h2.gen_MW);
        out.h2.ChargeFillHours_total=NaN;
        out.h2.DischargeHours_total=NaN;
        if out.h2.el_P_total_MW>1e-9
            out.h2.ChargeFillHours_total=out.h2.store_total_MWh/(cost.h2.eta_el*out.h2.el_P_total_MW);
        end
        if out.h2.gen_P_total_MW>1e-9
            out.h2.DischargeHours_total=out.h2.store_total_MWh*cost.h2.eta_gen/out.h2.gen_P_total_MW;
        end
        tiebreak_share = C.tiebreak/max(abs(C.net_total),eps);
        tiebreak_share_warning = dispatch_tiebreak_enable && tiebreak_share > dispatch_tiebreak_max_share;
        out.dispatch_tiebreak=struct('enabled',dispatch_tiebreak_enable, ...
            'mode',dispatch_tiebreak_mode, ...
            'system_curtailment_cost_USD_per_MWh',dispatch_tiebreak_cost_USD_per_MWh, ...
            'pdel_level_cost_USD_per_MWh',dispatch_tiebreak_pdel_level_cost_USD_per_MWh, ...
            'pdel_delta_cost_USD_per_MW',dispatch_tiebreak_pdel_delta_cost_USD_per_MW, ...
            'system_curtailment_delta_cost_USD_per_MW',dispatch_tiebreak_curt_delta_cost_USD_per_MW, ...
            'C_tiebreak_USD',C.tiebreak, ...
            'C_tiebreak_system_curtailment_USD',C.tiebreak_system_curtailment, ...
            'C_tiebreak_pdel_level_USD',C.tiebreak_pdel_level, ...
            'C_tiebreak_pdel_delta_USD',C.tiebreak_pdel_delta, ...
            'C_tiebreak_system_curtailment_delta_USD',C.tiebreak_system_curtailment_delta, ...
            'share_of_engineering_cost',tiebreak_share, ...
            'max_share_of_engineering_cost',dispatch_tiebreak_max_share, ...
            'share_warning',tiebreak_share_warning, ...
            'engineering_lcoe_no_tiebreak_USD_per_MWh',NaN, ...
            'engineering_lcoe_delta_vs_no_tiebreak_frac',NaN, ...
            'engineering_lcoe_delta_warning_frac',dispatch_tiebreak_lcoe_delta_warn_frac, ...
            'engineering_lcoe_delta_warning',false);
        if tiebreak_share_warning && cfg.run.verbose
            fprintf('[DispatchTiebreakWarning] %s %d C_tiebreak/C_engineering = %.4g > %.4g\n', ...
                char(prov_name),year,tiebreak_share,dispatch_tiebreak_max_share);
        end
        out.cost_params=struct('VRB_E_CAPEX_USD_per_MWh',cost.vrb.energy_capex_USD_per_MWh, ...
            'BESS_E_CAPEX_USD_per_MWh',cost.bess.energy_capex_USD_per_MWh, ...
            'H2_storage_CAPEX_USD_per_MWh',cost.h2.storage_capex_USD_per_MWh_H2, ...
            'ProjectRampMode',string(cfg.project_bess.ramp_mode), ...
            'ProjectRampQuantile',cfg.project_bess.ramp_quantile, ...
            'ProjectBESSDuration_h',cfg.project_bess.duration_h, ...
            'HourlyBandDelta',hourly_band_delta_this_year, ...
            'HourlyBandDeltaUp',hourly_band_delta_up_this_year, ...
            'HourlyBandDeltaLow',hourly_band_delta_low_this_year, ...
            'HourlyUpperDeltaUsed',hourly_delta_up_used, ...
            'HourlyUpperMultiplier',1+hourly_delta_up_used, ...
            'EnableHourlyLower',hourly_lower_enabled, ...
            'HourlyLowerDeltaUsed',hourly_delta_low_report, ...
            'HourlyLowerMultiplier',hourly_lower_multiplier_report, ...
            'MonthlyBandDelta',cfg.delivery.monthly_band_delta, ...
            'H2P2PStartYear',h2_start_year);
        out.diagnostic_slack_MWh=struct('delivery',0,'credit',0,'excess',0,'curtailment',0, ...
            'annual_low',0,'annual_high',0,'month_low',zeros(12,1),'month_high',zeros(12,1), ...
            'hour_low',zeros(T,1),'hour_high',zeros(T,1));
        if cfg.delivery.diagnostic_slack
            out.diagnostic_slack_MWh.delivery=zv(idx.slack_delivery);
            out.diagnostic_slack_MWh.credit=zv(idx.slack_credit);
            out.diagnostic_slack_MWh.excess=zv(idx.slack_excess);
            out.diagnostic_slack_MWh.curtailment=zv(idx.slack_curtail);
            if monthly_mode
                out.diagnostic_slack_MWh.annual_low=zv(idx.slack_annual_low);
                out.diagnostic_slack_MWh.annual_high=zv(idx.slack_annual_high);
                out.diagnostic_slack_MWh.month_low=zv(idx.slack_month_low);
                out.diagnostic_slack_MWh.month_high=zv(idx.slack_month_high);
            end
            if hourly_lower_enabled, out.diagnostic_slack_MWh.hour_low=zv(idx.slack_hour_low); end
            if hourly_upper_enabled, out.diagnostic_slack_MWh.hour_high=zv(idx.slack_hour_high); end
        end
        out.monthly_delivery=monthly_delivery_table(out);
        out.hourly_delivery=hourly_delivery_table(out);
        sm=smooth_metrics(out.Pdel_MW,out.system_curt_MW,out.Pshape_MW);
        sm.stage1=smooth_metrics(out.stage1.Pdel_MW,out.stage1.SystemCurtailment_MW,out.Pshape_MW);
        sm.stage2=smooth_metrics(out.Pdel_MW,out.system_curt_MW,out.Pshape_MW);
        sm.smooth_second_stage_enabled=isfield(cfg.delivery,'smooth_second_stage') && cfg.delivery.smooth_second_stage;
        sm.stage1_cost_USD=stage1_cost_USD;
        sm.stage2_cost_USD=stage2_cost_USD;
        sm.stage2_cost_change_frac=stage2_cost_change_frac;
        sm.stage2_status=stage2_status;
        sm.stage2_used=stage2_used;
        sm.stage2_cost_warning=stage2_cost_warning;
        sm.stage2_solve_time_s=stage2_solve_time_s;
        out.smooth=sm;
        out.max_eq_residual=max(abs(Aeq*zv-beq));
        out.max_ineq_residual=max([0;A*zv-b]);
        out.Edel_to_Etarget=out.delivery_MWh/max(out.Econtract_MWh,eps);
        annual_tol=cfg.delivery.annual_energy_tolerance;
        annual_lower=1-annual_tol;
        if delivery_mode=="monthly_upper_smooth", annual_lower=1; end
        bind_tol=max(1e-5,1e-6*max(1,out.Econtract_MWh));
        out.AnnualLowerBinding=abs(out.delivery_MWh-annual_lower*out.Econtract_MWh)<=bind_tol;
        out.AnnualUpperBinding=abs(out.delivery_MWh-(1+annual_tol)*out.Econtract_MWh)<=bind_tol;
        out.MonthlyBandBindingMonthsLow=nnz(out.monthly_delivery.binding_low);
        out.MonthlyBandBindingMonthsHigh=nnz(out.monthly_delivery.binding_high);
        out.MonthlyBandMaxLowViolation_MWh=max(out.monthly_delivery.violation_low_MWh);
        out.MonthlyBandMaxHighViolation_MWh=max(out.monthly_delivery.violation_high_MWh);
        out.UpperBandBindingHours=nnz(out.hourly_delivery.binding_high);
        out.LowerBandBindingHours=nnz(out.hourly_delivery.binding_low);
        out.performance=struct('PackageBuildTime_s',package_build_time_s, ...
            'LP_assembly_time_s',lp_assembly_time_s,'LP_solve_time_s',lp_solve_time_s, ...
            'LP_nvar',nvar,'LP_neq',size(Aeq,1),'LP_nineq',size(A,1), ...
            'LP_nnz',nnz(A)+nnz(Aeq));
        cache_fields={'RampCacheHit','RampCacheMiss','RampCacheNewFiles','RampCacheReusedFiles', ...
            'ProjectRampProfileCalls','ProjectRampProfileTime_s'};
        for kk=1:numel(cache_fields)
            nm=cache_fields{kk}; out.performance.(nm)=0;
            if isfield(P,nm), out.performance.(nm)=P.(nm); end
        end
        out.solver_runtime_s=get_solver_field(stage1_solver,'runtime_s',lp_solve_time_s);
        out.solver_attempt_count=get_solver_field(stage1_solver,'attempt_count',1);
        out.solver_method_used=get_solver_field(stage1_solver,'method',NaN);
        out.solver_crossover_used=get_solver_field(stage1_solver,'crossover',NaN);
        out.accepted_suboptimal_flag=logical(get_solver_field(stage1_solver,'accepted_suboptimal',false));
    end
    function Tmon = monthly_delivery_table(out)
        mid = month_index();
        deltaM = cfg.delivery.monthly_band_delta;
        ml = zeros(12,1); mh = zeros(12,1);
        if isfield(out,'diagnostic_slack_MWh')
            ml = out.diagnostic_slack_MWh.month_low(:);
            mh = out.diagnostic_slack_MWh.month_high(:);
        end
        rows = struct([]);
        for mm = 1:12
            ixm = find(mid == mm);
            eshape = sum(out.Pshape_MW(ixm));
            edel = sum(out.Pdel_MW(ixm));
            lower = (1-deltaM)*eshape;
            upper = (1+deltaM)*eshape;
            tol = max(1e-5, 1e-6*max(1,eshape));
            rows(mm).province = out.province;
            rows(mm).scenario = "";
            rows(mm).year = out.year;
            rows(mm).month = mm;
            rows(mm).Eshape_month_MWh = eshape;
            rows(mm).Edel_month_MWh = edel;
            rows(mm).lower_bound_MWh = lower;
            rows(mm).upper_bound_MWh = upper;
            rows(mm).binding_low = abs(edel + ml(mm) - lower) <= tol;
            rows(mm).binding_high = abs(edel - mh(mm) - upper) <= tol;
            rows(mm).slack_low_MWh = ml(mm);
            rows(mm).slack_high_MWh = mh(mm);
            rows(mm).band_ratio = edel / max(eshape,eps);
            rows(mm).violation_low_MWh = max(0,lower-edel-ml(mm));
            rows(mm).violation_high_MWh = max(0,edel-upper-mh(mm));
        end
        Tmon = struct2table(rows);
    end
    function Th = hourly_delivery_table(out)
        mid = month_index();
        deltaLow = hourly_delta_low_report;
        deltaUp = hourly_delta_up_used;
        pshape = out.Pshape_MW(:);
        pdel = out.Pdel_MW(:);
        low = nan(T,1);
        high = nan(T,1);
        if hourly_lower_enabled, low = (1-deltaLow) * pshape; end
        if hourly_upper_enabled, high = (1+deltaUp) * pshape; end
        slackLow = zeros(T,1);
        slackHigh = zeros(T,1);
        if isfield(out,'diagnostic_slack_MWh')
            slackLow = out.diagnostic_slack_MWh.hour_low(:);
            slackHigh = out.diagnostic_slack_MWh.hour_high(:);
        end
        violLow = zeros(T,1); violHigh = zeros(T,1);
        bindingLow = false(T,1); bindingHigh = false(T,1);
        if hourly_lower_enabled
            violLow = max(0, low - pdel - slackLow);
            tolLow=max(1e-6,1e-6*max(1,max(low)));
            bindingLow=abs(pdel+slackLow-low)<=tolLow;
        end
        if hourly_upper_enabled
            violHigh = max(0, pdel - high - slackHigh);
            tolHigh=max(1e-6,1e-6*max(1,max(high)));
            bindingHigh=abs(pdel-slackHigh-high)<=tolHigh;
        end
        Th = table((1:T)', mid(:), pshape, pdel, ...
            repmat(deltaLow,T,1), repmat(deltaUp,T,1), low, high, ...
            slackLow, slackHigh, violLow, violHigh,bindingLow,bindingHigh, ...
            'VariableNames',{'hour','month','Pshape_MW','Pdel_MW', ...
            'hourly_delta_low','hourly_delta_up','hourly_lower_MW','hourly_upper_MW', ...
            'slack_low_MW','slack_high_MW','violation_low_MW','violation_high_MW', ...
            'binding_low','binding_high'});
    end
    function sm = smooth_metrics(pdel,curt,pshape)
        dp = diff(pdel(:));
        ds = diff(pshape(:));
        dc = diff(curt(:));
        trend_eps = cfg.delivery.trend_eps_MW;
        valid = abs(ds) >= trend_eps;
        prod = ds(valid).*dp(valid);
        same = nnz(prod > 0);
        opp = nnz(prod < 0);
        nvalid = nnz(valid);
        corrv = NaN;
        if nvalid > 1 && std(dp(valid)) > 0 && std(ds(valid)) > 0
            Cc = corrcoef(dp(valid),ds(valid));
            corrv = Cc(1,2);
        end
        sm = struct();
        sm.sum_abs_Pdel_minus_Pshape_MWh = sum(abs(pdel(:)-pshape(:)));
        sm.sum_abs_delta_Pdel_minus_delta_Pshape_MW = sum(abs(dp-ds));
        sm.sum_abs_delta_curt_MW = sum(abs(dc));
        err=pdel(:)-pshape(:);
        sm.MAE_Pdel_Pshape_MW=mean(abs(err));
        sm.RMSE_Pdel_Pshape_MW=sqrt(mean(err.^2));
        sm.MAE_ratio_to_mean_Pshape=sm.MAE_Pdel_Pshape_MW/max(mean(pshape(:)),eps);
        sm.TrendMatchRate = same / max(nvalid,1);
        sm.TrendMismatchRate = opp / max(nvalid,1);
        sm.Corr_dPdel_dPshape = corrv;
        sm.Pdel_total_variation = sum(abs(dp));
        sm.Curt_total_variation = sum(abs(dc));
        sm.Pdel_ramp_p95_MW_per_h=local_percentile(abs(dp),95);
        sm.Pshape_ramp_p95_MW_per_h=local_percentile(abs(ds),95);
        sm.SystemCurtailment_ramp_p95_MW_per_h=local_percentile(abs(dc),95);
    end
    function value=get_solver_field(s,name,default)
        value=default;
        if isstruct(s) && isfield(s,name), value=s.(name); end
    end
    function q=local_percentile(x,p)
        x=sort(double(x(isfinite(x))));
        if isempty(x), q=NaN; return; end
        pos=1+(numel(x)-1)*p/100; lo=floor(pos); hi=ceil(pos); w=pos-lo;
        q=x(lo)*(1-w)+x(hi)*w;
    end
    function deltaH = hourly_band_delta_for_year(y)
        deltaH = cfg.delivery.hourly_band_delta;
        if isfield(cfg.delivery,'hourly_band_delta_years') && isfield(cfg.delivery,'hourly_band_delta_values') && ...
                ~isempty(cfg.delivery.hourly_band_delta_years) && ~isempty(cfg.delivery.hourly_band_delta_values)
            yrs = double(cfg.delivery.hourly_band_delta_years(:));
            vals = double(cfg.delivery.hourly_band_delta_values(:));
            assert(numel(yrs)==numel(vals),'hourly_band_delta_years and hourly_band_delta_values must have the same length.');
            deltaH = interp1(yrs, vals, double(y), 'linear', 'extrap');
        end
    end
    function deltaH = hourly_band_delta_side_for_year(y, side)
        side = string(side);
        if side == "up"
            deltaH = cfg.delivery.hourly_band_delta_up;
            years_field = 'hourly_band_delta_up_years';
            values_field = 'hourly_band_delta_up_values';
        else
            deltaH = cfg.delivery.hourly_band_delta_low;
            years_field = 'hourly_band_delta_low_years';
            values_field = 'hourly_band_delta_low_values';
        end
        if isfield(cfg.delivery,years_field) && isfield(cfg.delivery,values_field) && ...
                ~isempty(cfg.delivery.(years_field)) && ~isempty(cfg.delivery.(values_field))
            yrs = double(cfg.delivery.(years_field)(:));
            vals = double(cfg.delivery.(values_field)(:));
            assert(numel(yrs)==numel(vals),'hourly band side years and values must have the same length.');
            deltaH = interp1(yrs, vals, double(y), 'linear', 'extrap');
        end
    end
    function deltaH = hourly_upper_delta_for_year(y)
        yrs=double(cfg.delivery.hourly_upper_years(:));
        vals=double(cfg.delivery.hourly_upper_delta(:));
        assert(numel(yrs)==numel(vals), ...
            'hourly_upper_years and hourly_upper_delta must have the same length.');
        deltaH=interp1(yrs,vals,double(y),'linear','extrap');
    end
end

function [z,info]=solve_lp(f,A,b,Aeq,beq,lb,ub,cfg)
z=[];
allow_suboptimal=false;
if isfield(cfg.solver,'allow_suboptimal_with_x'), allow_suboptimal=logical(cfg.solver.allow_suboptimal_with_x); end
if strcmpi(cfg.solver.name,'gurobi') && exist('gurobi','file')>0
    model.A=[A;Aeq]; model.obj=f; model.rhs=[b;beq];
    model.sense=[repmat('<',size(A,1),1);repmat('=',size(Aeq,1),1)];
    model.lb=lb; model.ub=ub; model.modelsense='min';
    if isfinite(cfg.solver.time_limit_s)
        methods=unique([cfg.solver.method 1],'stable');
        crossovers=unique([cfg.solver.crossover 1],'stable');
    else
        methods=unique([cfg.solver.method 1 2],'stable');
        crossovers=unique([cfg.solver.crossover 1 0],'stable');
    end
    info=struct('name',"gurobi",'status',"not_run",'attempt_count',0, ...
        'runtime_s',0,'method',NaN,'crossover',NaN,'accepted_suboptimal',false);
    total_solve_tic=tic;
    for mi=1:numel(methods)
        for ci=1:numel(crossovers)
            params.OutputFlag=cfg.solver.output_flag; params.Threads=cfg.solver.threads;
            params.FeasibilityTol=cfg.solver.feasibility_tol; params.OptimalityTol=cfg.solver.optimality_tol;
            params.Method=methods(mi); params.Crossover=crossovers(ci);
            params.NumericFocus=2; params.ScaleFlag=2; params.BarHomogeneous=1;
            if isfinite(cfg.solver.time_limit_s)
                remaining=cfg.solver.time_limit_s-toc(total_solve_tic);
                if remaining<=0, return; end
                params.TimeLimit=max(1,remaining);
            end
            solve_tic=tic;
            r=gurobi(model,params);
            elapsed=toc(solve_tic);
            info.attempt_count=info.attempt_count+1;
            info.runtime_s=info.runtime_s+elapsed;
            info.status=string(r.status); info.method=methods(mi); info.crossover=crossovers(ci);
            if isfield(cfg,'run') && isfield(cfg.run,'verbose') && cfg.run.verbose
                fprintf('[SolverAttempt] method=%d crossover=%d status=%s runtime=%.2fs\n', ...
                    methods(mi),crossovers(ci),char(info.status),elapsed);
            end
            if isfield(r,'objval'), info.objective=r.objval; end
            if isfield(r,'x') && string(r.status)=="OPTIMAL"
                z=r.x;
                return
            elseif isfield(r,'x') && allow_suboptimal
                eqres=max(abs(Aeq*r.x-beq));
                ineqres=max([0;A*r.x-b]);
                if eqres<=max(1e-5,10*cfg.solver.feasibility_tol) && ...
                        ineqres<=max(1e-5,10*cfg.solver.feasibility_tol)
                    z=r.x;
                    info.accepted_suboptimal=true;
                    return
                end
            end
        end
    end
else
    solve_tic=tic;
    opts=optimoptions('linprog','Display','none','ConstraintTolerance',cfg.solver.feasibility_tol, ...
        'OptimalityTolerance',cfg.solver.optimality_tol);
    [z,obj,exitflag,output]=linprog(f,A,b,Aeq,beq,lb,ub,opts);
    info=struct('name',"linprog",'status',string(output.message),'exitflag',exitflag,'objective',obj, ...
        'attempt_count',1,'runtime_s',toc(solve_tic),'method',NaN,'crossover',NaN, ...
        'accepted_suboptimal',exitflag~=1 && ~isempty(z));
end
end
