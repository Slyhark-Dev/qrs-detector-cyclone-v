%% ARRHYTHMIA CLASSIFICATION
% Project: Cardiac arrhythmia detection system - FPGA DE1-SoC
% Universidad Tecnologica del Peru (UTP)
% Stage 2: MATLAB validation with MIT-BIH data
%
% Classification criteria (matches VHDL classifier.vhd FSM):
%   Normal:       60-100 BPM         (code 00, alert 00)
%   Bradycardia:  BPM < 60           (code 01, alert 10)
%   Tachycardia:  BPM > 100          (code 10, alert 10)
%   Atrial Fib:   RR variation > 20% (code 11, alert 11)

clc; clear; close all;

%% 1. Load QRS detection results
if ~isfile('qrs_results.mat')
    error('qrs_results.mat not found. Run detect_qrs.m first.');
end
load('qrs_results.mat');

fprintf('Classifying record %s (%d R-peaks detected)\n', record, length(r_peaks));

%% 2. Calculate RR intervals and BPM
rr_samples = diff(r_peaks);       % RR in samples
rr_seconds = rr_samples / fs;     % RR in seconds
bpm = 60 ./ rr_seconds;           % instantaneous BPM
n_beats = length(bpm);

%% 3. Classify each beat using 4-interval sliding window
% Matches VHDL rr_calculator.vhd (4-interval circular buffer)
buffer_size = 4;
classification = zeros(n_beats, 1);  % 0=normal, 1=bradi, 2=taqui, 3=afib
class_code = zeros(n_beats, 1);      % 2-bit code matching VHDL
alert_level = zeros(n_beats, 1);     % 2-bit alert matching VHDL

for i = 1:n_beats
    % Current BPM
    current_bpm = bpm(i);

    % RR variation (needs at least buffer_size intervals)
    if i >= buffer_size
        % Get last 4 RR intervals
        rr_window = rr_samples(i-buffer_size+1:i);
        rr_mean = mean(rr_window);

        % Variation: max deviation from mean / mean * 100
        rr_variation = max(abs(rr_window - rr_mean)) / rr_mean * 100;
    else
        rr_variation = 0; % not enough data yet
    end

    % Classification logic (matches classifier.vhd FSM priority)
    % AF has highest priority (checked first)
    if rr_variation > 20
        classification(i) = 3; % Atrial Fibrillation
        class_code(i) = 3;     % code 11
        alert_level(i) = 3;    % alert 11
    elseif current_bpm < 60
        classification(i) = 1; % Bradycardia
        class_code(i) = 1;     % code 01
        alert_level(i) = 2;    % alert 10
    elseif current_bpm > 100
        classification(i) = 2; % Tachycardia
        class_code(i) = 2;     % code 10
        alert_level(i) = 2;    % alert 10
    else
        classification(i) = 0; % Normal
        class_code(i) = 0;     % code 00
        alert_level(i) = 0;    % alert 00
    end
end

%% 4. Count classifications
n_normal = sum(classification == 0);
n_bradi  = sum(classification == 1);
n_taqui  = sum(classification == 2);
n_afib   = sum(classification == 3);

fprintf('\n--- Classification Results ---\n');
fprintf('Total beats analyzed: %d\n', n_beats);
fprintf('Normal (60-100 BPM):         %d (%.1f%%)\n', n_normal, n_normal/n_beats*100);
fprintf('Bradycardia (<60 BPM):       %d (%.1f%%)\n', n_bradi, n_bradi/n_beats*100);
fprintf('Tachycardia (>100 BPM):      %d (%.1f%%)\n', n_taqui, n_taqui/n_beats*100);
fprintf('Atrial Fibrillation (RR>20%%): %d (%.1f%%)\n', n_afib, n_afib/n_beats*100);

%% 5. Plot classification over time
t_beats = (r_peaks(2:end)) / fs; % time of each classification

% Color map: Normal=green, Bradi=blue, Taqui=red, AFib=magenta
colors = [0 0.7 0; 0 0 1; 1 0 0; 0.8 0 0.8];
class_names = {'Normal', 'Bradycardia', 'Tachycardia', 'Atrial Fib'};

% Plot 1: BPM with classification colors
figure('Name', 'Arrhythmia Classification', 'Position', [50 50 1000 500]);

subplot(2,1,1);
hold on;
for c = 0:3
    idx = classification == c;
    if any(idx)
        scatter(t_beats(idx), bpm(idx), 15, colors(c+1,:), 'filled');
    end
end
yline(60, 'g--', 'LineWidth', 1.5);
yline(100, 'r--', 'LineWidth', 1.5);
xlabel('Time (s)');
ylabel('BPM');
title(['Heart Rate Classification - Record ' record]);
legend(class_names{ismember(0:3, unique(classification))}, 'Location', 'best');
grid on;
hold off;

% Plot 2: Classification code over time (matches VHDL output)
subplot(2,1,2);
hold on;
for c = 0:3
    idx = classification == c;
    if any(idx)
        scatter(t_beats(idx), class_code(idx), 20, colors(c+1,:), 'filled');
    end
end
xlabel('Time (s)');
ylabel('Classification Code');
title('VHDL Classification Code (00=Normal, 01=Bradi, 10=Taqui, 11=AFib)');
yticks([0 1 2 3]);
yticklabels({'00 Normal', '01 Bradi', '10 Taqui', '11 AFib'});
grid on;
hold off;

% Plot 3: Pie chart distribution
figure('Name', 'Classification Distribution', 'Position', [50 600 500 400]);

counts = [n_normal, n_bradi, n_taqui, n_afib];
valid = counts > 0;
pie(counts(valid));
legend(class_names(valid), 'Location', 'bestoutside');
title(['Beat Classification Distribution - Record ' record]);

%% 6. Generate VHDL-compatible output table
% First 20 beats for verification
fprintf('\n--- First 20 beats (VHDL verification) ---\n');
fprintf('Beat | BPM    | Code | Class\n');
fprintf('-----|--------|------|----------------\n');
for i = 1:min(20, n_beats)
    fprintf('%4d | %6.1f | %02d   | %s\n', i, bpm(i), class_code(i), class_names{classification(i)+1});
end

%% 7. Save results
save('classification_results.mat', 'classification', 'class_code', ...
     'alert_level', 'bpm', 'rr_samples', 'r_peaks', 'fs', 'record', ...
     'n_normal', 'n_bradi', 'n_taqui', 'n_afib');

fprintf('\nResults saved to classification_results.mat\n');
fprintf('classify_arrhythmia completed successfully.\n');
