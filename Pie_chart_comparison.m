function Pie_chart_comparison(resultsFile)
%% =========================================================================
% plot_three_loss_pies.m
%
% Generates three side-by-side pie charts of loss composition at three
% characteristic operating points to substantiate the claim that the
% dominant loss mechanism varies across the speed-torque envelope.
%
% Operating points:
%   (a) Low-speed, high-torque  -> 1500 RPM, -150 Nm  (copper-dominated)
%   (b) Mid-speed, mid-torque   -> 3000 RPM, -100 Nm  (peak eta_rig point)
%   (c) High-speed, low-torque  -> 4500 RPM,  -40 Nm  (iron-dominated)
%
% Usage:
%   plot_three_loss_pies                                  % auto-find
%   plot_three_loss_pies('sweep_results_full.mat')        % explicit
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
if isfield(D,'R'), D = D.R; end

%% Operating points to inspect
points = [
    1500, -150;     % copper-dominated regime
    3000, -100;     % peak eta_rig point
    4500,  -40;     % iron-dominated regime
];
labels_main = { ...
    'Low speed / high torque', ...
    'Mid speed / mid torque', ...
    'High speed / low torque' };

%% Figure
figure('Name','Loss composition at three operating points', ...
       'Position',[60 60 1500 480],'Color','w');

for k = 1:size(points, 1)
    n_target = points(k, 1);
    T_target = points(k, 2);

    % Find nearest grid indices
    [~, j_idx] = min(abs(D.torque_pts - T_target));   % torque row
    [~, i_idx] = min(abs(D.speed_pts  - n_target));   % speed col

    n_actual = D.speed_pts(i_idx);
    T_actual = D.torque_pts(j_idx);

    % Extract losses at this point [W]
    Lcu    = D.Lcu_m(j_idx, i_idx) + D.Lcu_g(j_idx, i_idx);
    Lfe    = D.Lfe_m(j_idx, i_idx) + D.Lfe_g(j_idx, i_idx);
    Lshaft = D.Lshaft(j_idx, i_idx);
    Linv1  = D.Linv1(j_idx, i_idx);
    Linv2  = D.Linv2(j_idx, i_idx);
    Ldcdc  = D.Ldcdc(j_idx, i_idx);
    Lbat   = 0;
    if isfield(D,'LbatA'), Lbat = Lbat + D.LbatA(j_idx, i_idx); end
    if isfield(D,'LbatB'), Lbat = Lbat + D.LbatB(j_idx, i_idx); end
    Ldump  = 0;
    if isfield(D, 'Ldump')
        Ldump = D.Ldump(j_idx, i_idx);
    end

    losses = [Lcu, Lfe, Lshaft, Linv1, Linv2, Ldcdc, Lbat, Ldump];
    seg_labels = {'Copper','Iron','Shaft','Inv1','Inv2','DC/DC','Batteries','Dump'};

    % Filter zeros and tiny segments (< 1 W)
    keep = losses > 1;
    losses = losses(keep);
    seg_labels = seg_labels(keep);

    % Build percentage labels for the legend
    total = sum(losses);
    pct_labels = cell(size(seg_labels));
    for s = 1:numel(seg_labels)
        pct_labels{s} = sprintf('%s (%.0f W, %.1f%%)', ...
            seg_labels{s}, losses(s), 100*losses(s)/total);
    end

    % Pie chart
    subplot(1, 3, k);
    h = pie(losses);

    % Remove default percent labels (using legend instead)
    for ii = 2:2:numel(h)
        if isgraphics(h(ii),'text')
            set(h(ii), 'String', '');
        end
    end

    eta_here = D.eta_rig(j_idx, i_idx) * 100;
    title(sprintf('%s\n%d RPM, %d Nm (\\eta_{rig} = %.1f%%)\nTotal loss = %.0f W', ...
        labels_main{k}, n_actual, T_actual, eta_here, total), ...
        'FontSize', 11);
    legend(pct_labels, 'Location', 'southoutside', 'FontSize', 9);
end

sgtitle('Loss composition varies across the operating envelope', 'FontSize', 13);

%% Print summary
fprintf('\n=== Loss Pie Chart Summary ===\n');
for k = 1:size(points, 1)
    n_target = points(k, 1);
    T_target = points(k, 2);
    [~, j_idx] = min(abs(D.torque_pts - T_target));
    [~, i_idx] = min(abs(D.speed_pts  - n_target));

    Lcu = D.Lcu_m(j_idx, i_idx) + D.Lcu_g(j_idx, i_idx);
    Lfe = D.Lfe_m(j_idx, i_idx) + D.Lfe_g(j_idx, i_idx);
    fprintf('At %d RPM, %d Nm:  Cu = %.0f W,  Fe = %.0f W,  ratio Fe/Cu = %.2f\n', ...
        D.speed_pts(i_idx), D.torque_pts(j_idx), Lcu, Lfe, Lfe/max(Lcu, eps));
end

fprintf('\nExport with: print -dpng -r300 three_loss_pies.png\n');
end