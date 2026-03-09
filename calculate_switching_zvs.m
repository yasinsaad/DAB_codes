function [P_sw_total, is_zvs, t_trans_needed, E_ratio] = calculate_switching_zvs(V_DC, I_sw, f_sw, L_comm, s, t_dead)
% CALCULATE_SWITCHING_ZVS
% Calculates switching loss for one device/leg commutation using:
%   1) a ZVS feasibility check
%   2) hard-switching turn-on loss if ZVS fails
%   3) turn-off overlap loss
%
% Inputs:
%   V_DC   : DC bus voltage seen by the bridge leg [V]
%   I_sw   : current magnitude at the switching instant [A]
%   f_sw   : switching frequency [Hz]
%   L_comm : effective commutation inductance [H]
%   s      : semiconductor parameter struct
%   t_dead : actual inserted dead time [s]
%
% Outputs:
%   P_sw_total     : total switching-related loss [W]
%   is_zvs         : true if ZVS is achieved
%   t_trans_needed : time needed to complete node-voltage commutation [s]
%   E_ratio        : available inductive energy / required capacitive energy

    %% 1. ZVS FEASIBILITY CHECKS
    % Before calculating switching loss, first check whether the bridge leg
    % can achieve ZVS.
    %
    % In a DAB leg, after one switch turns off, the inductor current must:
    %   - discharge one device capacitance
    %   - charge the opposite device capacitance
    % before the complementary gate signal arrives.
    %
    % So ZVS needs:
    %   (a) enough energy
    %   (b) enough time within dead time

    % --- A. ENERGY CHECK ---
    % Required capacitive energy for one half-bridge node transition.
    %
    % For a half-bridge leg, two device output capacitances participate,
    % and the energy needed is approximated here as:
    %
    %   E_req_total ≈ Coss * V_DC^2
    %
    % This is a simplified leg-scope approximation.
    E_req_total = s.Coss * (V_DC^2);

    % Available inductive energy stored in the commutation/leakage inductance
    % at the switching instant:
    %
    %   E_avail = 1/2 * L_comm * I_sw^2
    E_avail = 0.5 * L_comm * (I_sw^2);

    % Ratio used as a convenient ZVS margin metric.
    % If E_ratio > 1, there is enough inductive energy in principle.
    E_ratio = E_avail / E_req_total;

    % --- B. TIMING CHECK ---
    % Equivalent switch-node capacitance during dead time.
    % In a half-bridge, both top and bottom device Coss appear in the
    % commutation process, so:
    %
    %   C_node_eq ≈ 2 * Coss
    C_node_eq = 2 * s.Coss;

    % Required transition time assuming the commutation current is roughly
    % constant while slewing the switch node:
    %
    %   t_trans_needed = C * V / I
    %
    % If current is too small, set transition time to a huge number.
    if I_sw > 0.1
        t_trans_needed = (C_node_eq * V_DC) / I_sw;
    else
        t_trans_needed = 1e9; % effectively impossible transition
    end

    %% 2. COMBINED ZVS DECISION
    % ZVS is achieved only if BOTH conditions hold:
    %   1) enough energy
    %   2) transition completes inside the available dead time
    if (E_avail > E_req_total) && (t_trans_needed < t_dead)

        % --- CASE A: ZVS SUCCESS ---
        is_zvs = true;

        % In ideal ZVS, the node voltage is already slewed before turn-on,
        % so there is no V*I overlap during turn-on.
        P_on = 0;

        % Also assume reverse-recovery loss is negligible because the body
        % diode / reverse-conduction path is already conducting naturally.
        P_rr = 0;

    else

        % --- CASE B: HARD TURN-ON ---
        is_zvs = false;

        % Turn-on current-rise interval estimate from gate-drive RC charging.
        %
        % Gate must rise from threshold toward Miller plateau:
        term_start = abs(s.V_dr_on - s.V_gs_th);
        term_end   = abs(s.V_dr_on - s.V_plateau);

        % Approximate current-rise time:
        %
        %   t_RI = Rg * Ciss * ln(Vstart / Vend)
        %
        % This is a rough gate-charge/RC-based estimate.
        t_RI = s.Rg * s.Ciss * log(term_start / max(term_end, 1e-3));

        % Current slope during turn-on:
        %
        %   a_iD = di/dt ≈ I_sw / t_RI
        %
        % Floor value added to avoid division instability.
        a_iD = max(I_sw / t_RI, 1e6);

        % --- DIODE REVERSE RECOVERY MODEL ---
        % If the opposite body diode had been conducting, hard turn-on must
        % commutate that diode off, causing reverse recovery.
        d = s.diode;

        % Scale reverse-recovery time from datasheet reference values.
        % This is an empirical approximation.
        scale_trr = -0.15 * (a_iD / d.didt_ref) + ...
                     0.20 * (I_sw / d.Io_ref) + 0.9;
        t_RR = d.trr_ref * scale_trr;

        % Scale peak reverse-recovery current from datasheet reference values.
        % Also empirical.
        scale_Irm = 0.2 * d.Irm_ref * ...
                    (I_sw / d.Io_ref + 1.25) * ...
                    (a_iD / d.didt_ref + 1);
        I_RM = scale_Irm;

        % --- EFFECTIVE TURN-ON TRANSITION SHAPING ---
        % Recovery current extends the current-rise interval.
        t_RI_prime = t_RI + (abs(I_RM) / a_iD);

        % Voltage-fall interval after recovery starts.
        t_FV = max(t_RR - (abs(I_RM) / a_iD), 0);

        % --- HARD TURN-ON ENERGY ---
        % Linearized overlap-energy approximation.
        %
        % First term: current rise including recovery-current contribution
        % Second term: voltage fall interval
        E_on = V_DC * ( (t_RI_prime/2) * (I_sw + abs(I_RM)) + ...
                        t_FV * (I_sw/2 + abs(I_RM)/3) );
        P_on = E_on * f_sw;

        % Reverse-recovery energy term
        E_rr = (V_DC * abs(I_RM) * t_FV) / 6;
        P_rr = E_rr * f_sw;
    end

    %% 3. TURN-OFF LOSS
    % In SPS DAB, turn-off is usually treated as hard switching because the
    % device is turning off while carrying current and the voltage rises.
    %
    % Turn-off loss is modeled by:
    %   - voltage rise interval (Miller region)
    %   - current fall interval

    % Voltage-rise time while charging the Miller capacitance Crss:
    denom_rv = abs(s.V_plateau - s.V_dr_off);
    t_RV = (s.Rg * s.Crss * V_DC) / max(denom_rv, 1e-3);

    % Current-fall time while the gate discharges from plateau to threshold:
    term_start = abs(s.V_dr_off - s.V_plateau);
    term_end   = abs(s.V_dr_off - s.V_gs_th);
    t_FI = s.Rg * s.Ciss * log(max(term_start, 1e-3) / max(term_end, 1e-3));

    % Turn-off overlap energy:
    %
    %   E_off = (V * I / 2) * (t_RV + t_FI)
    E_off = (V_DC * I_sw / 2) * (t_RV + t_FI);
    P_off = E_off * f_sw;

    %% 4. TOTAL SWITCHING LOSS
    % Total = turn-on + reverse-recovery + turn-off
    P_sw_total = P_on + P_rr + P_off;
end