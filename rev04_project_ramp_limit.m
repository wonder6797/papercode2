function [limit, diag] = rev04_project_ramp_limit(I, cfg, prov_idx, year)
%REV04_PROJECT_RAMP_LIMIT Project-side ramp limit in pu/h for one province-year.

mode = string(cfg.project_bess.ramp_mode);
diag = struct();
diag.Mode = mode;
diag.Year = year;
diag.Province = string(I.prov_names(prov_idx));
diag.Quantile = cfg.project_bess.ramp_quantile;

if mode == "fixed"
    limit = cfg.project_bess.ramp_rate_per_hour;
    diag.P50 = NaN; diag.P75 = NaN; diag.P85 = NaN; diag.P90 = NaN;
    diag.P95 = NaN; diag.P99 = NaN; diag.Max = NaN;
    fprintf('[ProjectRamp] %s %d ramp_limit = %.2f%%/h fixed.\n', ...
        diag.Province, year, 100*limit);
    return
end

assert(mode == "quantile", 'Unsupported project BESS ramp mode: %s', mode);
site_idx = find(strcmp(string(I.sites.prov_name), diag.Province));
available_turbines = find(cfg.turbine_first_year <= year);
ramps = [];
for si = reshape(site_idx,1,[])
    for ti = reshape(available_turbines,1,[])
        gp = squeeze(double(I.g_pu(si,ti,:)));
        if all(~isfinite(gp)) || max(gp) <= 0
            continue
        end
        ramps = [ramps; abs(diff(gp(:)))]; %#ok<AGROW>
    end
end
assert(~isempty(ramps), 'No raw wind ramp samples for %s %d.', diag.Province, year);

qs = local_percentiles(ramps, [50 75 85 90 95 99 100]);
diag.P50 = qs(1); diag.P75 = qs(2); diag.P85 = qs(3); diag.P90 = qs(4);
diag.P95 = qs(5); diag.P99 = qs(6); diag.Max = qs(7);

q = cfg.project_bess.ramp_quantile * 100;
limit = local_percentiles(ramps, q);
fprintf('[ProjectRamp] %s %d ramp_limit = %.2f%%/h based on raw wind P%.0f.\n', ...
    diag.Province, year, 100*limit, q);
end

function qv = local_percentiles(x, p)
x = sort(x(isfinite(x)));
assert(~isempty(x), 'Cannot compute percentile of empty vector.');
p = double(p(:));
n = numel(x);
pos = 1 + (n-1) .* p ./ 100;
lo = floor(pos);
hi = ceil(pos);
w = pos - lo;
qv = x(lo) .* (1-w) + x(hi) .* w;
qv = reshape(qv, size(p));
end
