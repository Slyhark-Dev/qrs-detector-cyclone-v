%% THRESHOLD FLOOR SWEEP ON DS1 UNDER FIXED CALIBRATION
% Project: Cardiac arrhythmia detection system - FPGA DE1-SoC
% Universidad Tecnologica del Peru (UTP)
%
% Selects the threshold floor for the fixed-calibration configuration.
%
% The vectors read here are the ones just regenerated with the format 212
% calibration constant, so the amplitude scale differs from the previous
% configuration and the floor has to be reselected.
%
% Protocol, identical to the one reported in the manuscript:
%   - the grid is swept ONLY over DS1
%   - the best F1 on DS1 selects a single value
%   - that value is evaluated once on DS2 and on the full database
%   - the DS2 grid is never printed, so the choice cannot lean on the
%     evaluation set
%
% Every other detector parameter keeps the compiled RTL value. Only the
% floor is swept.
%
% Reads: <batch_dir>/vectors_<rec>.txt and ann_<rec>.txt
% Writes: floor_fixed_cal_results.mat

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

% Compiled RTL parameters. Only THR_MIN is swept.
REFRACT  = 72;
VULN_LEN = 160;
VULN_NUM = 3;
THR_INIT = 512000;

fs        = 360;
tolerance = round(0.150 * fs);

% Search grid around the value obtained in the earlier exploration
floor_grid = [4000 3000 2500 2000 1750 1500 1250 1000 750 500];

n_rec = numel(records);

fprintf('=== THRESHOLD FLOOR SWEEP ON DS1, FIXED CALIBRATION ===\n\n');
fprintf('REFRACT=%d  VULN_LEN=%d  factor=%d  THR_INIT=%d\n', ...
        REFRACT, VULN_LEN, VULN_NUM, THR_INIT);
fprintf('Grid: %d values of THR_MIN\n\n', numel(floor_grid));

%% 1. Read the regenerated vectors and the annotations

u    = cell(n_rec,1);
anns = cell(n_rec,1);

fprintf('Reading vectors...\n');
t0 = tic;

for k = 1:n_rec
    rec = records{k};

    fv = [batch_dir 'vectors_' rec '.txt'];
    fa = [batch_dir 'ann_'     rec '.txt'];

    if ~isfile(fv) || ~isfile(fa)
        error('Missing file for record %s', rec);
    end

    u{k}    = read_vectors(fv);
    anns{k} = readmatrix(fa);
    anns{k} = anns{k}(:);
end

fprintf('Read completed in %.1f s\n\n', toc(t0));

idx_ds1 = ismember(records, ds1);
idx_ds2 = ismember(records, ds2);
idx_all = true(1, n_rec);

%% 2. Grid over DS1

n_g = numel(floor_grid);
SE = zeros(n_g,1);
PP = zeros(n_g,1);
F1 = zeros(n_g,1);

fprintf('=====================================================================\n');
fprintf('   THR_MIN GRID ON DS1 (22 records)\n');
fprintf('=====================================================================\n\n');
fprintf('%-10s | %6s | %6s | %6s |\n', 'THR_MIN', 'Se(%)', '+P(%)', 'F1(%)');
fprintf('-----------|--------|--------|--------|\n');

t0 = tic;

for g = 1:n_g
    [se, pp, f1] = eval_subset(u, anns, idx_ds1, REFRACT, VULN_LEN, ...
                               VULN_NUM, THR_INIT, floor_grid(g), tolerance);
    SE(g) = se; PP(g) = pp; F1(g) = f1;
end

for g = 1:n_g
    marca = '';
    if F1(g) == max(F1)
        marca = '  <- best on DS1';
    end
    fprintf('%10d | %6.2f | %6.2f | %6.2f |%s\n', ...
            floor_grid(g), SE(g), PP(g), F1(g), marca);
end

fprintf('\nGrid completed in %.1f s\n', toc(t0));

[~, gb] = max(F1);
SEL = floor_grid(gb);

if gb == 1 || gb == n_g
    fprintf('\nWARNING: the optimum sits at the edge of the grid. Widen it\n');
    fprintf('before adopting the value.\n');
end

%% 3. Single evaluation of the selected value

fprintf('\n=====================================================================\n');
fprintf('   SELECTED ON DS1: THR_MIN = %d\n', SEL);
fprintf('=====================================================================\n\n');

subsets = {idx_ds1, idx_ds2, idx_all};
names   = {'DS1 (22)', 'DS2 (22)', 'Full database (48)'};

RES = zeros(3,3);

fprintf('%-22s | %6s | %6s | %6s\n', 'Protocol', 'Se(%)', '+P(%)', 'F1(%)');
fprintf('-----------------------|--------|--------|-------\n');

for s = 1:3
    [se, pp, f1] = eval_subset(u, anns, subsets{s}, REFRACT, VULN_LEN, ...
                               VULN_NUM, THR_INIT, SEL, tolerance);
    RES(s,:) = [se pp f1];
    fprintf('%-22s | %6.2f | %6.2f | %6.2f\n', names{s}, se, pp, f1);
end

%% 4. Reference against the previously reported configuration

fprintf('\n=====================================================================\n');
fprintf('   REFERENCE\n');
fprintf('=====================================================================\n\n');
fprintf('Previously reported, per-record scaling, THR_MIN=4000:\n');
fprintf('  DS2: Se 99.65  +P 96.53  F1 98.07\n\n');
fprintf('Fixed calibration, THR_MIN=%d, selected on DS1:\n', SEL);
fprintf('  DS2: Se %5.2f  +P %5.2f  F1 %5.2f\n\n', ...
        RES(2,1), RES(2,2), RES(2,3));

fprintf('These are emulator figures. They are NOT the values to report.\n');
fprintf('The reported figures must come from the RTL batch simulation once\n');
fprintf('THR_MIN = %d is compiled into qrs_detector.vhd.\n', SEL);

%% 5. Save

save('floor_fixed_cal_results.mat', 'floor_grid', 'SE', 'PP', 'F1', ...
     'SEL', 'RES', 'REFRACT', 'VULN_LEN', 'VULN_NUM', 'THR_INIT');

fprintf('\nSaved to floor_fixed_cal_results.mat\n');
fprintf('sweep_floor_fixed_cal completed successfully.\n');


%% ====================================================================
%  LOCAL FUNCTIONS
%  ====================================================================

function u = read_vectors(fname)
% Reads the 12-bit binary vector file, one sample per line.
% Copy of the homonymous function in emulate_rtl.m.
    fid = fopen(fname, 'r');
    if fid == -1
        error('Vector file not found: %s', fname);
    end
    c = textscan(fid, '%s');
    fclose(fid);
    u = bin2dec(char(c{1}));
end


function [se, pp, f1] = eval_subset(u_all, anns, mask, REFRACT, VULN_LEN, ...
                                    VULN_NUM, THR_INIT, THR_MIN, tolerance)
    idx = find(mask);
    tp = 0; fp = 0; fn = 0;

    for j = 1:numel(idx)
        k  = idx(j);
        pk = emulate_detector(u_all{k}, REFRACT, VULN_LEN, VULN_NUM, ...
                              THR_INIT, THR_MIN);
        [t, f, n] = match_peaks(anns{k}, pk, tolerance);
        tp = tp + t; fp = fp + f; fn = fn + n;
    end

    se = safe_pct(tp, tp+fn);
    pp = safe_pct(tp, tp+fp);
    if se + pp > 0
        f1 = 2*se*pp/(se+pp);
    else
        f1 = 0;
    end
end


function p = safe_pct(a, b)
    if b > 0
        p = a / b * 100;
    else
        p = 0;
    end
end


function peaks = emulate_detector(u, REFRACT, VULN_LEN, VULN_NUM, ...
                                  THR_INIT, THR_MIN)
% Literal copy of the homonymous function in emulate_rtl.m.

    suma = movsum(u, [7 0]);
    f    = floor(suma / 8);
    f    = f(8:end);
    m    = numel(f);

    d  = [f(1); diff(f)];
    sq = d.^2;

    ws = movsum(sq, [7 0]);

    thr      = THR_INIT;
    last     = 0;
    refr_cnt = 0;
    in_refr  = false;
    vuln_cnt = 0;
    in_vuln  = false;

    peaks = zeros(m,1);
    np    = 0;

    for j = 1:m
        win_count_full = (j >= 8);

        o_in_refr  = in_refr;
        o_refr_cnt = refr_cnt;
        o_in_vuln  = in_vuln;
        o_vuln_cnt = vuln_cnt;
        o_thr      = thr;
        o_last     = last;

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


function [TP, FP, FN] = match_peaks(ann_peaks, det_peaks, tolerance)
% Literal copy of the matching used in compare_vhdl_batch.m: no latency
% correction, each annotation matched at most once.

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
