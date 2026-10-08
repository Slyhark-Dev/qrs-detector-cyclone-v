%% ANALYZE TACHYCARDIA MISCLASSIFICATION
% Project: Cardiac arrhythmia detection system - FPGA DE1-SoC
% Universidad Tecnologica del Peru (UTP)
%
% La clase taquicardia es la de menor F1 en la Tabla V, con 1,545 latidos
% clasificados como normales. La hipotesis es que ese error no proviene
% del clasificador sino del detector: cuando un latido rapido no se
% detecta, el intervalo RR medido por el hardware abarca dos ciclos, la
% frecuencia resultante se divide aproximadamente por dos y un latido
% taquicardico cae en el rango normal.
%
% El script reproduce la matriz de confusion como control y, para cada
% error de taquicardia a normal, comprueba si la anotacion inmediatamente
% anterior fue detectada por el hardware.
%
% Lee los mismos ficheros que validate_rate_classifier.m, de modo que el
% total de errores debe reproducir exactamente el valor publicado.

clc; clear;

%% 1. Configuracion

batch_dir = 'D:/proyectos/ecg_arrhythmia/batch/';

records = {'100','101','102','103','104','105','106','107','108','109', ...
           '111','112','113','114','115','116','117','118','119', ...
           '121','122','123','124', ...
           '200','201','202','203','205','207','208','209','210', ...
           '212','213','214','215','217','219', ...
           '220','221','222','223','228', ...
           '230','231','232','233','234'};

paced = {'102','104','107','217'};

fs        = 360;
tolerance = 54;
BPM_BRADI = 60;
BPM_TAQUI = 100;

BLOCK_END = 161;   % fin de la ventana vulnerable, en muestras

n_rec = numel(records);

fprintf('=== ERRORES DE TAQUICARDIA CLASIFICADA COMO NORMAL ===\n\n');

%% 2. Recorrido

CM = zeros(3,3);

rec_taq_norm   = zeros(n_rec,1);   % errores taquicardia -> normal
rec_prev_lost  = zeros(n_rec,1);   % de esos, con el latido previo no detectado
rec_prev_short = zeros(n_rec,1);   % de esos, ademas con RR anotado <= BLOCK_END
rec_taq_total  = zeros(n_rec,1);   % latidos taquicardicos evaluados

fprintf('Procesando...\n');
t0 = tic;

for k = 1:n_rec
    rec = records{k};

    beats_file = [batch_dir 'vhdl_beats_' rec '.txt'];
    if ~isfile(beats_file)
        fprintf('  falta %s\n', beats_file);
        continue;
    end

    ann = read_annotations(rec, 650000);
    V   = read_beats_file(beats_file);

    if isempty(V) || numel(ann) < 3
        continue;
    end

    det = V(:,1);

    % que anotaciones detecto el hardware
    matched = match_annotations(ann, det, tolerance);

    for i = 1:size(V,1)
        s_vhdl = V(i,1);
        bpm_hw = V(i,2);

        [dd, ix] = min(abs(ann - s_vhdl));
        if dd > tolerance || ix < 2
            continue;
        end

        rr = ann(ix) - ann(ix-1);
        if rr <= 0
            continue;
        end
        bpm_ref = 21600 / rr;

        pred  = rate_class(bpm_hw,  BPM_BRADI, BPM_TAQUI);
        truth = rate_class(bpm_ref, BPM_BRADI, BPM_TAQUI);

        if ~ismember(rec, paced)
            CM(truth+1, pred+1) = CM(truth+1, pred+1) + 1;

            if truth == 2
                rec_taq_total(k) = rec_taq_total(k) + 1;
            end

            % error taquicardia -> normal
            if truth == 2 && pred == 0
                rec_taq_norm(k) = rec_taq_norm(k) + 1;

                if ~matched(ix-1)
                    rec_prev_lost(k) = rec_prev_lost(k) + 1;
                    if rr <= BLOCK_END
                        rec_prev_short(k) = rec_prev_short(k) + 1;
                    end
                end
            end
        end
    end
end

fprintf('Procesado en %.1f s\n\n', toc(t0));

%% 3. Control

total   = sum(CM(:));
acc     = trace(CM) / total * 100;
taq_nor = CM(3,1);

fprintf('=====================================================================\n');
fprintf('   CONTROL CONTRA LAS CIFRAS PUBLICADAS\n');
fprintf('=====================================================================\n\n');
fprintf('Ronda anterior: 100,184 latidos, exactitud 95.33%%, 1,545 taqui -> normal\n');
fprintf('Obtenido : %d latidos, exactitud %.2f%%, %d taqui -> normal\n\n', ...
        total, acc, taq_nor);

if total == 100184 && taq_nor == 1545
    fprintf('El control reproduce las cifras publicadas.\n\n');
else
    fprintf('ATENCION: el control no reproduce las cifras publicadas.\n');
    fprintf('Interpretar el desglose con cautela.\n\n');
end

%% 4. Mecanismo

prev_lost  = sum(rec_prev_lost);
prev_short = sum(rec_prev_short);

fprintf('=====================================================================\n');
fprintf('   MECANISMO DEL ERROR\n');
fprintf('=====================================================================\n\n');
fprintf('Errores de taquicardia clasificada como normal : %d\n', sum(rec_taq_norm));
fprintf('  con el latido anterior no detectado          : %d  (%.1f%%)\n', ...
        prev_lost, safe_pct(prev_lost, sum(rec_taq_norm)));
fprintf('    y ademas con RR anotado <= %d muestras     : %d  (%.1f%%)\n\n', ...
        BLOCK_END, prev_short, safe_pct(prev_short, sum(rec_taq_norm)));

if safe_pct(prev_lost, sum(rec_taq_norm)) > 60
    fprintf('El error del clasificador es, en su mayor parte, propagacion de\n');
    fprintf('un fallo de deteccion y no un error de la regla de decision.\n');
elseif safe_pct(prev_lost, sum(rec_taq_norm)) > 25
    fprintf('Una fraccion apreciable del error proviene de fallos de\n');
    fprintf('deteccion, pero no explica la mayoria.\n');
else
    fprintf('El error no se explica por fallos de deteccion. Se concentra\n');
    fprintf('probablemente cerca de la frontera de %d BPM.\n', BPM_TAQUI);
end

%% 5. Desglose por registro

fprintf('\n=====================================================================\n');
fprintf('   DESGLOSE POR REGISTRO\n');
fprintf('=====================================================================\n\n');

[~, ord] = sort(rec_taq_norm, 'descend');

fprintf('Rec  | Taqui evaluados | Taqui->Normal | Previo perdido | %% explicado\n');
fprintf('-----|-----------------|---------------|----------------|------------\n');

acum = 0;
for j = 1:n_rec
    k = ord(j);
    if rec_taq_norm(k) == 0
        break;
    end
    acum = acum + rec_taq_norm(k);
    fprintf('%s  | %15d | %13d | %14d | %10.1f%%\n', ...
            records{k}, rec_taq_total(k), rec_taq_norm(k), ...
            rec_prev_lost(k), safe_pct(rec_prev_lost(k), rec_taq_norm(k)));
end

fprintf('\nRegistros con al menos un error: %d\n', sum(rec_taq_norm > 0));

[~, ord5] = sort(rec_taq_norm, 'descend');
top5 = sum(rec_taq_norm(ord5(1:min(5,n_rec))));
fprintf('Los cinco registros con mas errores concentran %d de %d (%.1f%%)\n', ...
        top5, sum(rec_taq_norm), safe_pct(top5, sum(rec_taq_norm)));

%% 6. Guardar

save('tachy_error_results.mat', 'records', 'CM', 'rec_taq_norm', ...
     'rec_prev_lost', 'rec_prev_short', 'rec_taq_total', 'BLOCK_END');

fprintf('\nGuardado en tachy_error_results.mat\n');
fprintf('analyze_tachy_errors completed successfully.\n');


%% ====================================================================
%  LOCAL FUNCTIONS
%  ====================================================================

function c = rate_class(bpm, lo, hi)
    if bpm < lo
        c = 1;
    elseif bpm > hi
        c = 2;
    else
        c = 0;
    end
end


function p = safe_pct(a, b)
    if b > 0
        p = a / b * 100;
    else
        p = 0;
    end
end


function matched_ann = match_annotations(ann_peaks, det_peaks, tolerance)
    n_ann = numel(ann_peaks);
    matched_ann = false(n_ann, 1);

    for d = 1:numel(det_peaks)
        distances = abs(ann_peaks - det_peaks(d));
        [min_dist, min_idx] = min(distances);

        if min_dist <= tolerance && ~matched_ann(min_idx)
            matched_ann(min_idx) = true;
        end
    end
end


function V = read_beats_file(fname)
% Copia literal de la funcion homonima de validate_rate_classifier.m.
    fid = fopen(fname, 'r');
    C = textscan(fid, '%f %f %f %s %s', 'CommentStyle', '#');
    fclose(fid);

    n = numel(C{1});
    V = zeros(n, 5);
    V(:,1) = C{1};
    V(:,2) = C{2};
    V(:,3) = C{3};
    for i = 1:n
        V(i,4) = bin2dec(C{4}{i});
        V(i,5) = bin2dec(C{5}{i});
    end
end


function ann_samples = read_annotations(record, n_samples)
% Copia literal de la funcion homonima de validate_sensitivity.m.

    atr_file = [record '.atr'];
    fid = fopen(atr_file, 'r');
    if fid == -1
        error('Annotation file not found: %s', atr_file);
    end

    bytes = fread(fid, inf, 'uint8');
    fclose(fid);

    beat_types = [1 2 3 4 5 6 7 8 9 10 11 12 13 34 38];

    ann_samples = [];
    current_sample = 0;
    i = 1;

    while i <= length(bytes) - 1
        low_byte  = bytes(i);
        high_byte = bytes(i + 1);
        i = i + 2;

        ann_type   = bitshift(high_byte, -2);
        time_delta = bitor(low_byte, bitand(high_byte, 3) * 256);

        if ann_type == 0
            break;

        elseif ann_type == 59
            if i + 3 <= length(bytes)
                hi_word = bytes(i)   + bytes(i+1) * 256;
                lo_word = bytes(i+2) + bytes(i+3) * 256;
                current_sample = current_sample + hi_word * 65536 + lo_word;
                i = i + 4;
            else
                break;
            end

        elseif ann_type == 63
            aux_len = time_delta;
            if mod(aux_len, 2) ~= 0
                aux_len = aux_len + 1;
            end
            i = i + aux_len;

        elseif ann_type == 60 || ann_type == 61 || ann_type == 62
            continue;

        else
            current_sample = current_sample + time_delta;
            if ismember(ann_type, beat_types) && current_sample <= n_samples
                ann_samples = [ann_samples; current_sample]; %#ok<AGROW>
            end
        end
    end
end
