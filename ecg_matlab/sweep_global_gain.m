%% SWEEP GLOBAL GAIN
% Project: Cardiac arrhythmia detection system - FPGA DE1-SoC
% Universidad Tecnologica del Peru (UTP)
%
% Evalua la dependencia del detector respecto al escalado de entrada.
%
% El lote actual normaliza cada registro con su propio minimo y maximo
% sobre los 30 minutos completos. Los umbrales THR_INIT y THR_MIN son
% constantes absolutas, de modo que su validez depende de que toda la
% senal llegue con la misma amplitud. Este script mide esa dependencia.
%
% Tres configuraciones sobre la misma cadena y el mismo protocolo:
%
%   A) POR REGISTRO   min/max propios de cada registro. Es el control:
%                     debe reproducir las cifras publicadas.
%   B) GLOBAL PLENO   min/max sobre los 48 registros. Una sola constante
%                     de calibracion para toda la base.
%   C) GLOBAL ROBUSTO rango derivado de los percentiles 0.1 y 99.9
%                     medianos entre registros, con saturacion. Equivale
%                     a fijar el rango de entrada de un ADC real.
%
% Emparejamiento identico a compare_vhdl_batch.m: ventana de 54 muestras
% (150 ms) sin correccion de retardo, cada anotacion emparejada una vez.
%
% Salida: metricas globales y por subconjunto DS1/DS2 para las tres
% configuraciones, mas la ocupacion en cuentas de cada registro bajo B.

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

% Parametros que deben coincidir con qrs_detector.vhd
REFRACT   = 72;
VULN_LEN  = 160;
VULN_NUM  = 3;
THR_INIT  = 512000;
THR_MIN   = 4000;

fs        = 360;
tolerance = round(0.150 * fs);

% Mapeo a 12 bits con 5% de margen en cada extremo
margin     = 0.05;
target_min = round(4095 * margin);
target_max = round(4095 * (1 - margin));

n_rec = numel(records);

fprintf('=== BARRIDO DE ESCALADO DE ENTRADA ===\n');
fprintf('Registros: %d   Tolerancia: %d muestras (%.0f ms)\n', ...
        n_rec, tolerance, tolerance/fs*1000);
fprintf('Rango destino: [%d %d] de 12 bits\n', target_min, target_max);
fprintf('REFRACT=%d  VULN_LEN=%d  factor=%d  THR_INIT=%d  THR_MIN=%d\n\n', ...
        REFRACT, VULN_LEN, VULN_NUM, THR_INIT, THR_MIN);

%% 2. Primera pasada: leer senal y anotaciones, medir rangos

sig   = cell(n_rec,1);
anns  = cell(n_rec,1);
rec_min = zeros(n_rec,1);
rec_max = zeros(n_rec,1);
p_lo    = zeros(n_rec,1);
p_hi    = zeros(n_rec,1);

fprintf('Leyendo registros...\n');
t0 = tic;

for k = 1:n_rec
    rec = records{k};

    [signal, ~, ~, ~, n_samples] = read_mitbih(rec);
    e = double(signal(:,1));

    sig{k}  = single(e);
    anns{k} = read_annotations(rec, n_samples);

    rec_min(k) = min(e);
    rec_max(k) = max(e);
    p_lo(k)    = prctile(e, 0.1);
    p_hi(k)    = prctile(e, 99.9);

    fprintf('  %s: %d muestras, %d anotaciones, rango [%.3f %.3f] mV\n', ...
            rec, n_samples, numel(anns{k}), rec_min(k), rec_max(k));
end

fprintf('Lectura completada en %.1f s\n\n', toc(t0));

% Constantes globales de calibracion
GLB_MIN = min(rec_min);
GLB_MAX = max(rec_max);

ROB_MIN = median(p_lo);
ROB_MAX = median(p_hi);

fprintf('Rango global pleno   : [%.3f %.3f] mV\n', GLB_MIN, GLB_MAX);
fprintf('Rango global robusto : [%.3f %.3f] mV\n', ROB_MIN, ROB_MAX);
fprintf('Compresion del pleno respecto al robusto: %.2fx\n\n', ...
        (GLB_MAX-GLB_MIN) / (ROB_MAX-ROB_MIN));

%% 3. Segunda pasada: detectar bajo las tres configuraciones

cfg_names = {'A por registro', 'B global pleno', 'C global robusto'};
n_cfg = 3;

TP = zeros(n_rec, n_cfg);
FP = zeros(n_rec, n_cfg);
FN = zeros(n_rec, n_cfg);
n_det = zeros(n_rec, n_cfg);
span_glb = zeros(n_rec,1);   % cuentas ocupadas bajo B
span_rob = zeros(n_rec,1);   % cuentas ocupadas bajo C
sat_rob  = zeros(n_rec,1);   % muestras saturadas bajo C

fprintf('Procesando...\n');
fprintf('Rec  | Anot  |   A: Se    +P   |   B: Se    +P   |   C: Se    +P\n');
fprintf('-----|-------|-----------------|-----------------|-----------------\n');

t0 = tic;

for k = 1:n_rec
    e   = double(sig{k});
    ann = anns{k};

    u = cell(n_cfg,1);
    u{1} = scale_to_12bit(e, rec_min(k), rec_max(k), target_min, target_max);
    u{2} = scale_to_12bit(e, GLB_MIN,    GLB_MAX,    target_min, target_max);
    u{3} = scale_to_12bit(e, ROB_MIN,    ROB_MAX,    target_min, target_max);

    span_glb(k) = max(u{2}) - min(u{2});
    span_rob(k) = max(u{3}) - min(u{3});
    sat_rob(k)  = sum(u{3} <= 0 | u{3} >= 4095);

    se_k = zeros(1,n_cfg);
    pp_k = zeros(1,n_cfg);

    for c = 1:n_cfg
        pk = emulate_detector(u{c}, REFRACT, VULN_LEN, VULN_NUM, ...
                              THR_INIT, THR_MIN);
        [tp, fp, fn] = match_peaks(ann, pk, tolerance);

        TP(k,c)    = tp;
        FP(k,c)    = fp;
        FN(k,c)    = fn;
        n_det(k,c) = numel(pk);

        se_k(c) = safe_pct(tp, tp+fn);
        pp_k(c) = safe_pct(tp, tp+fp);
    end

    fprintf('%s  | %5d | %6.2f %6.2f | %6.2f %6.2f | %6.2f %6.2f\n', ...
            records{k}, numel(ann), ...
            se_k(1), pp_k(1), se_k(2), pp_k(2), se_k(3), pp_k(3));
end

fprintf('Deteccion completada en %.1f s\n', toc(t0));

%% 4. Resumen por protocolo

idx_all = true(n_rec,1);
idx_ds1 = ismember(records, ds1)';
idx_ds2 = ismember(records, ds2)';
idx_44  = idx_ds1 | idx_ds2;

sets      = {idx_ds1, idx_ds2, idx_44, idx_all};
set_names = {'DS1 (22)', 'DS2 (22)', 'DS1+DS2 (44)', 'Base completa (48)'};

for c = 1:n_cfg
    fprintf('\n=====================================================================\n');
    fprintf('   CONFIGURACION %s\n', cfg_names{c});
    fprintf('=====================================================================\n\n');
    fprintf('%-20s | %8s | %8s | %8s | %7s | %6s\n', ...
            'Protocolo', 'Se(%)', '+P(%)', 'F1(%)', 'FP', 'FN');
    fprintf('---------------------|----------|----------|----------|---------|-------\n');

    for s = 1:numel(sets)
        m = sets{s};
        tp = sum(TP(m,c));  fp = sum(FP(m,c));  fn = sum(FN(m,c));

        se = safe_pct(tp, tp+fn);
        pp = safe_pct(tp, tp+fp);
        if se+pp > 0
            f1 = 2*se*pp/(se+pp);
        else
            f1 = 0;
        end

        fprintf('%-20s | %8.2f | %8.2f | %8.2f | %7d | %6d\n', ...
                set_names{s}, se, pp, f1, fp, fn);
    end
end

%% 5. Control contra las cifras publicadas

tp = sum(TP(:,1)); fp = sum(FP(:,1)); fn = sum(FN(:,1));
se = safe_pct(tp, tp+fn);
pp = safe_pct(tp, tp+fp);
f1 = 2*se*pp/(se+pp);

fprintf('\n=====================================================================\n');
fprintf('   CONTROL: configuracion A contra las cifras del manuscrito\n');
fprintf('=====================================================================\n\n');
fprintf('Publicado (48 reg): Se 99.42  +P 96.63  F1 98.01  FP 3791  FN 638\n');
fprintf('Obtenido  (48 reg): Se %5.2f  +P %5.2f  F1 %5.2f  FP %4d  FN %3d\n\n', ...
        se, pp, f1, fp, fn);

if abs(se-99.42) < 0.15 && abs(pp-96.63) < 0.30
    fprintf('El control reproduce las cifras publicadas. Las configuraciones\n');
    fprintf('B y C son comparables y sus diferencias son atribuibles al\n');
    fprintf('escalado de entrada.\n');
else
    fprintf('ATENCION: el control NO reproduce las cifras publicadas. Antes\n');
    fprintf('de interpretar B y C hay que explicar la discrepancia: la cadena\n');
    fprintf('o la verdad de referencia difieren de las usadas en el lote.\n');
end

%% 6. Ocupacion de rango bajo escalado global

fprintf('\n=====================================================================\n');
fprintf('   OCUPACION DE RANGO POR REGISTRO\n');
fprintf('=====================================================================\n\n');
fprintf('Cuentas de 4095 que ocupa cada registro. Bajo A todos ocupan 3685.\n\n');
fprintf('Rec  | B cuentas | B %% de A | C cuentas | C saturadas\n');
fprintf('-----|-----------|----------|-----------|------------\n');

for k = 1:n_rec
    fprintf('%s  | %9d | %7.1f%% | %9d | %10d\n', ...
            records{k}, span_glb(k), ...
            span_glb(k)/(target_max-target_min)*100, ...
            span_rob(k), sat_rob(k));
end

fprintf('\nMediana de ocupacion bajo B: %.0f cuentas (%.1f%% del rango util)\n', ...
        median(span_glb), median(span_glb)/(target_max-target_min)*100);
fprintf('Minima  de ocupacion bajo B: %.0f cuentas, registro %s\n', ...
        min(span_glb), records{find(span_glb == min(span_glb), 1)});

%% 7. Guardar

save('global_gain_results.mat', 'records', 'cfg_names', ...
     'TP', 'FP', 'FN', 'n_det', 'span_glb', 'span_rob', 'sat_rob', ...
     'GLB_MIN', 'GLB_MAX', 'ROB_MIN', 'ROB_MAX', ...
     'rec_min', 'rec_max', 'p_lo', 'p_hi', 'tolerance');

fprintf('\nGuardado en global_gain_results.mat\n');
fprintf('sweep_global_gain completed successfully.\n');


%% ====================================================================
%  LOCAL FUNCTIONS
%  ====================================================================

function u = scale_to_12bit(e, lo, hi, tmin, tmax)
% Mapeo lineal de mV a cuentas de 12 bits sin signo, con saturacion.
% Identico a generate_vhdl_vectors_batch.m salvo por los limites lo/hi,
% que aqui pueden ser globales en lugar de propios del registro.
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
% Emulacion registro a registro de ecg_filter + qrs_detector.
% Copia literal de la funcion homonima de emulate_rtl.m.

    % --- filtro: media movil de 8, valida desde la muestra 8
    suma = movsum(u, [7 0]);
    f    = floor(suma / 8);
    f    = f(8:end);
    m    = numel(f);

    % --- derivada y cuadrado
    d  = [f(1); diff(f)];
    sq = d.^2;

    % --- integracion de 8 muestras
    ws = movsum(sq, [7 0]);

    % --- maquina de estados del umbral
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
% Copia literal del emparejamiento de compare_vhdl_batch.m: sin
% correccion de retardo, cada anotacion emparejada a lo sumo una vez.

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
% Lector de ficheros .atr del MIT-BIH. Copia literal de la funcion
% homonima de validate_sensitivity.m.
%
%   59 = SKIP : intervalo de 32 bits en los 4 bytes siguientes,
%               palabra alta primero
%   60 = NUM, 61 = SUB, 62 = CHN : el campo de tiempo lleva datos,
%               el contador de muestra no avanza
%   63 = AUX  : el campo de tiempo es la longitud de la cadena auxiliar
%    0 = EOF

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
