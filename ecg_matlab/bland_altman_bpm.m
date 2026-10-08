%% BLAND-ALTMAN ANALYSIS OF HEART RATE
% Project: Cardiac arrhythmia detection system - FPGA DE1-SoC
% Universidad Tecnologica del Peru (UTP)
%
% Compara la frecuencia cardiaca instantanea calculada por el hardware
% contra la derivada de los intervalos RR anotados por cardiologos,
% mediante el metodo de Bland y Altman.
%
% Para cada latido emparejado se calculan:
%   media      = (BPM_hardware + BPM_referencia) / 2
%   diferencia =  BPM_hardware - BPM_referencia
%
% El sesgo es la media de las diferencias y los limites de concordancia
% se situan a 1.96 desviaciones estandar de ese sesgo.
%
% Se reportan dos escenarios:
%   (a) todos los latidos emparejados
%   (b) latidos con cadencia consistente, es decir, aquellos en los que
%       el latido previo tambien fue detectado por el hardware dentro de
%       la tolerancia. En los demas el intervalo RR del hardware abarca
%       dos ciclos cardiacos o una fraccion de uno, de modo que la
%       diferencia refleja un evento de deteccion y no la precision del
%       calculo de frecuencia, ya evaluada por separado.
%
% Evaluacion sobre 44 registros, excluyendo los registros con
% marcapasos conforme a ANSI/AAMI EC57.
%
% Genera: fig5_bland_altman.png

clc; clear; close all;

batch_dir = 'D:/proyectos/ecg_arrhythmia/batch/';

records = {'100','101','102','103','104','105','106','107','108','109', ...
           '111','112','113','114','115','116','117','118','119', ...
           '121','122','123','124', ...
           '200','201','202','203','205','207','208','209','210', ...
           '212','213','214','215','217','219', ...
           '220','221','222','223','228', ...
           '230','231','232','233','234'};

paced = {'102','104','107','217'};

fs        = 360;
tolerance = 54;

fprintf('=== ANALISIS BLAND-ALTMAN DE FRECUENCIA CARDIACA ===\n\n');

bpm_hw    = [];
bpm_ref   = [];
consistent = [];

for k = 1:numel(records)
    rec = records{k};
    if ismember(rec, paced)
        continue;
    end

    beats_file = [batch_dir 'vhdl_beats_' rec '.txt'];
    if ~isfile(beats_file)
        continue;
    end

    V   = read_beats_file(beats_file);
    ann = readmatrix([batch_dir 'ann_' rec '.txt']);
    ann = ann(:);

    if isempty(V) || numel(ann) < 3
        continue;
    end

    prev_idx = -1;   % indice de anotacion emparejado en el latido previo

    for i = 1:size(V,1)
        s_vhdl = V(i,1);
        b_hw   = V(i,2);

        [dd, ix] = min(abs(ann - s_vhdl));
        if dd > tolerance || ix < 2
            prev_idx = -1;
            continue;
        end

        rr = ann(ix) - ann(ix-1);
        if rr <= 0
            prev_idx = ix;
            continue;
        end
        b_ref = 21600 / rr;

        % descartar valores fuera del rango fisiologico razonable
        if b_hw < 20 || b_hw > 250 || b_ref < 20 || b_ref > 250
            prev_idx = ix;
            continue;
        end

        % cadencia consistente: el latido previo del hardware se emparejo
        % con la anotacion inmediatamente anterior
        cons = (prev_idx == ix - 1);

        bpm_hw(end+1,1)     = b_hw;  %#ok<SAGROW>
        bpm_ref(end+1,1)    = b_ref; %#ok<SAGROW>
        consistent(end+1,1) = cons;  %#ok<SAGROW>

        prev_idx = ix;
    end
end

consistent = logical(consistent);

fprintf('Latidos emparejados totales      : %d\n',   numel(bpm_hw));
fprintf('Latidos de cadencia consistente  : %d (%.2f%%)\n\n', ...
        sum(consistent), sum(consistent)/numel(bpm_hw)*100);

%% Escenario (a): todos los latidos emparejados
[s_a, sd_a, ls_a, li_a, med_a, p5_a] = ba_stats(bpm_hw, bpm_ref);

fprintf('--- (a) TODOS LOS LATIDOS EMPAREJADOS ---\n');
print_stats(s_a, sd_a, ls_a, li_a, med_a, p5_a, numel(bpm_hw));

%% Escenario (b): cadencia consistente
hw_c  = bpm_hw(consistent);
ref_c = bpm_ref(consistent);
[s_b, sd_b, ls_b, li_b, med_b, p5_b] = ba_stats(hw_c, ref_c);

fprintf('--- (b) CADENCIA CONSISTENTE ---\n');
print_stats(s_b, sd_b, ls_b, li_b, med_b, p5_b, numel(hw_c));

%% Figura, escenario (b)
media = (hw_c + ref_c) / 2;
dif   =  hw_c - ref_c;

figure('Name','Bland-Altman BPM','Position',[80 80 780 520]);
set(gcf,'Color','w','InvertHardcopy','off');

scatter(media, dif, 5, [0.25 0.45 0.75], 'filled', ...
        'MarkerFaceAlpha', 0.10, 'MarkerEdgeColor','none');
hold on;

xl = [min(media)-5, max(media)+5];
plot(xl, [s_b  s_b ], '-',  'Color',[0.85 0.15 0.15], 'LineWidth', 1.8);
plot(xl, [ls_b ls_b], '--', 'Color',[0.10 0.45 0.10], 'LineWidth', 1.4);
plot(xl, [li_b li_b], '--', 'Color',[0.10 0.45 0.10], 'LineWidth', 1.4);

text(xl(2), s_b,  sprintf('sesgo = %+.2f  ', s_b), 'Color','k', ...
     'VerticalAlignment','bottom','HorizontalAlignment','right','FontSize',14);
text(xl(2), ls_b, sprintf('+1.96 SD = %+.2f  ', ls_b), 'Color','k', ...
     'VerticalAlignment','bottom','HorizontalAlignment','right','FontSize',14);
text(xl(2), li_b, sprintf('-1.96 SD = %+.2f  ', li_b), 'Color','k', ...
     'VerticalAlignment','top','HorizontalAlignment','right','FontSize',14);

hold off;
xlim(xl);
ylim([min(li_b*3, -10), max(ls_b*3, 10)]);

xlabel(['Media de ambos m' char(233) 'todos (BPM)'],'FontSize',16,'Color','k');
ylabel('Hardware - Referencia (BPM)','FontSize',16,'Color','k');
n_str = regexprep(sprintf('%d', numel(hw_c)), '\d{1,3}(?=(\d{3})+$)', '$0,');
title(sprintf(['Concordancia de frecuencia card' char(237) 'aca, %s latidos, 44 registros'], ...
      n_str), 'FontSize',16,'FontWeight','normal','Color','k');

grid on;
box on;
set(gca,'Color','w','XColor','k','YColor','k', ...
        'GridColor',[0.80 0.80 0.80],'GridAlpha',0.6,'FontSize',14);

exportgraphics(gcf, 'fig5_bland_altman.png', 'Resolution', 300, ...
               'BackgroundColor','white');
fprintf('Figura guardada: fig5_bland_altman.png\n');

save('bland_altman_results.mat', ...
     's_a','sd_a','ls_a','li_a','med_a','p5_a', ...
     's_b','sd_b','ls_b','li_b','med_b','p5_b', ...
     'bpm_hw','bpm_ref','consistent');

fprintf('bland_altman_bpm completed successfully.\n');


%% ====================================================================
%  LOCAL FUNCTIONS
%  ====================================================================

function [sesgo, sd, loa_s, loa_i, med_abs, pct5] = ba_stats(hw, ref)
    dif   = hw - ref;
    sesgo = mean(dif);
    sd    = std(dif);
    loa_s = sesgo + 1.96 * sd;
    loa_i = sesgo - 1.96 * sd;
    med_abs = median(abs(dif));
    pct5    = sum(abs(dif) <= 5) / numel(dif) * 100;
end


function print_stats(sesgo, sd, loa_s, loa_i, med_abs, pct5, n)
    fprintf('Latidos                      : %d\n', n);
    fprintf('Sesgo medio                  : %+7.3f BPM\n', sesgo);
    fprintf('Desviacion estandar          : %7.3f BPM\n', sd);
    fprintf('Limite superior de concord.  : %+7.3f BPM\n', loa_s);
    fprintf('Limite inferior de concord.  : %+7.3f BPM\n', loa_i);
    fprintf('Diferencia absoluta mediana  : %7.3f BPM\n', med_abs);
    fprintf('Latidos dentro de +-5 BPM    : %6.2f%%\n\n', pct5);
end


function V = read_beats_file(fname)
    fid = fopen(fname, 'r');
    C = textscan(fid, '%f %f %f %s %s', 'CommentStyle', '#');
    fclose(fid);

    n = numel(C{1});
    V = zeros(n, 5);
    V(:,1) = C{1};
    V(:,2) = C{2};
    V(:,3) = C{3};
    for i = 1:n
        V(i,4) = bin2dec(C{4}{i});
        V(i,5) = bin2dec(C{5}{i});
    end
end
