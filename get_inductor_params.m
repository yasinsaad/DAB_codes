function inductor = get_inductor_params(source, trans, f_sw_curr, max_power) 
    inductor.Lk = (source.Vin * source.Vout) / (8 * trans.n * f_sw_curr * max_power);
    inductor.Rdc = calculate_dab_inductor_rdc(inductor.Lk);
end
function Rdc = calculate_dab_inductor_rdc(L)
    % CALCULATE_DAB_INDUCTOR_RDC Computes the DC resistance of a DAB inductor
    % based on typical high-frequency ferrite core (ETD44) parameters.
    % 
    % Input:
    %   L   - Required Inductance (Henries) [Can be a scalar or array]
    %
    % Output:
    %   Rdc - Estimated DC Resistance (Ohms)
    
    % Hardcoded typical parameters for a DAB inductor (ETD44 core, Litz wire)
    rho = 1.724e-8;         % Resistivity of copper at 20C (Ohm-meters)
    le  = 103e-3;           % Magnetic path length (meters)
    MLT = 77e-3;            % Mean length of turn (meters)
    mu  = 100 * (4*pi*1e-7);% Effective permeability of gapped core (H/m)
    Ac  = 173e-6;           % Core cross-sectional area (meters^2)
    Wa  = 213e-6;           % Core window area (meters^2)
    Ku  = 0.25;             % Fill factor for Litz wire (dimensionless)
    
    % Core and winding geometry constant
    % For these parameters, the constant is approx 118.1 Ohms/Henry
    geometry_constant = (rho * le * MLT) / (mu * Ac * Wa * Ku);
    
    % Calculate DC Resistance
    Rdc = L .* geometry_constant;
end