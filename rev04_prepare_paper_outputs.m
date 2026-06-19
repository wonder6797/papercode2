function out=rev04_prepare_paper_outputs(output_root)
%REV04_PREPARE_PAPER_OUTPUTS Build paper figures and Step 2 small QA tables.
if nargin<1 || strlength(string(output_root))==0
    cfg=rev04_default_config(); output_root=cfg.output_root;
end
output_root=string(output_root);
paper_dir=fullfile(output_root,'paper_analysis_01');
figure_dir=fullfile(paper_dir,'figures');
if ~isfolder(figure_dir), mkdir(figure_dir); end

step1=find_latest_run(output_root,'step1_GX_GD_S2_2050_*');
step2=find_latest_run(output_root,'step2_GX_GD_S0_S2_path_*');
step3=find_latest_run(output_root,'step3_hourly_corridor_GX_GD_S2_2050_*',false);

manifest=table();
manifest=[manifest;make_figure(step1,'Guangdong', ...
    'Fig_main_dispatch_Guangdong_S2_2050_stage2.png', ...
    'Guangdong S2 2050 Stage2','main_monthly_upper_smooth')]; %#ok<AGROW>
manifest=[manifest;make_figure(step1,'Guangxi', ...
    'Fig_appendix_dispatch_Guangxi_S2_2050_stage2.png', ...
    'Guangxi S2 2050 Stage2','appendix_resource_limited')]; %#ok<AGROW>
if strlength(step3)>0
    manifest=[manifest;make_figure(step3,'Guangdong', ...
        'Fig_sensitivity_hourly_corridor_Guangdong_S2_2050_stage2.png', ...
        'Guangdong S2 2050 Stage2 hourly corridor','sensitivity_hourly_corridor')]; %#ok<AGROW>
    manifest=[manifest;make_figure(step3,'Guangxi', ...
        'Fig_sensitivity_hourly_corridor_Guangxi_S2_2050_stage2.png', ...
        'Guangxi S2 2050 Stage2 hourly corridor','sensitivity_hourly_corridor')]; %#ok<AGROW>
end
writetable(manifest,fullfile(paper_dir,'qa_paper_figure_manifest.csv'));

summary_file=find_summary_file(step2);
S=readtable(summary_file,'TextType','string');
monthly=table(S.Province,S.Scenario,S.Year,S.MonthlyBandDelta, ...
    1-S.MonthlyBandDelta,1+S.MonthlyBandDelta, ...
    repmat(true,height(S),1), ...
    'VariableNames',{'Province','Scenario','Year','MonthlyBandDelta', ...
    'MonthlyLowerMultiplierUsed','MonthlyUpperMultiplierUsed','MonthlyLowerConstraintActive'});
writetable(monthly,fullfile(paper_dir,'qa_monthly_band_multipliers_step2.csv'));

denom_MWh=S.Contract_TWh*1e6;
decomp=table(S.Province,S.Scenario,S.Year,S.LCOE_contract_USD_per_MWh, ...
    S.CostWind_USDyr./denom_MWh,S.CostProjectBESS_USDyr./denom_MWh, ...
    S.CostSystemBESS_USDyr./denom_MWh,S.CostVRB_USDyr./denom_MWh, ...
    S.CostH2_USDyr./denom_MWh,S.CostOperation_USDyr./denom_MWh, ...
    S.UpperBandBindingHours,S.CurtailmentRate, ...
    S.MonthlyBandBindingMonthsLow,S.MonthlyBandBindingMonthsHigh, ...
    'VariableNames',{'Province','Scenario','Year','LCOE_contract', ...
    'Wind_LCOE_component','ProjectBESS_LCOE_component','SystemBESS_LCOE_component', ...
    'VRB_LCOE_component','H2_LCOE_component','Operation_LCOE_component', ...
    'UpperBandBindingHours','CurtailmentRate','MonthlyBandBindingMonthsLow', ...
    'MonthlyBandBindingMonthsHigh'});
writetable(decomp,fullfile(paper_dir,'qa_lcoe_component_decomposition_step2.csv'));

log_file=fullfile(paper_dir,'paper_analysis_log.txt');
fid=fopen(log_file,'w');
fprintf(fid,'[MonthlyBand] monthly_upper_smooth includes both monthly lower and upper bounds.\n');
fprintf(fid,'[MonthlyBand] Edel_month >= 0.70 * Eshape_month.\n');
fprintf(fid,'[MonthlyBand] Edel_month <= 1.30 * Eshape_month.\n');
fprintf(fid,'[CostBasis] Stage2 is used for smoothed dispatch figures; engineering LCOE uses Stage1 cost.\n');
fprintf(fid,'[Step2Source] %s\n',summary_file);
fclose(fid);
fprintf('[MonthlyBand] Edel_month >= 0.70 * Eshape_month and <= 1.30 * Eshape_month.\n');

out=struct('paper_dir',paper_dir,'figure_manifest',manifest, ...
    'monthly_band_qa',monthly,'lcoe_decomposition',decomp,'log_file',log_file);

    function row=make_figure(run_dir,province,file_name,title_text,product)
        result_file=fullfile(run_dir,'lp_results',sprintf('result_S2_%s_2050.mat',province));
        output_file=fullfile(figure_dir,file_name);
        row=rev04_generate_paper_dispatch_figure(result_file,output_file,title_text,product);
    end
end

function run_dir=find_latest_run(root,pattern,required)
if nargin<3, required=true; end
d=dir(fullfile(root,pattern)); d=d([d.isdir]);
if isempty(d)
    if required, error('No run directory matching %s.',pattern); end
    run_dir=""; return
end
[~,k]=max([d.datenum]); run_dir=string(fullfile(d(k).folder,d(k).name));
end

function file=find_summary_file(run_dir)
candidates=["path_summary.csv","path_summary1.csv"];
for k=1:numel(candidates)
    f=fullfile(run_dir,candidates(k));
    if isfile(f), file=string(f); return; end
end
error('No Step 2 path summary found in %s.',run_dir);
end
