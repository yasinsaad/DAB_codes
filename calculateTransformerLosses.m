function [P_core, P_cu, P_tr, B_pk, k_fe] = calculateTransformerLosses( ...
    f_sw, Vin, Ipri_rms, Isec_rms, ...
    V_core_fixed, A_core_fixed, N_pri, ...
    Ks_ref, alpha, beta, ...
    Rac_pri, Rac_sec, C_wave)
% CALCULATETRANSFORMERLOSSES
% ---------------------------------------------------------------
% Estimates transformer loss for a fixed magnetic design.
%
% OUTPUTS:
%   P_core  : estimated magnetic core loss [W]
%   P_cu    : winding copper loss [W]
%   P_tr    : total transformer loss = P_core + P_cu [W]
%   B_pk    : peak flux density in the core [T]
%   k_fe    : Steinmetz-type coefficient derived from the reference loss point
%
% INPUTS:
%   f_sw         : switching frequency [Hz]
%   Vin          : applied primary square-wave voltage magnitude [V]
%   Ipri_rms     : primary RMS current [A]
%   Isec_rms     : secondary RMS current [A]
%   V_core_fixed : physical core volume [m^3]
%   A_core_fixed : effective core cross-sectional area [m^2]
%   N_pri        : number of primary turns
%   Ks_ref       : reference core-loss density at (25 kHz, 100 mT)
%                  units must be consistent with the output desired for p_core_density
%   alpha, beta  : Steinmetz exponents for the selected magnetic material
%   Rac_pri      : primary AC resistance [ohm]
%   Rac_sec      : secondary AC resistance [ohm]
%   C_wave       : optional waveform correction factor
%
% MODELING NOTES
% ---------------------------------------------------------------
% 1) Core-loss model:
%       p_core = C_wave * k_fe * f^alpha * B^beta
%
%    This is a Steinmetz-style empirical loss-density model. The
%    original Steinmetz idea relates magnetic loss density to frequency
%    and flux-density swing using fitted material coefficients.
%
% 2) Flux-density model for square-wave excitation:
%       B_pk = Vin / (4 * N_pri * A_core * f_sw)
%
%    This comes from Faraday's law:
%       v = N * A * dB/dt
%    For a symmetric square wave, integrating voltage over half a period
%    gives the corresponding flux excursion, which leads to the usual
%    full-bridge transformer estimate above.
%
% 3) Copper-loss model:
%       P_cu = Ipri_rms^2 * Rac_pri + Isec_rms^2 * Rac_sec
%
%   Rac for both found using Krismer Model
% LITERATURE INSPIRATION
% ---------------------------------------------------------------
% - Steinmetz-style magnetic loss law:
%   The basic loss-density form k*f^alpha*B^beta is inspired by the
%   classical Steinmetz approach and its later extensions for power
%   magnetics materials.
%
% - Non-sinusoidal / switched-waveform loss treatment:
%   C_wave is a simplified practical way to adjust the sinusoidal-fit
%   Steinmetz law for square-wave or other nonsinusoidal excitation.
%   More rigorous treatments are given by MSE/GSE/iGSE-type methods.
%
% - Copper loss with AC winding resistance:
%   The I^2*R form is standard, while the use of AC resistance reflects
%   high-frequency winding-loss practice originating from Dowell-type
%   modeling and later refinements.
%--------------------------------------------------------

    % Default waveform correction factor:
    % If none is supplied, use a practical correction for switched
    % square-wave excitation.
    if nargin < 13 || isempty(C_wave)
        C_wave = 1.25;
    end

    % -----------------------------------------------------------
    % STEP 1: Estimate peak core flux density for square-wave drive
    % -----------------------------------------------------------
    % Using Faraday's law:
    %   v = N * A * dB/dt
    %
    % For a symmetric square wave in a transformer, the common practical
    % estimate of peak flux density is:
    %   B_pk = Vin / (4 * N_pri * A_core * f_sw)
    %
    % Meaning:
    % - Higher Vin increases flux.
    % - More turns lower flux.
    % - Larger core area lowers flux.
    % - Higher switching frequency lowers flux.
    B_pk = Vin ./ (4 .* N_pri .* A_core_fixed .* f_sw);

    % -----------------------------------------------------------
    % STEP 2: Define the reference point for the supplied loss data
    % -----------------------------------------------------------
    % We interpret Ks_ref as a known core-loss density measured or quoted
    % at:
    %   f_ref = 25 kHz
    %   B_ref = 100 mT = 0.1 T
    %
    % So:
    %   Ks_ref = p_core_ref = k_fe * f_ref^alpha * B_ref^beta
    %
    % Rearranging gives the Steinmetz coefficient k_fe.
    f_ref = 25e3;   % 100 kHz
    B_ref = 0.1;     % 100 mT = 0.1 T

    % Convert the single reference loss-density point into the coefficient
    % k_fe used by the Steinmetz-style law:
    %
    %   p_core_ref = k_fe * f_ref^alpha * B_ref^beta
    %   k_fe       = p_core_ref / (f_ref^alpha * B_ref^beta)
    k_fe = Ks_ref ./ ((f_ref.^alpha) .* (B_ref.^beta));

    % -----------------------------------------------------------
    % STEP 3: Compute core-loss density at the operating point
    % -----------------------------------------------------------
    % Steinmetz-style loss density:
    %   p_core_density = C_wave * k_fe * f_sw^alpha * B_pk^beta
    %
    % C_wave is an extra correction factor used to adapt the
    % reference Steinmetz law to the actual waveform shape.
    p_core_density = C_wave .* k_fe .* (f_sw.^alpha) .* (B_pk.^beta);

    % -----------------------------------------------------------
    % STEP 4: Convert loss density into total core loss
    % -----------------------------------------------------------
    % Total core loss is:
    %   P_core = loss_density * core_volume
    P_core = p_core_density .* V_core_fixed;

    % -----------------------------------------------------------
    % STEP 5: Compute copper loss in primary and secondary windings
    % -----------------------------------------------------------
    % Standard RMS copper-loss expression:
    %   P = I_rms^2 * R
    %
    % Here Rac_pri and Rac_sec are AC resistances, so they may already
    % include skin effect and proximity effect depending on how you
    % obtained them.
    P_cu = (Ipri_rms.^2 .* Rac_pri) + (Isec_rms.^2 .* Rac_sec);

    % -----------------------------------------------------------
    % STEP 6: Total transformer loss
    % -----------------------------------------------------------
    P_tr = P_core + P_cu;

end
