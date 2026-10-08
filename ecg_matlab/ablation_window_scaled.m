%% INTEGRATION WINDOW ABLATION WITH ANALYTICALLY SCALED FLOOR
% Project: Cardiac arrhythmia detection system - FPGA DE1-SoC
% Universidad Tecnologica del Peru (UTP)
%
% Ablacion de la ventana de integracion con el piso del umbral escalado
% en proporcion al ancho.
%
% La energia acumulada crece linealmente con el numero de terminos
% sumados, de modo que un piso fijo en valor absoluto deja de ser
% comparable al cambiar el ancho: con una ventana mayor el piso queda
% relativamente mas bajo y el umbral desciende hasta el nivel del ruido.
% Para aislar el efecto del ancho se escala el piso como
%
%     THR_MIN(W) = THR_MIN_BASE * W / 8
%
% que es la relacion analitica, no un ajuste sobre datos. Con W = 8 el
% piso conserva el valor del RTL compilado, de modo que esa fila debe
% reproducir exactamente las cifras publicadas. Esa coincidencia es el
% control del experimento.
%
% Pan-Tompkins especifica una ventana de 0.15*fs, esto es 54 muestras a
% 360 Hz. La implementacion usa 8.
%
% Se reporta ademas el desfase entre cada deteccion y su anotacion
% emparejada, que caracteriza el error de localizacion del punto
% fiducial y su dependencia del ancho de la ventana.

clc; clear;

records = {'100','101','102','103','104','105','106','107','108','109', ...
           '111','112','113','114','115','116','117','118','119', ...
           '121','122','123','124', ...
           '200','201','202','203','205','207','208','209','210', ...
           '212','213','214','215','217','219', ...
           '220','221','222','223','228', ...
           '230','231','232','233','234'};

ds1 = {'101','106','108','109','112','114','115','116','118','119', ...
       '122','124','201','203','205','207','208','209','215','220', ...
       '223','230'};

ds2 = {'100','103','105','111','113','117','121','123','200','202', ...
       '210','212','213','214','219','221','222','228','231','232', ...
       '233','234'};

% Parametros del RTL compilado. NINGUNO se modifica.
REFRACT  = 72;
VULN_LEN = 160;
VULN_NUM = 3;
THR_INIT = 512000;
THR_MIN_BASE = 4000;   % piso del RTL compilado, correspondiente a W = 8

fs        = 360;
tolerance = round(0.150 * fs);

margin     = 0.05;
target_min = round(4095 * margin);
target_max = round(4095 * (1 - margin));

W_list = [8 16 27 54];
n_W    = numel(W_list);
n_rec  = numel(records);

fprintf('=== ABLACION DE LA VENTANA DE INTEGRACION ===\n');
fprintf('Parametros del RTL compilado, sin modificar:\n');
fprintf('  REFRACT=%d  VULN_LEN=%d  factor=%d  THR_INIT=%d  THR_MIN=%d\n\n', ...
        REFRACT, VULN_LEN, VULN_NUM, THR_INIT, THR_MIN_BASE);
fprintf('Parametro variado: ancho de la ventana de integracion.\n');
fprintf('El piso y el valor inicial del umbral se escalan como W/8, que es\n');
fprintf('la relacion analitica entre el ancho y la energia acumulada.\n');
fprintf('Anchos: ');
fprintf('%d (%.1f ms)  ', [W_list; W_list/fs*1000]);
fprintf('\nPan-Tompkins especifica 0.15*fs = 54 muestras (150 ms)\n\n');

%% Lectura

sig  = cell(n_rec,1);
anns = cell(n_rec,1);

fprintf('Leyendo registros...\n');
t0 = tic;
for k = 1:n_rec
    [signal, ~, ~, ~, n_samples] = read_mitbih(records{k});
    e = double(signal(:,1));
    sig{k}  = single(scale_to_12bit(e, min(e), max(e), target_min, target_max));
    anns{k} = read_annotations(records{k}, n_samples);
end
fprintf('Lectura completada en %.1f s\n\n', toc(t0));

idx_ds1 = ismember(records, ds1);
idx_ds2 = ismember(records, ds2);
idx_all = true(1, n_rec);

%% Evaluacion

RES = zeros(n_W, 3, 3);
CNT = zeros(n_W, 3);   % TP, FP, FN sobre la base completa

subsets = {idx_ds1, idx_ds2, idx_all};

fprintf('Procesando...\n');
t0 = tic;

THR_MIN_W  = round(THR_MIN_BASE * W_list / 8);
THR_INIT_W = round(THR_INIT      * W_list / 8);

fprintf('%-26s | %10s | %10s\n', 'Ventana', 'THR_MIN', 'THR_INIT');
fprintf('---------------------------|------------|-----------\n');
for a = 1:n_W
    fprintf('%2d muestras (%5.1f ms)      | %10d | %10d\n', ...
            W_list(a), W_list(a)/fs*1000, THR_MIN_W(a), THR_INIT_W(a));
end
fprintf('\n');

for a = 1:n_W
    for s = 1:3
        [se, pp, f1, tp, fp, fn] = eval_subset(sig, anns, subsets{s}, ...
                                    W_list(a), REFRACT, VULN_LEN, VULN_NUM, ...
                                    THR_INIT_W(a), THR_MIN_W(a), tolerance);
        RES(a,s,1) = se; RES(a,s,2) = pp; RES(a,s,3) = f1;
        if s == 3
            CNT(a,:) = [tp fp fn];
        end
    end
end

fprintf('Procesado en %.1f s\n\n', toc(t0));

%% Control

a8 = find(W_list == 8, 1);

fprintf('=====================================================================\n');
fprintf('   CONTROL: ventana de 8 muestras contra las cifras publicadas\n');
fprintf('=====================================================================\n\n');
fprintf('%-22s | %6s | %6s | %6s\n', 'Protocolo', 'Se(%)', '+P(%)', 'F1(%)');
fprintf('-----------------------|--------|--------|-------\n');
fprintf('%-22s | %6.2f | %6.2f | %6.2f\n', 'DS1 publicado',  99.10, 98.66, 98.88);
fprintf('%-22s | %6.2f | %6.2f | %6.2f\n', 'DS1 obtenido',   RES(a8,1,1), RES(a8,1,2), RES(a8,1,3));
fprintf('%-22s | %6.2f | %6.2f | %6.2f\n', 'DS2 publicado',  99.65, 96.53, 98.07);
fprintf('%-22s | %6.2f | %6.2f | %6.2f\n', 'DS2 obtenido',   RES(a8,2,1), RES(a8,2,2), RES(a8,2,3));
fprintf('%-22s | %6.2f | %6.2f | %6.2f\n', '48 publicado',   99.42, 96.63, 98.01);
fprintf('%-22s | %6.2f | %6.2f | %6.2f\n', '48 obtenido',    RES(a8,3,1), RES(a8,3,2), RES(a8,3,3));
fprintf('\nConteos sobre la base completa: TP %d  FP %d  FN %d\n', ...
        CNT(a8,1), CNT(a8,2), CNT(a8,3));
fprintf('Publicado                     : TP 108856  FP 3791  FN 638\n\n');

ok = abs(RES(a8,2,1)-99.65) < 0.02 && abs(RES(a8,2,2)-96.53) < 0.02;
if ok
    fprintf('El control reproduce las cifras publicadas. Las filas de 16, 27\n');
    fprintf('y 54 muestras son comparables y la unica diferencia entre ellas\n');
    fprintf('es el ancho de la ventana.\n\n');
else
    fprintf('ATENCION: el control NO reproduce las cifras publicadas. No\n');
    fprintf('interpretar el resto hasta explicar la discrepancia.\n\n');
end

%% Tabla comparativa

fprintf('=====================================================================\n');
fprintf('   COMPARACION DE ANCHOS, TODOS LOS DEMAS PARAMETROS CONSTANTES\n');
fprintf('=====================================================================\n\n');

nombres = {'DS1 (22)', 'DS2 (22)', 'Base completa (48)'};
for s = 1:3
    fprintf('--- %s ---\n', nombres{s});
    fprintf('%-26s | %6s | %6s | %6s\n', 'Ventana', 'Se(%)', '+P(%)', 'F1(%)');
    fprintf('---------------------------|--------|--------|-------\n');
    for a = 1:n_W
        et = sprintf('%2d muestras (%5.1f ms)', W_list(a), W_list(a)/fs*1000);
        if W_list(a) == 8,  et = [et ' *']; end
        if W_list(a) == 54, et = [et ' PT']; end
        fprintf('%-26s | %6.2f | %6.2f | %6.2f\n', et, ...
                RES(a,s,1), RES(a,s,2), RES(a,s,3));
    end
    fprintf('\n');
end
fprintf('*  configuracion implementada\n');
fprintf('PT ancho especificado por Pan-Tompkins 1985\n\n');

%% Jitter de localizacion

fprintf('=====================================================================\n');
fprintf('   ERROR DE LOCALIZACION DEL PUNTO FIDUCIAL, SOBRE DS2\n');
fprintf('=====================================================================\n\n');
fprintf('Desfase entre cada deteccion y su anotacion emparejada, en muestras.\n');
fprintf('La mediana es retardo de grupo; la dispersion es el jitter que\n');
fprintf('afecta al calculo del intervalo RR.\n\n');
fprintf('%-26s | %8s | %8s | %8s | %8s | %8s\n', ...
        'Ventana', 'mediana', 'MAD', 'IQR', 'SD', 'p1-p99');
fprintf('---------------------------|----------|----------|----------|----------|----------\n');

JIT = zeros(n_W, 5);
for a = 1:n_W
    d_all = [];
    for k = 1:n_rec
        if ~idx_ds2(k), continue; end
        pk = emulate_detector(double(sig{k}), W_list(a), REFRACT, ...
                              VULN_LEN, VULN_NUM, THR_INIT_W(a), THR_MIN_W(a));
        ann = anns{k};
        for j = 1:numel(pk)
            [dd, ix] = min(abs(ann - pk(j)));
            if dd <= tolerance
                d_all(end+1,1) = pk(j) - ann(ix); %#ok<AGROW>
            end
        end
    end
    p = prctile(d_all, [1 99]);
    JIT(a,:) = [median(d_all), median(abs(d_all-median(d_all))), ...
                iqr(d_all), std(d_all), p(2)-p(1)];
    et = sprintf('%2d muestras (%5.1f ms)', W_list(a), W_list(a)/fs*1000);
    fprintf('%-26s | %8.1f | %8.2f | %8.1f | %8.2f | %8.1f\n', ...
            et, JIT(a,1), JIT(a,2), JIT(a,3), JIT(a,4), JIT(a,5));
end

%% Ley de propagacion a frecuencia

fprintf('\n=====================================================================\n');
fprintf('   PROPAGACION DEL JITTER A LA FRECUENCIA CARDIACA\n');
fprintf('=====================================================================\n\n');

sd_loc = JIT(a8,4);
sd_rr  = sd_loc * sqrt(2);

fprintf('Con la ventana implementada, la desviacion de localizacion es de\n');
fprintf('%.2f muestras. El intervalo RR es diferencia de dos localizaciones,\n', sd_loc);
fprintf('de modo que su desviacion es aproximadamente %.2f muestras si los\n', sd_rr);
fprintf('errores son independientes.\n\n');
fprintf('La conversion a frecuencia es inversa, luego\n');
fprintf('    sigma_BPM = sigma_RR * BPM^2 / 21600\n\n');
fprintf('%-12s | %-16s | %s\n', 'Frecuencia', 'RR (muestras)', 'sigma_BPM predicha');
fprintf('-------------|------------------|-------------------\n');
for b = [50 60 75 100 120 150]
    fprintf('%9d   | %14.0f   | %10.2f\n', b, 21600/b, sd_rr*b*b/21600);
end
fprintf('\nLa Tabla VI reporta 3.41 BPM sobre latidos de cadencia consistente,\n');
fprintf('valor que la ley anterior alcanza en torno a %.0f BPM.\n', ...
        sqrt(3.41*21600/sd_rr));

%% Veredicto

a54 = find(W_list == 54, 1);
d   = RES(a54,2,3) - RES(a8,2,3);

fprintf('\n=====================================================================\n');
fprintf('   VEREDICTO\n');
fprintf('=====================================================================\n\n');
fprintf('Sobre DS2: 8 muestras da F1 %.2f, 54 muestras da F1 %.2f\n', ...
        RES(a8,2,3), RES(a54,2,3));

if d < -0.30
    fprintf('\nLa ventana implementada supera a la especificada por Pan-Tompkins\n');
    fprintf('en %.2f puntos de F1. La desviacion no tiene costo: es una\n', -d);
    fprintf('decision de diseno respaldada por los datos y debe declararse\n');
    fprintf('como tal, no como simplificacion.\n');
elseif d > 0.30
    fprintf('\nLa ventana de Pan-Tompkins supera a la implementada en %.2f\n', d);
    fprintf('puntos de F1. La desviacion tiene un costo medible.\n');
else
    fprintf('\nAmbas ventanas son equivalentes dentro de %.2f puntos de F1.\n', abs(d));
end

if JIT(a54,4) > JIT(a8,4)
    fprintf('\nEl jitter de localizacion empeora al ensanchar la ventana, de\n');
    fprintf('%.2f a %.2f muestras. La ventana corta no es la causa del error\n', ...
            JIT(a8,4), JIT(a54,4));
    fprintf('de localizacion.\n');
end

save('window_ablation_scaled.mat', 'records', 'W_list', 'RES', 'CNT', 'JIT', ...
     'THR_MIN_W', 'THR_INIT_W', 'THR_MIN_BASE', 'REFRACT', 'VULN_LEN', 'VULN_NUM');

fprintf('\nGuardado en window_ablation_scaled.mat\n');
fprintf('ablation_window_scaled completed successfully.\n');


%% ====================================================================
%  LOCAL FUNCTIONS
%  ====================================================================

function [se, pp, f1, tp, fp, fn] = eval_subset(sig, anns, mask, W, REFRACT, ...
                                    VULN_LEN, VULN_NUM, THR_INIT, THR_MIN, tolerance)
    idx = find(mask);
    tp = 0; fp = 0; fn = 0;
    for j = 1:numel(idx)
        k  = idx(j);
        pk = emulate_detector(double(sig{k}), W, REFRACT, VULN_LEN, ...
                              VULN_NUM, THR_INIT, THR_MIN);
        [t, f, n] = match_peaks(anns{k}, pk, tolerance);
        tp = tp + t; fp = fp + f; fn = fn + n;
    end
    se = safe_pct(tp, tp+fn);
    pp = safe_pct(tp, tp+fp);
    if se + pp > 0, f1 = 2*se*pp/(se+pp); else, f1 = 0; end
end


function u = scale_to_12bit(e, lo, hi, tmin, tmax)
    rango = hi - lo;
    if rango <= 0, rango = 1; end
    u = round((e - lo) / rango * (tmax - tmin) + tmin);
    u = max(min(u, 4095), 0);
end


function p = safe_pct(a, b)
    if b > 0, p = a / b * 100; else, p = 0; end
end


function peaks = emulate_detector(u, W, REFRACT, VULN_LEN, VULN_NUM, ...
                                  THR_INIT, THR_MIN)
% Igual a la funcion homonima de emulate_rtl.m, con la ventana de
% integracion como parametro. W = 8 reproduce el RTL compilado.

    suma = movsum(u, [7 0]);
    f    = floor(suma / 8);
    f    = f(8:end);
    m    = numel(f);

    d  = [f(1); diff(f)];
    sq = d.^2;

    ws = movsum(sq, [W-1 0]);

    thr = THR_INIT; last = 0;
    refr_cnt = 0; in_refr = false;
    vuln_cnt = 0; in_vuln = false;

    peaks = zeros(m,1); np = 0;

    for j = 1:m
        win_count_full = (j >= W);

        o_in_refr = in_refr;  o_refr_cnt = refr_cnt;
        o_in_vuln = in_vuln;  o_vuln_cnt = vuln_cnt;
        o_thr     = thr;      o_last     = last;

        if o_in_refr
            if o_refr_cnt > 0, refr_cnt = o_refr_cnt - 1; else, in_refr = false; end
        end
        if o_in_vuln
            if o_vuln_cnt > 0, vuln_cnt = o_vuln_cnt - 1; else, in_vuln = false; end
        end

        if win_count_full && ~o_in_refr
            if o_in_vuln
                ok = ws(j) > o_last * VULN_NUM;
            else
                ok = true;
            end

            if ws(j) > o_thr && ok
                np = np + 1; peaks(np) = j;
                thr  = floor(o_thr/2) + floor(o_thr/4) + floor(ws(j)/4);
                last = ws(j);
                refr_cnt = REFRACT; in_refr = true;
                vuln_cnt = VULN_LEN; in_vuln = true;
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


function [TP, FP, FN] = match_peaks(ann_peaks, det_peaks, tolerance)
    n_ann = numel(ann_peaks);
    n_det = numel(det_peaks);
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
            if mod(aux_len, 2) ~= 0, aux_len = aux_len + 1; end
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
