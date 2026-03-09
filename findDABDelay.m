function t_delay = findDABDelay(Vin, Vout, Pout, n, Lk, fs)
% UPDATEDABDELAY Calculates SPS phase shift and updates workspace variables.
%   Inputs:
%       Vin, Vout: Voltages [V]
%       Pout: Target Power [W]
%       n: Turns ratio (Ns/Np)
%       Lk: Leakage Inductance [H]
%       fs: Switching Frequency [Hz]
%
%   Outputs to Workspace:
%       'd_opt': Normalized phase shift (0 - 0.5)
%       't_delay': Time delay in seconds

    % 1. Coefficient C for: d^2 - d + C = 0
    % Derived from P = (1-d)*d*Vin*Vout / (2*n*Lk*fs)
    c = (2 * Pout * n * Lk * fs) / (Vin * Vout);

    % 2. Stability Check (Discriminant)
    delta = 1 - 4*c;
    if delta < 0
        error('DAB_Calc:PowerLimit', ...
              'Target power %.2f kW exceeds max capacity.', Pout/1e3);
    end

    % 3. Solve for efficient root (d < 0.5)
    d = (1 - sqrt(delta)) / 2;

    % 4. Calculate Time Delay (Assuming d=1 is 180 deg / half-cycle)
    t_delay = d / (2 * fs);  

    % 6. Console Feedback
    fprintf('Workspace updated: d = %.4f, Delay = %.2f ns\n', d, t_delay*1e9);
end