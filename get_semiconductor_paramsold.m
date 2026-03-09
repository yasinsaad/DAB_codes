function [hv_params, lv_params] = get_semiconductor_params(type_hv, type_lv)
% GET_SEMICONDUCTOR_PARAMS Returns parameter structs for DAB semiconductors.
%
% Usage:
%   [semi.hv, semi.lv] = get_semiconductor_params('SiC_1200V', 'Si_100V');
%


    % Load HV Side
    hv_params = load_device_profile(type_hv);
    
    % Load LV Side
    lv_params = load_device_profile(type_lv);

end

function p = load_device_profile(type)
    switch type
        case {'SiC', 'SiC_1200V'}
            p.Ron       = 38e-3;          % Table 4, typical 30–38 mΩ
            p.Rd        = 2e-3;           % External gate resistor (2 Ω recommended)
            p.Vf        = 3.95;           % Table 6, forward voltage at 27 A, 25°C
            p.Qg        = 57e-9;          % Table 4, total gate charge
            p.Rg        = 2.6;            % Table 4, internal gate resistance
            p.Ciss      = 1738e-12;       % Table 4
            p.Crss      = 4.4e-12;        % Table 4
            p.Coss      = 82e-12;         % Table 4

% Drive logic
            p.V_dr_on   = 20;             % Table 3, recommended turn-on voltage
            p.V_dr_off  = -4;             % Typical negative turn-off voltage for SiC
            p.V_gs_th   = 4.4;            % Table 4, typical threshold voltage
            p.V_plateau = 6.0;            % Estimated Miller plateau voltage

% Body diode reverse recovery
            p.diode.trr_ref  = 35e-9;     % Typical reverse recovery time for SiC MOSFET
            p.diode.Irm_ref  = 13.5;      % Table 6, forward recovery peak current
            p.diode.Io_ref   = 27;        % Table 6 test current
            p.diode.didt_ref = 2000e6;    % Table 6, di/dt test condition (2000 A/μs)
        
        case {'Si', 'Si_LV', 'Si_60V'}
          % Vishay SQJQ160E 60 V N-Channel MOSFET Parameters
p.Ron       = 0.85e-3;        % Page 2, max RDS(on) at 20 A, 10 V, 25°C
p.Rd        = 1.0;            % Page 2, external gate resistor used in switching test
p.Vf        = 1.1;            % Page 2, max body diode forward voltage
p.Qg        = 275e-9;         % Page 2, max total gate charge at 30 V, 50 A
p.Rg        = 2.1;            % Page 2, max internal gate resistance
p.Ciss      = 16070e-12;      % Page 2, max input capacitance
p.Crss      = 458e-12;        % Page 2, max reverse transfer capacitance
p.Coss      = 6681e-12;       % Page 2, max output capacitance

% Drive logic
p.V_dr_on   = 10;             % Page 2, recommended turn-on voltage for RDS(on) spec
p.V_dr_off  = -5;             % Suggested negative turn-off for better noise immunity
p.V_gs_th   = 3.5;            % Page 2, max threshold voltage
p.V_plateau = 4.5;            % Estimated Miller plateau voltage (typical for trench MOSFET)

% Body diode reverse recovery
p.diode.trr_ref  = 176e-9;    % Page 2, max reverse recovery time
p.diode.Irm_ref  = 2.7;       % Page 2, typical peak reverse recovery current
p.diode.Io_ref   = 15;        % Page 2, test current for trr
p.diode.didt_ref = 100e6;     % Page 2, di/dt test condition (100 A/μs)

        case {'GaN', 'GaN_100V'}
           % EPC2218 100 V eGaN FET Parameters
p.Ron       = 3.2e-3;         % Page 1, max RDS(on) at 25 A, 5 V, 25°C
p.Rd        = 2.0;            % Suggested external gate resistor (adjust for ringing)
p.Vf        = 1.5;            % Page 1, typical body diode forward voltage at 0.5 A
p.Qg        = 13.6e-9;        % Page 2, max total gate charge at 50 V, 5 V, 25 A
p.Rg        = 0.4;            % Page 2, typical internal gate resistance
p.Ciss      = 1570e-12;       % Page 2, max input capacitance
p.Crss      = 4.3e-12;        % Page 2, typical reverse transfer capacitance
p.Coss      = 843e-12;        % Page 2, max output capacitance

% Drive logic
p.V_dr_on   = 5;              % Page 1, recommended turn-on voltage for RDS(on)
p.V_dr_off  = -2;             % Suggested negative turn-off for eGaN (improves noise immunity)
p.V_gs_th   = 2.5;            % Page 1, max gate threshold voltage
p.V_plateau = 2.0;            % Estimated Miller plateau voltage

% Body diode (zero reverse recovery)
p.diode.trr_ref  = 0;         % Page 2, Qrr = 0 (no reverse recovery)
p.diode.Irm_ref  = 0;         % No reverse recovery peak
p.diode.Io_ref   = 0.5;       % Page 1, test current for Vf
p.diode.didt_ref = 0;         % Not applicable

        case {'IGBT', 'IGBT_1200V'}
            
           % STGW15S120DF3 1200 V IGBT Parameters
p.Vce_sat   = 2.05;           % Table 4, max VCE(sat) at 15 A, 15 V, 25°C
p.Vge_th    = 7.0;            % Table 4, max gate threshold voltage
p.Qg        = 53e-9;          % Table 5, typical total gate charge
p.Qgc       = 28.2e-9;        % Table 5, typical gate-collector charge
p.Qge       = 7.8e-9;         % Table 5, typical gate-emitter charge
p.Cies      = 98e-12;         % Table 5, typical input capacitance
p.Cres      = 37e-12;         % Table 5, typical reverse transfer capacitance
p.Coes      = 82e-12;         % Table 5, typical output capacitance

% IGBT gate drive
p.V_dr_on   = 15;             % Table 4, recommended turn-on voltage
p.V_dr_off  = -5;             % Suggested negative turn-off for noise immunity
p.Rg        = 3.0;            % Estimated internal gate resistance
p.Rd        = 10;             % Typical external gate resistor for IGBT

% Body diode (antiparallel diode)
p.Vf        = 3.8;            % Table 4, max forward voltage at 15 A, 25°C
p.diode.trr_ref  = 200e-9;    % Estimated reverse recovery time (soft recovery)
p.diode.Irm_ref  = 15;        % Estimated peak reverse recovery current
p.diode.Io_ref   = 15;        % Table 4 test current
p.diode.didt_ref = 200e6;     % Estimated di/dt (200 A/μs)

% Switching times (estimated from curves)
p.t_don     = 100e-9;         % Estimated turn-on delay
p.t_rise    = 150e-9;         % Estimated rise time
p.t_doff    = 500e-9;         % Estimated turn-off delay
p.t_fall    = 300e-9;         % Estimated fall time

        otherwise
            error('Unknown Semiconductor Type: %s', type);
    end
end