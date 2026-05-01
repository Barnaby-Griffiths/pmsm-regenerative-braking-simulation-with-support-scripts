function Best_eff_loci(resultsFile)
%% =========================================================================
% Best_eff_loci.m
%
% Computes and plots the locus of operating points that maximises eta_rig
% and eta_regen at each commanded speed.
%
% Keeps the original Rogue_1 data handling and background contour map,
% but uses a cleaner overlay style for the loci, peak markers, labels,
% and legend.
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
if isfield(D,'R')
    D = D.R;
end

%% Unpack
SPD        = D.SPD;
TRQ        = D.TRQ;
VALID      = D.VALID;
speed_pts  = D.speed_pts;
torque_pts = D.torque_pts;

ETA_RIG   = D.eta_rig   * 100;
ETA_REGEN = D.eta_regen * 100;

ETA_RIG(~VALID)   = NaN;
ETA_REGEN(~VALID) = NaN;

%% Restrict to the reliable region (torque <= -40 Nm)
reliable = TRQ <= -40;

ETA_RIG_R   = ETA_RIG;
ETA_REGEN_R = ETA_REGEN;

ETA_RIG_R(~reliable)   = NaN;
ETA_REGEN_R(~reliable) = NaN;

%% For each speed column, find the torque that maximises each efficiency
n_speeds = numel(speed_pts);

T_best_rig      = nan(n_speeds,1);   % [Nm]
T_best_regen    = nan(n_speeds,1);   % [Nm]
eta_best_rig    = nan(n_speeds,1);   % [%]
eta_best_regen  = nan(n_speeds,1);   % [%]

for i = 1:n_speeds
    rig_col   = ETA_RIG_R(:,i);
    regen_col = ETA_REGEN_R(:,i);

    [eta_best_rig(i), j_rig]       = max(rig_col);
    [eta_best_regen(i), j_regen]   = max(regen_col);

    if isfinite(eta_best_rig(i))
        T_best_rig(i) = torque_pts(j_rig);
    end

    if isfinite(eta_best_regen(i))
        T_best_regen(i) = torque_pts(j_regen);
    end
end

%% Global peaks from the reliable-region loci
[peak_eta_rig, k_rig]       = max(eta_best_rig);
[peak_eta_regen, k_regen]   = max(eta_best_regen);

peak_rig_speed    = speed_pts(k_rig);
peak_rig_torque   = T_best_rig(k_rig);

peak_regen_speed  = speed_pts(k_regen);
peak_regen_torque = T_best_regen(k_regen);

%% Plot
figure('Name','Best efficiency locus','Color','w','Position',[80 80 1000 600]);

contourf(SPD, TRQ, ETA_RIG_R, 30, 'LineColor', 'none');
hold on;
grid on;
box on;

colormap(gca, turbo(256));
caxis([55 80]);   % cosmetic choice to match dissertation style

%% Best eta_rig locus
hRig = plot(speed_pts, T_best_rig, 'k-o', ...
    'LineWidth', 2, ...
    'MarkerSize', 6, ...
    'MarkerFaceColor', 'w', ...
    'MarkerEdgeColor', 'k', ...
    'DisplayName', 'Best \eta_{rig}');

%% Best eta_regen locus
hRegen = plot(speed_pts, T_best_regen, '--', ...
    'Color', [1.0 0.0 1.0], ...
    'LineWidth', 2, ...
    'DisplayName', 'Best \eta_{regen}');

%% Peak markers
plot(peak_rig_speed, peak_rig_torque, 'p', ...
    'MarkerSize', 13, ...
    'MarkerFaceColor', [1.0 1.0 0.0], ...
    'MarkerEdgeColor', 'k', ...
    'LineWidth', 1.2, ...
    'HandleVisibility', 'off');

plot(peak_regen_speed, peak_regen_torque, 'p', ...
    'MarkerSize', 13, ...
    'MarkerFaceColor', [0.85 0.0 0.0], ...
    'MarkerEdgeColor', 'k', ...
    'LineWidth', 1.2, ...
    'HandleVisibility', 'off');

%% Peak labels
text(peak_rig_speed + 130, peak_rig_torque - 7, ...
    sprintf('Peak  \\eta_{rig} = %.1f%%', peak_eta_rig), ...
    'BackgroundColor', 'w', ...
    'EdgeColor', [0.5 0.5 0.5], ...
    'FontWeight', 'bold', ...
    'FontSize', 11);

text(peak_regen_speed + 130, peak_regen_torque - 7, ...
    sprintf('Peak  \\eta_{regen} = %.1f%%', peak_eta_regen), ...
    'BackgroundColor', 'w', ...
    'EdgeColor', [0.5 0.5 0.5], ...
    'FontWeight', 'bold', ...
    'FontSize', 11);

%% Axes / labels / legend
xlabel('Speed (RPM)');
ylabel('Torque (Nm)');
title('Best-efficiency operating loci within the reliable operating region');

cb = colorbar;
ylabel(cb, '\eta_{rig} (%)');

legend([hRig, hRegen], ...
    'Location', 'southoutside', ...
    'Orientation', 'horizontal');

xlim([1000 5000]);
ylim([-200 -40]);

%% Print summary
fprintf('\n=== Best-Efficiency Operating Locus Summary ===\n');
fprintf('Speed (RPM)   T_best_rig (Nm)   eta_rig (%%)   T_best_regen (Nm)   eta_regen (%%)\n');
for i = 1:n_speeds
    fprintf('  %5.0f         %7.0f          %6.2f          %7.0f             %6.2f\n', ...
        speed_pts(i), T_best_rig(i), eta_best_rig(i), ...
        T_best_regen(i), eta_best_regen(i));
end

fprintf('\nGlobal peak eta_rig:   %.2f%% at %.0f RPM, %.0f Nm\n', ...
    peak_eta_rig, peak_rig_speed, peak_rig_torque);
fprintf('Global peak eta_regen: %.2f%% at %.0f RPM, %.0f Nm\n', ...
    peak_eta_regen, peak_regen_speed, peak_regen_torque);

fprintf('\nExport with: print -dpng -r300 best_eta_locus.png\n');
end
