-- ============================================================================
-- tb_ecg_input.vhd
-- Testbench para modulo ecg_input (Modulo 1)
-- Proyecto: ECG Arritmias FPGA DE1-SoC
-- Simulador: ModelSim-Altera Starter Edition
-- ============================================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity tb_ecg_input is
    -- entidad vacia (es un testbench)
end entity tb_ecg_input;

architecture sim of tb_ecg_input is

    -- constantes
    constant CLK_PERIOD : time := 20 ns;  -- 50 MHz DE1-SoC

    -- senales de estimulo
    signal clk        : std_logic := '0';
    signal rst        : std_logic := '0';
    signal ecg_data   : std_logic_vector(11 downto 0) := (others => '0');
    signal data_valid : std_logic := '0';

    -- senales de salida
    signal ecg_out    : std_logic_vector(11 downto 0);
    signal out_valid  : std_logic;

begin

    -- instancia del modulo bajo prueba
    uut: entity work.ecg_input
        port map(
            clk        => clk,
            rst        => rst,
            ecg_data   => ecg_data,
            data_valid => data_valid,
            ecg_out    => ecg_out,
            out_valid  => out_valid
        );

    -- generador de reloj 50 MHz
    clk <= not clk after CLK_PERIOD / 2;

    -- proceso de estimulos
    stim_proc: process
    begin
        -- 1) reset activo durante 5 ciclos
        rst <= '1';
        wait for CLK_PERIOD * 5;
        rst <= '0';
        wait for CLK_PERIOD * 2;

        -- 2) muestra 1: valor 500
        ecg_data   <= std_logic_vector(to_unsigned(500, 12));
        data_valid <= '1';
        wait for CLK_PERIOD;
        data_valid <= '0';
        wait for CLK_PERIOD * 3;

        -- 3) muestra 2: valor 2048
        ecg_data   <= std_logic_vector(to_unsigned(2048, 12));
        data_valid <= '1';
        wait for CLK_PERIOD;
        data_valid <= '0';
        wait for CLK_PERIOD * 3;

        -- 4) muestra 3: valor 300
        ecg_data   <= std_logic_vector(to_unsigned(300, 12));
        data_valid <= '1';
        wait for CLK_PERIOD;
        data_valid <= '0';
        wait for CLK_PERIOD * 3;

        -- 5) fin de simulacion
        wait for CLK_PERIOD * 5;
        assert false report "Simulacion completada con exito" severity note;
        wait;
    end process;

end architecture sim;