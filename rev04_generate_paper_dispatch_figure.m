function info = rev04_generate_paper_dispatch_figure(result_file, output_file, figure_title, product_label)
%REV04_GENERATE_PAPER_DISPATCH_FIGURE Four-panel Stage 2 paper figure.
S=load(result_file,'r');
assert(isfield(S,'r') && S.r.feasible,'Missing feasible result in %s.',result_file);
r=S.r;
assert(isfield(r,'smooth') && r.smooth.stage2_used, ...
    'The paper figure requires a used Stage 2 solution.');

T=numel(r.Pdel_MW);
ts=datetime(2025,1,1,0,0,0)+hours(0:(T-1));
winter_start=representative_week_start(ts,r.raw_wind_profile_MW,[12 1 2]);
summer_start=representative_week_start(ts,r.raw_wind_profile_MW,[6 7 8]);
winter_ix=winter_start:(winter_start+167);
summer_ix=summer_start:(summer_start+167);
storage_net=r.bess.discharge_MW-r.bess.charge_MW+ ...
    r.vrb.discharge_MW-r.vrb.charge_MW+r.h2.gen_MW-r.h2.el_MW;

f=figure('Visible','off','Color','w','Position',[100 100 1500 980]);
tl=tiledlayout(2,2,'TileSpacing','compact','Padding','compact');
plot_week(nexttile,winter_ix,'(a) Winter typical week');
plot_week(nexttile,summer_ix,'(b) Summer typical week');

ax=nexttile;
plot(ax,sort(r.project_output_profile_MW,'descend'),'Color',[0.15 0.45 0.78],'LineWidth',1.2); hold(ax,'on');
plot(ax,sort(r.Pshape_MW,'descend'),'--','Color',[0.85 0.25 0.20],'LineWidth',1.2);
plot(ax,sort(r.Pdel_MW,'descend'),'Color',[0.10 0.60 0.30],'LineWidth',1.35);
grid(ax,'on'); xlabel(ax,'Sorted hour'); ylabel(ax,'Power (MW)');
title(ax,'(c) 8760-hour duration curve');
legend(ax,{'After project BESS','Pshape','Stage2 Pdel'},'Location','northeast','Box','off');

ax=nexttile;
plot(ax,1:168,storage_net(summer_ix),'Color',[0.48 0.25 0.68],'LineWidth',1.2); hold(ax,'on');
plot(ax,1:168,r.system_curt_MW(summer_ix),'Color',[0.93 0.55 0.10],'LineWidth',1.15);
yline(ax,0,'Color',[0.45 0.45 0.45],'LineStyle',':');
grid(ax,'on'); xlim(ax,[1 168]); xlabel(ax,'Hour of typical week'); ylabel(ax,'Power (MW)');
title(ax,'(d) Summer flexibility diagnostic');
legend(ax,{'Storage net output','System curtailment'},'Location','best','Box','off');

title(tl,figure_title,'FontWeight','bold');
subtitle(tl,'Stage2 smooths dispatch only; engineering LCOE uses Stage1 cost.');
if ~isfolder(fileparts(output_file)), mkdir(fileparts(output_file)); end
exportgraphics(f,output_file,'Resolution',300);
close(f);

info=table(string(r.province),r.year,"S2","Stage2",string(product_label), ...
    string(result_file),string(output_file),winter_start,summer_start, ...
    "Stage2 dispatch; Stage1 engineering cost", ...
    'VariableNames',{'Province','Year','Scenario','Stage','Product','SourceResult', ...
    'OutputFile','WinterWeekStartHour','SummerWeekStartHour','CostBasisNote'});
fprintf('[PaperFigure] %s\n',output_file);
fprintf('[PaperFigure] Stage2 smooths dispatch only; engineering LCOE uses Stage1 cost.\n');

    function plot_week(ax,ix,panel_title)
        plot(ax,1:168,r.raw_wind_profile_MW(ix),'Color',[0.68 0.68 0.68],'LineWidth',1.0); hold(ax,'on');
        plot(ax,1:168,r.project_output_profile_MW(ix),'Color',[0.15 0.45 0.78],'LineWidth',1.15);
        plot(ax,1:168,r.Pshape_MW(ix),'--','Color',[0.85 0.25 0.20],'LineWidth',1.15);
        plot(ax,1:168,r.Pdel_MW(ix),'Color',[0.10 0.60 0.30],'LineWidth',1.3);
        grid(ax,'on'); xlim(ax,[1 168]); xlabel(ax,'Hour of typical week'); ylabel(ax,'Power (MW)');
        title(ax,panel_title);
        legend(ax,{'Raw wind','After project BESS','Pshape','Stage2 Pdel'}, ...
            'Location','best','Box','off');
    end
end

function start=representative_week_start(ts,raw,months)
week_starts=1:168:(numel(raw)-167);
ok=false(size(week_starts)); values=zeros(size(week_starts));
for k=1:numel(week_starts)
    ok(k)=any(month(ts(week_starts(k)+84))==months);
    values(k)=mean(raw(week_starts(k):(week_starts(k)+167)));
end
candidates=week_starts(ok); candidate_values=values(ok);
assert(~isempty(candidates),'No representative week candidate found.');
[~,j]=min(abs(candidate_values-median(candidate_values)));
start=candidates(j);
end
