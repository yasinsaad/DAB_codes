function t_delay = findDABDelay(Vin, Vout, Pout, n, Lk, fs)

% reflected secondary voltage
V2_ref = Vout / n;

% coefficient
c = (2 * Pout * Lk * fs) / (Vin * V2_ref);

delta = 1 - 4*c;

if delta < 0
    error('Target power exceeds DAB capability.');
end

% choose low phase shift root
d = (1 - sqrt(delta)) / 2;

% convert to time delay
t_delay = d / (2*fs);

fprintf('Workspace updated: d = %.4f, Delay = %.2f ns\n', d, t_delay*1e9);

end