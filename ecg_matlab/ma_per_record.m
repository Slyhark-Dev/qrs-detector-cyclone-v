%% MOVING AVERAGE UNDER A PER-RECORD THRESHOLD FLOOR
% Project: Cardiac arrhythmia detection system - FPGA DE1-SoC
% Universidad Tecnologica del Peru (UTP)
%
% The second ablation protocol gives the bandpass cascade a floor fitted to
% each record and compares it against the moving average under its single
% compiled floor. That is an oracle against a non-oracle. This script
% removes the asymmetry: the moving average is swept over the same relative
% grid, referred to its own energy scale, and the best value per record is
% reported the same way.
%
% The grid is the one the cascade received, {16 12 8 4 2 1 0.5 0.25 0.125
% 0.0625} times the base floor, so both filters get the same freedom: same
% number of points, same span, same delay compensation, same matcher.
%
% Either outcome is usable. If the moving average also improves, the cascade
% does not overtake it under equal treatment. If it stays at its compiled
% figure, the asymmetry between the two paths is measured instead of argued.
%
% Reads : <batch_dir>/vectors_<rec>.txt and ann_<rec>.txt
% Writes: ma_per_record.mat
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

REFRACT = 72;  VULN_LEN = 160;  VULN_NUM = 3;
THR_INIT = 512000;  THR_MIN = 1500;
tolerance = 54;                 % 150 ms at 360 Hz
DELAY_MA  = 0;                  % analytic residual of this path

factors = [16 12 8 4 2 1 0.5 0.25 0.125 0.0625];
grid_ma = sort(unique(round(THR_MIN * factors), 'stable'), 'descend');

fprintf('=== MOVING AVERAGE, PER-RECORD FLOOR ===\n\n');
fprintf('Grid: %d values, %d down to %d\n\n', numel(grid_ma), max(grid_ma), min(grid_ma));

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

CNT_FIX = zeros(n_rec,3);       % compiled floor
CNT_ORA = zeros(n_rec,3);       % best floor per record
SEL_R   = zeros(n_rec,1);
F1_FIX  = zeros(n_rec,1);
F1_ORA  = zeros(n_rec,1);

fprintf('%-5s | %8s | %8s | %9s\n', 'Rec', 'compiled', 'oracle', 'floor');
fprintf('------|----------|----------|----------\n');

for k = 1:n_rec
    ann = anns{k};
    f   = moving_average(u{k});
    ws  = integrated_energy(f);

    pk = emulate_detector(ws, REFRACT, VULN_LEN, VULN_NUM, THR_INIT, THR_MIN);
    [t1,f1a,n1] = match_peaks(ann, pk + DELAY_MA, tolerance);
    CNT_FIX(k,:) = [t1 f1a n1];  F1_FIX(k) = f1_of(t1,f1a,n1);

    best = -1;
    for g = 1:numel(grid_ma)
        ti = round(THR_INIT * grid_ma(g) / THR_MIN);
        pc = emulate_detector(ws, REFRACT, VULN_LEN, VULN_NUM, ti, grid_ma(g));
        [t2,f2,n2] = match_peaks(ann, pc + DELAY_MA, tolerance);
        v = f1_of(t2,f2,n2);
        if v > best
            best = v;  CNT_ORA(k,:) = [t2 f2 n2];  SEL_R(k) = grid_ma(g);
        end
    end
    F1_ORA(k) = best;

    fprintf('%-5s | %8.2f | %8.2f | %9d\n', records{k}, F1_FIX(k), F1_ORA(k), SEL_R(k));
end

fprintf('\n=====================================================================\n');
fprintf('   AGGREGATE, BEATS POOLED\n');
fprintf('=====================================================================\n\n');
fprintf('%-20s | %-20s | %6s %6s %6s\n', 'Protocol', 'Floor', 'Se', '+P', 'F1');
fprintf('---------------------|----------------------|----------------------\n');

sets  = {is1, is2, true(1,n_rec)};
names = {'DS1 (22)', 'DS2 (22)', 'Full database (48)'};
RES   = zeros(3,2,3);
for s = 1:3
    m = sets{s};
    for j = 1:2
        C = {CNT_FIX, CNT_ORA};
        c = sum(C{j}(m,:), 1);
        se = c(1)/max(c(1)+c(3),1)*100;
        pp = c(1)/max(c(1)+c(2),1)*100;
        RES(s,j,:) = [se pp f1_of(c(1),c(2),c(3))];
    end
    fprintf('%-20s | %-20s | %6.2f %6.2f %6.2f\n', names{s}, 'compiled, single', ...
            RES(s,1,1), RES(s,1,2), RES(s,1,3));
    fprintf('%-20s | %-20s | %6.2f %6.2f %6.2f\n', '', 'oracle, per record', ...
            RES(s,2,1), RES(s,2,2), RES(s,2,3));
end

fprintf('\nOn DS2 the per-record floor moves the moving average by %+.2f F1 points.\n', ...
        RES(2,2,3) - RES(2,1,3));
fprintf('Records where the compiled floor is already the best of the grid: %d of %d\n', ...
        sum(SEL_R == THR_MIN), n_rec);
fprintf('Floors selected: %d down to %d, a span of %.0f.\n', ...
        max(SEL_R), min(SEL_R), max(SEL_R)/min(SEL_R));

save('ma_per_record.mat', 'records', 'grid_ma', 'CNT_FIX', 'CNT_ORA', 'SEL_R', ...
     'F1_FIX', 'F1_ORA', 'RES', 'is1', 'is2');
fprintf('\nSaved to ma_per_record.mat\n');

%% ====================================================================
%  LOCAL FUNCTIONS
%  ====================================================================

function f = moving_average(u)
    f = floor(movsum(u, [7 0]) / 8);
    f = f(8:end);
end


function w = integrated_energy(f)
    d = [f(1); diff(f)];
    w = movsum(d.^2, [7 0]);
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
