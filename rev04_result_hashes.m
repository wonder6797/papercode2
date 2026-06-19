function H = rev04_result_hashes(cfg,I,cost,state,province,year,scenario)
%REV04_RESULT_HASHES Fingerprints required before a saved LP may be resumed.
H=struct();
H.config_hash=rev04_hash_value(cfg);
input_signature=struct( ...
    'input_mat',file_signature(cfg.input_mat), ...
    'load_xlsx',file_signature(cfg.load_xlsx), ...
    'province',string(province),'year',double(year),'scenario',string(scenario), ...
    'target_MWh',I.Etarget_MWh(I.prov_names==string(province),I.years==year), ...
    'state',state,'cost',cost,'T',I.T,'g_pu_size',size(I.g_pu));
H.input_hash=rev04_hash_value(input_signature);
H.code_version_hash=code_hash(cfg.root);
H.solver_setting_hash=rev04_hash_value(cfg.solver);
end

function s=file_signature(path)
d=dir(path);
if isempty(d)
    s=struct('path',string(path),'exists',false,'bytes',NaN,'datenum',NaN);
else
    s=struct('path',string(path),'exists',true,'bytes',d.bytes,'datenum',d.datenum);
end
end

function h=code_hash(root)
persistent cached_root cached_signature cached_hash
repo_root=fileparts(root);
files=dir(fullfile(repo_root,'**','rev04_*.m'));
[~,ord]=sort(string({files.folder})+"/"+string({files.name}));
files=files(ord);
sig=string({files.folder})+"/"+string({files.name})+":"+string([files.datenum])+":"+string([files.bytes]);
signature=strjoin(sig,"|");
if ~isempty(cached_root) && cached_root==string(repo_root) && cached_signature==signature
    h=cached_hash; return
end
payload=cell(numel(files),2);
for k=1:numel(files)
    full=fullfile(files(k).folder,files(k).name);
    payload{k,1}=erase(string(full),string(repo_root)+filesep);
    payload{k,2}=fileread(full);
end
h=rev04_hash_value(payload);
cached_root=string(repo_root); cached_signature=signature; cached_hash=h;
end
