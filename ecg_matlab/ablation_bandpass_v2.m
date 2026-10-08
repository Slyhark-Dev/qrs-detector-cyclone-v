%% BANDPASS FILTER ABLATION, SECOND PROTOCOL
% Project: Cardiac arrhythmia detection system - FPGA DE1-SoC
% Universidad Tecnologica del Peru (UTP)
%
% Separates two effects that the first protocol measured together:
%
%   1) The group delay of each path. The detector reports the index of the
%      sample inside the trimmed filtered series, and the matcher compares
%      that index against the annotation without compensating the delay of
%      the filter. The moving average trims 7 samples against a delay of
%      7.5, so the residual is under one sample. The cascade trims 80
%      against a delay of about 43, so every detection lands roughly 37
%      samples, 103 ms, before its annotation, against a matching window
%      of 150 ms. Two filters with different group delays cannot be
%      compared through an uncompensated matcher.
%
%   2) The threshold floor. The floor is an absolute constant. The moving
%      average has unit DC gain, so the fixed input calibration also fixes
%      the energy scale. The cascade has a passband gain near 121 that
%      interacts with the spectral content of each record, so the same
%      floor sits at very different points from one record to the next.
%
% Three protocols are evaluated:
%
%   A  single floor selected on DS1, no delay compensation. This is the
%      first protocol and is kept so both results appear side by side.
%   B  single floor selected on DS1, delay compensated by the design-time
%      constant of each path. Isolates effect 1.
%   C  best floor per record from the grid, delay compensated. This is an
%      oracle and not a deployable configuration: it bounds what the
%      cascade can reach when the floor is not the limiting factor.
%
% The compensation uses the analytic delay of each path, a design-time
% number. No annotation is used to align anything.
%
% Reads : <batch_dir>/vectors_<rec>.txt and ann_<rec>.txt
% Writes: bandpass_ablation_v2.mat
% Recomputes no synthesis figure. No Quartus, no ModelSim.

clc; clear;

batch_dir = 'D:/PROYECTOS/ecg_arrhythmia/batch/';

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

n_rec = numel(records);

D_LP = 11;  D_HP = 29;
REFRACT = 72;  VULN_LEN = 160;  VULN_NUM = 3;
THR_INIT = 512000;  THR_MIN = 1500;
tolerance = 54;                       % 150 ms at 360 Hz

% Analytic delay of each path, in samples, relative to the trimmed series.
%   moving average : trim 7,  filter 3.5 + derivative 0.5 + window 3.5
%   cascade        : trim 80, filter 39  + derivative 0.5 + window 3.5
DELAY_MA = 0;
DELAY_BP = 37;

%% Load

fprintf('=== BANDPASS FILTER ABLATION, SECOND PROTOCOL ===\n\n');
u    = cell(n_rec,1);
anns = cell(n_rec,1);
fprintf('Reading vectors...\n');
t0 = tic;
for k = 1:n_rec
    u{k}    = read_vectors([batch_dir 'vectors_' records{k} '.txt']);
    a       = readmatrix([batch_dir 'ann_' records{k} '.txt']);
    anns{k} = a(:);
end
fprintf('Read completed in %.1f s\n\n', toc(t0));

idx_ds1 = ismember(records, ds1);
idx_ds2 = ismember(records, ds2);
% The four paced records belong to neither subset, as in de Chazal.

%% Energy scale and grids

scale = energy_scale_ratio(u, idx_ds1, D_LP, D_HP);
base  = THR_MIN * scale;
factors = [16 12 8 4 2 1 0.5 0.25 0.125 0.0625];
grid_bp = sort(unique(round(base * factors), 'stable'), 'descend');

fprintf('Energy ratio cascade / moving average : %.1f\n', scale);
fprintf('Floor grid for the cascade            : %d values, x%.4f to x%.0f\n\n', ...
        numel(grid_bp), min(factors), max(factors));

%% Per-record evaluation under the three protocols

fprintf('Evaluating. This sweeps %d record-configurations and takes a while.\n\n', ...
        n_rec * (2 + numel(grid_bp)));

F1_MA  = zeros(n_rec,1);
F1_A   = zeros(n_rec,1);
F1_B   = zeros(n_rec,1);
F1_C   = zeros(n_rec,1);
SEL_R  = zeros(n_rec,1);

CNT_MA = zeros(n_rec,3);     % tp fp fn
CNT_A  = zeros(n_rec,3);
CNT_B  = zeros(n_rec,3);
CNT_C  = zeros(n_rec,3);

% The single floor for the cascade is the one already selected on DS1.
SEL_BP_GLOBAL = 55392352;

fprintf('%-5s | %7s | %7s | %7s | %7s | %8s\n', ...
        'Rec', 'MA', 'BP A', 'BP B', 'BP C', 'floor C');
fprintf('------|---------|---------|---------|---------|----------\n');

for k = 1:n_rec
    ann = anns{k};

    % moving average, the compiled configuration
    fa = apply_filter(u{k}, 'ma', D_LP, D_HP);
    wa = integrated_energy(fa);
    pa = emulate_detector(wa, REFRACT, VULN_LEN, VULN_NUM, THR_INIT, THR_MIN);
    [t1,f1_,n1] = match_peaks(ann, pa + DELAY_MA, tolerance);
    CNT_MA(k,:) = [t1 f1_ n1];  F1_MA(k) = f1_of(t1,f1_,n1);

    % cascade
    fb = apply_filter(u{k}, 'bp', D_LP, D_HP);
    wb = integrated_energy(fb);
    ti = round(THR_INIT * scale);

    pb = emulate_detector(wb, REFRACT, VULN_LEN, VULN_NUM, ti, SEL_BP_GLOBAL);
    [t2,f2,n2] = match_peaks(ann, pb, tolerance);               % A
    CNT_A(k,:) = [t2 f2 n2];  F1_A(k) = f1_of(t2,f2,n2);
    [t3,f3,n3] = match_peaks(ann, pb + DELAY_BP, tolerance);     % B
    CNT_B(k,:) = [t3 f3 n3];  F1_B(k) = f1_of(t3,f3,n3);

    best = -1;
    for g = 1:numel(grid_bp)
        tig = round(THR_INIT * scale * grid_bp(g) / (THR_MIN*scale));
        pc  = emulate_detector(wb, REFRACT, VULN_LEN, VULN_NUM, tig, grid_bp(g));
        [t4,f4,n4] = match_peaks(ann, pc + DELAY_BP, tolerance);
        v = f1_of(t4,f4,n4);
        if v > best
            best = v;  CNT_C(k,:) = [t4 f4 n4];  SEL_R(k) = grid_bp(g);
        end
    end
    F1_C(k) = best;

    fprintf('%-5s | %7.2f | %7.2f | %7.2f | %7.2f | x%7.4f\n', ...
            records{k}, F1_MA(k), F1_A(k), F1_B(k), F1_C(k), SEL_R(k)/(THR_MIN*scale));
end

%% Aggregates

fprintf('\n=====================================================================\n');
fprintf('   AGGREGATE, BEATS POOLED\n');
fprintf('=====================================================================\n\n');

sets  = {idx_ds1, idx_ds2, true(1,n_rec)};
names = {'DS1 (22)', 'DS2 (22)', 'Full database (48)'};
RES   = zeros(3,4,3);      % set x protocol x (se pp f1)

fprintf('%-20s | %-8s | %6s %6s %6s\n', 'Protocol', 'Filter', 'Se', '+P', 'F1');
fprintf('---------------------|----------|----------------------\n');
labels = {'MA compiled', 'A global floor', 'B delay compensated', 'C floor per record'};
CNTS   = {CNT_MA, CNT_A, CNT_B, CNT_C};

for s = 1:3
    m = sets{s};
    for p = 1:4
        c  = sum(CNTS{p}(m,:), 1);
        se = c(1)/max(c(1)+c(3),1)*100;
        pp = c(1)/max(c(1)+c(2),1)*100;
        RES(s,p,:) = [se pp f1_of(c(1),c(2),c(3))];
    end
    fprintf('%-20s |\n', names{s});
    for p = 1:4
        fprintf('%-20s | %-8s | %6.2f %6.2f %6.2f\n', '', labels{p}, ...
                RES(s,p,1), RES(s,p,2), RES(s,p,3));
    end
end

fprintf('\nOn DS2:\n');
fprintf('  moving average over cascade, protocol A : %+6.2f points of F1\n', ...
        RES(2,1,3) - RES(2,2,3));
fprintf('  moving average over cascade, protocol B : %+6.2f points of F1\n', ...
        RES(2,1,3) - RES(2,3,3));
fprintf('  moving average over cascade, protocol C : %+6.2f points of F1\n', ...
        RES(2,1,3) - RES(2,4,3));

fprintf('\nFloor selected per record, protocol C: x%.4f to x%.4f, a span of %.0f.\n', ...
        min(SEL_R)/(THR_MIN*scale), max(SEL_R)/(THR_MIN*scale), ...
        max(SEL_R)/min(SEL_R));
fprintf('Records where the cascade falls below 60 F1:\n');
fprintf('  protocol A : %d\n', sum(F1_A < 60));
fprintf('  protocol B : %d\n', sum(F1_B < 60));
fprintf('  protocol C : %d\n', sum(F1_C < 60));

save('bandpass_ablation_v2.mat', 'records', 'F1_MA', 'F1_A', 'F1_B', 'F1_C', ...
     'SEL_R', 'CNT_MA', 'CNT_A', 'CNT_B', 'CNT_C', 'RES', 'scale', 'grid_bp', ...
     'DELAY_MA', 'DELAY_BP', 'SEL_BP_GLOBAL');
fprintf('\nSaved to bandpass_ablation_v2.mat\n');

%% ====================================================================
%  LOCAL FUNCTIONS
%  ====================================================================

function [b, a] = pt_lowpass(D)
    b = zeros(1, 2*D+1);
    b(1) = 1;  b(D+1) = -2;  b(2*D+1) = 1;
    a = [1 -2 1];
end


function [b, a] = pt_highpass(D)
    b = zeros(1, 2*D+1);
    b(1) = -1/(2*D);  b(D+1) = 1;  b(D+2) = -1;  b(2*D+1) = 1/(2*D);
    a = [1 -1];
end


function f = apply_filter(u, mode, D_LP, D_HP)
    if strcmp(mode, 'ma')
        suma = movsum(u, [7 0]);
        f    = floor(suma / 8);
        f    = f(8:end);
    else
        [b_lp, a_lp] = pt_lowpass(D_LP);
        [b_hp, a_hp] = pt_highpass(D_HP);
        y = filter(b_hp, a_hp, filter(b_lp, a_lp, double(u)));
        f = round(y);
        f = f(2*D_LP + 2*D_HP + 1 : end);
    end
end


function w = integrated_energy(f)
    d = [f(1); diff(f)];
    w = movsum(d.^2, [7 0]);
end


function r = energy_scale_ratio(u_all, mask, D_LP, D_HP)
    idx = find(mask);
    n   = min(numel(idx), 6);
    ra  = zeros(n,1);
    for j = 1:n
        k  = idx(j);
        wa = integrated_energy(apply_filter(u_all{k}, 'ma', D_LP, D_HP));
        wb = integrated_energy(apply_filter(u_all{k}, 'bp', D_LP, D_HP));
        ra(j) = prctile(wb, 99) / prctile(wa, 99);
    end
    r = median(ra);
end


function f1 = f1_of(tp, fp, fn)
    se = tp/max(tp+fn,1)*100;
    pp = tp/max(tp+fp,1)*100;
    if se+pp > 0, f1 = 2*se*pp/(se+pp); else, f1 = 0; end
end


function u = read_vectors(fname)
    fid = fopen(fname, 'r');
    if fid == -1
        error('Vector file not found: %s', fname);
    end
    c = textscan(fid, '%s');
    fclose(fid);
    u = bin2dec(char(c{1}));
end


function peaks = emulate_detector(ws, REFRACT, VULN_LEN, VULN_NUM, THR_INIT, THR_MIN)
    m = numel(ws);
    thr = THR_INIT; last = 0;
    refr_cnt = 0; in_refr = false;
    vuln_cnt = 0; in_vuln = false;
    peaks = zeros(m,1); np = 0;

    for j = 1:m
        win_full = (j >= 8);
        o_in_refr = in_refr;  o_refr_cnt = refr_cnt;
        o_in_vuln = in_vuln;  o_vuln_cnt = vuln_cnt;
        o_thr     = thr;      o_last     = last;

        if o_in_refr
            if o_refr_cnt > 0, refr_cnt = o_refr_cnt - 1; else, in_refr = false; end
        end
        if o_in_vuln
            if o_vuln_cnt > 0, vuln_cnt = o_vuln_cnt - 1; else, in_vuln = false; end
        end

        if win_full && ~o_in_refr
            if o_in_vuln
                ok = ws(j) > o_last * VULN_NUM;
            else
                ok = true;
            end
            if ws(j) > o_thr && ok
                np = np + 1; peaks(np) = j;
                thr  = floor(o_thr/2) + floor(o_thr/4) + floor(ws(j)/4);
                last = ws(j);
                refr_cnt = REFRACT; in_refr = true;
                vuln_cnt = VULN_LEN; in_vuln = true;
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
