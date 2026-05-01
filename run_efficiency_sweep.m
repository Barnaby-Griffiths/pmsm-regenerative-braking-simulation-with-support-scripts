function R = run_efficiency_sweep(mode)
%% =========================================================================
% run_efficiency_sweep.m
%
% Full fixed-boundary efficiency sweep for Final.slx.
%
% Usage:
%   R = run_efficiency_sweep('fresh');   % start from beginning
%   R = run_efficiency_sweep('resume');  % continue from latest checkpoint
%
% Saves:
%   sweep_resume_latest.mat
%   sweep_partial_XXX_of_YYY.mat
%   sweep_results_fixed_boundaries_full.mat
%   sweep_results_fixed_boundaries_full_unpacked.mat
%
% Features:
%   - Fast Restart ON
%   - checkpoint/resume support
%   - robust extraction from simOut and base workspace
%   - detailed REJECT 6 diagnostics
%   - automatic checkpoint every 10 completed cases
%% =========================================================================

if nargin < 1
    mode = 'fresh';
end

mode = lower(string(mode));

if ~ismember(mode, ["fresh","resume"])
    error("Mode must be 'fresh' or 'resume'.");
end

clc;
close all force;

%% Always run from this script folder
thisFolder = fileparts(mfilename('fullpath'));
cd(thisFolder);

%% User settings
mdl = 'Final';

USE_FAST_RESTART = true;
checkpoint_every = 10;
fast_restart_reset_every = 50;

resumeFile = 'sweep_resume_latest.mat';

%% Load model parameters
INIT_VERBOSE    = true;
INIT_MAKE_PLOTS = false;
simulink_init_params_CORRECTED

baseVars = {'PMSM','INV','INV2','BAT','BAT_A','BAT_B','DCLINK','DCDC','MECH','FOC','THERM','FW','SIM'};

for ii = 1:numel(baseVars)
    if exist(baseVars{ii}, 'var')
        assignin('base', baseVars{ii}, eval(baseVars{ii}));
    end
end

t_stop   = SIM.t_sim;
t_settle = SIM.t_settle;

speed_pts  = SIM.speed_rpm;
torque_pts = SIM.torque_regen_Nm;

fprintf('\nSweep: %d speed points x %d torque points = %d cases\n', ...
    numel(speed_pts), numel(torque_pts), numel(speed_pts)*numel(torque_pts));

%% Load model
if ~bdIsLoaded(mdl)
    load_system(mdl);
end

%% Preserve original model settings
warn_state_all = warning;
warning('off','all');

orig = struct();
orig.SignalLogging    = tryget(mdl,'SignalLogging','off');
orig.FastRestart      = tryget(mdl,'FastRestart','off');
orig.LoggingIntervals = tryget(mdl,'LoggingIntervals','[-inf, inf]');
orig.SimscapeLogType  = tryget(mdl,'SimscapeLogType','none');
orig.SaveOutput       = tryget(mdl,'SaveOutput','on');
orig.SaveTime         = tryget(mdl,'SaveTime','on');
orig.SaveState        = tryget(mdl,'SaveState','off');
orig.SaveFinalState   = tryget(mdl,'SaveFinalState','off');
orig.ReturnWorkspaceOutputs = tryget(mdl,'ReturnWorkspaceOutputs','on');

cleaner = onCleanup(@() restoreAllExtended(mdl, orig, warn_state_all)); %#ok<NASGU>

%% Sweep run settings
% Keep SDI recording off to avoid disk growth.
% Keep SaveOutput/SaveTime/SignalLogging on because your model outputs are needed.
try
    Simulink.sdi.clear;
    Simulink.sdi.setAutoArchiveMode(false);
    Simulink.sdi.setRecordData(true);
catch
end

trySet(mdl,'FastRestart','off');
trySet(mdl,'LoggingIntervals','[-inf, inf]');
trySet(mdl,'SignalLogging','on');
trySet(mdl,'SimscapeLogType','none');
trySet(mdl,'SaveOutput','on');
trySet(mdl,'SaveTime','on');
trySet(mdl,'SaveState','off');
trySet(mdl,'SaveFinalState','off');
trySet(mdl,'ReturnWorkspaceOutputs','on');

set_param(mdl,'StopTime',num2str(t_stop));

if USE_FAST_RESTART
    try
        set_param(mdl,'FastRestart','on');
        fprintf('Fast Restart enabled.\n');
    catch ME
        fprintf('Fast Restart could not be enabled: %s\n', ME.message);
    end
else
    set_param(mdl,'FastRestart','off');
    fprintf('Fast Restart disabled.\n');
end

%% Signal names exported by To Workspace blocks
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

if explicitLossesAvailable
    fprintf('Explicit-loss channels detected: P_inv1_loss, P_inv2_loss, P_dcdc_loss, P_dump\n');
else
    fprintf('Explicit-loss channels missing; deriving missing terms from corrected power differences.\n');
end

%% Build grid and feasibility mask
[SPD, TRQ] = meshgrid(speed_pts, torque_pts);
sz = size(SPD);

feas = true(sz);

for k = 1:numel(SPD)
    n   = SPD(k);
    Tab = abs(TRQ(k));

    if Tab > PMSM.T_peak
        feas(k) = false;
        continue
    end

    omega_e = PMSM.p * n * 2*pi/60;
    E_pk    = PMSM.lambda_m * omega_e;
    Vph_pk_limit = BAT.V_nom / sqrt(3);

    if E_pk > 1.5 * Vph_pk_limit
        feas(k) = false;
    end
end

%% Result fields
F = { ...
    'spd_avg','spd_std','T_wind_end', ...
    'Pba','Pi1','Pme','Pmm','Pgm','Pge','Pi2','Pdi','Pdo','Pbb_term','Pbb_store', ...
    'Lcu_m','Lfe_m','Lcu_g','Lfe_g','Lshaft','LbatA','LbatB','Ltot', ...
    'Linv1','Linv2','Ldcdc','Ldump','Pbus','Ltot_explicit', ...
    'battA_balance_W','battA_balance_pct', ...
    'inv1_balance_W','inv1_balance_pct', ...
    'motor_balance_W','motor_balance_pct', ...
    'gen_balance_W','gen_balance_pct', ...
    'inv2_balance_W','inv2_balance_pct', ...
    'bus_balance_W','bus_balance_pct', ...
    'dcdc_balance_W','dcdc_balance_pct', ...
    'battB_balance_W','battB_balance_pct', ...
    'shaft_balance_W','shaft_balance_pct', ...
    'PB_resid_W','PB_resid_pct', ...
    'eta_battA','eta_inv1','eta_motor','eta_shaft','eta_gen','eta_inv2','eta_dcdc','eta_battB', ...
    'eta_regen','eta_rig','eta_b2b'};

%% Fresh result structure
Rfresh = struct();
Rfresh.speed_pts  = speed_pts;
Rfresh.torque_pts = torque_pts;
Rfresh.SPD        = SPD;
Rfresh.TRQ        = TRQ;
Rfresh.feasible   = feas;
Rfresh.explicitLossesAvailable = explicitLossesAvailable;

for f = 1:numel(F)
    Rfresh.(F{f}) = nan(sz);
end

Rfresh.VALID      = false(sz);
Rfresh.REJECT     = zeros(sz);
Rfresh.PB_WARN    = false(sz);
Rfresh.BATTA_WARN = false(sz);
Rfresh.INV1_WARN  = false(sz);
Rfresh.MOTOR_WARN = false(sz);
Rfresh.GEN_WARN   = false(sz);
Rfresh.INV2_WARN  = false(sz);
Rfresh.BUS_WARN   = false(sz);
Rfresh.DCDC_WARN  = false(sz);
Rfresh.BATTB_WARN = false(sz);
Rfresh.SHAFT_WARN = false(sz);
Rfresh.ERR        = repmat({''}, sz);

%% Fresh or resume
if mode == "resume"
    if exist(resumeFile, 'file')
        Sresume = load(resumeFile);

        if ~isfield(Sresume,'R')
            error('Resume file exists but does not contain R.');
        end

        R = Sresume.R;

        if ~isequal(size(R.SPD), size(SPD)) || ~isequal(R.SPD, SPD) || ~isequal(R.TRQ, TRQ)
            error('Resume file grid does not match current sweep grid.');
        end

        fprintf('\n=== Resuming from %s ===\n', resumeFile);
        fprintf('Already completed: %d / %d\n', nnz(R.VALID | R.REJECT ~= 0), numel(R.REJECT));
    else
        error('No resume checkpoint found. Run R = run_efficiency_sweep(''fresh'') first.');
    end
else
    R = Rfresh;
    fprintf('\n=== Fresh sweep requested. Old resume file will be overwritten. ===\n');

    if exist(resumeFile,'file')
        delete(resumeFile);
    end
end

%% Sweep loop
fprintf('Running sweep...\n');
tic;

total = numel(SPD);

if mode == "resume"
    done = nnz(R.VALID | R.REJECT ~= 0);
else
    done = 0;
end

for k = 1:numel(SPD)

    n_ref = SPD(k);
    T_ref = TRQ(k);

    %% Resume mode: skip completed points
    if mode == "resume" && (R.VALID(k) || R.REJECT(k) ~= 0)
        continue
    end

    %% Periodically reset Fast Restart to control memory build-up
    if USE_FAST_RESTART && done > 0 && mod(done, fast_restart_reset_every) == 0
        fprintf('\nResetting Fast Restart at completed case %d...\n', done);
        try
            set_param(mdl,'FastRestart','off');
            Simulink.sdi.clear;
            pack;
            set_param(mdl,'FastRestart','on');
            fprintf('Fast Restart re-enabled.\n');
        catch ME
            fprintf('Fast Restart reset warning: %s\n', ME.message);
        end
    end

    %% Infeasible envelope
    if ~feas(k)
        R.REJECT(k) = 1;
        done = done + 1;
        printStatus(done,total,n_ref,T_ref,'REJECT 1 infeasible envelope',toc);
        checkpointIfNeeded(R, done, total, checkpoint_every);
        continue
    end

    %% Set operating point
    assignin('base','SpeedRef_rpm_cmd',     n_ref);
    assignin('base','TorqueRef_gen_Nm_cmd', T_ref);
    assignin('base','omega_init_cmd',       n_ref*2*pi/60);

    %% Clear previous To Workspace variables from base workspace
    clearLoggedVarsFromBase(S);

    %% Run simulation
    try
        simOut = sim(mdl,'StopTime',num2str(t_stop),'ReturnWorkspaceOutputs','on');
    catch ME
        R.REJECT(k) = 9;
        R.ERR{k} = ME.message;
        done = done + 1;
        printStatus(done,total,n_ref,T_ref,['REJECT 9 sim error: ' ME.message],toc);
        clear simOut
        cleanupAfterCase(done);
        checkpointIfNeeded(R, done, total, checkpoint_every);
        continue
    end

    %% Extract scalar results
    out = postExtractCorrected(simOut, t_settle, t_stop, S, explicitLossesAvailable);

    if ~out.ok
        R.REJECT(k) = 5;
        R.ERR{k} = out.err;
        done = done + 1;
        printStatus(done,total,n_ref,T_ref,['REJECT 5 extraction error: ' out.err],toc);
        clear simOut out
        cleanupAfterCase(done);
        checkpointIfNeeded(R, done, total, checkpoint_every);
        continue
    end

    %% Store extracted values even if later rejected
    for f = 1:numel(F)
        if isfield(out, F{f})
            R.(F{f})(k) = out.(F{f});
        end
    end

    %% Rejection rules
    rejectMsg = '';

    if isnan(out.spd_avg) || out.spd_avg < 0
        R.REJECT(k) = 2;
        rejectMsg = sprintf('REJECT 2 bad speed: %.3g rpm', out.spd_avg);

    elseif isnan(out.spd_std) || out.spd_std > 50
        R.REJECT(k) = 3;
        rejectMsg = sprintf('REJECT 3 speed std %.2f rpm', out.spd_std);

    elseif abs(out.spd_avg - n_ref) > 150
        R.REJECT(k) = 4;
        rejectMsg = sprintf('REJECT 4 speed mismatch avg %.1f rpm', out.spd_avg);

    else
        pNames = {'Pba','Pi1','Pme','Pmm','Pgm','Pge','Pi2','Pdi','Pdo','Pbb_term','Pbb_store'};
        pVals  = [out.Pba out.Pi1 out.Pme out.Pmm out.Pgm out.Pge out.Pi2 out.Pdi out.Pdo out.Pbb_term out.Pbb_store];

        badNaN  = isnan(pVals);
        badZero = pVals < 1e-3;

        if any(badNaN | badZero)
            R.REJECT(k) = 6;

            fprintf('\nREJECT 6 detail at %.0f rpm / %.0f Nm:\n', n_ref, T_ref);
            for jj = find(badNaN | badZero)
                if badNaN(jj)
                    fprintf('  %s = NaN\n', pNames{jj});
                else
                    fprintf('  %s = %.6g W\n', pNames{jj}, pVals(jj));
                end
            end

            rejectMsg = 'REJECT 6 zero/NaN core power';
        end
    end

    if R.REJECT(k) ~= 0
        done = done + 1;
        printStatus(done,total,n_ref,T_ref,rejectMsg,toc);
        clear simOut out
        cleanupAfterCase(done);
        checkpointIfNeeded(R, done, total, checkpoint_every);
        continue
    end

    %% Balance warnings
    warn_parts = {};

    if abs(out.PB_resid_pct) > 5
        R.PB_WARN(k) = true;
        warn_parts{end+1} = sprintf('PB %.2f%%%%', out.PB_resid_pct); %#ok<AGROW>
    end
    if abs(out.battA_balance_pct) > 5
        R.BATTA_WARN(k) = true;
        warn_parts{end+1} = sprintf('BA %.2f%%%%', out.battA_balance_pct); %#ok<AGROW>
    end
    if abs(out.inv1_balance_pct) > 5
        R.INV1_WARN(k) = true;
        warn_parts{end+1} = sprintf('I1 %.2f%%%%', out.inv1_balance_pct); %#ok<AGROW>
    end
    if abs(out.motor_balance_pct) > 5
        R.MOTOR_WARN(k) = true;
        warn_parts{end+1} = sprintf('M %.2f%%%%', out.motor_balance_pct); %#ok<AGROW>
    end
    if abs(out.gen_balance_pct) > 5
        R.GEN_WARN(k) = true;
        warn_parts{end+1} = sprintf('G %.2f%%%%', out.gen_balance_pct); %#ok<AGROW>
    end
    if abs(out.inv2_balance_pct) > 5
        R.INV2_WARN(k) = true;
        warn_parts{end+1} = sprintf('I2 %.2f%%%%', out.inv2_balance_pct); %#ok<AGROW>
    end
    if abs(out.bus_balance_pct) > 5
        R.BUS_WARN(k) = true;
        warn_parts{end+1} = sprintf('BUS %.2f%%%%', out.bus_balance_pct); %#ok<AGROW>
    end
    if abs(out.dcdc_balance_pct) > 5
        R.DCDC_WARN(k) = true;
        warn_parts{end+1} = sprintf('DCDC %.2f%%%%', out.dcdc_balance_pct); %#ok<AGROW>
    end
    if abs(out.battB_balance_pct) > 5
        R.BATTB_WARN(k) = true;
        warn_parts{end+1} = sprintf('BB %.2f%%%%', out.battB_balance_pct); %#ok<AGROW>
    end
    if abs(out.shaft_balance_pct) > 5
        R.SHAFT_WARN(k) = true;
        warn_parts{end+1} = sprintf('SH %.2f%%%%', out.shaft_balance_pct); %#ok<AGROW>
    end

    %% Efficiencies
    out = computeEfficienciesCorrected(out);

    etaNames = {'eta_battA','eta_inv1','eta_motor','eta_shaft','eta_gen','eta_inv2','eta_dcdc','eta_battB','eta_regen','eta_rig','eta_b2b'};
    etas = struct2vec(out, etaNames);

    if any(isnan(etas) | isinf(etas) | etas <= 0 | etas > 1)
        R.REJECT(k) = 8;

        fprintf('\nREJECT 8 efficiency detail at %.0f rpm / %.0f Nm:\n', n_ref, T_ref);
        for jj = 1:numel(etaNames)
            fprintf('  %s = %.6g\n', etaNames{jj}, etas(jj));
        end

        done = done + 1;
        printStatus(done,total,n_ref,T_ref,'REJECT 8 invalid efficiency',toc);
        clear simOut out etas warn_parts
        cleanupAfterCase(done);
        checkpointIfNeeded(R, done, total, checkpoint_every);
        continue
    end

    %% Store accepted values
    for f = 1:numel(F)
        if isfield(out, F{f})
            R.(F{f})(k) = out.(F{f});
        end
    end

    R.VALID(k) = true;

    done = done + 1;

    if isempty(warn_parts)
        msg = sprintf('VALID | eta_motor=%5.1f%%%% | eta_gen=%5.1f%%%% | eta_rig=%5.1f%%%%', ...
            100*out.eta_motor, 100*out.eta_gen, 100*out.eta_rig);
    else
        msg = sprintf('VALID | eta_motor=%5.1f%%%% | eta_gen=%5.1f%%%% | eta_rig=%5.1f%%%% | WARN: %s', ...
            100*out.eta_motor, 100*out.eta_gen, 100*out.eta_rig, strjoin(warn_parts, ' | '));
    end

    printStatus(done,total,n_ref,T_ref,msg,toc);

    clear simOut out etas warn_parts
    cleanupAfterCase(done);
    checkpointIfNeeded(R, done, total, checkpoint_every);
end

%% Final summary
fprintf('\nDone in %.1f min.\n', toc/60);
fprintf('Valid points: %d / %d\n', nnz(R.VALID), numel(R.VALID));
fprintf('Rejected points: %d / %d\n', nnz(R.REJECT ~= 0), numel(R.REJECT));
fprintf('PB warnings: %d / %d\n', nnz(R.PB_WARN), numel(R.PB_WARN));
fprintf('Motor warnings: %d / %d\n', nnz(R.MOTOR_WARN), numel(R.MOTOR_WARN));
fprintf('Generator warnings: %d / %d\n', nnz(R.GEN_WARN), numel(R.GEN_WARN));
fprintf('Shaft warnings: %d / %d\n', nnz(R.SHAFT_WARN), numel(R.SHAFT_WARN));
fprintf('DC/DC warnings: %d / %d\n', nnz(R.DCDC_WARN), numel(R.DCDC_WARN));
fprintf('Bus warnings: %d / %d\n', nnz(R.BUS_WARN), numel(R.BUS_WARN));
fprintf('Battery A warnings: %d / %d\n', nnz(R.BATTA_WARN), numel(R.BATTA_WARN));
fprintf('Inverter 1 warnings: %d / %d\n', nnz(R.INV1_WARN), numel(R.INV1_WARN));
fprintf('Inverter 2 warnings: %d / %d\n', nnz(R.INV2_WARN), numel(R.INV2_WARN));
fprintf('Battery B warnings: %d / %d\n', nnz(R.BATTB_WARN), numel(R.BATTB_WARN));

save('sweep_results_fixed_boundaries_full.mat','R','-v7.3');
save('sweep_results_fixed_boundaries_full_unpacked.mat','-struct','R','-v7.3');
save(resumeFile,'R','done','total','-v7.3');

fprintf('\nSaved:\n');
fprintf('  sweep_results_fixed_boundaries_full.mat\n');
fprintf('  sweep_results_fixed_boundaries_full_unpacked.mat\n');
fprintf('  sweep_resume_latest.mat\n');

end

%% =========================================================================
% Helper functions
%% =========================================================================

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

function printStatus(done,total,n_ref,T_ref,msg,elapsed)

eta_min = (elapsed/max(done,1)) * (total-done) / 60;

fprintf('[%3d/%3d] %4d RPM / %4.0f Nm | %s | ETA %.1f min\n', ...
    done, total, n_ref, T_ref, msg, eta_min);

end

function assertSignalAvailability(mdl, signalNames)

vars = getToWorkspaceVars(mdl);
missing = signalNames(~ismember(signalNames, vars));

if ~isempty(missing)
    error('Sweep:MissingSignals', ...
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

if isempty(ts)
    try
        ts = so.(name);
    catch
    end
end

if isempty(ts)
    try
        ts = evalin('base', name);
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

    elseif isstruct(ts) && isfield(ts,'time') && isfield(ts,'signals')
        tf = isempty(ts.time) || isempty(ts.signals.values);

    elseif isnumeric(ts)
        tf = isempty(ts) || all(isnan(ts(:)));

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

elseif isstruct(ts) && isfield(ts,'time') && isfield(ts,'signals')
    t = ts.time(:);
    y = squeeze(ts.signals.values);

elseif isnumeric(ts)
    y = ts(:);
    t = linspace(0, numel(y)-1, numel(y)).';

else
    error('tsTY:badClass','Unexpected signal class: %s', class(ts));
end

y = y(:);

if numel(y) ~= numel(t)
    y = reshape(y, numel(t), []);
    y = y(:,1);
end

end

function v = struct2vec(s, names)

v = nan(numel(names),1);

for i = 1:numel(names)
    if isfield(s, names{i})
        v(i) = s.(names{i});
    end
end

end

function val = tryget(obj, param, default)

try
    val = get_param(obj, param);
catch
    val = default;
end

end

function trySet(obj, param, val)

try
    set_param(obj, param, val);
catch
end

end

function checkpointIfNeeded(R, done, total, checkpoint_every)

if mod(done, checkpoint_every) == 0 || done == total

    tmpFile    = 'sweep_resume_latest_tmp.mat';
    resumeFile = 'sweep_resume_latest.mat';

    save(tmpFile,'R','done','total','-v7.3');
    movefile(tmpFile, resumeFile, 'f');

    backupName = sprintf('sweep_partial_%03d_of_%03d.mat', done, total);
    save(backupName,'R','done','total','-v7.3');

    fprintf('Checkpoint saved at %d / %d\n', done, total);
end

end

function cleanupAfterCase(done)

try
    Simulink.sdi.clear;
catch
end

if mod(done, 25) == 0
    try
        pack;
    catch
    end
end

end

function clearLoggedVarsFromBase(S)

names = struct2cell(S);

for i = 1:numel(names)
    try
        evalin('base', sprintf('clear(''%s'')', names{i}));
    catch
    end
end

end

function restoreAllExtended(mdl, orig, warn_state_all)

try set_param(mdl,'FastRestart','off'); catch, end
try set_param(mdl,'SignalLogging',    orig.SignalLogging);    catch, end
try set_param(mdl,'SimscapeLogType',  orig.SimscapeLogType);  catch, end
try set_param(mdl,'LoggingIntervals', orig.LoggingIntervals); catch, end
try set_param(mdl,'SaveOutput',       orig.SaveOutput);       catch, end
try set_param(mdl,'SaveTime',         orig.SaveTime);         catch, end
try set_param(mdl,'SaveState',        orig.SaveState);        catch, end
try set_param(mdl,'SaveFinalState',   orig.SaveFinalState);   catch, end
try set_param(mdl,'ReturnWorkspaceOutputs', orig.ReturnWorkspaceOutputs); catch, end

try
    Simulink.sdi.setRecordData(true);
    Simulink.sdi.setAutoArchiveMode(true);
catch
end

try
    warning(warn_state_all);
catch
end

end