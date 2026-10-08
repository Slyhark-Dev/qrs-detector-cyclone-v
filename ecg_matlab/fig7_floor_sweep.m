%% FIGURE: THRESHOLD FLOOR SWEEP ON DS1
% Project: Cardiac arrhythmia detection system - FPGA DE1-SoC
% Universidad Tecnologica del Peru (UTP)
%
% Draws the DS1 sweep of the threshold floor under fixed calibration. Shows
% that the selected value sits at an interior optimum and that DS2 played no
% part in the choice.
%
% The grid is drawn on an evenly spaced categorical axis instead of a log
% axis, so the ten grid values get equal room and no tick label overlaps.
%
% The axes background is forced to white: recent MATLAB releases default the
% axes to a dark theme regardless of the figure Color property.
%
% Reads : floor_fixed_cal_results.mat  (floor_grid, SE, PP, F1, SEL)
% Writes: fig7_floor_sweep.png
% Recomputes nothing. No Quartus, no ModelSim.

clc; clear;

S  = load('floor_fixed_cal_results.mat');
g  = S.floor_grid(:);
se = S.SE(:); pp = S.PP(:); f1 = S.F1(:);
sel = S.SEL;

[g, k] = sort(g); se = se(k); pp = pp(k); f1 = f1(k);
i_sel = find(g == sel, 1);
x = (1:numel(g))';

fig = figure('Color','w','Units','centimeters','Position',[2 2 8.8 7.8]);
ax  = axes(fig); hold(ax,'on');

plot(ax, x, se, '-s', 'LineWidth',1.0, 'MarkerSize',4, 'Color',[0.55 0.55 0.55]);
plot(ax, x, pp, '-^', 'LineWidth',1.0, 'MarkerSize',4, 'Color',[0.45 0.65 0.45]);
plot(ax, x, f1, '-o', 'LineWidth',1.8, 'MarkerSize',5, 'Color',[0.20 0.45 0.70], ...
     'MarkerFaceColor',[0.20 0.45 0.70]);

plot(ax, x(i_sel), f1(i_sel), 'o', 'MarkerSize',11, 'LineWidth',1.6, ...
     'Color',[0.75 0.30 0.25]);
text(ax, x(i_sel), f1(i_sel)-1.5, sprintf('%d', sel), ...
     'HorizontalAlignment','center', 'FontSize',11, 'Color',[0.75 0.30 0.25]);

set(ax,'FontSize',10,'Box','off','XColor','k','YColor','k','TickDir','out');
set(ax,'Color','w');   % tema claro explicito: MATLAB reciente pinta los ejes en oscuro
set(ax,'XTick', x, 'XTickLabel', compose('%d', g), 'XTickLabelRotation', 45);
grid(ax,'on'); set(ax,'GridColor',[0.8 0.8 0.8],'GridAlpha',0.6);
xlim(ax,[0.5 numel(g)+0.5]);

xlabel(ax, 'Piso del umbral (THR\_MIN)', 'FontSize',13, 'Color','k');
ylabel(ax, ['M' char(233) 'trica sobre DS1 (%)'], 'FontSize',13, 'Color','k');
legend(ax, {'Sensibilidad', 'Predictividad positiva', 'F1'}, ...
       'Location','southwest','FontSize',10,'Box','off','TextColor','k');

fprintf('Optimo sobre DS1: THR_MIN = %d, F1 = %.2f%%\n', sel, f1(i_sel));
if i_sel > 1 && i_sel < numel(g)
    fprintf('Vecinos: %d -> %.2f%%   %d -> %.2f%%\n', ...
            g(i_sel-1), f1(i_sel-1), g(i_sel+1), f1(i_sel+1));
    fprintf('El optimo es interior: la rejilla lo acota por ambos lados.\n');
end

exportgraphics(fig, 'fig7_floor_sweep.png', 'Resolution', 300, ...
               'BackgroundColor','white');
fprintf('Figura guardada: fig7_floor_sweep.png\n');
