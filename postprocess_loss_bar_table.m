function postprocess_loss_bar_table(resultsFile, targetSpeed, targetTorque)
%POSTPROCESS_LOSS_BAR_TABLE Interactive loss bar-chart and table explorer.
%
%   POSTPROCESS_LOSS_BAR_TABLE loads the completed sweep result structure R
%   and displays an interactive efficiency map. Selecting an operating point
%   by clicking the map, using the dropdown menus, or passing a target speed
%   and torque produces a terminal-basis loss breakdown as a bar chart and
%   table.
%
%   Usage:
%       postprocess_loss_bar_table
%       postprocess_loss_bar_table('sweep_results_fixed_boundaries_full.mat')
%       postprocess_loss_bar_table('sweep_results_fixed_boundaries_full.mat',3000,-100)
%
%   Speed is plotted in rpm, regenerative torque in N.m, losses in W and kW,
%   and efficiencies in percent.
%
%   Terminal-basis loss accounting:
%       - Battery A internal source loss is excluded because Pba is already
%         the terminal output power from Battery A.
%       - Battery B loss, dump-resistor power and DC-bus loss are included
%         when present in the sweep result structure.

if nargin < 1
    resultsFile = [];
end

if nargin < 2
    targetSpeed = [];
end

if nargin < 3
    targetTorque = [];
end

%% 1) Resolve results source ------------------------------------------------
[S, sourceName] = loadSweepResults(resultsFile);

%% 2) Validate required grid fields ----------------------------------------
requiredFields = {'speed_pts','torque_pts','SPD','TRQ'};

for k = 1:numel(requiredFields)
    if ~isfield(S, requiredFields{k})
        error('LossBarTable:MissingField', ...
              'The results source is missing required field: %s', requiredFields{k});
    end
end

speed_pts  = S.speed_pts(:).';       % [rpm]
torque_pts = S.torque_pts(:).';      % [N.m]
SPD        = S.SPD;                  % [rpm]
TRQ        = S.TRQ;                  % [N.m]

VALID   = logical(getFieldOr(S, 'VALID', true(size(SPD))));
ETA_map = getFieldOr(S, 'eta_rig', getFieldOr(S, 'eta_regen', nan(size(SPD))));
REJECT  = getFieldOr(S, 'REJECT', zeros(size(SPD)));

warnMask = getWarnMask(S, size(SPD));

fprintf('=== Loss Bar/Table Explorer ===\n');
fprintf('Loaded: %s\n', sourceName);
fprintf('Valid points: %d / %d\n', nnz(VALID), numel(VALID));
fprintf('Warned valid points: %d\n', nnz(VALID & warnMask));

%% 3) Build figure ----------------------------------------------------------
fig = figure('Name','Loss Bar/Table Explorer', ...
             'NumberTitle','off', ...
             'Color','w', ...
             'Position',[80 80 1350 720]);

%% Left-hand efficiency map
mapAx = axes('Parent',fig, ...
             'Position',[0.06 0.13 0.40 0.78]);

Z = ETA_map * 100;       % [%]
Z(~VALID) = NaN;

contourf(mapAx, SPD, TRQ, Z, 20, 'LineColor','none');

cb = colorbar(mapAx);
cb.Label.String = 'Efficiency (%)';
cb.Label.FontWeight = 'bold';

xlabel(mapAx,'Speed (rpm)');
ylabel(mapAx,'Regenerative torque (N.m)');
title(mapAx,'Select operating point for terminal-basis loss breakdown', ...
    'FontWeight','bold');

grid(mapAx,'on');
box(mapAx,'on');
colormap(mapAx,turbo);

set(mapAx, ...
    'Color','w', ...
    'XColor','k', ...
    'YColor','k', ...
    'GridColor',[0.65 0.65 0.65], ...
    'FontSize',10, ...
    'LineWidth',0.8);

hold(mapAx,'on');

bad = ~VALID | REJECT ~= 0;

if any(bad(:))
    plot(mapAx, SPD(bad), TRQ(bad), 'kx', ...
        'MarkerSize',8, ...
        'LineWidth',1.2);
end

warnMask = warnMask & VALID;

if any(warnMask(:))
    plot(mapAx, SPD(warnMask), TRQ(warnMask), 'ko', ...
        'MarkerSize',7, ...
        'LineWidth',1.0);
end

hold(mapAx,'off');

%% Right-hand control and output panel
panel = uipanel('Parent',fig, ...
                'Title','Selected Operating Point', ...
                'FontSize',10, ...
                'Position',[0.51 0.06 0.46 0.88]);

uicontrol(panel,'Style','text', ...
          'String','Speed (rpm):', ...
          'Units','normalized', ...
          'Position',[0.04 0.92 0.17 0.045], ...
          'HorizontalAlignment','left');

speedMenu = uicontrol(panel,'Style','popupmenu', ...
          'String',cellstr(string(speed_pts)), ...
          'Units','normalized', ...
          'Position',[0.21 0.92 0.18 0.050]);

uicontrol(panel,'Style','text', ...
          'String','Torque (N.m):', ...
          'Units','normalized', ...
          'Position',[0.43 0.92 0.17 0.045], ...
          'HorizontalAlignment','left');

torqueMenu = uicontrol(panel,'Style','popupmenu', ...
          'String',cellstr(string(torque_pts)), ...
          'Units','normalized', ...
          'Position',[0.60 0.92 0.18 0.050]);

uicontrol(panel,'Style','pushbutton', ...
          'String','Update', ...
          'Units','normalized', ...
          'Position',[0.82 0.915 0.13 0.060], ...
          'Callback',@generateFromDropdown);

statusText = uicontrol(panel,'Style','text', ...
          'String','', ...
          'Units','normalized', ...
          'Position',[0.04 0.855 0.91 0.045], ...
          'HorizontalAlignment','left');

barAx = axes('Parent',panel, ...
             'Position',[0.08 0.43 0.86 0.39]);

lossTable = uitable('Parent',panel, ...
          'Units','normalized', ...
          'Position',[0.04 0.055 0.92 0.315], ...
          'ColumnName',{'Loss component','Power [W]','Power [kW]','Share [%]'}, ...
          'ColumnEditable',[false false false false], ...
          'RowName',[]);

%% 4) Attach click callback to map and children -----------------------------
set(mapAx,'ButtonDownFcn',@clickCallback);

mapChildren = get(mapAx,'Children');

for k = 1:numel(mapChildren)
    try
        set(mapChildren(k), ...
            'HitTest','on', ...
            'PickableParts','all', ...
            'ButtonDownFcn',@clickCallback);
    catch
    end
end

%% 5) Initial selected point -------------------------------------------------
if ~isempty(targetSpeed) && ~isempty(targetTorque)

    [~, i0] = min(abs(speed_pts - targetSpeed));
    [~, j0] = min(abs(torque_pts - targetTorque));

else

    validIdx = find(VALID, 1, 'first');

    if isempty(validIdx)
        j0 = 1;
        i0 = 1;
    else
        [j0, i0] = ind2sub(size(VALID), validIdx);
    end
end

speedMenu.Value = i0;
torqueMenu.Value = j0;

generateBarAndTable(j0, i0);

%% Nested callbacks ---------------------------------------------------------
    function clickCallback(~, ~)

        cp = get(mapAx,'CurrentPoint');

        clickedSpeed  = cp(1,1);
        clickedTorque = cp(1,2);

        [~, i] = min(abs(speed_pts - clickedSpeed));
        [~, j] = min(abs(torque_pts - clickedTorque));

        speedMenu.Value = i;
        torqueMenu.Value = j;

        generateBarAndTable(j, i);
    end

    function generateFromDropdown(~, ~)

        i = speedMenu.Value;
        j = torqueMenu.Value;

        generateBarAndTable(j, i);
    end

    function generateBarAndTable(j, i)

        cla(barAx);

        selectedSpeed  = speed_pts(i);
        selectedTorque = torque_pts(j);

        if ~VALID(j,i)

            text(barAx,0.05,0.50,'Selected point is invalid or rejected.', ...
                'Units','normalized', ...
                'FontSize',11);

            title(barAx,sprintf('%g rpm / %g N.m', selectedSpeed, selectedTorque));

            lossTable.Data = {'Rejected/invalid point', NaN, NaN, NaN};

            statusText.String = sprintf('INVALID: %.0f rpm / %.0f N.m | REJECT = %g', ...
                selectedSpeed, selectedTorque, REJECT(j,i));

            return
        end

        [labels, losses] = getLossVector(S, j, i);

        validLoss = isfinite(losses) & losses > 0;
        totalLoss = sum(losses(validLoss));

        labelsPlot = labels(validLoss);
        lossesPlot = losses(validLoss);

        if isempty(lossesPlot)

            text(barAx,0.05,0.50,'No positive loss data available.', ...
                'Units','normalized', ...
                'FontSize',11);

        else

            bar(barAx, lossesPlot/1000);

            set(barAx, ...
                'XTick',1:numel(lossesPlot), ...
                'XTickLabel',labelsPlot, ...
                'XTickLabelRotation',35);

            ylabel(barAx,'Loss power (kW)');
            grid(barAx,'on');
            box(barAx,'on');

            set(barAx, ...
                'Color','w', ...
                'XColor','k', ...
                'YColor','k', ...
                'GridColor',[0.65 0.65 0.65], ...
                'FontSize',9, ...
                'LineWidth',0.8);
        end

        title(barAx,sprintf('Loss breakdown at %.0f rpm / %.0f N.m', ...
            selectedSpeed, selectedTorque), ...
            'FontWeight','bold');

        lossTable.Data = buildLossTable(labels, losses, totalLoss);

        etaRig   = getScalar(S, 'eta_rig',        j, i, NaN) * 100;
        etaRegen = getScalar(S, 'eta_regen',      j, i, NaN) * 100;
        pbResid  = getScalar(S, 'PB_resid_pct',   j, i, NaN);
        ltot     = getScalar(S, 'Ltot_explicit',  j, i, totalLoss);

        statusText.String = sprintf(['VALID: %.0f rpm / %.0f N.m | ', ...
            'eta_rig = %.1f%% | eta_regen = %.1f%% | ', ...
            'total plotted loss = %.2f kW | PB residual = %.2f%%'], ...
            selectedSpeed, selectedTorque, etaRig, etaRegen, ltot/1000, pbResid);
    end
end

function [S, sourceName] = loadSweepResults(resultsFile)
%LOADSWEEPRESULTS Load sweep result structure from workspace R or MAT-file.

if nargin >= 1 && ~isempty(resultsFile)

    if isstruct(resultsFile)
        S = resultsFile;
        sourceName = 'input struct';
        return
    end

    if exist(resultsFile, 'file') ~= 2
        error('LossBarTable:MissingFile', ...
              'Results file not found: %s', resultsFile);
    end

    loadedData = load(resultsFile);
    sourceName = resultsFile;

    if isfield(loadedData,'R')
        S = loadedData.R;
    else
        S = loadedData;
    end

    return
end

if evalin('base', 'exist(''R'', ''var'')')
    S = evalin('base', 'R');
    sourceName = 'base workspace variable R';
    return
end

candidates = { ...
    'sweep_results_fixed_boundaries_full.mat', ...
    'sweep_results_fixed_boundaries_fast.mat', ...
    'sweep_results_MATCHED.mat', ...
    'sweep_results.mat'};

for k = 1:numel(candidates)

    if exist(candidates{k}, 'file') == 2

        loadedData = load(candidates{k});
        sourceName = candidates{k};

        if isfield(loadedData,'R')
            S = loadedData.R;
        else
            S = loadedData;
        end

        return
    end
end

error('LossBarTable:NoResults', ...
      ['No results found. Run the sweep first, or pass a MAT-file name, e.g. ', ...
       'postprocess_loss_bar_table(''sweep_results_fixed_boundaries_full.mat'').']);
end

function [labels, losses] = getLossVector(S, j, i)
%GETLOSSVECTOR Return terminal-basis loss vector for one grid point.

labels = { ...
    'Motor copper', ...
    'Motor iron', ...
    'Shaft', ...
    'Generator copper', ...
    'Generator iron', ...
    'Inverter 1', ...
    'Inverter 2', ...
    'DC bus', ...
    'DC/DC', ...
    'Battery B', ...
    'Dump'};

losses = [ ...
    getScalar(S,'Lcu_m',  j, i, 0), ...
    getScalar(S,'Lfe_m',  j, i, 0), ...
    getScalar(S,'Lshaft', j, i, 0), ...
    getScalar(S,'Lcu_g',  j, i, 0), ...
    getScalar(S,'Lfe_g',  j, i, 0), ...
    getScalar(S,'Linv1',  j, i, 0), ...
    getScalar(S,'Linv2',  j, i, 0), ...
    getScalar(S,'Pbus',   j, i, 0), ...
    getScalar(S,'Ldcdc',  j, i, 0), ...
    getScalar(S,'LbatB',  j, i, 0), ...
    getScalar(S,'Ldump',  j, i, 0)];

losses = abs(losses);
end

function rows = buildLossTable(labels, losses, totalLoss)
%BUILDLOSSTABLE Build table rows with a total row at the bottom.

n = numel(labels);
rows = cell(n+1, 4);

for k = 1:n

    if isfinite(losses(k)) && losses(k) > 0 && totalLoss > 0
        share = 100 * losses(k) / totalLoss;
    else
        share = 0;
    end

    rows{k,1} = labels{k};
    rows{k,2} = round(losses(k), 1);
    rows{k,3} = round(losses(k)/1000, 3);
    rows{k,4} = round(share, 2);
end

rows{n+1,1} = 'TOTAL';
rows{n+1,2} = round(totalLoss, 1);
rows{n+1,3} = round(totalLoss/1000, 3);

if totalLoss > 0
    rows{n+1,4} = 100.00;
else
    rows{n+1,4} = 0.00;
end
end

function val = getScalar(S, fieldName, j, i, defaultVal)
%GETSCALAR Safely extract a scalar value from a matrix field.

if isfield(S, fieldName)

    A = S.(fieldName);

    try
        val = A(j,i);

        if isempty(val) || ~isfinite(val)
            val = defaultVal;
        end

    catch
        val = defaultVal;
    end

else
    val = defaultVal;
end
end

function WARN_ANY = getWarnMask(S, sz)
%GETWARNMASK Combine all warning masks present in the result structure.

warnFields = {'PB_WARN','BATTA_WARN','INV1_WARN','MOTOR_WARN','GEN_WARN', ...
              'INV2_WARN','BUS_WARN','DCDC_WARN','BATTB_WARN','SHAFT_WARN'};

WARN_ANY = false(sz);

for i = 1:numel(warnFields)

    if isfield(S, warnFields{i})
        WARN_ANY = WARN_ANY | logical(S.(warnFields{i}));
    end
end
end

function v = getFieldOr(S, name, defaultVal)
%GETFIELDOR Return S.(name) if present, otherwise return defaultVal.

if isfield(S, name)
    v = S.(name);
else
    v = defaultVal;
end
end