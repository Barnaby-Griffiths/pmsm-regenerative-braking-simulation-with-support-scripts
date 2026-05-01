%% Test_one.m
% Robust single-point verification for Final.slx
% Operating point: 3000 rpm, -100 Nm

clearvars
clc
close all force

%% Always run from this script folder
thisFolder = fileparts(mfilename('fullpath'));
cd(thisFolder)

mdl = 'Final';

%% Force logging/recording ON for this diagnostic script
try
    Simulink.sdi.setRecordData(true);
    Simulink.sdi.setAutoArchiveMode(true);
    Simulink.sdi.clear;
catch
end

%% Load parameters
INIT_VERBOSE    = true;
INIT_MAKE_PLOTS = false;
simulink_init_params_CORRECTED

baseVars = {'PMSM','INV','INV2','BAT','BAT_A','BAT_B','DCLINK','DCDC','MECH','FOC','THERM','FW','SIM'};
for ii = 1:numel(baseVars)
    if exist(baseVars{ii}, 'var')
        assignin('base', baseVars{ii}, eval(baseVars{ii}));
    end
end

%% Load model
if ~bdIsLoaded(mdl)
    load_system(mdl);
end

%% Clean model run settings for single-point test
try set_param(mdl,'FastRestart','off'); catch, end
try set_param(mdl,'SignalLogging','on'); catch, end
try set_param(mdl,'ReturnWorkspaceOutputs','on'); catch, end
try set_param(mdl,'SaveOutput','on'); catch, end
try set_param(mdl,'SaveTime','on'); catch, end
try set_param(mdl,'SaveState','off'); catch, end
try set_param(mdl,'SaveFinalState','off'); catch, end
try set_param(mdl,'SimscapeLogType','none'); catch, end

%% Operating point
n_ref = 3000;
T_ref = -100;

assignin('base','SpeedRef_rpm_cmd',     n_ref);
assignin('base','TorqueRef_gen_Nm_cmd', T_ref);
assignin('base','omega_init_cmd',       n_ref*2*pi/60);

t_stop   = SIM.t_sim;
t_settle = SIM.t_settle;

set_param(mdl,'StopTime',num2str(t_stop));

%% Signal names
S.speed         = 'Speed_in_RPM';
S.P_battA_out   = 'P_battA_out';
S.P_inv1_out    = 'P_inv1_out';
S.P_motor_elec  = 'P_motor_elec_in';
S.P_motor_mech  = 'P_motor_mech_out';
S.P_gen_mech    = 'P_gen_mech_in';
S.P_gen_elec    = 'P_gen_elec_out';
S.P_inv2_out    = 'P_inv2_out';
S.P_dcdc_in     = 'P_dcdc_in';
S.P_dcdc_out    = 'P_dcdc_out';
S.P_battB_in    = 'P_battB_in';
S.P_batA_loss   = 'P_batA_loss';
S.P_batB_loss   = 'P_batB_loss';
S.P_shaft_loss  = 'P_shaft_loss';
S.P_tot_loss    = 'P_total_loss';
S.T_wind        = 'T_wind';
S.P_cu_motor    = 'P_cu_motor';
S.P_fe_motor    = 'P_fe_motor';
S.P_cu_gen      = 'P_cu_gen';
S.P_fe_gen      = 'P_fe_gen';
S.P_inv1_loss   = 'P_inv1_loss';
S.P_inv2_loss   = 'P_inv2_loss';
S.P_dcdc_loss   = 'P_dcdc_loss';
S.P_dump        = 'P_dump';

requiredCore = { ...
    S.speed, S.P_battA_out, S.P_inv1_out, S.P_motor_elec, S.P_motor_mech, ...
    S.P_gen_mech, S.P_gen_elec, S.P_inv2_out, S.P_dcdc_in, S.P_dcdc_out, ...
    S.P_battB_in, S.P_batA_loss, S.P_batB_loss, S.P_shaft_loss, ...
    S.P_tot_loss, S.T_wind, S.P_cu_motor, S.P_fe_motor, S.P_cu_gen, S.P_fe_gen };

assertSignalAvailability(mdl, requiredCore);

availableVars = getToWorkspaceVars(mdl);
explicitLossesAvailable = all(ismember({S.P_inv1_loss,S.P_inv2_loss,S.P_dcdc_loss,S.P_dump}, availableVars));

%% Run simulation
simOut = sim(mdl,'StopTime',num2str(t_stop),'ReturnWorkspaceOutputs','on');

%% Extract
out = postExtractCorrected(simOut, t_settle, t_stop, S, explicitLossesAvailable);

if ~out.ok
    error('Test_one:ExtractionFailed','Could not extract signals: %s', out.err);
end

out = computeEfficienciesCorrected(out);

%% Print results
fprintf('\n=== Init complete. Variables loaded: PMSM INV INV2 BAT BAT_A BAT_B DCLINK DCDC MECH FOC THERM FW SIM ===\n');
fprintf('\nSteady-state averaging window: %.2f s to %.2f s\n', t_settle, t_stop);
fprintf('Average shaft speed: %.1f rpm\n', out.spd_avg);

fprintf('\n=== Per-stage balance (should all be ~0) ===\n');
fprintf('  BattA terminal -> Inv1 out:  Pba - Pme - Linv1                 = %+8.1f W\n', out.battA_balance_W);
fprintf('  Inv1 consistency:            Pi1 - Pme                         = %+8.1f W\n', out.inv1_balance_W);
fprintf('  Motor stator:                Pme - Pmm - Lcu_m - Lfe_m         = %+8.1f W\n', out.motor_balance_W);
fprintf('  Shaft:                       Pmm - Pgm - Lshaft                = %+8.1f W\n', out.shaft_balance_W);
fprintf('  Generator stator:            Pgm - Pge - Lcu_g - Lfe_g         = %+8.1f W\n', out.gen_balance_W);
fprintf('  Inv2 stage:                  Pge - Pi2 - Linv2                 = %+8.1f W\n', out.inv2_balance_W);
fprintf('  DC bus stage:                Pi2 - Pdcdc_in - Pbus             = %+8.1f W\n', out.bus_balance_W);
fprintf('  DC/DC stage:                 Pdcdc_in - Pdcdc_out - Ldcdc      = %+8.1f W\n', out.dcdc_balance_W);
fprintf('  BattB terminal/storage:      Pdcdc_out - PbattB - LbatB        = %+8.1f W\n', out.battB_balance_W);

fprintf('\n=== Whole-rig balance ===\n');
fprintf('  Pba           = %8.1f W\n', out.Pba);
fprintf('  PbattB_stored = %8.1f W\n', out.Pbb_store);
fprintf('  Sum explicit losses = %8.1f W\n', out.Ltot_explicit);
fprintf('    Lcu_m=%.1f  Lfe_m=%.1f  Lcu_g=%.1f  Lfe_g=%.1f\n', out.Lcu_m, out.Lfe_m, out.Lcu_g, out.Lfe_g);
fprintf('    Linv1=%.1f  Linv2=%.1f  Ldcdc=%.1f  Pbus=%.1f\n', out.Linv1, out.Linv2, out.Ldcdc, out.Pbus);
fprintf('    LbatB=%.1f  Lshaft=%.1f  Pdump=%.1f\n', out.LbatB, out.Lshaft, out.Ldump);
fprintf('  PB residual = %+7.1f W (%+.3f%%)\n', out.PB_resid_W, out.PB_resid_pct);

fprintf('\n=== Top-line efficiencies ===\n');
fprintf('  eta_regen = Pbb/Pgm      = %.2f %%\n', 100*out.eta_regen);
fprintf('  eta_rig   = Pbb/Pba      = %.2f %%\n', 100*out.eta_rig);
fprintf('  eta_b2b   = Pdo/Pba      = %.2f %%\n', 100*out.eta_b2b);

%% Local functions
function r = postExtractCorrected(so, t1, t2, S, explicitLossesAvailable)

r = struct();
r.ok = false;
r.err = '';

try
    coreNames = {'speed','P_battA_out','P_inv1_out','P_motor_elec','P_motor_mech','P_gen_mech','P_gen_elec', ...
                 'P_inv2_out','P_dcdc_in','P_dcdc_out','P_battB_in', ...
                 'P_batA_loss','P_batB_loss','P_shaft_loss','P_tot_loss','T_wind', ...
                 'P_cu_motor','P_fe_motor','P_cu_gen','P_fe_gen'};

    for ii = 1:numel(coreNames)
        key = coreNames{ii};
        ts = findSafely(so, S.(key));
        r.(['avg_' key]) = avgInWindow(ts, t1, t2);
    end

    if explicitLossesAvailable
        extraNames = {'P_inv1_loss','P_inv2_loss','P_dcdc_loss','P_dump'};
        for ii = 1:numel(extraNames)
            key = extraNames{ii};
            ts = findSafely(so, S.(key));
            r.(['avg_' key]) = avgInWindow(ts, t1, t2);
        end
    else
        r.avg_P_inv1_loss = NaN;
        r.avg_P_inv2_loss = NaN;
        r.avg_P_dcdc_loss = NaN;
        r.avg_P_dump      = 0;
    end

    ts = findSafely(so, S.speed);
    if ~isTsEmpty(ts)
        [t, y] = tsTY(ts);
        m = t >= t1 & t <= t2;
        if any(m)
            r.spd_std = std(y(m), 'omitnan');
        else
            r.spd_std = NaN;
        end
    else
        r.spd_std = NaN;
    end

    ts = findSafely(so, S.T_wind);
    if ~isTsEmpty(ts)
        [t, y] = tsTY(ts);
        m = t >= max(t1, t2-0.2) & t <= t2;
        if any(m)
            r.T_wind_end = mean(y(m), 'omitnan');
        else
            r.T_wind_end = NaN;
        end
    else
        r.T_wind_end = NaN;
    end

    r.spd_avg   = r.avg_speed;
    r.Pba       = abs(r.avg_P_battA_out);
    r.Pi1       = abs(r.avg_P_inv1_out);
    r.Pme       = abs(r.avg_P_motor_elec);
    r.Pmm       = abs(r.avg_P_motor_mech);
    r.Pgm       = abs(r.avg_P_gen_mech);
    r.Pge       = abs(r.avg_P_gen_elec);
    r.Pi2       = abs(r.avg_P_inv2_out);
    r.Pdi       = abs(r.avg_P_dcdc_in);
    r.Pdo       = abs(r.avg_P_dcdc_out);
    r.Pbb_term  = r.Pdo;
    r.Pbb_store = abs(r.avg_P_battB_in);

    r.Lcu_m     = abs(r.avg_P_cu_motor);
    r.Lfe_m     = abs(r.avg_P_fe_motor);
    r.Lcu_g     = abs(r.avg_P_cu_gen);
    r.Lfe_g     = abs(r.avg_P_fe_gen);
    r.Lshaft    = abs(r.avg_P_shaft_loss);
    r.LbatA     = abs(r.avg_P_batA_loss);
    r.LbatB     = abs(r.avg_P_batB_loss);
    r.Ltot      = abs(r.avg_P_tot_loss);
    r.Ldump     = abs(r.avg_P_dump);

    if explicitLossesAvailable
        r.Linv1 = abs(r.avg_P_inv1_loss);
        r.Linv2 = abs(r.avg_P_inv2_loss);
        r.Ldcdc = abs(r.avg_P_dcdc_loss);
    else
        r.Linv1 = max(r.Pba - r.Pi1, 0);
        r.Linv2 = max(r.Pge - r.Pi2, 0);
        r.Ldcdc = max(r.Pdi - r.Pdo, 0);
    end

    r.Pbus = max(r.Pi2 - r.Pdi, 0);

    r.Ltot_explicit = r.Linv1 + r.Lcu_m + r.Lfe_m + ...
                      r.Lshaft + r.Lcu_g + r.Lfe_g + ...
                      r.Linv2 + r.Pbus + r.Ldcdc + ...
                      r.LbatB + r.Ldump;

    r.battA_balance_W   = r.Pba - r.Pme - r.Linv1;
    r.battA_balance_pct = 100 * r.battA_balance_W / max([r.Pba, r.Pme + r.Linv1, 1000]);

    r.inv1_balance_W    = r.Pi1 - r.Pme;
    r.inv1_balance_pct  = 100 * r.inv1_balance_W / max([r.Pi1, r.Pme, 1000]);

    r.motor_balance_W   = r.Pme - r.Pmm - r.Lcu_m - r.Lfe_m;
    r.motor_balance_pct = 100 * r.motor_balance_W / max([r.Pme, r.Pmm + r.Lcu_m + r.Lfe_m, 1000]);

    r.shaft_balance_W   = r.Pmm - r.Pgm - r.Lshaft;
    r.shaft_balance_pct = 100 * r.shaft_balance_W / max([r.Pmm, r.Pgm + r.Lshaft, 1000]);

    r.gen_balance_W     = r.Pgm - r.Pge - r.Lcu_g - r.Lfe_g;
    r.gen_balance_pct   = 100 * r.gen_balance_W / max([r.Pgm, r.Pge + r.Lcu_g + r.Lfe_g, 1000]);

    r.inv2_balance_W    = r.Pge - r.Pi2 - r.Linv2;
    r.inv2_balance_pct  = 100 * r.inv2_balance_W / max([r.Pge, r.Pi2 + r.Linv2, 1000]);

    r.bus_balance_W     = r.Pi2 - r.Pdi - r.Pbus;
    r.bus_balance_pct   = 100 * r.bus_balance_W / max([r.Pi2, r.Pdi + r.Pbus, 1000]);

    r.dcdc_balance_W    = r.Pdi - r.Pdo - r.Ldcdc;
    r.dcdc_balance_pct  = 100 * r.dcdc_balance_W / max([r.Pdi, r.Pdo + r.Ldcdc, 1000]);

    r.battB_balance_W   = r.Pdo - r.Pbb_store - r.LbatB - r.Ldump;
    r.battB_balance_pct = 100 * r.battB_balance_W / max([r.Pdo, r.Pbb_store + r.LbatB + r.Ldump, 1000]);

    r.PB_resid_W   = r.Pba - r.Pbb_store - r.Ltot_explicit;
    r.PB_resid_pct = 100 * r.PB_resid_W / max([r.Pba, r.Pbb_store + r.Ltot_explicit, 1000]);

    r.ok = true;

catch ME
    r.ok = false;
    r.err = ME.message;
end

end

function out = computeEfficienciesCorrected(out)

ep = eps;

out.eta_battA = out.Pba       / max(out.Pba + out.LbatA, ep);
out.eta_inv1  = out.Pi1       / max(out.Pba, ep);
out.eta_motor = out.Pmm       / max(out.Pme, ep);
out.eta_shaft = out.Pgm       / max(out.Pmm, ep);
out.eta_gen   = out.Pge       / max(out.Pgm, ep);
out.eta_inv2  = out.Pi2       / max(out.Pge, ep);
out.eta_dcdc  = out.Pdo       / max(out.Pdi, ep);
out.eta_battB = out.Pbb_store / max(out.Pbb_term, ep);
out.eta_regen = out.Pbb_store / max(out.Pgm, ep);
out.eta_rig   = out.Pbb_store / max(out.Pba, ep);
out.eta_b2b   = out.Pbb_term  / max(out.Pba, ep);

end

function y = avgInWindow(ts, t1, t2)

if isTsEmpty(ts)
    y = NaN;
    return;
end

[t, v] = tsTY(ts);
m = t >= t1 & t <= t2;

if any(m)
    y = mean(v(m), 'omitnan');
else
    y = NaN;
end

end

function vars = getToWorkspaceVars(mdl)

tw = find_system(mdl,'LookUnderMasks','all','FollowLinks','on', ...
    'MatchFilter', @Simulink.match.allVariants, ...
    'BlockType','ToWorkspace');

vars = cell(size(tw));

for k = 1:numel(tw)
    vars{k} = get_param(tw{k},'VariableName');
end

end

function assertSignalAvailability(mdl, signalNames)

vars = getToWorkspaceVars(mdl);
missing = signalNames(~ismember(signalNames, vars));

if ~isempty(missing)
    error('Test_one:MissingSignals', ...
        'These ToWorkspace variables are missing from the model: %s', ...
        strjoin(missing, ', '));
end

end

function ts = findSafely(so, name)

ts = [];

try
    ts = so.get(name);
catch
end

if isempty(ts)
    try
        ts = so.find(name);
    catch
    end
end

if isempty(ts)
    try
        ts = so.logsout.get(name);
    catch
    end
end

end

function tf = isTsEmpty(ts)

if isempty(ts)
    tf = true;
    return;
end

try
    if isa(ts,'timeseries')
        tf = isempty(ts.Time) || isempty(ts.Data);
    elseif isa(ts,'Simulink.SimulationData.Signal')
        tf = isempty(ts.Values.Time) || isempty(ts.Values.Data);
    elseif isstruct(ts) && isfield(ts,'Values')
        tf = isempty(ts.Values.Time) || isempty(ts.Values.Data);
    else
        tf = true;
    end
catch
    tf = true;
end

end

function [t, y] = tsTY(ts)

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
    error('tsTY:badClass','Unexpected signal class: %s', class(ts));
end

y = y(:);

if numel(y) ~= numel(t)
    y = reshape(y, numel(t), []);
    y = y(:,1);
end

end