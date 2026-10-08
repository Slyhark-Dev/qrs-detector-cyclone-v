%% AUDIT MIT-BIH RHYTHM ANNOTATIONS
% Project: Cardiac arrhythmia detection system - FPGA DE1-SoC
% Universidad Tecnologica del Peru (UTP)
%
% Extrae los episodios de ritmo anotados por los cardiologos en los
% ficheros .atr y construye, para cada registro, la lista de intervalos
% [muestra_inicio, muestra_fin, etiqueta].
%
% Las marcas de cambio de ritmo son anotaciones de tipo 28 ('+') cuyo
% campo auxiliar (tipo 63, AUX) contiene la etiqueta entre parentesis.
% Etiquetas presentes en MIT-BIH:
%   (N    ritmo sinusal normal
%   (AFIB fibrilacion auricular
%   (AFL  flutter auricular
%   (B    bigeminismo ventricular
%   (T    trigeminismo ventricular
%   (VT   taquicardia ventricular
%   (SVTA taquicardia supraventricular
%   (SBR  bradicardia sinusal
%   (BII  bloqueo AV de segundo grado
%   (IVR  ritmo idioventricular
%   (NOD  ritmo nodal
%   (VFL  flutter ventricular
%   (P    ritmo de marcapasos
%   (PREX preexcitacion
%
% Este script es de verificacion: no modifica nada y sirve para
% comprobar que la lectura del campo auxiliar es correcta antes de
% construir la matriz de confusion del clasificador.

clc; clear;

records = {'100','101','102','103','104','105','106','107','108','109', ...
           '111','112','113','114','115','116','117','118','119', ...
           '121','122','123','124', ...
           '200','201','202','203','205','207','208','209','210', ...
           '212','213','214','215','217','219', ...
           '220','221','222','223','228', ...
           '230','231','232','233','234'};

fs = 360;

fprintf('=== AUDITORIA DE ANOTACIONES DE RITMO ===\n\n');

all_labels = containers.Map('KeyType','char','ValueType','double');
episodes   = struct();

for k = 1:numel(records)
    rec = records{k};
    ep  = read_rhythm(rec);
    episodes(k).record   = rec;
    episodes(k).episodes = ep;

    if isempty(ep)
        fprintf('%s: sin marcas de ritmo\n', rec);
        continue;
    end

    % duracion acumulada por etiqueta
    labs = unique({ep.label});
    txt  = '';
    for i = 1:numel(labs)
        sel = strcmp({ep.label}, labs{i});
        dur = sum([ep(sel).stop] - [ep(sel).start]) / fs;
        txt = [txt sprintf('%s:%.0fs  ', labs{i}, dur)]; %#ok<AGROW>

        if isKey(all_labels, labs{i})
            all_labels(labs{i}) = all_labels(labs{i}) + dur;
        else
            all_labels(labs{i}) = dur;
        end
    end

    fprintf('%s: %2d episodios | %s\n', rec, numel(ep), txt);
end

%% Resumen global
fprintf('\n=== ETIQUETAS ENCONTRADAS EN TODA LA BASE ===\n');
fprintf('Etiqueta | Duracion total (min) | %% de la base\n');
fprintf('---------|----------------------|-------------\n');

labs  = keys(all_labels);
durs  = cell2mat(values(all_labels));
[~,o] = sort(durs, 'descend');
total = sum(durs);

for i = o
    fprintf('%-8s | %20.1f | %11.2f\n', ...
            labs{i}, durs(i)/60, durs(i)/total*100);
end

fprintf('\nDuracion total anotada: %.1f min (esperado ~1445 min)\n', total/60);

save('rhythm_episodes.mat', 'episodes', 'records');
fprintf('\nGuardado en rhythm_episodes.mat\n');
fprintf('audit_rhythm_annotations completed successfully.\n');


%% ====================================================================
%  LOCAL FUNCTIONS
%  ====================================================================

function ep = read_rhythm(record)
% READ_RHYTHM - Extrae los episodios de ritmo de un fichero .atr
%
% Devuelve una estructura con campos start, stop y label. Cada episodio
% se extiende desde su marca de cambio de ritmo hasta la siguiente, o
% hasta el final del registro.

    fid = fopen([record '.atr'], 'r');
    if fid == -1
        error('Annotation file not found: %s.atr', record);
    end
    bytes = fread(fid, inf, 'uint8');
    fclose(fid);

    marks  = zeros(0,1);
    labels = {};
    pending_mark = -1;

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
            % SKIP: intervalo en 4 bytes, palabra alta primero
            if i + 3 <= numel(bytes)
                hi_word = bytes(i)   + bytes(i+1) * 256;
                lo_word = bytes(i+2) + bytes(i+3) * 256;
                current_sample = current_sample + hi_word * 65536 + lo_word;
                i = i + 4;
            else
                break;
            end

        elseif ann_type == 63
            % AUX: el campo de 10 bits es la longitud del texto
            aux_len = time_delta;
            n_read  = aux_len;
            if mod(n_read, 2) ~= 0
                n_read = n_read + 1;
            end

            if i + n_read - 1 <= numel(bytes)
                raw = bytes(i : i + aux_len - 1);
                % algunas implementaciones anteponen un byte de longitud
                txt = char(raw(:)');
                txt = txt(txt >= 32 & txt <= 126);
                txt = strtrim(txt);

                % solo interesan las etiquetas de ritmo, que empiezan por '('
                if ~isempty(txt) && txt(1) == '(' && pending_mark >= 0
                    marks(end+1,1)  = pending_mark; %#ok<AGROW>
                    labels{end+1,1} = txt;          %#ok<AGROW>
                    pending_mark = -1;
                end
            end
            i = i + n_read;

        elseif ann_type >= 60 && ann_type <= 62
            % NUM, SUB, CHN: dato, no tiempo
            continue;

        else
            current_sample = current_sample + time_delta;
            if ann_type == 28
                % marca de cambio de ritmo, la etiqueta llega en el AUX
                pending_mark = current_sample;
            end
        end
    end

    % construir intervalos
    ep = struct('start', {}, 'stop', {}, 'label', {});
    if isempty(marks)
        return;
    end

    n_total = 650000;
    for j = 1:numel(marks)
        ep(j).start = marks(j);
        if j < numel(marks)
            ep(j).stop = marks(j+1);
        else
            ep(j).stop = n_total;
        end
        ep(j).label = labels{j};
    end
end
