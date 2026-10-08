% =========================================================================
%  download_mitbih_records.m
%  Descarga los registros del MIT-BIH Arrhythmia Database desde PhysioNet
%
%  PROYECTO: Deteccion de arritmias cardiacas en FPGA DE1-SoC (UTP)
%  FASE 1: Linea base MATLAB - validacion de los 48 registros
%
%  COMPORTAMIENTO (idempotente):
%    - Revisa, para cada uno de los 48 registros, si existen sus 3 archivos
%      (.dat, .hea, .atr) en la carpeta de destino.
%    - Descarga SOLO los archivos que faltan o estan vacios.
%    - Se puede ejecutar varias veces sin riesgo: no duplica ni re-descarga
%      lo que ya esta bien. Si se corta la red, al re-ejecutar solo baja
%      lo que aun falta.
%
%  USO:
%    1. Copiar este archivo a D:/proyectos/ecg_matlab/
%    2. En MATLAB, situarse en esa carpeta.
%    3. Ejecutar:  download_mitbih_records
%
%  REQUISITO: conexion a internet con acceso a physionet.org
%    Si la red universitaria bloquea physionet.org, usar otra red
%    (casa, datos moviles) o descarga manual.
% =========================================================================

function download_mitbih_records()

    % ---------------------------------------------------------------------
    % CONFIGURACION
    % ---------------------------------------------------------------------
    % Carpeta de destino: por defecto, la carpeta actual de MATLAB.
    % Si se desea forzar una ruta fija, descomentar la linea siguiente:
    % dest_dir = 'D:/proyectos/ecg_matlab/';
    dest_dir = pwd;

    % URL base de PhysioNet para el MIT-BIH Arrhythmia Database v1.0.0
    base_url = 'https://physionet.org/files/mitdb/1.0.0/';

    % Extensiones que componen un registro completo
    extensions = {'.dat', '.hea', '.atr'};

    % Lista OFICIAL de los 48 registros del MIT-BIH Arrhythmia Database.
    % La numeracion NO es consecutiva (no van del 1 al 48).
    records = [ ...
        100 101 102 103 104 105 106 107 108 109 ...
        111 112 113 114 115 116 117 118 119 ...
        121 122 123 124 ...
        200 201 202 203 205 207 208 209 210 ...
        212 213 214 215 217 219 ...
        220 221 222 223 228 ...
        230 231 232 233 234 ];

    fprintf('========================================================\n');
    fprintf('  DESCARGA MIT-BIH Arrhythmia Database (48 registros)\n');
    fprintf('  Destino: %s\n', dest_dir);
    fprintf('  Modo: verificar y descargar solo lo que falte\n');
    fprintf('========================================================\n\n');

    % Timeout de descarga (segundos) por archivo
    opts = weboptions('Timeout', 60);

    total_descargados = 0;
    total_ya_existian = 0;
    total_fallidos    = 0;
    fallidos_lista    = {};

    % ---------------------------------------------------------------------
    % BUCLE PRINCIPAL: registro por registro, extension por extension
    % ---------------------------------------------------------------------
    for i = 1:numel(records)
        rec = records(i);
        rec_str = num2str(rec);

        fprintf('[%2d/%2d] Registro %s ... ', i, numel(records), rec_str);
        acciones = {};

        for k = 1:numel(extensions)
            ext = extensions{k};
            fname = [rec_str ext];
            local_path = fullfile(dest_dir, fname);

            % Verificar si el archivo ya existe y NO esta vacio
            existe_ok = false;
            if exist(local_path, 'file') == 2
                info = dir(local_path);
                if ~isempty(info) && info.bytes > 0
                    existe_ok = true;
                end
            end

            if existe_ok
                total_ya_existian = total_ya_existian + 1;
                continue;  % ya esta, no descargar
            end

            % Descargar el archivo faltante
            url = [base_url fname];
            try
                websave(local_path, url, opts);
                total_descargados = total_descargados + 1;
                acciones{end+1} = [ext ' OK']; %#ok<AGROW>
            catch ME
                total_fallidos = total_fallidos + 1;
                fallidos_lista{end+1} = fname; %#ok<AGROW>
                acciones{end+1} = [ext ' FALLO']; %#ok<AGROW>
                % Borrar archivo parcial si quedo a medias
                if exist(local_path, 'file') == 2
                    info = dir(local_path);
                    if ~isempty(info) && info.bytes == 0
                        delete(local_path);
                    end
                end
            end
        end

        if isempty(acciones)
            fprintf('completo (ya existia)\n');
        else
            fprintf('%s\n', strjoin(acciones, ', '));
        end
    end

    % ---------------------------------------------------------------------
    % RESUMEN FINAL
    % ---------------------------------------------------------------------
    fprintf('\n========================================================\n');
    fprintf('  RESUMEN\n');
    fprintf('--------------------------------------------------------\n');
    fprintf('  Archivos ya presentes : %d\n', total_ya_existian);
    fprintf('  Archivos descargados  : %d\n', total_descargados);
    fprintf('  Archivos fallidos     : %d\n', total_fallidos);

    if total_fallidos > 0
        fprintf('\n  ATENCION: fallaron %d archivos:\n', total_fallidos);
        for j = 1:numel(fallidos_lista)
            fprintf('    - %s\n', fallidos_lista{j});
        end
        fprintf('\n  Posibles causas: red universitaria bloquea physionet.org,\n');
        fprintf('  corte de conexion, o timeout. Vuelve a ejecutar este script\n');
        fprintf('  (solo intentara los que faltan) o usa otra red.\n');
    else
        fprintf('\n  Todos los registros estan completos (48 x 3 = 144 archivos).\n');
        fprintf('  Listo para la validacion de Fase 1.\n');
    end
    fprintf('========================================================\n');

    % ---------------------------------------------------------------------
    % VERIFICACION FINAL: contar registros completos
    % ---------------------------------------------------------------------
    completos = 0;
    incompletos = {};
    for i = 1:numel(records)
        rec_str = num2str(records(i));
        ok = true;
        for k = 1:numel(extensions)
            local_path = fullfile(dest_dir, [rec_str extensions{k}]);
            if exist(local_path, 'file') ~= 2
                ok = false;
                break;
            end
            info = dir(local_path);
            if isempty(info) || info.bytes == 0
                ok = false;
                break;
            end
        end
        if ok
            completos = completos + 1;
        else
            incompletos{end+1} = rec_str; %#ok<AGROW>
        end
    end

    fprintf('\n  Registros completos: %d de 48\n', completos);
    if ~isempty(incompletos)
        fprintf('  Registros incompletos: %s\n', strjoin(incompletos, ', '));
    end

end
