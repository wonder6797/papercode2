function P = rev04_build_site_packages(I, cfg, prov_idx, year, cost, used_frac)
% Build candidates, cheaply pre-screen them, then run project ramp LPs.

persistent ramp_smooth_cache
if isempty(ramp_smooth_cache)
    ramp_smooth_cache = containers.Map('KeyType','char','ValueType','any');
end

site_idx = find(strcmp(string(I.sites.prov_name), string(I.province_names(prov_idx))));
if isempty(site_idx)
    error('Rev04:NoSites','No sites for province %s.', I.province_names(prov_idx));
end
if nargin < 6 || isempty(used_frac)
    used_frac = zeros(numel(I.sites.prov_name),1);
end
iy = find(I.years == year,1);
assert(~isempty(iy),'Year %d is not configured.',year);

if isfinite(cfg.screen.max_sites_per_province) && numel(site_idx) > cfg.screen.max_sites_per_province
    score = squeeze(max(I.wind.capMax_MW_year(site_idx,:,iy),[],2));
    [~,ord] = sort(score,'descend');
    site_idx = site_idx(ord(1:cfg.screen.max_sites_per_province));
end

available_turbines = find(cfg.turbine_first_year <= year);
raw_profiles = I.g_pu;
T = I.T;
[ramp_limit, ~] = rev04_project_ramp_limit(I, cfg, prov_idx, year);

% Cheap candidate metadata. No ramp LP is called in this block.
raw_site=zeros(0,1); raw_turb=zeros(0,1); raw_cap=zeros(0,1);
raw_energy=zeros(0,1); raw_cf=zeros(0,1); raw_wind_cost=zeros(0,1);
raw_profile_cells=cell(0,1);
for si=reshape(site_idx,1,[])
    if used_frac(si)>=1-1e-9, continue; end
    for ti=reshape(available_turbines,1,[])
        cap=double(I.wind.capMax_MW_year(si,ti,iy));
        if cap<=0, continue; end
        raw_pu=double(squeeze(raw_profiles(si,ti,:)));
        energy=cap*sum(raw_pu);
        if energy<=0, continue; end
        raw_site(end+1,1)=si; %#ok<AGROW>
        raw_turb(end+1,1)=ti; %#ok<AGROW>
        raw_cap(end+1,1)=cap; %#ok<AGROW>
        raw_energy(end+1,1)=energy; %#ok<AGROW>
        raw_cf(end+1,1)=sum(raw_pu)/T; %#ok<AGROW>
        raw_wind_cost(end+1,1)=double(I.wind.C_wind_annual_year_USDyr(si,ti,iy)); %#ok<AGROW>
        raw_profile_cells{end+1,1}=raw_pu; %#ok<AGROW>
    end
end
raw_candidate_count=numel(raw_site);

if isfield(cfg,'packages') && isfield(cfg.packages,'pre_screen_before_ramp') && ...
        cfg.packages.pre_screen_before_ramp && raw_candidate_count>0
    maxN=double(cfg.packages.pre_screen_max_packages);
    if isfinite(maxN) && maxN>0 && raw_candidate_count>maxN
        unit_cost=raw_wind_cost./max(raw_energy,eps);
        [~,ord]=sortrows([unit_cost -raw_cf],[1 2]);
        keep=sort(ord(1:maxN));
        raw_site=raw_site(keep); raw_turb=raw_turb(keep); raw_cap=raw_cap(keep);
        raw_energy=raw_energy(keep); raw_cf=raw_cf(keep); %#ok<NASGU>
        raw_wind_cost=raw_wind_cost(keep); raw_profile_cells=raw_profile_cells(keep);
    end
end
pre_screen_retained_count=numel(raw_site);

disk_cache_enable=isfield(cfg.project_bess,'ramp_cache_enable') && logical(cfg.project_bess.ramp_cache_enable);
disk_cache_dir="";
if disk_cache_enable
    disk_cache_dir=string(cfg.project_bess.ramp_cache_dir);
    if strlength(disk_cache_dir)==0
        disk_cache_enable=false;
    elseif ~isfolder(disk_cache_dir)
        mkdir(disk_cache_dir);
    end
end
smoothing_version="ramp_lp_v1";
if isfield(cfg.project_bess,'smoothing_version'), smoothing_version=string(cfg.project_bess.smoothing_version); end

candidate_site=zeros(0,1); candidate_turb=zeros(0,1); candidate_pkg=zeros(0,1);
cap_MW=zeros(0,1); raw_MWh=zeros(0,1); project_curt_MWh=zeros(0,1);
annual_cost_USDyr=zeros(0,1); wind_annual_cost_USDyr=zeros(0,1);
project_bess_annual_cost_USDyr=zeros(0,1); profile_cells=cell(0,1);
raw_profile_out_cells=cell(0,1); package_P_MW=zeros(0,1); package_E_MWh=zeros(0,1);
ramp_limit_pu_per_h=zeros(0,1); raw_ramp_p50=zeros(0,1); raw_ramp_p85=zeros(0,1);
raw_ramp_p90=zeros(0,1); raw_ramp_p95=zeros(0,1); raw_ramp_p99=zeros(0,1);
post_ramp_max=zeros(0,1); post_ramp_p95=zeros(0,1); smooth_status=strings(0,1);
rdu_id=strings(0,1); area_dev_km2=zeros(0,1); density_MW_per_km2=zeros(0,1);
stats=struct('RampCacheHit',0,'RampCacheMiss',0,'RampCacheNewFiles',0, ...
    'RampCacheReusedFiles',0,'ProjectRampProfileCalls',0,'ProjectRampProfileTime_s',0);

for jj=1:pre_screen_retained_count
    si=raw_site(jj); ti=raw_turb(jj); cap=raw_cap(jj); raw_pu=raw_profile_cells{jj};
    rid=string(I.sites.grid_id(si));
    profile_hash=rev04_hash_value(single(raw_pu));
    cache_key=sprintf('rdu=%s|turbine=%d|profile=%s|ramp=%.12g|duration=%.12g|smooth=%s|solver=%s', ...
        char(rid),ti,char(profile_hash),ramp_limit,cfg.project_bess.duration_h, ...
        char(smoothing_version),char(string(cfg.solver.name)));
    cache_file=""; sm=[];
    if isKey(ramp_smooth_cache,cache_key)
        sm=ramp_smooth_cache(cache_key); stats.RampCacheHit=stats.RampCacheHit+1;
    elseif disk_cache_enable
        cache_file=fullfile(disk_cache_dir,cache_filename(cache_key));
        if isfile(cache_file)
            S=load(cache_file,'sm','cache_key_saved');
            if isfield(S,'cache_key_saved') && strcmp(S.cache_key_saved,cache_key)
                sm=S.sm; stats.RampCacheHit=stats.RampCacheHit+1;
                stats.RampCacheReusedFiles=stats.RampCacheReusedFiles+1;
            end
        end
    end
    if isempty(sm)
        stats.RampCacheMiss=stats.RampCacheMiss+1;
        ramp_tic=tic;
        sm=rev04_smooth_project_profile_ramp_lp(raw_pu,ramp_limit, ...
            cfg.project_bess.duration_h,cfg.storage.bess.eta_ch,cfg.storage.bess.eta_dis,cfg);
        elapsed=toc(ramp_tic);
        if ~isfield(sm,'lp_solved') || sm.lp_solved
            stats.ProjectRampProfileCalls=stats.ProjectRampProfileCalls+1;
            stats.ProjectRampProfileTime_s=stats.ProjectRampProfileTime_s+elapsed;
        end
        if disk_cache_enable
            if strlength(cache_file)==0, cache_file=fullfile(disk_cache_dir,cache_filename(cache_key)); end
            cache_key_saved=cache_key; %#ok<NASGU>
            save(cache_file,'sm','cache_key_saved','-v7');
            stats.RampCacheNewFiles=stats.RampCacheNewFiles+1;
        end
    end
    ramp_smooth_cache(cache_key)=sm;

    bessP=sm.P_bess_pu*cap; bessE=sm.E_bess_puh*cap;
    project_bess_cost=bessP*cost.bess.power_annual_USD_per_MWyr+ ...
        bessE*cost.bess.energy_annual_USD_per_MWhyr;
    candidate_site(end+1,1)=si; candidate_turb(end+1,1)=ti; candidate_pkg(end+1,1)=1; %#ok<AGROW>
    cap_MW(end+1,1)=cap; raw_MWh(end+1,1)=raw_energy(jj); %#ok<AGROW>
    project_curt_MWh(end+1,1)=cap*sum(sm.curt_pu); %#ok<AGROW>
    wind_annual_cost_USDyr(end+1,1)=raw_wind_cost(jj); %#ok<AGROW>
    project_bess_annual_cost_USDyr(end+1,1)=project_bess_cost; %#ok<AGROW>
    annual_cost_USDyr(end+1,1)=raw_wind_cost(jj)+project_bess_cost; %#ok<AGROW>
    profile_cells{end+1,1}=single(cap*sm.output_pu); %#ok<AGROW>
    raw_profile_out_cells{end+1,1}=single(cap*raw_pu); %#ok<AGROW>
    package_P_MW(end+1,1)=bessP; package_E_MWh(end+1,1)=bessE; %#ok<AGROW>
    ramp_limit_pu_per_h(end+1,1)=sm.ramp_limit_pu_per_h; %#ok<AGROW>
    raw_ramp_p50(end+1,1)=sm.raw_ramp_p50; raw_ramp_p85(end+1,1)=sm.raw_ramp_p85; %#ok<AGROW>
    raw_ramp_p90(end+1,1)=sm.raw_ramp_p90; raw_ramp_p95(end+1,1)=sm.raw_ramp_p95; %#ok<AGROW>
    raw_ramp_p99(end+1,1)=sm.raw_ramp_p99; post_ramp_max(end+1,1)=sm.post_ramp_max; %#ok<AGROW>
    post_ramp_p95(end+1,1)=sm.post_ramp_p95; smooth_status(end+1,1)=sm.status; %#ok<AGROW>
    rdu_id(end+1,1)=rid; area_dev_km2(end+1,1)=I.sites.A_km2(si); %#ok<AGROW>
    density_MW_per_km2(end+1,1)=cap/max(I.sites.A_km2(si),eps); %#ok<AGROW>
end

[candidate_site,candidate_turb,candidate_pkg,cap_MW,raw_MWh,project_curt_MWh, ...
    annual_cost_USDyr,wind_annual_cost_USDyr,project_bess_annual_cost_USDyr, ...
    profile_cells,raw_profile_out_cells,package_P_MW,package_E_MWh,ramp_limit_pu_per_h, ...
    raw_ramp_p50,raw_ramp_p85,raw_ramp_p90,raw_ramp_p95,raw_ramp_p99,post_ramp_max, ...
    post_ramp_p95,smooth_status,rdu_id,area_dev_km2,density_MW_per_km2] = ...
    screen_packages_by_quality(cfg,year,candidate_site,candidate_turb,candidate_pkg,cap_MW, ...
    raw_MWh,project_curt_MWh,annual_cost_USDyr,wind_annual_cost_USDyr, ...
    project_bess_annual_cost_USDyr,profile_cells,raw_profile_out_cells,package_P_MW, ...
    package_E_MWh,ramp_limit_pu_per_h,raw_ramp_p50,raw_ramp_p85,raw_ramp_p90, ...
    raw_ramp_p95,raw_ramp_p99,post_ramp_max,post_ramp_p95,smooth_status,rdu_id, ...
    area_dev_km2,density_MW_per_km2);

if isempty(profile_cells)
    P.profile_MW=zeros(T,0,'single'); P.raw_profile_MW=zeros(T,0,'single');
else
    P.profile_MW=single(cell2mat(profile_cells'));
    P.raw_profile_MW=single(cell2mat(raw_profile_out_cells'));
end
P.site_idx=candidate_site; P.turbine_idx=candidate_turb; P.package_idx=candidate_pkg;
P.cap_MW=cap_MW; P.raw_MWh=raw_MWh; P.project_curt_MWh=project_curt_MWh;
P.annual_cost_USDyr=annual_cost_USDyr; P.wind_annual_cost_USDyr=wind_annual_cost_USDyr;
P.project_bess_annual_cost_USDyr=project_bess_annual_cost_USDyr;
P.project_bess_P_MW=package_P_MW; P.project_bess_E_MWh=package_E_MWh;
P.ramp_limit_pu_per_h=ramp_limit_pu_per_h; P.raw_ramp_p50=raw_ramp_p50;
P.raw_ramp_p85=raw_ramp_p85; P.raw_ramp_p90=raw_ramp_p90;
P.raw_ramp_p95=raw_ramp_p95; P.raw_ramp_p99=raw_ramp_p99;
P.post_ramp_max=post_ramp_max; P.post_ramp_p95=post_ramp_p95;
P.smooth_status=smooth_status; P.rdu_id=rdu_id; P.area_dev_km2=area_dev_km2;
P.density_MW_per_km2=density_MW_per_km2; P.site_rows=unique(candidate_site(:))';
P.site_remaining_frac=max(0,1-used_frac(P.site_rows)); P.n=numel(candidate_site);
P.RawCandidateCount=raw_candidate_count; P.PreScreenRetainedCount=pre_screen_retained_count;
names=fieldnames(stats);
for k=1:numel(names), P.(names{k})=stats.(names{k}); end
end

function varargout=screen_packages_by_quality(cfg,year,varargin)
varargout=varargin;
if ~isfield(cfg,'screen') || ~isfield(cfg.screen,'max_packages_per_province_year'), return; end
maxN=cfg.screen.max_packages_per_province_year;
if ~isfinite(maxN) || maxN<=0, return; end
if isfield(cfg.screen,'max_packages_years') && ~isempty(cfg.screen.max_packages_years) && ...
        ~any(double(cfg.screen.max_packages_years(:))==double(year)), return; end
if numel(varargin{1})<=maxN, return; end
raw_MWh=varargin{5}; annual_cost=varargin{7}; cap_MW=varargin{4};
metric=string(cfg.screen.package_score_metric);
switch metric
    case "raw_MWh", score=-raw_MWh;
    case "capacity", score=-cap_MW;
    otherwise, score=annual_cost./max(raw_MWh,eps);
end
[~,ord]=sort(score,'ascend'); keep=sort(ord(1:maxN));
for k=1:numel(varargin)
    v=varargin{k};
    if iscell(v), varargout{k}=v(keep); else, varargout{k}=v(keep,:); end
end
end

function name=cache_filename(key)
name=['ramp_' char(rev04_hash_value(char(key))) '.mat'];
end
