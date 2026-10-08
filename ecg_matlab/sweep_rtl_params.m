%% SWEEP DETECTOR PARAMETERS ON VALIDATED RTL EMULATOR
% Project: Cardiac arrhythmia detection system - FPGA DE1-SoC
% Universidad Tecnologica del Peru (UTP)
%
% Barre los parametros del umbral secundario usando el emulador
% verificado en emulate_rtl.m, que reproduce exactamente la salida de
% ModelSim sobre los mismos ficheros de vectores.
%
% Parametros barridos:
%   VULN_LEN : longitud del umbral secundario, contada desde el pico R
%   VULN_NUM / VULN_DEN : exigencia dentro de esa ventana, expresada
%                         como win_sum > last_peak * NUM / DEN
%
% Todas las fracciones evaluadas son sumas de potencias de dos, por lo
% que son sintetizables con desplazamientos y sumadores.
%
% Las metricas se calculan contra las anotaciones de cardiologo con
% tolerancia de 150 ms (ANSI/AAMI EC57).

clc; clear;

batch_dir = 'D:/proyectos/ecg_arrhythmia/batch/';

recs = {'100','101','102','103','104','105','106','107','108','109', ...
        '111','112','113','114','115','116','117','118','119', ...
        '121','122','123','124', ...
        '200','201','202','203','205','207','208','209','210', ...
        '212','213','214','215','217','219', ...
        '220','221','222','223','228', ...
        '230','231','232','233','234'};

REFRACT   = 72;
THR_INIT  = 512000;
THR_MIN   = 4000;
tolerance = 54;

% VULN_LEN = 0 desactiva el umbral secundario y sirve de referencia
vuln_lens = [180 190 200];

fracs = { '5/2', 5, 2; ...
          '11/4', 11, 4; ...
          '3/1', 3, 1; ...
          '7/2', 7, 2; ...
          '4/1', 4, 1 };

fprintf('=== BARRIDO SOBRE EMULADOR VALIDADO ===\n');
fprintf('Registros: %d | Tolerancia: %d muestras\n\n', numel(recs), tolerance);

%% Precarga de vectores y anotaciones
fprintf('Cargando vectores...\n');
U = cell(numel(recs),1);
A = cell(numel(recs),1);
for k = 1:numel(recs)
    U{k} = read_vectors([batch_dir 'vectors_' recs{k} '.txt']);
    a = readmatrix([batch_dir 'ann_' recs{k} '.txt']);
    A{k} = a(:);
end
fprintf('Listo.\n\n');

%% Barrido
fprintf('VULN_LEN |');
for f = 1:size(fracs,1)
    fprintf('  %s F1  |', fracs{f,1});
end
fprintf('\n---------|');
for f = 1:size(fracs,1)
    fprintf('----------|');
end
fprintf('\n');

best_f1 = -1; best_txt = '';

for v = 1:numel(vuln_lens)
    VL = vuln_lens(v);
    fprintf('%8d |', VL);

    for f = 1:size(fracs,1)
        NUM = fracs{f,2};
        DEN = fracs{f,3};

        TP = 0; FP = 0; FN = 0;

        for k = 1:numel(recs)
            pk = emulate_detector(U{k}, REFRACT, VL, NUM, DEN, ...
                                  THR_INIT, THR_MIN);
            a  = A{k};

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

        fprintf('  %7.2f |', f1);

        if f1 > best_f1
            best_f1  = f1;
            best_txt = sprintf('VULN_LEN=%d  factor=%s  Se=%.2f  +P=%.2f', ...
                               VL, fracs{f,1}, se, pp);
        end
    end
    fprintf('\n');
end

fprintf('\nMejor F1: %.2f\n%s\n', best_f1, best_txt);
fprintf('\nsweep_rtl_params completed successfully.\n');


%% ====================================================================
%  LOCAL FUNCTIONS
%  ====================================================================

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
