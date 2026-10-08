%% SWEEP DECAY RATE ON DS1
% Project: Cardiac arrhythmia detection system - FPGA DE1-SoC
% Universidad Tecnologica del Peru (UTP)
%
% Ultimo parametro del detector sin trazabilidad declarada.
%
% El decaimiento del umbral adaptivo se implementa como
%
%     decay = (threshold >> SHIFT) + CONST
%
% con SHIFT = 6 y CONST = 1 en el RTL compilado. Ambos se fijaron por
% barrido sobre la base completa antes de establecer la particion
% inter-paciente. Aqui se repite el barrido restringido a DS1.
%
% El termino constante existe para que el decaimiento no se anule por
% division entera cuando el umbral es pequeno. El barrido incluye
% CONST = 0 para cuantificar ese efecto sobre datos, no por argumento.
%
% Solo se recorren desplazamientos, que es lo realizable en hardware sin
% divisor. El resto de parametros se mantiene en los valores del RTL.
%
% Protocolo: rejilla sobre DS1, seleccion sobre DS1, evaluacion unica del
% punto elegido sobre DS2 y sobre la base completa.

clc; clear;

%% 1. Configuracion

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

% Parametros del RTL compilado
REFRACT  = 72;
VULN_LEN = 160;
VULN_NUM = 3;
THR_INIT = 512000;
THR_MIN  = 4000;

SHIFT_REF = 6;
CONST_REF = 1;

% Rejilla
shift_grid = [3 4 5 6 7 8 9 10];
const_grid = [0 1 2 4];

fs        = 360;
tolerance = round(0.150 * fs);

margin     = 0.05;
target_min = round(4095 * margin);
target_max = round(4095 * (1 - margin));

n_rec = numel(records);

fprintf('=== BARRIDO DE LA TASA DE DECAIMIENTO SOBRE DS1 ===\n');
fprintf('decay = (threshold >> SHIFT) + CONST\n');
fprintf('RTL compilado: SHIFT=%d  CONST=%d\n', SHIFT_REF, CONST_REF);
fprintf('Rejilla: %d desplazamientos x %d constantes = %d puntos\n\n', ...
        numel(shift_grid), numel(const_grid), ...
        numel(shift_grid)*numel(const_grid));

%% 2. Lectura y escalado por registro

anns = cell(n_rec,1);
u    = cell(n_rec,1);

fprintf('Leyendo registros...\n');
t0 = tic;

for k = 1:n_rec
    [signal, ~, ~, ~, n_samples] = read_mitbih(records{k});
    e = double(signal(:,1));

    anns{k} = read_annotations(records{k}, n_samples);
    u{k}    = scale_to_12bit(e, min(e), max(e), target_min, target_max);
end

fprintf('Lectura completada en %.1f s\n\n', toc(t0));

idx_ds1 = ismember(records, ds1);
idx_ds2 = ismember(records, ds2);
idx_all = true(1, n_rec);

%% 3. Rejilla sobre DS1

n_s = numel(shift_grid);
n_c = numel(const_grid);

SE = zeros(n_s, n_c);
PP = zeros(n_s, n_c);
F1 = zeros(n_s, n_c);

fprintf('Recorriendo la rejilla sobre DS1 (%d registros)...\n', sum(idx_ds1));
t0 = tic;

for a = 1:n_s
    for b = 1:n_c
        [se, pp, f1] = eval_subset(u, anns, idx_ds1, REFRACT, VULN_LEN, ...
                                   VULN_NUM, THR_INIT, THR_MIN, ...
                                   shift_grid(a), const_grid(b), tolerance);
        SE(a,b) = se;
        PP(a,b) = pp;
        F1(a,b) = f1;
    end
end

fprintf('Rejilla completada en %.1f s\n\n', toc(t0));

%% 4. Tabla

fprintf('=====================================================================\n');
fprintf('   F1 SOBRE DS1\n');
fprintf('=====================================================================\n\n');

fprintf('%-22s |', 'decay');
for b = 1:n_c
    fprintf(' CONST=%d |', const_grid(b));
end
fprintf('\n');
fprintf('-----------------------|');
for b = 1:n_c
    fprintf('---------|');
end
fprintf('\n');

for a = 1:n_s
    etiqueta = sprintf('thr>>%d  (thr/%d)', shift_grid(a), 2^shift_grid(a));
    fprintf('%-22s |', etiqueta);
    for b = 1:n_c
        fprintf(' %7.2f |', F1(a,b));
    end
    if shift_grid(a) == SHIFT_REF
        fprintf('  <- SHIFT del RTL');
    end
    fprintf('\n');
end

fprintf('\nSensibilidad y predictividad:\n\n');
fprintf('%-22s |', 'decay');
for b = 1:n_c
    fprintf('  CONST=%d    |', const_grid(b));
end
fprintf('\n');
fprintf('-----------------------|');
for b = 1:n_c
    fprintf('--------------|');
end
fprintf('\n');

for a = 1:n_s
    etiqueta = sprintf('thr>>%d  (thr/%d)', shift_grid(a), 2^shift_grid(a));
    fprintf('%-22s |', etiqueta);
    for b = 1:n_c
        fprintf(' %5.2f  %5.2f |', SE(a,b), PP(a,b));
    end
    fprintf('\n');
end

%% 5. Efecto del termino constante

fprintf('\n=====================================================================\n');
fprintf('   EFECTO DEL TERMINO CONSTANTE\n');
fprintf('=====================================================================\n\n');

b0 = find(const_grid == 0, 1);
b1 = find(const_grid == CONST_REF, 1);
a6 = find(shift_grid == SHIFT_REF, 1);

fprintf('Con SHIFT=%d, sobre DS1:\n', SHIFT_REF);
fprintf('  CONST=0 : Se %.2f  +P %.2f  F1 %.2f\n', ...
        SE(a6,b0), PP(a6,b0), F1(a6,b0));
fprintf('  CONST=%d : Se %.2f  +P %.2f  F1 %.2f\n\n', ...
        CONST_REF, SE(a6,b1), PP(a6,b1), F1(a6,b1));

d = F1(a6,b1) - F1(a6,b0);
if abs(d) < 0.01
    fprintf('El termino constante no altera el resultado a este ancho de\n');
    fprintf('palabra: el umbral no llega a valores donde la division entera\n');
    fprintf('se anule, porque el piso lo impide antes.\n');
else
    fprintf('El termino constante aporta %.2f puntos de F1 sobre DS1.\n', d);
end

%% 6. Seleccion sobre DS1 y evaluacion unica

[~, lin] = max(F1(:));
[ia, ib] = ind2sub(size(F1), lin);

SEL_SHIFT = shift_grid(ia);
SEL_CONST = const_grid(ib);

fprintf('\n=====================================================================\n');
fprintf('   TRAZABILIDAD DE LA TASA DE DECAIMIENTO\n');
fprintf('=====================================================================\n\n');
fprintf('RTL compilado         : SHIFT=%d  CONST=%d\n', SHIFT_REF, CONST_REF);
fprintf('Optimo sobre DS1      : SHIFT=%d  CONST=%d\n\n', SEL_SHIFT, SEL_CONST);

if SEL_SHIFT == SHIFT_REF && SEL_CONST == CONST_REF
    fprintf('Coinciden. El valor implementado es reproducible ajustando\n');
    fprintf('solo sobre DS1, sin usar informacion del conjunto de\n');
    fprintf('evaluacion.\n');
else
    fprintf('No coinciden. Diferencia de F1 en DS1: %.2f puntos.\n', ...
            F1(ia,ib) - F1(a6,b1));
end

if ia == 1 || ia == n_s
    fprintf('\nAVISO: el optimo cae en el borde de la rejilla de\n');
    fprintf('desplazamientos. Conviene ampliarla.\n');
end

%% 7. Comparacion final

fprintf('\n=====================================================================\n');
fprintf('   COMPARACION FINAL\n');
fprintf('=====================================================================\n\n');

final_cases = { ...
  sprintf('RTL: SHIFT=%d CONST=%d', SHIFT_REF, CONST_REF), SHIFT_REF, CONST_REF; ...
  sprintf('Optimo DS1: SHIFT=%d CONST=%d', SEL_SHIFT, SEL_CONST), SEL_SHIFT, SEL_CONST };

subsets      = {idx_ds1, idx_ds2, idx_all};
subset_names = {'DS1 (22)', 'DS2 (22)', 'Base completa (48)'};

RES = zeros(2, 3, 3);

for s = 1:3
    fprintf('--- %s ---\n', subset_names{s});
    fprintf('%-36s | %6s | %6s | %6s\n', 'Configuracion', 'Se(%)', '+P(%)', 'F1(%)');
    fprintf('-------------------------------------|--------|--------|-------\n');

    for c = 1:2
        [se, pp, f1] = eval_subset(u, anns, subsets{s}, REFRACT, VULN_LEN, ...
                                   VULN_NUM, THR_INIT, THR_MIN, ...
                                   final_cases{c,2}, final_cases{c,3}, tolerance);
        RES(c,s,1) = se;
        RES(c,s,2) = pp;
        RES(c,s,3) = f1;
        fprintf('%-36s | %6.2f | %6.2f | %6.2f\n', ...
                final_cases{c,1}, se, pp, f1);
    end
    fprintf('\n');
end

%% 8. Guardar

save('decay_ds1_results.mat', 'records', 'shift_grid', 'const_grid', ...
     'SE', 'PP', 'F1', 'SEL_SHIFT', 'SEL_CONST', 'RES', ...
     'SHIFT_REF', 'CONST_REF', 'tolerance');

fprintf('Guardado en decay_ds1_results.mat\n');
fprintf('sweep_decay_ds1 completed successfully.\n');


%% ====================================================================
%  LOCAL FUNCTIONS
%  ====================================================================

function [se, pp, f1] = eval_subset(u_all, anns, mask, REFRACT, VULN_LEN, ...
                                    VULN_NUM, THR_INIT, THR_MIN, ...
                                    SHIFT, CONST, tolerance)
    idx = find(mask);
    tp = 0; fp = 0; fn = 0;

    for j = 1:numel(idx)
        k  = idx(j);
        pk = emulate_detector(u_all{k}, REFRACT, VULN_LEN, VULN_NUM, ...
                              THR_INIT, THR_MIN, SHIFT, CONST);
        [t, f, n] = match_peaks(anns{k}, pk, tolerance);
        tp = tp + t;
        fp = fp + f;
        fn = fn + n;
    end

    se = safe_pct(tp, tp+fn);
    pp = safe_pct(tp, tp+fp);
    if se + pp > 0
        f1 = 2*se*pp/(se+pp);
    else
        f1 = 0;
    end
end


function u = scale_to_12bit(e, lo, hi, tmin, tmax)
    rango = hi - lo;
    if rango <= 0
        rango = 1;
    end
    u = round((e - lo) / rango * (tmax - tmin) + tmin);
    u = max(min(u, 4095), 0);
end


function p = safe_pct(a, b)
    if b > 0
        p = a / b * 100;
    else
        p = 0;
    end
end


function peaks = emulate_detector(u, REFRACT, VULN_LEN, VULN_NUM, ...
                                  THR_INIT, THR_MIN, SHIFT, CONST)
% Identica a la funcion homonima de emulate_rtl.m salvo por SHIFT y
% CONST, que alli estan fijados en 6 y 1.

    suma = movsum(u, [7 0]);
    f    = floor(suma / 8);
    f    = f(8:end);
    m    = numel(f);

    d  = [f(1); diff(f)];
    sq = d.^2;

    ws = movsum(sq, [7 0]);

    div_decay = 2^SHIFT;

    thr      = THR_INIT;
    last     = 0;
    refr_cnt = 0;
    in_refr  = false;
    vuln_cnt = 0;
    in_vuln  = false;

    peaks = zeros(m,1);
    np    = 0;

    for j = 1:m
        win_count_full = (j >= 8);

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

        if win_count_full && ~o_in_refr
            if o_in_vuln
                ok = ws(j) > o_last * VULN_NUM;
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
                vuln_cnt = VULN_LEN;
                in_vuln  = true;
            else
                dec = floor(o_thr/div_decay) + CONST;
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
% Copia literal del emparejamiento de compare_vhdl_batch.m.

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
