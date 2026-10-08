%% QRS PEAK LOCATION FIGURES - RECORDS 100 AND 208
% Project: Cardiac arrhythmia detection system - FPGA DE1-SoC
% Universidad Tecnologica del Peru (UTP)
%
% Generates the R-peak localization figures for the manuscript.
% For each record it overlays three marker sets on the ECG trace:
%   - cardiologist annotation from the .atr file
%   - MATLAB reference detection (pan_tompkins_causal), the same source
%     used to build the comparison table in compare_vhdl_batch.m
%   - RTL detection read back from the ModelSim batch run
%
% The cycle-accurate emulator (emulate_rtl.m) is a separate check and is
% not plotted here.
%
% No latency correction is applied. Sample indices are plotted as produced.
%
% Signal is shown in 12-bit ADC counts, using the same full-scale mapping
% as generate_vhdl_vectors_batch.m (5% headroom at each end), so the axis
% matches what the hardware actually receives.
%
% Light theme is forced explicitly: recent MATLAB releases default the axes
% to a dark theme regardless of the figure Color property.
%
% Requires in <batch_dir>:  ann_<rec>.txt, matlab_qrs_<rec>.txt,
%                           vhdl_qrs_<rec>.txt
%
% Outputs: fig2_rpeaks_record100.png, fig3_rpeaks_record208.png

clc; clear; close all;

batch_dir = 'D:/proyectos/ecg_arrhythmia/batch/';

records  = {'100', '208'};
outnames = {'fig2_rpeaks_record100.png', 'fig3_rpeaks_record208.png'};

t_start  = 0;      % window start in seconds
t_window = 10;     % window length in seconds

%% COLORS - edit here to restyle every figure
C.signal = [0.20 0.20 0.20];   % ECG trace, dark grey
C.ann    = [0.10 0.10 0.10];   % cardiologist annotation, near black
C.model  = [0.00 0.35 0.70];   % MATLAB reference, blue
C.rtl    = [0.80 0.10 0.10];   % RTL detection, red
C.grid   = [0.75 0.75 0.75];   % grid lines, light grey
C.axis   = [0.15 0.15 0.15];   % axis lines and tick labels

fprintf('=== R-PEAK LOCALIZATION FIGURES ===\n\n');

for k = 1:numel(records)

    rec = records{k};
    fprintf('Record %s\n', rec);

    %% Signal, mapped to 12-bit ADC counts
    [signal, fs, ~, ~, n_samples] = read_mitbih(rec);
    ecg = signal(:, 1);

    % Fixed calibration constant, format 212 full scale.
    % 11-bit code, gain 200 ADU/mV, zero at 1024:
    %   ADC 0    -> -5.120 mV
    %   ADC 2047 -> +5.115 mV
    % Same mapping used by generate_vhdl_vectors_batch.m, so the trace
    % shown here is the one the RTL actually processed.
    CAL_MIN = (0    - 1024) / 200;
    CAL_MAX = (2047 - 1024) / 200;

    target_min = round(0.05 * 4095);
    target_max = round(0.95 * 4095);

    ecg_u = round((ecg - CAL_MIN) / (CAL_MAX - CAL_MIN) * ...
                  (target_max - target_min) + target_min);
    ecg_u = max(min(ecg_u, 4095), 0);

    %% Reference and detection files
    ann = load_indices(fullfile(batch_dir, ['ann_'        rec '.txt']));
    ml  = load_indices(fullfile(batch_dir, ['matlab_qrs_' rec '.txt']));
    vh  = load_indices(fullfile(batch_dir, ['vhdl_qrs_'   rec '.txt']));

    %% Window
    i0 = max(1, round(t_start * fs) + 1);
    i1 = min(n_samples, i0 + round(t_window * fs) - 1);

    idx = (i0:i1)';
    t   = (idx - 1) / fs;
    y   = double(ecg_u(idx));

    ann_w = ann(ann >= i0 & ann <= i1);
    ml_w  = ml (ml  >= i0 & ml  <= i1);
    vh_w  = vh (vh  >= i0 & vh  <= i1);

    fprintf('  window %.0f-%.0f s : %d annotations, %d MATLAB, %d RTL\n', ...
            t_start, t_start + t_window, ...
            numel(ann_w), numel(ml_w), numel(vh_w));

    %% Marker heights, placed above the trace
    y_lo = min(y);
    y_hi = max(y);
    span = y_hi - y_lo;

    h_ann = y_hi + 0.16 * span;
    h_det = y_hi + 0.07 * span;

    %% Figure
    fig = figure('Name', ['R peaks ' rec], ...
                 'Position', [80 80 900 400], 'Color', 'w');

    try
        fig.Theme = 'light';   % available from R2025a onwards
    catch
    end

    ax = axes('Parent', fig);
    hold(ax, 'on');

    hs = plot(ax, t, y, '-', 'Color', C.signal, 'LineWidth', 0.6);

    ha = plot(ax, (ann_w - 1) / fs, h_ann * ones(size(ann_w)), 'v', ...
              'MarkerSize', 6, 'MarkerEdgeColor', C.ann, ...
              'MarkerFaceColor', C.ann, 'LineStyle', 'none');

    hm = plot(ax, (ml_w - 1) / fs, h_det * ones(size(ml_w)), 'o', ...
              'MarkerSize', 9, 'MarkerEdgeColor', C.model, ...
              'MarkerFaceColor', 'none', 'LineWidth', 1.2, ...
              'LineStyle', 'none');

    hr = plot(ax, (vh_w - 1) / fs, h_det * ones(size(vh_w)), 'x', ...
              'MarkerSize', 7, 'MarkerEdgeColor', C.rtl, ...
              'LineWidth', 1.4, 'LineStyle', 'none');

    hold(ax, 'off');

    xlim(ax, [t(1) t(end)]);
    ylim(ax, [y_lo - 0.06 * span, y_hi + 0.26 * span]);

    xlabel(ax, 'Tiempo (s)', 'FontSize', 16, 'Color', C.axis);
    ylabel(ax, 'Amplitud (cuentas ADC de 12 bits)', ...
           'FontSize', 16, 'Color', C.axis);

    lg = legend(ax, [hs ha hm hr], ...
                {'Señal de entrada', 'Anotación de cardiólogo', ...
                 'Referencia MATLAB', 'Detección RTL'}, ...
                'Orientation', 'horizontal', 'NumColumns', 4, ...
                'FontSize', 14, 'Box', 'off', ...
                'Location', 'northoutside');
    lg.TextColor = C.axis;

    grid(ax, 'on');
    box(ax, 'on');

    set(ax, 'Color', 'w', ...
            'XColor', C.axis, 'YColor', C.axis, ...
            'GridColor', C.grid, 'GridAlpha', 0.9, ...
            'MinorGridColor', C.grid, ...
            'LineWidth', 0.7, 'FontSize', 14, ...
            'Layer', 'bottom');

    exportgraphics(fig, outnames{k}, ...
                   'Resolution', 300, 'BackgroundColor', 'white');
    fprintf('  saved: %s\n\n', outnames{k});

end

%% Localization agreement over the full record
fprintf('=== INDEX AGREEMENT, FULL RECORD ===\n');
for k = 1:numel(records)
    rec = records{k};
    ml  = load_indices(fullfile(batch_dir, ['matlab_qrs_' rec '.txt']));
    vh  = load_indices(fullfile(batch_dir, ['vhdl_qrs_'   rec '.txt']));

    if numel(ml) == numel(vh)
        d = vh - ml;
        fprintf('  %s : %d MATLAB, %d RTL, max |diff| = %d samples\n', ...
                rec, numel(ml), numel(vh), max(abs(d)));
    else
        fprintf('  %s : %d MATLAB, %d RTL, counts differ\n', ...
                rec, numel(ml), numel(vh));
    end
end

fprintf('\nplot_qrs_figures completed successfully.\n');


%% ====================================================================
%  LOCAL FUNCTIONS
%  ====================================================================

function idx = load_indices(fname)
    if ~isfile(fname)
        error('File not found: %s', fname);
    end
    idx = readmatrix(fname, 'CommentStyle', '#');
    idx = idx(:);
    idx = idx(~isnan(idx));
end
