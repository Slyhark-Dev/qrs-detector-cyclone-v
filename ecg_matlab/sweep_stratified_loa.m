%% STRATIFIED BLAND-ALTMAN LIMITS OF AGREEMENT
% Project: Cardiac arrhythmia detection system - FPGA DE1-SoC
% Universidad Tecnologica del Peru (UTP)
%
% Extension de bland_altman_bpm.m. La recoleccion de pares (bpm_hw,
% bpm_ref) y la definicion de cadencia consistente son una copia literal
% de ese script, para que el control reproduzca exactamente la Tabla VI
% publicada. Lo unico anadido es el reparto en bandas de frecuencia de
% referencia al final.
%
% No modifica ningun fichero del proyecto.

clc; clear;

batch_dir = 'D:/proyectos/ecg_arrhythmia/batch/';

records = {'100','101','102','103','104','105','106','107','108','109', ...
           '111','112','113','114','115','116','117','118','119', ...
           '121','122','123','124', ...
           '200','201','202','203','205','207','208','209','210', ...
           '212','213','214','215','217','219', ...
           '220','221','222','223','228', ...
           '230','231','232','233','234'};

paced = {'102','104','107','217'};

fs        = 360;
tolerance = 54;

bands = [0   60;
         60  80;
         80  100;
         100 120;
         120 250];

band_names = {'< 60', '60-80', '80-100', '100-120', '> 120'};

fprintf('=== LIMITES DE CONCORDANCIA ESTRATIFICADOS POR FRECUENCIA ===\n\n');

%% 1. Recoleccion identica a bland_altman_bpm.m

bpm_hw    = [];
bpm_ref   = [];
consistent = [];

for k = 1:numel(records)
    rec = records{k};
    if ismember(rec, paced)
        continue;
    end

    beats_file = [batch_dir 'vhdl_beats_' rec '.txt'];
    if ~isfile(beats_file)
        continue;
    end

    V   = read_beats_file(beats_file);
    ann = readmatrix([batch_dir 'ann_' rec '.txt']);
    ann = ann(:);

    if isempty(V) || numel(ann) < 3
        continue;
    end

    prev_idx = -1;

    for i = 1:size(V,1)
        s_vhdl = V(i,1);
        b_hw   = V(i,2);

        [dd, ix] = min(abs(ann - s_vhdl));
        if dd > tolerance || ix < 2
            prev_idx = -1;
            continue;
        end

        rr = ann(ix) - ann(ix-1);
        if rr <= 0
            prev_idx = ix;
            continue;
        end
        b_ref = 21600 / rr;

        if b_hw < 20 || b_hw > 250 || b_ref < 20 || b_ref > 250
            prev_idx = ix;
            continue;
        end

        cons = (prev_idx == ix - 1);

        bpm_hw(end+1,1)     = b_hw;  %#ok<SAGROW>
        bpm_ref(end+1,1)    = b_ref; %#ok<SAGROW>
        consistent(end+1,1) = cons;  %#ok<SAGROW>

        prev_idx = ix;
    end
end

consistent = logical(consistent);

fprintf('Latidos emparejados totales      : %d\n',   numel(bpm_hw));
fprintf('Latidos de cadencia consistente  : %d (%.2f%%)\n\n', ...
        sum(consistent), sum(consistent)/numel(bpm_hw)*100);

%% 2. Control: reproducir la Tabla VI publicada, escenario (b)

hw_c  = bpm_hw(consistent);
ref_c = bpm_ref(consistent);
dif_c = hw_c - ref_c;

bias_all = mean(dif_c);
sd_all   = std(dif_c);
loa_u    = bias_all + 1.96*sd_all;
loa_l    = bias_all - 1.96*sd_all;

fprintf('=====================================================================\n');
fprintf('   CONTROL: LIMITES GLOBALES CONTRA LA TABLA VI PUBLICADA\n');
fprintf('=====================================================================\n\n');
fprintf('Publicado : sesgo -0.35  SD 3.41  LoA [+6.34 -7.04]\n');
fprintf('Obtenido  : sesgo %+.2f  SD %.2f  LoA [%+.2f %+.2f]\n\n', ...
        bias_all, sd_all, loa_u, loa_l);

if abs(bias_all-(-0.35)) < 0.02 && abs(sd_all-3.41) < 0.02
    fprintf('El control reproduce la Tabla VI. Los limites por banda son\n');
    fprintf('comparables.\n\n');
    control_ok = true;
else
    fprintf('ATENCION: el control no reproduce la Tabla VI exactamente.\n');
    fprintf('Las bandas se calculan igual, pero interpretar con cautela.\n\n');
    control_ok = false;
end

%% 3. Limites por banda de frecuencia, sobre cadencia consistente

n_b = size(bands,1);

fprintf('=====================================================================\n');
fprintf('   LIMITES DE CONCORDANCIA POR BANDA DE FRECUENCIA DE REFERENCIA\n');
fprintf('=====================================================================\n\n');
fprintf('%-10s | %8s | %8s | %8s | %9s | %9s | %9s\n', ...
        'Banda', 'N', 'Sesgo', 'SD', 'LoA sup', 'LoA inf', 'SD predicha');
fprintf('-----------|----------|----------|----------|-----------|-----------|-------------\n');

sd_loc = 8.52;
sd_rr  = sd_loc * sqrt(2);

BAND_BIAS = zeros(n_b,1);
BAND_SD   = zeros(n_b,1);
BAND_N    = zeros(n_b,1);

for b = 1:n_b
    if bands(b,2) >= 250
        m = ref_c >= bands(b,1) & ref_c <= bands(b,2);
    else
        m = ref_c >= bands(b,1) & ref_c < bands(b,2);
    end

    n = sum(m);
    if n < 10
        fprintf('%-10s | %8d | %8s | %8s | %9s | %9s | %9s\n', ...
                band_names{b}, n, '--', '--', '--', '--', '--');
        continue;
    end

    d = dif_c(m);
    bi = mean(d);
    sd = std(d);
    lu = bi + 1.96*sd;
    ll = bi - 1.96*sd;

    band_mid = mean(ref_c(m));
    sd_pred = sd_rr * band_mid^2 / 21600;

    BAND_BIAS(b) = bi;
    BAND_SD(b)   = sd;
    BAND_N(b)    = n;

    fprintf('%-10s | %8d | %+8.2f | %8.2f | %+9.2f | %+9.2f | %11.2f\n', ...
            band_names{b}, n, bi, sd, lu, ll, sd_pred);
end

%% 4. Ensanchamiento del margen, alta contra baja frecuencia

fprintf('\n=====================================================================\n');
fprintf('   ENSANCHAMIENTO DEL MARGEN\n');
fprintf('=====================================================================\n\n');

valid_bands = find(BAND_N >= 10);
if numel(valid_bands) >= 2
    b_lo = valid_bands(1);
    b_hi = valid_bands(end);
    ratio = BAND_SD(b_hi) / BAND_SD(b_lo);

    fprintf('Banda mas baja  (%s): SD %.2f BPM, N=%d\n', band_names{b_lo}, BAND_SD(b_lo), BAND_N(b_lo));
    fprintf('Banda mas alta  (%s): SD %.2f BPM, N=%d\n', band_names{b_hi}, BAND_SD(b_hi), BAND_N(b_hi));
    fprintf('Razon: %.2fx\n\n', ratio);
end

%% 5. Guardar

save('stratified_loa_results.mat', 'bands', 'band_names', ...
     'BAND_BIAS', 'BAND_SD', 'BAND_N', 'bias_all', 'sd_all', ...
     'loa_u', 'loa_l', 'sd_loc', 'sd_rr', 'control_ok');

fprintf('Guardado en stratified_loa_results.mat\n');
fprintf('sweep_stratified_loa completed successfully.\n');


%% ====================================================================
%  LOCAL FUNCTIONS
%  ====================================================================

function V = read_beats_file(fname)
% Copia literal de la funcion homonima de bland_altman_bpm.m.
    fid = fopen(fname, 'r');
    C = textscan(fid, '%f %f %f %s %s', 'CommentStyle', '#');
    fclose(fid);

    n = numel(C{1});
    V = zeros(n, 5);
    V(:,1) = C{1};
    V(:,2) = C{2};
    V(:,3) = C{3};
    for i = 1:n
        V(i,4) = bin2dec(C{4}{i});
        V(i,5) = bin2dec(C{5}{i});
    end
end
