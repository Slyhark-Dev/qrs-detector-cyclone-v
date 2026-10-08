%% PARAMETER SELECTION ON DS1, EVALUATION ON DS2
% Project: Cardiac arrhythmia detection system - FPGA DE1-SoC
% Universidad Tecnologica del Peru (UTP)
%
% Division inter-paciente de la base MIT-BIH segun de Chazal et al.
% (IEEE TBME 51(7), 2004). DS1 y DS2 contienen 22 registros cada uno,
% sin solapamiento de sujetos. Los cuatro registros con marcapasos
% (102, 104, 107, 217) quedan excluidos conforme a ANSI/AAMI EC57.
%
% Los parametros del umbral secundario se seleccionan unicamente sobre
% DS1. DS2 se evalua una sola vez, con los parametros ya fijados, y es
% la cifra que debe reportarse.
%
% Emplea el emulador verificado contra ModelSim con coincidencia exacta
% de indices de muestra.

clc; clear;

batch_dir = 'D:/proyectos/ecg_arrhythmia/batch/';

DS1 = {'101','106','108','109','112','114','115','116','118','119', ...
       '122','124','201','203','205','207','208','209','215','220', ...
       '223','230'};

DS2 = {'100','103','105','111','113','117','121','123','200','202', ...
       '210','212','213','214','219','221','222','228','231','232', ...
       '233','234'};

REFRACT   = 72;
THR_INIT  = 512000;
THR_MIN   = 4000;
tolerance = 54;

vuln_lens = [0 120 160 180 200 220 260];

fracs = { '1/1',  1, 1; ...
          '3/2',  3, 2; ...
          '2/1',  2, 1; ...
          '5/2',  5, 2; ...
          '3/1',  3, 1; ...
          '4/1',  4, 1 };

fprintf('=== SELECCION EN DS1, EVALUACION EN DS2 ===\n');
fprintf('DS1: %d registros | DS2: %d registros\n', numel(DS1), numel(DS2));
fprintf('Excluidos por marcapasos (AAMI): 102, 104, 107, 217\n');
fprintf('Tolerancia: %d muestras (%.0f ms)\n\n', tolerance, tolerance/360*1000);

%% 1. Precarga
fprintf('Cargando DS1...\n');
[U1, A1] = load_set(DS1, batch_dir);
fprintf('Cargando DS2...\n');
[U2, A2] = load_set(DS2, batch_dir);
fprintf('Listo.\n\n');

%% 2. Barrido sobre DS1
fprintf('--- BARRIDO SOBRE DS1 (seleccion de parametros) ---\n\n');
fprintf('VULN_LEN |');
for f = 1:size(fracs,1)
    fprintf(' %6s |', fracs{f,1});
end
fprintf('\n---------|');
for f = 1:size(fracs,1)
    fprintf('--------|');
end
fprintf('\n');

best_f1  = -1;
best_vl  = 0;
best_num = 1;
best_den = 1;
best_lbl = '';

for v = 1:numel(vuln_lens)
    VL = vuln_lens(v);
    fprintf('%8d |', VL);

    for f = 1:size(fracs,1)
        [se, pp, f1] = eval_set(U1, A1, REFRACT, VL, ...
                                fracs{f,2}, fracs{f,3}, ...
                                THR_INIT, THR_MIN, tolerance);
        fprintf(' %6.2f |', f1);

        if f1 > best_f1
            best_f1  = f1;
            best_vl  = VL;
            best_num = fracs{f,2};
            best_den = fracs{f,3};
            best_lbl = fracs{f,1};
        end
    end
    fprintf('\n');
end

fprintf('\nParametros seleccionados en DS1:\n');
fprintf('  VULN_LEN = %d muestras (%.0f ms)\n', best_vl, best_vl/360*1000);
fprintf('  Exigencia = %s de la energia del ultimo complejo\n', best_lbl);
fprintf('  F1 en DS1 = %.2f%%\n\n', best_f1);

%% 3. Evaluacion unica sobre DS2
fprintf('--- EVALUACION SOBRE DS2 (conjunto no usado en la seleccion) ---\n\n');

[se1, pp1, f11, TP1, FP1, FN1] = eval_set(U1, A1, REFRACT, best_vl, ...
        best_num, best_den, THR_INIT, THR_MIN, tolerance);
[se2, pp2, f12, TP2, FP2, FN2] = eval_set(U2, A2, REFRACT, best_vl, ...
        best_num, best_den, THR_INIT, THR_MIN, tolerance);

fprintf('Conjunto | Reg |    TP |   FP |   FN |     Se |     +P |     F1\n');
fprintf('---------|-----|-------|------|------|--------|--------|-------\n');
fprintf('DS1      | %3d | %5d | %4d | %4d | %6.2f | %6.2f | %6.2f\n', ...
        numel(DS1), TP1, FP1, FN1, se1, pp1, f11);
fprintf('DS2      | %3d | %5d | %4d | %4d | %6.2f | %6.2f | %6.2f\n', ...
        numel(DS2), TP2, FP2, FN2, se2, pp2, f12);
fprintf('---------|-----|-------|------|------|--------|--------|-------\n');

TPt = TP1 + TP2; FPt = FP1 + FP2; FNt = FN1 + FN2;
set = TPt/(TPt+FNt)*100; ppt = TPt/(TPt+FPt)*100;
fprintf('DS1+DS2  | %3d | %5d | %4d | %4d | %6.2f | %6.2f | %6.2f\n', ...
        numel(DS1)+numel(DS2), TPt, FPt, FNt, set, ppt, ...
        2*set*ppt/(set+ppt));

fprintf('\nLa cifra a reportar como desempeno del detector es la de DS2.\n');
fprintf('La diferencia DS1 - DS2 en F1 es %.2f puntos.\n', f11 - f12);

save('ds1_ds2_results.mat', 'best_vl', 'best_num', 'best_den', ...
     'se1','pp1','f11','se2','pp2','f12', 'DS1','DS2');

fprintf('\nsweep_ds1_ds2 completed successfully.\n');


%% ====================================================================
%  LOCAL FUNCTIONS
%  ====================================================================

function [U, A] = load_set(recs, batch_dir)
    U = cell(numel(recs),1);
    A = cell(numel(recs),1);
    for k = 1:numel(recs)
        U{k} = read_vectors([batch_dir 'vectors_' recs{k} '.txt']);
        a = readmatrix([batch_dir 'ann_' recs{k} '.txt']);
        A{k} = a(:);
    end
end


function [se, pp, f1, TP, FP, FN] = eval_set(U, A, REFRACT, VL, ...
                                    NUM, DEN, THR_INIT, THR_MIN, tolerance)
    TP = 0; FP = 0; FN = 0;
    for k = 1:numel(U)
        pk = emulate_detector(U{k}, REFRACT, VL, NUM, DEN, ...
                              THR_INIT, THR_MIN);
        a = A{k};
        matched = false(numel(a),1);
        t = 0;
        for i = 1:numel(pk)
            [dd, ix] = min(abs(a - pk(i)));
            if dd <= tolerance && ~matched(ix)
                matched(ix) = true;
                t = t + 1;
            end
        end
        TP = TP + t;
        FP = FP + numel(pk) - t;
        FN = FN + numel(a) - sum(matched);
    end
    se = TP / (TP + FN) * 100;
    pp = TP / (TP + FP) * 100;
    f1 = 2 * se * pp / (se + pp);
end


function u = read_vectors(fname)
    fid = fopen(fname, 'r');
    if fid == -1
        error('Vector file not found: %s', fname);
    end
    c = textscan(fid, '%s');
    fclose(fid);
    u = bin2dec(char(c{1}));
end


function peaks = emulate_detector(u, REFRACT, VULN_LEN, VULN_NUM, ...
                                  VULN_DEN, THR_INIT, THR_MIN)
% Emulacion registro a registro de ecg_filter + qrs_detector.
% Verificada contra ModelSim con coincidencia exacta de indices.
% VULN_LEN = 0 desactiva el umbral secundario.

    suma = movsum(u, [7 0]);
    f    = floor(suma / 8);
    f    = f(8:end);
    m    = numel(f);

    d  = [f(1); diff(f)];
    sq = d.^2;
    ws = movsum(sq, [7 0]);

    thr      = THR_INIT;
    last     = 0;
    refr_cnt = 0;
    in_refr  = false;
    vuln_cnt = 0;
    in_vuln  = false;

    peaks = zeros(m,1);
    np    = 0;

    for j = 1:m
        o_in_refr  = in_refr;
        o_refr_cnt = refr_cnt;
        o_in_vuln  = in_vuln;
        o_vuln_cnt = vuln_cnt;
        o_thr      = thr;
        o_last     = last;

        if o_in_refr
            if o_refr_cnt > 0
                refr_cnt = o_refr_cnt - 1;
            else
                in_refr = false;
            end
        end
        if o_in_vuln
            if o_vuln_cnt > 0
                vuln_cnt = o_vuln_cnt - 1;
            else
                in_vuln = false;
            end
        end

        if j >= 8 && ~o_in_refr
            if o_in_vuln
                ok = ws(j) > floor(o_last * VULN_NUM / VULN_DEN);
            else
                ok = true;
            end

            if ws(j) > o_thr && ok
                np = np + 1;
                peaks(np) = j;

                thr  = floor(o_thr/2) + floor(o_thr/4) + floor(ws(j)/4);
                last = ws(j);

                refr_cnt = REFRACT;
                in_refr  = true;
                if VULN_LEN > 0
                    vuln_cnt = VULN_LEN;
                    in_vuln  = true;
                end
            else
                dec = floor(o_thr/64) + 1;
                if o_thr > THR_MIN + dec
                    thr = o_thr - dec;
                else
                    thr = THR_MIN;
                end
            end
        end
    end

    peaks = peaks(1:np);
end
