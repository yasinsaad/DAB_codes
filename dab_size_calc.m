function [V_L, V_T, V_total, L_req] = dab_size_calc( f, Vin, Vout, P, n, Delay, Ipk)
% INPUTS:
% f   : switching frequency [Hz]
% Vin  : primary DC voltage [V]
% Vout  : secondary DC voltage [V]
% P   : transferred power [W]
% n   : transformer turns ratio (Np/Ns)
% Delay : phase shift [rad]
% Ipk : peak current from Simulink [A]

% OUTPUTS:
% V_L     : Inductor core volume [m^3]
% V_T     : Transformer core volume [m^3]
% V_total : Total magnetic volume [m^3]
% L_req   : Required series inductance [H]

% MAGNETIC MATERIAL ASSUMPTIONS

Bmax_L = 0.30;    % Tesla (ferrite inductor)
Bmax_T = 0.30;    % Tesla (ferrite transformer)

kL = 0.4;         % Inductor utilization factor
kT = 6.0;         % Transformer geometry constant

% REQUIRED DAB INDUCTANCE (SPS)
L_req = (n * Vin * Vout * Delay) / (2*pi*f*P);

%Peak Current needs to calculated from Simulink. In main script, before
%calling this function, write Ipk_vec(k) = max(abs(Ipk_sim.Data))where k is iteration number.
%Additionally, we need to import the Ipk value from Simulink. First place a
%current measurement block at series inductance/ transformer leakage branch
%and then use the To Workspace block and then use I

% INDUCTOR CORE VOLUME
E_L = 0.5 * L_req * Ipk^2;         % Stored energy [J]
V_L = (2 * E_L) / (kL * Bmax_L^2); % Core volume [m^3]


% TRANSFORMER CORE VOLUME
Np = 16;   % Fixed primary turns (design choice)

Ac = Vin / (4.44 * f * Np * Bmax_T);  % Core area [m^2]
V_T = kT * Ac^(3/2);                 % Core volume [m^3]

% TOTAL MAGNETIC SIZE

V_total = V_L + V_T;

end

