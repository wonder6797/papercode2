function pkg = rev04_smooth_project_profile_ramp_lp(raw_pu, ramp_limit, duration_h, eta_ch, eta_dis, cfg)
%REV04_SMOOTH_PROJECT_PROFILE_RAMP_LP Size project-side BESS for RDU ramp service.
% All quantities are per 1 MW wind capacity. Power is MW/MWwind, SOC is MWh/MWwind.

raw_pu = double(raw_pu(:));
T = numel(raw_pu);
assert(T > 1, 'Project ramp LP needs at least two hours.');
assert(isfinite(ramp_limit) && ramp_limit >= 0, 'Invalid ramp limit.');
raw_ramp = abs(diff(raw_pu));
if max(raw_ramp) <= ramp_limit + 1e-12
    pkg.output_pu=raw_pu; pkg.curt_pu=zeros(T,1); pkg.charge_pu=zeros(T,1);
    pkg.discharge_pu=zeros(T,1); pkg.soc_puh=zeros(T,1);
    pkg.P_bess_pu=0; pkg.E_bess_puh=0; pkg.loss_pu=zeros(T,1);
    pkg.ramp_limit_pu_per_h=ramp_limit; pkg.status="BYPASS_RAW_WITHIN_LIMIT";
    pkg.max_balance_residual=0; pkg.post_ramp_max=max(raw_ramp);
    pkg.post_ramp_p95=local_percentiles(raw_ramp,95);
    pkg.raw_ramp_p50=local_percentiles(raw_ramp,50);
    pkg.raw_ramp_p85=local_percentiles(raw_ramp,85);
    pkg.raw_ramp_p90=local_percentiles(raw_ramp,90);
    pkg.raw_ramp_p95=local_percentiles(raw_ramp,95);
    pkg.raw_ramp_p99=local_percentiles(raw_ramp,99);
    pkg.lp_solved=false;
    return
end

cursor = 0;
idx.grid = alloc(T);
idx.curt = alloc(T);
idx.ch = alloc(T);
idx.dis = alloc(T);
idx.soc = alloc(T);
idx.P = alloc(1);
nvar = cursor;

lb = zeros(nvar,1);
ub = inf(nvar,1);
ub(idx.grid) = 1;
ub(idx.curt) = max(raw_pu, 0);

f = zeros(nvar,1);
f(idx.curt) = 1e3;
f(idx.P) = 1;
flow_penalty = 1e-3;
if isfield(cfg.project_bess, 'flow_penalty')
    flow_penalty = cfg.project_bess.flow_penalty;
end
f(idx.ch) = flow_penalty;
f(idx.dis) = flow_penalty;

% Balance: raw - curt - charge + discharge = grid.
Aeq = sparse(T*2,nvar);
beq = zeros(T*2,1);
Aeq(1:T,idx.grid) = speye(T);
Aeq(1:T,idx.curt) = speye(T);
Aeq(1:T,idx.ch) = speye(T);
Aeq(1:T,idx.dis) = -speye(T);
beq(1:T) = raw_pu;

% Daily cyclic SOC: soc_t - soc_prev - eta_ch*ch + dis/eta_dis = 0.
rows = (T+1):(2*T);
Aeq(rows,idx.soc) = speye(T);
Aeq(rows,idx.ch) = -eta_ch * speye(T);
Aeq(rows,idx.dis) = (1/eta_dis) * speye(T);
prev = zeros(T,1);
closure_h = cfg.project_bess.daily_closure_h;
for bs = 1:closure_h:T
    be = min(T, bs+closure_h-1);
    prev(bs) = be;
    if be > bs
        prev((bs+1):be) = (bs:(be-1))';
    end
end
Aeq(rows,idx.soc) = Aeq(rows,idx.soc) - sparse(1:T,prev,ones(T,1),T,T);

A = sparse(0,nvar);
b = zeros(0,1);
append_cap(idx.ch, idx.P, 1.0);
append_cap(idx.dis, idx.P, 1.0);
append_cap(idx.soc, idx.P, duration_h);

% Hour-to-hour ramp limits on grid injection.
nr = T - 1;
R = sparse(nr,nvar);
R(:,idx.grid(2:end)) = speye(nr);
R(:,idx.grid(1:end-1)) = R(:,idx.grid(1:end-1)) - speye(nr);
A = [A; R; -R]; %#ok<AGROW>
b = [b; ramp_limit*ones(nr,1); ramp_limit*ones(nr,1)]; %#ok<AGROW>

[z, status] = solve_project_lp(f,A,b,Aeq,beq,lb,ub,cfg);
if isempty(z)
    error('Project ramp LP failed: %s', status);
end

pkg.output_pu = z(idx.grid);
pkg.curt_pu = z(idx.curt);
pkg.charge_pu = z(idx.ch);
pkg.discharge_pu = z(idx.dis);
pkg.soc_puh = z(idx.soc);
pkg.P_bess_pu = z(idx.P);
pkg.E_bess_puh = duration_h * z(idx.P);
pkg.loss_pu = raw_pu - pkg.output_pu;
pkg.ramp_limit_pu_per_h = ramp_limit;
pkg.status = string(status);
pkg.max_balance_residual = max(abs(raw_pu - pkg.curt_pu - pkg.charge_pu + pkg.discharge_pu - pkg.output_pu));
post_ramp = abs(diff(pkg.output_pu));
raw_ramp = abs(diff(raw_pu));
pkg.post_ramp_max = max(post_ramp);
pkg.post_ramp_p95 = local_percentiles(post_ramp, 95);
pkg.raw_ramp_p50 = local_percentiles(raw_ramp, 50);
pkg.raw_ramp_p85 = local_percentiles(raw_ramp, 85);
pkg.raw_ramp_p90 = local_percentiles(raw_ramp, 90);
pkg.raw_ramp_p95 = local_percentiles(raw_ramp, 95);
pkg.raw_ramp_p99 = local_percentiles(raw_ramp, 99);
pkg.lp_solved = true;

    function r = alloc(n)
        r = (cursor+1):(cursor+n);
        cursor = cursor + n;
    end
    function append_cap(flow, cap, mult)
        Rcap = sparse(T,nvar);
        Rcap(:,flow) = speye(T);
        Rcap(:,cap) = -mult * ones(T,1);
        A = [A; Rcap]; %#ok<AGROW>
        b = [b; zeros(T,1)]; %#ok<AGROW>
    end
end

function [z, status] = solve_project_lp(f,A,b,Aeq,beq,lb,ub,cfg)
z = [];
status = "not_run";
if strcmpi(cfg.solver.name,'gurobi') && exist('gurobi','file') > 0
    model.A = [A; Aeq];
    model.obj = f;
    model.rhs = [b; beq];
    model.sense = [repmat('<',size(A,1),1); repmat('=',size(Aeq,1),1)];
    model.lb = lb;
    model.ub = ub;
    model.modelsense = 'min';
    methods = unique([cfg.solver.method 1],'stable');
    crossovers = unique([cfg.solver.crossover 1],'stable');
    total_tic=tic;
    for mi = 1:numel(methods)
        for ci=1:numel(crossovers)
            params.OutputFlag = 0;
            params.Threads = max(1, min(4, cfg.solver.threads));
            params.FeasibilityTol = cfg.solver.feasibility_tol;
            params.OptimalityTol = cfg.solver.optimality_tol;
            params.Method = methods(mi); params.Crossover = crossovers(ci);
            params.NumericFocus = 2; params.ScaleFlag=2; params.BarHomogeneous=1;
            if isfinite(cfg.solver.time_limit_s)
                remaining=cfg.solver.time_limit_s-toc(total_tic);
                if remaining<=0, return; end
                params.TimeLimit=max(1,remaining);
            end
            r = gurobi(model, params);
            status = string(r.status);
            allow_suboptimal=isfield(cfg.solver,'allow_suboptimal_with_x') && cfg.solver.allow_suboptimal_with_x;
            if isfield(r,'x') && (status=="OPTIMAL" || allow_suboptimal)
                z = r.x;
                return
            end
        end
    end
else
    opts = optimoptions('linprog','Display','none', ...
        'ConstraintTolerance',cfg.solver.feasibility_tol, ...
        'OptimalityTolerance',cfg.solver.optimality_tol);
    [z,~,exitflag,output] = linprog(f,A,b,Aeq,beq,lb,ub,opts);
    status = sprintf('linprog_%d_%s', exitflag, output.message);
end
end

function qv = local_percentiles(x, p)
x = sort(x(isfinite(x)));
if isempty(x)
    qv = NaN(size(p));
    return
end
p = double(p(:));
n = numel(x);
pos = 1 + (n-1) .* p ./ 100;
lo = floor(pos);
hi = ceil(pos);
w = pos - lo;
qv = x(lo) .* (1-w) + x(hi) .* w;
qv = reshape(qv, size(p));
end
