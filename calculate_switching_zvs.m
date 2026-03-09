function [P_sw_total, is_zvs, t_trans_needed, E_ratio] = calculate_switching_zvs(V_DC, I_sw, f_sw, L_comm, s, t_dead)
% CALCULATE_SWITCHING_ZVS Calculates switching losses with physics-based ZVS validation.
%
%   Implements the analytical loss model from "Analytical Estimation of Power Losses..."
%   (Energies 2022, 15, 8262), extended with a Dead Time constraint check.
%
%   Inputs:
%       V_DC   : DC Link Voltage (V) across the bridge leg.
%       I_sw   : Instantaneous current (A) at the commutation moment.
%       f_sw   : Switching Frequency (Hz).
%       L_comm : Commutation Inductance (H) (e.g., Lk for primary).
%       s      : Semiconductor struct (contains C_oss, R_g, diode params, etc.).
%       t_dead : Dead time (s) allocated for the transition.
%
%   Outputs:
%       P_sw_total     : Total switching loss (Turn-ON + Turn-OFF + Recovery) [W].
%       is_zvs         : Boolean, true if Soft Switching achieved.
%       t_trans_needed : Time required to slew voltage from 0 to V_DC [s].
%       E_ratio        : Ratio of Available Inductive Energy to Required Capacitive Energy.

    %% 1. ZVS Feasibility Checks
    %  To achieve ZVS, the inductor current must discharge the parasitic capacitors
    %  of the bridge leg BEFORE the dead time expires.

    %  --- A. Energy Check (Full Bridge Scope) ---
    %  Total energy required to charge/discharge all 4 switches (2 legs) in an SPS transition.
    %  E_req = 4 * (0.5 * C_oss * V^2) = 2 * C_oss * V^2
 
    E_req_total = s.Coss * (V_DC^2); % LEG-scope energy requirement

    %  Energy available in the leakage/commutation inductance at the switching instant.
    E_avail = 0.5 * L_comm * (I_sw^2);
    
    %  Metric for plotting: Values > 1 indicate sufficient energy is present.
    E_ratio = E_avail / E_req_total; 
    
    %  --- B. Timing Check (Leg Transition Scope) ---
    %  The voltage transition is driven by I_sw charging the equivalent node capacitance.
    %  In a half-bridge, C_top and C_bot appear in parallel during the dead time.
    C_node_eq = 2 * s.Coss;
    
    %  Calculate transition time assuming constant current source behavior: dt = (C * dV) / I
    if I_sw > 0.1 
        t_trans_needed = (C_node_eq * V_DC) / I_sw;
    else
        t_trans_needed = 1e9; % Effectively infinite time if current is near zero
    end
    
    %% 3. Combined ZVS Condition
    %  ZVS is ONLY achieved if:
    %  1. We have enough energy (E_avail > E_req) AND
    %  2. The transition completes within the dead time window (t_trans < t_dead).
    if (E_avail > E_req_total) && (t_trans_needed < t_dead)
        % --- Case A: Soft Switching (ZVS) ---
        is_zvs = true;
        
        %  In ZVS, the body diode clamps V_ds to ~0V before the gate turns on.
        %  Therefore, Turn-ON overlap loss is eliminated.
        P_on = 0; 
        
        %  Since the diode is already conducting forward current, there is no
        %  reverse voltage snap-off event. Recovery loss is negligible.
        P_rr = 0; 
    else
        % --- Case B: Hard Switching ---
        is_zvs = false;
        
        %  --- Turn-ON Loss (Hard) ---
        %  Gate Driver charging Input Capacitance (C_iss)
        term_start = abs(s.V_dr_on - s.V_gs_th);      % Voltage to cross Threshold
        term_end   = abs(s.V_dr_on - s.V_plateau);    % Voltage to reach Plateau
        
        %  [Eq. 25] Current Rise Time (t_RI): t = Rg * Ciss * ln(V_start/V_end)
        %  'max' prevents log(0) or division by zero errors for ideal parameters.
        t_RI = s.Rg * s.Ciss * log(term_start / max(term_end, 1e-3));
        
        %  [Eq. 16] Current Slope (di/dt) during turn-on
        a_iD = max(I_sw / t_RI, 1e6); 
        
        %  --- Diode Reverse Recovery ---
        %  The complementary body diode must be forced off, causing a recovery current spike.
        d = s.diode;
        
        %  [Eq. 26] Scale t_rr based on current (I_sw) and slope (di/dt) vs datasheets
        scale_trr = -0.15 * (a_iD / d.didt_ref) + 0.20 * (I_sw / d.Io_ref) + 0.9;
        t_RR = d.trr_ref * scale_trr;
        
        %  [Eq. 27] Scale Peak Reverse Current (I_rm)
        scale_Irm = 0.2 * d.Irm_ref * (I_sw / d.Io_ref + 1.25) * (a_iD / d.didt_ref + 1);
        I_RM = scale_Irm;
        
        %  --- Effective Transition Times ---
        %  [Eq. 28] Rise Time with Recovery: Extends t_RI to account for I_RM spike.
        t_RI_prime = t_RI + (abs(I_RM) / a_iD);
        
        %  [Eq. 29] Voltage Fall Time (t_FV): Occurs after diode recovers.
        t_FV = max(t_RR - (abs(I_RM) / a_iD), 0);
        
        %  --- Energy Integration ---
        %  [Eq. 31] Turn-ON Energy (E_on): Linear approximation of V*I overlap.
        %  Includes load current I_sw plus the reverse recovery spike I_RM.
        E_on = V_DC * ( (t_RI_prime/2)*(I_sw + abs(I_RM)) + t_FV*(I_sw/2 + abs(I_RM)/3) );
        P_on = E_on * f_sw;
        
        %  [Eq. 32] Reverse Recovery Energy (E_rr): Loss inside the diode/circuit.
        E_rr = (V_DC * abs(I_RM) * t_FV) / 6;
        P_rr = E_rr * f_sw;
    end
    
    %% 4. Turn-OFF Loss (Always Hard)
    %  In DAB (SPS), turn-off always interrupts peak current, forcing a hard voltage rise.
    
    %  Voltage Rise Time (t_RV): Charging C_rss (Miller Cap) from Plateau to Off.
    denom_rv = abs(s.V_plateau - s.V_dr_off);
    t_RV = (s.Rg * s.Crss * V_DC) / max(denom_rv, 1e-3);
    
    %  Current Fall Time (t_FI): Discharging C_iss from Plateau to Threshold.
    term_start = abs(s.V_dr_off - s.V_plateau);
    term_end   = abs(s.V_dr_off - s.V_gs_th);
    t_FI = s.Rg * s.Ciss * log(max(term_start, 1e-3) / max(term_end, 1e-3));
    
    %  [Eq. 36] Turn-OFF Energy (E_off): Overlap of rising V and falling I.
    E_off = (V_DC * I_sw / 2) * (t_RV + t_FI);
    P_off = E_off * f_sw;

    %% 5. Total Loss Summation
    P_sw_total = P_on + P_rr + P_off;
end