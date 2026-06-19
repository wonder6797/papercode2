function T = rev04_path_rdu_table(case_outputs, provinces)
% Flatten active RDU vintage cohorts for spatial expansion analysis.

T=table(); cases=string(fieldnames(case_outputs));
for ci=1:numel(cases)
    assets=case_outputs.(char(cases(ci))).assets;
    for p=1:numel(assets)
        q=assets{p}.wind_cohorts;
        for i=1:numel(q)
            row=table(cases(ci),string(provinces(p)),q(i).build_year,q(i).site_idx,string(q(i).rdu_id), ...
                q(i).turbine_idx,q(i).package_idx,q(i).share,q(i).area_dev_km2,q(i).density_MW_per_km2,q(i).cap_MW, ...
                'VariableNames',{'Scenario','Province','BuildYear','RDUIndex','RDUId','TurbineIndex','PackageIndex', ...
                'DevelopedFraction','DevelopedArea_km2','Density_MW_per_km2','DevelopedCapacity_MW'});
            T=[T;row]; %#ok<AGROW>
        end
    end
end
end
