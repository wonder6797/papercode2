function state = rev04_init_learning_state(cfg)
% Initialize cumulative model deployment used by the Rev04 learning curve.

components = fieldnames(cfg.learning.component_Q0);
for i = 1:numel(components)
    state.Qmodel.(components{i}) = 0;
end
state.last_year = cfg.years(1) - 1;
end
