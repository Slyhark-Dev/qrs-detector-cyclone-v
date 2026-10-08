%% SWEEP T-WAVE REJECTION PARAMETERS
% Project: Cardiac arrhythmia detection system - FPGA DE1-SoC
% Universidad Tecnologica del Peru (UTP)
%
% Emula en punto fijo la cadena de qrs_detector.vhd y realiza un barrido
% bidimensional sobre los dos parametros del rechazo de onda T:
%
%   VULN_LEN : longitud de la ventana vulnerable, contada desde el pico R
%   SHIFT    : exigencia dentro de esa ventana, expresada como
%              e(i) > last_peak >> SHIFT
%              SHIFT=1 -> mitad, SHIFT=0 -> igual, negativo -> multiplo
%
% Se implementa como e(i) > last_peak * NUM / DEN con potencias de dos,
% de modo que todos los valores evaluados son sintetizables mediante
% desplazamientos y sumas.
%
% Primera parte: estadistica de la relacion de energias QRS / onda T,
% para acotar el rango util antes del barrido.

clc; clear;

recs = {'100','101','102','103','104','105','106','107','108','109', ...
        '111','112','113','114','115','116','117','118','119', ...
        '121','122','123','124', ...
        '200','201','202','203','205','207','208','209','210', ...
        '212','213','214','215','217','219', ...
        '220','221','222','223','228', ...
        '230','231','232','233','234'};

fs        = 360;
tolerance = round(0.150 * fs);
REFRACT   = 72;
THR_INIT  = 512000;
THR_MIN   = 4000;

fprintf('=== RECHAZO DE ONDA T: CARACTERIZACION Y BARRIDO ===\n\n');

%% 1. Precarga de energia y anotaciones
E = cell(numel(recs),1);
A = cell(numel(recs),1);

for k = 1:numel(recs)
    [s, ~, ~, ~, n] = read_mitbih(recs{k});
    x = s(:,1);
    u = round((x - min(x)) / (max(x) - min(x)) * 3685 + 205);
    u = max(min(u, 4095), 0);

    f  = floor(movsum(u, [7 0]) / 8);
    d  = [0; diff(f)];
    sq = floor(d.^2);
    E{k} = movsum(sq, [7 0]);
    A{k} = read_ann_local(recs{k}, n);
end

%% 2. Relacion de energias QRS vs onda T
% Para cada latido anotado se toma la energia maxima en la ventana del
% QRS (+-54 muestras) y la energia maxima en la ventana vulnerable
% (73 a 200 muestras despues), que es donde cae la onda T.

fprintf('Relacion energia_T / energia_QRS por registro:\n');
fprintf('Rec  |  p50   |  p90   |  p99\n');
fprintf('-----|--------|--------|-------\n');

all_ratio = [];

for k = 1:numel(recs)
    e = E{k};
    a = A{k};
    n = numel(e);
    r = zeros(numel(a),1);
    valid = false(numel(a),1);

    for j = 1:numel(a)
        q0 = max(a(j) - tolerance, 1);
        q1 = min(a(j) + tolerance, n);
        t0 = min(a(j) + REFRACT + 1, n);
        t1 = min(a(j) + 200, n);
        if t1 > t0 && q1 > q0
            eq = max(e(q0:q1));
            et = max(e(t0:t1));
            if eq > 0
                r(j) = et / eq;
                valid(j) = true;
            end
        end
    end

    r = r(valid);
    all_ratio = [all_ratio; r]; %#ok<AGROW>
    fprintf('%s  | %6.3f | %6.3f | %6.3f\n', ...
            recs{k}, prctile(r,50), prctile(r,90), prctile(r,99));
end

fprintf('-----|--------|--------|-------\n');
fprintf('TOT  | %6.3f | %6.3f | %6.3f\n\n', ...
        prctile(all_ratio,50), prctile(all_ratio,90), prctile(all_ratio,99));

%% 3. Barrido bidimensional
% Exigencia expresada como fraccion NUM/DEN de la energia del ultimo pico.
% Todas las fracciones son sumas de potencias de dos.

fracs = { '1/2',  1, 2; ...
          '3/4',  3, 4; ...
          '1/1',  1, 1; ...
          '3/2',  3, 2; ...
          '2/1',  2, 1; ...
          '3/1',  3, 1 };

vuln_values = [240 260 280];

fprintf('Barrido: filas = ventana vulnerable, columnas = exigencia\n\n');
fprintf('VULN_LEN |');
for f = 1:size(fracs,1)
    fprintf(' %10s |', fracs{f,1});
end
fprintf('\n');
fprintf('---------|');
for f = 1:size(fracs,1)
    fprintf('------------|');
end
fprintf('\n');

best_f1 = -1;
best_cfg = '';

for v = 1:numel(vuln_values)
    VL = vuln_values(v);
    fprintf('%8d |', VL);

    for f = 1:size(fracs,1)
        NUM = fracs{f,2};
        DEN = fracs{f,3};

        TP = 0; FP = 0; FN = 0;

        for k = 1:numel(recs)
            e = E{k};
            n = numel(e);
            a = A{k};

            thr  = THR_INIT;
            last = 0;
            refr = 0;
            vuln = 0;
            pk   = zeros(n,1);
            np   = 0;

            for i = 9:n
                if refr > 0
                    refr = refr - 1;
                    if vuln > 0, vuln = vuln - 1; end
                    continue;
                end

                if vuln > 0
                    vuln = vuln - 1;
                    ok   = e(i) > floor(last * NUM / DEN);
                else
                    ok = true;
                end

                if e(i) > thr && ok
                    np = np + 1;
                    pk(np) = i;
                    thr  = floor(thr/2) + floor(thr/4) + floor(e(i)/4);
                    last = e(i);
                    refr = REFRACT;
                    vuln = max(VL - REFRACT, 0);
                else
                    dec = floor(thr/64) + 1;
                    if thr > THR_MIN + dec
                        thr = thr - dec;
                    else
                        thr = THR_MIN;
                    end
                end
            end

            pk = pk(1:np);

            matched = false(numel(a),1);
            t = 0;
            for i = 1:np
                [dd, ix] = min(abs(a - pk(i)));
                if dd <= tolerance && ~matched(ix)
                    matched(ix) = true;
                    t = t + 1;
                end
            end

            TP = TP + t;
            FP = FP + np - t;
            FN = FN + numel(a) - sum(matched);
        end

        se = TP / (TP + FN) * 100;
        pp = TP / (TP + FP) * 100;
        f1 = 2 * se * pp / (se + pp);

        fprintf(' %10.2f |', f1);

        if f1 > best_f1
            best_f1  = f1;
            best_cfg = sprintf('VULN_LEN=%d, exigencia=%s, Se=%.2f, +P=%.2f', ...
                               VL, fracs{f,1}, se, pp);
        end
    end
    fprintf('\n');
end

fprintf('\nMejor F1: %.2f  (%s)\n', best_f1, best_cfg);
fprintf('\nsweep_twave_rejection completed successfully.\n');


%% ====================================================================
%  LOCAL FUNCTIONS
%  ====================================================================

function ann_samples = read_ann_local(record, n_samples)
% Lector de anotaciones MIT-BIH conforme al formato WFDB.
% Codigos 60/61/62 son pseudo-anotaciones y no avanzan el contador.
% El codigo 59 (SKIP) almacena el intervalo en 4 bytes, palabra alta
% primero. El codigo 63 (AUX) lleva la longitud del texto auxiliar.

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
