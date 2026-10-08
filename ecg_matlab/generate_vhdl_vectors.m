%% GENERATE VHDL TEST VECTORS FROM MIT-BIH DATA
% Project: Cardiac arrhythmia detection system - FPGA DE1-SoC
% Universidad Tecnologica del Peru (UTP)
% Stage 2: MATLAB validation with MIT-BIH data
%
% This script is the bridge between MATLAB and VHDL.
% Generates .txt files that ModelSim can read via VHDL textio:
%   1. ECG input samples (12-bit binary strings)
%   2. Expected QRS detections
%   3. Expected classification codes
%
% Output files go to: D:/proyectos/ecg_arrhythmia/ (Quartus project)
%
% VERSION 3 (CORRECCION ANOMALIA 2): la referencia QRS ahora se obtiene
% del detector oficial causal pan_tompkins_causal.m (v4-SELFCAL), NO con
% filtfilt. filtfilt es bidireccional y NO es implementable en FPGA, por
% lo que usarlo como "verdad de referencia" del VHDL era incoherente.
% Ahora MATLAB y VHDL comparten el mismo algoritmo causal de referencia.

clc; clear; close all;

%% 1. Configuration
record = '115';
output_dir = 'D:/proyectos/ecg_arrhythmia/'; % Quartus project folder

% Duration to export (seconds)
% 30 seconds = 10800 samples (enough for ~40 beats, fast simulation)
% Full record = 650000 samples (slow simulation, for final validation)
export_duration = 30; % seconds

fprintf('Generating VHDL test vectors for record %s\n', record);
fprintf('Output directory: %s\n', output_dir);

%% 2. Load MIT-BIH data
[signal, fs, gain, baseline, n_samples] = read_mitbih(record);
ecg = signal(:, 1); % Channel 1 (MLII)

% Limit to export duration
n_export = min(export_duration * fs, n_samples);
ecg_export = ecg(1:n_export);

fprintf('Exporting %d samples (%.1f seconds)\n', n_export, n_export/fs);

%% 3. Convert ECG to 12-bit unsigned integer (FULL-SCALE 0-4095)
% VHDL expects: std_logic_vector(11 downto 0) = 0 to 4095
%
% NUEVO ESCALADO (Etapa 3):
%   - Mapear la senal ECG en mV al rango completo 0-4095
%   - Preserva la forma de onda (lo unico relevante para Pan-Tompkins)
%   - Aprovecha toda la resolucion del ADC simulado
%   - Equivalente a un front-end con ganancia ajustada al rango de la senal
%
% Esto reemplaza el escalado anterior que dejaba la senal en 2936-3282
% (solo 8% del rango), insuficiente para el umbral adaptativo del QRS.

ecg_min = min(ecg_export);
ecg_max = max(ecg_export);

% Margen de 5% en cada extremo para evitar saturacion en valores extremos
margin = 0.05;
ecg_range = ecg_max - ecg_min;
target_min = round(4095 * margin);                  % ~205
target_max = round(4095 * (1 - margin));            % ~3890

ecg_unsigned = round( (ecg_export - ecg_min) / ecg_range * (target_max - target_min) + target_min );

% Clip de seguridad al rango 12-bit
ecg_unsigned = max(min(ecg_unsigned, 4095), 0);

fprintf('ECG original (mV): [%.3f, %.3f]\n', ecg_min, ecg_max);
fprintf('ECG escalado 12-bit: [%d, %d] (rango usado: %.1f%%)\n', ...
    min(ecg_unsigned), max(ecg_unsigned), ...
    (max(ecg_unsigned)-min(ecg_unsigned))/4095*100);

%% 4. Generate ECG input vectors file
% Format: one 12-bit binary string per line
% ModelSim reads with: readline(file_line); read(file_line, ecg_vector);
ecg_file = fullfile(output_dir, 'ecg_test_vectors.txt');
fid = fopen(ecg_file, 'w');
if fid == -1
    error('Cannot write to: %s', ecg_file);
end

for i = 1:n_export
    % Convert to 12-bit binary string
    bin_str = dec2bin(ecg_unsigned(i), 12);
    fprintf(fid, '%s\n', bin_str);
end
fclose(fid);

fprintf('Created: ecg_test_vectors.txt (%d lines)\n', n_export);

%% 5. Run Pan-Tompkins on exported segment to get expected results
% CORRECCION ANOMALIA 2:
% Se usa el detector OFICIAL causal pan_tompkins_causal.m (v4-SELFCAL),
% el mismo validado sobre 48 registros (F1=83.31%) en validate_sensitivity.m.
% Antes esta seccion reimplementaba un detector con filtfilt (bidireccional),
% que NO es implementable en FPGA y por tanto no servia como referencia
% honesta para comparar contra el VHDL. Ahora la referencia es causal y
% coherente con la implementacion hardware.
%
% Se ejecuta sobre la senal en mV original (flotante); esa es la verdad
% de referencia contra la cual se compara el VHDL en compare_vhdl_matlab.m.

r_peaks_local = pan_tompkins_causal(ecg_export, fs, n_export);
r_peaks_local = r_peaks_local(:);

fprintf('Detected %d R-peaks in exported segment (pan_tompkins_causal v4)\n', ...
        length(r_peaks_local));

%% 6. Generate expected QRS detection file
% Format: one line per sample, '1' if QRS detected at that sample, '0' otherwise
% VHDL qrs_detector output: qrs_pulse goes high for one clock cycle
qrs_file = fullfile(output_dir, 'expected_qrs.txt');
fid = fopen(qrs_file, 'w');

qrs_vector = zeros(n_export, 1);
qrs_vector(r_peaks_local) = 1;

for i = 1:n_export
    fprintf(fid, '%d\n', qrs_vector(i));
end
fclose(fid);

fprintf('Created: expected_qrs.txt (%d lines)\n', n_export);

%% 7. Calculate expected BPM and classification for each beat
rr_local = diff(r_peaks_local);
bpm_local = 60 ./ (rr_local / fs);

% Classification with 4-beat buffer (matches classifier.vhd)
n_beats = length(bpm_local);
class_code = zeros(n_beats, 1);

for b = 1:n_beats
    curr_bpm = bpm_local(b);
    
    % RR variation (4-beat window)
    if b >= 4
        rr_win = rr_local(b-3:b);
        rr_mean = mean(rr_win);
        rr_var = max(abs(rr_win - rr_mean)) / rr_mean * 100;
    else
        rr_var = 0;
    end
    
    % Priority: AFib > Bradi > Taqui > Normal
    if rr_var > 20
        class_code(b) = 3; % 11 = AFib
    elseif curr_bpm < 60
        class_code(b) = 1; % 01 = Bradycardia
    elseif curr_bpm > 100
        class_code(b) = 2; % 10 = Tachycardia
    else
        class_code(b) = 0; % 00 = Normal
    end
end

%% 8. Generate expected classification file
% Format: beat_sample_index,bpm,class_code (2-bit binary)
class_file = fullfile(output_dir, 'expected_classification.txt');
fid = fopen(class_file, 'w');

fprintf(fid, '%% Beat | Sample | BPM | Class Code\n');
for b = 1:n_beats
    fprintf(fid, '%d %d %.1f %s\n', b, r_peaks_local(b+1), bpm_local(b), dec2bin(class_code(b), 2));
end
fclose(fid);

fprintf('Created: expected_classification.txt (%d beats)\n', n_beats);

%% 9. Generate summary info file
info_file = fullfile(output_dir, 'test_vectors_info.txt');
fid = fopen(info_file, 'w');

fprintf(fid, 'TEST VECTORS INFORMATION\n');
fprintf(fid, '========================\n');
fprintf(fid, 'Generated: %s\n', datestr(now));
fprintf(fid, 'MIT-BIH Record: %s\n', record);
fprintf(fid, 'Sampling frequency: %d Hz\n', fs);
fprintf(fid, 'Export duration: %.1f seconds\n', n_export/fs);
fprintf(fid, 'Total samples: %d\n', n_export);
fprintf(fid, 'R-peaks detected: %d\n', length(r_peaks_local));
fprintf(fid, 'Mean BPM: %.1f\n', mean(bpm_local));
fprintf(fid, '\nQRS reference detector: pan_tompkins_causal.m (v4-SELFCAL, causal)\n');
fprintf(fid, '\nECG data format: 12-bit unsigned (0-4095)\n');
fprintf(fid, 'Scaling: full-scale mapping con margen 5%% en cada extremo\n');
fprintf(fid, 'ECG escalado: [%d, %d]\n', min(ecg_unsigned), max(ecg_unsigned));
fprintf(fid, '\nFiles generated:\n');
fprintf(fid, '  ecg_test_vectors.txt      - ECG input (12-bit binary, 1 per line)\n');
fprintf(fid, '  expected_qrs.txt          - Expected QRS pulses (0/1, 1 per line)\n');
fprintf(fid, '  expected_classification.txt - Expected beat classification\n');
fprintf(fid, '\nUsage in ModelSim testbench:\n');
fprintf(fid, '  Read ecg_test_vectors.txt line by line\n');
fprintf(fid, '  Feed each 12-bit value to ecg_data input\n');
fprintf(fid, '  Assert data_valid for one clock cycle per sample\n');
fprintf(fid, '  Compare qrs_pulse output against expected_qrs.txt\n');
fprintf(fid, '  Compare classification output against expected_classification.txt\n');
fclose(fid);

fprintf('Created: test_vectors_info.txt\n');

%% 10. Verification plot
t_export = (0:n_export-1) / fs;

figure('Name', 'Test Vectors Verification', 'Position', [50 50 1000 500]);

subplot(2,1,1);
plot(t_export, ecg_unsigned, 'b', 'LineWidth', 0.5);
hold on;
plot(t_export(r_peaks_local), ecg_unsigned(r_peaks_local), 'rv', ...
     'MarkerSize', 10, 'MarkerFaceColor', 'r');
hold off;
xlabel('Time (s)');
ylabel('12-bit unsigned value');
title(['Test Vectors - Record ' record ' (12-bit unsigned, full-scale)']);
legend('ECG data', 'R-peaks');
ylim([0 4095]);
grid on;

subplot(2,1,2);
stem(1:n_beats, bpm_local, 'b', 'MarkerSize', 5, 'MarkerFaceColor', 'b');
hold on;
yline(60, 'g--');
yline(100, 'r--');
% Color beats by classification
for b = 1:n_beats
    colors = {'g', 'b', 'r', 'm'}; % Normal, Bradi, Taqui, AFib
    plot(b, bpm_local(b), 'o', 'MarkerSize', 6, ...
         'MarkerFaceColor', colors{class_code(b)+1}, 'MarkerEdgeColor', 'none');
end
hold off;
xlabel('Beat number');
ylabel('BPM');
title('Expected BPM and Classification');
legend('BPM', 'Bradi limit', 'Taqui limit', 'Location', 'best');
grid on;

%% 11. Save workspace
save('vhdl_vectors_results.mat', 'ecg_unsigned', 'r_peaks_local', ...
     'bpm_local', 'class_code', 'n_export', 'fs', 'record');

fprintf('\n--- Summary ---\n');
fprintf('Output directory: %s\n', output_dir);
fprintf('Files ready for ModelSim testbench.\n');
fprintf('generate_vhdl_vectors completed successfully.\n');