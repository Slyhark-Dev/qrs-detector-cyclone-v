%% COMPARE VHDL vs MATLAB RESULTS
% Project: Cardiac arrhythmia detection system - FPGA DE1-SoC
% Universidad Tecnologica del Peru (UTP)
% Stage 3: VHDL-MATLAB equivalence validation with MIT-BIH data
%
% VERSION 3: Parametrizacion por registro para la Tarea 5 (revalidacion
% de equivalencia VHDL-MATLAB sobre varios registros: 100, 115, 208).
%   - Se define el registro esperado en una sola variable arriba.
%   - Verificacion de consistencia: el registro definido se compara contra
%     el registro que viene dentro de vhdl_vectors_results.mat. Si no
%     coinciden, se detiene con error (evita comparar datos descuadrados).
%   - El .mat de resultados se guarda con el registro en el nombre
%     (comparison_results_<record>.mat) para no pisar corridas anteriores.
% VERSION 2: Lectura de los archivos VHDL reales generados por el
% testbench tb_top_ecg.vhd (Etapa 3). Sin modo demo.
%
% Compara la salida de la simulacion VHDL (ModelSim) contra los
% resultados de referencia MATLAB para validar la implementacion FPGA.
%
% Archivos VHDL requeridos (generados por ModelSim, formato con cabecera #):
%   vhdl_qrs_output.txt   - "indice_muestra r_peak" (2 columnas)
%   vhdl_bpm_output.txt   - "tiempo_us bpm rr_interval rr_mean rr_max rr_min"
%   vhdl_class_output.txt - "tiempo_us code alert" (code/alert en binario 2-bit)
%
% Deben estar en: D:/proyectos/ecg_arrhythmia/

clc; clear; close all;

%% 1. Configuration
vhdl_dir = 'D:/proyectos/ecg_arrhythmia/';
% Registro esperado para esta corrida. Debe coincidir con el registro
% que se uso al generar los vectores (generate_vhdl_vectors.m) y al correr
% ModelSim. Cambiar a '100', '115' o '208' segun la corrida.
record_esperado = '115';

fprintf('=== VHDL vs MATLAB COMPARISON (Etapa 3) ===\n');
fprintf('Record esperado: %s\n', record_esperado);
fprintf('VHDL output directory: %s\n\n', vhdl_dir);

%% 2. Check VHDL output files
qrs_file   = fullfile(vhdl_dir, 'vhdl_qrs_output.txt');
bpm_file   = fullfile(vhdl_dir, 'vhdl_bpm_output.txt');
class_file = fullfile(vhdl_dir, 'vhdl_class_output.txt');

if ~(isfile(qrs_file) && isfile(bpm_file) && isfile(class_file))
    error(['No se encontraron los archivos VHDL en %s. ' ...
           'Ejecuta ModelSim (run 31 sec) primero.'], vhdl_dir);
end
fprintf('Archivos VHDL encontrados. Cargando...\n\n');

%% 3. Load MATLAB reference results
if ~isfile('vhdl_vectors_results.mat')
    error('vhdl_vectors_results.mat no encontrado. Ejecuta generate_vhdl_vectors.m primero.');
end
load('vhdl_vectors_results.mat');  % carga r_peaks_local, bpm_local, class_code, n_export, fs, record

% --- Verificacion de consistencia del registro ---
% El .mat trae adentro la variable 'record' del registro con que se generaron
% los vectores. Si no coincide con record_esperado, los datos estan
% descuadrados (p.ej. se corrio ModelSim para 208 pero no se regenero el .mat).
if ~exist('record', 'var')
    error(['vhdl_vectors_results.mat no contiene la variable ''record''. ' ...
           'Regenera los vectores con generate_vhdl_vectors.m.']);
end
if ~strcmp(char(string(record)), record_esperado)
    error(['INCONSISTENCIA DE REGISTRO: el .mat es del registro %s pero ' ...
           'record_esperado = %s.\nRegenera los vectores con ' ...
           'generate_vhdl_vectors.m para el registro %s y vuelve a correr ' ...
           'ModelSim antes de comparar.'], ...
           char(string(record)), record_esperado, record_esperado);
end
fprintf('Consistencia OK: .mat y record_esperado son del registro %s.\n', record_esperado);

ref_qrs_peaks = r_peaks_local(:);
ref_bpm       = bpm_local(:);
ref_class     = class_code(:);
n_ref_beats   = length(ref_bpm);

fprintf('MATLAB referencia: %d picos R, %d latidos, BPM medio=%.1f\n', ...
        length(ref_qrs_peaks), n_ref_beats, mean(ref_bpm));

%% 4. Load VHDL output files
% --- 4a. QRS: archivo "indice_muestra r_peak", cabecera con # ---
M_qrs = readmatrix(qrs_file, 'NumHeaderLines', 1, 'FileType', 'text');
% Columna 1 = indice de muestra, Columna 2 = r_peak (0/1)
vhdl_sample_idx = M_qrs(:,1);
vhdl_rpeak_flag = M_qrs(:,2);
% indice (en muestras) de cada pico R detectado por el VHDL
vhdl_peaks = vhdl_sample_idx(vhdl_rpeak_flag == 1);
vhdl_peaks = vhdl_peaks(:);

% --- 4b. BPM: archivo de 6 columnas, tomar solo la columna bpm (col 2) ---
M_bpm = readmatrix(bpm_file, 'NumHeaderLines', 1, 'FileType', 'text');
vhdl_bpm_all = M_bpm(:,2);
% Filtrar valores saturados (255) que indican intervalos espurios;
% con el fix del refractario no deberia haber ninguno, pero por seguridad.
vhdl_bpm = vhdl_bpm_all(vhdl_bpm_all > 0 & vhdl_bpm_all < 255);
vhdl_bpm = vhdl_bpm(:);
n_vhdl_beats = length(vhdl_bpm);

% --- 4c. Clasificacion: "tiempo_us code alert", code en binario 2-bit ---
T_class = readtable(class_file, 'NumHeaderLines', 1, 'FileType', 'text', ...
                    'ReadVariableNames', false, 'Format', '%f %s %s');
code_str = string(T_class.Var2);
vhdl_class = zeros(length(code_str), 1);
for i = 1:length(code_str)
    vhdl_class(i) = bin2dec(char(code_str(i)));
end
vhdl_class = vhdl_class(:);

fprintf('VHDL salida:       %d picos R, %d latidos, BPM medio=%.1f\n\n', ...
        length(vhdl_peaks), n_vhdl_beats, mean(vhdl_bpm));

%% 5. Compare QRS detection (emparejamiento por cercania, tolera latencia pipeline)
tolerance = round(0.150 * fs);  % 150 ms = 54 muestras a 360 Hz

matched      = 0;
peak_errors  = [];
used_vhdl    = false(length(vhdl_peaks), 1);

for i = 1:length(ref_qrs_peaks)
    % buscar el pico VHDL mas cercano aun no usado
    [d, j] = min(abs(vhdl_peaks - ref_qrs_peaks(i)) + used_vhdl*1e9);
    if d <= tolerance
        matched      = matched + 1;
        peak_errors  = [peak_errors; vhdl_peaks(j) - ref_qrs_peaks(i)]; %#ok<AGROW>
        used_vhdl(j) = true;
    end
end

qrs_match_pct = matched / length(ref_qrs_peaks) * 100;

fprintf('--- QRS Detection Comparison ---\n');
fprintf('Picos referencia (MATLAB): %d\n', length(ref_qrs_peaks));
fprintf('Picos VHDL:                %d\n', length(vhdl_peaks));
fprintf('Emparejados (<%d muestras): %d\n', tolerance, matched);
fprintf('Tasa de coincidencia:      %.2f%%\n', qrs_match_pct);
if ~isempty(peak_errors)
    fprintf('Latencia media pipeline:   %.1f muestras (%.1f ms)\n', ...
            mean(peak_errors), mean(peak_errors)/fs*1000);
    fprintf('Desviacion latencia:       %.1f muestras\n', std(peak_errors));
end

%% 6. Compare BPM values
n_compare = min(n_ref_beats, n_vhdl_beats);
bpm_error = abs(ref_bpm(1:n_compare) - vhdl_bpm(1:n_compare));
bpm_match = sum(bpm_error < 5) / n_compare * 100;  % dentro de 5 BPM

fprintf('\n--- BPM Comparison ---\n');
fprintf('Latidos comparados: %d\n', n_compare);
fprintf('Error medio BPM:    %.2f BPM\n', mean(bpm_error));
fprintf('Error maximo BPM:   %.2f BPM\n', max(bpm_error));
fprintf('Coincidencia (<5 BPM): %.2f%%\n', bpm_match);

%% 7. Compare classification
class_match     = sum(ref_class(1:n_compare) == vhdl_class(1:n_compare));
class_match_pct = class_match / n_compare * 100;

fprintf('\n--- Classification Comparison ---\n');
fprintf('Latidos comparados: %d\n', n_compare);
fprintf('Codigos coincidentes: %d\n', class_match);
fprintf('Tasa de coincidencia: %.2f%%\n', class_match_pct);

% Matriz de confusion
class_names = {'Normal', 'Bradi', 'Taqui', 'AFib'};
fprintf('\nMatriz de Confusion (filas=MATLAB, cols=VHDL):\n');
fprintf('          ');
for c = 0:3
    fprintf('%-8s ', class_names{c+1});
end
fprintf('\n');
for r = 0:3
    fprintf('%-8s  ', class_names{r+1});
    for c = 0:3
        count = sum(ref_class(1:n_compare)==r & vhdl_class(1:n_compare)==c);
        fprintf('%-8d ', count);
    end
    fprintf('\n');
end

%% 8. Overall summary
fprintf('\n====================================\n');
fprintf('     OVERALL COMPARISON SUMMARY\n');
fprintf('====================================\n');
fprintf('QRS detection match:    %.2f%%\n', qrs_match_pct);
fprintf('BPM match (<5 BPM):     %.2f%%\n', bpm_match);
fprintf('Classification match:   %.2f%%\n', class_match_pct);

overall = (qrs_match_pct + bpm_match + class_match_pct) / 3;
fprintf('Overall equivalence:    %.2f%%\n', overall);

if overall >= 95
    fprintf('Status: EXCELLENT - VHDL implementation validated\n');
elseif overall >= 85
    fprintf('Status: GOOD - Minor differences, acceptable for paper\n');
elseif overall >= 70
    fprintf('Status: ACCEPTABLE - Review differences before publishing\n');
else
    fprintf('Status: NEEDS REVIEW - Significant differences found\n');
end
fprintf('====================================\n');

%% 9. Plots
figure('Name', 'VHDL vs MATLAB Comparison', 'Position', [50 50 1000 700]);

subplot(3,1,1);
plot(1:n_compare, ref_bpm(1:n_compare), 'b.-', 'LineWidth', 1, 'MarkerSize', 8);
hold on;
plot(1:n_compare, vhdl_bpm(1:n_compare), 'r.--', 'LineWidth', 1, 'MarkerSize', 8);
hold off;
xlabel('Beat number'); ylabel('BPM');
title('BPM: MATLAB (reference) vs VHDL');
legend('MATLAB', 'VHDL', 'Location', 'best'); grid on;

subplot(3,1,2);
bar(1:n_compare, bpm_error, 'FaceColor', [0.9 0.3 0.1]);
xlabel('Beat number'); ylabel('BPM error');
title('Absolute BPM Error per Beat');
yline(5, 'r--', '5 BPM threshold', 'LineWidth', 1.5); grid on;

subplot(3,1,3);
hold on;
plot(1:n_compare, ref_class(1:n_compare), 'bs', 'MarkerSize', 10, 'MarkerFaceColor', 'b');
plot(1:n_compare, vhdl_class(1:n_compare), 'r^', 'MarkerSize', 8, 'MarkerFaceColor', 'r');
hold off;
xlabel('Beat number'); ylabel('Class code');
title('Classification Code: MATLAB vs VHDL');
yticks([0 1 2 3]);
yticklabels({'00 Normal', '01 Bradi', '10 Taqui', '11 AFib'});
legend('MATLAB', 'VHDL', 'Location', 'best'); grid on;

% Localizacion de picos (primeros 10 segundos)
figure('Name', 'Peak Location Comparison', 'Position', [50 50 1000 400]);
[signal_plot, ~, ~, ~, ~] = read_mitbih(record);
ecg_plot = signal_plot(1:n_export, 1);
t_plot = (0:n_export-1) / fs;
samples_10s = min(10*fs, n_export);

plot(t_plot(1:samples_10s), ecg_plot(1:samples_10s), 'b', 'LineWidth', 0.8);
hold on;
ref_10s  = ref_qrs_peaks(ref_qrs_peaks <= samples_10s);
vhdl_10s = vhdl_peaks(vhdl_peaks <= samples_10s);
plot(t_plot(ref_10s), ecg_plot(ref_10s), 'go', 'MarkerSize', 14, 'LineWidth', 2);
% Los picos VHDL llevan latencia de pipeline; restarla para alinear visualmente
if ~isempty(peak_errors)
    lat = round(mean(peak_errors));
else
    lat = 0;
end
vhdl_10s_aligned = vhdl_10s - lat;
vhdl_10s_aligned = vhdl_10s_aligned(vhdl_10s_aligned >= 1 & vhdl_10s_aligned <= samples_10s);
plot(t_plot(vhdl_10s_aligned), ecg_plot(vhdl_10s_aligned), 'rv', ...
     'MarkerSize', 8, 'MarkerFaceColor', 'r');
hold off;
xlabel('Time (s)'); ylabel('Amplitude (mV)');
title(['Peak Location: MATLAB vs VHDL - Record ' record ' (first 10 s, VHDL aligned)']);
legend('ECG', 'MATLAB peaks', 'VHDL peaks (lat-corrected)');
grid on; xlim([0 10]);

%% 10. Save results
out_mat = sprintf('comparison_results_%s.mat', record_esperado);
save(out_mat, 'qrs_match_pct', 'bpm_match', 'class_match_pct', ...
     'overall', 'bpm_error', 'ref_bpm', 'vhdl_bpm', 'ref_class', 'vhdl_class', ...
     'ref_qrs_peaks', 'vhdl_peaks', 'peak_errors', 'record');

fprintf('\nResultados guardados en %s\n', out_mat);
fprintf('compare_vhdl_matlab completado correctamente.\n');
