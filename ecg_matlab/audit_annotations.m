%% AUDIT ANNOTATIONS
% Compara el parser de anotaciones actual contra una version corregida
% del formato WFDB. No modifica ningun archivo del proyecto.
%
% Salida: tabla por registro con numero de latidos segun cada parser,
% ultima muestra anotada y codigos pseudo-anotacion presentes.
%
% Criterio: la ultima anotacion debe caer cerca de n_samples (650000).
% Una diferencia grande indica desplazamiento del contador de muestras.

clc; clear;

records = {'100','101','102','103','104','105','106','107','108','109', ...
           '111','112','113','114','115','116','117','118','119', ...
           '121','122','123','124', ...
           '200','201','202','203','205','207','208','209','210', ...
           '212','213','214','215','217','219', ...
           '220','221','222','223','228', ...
           '230','231','232','233','234'};

fs = 360;
n_samples_nominal = 650000;

fprintf('=== AUDITORIA DEL PARSER DE ANOTACIONES ===\n\n');
fprintf('Rec  | Actual | Corregido | Delta | Ultima(act) | Ultima(cor) | Pseudo-codigos\n');
fprintf('-----|--------|-----------|-------|-------------|-------------|---------------\n');

audit = struct();
n_diff = 0;

for k = 1:length(records)
    rec = records{k};

    [ann_old, codes_old] = parse_current(rec, n_samples_nominal);
    [ann_new, codes_new] = parse_fixed(rec, n_samples_nominal);

    last_old = 0; if ~isempty(ann_old), last_old = ann_old(end); end
    last_new = 0; if ~isempty(ann_new), last_new = ann_new(end); end

    delta = length(ann_new) - length(ann_old);
    if delta ~= 0 || abs(last_new - last_old) > fs
        n_diff = n_diff + 1;
        flag = ' <<<';
    else
        flag = '';
    end

    pseudo = intersect(unique([codes_old(:); codes_new(:)]), [59 60 61 62 63]);
    pstr = strjoin(arrayfun(@(x) sprintf('%d', x), pseudo, 'UniformOutput', false), ',');
    if isempty(pstr), pstr = '-'; end

    fprintf('%s  | %6d | %9d | %5d | %11d | %11d | %s%s\n', ...
            rec, length(ann_old), length(ann_new), delta, ...
            last_old, last_new, pstr, flag);

    audit(k).record   = rec;
    audit(k).n_old    = length(ann_old);
    audit(k).n_new    = length(ann_new);
    audit(k).last_old = last_old;
    audit(k).last_new = last_new;
    audit(k).ann_old  = ann_old;
    audit(k).ann_new  = ann_new;
    audit(k).pseudo   = pseudo;
end

fprintf('\nRegistros con discrepancia: %d de %d\n', n_diff, length(records));

save('annotation_audit.mat', 'audit');
fprintf('Guardado en annotation_audit.mat\n');


%% ====================================================================
%  LOCAL FUNCTIONS
%  ====================================================================

function [ann_samples, codes_seen] = parse_current(record, n_samples)
% Replica exacta del parser actual en validate_sensitivity.m

    bytes = load_atr(record);
    beat_types = [1 2 3 4 5 6 7 8 9 10 11 12 13 34 38];

    ann_samples = [];
    codes_seen  = [];
    current_sample = 0;
    i = 1;

    while i <= length(bytes) - 1
        low_byte  = bytes(i);
        high_byte = bytes(i + 1);
        i = i + 2;

        ann_type   = bitshift(high_byte, -2);
        time_delta = bitor(low_byte, bitand(high_byte, 3) * 256);
        codes_seen(end+1) = ann_type; %#ok<AGROW>

        if ann_type == 59
            if i + 3 <= length(bytes)
                skip_low  = bytes(i)   + bytes(i+1) * 256;
                skip_high = bytes(i+2) + bytes(i+3) * 256;
                current_sample = current_sample + skip_low + skip_high * 65536;
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
        elseif ann_type == 0
            continue;
        else
            current_sample = current_sample + time_delta;
            if ismember(ann_type, beat_types) && current_sample <= n_samples
                ann_samples = [ann_samples; current_sample]; %#ok<AGROW>
            end
        end
    end
end


function [ann_samples, codes_seen] = parse_fixed(record, n_samples)
% Parser conforme al formato WFDB:
%   59 SKIP: intervalo en 4 bytes, palabra ALTA primero
%   60 NUM, 61 SUB, 62 CHN: el campo de 10 bits es dato, NO tiempo
%   63 AUX: el campo de 10 bits es longitud del texto, NO tiempo
%   0  EOF: fin del archivo

    bytes = load_atr(record);
    beat_types = [1 2 3 4 5 6 7 8 9 10 11 12 13 34 38];

    ann_samples = [];
    codes_seen  = [];
    current_sample = 0;
    i = 1;

    while i <= length(bytes) - 1
        low_byte  = bytes(i);
        high_byte = bytes(i + 1);
        i = i + 2;

        ann_type   = bitshift(high_byte, -2);
        time_delta = bitor(low_byte, bitand(high_byte, 3) * 256);
        codes_seen(end+1) = ann_type; %#ok<AGROW>

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
            % pseudo-anotacion: no avanza el contador de muestras
            continue;

        else
            current_sample = current_sample + time_delta;
            if ismember(ann_type, beat_types) && current_sample <= n_samples
                ann_samples = [ann_samples; current_sample]; %#ok<AGROW>
            end
        end
    end
end


function bytes = load_atr(record)
    atr_file = [record '.atr'];
    fid = fopen(atr_file, 'r');
    if fid == -1
        error('Annotation file not found: %s', atr_file);
    end
    bytes = fread(fid, inf, 'uint8');
    fclose(fid);
end
