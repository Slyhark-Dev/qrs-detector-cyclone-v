%% FINAL CHECKS
% Project: Cardiac arrhythmia detection system - FPGA DE1-SoC
% Universidad Tecnologica del Peru (UTP)
%
% Reune los cuatro pendientes de la fase de datos en una sola corrida.
%
%   1) Cabecera del registro 114: derivacion del canal 1
%   2) Transitorio de arranque: cuantos falsos positivos en el primer
%      segundo, sobre los 48 registros
%   3) Diferencia indice a indice entre pan_tompkins_causal y el emulador
%      del RTL en el registro 208
%   4) Ablacion limpia del truncamiento de energia a 16 bits sobre el
%      codigo actual, conservando el piso y el termino constante del
%      decaimiento
%
% Ninguna de las cuatro modifica archivos del proyecto.

clc; clear;

records = {'100','101','102','103','104','105','106','107','108','109', ...
           '111','112','113','114','115','116','117','118','119', ...
           '121','122','123','124', ...
           '200','201','202','203','205','207','208','209','210', ...
           '212','213','214','215','217','219', ...
           '220','221','222','223','228', ...
           '230','231','232','233','234'};

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

STARTUP = fs;   % primer segundo

n_rec = numel(records);

%% ====================================================================
%  1. CABECERA DEL REGISTRO 114
%  ====================================================================

fprintf('=====================================================================\n');
fprintf('   1. DERIVACIONES DECLARADAS EN LAS CABECERAS\n');
fprintf('=====================================================================\n\n');

sospechosos = {'100','102','104','114','117','123'};

for k = 1:numel(sospechosos)
    hea = [sospechosos{k} '.hea'];
    fid = fopen(hea, 'r');
    if fid == -1
        fprintf('%s: no encontrado\n', hea);
        continue;
    end
    lineas = {};
    while true
        l = fgetl(fid);
        if ~ischar(l), break; end
        lineas{end+1} = l; %#ok<AGROW>
    end
    fclose(fid);

    d1 = '?'; d2 = '?';
    if numel(lineas) >= 2, d1 = ultimo_campo(lineas{2}); end
    if numel(lineas) >= 3, d2 = ultimo_campo(lineas{3}); end

    fprintf('%s: canal 1 = %-6s   canal 2 = %-6s\n', sospechosos{k}, d1, d2);
end

fprintf('\nEl manuscrito afirma canal 1 = MLII en 46 de 48 registros, con\n');
fprintf('V5 en 102 y 104. Verificar arriba si 114 es la excepcion.\n\n');

%% ====================================================================
%  2 y 3. TRANSITORIO DE ARRANQUE Y ABLACION DE 16 BITS
%  ====================================================================

fprintf('=====================================================================\n');
fprintf('   2. TRANSITORIO DE ARRANQUE Y 3. ABLACION DE 16 BITS\n');
fprintf('=====================================================================\n\n');
fprintf('Leyendo y procesando los 48 registros...\n');

t0 = tic;

n_startup   = zeros(n_rec,1);   % detecciones en el primer segundo sin anotacion
first_idx   = zeros(n_rec,1);   % indice de la primera deteccion

tp_f = 0; fp_f = 0; fn_f = 0;   % configuracion final
tp_t = 0; fp_t = 0; fn_t = 0;   % energia truncada a 16 bits, resto igual

sig208 = [];
ann208 = [];

for k = 1:n_rec
    rec = records{k};

    [signal, ~, ~, ~, n_samples] = read_mitbih(rec);
    e   = double(signal(:,1));
    ann = read_annotations(rec, n_samples);

    u = scale_to_12bit(e, min(e), max(e), target_min, target_max);

    pk = emulate_detector(u, REFRACT, VULN_LEN, VULN_NUM, ...
                          THR_INIT, THR_MIN, 0);
    pt = emulate_detector(u, REFRACT, VULN_LEN, VULN_NUM, ...
                          THR_INIT, THR_MIN, 10);

    % transitorio: detecciones en el primer segundo sin anotacion cercana
    early = pk(pk <= STARTUP);
    cnt = 0;
    for j = 1:numel(early)
        if isempty(ann) || min(abs(ann - early(j))) > tolerance
            cnt = cnt + 1;
        end
    end
    n_startup(k) = cnt;
    if ~isempty(pk)
        first_idx(k) = pk(1);
    end

    [a,b,c] = match_peaks(ann, pk, tolerance);
    tp_f = tp_f + a; fp_f = fp_f + b; fn_f = fn_f + c;

    [a,b,c] = match_peaks(ann, pt, tolerance);
    tp_t = tp_t + a; fp_t = fp_t + b; fn_t = fn_t + c;

    if strcmp(rec, '208')
        sig208 = e;
        ann208 = ann;
    end
end

fprintf('Procesado en %.1f s\n\n', toc(t0));

fprintf('--- Transitorio de arranque ---\n\n');
fprintf('Registros con al menos un falso positivo en el primer segundo: %d de %d\n', ...
        sum(n_startup > 0), n_rec);
fprintf('Total de esos falsos positivos: %d\n', sum(n_startup));
fprintf('Distribucion: %d registros con 0, %d con 1, %d con mas de 1\n', ...
        sum(n_startup==0), sum(n_startup==1), sum(n_startup>1));
fprintf('Indice mediano de la primera deteccion: %.0f muestras (%.3f s)\n\n', ...
        median(first_idx), median(first_idx)/fs);

fprintf('--- Ablacion limpia del truncamiento a 16 bits ---\n\n');
fprintf('Se descartan los 10 bits menos significativos del cuadrado y se\n');
fprintf('conservan el piso THR_MIN=%d y el decaimiento thr>>6 + 1.\n\n', THR_MIN);

se_f = safe_pct(tp_f, tp_f+fn_f);  pp_f = safe_pct(tp_f, tp_f+fp_f);
se_t = safe_pct(tp_t, tp_t+fn_t);  pp_t = safe_pct(tp_t, tp_t+fp_t);

fprintf('%-40s | %6s | %6s | %6s\n', 'Configuracion', 'Se(%)', '+P(%)', 'F1(%)');
fprintf('-----------------------------------------|--------|--------|-------\n');
fprintf('%-40s | %6.2f | %6.2f | %6.2f\n', 'Final (24 bits)', ...
        se_f, pp_f, f1_of(se_f, pp_f));
fprintf('%-40s | %6.2f | %6.2f | %6.2f\n', 'Truncada a 16 bits, resto igual', ...
        se_t, pp_t, f1_of(se_t, pp_t));
fprintf('%-40s | %6s | %6s | %6s\n', 'Tabla VI, version previa completa', ...
        '89.73', '99.80', '94.50');

fprintf('\nSi la fila truncada de arriba difiere mucho de 89.73 / 99.80, la\n');
fprintf('degradacion de la Tabla VI no proviene solo del ancho de palabra\n');
fprintf('y la fila debe renombrarse como configuracion previa completa.\n\n');

%% ====================================================================
%  4. DIFERENCIA ENTRE pan_tompkins_causal Y EL EMULADOR, REGISTRO 208
%  ====================================================================

fprintf('=====================================================================\n');
fprintf('   4. MODELO MATLAB CONTRA EMULADOR DEL RTL, REGISTRO 208\n');
fprintf('=====================================================================\n\n');

u208 = scale_to_12bit(sig208, min(sig208), max(sig208), target_min, target_max);
pk_emul = emulate_detector(u208, REFRACT, VULN_LEN, VULN_NUM, ...
                           THR_INIT, THR_MIN, 0);
pk_mat  = pan_tompkins_causal(sig208, fs, numel(sig208));
pk_mat  = pk_mat(:);

fprintf('Detecciones del emulador del RTL : %d\n', numel(pk_emul));
fprintf('Detecciones de pan_tompkins_causal: %d\n', numel(pk_mat));
fprintf('Diferencia neta: %+d\n\n', numel(pk_emul) - numel(pk_mat));

% emparejamiento mutuo con ventana de tolerancia
solo_rtl = [];
for j = 1:numel(pk_emul)
    if isempty(pk_mat) || min(abs(pk_mat - pk_emul(j))) > tolerance
        solo_rtl(end+1,1) = pk_emul(j); %#ok<AGROW>
    end
end

solo_mat = [];
for j = 1:numel(pk_mat)
    if isempty(pk_emul) || min(abs(pk_emul - pk_mat(j))) > tolerance
        solo_mat(end+1,1) = pk_mat(j); %#ok<AGROW>
    end
end

fprintf('Detecciones solo del RTL   : %d\n', numel(solo_rtl));
if ~isempty(solo_rtl)
    fprintf('  primeras: ');
    fprintf('%d (%.3f s)  ', [solo_rtl(1:min(8,end))'; solo_rtl(1:min(8,end))'/fs]);
    fprintf('\n');
end

fprintf('Detecciones solo del modelo: %d\n', numel(solo_mat));
if ~isempty(solo_mat)
    fprintf('  primeras: ');
    fprintf('%d (%.3f s)  ', [solo_mat(1:min(8,end))'; solo_mat(1:min(8,end))'/fs]);
    fprintf('\n');
end

fprintf('\nEn los primeros 10 s:\n');
fprintf('  solo RTL   : %d\n', sum(solo_rtl <= 10*fs));
fprintf('  solo modelo: %d\n', sum(solo_mat <= 10*fs));

if numel(solo_rtl) <= 1 && isempty(solo_mat)
    fprintf('\nLa unica diferencia es el transitorio de arranque. La\n');
    fprintf('afirmacion del manuscrito se sostiene sin matices adicionales.\n');
elseif ~isempty(solo_mat)
    fprintf('\nHay latidos que el modelo detecta y el RTL no. La diferencia\n');
    fprintf('no se reduce al transitorio de arranque y debe declararse.\n');
else
    fprintf('\nHay mas de una deteccion exclusiva del RTL. Revisar cuales.\n');
end

%% ====================================================================

save('final_checks_results.mat', 'records', 'n_startup', 'first_idx', ...
     'se_f', 'pp_f', 'se_t', 'pp_t', 'solo_rtl', 'solo_mat');

fprintf('\nGuardado en final_checks_results.mat\n');
fprintf('final_checks completed successfully.\n');


%% ====================================================================
%  LOCAL FUNCTIONS
%  ====================================================================

function s = ultimo_campo(linea)
    partes = strsplit(strtrim(linea));
    s = partes{end};
end


function f1 = f1_of(se, pp)
    if se + pp > 0
        f1 = 2*se*pp/(se+pp);
    else
        f1 = 0;
    end
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


function peaks = emulate_detector(u, REFRACT, VULN_LEN, VULN_NUM, ...
                                  THR_INIT, THR_MIN, TRUNC_BITS)
% Igual que la funcion homonima de emulate_rtl.m, con un parametro extra
% que descarta los TRUNC_BITS menos significativos del cuadrado de la
% derivada. TRUNC_BITS = 0 reproduce la configuracion final.

    suma = movsum(u, [7 0]);
    f    = floor(suma / 8);
    f    = f(8:end);
    m    = numel(f);

    d  = [f(1); diff(f)];
    sq = d.^2;

    if TRUNC_BITS > 0
        sq = floor(sq / 2^TRUNC_BITS);
    end

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
