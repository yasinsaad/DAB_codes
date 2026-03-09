function S = calculate_dab_size_fixed(mode, f, Vin, Vout, P, n, d, varargin)
% CALCULATE_DAB_SIZE_FIXED
% Fixed-hardware DAB magnetic sizing function.
%
% This version estimates:
%   1) transformer size from
%        - flux-density constraint
%        - window-area / current-density constraint
%   2) separate inductor size from
%        - stored energy
%        - practical packing factor
%
% Inputs:
%   mode : 'design' or 'eval'
%   f    : switching frequency [Hz]
%   Vin  : primary-side DC voltage [V]
%   Vout : secondary-side DC voltage [V]
%   P    : power at operating/design point [W]
%   n    : transformer turns ratio Ns/Np
%   d    : normalized SPS phase shift, 0 < d < 0.5
%
% DESIGN call:
%   Sfix = calculate_dab_size_fixed('design', f_design, Vin, Vout, P_design, ...
%                                   n, d_design, opts)
%
% EVAL call:
%   Seval = calculate_dab_size_fixed('eval', f_curr, Vin, Vout, P_curr, ...
%                                    n, d_eval, Sfix)

    % Permeability of free space [H/m]
    mu0 = 4*pi*1e-7;

    % Select operating mode
    switch lower(mode)

        case 'design'
            % In design mode, the final argument must be an opts struct
            if isempty(varargin)
                error('Design mode requires opts struct.');
            end
            opts = varargin{1};

            %% -------- DEFAULTS --------
            % Number of primary turns
            if ~isfield(opts,'Np'),          opts.Np = 16;         end

            % Transformer maximum flux density target [T]
            if ~isfield(opts,'Bmax_T'),      opts.Bmax_T = 0.25;   end

            % Inductor maximum flux density target [T]
            if ~isfield(opts,'Bmax_L'),      opts.Bmax_L = 0.30;   end

            % Margin applied to ideal SPS inductance
            if ~isfield(opts,'L_margin'),    opts.L_margin = 1.0;  end

            % Window utilization factor Ku (how much winding window is actually used)
            if ~isfield(opts,'Ku'),          opts.Ku = 0.30;       end

            % Allowable current density J [A/m^2]
            % 4e6 A/m^2 = 4 A/mm^2
            if ~isfield(opts,'J'),           opts.J = 4e6;         end

            % Empirical transformer volume scaling constant
            if ~isfield(opts,'k_tr'),        opts.k_tr = 5.0;      end
            % The model later uses:
            %   V_T_cm3 = k_tr * (Ap_cm4)^0.75

            % Practical inductor packing factor
            % This inflates the ideal minimum magnetic-gap volume into
            % something closer to a real component.
            if ~isfield(opts,'k_pack_L'),    opts.k_pack_L = 8.0;  end

            % Check normalized phase shift validity
            if d <= 0 || d >= 0.5
                error('Design d must satisfy 0 < d < 0.5');
            end

            % Extract design choices
            Np     = opts.Np;
            Ns     = max(round(n * Np), 1);   % secondary turns from ratio
            Bmax_T = opts.Bmax_T;
            Bmax_L = opts.Bmax_L;

            %% -------- 1) FIXED SPS TRANSFER INDUCTANCE --------
            % Standard SPS DAB power relation:
            %
            %   P = Vin*Vout/(2*n*f*L) * d*(1-d)
            %
            % Rearranged for L:
            L_req = (Vin * Vout * d * (1 - d)) / (2 * n * f * P);

            % Add optional design margin
            L_req = opts.L_margin * L_req;

            %% -------- 2) INTERNAL SPS CURRENT ESTIMATE --------
            % Calculate DAB inductor/bridge current waveform quantities
            % from SPS physics:
            %   - Ipk   : peak current
            %   - Imin  : minimum current
            %   - Irms  : RMS primary current
            %   - Iabs  : average absolute current
            [Ipk, Imin, Irms_pri, Iabs_pri, dbg] = local_sps_currents(Vin, Vout, n, L_req, f, d);

            % Convert primary current quantities to secondary side
            % using ideal transformer scaling
            Irms_sec = Irms_pri / n;
            Ipk_sec  = Ipk / n;

            %% -------- 3) TRANSFORMER CORE AREA FROM FLUX --------
            % Square-wave transformer flux relation:
            %
            %   Bpk = Vin / (4*Np*Ac*f)
            %
            % Solving for required core cross-sectional area:
            Ac_T = Vin / (4 * Np * Bmax_T * f);   % [m^2]

            %% -------- 4) TRANSFORMER WINDOW AREA FROM CURRENT DENSITY --------
            % Estimate required winding window area from current density:
            %
            %   Aw >= (Np*Ipri_rms + Ns*Isec_rms)/(Ku*J)
            %
            % This is a practical winding-space constraint.
            Aw_T = (Np * Irms_pri + Ns * Irms_sec) / max(opts.Ku * opts.J, 1e-12);   % [m^2]

            %% -------- 5) TRANSFORMER AREA PRODUCT AND VOLUME --------
            % Area product:
            %
            %   Ap = Ac * Aw
            %
            % Common magnetics design metric for transformer sizing.
            Ap_T = Ac_T * Aw_T;        % [m^4]

            % Convert to cm^4 for empirical geometric scaling
            Ap_cm4 = Ap_T * 1e8;       % [cm^4]

            % Estimate transformer volume from area product.
            % This is not an exact catalog equation, but a practical
            % geometric scaling law.
            V_T_cm3 = opts.k_tr * (Ap_cm4^0.75);

            %% -------- 6) SEPARATE INDUCTOR VOLUME FROM ENERGY --------
            % Stored energy in the transfer inductor:
            %
            %   E = 1/2 * L * Ipk^2
            E_L = 0.5 * L_req * Ipk^2;   % [J]

            % Theoretical minimum magnetic gap volume for an energy-storage inductor:
            %
            %   V_gap,min = mu0 * L * Ipk^2 / Bmax^2
            %
            % This is the minimum ideal gap-energy volume.
            V_gap_min_m3 = mu0 * L_req * Ipk^2 / max(Bmax_L^2, 1e-12);

            % Inflate to a more realistic practical inductor volume using
            % the packing factor.
            V_L_cm3 = opts.k_pack_L * V_gap_min_m3 * 1e6;

            %% -------- 7) TOTAL MAGNETIC VOLUME --------
            % Total magnetics = transformer + separate inductor
            V_total_cm3 = V_T_cm3 + V_L_cm3;

            %% -------- OUTPUT STRUCT --------
            S = struct();
            S.mode = 'design';

            % Design-point operating conditions
            S.f_design = f;
            S.P_design = P;
            S.Vin = Vin;
            S.Vout = Vout;
            S.n = n;
            S.d_design = d;

            % Turns and magnetic limits
            S.Np = Np;
            S.Ns = Ns;
            S.Bmax_T = Bmax_T;
            S.Bmax_L = Bmax_L;

            % Sizing assumptions
            S.Ku = opts.Ku;
            S.J = opts.J;
            S.k_tr = opts.k_tr;
            S.k_pack_L = opts.k_pack_L;
            S.L_margin = opts.L_margin;

            % Fixed transfer inductance chosen for this hardware
            S.L_fixed = L_req;

            % Current quantities at design point
            S.Ipk_design = Ipk;
            S.Imin_design = Imin;
            S.Irms_pri_design = Irms_pri;
            S.Irms_sec_design = Irms_sec;
            S.Ipk_sec_design = Ipk_sec;
            S.Iabs_pri_design = Iabs_pri;

            % Transformer geometric quantities
            S.Ac_T_fixed = Ac_T;
            S.Aw_T_fixed = Aw_T;
            S.Ap_T_fixed = Ap_T;

            % Transformer flux and inductor energy at design point
            S.Bpk_T_design = Vin / (4 * Np * Ac_T * f);
            S.E_L_design = E_L;

            % Volumes
            S.Vgap_min_L_cm3 = V_gap_min_m3 * 1e6;
            S.V_T_cm3 = V_T_cm3;
            S.V_L_cm3 = V_L_cm3;
            S.V_total_cm3 = V_total_cm3;

            % Debug/current waveform info
            S.current_debug = dbg;

        case 'eval'
            % In eval mode, final argument must be fixed design struct
            if isempty(varargin)
                error('Eval mode requires Sfix struct.');
            end
            Sfix = varargin{1};

            % Check normalized phase shift validity
            if d <= 0 || d >= 0.5
                error('Eval d must satisfy 0 < d < 0.5');
            end

            %% -------- RE-EVALUATE FIXED HARDWARE AT NEW POINT --------
            % Recalculate current waveform using same fixed inductance
            [Ipk, Imin, Irms_pri, Iabs_pri, dbg] = local_sps_currents(Vin, Vout, n, Sfix.L_fixed, f, d);

            % Convert to secondary side
            Irms_sec = Irms_pri / n;
            Ipk_sec  = Ipk / n;

            % Transformer flux at this new operating frequency
            Bpk_T = Vin / (4 * Sfix.Np * Sfix.Ac_T_fixed * f);

            % Flag transformer saturation / over-flux condition
            is_sat_T = (Bpk_T > Sfix.Bmax_T);

            % Inductor stored energy at this operating point
            E_L = 0.5 * Sfix.L_fixed * Ipk^2;

            % Recompute minimum required inductor gap volume at this operating point
            V_gap_min_m3 = 4*pi*1e-7 * Sfix.L_fixed * Ipk^2 / max(Sfix.Bmax_L^2, 1e-12);

            % Practical required inductor volume at this point
            V_L_req_cm3 = Sfix.k_pack_L * V_gap_min_m3 * 1e6;

            % Flag if the previously chosen inductor volume is no longer sufficient
            is_sat_L = V_L_req_cm3 > Sfix.V_L_cm3;

            % SPS power capability with same fixed L at this frequency and phase shift
            P_sps_cap = (Vin * Vout * d * (1 - d)) / (2 * n * f * Sfix.L_fixed);

            %% -------- OUTPUT STRUCT --------
            S = struct();
            S.mode = 'eval';

            S.f_eval = f;
            S.P_eval = P;
            S.Vin = Vin;
            S.Vout = Vout;
            S.n = n;
            S.d_eval = d;

            % Fixed hardware carried over from design
            S.L_fixed = Sfix.L_fixed;
            S.Np = Sfix.Np;
            S.Ns = Sfix.Ns;

            % Current quantities at this operating point
            S.Ipk = Ipk;
            S.Imin = Imin;
            S.Irms_pri = Irms_pri;
            S.Irms_sec = Irms_sec;
            S.Ipk_sec = Ipk_sec;
            S.Iabs_pri = Iabs_pri;

            % Flux / energy checks
            S.Bpk_T = Bpk_T;
            S.is_sat_T = is_sat_T;
            S.E_L = E_L;
            S.is_sat_L = is_sat_L;

            % Fixed transformer geometry
            S.Ac_T_fixed = Sfix.Ac_T_fixed;
            S.Aw_T_fixed = Sfix.Aw_T_fixed;
            S.Ap_T_fixed = Sfix.Ap_T_fixed;

            % Fixed design volumes
            S.V_T_cm3 = Sfix.V_T_cm3;
            S.V_L_cm3 = Sfix.V_L_cm3;
            S.V_total_cm3 = Sfix.V_total_cm3;

            % Required inductor volume at current operating point
            S.V_L_req_cm3 = V_L_req_cm3;

            % Power capability indicator
            S.P_sps_cap = P_sps_cap;
            S.power_ratio = P / max(P_sps_cap, 1e-12);

            % Debug/current waveform info
            S.current_debug = dbg;

        otherwise
            error('Mode must be ''design'' or ''eval''.');
    end
end


function [Ipk, Imin, Irms, Iabs, dbg] = local_sps_currents(Vin, Vout, n, L, f, d)
% LOCAL_SPS_CURRENTS
% Calculates SPS DAB current waveform quantities, primary-referred.
%
% Outputs:
%   Ipk  : peak current magnitude [A]
%   Imin : minimum current [A]
%   Irms : RMS current over full switching period [A]
%   Iabs : average absolute current over full switching period [A]

    % Check valid SPS phase-shift range
    if d <= 0 || d >= 0.5
        error('local_sps_currents: d must satisfy 0 < d < 0.5');
    end

    % Switching period
    T = 1 / f;

    % Duration of the two positive-half-cycle intervals
    dt1 = d * T / 2;
    dt2 = (1 - d) * T / 2;

    % Secondary bridge voltage referred to primary side
    V2p = Vout / n;

    % Inductor voltage during the first and second intervals
    vL1 = Vin + V2p;
    vL2 = Vin - V2p;

    % Corresponding current slopes
    m1 = vL1 / L;
    m2 = vL2 / L;

    % Current increments during each interval
    dI1 = m1 * dt1;
    dI2 = m2 * dt2;

    % Total current rise over one half-cycle
    dI_half = dI1 + dI2;

    % Symmetric steady-state waveform assumption
    Imin = -dI_half / 2;

    % Current values at interval boundaries
    i0   = Imin;
    i1   = i0 + dI1;
    i2   = i1 + dI2;

    % Peak current magnitude
    Ipk = max(abs([i0, i1, i2]));

    % Exact RMS calculation from the two linear current segments
    int1 = dt1/3 * (i0^2 + i0*i1 + i1^2);
    int2 = dt2/3 * (i1^2 + i1*i2 + i2^2);
    Irms = sqrt( 2*(int1 + int2) / T );

    % Average absolute current over one full switching period
    Iabs = (2/T) * ( local_abs_linear_area(i0, i1, dt1) + ...
                     local_abs_linear_area(i1, i2, dt2) );

    % Debug information
    dbg = struct('V2p',V2p,'vL1',vL1,'vL2',vL2,'m1',m1,'m2',m2, ...
                 'dt1',dt1,'dt2',dt2,'dI1',dI1,'dI2',dI2,'i0',i0,'i1',i1,'i2',i2);
end


function A = local_abs_linear_area(i0, i1, dt)
% LOCAL_ABS_LINEAR_AREA
% Computes area under |i(t)| for a linear current segment from i0 to i1
% over interval dt.

    if dt <= 0
        A = 0;
        return;
    end

    % If the segment does not cross zero, use trapezoid area directly
    if sign(i0) == sign(i1) || i0 == 0 || i1 == 0
        A = dt * (abs(i0) + abs(i1)) / 2;
    else
        % If the segment crosses zero, split into two triangles
        tz = dt * abs(i0) / max(abs(i1 - i0), 1e-12);
        A1 = tz * abs(i0) / 2;
        A2 = (dt - tz) * abs(i1) / 2;
        A = A1 + A2;
    end
end