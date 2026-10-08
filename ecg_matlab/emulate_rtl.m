%% EMULATE RTL AND VALIDATE AGAINST MODELSIM OUTPUT
% Project: Cardiac arrhythmia detection system - FPGA DE1-SoC
% Universidad Tecnologica del Peru (UTP)
%
% Reproduce en MATLAB la cadena completa implementada en hardware
% (ecg_filter -> qrs_detector) con la misma secuencia de registros que
% el RTL, leyendo los mismos ficheros de vectores que consumio ModelSim.
%
% El objetivo es disponer de un modelo verificado que permita barrer
% parametros en minutos, en lugar de relanzar el lote completo.
%
% La comparacion se reporta de dos formas independientes:
%
%   1) Coincidencia con desfase cero. Es la que respalda la afirmacion
%      de equivalencia indice a indice del manuscrito. Ninguna alineacion
%      se aplica a los indices del emulador.
%
%   2) Coincidencia con el mejor desfase constante en el rango -20..20.
%      Sirve como diagnostico: si supera a la anterior, existe un retardo
%      sistematico entre emulador y testbench que hay que explicar antes
%      de hablar de equivalencia exacta.
%
% Salida: por registro, numero de picos del RTL, del emulador, ambas
% coincidencias y el desfase ganador.

clc; clear;

batch_dir = 'D:/proyectos/ecg_arrhythmia/batch/';

% Parametros que deben coincidir con qrs_detector.vhd
REFRACT   = 72;
VULN_LEN  = 160;
VULN_NUM  = 3;      % exigencia: win_sum > last_peak * VULN_NUM
THR_INIT  = 512000;
THR_MIN   = 1500;

recs = {'100','101','102','103','104','105','106','107','108','109', ...
        '111','112','113','114','115','116','117','118','119', ...
        '121','122','123','124', ...
        '200','201','202','203','205','207','208','209','210', ...
        '212','213','214','215','217','219', ...
        '220','221','222','223','228', ...
        '230','231','232','233','234'};

fprintf('=== VALIDACION DEL EMULADOR CONTRA MODELSIM ===\n');
fprintf('REFRACT=%d  VULN_LEN=%d  factor=%d  THR_INIT=%d  THR_MIN=%d\n\n', ...
        REFRACT, VULN_LEN, VULN_NUM, THR_INIT, THR_MIN);

fprintf('Rec  | RTL   | Emul  | Delta | Offset 0        | Mejor offset\n');
fprintf('-----|-------|-------|-------|-----------------|----------------\n');

n_rec    = numel(recs);
hit0_pct = zeros(n_rec,1);
off_best = zeros(n_rec,1);

for k = 1:n_rec
    rec = recs{k};

    u = read_vectors([batch_dir 'vectors_' rec '.txt']);
    pk_emul = emulate_detector(u, REFRACT, VULN_LEN, VULN_NUM, ...
                               THR_INIT, THR_MIN);

    pk_rtl = readmatrix([batch_dir 'vhdl_qrs_' rec '.txt']);
    pk_rtl = pk_rtl(:);

    n_rtl = numel(pk_rtl);

    % --- coincidencia sin alineacion alguna
    hit0 = numel(intersect(pk_emul, pk_rtl));

    % --- diagnostico: mejor desfase constante en -20..20
    best_hit = 0; best_off = 0;
    for off = -20:20
        hit = numel(intersect(pk_emul + off, pk_rtl));
        if hit > best_hit
            best_hit = hit;
            best_off = off;
        end
    end

    hit0_pct(k) = hit0 / max(n_rtl,1) * 100;
    off_best(k) = best_off;

    fprintf('%s  | %5d | %5d | %5d | %5d (%6.2f%%) | %5d (%6.2f%%) off %+d\n', ...
            rec, n_rtl, numel(pk_emul), numel(pk_emul) - n_rtl, ...
            hit0, hit0_pct(k), ...
            best_hit, best_hit / max(n_rtl,1) * 100, best_off);
end

%% Veredicto
fprintf('\n');

if all(off_best == 0) && all(hit0_pct >= 99.9)
    fprintf('Equivalencia indice a indice confirmada sin alineacion:\n');
    fprintf('el desfase ganador es cero en los %d registros y la\n', n_rec);
    fprintf('coincidencia minima es %.2f%%.\n', min(hit0_pct));
elseif all(off_best == 0)
    fprintf('El desfase ganador es cero, pero la coincidencia minima\n');
    fprintf('con offset 0 es %.2f%%. La equivalencia no es total y la\n', min(hit0_pct));
    fprintf('afirmacion del manuscrito debe matizarse.\n');
else
    fprintf('ATENCION: existe un desfase sistematico distinto de cero\n');
    fprintf('en al menos un registro. La equivalencia indice a indice\n');
end

fprintf('\nemulate_rtl completed successfully.\n');


%% ====================================================================
%  LOCAL FUNCTIONS
%  ====================================================================

function u = read_vectors(fname)
% Lee el fichero de vectores de 12 bits en binario, una muestra por linea
    fid = fopen(fname, 'r');
    if fid == -1
        error('Vector file not found: %s', fname);
    end
    c = textscan(fid, '%s');
    fclose(fid);
    u = bin2dec(char(c{1}));
end


function peaks = emulate_detector(u, REFRACT, VULN_LEN, VULN_NUM, ...
                                  THR_INIT, THR_MIN)
% Emulacion registro a registro de ecg_filter + qrs_detector.
%
% ecg_filter: media movil de 8 muestras, salida = suma >> 3, valida a
% partir de la octava muestra (count = 8).
%
% qrs_detector: derivada de primera diferencia, cuadrado sin truncar,
% integracion de 8 muestras, umbral adaptivo con refractario absoluto y
% umbral secundario. Cada pulso de entrada valido avanza una posicion
% del pipeline, de modo que basta un paso por muestra.

    n = numel(u);

    % --- filtro: media movil de 8, valida desde la muestra 8
    suma = movsum(u, [7 0]);
    f    = floor(suma / 8);
    f    = f(8:end);              % out_valid = '1' solo con count = 8
    m    = numel(f);

    % --- derivada y cuadrado
    d  = [f(1); diff(f)];         % prev_sample arranca en 0
    sq = d.^2;

    % --- integracion de 8 muestras
    ws = movsum(sq, [7 0]);

    % --- maquina de estados del umbral
    thr       = THR_INIT;
    last      = 0;
    refr_cnt  = 0;
    in_refr   = false;
    vuln_cnt  = 0;
    in_vuln   = false;

    peaks = zeros(m,1);
    np    = 0;

    for j = 1:m
        win_count_full = (j >= 8);

        % valores registrados antes del flanco
        o_in_refr  = in_refr;
        o_refr_cnt = refr_cnt;
        o_in_vuln  = in_vuln;
        o_vuln_cnt = vuln_cnt;
        o_thr      = thr;
        o_last     = last;

        % bloque de temporizadores
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

        % bloque de deteccion, con los valores previos al flanco
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
