%% GENERATE VHDL TEST VECTORS - FULL DATABASE BATCH, FIXED CALIBRATION
% Project: Cardiac arrhythmia detection system - FPGA DE1-SoC
% Universidad Tecnologica del Peru (UTP)
%
% Exports the complete MIT-BIH Arrhythmia Database (48 records, 30 min each,
% channel 1) as ModelSim-readable test vectors, plus two reference files
% per record:
%   ann_<rec>.txt        - cardiologist beat annotations (sample index)
%   matlab_qrs_<rec>.txt - pan_tompkins_causal detections (sample index)
%
% DIFFERENCE FROM THE PREVIOUS VERSION
%
% The previous version mapped each record to the 12-bit range using its own
% minimum and maximum over the complete 30-minute recording. Those extremes
% are not available during real-time acquisition, which is inconsistent with
% a detector presented as causal.
%
% This version uses a single calibration constant shared by all 48 records,
% derived from the format 212 full scale and not from the data:
%
%   11-bit two's complement, gain 200 ADU/mV, zero at 1024
%   ADC 0    -> (0    - 1024)/200 = -5.120 mV
%   ADC 2047 -> (2047 - 1024)/200 = +5.115 mV
%
% The mapping is therefore fixed at design time, as an ADC input range would
% be. No sample can fall outside it by construction.
%
% Everything else, including the output format, is unchanged.
%
% Output: <output_dir>

clc; clear; close all;

%% 1. Configuration
records = {'100','101','102','103','104','105','106','107','108','109', ...
           '111','112','113','114','115','116','117','118','119', ...
           '121','122','123','124', ...
           '200','201','202','203','205','207','208','209','210', ...
           '212','213','214','215','217','219', ...
           '220','221','222','223','228', ...
           '230','231','232','233','234'};

output_dir = 'D:/PROYECTOS/ecg_arrhythmia/batch/';

if ~exist(output_dir, 'dir')
    mkdir(output_dir);
end

% --- fixed calibration constant, format 212 full scale
ADC_ZERO  = 1024;      % zero offset of the 11-bit code
ADC_GAIN  = 200;       % ADU per mV
CAL_MIN   = (0    - ADC_ZERO) / ADC_GAIN;   % -5.120 mV
CAL_MAX   = (2047 - ADC_ZERO) / ADC_GAIN;   % +5.115 mV

margin     = 0.05;
target_min = round(4095 * margin);
target_max = round(4095 * (1 - margin));

fprintf('=== BATCH TEST VECTOR GENERATION, FIXED CALIBRATION ===\n');
fprintf('Records: %d\n', length(records));
fprintf('Output: %s\n', output_dir);
fprintf('Calibration range: [%.3f %.3f] mV, format 212 full scale\n', ...
        CAL_MIN, CAL_MAX);
fprintf('Target 12-bit range: [%d %d]\n\n', target_min, target_max);

manifest = struct();
n_clipped_total = 0;

%% 2. Process each record
for k = 1:length(records)
    record = records{k};
    t_start = tic;

    [signal, fs, ~, ~, n_samples] = read_mitbih(record);
    ecg = signal(:, 1);

    % --- 12-bit unsigned scaling with the shared calibration constant
    ecg_u = round((ecg - CAL_MIN) / (CAL_MAX - CAL_MIN) * ...
                  (target_max - target_min) + target_min);

    n_clipped = sum(ecg_u < 0 | ecg_u > 4095);
    n_clipped_total = n_clipped_total + n_clipped;

    ecg_u = max(min(ecg_u, 4095), 0);

    % --- ECG vectors: one 12-bit binary string per line
    vec_file = fullfile(output_dir, ['vectors_' record '.txt']);
    bin_matrix = dec2bin(ecg_u, 12);
    fid = fopen(vec_file, 'w');
    if fid == -1
        error('Cannot write to: %s', vec_file);
    end
    fprintf(fid, '%s\n', string(bin_matrix));
    fclose(fid);

    % --- MATLAB reference detections
    % Operates on the signal in mV, unaffected by the scaling change.
    r_peaks = pan_tompkins_causal(ecg, fs, n_samples);
    r_peaks = r_peaks(:);
    ref_file = fullfile(output_dir, ['matlab_qrs_' record '.txt']);
    fid = fopen(ref_file, 'w');
    fprintf(fid, '%d\n', r_peaks);
    fclose(fid);

    % --- Cardiologist annotations
    ann_peaks = read_annotations(record, n_samples);
    ann_peaks = ann_peaks(:);
    ann_file = fullfile(output_dir, ['ann_' record '.txt']);
    fid = fopen(ann_file, 'w');
    fprintf(fid, '%d\n', ann_peaks);
    fclose(fid);

    span = max(ecg_u) - min(ecg_u);

    manifest(k).record    = record;
    manifest(k).n_samples = n_samples;
    manifest(k).fs        = fs;
    manifest(k).n_ann     = length(ann_peaks);
    manifest(k).n_matlab  = length(r_peaks);
    manifest(k).ecg_min   = min(ecg_u);
    manifest(k).ecg_max   = max(ecg_u);
    manifest(k).span      = span;
    manifest(k).n_clipped = n_clipped;

    fprintf('%s: %d ann, %d MATLAB peaks, range [%4d %4d], span %4d (%4.1f%%), clip %d, %.1f s\n', ...
            record, length(ann_peaks), length(r_peaks), ...
            min(ecg_u), max(ecg_u), span, ...
            span/(target_max-target_min)*100, n_clipped, toc(t_start));
end

%% 3. Occupancy summary

spans = [manifest.span];

fprintf('\n=====================================================================\n');
fprintf('   RANGE OCCUPANCY UNDER FIXED CALIBRATION\n');
fprintf('=====================================================================\n\n');
fprintf('Useful range: %d counts\n', target_max - target_min);
fprintf('Median span : %.0f counts (%.1f%%)\n', ...
        median(spans), median(spans)/(target_max-target_min)*100);
fprintf('Minimum span: %d counts, record %s\n', ...
        min(spans), records{find(spans == min(spans), 1)});
fprintf('Maximum span: %d counts, record %s\n', ...
        max(spans), records{find(spans == max(spans), 1)});
fprintf('Total clipped samples: %d of %d\n\n', ...
        n_clipped_total, sum([manifest.n_samples]));

if n_clipped_total == 0
    fprintf('No sample falls outside the calibration range, as expected from\n');
    fprintf('a constant derived from the format rather than from the data.\n');
else
    fprintf('ATENCION: %d muestras recortadas. Revisar antes de continuar,\n', ...
            n_clipped_total);
    fprintf('la constante deberia cubrir el formato por construccion.\n');
end

%% 4. Manifest for the ModelSim batch script
man_file = fullfile(output_dir, 'batch_manifest.txt');
fid = fopen(man_file, 'w');
fprintf(fid, '# record n_samples n_annotations n_matlab_peaks\n');
for k = 1:length(records)
    m = manifest(k);
    fprintf(fid, '%s %d %d %d\n', m.record, m.n_samples, m.n_ann, m.n_matlab);
end
fclose(fid);

save('batch_manifest.mat', 'manifest', 'CAL_MIN', 'CAL_MAX', ...
     'target_min', 'target_max');

fprintf('\nManifest: %s\n', man_file);
fprintf('generate_vhdl_vectors_batch completed successfully.\n');


%% ====================================================================
%  LOCAL FUNCTIONS
%  ====================================================================

function ann_samples = read_annotations(record, n_samples)
% READ_ANNOTATIONS - Read MIT-BIH annotation file (.atr)
% Returns sample indices of all beat annotations
%
% MIT-BIH annotation format (binary):
%   Each annotation = 2 bytes (16 bits)
%   Bits 15-10: annotation type code
%   Bits 9-0: time offset from previous annotation
%   Pseudo-annotation codes (WFDB):
%     59 = SKIP : interval stored in next 4 bytes, high word first
%     60 = NUM  : annotator number, time field carries data, not time
%     61 = SUB  : subtype, time field carries data, not time
%     62 = CHN  : channel, time field carries data, not time
%     63 = AUX  : time field carries auxiliary string length, not time
%      0 = EOF

    atr_file = [record '.atr'];
    fid = fopen(atr_file, 'r');
    if fid == -1
        error('Annotation file not found: %s', atr_file);
    end

    bytes = fread(fid, inf, 'uint8');
    fclose(fid);

    % Beat type codes (all types that represent a heartbeat)
    % 1=N, 2=L, 3=R, 4=A, 5=V, 6=F, 7=J, 8=a, 9=S, 10=E
    % 11=j, 12=/, 13=Q, 34=r, 38=f
    beat_types = [1 2 3 4 5 6 7 8 9 10 11 12 13 34 38];

    ann_samples = [];
    current_sample = 0;
    i = 1;

    while i <= length(bytes) - 1
        low_byte  = bytes(i);
        high_byte = bytes(i + 1);
        i = i + 2;

        ann_type   = bitshift(high_byte, -2);
        time_delta = bitor(low_byte, bitand(high_byte, 3) * 256);

        if ann_type == 0
            break;

        elseif ann_type == 59
            if i + 3 <= length(bytes)
                hi_word = bytes(i)   + bytes(i+1) * 256;
                lo_word = bytes(i+2) + bytes(i+3) * 256;
                current_sample = current_sample + hi_word * 65536 + lo_word;
                i = i + 4;
            else
                break;
            end

        elseif ann_type == 63
            aux_len = time_delta;
            if mod(aux_len, 2) ~= 0
                aux_len = aux_len + 1;
            end
            i = i + aux_len;

        elseif ann_type == 60 || ann_type == 61 || ann_type == 62
            continue;

        else
            current_sample = current_sample + time_delta;
            if ismember(ann_type, beat_types) && current_sample <= n_samples
                ann_samples = [ann_samples; current_sample]; %#ok<AGROW>
            end
        end
    end
end
