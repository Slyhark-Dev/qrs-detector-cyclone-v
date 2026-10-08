%% CLASSIFIER VALIDATION AGAINST CLINICAL GROUND TRUTH
% Project: Cardiac arrhythmia detection system - FPGA DE1-SoC
% Universidad Tecnologica del Peru (UTP)
%
% Evalua la salida del clasificador implementado en hardware contra una
% verdad de referencia construida a partir de las anotaciones del
% MIT-BIH Arrhythmia Database.
%
% Definicion de la verdad de referencia, alineada con el criterio que
% implementa classifier.vhd:
%
%   Fibrilacion auricular : el latido cae dentro de un episodio
%                           anotado como (AFIB o (AFL
%   Bradicardia           : BPM < 60, con BPM = 21600 / RR en muestras
%   Taquicardia           : BPM > 100, misma definicion
%   Normal                : resto de casos
%
% Prioridad FA > bradicardia > taquicardia, igual que en el RTL.
%
% Los episodios de ritmo proceden de audit_rhythm_annotations.m; las
% predicciones proceden de los ficheros vhdl_beats_*.txt generados por
% la simulacion en lote.

clc; clear;

batch_dir = 'D:/proyectos/ecg_arrhythmia/batch/';

records = {'100','101','102','103','104','105','106','107','108','109', ...
           '111','112','113','114','115','116','117','118','119', ...
           '121','122','123','124', ...
           '200','201','202','203','205','207','208','209','210', ...
           '212','213','214','215','217','219', ...
           '220','221','222','223','228', ...
           '230','231','232','233','234'};

paced = {'102','104','107','217'};   % excluidos por ANSI/AAMI EC57

fs        = 360;
tolerance = 54;                      % 150 ms
BPM_BRADI = 60;
BPM_TAQUI = 100;

class_names = {'Normal','Bradicardia','Taquicardia','Fib. auricular'};

if ~isfile('rhythm_episodes.mat')
    error('Falta rhythm_episodes.mat: ejecutar audit_rhythm_annotations.m');
end
S = load('rhythm_episodes.mat');

fprintf('=== VALIDACION DEL CLASIFICADOR ===\n');
fprintf('Tolerancia de emparejamiento: %d muestras (%.0f ms)\n', ...
        tolerance, tolerance/fs*1000);
fprintf('Umbrales: bradicardia < %d BPM, taquicardia > %d BPM\n\n', ...
        BPM_BRADI, BPM_TAQUI);

CM_all = zeros(4,4);   % filas verdad, columnas prediccion
CM_44  = zeros(4,4);

fprintf('Rec  | Latidos | Emparejados | Aciertos | Exactitud\n');
fprintf('-----|---------|-------------|----------|----------\n');

for k = 1:numel(records)
    rec = records{k};

    ann = read_beats(rec, 650000);
    ep  = get_episodes(S, rec);

    beats_file = [batch_dir 'vhdl_beats_' rec '.txt'];
    if ~isfile(beats_file)
        fprintf('%s: falta %s\n', rec, beats_file);
        continue;
    end
    V = read_beats_file(beats_file);

    if isempty(V) || numel(ann) < 6
        continue;
    end

    cm = zeros(4,4);
    n_match = 0;

    for i = 1:size(V,1)
        s_vhdl = V(i,1);
        pred   = V(i,4);              % codigo 0..3

        % emparejar con la anotacion de latido mas cercana
        [dd, ix] = min(abs(ann - s_vhdl));
        if dd > tolerance || ix < 2
            continue;
        end

        % BPM de referencia a partir del intervalo RR anotado
        rr = ann(ix) - ann(ix-1);
        if rr <= 0
            continue;
        end
        bpm_ref = 21600 / rr;

        % etiqueta de ritmo en esa posicion
        lab = label_at(ep, ann(ix));

        if strcmp(lab,'(AFIB') || strcmp(lab,'(AFL')
            truth = 3;
        elseif bpm_ref < BPM_BRADI
            truth = 1;
        elseif bpm_ref > BPM_TAQUI
            truth = 2;
        else
            truth = 0;
        end

        cm(truth+1, pred+1) = cm(truth+1, pred+1) + 1;
        n_match = n_match + 1;
    end

    acc = 0;
    if n_match > 0
        acc = trace(cm) / n_match * 100;
    end

    fprintf('%s  | %7d | %11d | %8d | %7.2f%%\n', ...
            rec, numel(ann), n_match, round(trace(cm)), acc);

    CM_all = CM_all + cm;
    if ~ismember(rec, paced)
        CM_44 = CM_44 + cm;
    end
end

%% Resultados
print_report(CM_all, class_names, 'BASE COMPLETA (48 registros)');
print_report(CM_44,  class_names, 'SIN MARCAPASOS (44 registros, AAMI)');

save('classifier_results.mat', 'CM_all', 'CM_44', 'class_names');
fprintf('\nGuardado en classifier_results.mat\n');
fprintf('validate_classifier completed successfully.\n');


%% ====================================================================
%  LOCAL FUNCTIONS
%  ====================================================================

function print_report(CM, names, titulo)
    fprintf('\n=====================================================================\n');
    fprintf('   %s\n', titulo);
    fprintf('=====================================================================\n\n');

    fprintf('MATRIZ DE CONFUSION (filas = verdad, columnas = prediccion)\n\n');
    fprintf('%-15s |', 'Verdad \ Pred');
    for j = 1:4
        fprintf(' %10s |', names{j}(1:min(10,end)));
    end
    fprintf('  Total\n');
    fprintf('----------------|');
    for j = 1:4
        fprintf('------------|');
    end
    fprintf('--------\n');

    for i = 1:4
        fprintf('%-15s |', names{i});
        for j = 1:4
            fprintf(' %10d |', CM(i,j));
        end
        fprintf(' %6d\n', sum(CM(i,:)));
    end

    total = sum(CM(:));
    fprintf('\nExactitud global: %.2f%%  (%d de %d latidos)\n\n', ...
            trace(CM)/total*100, round(trace(CM)), total);

    fprintf('METRICAS POR CLASE\n\n');
    fprintf('%-15s | %8s | %8s | %8s | %8s | %8s\n', ...
            'Clase', 'Se(%)', 'Sp(%)', '+P(%)', 'F1(%)', 'N');
    fprintf('----------------|----------|----------|----------|----------|----------\n');

    for i = 1:4
        TP = CM(i,i);
        FN = sum(CM(i,:)) - TP;
        FP = sum(CM(:,i)) - TP;
        TN = total - TP - FN - FP;

        se = safe_div(TP, TP+FN);
        sp = safe_div(TN, TN+FP);
        pp = safe_div(TP, TP+FP);
        if se+pp > 0
            f1 = 2*se*pp/(se+pp);
        else
            f1 = 0;
        end

        fprintf('%-15s | %8.2f | %8.2f | %8.2f | %8.2f | %8d\n', ...
                names{i}, se, sp, pp, f1, sum(CM(i,:)));
    end
end


function r = safe_div(a, b)
    if b > 0
        r = a / b * 100;
    else
        r = 0;
    end
end


function ep = get_episodes(S, rec)
    ep = [];
    for k = 1:numel(S.episodes)
        if strcmp(S.episodes(k).record, rec)
            ep = S.episodes(k).episodes;
            return;
        end
    end
end


function lab = label_at(ep, sample)
    lab = '(N';
    for j = 1:numel(ep)
        if sample >= ep(j).start && sample < ep(j).stop
            lab = ep(j).label;
            return;
        end
    end
end


function V = read_beats_file(fname)
% Lee sample bpm rr code alert; code y alert vienen en binario de 2 bits
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


function ann_samples = read_beats(record, n_samples)
% Lector de anotaciones de latido conforme al formato WFDB

    fid = fopen([record '.atr'], 'r');
    if fid == -1
        error('Annotation file not found: %s.atr', record);
    end
    bytes = fread(fid, inf, 'uint8');
    fclose(fid);

    beat_types = [1 2 3 4 5 6 7 8 9 10 11 12 13 34 38];

    ann_samples = [];
    current_sample = 0;
    i = 1;

    while i <= numel(bytes) - 1
        low_byte  = bytes(i);
        high_byte = bytes(i + 1);
        i = i + 2;

        ann_type   = bitshift(high_byte, -2);
        time_delta = bitor(low_byte, bitand(high_byte, 3) * 256);

        if ann_type == 0
            break;
        elseif ann_type == 59
            if i + 3 <= numel(bytes)
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
        elseif ann_type >= 60 && ann_type <= 62
            continue;
        else
            current_sample = current_sample + time_delta;
            if ismember(ann_type, beat_types) && current_sample <= n_samples
                ann_samples(end+1, 1) = current_sample; %#ok<AGROW>
            end
        end
    end
end
