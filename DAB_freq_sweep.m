%% DAB Frequency Sweep: Fixed Magnetic Size + Explicit Dead Time
clear; clc; close all;

%% --- 1. CONFIGURATION ---
model_name = 'DAB_freq_sweep_sim';
target_power = 25000;                  % W
headroom_factor = 1.2;                 % design at 30 kW
freq_steps = (40:10:120) * 1e3;        % Hz
num_points = length(freq_steps);
sim_time = 0.03;                       % s

f_design = 100e3;                      % fixed hardware design frequency
P_design = target_power * headroom_factor;

%% --- 2. PARAMETERS ---

% A. Semiconductor Profiles
[semi.hv, semi.lv] = get_semiconductor_params('SiC_1200V', 'Si_60V');

% Dead-time helper fields (used only to estimate an initial chosen dead time)
if ~isfield(semi.hv,'Rg_ext_on'),    semi.hv.Rg_ext_on = 2.0; end
if ~isfield(semi.hv,'Rg_ext_off'),   semi.hv.Rg_ext_off = 2.0; end
if ~isfield(semi.hv,'R_driver_on'),  semi.hv.R_driver_on = 1.0; end
if ~isfield(semi.hv,'R_driver_off'), semi.hv.R_driver_off = 1.0; end
if ~isfield(semi.hv,'deadtime_sf'),  semi.hv.deadtime_sf = 2.0; end
if ~isfield(semi.hv,'t_dead_min'),   semi.hv.t_dead_min = 50e-9; end
if ~isfield(semi.hv,'t_dead_max'),   semi.hv.t_dead_max = 300e-9; end

if ~isfield(semi.lv,'Rg_ext_on'),    semi.lv.Rg_ext_on = 2.0; end
if ~isfield(semi.lv,'Rg_ext_off'),   semi.lv.Rg_ext_off = 2.0; end
if ~isfield(semi.lv,'R_driver_on'),  semi.lv.R_driver_on = 1.0; end
if ~isfield(semi.lv,'R_driver_off'), semi.lv.R_driver_off = 1.0; end
if ~isfield(semi.lv,'deadtime_sf'),  semi.lv.deadtime_sf = 2.0; end
if ~isfield(semi.lv,'t_dead_min'),   semi.lv.t_dead_min = 20e-9; end
if ~isfield(semi.lv,'t_dead_max'),   semi.lv.t_dead_max = 150e-9; end

% Chosen actual dead time from device/driver data
[t_dead_h_actual, info_dt_h] = estimate_dead_time_from_device(semi.hv);
[t_dead_l_actual, info_dt_l] = estimate_dead_time_from_device(semi.lv);

% B. Passives
passives.Rs = 1e6;
passives.hv.R_cab = 5e-3;   passives.hv.L_cab = 2e-6;   passives.hv.C_bulk = 470e-6;
passives.lv.R_cab = 0.1e-3; passives.lv.L_cab = 100e-9; passives.lv.C_bulk = 4e-3;

% C. Converter / Transformer
trans.V1 = 16;
trans.V2 = 1;
trans.n = trans.V2 / trans.V1;        % n = Ns/Np
trans.Vin = 800;
trans.Vout = 48;

Lm = 0.002;
Rm = 10e3;

trLoss.C_wave  = 1.2;
trLoss.V_core  = 1.2e-4;
trLoss.A_core  = 8e-4;
trLoss.N_pri   = 16;
trLoss.Ks      = 200000;
trLoss.alpha   = 1.6;
trLoss.beta    = 2.2;
trLoss.Rac_pri = 4e-3;
trLoss.Rac_sec = 0.3e-3;

%% --- 2A. FIXED MAGNETIC DESIGN ---
% d is normalized SPS shift, 0 < d < 0.5
d_design = 0.20;

optsSize = struct();
optsSize.Np            = trLoss.N_pri;
optsSize.Bmax_T        = 0.25;
optsSize.Bmax_L        = 0.30;
optsSize.L_margin      = 1.0;
optsSize.A_core_ref_m2 = trLoss.A_core;
optsSize.V_core_ref_m3 = trLoss.V_core;
optsSize.ku_gap        = 0.22;

Sfix = calculate_dab_size_fixed( ...
    'design', f_design, trans.Vin, trans.Vout, P_design, ...
    trans.n, d_design, optsSize);

Lk_fixed = Sfix.L_fixed;
Bmax_T_used = Sfix.Bmax_T;

fprintf('Fixed design @ %.1f kHz | Lk = %.3f uH | Vmag = %.2f cm^3 | Ipk = %.1f A\n', ...
    f_design/1e3, Lk_fixed/1e-6, Sfix.V_total_cm3, Sfix.Ipk_design);

%% --- 3. INITIALIZE RESULT ARRAYS ---
results.freq = zeros(1, num_points);
results.eff_analytical = zeros(1, num_points);
results.eff_worst_case = zeros(1, num_points);
results.loss_total = zeros(1, num_points);
results.breakdown = zeros(6, num_points);   % cond, cables, gate, switching, body, transformer
results.delay = zeros(1, num_points);

results.I_rms_h = zeros(1, num_points);
results.I_rms_l = zeros(1, num_points);
results.I_sw_ss_h = zeros(1, num_points);
results.I_sw_ss_l = zeros(1, num_points);
results.I_peak_h_global = zeros(1, num_points);
results.I_peak_l_global = zeros(1, num_points);

results.zvs_margin_h = zeros(1, num_points);
results.zvs_margin_l = zeros(1, num_points);
results.t_trans_h = zeros(1, num_points);
results.t_trans_l = zeros(1, num_points);

results.Vol_L = zeros(1, num_points);
results.Vol_T = zeros(1, num_points);
results.Vol_Total = zeros(1, num_points);

data_loss_core   = zeros(1, num_points);
data_loss_tr_cu  = zeros(1, num_points);
data_loss_tr_tot = zeros(1, num_points);
data_loss_body   = zeros(1, num_points);
data_loss_body_h = zeros(1, num_points);
data_loss_body_l = zeros(1, num_points);

data_Lk = zeros(1, num_points);
data_Rm = zeros(1, num_points);

data_Bpk_T   = zeros(1, num_points);
data_Ac_T    = zeros(1, num_points);
data_VT_core = zeros(1, num_points);
data_VL_core = zeros(1, num_points);
data_sat_T   = false(1, num_points);
data_sat_L   = false(1, num_points);

%% --- 4. PUSH STATIC PARAMS TO BASE WORKSPACE ---
assignin('base','R_on_h', semi.hv.Ron);
assignin('base','R_on_l', semi.lv.Ron);

assignin('base','R_d_h',  semi.hv.Rd);
assignin('base','R_d_l',  semi.lv.Rd);
assignin('base','V_f_h',  semi.hv.Vf);
assignin('base','V_f_l',  semi.lv.Vf);
assignin('base','Q_g_h',  semi.hv.Qg);
assignin('base','Q_g_l',  semi.lv.Qg);
assignin('base','V_gs_h', semi.hv.V_dr_on);
assignin('base','V_gs_l', semi.lv.V_dr_on);

assignin('base','R_cab_h', passives.hv.R_cab);
assignin('base','L_cab_h', passives.hv.L_cab);
assignin('base','C_bulk_h',passives.hv.C_bulk);
assignin('base','R_cab_l', passives.lv.R_cab);
assignin('base','L_cab_l', passives.lv.L_cab);
assignin('base','C_bulk_l',passives.lv.C_bulk);
assignin('base','R_s', passives.Rs);

assignin('base','V1', trans.V1);
assignin('base','V2', trans.V2);
assignin('base','Vin', trans.Vin);
assignin('base','Vout', trans.Vout);
assignin('base','n', trans.n);

assignin('base','Lm', Lm);
assignin('base','Rm', Rm);
assignin('base','Lk', Lk_fixed);

% Actual chosen dead times pushed to model if needed
assignin('base','t_dead_h_actual', t_dead_h_actual);
assignin('base','t_dead_l_actual', t_dead_l_actual);

% Transformer block mask variables
assignin('base','Tr1', trLoss.Rac_pri);
assignin('base','Tr2', trLoss.Rac_sec);
assignin('base','target_powertrans', P_design);

fprintf('Starting fixed-hardware sweep...\n');

%% --- 5. MAIN SWEEP LOOP ---
for i = 1:num_points
    f_sw_curr = freq_steps(i);
    T_curr = 1 / f_sw_curr;

    assignin('base','T', T_curr);
    assignin('base','Lk', Lk_fixed);
    assignin('base','f_sw_curr', f_sw_curr);

    % Control
    try
        Delay_Sweep = findDABDelay( ...
            trans.Vin, trans.Vout, target_power, trans.n, Lk_fixed, f_sw_curr);
        assignin('base','Delay', Delay_Sweep);
    catch ME
        fprintf('[Control error at %.1f kHz] %s\n', f_sw_curr/1e3, ME.message);
        continue;
    end

    % Simulation
    try
        simOut = sim(model_name, 'StopTime', num2str(sim_time));
    catch ME
        fprintf('\n[SIMULATION CRASH at %.1f kHz]\n', f_sw_curr/1e3);
        disp(ME.message);
        continue;
    end

    % Extract currents
    try
        I_raw_h   = simOut.I_raw_h.Data;
        I_raw_l   = simOut.I_raw_l.Data;
        I_raw_in  = simOut.I_raw_in.Data;
        I_raw_out = simOut.I_raw_out.Data;
    catch
        error('Variable Name Mismatch: Check To Workspace block names.');
    end

    idx = floor(length(I_raw_h) * 0.5);
    I_ss_h   = I_raw_h(idx:end);
    I_ss_l   = I_raw_l(idx:end);
    I_ss_in  = I_raw_in(idx:end);
    I_ss_out = I_raw_out(idx:end);

    I_rms_h   = rms(I_ss_h);
    I_rms_l   = rms(I_ss_l);
    I_rms_in  = rms(I_ss_in);
    I_rms_out = rms(I_ss_out);

    I_sw_ss_h = max(abs(I_ss_h));
    I_sw_ss_l = max(abs(I_ss_l));

    I_peak_h_global = max(abs(I_raw_h));
    I_peak_l_global = max(abs(I_raw_l));

    %% Fixed magnetic evaluation
    d_eval = 2 * f_sw_curr * Delay_Sweep;

    Seval = calculate_dab_size_fixed( ...
        'eval', f_sw_curr, trans.Vin, trans.Vout, target_power, ...
        trans.n, d_eval, Sfix);

    data_Bpk_T(i)   = Seval.Bpk_T;
    data_Ac_T(i)    = Seval.Ac_T_fixed;
    data_VT_core(i) = Seval.V_T_cm3;
    data_VL_core(i) = Seval.V_L_cm3;
    data_sat_T(i)   = Seval.is_sat_T;
    data_sat_L(i)   = Seval.is_sat_L;

    results.Vol_L(i)     = Seval.V_L_cm3;
    results.Vol_T(i)     = Seval.V_T_cm3;
    results.Vol_Total(i) = Seval.V_total_cm3;

    %% Conduction + passive losses
    P_cond_h = 4 * (I_rms_h^2 * semi.hv.Ron);
    P_cond_l = 4 * (I_rms_l^2 * semi.lv.Ron);
    P_cond = P_cond_h + P_cond_l;

    P_cab = 2*(I_rms_in^2 * passives.hv.R_cab) + ...
            2*(I_rms_out^2 * passives.lv.R_cab);

    P_gate = (4 * semi.hv.Qg * semi.hv.V_dr_on * f_sw_curr) + ...
             (4 * semi.lv.Qg * semi.lv.V_dr_on * f_sw_curr);

    %% Switching losses with explicit chosen dead time
   [P_sw_h_unit, zvs_h, t_req_h, E_rat_h] = ...
    calculate_switching_zvs( ...
        trans.Vin, I_sw_ss_h, f_sw_curr, Lk_fixed, semi.hv, t_dead_h_actual);

[P_sw_l_unit, zvs_l, t_req_l, E_rat_l] = ...
    calculate_switching_zvs( ...
        trans.Vout, I_sw_ss_l, f_sw_curr, Lk_fixed*(trans.n^2), semi.lv, t_dead_l_actual);

P_sw_total = 4 * P_sw_h_unit + 4 * P_sw_l_unit;

    % Worst-case rough comparison
    P_sw_wc = 4 * f_sw_curr * 0.5 * (trans.Vin * I_rms_h + trans.Vout * I_rms_l) * ...
              (t_dead_h_actual + t_dead_l_actual);

    %% Analytical dead-time conduction loss (DAB-consistent)
[P_body, P_body_h, P_body_l, info_body] = calculateBodyDiodeLosses_DAB( ...
    I_sw_ss_h, I_sw_ss_l, ...
    semi.hv.Vf, semi.lv.Vf, ...
    f_sw_curr, ...
    t_dead_h_actual, t_dead_l_actual, ...
    zvs_h, zvs_l, ...
    t_req_h, t_req_l);

    data_loss_body(i)   = P_body;
    data_loss_body_h(i) = P_body_h;
    data_loss_body_l(i) = P_body_l;

    %% Transformer losses with fixed geometry
    [P_core, P_cu, P_tr, Rm_dyn, ~] = calculateTransformerLosses_fixed( ...
        f_sw_curr, trans.Vin, I_rms_h, I_rms_l, ...
        trLoss.V_core, trLoss.A_core, trLoss.N_pri, ...
        trLoss.Ks, trLoss.alpha, trLoss.beta, ...
        trLoss.Rac_pri, trLoss.Rac_sec, trLoss.C_wave, true);

    data_loss_core(i)   = P_core;
    data_loss_tr_cu(i)  = P_cu;
    data_loss_tr_tot(i) = P_tr;
    data_Lk(i)          = Lk_fixed;
    data_Rm(i)          = Rm_dyn;

    %% Store results
    results.freq(i) = f_sw_curr;
    results.loss_total(i) = P_cond + P_cab + P_gate + P_sw_total + P_body + P_tr;
    results.eff_analytical(i) = 100 * target_power / (target_power + results.loss_total(i));
    results.eff_worst_case(i) = 100 * target_power / (target_power + P_cond + P_cab + P_gate + P_sw_wc);
    results.breakdown(:, i) = [P_cond; P_cab; P_gate; P_sw_total; P_body; P_tr];
    results.delay(i) = Delay_Sweep;

    results.I_rms_h(i) = I_rms_h;
    results.I_rms_l(i) = I_rms_l;
    results.I_sw_ss_h(i) = I_sw_ss_h;
    results.I_sw_ss_l(i) = I_sw_ss_l;
    results.I_peak_h_global(i) = I_peak_h_global;
    results.I_peak_l_global(i) = I_peak_l_global;

    results.zvs_margin_h(i) = E_rat_h;
    results.zvs_margin_l(i) = E_rat_l;
    results.t_trans_h(i)    = t_req_h;
    results.t_trans_l(i)    = t_req_l;

    fprintf(' %.1f kHz | Lk = %.2f uH | Eff = %.2f%% | ZVS H:%d L:%d | Bpk = %.3f T | td_h = %.1f ns | td_l = %.1f ns\n', ...
        f_sw_curr/1e3, Lk_fixed/1e-6, results.eff_analytical(i), ...
        zvs_h, zvs_l, Seval.Bpk_T, t_dead_h_actual*1e9, t_dead_l_actual*1e9);
end

%% --- 6. PLOTTING PREP ---
valid = results.freq > 0 & ~isnan(results.eff_analytical);
if ~any(valid)
    error('No valid sweep points completed. All simulations failed.');
end

f_kHz = results.freq(valid)/1e3;
[f_kHz, idxS] = sort(f_kHz);

% Core summary
effA     = results.eff_analytical(valid); effA     = effA(idxS);
effW     = results.eff_worst_case(valid); effW     = effW(idxS);
lossTot  = results.loss_total(valid);     lossTot  = lossTot(idxS);
delay_us = results.delay(valid)*1e6;      delay_us = delay_us(idxS);

% Current stress
I_rms_h_p = results.I_rms_h(valid);          I_rms_h_p = I_rms_h_p(idxS);
I_rms_l_p = results.I_rms_l(valid);          I_rms_l_p = I_rms_l_p(idxS);
I_pk_h    = results.I_peak_h_global(valid);  I_pk_h    = I_pk_h(idxS);
I_pk_l    = results.I_peak_l_global(valid);  I_pk_l    = I_pk_l(idxS);

% ZVS physics
zvsM_h = results.zvs_margin_h(valid);  zvsM_h = zvsM_h(idxS);
zvsM_l = results.zvs_margin_l(valid);  zvsM_l = zvsM_l(idxS);
tReq_h = results.t_trans_h(valid)*1e9; tReq_h = tReq_h(idxS);
tReq_l = results.t_trans_l(valid)*1e9; tReq_l = tReq_l(idxS);

% Magnetic volumes (already in cm^3)
VolL   = results.Vol_L(valid);       VolL   = VolL(idxS);
VolT   = results.Vol_T(valid);       VolT   = VolT(idxS);
VolTot = results.Vol_Total(valid);   VolTot = VolTot(idxS);

% Transformer losses
Pcore = data_loss_core(valid);   Pcore = Pcore(idxS);
Pcu   = data_loss_tr_cu(valid);  Pcu   = Pcu(idxS);
Ptr   = data_loss_tr_tot(valid); Ptr   = Ptr(idxS);

% Magnetic state
Bpk = data_Bpk_T(valid); Bpk = Bpk(idxS);
sat = data_sat_T(valid); sat = sat(idxS);

Ac_fixed_cm2 = data_Ac_T(valid) * 1e4;   % m^2 -> cm^2
Ac_fixed_cm2 = Ac_fixed_cm2(idxS);

VT = data_VT_core(valid); VT = VT(idxS); % cm^3
VL = data_VL_core(valid); VL = VL(idxS); % cm^3

% Loss breakdown
BD = results.breakdown(:,valid);
BD = BD(:,idxS);
LossMat = [BD(1,:)' BD(2,:)' BD(3,:)' BD(4,:)' BD(5,:)' BD(6,:)'];

%% --- 7. FIGURE 1: OVERVIEW ---
figure('Color','w', 'Name', 'DAB Overview', 'Position', [50 50 1100 650]);
tiledlayout(2,2,'Padding','compact','TileSpacing','compact');

nexttile;
plot(f_kHz, effA, 'o-','LineWidth',2,'MarkerSize',6); hold on;
plot(f_kHz, effW, '--','LineWidth',1.5);
grid on;
xlabel('Frequency (kHz)');
ylabel('Efficiency (%)');
legend('ZVS-aware','Worst-case','Location','best');
title('Efficiency vs Frequency');

nexttile;
plot(f_kHz, lossTot, 'o-','LineWidth',2,'MarkerSize',6);
grid on;
xlabel('Frequency (kHz)');
ylabel('Total Loss (W)');
title('Total Loss vs Frequency');

nexttile;
bar(f_kHz, LossMat, 'stacked');
grid on;
xlabel('Frequency (kHz)');
ylabel('Loss (W)');
legend('Cond','Cables','Gate','Switching','Body diode','Transformer','Location','best');
title('Loss Breakdown (Absolute)');

nexttile;
plot(f_kHz, delay_us, 's-','LineWidth',2,'MarkerSize',6); hold on;
plot(f_kHz, (1./(f_kHz*1e3)/4)*1e6, '--','LineWidth',1.3);
grid on;
xlabel('Frequency (kHz)');
ylabel('Delay (\mus)');
legend('Required delay','T/4 reference','Location','best');
title('Control Effort');

%% --- 8. FIGURE 2: CURRENT STRESS ---
figure('Color','w', 'Name', 'Current Stress', 'Position', [100 100 950 420]);
tiledlayout(1,2,'Padding','compact','TileSpacing','compact');

nexttile;
yyaxis left;
plot(f_kHz, I_rms_h_p, 'o-','LineWidth',2,'MarkerSize',6);
ylabel('I_{RMS} (A)');
yyaxis right;
plot(f_kHz, I_pk_h, '^-','LineWidth',1.7,'MarkerSize',6);
ylabel('I_{Peak} (A)');
grid on;
xlabel('Frequency (kHz)');
title('HV Side');

nexttile;
yyaxis left;
plot(f_kHz, I_rms_l_p, 'o-','LineWidth',2,'MarkerSize',6);
ylabel('I_{RMS} (A)');
yyaxis right;
plot(f_kHz, I_pk_l, '^-','LineWidth',1.7,'MarkerSize',6);
ylabel('I_{Peak} (A)');
grid on;
xlabel('Frequency (kHz)');
title('LV Side');

%% --- 9. FIGURE 3: ZVS PHYSICS ---
figure('Color','w', 'Name', 'ZVS Physics', 'Position', [150 150 1050 420]);
tiledlayout(1,2,'Padding','compact','TileSpacing','compact');

nexttile;
semilogy(f_kHz, zvsM_h, 'o-','LineWidth',2,'MarkerSize',6); hold on;
semilogy(f_kHz, zvsM_l, 's-','LineWidth',2,'MarkerSize',6);
yline(1,'--','LineWidth',1.5);
grid on;
xlabel('Frequency (kHz)');
ylabel('E_{avail}/E_{req}');
legend('HV','LV','Threshold = 1','Location','best');
title('ZVS Energy Margin');

nexttile;
plot(f_kHz, tReq_h, 'o-','LineWidth',2,'MarkerSize',6); hold on;
plot(f_kHz, tReq_l, 's-','LineWidth',2,'MarkerSize',6);
grid on;
xlabel('Frequency (kHz)');
ylabel('t_{req} (ns)');
legend('HV','LV','Location','best');
title('Transition Time Needed');

%% --- 10. FIGURE 4: MAGNETIC SIZE + PARETO ---
figure('Color','w', 'Name', 'Magnetics Size & Pareto', 'Position', [200 200 1050 420]);
tiledlayout(1,2,'Padding','compact','TileSpacing','compact');

nexttile;
plot(f_kHz, VolL, 'o-','LineWidth',1.7,'MarkerSize',6); hold on;
plot(f_kHz, VolT, 's-','LineWidth',1.7,'MarkerSize',6);
plot(f_kHz, VolTot, '-','LineWidth',2.2);
grid on;
xlabel('Frequency (kHz)');
ylabel('Volume (cm^3)');
legend('Inductor','Transformer','Total','Location','best');
title('Magnetic Component Volume');

nexttile;
scatter(VolTot, effA, 55, f_kHz, 'filled');
grid on;
xlabel('Total Magnetic Volume (cm^3)');
ylabel('Efficiency (%)');
title('Pareto: Size vs Efficiency');
cb = colorbar;
cb.Label.String = 'Frequency (kHz)';

%% --- 11. FIGURE 5: TRANSFORMER LOSS ---
figure('Color','w', 'Name', 'Transformer Loss', 'Position', [250 250 900 380]);
plot(f_kHz, Pcore, 'o-','LineWidth',2,'MarkerSize',6); hold on;
plot(f_kHz, Pcu,   's-','LineWidth',2,'MarkerSize',6);
plot(f_kHz, Ptr,   'd-','LineWidth',2.3,'MarkerSize',6);
grid on;
xlabel('Frequency (kHz)');
ylabel('Loss (W)');
legend('Core','Copper','Total','Location','best');
title('Transformer Loss vs Frequency');

%% --- 12. FIGURE 6: LOSS BREAKDOWN (%) ---
figure('Color','w', 'Name', 'Loss Breakdown (%)', 'Position', [300 300 950 420]);
LossMatPct = 100 * LossMat ./ max(sum(LossMat,2), 1e-12);
bar(f_kHz, LossMatPct, 'stacked');
grid on;
xlabel('Frequency (kHz)');
ylabel('Loss Share (%)');
legend('Cond','Cables','Gate','Switching','Body diode','Transformer','Location','best');
title('Loss Breakdown (Percentage)');

%% --- 13. FIGURE 7: TRANSFORMER Bpk ---
figure('Color','w', 'Name', 'Transformer Flux (Bpk)', 'Position', [350 120 900 420]);
plot(f_kHz, Bpk, 'o-','LineWidth',2,'MarkerSize',6); hold on;
yline(Bmax_T_used, '--','LineWidth',1.8);
grid on;
xlabel('Frequency (kHz)');
ylabel('B_{pk} (T)');
title('Transformer Peak Flux Density vs Frequency');
legend('B_{pk}','B_{max} target','Location','best');

if any(sat)
    scatter(f_kHz(sat), Bpk(sat), 80, 'filled');
    legend('B_{pk}','B_{max} target','Saturated/Invalid','Location','best');
end

%% --- 14. FIGURE 8: TRANSFORMER CORE AREA ---
figure('Color','w', 'Name', 'Transformer Core Area', 'Position', [380 150 900 420]);
plot(f_kHz, Ac_fixed_cm2, 's-','LineWidth',2,'MarkerSize',6);
grid on;
xlabel('Frequency (kHz)');
ylabel('A_c fixed (cm^2)');
title('Transformer Core Cross-Section');

%% --- 15. FIGURE 9: CORE / MAGNETIC VOLUMES ---
figure('Color','w', 'Name', 'Core Volumes (Sizing)', 'Position', [410 180 1000 420]);
tiledlayout(1,2,'Padding','compact','TileSpacing','compact');

nexttile;
plot(f_kHz, VT, 'o-','LineWidth',2,'MarkerSize',6);
grid on;
xlabel('Frequency (kHz)');
ylabel('Transformer Volume (cm^3)');
title('Transformer Volume');

nexttile;
plot(f_kHz, VL, 'o-','LineWidth',2,'MarkerSize',6);
grid on;
xlabel('Frequency (kHz)');
ylabel('Inductor Volume (cm^3)');
title('Inductor Volume');
pdf_file = 'DAB_frequency_sweep_results.pdf';

if exist(pdf_file,'file')
    delete(pdf_file);
end

figs = findall(0,'type','figure');

for k = length(figs):-1:1
    exportgraphics(figs(k), pdf_file, ...
        'Append', true, ...
        'ContentType','vector');
end

disp(['All figures saved to: ', pdf_file])