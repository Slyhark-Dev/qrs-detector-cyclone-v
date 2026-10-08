%% COMPARE VHDL BATCH RESULTS
% Project: Cardiac arrhythmia detection system - FPGA DE1-SoC
% Universidad Tecnologica del Peru (UTP)
%
% Evaluates the ModelSim batch simulation of the full MIT-BIH database.
% Produces two independent sets of metrics:
%
%   A) VHDL vs cardiologist annotations  -> hardware detection performance
%   B) VHDL vs pan_tompkins_causal       -> hardware/software equivalence
%
% Matching tolerance: 150 ms (54 samples at 360 Hz), per ANSI/AAMI EC57.
%
% Requires the outputs of generate_vhdl_vectors_batch.m and run_batch.do
% in <batch_dir>.

clc; clear; close all;

%% 1. Configuration
records = {'100','101','102','103','104','105','106','107','108','109', ...
           '111','112','113','114','115','116','117','118','119', ...
           '121','122','123','124', ...
           '200','201','202','203','205','207','208','209','210', ...
           '212','213','214','215','217','219', ...
           '220','221','222','223','228', ...
           '230','231','232','233','234'};

batch_dir = 'D:/proyectos/ecg_arrhythmia/batch/';
fs        = 360;
tolerance = round(0.150 * fs);

fprintf('=== VHDL BATCH EVALUATION ===\n');
fprintf('Records: %d\n', length(records));
fprintf('Tolerance window: %d samples (%.0f ms)\n\n', tolerance, tolerance/fs*1000);

res = struct();

%% 2. Per-record evaluation
for k = 1:length(records)
    rec = records{k};

    ann  = load_indices(fullfile(batch_dir, ['ann_' rec '.txt']));
    ml   = load_indices(fullfile(batch_dir, ['matlab_qrs_' rec '.txt']));
    vhdl = load_indices(fullfile(batch_dir, ['vhdl_qrs_' rec '.txt']));

    % Pipeline latency: the VHDL sample index advances only on filter
    % out_valid, so detections carry a fixed offset relative to the input
    % sample index. Estimated as the median nearest-neighbour offset and
    % reported, not corrected.
    lag = estimate_lag(ann, vhdl, tolerance);

    % A) hardware vs cardiologist annotations
    [TPa, FPa, FNa] = match_peaks(ann, vhdl, tolerance);
    se_a = TPa / (TPa + FNa) * 100;
    pp_a = TPa / (TPa + FPa) * 100;
    f1_a = harmonic(se_a, pp_a);

    % B) hardware vs MATLAB reference
    [TPb, FPb, FNb] = match_peaks(ml, vhdl, tolerance);
    se_b = TPb / (TPb + FNb) * 100;
    pp_b = TPb / (TPb + FPb) * 100;
    f1_b = harmonic(se_b, pp_b);

    res(k).record  = rec;
    res(k).n_ann   = length(ann);
    res(k).n_ml    = length(ml);
    res(k).n_vhdl  = length(vhdl);
    res(k).lag     = lag;

    res(k).TPa = TPa; res(k).FPa = FPa; res(k).FNa = FNa;
    res(k).se_a = se_a; res(k).pp_a = pp_a; res(k).f1_a = f1_a;

    res(k).TPb = TPb; res(k).FPb = FPb; res(k).FNb = FNb;
    res(k).se_b = se_b; res(k).pp_b = pp_b; res(k).f1_b = f1_b;
end

%% 3. Table A: VHDL vs cardiologist annotations
fprintf('=====================================================================\n');
fprintf('   A) VHDL HARDWARE vs MIT-BIH ANNOTATIONS\n');
fprintf('=====================================================================\n');
fprintf('Record | Annot | VHDL  | TP    | FP   | FN   | Se(%%)  | +P(%%)  | F1(%%)\n');
fprintf('-------|-------|-------|-------|------|------|--------|--------|-------\n');

TA = 0; FA = 0; NA = 0;
for k = 1:length(records)
    r = res(k);
    fprintf('  %s  | %5d | %5d | %5d | %4d | %4d | %6.2f | %6.2f | %5.2f\n', ...
        r.record, r.n_ann, r.n_vhdl, r.TPa, r.FPa, r.FNa, r.se_a, r.pp_a, r.f1_a);
    TA = TA + r.TPa; FA = FA + r.FPa; NA = NA + r.FNa;
end

se_A = TA / (TA + NA) * 100;
pp_A = TA / (TA + FA) * 100;
f1_A = harmonic(se_A, pp_A);

fprintf('-------|-------|-------|-------|------|------|--------|--------|-------\n');
fprintf(' TOTAL |       |       | %5d | %4d | %4d | %6.2f | %6.2f | %5.2f\n', ...
        TA, FA, NA, se_A, pp_A, f1_A);
fprintf('=====================================================================\n\n');

%% 4. Table B: VHDL vs MATLAB reference
fprintf('=====================================================================\n');
fprintf('   B) VHDL HARDWARE vs MATLAB REFERENCE (pan_tompkins_causal)\n');
fprintf('=====================================================================\n');
fprintf('Record | MATLAB| VHDL  | TP    | FP   | FN   | Se(%%)  | +P(%%)  | F1(%%)  | lag\n');
fprintf('-------|-------|-------|-------|------|------|--------|--------|--------|-----\n');

TB = 0; FB = 0; NB = 0;
for k = 1:length(records)
    r = res(k);
    fprintf('  %s  | %5d | %5d | %5d | %4d | %4d | %6.2f | %6.2f | %6.2f | %3d\n', ...
        r.record, r.n_ml, r.n_vhdl, r.TPb, r.FPb, r.FNb, ...
        r.se_b, r.pp_b, r.f1_b, r.lag);
    TB = TB + r.TPb; FB = FB + r.FPb; NB = NB + r.FNb;
end

se_B = TB / (TB + NB) * 100;
pp_B = TB / (TB + FB) * 100;
f1_B = harmonic(se_B, pp_B);

fprintf('-------|-------|-------|-------|------|------|--------|--------|--------|-----\n');
fprintf(' TOTAL |       |       | %5d | %4d | %4d | %6.2f | %6.2f | %6.2f |\n', ...
        TB, FB, NB, se_B, pp_B, f1_B);
fprintf('=====================================================================\n\n');

fprintf('Median pipeline lag across records: %d samples (%.1f ms)\n', ...
        median([res.lag]), median([res.lag])/fs*1000);

%% 5. Save
save('vhdl_batch_results.mat', 'res', ...
     'se_A', 'pp_A', 'f1_A', 'TA', 'FA', 'NA', ...
     'se_B', 'pp_B', 'f1_B', 'TB', 'FB', 'NB', 'tolerance');

fprintf('\nResults saved to vhdl_batch_results.mat\n');
fprintf('compare_vhdl_batch completed successfully.\n');


%% ====================================================================
%  LOCAL FUNCTIONS
%  ====================================================================

function idx = load_indices(fname)
    if ~isfile(fname)
        error('File not found: %s', fname);
    end
    idx = readmatrix(fname, 'CommentStyle', '#');
    if isempty(idx)
        idx = [];
        return;
    end
    idx = idx(:, 1);
    idx = idx(~isnan(idx));
    idx = sort(idx(:));
end


function lag = estimate_lag(ref, det, tolerance)
% Median offset between each detection and its nearest reference event,
% over the pairs that fall inside the tolerance window.
    if isempty(ref) || isempty(det)
        lag = 0;
        return;
    end
    offsets = zeros(length(det), 1);
    valid   = false(length(det), 1);
    for d = 1:length(det)
        [dist, idx] = min(abs(ref - det(d)));
        if dist <= tolerance
            offsets(d) = det(d) - ref(idx);
            valid(d)   = true;
        end
    end
    if any(valid)
        lag = round(median(offsets(valid)));
    else
        lag = 0;
    end
end


function [TP, FP, FN] = match_peaks(ref_peaks, det_peaks, tolerance)
% Each reference event can be matched at most once.
    n_ref = length(ref_peaks);
    n_det = length(det_peaks);

    matched_ref = false(n_ref, 1);
    matched_det = false(n_det, 1);

    for d = 1:n_det
        distances = abs(ref_peaks - det_peaks(d));
        [min_dist, min_idx] = min(distances);
        if min_dist <= tolerance && ~matched_ref(min_idx)
            matched_ref(min_idx) = true;
            matched_det(d)       = true;
        end
    end

    TP = sum(matched_det);
    FP = n_det - TP;
    FN = n_ref - sum(matched_ref);
end


function h = harmonic(a, b)
    if (a + b) > 0
        h = 2 * a * b / (a + b);
    else
        h = 0;
    end
end
