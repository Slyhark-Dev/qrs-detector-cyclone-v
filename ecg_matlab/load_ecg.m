%% LOAD AND VISUALIZE MIT-BIH ECG DATA
% Project: Cardiac arrhythmia detection system - FPGA DE1-SoC
% Universidad Tecnologica del Peru (UTP)
% Stage 2: MATLAB validation with MIT-BIH data

clc; clear; close all;

%% 1. Load record 100 (normal patient, sinus rhythm)
record = '100';
[signal, fs, gain, baseline, n_samples] = read_mitbih(record);

%% 2. Extract channel 1 (MLII - main lead)
ecg = signal(:, 1);
t = (0:n_samples-1) / fs; % time vector in seconds

%% 3. Plot first 10 seconds
figure('Name', 'ECG MIT-BIH Record 100', 'Position', [100 100 900 400]);

samples_10s = 10 * fs;
plot(t(1:samples_10s), ecg(1:samples_10s), 'b', 'LineWidth', 0.8);
xlabel('Time (s)');
ylabel('Amplitude (mV)');
title(['ECG MIT-BIH - Record ' record ' - Lead MLII (first 10 s)']);
grid on;
xlim([0 10]);

%% 4. Plot 3-second detail (to visualize QRS complexes)
figure('Name', 'QRS Detail', 'Position', [100 550 900 400]);

samples_3s = 3 * fs;
plot(t(1:samples_3s), ecg(1:samples_3s), 'b', 'LineWidth', 1.2);
xlabel('Time (s)');
ylabel('Amplitude (mV)');
title(['QRS Detail - Record ' record ' (first 3 s)']);
grid on;
xlim([0 3]);

%% 5. Basic statistics
fprintf('\n--- Record %s statistics ---\n', record);
fprintf('Min value: %.3f mV\n', min(ecg));
fprintf('Max value: %.3f mV\n', max(ecg));
fprintf('Mean: %.3f mV\n', mean(ecg));
fprintf('Std deviation: %.3f mV\n', std(ecg));
fprintf('Dynamic range: %.3f mV\n', max(ecg) - min(ecg));

%% 6. Verify data is consistent with real ECG
% Normal ECG: R peaks between 0.5 and 3.0 mV, rate 60-100 BPM
if max(ecg) > 0.3 && max(ecg) < 5.0
    fprintf('\nVerification: Amplitude within normal ECG range.\n');
else
    fprintf('\nWARNING: Amplitude outside typical ECG range.\n');
end

fprintf('\nLoad ECG completed. MIT-BIH data loaded successfully.\n');
