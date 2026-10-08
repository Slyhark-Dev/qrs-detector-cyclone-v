%% SWEEP VULNERABLE WINDOW LENGTH
% Project: Cardiac arrhythmia detection system - FPGA DE1-SoC
% Universidad Tecnologica del Peru (UTP)
%
% Emula en punto fijo la cadena implementada en qrs_detector.vhd
% (derivada -> cuadrado -> ventana movil de 8 -> umbral adaptivo con
% refractario y ventana vulnerable) y barre la longitud de la ventana
% vulnerable para elegir el valor antes de sintetizar y simular.
%
% VULN_LEN se cuenta desde el pico R, no desde el fin del refractario.
% El refractario absoluto es de 72 muestras (200 ms a 360 Hz).
%
% Subconjunto: registros con exceso de falsos positivos por onda T
% mas registros de control con buen desempeno.

clc; clear;

recs = {'113','117','107','232','212','219','215','209','119', ...
        '100','115','220','208','234','106'};

vuln_values = [72 100 120 147 160 180];

fs        = 360;
tolerance = round(0.150 * fs);
REFRACT   = 72;
THR_INIT  = 512000;
THR_MIN   = 4000;

fprintf('=== BARRIDO DE VENTANA VULNERABLE ===\n');
fprintf('Registros: %d | Refractario: %d muestras (%.0f ms)\n\n', ...
        numel(recs), REFRACT, REFRACT/fs*1000);

% Precarga: energia y anotaciones por registro (una sola vez)
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

fprintf('VULN_LEN | cobertura |     Se |     +P |     F1 |     FP |   FN\n');
fprintf('---------|-----------|--------|--------|--------|--------|------\n');

for v = 1:numel(vuln_values)
    VL = vuln_values(v);
    TP = 0; FP = 0; FN = 0;

    for k = 1:numel(recs)
        e  = E{k};
        n  = numel(e);
        a  = A{k};

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
                ok   = e(i) > floor(last/2);
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

    fprintf('%8d | %6.0f ms | %6.2f | %6.2f | %6.2f | %6d | %4d\n', ...
            VL, VL/fs*1000, se, pp, f1, FP, FN);
end

fprintf('\nsweep_vuln_window completed successfully.\n');


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
