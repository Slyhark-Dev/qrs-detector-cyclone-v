%% QRS DETECTION - PAN-TOMPKINS CAUSAL (DETECTOR OFICIAL)
% Project: Cardiac arrhythmia detection system - FPGA DE1-SoC
% Universidad Tecnologica del Peru (UTP)
% Stage 2: MATLAB validation with MIT-BIH data
%
% VERSION 2 (CORRECCION ANOMALIA 2): este script ahora usa el detector
% oficial causal pan_tompkins_causal.m (v4-SELFCAL), el mismo validado
% sobre 48 registros en validate_sensitivity.m y usado como referencia
% del VHDL en generate_vhdl_vectors.m.
%
% Este script es ahora un DEMO de visualizacion del detector oficial
% sobre un registro (por defecto el 100): grafica los picos R detectados
% y el BPM, y guarda qrs_results.mat para classify_arrhythmia.m.

clc; clear; close all;

%% 1. Load MIT-BIH record
record = '100';
[signal, fs, ~, ~, n_samples] = read_mitbih(record);
ecg = signal(:, 1); % Channel 1 (MLII)

fprintf('Processing record %s (%d samples, %d Hz)...\n', record, n_samples, fs);

%% 2. QRS detection with the official causal detector
% pan_tompkins_causal.m hace internamente: baseline removal, suavizado,
% derivada, cuadrado, integracion 150 ms, doble umbral adaptativo (SPKI/NPKI),
% searchback, discriminacion de onda T y autocalibracion de lag. TODO causal
% (filter, no filtfilt), por lo que es replicable en VHDL punto fijo.
r_peaks = pan_tompkins_causal(ecg, fs, n_samples);
r_peaks = r_peaks(:);
n_peaks = length(r_peaks);

fprintf('Detected R-peaks: %d (pan_tompkins_causal v4)\n', n_peaks);

%% 3. Calculate RR intervals and BPM
rr_intervals = diff(r_peaks); % in samples
rr_seconds = rr_intervals / fs; % in seconds
bpm = 60 ./ rr_seconds;

fprintf('Mean BPM: %.1f\n', mean(bpm));
fprintf('Min BPM: %.1f\n', min(bpm));
fprintf('Max BPM: %.1f\n', max(bpm));
fprintf('Std BPM: %.1f\n', std(bpm));

%% 4. Plot results
t = (0:n_samples-1) / fs;
samples_10s = 10 * fs;

% Plot 1: Detected R-peaks on original ECG (first 10 seconds)
figure('Name', 'Detected R-peaks', 'Position', [50 50 1000 400]);

plot(t(1:samples_10s), ecg(1:samples_10s), 'b', 'LineWidth', 0.8);
hold on;
% Mark only peaks within first 10 seconds
peaks_10s = r_peaks(r_peaks <= samples_10s);
plot(t(peaks_10s), ecg(peaks_10s), 'rv', 'MarkerSize', 10, 'MarkerFaceColor', 'r');
hold off;
xlabel('Time (s)');
ylabel('Amplitude (mV)');
title(['Detected R-peaks - Record ' record ' (first 10 s, causal detector)']);
legend('ECG', 'R-peaks');
grid on; xlim([0 10]);

% Plot 2: BPM over time
figure('Name', 'Heart Rate', 'Position', [50 50 900 350]);

t_bpm = t(r_peaks(2:end)); % time of each BPM measurement
plot(t_bpm, bpm, 'b.-', 'LineWidth', 1, 'MarkerSize', 8);
xlabel('Time (s)');
ylabel('BPM');
title(['Heart Rate - Record ' record]);
yline(60, 'g--', 'Bradycardia limit');
yline(100, 'r--', 'Tachycardia limit');
legend('BPM', 'Bradycardia (<60)', 'Tachycardia (>100)');
grid on;

%% 5. Save results for next scripts
% classify_arrhythmia.m usa: record, r_peaks, fs (mas rr_intervals y bpm por
% comodidad). Ya NO se guardan senales internas del filtro porque el detector
% causal no las expone y classify_arrhythmia no las necesita.
save('qrs_results.mat', 'r_peaks', 'rr_intervals', 'bpm', 'ecg', 'fs', ...
     'n_samples', 'record');

fprintf('\nResults saved to qrs_results.mat\n');
fprintf('detect_qrs completed successfully.\n');