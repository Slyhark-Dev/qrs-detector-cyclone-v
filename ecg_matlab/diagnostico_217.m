%% DIAGNOSTICO VISUAL - RECORD 217
% Proyecto: Deteccion de arritmias FPGA DE1-SoC (UTP)
%
% Objetivo: ver POR QUE el detector causal falla en el registro 217
% (Se~42%, +P~40%, con FP y FN casi iguales).
%
% Muestra, en ventanas de tiempo, la senal ECG real con:
%   - circulos verdes = anotaciones del cardiologo (verdad de referencia)
%   - triangulos rojos = detecciones de nuestro algoritmo causal
%
% Si los rojos caen sobre los QRS reales -> problema de alineacion/match
% Si los rojos caen en sitios sin QRS    -> falsos positivos por ruido
% Si faltan rojos sobre QRS reales       -> falsos negativos
%
% Este script NO modifica nada. Se puede borrar despues.

clc; clear; close all;

record = '217';
fs_target = 360;

%% 1. Cargar senal y anotaciones
[signal, fs, ~, ~, n_samples] = read_mitbih(record);
fprintf('\n=== DIAGNOSTICO RECORD %s ===\n', record);

% leer anotaciones reutilizando la logica de validate_sensitivity
ann_peaks = leer_anotaciones_local(record, n_samples);
fprintf('Latidos anotados (cardiologo): %d\n', length(ann_peaks));

%% 2. Correr el detector causal en AMBOS canales
n_channels = size(signal, 2);
det = cell(1, n_channels);
for ch = 1:n_channels
    det{ch} = pan_tompkins_causal(signal(:, ch), fs, n_samples);
    fprintf('Canal %d: detectados %d\n', ch, length(det{ch}));
end

%% 3. Graficar 3 ventanas de 8 segundos cada una (inicio, medio, final)
t = (0:n_samples-1) / fs;
win_sec = 8;
win_samp = win_sec * fs;

% puntos de inicio de cada ventana: 10s, mitad del registro, y 60s
starts = [10*fs, round(n_samples/2), 60*fs];
labels = {'Inicio (~10s)', 'Mitad del registro', '~60s'};

for ch = 1:n_channels
    figure('Name', sprintf('Record %s - Canal %d', record, ch), ...
           'Position', [30 30 1200 750]);

    for w = 1:3
        s0 = starts(w);
        s1 = min(s0 + win_samp, n_samples);

        subplot(3,1,w);
        plot(t(s0:s1), signal(s0:s1, ch), 'b', 'LineWidth', 0.7);
        hold on;

        % anotaciones en esta ventana
        ann_w = ann_peaks(ann_peaks >= s0 & ann_peaks <= s1);
        plot(t(ann_w), signal(ann_w, ch), 'go', ...
             'MarkerSize', 12, 'LineWidth', 1.8);

        % detecciones en esta ventana
        det_w = det{ch}(det{ch} >= s0 & det{ch} <= s1);
        plot(t(det_w), signal(det_w, ch), 'rv', ...
             'MarkerSize', 8, 'MarkerFaceColor', 'r');

        hold off;
        xlabel('Tiempo (s)'); ylabel('mV'); grid on;
        xlim([t(s0) t(s1)]);
        title(sprintf('Canal %d - %s  (verde=cardiologo, rojo=deteccion)', ...
                      ch, labels{w}));
        if w == 1
            legend('ECG', 'Anotacion cardiologo', 'Deteccion', ...
                   'Location', 'best');
        end
    end
end

fprintf('\nRevisa las figuras:\n');
fprintf(' - Si los rojos caen sobre los QRS reales pero no coinciden con\n');
fprintf('   los verdes -> problema de alineacion temporal.\n');
fprintf(' - Si hay muchos rojos donde NO hay QRS -> falsos positivos (ruido).\n');
fprintf(' - Si faltan rojos sobre QRS claros -> falsos negativos.\n');
fprintf('diagnostico completado.\n');


%% ====================================================================
%  FUNCION LOCAL: lectura de anotaciones (misma logica que validate)
%  ====================================================================
function ann_samples = leer_anotaciones_local(record, n_samples)
    atr_file = [record '.atr'];
    fid = fopen(atr_file, 'r');
    if fid == -1
        error('No se encontro: %s', atr_file);
    end
    bytes = fread(fid, inf, 'uint8');
    fclose(fid);

    beat_types = [1 2 3 4 5 6 7 8 9 10 11 12 13 34 38];
    ann_samples = [];
    current_sample = 0;
    i = 1;
    while i <= length(bytes) - 1
        low_byte = bytes(i);
        high_byte = bytes(i + 1);
        i = i + 2;
        ann_type = bitshift(high_byte, -2);
        time_delta = bitor(low_byte, bitand(high_byte, 3) * 256);
        if ann_type == 59
            if i + 3 <= length(bytes)
                skip_low = bytes(i) + bytes(i+1) * 256;
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
