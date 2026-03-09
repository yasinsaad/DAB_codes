%% DAB Frequency Sweep: Complete Analysis (Final Version)
% Features: Struct-based params, Physics-based ZVS (Time+Energy), Advanced Plotting.
clear; clc; close all;

%% --- 1. CONFIGURATION ---
model_name = 'DAB_freq_sweep_sim'; 
target_power = 25000;              % 25 kW Nominal
headroom_factor = 1.2;             % Design for 30 kW Peak
freq_steps = (10:10:120) * 1e3;    % Frequency Sweep (10kHz to 180kHz)
num_points = length(freq_steps);
sim_time = 0.03;

%% --- 2. PARAMETERS ---

% A. Semiconductor Global Timing
semi.timing.t_dead_on  = 30e-9;
semi.timing.t_dead_off = 90e-9;

% B. Load Semiconductor Profiles (Embedded Local Function)
[semi.hv, semi.lv] = get_semiconductor_params('SiC_1200V', 'Si_60V');

% C. Passives
passives.Rs = 1e6; 
passives.hv.R_cab = 5e-3;   passives.hv.L_cab = 2e-6;   passives.hv.C_bulk = 470e-6;
passives.lv.R_cab = 0.1e-3; passives.lv.L_cab = 100e-9; passives.lv.C_bulk = 4e-3;

% D. Transformer
trans.V1 = 16; trans.V2 = 1; trans.n = trans.V2/trans.V1;
trans.Vin = 800; trans.Vout = 48;


% --- Magnetization branch initialization (CRITICAL) ---
Lm = 1e6;        % H (constant magnetizing inductance)
Rm = 1e6;          % Ohm (dummy initial value, overwritten later)
Tr1=0.004;
Tr2=0.003;
target_powertrans = 30000;
% --- Core parameters (you already have these) ---
trLoss.V_core = 1.2e-4;
trLoss.A_core = 8e-4;
trLoss.N_pri  = 16;

% --- Material point (you already have these) ---
trLoss.Ks    = 200000;  
trLoss.alpha = 1.6;
trLoss.beta  = 2.2;

% --- Winding AC resistances (YOU MUST SET THESE properly) ---
trLoss.Rac_pri = 4e-3;
trLoss.Rac_sec = 0.3e-3;

% --- Initialize Data Arrays ---
results.freq = zeros(1, num_points);
results.eff_analytical = zeros(1, num_points);
results.eff_worst_case = zeros(1, num_points);
results.loss_total = zeros(1, num_points);
results.breakdown = zeros(5, num_points);
results.delay = zeros(1, num_points);
data_loss_core   = zeros(1, num_points);
data_loss_tr_cu  = zeros(1, num_points);
data_loss_tr_tot = zeros(1, num_points);
data_Lk = zeros(1, num_points);
data_Rm = zeros(1, num_points);

% Current Metrics
results.I_rms_h = zeros(1, num_points);
results.I_rms_l = zeros(1, num_points);
results.I_sw_ss_h = zeros(1, num_points); % Switching Instant Current
results.I_sw_ss_l = zeros(1, num_points);
results.I_peak_h_global = zeros(1, num_points); % Transient
results.I_peak_l_global = zeros(1, num_points);

% ZVS Physics Metrics (For Figure 5)
results.zvs_margin_h = zeros(1, num_points); % Energy Ratio
results.t_trans_h = zeros(1, num_points);    % Required Transition Time

% --- Magnetic Sizing Data ---
results.Vol_L = zeros(1, num_points);      % Inductor Volume
results.Vol_T = zeros(1, num_points);      % Transformer Volume
results.Vol_Total = zeros(1, num_points);  % Total Volume
%Body diode losses
data_loss_body = zeros(1, num_points);
data_loss_body_h = zeros(1, num_points);
data_loss_body_l = zeros(1, num_points);

% --- PUSH PARAMS TO SIMULINK WORKSPACE ---
assignin('base', 'R_on_h', semi.hv.Ron);  assignin('base', 'R_on_l', semi.lv.Ron);
assignin('base', 'R_d_h',  semi.hv.Rd);   assignin('base', 'R_d_l',  semi.lv.Rd);
assignin('base', 'V_f_h',  semi.hv.Vf);   assignin('base', 'V_f_l',  semi.lv.Vf);
assignin('base', 'Q_g_h',  semi.hv.Qg);   assignin('base', 'Q_g_l',  semi.lv.Qg);
assignin('base', 'V_gs_h', semi.hv.V_dr_on); assignin('base', 'V_gs_l', semi.lv.V_dr_on);

assignin('base', 'R_cab_h', passives.hv.R_cab); assignin('base', 'L_cab_h', passives.hv.L_cab);
assignin('base', 'C_bulk_h',passives.hv.C_bulk);
assignin('base', 'R_cab_l', passives.lv.R_cab); assignin('base', 'L_cab_l', passives.lv.L_cab);
assignin('base', 'C_bulk_l',passives.lv.C_bulk);
assignin('base', 'R_s',     passives.Rs);

assignin('base', 'V1', trans.V1);   assignin('base', 'V2', trans.V2);
assignin('base', 'Vin', trans.Vin); assignin('base', 'Vout', trans.Vout);
assignin('base', 'n', trans.n); 
assignin('base','Lm',Lm);
assignin('base','Rm',Rm);

assignin('base', 't_on', semi.timing.t_dead_on); assignin('base', 't_off', semi.timing.t_dead_off);

fprintf('Starting Sweep (Target: %.1f kW)...\n', target_power/1e3);

%% --- 3. MAIN SWEEP LOOP ---
for i = 1:num_points
    f_sw_curr = freq_steps(i);
    T_curr = 1 / f_sw_curr;
    
    %% A. Dynamic Lk Calculation
    P_max_req = target_power * headroom_factor;
    Lk_opt = (trans.Vin * trans.Vout) / (8 * trans.n * f_sw_curr * P_max_req);
    
    assignin('base', 'Lk', Lk_opt);
    assignin('base', 'T', T_curr);
    
    %% B. Control Calculation
    try
        Delay_Sweep = findDABDelay(trans.Vin, trans.Vout, target_power, trans.n, Lk_opt, f_sw_curr);
        assignin('base', 'Delay', Delay_Sweep); 
        
    catch
        fprintf(' [Error] Control calc failed at %.1f kHz\n', f_sw_curr/1e3);
        continue;
    end
    
    %% C. Run Simulation
    try
        simOut = sim(model_name,'StopTime',num2str(sim_time));
    catch ME
        fprintf('\n[SIMULATION CRASH at %.1f kHz]\n', f_sw_curr/1e3);
        disp(ME.message);
        continue;
    end
    
    %% D. Extract Data
    try
        I_raw_h = simOut.I_raw_h.Data; I_raw_l = simOut.I_raw_l.Data;
        I_raw_in = simOut.I_raw_in.Data; I_raw_out = simOut.I_raw_out.Data;
    catch
        error('Variable Name Mismatch: Check "To Workspace" block names!');
    end
    
    % Steady State Slice (Last 50%)
    idx = floor(length(I_raw_h) * 0.5);
    I_ss_h = I_raw_h(idx:end); I_ss_l = I_raw_l(idx:end);
    I_ss_in = I_raw_in(idx:end); I_ss_out = I_raw_out(idx:end);
    
    % Metrics
    I_rms_h = rms(I_ss_h); I_rms_l = rms(I_ss_l);
    I_rms_in = rms(I_ss_in); I_rms_out = rms(I_ss_out);
    
    % Switching Peaks (Steady State)
    I_sw_ss_h = max(abs(I_ss_h)); 
    I_sw_ss_l = max(abs(I_ss_l)); 
    
    % Global Peaks (Transient)
    I_peak_h_global = max(abs(I_raw_h));
    I_peak_l_global = max(abs(I_raw_l));
    
    % --- 1. Conduction & Passive Losses ---
    P_cond = 4*(I_rms_h^2 * semi.hv.Ron) + 4*(I_rms_l^2 * semi.lv.Ron);
    P_cab  = 2*(I_rms_in^2 * passives.hv.R_cab) + 2*(I_rms_out^2 * passives.lv.R_cab);
    P_gate = (4 * semi.hv.Qg * semi.hv.V_dr_on * f_sw_curr) + ...
             (4 * semi.lv.Qg * semi.lv.V_dr_on * f_sw_curr);
    
    % --- 2. Switching Losses (Analytical w/ ZVS & Time Check) ---
    % HV Side
    [P_sw_h_unit, zvs_h, t_req_h, E_rat_h] = calculate_switching_zvs(trans.Vin, I_sw_ss_h, f_sw_curr, Lk_opt, semi.hv, semi.timing.t_dead_on);
    % LV Side (Reflect Lk by MULTIPLYING n^2)
    [P_sw_l_unit, zvs_l, ~, ~] = calculate_switching_zvs(trans.Vout, I_sw_ss_l, f_sw_curr, Lk_opt * (trans.n^2), semi.lv, semi.timing.t_dead_on);
    
    P_sw_total = 4 * P_sw_h_unit + 4 * P_sw_l_unit;
    
    % --- 3. Worst Case Reference ---
    P_sw_wc = 4 * f_sw_curr * 0.5 * (trans.Vin * I_rms_h + trans.Vout * I_rms_l) * ...
              (semi.timing.t_dead_on + semi.timing.t_dead_off);
    t_dead_total = semi.timing.t_dead_on + semi.timing.t_dead_off;

% Body diode losses (use commutation current, not RMS)
[P_body, P_body_h, P_body_l] = calculateBodyDiodeLosses( ...
    I_sw_ss_h, I_sw_ss_l, semi.hv.Vf, semi.lv.Vf, f_sw_curr, t_dead_total);

data_loss_body(i)   = P_body;
data_loss_body_h(i) = P_body_h;
data_loss_body_l(i) = P_body_l;

   % --- 4.Transformer Losses ---  
[P_core, P_cu, P_tr, Rm_dyn, B_pk] = calculateTransformerLosses( ...
    f_sw_curr, trans.Vin, I_rms_h, I_rms_l, ...
    trLoss.V_core, trLoss.A_core, trLoss.N_pri, ...
    trLoss.Ks, trLoss.alpha, trLoss.beta, ...
    trLoss.Rac_pri, trLoss.Rac_sec, true);

assignin('base','Rm',Rm_dyn);

data_loss_core(i) = P_core;        % Core loss
data_loss_tr_cu(i) = P_cu;         % Copper loss
data_loss_tr_tot(i) = P_tr;        % Total transformer loss     
data_Lk(i) = Lk_opt;  % Store leakage inductance
data_Rm(i) = Rm_dyn;  % Store magnetization resistance
    % --- Store Results ---
    results.freq(i) = f_sw_curr;
  results.loss_total(i) = P_cond + P_cab + P_gate + P_sw_total + P_body + P_tr;
    results.eff_analytical(i) = 100 * target_power / (target_power + results.loss_total(i));
    results.eff_worst_case(i) = 100 * target_power / (target_power + P_cond + P_cab + P_gate + P_sw_wc);
    results.breakdown(:, i) = [P_cond; P_cab; P_gate; P_sw_total; P_body];
    results.delay(i) = Delay_Sweep;
    
    % Save Metrics for Plotting
    results.I_rms_h(i) = I_rms_h;
    results.I_rms_l(i) = I_rms_l;
    results.I_sw_ss_h(i) = I_sw_ss_h;
    results.I_sw_ss_l(i) = I_sw_ss_l;
    results.I_peak_h_global(i) = I_peak_h_global;
    results.I_peak_l_global(i) = I_peak_l_global;
    
    % Save Physics Metrics
    results.zvs_margin_h(i) = E_rat_h;
    results.t_trans_h(i) = t_req_h;

    % --- Calculate Magnetic Size ---
    % Conversion: Phase(rad) = Delay(ratio) * pi or Delay(sec) * 2*pi*f
    % Assuming 'Delay_Sweep' from findDABDelay is in SECONDS:
    phase_rad = Delay_Sweep * 2 * pi * f_sw_curr;
    
    [v_L, v_T, v_tot, ~] = dab_size_calc(f_sw_curr, trans.Vin, trans.Vout, ...
                                         target_power, trans.n, phase_rad, I_peak_h_global);
                                     
    results.Vol_L(i) = v_L * 1e6;     % Convert m^3 to cm^3 for easier reading
    results.Vol_T(i) = v_T * 1e6;     % Convert m^3 to cm^3
    results.Vol_Total(i) = v_tot * 1e6;
    
    fprintf(' %.1f kHz | Lk:%.1fuH | I_sw: %.1fA | Eff: %.2f%% | ZVS: H:%d L:%d\n', ...
        f_sw_curr/1e3, Lk_opt/1e-6, I_sw_ss_l, results.eff_analytical(i), zvs_h, zvs_l);
end


%% --- 4. EXTENDED PLOTTING SUITE (CLEAN) ---

% --- Clean valid points (in case some sweep points failed) ---
valid = results.freq > 0 & ~isnan(results.eff_analytical);
f_kHz = results.freq(valid)/1e3;

% Sort by frequency
[ f_kHz, idxS ] = sort(f_kHz);

effA = results.eff_analytical(valid); effA = effA(idxS);
effW = results.eff_worst_case(valid); effW = effW(idxS);
lossTot = results.loss_total(valid);  lossTot = lossTot(idxS);
delay_us = results.delay(valid)*1e6;  delay_us = delay_us(idxS);

I_rms_h = results.I_rms_h(valid); I_rms_h = I_rms_h(idxS);
I_rms_l = results.I_rms_l(valid); I_rms_l = I_rms_l(idxS);
I_pk_h  = results.I_peak_h_global(valid); I_pk_h = I_pk_h(idxS);
I_pk_l  = results.I_peak_l_global(valid); I_pk_l = I_pk_l(idxS);

zvsM = results.zvs_margin_h(valid); zvsM = zvsM(idxS);
tReq = results.t_trans_h(valid)*1e9; tReq = tReq(idxS); % ns

VolL = results.Vol_L(valid); VolL = VolL(idxS);
VolT = results.Vol_T(valid); VolT = VolT(idxS);
VolTot = results.Vol_Total(valid); VolTot = VolTot(idxS);

Pcore = data_loss_core(valid);   Pcore = Pcore(idxS);
Pcu   = data_loss_tr_cu(valid);  Pcu   = Pcu(idxS);
Ptr   = data_loss_tr_tot(valid); Ptr   = Ptr(idxS);

% Breakdown matrix assumed: [Cond; Cab; Gate; Switching; Body]
BD = results.breakdown(:,valid); 
BD = BD(:,idxS);

%% === FIGURE 1: OVERVIEW (4-panels) ===
figure('Color','w', 'Name', 'DAB Overview', 'Position', [50 50 1100 650]);
tiledlayout(2,2,'Padding','compact','TileSpacing','compact');

nexttile;
plot(f_kHz, effA, 'o-','LineWidth',2,'MarkerSize',6); hold on;
plot(f_kHz, effW, '--','LineWidth',1.5);
grid on; xlabel('Frequency (kHz)'); ylabel('Efficiency (%)');
legend('ZVS-aware','Worst-case','Location','best');
title('Efficiency vs Frequency');

nexttile;
plot(f_kHz, lossTot, 'o-','LineWidth',2,'MarkerSize',6);
grid on; xlabel('Frequency (kHz)'); ylabel('Total Loss (W)');
title('Total Loss vs Frequency');

nexttile;
% Stacked bar: add transformer explicitly
LossMat = [BD(1,:)' BD(2,:)' BD(3,:)' BD(4,:)' BD(5,:)' Ptr(:)];
bar(f_kHz, LossMat, 'stacked'); grid on;
xlabel('Frequency (kHz)'); ylabel('Loss (W)');
legend('MOSFET Cond','Cables','Gate','Switching','Body diode','Transformer','Location','best');
title('Loss Breakdown (Absolute)');

nexttile;
plot(f_kHz, delay_us, 's-','LineWidth',2,'MarkerSize',6); hold on;
plot(f_kHz, (1./(f_kHz*1e3)/4)*1e6, '--','LineWidth',1.3);
grid on; xlabel('Frequency (kHz)'); ylabel('Delay (\mus)');
legend('Required delay','T/4 reference','Location','best');
title('Control Effort');

%% === FIGURE 2: CURRENT STRESS ===
figure('Color','w', 'Name', 'Current Stress', 'Position', [100 100 950 420]);
tiledlayout(1,2,'Padding','compact','TileSpacing','compact');

nexttile;
yyaxis left; plot(f_kHz, I_rms_h, 'o-','LineWidth',2,'MarkerSize',6);
ylabel('I_{RMS} (A)');
yyaxis right; plot(f_kHz, I_pk_h, '^-','LineWidth',1.7,'MarkerSize',6);
ylabel('I_{Peak} (A)');
grid on; xlabel('Frequency (kHz)'); title('HV Side');

nexttile;
yyaxis left; plot(f_kHz, I_rms_l, 'o-','LineWidth',2,'MarkerSize',6);
ylabel('I_{RMS} (A)');
yyaxis right; plot(f_kHz, I_pk_l, '^-','LineWidth',1.7,'MarkerSize',6);
ylabel('I_{Peak} (A)');
grid on; xlabel('Frequency (kHz)'); title('LV Side');

%% === FIGURE 3: ZVS PHYSICS ===
figure('Color','w', 'Name', 'ZVS Physics', 'Position', [150 150 950 420]);
tiledlayout(1,2,'Padding','compact','TileSpacing','compact');

nexttile;
semilogy(f_kHz, zvsM, 'o-','LineWidth',2,'MarkerSize',6); hold on;
yline(1,'--','LineWidth',1.5);
grid on; xlabel('Frequency (kHz)'); ylabel('E_{avail}/E_{req}');
title('ZVS Energy Margin (HV)');

nexttile;
plot(f_kHz, tReq, 's-','LineWidth',2,'MarkerSize',6); hold on;
yline(semi.timing.t_dead_on*1e9,'--','LineWidth',1.5);
grid on; xlabel('Frequency (kHz)'); ylabel('t_{req} (ns)');
title('Dead-time Utilization (HV)');

%% === FIGURE 4: MAGNETIC SIZE + PARETO ===
figure('Color','w', 'Name', 'Magnetics Size & Pareto', 'Position', [200 200 1050 420]);
tiledlayout(1,2,'Padding','compact','TileSpacing','compact');

nexttile;
plot(f_kHz, VolL, 'o-','LineWidth',1.7,'MarkerSize',6); hold on;
plot(f_kHz, VolT, 's-','LineWidth',1.7,'MarkerSize',6);
plot(f_kHz, VolTot,'-','LineWidth',2.2);
grid on; xlabel('Frequency (kHz)'); ylabel('Volume (cm^3)');
legend('Inductor','Transformer','Total','Location','best');
title('Magnetic Component Volume');

nexttile;
scatter(VolTot, effA, 55, f_kHz, 'filled');
grid on; xlabel('Total Magnetic Volume (cm^3)'); ylabel('Efficiency (%)');
title('Pareto: Size vs Efficiency'); cb=colorbar; cb.Label.String='Frequency (kHz)';

%% === FIGURE 5: TRANSFORMER LOSSES (one clean plot) ===
figure('Color','w', 'Name', 'Transformer Loss', 'Position', [250 250 900 380]);
plot(f_kHz, Pcore, 'o-','LineWidth',2,'MarkerSize',6); hold on;
plot(f_kHz, Pcu,   's-','LineWidth',2,'MarkerSize',6);
plot(f_kHz, Ptr,   'd-','LineWidth',2.3,'MarkerSize',6);
grid on; xlabel('Frequency (kHz)'); ylabel('Loss (W)');
legend('Core','Copper','Total','Location','best');
title('Transformer Loss vs Frequency');

%% === FIGURE 6 (OPTIONAL but very helpful): LOSS BREAKDOWN IN % ===
figure('Color','w', 'Name', 'Loss Breakdown (%)', 'Position', [300 300 950 420]);

LossMatPct = LossMat ./ sum(LossMat,2) * 100; % per-frequency percentage
bar(f_kHz, LossMatPct, 'stacked'); grid on;
xlabel('Frequency (kHz)'); ylabel('Loss Share (%)');
legend('MOSFET Cond','Cables','Gate','Switching','Body diode','Transformer','Location','best');
title('Loss Breakdown (Percentage)');
