function ybar = avg_ts(ts, t1, t2)
%% =========================================================================
% avg_ts.m
%
% Average value of a signal over the window [t1, t2] for a timeseries,
% Simulink.SimulationData.Signal, or struct with a Values field.
%% =========================================================================

[t, y] = local_tsTY(ts);
idx = (t >= t1) & (t <= t2);

if ~any(idx)
    ybar = NaN;
else
    ybar = mean(y(idx), 'omitnan');
end
end

function [t, y] = local_tsTY(ts)
%% Extract time and data vectors from a supported signal type
if isa(ts,'timeseries')
    t = ts.Time(:);
    y = squeeze(ts.Data);
elseif isa(ts,'Simulink.SimulationData.Signal')
    t = ts.Values.Time(:);
    y = squeeze(ts.Values.Data);
elseif isstruct(ts) && isfield(ts,'Values')
    t = ts.Values.Time(:);
    y = squeeze(ts.Values.Data);
else
    error('avg_ts:UnsupportedType','Unsupported signal type: %s', class(ts));
end

y = y(:);
if numel(y) ~= numel(t)
    y = reshape(y, numel(t), []);
    y = y(:,1);
end
end