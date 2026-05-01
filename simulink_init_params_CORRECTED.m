%% =========================================================================
% simulink_init_params.m
%
% Parameter initialisation for Final.slx.
%
% Source key (third column of every block below):
%   D = manufacturer datasheet (cite in dissertation reference list)
%   T = standard textbook value (Krishnan, Bose, Ehsani et al.)
%   E = first-pass engineering estimate (sensitivity-tested in Chapter 5)
%   P = project specification agreed with supervisor
%
% Variables exposed to the model workspace:
%   PMSM, INV, INV2, BAT, BAT_A, BAT_B, DCLINK, DCDC, MECH, FOC, FW, SIM,
%   THERM, SpeedRef_rpm_cmd, TorqueRef_gen_Nm_cmd, omega_init_cmd
%% =========================================================================

fprintf('=== simulink_init_params ===\n\n');

%% 0) Optional behaviour flags ---------------------------------------------
% INIT_VERBOSE     : print parameter summary to the command window
% INIT_MAKE_PLOTS  : draw the analytical reference efficiency map
if ~exist('INIT_VERBOSE',   'var'), INIT_VERBOSE    = true;  end
if ~exist('INIT_MAKE_PLOTS','var'), INIT_MAKE_PLOTS = false; end

%% 1) PMSM electrical and mechanical parameters ----------------------------
% EMRAX 228 MV CC axial flux machine. All values from manufacturer datasheet
% (EMRAX, 2017) except for the iron loss and mechanical loss coefficients,
% which are textbook representative values for axial flux PMSMs.
PMSM.name        = 'EMRAX 228 MV CC';
PMSM.P_peak      = 124e3;            % [W]      D
PMSM.P_cont      = 75e3;             % [W]      D
PMSM.T_peak      = 220;              % [N.m]    D
PMSM.T_cont      = 130;              % [N.m]    D
PMSM.n_base      = 5500;             % [RPM]    D
PMSM.n_max       = 6500;             % [RPM]    D
PMSM.V_dc_rated  = 630;              % [V]      D
PMSM.p           = 10;               % pole pairs        D
PMSM.Rs          = 7.06e-3;          % [ohm]    D  (line-to-line resistance per phase)
PMSM.Ld          = 96.5e-6;          % [H]      D
PMSM.Lq          = 96.5e-6 * 1.04;   % [H]      D  (small saliency assumed, Lq/Ld = 1.04)
PMSM.J           = 0.02521;          % [kg.m^2] D
PMSM.D_stator    = 0.228;            % [m]      D
PMSM.I_peak      = 360;              % [A_rms]  D
PMSM.I_cont      = 180;              % [A_rms]  D

PMSM.ke_Vrms_RPM = 0.04793;          % [V_rms/RPM]   D  (line-to-line back-EMF constant)
PMSM.lambda_m    = 0.03737;          % [Wb]          D  (rotor flux linkage)

% Two torque constants are kept for reference. Kt_peak_theory is derived
% from lambda_m using the dq peak convention; Kt_rms is the datasheet value.
% See Section 3.x for the chosen value used by the controller.
PMSM.Kt_peak_theory = 1.5 * PMSM.p * PMSM.lambda_m;     % [N.m/A_peak] derived
PMSM.Kt_rms         = 0.61;                              % [N.m/A_rms]  D
PMSM.Kt_peak        = PMSM.Kt_rms / sqrt(2);             % [N.m/A_peak] derived

%% 2) Iron loss model coefficients -----------------------------------------
% Steinmetz hysteresis plus eddy current decomposition. Coefficients are
% representative values for laminated PMSM stators (Krishnan, 2017).
PMSM.iron.k_h    = 0.012;            %                   T  hysteresis coefficient
PMSM.iron.k_e    = 0.001;            %                   T  eddy current coefficient
PMSM.iron.alpha  = 1.7;              %                   T  Steinmetz exponent
PMSM.iron.B_pk   = 1.2;              % [T]               T  peak airgap flux density

%% 3) Mechanical friction and windage --------------------------------------
% Coulomb plus quadratic windage model. First-pass values; sensitivity
% analysis in Chapter 5 confirms total contribution is small at peak power.
PMSM.mech.T_f0   = 1.5;              % [N.m]             E  static friction
PMSM.mech.k_w    = 1.2e-7;           % [N.m.s^2/rad^2]   E  windage coefficient

%% 4) Inverter parameters --------------------------------------------------
% Sevcon Gen4 Size 8 traction-class IGBT inverter. Voltage and current
% ratings from manufacturer specification; switching/conduction loss
% parameters are representative IGBT values (Bose, 2020).
INV.Vdc_min       = 128;             % [V]               D
INV.Vdc_max       = 400;             % [V]               D
INV.I_phase_boost = 400;             % [A_rms]           D
INV.I_phase_30s   = 360;             % [A_rms]           D
INV.I_phase_2min  = 300;             % [A_rms]           D
INV.I_phase_cont  = 200;             % [A_rms]           D
INV.P_peak        = 100e3;           % [W]               D
INV.P_cont        = 60e3;            % [W]               D

INV.f_sw          = 16e3;            % [Hz]              D  PWM switching frequency
INV.f_sw_alt      = 24e3;            % [Hz]              D  alternative switching mode

INV.V_CE_sat      = 1.9;             % [V]               T  IGBT saturation voltage
INV.V_D_fwd       = 1.5;             % [V]               T  diode forward drop
INV.E_on_coeff    = 1.2e-7;          % [J/(A.V)]         T  turn-on energy coefficient
INV.E_off_coeff   = 1.0e-7;          % [J/(A.V)]         T  turn-off energy coefficient
INV.t_dead        = 2.0e-6;          % [s]               T  dead time

% Generator-side inverter assumed identical to motor side
INV2 = INV;

%% 5) Battery packs --------------------------------------------------------
% Nominal pack: 265 V, 50 Ah Li-ion automotive specification.
% Internal resistance set to 25 mOhm, consistent with packs of this voltage
% and capacity rating per Plett (2015) and Battery University data on
% automotive Li-ion cells. An earlier draft of the model used 0.15 ohm; the
% sensitivity to this parameter is reported in Chapter 5 Section 5.5.
BAT.V_nom         = 265;             % [V]               P
BAT.V_max         = 302;             % [V]               P
BAT.V_min         = 228;             % [V]               P
BAT.C_Ah          = 50;              % [Ah]              P
BAT.R_int         = 0.025;           % [ohm]             E  pack-level estimate, see Plett (2015)
BAT.SOC_init      = 0.80;            % [-]               P
BAT.I_regen_max   = 150;             % [A]               P  3 C charge limit

% Source battery (battery A) starts near full
BAT_A             = BAT;
BAT_A.SOC_init    = BAT.SOC_init;

% Sink battery (battery B) starts low and accepts charge up to SOC_charge_hi
BAT_B             = BAT;
BAT_B.SOC_init      = 0.20;          % [-]               P
BAT_B.I_charge_max  = BAT.I_regen_max; % [A]              P
BAT_B.SOC_charge_hi = 0.90;          % [-]               P

%% 5B) Recovery DC link ----------------------------------------------------
% Bus capacitor with a parallel dump resistor that activates on overvoltage.
DCLINK.C_F          = 0.002;         % [F]               D  Sevcon Gen4 Size 8 nominal bus capacitance (1880 uF rounded)
DCLINK.V_init       = 330;           % [V]               P
DCLINK.V_ref        = 330;           % [V]               P
DCLINK.V_dump_on    = 360;           % [V]               P  dump activation threshold
DCLINK.P_dump_max   = 25e3;          % [W]               P  dump resistor saturation
DCLINK.epsV         = 1;             % [V]               E  dead-band on safe-V calc

%% 5C) Averaged bidirectional DC/DC converter ------------------------------
% First-pass constant-efficiency model. A load-dependent efficiency map
% would improve fidelity at light load (see Chapter 5 Section 5.5).
DCDC.eta_chg          = 0.97;        % [-]               E
DCDC.eta_dis          = 0.96;        % [-]               E
DCDC.P_max            = BAT_B.V_nom * BAT_B.I_regen_max; % [W]  derived
DCDC.I_charge_max     = BAT_B.I_regen_max;               % [A]  derived
DCDC.I_discharge_max  = 80;          % [A]               P
DCDC.Kp_v             = 2.0;         %                   E  Vdc PI gain
DCDC.Ki_v             = 50.0;        %                   E  Vdc PI gain
DCDC.SOC_taper_start  = 0.85;        % [-]               P  charge taper start
DCDC.SOC_full         = 0.95;        % [-]               P  charge full
DCDC.epsV             = 1;           % [V]               E

%% 6) Mechanical coupling --------------------------------------------------
% Two PMSMs share a rigid coupling. Total inertia is the sum of both rotors
% plus the coupling. Damping is small but non-zero to ensure shaft balance.
MECH.J_coupling = 0.002;                       % [kg.m^2]      E
MECH.J_total    = 2 * PMSM.J + MECH.J_coupling; % [kg.m^2]      derived
MECH.B_damping  = 0.005;                       % [N.m.s/rad]   E

%% 7) Field-oriented control gains -----------------------------------------
% Bandwidth-based PI tuning. Current loop bandwidth chosen one decade above
% mechanical loop bandwidth. Gains are derived to give critical damping.
omega_BW_curr = 2000;                                  % [rad/s]    E
FOC.Kp_id     = PMSM.Ld * omega_BW_curr;
FOC.Ki_id     = PMSM.Rs * omega_BW_curr;
FOC.Kp_iq     = PMSM.Lq * omega_BW_curr;
FOC.Ki_iq     = PMSM.Rs * omega_BW_curr;

omega_BW_spd = 30;                                     % [rad/s]    E
rpm_to_radps = 2 * pi / 60;
FOC.Kp_speed  = MECH.J_total * omega_BW_spd       * rpm_to_radps;
FOC.Ki_speed  = MECH.J_total * omega_BW_spd^2 / 4 * rpm_to_radps;

FOC.I_limit   = PMSM.T_peak / PMSM.Kt_peak;            % [A_peak]   derived
FOC.Ts        = 1e-4;                                  % [s]        E  control sample time

%% 8) Field-weakening parameters -------------------------------------------
% Engages when the modulation index exceeds k_trigger times the linear
% modulation limit. id is allowed to go negative down to id_min.
FW.k_trigger  = 0.95;                %                   E
FW.k_fw       = 2.0;                 %                   E  d-axis push gain
FW.id_min     = -200;                % [A_peak]          E

%% 9) Default sweep grid ---------------------------------------------------
% Used by test_fast.m. Override at the call site if a different grid is
% needed.
SIM.speed_rpm        = 1000:250:5000;        % [RPM]
SIM.torque_regen_Nm  = -200:10:-20;          % [N.m]
SIM.t_sim            = 3.0;                  % [s]    total sim time per point
SIM.t_settle         = 2.0;                  % [s]    averaging window starts here
SIM.dt               = 1e-5;                 % [s]    fixed solver step

%% 10) Default operating-point references for single-shot runs -------------
SpeedRef_rpm_cmd     = 3000;                                 % [RPM]
TorqueRef_gen_Nm_cmd = -100;                                 % [N.m]
omega_init_cmd       = SpeedRef_rpm_cmd * 2 * pi / 60;       % [rad/s]

%% 11) Thermal model -------------------------------------------------------
% Single-node lumped capacitance model for the stator winding. Allows
% temperature-dependent Rs.
THERM.T_amb     = 25;                % [degC]            P
THERM.T_init    = 30;                % [degC]            P
THERM.alpha_cu  = 0.00393;           % [1/degC]          T  copper temp coefficient
THERM.Rth_wind  = 0.08;              % [degC/W]          E
THERM.Cth_wind  = 1200;              % [J/degC]          E
THERM.Rs_ref    = PMSM.Rs;           % [ohm]             derived
THERM.T_ref     = 25;                % [degC]            P

%% 12) Sanity checks -------------------------------------------------------
mustBePositive = { ...
    PMSM.Rs, PMSM.Ld, PMSM.Lq, PMSM.lambda_m, ...
    BAT.V_nom, BAT.C_Ah, BAT.R_int, ...
    DCLINK.C_F, DCDC.P_max, MECH.J_total, FOC.Ts, INV.f_sw};

if any(~isfinite([mustBePositive{:}])) || any([mustBePositive{:}] <= 0)
    error('InitParams:NonPositive', ...
          'One or more required parameters are non-finite or non-positive.');
end

if DCDC.SOC_full <= DCDC.SOC_taper_start
    error('InitParams:BadSOCWindow', ...
          'DCDC.SOC_full must exceed DCDC.SOC_taper_start.');
end

%% 13) Analytical reference efficiency map ---------------------------------
% First-principles back-of-the-envelope efficiency surface used as a
% sanity baseline against the Simulink result. All loss terms apply to both
% machines in the back-to-back rig, hence the leading 2 on each component.
speed_v  = linspace(500, 5000, 50);          % [RPM]
torque_v = linspace(-220, -5, 40);           % [N.m]
[SPD_ref, TRQ_ref] = meshgrid(speed_v, torque_v);
EFF_ref = zeros(size(SPD_ref));              % [-]

for i = 1:numel(SPD_ref)
    n     = SPD_ref(i);                                          % [RPM]
    Tabs  = abs(TRQ_ref(i));                                     % [N.m]
    omega = n * 2*pi/60;                                         % [rad/s]
    if Tabs * omega < 10
        continue
    end

    iq_pk  = min(Tabs / PMSM.Kt_peak, PMSM.I_peak * sqrt(2));    % [A_peak]
    I_rms  = iq_pk / sqrt(2);                                    % [A_rms]
    P_mech = iq_pk * PMSM.Kt_peak * omega;                       % [W]

    P_cu   = 3 * I_rms^2 * PMSM.Rs;                              % [W] one machine
    f_e    = PMSM.p * n / 60;                                    % [Hz]
    P_fe   = PMSM.iron.k_h * f_e^PMSM.iron.alpha + ...
             PMSM.iron.k_e * (f_e * PMSM.iron.B_pk)^2;           % [W] one machine
    P_ml   = PMSM.mech.T_f0 * omega + PMSM.mech.k_w * omega^3;   % [W] one machine
    P_cond = (2*sqrt(2)/pi) * I_rms * (INV.V_CE_sat + INV.V_D_fwd);  % [W] one machine
    P_sw   = (INV.E_on_coeff + INV.E_off_coeff) * I_rms * BAT.V_nom * INV.f_sw;  % [W]
    P_inv  = P_cond + P_sw;                                      % [W] one machine

    % Both machines contribute losses in the back-to-back rig
    P_net = P_mech - 2*P_cu - 2*P_fe - 2*P_ml - 2*P_inv;         % [W]
    EFF_ref(i) = max(0, min(0.97, P_net / max(P_mech, eps)));
end

[eta_ref_peak, idx_ref_peak] = max(EFF_ref(:));
eta_ref_peak_pct = 100 * eta_ref_peak;       % [%]
n_ref_peak       = round(SPD_ref(idx_ref_peak));   % [RPM]
T_ref_peak       = TRQ_ref(idx_ref_peak);          % [N.m]

%% 14) Verbose summary -----------------------------------------------------
if INIT_VERBOSE
    fprintf('lambda_m           = %.5f Wb\n',                PMSM.lambda_m);
    fprintf('Kt_rms             = %.4f N.m/A_rms\n',         PMSM.Kt_rms);
    fprintf('Battery            = %.0f V, %.0f Ah, R_int = %.3f ohm\n', ...
            BAT.V_nom, BAT.C_Ah, BAT.R_int);
    fprintf('J_total            = %.5f kg.m^2\n',            MECH.J_total);
    fprintf('FOC current PI     = [Kp %.4f, Ki %.4f]\n',     FOC.Kp_iq, FOC.Ki_iq);
    fprintf('FOC speed PI       = [Kp %.4f, Ki %.4f]\n',     FOC.Kp_speed, FOC.Ki_speed);
    fprintf('Default operating point: %d RPM / %d N.m\n', ...
            SpeedRef_rpm_cmd, TorqueRef_gen_Nm_cmd);
    fprintf('Reference map peak = %.1f%% at %d RPM / %.0f N.m\n\n', ...
            eta_ref_peak_pct, n_ref_peak, T_ref_peak);
end

%% 15) Optional reference-map plots ----------------------------------------
if INIT_MAKE_PLOTS
    figure('Name','Reference Efficiency Map','Position',[50 50 900 380]);

    subplot(1,2,1);
    contourf(SPD_ref, TRQ_ref, EFF_ref*100, 25, 'LineStyle','none');
    colorbar; hold on;
    contour(SPD_ref, TRQ_ref, EFF_ref*100, [80 85 88 90 92], ...
            'k', 'LineWidth', 1.2, 'ShowText', 'on');
    xlabel('Speed (RPM)');
    ylabel('Regen torque (N.m)');
    title('Analytical recovery efficiency (%)');
    grid on;

    subplot(1,2,2);
    surf(SPD_ref, TRQ_ref, EFF_ref*100, 'EdgeColor', 'none');
    xlabel('Speed (RPM)');
    ylabel('Torque (N.m)');
    zlabel('\eta (%)');
    title('Efficiency surface');
    view(45, 30);
    grid on;
    sgtitle('Analytical reference, EMRAX 228 back-to-back rig');
end

fprintf('=== Init complete ===\n');