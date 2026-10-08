%% ANALYZE SHORT RR INTERVALS AGAINST FALSE NEGATIVES
% Project: Cardiac arrhythmia detection system - FPGA DE1-SoC
% Universidad Tecnologica del Peru (UTP)
%
% El detector bloquea eventos mediante dos mecanismos encadenados:
%
%   refractario absoluto : 72 muestras, 200 ms, ningun evento se acepta
%   ventana vulnerable   : 160 muestras, 444 ms, el evento debe superar
%                          tres veces la energia del complejo anterior
%
% Un latido normal tiene energia comparable a la del latido previo, de
% modo que dentro de la ventana vulnerable no supera el factor tres. El
% efecto practico es un refractario extendido de unas 161 muestras, que
% a 360 Hz corresponde a 447 ms, o sea unos 134 latidos por minuto.
%
% Este script comprueba si ese techo se manifiesta en los datos. Para
% cada anotacion no detectada se calcula el intervalo respecto de la
% anotacion anterior y se reparte por tramos. Si el mecanismo es real,
% la tasa de falsos negativos debe dispararse en el tramo comprendido
% entre el refractario y el fin de la ventana vulnerable.
%
% Configuracion identica a la reportada: escalado por registro,
% REFRACT=72, VULN_LEN=160, VULN_NUM=3, THR_INIT=512000, THR_MIN=4000.

clc; clear;

%% 1. Configuracion

records = {'100','101','102','103','104','105','106','107','108','109', ...
           '111','112','113','114','115','116','117','118','119', ...
           '121','122','123','124', ...
           '200','201','202','203','205','207','208','209','210', ...
           '212','213','214','215','217','219', ...
           '220','221','222','223','228', ...
           '230','231','232','233','234'};

ds2 = {'100','103','105','111','113','117','121','123','200','202', ...
       '210','212','213','214','219','221','222','228','231','232', ...
       '233','234'};

REFRACT  = 72;
VULN_LEN = 160;
VULN_NUM = 3;
THR_INIT = 512000;
THR_MIN  = 4000;

fs        = 360;
tolerance = round(0.150 * fs);

margin     = 0.05;
target_min = round(4095 * margin);
target_max = round(4095 * (1 - margin));

% Frontera efectiva del bloqueo
BLOCK_END = VULN_LEN + 1;

n_rec = numel(records);

fprintf('=== INTERVALOS RR CORTOS CONTRA FALSOS NEGATIVOS ===\n\n');
fprintf('Refractario absoluto : %d muestras = %.0f ms = %.1f BPM\n', ...
        REFRACT+1, (REFRACT+1)/fs*1000, 21600/(REFRACT+1));
fprintf('Fin ventana vulnerable: %d muestras = %.0f ms = %.1f BPM\n\n', ...
        BLOCK_END, BLOCK_END/fs*1000, 21600/BLOCK_END);

%% 2. Deteccion y clasificacion de cada anotacion

% Tramos de intervalo RR en muestras
edges  = [0 REFRACT+1 BLOCK_END 200 250 300 400 600 inf];
labels = { ...
    sprintf('RR <= %d  (refractario)', REFRACT+1), ...
    sprintf('%d < RR <= %d  (ventana vulnerable)', REFRACT+1, BLOCK_END), ...
    sprintf('%d < RR <= 200', BLOCK_END), ...
    '200 < RR <= 250', ...
    '250 < RR <= 300', ...
    '300 < RR <= 400', ...
    '400 < RR <= 600', ...
    'RR > 600' };

n_bin = numel(labels);

tot_bin = zeros(n_bin,1);   % anotaciones por tramo
fn_bin  = zeros(n_bin,1);   % no detectadas por tramo

tot_bin_ds2 = zeros(n_bin,1);
fn_bin_ds2  = zeros(n_bin,1);

rec_short     = zeros(n_rec,1);   % anotaciones con RR <= BLOCK_END
rec_short_fn  = zeros(n_rec,1);   % de esas, no detectadas
rec_fn_total  = zeros(n_rec,1);

fprintf('Procesando...\n');
t0 = tic;

for k = 1:n_rec
    rec = records{k};

    [signal, ~, ~, ~, n_samples] = read_mitbih(rec);
    e   = double(signal(:,1));
    ann = read_annotations(rec, n_samples);

    u  = scale_to_12bit(e, min(e), max(e), target_min, target_max);
    pk = emulate_detector(u, REFRACT, VULN_LEN, VULN_NUM, THR_INIT, THR_MIN);

    matched = match_annotations(ann, pk, tolerance);

    % intervalo respecto de la anotacion previa; la primera se descarta
    rr = [inf; diff(ann(:))];

    is_ds2 = ismember(rec, ds2);

    for b = 1:n_bin
        sel = rr > edges(b) & rr <= edges(b+1);
        tot_bin(b) = tot_bin(b) + sum(sel);
        fn_bin(b)  = fn_bin(b)  + sum(sel & ~matched);

        if is_ds2
            tot_bin_ds2(b) = tot_bin_ds2(b) + sum(sel);
            fn_bin_ds2(b)  = fn_bin_ds2(b)  + sum(sel & ~matched);
        end
    end

    sel_short       = rr <= BLOCK_END;
    rec_short(k)    = sum(sel_short);
    rec_short_fn(k) = sum(sel_short & ~matched);
    rec_fn_total(k) = sum(~matched);
end

fprintf('Procesado en %.1f s\n\n', toc(t0));

%% 3. Tabla por tramo, base completa

print_bins('BASE COMPLETA (48 registros)', labels, tot_bin, fn_bin, fs);
print_bins('DS2 (22 registros)', labels, tot_bin_ds2, fn_bin_ds2, fs);

%% 4. Veredicto

n_short    = sum(tot_bin(1:2));
fn_short   = sum(fn_bin(1:2));
n_long     = sum(tot_bin(3:end));
fn_long    = sum(fn_bin(3:end));
fn_total   = sum(fn_bin);

rate_short = safe_pct(fn_short, n_short);
rate_long  = safe_pct(fn_long,  n_long);

fprintf('=====================================================================\n');
fprintf('   VEREDICTO\n');
fprintf('=====================================================================\n\n');

fprintf('Anotaciones con RR <= %d muestras (> %.0f BPM): %d de %d (%.2f%%)\n', ...
        BLOCK_END, 21600/BLOCK_END, n_short, n_short+n_long, ...
        safe_pct(n_short, n_short+n_long));
fprintf('  de ellas no detectadas: %d  (tasa de FN %.2f%%)\n\n', fn_short, rate_short);

fprintf('Anotaciones con RR > %d muestras: %d\n', BLOCK_END, n_long);
fprintf('  de ellas no detectadas: %d  (tasa de FN %.2f%%)\n\n', fn_long, rate_long);

if rate_long > 0
    fprintf('Razon entre ambas tasas: %.1fx\n\n', rate_short / rate_long);
end

fprintf('Falsos negativos totales: %d\n', fn_total);
fprintf('Atribuibles a intervalo corto: %d  (%.1f%% del total)\n\n', ...
        fn_short, safe_pct(fn_short, fn_total));

if rate_short > 5 * max(rate_long, 1e-9)
    fprintf('El techo de frecuencia se confirma: la tasa de falsos negativos\n');
    fprintf('en intervalos por debajo del fin de la ventana vulnerable es\n');
    fprintf('muy superior a la del resto. El mecanismo de umbral secundario\n');
    fprintf('actua como refractario extendido y debe declararse.\n');
elseif rate_short > 2 * max(rate_long, 1e-9)
    fprintf('Hay evidencia parcial: la tasa de falsos negativos es mayor en\n');
    fprintf('intervalos cortos, pero el efecto no domina el total. Conviene\n');
    fprintf('declararlo como limitacion acotada.\n');
else
    fprintf('El techo de frecuencia NO se manifiesta en los datos: la tasa\n');
    fprintf('de falsos negativos en intervalos cortos es comparable a la del\n');
    fprintf('resto. La hipotesis queda descartada.\n');
end

%% 5. Registros con mas intervalos cortos

fprintf('\n=====================================================================\n');
fprintf('   REGISTROS CON MAS INTERVALOS CORTOS\n');
fprintf('=====================================================================\n\n');

[~, ord] = sort(rec_short, 'descend');
fprintf('Rec  | RR cortos | FN en cortos | FN totales | %% de FN por RR corto\n');
fprintf('-----|-----------|--------------|------------|---------------------\n');

for j = 1:min(15, n_rec)
    k = ord(j);
    if rec_short(k) == 0
        break;
    end
    fprintf('%s  | %9d | %12d | %10d | %18.1f%%\n', ...
            records{k}, rec_short(k), rec_short_fn(k), rec_fn_total(k), ...
            safe_pct(rec_short_fn(k), max(rec_fn_total(k),1)));
end

%% 6. Guardar

save('short_rr_results.mat', 'records', 'labels', 'edges', ...
     'tot_bin', 'fn_bin', 'tot_bin_ds2', 'fn_bin_ds2', ...
     'rec_short', 'rec_short_fn', 'rec_fn_total', 'BLOCK_END', 'tolerance');

fprintf('\nGuardado en short_rr_results.mat\n');
fprintf('analyze_short_rr completed successfully.\n');


%% ====================================================================
%  LOCAL FUNCTIONS
%  ====================================================================

function print_bins(titulo, labels, tot, fn, fs)
    fprintf('=====================================================================\n');
    fprintf('   %s\n', titulo);
    fprintf('=====================================================================\n\n');
    fprintf('%-42s | %8s | %6s | %8s | %8s\n', ...
            'Tramo de intervalo RR', 'Latidos', 'FN', 'FN (%)', 'BPM min');
    fprintf('-------------------------------------------|----------|--------|----------|--------\n');

    for b = 1:numel(labels)
        if tot(b) == 0 && fn(b) == 0
            continue;
        end
        fprintf('%-42s | %8d | %6d | %8.2f | %8s\n', ...
                labels{b}, tot(b), fn(b), safe_pct(fn(b), tot(b)), '');
    end
    fprintf('\n');
end


function p = safe_pct(a, b)
    if b > 0
        p = a / b * 100;
    else
        p = 0;
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


function matched_ann = match_annotations(ann_peaks, det_peaks, tolerance)
% Igual que match_peaks pero devuelve el vector logico de anotaciones
% emparejadas, que es lo que aqui se necesita.

    n_ann = numel(ann_peaks);
    n_det = numel(det_peaks);

    matched_ann = false(n_ann, 1);

    for d = 1:n_det
        distances = abs(ann_peaks - det_peaks(d));
        [min_dist, min_idx] = min(distances);

        if min_dist <= tolerance && ~matched_ann(min_idx)
            matched_ann(min_idx) = true;
        end
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
