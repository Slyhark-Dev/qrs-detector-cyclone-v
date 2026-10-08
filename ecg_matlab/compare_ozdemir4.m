%% COMPARE OZDEMIR4 - Comparacion contra el subconjunto de Ozdemir 2011
% Project: Cardiac arrhythmia detection system - FPGA DE1-SoC
% Universidad Tecnologica del Peru (UTP)
%
% Ozdemir 2011 usa ANN + PCA (NO Pan-Tompkins), clasifica morfologia,
% y reporta Se=97.66% sobre SOLO 4 registros del MIT-BIH: 205, 208, 210, 213.
%
% Este script corre el detector causal OFICIAL del proyecto
% (pan_tompkins_causal.m, v4-SELFCAL) UNICAMENTE sobre esos 4 registros,
% para ver que sensibilidad alcanza el proyecto en ese subconjunto
% especifico y poder compararlo de forma justa contra Ozdemir.
%
% IMPORTANTE: esta comparacion NO es un reemplazo de la metrica oficial
% del proyecto (48 registros, Se=85.47%). Es un anexo de referencia para
% contextualizar contra un trabajo que solo evalua 4 registros faciles.
%
% Requiere los archivos .dat/.hea/.atr de los registros 205, 208, 210, 213
% en la carpeta actual de MATLAB (D:/proyectos/ecg_matlab/).

clc; clear; close all;

%% 1. Configuration
records = {'205', '208', '210', '213'};
tolerance = round(0.150 * 360); % 150 ms tolerance window (54 samples a 360 Hz)

ozdemir_se = 97.66; % Se reportada por Ozdemir 2011 sobre estos 4 registros

fprintf('=== COMPARACION CONTRA SUBCONJUNTO OZDEMIR 2011 ===\n');
fprintf('Registros: %s\n', strjoin(records, ', '));
fprintf('Metodo Ozdemir: ANN + PCA (morfologia, NO Pan-Tompkins)\n');
fprintf('Metodo propio:  Pan-Tompkins causal punto fijo (calibracion fija)\n');
fprintf('Ventana de tolerancia: %d muestras (%.0f ms)\n\n', tolerance, tolerance/360*1000);

%% 2. Process each record
results = struct();

for rec = 1:length(records)
    record = records{rec};
    fprintf('--- Procesando registro %s ---\n', record);

    % Load ECG
    [signal, fs, ~, ~, n_samples] = read_mitbih(record);

    % Read cardiologist annotations
    ann_peaks = read_annotations(record, n_samples);
    fprintf('Latidos anotados: %d\n', length(ann_peaks));

    % Run official causal detector on channel 1 (MLII)
    ecg = signal(:, 1);
    det_peaks = pan_tompkins_causal(ecg, fs, n_samples);
    det_peaks = det_peaks(:);
    fprintf('Latidos detectados: %d\n', length(det_peaks));

    % Match detections against annotations
    [TP, FP, FN] = match_peaks(ann_peaks, det_peaks, tolerance);

    se = TP / (TP + FN) * 100;
    pp = TP / (TP + FP) * 100;
    f1 = 2 * (se * pp) / (se + pp);

    fprintf('Se = %.2f%% | +P = %.2f%% | F1 = %.2f%%\n\n', se, pp, f1);

    results(rec).record = record;
    results(rec).annotated = length(ann_peaks);
    results(rec).detected = length(det_peaks);
    results(rec).TP = TP;
    results(rec).FP = FP;
    results(rec).FN = FN;
    results(rec).sensitivity = se;
    results(rec).pos_predict = pp;
    results(rec).f1_score = f1;
end

%% 3. Summary table
fprintf('=====================================================================\n');
fprintf('       RESULTADOS - SUBCONJUNTO OZDEMIR 2011 (4 REGISTROS)\n');
fprintf('=====================================================================\n');
fprintf('Registro | Anotados | Detectados | TP   | FP  | FN  | Se(%%)   | +P(%%)   | F1(%%)\n');
fprintf('---------|----------|------------|------|-----|-----|---------|---------|--------\n');

total_ann = 0; total_det = 0; total_TP = 0; total_FP = 0; total_FN = 0;

for rec = 1:length(records)
    r = results(rec);
    fprintf('   %s   |   %4d   |    %4d    | %4d | %3d | %3d | %6.2f  | %6.2f  | %5.2f\n', ...
        r.record, r.annotated, r.detected, r.TP, r.FP, r.FN, ...
        r.sensitivity, r.pos_predict, r.f1_score);

    total_ann = total_ann + r.annotated;
    total_det = total_det + r.detected;
    total_TP = total_TP + r.TP;
    total_FP = total_FP + r.FP;
    total_FN = total_FN + r.FN;
end

overall_se = total_TP / (total_TP + total_FN) * 100;
overall_pp = total_TP / (total_TP + total_FP) * 100;
overall_f1 = 2 * (overall_se * overall_pp) / (overall_se + overall_pp);

fprintf('---------|----------|------------|------|-----|-----|---------|---------|--------\n');
fprintf('  TOTAL  |   %4d   |    %4d    | %4d | %3d | %3d | %6.2f  | %6.2f  | %5.2f\n', ...
    total_ann, total_det, total_TP, total_FP, total_FN, ...
    overall_se, overall_pp, overall_f1);
fprintf('=====================================================================\n\n');

%% 4. Direct comparison vs Ozdemir 2011
diff_se = overall_se - ozdemir_se;

fprintf('=== COMPARACION DIRECTA ===\n');
fprintf('Ozdemir 2011 (ANN+PCA, 4 registros):      Se = %.2f%%\n', ozdemir_se);
fprintf('Proyecto propio (Pan-Tompkins, mismos 4): Se = %.2f%%\n', overall_se);
if diff_se >= 0
    fprintf('Diferencia: +%.2f puntos porcentuales (proyecto propio mayor)\n', diff_se);
else
    fprintf('Diferencia: %.2f puntos porcentuales (Ozdemir mayor)\n', diff_se);
end
fprintf('=====================================================================\n');

%% 5. Save results
save('comparison_ozdemir4_results.mat', 'results', 'total_TP', 'total_FP', 'total_FN', ...
     'overall_se', 'overall_pp', 'overall_f1', 'ozdemir_se');

fprintf('\nResultados guardados en comparison_ozdemir4_results.mat\n');
fprintf('compare_ozdemir4 completado exitosamente.\n');


%% ====================================================================
%  LOCAL FUNCTIONS (idénticas a las usadas en validate_sensitivity.m)
%  ====================================================================

function ann_samples = read_annotations(record, n_samples)
% READ_ANNOTATIONS - Read MIT-BIH annotation file (.atr)
% Returns sample indices of all beat annotations

    atr_file = [record '.atr'];
    fid = fopen(atr_file, 'r');
    if fid == -1
        error('Annotation file not found: %s', atr_file);
    end

    bytes = fread(fid, inf, 'uint8');
    fclose(fid);

    % Beat type codes (all types that represent a heartbeat)
    beat_types = [1 2 3 4 5 6 7 8 9 10 11 12 13 34 38];

    ann_samples = [];
    current_sample = 0;
    i = 1;

    while i <= length(bytes) - 1
        low_byte = bytes(i);
        high_byte = bytes(i + 1);
        i = i + 2;

        ann_type = bitshift(high_byte, -2);
        time_delta = bitor(low_byte, bitand(high_byte, 3) * 256);

        if ann_type == 59
            % SKIP: next 4 bytes contain large time offset
            if i + 3 <= length(bytes)
                skip_low = bytes(i) + bytes(i+1) * 256;
                skip_high = bytes(i+2) + bytes(i+3) * 256;
                current_sample = current_sample + skip_low + skip_high * 65536;
                i = i + 4;
            else
                break;
            end
        elseif ann_type == 63
            % AUX: auxiliary information, skip data bytes
            aux_len = time_delta;
            if mod(aux_len, 2) ~= 0
                aux_len = aux_len + 1;
            end
            i = i + aux_len;
        elseif ann_type == 0
            continue;
        else
            current_sample = current_sample + time_delta;
            if ismember(ann_type, beat_types) && current_sample <= n_samples
                ann_samples = [ann_samples; current_sample]; %#ok<AGROW>
            end
        end
    end
end


function [TP, FP, FN] = match_peaks(ann_peaks, det_peaks, tolerance)
% MATCH_PEAKS - Match detected peaks against annotated peaks
% A detection is a True Positive if it falls within 'tolerance' samples
% of an annotation. Each annotation can only be matched once.

    n_ann = length(ann_peaks);
    n_det = length(det_peaks);

    matched_ann = false(n_ann, 1);
    matched_det = false(n_det, 1);

    for d = 1:n_det
        distances = abs(ann_peaks - det_peaks(d));
        [min_dist, min_idx] = min(distances);

        if min_dist <= tolerance && ~matched_ann(min_idx)
            matched_ann(min_idx) = true;
            matched_det(d) = true;
        end
    end

    TP = sum(matched_det);
    FP = n_det - TP;
    FN = n_ann - sum(matched_ann);
end
