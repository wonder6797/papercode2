function [cfg, load_data, I] = rev04_initialize(cfg)
% Prepare validated load and stable spatial/wind inputs.

if nargin < 1 || isempty(cfg), cfg=rev04_default_config(); end
load_data=rev04_prepare_hourly_load(string(cfg.load_xlsx),cfg);
I=rev04_build_inputs(cfg,load_data);
end
