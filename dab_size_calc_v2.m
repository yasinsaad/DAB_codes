function out = dab_size_calc_v2(f, Vin, Vout, P, n, phi, Ipk_sim, opts)
% dab_size_calc_v2
% Better sizing model for SPS DAB (full-bridge) magnetics.
%
% INPUTS
%   f        : switching frequency [Hz]
%   Vin      : HV DC bus [V] (primary full-bridge)
%   Vout     : LV DC bus [V] (secondary full-bridge)
%   P        : transferred power (positive) [W]
%   n        : turns ratio (depends on opts.n_def)
%   phi      : phase shift [rad], 0..pi
%   Ipk_sim  : (optional) peak link current from Simulink [A], pass [] if unknown
%   opts     : struct with sizing assumptions (optional)
%
% OUTPUT (struct)
%   out.L_req       : required series inductance for SPS [H]
%   out.V2_ref_pri  : secondary bridge voltage referred to primary [V]
%   out.Ipk_used    : peak current used for inductor energy sizing [A]
%   out.Ipk_est     : estimated peak current (if Ipk_sim not provided) [A]
%   out.V_L_pk      : approximate peak inductor voltage during first interval [V]
%   out.E_L         : energy at peak current [J]
%   out.V_L_core    : estimated inductor core volume [m^3]
%   out.Ac_req_T    : required transformer core area [m^2]
%   out.V_T_core    : estimated transformer core volume [m^3]
%   out.V_total     : total magnetic volume [m^3]
%   out.ok          : boolean validity flag
%   out.notes       : string with warnings/notes
%
% MODEL NOTES
%   - Uses standard SPS DAB power law:
%     P = (V1 * V2')/(w*L) * (phi*(pi-phi)/pi)
%     where V2' is secondary bridge voltage referred to primary.
%   - Transformer core area uses square-wave relation:
%     Bpk = Vin/(4*Np*Ac*f)  =>  Ac = Vin/(4*f*Np*Bmax_T)
%   - Inductor volume uses energy method:
%     Vcore ≈ (2*E)/(k_u*Bmax^2)
%
% DEFAULTS
%   opts.n_def   = 'Ns_over_Np'  (matches your trans.n = V2/V1 = Ns/Np)
%   opts.Np      = 16
%   opts.Bmax_L  = 0.30   Tesla
%   opts.Bmax_T  = 0.25   Tesla (more realistic for HF transformer)
%   opts.ku_L    = 0.40   utilization factor (inductor)
%   opts.kT      = 6.0    geometry constant for transformer volume heuristic
%   opts.phi_min = 1*pi/180  (avoid divide-by-zero)
%   opts.phi_max = 179*pi/180
%
% IMPORTANT:
%   This is a sizing estimator. For final design, use manufacturer core families and
%   window/copper constraints.

    if nargin < 8 || isempty(opts)
        opts = struct();
    end

    % Defaults
    if ~isfield(opts,'n_def');   opts.n_def   = 'Ns_over_Np'; end
    if ~isfield(opts,'Np');      opts.Np      = 16;          end
    if ~isfield(opts,'Bmax_L');  opts.Bmax_L  = 0.30;        end
    if ~isfield(opts,'Bmax_T');  opts.Bmax_T  = 0.25;        end
    if ~isfield(opts,'ku_L');    opts.ku_L    = 0.40;        end
    if ~isfield(opts,'kT');      opts.kT      = 6.0;         end
    if ~isfield(opts,'phi_min'); opts.phi_min = 1*pi/180;    end
    if ~isfield(opts,'phi_max'); opts.phi_max = 179*pi/180;  end

    out = struct();
    out.ok = true;
    out.notes = "";

    % sanitize inputs
    P   = abs(P);
    phi = abs(phi);

    if phi < opts.phi_min || phi > opts.phi_max
        out.ok = false;
        out.notes = "phi out of safe range (near 0 or pi). Results may be unstable.";
        phi = min(max(phi, opts.phi_min), opts.phi_max);
    end

    w = 2*pi*f;

    % --- Turns ratio convention handling ---
    % You usually use trans.n = Ns/Np (because V2/V1 = 1/16).
    % For DAB power formula we need V2' referred to primary:
    % V2' = Vout * (Np/Ns) = Vout / (Ns/Np)
    switch opts.n_def
        case 'Ns_over_Np'
            n_NsNp = n;
            out.V2_ref_pri = Vout / n_NsNp;
        case 'Np_over_Ns'
            n_NpNs = n;
            out.V2_ref_pri = Vout * n_NpNs;
        otherwise
            error('opts.n_def must be ''Ns_over_Np'' or ''Np_over_Ns''');
    end

    V1 = Vin;
    V2p = out.V2_ref_pri;

    % --- SPS DAB power law (standard) ---
    % P = (V1*V2p)/(w*L) * (phi*(pi-phi)/pi)
    kphi = (phi*(pi-phi))/pi;
    out.L_req = (V1*V2p) * kphi / (w * P);

    % --- Peak inductor voltage during first interval (approx) ---
    % When bridges oppose/aid depends on phi region, but |V1 - V2p| is a good magnitude.
    out.V_L_pk = abs(V1 - V2p);

    % --- Peak current: use Simulink if provided, else estimate ---
    % First-interval duration = phi/w
    % DeltaI ≈ (V_L/L) * (phi/w)
    % If we assume symmetric triangular about 0, Ipk ≈ DeltaI/2
    out.Ipk_est = 0.5 * (out.V_L_pk/out.L_req) * (phi/w);

    if nargin >= 7 && ~isempty(Ipk_sim) && isfinite(Ipk_sim) && Ipk_sim > 0
        out.Ipk_used = Ipk_sim;
    else
        out.Ipk_used = out.Ipk_est;
        if out.notes ~= ""; out.notes = out.notes + " "; end
        out.notes = out.notes + "Ipk_sim not provided -> used estimated peak current.";
    end

    % --- Inductor energy + volume estimate ---
    out.E_L = 0.5 * out.L_req * (out.Ipk_used^2);
    out.V_L_core = (2*out.E_L) / (opts.ku_L * (opts.Bmax_L^2));

    % --- Transformer core area (square wave) ---
    % Bpk = Vin/(4*Np*Ac*f) => Ac = Vin/(4*f*Np*Bmax_T)
    out.Ac_req_T = Vin / (4 * f * opts.Np * opts.Bmax_T);

    % --- Transformer volume heuristic ---
    % V ~ kT * Ac^(3/2) (keeps your old scaling but uses correct Ac)
    out.V_T_core = opts.kT * (out.Ac_req_T^(3/2));

    out.V_total = out.V_L_core + out.V_T_core;

    % Extra sanity flags
    % Check flux at this Ac (should be <= Bmax_T by construction)
    out.Bpk_T = Vin/(4*opts.Np*out.Ac_req_T*f);

end
