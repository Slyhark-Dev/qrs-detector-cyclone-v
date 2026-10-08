-- ============================================================================
-- rr_calculator.vhd
-- Modulo 4: Calculador de intervalo RR y BPM
-- Proyecto: ECG Arritmias FPGA DE1-SoC
-- Cuenta ciclos de reloj entre picos R
-- BPM = 60 * freq_muestreo / intervalo_RR
-- Buffer de 4 intervalos para variabilidad (usado por classifier)
-- ============================================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity rr_calculator is
    port(
        clk          : in  std_logic;                     -- reloj 50 MHz
        rst          : in  std_logic;                     -- reset activo alto
        sample_tick  : in  std_logic;                     -- pulso a 360 Hz
        r_peak       : in  std_logic;                     -- pulso pico R detectado
        bpm_out      : out std_logic_vector(7 downto 0);  -- BPM (0-255)
        bpm_valid    : out std_logic;                     -- pulso BPM nuevo
        rr_interval  : out std_logic_vector(15 downto 0); -- intervalo RR en muestras
        rr_mean      : out std_logic_vector(15 downto 0); -- promedio 4 intervalos RR
        rr_max       : out std_logic_vector(15 downto 0); -- maximo de 4 intervalos
        rr_min       : out std_logic_vector(15 downto 0)  -- minimo de 4 intervalos
    );
end entity rr_calculator;

architecture rtl of rr_calculator is

    -- contador de muestras entre picos R (16 bits = hasta 65535 muestras)
    signal sample_cnt   : unsigned(15 downto 0) := (others => '0');
    signal rr_current   : unsigned(15 downto 0) := (others => '0');
    signal first_peak   : std_logic := '1';

    -- buffer circular de 4 intervalos RR
    type rr_buf_t is array (0 to 3) of unsigned(15 downto 0);
    signal rr_buf   : rr_buf_t := (others => (others => '0'));
    signal buf_idx  : unsigned(1 downto 0) := (others => '0');
    signal buf_full : std_logic := '0';
    signal buf_cnt  : unsigned(2 downto 0) := (others => '0');

    -- calculo BPM: 60 * 360 = 21600 / rr_interval
    -- usamos constante 21600 para frecuencia de muestreo 360 Hz
    constant NUMERADOR_BPM : unsigned(15 downto 0) := to_unsigned(21600, 16);

    -- resultados internos
    signal bpm_reg       : unsigned(7 downto 0)  := (others => '0');
    signal bpm_valid_reg : std_logic := '0';

    -- estadisticas de los 4 intervalos
    signal mean_reg : unsigned(15 downto 0) := (others => '0');
    signal max_reg  : unsigned(15 downto 0) := (others => '0');
    signal min_reg  : unsigned(15 downto 0) := (others => '1');

begin

    process(clk)
        variable sum_rr   : unsigned(17 downto 0);
        variable max_temp : unsigned(15 downto 0);
        variable min_temp : unsigned(15 downto 0);
        variable bpm_temp : unsigned(31 downto 0);
    begin
        if rising_edge(clk) then
            if rst = '1' then
                sample_cnt   <= (others => '0');
                rr_current   <= (others => '0');
                first_peak   <= '1';
                rr_buf       <= (others => (others => '0'));
                buf_idx      <= (others => '0');
                buf_full     <= '0';
                buf_cnt      <= (others => '0');
                bpm_reg      <= (others => '0');
                bpm_valid_reg <= '0';
                mean_reg     <= (others => '0');
                max_reg      <= (others => '0');
                min_reg      <= (others => '1');
            else
                bpm_valid_reg <= '0';

                -- contar muestras entre picos (incrementa con sample_tick)
                if sample_tick = '1' then
                    if sample_cnt < 65535 then
                        sample_cnt <= sample_cnt + 1;
                    end if;
                end if;

                -- cuando llega un pico R
                if r_peak = '1' then
                    if first_peak = '1' then
                        -- primer pico: solo reiniciar contador
                        first_peak <= '0';
                        sample_cnt <= (others => '0');
                    else
                        -- guardar intervalo RR
                        rr_current <= sample_cnt;

                        -- almacenar en buffer circular
                        rr_buf(to_integer(buf_idx)) <= sample_cnt;
                        buf_idx <= buf_idx + 1;

                        if buf_cnt < 4 then
                            buf_cnt <= buf_cnt + 1;
                        end if;

                        if buf_cnt >= 3 then
                            buf_full <= '1';
                        end if;

                        -- calcular BPM: 21600 / rr_interval
                        if sample_cnt > 0 then
                            bpm_temp := resize(NUMERADOR_BPM, 32);
                            bpm_temp := bpm_temp / resize(sample_cnt, 32);
                            -- saturar a 255
                            if bpm_temp > 255 then
                                bpm_reg <= to_unsigned(255, 8);
                            else
                                bpm_reg <= bpm_temp(7 downto 0);
                            end if;
                            bpm_valid_reg <= '1';
                        end if;

                        -- calcular estadisticas si buffer lleno
                        if buf_full = '1' then
                            -- promedio de 4 intervalos
                            sum_rr := resize(rr_buf(0), 18)
                                    + resize(rr_buf(1), 18)
                                    + resize(rr_buf(2), 18)
                                    + resize(rr_buf(3), 18);
                            mean_reg <= sum_rr(17 downto 2); -- div 4

                            -- maximo y minimo
                            max_temp := rr_buf(0);
                            min_temp := rr_buf(0);
                            for i in 1 to 3 loop
                                if rr_buf(i) > max_temp then
                                    max_temp := rr_buf(i);
                                end if;
                                if rr_buf(i) < min_temp then
                                    min_temp := rr_buf(i);
                                end if;
                            end loop;
                            max_reg <= max_temp;
                            min_reg <= min_temp;
                        end if;

                        -- reiniciar contador
                        sample_cnt <= (others => '0');
                    end if;
                end if;

            end if;
        end if;
    end process;

    -- asignacion de salidas
    bpm_out     <= std_logic_vector(bpm_reg);
    bpm_valid   <= bpm_valid_reg;
    rr_interval <= std_logic_vector(rr_current);
    rr_mean     <= std_logic_vector(mean_reg);
    rr_max      <= std_logic_vector(max_reg);
    rr_min      <= std_logic_vector(min_reg);

end architecture rtl;