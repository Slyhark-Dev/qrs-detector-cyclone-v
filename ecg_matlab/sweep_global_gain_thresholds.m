%% SWEEP GLOBAL GAIN THRESHOLDS
% Project: Cardiac arrhythmia detection system - FPGA DE1-SoC
% Universidad Tecnologica del Peru (UTP)
%
% Continuacion de sweep_global_gain.m.
%
% Aquel script mostro que con una unica constante de calibracion para los
% 48 registros el detector conserva el F1 pero desplaza su punto de
% operacion: pierde sensibilidad y gana predictividad positiva. La causa
% es que la energia integrada cae al cuadrado de la compresion de
% amplitud mientras THR_INIT y THR_MIN permanecen fijos.
%
% Aqui se comprueba si el punto de operacion se recupera reescalando los
% umbrales, que es la unica magnitud del diseno acoplada a la escala de
% entrada.
%
% Protocolo, identico al del manuscrito:
%   - la rejilla de umbrales se recorre SOLO sobre DS1
%   - se elige el maximo F1 en DS1
%   - ese unico punto se evalua una vez sobre DS2 y sobre la base completa
%   - la rejilla de DS2 no se imprime, para que la seleccion no pueda
%     apoyarse en el conjunto de evaluacion
%
% Escalado de entrada: global pleno, min/max sobre los 48 registros.

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

REFRACT  = 72;
VULN_LEN = 160;
VULN_NUM = 3;

% Umbrales de referencia, los del RTL compilado
THR_INIT_REF = 512000;
THR_MIN_REF  = 4000;

% Rejilla de busqueda
init_list = [512000 256000 128000 64000 32000];
min_list  = [4000 2000 1000 500 250 125];

fs        = 360;
tolerance = round(0.150 * fs);

margin     = 0.05;
target_min = round(4095 * margin);
target_max = round(4095 * (1 - margin));

n_rec = numel(records);

fprintf('=== BARRIDO DE UMBRALES BAJO GANANCIA GLOBAL ===\n');
fprintf('Ajuste sobre DS1, evaluacion unica sobre DS2\n');
fprintf('Rejilla: %d valores de THR_INIT x %d de THR_MIN = %d puntos\n\n', ...
        numel(init_list), numel(min_list), numel(init_list)*numel(min_list));

%% 2. Lectura y escalado global

sig     = cell(n_rec,1);
anns    = cell(n_rec,1);
rec_min = zeros(n_rec,1);
rec_max = zeros(n_rec,1);

fprintf('Leyendo registros...\n');
t0 = tic;

for k = 1:n_rec
    [signal, ~, ~, ~, n_samples] = read_mitbih(records{k});
    e = double(signal(:,1));

    sig{k}     = single(e);
    anns{k}    = read_annotations(records{k}, n_samples);
    rec_min(k) = min(e);
    rec_max(k) = max(e);
end

GLB_MIN = min(rec_min);
GLB_MAX = max(rec_max);

fprintf('Lectura completada en %.1f s\n', toc(t0));
fprintf('Rango global: [%.3f %.3f] mV\n\n', GLB_MIN, GLB_MAX);

% Vectores escalados: A por registro (referencia), B global
uA = cell(n_rec,1);
uB = cell(n_rec,1);

for k = 1:n_rec
    e = double(sig{k});
    uA{k} = scale_to_12bit(e, rec_min(k), rec_max(k), target_min, target_max);
    uB{k} = scale_to_12bit(e, GLB_MIN,    GLB_MAX,    target_min, target_max);
end

clear sig;

idx_ds1 = ismember(records, ds1);
idx_ds2 = ismember(records, ds2);

%% 3. Rejilla sobre DS1

n_i = numel(init_list);
n_m = numel(min_list);

F1_ds1 = zeros(n_i, n_m);
SE_ds1 = zeros(n_i, n_m);
PP_ds1 = zeros(n_i, n_m);

fprintf('Recorriendo la rejilla sobre DS1 (%d registros)...\n\n', sum(idx_ds1));
t0 = tic;

for a = 1:n_i
    for b = 1:n_m
        [se, pp, f1] = eval_subset(uB, anns, idx_ds1, ...
                                   REFRACT, VULN_LEN, VULN_NUM, ...
                                   init_list(a), min_list(b), tolerance);
        SE_ds1(a,b) = se;
        PP_ds1(a,b) = pp;
        F1_ds1(a,b) = f1;
    end
end

fprintf('Rejilla completada en %.1f s\n\n', toc(t0));

%% 4. Tabla de la rejilla en DS1

fprintf('=====================================================================\n');
fprintf('   F1 SOBRE DS1, ESCALADO GLOBAL\n');
fprintf('=====================================================================\n\n');

fprintf('%-10s |', 'THR_INIT');
for b = 1:n_m
    fprintf(' MIN=%5d |', min_list(b));
end
fprintf('\n');
fprintf('-----------|');
for b = 1:n_m
    fprintf('-----------|');
end
fprintf('\n');

for a = 1:n_i
    fprintf('%10d |', init_list(a));
    for b = 1:n_m
        fprintf('  %8.2f |', F1_ds1(a,b));
    end
    fprintf('\n');
end

fprintf('\nSensibilidad y predictividad en los mismos puntos:\n\n');
fprintf('%-10s |', 'THR_INIT');
for b = 1:n_m
    fprintf('  MIN=%5d  |', min_list(b));
end
fprintf('\n');
fprintf('-----------|');
for b = 1:n_m
    fprintf('-------------|');
end
fprintf('\n');

for a = 1:n_i
    fprintf('%10d |', init_list(a));
    for b = 1:n_m
        fprintf(' %5.2f %5.2f |', SE_ds1(a,b), PP_ds1(a,b));
    end
    fprintf('\n');
end

%% 5. Seleccion sobre DS1

[~, lin] = max(F1_ds1(:));
[ia, ib] = ind2sub(size(F1_ds1), lin);

SEL_INIT = init_list(ia);
SEL_MIN  = min_list(ib);

fprintf('\n=====================================================================\n');
fprintf('   PUNTO SELECCIONADO SOBRE DS1\n');
fprintf('=====================================================================\n\n');
fprintf('THR_INIT = %d   THR_MIN = %d\n', SEL_INIT, SEL_MIN);
fprintf('Factor respecto al RTL compilado: THR_INIT x%.3f   THR_MIN x%.3f\n', ...
        SEL_INIT/THR_INIT_REF, SEL_MIN/THR_MIN_REF);
fprintf('DS1: Se %.2f   +P %.2f   F1 %.2f\n', ...
        SE_ds1(ia,ib), PP_ds1(ia,ib), F1_ds1(ia,ib));

if ia == 1 || ia == n_i || ib == 1 || ib == n_m
    fprintf('\nAVISO: el optimo cae en el borde de la rejilla. Conviene\n');
    fprintf('ampliarla antes de reportar el valor como optimo interior.\n');
else
    fprintf('\nOptimo interior: la rejilla contiene el maximo.\n');
end

%% 6. Evaluacion unica sobre DS2 y base completa

idx_all = true(1, n_rec);

fprintf('\n=====================================================================\n');
fprintf('   COMPARACION FINAL\n');
fprintf('=====================================================================\n\n');
fprintf('%-42s | %6s | %6s | %6s\n', 'Configuracion', 'Se(%)', '+P(%)', 'F1(%)');
fprintf('-------------------------------------------|--------|--------|-------\n');

cases = { ...
  'A por registro, umbrales del RTL',        uA, THR_INIT_REF, THR_MIN_REF; ...
  'B global, umbrales del RTL',              uB, THR_INIT_REF, THR_MIN_REF; ...
  'B global, umbrales reajustados en DS1',   uB, SEL_INIT,     SEL_MIN };

subsets      = {idx_ds1, idx_ds2, idx_all};
subset_names = {'DS1 (22)', 'DS2 (22)', 'Base completa (48)'};

RES = zeros(3, 3, 3);   % caso x subconjunto x metrica

for s = 1:3
    fprintf('\n--- %s ---\n', subset_names{s});
    for c = 1:3
        [se, pp, f1] = eval_subset(cases{c,2}, anns, subsets{s}, ...
                                   REFRACT, VULN_LEN, VULN_NUM, ...
                                   cases{c,3}, cases{c,4}, tolerance);
        RES(c,s,1) = se;
        RES(c,s,2) = pp;
        RES(c,s,3) = f1;

        fprintf('%-42s | %6.2f | %6.2f | %6.2f\n', cases{c,1}, se, pp, f1);
    end
end

%% 7. Veredicto

fprintf('\n=====================================================================\n');
fprintf('   VEREDICTO SOBRE DS2\n');
fprintf('=====================================================================\n\n');

seA = RES(1,2,1); ppA = RES(1,2,2); f1A = RES(1,2,3);
seB = RES(2,2,1); ppB = RES(2,2,2); f1B = RES(2,2,3);
seT = RES(3,2,1); ppT = RES(3,2,2); f1T = RES(3,2,3);

fprintf('Referencia por registro   : Se %.2f  +P %.2f  F1 %.2f\n', seA, ppA, f1A);
fprintf('Global sin reajuste       : Se %.2f  +P %.2f  F1 %.2f\n', seB, ppB, f1B);
fprintf('Global con reajuste en DS1: Se %.2f  +P %.2f  F1 %.2f\n\n', seT, ppT, f1T);

if f1T >= f1A - 0.10
    fprintf('El reajuste de umbrales recupera el desempeno de la\n');
    fprintf('normalizacion por registro. La dependencia del escalado se\n');
    fprintf('reduce a una constante de calibracion, no a la arquitectura.\n');
elseif f1T > f1B
    fprintf('El reajuste mejora respecto a no reajustar, pero no alcanza\n');
    fprintf('a la normalizacion por registro. Diferencia de F1: %.2f puntos.\n', f1A - f1T);
else
    fprintf('El reajuste no mejora. El desplazamiento del punto de\n');
    fprintf('operacion no se explica solo por la escala de los umbrales.\n');
end

%% 8. Guardar

save('global_gain_thresholds.mat', 'records', 'init_list', 'min_list', ...
     'F1_ds1', 'SE_ds1', 'PP_ds1', 'SEL_INIT', 'SEL_MIN', 'RES', ...
     'GLB_MIN', 'GLB_MAX', 'tolerance');

fprintf('\nGuardado en global_gain_thresholds.mat\n');
fprintf('sweep_global_gain_thresholds completed successfully.\n');


%% ====================================================================
%  LOCAL FUNCTIONS
%  ====================================================================

function [se, pp, f1] = eval_subset(u_all, anns, mask, REFRACT, VULN_LEN, ...
                                    VULN_NUM, THR_INIT, THR_MIN, tolerance)
% Acumula TP, FP y FN sobre los registros marcados y devuelve las
% metricas agregadas.
    idx = find(mask);
    tp = 0; fp = 0; fn = 0;

    for j = 1:numel(idx)
        k  = idx(j);
        pk = emulate_detector(u_all{k}, REFRACT, VULN_LEN, VULN_NUM, ...
                              THR_INIT, THR_MIN);
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
                                  THR_INIT, THR_MIN)
% Copia literal de la funcion homonima de emulate_rtl.m.

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
