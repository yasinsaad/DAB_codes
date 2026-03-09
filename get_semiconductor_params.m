function [hv_params, lv_params] = get_semiconductor_params(type_hv, type_lv)
% GET_SEMICONDUCTOR_PARAMS
% Returns parameter structs for DAB semiconductors.
%
% Usage:
%   [semi.hv, semi.lv] = get_semiconductor_params('SiC_1200V', 'Si_60V');

    hv_params = load_device_profile(type_hv);
    lv_params = load_device_profile(type_lv);
end

function p = load_device_profile(type)

    switch type

        case {'SiC', 'SiC_1200V'}
            % Infineon AIMBG120R030M1 CoolSiC 1200 V MOSFET

            % Conduction
            p.Ron = 38e-3;          % ohm, Table 4 max/typ range around 30-38 mOhm
            p.Vf  = 3.95;           % V, Table 6 typ at 27 A, 25 C

            % Gate network
            p.Rd = 2.0;             % ohm, chosen external gate resistor
            p.Rg = 2.6;             % ohm, Table 4 internal gate resistance

            % Charges
            p.Qg  = 57e-9;          % C, Table 4 total gate charge
            p.Qgs = 15e-9;          % C, plateau gate charge
            p.Qgd = 10e-9;          % C, gate-drain charge

            % Capacitances
            p.Ciss = 1738e-12;      % F
            p.Crss = 4.4e-12;       % F
            p.Coss = 82e-12;        % F
            p.Eoss = 34e-6;         % J at 800 V, if you want to use Eoss-based ZVS later

            % Drive logic
            p.V_dr_on   = 20;       % V
            p.V_dr_off  = -4;       % V, design choice
            p.V_gs_th   = 4.4;      % V, typical threshold
            p.V_plateau = 6.0;      % V, engineering estimate

            % Body diode / reverse conduction
            p.diode.trr_ref  = 35e-9;      % s, rough placeholder for fast SiC behavior
            p.diode.Irm_ref  = 13.5;       % A, Table 6 forward recovery peak current
            p.diode.Io_ref   = 27;         % A, Table 6 test current
            p.diode.didt_ref = 2000e6;     % A/s = 2000 A/us

            % Flags
            p.isMOSFET = true;
            p.isGaN    = false;

        case {'Si', 'Si_LV', 'Si_60V'}
            % Vishay SQJQ160E 60 V N-channel MOSFET

            % Conduction
            p.Ron = 0.85e-3;        % ohm, max RDS(on) at 10 V
            p.Vf  = 1.1;            % V, max body diode forward voltage

            % Gate network
            p.Rd = 1.0;             % ohm, external gate resistor used in test
            p.Rg = 2.1;             % ohm, max internal gate resistance

            % Charges
            p.Qg  = 275e-9;         % C, max total gate charge
            p.Qgs = 53e-9;          % C, typical gate-source charge
            p.Qgd = 42e-9;          % C, typical gate-drain charge

            % Capacitances
            p.Ciss = 16070e-12;     % F, max
            p.Crss = 458e-12;       % F, max
            p.Coss = 6681e-12;      % F, max

            % Drive logic
            p.V_dr_on   = 10;       % V
            p.V_dr_off  = -5;       % V, design choice
            p.V_gs_th   = 3.5;      % V, max threshold
            p.V_plateau = 4.5;      % V, engineering estimate

            % Body diode
            p.diode.trr_ref  = 176e-9;     % s, max reverse recovery time
            p.diode.Irm_ref  = 2.7;        % A, typical
            p.diode.Io_ref   = 15;         % A, test current
            p.diode.didt_ref = 100e6;      % A/s = 100 A/us

            % Flags
            p.isMOSFET = true;
            p.isGaN    = false;

        case {'GaN', 'GaN_100V'}
            % 100 V eGaN FET
            % Update these values if you are specifically using EPC2218 or EPC2367.

            % Conduction
            p.Ron = 1.2e-3;         % ohm
            p.Vf  = 1.4;            % V, reverse conduction drop estimate

            % Gate network
            p.Rd = 2.0;             % ohm, chosen external gate resistor
            p.Rg = 0.6;             % ohm, internal gate resistance

            % Charges
            p.Qg  = 17e-9;          % C
            p.Qgs = 5.3e-9;         % C
            p.Qgd = 2.4e-9;         % C
            p.Qoss = 54e-9;         % C
            p.Qrr  = 0;             % C

            % Capacitances
            p.Ciss = 2170e-12;      % F
            p.Crss = 8e-12;         % F
            p.Coss = 590e-12;       % F

            % Drive logic
            p.V_dr_on   = 5;        % V
            p.V_dr_off  = 0;        % V
            p.V_gs_th   = 1.5;      % V, rough estimate if needed by your models
            p.V_plateau = 2.5;      % V, rough estimate

            % Reverse conduction placeholder
            p.diode.trr_ref  = 0;
            p.diode.Irm_ref  = 0;
            p.diode.Io_ref   = 1;
            p.diode.didt_ref = 1;

            % Limits
            p.Vds_max = 100;        % V
            p.Id_max  = 101;        % A

            % Flags       
p.isMOSFET = true;
p.isGaN    = true;

        otherwise
            error('Unknown Semiconductor Type: %s', type);
    end
end