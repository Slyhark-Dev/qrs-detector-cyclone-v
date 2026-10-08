%% DETECTOR PERFORMANCE BY EVALUATION PROTOCOL
% Project: Cardiac arrhythmia detection system - FPGA DE1-SoC
% Universidad Tecnologica del Peru (UTP)
%
% Aggregates the per-record counts produced by compare_vhdl_batch.m into
% the four rows of Table III: DS1, DS2, DS1+DS2 and the full database.
%
% Reads vhdl_batch_results.mat, so it does not re-run any simulation and
% cannot alter the underlying figures.
%
% The reported figure is the DS2 row: the parameters were selected on DS1
% and DS2 was evaluated once with a single preselected configuration.

clc; clear;

if ~isfile('vhdl_batch_results.mat')
    error('Missing vhdl_batch_results.mat. Run compare_vhdl_batch.m first.');
end

S = load('vhdl_batch_results.mat');

% Per-record results. Block A is the comparison against the cardiologist
% annotations, which is the one Table III reports. Block B compares against
% the MATLAB reference model and is not used here.
if ~isfield(S, 'res')
    error('vhdl_batch_results.mat does not contain the res structure.');
end
res = S.res;

ds1 = {'101','106','108','109','112','114','115','116','118','119', ...
       '122','124','201','203','205','207','208','209','215','220', ...
       '223','230'};

ds2 = {'100','103','105','111','113','117','121','123','200','202', ...
       '210','212','213','214','219','221','222','228','231','232', ...
       '233','234'};

paced = {'102','104','107','217'};

recs = {res.record};
TP   = [res.TPa];
FP   = [res.FPa];
FN   = [res.FNa];

fprintf('=== DETECTOR PERFORMANCE BY PROTOCOL ===\n\n');
fprintf('Records found: %d\n', numel(recs));
fprintf('Total TP %d  FP %d  FN %d\n\n', sum(TP), sum(FP), sum(FN));

%% Table III rows

idx_ds1 = ismember(recs, ds1);
idx_ds2 = ismember(recs, ds2);
idx_44  = idx_ds1 | idx_ds2;
idx_all = true(1, numel(recs));

sets  = {idx_ds1, idx_ds2, idx_44, idx_all};
names = {'DS1, parameter tuning', 'DS2, evaluation', ...
         'DS1 + DS2', 'Full database'};
nrec  = [sum(idx_ds1) sum(idx_ds2) sum(idx_44) sum(idx_all)];

fprintf('=====================================================================\n');
fprintf('   TABLE III\n');
fprintf('=====================================================================\n\n');
fprintf('%-24s | %4s | %6s | %6s | %6s | %6s | %5s | %5s\n', ...
        'Protocol', 'Rec', 'Se(%)', '+P(%)', 'F1(%)', 'TP', 'FP', 'FN');
fprintf('-------------------------|------|--------|--------|--------|--------|-------|------\n');

ROWS = zeros(4,3);

for s = 1:4
    m  = sets{s};
    tp = sum(TP(m));  fp = sum(FP(m));  fn = sum(FN(m));

    se = tp/(tp+fn)*100;
    pp = tp/(tp+fp)*100;
    f1 = 2*se*pp/(se+pp);

    ROWS(s,:) = [se pp f1];

    fprintf('%-24s | %4d | %6.2f | %6.2f | %6.2f | %6d | %5d | %4d\n', ...
            names{s}, nrec(s), se, pp, f1, tp, fp, fn);
end

%% Comparison against the previously reported configuration

fprintf('\n=====================================================================\n');
fprintf('   COMPARISON WITH THE PREVIOUS CONFIGURATION\n');
fprintf('=====================================================================\n\n');
fprintf('%-24s | %6s | %6s | %6s\n', 'Configuration', 'Se(%)', '+P(%)', 'F1(%)');
fprintf('-------------------------|--------|--------|-------\n');
fprintf('%-24s | %6.2f | %6.2f | %6.2f\n', ...
        'DS2, per-record scaling', 99.65, 96.53, 98.07);
fprintf('%-24s | %6.2f | %6.2f | %6.2f\n', ...
        'DS2, fixed calibration', ROWS(2,1), ROWS(2,2), ROWS(2,3));

d_se = ROWS(2,1) - 99.65;
d_pp = ROWS(2,2) - 96.53;
d_f1 = ROWS(2,3) - 98.07;

fprintf('%-24s | %+6.2f | %+6.2f | %+6.2f\n\n', 'Difference', d_se, d_pp, d_f1);

%% Cross-check against the emulator prediction

fprintf('=====================================================================\n');
fprintf('   CROSS-CHECK: RTL AGAINST THE EMULATOR PREDICTION\n');
fprintf('=====================================================================\n\n');
fprintf('The emulator predicted, before compiling THR_MIN = 1500:\n');
fprintf('  DS1: 99.23 / 99.20 / 99.22\n');
fprintf('  DS2: 99.56 / 99.30 / 99.43\n');
fprintf('  Full: 99.44 / 97.76 / 98.59\n\n');
fprintf('The RTL batch simulation gives:\n');
fprintf('  DS1: %.2f / %.2f / %.2f\n', ROWS(1,1), ROWS(1,2), ROWS(1,3));
fprintf('  DS2: %.2f / %.2f / %.2f\n', ROWS(2,1), ROWS(2,2), ROWS(2,3));
fprintf('  Full: %.2f / %.2f / %.2f\n\n', ROWS(4,1), ROWS(4,2), ROWS(4,3));

if abs(ROWS(2,3) - 99.43) < 0.02
    fprintf('The RTL reproduces the emulator prediction on DS2. The\n');
    fprintf('emulator remains a valid substitute for parameter exploration.\n');
else
    fprintf('The RTL and the emulator differ on DS2 by %.2f points of F1.\n', ...
            abs(ROWS(2,3) - 99.43));
    fprintf('Investigate before reporting either figure.\n');
end

%% Cost of the paced records

tp44 = sum(TP(idx_44)); fp44 = sum(FP(idx_44)); fn44 = sum(FN(idx_44));
se44 = tp44/(tp44+fn44)*100; pp44 = tp44/(tp44+fp44)*100;
f144 = 2*se44*pp44/(se44+pp44);

fprintf('\n=====================================================================\n');
fprintf('   COST OF THE FOUR PACED RECORDS\n');
fprintf('=====================================================================\n\n');
fprintf('DS1 + DS2, 44 records : F1 %.2f\n', f144);
fprintf('Full database, 48     : F1 %.2f\n', ROWS(4,3));
fprintf('Difference            : %.2f points of F1\n\n', f144 - ROWS(4,3));

idx_paced = ismember(recs, paced);
fprintf('Per paced record:\n');
fprintf('%-6s | %6s | %5s | %5s | %6s | %6s\n', ...
        'Rec', 'TP', 'FP', 'FN', 'Se(%)', '+P(%)');
fprintf('-------|--------|-------|-------|--------|-------\n');
for k = find(idx_paced)
    se = TP(k)/(TP(k)+FN(k))*100;
    pp = TP(k)/(TP(k)+FP(k))*100;
    fprintf('%-6s | %6d | %5d | %5d | %6.2f | %6.2f\n', ...
            recs{k}, TP(k), FP(k), FN(k), se, pp);
end

%% Per-record distributions, requested by the reviewer

se_all = TP ./ (TP + FN) * 100;
pp_all = TP ./ (TP + FP) * 100;
f1_all = 2 .* se_all .* pp_all ./ (se_all + pp_all);

fprintf('\n=====================================================================\n');
fprintf('   PER-RECORD DISTRIBUTIONS\n');
fprintf('=====================================================================\n\n');
fprintf('%-14s | %8s | %8s | %8s | %8s | %8s\n', ...
        'Subset', 'median', 'IQR', 'p25', 'p75', 'min');
fprintf('---------------|----------|----------|----------|----------|--------\n');

for s = [2 4]
    m = sets{s};
    for metric = 1:3
        switch metric
            case 1, v = se_all(m); lab = 'Se';
            case 2, v = pp_all(m); lab = '+P';
            case 3, v = f1_all(m); lab = 'F1';
        end
        q = prctile(v, [25 75]);
        fprintf('%-14s | %8.2f | %8.2f | %8.2f | %8.2f | %8.2f\n', ...
                sprintf('%s, %s', lab, names{s}(1:3)), ...
                median(v), q(2)-q(1), q(1), q(2), min(v));
    end
end

fprintf('\nWorst three records by F1 over the full database:\n');
[~, ord] = sort(f1_all, 'ascend');
for j = 1:3
    k = ord(j);
    fprintf('  %s: Se %.2f  +P %.2f  F1 %.2f\n', ...
            recs{k}, se_all(k), pp_all(k), f1_all(k));
end

%% Save

save('table3_fixed_cal.mat', 'ROWS', 'names', 'nrec', ...
     'se_all', 'pp_all', 'f1_all', 'recs', 'TP', 'FP', 'FN');

fprintf('\nSaved to table3_fixed_cal.mat\n');
fprintf('report_table3 completed successfully.\n');
