%% GENERATE ECG ROM FOR FPGA DEMO MODE
% Project: Cardiac arrhythmia detection system - FPGA DE1-SoC
% Universidad Tecnologica del Peru (UTP)
%
% Creates ecg_rom.vhd with MIT-BIH record 100 data embedded as internal
% ROM for physical deployment on DE1-SoC without external ADC.
% The ROM loops automatically at 360 Hz using sample_tick from top_ecg.
%
% Output: D:/proyectos/ecg_arrhythmia/ecg_rom.vhd
%
% VERSION 1

clc; clear; close all;

%% 1. Configuration
record = '100';
rom_duration = 10;  % seconds of data to embed (3600 samples = ~13 beats)
output_file = 'D:/proyectos/ecg_arrhythmia/ecg_rom.vhd';

fprintf('Generating ECG ROM for FPGA demo mode\n');
fprintf('Record: %s, Duration: %d seconds\n', record, rom_duration);

%% 2. Load and scale data (same scaling as generate_vhdl_vectors.m)
[signal, fs, ~, ~, ~] = read_mitbih(record);
ecg = signal(:, 1);  % Channel 1 (MLII)

n_rom = rom_duration * fs;  % 3600 samples at 360 Hz
ecg_rom = ecg(1:n_rom);

% Full-scale mapping to 12-bit unsigned with 5% margin
ecg_min = min(ecg_rom);
ecg_max = max(ecg_rom);
margin = 0.05;
ecg_range = ecg_max - ecg_min;
target_min = round(4095 * margin);       % ~205
target_max = round(4095 * (1 - margin)); % ~3890

ecg_unsigned = round((ecg_rom - ecg_min) / ecg_range * (target_max - target_min) + target_min);
ecg_unsigned = max(min(ecg_unsigned, 4095), 0);

fprintf('ECG original (mV): [%.3f, %.3f]\n', ecg_min, ecg_max);
fprintf('ECG scaled 12-bit: [%d, %d]\n', min(ecg_unsigned), max(ecg_unsigned));
fprintf('ROM samples: %d (%.1f seconds)\n', n_rom, n_rom/fs);

%% 3. Calculate address width needed
addr_bits = ceil(log2(n_rom));  % 12 bits for 3600
fprintf('Address width: %d bits (max addr = %d)\n', addr_bits, n_rom-1);

%% 4. Generate ecg_rom.vhd
fid = fopen(output_file, 'w');
if fid == -1
    error('Cannot write to: %s', output_file);
end

% -- VHDL header --
fprintf(fid, '-- ============================================================================\n');
fprintf(fid, '-- ecg_rom.vhd\n');
fprintf(fid, '-- ROM interna con datos MIT-BIH record %s para modo demo\n', record);
fprintf(fid, '-- %d muestras (%.1f segundos a %d Hz), 12-bit unsigned\n', n_rom, rom_duration, fs);
fprintf(fid, '-- Auto-generado por generate_ecg_rom.m el %s\n', datestr(now));
fprintf(fid, '-- Proyecto: ECG Arritmias FPGA DE1-SoC\n');
fprintf(fid, '-- Universidad Tecnologica del Peru (UTP)\n');
fprintf(fid, '-- ============================================================================\n\n');

fprintf(fid, 'library ieee;\n');
fprintf(fid, 'use ieee.std_logic_1164.all;\n');
fprintf(fid, 'use ieee.numeric_std.all;\n\n');

% -- Entity --
fprintf(fid, 'entity ecg_rom is\n');
fprintf(fid, '    port(\n');
fprintf(fid, '        clk     : in  std_logic;                     -- reloj 50 MHz\n');
fprintf(fid, '        rst     : in  std_logic;                     -- reset activo alto\n');
fprintf(fid, '        tick    : in  std_logic;                     -- sample_tick a 360 Hz\n');
fprintf(fid, '        ecg_out : out std_logic_vector(11 downto 0); -- muestra ECG 12-bit\n');
fprintf(fid, '        valid   : out std_logic                      -- pulso dato valido\n');
fprintf(fid, '    );\n');
fprintf(fid, 'end entity ecg_rom;\n\n');

% -- Architecture --
fprintf(fid, 'architecture rtl of ecg_rom is\n\n');
fprintf(fid, '    constant ROM_SIZE : integer := %d;\n', n_rom);
fprintf(fid, '    type rom_type is array(0 to ROM_SIZE-1) of std_logic_vector(11 downto 0);\n\n');

% -- ROM data --
fprintf(fid, '    constant ECG_DATA : rom_type := (\n');
for i = 1:n_rom
    hex_val = dec2hex(ecg_unsigned(i), 3);
    if i < n_rom
        fprintf(fid, '        x"%s", -- %d\n', hex_val, i-1);
    else
        fprintf(fid, '        x"%s"  -- %d\n', hex_val, i-1);
    end
end
fprintf(fid, '    );\n\n');

% -- Signals --
fprintf(fid, '    signal addr      : unsigned(%d downto 0) := (others => ''0'');\n', addr_bits-1);
fprintf(fid, '    signal valid_reg : std_logic := ''0'';\n\n');

% -- Process --
fprintf(fid, 'begin\n\n');
fprintf(fid, '    -- Contador de direccion: avanza con sample_tick, loop al llegar al final\n');
fprintf(fid, '    process(clk)\n');
fprintf(fid, '    begin\n');
fprintf(fid, '        if rising_edge(clk) then\n');
fprintf(fid, '            if rst = ''1'' then\n');
fprintf(fid, '                addr      <= (others => ''0'');\n');
fprintf(fid, '                valid_reg <= ''0'';\n');
fprintf(fid, '            elsif tick = ''1'' then\n');
fprintf(fid, '                if addr >= to_unsigned(ROM_SIZE - 1, %d) then\n', addr_bits);
fprintf(fid, '                    addr <= (others => ''0'');  -- loop al inicio\n');
fprintf(fid, '                else\n');
fprintf(fid, '                    addr <= addr + 1;\n');
fprintf(fid, '                end if;\n');
fprintf(fid, '                valid_reg <= ''1'';\n');
fprintf(fid, '            else\n');
fprintf(fid, '                valid_reg <= ''0'';\n');
fprintf(fid, '            end if;\n');
fprintf(fid, '        end if;\n');
fprintf(fid, '    end process;\n\n');

% -- Output --
fprintf(fid, '    ecg_out <= ECG_DATA(to_integer(addr));\n');
fprintf(fid, '    valid   <= valid_reg;\n\n');

fprintf(fid, 'end architecture rtl;\n');

fclose(fid);

%% 5. Summary
fprintf('\n--- ROM Generation Complete ---\n');
fprintf('Output file: %s\n', output_file);
fprintf('ROM size: %d samples x 12 bits = %d bits\n', n_rom, n_rom*12);
fprintf('Estimated M10K blocks: %d (of 397 available)\n', ceil(n_rom*12/10240));
fprintf('Demo loop duration: %.1f seconds at 360 Hz\n', n_rom/fs);
fprintf('Ready to add to Quartus project and compile.\n');
