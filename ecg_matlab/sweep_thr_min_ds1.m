%% SWEEP THRESHOLD MIN ON DS1
% Project: Cardiac arrhythmia detection system - FPGA DE1-SoC
% Universidad Tecnologica del Peru (UTP)
%
% Cierra dos flancos metodologicos abiertos.
%
% 1) CONTAMINACION DEL RANGO GLOBAL
%    En sweep_global_gain.m la constante de calibracion se calculo con
%    los 48 registros, DS2 incluido. Aqui se recalcula usando solo DS1 y
%    se aplica sin cambios a los 48, midiendo la saturacion que eso
%    provoca en los registros que no participaron en su calculo.
%
% 2) TRAZABILIDAD DE THR_MIN
%    THR_MIN = 4000 se fijo por barrido sobre la base completa, antes de
%    que existiera la particion inter-paciente. Aqui se repite el barrido
%    solo sobre DS1. Si el optimo coincide con 4000, el valor publicado
%    es reproducible sin usar DS2 y la separacion inter-paciente se
%    sostiene tambien para ese parametro.
%
% El barrido anterior mostro que THR_INIT no altera ninguna deteccion en
% un rango de 16x. Aqui se verifica que la inercia tambien se cumple bajo
% escalado por registro.
%
% Protocolo: rejilla sobre DS1, seleccion sobre DS1, evaluacion unica de
% los puntos elegidos sobre DS2 y sobre la base completa.

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

THR_INIT = 512000;
THR_MIN_REF = 4000;

min_grid = [16000 8000 6000 4000 3000 2000 1500 1000 500];

fs        = 360;
tolerance = round(0.150 * fs);

margin     = 0.05;
target_min = round(4095 * margin);
target_max = round(4095 * (1 - margin));

n_rec = numel(records);

fprintf('=== BARRIDO DE THR_MIN SOBRE DS1 ===\n');
fprintf('Rango de calibracion derivado solo de DS1\n');
fprintf('Rejilla de %d valores de THR_MIN\n\n', numel(min_grid));

%% 2. Lectura

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

fprintf('Lectura completada en %.1f s\n\n', toc(t0));

idx_ds1 = ismember(records, ds1);
idx_ds2 = ismember(records, ds2);
idx_all = true(1, n_rec);

%% 3. Rango de calibracion: DS1 solamente contra base completa

DS1_MIN = min(rec_min(idx_ds1));
DS1_MAX = max(rec_max(idx_ds1));

ALL_MIN = min(rec_min);
ALL_MAX = max(rec_max);

fprintf('=====================================================================\n');
fprintf('   RANGO DE CALIBRACION\n');
fprintf('=====================================================================\n\n');
fprintf('Derivado de DS1 (22 reg) : [%.3f %.3f] mV\n', DS1_MIN, DS1_MAX);
fprintf('Derivado de los 48 reg   : [%.3f %.3f] mV\n', ALL_MIN, ALL_MAX);

k_dmin = find(rec_min == DS1_MIN, 1);
k_dmax = find(rec_max == DS1_MAX, 1);
fprintf('Extremos de DS1 fijados por los registros %s y %s\n', ...
        records{k_dmin}, records{k_dmax});

if abs(DS1_MIN-ALL_MIN) < 1e-9 && abs(DS1_MAX-ALL_MAX) < 1e-9
    fprintf('\nAmbos rangos coinciden: los extremos de la base estan dentro\n');
    fprintf('de DS1, de modo que la constante de calibracion no usa ninguna\n');
    fprintf('informacion de DS2.\n\n');
else
    fprintf('\nLos rangos difieren. La calibracion de DS1 provocara\n');
    fprintf('saturacion en los registros de mayor excursion fuera de DS1.\n\n');
end

%% 4. Escalado

uA = cell(n_rec,1);   % por registro
uB = cell(n_rec,1);   % global, calibracion de DS1
sat = zeros(n_rec,1);

for k = 1:n_rec
    e = double(sig{k});
    uA{k} = scale_to_12bit(e, rec_min(k), rec_max(k), target_min, target_max);
    uB{k} = scale_to_12bit(e, DS1_MIN,    DS1_MAX,    target_min, target_max);
    sat(k) = sum(uB{k} <= 0 | uB{k} >= 4095);
end

clear sig;

fprintf('Saturacion bajo la calibracion de DS1:\n');
fprintf('  registros DS1 : %d muestras recortadas en total\n', sum(sat(idx_ds1)));
fprintf('  registros DS2 : %d muestras recortadas en total\n', sum(sat(idx_ds2)));
fprintf('  base completa : %d de %d muestras (%.4f%%)\n\n', ...
        sum(sat), n_rec*650000, sum(sat)/(n_rec*650000)*100);

%% 5. Inercia de THR_INIT bajo escalado por registro

fprintf('=====================================================================\n');
fprintf('   VERIFICACION: INERCIA DE THR_INIT (configuracion A, DS1)\n');
fprintf('=====================================================================\n\n');

init_check = [512000 128000 32000];
fprintf('%-10s | %6s | %6s | %6s\n', 'THR_INIT', 'Se(%)', '+P(%)', 'F1(%)');
fprintf('-----------|--------|--------|-------\n');

f1_check = zeros(size(init_check));
for a = 1:numel(init_check)
    [se, pp, f1] = eval_subset(uA, anns, idx_ds1, REFRACT, VULN_LEN, ...
                               VULN_NUM, init_check(a), THR_MIN_REF, tolerance);
    f1_check(a) = f1;
    fprintf('%10d | %6.2f | %6.2f | %6.2f\n', init_check(a), se, pp, f1);
end

if max(f1_check) - min(f1_check) < 0.005
    fprintf('\nTHR_INIT es inerte tambien bajo escalado por registro: un\n');
    fprintf('factor de %.0fx no altera el resultado.\n\n', ...
            max(init_check)/min(init_check));
else
    fprintf('\nTHR_INIT si influye bajo escalado por registro. Diferencia\n');
    fprintf('maxima de F1: %.3f puntos.\n\n', max(f1_check)-min(f1_check));
end

%% 6. Rejilla de THR_MIN sobre DS1, ambas configuraciones

n_g = numel(min_grid);
SE = zeros(2, n_g);
PP = zeros(2, n_g);
F1 = zeros(2, n_g);

cfgs      = {uA, uB};
cfg_names = {'A por registro', 'B global, calibracion DS1'};

fprintf('Recorriendo la rejilla...\n');
t0 = tic;

for c = 1:2
    for g = 1:n_g
        [se, pp, f1] = eval_subset(cfgs{c}, anns, idx_ds1, REFRACT, ...
                                   VULN_LEN, VULN_NUM, THR_INIT, ...
                                   min_grid(g), tolerance);
        SE(c,g) = se;
        PP(c,g) = pp;
        F1(c,g) = f1;
    end
end

fprintf('Rejilla completada en %.1f s\n\n', toc(t0));

for c = 1:2
    fprintf('=====================================================================\n');
    fprintf('   THR_MIN SOBRE DS1, CONFIGURACION %s\n', cfg_names{c});
    fprintf('=====================================================================\n\n');
    fprintf('%-10s | %6s | %6s | %6s |\n', 'THR_MIN', 'Se(%)', '+P(%)', 'F1(%)');
    fprintf('-----------|--------|--------|--------|\n');

    for g = 1:n_g
        marca = '';
        if min_grid(g) == THR_MIN_REF
            marca = '  <- valor publicado';
        end
        if F1(c,g) == max(F1(c,:))
            marca = [marca '  <- maximo'];
        end
        fprintf('%10d | %6.2f | %6.2f | %6.2f |%s\n', ...
                min_grid(g), SE(c,g), PP(c,g), F1(c,g), marca);
    end
    fprintf('\n');
end

%% 7. Seleccion y evaluacion unica

[~, gA] = max(F1(1,:));
[~, gB] = max(F1(2,:));

SEL_A = min_grid(gA);
SEL_B = min_grid(gB);

fprintf('=====================================================================\n');
fprintf('   TRAZABILIDAD DE THR_MIN\n');
fprintf('=====================================================================\n\n');
fprintf('Valor publicado, ajustado sobre la base completa : %d\n', THR_MIN_REF);
fprintf('Optimo sobre DS1, configuracion A               : %d\n\n', SEL_A);

if SEL_A == THR_MIN_REF
    fprintf('Coinciden. El valor publicado es reproducible ajustando solo\n');
    fprintf('sobre DS1, de modo que la evaluacion sobre DS2 no esta\n');
    fprintf('contaminada por la eleccion de este parametro.\n\n');
else
    fprintf('No coinciden. Ajustando solo sobre DS1 el optimo seria %d.\n', SEL_A);
    fprintf('Diferencia de F1 en DS1 entre ambos: %.2f puntos.\n\n', ...
            F1(1,gA) - F1(1, min_grid == THR_MIN_REF));
end

fprintf('=====================================================================\n');
fprintf('   COMPARACION FINAL\n');
fprintf('=====================================================================\n\n');

final_cases = { ...
  sprintf('A por registro, THR_MIN=%d (publicado)', THR_MIN_REF), uA, THR_MIN_REF; ...
  sprintf('A por registro, THR_MIN=%d (optimo DS1)', SEL_A),      uA, SEL_A; ...
  sprintf('B global DS1, THR_MIN=%d (publicado)', THR_MIN_REF),   uB, THR_MIN_REF; ...
  sprintf('B global DS1, THR_MIN=%d (optimo DS1)', SEL_B),        uB, SEL_B };

subsets      = {idx_ds1, idx_ds2, idx_all};
subset_names = {'DS1 (22)', 'DS2 (22)', 'Base completa (48)'};

RES = zeros(4, 3, 3);

for s = 1:3
    fprintf('--- %s ---\n', subset_names{s});
    fprintf('%-44s | %6s | %6s | %6s\n', 'Configuracion', 'Se(%)', '+P(%)', 'F1(%)');
    fprintf('---------------------------------------------|--------|--------|-------\n');

    for c = 1:4
        [se, pp, f1] = eval_subset(final_cases{c,2}, anns, subsets{s}, ...
                                   REFRACT, VULN_LEN, VULN_NUM, ...
                                   THR_INIT, final_cases{c,3}, tolerance);
        RES(c,s,1) = se;
        RES(c,s,2) = pp;
        RES(c,s,3) = f1;
        fprintf('%-44s | %6.2f | %6.2f | %6.2f\n', ...
                final_cases{c,1}, se, pp, f1);
    end
    fprintf('\n');
end

%% 8. Guardar

save('thr_min_ds1_results.mat', 'records', 'min_grid', 'SE', 'PP', 'F1', ...
     'SEL_A', 'SEL_B', 'RES', 'DS1_MIN', 'DS1_MAX', 'ALL_MIN', 'ALL_MAX', ...
     'sat', 'tolerance');

fprintf('Guardado en thr_min_ds1_results.mat\n');
fprintf('sweep_thr_min_ds1 completed successfully.\n');


%% ====================================================================
%  LOCAL FUNCTIONS
%  ====================================================================

function [se, pp, f1] = eval_subset(u_all, anns, mask, REFRACT, VULN_LEN, ...
                                    VULN_NUM, THR_INIT, THR_MIN, tolerance)
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
