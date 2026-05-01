%% Plot_efficiency_maps.m
% Plot dissertation-ready efficiency, loss, and power-balance maps.
%
% This script loads the completed sweep result structure R from
% sweep_results_fixed_boundaries_full.mat if R is not already present in the
% workspace. Speed is plotted in rpm, regenerative torque in N.m, powers and
% losses in kW or W as stated in each title, and efficiencies in percent.
%
% The figures produced are:
%   1. Top-line rig efficiencies
%   2. Section-by-section efficiencies
%   3. Terminal-basis loss breakdown at the best eta_rig point per speed
%   4. Whole-rig power-balance residual
%   5. Terminal-basis explicit losses
%   6. eta_rig surface
%   7. Rejected recovered power / dump power
%   8. Battery B stored power

clc

%% Go to script folder
thisFolder = fileparts(mfilename('fullpath'));
cd(thisFolder)

%% Load R if not already loaded
if ~exist('R','var')
    if exist('sweep_results_fixed_boundaries_full.mat','file')
        S = load('sweep_results_fixed_boundaries_full.mat');
        fprintf('Loaded sweep_results_fixed_boundaries_full.mat\n');

    elseif exist('sweep_results_fixed_boundaries_fast.mat','file')
        S = load('sweep_results_fixed_boundaries_fast.mat');
        fprintf('Loaded sweep_results_fixed_boundaries_fast.mat\n');

    else
        error('No sweep result file found. Run run_efficiency_sweep first.');
    end

    if isfield(S,'R')
        R = S.R;
    else
        R = S;
    end
end

%% Basic checks
requiredFields = {'SPD','TRQ','VALID','eta_regen','eta_rig','eta_b2b','PB_resid_pct'};

for k = 1:numel(requiredFields)
    if ~isfield(R, requiredFields{k})
        error('Result structure is missing field: %s', requiredFields{k});
    end
end

valid = R.VALID;

fprintf('\n=== Plotting summary ===\n');
fprintf('Valid points: %d / %d\n', nnz(R.VALID), numel(R.VALID));

if isfield(R,'REJECT')
    fprintf('Rejected points: %d / %d\n', nnz(R.REJECT ~= 0), numel(R.REJECT));
end

if isfield(R,'PB_WARN')
    fprintf('PB warnings: %d\n', nnz(R.PB_WARN));
end

if isfield(R,'MOTOR_WARN')
    fprintf('Motor warnings: %d\n', nnz(R.MOTOR_WARN));
end

if isfield(R,'GEN_WARN')
    fprintf('Generator warnings: %d\n', nnz(R.GEN_WARN));
end

%% Mask invalid points
eta_regen = 100 * R.eta_regen;
eta_rig   = 100 * R.eta_rig;
eta_b2b   = 100 * R.eta_b2b;
pb_resid  = R.PB_resid_pct;

eta_regen(~valid) = NaN;
eta_rig(~valid)   = NaN;
eta_b2b(~valid)   = NaN;
pb_resid(~valid)  = NaN;

%% Headline values
fprintf('\n=== Headline values ===\n');

printPeak(R, R.eta_regen, 'eta_regen');
printPeak(R, R.eta_rig,   'eta_rig');
printPeak(R, R.eta_b2b,   'eta_b2b');

mainMask = R.VALID & R.TRQ <= -40;

fprintf('Max abs PB residual, full valid envelope: %.2f %%\n', ...
    max(abs(R.PB_resid_pct(R.VALID)), [], 'all', 'omitnan'));

fprintf('Max abs PB residual, excluding -20 Nm boundary: %.2f %%\n', ...
    max(abs(R.PB_resid_pct(mainMask)), [], 'all', 'omitnan'));

if isfield(R,'Pbb_store')
    temp = R.Pbb_store;
    temp(~R.VALID) = NaN;

    [Pmax, idx] = max(temp, [], 'all', 'omitnan', 'linear');

    fprintf('Maximum stored recovered power: %.2f kW at %.0f rpm, %.0f Nm\n', ...
        Pmax/1000, R.SPD(idx), R.TRQ(idx));
end

%% Figure 1: Top-line rig efficiencies
figure('Name','Top-line rig efficiencies','Color','w');

subplot(1,3,1)
plotContourLight(R.SPD, R.TRQ, eta_regen, '\eta_{regen} (%)');
xlabel('Speed (rpm)');
ylabel('Regenerative torque (N.m)');

subplot(1,3,2)
plotContourLight(R.SPD, R.TRQ, eta_rig, '\eta_{rig} (%)');
xlabel('Speed (rpm)');
ylabel('Regenerative torque (N.m)');

subplot(1,3,3)
plotContourLight(R.SPD, R.TRQ, eta_b2b, '\eta_{b2b} (%)');
xlabel('Speed (rpm)');
ylabel('Regenerative torque (N.m)');

sgtitle('Top-line rig efficiencies','Color','k','FontWeight','bold');

%% Figure 2: Section-by-section efficiencies
fig2 = figure('Name','Section-by-section efficiencies', ...
              'Color','w', ...
              'Position',[100 50 800 1000]);

sectionNames = {'eta_battA','eta_inv1','eta_motor','eta_shaft', ...
                'eta_gen','eta_inv2','eta_battB'};

sectionTitles = {'\eta_{battA}','\eta_{inv1}','\eta_{motor}','\eta_{shaft}', ...
                 '\eta_{gen}','\eta_{inv2}','\eta_{battB}'};

tl = tiledlayout(4,2,'TileSpacing','compact','Padding','compact');

if isfield(R,'eta_dcdc')
    dcdcVals = 100 * R.eta_dcdc(R.VALID);

    titleStr = sprintf(['Section-by-section efficiencies' ...
        '   (\\eta_{dcdc} = %.2f %% mean)'], ...
        mean(dcdcVals,'omitnan'));
else
    titleStr = 'Section-by-section efficiencies';
end

title(tl, titleStr, ...
    'FontWeight','bold', ...
    'FontSize',13, ...
    'Color','k');

% Plot the first six section efficiencies in the top three rows.
for k = 1:6
    nexttile

    showXLabel = any(k == [5 6]);
    showYLabel = any(k == [1 3 5]);

    plotSectionEfficiency(R, valid, sectionNames{k}, sectionTitles{k}, ...
        showXLabel, showYLabel);
end

% Plot eta_battB on the final row across both columns.
nexttile([1 2])
plotSectionEfficiency(R, valid, sectionNames{7}, sectionTitles{7}, true, true);
pbaspect([2.8 1 1]);

%% Figure 3: Loss breakdown at best eta_rig point per speed
if all(isfield(R, {'Lcu_m','Lfe_m','Lcu_g','Lfe_g','Lshaft', ...
                   'Linv1','Linv2','Ldcdc','LbatB','Ldump','eta_rig'}))

    speeds = R.speed_pts;
    lossMat = nan(numel(speeds),8);

    for i = 1:numel(speeds)
        mask = R.VALID & R.SPD == speeds(i);

        temp = R.eta_rig;
        temp(~mask) = NaN;

        if any(~isnan(temp),'all')
            [~, idx] = max(temp, [], 'all', 'omitnan', 'linear');

            copper = R.Lcu_m(idx) + R.Lcu_g(idx);
            iron   = R.Lfe_m(idx) + R.Lfe_g(idx);

            lossMat(i,:) = [ ...
                copper, ...
                iron, ...
                R.Lshaft(idx), ...
                R.Linv1(idx), ...
                R.Linv2(idx), ...
                R.Ldcdc(idx), ...
                R.LbatB(idx), ...
                R.Ldump(idx)];
        end
    end

    figure('Name','Terminal-basis loss breakdown','Color','w');

    bar(speeds, lossMat, 'stacked');

    grid on
    box on

    xlabel('Speed (rpm)');
    ylabel('Loss (W)');

    title('Terminal-basis loss breakdown at best \eta_{rig} point per speed', ...
        'Color','k', ...
        'FontWeight','bold');

    lgd = legend({'Copper','Iron','Shaft','Inv1','Inv2','DC/DC','Battery B','Dump'}, ...
        'Location','northwest');

    lgd.TextColor = 'k';

    set(gca, ...
        'Color','w', ...
        'XColor','k', ...
        'YColor','k', ...
        'GridColor',[0.65 0.65 0.65], ...
        'FontSize',10, ...
        'LineWidth',0.8);
end

%% Figure 4: Whole-rig power-balance residual
figure('Name','Whole-rig power-balance residual','Color','w');

% The residual map is plotted without overlaid contour lines. Since much of
% the residual field is close to flat, contour lines can create misleading
% visual artefacts.
contourf(R.SPD, R.TRQ, pb_resid, 20, 'LineColor','none');

grid on
box on

title('Whole-rig power-balance residual (%)', ...
    'Color','k', ...
    'FontWeight','bold');

xlabel('Speed (rpm)');
ylabel('Regenerative torque (N.m)');

cb = colorbar;
cb.Color = 'k';
cb.Label.String = 'Residual (%)';
cb.Label.Color = 'k';
cb.Label.FontWeight = 'bold';

set(gca, ...
    'Color','w', ...
    'XColor','k', ...
    'YColor','k', ...
    'GridColor',[0.65 0.65 0.65], ...
    'FontSize',10, ...
    'LineWidth',0.8);

set(gcf,'Color','w');
colormap turbo

%% Figure 5: Explicit losses excluding Battery A internal source loss
if all(isfield(R, {'Lcu_m','Lfe_m','Lcu_g','Lfe_g','Lshaft', ...
                   'Linv1','Linv2','Ldcdc','LbatB','Ldump'}))

    explicitLoss = R.Lcu_m + R.Lfe_m + R.Lcu_g + R.Lfe_g + ...
                   R.Lshaft + R.Linv1 + R.Linv2 + R.Ldcdc + ...
                   R.LbatB + R.Ldump;

    explicitLoss(~valid) = NaN;

    figure('Name','Terminal-basis explicit losses excluding Battery A internal source loss', ...
           'Color','w');

    plotContourLight(R.SPD, R.TRQ, explicitLoss/1000, ...
        'Terminal-basis explicit losses, excluding Battery A internal source loss (kW)');

    xlabel('Speed (rpm)');
    ylabel('Regenerative torque (N.m)');
end

%% Figure 6: eta_rig surface
figure('Name','eta_rig surface','Color','w');

surf(R.SPD, R.TRQ, eta_rig, 'EdgeColor','none');

xlabel('Speed (rpm)');
ylabel('Regenerative torque (N.m)');
zlabel('\eta_{rig} (%)');

title('\eta_{rig} surface', ...
    'Color','k', ...
    'FontWeight','bold');

cb = colorbar;
cb.Color = 'k';
cb.Label.String = 'Efficiency (%)';
cb.Label.Color = 'k';
cb.Label.FontWeight = 'bold';

grid on
box on

set(gca, ...
    'Color','w', ...
    'XColor','k', ...
    'YColor','k', ...
    'ZColor','k', ...
    'GridColor',[0.65 0.65 0.65], ...
    'FontSize',10, ...
    'LineWidth',0.8);

colormap turbo
view(135,30);

%% Figure 7: Rejected recovered power / dump power
if isfield(R,'Ldump') && isfield(R,'Pdo')

    Pdump_kW = R.Ldump / 1000;
    Pdump_kW(~valid) = NaN;

    Pdump_pct = 100 * R.Ldump ./ max(R.Pdo, eps);
    Pdump_pct(~valid) = NaN;

    figure('Name','Rejected recovered power','Color','w');

    subplot(1,2,1)
    plotContourLight(R.SPD, R.TRQ, Pdump_kW, ...
        'Rejected recovered power, P_{dump} (kW)');
    xlabel('Speed (rpm)');
    ylabel('Regenerative torque (N.m)');

    subplot(1,2,2)
    plotContourLight(R.SPD, R.TRQ, Pdump_pct, ...
        'Rejected recovered power, P_{dump}/P_{DC/DC,out} (%)');
    xlabel('Speed (rpm)');
    ylabel('Regenerative torque (N.m)');
end

%% Figure 8: Battery B stored power
if isfield(R,'Pbb_store')

    figure('Name','Battery B stored power','Color','w');

    Z = R.Pbb_store / 1000;
    Z(~valid) = NaN;

    plotContourLight(R.SPD, R.TRQ, Z, ...
        'Battery B stored power (kW)');

    xlabel('Speed (rpm)');
    ylabel('Regenerative torque (N.m)');
end

fprintf('\nPlotting complete. Figures are open in MATLAB.\n');

%% Local functions
function plotContourLight(X, Y, Z, ttl)
%PLOTCONTOURLIGHT Plot a filled contour map with light-background styling.

contourf(X, Y, Z, 20, 'LineColor','none');
hold on

% Add sparse contour lines for readability, but omit contour labels to avoid
% cluttering the dissertation figures.
zvals = Z(~isnan(Z));

if ~isempty(zvals)
    zmin = min(zvals);
    zmax = max(zvals);

    if zmax > zmin
        levels = linspace(zmin, zmax, 5);

        contour(X, Y, Z, levels, ...
            'LineColor',[0.10 0.10 0.10], ...
            'LineWidth',0.45);
    end
end

grid on
box on

title(ttl, ...
    'Color','k', ...
    'FontWeight','bold');

cb = colorbar;
cb.Color = 'k';
cb.Label.String = getColourbarLabel(ttl);
cb.Label.Color = 'k';
cb.Label.FontWeight = 'bold';

set(gca, ...
    'Color','w', ...
    'XColor','k', ...
    'YColor','k', ...
    'GridColor',[0.65 0.65 0.65], ...
    'FontSize',10, ...
    'LineWidth',0.8);

set(gcf,'Color','w');
colormap turbo

end

function plotSectionEfficiency(R, valid, fieldName, titleTex, showXLabel, showYLabel)
%PLOTSECTIONEFFICIENCY Plot one section-efficiency map in Figure 2.

if ~isfield(R, fieldName)
    axis off
    title(sprintf('%s missing', titleTex), ...
        'Color','k', ...
        'FontWeight','bold');
    return
end

Z = 100 * R.(fieldName);
Z(~valid) = NaN;

contourf(R.SPD, R.TRQ, Z, 15, 'LineColor','none');

title(sprintf('%s (%%)', titleTex), ...
    'FontWeight','bold', ...
    'FontSize',11, ...
    'Color','k');

cb = colorbar;
cb.Color = 'k';
cb.FontSize = 9;
cb.Label.String = 'Efficiency (%)';
cb.Label.FontSize = 9;
cb.Label.Color = 'k';
cb.Label.FontWeight = 'bold';

grid on
box on

set(gca, ...
    'Color','w', ...
    'XColor','k', ...
    'YColor','k', ...
    'GridColor',[0.75 0.75 0.75], ...
    'FontSize',9, ...
    'LineWidth',0.7);

colormap(gca, turbo)

if showXLabel
    xlabel('Speed (rpm)');
else
    set(gca,'XTickLabel',{})
end

if showYLabel
    ylabel('Regenerative torque (N.m)');
else
    set(gca,'YTickLabel',{})
end

end

function label = getColourbarLabel(ttl)
%GETCOLOURBARLABEL Return an appropriate colourbar label from the plot title.

if contains(ttl, '\eta') || contains(ttl, 'efficien', 'IgnoreCase', true)
    label = 'Efficiency (%)';

elseif contains(ttl, 'residual', 'IgnoreCase', true)
    label = 'Residual (%)';

elseif contains(ttl, 'P_{dump}/P_{DC/DC,out}', 'IgnoreCase', true)
    label = 'Rejected recovered power (%)';

elseif contains(ttl, 'P_{dump}', 'IgnoreCase', true) && contains(ttl, 'kW', 'IgnoreCase', true)
    label = 'Rejected power (kW)';

elseif contains(ttl, 'stored power', 'IgnoreCase', true)
    label = 'Stored power (kW)';

elseif contains(ttl, 'loss', 'IgnoreCase', true) && contains(ttl, 'kW', 'IgnoreCase', true)
    label = 'Loss (kW)';

elseif contains(ttl, 'loss', 'IgnoreCase', true)
    label = 'Loss';

else
    label = 'Value';
end

end

function printPeak(R, fieldData, label)
%PRINTPEAK Print the maximum valid value of one efficiency field.

temp = fieldData;
temp(~R.VALID) = NaN;

if all(isnan(temp),'all')
    fprintf('%s: no valid values\n', label);
    return
end

[val, idx] = max(temp, [], 'all', 'omitnan', 'linear');

fprintf('Peak %s = %.2f %% at %.0f rpm, %.0f Nm\n', ...
    label, 100*val, R.SPD(idx), R.TRQ(idx));

end