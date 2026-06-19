function load_data = rev04_prepare_hourly_load(load_file, cfg)
%REV04_PREPARE_HOURLY_LOAD Read and validate the 2015-2024 provincial load workbook.
% Workbook hourly values are GWh per hour. Model output is average MW.

arguments
    load_file (1,1) string
    cfg (1,1) struct
end
assert(isfile(load_file), 'Missing hourly load workbook: %s', load_file);

years = cfg.load.history_years(:)';
raw = cell(numel(years),1);
times = cell(numel(years),1);
prov_names = strings(0,1);
qa_rows = struct([]);

for iy = 1:numel(years)
    y = years(iy);
    sheet = sprintf('%d load curve', y);
    C = readcell(load_file, 'Sheet', sheet);
    original_rows = size(C,1);
    original_cols = size(C,2);
    assert(size(C,1) >= 8761 && size(C,2) >= 32, ...
        'Unexpected dimensions in sheet %s.', sheet);

    header = string(C(1,:));
    keep_col = strlength(strtrim(header)) > 0;
    C = C(:, keep_col);
    header = header(keep_col);
    assert(numel(header) == 32, 'Sheet %s must contain time plus 31 provinces.', sheet);

    keep_row = ~cellfun(@(x) isempty(x) || (isstring(x) && ismissing(x)), C(:,1));
    keep_row(1) = true;
    C = C(keep_row,:);

    t = cell_to_datetime(C(2:end,1));
    X = cell_to_numeric(C(2:end,2:end));
    assert(numel(t) == size(X,1), 'Time/value row mismatch in %s.', sheet);
    assert(all(isfinite(X(:))) && all(X(:) >= 0), ...
        'Sheet %s contains missing, non-finite, or negative load values.', sheet);
    assert(numel(unique(t)) == numel(t), 'Sheet %s contains duplicate timestamps.', sheet);
    assert(all(abs(seconds(diff(t))-3600) < 1), 'Sheet %s timestamps are not hourly-contiguous.', sheet);

    expected = 8760 + 24 * double(eomday(y,2) == 29);
    assert(numel(t) == expected, 'Sheet %s expected %d hours, got %d.', sheet, expected, numel(t));
    names_y = strtrim(regexprep(header(2:end), '\s*\(.*$', ''));
    if isempty(prov_names)
        prov_names = names_y(:);
    else
        assert(isequal(prov_names, names_y(:)), 'Province order differs in sheet %s.', sheet);
    end

    times{iy} = t(:);
    raw{iy} = X .* cfg.load.unit_GWh_to_MWh; % one-hour MWh equals average MW numerically
    qa_rows(iy).Year = y;
    qa_rows(iy).OriginalRows = original_rows;
    qa_rows(iy).OriginalCols = original_cols;
    qa_rows(iy).RemovedBlankRows = original_rows-size(C,1);
    qa_rows(iy).RemovedBlankCols = original_cols-size(C,2);
    qa_rows(iy).Hours = numel(t);
    qa_rows(iy).ProvinceCount = size(X,2);
    qa_rows(iy).MissingCount = nnz(~isfinite(X));
    qa_rows(iy).NegativeCount = nnz(X < 0);
    qa_rows(iy).TotalLoad_TWh = sum(X,'all') / 1000;
    qa_rows(iy).InputUnit = "GWh_per_hour";
    qa_rows(iy).OutputUnit = "average_MW";
    qa_rows(iy).ConversionMultiplier = cfg.load.unit_GWh_to_MWh;
end

annual_hist_MWh = zeros(numel(prov_names), numel(years));
peak_hist_MW = zeros(numel(prov_names), numel(years));
for iy = 1:numel(years)
    annual_hist_MWh(:,iy) = sum(raw{iy},1)';
    peak_hist_MW(:,iy) = max(raw{iy},[],1)';
end

[shape2025, shape_qa] = build_2025_shape(times, raw, years, prov_names, cfg);
[annual2025_MWh, trend_qa] = forecast_2025_annual(annual_hist_MWh, years, prov_names, cfg);

model_years = cfg.years(:)';
D_MW = zeros(numel(prov_names), numel(model_years), 8760, 'single');
annual_model_MWh = zeros(numel(prov_names), numel(model_years));
for iy = 1:numel(model_years)
    growth = future_growth_factor(model_years(iy), cfg);
    annual_model_MWh(:,iy) = annual2025_MWh .* growth;
    D_MW(:,iy,:) = single(shape2025 .* annual_model_MWh(:,iy));
end

load_data = struct();
load_data.note = "Provincial multi-year hourly load dataset; provenance pending.";
load_data.source_file = char(load_file);
load_data.provenance_status = cfg.load.provenance_status;
load_data.prov_names = prov_names;
load_data.history_years = years;
load_data.timestamps_by_year = times;
load_data.MW_by_year = raw;
load_data.annual_history_MWh = annual_hist_MWh;
load_data.peak_history_MW = peak_hist_MW;
load_data.model_years = model_years;
load_data.shape_2025 = shape2025;
load_data.annual_2025_MWh = annual2025_MWh;
load_data.annual_model_MWh = annual_model_MWh;
load_data.D_MW = D_MW;
load_data.qa = struct('sheets',struct2table(qa_rows),'shape',shape_qa,'trend',trend_qa);

assert(max(abs(sum(shape2025,2)-1)) < 1e-10, '2025 load shapes do not sum to one.');
assert(max(abs(squeeze(sum(double(D_MW),3)) - annual_model_MWh),[],'all') < 5, ...
    'Model load profiles do not reconcile to annual energy.');
end

function t = cell_to_datetime(c)
t = NaT(numel(c),1);
for i = 1:numel(c)
    v = c{i};
    if isdatetime(v)
        t(i) = v;
    elseif isnumeric(v) && isfinite(v)
        t(i) = datetime(v, 'ConvertFrom', 'excel');
    elseif ischar(v) || isstring(v)
        t(i) = datetime(v);
    else
        error('Invalid timestamp at row %d.', i+1);
    end
end
end

function X = cell_to_numeric(c)
X = nan(size(c));
for i = 1:numel(c)
    v = c{i};
    if isnumeric(v) && isscalar(v)
        X(i) = double(v);
    else
        error('Non-numeric hourly load value at data cell %d.', i);
    end
end
end

function [shape, qa] = build_2025_shape(times, raw, years, prov_names, cfg)
shape_years = cfg.load.shape_years(:)';
nP = numel(prov_names);
bucket_values = cell(12,2,24,nP);
for y = shape_years
    iy = find(years == y,1);
    t = times{iy};
    X = raw{iy};
    for r = 1:numel(t)
        m = month(t(r));
        dtyp = 1 + isweekend(t(r));
        h = hour(t(r)) + 1;
        for p = 1:nP
            bucket_values{m,dtyp,h,p}(end+1,1) = X(r,p); %#ok<AGROW>
        end
    end
end

t25 = datetime(2025,1,1,0,0,0) + hours(0:8759);
profile = zeros(nP,8760);
for r = 1:8760
    m = month(t25(r));
    dtyp = 1 + isweekend(t25(r));
    h = hour(t25(r)) + 1;
    for p = 1:nP
        vals = bucket_values{m,dtyp,h,p};
        assert(~isempty(vals), 'Missing historical load-shape bucket.');
        profile(p,r) = median(vals);
    end
end
shape = profile ./ sum(profile,2);
qa = table(prov_names, min(shape,[],2), max(shape,[],2), sum(shape,2), ...
    'VariableNames', {'Province','ShapeMin','ShapeMax','ShapeSum'});
end

function [annual2025, qa] = forecast_2025_annual(annual_hist, years, prov_names, cfg)
trend_years = cfg.load.trend_years(:)';
idx = arrayfun(@(y)find(years==y,1), trend_years);
nP = size(annual_hist,1);
annual2025 = zeros(nP,1);
g_raw = zeros(nP,1);
g_used = zeros(nP,1);
for p = 1:nP
    yy = trend_years(:);
    z = log(annual_hist(p,idx(:))');
    slopes = zeros(nchoosek(numel(yy),2),1);
    k = 0;
    for i = 1:numel(yy)-1
        for j = i+1:numel(yy)
            k = k + 1;
            slopes(k) = (z(j)-z(i))/(yy(j)-yy(i));
        end
    end
    slope = median(slopes);
    g_raw(p) = exp(slope)-1;
    g_used(p) = min(cfg.load.trend_ceiling, max(cfg.load.trend_floor, g_raw(p)));
    annual2025(p) = annual_hist(p,years==2024) * (1 + g_used(p));
end
qa = table(prov_names, annual_hist(:,years==2024)/1e6, annual2025/1e6, g_raw, g_used, ...
    'VariableNames', {'Province','Annual2024_TWh','Forecast2025_TWh','RawGrowth','UsedGrowth'});
end

function g = future_growth_factor(y, cfg)
a = min(max(y-2025,0),5);
b = min(max(y-2030,0),10);
c = max(y-2040,0);
g = (1+cfg.load.future_growth_2025_2030)^a * ...
    (1+cfg.load.future_growth_2030_2040)^b * ...
    (1+cfg.load.future_growth_2040_2050)^c;
end
