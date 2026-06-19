function pkg = rev04_smooth_project_profile(raw_pu, power_ratio, duration_h, eta_ch, eta_dis)
% Deterministic daily project-BESS package. SOC starts/ends each day at zero.

raw_pu = double(raw_pu(:));
T = numel(raw_pu);
pkg.output_pu = raw_pu;
pkg.charge_pu = zeros(T,1);
pkg.discharge_pu = zeros(T,1);
pkg.soc_puh = zeros(T,1);
pkg.curt_pu = zeros(T,1);

if power_ratio <= 0 || duration_h <= 0
    return
end

P = power_ratio;
E = power_ratio * duration_h;
nd = ceil(T / 24);

for d = 1:nd
    ix = (24*(d-1)+1):min(24*d,T);
    r = raw_pu(ix);
    target = movmean(r, min(6,numel(ix)), 'Endpoints','shrink');
    soc = 0;
    charge_budget = E; % At most one equivalent full charge cycle per day.

    for j = 1:numel(ix)
        remaining = numel(ix) - j;
        desired = r(j) - target(j);
        ch = 0;
        dis = 0;
        if desired > 0
            ch = min([desired, P, r(j), charge_budget, (E-soc)/eta_ch]);
        elseif desired < 0
            dis = min([-desired, P, soc*eta_dis]);
        end

        soc_new = soc + eta_ch*ch - dis/eta_dis;
        max_reachable_soc = remaining * P / eta_dis;
        if soc_new > max_reachable_soc
            extra_dis = min([soc_new-max_reachable_soc, P-dis, (soc_new/1)*eta_dis]);
            dis = dis + extra_dis;
            soc_new = soc + eta_ch*ch - dis/eta_dis;
        end

        if j == numel(ix) && soc_new > 1e-10
            dis = dis + soc_new*eta_dis;
            soc_new = 0;
        end

        charge_budget = charge_budget - ch;
        pkg.charge_pu(ix(j)) = ch;
        pkg.discharge_pu(ix(j)) = dis;
        pkg.soc_puh(ix(j)) = soc_new;
        pkg.output_pu(ix(j)) = r(j) - ch + dis;
        soc = soc_new;
    end
end

pkg.loss_pu = raw_pu - pkg.output_pu;
pkg.max_balance_residual = max(abs(raw_pu - pkg.output_pu - pkg.charge_pu + pkg.discharge_pu));
end
