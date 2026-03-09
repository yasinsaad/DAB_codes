function [P_body, P_body_h, P_body_l, info] = calculateBodyDiodeLosses_DAB( ...
    I_comm_h, I_comm_l, V_f_h, V_f_l, f_sw, ...
    t_dead_actual_h, t_dead_actual_l, ...
    is_zvs_h, is_zvs_l, ...
    t_trans_needed_h, t_trans_needed_l)
% CALCULATEBODYDIODELOSSES_DAB
% -------------------------------------------------------------------------
% Estimates dead-time body-diode / reverse-conduction loss in a DAB.
%
% OUTPUTS:
%   P_body     : total dead-time diode / reverse-conduction loss [W]
%   P_body_h   : HV-bridge contribution [W]
%   P_body_l   : LV-bridge contribution [W]
%   info       : diagnostic structure with intermediate values
%
% INPUTS:
%   I_comm_h, I_comm_l       : commutation current magnitudes [A]
%   V_f_h, V_f_l             : effective diode / reverse-conduction drop [V]
%   f_sw                     : switching frequency [Hz]
%   t_dead_actual_h/l        : actual inserted dead time per event [s]
%   is_zvs_h/l               : true if the corresponding bridge achieves ZVS
%   t_trans_needed_h/l       : time required to fully slew switch-node
%                              voltage during commutation [s]
%
% PHYSICAL INTERPRETATION
% -------------------------------------------------------------------------
% In a bridge leg, dead time is inserted between turning one device OFF and
% the complementary device ON, in order to avoid shoot-through.
%
% During this dead-time interval, the load / leakage current must continue
% flowing somehow. It therefore flows through:
%   - the body diode in Si MOSFET implementations, or
%   - the reverse-conduction path in GaN devices.
%
% However, the entire dead-time interval does NOT necessarily correspond to
% diode/reverse-conduction loss.
%
% The dead-time interval is divided conceptually into:
%
%   1) COMMUTATION INTERVAL:
%      Current charges/discharges output capacitances and slews the switch
%      node voltage. This interval is needed to achieve ZVS.
%
%   2) REMAINING CLAMP INTERVAL:
%      After the node voltage has completed its transition, the current may
%      continue flowing through the diode / reverse-conduction path until
%      the channel is actively turned on.
%
% This function assumes the diode/reverse-conduction loss is generated only
% during part (2), not part (1).
%
% Therefore:
%   t_dead_eff = t_dead_actual - t_trans_needed
%
% but only if ZVS succeeds. If ZVS does not succeed, this function sets the
% dead-time diode loss of that event to zero and assumes the turn-on loss
% will be handled separately in the switching-loss model.
%
% LOSS MODEL USED
% -------------------------------------------------------------------------
% Average conduction loss is computed using:
%
%   P = V_f * I_avg
%
% For a repeated dead-time event, the equivalent average current is modeled
% by multiplying the commutation current magnitude by the fraction of time
% spent in diode / reverse conduction:
%
%   duty_dead = N_events * t_dead_eff * f_sw
%
% so that:
%
%   P_body = V_f * |I_comm| * duty_dead
%
% This is equivalent to saying:
%
%   Energy per event   = V_f * |I_comm| * t_dead_eff
%   Power              = Energy/event * events/second
%
% Since:
%   events/second = N_events * f_sw
%
% we get the same result.
%
% DAB-SPECIFIC ASSUMPTION
% -------------------------------------------------------------------------
% This implementation assumes:
%   N_events = 4
%
% meaning 4 dead-time events per switching period per full bridge.
% This is a common full-bridge counting assumption. If your modulation,
% gating sequence, or event-counting convention differs, change N_events.
%
% IMPORTANT MODEL LIMITATIONS
% -------------------------------------------------------------------------
% - Current is treated as approximately constant during each dead-time event.
% - V_f is treated as constant.
% - Reverse-recovery loss is NOT calculated here.
% - If ZVS fails, this function intentionally assigns zero dead-time diode
%   loss and leaves the corresponding hard-switching loss to another model.
% - This is a compact engineering model, not a full device-physics model.
%
% LITERATURE INSPIRATION
% -------------------------------------------------------------------------
% The modeling idea is inspired by standard power-electronics dead-time and
% soft-switching analysis:
%
% 1) Dead time exists to avoid shoot-through, but too much dead time causes
%    extra diode / reverse-conduction loss.
%
% 2) Soft-switching requires a finite commutation time to charge/discharge
%    parasitic capacitances before the device can turn on at low voltage.
%
% 3) Reverse-conduction loss is approximately proportional to:
%       conduction drop * current * conduction time
%
% 4) For GaN, this "diode loss" is usually really reverse-conduction loss,
%    since the reverse path differs from the classical silicon body-diode
%    picture.
%
% Recommended use:
%   - First compute is_zvs_* and t_trans_needed_* from your ZVS model.
%   - Then pass the ACTUAL inserted dead time into this function.
% -------------------------------------------------------------------------

    % Number of dead-time events per switching period per full bridge.
    % For a standard full bridge, 4 is a common assumption:
    % each leg commutates twice per switching cycle.
    %
    % If your modulation changes the effective number of dead-time intervals,
    % modify this value accordingly.
    N_events = 4;

    % ---------------------------------------------------------------------
    % HV side: effective diode / reverse-conduction interval
    % ---------------------------------------------------------------------
    % If ZVS is achieved, part of the dead time is "used up" by the voltage
    % transition itself:
    %
    %   t_trans_needed_h
    %
    % Only the remaining interval contributes to diode / reverse-conduction
    % loss:
    %
    %   t_dead_eff_h = t_dead_actual_h - t_trans_needed_h
    %
    % A max(.,0) is used because negative conduction time has no meaning.
    %
    % If ZVS is NOT achieved, we set this dead-time loss term to zero here
    % and assume the penalty appears instead in the switching-loss model.
    if is_zvs_h
        t_dead_eff_h = max(t_dead_actual_h - t_trans_needed_h, 0);
    else
        t_dead_eff_h = 0;
    end

    % ---------------------------------------------------------------------
    % LV side: same logic as HV side
    % ---------------------------------------------------------------------
    if is_zvs_l
        t_dead_eff_l = max(t_dead_actual_l - t_trans_needed_l, 0);
    else
        t_dead_eff_l = 0;
    end

    % ---------------------------------------------------------------------
    % Convert conduction time into an equivalent duty fraction
    % ---------------------------------------------------------------------
    % Each event contributes a conduction duration t_dead_eff.
    % There are N_events such events per switching period.
    % There are f_sw switching periods per second.
    %
    % Therefore the fraction of total time spent in dead-time conduction is:
    %
    %   duty_dead = N_events * t_dead_eff * f_sw
    %
    % This is dimensionless:
    %   [events/cycle] * [s/event] * [cycle/s] = [-]
    %
    % It can be interpreted as the effective conduction duty ratio of the
    % diode / reverse-conduction path.
    duty_dead_h = N_events * t_dead_eff_h * f_sw;
    duty_dead_l = N_events * t_dead_eff_l * f_sw;

    % Numerical guard:
    % In normal designs this duty should be small. The clamp prevents bad
    % upstream values from producing unrealistic results.
    %
    % This clamp is NOT a physical law, just a safety guard.
    duty_dead_h = min(max(duty_dead_h, 0), 0.2);
    duty_dead_l = min(max(duty_dead_l, 0), 0.2);

    % ---------------------------------------------------------------------
    % Loss calculation
    % ---------------------------------------------------------------------
    % Approximate conduction loss:
    %
    %   P = V_f * I * duty
    %
    % Here:
    %   V_f          = effective conduction drop of diode / reverse path
    %   |I_comm|     = magnitude of current during dead time
    %   duty_dead    = fraction of total time the path conducts
    %
    % This is equivalent to:
    %   E_event = V_f * |I_comm| * t_dead_eff
    %   P       = E_event * N_events * f_sw
    P_body_h = V_f_h * abs(I_comm_h) * duty_dead_h;
    P_body_l = V_f_l * abs(I_comm_l) * duty_dead_l;

    % Total body-diode / reverse-conduction loss
    P_body = P_body_h + P_body_l;

    % ---------------------------------------------------------------------
    % Diagnostic output structure
    % ---------------------------------------------------------------------
    % These values are useful for checking whether:
    %   - dead time is too large,
    %   - transition time is consuming most of dead time,
    %   - ZVS is actually being achieved,
    %   - duty_dead is staying in a realistic range.
    info = struct();
    info.N_events = N_events;

    info.t_dead_actual_h = t_dead_actual_h;
    info.t_dead_actual_l = t_dead_actual_l;

    info.t_trans_needed_h = t_trans_needed_h;
    info.t_trans_needed_l = t_trans_needed_l;

    info.is_zvs_h = is_zvs_h;
    info.is_zvs_l = is_zvs_l;

    info.t_dead_eff_h = t_dead_eff_h;
    info.t_dead_eff_l = t_dead_eff_l;

    info.duty_dead_h = duty_dead_h;
    info.duty_dead_l = duty_dead_l;
end