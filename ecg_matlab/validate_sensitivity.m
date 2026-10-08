%% VALIDATE SENSITIVITY AND SPECIFICITY
% Project: Cardiac arrhythmia detection system - FPGA DE1-SoC
% Universidad Tecnologica del Peru (UTP)
% Stage 2: MATLAB validation with MIT-BIH data
%
% Compares detected R-peaks against MIT-BIH cardiologist annotations
% Calculates: Sensitivity, Positive Predictivity (+P), F1-score
% Runs on the full 48-record database, channel 1, no record exclusions

clc; clear; close all;

%% 1. Configuration
% Full MIT-BIH Arrhythmia Database: 48 records (non-consecutive numbering)
records = {'100','101','102','103','104','105','106','107','108','109', ...
           '111','112','113','114','115','116','117','118','119', ...
           '121','122','123','124', ...
           '200','201','202','203','205','207','208','209','210', ...
           '212','213','214','215','217','219', ...
           '220','221','222','223','228', ...
           '230','231','232','233','234'};
tolerance = round(0.150 * 360); % 150 ms tolerance window (54 samples at 360 Hz)

fprintf('=== MIT-BIH VALIDATION ===\n');
fprintf('Records: %s\n', strjoin(records, ', '));
fprintf('Tolerance window: %d samples (%.0f ms)\n\n', tolerance, tolerance/360*1000);

%% 2. Process each record
results = struct();

for rec = 1:length(records)
    record = records{rec};
    fprintf('--- Processing record %s ---\n', record);

    % Load ECG (both channels are real recordings of the same patient)
    [signal, fs, ~, ~, n_samples] = read_mitbih(record);


    % Read cardiologist annotations (the reference truth)
    ann_peaks = read_annotations(record, n_samples);
    fprintf('Annotated beats: %d\n', length(ann_peaks));

    % LEAD SELECTION: channel 1 only, fixed for every record.
    % Channel 1 is the modified limb lead II (MLII) in 46 of the 48 records
    % and V5 in records 102 and 104, which lack MLII. No per-record choice
    % is made, so the protocol is identical across the whole database.
    ecg_ch = signal(:, 1);
    det_ch = pan_tompkins_causal(ecg_ch, fs, n_samples);
    [TP, FP, FN] = match_peaks(ann_peaks, det_ch, tolerance);

    sensitivity = TP / (TP + FN) * 100;
    pos_predict = TP / (TP + FP) * 100;
    if (sensitivity + pos_predict) > 0
        f1_score = 2 * (sensitivity * pos_predict) / (sensitivity + pos_predict);
    else
        f1_score = 0;
    end

    best_ch = 1;

    % Store results
    results(rec).record = record;
    results(rec).channel = best_ch;
    results(rec).annotated = length(ann_peaks);
    results(rec).detected = length(det_ch);
    results(rec).TP = TP;
    results(rec).FP = FP;
    results(rec).FN = FN;
    results(rec).sensitivity = sensitivity;
    results(rec).pos_predict = pos_predict;
    results(rec).f1_score = f1_score;

    fprintf('Channel: 1 (fixed)\n');
    fprintf('TP=%d, FP=%d, FN=%d\n', TP, FP, FN);
    fprintf('Sensitivity: %.2f%%\n', sensitivity);
    fprintf('+P:          %.2f%%\n', pos_predict);
    fprintf('F1-score:    %.2f%%\n\n', f1_score);
end

%% 3. Summary table (for the paper)
fprintf('=====================================================================\n');
fprintf('                MIT-BIH VALIDATION RESULTS\n');
fprintf('=====================================================================\n');
fprintf('Record | Ch | Annotated | Detected | TP    | FP  | FN  | Se(%%)   | +P(%%)   | F1(%%)\n');
fprintf('-------|----|-----------|----------|-------|-----|-----|---------|---------|--------\n');

total_ann = 0; total_det = 0; total_TP = 0; total_FP = 0; total_FN = 0;

for rec = 1:length(records)
    r = results(rec);
    fprintf('  %s  | %2d | %7d   | %6d   | %5d | %3d | %3d | %6.2f  | %6.2f  | %5.2f\n', ...
        r.record, r.channel, r.annotated, r.detected, r.TP, r.FP, r.FN, ...
        r.sensitivity, r.pos_predict, r.f1_score);

    total_ann = total_ann + r.annotated;
    total_det = total_det + r.detected;
    total_TP = total_TP + r.TP;
    total_FP = total_FP + r.FP;
    total_FN = total_FN + r.FN;
end

% Overall metrics
overall_se = total_TP / (total_TP + total_FN) * 100;
overall_pp = total_TP / (total_TP + total_FP) * 100;
overall_f1 = 2 * (overall_se * overall_pp) / (overall_se + overall_pp);

fprintf('-------|----|-----------|----------|-------|-----|-----|---------|---------|--------\n');
fprintf(' TOTAL |    | %7d   | %6d   | %5d | %3d | %3d | %6.2f  | %6.2f  | %5.2f\n', ...
    total_ann, total_det, total_TP, total_FP, total_FN, ...
    overall_se, overall_pp, overall_f1);
fprintf('=====================================================================\n');

%% 4. Plot results
figure('Name', 'Validation Results', 'Position', [50 50 900 500]);

% Bar chart: Sensitivity and +P per record
subplot(2,1,1);
rec_names = {results.record};
se_vals = [results.sensitivity];
pp_vals = [results.pos_predict];

bar_data = [se_vals; pp_vals]';
b = bar(bar_data);
b(1).FaceColor = [0.2 0.6 0.2];
b(2).FaceColor = [0.2 0.2 0.8];
set(gca, 'XTickLabel', rec_names);
xlabel('MIT-BIH Record');
ylabel('Percentage (%)');
title('Sensitivity and Positive Predictivity per Record');
legend('Sensitivity', '+P', 'Location', 'southwest');
ylim([0 105]);   % full range so hard records (200, 228) are visible
yline(95, 'r--', '95% target', 'LineWidth', 1.5);
grid on;

% TP, FP, FN breakdown
subplot(2,1,2);
fp_vals = [results.FP];
fn_vals = [results.FN];
bar_err = [fp_vals; fn_vals]';
b2 = bar(bar_err);
b2(1).FaceColor = [0.9 0.3 0.1];
b2(2).FaceColor = [0.9 0.7 0.1];
set(gca, 'XTickLabel', rec_names);
xlabel('MIT-BIH Record');
ylabel('Count');
title('False Positives and False Negatives per Record');
legend('False Positives', 'False Negatives', 'Location', 'northwest');
grid on;

%% 5. Detailed plot for one record (first 10 seconds of record 100)
record_detail = '100';
[signal_d, fs_d, ~, ~, n_d] = read_mitbih(record_detail);
ecg_d = signal_d(:, 1);
ann_d = read_annotations(record_detail, n_d);
det_d = pan_tompkins_causal(ecg_d, fs_d, n_d);

figure('Name', 'Detection Detail - Record 100', 'Position', [50 50 1000 400]);

samples_10s = 10 * fs_d;
t = (0:n_d-1) / fs_d;

plot(t(1:samples_10s), ecg_d(1:samples_10s), 'b', 'LineWidth', 0.8);
hold on;

% Annotated beats (cardiologist) - green circles
ann_10s = ann_d(ann_d <= samples_10s);
plot(t(ann_10s), ecg_d(ann_10s), 'go', 'MarkerSize', 14, 'LineWidth', 2);

% Detected beats (our algorithm) - red triangles
det_10s = det_d(det_d <= samples_10s);
plot(t(det_10s), ecg_d(det_10s), 'rv', 'MarkerSize', 8, 'MarkerFaceColor', 'r');

hold off;
xlabel('Time (s)');
ylabel('Amplitude (mV)');
title('Detection vs Annotation - Record 100 (first 10 s)');
legend('ECG', 'Cardiologist annotation', 'Our detection');
grid on;
xlim([0 10]);

%% 6. Save results
save('validation_results.mat', 'results', 'total_TP', 'total_FP', 'total_FN', ...
     'overall_se', 'overall_pp', 'overall_f1');

fprintf('\nResults saved to validation_results.mat\n');
fprintf('validate_sensitivity completed successfully.\n');


%% ====================================================================
%  LOCAL FUNCTIONS
%  ====================================================================

function ann_samples = read_annotations(record, n_samples)
% READ_ANNOTATIONS - Read MIT-BIH annotation file (.atr)
% Returns sample indices of all beat annotations
%
% MIT-BIH annotation format (binary):
%   Each annotation = 2 bytes (16 bits)
%   Bits 15-10: annotation type code
%   Bits 9-0: time offset from previous annotation
%   Pseudo-annotation codes (WFDB):
%     59 = SKIP : interval stored in next 4 bytes, high word first
%     60 = NUM  : annotator number, time field carries data, not time
%     61 = SUB  : subtype, time field carries data, not time
%     62 = CHN  : channel, time field carries data, not time
%     63 = AUX  : time field carries auxiliary string length, not time
%      0 = EOF

    atr_file = [record '.atr'];
    fid = fopen(atr_file, 'r');
    if fid == -1
        error('Annotation file not found: %s', atr_file);
    end

    bytes = fread(fid, inf, 'uint8');
    fclose(fid);

    % Beat type codes (all types that represent a heartbeat)
    % 1=N, 2=L, 3=R, 4=A, 5=V, 6=F, 7=J, 8=a, 9=S, 10=E
    % 11=j, 12=/, 13=Q, 34=r, 38=f
    beat_types = [1 2 3 4 5 6 7 8 9 10 11 12 13 34 38];

    ann_samples = [];
    current_sample = 0;
    i = 1;

    while i <= length(bytes) - 1
        % Read 2 bytes (little-endian)
        low_byte = bytes(i);
        high_byte = bytes(i + 1);
        i = i + 2;

        % Extract type (bits 15-10) and time delta (bits 9-0)
        ann_type = bitshift(high_byte, -2);
        time_delta = bitor(low_byte, bitand(high_byte, 3) * 256);

        if ann_type == 0
            % End of annotation file
            break;

        elseif ann_type == 59
            % SKIP: 32-bit interval in next 4 bytes, high word first
            if i + 3 <= length(bytes)
                hi_word = bytes(i)   + bytes(i+1) * 256;
                lo_word = bytes(i+2) + bytes(i+3) * 256;
                current_sample = current_sample + hi_word * 65536 + lo_word;
                i = i + 4;
            else
                break;
            end

        elseif ann_type == 63
            % AUX: time field is the auxiliary string length in bytes
            aux_len = time_delta;
            % Pad to even number of bytes
            if mod(aux_len, 2) ~= 0
                aux_len = aux_len + 1;
            end
            i = i + aux_len;

        elseif ann_type == 60 || ann_type == 61 || ann_type == 62
            % NUM, SUB, CHN: time field carries data, sample counter unchanged
            continue;

        else
            % Regular annotation
            current_sample = current_sample + time_delta;

            % Check if it's a beat type
            if ismember(ann_type, beat_types) && current_sample <= n_samples
                ann_samples = [ann_samples; current_sample]; %#ok<AGROW>
            end
        end
    end
end


function [TP, FP, FN, matched_ann, matched_det] = match_peaks(ann_peaks, det_peaks, tolerance)
% MATCH_PEAKS - Match detected peaks against annotated peaks
% A detection is a True Positive if it falls within 'tolerance' samples
% of an annotation. Each annotation can only be matched once.

    n_ann = length(ann_peaks);
    n_det = length(det_peaks);

    matched_ann = false(n_ann, 1);
    matched_det = false(n_det, 1);

    % For each detected peak, find closest annotation
    for d = 1:n_det
        distances = abs(ann_peaks - det_peaks(d));
        [min_dist, min_idx] = min(distances);

        if min_dist <= tolerance && ~matched_ann(min_idx)
            matched_ann(min_idx) = true;
            matched_det(d) = true;
        end
    end

    TP = sum(matched_det);      % Correctly detected beats
    FP = n_det - TP;            % Detections without matching annotation
    FN = n_ann - sum(matched_ann); % Annotations without matching detection
end
