function T = rev04_audit_raw_wind_ramp(I, cfg, out_file)
%REV04_AUDIT_RAW_WIND_RAMP Audit raw offshore-wind hourly ramp distributions.
% Ramp unit is fraction of installed capacity per hour (pu/h).

if nargin < 3 || isempty(out_file)
    out_file = fullfile(cfg.output_root, 'qa_raw_wind_ramp_distribution.csv');
end

rows = struct([]);
add_group("all", "", "", collect_ramps(I, [], []));

for p = 1:numel(I.prov_names)
    add_group("province", string(I.prov_names(p)), "", collect_ramps(I, p, []));
end
for ti = 1:numel(cfg.turbine_names)
    add_group("turbine", "", string(cfg.turbine_names(ti)), collect_ramps(I, [], ti));
end
for p = 1:numel(I.prov_names)
    for ti = 1:numel(cfg.turbine_names)
        add_group("province_turbine", string(I.prov_names(p)), ...
            string(cfg.turbine_names(ti)), collect_ramps(I, p, ti));
    end
end

T = struct2table(rows);
[od,~,~] = fileparts(out_file);
if ~isempty(od) && ~isfolder(od), mkdir(od); end
writetable(T, out_file);

    function add_group(scope, province, turbine, ramps)
        if isempty(ramps)
            return
        end
        q = local_percentiles(ramps, [50 75 85 90 95 99 100]);
        k = numel(rows) + 1;
        rows(k).Scope = string(scope);
        rows(k).Province = string(province);
        rows(k).Turbine = string(turbine);
        rows(k).SampleCount = numel(ramps);
        rows(k).P50 = q(1);
        rows(k).P75 = q(2);
        rows(k).P85 = q(3);
        rows(k).P90 = q(4);
        rows(k).P95 = q(5);
        rows(k).P99 = q(6);
        rows(k).Max = q(7);
    end
end

function ramps = collect_ramps(I, prov_idx, turb_idx)
if isempty(prov_idx)
    site_idx = 1:numel(I.sites.prov_name);
else
    site_idx = find(strcmp(string(I.sites.prov_name), string(I.prov_names(prov_idx))));
end
if isempty(turb_idx)
    turb_idx = 1:size(I.g_pu,2);
end
ramps = [];
for si = reshape(site_idx,1,[])
    for ti = reshape(turb_idx,1,[])
        gp = squeeze(double(I.g_pu(si,ti,:)));
        if all(~isfinite(gp)) || max(gp) <= 0
            continue
        end
        ramps = [ramps; abs(diff(gp(:)))]; %#ok<AGROW>
    end
end
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
