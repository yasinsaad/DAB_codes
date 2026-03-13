%% DAB Frequency Sweep: Complete Analysis (Final Version)
% Features: Struct-based params, Physics-based ZVS (Time+Energy), Advanced Plotting.
clear; clc; close all;

%% --- 1. CONFIGURATION ---
model_name = 'DAB_freq_sweep_sim'; 
power.target = 25000;              % 25 kW Nominal
headroom_factor = 1.3;             % Design for 30 kW Peak
freq_steps = (70:10:90) * 1e3;    % Frequency Sweep (10kHz to 180kHz)
num_sweep = length(freq_steps);
sim_time = 0.16;
max_power = headroom_factor*power.target;
%% --- 2. PARAMETERS ---


% B. Load Semiconductor Profiles (Embedded Local Function)
[semi.hv, semi.lv] = get_semiconductor_params('SiC_1200V', 'Si_60V');

%dead time incorporated in get_semiconductor_params


% C. Passives
passives.Rs = 1e6; %snubber resistance
passives.hv.R_cab = 5e-3;   passives.hv.L_cab = 2e-6;   passives.hv.C_bulk = 470e-6;
passives.lv.R_cab = 0.1e-3; passives.lv.L_cab = 100e-9; passives.lv.C_bulk = 4e-3;

% D. Transformer
trans.V1 = 16; trans.V2 = 1; trans.n = trans.V2/trans.V1;
trans.power = max_power;
% Source
source.Vin = 800; source.Vout = 48;


% --- Magnetization branch initialization (CRITICAL) ---
trans.Lm = 1e6;        % H (constant magnetizing inductance)
trans.Rm = 1e6;          % Ohm (dummy initial value, overwritten later) @saquib, not overwritten later. also provide source-
%very high value of rm and lm taken in simulation block as recommended by bhai, isnt a dummy as rym is not dyamic anymore
trans.R1=0.075; % @saquib what are these? source? 
%from krismer dab model i got rac for primary and secondary, tr1 and tr2 are dc winding res for transformer simulation block , which i scaled from rac
trans.R2=6e-6;
% --- Core parameters (you already have these) --- 
% these may be redundant. Also source needed
% @saquib
%these are needed for my transformer loss calculations,source E 140/68/40 Core
trans.V_core = 5.00045e-3; %in m3
trans.A_core = 1.585e-3;   %in m2
trans.N_pri  = 16;

% --- Material point (you already have these) --- @saquib source ??!
%source is SIFERRIT material N97 i have calculated all these from the graphs 
trans.Ks    = 1.96e4;  
trans.alpha = 1.15;
trans.beta  = 2.32;
trans.C_wave = 1.25;
% --- Winding AC resistances (YOU MUST SET THESE properly) --- @saquib source ??!
%source krismer page 311
trans.Rac_pri =  149e-3;
trans.Rac_sec = 1e-5;

% --- Initialize Data Arrays ---
results.freq = zeros(1, num_sweep);
results.eff_analytical = zeros(1, num_sweep);
results.eff_worst_case = zeros(1, num_sweep);
results.loss_total = zeros(1, num_sweep);
results.breakdown = zeros(6, num_sweep);

results.coreLoss   = zeros(1, num_sweep);
results.copperLoss  = zeros(1, num_sweep);
results.totalTransformerLoss = zeros(1, num_sweep);
results.Lk = zeros(1, num_sweep);


% Current Metrics
results.I_rms_h = zeros(1, num_sweep);
results.I_rms_l = zeros(1, num_sweep);
results.I_sw_ss_h = zeros(1, num_sweep); % Switching Instant Current
results.I_sw_ss_l = zeros(1, num_sweep);


results.t_req_h = zeros(1, num_sweep);    % Required Transition Time
results.t_req_l = zeros(1, num_sweep);
% --- Magnetic Sizing Data ---
results.Vol_L = zeros(1, num_sweep);      % Inductor Volume
results.Vol_T = zeros(1, num_sweep);      % Transformer Volume
results.Vol_Total = zeros(1, num_sweep);  % Total Volume
%Body diode losses
data_loss_body = zeros(1, num_sweep);
data_loss_body_h = zeros(1, num_sweep);
data_loss_body_l = zeros(1, num_sweep);

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



fprintf('Starting Sweep (Target: %.1f kW)...\n', power.target/1e3);

%% --- 3. MAIN SWEEP LOOP ---
for i = 1:num_sweep
    f_sw_curr = freq_steps(i);
    T = 1 / f_sw_curr;
    
    %% A. Inductor Parameters Calculation
  inductor = get_inductor_params(source, trans, f_sw_curr, max_power); 
     
    %% B. Control Calculation
    % not needed for closed loop
%     try
%         Delay_Sweep = findDABDelay(source.Vin, source.Vin, power.target, trans.n, Lk_opt, f_sw_curr);
%         assignin('base', 'Delay', Delay_Sweep); 
%         
%     catch
%         fprintf(' [Error] Control calc failed at %.1f kHz\n', f_sw_curr/1e3);
%         continue;
%     end
%     
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
    
    % Steady State Slice (Last 80%)
    idx = floor(length(I_raw_h) * 0.8);
    I_ss_h = I_raw_h(idx:end); I_ss_l = I_raw_l(idx:end);
    I_ss_in = I_raw_in(idx:end); I_ss_out = I_raw_out(idx:end);
    
    % Metrics
    I_rms_h = rms(I_ss_h); I_rms_l = rms(I_ss_l);
    I_rms_in = rms(I_ss_in); I_rms_out = rms(I_ss_out);
    
    % Switching Peaks (Steady State)
    I_sw_ss_h = max(abs(I_ss_h)); 
    I_sw_ss_l = max(abs(I_ss_l)); 
    
    % Global Peaks (Transient) % not needed actually
    I_peak_h_global = max(abs(I_raw_h));
    I_peak_l_global = max(abs(I_raw_l));
    
    % --- 1. Conduction & Passive Losses ---
    power.loss.conduction = 4*(I_rms_h^2 * semi.hv.Ron) + 4*(I_rms_l^2 * semi.lv.Ron);
    power.loss.cable  = 2*(I_rms_in^2 * passives.hv.R_cab) + 2*(I_rms_out^2 * passives.lv.R_cab);
    power.loss.gateDrive = (4 * semi.hv.Qg * semi.hv.V_dr_on * f_sw_curr) + ...
             (4 * semi.lv.Qg * semi.lv.V_dr_on * f_sw_curr);
    power.loss.inductorDC = I_rms_in^2 * inductor.Rdc;
    
    % --- 2. Switching Losses (Analytical w/ ZVS & Time Check) ---
    % HV Side
    [P_sw_h_unit, zvs_h, t_req_h, E_rat_h] = calculate_switching_zvs(source.Vin, I_sw_ss_h, f_sw_curr, inductor.Lk, semi.hv, semi.hv.timing.t_dead);
    % LV Side (Reflect Lk by MULTIPLYING n^2)
    [P_sw_l_unit, zvs_l, t_req_l, ~] = calculate_switching_zvs(source.Vout, I_sw_ss_l, f_sw_curr, inductor.Lk * (trans.n^2), semi.lv, semi.lv.timing.t_dead);
    
    P_sw_total = 4 * P_sw_h_unit + 4 * P_sw_l_unit;
    
%     % --- 3. Worst Case Reference ---
%     P_sw_wc = 4 * f_sw_curr * 0.5 * (source.Vin * I_rms_h + source.Vin * I_rms_l) * ...
%               (semi.timing.t_dead_on + semi.timing.t_dead_off);
%     t_dead_total = semi.timing.t_dead_on + semi.timing.t_dead_off;

% Body diode losses (use commutation current, not RMS)
[P_body, P_body_h, P_body_l, info] = calculateBodyDiodeLosses( ...
    I_comm_h, I_comm_l, V_f_h, V_f_l, f_sw, ...
    t_dead_actual_h, t_dead_actual_l, ...
    is_zvs_h, is_zvs_l, ...
    t_trans_needed_h, t_trans_needed_l) % @saquib does commutation current == maximum ss current? Also check function calling, set dead_time consts and what is t_trans_??
   % Commutation current is not the maximum steady-state current.I_comm_h and I_comm_l should be the instantaneous bridge/leg current at the exact commutation moment,
%t_trans_needed_h and t_trans_needed_l are the commutation-transition times needed for the switch node to actually move from one rail to the other during dead time
data_loss_body(i)   = P_body;
data_loss_body_h(i) = P_body_h;
data_loss_body_l(i) = P_body_l;

   % --- 4.Transformer Losses ---  
[P_core, P_cu, P_tr, B_pk, k_fe] = calculateTransformerLosses( ...
    f_sw, Vin, Ipri_rms, Isec_rms, ...
    V_core_fixed, A_core_fixed, N_pri, ...
    Ks_ref, alpha, beta, ...
    Rac_pri, Rac_sec, C_wave)
%fixed calling

results.coreLoss(i) = P_core;        % Core loss
results.copperLoss(i) = P_cu;         % Copper loss
results.totalTransformerLoss(i) = P_trans;        % Total transformer loss     
results.Lk(i) = inductor.Lk;  % Store leakage inductance
    % --- Store Results ---
    power.delivered = source.Vout*I_rms_out;
    power.supplied = source.Vin*I_rms_in;
    results.freq(i) = f_sw_curr;
  results.loss_total(i) = power.loss.conduction + power.loss.cable + power.loss.gateDrive + P_sw_total + P_body + P_trans +power.loss.inductorDC;
    results.eff_analytical(i) = 100 * power.delivered / power.supplied;
    test = 100*(power.supplied-power.delivered)/results.loss_total(i);
    
    results.breakdown(:, i) = [power.loss.conduction; power.loss.cable; power.loss.gateDrive; P_sw_total; P_body; power.loss.inductorDC];
    
    % Save Metrics for Plotting
    results.I_rms_h(i) = I_rms_h;
    results.I_rms_l(i) = I_rms_l;
    results.I_sw_ss_h(i) = I_sw_ss_h;
    results.I_sw_ss_l(i) = I_sw_ss_l;
    
    
    % Save Physics Metrics
   
    results.t_req_h(i) = t_req_h;
    results.t_req_l(i) = t_req_l;

    % --- Calculate Magnetic Size ---
    % Conversion: Phase(rad) = Delay(ratio) * pi or Delay(sec) * 2*pi*f
    % Assuming 'Delay_Sweep' from findDABDelay is in SECONDS:
%     phase_rad = Delay_Sweep * 2 * pi * f_sw_curr;
%     
%     [v_L, v_T, v_tot, ~] = dab_size_calc(f_sw_curr, source.Vin, source.Vin, ...
%                                          power.target, trans.n, phase_rad, I_peak_h_global); 
%% @sahib @saquib, this fcn needs to be reworked. We are using a closed loop control, hence no delay param. Also Lk is already calculated, why recalculate it?
%                                      
%     results.Vol_L(i) = v_L * 1e6;     % Convert m^3 to cm^3 for easier reading
%     results.Vol_T(i) = v_T * 1e6;     % Convert m^3 to cm^3
%     results.Vol_Total(i) = v_tot * 1e6;
%     
    fprintf('%.3f| %.1f kHz | Lk:%.1fuH | I_sw: %.1fA | Eff: %.2f%% | ZVS: H:%d L:%d\n', ...
       test, f_sw_curr/1e3, inductor.Lk/1e-6, I_sw_ss_l, results.eff_analytical(i), zvs_h, zvs_l);
    
    plot(simOut.tout,I_raw_out);
    title("%.2f kHz", f_sw_curr*1e-3);
    
     exportgraphics(gcf, "current_plots.pdf", ...
        'Append', true, ...
        'ContentType','image');
    close
end


%% --- 4. PLOTTING RESULTS ---
% Convert frequency to kHz for readability
freq_kHz = results.freq / 1e3;

% Plot 1: Efficiency vs Frequency
figure('Name', 'Efficiency vs Frequency', 'Color', 'w');
plot(freq_kHz, results.eff_analytical, '-o', 'LineWidth', 2);
xlabel('Frequency (kHz)');
ylabel('Efficiency (%)');
title('Efficiency vs Frequency');
grid on;

% Plot 2: Total Loss vs Frequency
figure('Name', 'Total Loss vs Frequency', 'Color', 'w');
plot(freq_kHz, results.loss_total, '-o', 'LineWidth', 2, 'Color', '#D95319');
xlabel('Frequency (kHz)');
ylabel('Total Loss (W)');
title('Total System Loss vs Frequency');
grid on;

% Plot 3: Individual Losses vs Frequency
figure('Name', 'Loss Breakdown vs Frequency', 'Color', 'w');
hold on;
plot(freq_kHz, results.breakdown(1, :), '-x', 'LineWidth', 1.5, 'DisplayName', 'Conduction Loss');
plot(freq_kHz, results.breakdown(2, :), '-x', 'LineWidth', 1.5, 'DisplayName', 'Cable Loss');
plot(freq_kHz, results.breakdown(3, :), '-x', 'LineWidth', 1.5, 'DisplayName', 'Gate Drive Loss');
plot(freq_kHz, results.breakdown(4, :), '-x', 'LineWidth', 1.5, 'DisplayName', 'Switching Loss');
plot(freq_kHz, results.breakdown(5, :), '-x', 'LineWidth', 1.5, 'DisplayName', 'Body Diode Loss');
plot(freq_kHz, results.breakdown(6, :), '-x', 'LineWidth', 1.5, 'DisplayName', 'Inductor DC Loss');
plot(freq_kHz, results.totalTransformerLoss, '-x', 'LineWidth', 1.5, 'DisplayName', 'Transformer Loss');
hold off;

xlabel('Frequency (kHz)');
ylabel('Loss (W)');
title('Individual Loss Components vs Frequency');
legend('Location', 'best');
grid on;
