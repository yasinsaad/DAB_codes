function [P_core, P_cu, P_tr, Rm_eq, B_pk, k_fe] = calculateTransformerLosses( ...
    f_sw, Vin, Ipri_rms, Isec_rms, ...
    V_core, A_core, N_pri, ...
    Ks, alpha, beta, ...
    Rac_pri, Rac_sec, makeRmEq)

% calculateTransformerLosses_paper
% Consistent with the paper's loss breakdown style: transformer = core + copper.
% Core: Steinmetz-like p = k * f^alpha * B^beta, with k derived from Ks at (100kHz,100mT)
% Copper: I_rms^2 * Rac per winding
%
% Full-bridge DAB assumption: primary voltage is a square wave ±Vin -> Vpri_pk = Vin
% Flux estimate: B_pk = Vin / (4*N*A*f)

    if nargin < 14 || isempty(makeRmEq)
        makeRmEq = true; % you are using Rm in Simulink; keep it on by default
    end

    % --- Convert single-point loss density "Ks @ 100kHz, 100mT" to Steinmetz constant k ---
    f_ref = 100e3; % Hz
    B_ref = 0.1;   % T
    k_fe = Ks / ((f_ref^alpha) * (B_ref^beta));

    % --- Peak flux density under square-wave excitation (full bridge) ---
    B_pk = Vin / (4 * N_pri * A_core * f_sw);

    % --- Core loss ---
    % P_core = (k * f^alpha * B^beta) * V_core
    P_core = (k_fe * (f_sw^alpha) * (abs(B_pk)^beta)) * V_core;

    % --- Copper loss ---
    P_cu = (Ipri_rms^2)*Rac_pri + (Isec_rms^2)*Rac_sec;

    % --- Total transformer loss ---
    P_tr = P_core + P_cu;

    % --- Equivalent parallel resistance for core loss (simulation convenience) ---
    if makeRmEq
        Vpri_rms = Vin; % RMS of square wave ±Vin is Vin
        if P_core > 0
            Rm_eq = (Vpri_rms^2) / P_core;
        else
            Rm_eq = Inf;
        end
    else
        Rm_eq = [];
    end
end
