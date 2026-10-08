-- ============================================================================
-- tb_classifier.vhd
-- Testbench para modulo classifier (Modulo 5)
-- Proyecto: ECG Arritmias FPGA DE1-SoC
-- Simulador: ModelSim-Altera Starter Edition
-- Verifica: normal, bradicardia y taquicardia
--
-- VERSION 2: adaptado al clasificador de tres estados. Los estimulos de
-- variabilidad RR se retiran junto con la rama de fibrilacion auricular.
-- ============================================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity tb_classifier is
end entity tb_classifier;

architecture sim of tb_classifier is

    constant CLK_PERIOD : time := 20 ns;

    signal clk          : std_logic := '0';
    signal rst          : std_logic := '0';
    signal bpm_in       : std_logic_vector(7 downto 0) := (others => '0');
    signal bpm_valid    : std_logic := '0';
    signal arrhyth_code : std_logic_vector(1 downto 0);
    signal alert_level  : std_logic_vector(1 downto 0);
    signal class_valid  : std_logic;

    -- procedimiento para enviar una clasificacion
    procedure classify(
        signal   bpm   : out std_logic_vector(7 downto 0);
        signal   valid : out std_logic;
        constant b_val : in  integer
    ) is
    begin
        bpm   <= std_logic_vector(to_unsigned(b_val, 8));
        valid <= '1';
        wait for CLK_PERIOD;
        valid <= '0';
        wait for CLK_PERIOD * 10;
    end procedure;

begin

    uut: entity work.classifier
        port map(
            clk          => clk,
            rst          => rst,
            bpm_in       => bpm_in,
            bpm_valid    => bpm_valid,
            arrhyth_code => arrhyth_code,
            alert_level  => alert_level,
            class_valid  => class_valid
        );

    clk <= not clk after CLK_PERIOD / 2;

    stim_proc: process
    begin
        -- 1) reset
        rst <= '1';
        wait for CLK_PERIOD * 5;
        rst <= '0';
        wait for CLK_PERIOD * 2;

        -- 2) caso NORMAL: 75 BPM
        --    esperado: code=00, alert=00
        classify(bpm_in, bpm_valid, 75);

        -- 3) caso BRADICARDIA: 50 BPM
        --    esperado: code=01, alert=10
        classify(bpm_in, bpm_valid, 50);

        -- 4) caso TAQUICARDIA: 120 BPM
        --    esperado: code=10, alert=10
        classify(bpm_in, bpm_valid, 120);

        -- 5) limite inferior: 60 BPM, primer valor considerado normal
        --    esperado: code=00, alert=00
        classify(bpm_in, bpm_valid, 60);

        -- 6) limite superior: 100 BPM, ultimo valor considerado normal
        --    esperado: code=00, alert=00
        classify(bpm_in, bpm_valid, 100);

        -- 7) justo por encima del limite: 101 BPM
        --    esperado: code=10, alert=10
        classify(bpm_in, bpm_valid, 101);

        -- 8) retorno a normal
        --    esperado: code=00, alert=00
        classify(bpm_in, bpm_valid, 70);

        wait for CLK_PERIOD * 10;
        assert false report "Simulacion classifier completada" severity note;
        wait;
    end process;

end architecture sim;
