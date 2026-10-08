%% FIGURE: PER-RECORD EFFECT OF THE FILTER SUBSTITUTION
% Project: Cardiac arrhythmia detection system - FPGA DE1-SoC
% Universidad Tecnologica del Peru (UTP)
%
% Draws the per-record difference in F1 between the Pan-Tompkins bandpass
% cascade and the 8-sample moving average, under the two protocols of the
% second ablation:
%
%   bars   single absolute floor selected on DS1, the floor the compiled
%          architecture imposes, with the group delay of each path
%          compensated by its design-time constant
%   line   floor selected per record, an oracle bound that stands in for
%          the learning phase the 1985 algorithm has and this design does
%          not implement
%
% Records are ordered by the difference under the single floor, so the
% collapse and its recovery read left to right in one picture.
%
% The axes background is forced to white: recent MATLAB releases default
% the axes to a dark theme regardless of the figure Color property.
%
% Reads : bandpass_ablation_v2.mat  (records, F1_MA, F1_B, F1_C)
% Writes: fig6_bandpass_ablation.png
% Recomputes nothing. No Quartus, no ModelSim.

clc; clear;

S = load('bandpass_ablation_v2.mat');
recs = string(cellfun(@(c) string(c), S.records(:)));
dA = S.F1_B(:) - S.F1_MA(:);
dC = S.F1_C(:) - S.F1_MA(:);

[dA_ord, ord] = sort(dA, 'descend');
dC_ord = dC(ord);
r_ord  = recs(ord);
n      = numel(dA_ord);

pos = dA_ord >  0;
neg = dA_ord <= 0;

C_POS = [0.20 0.45 0.70];      % the cascade improves
C_NEG = [0.75 0.30 0.25];      % the moving average improves
C_ORA = [0.15 0.15 0.15];      % per-record floor

fig = figure('Color','w','Units','centimeters','Position',[2 2 17.8 9.5]);
ax  = axes(fig); hold(ax,'on');

b1 = bar(ax, find(pos), dA_ord(pos), 0.75, 'FaceColor', C_POS, 'EdgeColor','none');
b2 = bar(ax, find(neg), dA_ord(neg), 0.75, 'FaceColor', C_NEG, 'EdgeColor','none');
p1 = plot(ax, 1:n, dC_ord, '-o', 'Color', C_ORA, 'LineWidth', 1.0, ...
          'MarkerSize', 3, 'MarkerFaceColor', C_ORA);
yline(ax, 0, 'k-', 'LineWidth', 0.8);

xlim(ax, [0.3 n+0.7]);
set(ax, 'XTick', 1:n, 'XTickLabel', r_ord, ...
        'XTickLabelRotation', 90, 'FontSize', 8, 'Box','off', ...
        'XColor','k','YColor','k','TickDir','out');
set(ax, 'Color','w');
set(ax, 'Units','normalized', 'Position', [0.085 0.24 0.895 0.72]);
grid(ax,'on'); set(ax,'GridColor',[0.8 0.8 0.8],'GridAlpha',0.6);

xlabel(ax, 'Registro del MIT-BIH', 'FontSize', 13, 'Color','k');
ylabel(ax, 'Diferencia de F1 (puntos)', 'FontSize', 13, 'Color','k');

legend(ax, [b1 b2 p1], ...
     {['Piso ' char(250) 'nico: la cascada mejora'], ...
      ['Piso ' char(250) 'nico: el promedio m' char(243) 'vil mejora'], ...
      'Piso por registro'}, ...
     'Location','southwest', 'FontSize', 9, 'Box','off', 'TextColor','k');

fprintf('Piso unico     : cascada mejor en %d de %d, peor en %d\n', ...
        sum(dA > 0.01), n, sum(dA < -0.01));
fprintf('Piso/registro  : cascada mejor en %d de %d, peor en %d\n', ...
        sum(dC > 0.01), n, sum(dC < -0.01));
fprintf('Diferencia mediana absoluta: %.2f con piso unico, %.2f con piso por registro\n', ...
        median(abs(dA)), median(abs(dC)));

exportgraphics(fig, 'fig6_bandpass_ablation.png', 'Resolution', 300, ...
               'BackgroundColor','white');
fprintf('Figura guardada: fig6_bandpass_ablation.png\n');
