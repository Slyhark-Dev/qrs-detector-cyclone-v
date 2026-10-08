%% DIAGNOSTICO MULTIPLE - 9 REGISTROS DIFICILES
% Proyecto: Deteccion de arritmias FPGA DE1-SoC (UTP)
%
% Analiza los 9 registros que no superan ~60% F1, para entender la causa
% comun y decidir si 90% global es alcanzable.
%
% Para cada registro:
%   - Grafica una ventana de 8 s con senal, anotaciones (verde) y
%     detecciones (rojo)
%   - Mide el DESFASE entre cada deteccion y su anotacion mas cercana
%   - Reporta: % de detecciones dentro de tolerancia, desfase medio,
%     y si hay sobre-deteccion (mas detecciones que latidos reales)
%
% INTERPRETACION:
%   - Desfase pequeno pero pocas dentro de tolerancia -> problema de match
%   - Desfase grande/caotico -> deteccion genuinamente mala
%   - Muchas mas detecciones que anotaciones -> sobre-deteccion (ruido/PVC)
%
% NO modifica nada. Se puede borrar despues.

clc; clear; close all;

records = {'104','105','106','108','200','208','210','217','221'};
fs = 360;

% Probar varias tolerancias para diagnosticar si es desfase sistematico
tol_ms_list = [150 200 250 300 400];   % milisegundos
tol_list = round(tol_ms_list/1000 * fs);

fprintf('\n===========================================================\n');
fprintf('  TEST DE TOLERANCIA - 9 REGISTROS DIFICILES\n');
fprintf('  Si el %%InTol sube mucho al ampliar tolerancia -> desfase\n');
fprintf('  sistematico corregible. Si se queda bajo -> deteccion mala.\n');
fprintf('===========================================================\n');
fprintf('%-6s |', 'Rec');
for m = 1:numel(tol_ms_list)
    fprintf(' %5dms |', tol_ms_list(m));
end
fprintf(' MedDesf\n');
fprintf('-------|');
for m = 1:numel(tol_ms_list), fprintf('--------|'); end
fprintf('---------\n');

for r = 1:numel(records)
    record = records{r};
    [signal, fsr, ~, ~, n_samples] = read_mitbih(record);
    ann = leer_anotaciones_local(record, n_samples);

    % mejor canal por F1 con tolerancia base 150ms
    tol_base = round(0.150*fs);
    bestF1 = -1; det_best = [];
    for ch = 1:size(signal,2)
        d = pan_tompkins_causal(signal(:,ch), fsr, n_samples);
        [tp,fp,fn] = match_local(ann, d, tol_base);
        se = tp/(tp+fn)*100; pp = tp/(tp+fp)*100;
        if (se+pp)>0, f1 = 2*se*pp/(se+pp); else, f1=0; end
        if f1 > bestF1, bestF1 = f1; det_best = d; end
    end
    det = det_best;

    % desfase de cada deteccion a su anotacion mas cercana
    desfases = zeros(numel(det),1);
    for k = 1:numel(det)
        desfases(k) = min(abs(ann - det(k)));
    end
    med_desf = median(desfases);

    fprintf('%-6s |', record);
    for m = 1:numel(tol_list)
        pct = sum(desfases <= tol_list(m)) / max(numel(det),1) * 100;
        fprintf(' %5.1f%% |', pct);
    end
    fprintf(' %4d sm\n', round(med_desf));
end

fprintf('===========================================================\n');
fprintf('Lectura: si una fila pasa de ~45%% (150ms) a ~85%% (300ms),\n');
fprintf('hay desfase sistematico CORREGIBLE. Si se queda baja en todas\n');
fprintf('las columnas, la deteccion es genuinamente mala (ruido/PVC).\n');
fprintf('test completado.\n');


%% ===================== FUNCIONES LOCALES =====================
function [TP,FP,FN] = match_local(ann_peaks, det_peaks, tol)
    n_ann = numel(ann_peaks); n_det = numel(det_peaks);
    matched_ann = false(n_ann,1); matched_det = false(n_det,1);
    for d = 1:n_det
        [mind, idx] = min(abs(ann_peaks - det_peaks(d)));
        if mind <= tol && ~matched_ann(idx)
            matched_ann(idx) = true; matched_det(d) = true;
        end
    end
    TP = sum(matched_det); FP = n_det - TP; FN = n_ann - sum(matched_ann);
end

function ann_samples = leer_anotaciones_local(record, n_samples)
    atr_file = [record '.atr'];
    fid = fopen(atr_file, 'r');
    if fid == -1, error('No se encontro: %s', atr_file); end
    bytes = fread(fid, inf, 'uint8'); fclose(fid);
    beat_types = [1 2 3 4 5 6 7 8 9 10 11 12 13 34 38];
    ann_samples = []; current_sample = 0; i = 1;
    while i <= length(bytes) - 1
        low_byte = bytes(i); high_byte = bytes(i + 1); i = i + 2;
        ann_type = bitshift(high_byte, -2);
        time_delta = bitor(low_byte, bitand(high_byte, 3) * 256);
        if ann_type == 59
            if i + 3 <= length(bytes)
                skip_low = bytes(i) + bytes(i+1) * 256;
                skip_high = bytes(i+2) + bytes(i+3) * 256;
                current_sample = current_sample + skip_low + skip_high * 65536;
                i = i + 4;
            else, break; end
        elseif ann_type == 63
            aux_len = time_delta;
            if mod(aux_len, 2) ~= 0, aux_len = aux_len + 1; end
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
