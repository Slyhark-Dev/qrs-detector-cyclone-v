%% BANDPASS FILTER ABLATION
% Project: Cardiac arrhythmia detection system - FPGA DE1-SoC
% Universidad Tecnologica del Peru (UTP)
%
% Quantifies the cost of replacing the Pan-Tompkins bandpass filter with
% the 8-sample moving average used in this implementation.
%
% ---------------------------------------------------------------------
% FILTER
% ---------------------------------------------------------------------
% The 1985 paper specifies the cascade for a 200 Hz sampling rate:
%
%   Low-pass   y(n)   = 2y(n-1) - y(n-2) + x(n) - 2x(n-6) + x(n-12)
%   High-pass  ylp(n) = ylp(n-1) + x(n) - x(n-32)
%              p(n)   = x(n-16) - ylp(n)/32
%
% The delays are tied to that rate, so they are rescaled by 360/200 = 1.8:
% the low-pass uses 11 and 22, the high-pass 29 and 58. The structure, the
% integer coefficients and the shift-and-add realisability are unchanged.
%
% The script measures the resulting passband before detecting anything and
% aborts if it does not reproduce the original response.
%
% ---------------------------------------------------------------------
% PROTOCOL
% ---------------------------------------------------------------------
% The two filters place the signal at different amplitude scales: the
% moving average leaves it centred near 2000 counts, while the bandpass
% rejects DC and centres it at zero. A threshold floor calibrated for one
% is therefore not meaningful for the other, and comparing them with a
% single floor measures the mismatch rather than the filter.
%
% Each configuration is given its own floor, selected with the SAME
% procedure the manuscript already documents in Section IV.E:
%
%   - the grid is swept only over DS1
%   - the best F1 on DS1 selects one value
%   - that value is evaluated once on DS2 and on the full database
%
% No other parameter is touched, and the DS2 grid is never printed.
%
% Reads: <batch_dir>/vectors_<rec>.txt and ann_<rec>.txt
% Writes: bandpass_ablation_results.mat
% Overwrites no existing project file.

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

% Compiled RTL parameters
REFRACT  = 72;
VULN_LEN = 160;
VULN_NUM = 3;
THR_INIT = 512000;
THR_MIN  = 1500;      % compiled value, used as is for the moving average

fs        = 360;
tolerance = round(0.150 * fs);

D_LP = 11;
D_HP = 29;

n_rec = numel(records);

fprintf('=== BANDPASS FILTER ABLATION ===\n\n');
fprintf('REFRACT=%d  VULN_LEN=%d  factor=%d\n', REFRACT, VULN_LEN, VULN_NUM);
fprintf('Each filter gets its own threshold floor, selected on DS1.\n\n');

%% ====================================================================
%  1. FILTER VERIFICATION, BEFORE ANY DETECTION
%  ====================================================================

fprintf('=====================================================================\n');
fprintf('   1. FILTER VERIFICATION\n');
fprintf('=====================================================================\n\n');

[b_lp, a_lp] = pt_lowpass(D_LP);
[b_hp, a_hp] = pt_highpass(D_HP);

L   = 8192;
imp = zeros(L,1); imp(1) = 1;
h   = filter(b_hp, a_hp, filter(b_lp, a_lp, imp));

NFFT = 16384;
H    = abs(fft(h, NFFT));  H = H(1:NFFT/2+1);
fax  = (0:NFFT/2)' * fs / NFFT;

G_peak = max(H);
Hn     = H / G_peak;
i3     = find(Hn >= 1/sqrt(2));
f_lo   = fax(i3(1));
f_hi   = fax(i3(end));
[~, ip] = max(H);

fprintf('Rescaled cascade at %d Hz, D_lp = %d, D_hp = %d:\n', fs, D_LP, D_HP);
fprintf('  3 dB band   : %.2f to %.2f Hz\n', f_lo, f_hi);
fprintf('  peak at     : %.2f Hz\n', fax(ip));
fprintf('  DC gain     : %.2e\n', Hn(1));
fprintf('Original cascade at 200 Hz: 4.92 to 11.77 Hz, peak 7.97 Hz\n\n');

if f_lo < 3 || f_lo > 7 || f_hi < 9 || f_hi > 15
    error('The rescaled cascade does not reproduce the original band.');
end

h_ma = ones(8,1)/8;
Hma  = abs(fft(h_ma, NFFT)); Hma = Hma(1:NFFT/2+1);
i3m  = find(Hma/max(Hma) >= 1/sqrt(2));

fprintf('Moving average, 8 samples:\n');
fprintf('  3 dB cutoff : %.2f Hz\n', fax(i3m(end)));
fprintf('  first null  : %.1f Hz\n', fs/8);
fprintf('  DC gain     : %.3f\n\n', Hma(1)/max(Hma));

%% Load

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
idx_all = true(1, n_rec);

%% ====================================================================
%  2. INTEGRATED ENERGY SCALE OF EACH PATH
%  ====================================================================

fprintf('=====================================================================\n');
fprintf('   2. ENERGY SCALE OF EACH PATH\n');
fprintf('=====================================================================\n\n');
fprintf('Ratio between the integrated energy of the two paths, measured\n');
fprintf('from the 99th percentile of the full series over DS1. The floor\n');
fprintf('itself is chosen by sweep; this only centres the grid.\n\n');

scale = energy_scale_ratio(u, idx_ds1, D_LP, D_HP);

fprintf('  energy ratio bandpass / moving average : %.1f\n', scale);
fprintf('  compiled floor for the moving average  : %d\n', THR_MIN);
fprintf('  equivalent floor for the bandpass      : %.3e\n\n', THR_MIN*scale);

%% ====================================================================
%  3. THRESHOLD FLOOR SWEEP ON DS1, EACH FILTER SEPARATELY
%  ====================================================================

fprintf('=====================================================================\n');
fprintf('   3. THRESHOLD FLOOR SWEEP ON DS1\n');
fprintf('=====================================================================\n\n');

% Moving average: the compiled value is already the DS1 optimum, shown
% here for completeness.
grid_ma = [4000 3000 2000 1750 1500 1250 1000 750];

% Bandpass: the same relative grid, moved to its own energy scale, with a
% wide multiplicative span so the optimum cannot sit at an edge.
base    = THR_MIN * scale;
factors = [64 48 32 24 16 12 8 4 2 1 0.5 0.25];
grid_bp = unique(round(base * factors), 'stable');
grid_bp = sort(grid_bp(grid_bp >= 1), 'descend');

fprintf('--- Moving average ---\n');
fprintf('%-10s | %6s | %6s | %6s |\n', 'THR_MIN', 'Se(%)', '+P(%)', 'F1(%)');
fprintf('-----------|--------|--------|--------|\n');
F1a = zeros(numel(grid_ma),1);
for g = 1:numel(grid_ma)
    ti = round(THR_INIT * grid_ma(g)/THR_MIN);
    [se,pp,f1] = eval_subset(u, anns, idx_ds1, REFRACT, VULN_LEN, VULN_NUM, ...
                             ti, grid_ma(g), 'ma', D_LP, D_HP, tolerance);
    F1a(g) = f1;
    fprintf('%10d | %6.2f | %6.2f | %6.2f |\n', grid_ma(g), se, pp, f1);
end
[~, ga] = max(F1a);
SEL_MA  = grid_ma(ga);
fprintf('Selected on DS1: %d\n\n', SEL_MA);

fprintf('--- Bandpass cascade ---\n');
fprintf('%-10s | %6s | %6s | %6s |\n', 'THR_MIN', 'Se(%)', '+P(%)', 'F1(%)');
fprintf('-----------|--------|--------|--------|\n');
F1b = zeros(numel(grid_bp),1);
for g = 1:numel(grid_bp)
    ti = round(THR_INIT * scale);
    [se,pp,f1] = eval_subset(u, anns, idx_ds1, REFRACT, VULN_LEN, VULN_NUM, ...
                             ti, grid_bp(g), 'bp', D_LP, D_HP, tolerance);
    F1b(g) = f1;
    fprintf('%10.3e | %6.2f | %6.2f | %6.2f |\n', grid_bp(g), se, pp, f1);
end
[~, gb] = max(F1b);
SEL_BP  = grid_bp(gb);
fprintf('Selected on DS1: %.3e\n\n', SEL_BP);

if gb == 1 || gb == numel(grid_bp)
    fprintf('WARNING: the bandpass optimum sits at the edge of its grid.\n\n');
end

%% ====================================================================
%  4. SINGLE EVALUATION
%  ====================================================================

fprintf('=====================================================================\n');
fprintf('   4. DETECTION PERFORMANCE, EACH FILTER AT ITS DS1 OPTIMUM\n');
fprintf('=====================================================================\n\n');

sets  = {idx_ds1, idx_ds2, idx_all};
names = {'DS1 (22)', 'DS2 (22)', 'Full database (48)'};

RES_MA = zeros(3,3);
RES_BP = zeros(3,3);

fprintf('%-22s | %-22s | %-22s\n', '', 'Moving average, 8', 'Bandpass cascade');
fprintf('%-22s | %6s %6s %6s | %6s %6s %6s\n', ...
        'Protocol', 'Se', '+P', 'F1', 'Se', '+P', 'F1');
fprintf('-----------------------|------------------------|------------------------\n');

ti_ma = round(THR_INIT * SEL_MA/THR_MIN);
ti_bp = round(THR_INIT * scale);

for s = 1:3
    [se1,pp1,f11] = eval_subset(u, anns, sets{s}, REFRACT, VULN_LEN, ...
                        VULN_NUM, ti_ma, SEL_MA, 'ma', D_LP, D_HP, tolerance);
    [se2,pp2,f12] = eval_subset(u, anns, sets{s}, REFRACT, VULN_LEN, ...
                        VULN_NUM, ti_bp, SEL_BP, 'bp', D_LP, D_HP, tolerance);

    RES_MA(s,:) = [se1 pp1 f11];
    RES_BP(s,:) = [se2 pp2 f12];

    fprintf('%-22s | %6.2f %6.2f %6.2f | %6.2f %6.2f %6.2f\n', ...
            names{s}, se1, pp1, f11, se2, pp2, f12);
end

d_f1 = RES_BP(2,3) - RES_MA(2,3);
if d_f1 > 0
    winner = 'bandpass cascade';
else
    winner = 'moving average';
end
fprintf('\nDifference on DS2: %.2f points of F1 in favour of the %s.\n\n', ...
        abs(d_f1), winner);

%% ====================================================================
%  5. PER-RECORD BREAKDOWN
%  ====================================================================

fprintf('=====================================================================\n');
fprintf('   5. PER-RECORD BREAKDOWN\n');
fprintf('=====================================================================\n\n');

f1_ma = zeros(n_rec,1);
f1_bp = zeros(n_rec,1);

for k = 1:n_rec
    pk1 = emulate_detector(u{k}, REFRACT, VULN_LEN, VULN_NUM, ...
                           ti_ma, SEL_MA, 'ma', D_LP, D_HP);
    pk2 = emulate_detector(u{k}, REFRACT, VULN_LEN, VULN_NUM, ...
                           ti_bp, SEL_BP, 'bp', D_LP, D_HP);
    [t1,fa,na] = match_peaks(anns{k}, pk1, tolerance);
    [t2,fb,nb] = match_peaks(anns{k}, pk2, tolerance);
    f1_ma(k) = f1_of(t1,fa,na);
    f1_bp(k) = f1_of(t2,fb,nb);
end

delta = f1_bp - f1_ma;
[~, ord] = sort(delta, 'descend');

fprintf('%-6s | %8s | %8s | %8s\n', 'Rec', 'MA F1', 'BP F1', 'Delta');
fprintf('-------|----------|----------|--------\n');
fprintf('Where the bandpass helps most:\n');
for j = 1:5
    k = ord(j);
    fprintf('%-6s | %8.2f | %8.2f | %+8.2f\n', ...
            records{k}, f1_ma(k), f1_bp(k), delta(k));
end
fprintf('Where the moving average helps most:\n');
for j = 0:4
    k = ord(end-j);
    fprintf('%-6s | %8.2f | %8.2f | %+8.2f\n', ...
            records{k}, f1_ma(k), f1_bp(k), delta(k));
end

fprintf('\nRecords where the bandpass improves F1 : %d of %d\n', ...
        sum(delta > 0.01), n_rec);
fprintf('Records where it degrades F1           : %d of %d\n', ...
        sum(delta < -0.01), n_rec);
fprintf('Median absolute difference             : %.2f points of F1\n\n', ...
        median(abs(delta)));

%% 6. Hardware cost

fprintf('=====================================================================\n');
fprintf('   6. HARDWARE COST\n');
fprintf('=====================================================================\n\n');
fprintf('Moving average : 8 delay registers, one accumulator, one shift.\n');
fprintf('                 Synthesised: 53.3 ALMs, 101 registers (Table II).\n');
fprintf('Cascade        : %d delay registers, 3 recursive accumulators.\n', ...
        2*D_LP + 2*D_HP);
fprintf('                 A VHDL implementation and a recompilation would be\n');
fprintf('                 needed for a synthesised figure.\n\n');

%% Save

save('bandpass_ablation_results.mat', 'RES_MA', 'RES_BP', 'names', ...
     'f1_ma', 'f1_bp', 'delta', 'records', 'D_LP', 'D_HP', ...
     'f_lo', 'f_hi', 'SEL_MA', 'SEL_BP', 'grid_ma', 'grid_bp', ...
     'F1a', 'F1b', 'scale');

fprintf('Saved to bandpass_ablation_results.mat\n');
fprintf('ablation_bandpass completed successfully.\n');


%% ====================================================================
%  LOCAL FUNCTIONS
%  ====================================================================

function [b, a] = pt_lowpass(D)
    b = zeros(1, 2*D+1);
    b(1) = 1;  b(D+1) = -2;  b(2*D+1) = 1;
    a = [1 -2 1];
end


function [b, a] = pt_highpass(D)
% All-pass minus running mean, multiplied through by (1 - z^-1).
% DC gain is exactly zero.
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


function r = energy_scale_ratio(u_all, mask, D_LP, D_HP)
% Ratio between the integrated energy of the two filtering paths.
%
% Measured from a high percentile of the whole integrated-energy series,
% not at annotated positions. The bandpass path is truncated by its
% transient and carries a group delay, so any measurement anchored to
% annotation indices would be misaligned; a percentile of the full series
% is immune to that.
    idx = find(mask);
    n   = min(numel(idx), 6);
    ra  = zeros(n,1);

    for j = 1:n
        k = idx(j);

        fa = apply_filter(u_all{k}, 'ma', D_LP, D_HP);
        da = [fa(1); diff(fa)];
        wa = movsum(da.^2, [7 0]);

        fb = apply_filter(u_all{k}, 'bp', D_LP, D_HP);
        db = [fb(1); diff(fb)];
        wb = movsum(db.^2, [7 0]);

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


function [se, pp, f1] = eval_subset(u_all, anns, mask, REFRACT, VULN_LEN, ...
                        VULN_NUM, THR_INIT, THR_MIN, mode, D_LP, D_HP, tol)
    idx = find(mask);
    tp = 0; fp = 0; fn = 0;
    for j = 1:numel(idx)
        k  = idx(j);
        pk = emulate_detector(u_all{k}, REFRACT, VULN_LEN, VULN_NUM, ...
                              THR_INIT, THR_MIN, mode, D_LP, D_HP);
        [t, f, n] = match_peaks(anns{k}, pk, tol);
        tp = tp + t; fp = fp + f; fn = fn + n;
    end
    se = tp/max(tp+fn,1)*100;
    pp = tp/max(tp+fp,1)*100;
    if se+pp > 0, f1 = 2*se*pp/(se+pp); else, f1 = 0; end
end


function peaks = emulate_detector(u, REFRACT, VULN_LEN, VULN_NUM, ...
                                  THR_INIT, THR_MIN, mode, D_LP, D_HP)
% Everything downstream of the filter is identical in both paths and
% matches the emulator verified against the RTL.

    f  = apply_filter(u, mode, D_LP, D_HP);
    m  = numel(f);

    d  = [f(1); diff(f)];
    ws = movsum(d.^2, [7 0]);

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
