function [P_body, P_body_h, P_body_l] = calculateBodyDiodeLosses( ...
    I_comm_h, I_comm_l, V_f_h, V_f_l, f_sw, t_dead_total)

% Simple dead-time diode conduction loss estimate for full-bridge DAB.
% Uses commutation current magnitude (best: switching instant current).
%
% Assumptions:
% - Each leg experiences 2 dead-times per switching period.
% - During each dead-time, current freewheels through diode (or body diode).
% - 2 legs per full bridge => 4 dead-time events per period per bridge.

    % Total dead-time per commutation (you have on+off dead times)
    t_d = t_dead_total;  % seconds

    % 4 dead-time events per period per bridge (2 legs × 2 commutations)
    duty_dead = 4 * t_d * f_sw;   % fraction of time in dead-time per bridge

    % Clamp to avoid nonsense if dead time too big
    duty_dead = min(duty_dead, 0.2);

    P_body_h = V_f_h * abs(I_comm_h) * duty_dead;
    P_body_l = V_f_l * abs(I_comm_l) * duty_dead;

    P_body = P_body_h + P_body_l;
end
