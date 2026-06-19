function inputs = rev04_build_inputs(cfg, load_data)
%REV04_BUILD_INPUTS Assemble stable Rev03 spatial/wind data with Rev04 load data.

arguments
    cfg (1,1) struct
    load_data (1,1) struct
end
S = load(cfg.input_mat, 'inner');
I = S.inner;

site_prov = string(I.sites.prov_name(:));
prov_names = unique(site_prov, 'stable');
assert(isequal(prov_names(:), cfg.provinces(:)), ...
    'Configured province order must match the wind-site province order.');

load_idx = zeros(numel(prov_names),1);
for p = 1:numel(prov_names)
    load_idx(p) = find(load_data.prov_names == prov_names(p), 1);
    assert(load_idx(p) > 0, 'Missing load province: %s', prov_names(p));
end

inputs = struct();
inputs.note = "Rev04 input assembly. Rev03 MAT files remain read-only.";
inputs.prov_names = prov_names;
inputs.province_names = prov_names;
inputs.years = cfg.years(:)';
inputs.site = I.sites;
inputs.sites = I.sites;
inputs.turbines = I.turbines;
inputs.timeslice = I.timeslice;
inputs.g_pu = I.profiles.g_pu;
inputs.profiles = I.profiles;
inputs.wind = I.wind;
inputs.load = load_data;
inputs.load_idx = load_idx;
inputs.cost_source = I.cost;
inputs.target_share = interp1(cfg.delivery.target_share_years, ...
    cfg.delivery.target_share_values, inputs.years, 'linear');

inputs.D_MW = load_data.D_MW(load_idx,:,:);
inputs.annual_load_MWh = load_data.annual_model_MWh(load_idx,:);
inputs.Etarget_requested_MWh = inputs.annual_load_MWh .* inputs.target_share;

inputs.tech_potential_MWh = zeros(numel(prov_names),numel(inputs.years));
for iy = 1:numel(inputs.years)
    available = cfg.turbine_first_year <= inputs.years(iy);
    for p = 1:numel(prov_names)
        idx = find(site_prov == prov_names(p));
        best = zeros(numel(idx),1);
        for k = find(available)
            cap = double(I.wind.capMax_MW_year(idx,k,iy));
            gp = reshape(double(I.profiles.g_pu(idx,k,:)),numel(idx),[]);
            best = max(best, cap .* sum(gp,2));
        end
        inputs.tech_potential_MWh(p,iy) = sum(best);
    end
end
inputs.Etarget_MWh = min(inputs.Etarget_requested_MWh, ...
    cfg.delivery.max_target_fraction_of_raw_potential .* inputs.tech_potential_MWh);
inputs.target_potential_limited = inputs.Etarget_MWh < inputs.Etarget_requested_MWh-1;
inputs.T = size(inputs.g_pu,3);
inputs.hourly_time = datetime(2025,1,1,0,0,0) + hours(0:(inputs.T-1));
inputs.month_id = month(inputs.hourly_time(:));
end
