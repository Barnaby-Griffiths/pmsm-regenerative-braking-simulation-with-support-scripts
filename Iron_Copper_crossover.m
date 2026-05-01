function Iron_Copper_crossover(resultsFile)
%% =========================================================================
% plot_iron_copper_crossover.m
%
% Overlays the iron-vs-copper crossover contour on the eta_rig efficiency
% map. The crossover is the locus of operating points at which total iron
% loss equals total copper loss. Below the curve copper dominates; above
% the curve iron dominates.
%
% Usage:
%   plot_iron_copper_crossover                                  % auto-find
%   plot_iron_copper_crossover('sweep_results_full.mat')        % explicit
%% =========================================================================

if nargin < 1 || isempty(resultsFile)
    candidates = { ...
        'sweep_results_fixed_boundaries_full.mat', ...
        'sweep_results_fixed_boundaries_fast.mat'};
    resultsFile = '';
    for k = 1:numel(candidates)
        if exist(candidates{k}, 'file') == 2
            resultsFile = candidates{k};
            break
        end
    end
    if isempty(resultsFile)
        error('No sweep results file found.');
    end
end
fprintf('Loading %s\n', resultsFile);

D = load(resultsFile);
if isfield(D,'R'), D = D.R; end   % accommodate either flat or wrapped

%% Unpack
SPD        = D.SPD;
TRQ        = D.TRQ;
VALID      = D.VALID;
speed_pts  = D.speed_pts;
torque_pts = D.torque_pts;

LOSS_CU = D.Lcu_m + D.Lcu_g;     % [W] both machines
LOSS_FE = D.Lfe_m + D.Lfe_g;     % [W] both machines

DELTA = LOSS_FE - LOSS_CU;       % [W] positive => iron dominates
DELTA(~VALID) = NaN;

ETA = D.eta_rig * 100;           % [%]
ETA(~VALID) = NaN;

%% Find crossover speed at each torque level
[nT, ~] = size(DELTA);
crossover_speed = nan(nT, 1);    % [RPM]

for j = 1:nT
    row = DELTA(j, :);
    idx = find(row > 0, 1, 'first');
    if ~isempty(idx) && idx > 1
        x1 = speed_pts(idx-1); x2 = speed_pts(idx);
        y1 = row(idx-1);       y2 = row(idx);
        if isfinite(y1) && isfinite(y2) && (y2 - y1) ~= 0
            crossover_speed(j) = x1 - y1 * (x2 - x1) / (y2 - y1);
        end
    end
end

%% Plot
figure('Name','Iron vs Copper Crossover','Position',[80 80 900 600],'Color','w');
contourf(SPD, TRQ, ETA, 18, 'LineStyle', 'none');
hold on;
colorbar;
xlabel('Speed (RPM)');
ylabel('Torque (Nm)');
title('\eta_{rig} (%) with iron = copper crossover overlay');
grid on;

% Zero contour of (Fe - Cu)
contour(SPD, TRQ, DELTA, [0 0], 'k-', 'LineWidth', 2.5);

% Mark crossover points along the line
valid_cross = ~isnan(crossover_speed);
if any(valid_cross)
    plot(crossover_speed(valid_cross), torque_pts(valid_cross), ...
         'ko-', 'MarkerSize', 5, 'MarkerFaceColor', 'w', 'LineWidth', 1.5);
end

% Region annotations
text(1500, -180, {'\bfCopper-dominated','I^2R losses scale','with torque demand'}, ...
    'Color', 'k', 'BackgroundColor', [1 1 1 0.7], ...
    'EdgeColor', 'k', 'FontSize', 9, 'Margin', 3);

text(4300, -40, {'\bfIron-dominated','Hysteresis + eddy','grow with speed'}, ...
    'Color', 'k', 'BackgroundColor', [1 1 1 0.7], ...
    'EdgeColor', 'k', 'FontSize', 9, 'Margin', 3);

colormap turbo

%% Print summary
fprintf('\n=== Iron-vs-Copper Crossover Summary ===\n');
fprintf('Crossover speed at each torque level:\n');
fprintf('  Torque (Nm)   Crossover speed (RPM)\n');
for j = 1:nT
    if ~isnan(crossover_speed(j))
        fprintf('    %7.0f         %6.0f\n', torque_pts(j), crossover_speed(j));
    end
end

if any(valid_cross)
    cross_torques = torque_pts(valid_cross);
    cross_speeds  = crossover_speed(valid_cross);
    [smin, jmin] = min(cross_speeds);
    [smax, jmax] = max(cross_speeds);
    fprintf('\nMin crossover speed: %.0f RPM at %.0f Nm\n', smin, cross_torques(jmin));
    fprintf('Max crossover speed: %.0f RPM at %.0f Nm\n', smax, cross_torques(jmax));
end

fprintf('\nExport with: print -dpng -r300 iron_copper_crossover.png\n');
end