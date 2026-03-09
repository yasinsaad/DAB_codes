function [P_body, P_body_h, P_body_l] = calculateBodyDiodeLosses( ...
    I_comm_h, I_comm_l, V_f_h, V_f_l, f_sw, t_dead_h, t_dead_l)

% Full-bridge DAB dead-time diode loss (simple model)
% Uses commutation current magnitudes (best: switching instant current)
% t_dead_h, t_dead_l are EFFECTIVE diode conduction times per commutation event

    % 4 dead-time events per period per bridge = 2 legs × 2 commutations
    duty_dead_h = 4 * t_dead_h * f_sw;
    duty_dead_l = 4 * t_dead_l * f_sw;

    duty_dead_h = min(duty_dead_h, 0.2);
    duty_dead_l = min(duty_dead_l, 0.2);

    P_body_h = V_f_h * abs(I_comm_h) * duty_dead_h;
    P_body_l = V_f_l * abs(I_comm_l) * duty_dead_l;

    P_body = P_body_h + P_body_l;
end
