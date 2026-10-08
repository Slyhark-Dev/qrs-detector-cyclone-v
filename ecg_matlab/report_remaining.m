%% REMAINING FIGURES UNDER FIXED CALIBRATION
% Project: Cardiac arrhythmia detection system - FPGA DE1-SoC
% Universidad Tecnologica del Peru (UTP)
%
% Recomputes every remaining number quoted in the manuscript under the
% fixed-calibration configuration with THR_MIN = 1500.
%
% Sections produced:
%   1. Table VII, effect of the fixed-point simplifications
%   2. Integration window ablation
%   3. Secondary-threshold rate ceiling
%   4. Fiducial jitter, for equation (2)
%   5. Stratified limits of agreement
%   6. Start-up transient
%   7. Matching at 300 ms, comparable with Chen
%
% The emulator reproduces the RTL exactly on all 48 records, verified with
% emulate_rtl.m, so it is a valid substitute here and avoids one ModelSim
% batch per configuration.
%
% Reads: <batch_dir>/vectors_<rec>.txt and ann_<rec>.txt
% Writes: remaining_figures_fixed_cal.mat
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
THR_MIN  = 1500;

fs        = 360;
tolerance = round(0.150 * fs);

n_rec = numel(records);

fprintf('=== REMAINING FIGURES, FIXED CALIBRATION, THR_MIN = %d ===\n\n', THR_MIN);

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
%  1. TABLE VII, fixed-point simplifications
%  ====================================================================

fprintf('=====================================================================\n');
fprintf('   1. TABLE VII, EFFECT OF THE SIMPLIFICATIONS\n');
fprintf('=====================================================================\n\n');
fprintf('Evaluated over the 48 records, same matching protocol throughout.\n\n');
fprintf('%-34s | %6s | %6s | %6s\n', 'Configuration', 'Se(%)', '+P(%)', 'F1(%)');
fprintf('-----------------------------------|--------|--------|-------\n');

% (a) final configuration
[se_f, pp_f, f1_f] = eval_subset(u, anns, idx_all, REFRACT, VULN_LEN, ...
                                 VULN_NUM, THR_INIT, THR_MIN, 0, 8, tolerance);
fprintf('%-34s | %6.2f | %6.2f | %6.2f\n', 'Final configuration', se_f, pp_f, f1_f);

% (b) no secondary threshold: VULN_LEN = 0
[se_n, pp_n, f1_n] = eval_subset(u, anns, idx_all, REFRACT, 0, ...
                                 VULN_NUM, THR_INIT, THR_MIN, 0, 8, tolerance);
fprintf('%-34s | %6.2f | %6.2f | %6.2f\n', 'No secondary threshold', se_n, pp_n, f1_n);

% (c) preliminary configuration: 16-bit energy, decay without floor
[se_p, pp_p, f1_p] = eval_prelim(u, anns, idx_all, REFRACT, VULN_LEN, ...
                                 VULN_NUM, tolerance);
fprintf('%-34s | %6.2f | %6.2f | %6.2f\n\n', 'Preliminary configuration', ...
        se_p, pp_p, f1_p);

fprintf('Previously reported: 89.73/99.80/94.50, 99.78/84.66/91.60, 99.42/96.63/98.01\n\n');

%% ====================================================================
%  2. INTEGRATION WINDOW ABLATION
%  ====================================================================

fprintf('=====================================================================\n');
fprintf('   2. INTEGRATION WINDOW ABLATION\n');
fprintf('=====================================================================\n\n');
fprintf('The threshold floor scales with the window width, since the\n');
fprintf('accumulated energy grows linearly with the number of terms.\n\n');

W_list = [8 16 27 54];
fprintf('%-26s | %6s | %6s | %6s | %8s\n', 'Window', 'Se(%)', '+P(%)', 'F1(%)', 'THR_MIN');
fprintf('---------------------------|--------|--------|--------|--------\n');

WIN = zeros(numel(W_list), 3);
for a = 1:numel(W_list)
    W  = W_list(a);
    tm = round(THR_MIN * W / 8);
    ti = round(THR_INIT * W / 8);
    [se, pp, f1] = eval_subset(u, anns, idx_ds2, REFRACT, VULN_LEN, ...
                               VULN_NUM, ti, tm, 0, W, tolerance);
    WIN(a,:) = [se pp f1];

    et = sprintf('%2d samples (%5.1f ms)', W, W/fs*1000);
    if W == 8,  et = [et ' *'];  end
    if W == 54, et = [et ' PT']; end
    fprintf('%-26s | %6.2f | %6.2f | %6.2f | %8d\n', et, se, pp, f1, tm);
end
fprintf('\nEvaluated on DS2. * synthesized, PT the Pan-Tompkins width.\n\n');

%% ====================================================================
%  3. SECONDARY-THRESHOLD RATE CEILING
%  ====================================================================

fprintf('=====================================================================\n');
fprintf('   3. SECONDARY-THRESHOLD RATE CEILING\n');
fprintf('=====================================================================\n\n');

BLOCK_END = VULN_LEN + 1;
fprintf('Effective refractory: %d samples = %.0f ms = %.0f BPM\n\n', ...
        BLOCK_END, BLOCK_END/fs*1000, 21600/BLOCK_END);

n_short = 0; fn_short = 0;
n_long  = 0; fn_long  = 0;
fn_total = 0;

for k = 1:n_rec
    pk  = emulate_detector(u{k}, REFRACT, VULN_LEN, VULN_NUM, ...
                           THR_INIT, THR_MIN, 0, 8);
    ann = anns{k};
    matched = match_annotations(ann, pk, tolerance);

    rr = [inf; diff(ann(:))];
    s  = rr <= BLOCK_END;

    n_short  = n_short  + sum(s);
    fn_short = fn_short + sum(s & ~matched);
    n_long   = n_long   + sum(~s);
    fn_long  = fn_long  + sum(~s & ~matched);
    fn_total = fn_total + sum(~matched);
end

r_short = fn_short/max(n_short,1)*100;
r_long  = fn_long /max(n_long ,1)*100;

fprintf('RR <= %d samples : %d beats (%.2f%% of base), %d FN, rate %.2f%%\n', ...
        BLOCK_END, n_short, n_short/(n_short+n_long)*100, fn_short, r_short);
fprintf('RR >  %d samples : %d beats, %d FN, rate %.2f%%\n', ...
        BLOCK_END, n_long, fn_long, r_long);
fprintf('Ratio between rates: %.1fx\n', r_short/max(r_long,1e-9));
fprintf('Short-RR share of all FN: %.1f%% (%d of %d)\n\n', ...
        fn_short/max(fn_total,1)*100, fn_short, fn_total);
fprintf('Previously: 3117 beats, 2.85%%, 261 FN, 8.37%% vs 0.35%%, 40.9%%\n\n');

%% ====================================================================
%  4. FIDUCIAL JITTER, FOR EQUATION (2)
%  ====================================================================

fprintf('=====================================================================\n');
fprintf('   4. FIDUCIAL JITTER\n');
fprintf('=====================================================================\n\n');

d_all = [];
for k = 1:n_rec
    if ~idx_ds2(k), continue; end
    pk  = emulate_detector(u{k}, REFRACT, VULN_LEN, VULN_NUM, ...
                           THR_INIT, THR_MIN, 0, 8);
    ann = anns{k};
    for j = 1:numel(pk)
        [dd, ix] = min(abs(ann - pk(j)));
        if dd <= tolerance
            d_all(end+1,1) = pk(j) - ann(ix); %#ok<AGROW>
        end
    end
end

sd_loc = std(d_all);
sd_rr  = sd_loc * sqrt(2);

fprintf('Offset between each detection and its matched annotation, DS2:\n');
fprintf('  median %.1f  MAD %.2f  IQR %.1f  SD %.2f samples\n\n', ...
        median(d_all), median(abs(d_all-median(d_all))), iqr(d_all), sd_loc);
fprintf('RR interval SD, assuming independent errors: %.2f samples\n\n', sd_rr);

fprintf('Equation (2): sigma_BPM = sigma_RR * BPM^2 / 21600\n\n');
fprintf('%-12s | %-16s | %s\n', 'Rate', 'RR (samples)', 'predicted sigma_BPM');
fprintf('-------------|------------------|--------------------\n');
for b = [50 60 75 100 120 150]
    fprintf('%9d   | %14.0f   | %10.2f\n', b, 21600/b, sd_rr*b*b/21600);
end

SD_TAB6 = 3.058;
fprintf('\nTable VI reports SD = %.2f BPM, which the law reaches at %.0f BPM\n', ...
        SD_TAB6, sqrt(SD_TAB6*21600/sd_rr));
fprintf('Previously: SD 8.52 samples, RR 12.05, Table VI 3.41 at 78 BPM\n\n');

%% ====================================================================
%  5. STRATIFIED LIMITS OF AGREEMENT
%  ====================================================================

fprintf('=====================================================================\n');
fprintf('   5. STRATIFIED LIMITS OF AGREEMENT\n');
fprintf('=====================================================================\n\n');

bands = [0 60; 60 80; 80 100; 100 120; 120 250];
band_names = {'< 60', '60-80', '80-100', '100-120', '> 120'};

hw = []; rf = []; cons = [];
paced = {'102','104','107','217'};

for k = 1:n_rec
    if ismember(records{k}, paced), continue; end

    pk  = emulate_detector(u{k}, REFRACT, VULN_LEN, VULN_NUM, ...
                           THR_INIT, THR_MIN, 0, 8);
    ann = anns{k};

    prev_idx = -1;
    prev_pk  = -1;

    for j = 1:numel(pk)
        [dd, ix] = min(abs(ann - pk(j)));
        if dd > tolerance || ix < 2
            prev_idx = -1; prev_pk = pk(j); continue;
        end

        rr_ann = ann(ix) - ann(ix-1);
        if rr_ann <= 0 || prev_pk < 0
            prev_idx = ix; prev_pk = pk(j); continue;
        end

        rr_hw = pk(j) - prev_pk;
        if rr_hw <= 0
            prev_idx = ix; prev_pk = pk(j); continue;
        end

        b_hw  = 21600 / rr_hw;
        b_ref = 21600 / rr_ann;

        if b_hw >= 20 && b_hw <= 250 && b_ref >= 20 && b_ref <= 250
            hw(end+1,1)   = b_hw;  %#ok<AGROW>
            rf(end+1,1)   = b_ref; %#ok<AGROW>
            cons(end+1,1) = (prev_idx == ix - 1); %#ok<AGROW>
        end

        prev_idx = ix; prev_pk = pk(j);
    end
end

cons = logical(cons);
d_c  = hw(cons) - rf(cons);
r_c  = rf(cons);

fprintf('Consistent-cadence beats: %d\n', numel(d_c));
fprintf('Global: bias %+.2f  SD %.2f  LoA [%+.2f %+.2f]\n\n', ...
        mean(d_c), std(d_c), mean(d_c)+1.96*std(d_c), mean(d_c)-1.96*std(d_c));

fprintf('%-10s | %8s | %8s | %8s | %9s | %9s\n', ...
        'Band', 'N', 'Bias', 'SD', 'LoA up', 'LoA low');
fprintf('-----------|----------|----------|----------|-----------|----------\n');

BAND_SD = zeros(size(bands,1),1);
BAND_N  = zeros(size(bands,1),1);

for b = 1:size(bands,1)
    if bands(b,2) >= 250
        m = r_c >= bands(b,1) & r_c <= bands(b,2);
    else
        m = r_c >= bands(b,1) & r_c < bands(b,2);
    end
    n = sum(m);
    BAND_N(b) = n;
    if n < 10
        fprintf('%-10s | %8d | %8s | %8s | %9s | %9s\n', ...
                band_names{b}, n, '--', '--', '--', '--');
        continue;
    end
    dd = d_c(m);
    BAND_SD(b) = std(dd);
    fprintf('%-10s | %8d | %+8.2f | %8.2f | %+9.2f | %+9.2f\n', ...
            band_names{b}, n, mean(dd), std(dd), ...
            mean(dd)+1.96*std(dd), mean(dd)-1.96*std(dd));
end

vb = find(BAND_N >= 10);
if numel(vb) >= 2
    fprintf('\nSD grows from %.2f BPM (%s) to %.2f BPM (%s), a factor of %.1f\n', ...
            BAND_SD(vb(1)), band_names{vb(1)}, ...
            BAND_SD(vb(end)), band_names{vb(end)}, ...
            BAND_SD(vb(end))/BAND_SD(vb(1)));
end
fprintf('Previously: 0.76 to 7.69 BPM, factor of ten\n\n');

%% ====================================================================
%  6. START-UP TRANSIENT
%  ====================================================================

fprintf('=====================================================================\n');
fprintf('   6. START-UP TRANSIENT\n');
fprintf('=====================================================================\n\n');

n_startup = zeros(n_rec,1);
first_idx = zeros(n_rec,1);

for k = 1:n_rec
    pk  = emulate_detector(u{k}, REFRACT, VULN_LEN, VULN_NUM, ...
                           THR_INIT, THR_MIN, 0, 8);
    ann = anns{k};
    early = pk(pk <= fs);
    c = 0;
    for j = 1:numel(early)
        if isempty(ann) || min(abs(ann - early(j))) > tolerance
            c = c + 1;
        end
    end
    n_startup(k) = c;
    if ~isempty(pk), first_idx(k) = pk(1); end
end

fprintf('Records with a start-up false positive: %d of %d\n', ...
        sum(n_startup > 0), n_rec);
fprintf('Total such events: %d\n', sum(n_startup));
fprintf('Distribution: %d with 0, %d with 1, %d with more than 1\n', ...
        sum(n_startup==0), sum(n_startup==1), sum(n_startup>1));
fprintf('Median index of the first detection: %.0f samples (%.3f s)\n\n', ...
        median(first_idx), median(first_idx)/fs);
fprintf('Previously: 42 of 48 records, one each, at sample 8\n\n');

%% ====================================================================
%  7. MATCHING AT 300 ms, COMPARABLE WITH CHEN
%  ====================================================================

fprintf('=====================================================================\n');
fprintf('   7. MATCHING AT 300 ms\n');
fprintf('=====================================================================\n\n');

tol300 = round(0.300 * fs);

fprintf('%-22s | %6s | %6s | %6s\n', 'Protocol', 'Se(%)', '+P(%)', 'F1(%)');
fprintf('-----------------------|--------|--------|-------\n');

[se, pp, f1] = eval_subset(u, anns, idx_all, REFRACT, VULN_LEN, VULN_NUM, ...
                           THR_INIT, THR_MIN, 0, 8, tolerance);
fprintf('%-22s | %6.2f | %6.2f | %6.2f\n', 'Full base, 150 ms', se, pp, f1);

[se3, pp3, f13] = eval_subset(u, anns, idx_all, REFRACT, VULN_LEN, VULN_NUM, ...
                              THR_INIT, THR_MIN, 0, 8, tol300);
fprintf('%-22s | %6.2f | %6.2f | %6.2f\n\n', 'Full base, 300 ms', se3, pp3, f13);

fprintf('Chen reports, 300 ms, full base without exclusions: 99.80 / 99.92\n\n');

%% Save

save('remaining_figures_fixed_cal.mat', ...
     'se_f','pp_f','f1_f','se_n','pp_n','f1_n','se_p','pp_p','f1_p', ...
     'W_list','WIN','n_short','fn_short','n_long','fn_long','fn_total', ...
     'sd_loc','sd_rr','d_all','bands','band_names','BAND_SD','BAND_N', ...
     'n_startup','first_idx','se3','pp3','f13');

fprintf('Saved to remaining_figures_fixed_cal.mat\n');
fprintf('report_remaining completed successfully.\n');


%% ====================================================================
%  LOCAL FUNCTIONS
%  ====================================================================

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
                                    VULN_NUM, THR_INIT, THR_MIN, TRUNC, W, tol)
    idx = find(mask);
    tp = 0; fp = 0; fn = 0;
    for j = 1:numel(idx)
        k  = idx(j);
        pk = emulate_detector(u_all{k}, REFRACT, VULN_LEN, VULN_NUM, ...
                              THR_INIT, THR_MIN, TRUNC, W);
        [t, f, n] = match_peaks(anns{k}, pk, tol);
        tp = tp + t; fp = fp + f; fn = fn + n;
    end
    se = tp/max(tp+fn,1)*100;
    pp = tp/max(tp+fp,1)*100;
    if se+pp > 0, f1 = 2*se*pp/(se+pp); else, f1 = 0; end
end


function [se, pp, f1] = eval_prelim(u_all, anns, mask, REFRACT, VULN_LEN, ...
                                    VULN_NUM, tol)
% Preliminary configuration: 16 most significant bits of the squared
% derivative, decay as a pure fraction with no floor, THR_INIT = 500.
    idx = find(mask);
    tp = 0; fp = 0; fn = 0;
    for j = 1:numel(idx)
        k  = idx(j);
        pk = emulate_prelim(u_all{k}, REFRACT, VULN_LEN, VULN_NUM);
        [t, f, n] = match_peaks(anns{k}, pk, tol);
        tp = tp + t; fp = fp + f; fn = fn + n;
    end
    se = tp/max(tp+fn,1)*100;
    pp = tp/max(tp+fp,1)*100;
    if se+pp > 0, f1 = 2*se*pp/(se+pp); else, f1 = 0; end
end


function peaks = emulate_detector(u, REFRACT, VULN_LEN, VULN_NUM, ...
                                  THR_INIT, THR_MIN, TRUNC, W)
% Literal copy of the emulator verified against the RTL, with the
% truncation and the window width as parameters. TRUNC = 0 and W = 8
% reproduce the compiled configuration.

    suma = movsum(u, [7 0]);
    f    = floor(suma / 8);
    f    = f(8:end);
    m    = numel(f);

    d  = [f(1); diff(f)];
    sq = d.^2;
    if TRUNC > 0
        sq = floor(sq / 2^TRUNC);
    end

    ws = movsum(sq, [W-1 0]);

    thr = THR_INIT; last = 0;
    refr_cnt = 0; in_refr = false;
    vuln_cnt = 0; in_vuln = false;

    peaks = zeros(m,1); np = 0;

    for j = 1:m
        win_full = (j >= W);

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
            if o_in_vuln && VULN_LEN > 0
                ok = ws(j) > o_last * VULN_NUM;
            else
                ok = true;
            end

            if ws(j) > o_thr && ok
                np = np + 1; peaks(np) = j;
                thr  = floor(o_thr/2) + floor(o_thr/4) + floor(ws(j)/4);
                last = ws(j);
                refr_cnt = REFRACT; in_refr = true;
                if VULN_LEN > 0
                    vuln_cnt = VULN_LEN; in_vuln = true;
                end
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


function peaks = emulate_prelim(u, REFRACT, VULN_LEN, VULN_NUM)
% Preliminary configuration as originally implemented: 16 most
% significant bits of the square, decay as threshold - threshold/32 with
% no lower floor, THR_INIT = 500.

    THR_INIT_P = 500;

    suma = movsum(u, [7 0]);
    f    = floor(suma / 8);
    f    = f(8:end);
    m    = numel(f);

    d  = [f(1); diff(f)];
    sq = floor(d.^2 / 1024);          % keep the 16 MSB of a 26-bit product

    ws = movsum(sq, [7 0]);

    thr = THR_INIT_P; last = 0;
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
                thr = o_thr - floor(o_thr/32);   % no floor
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


function matched_ann = match_annotations(ann_peaks, det_peaks, tolerance)
    matched_ann = false(numel(ann_peaks), 1);
    for d = 1:numel(det_peaks)
        distances = abs(ann_peaks - det_peaks(d));
        [min_dist, min_idx] = min(distances);
        if min_dist <= tolerance && ~matched_ann(min_idx)
            matched_ann(min_idx) = true;
        end
    end
end
