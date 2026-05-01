function postprocess_loss_explorer(resultsFile)
%POSTPROCESS_LOSS_EXPLORER Interactive pie-chart loss explorer.
%
%   POSTPROCESS_LOSS_EXPLORER(resultsFile) loads a sweep result file and
%   displays an interactive efficiency map. Selecting a speed/torque point
%   updates the loss distribution at that operating point.
%
%   Speed is in rpm, regenerative torque is in N.m, powers and losses are
%   displayed in watts [W], and efficiencies are displayed in percent [%].
%
%   Losses are presented on a terminal-power basis. Battery A internal
%   source loss is excluded because Pba is already the terminal output power
%   from Battery A. Battery B loss and dump power are included when present.

if nargin < 1
    resultsFile = [];
end

%% 1) Resolve results source ------------------------------------------------
[S, sourceName] = loadSweepResults(resultsFile);

%% 2) Validate and unpack ---------------------------------------------------
need = {'speed_pts','torque_pts','SPD','TRQ'};

for k = 1:numel(need)
    if ~isfield(S, need{k})
        error('LossExplorer:MissingField', ...
              'Missing field "%s" in %s', need{k}, sourceName);
    end
end

speed_pts  = S.speed_pts;              % [rpm]
torque_pts = S.torque_pts;             % [N.m]
SPD        = S.SPD;                    % [rpm]
TRQ        = S.TRQ;                    % [N.m]
VALID      = logical(getFieldOr(S, 'VALID', true(size(SPD))));

ETA_map = getFieldOr(S, 'eta_rig', getFieldOr(S, 'eta_regen', nan(size(SPD)))); % [-]
PB_pct  = getFieldOr(S, 'PB_resid_pct', nan(size(SPD)));                        % [%]

LOSS_CU    = getFieldOr(S, 'Lcu_m', zeros(size(SPD))) + ...
             getFieldOr(S, 'Lcu_g', zeros(size(SPD)));       % [W]
LOSS_FE    = getFieldOr(S, 'Lfe_m', zeros(size(SPD))) + ...
             getFieldOr(S, 'Lfe_g', zeros(size(SPD)));       % [W]
LOSS_SHAFT = getFieldOr(S, 'Lshaft', zeros(size(SPD)));      % [W]
LOSS_INV1  = getFieldOr(S, 'Linv1', zeros(size(SPD)));       % [W]
LOSS_INV2  = getFieldOr(S, 'Linv2', zeros(size(SPD)));       % [W]
LOSS_DCDC  = getFieldOr(S, 'Ldcdc', zeros(size(SPD)));       % [W]
LOSS_BATB  = getFieldOr(S, 'LbatB', zeros(size(SPD)));       % [W]
LOSS_DUMP  = getFieldOr(S, 'Ldump', zeros(size(SPD)));       % [W]
LOSS_BUS   = getFieldOr(S, 'Pbus', zeros(size(SPD)));        % [W]

LOSS_TOT = getFieldOr(S, 'Ltot_explicit', ...
           LOSS_CU + LOSS_FE + LOSS_SHAFT + LOSS_INV1 + ...
           LOSS_INV2 + LOSS_DCDC + LOSS_BATB + LOSS_DUMP + LOSS_BUS);

WARN_ANY = getWarnMask(S, size(SPD));

fprintf('=== Loss Breakdown Explorer ===\n');
fprintf('Loaded: %s\n', sourceName);
fprintf('Valid points: %d / %d\n', nnz(VALID), numel(VALID));
fprintf('Warned valid points: %d\n', nnz(VALID & WARN_ANY));

%% 3) Build figure ----------------------------------------------------------
fig = figure('Name','Loss Breakdown Explorer', ...
             'Color','w', ...
             'Position',[100 100 1280 600]);

ax = subplot(1,2,1);

Z = ETA_map * 100;   % [%]
Z(~VALID) = NaN;

contourf(SPD, TRQ, Z, 20, 'LineColor','none');

cb = colorbar;
cb.Label.String = 'Efficiency (%)';

xlabel('Speed (rpm)');
ylabel('Regenerative torque (N.m)');
title('Click map or use dropdowns for terminal-basis loss pie');

grid on
box on
hold on
plotRejectedAndWarned(SPD, TRQ, VALID, WARN_ANY);
hold off

colormap turbo

panel = uipanel('Parent',fig, ...
                'Title','Select Operating Point', ...
                'FontSize',10, ...
                'Position',[0.55 0.08 0.4 0.84]);

uicontrol(panel,'Style','text', ...
          'String','Speed (rpm):', ...
          'Units','normalized', ...
          'Position',[0.08 0.89 0.35 0.055], ...
          'HorizontalAlignment','left');

speedMenu = uicontrol(panel,'Style','popupmenu', ...
          'String',cellstr(string(speed_pts)), ...
          'Units','normalized', ...
          'Position',[0.45 0.885 0.42 0.065]);

uicontrol(panel,'Style','text', ...
          'String','Torque (N.m):', ...
          'Units','normalized', ...
          'Position',[0.08 0.80 0.35 0.055], ...
          'HorizontalAlignment','left');

torqueMenu = uicontrol(panel,'Style','popupmenu', ...
          'String',cellstr(string(torque_pts)), ...
          'Units','normalized', ...
          'Position',[0.45 0.795 0.42 0.065]);

uicontrol(panel,'Style','pushbutton', ...
          'String','Generate Pie Chart', ...
          'Units','normalized', ...
          'Position',[0.24 0.70 0.52 0.075], ...
          'Callback',@generatePieFromDropdown);

statusText = uicontrol(panel,'Style','text', ...
          'String','', ...
          'Units','normalized', ...
          'Position',[0.08 0.61 0.84 0.075], ...
          'HorizontalAlignment','left');

pieAx = axes('Parent',panel, ...
             'Position',[0.08 0.08 0.84 0.50]);

%% 4) Attach click callback -------------------------------------------------
set(ax,'ButtonDownFcn',@clickCallback);

ch = get(ax,'Children');

for k = 1:numel(ch)
    try
        set(ch(k), ...
            'HitTest','on', ...
            'PickableParts','all', ...
            'ButtonDownFcn',@clickCallback);
    catch
    end
end

generatePie(1, 1);

    function clickCallback(~, ~)
        cp = get(ax,'CurrentPoint');

        x = cp(1,1);
        y = cp(1,2);

        [~, i] = min(abs(speed_pts - x));
        [~, j] = min(abs(torque_pts - y));

        speedMenu.Value = i;
        torqueMenu.Value = j;

        generatePie(j, i);
    end

    function generatePieFromDropdown(~, ~)
        i = speedMenu.Value;
        j = torqueMenu.Value;

        generatePie(j, i);
    end

    function generatePie(j, i)
        % Draw a terminal-basis loss pie chart for indices (j, i).

        cla(pieAx);
        axes(pieAx); 

        titleStr = sprintf('%g rpm / %g N.m', speed_pts(i), torque_pts(j));

        if ~VALID(j,i)
            text(0.05,0.55,'Selected point is invalid/rejected.', ...
                'Parent',pieAx);

            title(pieAx, titleStr);

            set(statusText,'String',sprintf('INVALID point at %s', titleStr));

            axis(pieAx,'off');
            return
        end

        losses = [ ...
            LOSS_CU(j,i), ...
            LOSS_FE(j,i), ...
            LOSS_SHAFT(j,i), ...
            LOSS_INV1(j,i), ...
            LOSS_INV2(j,i), ...
            LOSS_DCDC(j,i), ...
            LOSS_BATB(j,i), ...
            LOSS_DUMP(j,i), ...
            LOSS_BUS(j,i)];

        labels = {'Copper','Iron','Shaft','Inv1','Inv2', ...
                  'DC/DC','Battery B','Dump','DC bus'};

        keep = isfinite(losses) & losses > 0;

        losses = losses(keep);
        labels = labels(keep);

        if isempty(losses)
            text(0.05,0.55,'No positive loss data available.', ...
                'Parent',pieAx);

            axis(pieAx,'off');
        else
            pie(pieAx, losses, labels);
        end

        title(pieAx, sprintf('Terminal-basis loss breakdown at %s', titleStr));

        etaVal  = ETA_map(j,i) * 100;   % [%]
        pbVal   = PB_pct(j,i);          % [%]
        lossVal = LOSS_TOT(j,i)/1000;   % [kW]

        status = sprintf(['eta_rig = %.1f%% | loss = %.2f kW | ' ...
                          'PB = %.2f%% | VALID = %d'], ...
                          etaVal, lossVal, pbVal, VALID(j,i));

        if WARN_ANY(j,i)
            status = [status ' | WARNING']; 
        end

        set(statusText,'String',status);
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
        error('LossExplorer:MissingFile', ...
              'Results file not found: %s', resultsFile);
    end

    loadedData = load(resultsFile);
    sourceName = resultsFile;

    % Most sweep files store the actual result structure as loadedData.R.
    % If R is present, unwrap it. Otherwise use the loaded structure directly.
    if isfield(loadedData,'R')
        S = loadedData.R;
    else
        S = loadedData;
    end

    return
end

% Prefer workspace R to avoid path/save-folder issues during debugging.
if evalin('base', 'exist(''R'', ''var'')')
    S = evalin('base', 'R');
    sourceName = 'base workspace variable R';
    return
end

% Fallback to common MAT-file names in current folder.
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

error('LossExplorer:NoResults', ...
      ['No results found. Run the sweep first, or pass a MAT-file name, e.g. ', ...
       'postprocess_loss_explorer(''sweep_results_fixed_boundaries_full.mat'').']);
end

function WARN_ANY = getWarnMask(S, sz)
%GETWARNMASK Combine all warning masks that are present in the result file.

warnFields = {'PB_WARN','BATTA_WARN','INV1_WARN','MOTOR_WARN','GEN_WARN', ...
              'INV2_WARN','BUS_WARN','DCDC_WARN','BATTB_WARN','SHAFT_WARN'};

WARN_ANY = false(sz);

for i = 1:numel(warnFields)
    if isfield(S, warnFields{i})
        WARN_ANY = WARN_ANY | logical(S.(warnFields{i}));
    end
end
end

function plotRejectedAndWarned(SPD, TRQ, VALID, WARN_ANY)
%PLOTREJECTEDANDWARNED Mark rejected and warning points on the map.

bad  = ~VALID;
warn = VALID & WARN_ANY;

if any(bad(:))
    plot(SPD(bad), TRQ(bad), 'kx', ...
        'MarkerSize',8, ...
        'LineWidth',1.3);
end

if any(warn(:))
    plot(SPD(warn), TRQ(warn), 'ko', ...
        'MarkerSize',7, ...
        'LineWidth',1.2);
end
end

function v = getFieldOr(S, name, defaultVal)
%GETFIELDOR Return S.name if it exists, otherwise return defaultVal.

if isfield(S, name)
    v = S.(name);
else
    v = defaultVal;
end
end