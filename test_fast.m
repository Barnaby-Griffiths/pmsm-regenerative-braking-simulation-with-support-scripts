function R = test_fast()
%% =========================================================================
% test_fast.m
%
% Fixed-boundary operating-point sweep for Final.slx. Runs a 5x5 reduced
% grid of speed/regen-torque points, extracts averaged powers and losses,
% computes corrected section and top-line efficiencies using the same
% accounting as test_one.m, and saves results to
% sweep_results_fixed_boundaries_fast.mat.
%% =========================================================================

clc;
close all force;

%% 1) Load model parameters
INIT_VERBOSE    = true;
INIT_MAKE_PLOTS = false;
simulink_init_params_CORRECTED

% The model resolves parameter structs from the base workspace.
% This keeps the script safe when run as a function.
baseVars = {'PMSM','INV','INV2','BAT','BAT_A','BAT_B','DCLINK','DCDC','MECH','FOC','THERM','FW','SIM'};
for ii = 1:numel(baseVars)
    if exist(baseVars{ii}, 'var')
        assignin('base', baseVars{ii}, eval(baseVars{ii}));
    end
end

mdl = 'Final';

%% 2) Simulation and sweep configuration
t_stop           = SIM.t_sim;        % [s]
t_settle         = SIM.t_settle;     % [s]
USE_FAST_RESTART = true;
checkpoint_every = 5;

speed_full  = SIM.speed_rpm;         % [RPM]
torque_full = SIM.torque_regen_Nm;   % [N.m]

speed_idx   = unique(round(linspace(1, numel(speed_full), 5)));
torque_idx  = unique(round(linspace(1, numel(torque_full), 5)));

assert(numel(speed_idx)  == 5, 'Expected at least 5 speed points in SIM.speed_rpm');
assert(numel(torque_idx) == 5, 'Expected at least 5 torque points in SIM.torque_regen_Nm');

speed_pts   = speed_full(speed_idx);    % [RPM]
torque_pts  = torque_full(torque_idx);  % [N.m]

fprintf('Sweep: %d speed points x %d torque points = %d cases\n', ...
    numel(speed_pts), numel(torque_pts), numel(speed_pts)*numel(torque_pts));

%% 3) Load model and stash original settings
if ~bdIsLoaded(mdl)
    load_system(mdl);
end

warn_state_all = warning;
warning('off','all');

orig = struct();
orig.SignalLogging    = tryget(mdl,'SignalLogging','off');
orig.FastRestart      = tryget(mdl,'FastRestart','off');
orig.LoggingIntervals = tryget(mdl,'LoggingIntervals','[-inf, inf]');
orig.SimscapeLogType  = tryget(mdl,'SimscapeLogType','none');

cleaner = onCleanup(@() restoreAllExtended(mdl, orig, warn_state_all)); %#ok<NASGU>

set_param(mdl,'LoggingIntervals','[-inf, inf]');
trySet(mdl,'SignalLogging','off');
trySet(mdl,'SimscapeLogType','none');

if USE_FAST_RESTART
    try
        set_param(mdl,'FastRestart','on');
        fprintf('Fast Restart enabled.\n');
    catch ME
        fprintf('Fast Restart could not be enabled: %s\n', ME.message);
    end
end

%% 4) Signal names exported by the model
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

%% 5) Check that required signals are available
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

%% 6) Build grid and mark infeasible points
[SPD, TRQ] = meshgrid(speed_pts, torque_pts);   % [RPM], [N.m]
sz = size(SPD);
feas = true(sz);

% Avoid Simulink.SimulationInput here: this model uses base-workspace structs.
% Set StopTime directly and drive command variables through assignin().
set_param(mdl, 'StopTime', num2str(t_stop));

for k = 1:numel(SPD)
    n = SPD(k);          % [RPM]
    Tab = abs(TRQ(k));   % [N.m]

    if Tab > PMSM.T_peak
        feas(k) = false;
        continue
    end

    omega_e = PMSM.p * n * 2*pi/60;              % [rad/s]
    E_pk    = PMSM.lambda_m * omega_e;           % [V]
    Vph_pk_limit = BAT.V_nom / sqrt(3);          % [V]

    if E_pk > 1.5 * Vph_pk_limit
        feas(k) = false;
    end
end

%% 7) Allocate result struct
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

R = struct();
R.speed_pts  = speed_pts;
R.torque_pts = torque_pts;
R.SPD        = SPD;
R.TRQ        = TRQ;
R.feasible   = feas;
R.explicitLossesAvailable = explicitLossesAvailable;

for f = 1:numel(F)
    R.(F{f}) = nan(sz);
end
R.VALID      = false(sz);
R.REJECT     = zeros(sz);
R.PB_WARN    = false(sz);
R.BATTA_WARN = false(sz);
R.INV1_WARN  = false(sz);
R.MOTOR_WARN = false(sz);
R.GEN_WARN   = false(sz);
R.INV2_WARN  = false(sz);
R.BUS_WARN   = false(sz);
R.DCDC_WARN  = false(sz);
R.BATTB_WARN = false(sz);
R.SHAFT_WARN = false(sz);
R.ERR        = repmat({''}, sz);

%% 8) Sweep loop
fprintf('Running %d points...\n', numel(SPD));
tic;
done  = 0;
total = numel(SPD);

for k = 1:numel(SPD)
    n_ref = SPD(k);    % [RPM]
    T_ref = TRQ(k);    % [N.m]

    if ~feas(k)
        R.REJECT(k) = 1;
        done = done + 1;
        printStatus(done,total,n_ref,T_ref,'REJECT 1',toc);
        continue
    end

    assignin('base', 'SpeedRef_rpm_cmd',     n_ref);
    assignin('base', 'TorqueRef_gen_Nm_cmd', T_ref);
    assignin('base', 'omega_init_cmd',       n_ref*2*pi/60);

    try
        simOut = sim(mdl, 'StopTime', num2str(t_stop), 'ReturnWorkspaceOutputs', 'on');
    catch ME
        R.REJECT(k) = 9;
        R.ERR{k} = ME.message;
        done = done + 1;
        printStatus(done,total,n_ref,T_ref,['REJECT 9 (' ME.message ')'],toc);
        continue
    end

    out = postExtractCorrected(simOut, t_settle, t_stop, S, explicitLossesAvailable);

    if ~out.ok
        R.REJECT(k) = 5;
        R.ERR{k} = out.err;
        done = done + 1;
        printStatus(done,total,n_ref,T_ref,['REJECT 5 (' out.err ')'],toc);
        continue
    end

    %% Apply rejection rules on the averaged window
    if out.spd_avg < 0
        R.REJECT(k) = 2;
    elseif out.spd_std > 50
        R.REJECT(k) = 3;
    elseif abs(out.spd_avg - n_ref) > 150
        R.REJECT(k) = 4;
    elseif any([out.Pba out.Pi1 out.Pme out.Pmm out.Pgm out.Pge out.Pi2 out.Pdi out.Pdo out.Pbb_term out.Pbb_store] < 1e-3 | ...
               isnan([out.Pba out.Pi1 out.Pme out.Pmm out.Pgm out.Pge out.Pi2 out.Pdi out.Pdo out.Pbb_term out.Pbb_store]))
        R.REJECT(k) = 6;
    end

    if R.REJECT(k) ~= 0
        done = done + 1;
        printStatus(done,total,n_ref,T_ref,sprintf('REJECT %d',R.REJECT(k)),toc);
        continue
    end

    %% Flag large balance residuals
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

    %% Compute efficiencies and sanity-check range
    out = computeEfficienciesCorrected(out);
    etas = struct2vec(out, {'eta_battA','eta_inv1','eta_motor','eta_shaft','eta_gen','eta_inv2','eta_dcdc','eta_battB','eta_regen','eta_rig','eta_b2b'});

    if any(etas <= 0 | etas > 1 | isnan(etas))
        R.REJECT(k) = 8;
        done = done + 1;
        printStatus(done,total,n_ref,T_ref,'REJECT 8',toc);
        continue
    end

    %% Store accepted point
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

    if mod(done, checkpoint_every) == 0
        save('sweep_partial_fixed_boundaries_fast.mat','-struct','R','-v7.3');
    end
end

%% 9) Summary and save
fprintf('\nDone in %.1f min.\n', toc/60);
fprintf('Valid points: %d / %d\n', nnz(R.VALID), numel(R.VALID));
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
save('sweep_results_fixed_boundaries_fast.mat','-struct','R','-v7.3');

end

function r = postExtractCorrected(so, t1, t2, S, explicitLossesAvailable)
%% Extract averaged powers, losses and corrected balance residuals over [t1, t2]
r = struct();
r.ok = false;
r.err = '';

try
    %% Average core signals over the settled window
    coreNames = {'speed','P_battA_out','P_inv1_out','P_motor_elec','P_motor_mech','P_gen_mech','P_gen_elec', ...
                 'P_inv2_out','P_dcdc_in','P_dcdc_out','P_battB_in', ...
                 'P_batA_loss','P_batB_loss','P_shaft_loss','P_tot_loss','T_wind', ...
                 'P_cu_motor','P_fe_motor','P_cu_gen','P_fe_gen'};

    for ii = 1:numel(coreNames)
        key = coreNames{ii};
        ts = findSafely(so, S.(key));
        r.(['avg_' key]) = avgInWindow(ts, t1, t2);
    end

    %% Average explicit loss channels if available
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

    %% Speed standard deviation over the settled window
    ts = findSafely(so, S.speed);
    if ~isTsEmpty(ts)
        [t, y] = tsTY(ts);
        m = t >= t1 & t <= t2;
        if any(m), r.spd_std = std(y(m), 'omitnan'); else, r.spd_std = NaN; end
    else
        r.spd_std = NaN;
    end

    %% End-of-run winding temperature over the last 0.2 s
    ts = findSafely(so, S.T_wind);
    if ~isTsEmpty(ts)
        [t, y] = tsTY(ts);
        m = t >= max(t1, t2-0.2) & t <= t2;
        if any(m), r.T_wind_end = mean(y(m), 'omitnan'); else, r.T_wind_end = NaN; end
    else
        r.T_wind_end = NaN;
    end

    %% Pack averaged quantities with short aliases
    r.spd_avg   = r.avg_speed;              % [RPM]
    r.Pba       = abs(r.avg_P_battA_out);   % [W]
    r.Pi1       = abs(r.avg_P_inv1_out);    % [W]
    r.Pme       = abs(r.avg_P_motor_elec);  % [W]
    r.Pmm       = abs(r.avg_P_motor_mech);  % [W]
    r.Pgm       = abs(r.avg_P_gen_mech);    % [W]
    r.Pge       = abs(r.avg_P_gen_elec);    % [W]
    r.Pi2       = abs(r.avg_P_inv2_out);    % [W]
    r.Pdi       = abs(r.avg_P_dcdc_in);     % [W]
    r.Pdo       = abs(r.avg_P_dcdc_out);    % [W]
    r.Pbb_term  = r.Pdo;                    % [W]
    r.Pbb_store = abs(r.avg_P_battB_in);    % [W]

    r.Lcu_m     = abs(r.avg_P_cu_motor);    % [W]
    r.Lfe_m     = abs(r.avg_P_fe_motor);    % [W]
    r.Lcu_g     = abs(r.avg_P_cu_gen);      % [W]
    r.Lfe_g     = abs(r.avg_P_fe_gen);      % [W]
    r.Lshaft    = abs(r.avg_P_shaft_loss);  % [W]
    r.LbatA     = abs(r.avg_P_batA_loss);   % [W]
    r.LbatB     = abs(r.avg_P_batB_loss);   % [W]
    r.Ltot      = abs(r.avg_P_tot_loss);    % [W]
    r.Ldump     = abs(r.avg_P_dump);        % [W]

    if explicitLossesAvailable
        r.Linv1 = abs(r.avg_P_inv1_loss);   % [W]
        r.Linv2 = abs(r.avg_P_inv2_loss);   % [W]
        r.Ldcdc = abs(r.avg_P_dcdc_loss);   % [W]
    else
        r.Linv1 = max(r.Pba - r.Pi1, 0);    % [W]
        r.Linv2 = max(r.Pge - r.Pi2, 0);    % [W]
        r.Ldcdc = max(r.Pdi - r.Pdo, 0);    % [W]
    end

    r.Pbus = max(r.Pi2 - r.Pdi, 0);         % [W]

    %% Corrected terminal-basis explicit-loss sum
    % Do NOT include LbatA here because Pba is already Battery A terminal power.
    r.Ltot_explicit = r.Linv1 + r.Lcu_m + r.Lfe_m + ...
                      r.Lshaft + r.Lcu_g + r.Lfe_g + ...
                      r.Linv2 + r.Pbus + r.Ldcdc + ...
                      r.LbatB + r.Ldump;                        % [W]

    %% Corrected section balance residuals
    r.battA_balance_W   = r.Pba - r.Pme - r.Linv1;             % [W]
    battA_den = max([r.Pba, r.Pme + r.Linv1, 1000]);
    r.battA_balance_pct = 100 * r.battA_balance_W / battA_den;

    r.inv1_balance_W    = r.Pi1 - r.Pme;                       % [W]
    inv1_den = max([r.Pi1, r.Pme, 1000]);
    r.inv1_balance_pct  = 100 * r.inv1_balance_W / inv1_den;

    r.motor_balance_W   = r.Pme - r.Pmm - r.Lcu_m - r.Lfe_m;  % [W]
    motor_den = max([r.Pme, r.Pmm + r.Lcu_m + r.Lfe_m, 1000]);
    r.motor_balance_pct = 100 * r.motor_balance_W / motor_den;

    r.shaft_balance_W   = r.Pmm - r.Pgm - r.Lshaft;           % [W]
    shaft_den = max([r.Pmm, r.Pgm + r.Lshaft, 1000]);
    r.shaft_balance_pct = 100 * r.shaft_balance_W / shaft_den;

    r.gen_balance_W     = r.Pgm - r.Pge - r.Lcu_g - r.Lfe_g; % [W]
    gen_den = max([r.Pgm, r.Pge + r.Lcu_g + r.Lfe_g, 1000]);
    r.gen_balance_pct   = 100 * r.gen_balance_W / gen_den;

    r.inv2_balance_W    = r.Pge - r.Pi2 - r.Linv2;           % [W]
    inv2_den = max([r.Pge, r.Pi2 + r.Linv2, 1000]);
    r.inv2_balance_pct  = 100 * r.inv2_balance_W / inv2_den;

    r.bus_balance_W     = r.Pi2 - r.Pdi - r.Pbus;            % [W]
    bus_den = max([r.Pi2, r.Pdi + r.Pbus, 1000]);
    r.bus_balance_pct   = 100 * r.bus_balance_W / bus_den;

    r.dcdc_balance_W    = r.Pdi - r.Pdo - r.Ldcdc;           % [W]
    dcdc_den = max([r.Pdi, r.Pdo + r.Ldcdc, 1000]);
    r.dcdc_balance_pct  = 100 * r.dcdc_balance_W / dcdc_den;

    % Include Ldump here because P_dump is rejected power on the Battery-B side.
    r.battB_balance_W   = r.Pdo - r.Pbb_store - r.LbatB - r.Ldump;     % [W]
    battB_den = max([r.Pdo, r.Pbb_store + r.LbatB + r.Ldump, 1000]);
    r.battB_balance_pct = 100 * r.battB_balance_W / battB_den;

    %% Whole-rig corrected residual
    r.PB_resid_W   = r.Pba - r.Pbb_store - r.Ltot_explicit;  % [W]
    pb_den = max([r.Pba, r.Pbb_store + r.Ltot_explicit, 1000]);
    r.PB_resid_pct = 100 * r.PB_resid_W / pb_den;   % [%]

    r.ok = true;

catch ME
    r.ok = false;
    r.err = ME.message;
end
end

function out = computeEfficienciesCorrected(out)
%% Section and top-line efficiencies from averaged powers and corrected losses
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
%% Mean value of ts over [t1, t2] with NaN for empty windows
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
%% Names of all ToWorkspace variables in the model
tw = find_system(mdl,'LookUnderMasks','all','FollowLinks','on', ...
    'MatchFilter', @Simulink.match.allVariants, 'BlockType','ToWorkspace');
vars = cell(size(tw));
for k = 1:numel(tw)
    vars{k} = get_param(tw{k},'VariableName');
end
end

function printStatus(done,total,n_ref,T_ref,msg,elapsed)
%% Per-point progress line with running ETA
eta_min = (elapsed/max(done,1)) * (total-done) / 60;   % [min]
fprintf('[%3d/%3d] %4d RPM / %4.0f Nm | %s | ETA %.1f min\n', ...
    done, total, n_ref, T_ref, msg, eta_min);
end

function assertSignalAvailability(mdl, signalNames)
%% Error if any required ToWorkspace variable is missing from the model
vars = getToWorkspaceVars(mdl);
missing = signalNames(~ismember(signalNames, vars));
if ~isempty(missing)
    error('Sweep:MissingSignals', ...
        'These ToWorkspace variables are missing from the model: %s', ...
        strjoin(missing, ', '));
end
end

function ts = findSafely(so, name)
%% Retrieve a logged signal by name from a simOut object
ts = [];
try, ts = so.get(name); catch, end
if isempty(ts)
    try, ts = so.find(name); catch, end
end
if isempty(ts)
    try, ts = so.logsout.get(name); catch, end
end
end

function tf = isTsEmpty(ts)
%% True if the signal has no time or data samples
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
    error('tsTY:badClass','Unexpected signal class: %s', class(ts));
end
y = y(:);
if numel(y) ~= numel(t)
    y = reshape(y, numel(t), []);
    y = y(:,1);
end
end

function v = struct2vec(s, names)
%% Pack named fields of struct s into a column vector
v = nan(numel(names),1);
for i = 1:numel(names)
    if isfield(s, names{i})
        v(i) = s.(names{i});
    end
end
end

function val = tryget(obj, param, default)
%% get_param with a default value on failure
try
    val = get_param(obj, param);
catch
    val = default;
end
end

function trySet(obj, param, val)
%% set_param that silently ignores failures
try
    set_param(obj, param, val);
catch
end
end

function restoreAllExtended(mdl, orig, warn_state_all)
%% Restore original model settings and warning state on cleanup
try, set_param(mdl,'FastRestart','off'); catch, end
try, set_param(mdl,'SignalLogging',   orig.SignalLogging);    catch, end
try, set_param(mdl,'SimscapeLogType', orig.SimscapeLogType);  catch, end
try, set_param(mdl,'LoggingIntervals',orig.LoggingIntervals); catch, end
try, warning(warn_state_all); catch, end
end