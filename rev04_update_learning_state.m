function state = rev04_update_learning_state(state, additions, year)
% Update cumulative deployment only after all provinces in a planning year solve.

names = fieldnames(state.Qmodel);
for i = 1:numel(names)
    k = names{i};
    if isfield(additions, k)
        state.Qmodel.(k) = state.Qmodel.(k) + additions.(k);
    end
end
state.last_year = year;
end
