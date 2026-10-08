%% RATE CLASSIFIER VALIDATION WITHOUT THE ATRIAL FIBRILLATION BRANCH
% Project: Cardiac arrhythmia detection system - FPGA DE1-SoC
% Universidad Tecnologica del Peru (UTP)
%
% Evalua el clasificador restringido a tres estados basados en la
% frecuencia cardiaca instantanea, sin la rama de fibrilacion auricular:
%
%   Bradicardia : BPM < 60
%   Taquicardia : BPM > 100
%   Normal      : resto
%
% La prediccion se deriva del BPM que el hardware entrego en cada
% latido (fichero vhdl_beats_*.txt), de modo que la cadena evaluada es
% la completa: deteccion QRS, calculo de RR y conversion a BPM en punto
% fijo. Solo se omite la decision de FA.
%
% La verdad de referencia se calcula sobre los intervalos RR de las
% anotaciones de cardiologo, con los mismos umbrales.
%
% Se reportan dos escenarios:
%   (a) todos los latidos
%   (b) excluyendo los episodios anotados como (AFIB o (AFL, donde el
%       ritmo es irregular por definicion y la frecuencia instantanea
%       no admite una interpretacion diagnostica directa

clc; clear;

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

class_names = {'Normal','Bradicardia','Taquicardia'};

if ~isfile('rhythm_episodes.mat')
    error('Falta rhythm_episodes.mat: ejecutar audit_rhythm_annotations.m');
end
S = load('rhythm_episodes.mat');

fprintf('=== CLASIFICADOR DE FRECUENCIA, SIN RAMA DE FA ===\n');
fprintf('Umbrales: bradicardia < %d BPM, taquicardia > %d BPM\n\n', ...
        BPM_BRADI, BPM_TAQUI);

CM_all    = zeros(3,3);   % 48 registros, todos los latidos
CM_44     = zeros(3,3);   % 44 registros sin marcapasos
CM_noafib = zeros(3,3);   % 44 registros, excluyendo episodios de FA

fprintf('Rec  | Emparejados | Aciertos | Exactitud\n');
fprintf('-----|-------------|----------|----------\n');

for k = 1:numel(records)
    rec = records{k};

    ann = read_beats(rec, 650000);
    ep  = get_episodes(S, rec);

    beats_file = [batch_dir 'vhdl_beats_' rec '.txt'];
    if ~isfile(beats_file)
        continue;
    end
    V = read_beats_file(beats_file);
    if isempty(V) || numel(ann) < 3
        continue;
    end

    cm = zeros(3,3);
    cm_na = zeros(3,3);
    n_match = 0;

    for i = 1:size(V,1)
        s_vhdl  = V(i,1);
        bpm_hw  = V(i,2);

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

        cm(truth+1, pred+1) = cm(truth+1, pred+1) + 1;
        n_match = n_match + 1;

        lab = label_at(ep, ann(ix));
        if ~strcmp(lab,'(AFIB') && ~strcmp(lab,'(AFL')
            cm_na(truth+1, pred+1) = cm_na(truth+1, pred+1) + 1;
        end
    end

    acc = 0;
    if n_match > 0
        acc = trace(cm) / n_match * 100;
    end
    fprintf('%s  | %11d | %8d | %7.2f%%\n', ...
            rec, n_match, round(trace(cm)), acc);

    CM_all = CM_all + cm;
    if ~ismember(rec, paced)
        CM_44     = CM_44 + cm;
        CM_noafib = CM_noafib + cm_na;
    end
end

print_report(CM_all,    class_names, 'BASE COMPLETA (48 registros)');
print_report(CM_44,     class_names, 'SIN MARCAPASOS (44 registros, AAMI)');
print_report(CM_noafib, class_names, 'SIN MARCAPASOS NI EPISODIOS DE FA');

save('rate_classifier_results.mat', 'CM_all', 'CM_44', 'CM_noafib', ...
     'class_names');
fprintf('\nGuardado en rate_classifier_results.mat\n');
fprintf('validate_rate_classifier completed successfully.\n');


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


function print_report(CM, names, titulo)
    total = sum(CM(:));
    if total == 0
        return;
    end

    fprintf('\n=====================================================================\n');
    fprintf('   %s\n', titulo);
    fprintf('=====================================================================\n\n');

    fprintf('%-15s |', 'Verdad \ Pred');
    for j = 1:3
        fprintf(' %11s |', names{j});
    end
    fprintf('  Total\n');
    fprintf('----------------|');
    for j = 1:3
        fprintf('-------------|');
    end
    fprintf('--------\n');

    for i = 1:3
        fprintf('%-15s |', names{i});
        for j = 1:3
            fprintf(' %11d |', CM(i,j));
        end
        fprintf(' %6d\n', sum(CM(i,:)));
    end

    fprintf('\nExactitud global: %.2f%%  (%d de %d latidos)\n\n', ...
            trace(CM)/total*100, round(trace(CM)), total);

    fprintf('%-15s | %8s | %8s | %8s | %8s | %8s\n', ...
            'Clase', 'Se(%)', 'Sp(%)', '+P(%)', 'F1(%)', 'N');
    fprintf('----------------|----------|----------|----------|----------|----------\n');

    for i = 1:3
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
