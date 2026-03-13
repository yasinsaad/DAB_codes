function [t_dead_eff, info] = estimate_dead_time_from_device(s, op)
% ESTIMATE_DEAD_TIME_FROM_DEVICE
% Practical dead-time estimator for DAB use.
%
% Two usage modes:
%   1) Device-only mode:
%        t_dead_eff ~= safe turn-off dead time
%
%   2) Device + operating-point mode:
%        t_dead_eff = max(t_off_safe, t_comm_zvs_req)
%
% Inputs:
%   s : semiconductor struct
%       Required/useful fields:
%         s.Rg            internal gate resistance [ohm]
%         s.V_dr_on       gate drive ON voltage [V]
%         s.V_dr_off      gate drive OFF voltage [V]
%         s.V_gs_th       threshold voltage [V]
%         s.V_plateau     Miller plateau voltage [V]
%
%       Optional/useful:
%         s.Qg            total gate charge [C]
%         s.Qgs           gate-source charge [C]
%         s.Qgd           gate-drain (Miller) charge [C]
%         s.Ciss          input capacitance [F]
%         s.Coss          output capacitance [F]
%         s.Qoss          output charge [C]
%
%         s.Rg_ext_on
%         s.Rg_ext_off
%         s.R_driver_on
%         s.R_driver_off
%         s.deadtime_sf
%         s.t_dead_min
%         s.t_dead_max
%
%   op : optional operating-point struct
%       op.V_DC          bridge-leg DC voltage [V]
%       op.I_comm        commutation current magnitude [A]
%       Optional:
%       op.Q_node        total node charge to move during commutation [C]
%
% Outputs:
%   t_dead_eff : estimated dead time [s]
%   info       : diagnostic struct
%
% Notes:
%   - For fixed-dead-time converter studies, call this WITHOUT op and use
%     the result as a practical chosen dead time based on device turn-off.
%   - For adaptive-dead-time studies, call this WITH op so the function
%     also considers how much time is needed for ZVS commutation.

    % If operating-point struct is not supplied, use empty struct.
    % That means the function will run in "device-only" mode.
    if nargin < 2
        op = struct();
    end

    %% -------- DEFAULTS --------
    % These defaults fill in missing external-gate-drive values so the
    % function can still run even if your device struct is incomplete.

    % External ON gate resistor
    if ~isfield(s,'Rg_ext_on'),    s.Rg_ext_on = 0; end

    % External OFF gate resistor
    if ~isfield(s,'Rg_ext_off'),   s.Rg_ext_off = s.Rg_ext_on; end

    % Driver output resistance during turn-on
    if ~isfield(s,'R_driver_on'),  s.R_driver_on = 1.0; end

    % Driver output resistance during turn-off
    if ~isfield(s,'R_driver_off'), s.R_driver_off = s.R_driver_on; end

    % Safety factor used to enlarge estimated turn-off time into a practical dead time
    if ~isfield(s,'deadtime_sf'),  s.deadtime_sf = 1.5; end

    % Practical clamp values so dead time does not become unrealistically small or large
    if ~isfield(s,'t_dead_min'),   s.t_dead_min = 20e-9; end
    if ~isfield(s,'t_dead_max'),   s.t_dead_max = 300e-9; end

    %% -------- BASIC REQUIRED CHECKS --------
    % These are the minimum fields needed to estimate turn-off-related timing.
    req = {'Rg','V_dr_on','V_dr_off','V_gs_th','V_plateau'};
    for k = 1:numel(req)
        if ~isfield(s, req{k})
            error('estimate_dead_time_from_device: missing field s.%s', req{k});
        end
    end

    %% -------- TOTAL GATE PATH RESISTANCES --------
    % Total ON-path resistance = internal gate resistance + external resistor + driver resistance
    Rtot_on  = s.Rg + s.Rg_ext_on  + s.R_driver_on;

    % Total OFF-path resistance = internal gate resistance + external resistor + driver resistance
    Rtot_off = s.Rg + s.Rg_ext_off + s.R_driver_off;

    %% -------- GATE-CURRENT ESTIMATES --------
    % Approximate gate current during the Miller plateau while turning ON.
    % This is useful mostly for diagnostics, not for final dead-time selection.
    Ig_on_miller = abs(s.V_dr_on  - s.V_plateau) / max(Rtot_on,  1e-3);

    % Approximate gate discharge current during the Miller plateau while turning OFF.
    % This matters strongly for turn-off speed and therefore for safe dead time.
    Ig_off_miller = abs(s.V_plateau - s.V_dr_off) / max(Rtot_off, 1e-3);

    % Approximate gate discharge current from threshold region toward OFF.
    % This models the gate moving from threshold toward the OFF bias.
    Ig_off_thresh = abs(s.V_gs_th - s.V_dr_off) / max(Rtot_off, 1e-3);

    %% -------- CHARGE ESTIMATES --------
    % Prefer explicit Qgd and Qgs if they are available.
    % If not, approximate them as fractions of total gate charge.

    if isfield(s,'Qgd')
        % Qgd = Miller charge, strongly related to the drain/collector voltage transition
        Qgd = s.Qgd;
    else
        % Rough fallback if only total gate charge is available
        Qgd = 0.25 * s.Qg;
    end

    if isfield(s,'Qgs')
        % Qgs = gate-source charge before / around threshold region
        Qgs = s.Qgs;
    else
        % Rough fallback
        Qgs = 0.35 * s.Qg;
    end

    % Effective threshold-region charge contribution.
    % Kept non-negative for robustness.
    Qgs_eff = max(Qgs, 0);

    %% -------- TURN-ON / TURN-OFF TIME ESTIMATES --------
    % Turn-on estimate:
    % Uses Miller + source charge divided by approximate ON current.
    % Mostly included for diagnostic comparison.
    t_on_est = (Qgd + Qgs_eff) / max(Ig_on_miller, 1e-6);

    % Turn-off estimate:
    % Sum of:
    %   1) Miller discharge time
    %   2) threshold-region discharge time
    %
    % This is more relevant than t_on_est for dead-time selection because
    % dead time is primarily needed to guarantee the outgoing device is OFF
    % before the complementary device turns ON.
    t_off_est = Qgd / max(Ig_off_miller, 1e-6) + ...
                Qgs_eff / max(Ig_off_thresh, 1e-6);

    %% -------- SAFE DEAD TIME FROM DEVICE TURN-OFF --------
    % Add margin using a safety factor.
    % This gives a practical "safe turn-off dead time" estimate.
    t_off_safe = s.deadtime_sf * t_off_est;

    %% -------- OPTIONAL ZVS COMMUTATION REQUIRED TIME --------
    % If operating-point info is provided, also estimate how much dead time
    % is needed for the switch node to actually complete its commutation for ZVS.
    t_comm_zvs_req = NaN;

    if isfield(op,'I_comm') && isfield(op,'V_DC')
        % Use current magnitude because commutation time depends on |I_comm|
        Iabs = abs(op.I_comm);

        if Iabs > 0.1
            % If user supplies direct total node charge, use that
            if isfield(op,'Q_node')
                Q_node = op.Q_node;

            % Else if device output charge is known, use two-device half-bridge estimate
            elseif isfield(s,'Qoss')
                Q_node = 2 * s.Qoss;

            % Else fallback to constant-Coss estimate:
            % Q = C * V for two devices in the half-bridge node
            elseif isfield(s,'Coss')
                Q_node = 2 * s.Coss * op.V_DC;

            else
                Q_node = NaN;
            end

            % Required ZVS commutation time:
            % t = Q / I
            if ~isnan(Q_node)
                t_comm_zvs_req = Q_node / Iabs;
            end
        else
            % If commutation current is near zero, ZVS commutation time is effectively infinite
            t_comm_zvs_req = inf;
        end
    end

    %% -------- FINAL DEAD TIME CHOICE --------
    % If no operating-point info is given:
    %   use only safe turn-off dead time
    %
    % If operating-point info is given:
    %   choose the larger of:
    %       - safe turn-off dead time
    %       - ZVS commutation-required dead time
    if isnan(t_comm_zvs_req)
        t_dead_est = t_off_safe;
    else
        t_dead_est = max(t_off_safe, t_comm_zvs_req);
    end

    % Clamp into practical allowed range
    t_dead_eff = min(max(t_dead_est, s.t_dead_min), s.t_dead_max);

    %% -------- DIAGNOSTICS --------
    % Return all intermediate values so you can inspect how the estimate was built
    info = struct();

    info.Rtot_on        = Rtot_on;
    info.Rtot_off       = Rtot_off;

    info.Ig_on_miller   = Ig_on_miller;
    info.Ig_off_miller  = Ig_off_miller;
    info.Ig_off_thresh  = Ig_off_thresh;

    info.Qgd            = Qgd;
    info.Qgs_eff        = Qgs_eff;

    info.t_on_est       = t_on_est;
    info.t_off_est      = t_off_est;
    info.t_off_safe     = t_off_safe;

    info.t_comm_zvs_req = t_comm_zvs_req;
    info.t_dead_est     = t_dead_est;
end