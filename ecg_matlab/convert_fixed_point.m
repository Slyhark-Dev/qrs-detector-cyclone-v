%% FIXED-POINT CONVERSION AND ANALYSIS
% Project: Cardiac arrhythmia detection system - FPGA DE1-SoC
% Universidad Tecnologica del Peru (UTP)
% Stage 2: MATLAB validation with MIT-BIH data
%
% Converts floating-point Pan-Tompkins to fixed-point arithmetic
% matching VHDL implementation:
%   - ECG samples: Q12.4 (12 integer bits, 4 fractional bits = 16 bits)
%   - Filter coefficients: Q8.8 (8 integer bits, 8 fractional bits = 16 bits)
%   - Goal: SNR > 40 dB between float and fixed-point outputs

clc; clear; close all;

%% 1. Load original data
if ~isfile('qrs_results.mat')
    error('qrs_results.mat not found. Run detect_qrs.m first.');
end
load('qrs_results.mat');

fprintf('Fixed-point conversion for record %s\n', record);
fprintf('Samples: %d, Fs: %d Hz\n\n', n_samples, fs);

%% 2. Define fixed-point formats
% Q12.4: 16 bits total, 12 integer + 4 fractional
% Range: -2048 to 2047.9375, resolution: 0.0625
q_sample_int = 12;
q_sample_frac = 4;
q_sample_bits = q_sample_int + q_sample_frac;

% Q8.8: 16 bits total, 8 integer + 8 fractional
% Range: -128 to 127.996, resolution: 0.00390625
q_coeff_int = 8;
q_coeff_frac = 8;
q_coeff_bits = q_coeff_int + q_coeff_frac;

fprintf('--- Fixed-Point Formats ---\n');
fprintf('Samples:      Q%d.%d (%d bits)\n', q_sample_int, q_sample_frac, q_sample_bits);
fprintf('  Range:      [%.4f, %.4f]\n', -2^(q_sample_int-1), 2^(q_sample_int-1) - 2^(-q_sample_frac));
fprintf('  Resolution: %.4f\n', 2^(-q_sample_frac));
fprintf('Coefficients: Q%d.%d (%d bits)\n', q_coeff_int, q_coeff_frac, q_coeff_bits);
fprintf('  Range:      [%.4f, %.4f]\n', -2^(q_coeff_int-1), 2^(q_coeff_int-1) - 2^(-q_coeff_frac));
fprintf('  Resolution: %.6f\n\n', 2^(-q_coeff_frac));

%% 3. Convert ECG samples to fixed-point Q12.4
% Scale: multiply by 2^frac_bits, round, clip to range
scale_sample = 2^q_sample_frac;
max_val_sample = 2^(q_sample_bits-1) - 1;  % 32767
min_val_sample = -2^(q_sample_bits-1);      % -32768

ecg_fp_raw = round(ecg * scale_sample);
ecg_fp_clipped = max(min(ecg_fp_raw, max_val_sample), min_val_sample);
n_clipped = sum(ecg_fp_raw ~= ecg_fp_clipped);

% Convert back to floating point for comparison
ecg_fp = ecg_fp_clipped / scale_sample;

fprintf('--- Sample Conversion ---\n');
fprintf('Clipped samples: %d (%.4f%%)\n', n_clipped, n_clipped/n_samples*100);

%% 4. Fixed-point bandpass filter
% FIR coefficients in Q8.8
fir_order = 32;
f_low = 5;
f_high = 15;
b_bp_float = fir1(fir_order, [f_low f_high] / (fs/2), 'bandpass');

% Quantize coefficients to Q8.8
scale_coeff = 2^q_coeff_frac;
b_bp_fp = round(b_bp_float * scale_coeff) / scale_coeff;

% Apply filter using fixed-point coefficients on fixed-point data
ecg_filtered_fp = filter(b_bp_fp, 1, ecg_fp);

% Floating-point reference
ecg_filtered_float = filter(b_bp_float, 1, ecg);

%% 5. Fixed-point derivative (5-point)
b_deriv_float = (1/8) * [-1 -2 0 2 1];
b_deriv_fp = round(b_deriv_float * scale_coeff) / scale_coeff;

ecg_deriv_fp = filter(b_deriv_fp, 1, ecg_filtered_fp);
ecg_deriv_float = filter(b_deriv_float, 1, ecg_filtered_float);

%% 6. Fixed-point squaring
ecg_squared_fp = ecg_deriv_fp .^ 2;
ecg_squared_float = ecg_deriv_float .^ 2;

%% 7. Fixed-point moving window integration
win_width = round(0.150 * fs);
b_win = ones(1, win_width) / win_width;
b_win_fp = round(b_win * scale_coeff) / scale_coeff;

ecg_integrated_fp = filter(b_win_fp, 1, ecg_squared_fp);
ecg_integrated_float = filter(b_win, 1, ecg_squared_float);

%% 8. Calculate SNR at each stage
% SNR = 10*log10( sum(signal^2) / sum(error^2) )
error_filter = ecg_filtered_float - ecg_filtered_fp;
error_deriv = ecg_deriv_float - ecg_deriv_fp;
error_squared = ecg_squared_float - ecg_squared_fp;
error_integrated = ecg_integrated_float - ecg_integrated_fp;

snr_filter = 10 * log10(sum(ecg_filtered_float.^2) / sum(error_filter.^2));
snr_deriv = 10 * log10(sum(ecg_deriv_float.^2) / sum(error_deriv.^2));
snr_squared = 10 * log10(sum(ecg_squared_float.^2) / sum(error_squared.^2));
snr_integrated = 10 * log10(sum(ecg_integrated_float.^2) / sum(error_integrated.^2));

fprintf('\n--- SNR Analysis (Float vs Fixed-Point) ---\n');
fprintf('Stage              | SNR (dB)  | Status\n');
fprintf('-------------------|-----------|--------\n');
fprintf('Bandpass filter    | %7.1f   | %s\n', snr_filter, status_snr(snr_filter));
fprintf('Derivative         | %7.1f   | %s\n', snr_deriv, status_snr(snr_deriv));
fprintf('Squaring           | %7.1f   | %s\n', snr_squared, status_snr(snr_squared));
fprintf('Integration        | %7.1f   | %s\n', snr_integrated, status_snr(snr_integrated));

%% 9. Run QRS detection on fixed-point data
refractory_samples = round(0.200 * fs);
threshold = max(ecg_integrated_fp(1:2*fs)) * 0.25;
signal_peak = threshold;
noise_peak = threshold * 0.5;

r_peaks_fp = [];
i = 2;

while i <= length(ecg_integrated_fp) - 1
    if ecg_integrated_fp(i) > threshold && ...
       ecg_integrated_fp(i) >= ecg_integrated_fp(i-1) && ...
       ecg_integrated_fp(i) >= ecg_integrated_fp(i+1)

        if isempty(r_peaks_fp) || (i - r_peaks_fp(end)) > refractory_samples
            r_peaks_fp = [r_peaks_fp; i]; %#ok<AGROW>
            signal_peak = 0.875 * signal_peak + 0.125 * ecg_integrated_fp(i);
        end
        i = i + refractory_samples;
    else
        noise_peak = 0.875 * noise_peak + 0.125 * ecg_integrated_fp(i);
        i = i + 1;
    end
    threshold = noise_peak + 0.25 * (signal_peak - noise_peak);
end

% Refine peaks on original signal
search_window = round(0.150 * fs);
r_peaks_fp_refined = zeros(size(r_peaks_fp));
for k = 1:length(r_peaks_fp)
    win_start = max(1, r_peaks_fp(k) - search_window);
    win_end = min(n_samples, r_peaks_fp(k) + search_window);
    [~, local_idx] = max(abs(ecg(win_start:win_end)));
    r_peaks_fp_refined(k) = win_start + local_idx - 1;
end
r_peaks_fp = r_peaks_fp_refined;

%% 10. Compare float vs fixed-point detection
fprintf('\n--- Detection Comparison ---\n');
fprintf('Float R-peaks detected:       %d\n', length(r_peaks));
fprintf('Fixed-point R-peaks detected: %d\n', length(r_peaks_fp));
fprintf('Difference:                   %d peaks\n', abs(length(r_peaks) - length(r_peaks_fp)));

% Calculate BPM from fixed-point
rr_fp = diff(r_peaks_fp);
bpm_fp = 60 ./ (rr_fp / fs);
fprintf('Float mean BPM:       %.1f\n', mean(bpm));
fprintf('Fixed-point mean BPM: %.1f\n', mean(bpm_fp));
fprintf('BPM difference:       %.2f\n', abs(mean(bpm) - mean(bpm_fp)));

%% 11. Plot comparison
t = (0:n_samples-1) / fs;
samples_5s = 5 * fs;

figure('Name', 'Fixed-Point vs Float Comparison', 'Position', [50 50 1000 700]);

% Filter output comparison
subplot(3,1,1);
plot(t(1:samples_5s), ecg_filtered_float(1:samples_5s), 'b', 'LineWidth', 1);
hold on;
plot(t(1:samples_5s), ecg_filtered_fp(1:samples_5s), 'r--', 'LineWidth', 1);
hold off;
title('Bandpass Filter Output');
ylabel('mV');
legend('Float', 'Fixed-Point Q8.8');
grid on; xlim([0 5]);

% Integration output comparison
subplot(3,1,2);
plot(t(1:samples_5s), ecg_integrated_float(1:samples_5s), 'b', 'LineWidth', 1);
hold on;
plot(t(1:samples_5s), ecg_integrated_fp(1:samples_5s), 'r--', 'LineWidth', 1);
hold off;
title('Integration Output');
ylabel('Amplitude');
legend('Float', 'Fixed-Point');
grid on; xlim([0 5]);

% Quantization error
subplot(3,1,3);
plot(t(1:samples_5s), error_filter(1:samples_5s), 'k', 'LineWidth', 0.5);
title('Quantization Error (Bandpass Stage)');
xlabel('Time (s)');
ylabel('Error (mV)');
grid on; xlim([0 5]);

% R-peak comparison plot
figure('Name', 'R-peak Detection Comparison', 'Position', [50 50 1000 400]);
samples_10s = 10 * fs;

plot(t(1:samples_10s), ecg(1:samples_10s), 'b', 'LineWidth', 0.8);
hold on;
peaks_float_10s = r_peaks(r_peaks <= samples_10s);
peaks_fp_10s = r_peaks_fp(r_peaks_fp <= samples_10s);
plot(t(peaks_float_10s), ecg(peaks_float_10s), 'gv', 'MarkerSize', 12, 'MarkerFaceColor', 'g');
plot(t(peaks_fp_10s), ecg(peaks_fp_10s), 'r^', 'MarkerSize', 8, 'MarkerFaceColor', 'r');
hold off;
xlabel('Time (s)');
ylabel('Amplitude (mV)');
title(['R-peak Comparison: Float vs Fixed-Point - Record ' record]);
legend('ECG', 'Float peaks', 'Fixed-point peaks');
grid on; xlim([0 10]);

%% 12. Save results
save('fixed_point_results.mat', 'r_peaks_fp', 'bpm_fp', 'ecg_fp', ...
     'ecg_filtered_fp', 'ecg_integrated_fp', 'b_bp_fp', 'b_deriv_fp', ...
     'snr_filter', 'snr_deriv', 'snr_squared', 'snr_integrated', ...
     'record', 'fs', 'n_samples');

fprintf('\nResults saved to fixed_point_results.mat\n');
fprintf('convert_fixed_point completed successfully.\n');

%% Local function
function s = status_snr(snr_val)
    if snr_val >= 40
        s = 'PASS';
    elseif snr_val >= 30
        s = 'ACCEPTABLE';
    else
        s = 'REVIEW';
    end
end
