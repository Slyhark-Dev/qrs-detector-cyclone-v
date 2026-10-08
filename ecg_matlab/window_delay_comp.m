%% INTEGRATION WINDOW WIDTH, WITH AND WITHOUT DELAY COMPENSATION
% Project: Cardiac arrhythmia detection system - FPGA DE1-SoC
% Universidad Tecnologica del Peru (UTP)
%
% A trailing integrator of W samples delays the series by (W-1)/2. The width
% sweep of window_ds1_ds2.m compares four widths against a fixed annotation
% set without accounting for that, so each width is matched under a different
% alignment: 0, 4, 10 and 23 samples relative to the shipped width, the last
% being 64 ms of a 150 ms tolerance window.
%
% This run repeats the sweep twice. The first pass reproduces the published
% numbers. The second subtracts the analytic delay of each width before
% matching, so the four widths are compared under the same alignment and the
% loss attributable to T-wave energy is separated from the loss attributable
% to the shift.
%
% Delay is referred to the 8-sample width, whose own residual after the
% moving-average trim and the difference is below one sample.
%
% Reads : <batch_dir>/vectors_<rec>.txt and ann_<rec>.txt
% Writes: window_delay_comp.mat
% Recomputes no synthesis figure. No Quartus, no ModelSim.

clc; clear;

batch_dir = 'D:/PROYECTOS/ecg_arrhythmia/batch/';

ds1 = {'101','106','108','109','112','114','115','116','118','119', ...
       '122','124','201','203','205','207','208','209','215','220', ...
       '223','230'};

ds2 = {'100','103','105','111','113','117','121','123','200','202', ...
       '210','212','213','214','219','221','222','228','231','232', ...
       '233','234'};

records = [ds1 ds2];
n_rec   = numel(records);

REFRACT = 72;  VULN_LEN = 160;  VULN_NUM = 3;
THR_INIT = 512000;  THR_MIN = 1500;   % compiled values, for the 8-sample window
tolerance = 54;                        % 150 ms at 360 Hz

W_list = [8 16 27 54];
DELAY  = round((W_list - 8) / 2);      % samples, referred to the shipped width

fprintf('=== INTEGRATION WINDOW WIDTH, DELAY COMPENSATION ===\n\n');
for w = 1:numel(W_list)
    fprintf('Width %2d -> delay %2d samples (%.0f ms)\n', ...
            W_list(w), DELAY(w), DELAY(w)/360*1000);
end
fprintf('\n');

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

is1 = ismember(records, ds1);
is2 = ismember(records, ds2);

CNT_RAW = zeros(n_rec, 3, numel(W_list));
CNT_CMP = zeros(n_rec, 3, numel(W_list));

for w = 1:numel(W_list)
    W   = W_list(w);
    thr_min  = round(THR_MIN  * W / 8);
    thr_init = round(THR_INIT * W / 8);
    fprintf('Window of %2d samples, floor %6d ... ', W, thr_min);
    tw = tic;
    for k = 1:n_rec
        f  = moving_average(u{k});
        ws = integrated_energy(f, W);
        pk = emulate_detector(ws, W, REFRACT, VULN_LEN, VULN_NUM, thr_init, thr_min);

        [tp,fp,fn] = match_peaks(anns{k}, pk, tolerance);
        CNT_RAW(k,:,w) = [tp fp fn];

        [tp,fp,fn] = match_peaks(anns{k}, pk - DELAY(w), tolerance);
        CNT_CMP(k,:,w) = [tp fp fn];
    end
    fprintf('%.0f s\n', toc(tw));
end

RES1_RAW = zeros(numel(W_list),3);  RES2_RAW = zeros(numel(W_list),3);
RES1_CMP = zeros(numel(W_list),3);  RES2_CMP = zeros(numel(W_list),3);
for w = 1:numel(W_list)
    RES1_RAW(w,:) = metrics(sum(CNT_RAW(is1,:,w), 1));
    RES2_RAW(w,:) = metrics(sum(CNT_RAW(is2,:,w), 1));
    RES1_CMP(w,:) = metrics(sum(CNT_CMP(is1,:,w), 1));
    RES2_CMP(w,:) = metrics(sum(CNT_CMP(is2,:,w), 1));
end

fprintf('\n=====================================================================\n');
fprintf('   WITHOUT COMPENSATION (reproduces the published figures)\n');
fprintf('=====================================================================\n\n');
print_block(W_list, RES1_RAW, RES2_RAW);

fprintf('\n=====================================================================\n');
fprintf('   WITH COMPENSATION (same alignment for the four widths)\n');
fprintf('=====================================================================\n\n');
print_block(W_list, RES1_CMP, RES2_CMP);

fprintf('\n=====================================================================\n');
fprintf('   WHAT THE SHIFT WAS WORTH\n');
fprintf('=====================================================================\n\n');
fprintf('%-8s | %8s | %8s | %8s | %8s\n', 'Ancho', 'DS1 sin', 'DS1 con', 'DS2 sin', 'DS2 con');
fprintf('---------|----------|----------|----------|----------\n');
for w = 1:numel(W_list)
    fprintf('%8d | %8.2f | %8.2f | %8.2f | %8.2f\n', W_list(w), ...
            RES1_RAW(w,3), RES1_CMP(w,3), RES2_RAW(w,3), RES2_CMP(w,3));
end

[~, b1] = max(RES1_CMP(:,3));
[~, b2] = max(RES2_CMP(:,3));
fprintf('\nCompensado, optimo sobre DS1: %d muestras\n', W_list(b1));
fprintf('Compensado, optimo sobre DS2: %d muestras\n', W_list(b2));
fprintf('Caida de 8 a 54 sobre DS1: %.2f puntos sin compensar, %.2f compensado\n', ...
        RES1_RAW(1,3) - RES1_RAW(end,3), RES1_CMP(1,3) - RES1_CMP(end,3));
fprintf('Caida de 8 a 54 sobre DS2: %.2f puntos sin compensar, %.2f compensado\n', ...
        RES2_RAW(1,3) - RES2_RAW(end,3), RES2_CMP(1,3) - RES2_CMP(end,3));

save('window_delay_comp.mat', 'records', 'W_list', 'DELAY', 'CNT_RAW', 'CNT_CMP', ...
     'RES1_RAW', 'RES2_RAW', 'RES1_CMP', 'RES2_CMP', 'is1', 'is2');
fprintf('\nSaved to window_delay_comp.mat\n');

%% ====================================================================
%  LOCAL FUNCTIONS
%  ====================================================================

function print_block(W_list, R1, R2)
    fprintf('%-8s | %-22s | %-22s\n', '', 'DS1 (22)', 'DS2 (22)');
    fprintf('%-8s | %6s %6s %6s | %6s %6s %6s\n', 'Ancho', 'Se', '+P', 'F1', 'Se', '+P', 'F1');
    fprintf('---------|------------------------|------------------------\n');
    for w = 1:numel(W_list)
        fprintf('%8d | %6.2f %6.2f %6.2f | %6.2f %6.2f %6.2f\n', W_list(w), ...
                R1(w,1), R1(w,2), R1(w,3), R2(w,1), R2(w,2), R2(w,3));
    end
end


function m = metrics(c)
    se = c(1)/max(c(1)+c(3),1)*100;
    pp = c(1)/max(c(1)+c(2),1)*100;
    if se+pp > 0, f1 = 2*se*pp/(se+pp); else, f1 = 0; end
    m = [se pp f1];
end


function f = moving_average(u)
    f = floor(movsum(u, [7 0]) / 8);
    f = f(8:end);
end


function w = integrated_energy(f, W)
    d = [f(1); diff(f)];
    w = movsum(d.^2, [W-1 0]);
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


function peaks = emulate_detector(ws, W, REFRACT, VULN_LEN, VULN_NUM, THR_INIT, THR_MIN)
    m = numel(ws);
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
