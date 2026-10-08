-- ============================================================================
-- qrs_detector.vhd
-- Modulo 3: Detector de pico R — Pan-Tompkins simplificado
-- Proyecto: ECG Arritmias FPGA DE1-SoC
-- Etapas: derivada -> cuadrado -> integracion ventana -> umbral adaptivo
--
-- VERSION 2 (FIX refractario):
--   El periodo refractario se decrementa UNA VEZ POR MUESTRA
--   (cuando valid_d3='1'), no en cada ciclo de reloj de 50 MHz.
--   72 muestras = 200 ms a 360 Hz.
--
-- VERSION 3 (FIX rango dinamico de la energia):
--   El cuadrado se conservaba truncado a sq_full(25 downto 10), lo que
--   descartaba 10 bits y dejaba la energia integrada de los registros de
--   QRS de baja pendiente por debajo del piso del umbral. Ademas el
--   decaimiento threshold - threshold/32 se anula para threshold < 32
--   (division entera), de modo que el umbral quedaba bloqueado.
--
--   Cambios:
--     squared    : 16 -> 24 bits, sin truncamiento
--     win_sum    : 19 -> 27 bits
--     threshold  : 19 -> 27 bits, valor inicial escalado
--     decaimiento: threshold/64 + 1, con piso THR_MIN
--
-- VERSION 4 (umbral secundario post-refractario):
--   El decaimiento del umbral adaptivo lo lleva al piso THR_MIN durante
--   el intervalo entre latidos, momento en el que ondas T, artefacto y
--   ruido de linea base superan el umbral y generan detecciones espurias.
--
--   Se anade un umbral secundario activo durante VULN_LEN muestras
--   contadas desde el pico R. Dentro de esa ventana una deteccion debe
--   superar tanto el umbral adaptivo como tres veces la energia del
--   ultimo complejo aceptado. Es el equivalente en punto fijo del
--   segundo umbral del algoritmo Pan-Tompkins original.
--
--   El factor 3 se implementa como last_peak + (last_peak << 1): un
--   sumador y un desplazamiento, sin multiplicador. La comparacion se
--   extiende a 29 bits para que el triple no desborde.
--
--   Parametros seleccionados sobre el conjunto DS1 de la division
--   inter-paciente de de Chazal (22 registros), evaluados una sola vez
--   sobre DS2 (22 registros disjuntos). Optimo interior en VULN_LEN =
--   160 muestras (444 ms), dentro del intervalo T-P tipico, y factor 3,
--   del mismo orden que el umbral secundario de Pan-Tompkins.
-- ============================================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity qrs_detector is
    port(
        clk        : in  std_logic;                     -- reloj 50 MHz
        rst        : in  std_logic;                     -- reset activo alto
        ecg_in     : in  std_logic_vector(11 downto 0); -- entrada filtrada 12 bits
        in_valid   : in  std_logic;                     -- pulso dato valido
        r_peak     : out std_logic;                     -- pulso cuando detecta pico R
        energy_out : out std_logic_vector(15 downto 0)  -- energia integrada (debug)
    );
end entity qrs_detector;

architecture rtl of qrs_detector is

    -- etapa 1: derivada
    signal prev_sample : signed(12 downto 0) := (others => '0');
    signal deriv       : signed(12 downto 0) := (others => '0');

    -- etapa 2: cuadrado
    -- deriv en [-4096, 4095] -> deriv*deriv cabe en 24 bits sin signo
    signal squared     : unsigned(23 downto 0) := (others => '0');

    -- etapa 3: integracion ventana movil 8 muestras
    -- 8 x 2^24 cabe en 27 bits
    type win_reg_t is array (0 to 7) of unsigned(23 downto 0);
    signal win       : win_reg_t := (others => (others => '0'));
    signal win_sum   : unsigned(26 downto 0) := (others => '0');
    signal win_count : unsigned(3 downto 0)  := (others => '0');

    -- etapa 4: umbral adaptivo
    constant THR_INIT : unsigned(26 downto 0) := to_unsigned(512000, 27);
    constant THR_MIN  : unsigned(26 downto 0) := to_unsigned(1500, 27);

    signal threshold  : unsigned(26 downto 0) := THR_INIT;
    signal peak_found : std_logic := '0';

    -- periodo refractario: evita doble deteccion
    -- a 360 Hz, minimo 200 ms entre picos = 72 muestras
    signal refract_cnt : unsigned(7 downto 0) := (others => '0');
    signal in_refract  : std_logic := '0';

    -- umbral secundario: 160 muestras = 444 ms contadas desde el pico R.
    -- El refractario absoluto ocupa las primeras 72; en las 88 restantes
    -- se exige superar tres veces la energia del ultimo complejo.
    constant VULN_LEN : integer := 160;

    signal vuln_cnt  : unsigned(8 downto 0) := (others => '0');
    signal in_vuln   : std_logic := '0';
    signal last_peak : unsigned(26 downto 0) := (others => '0');

    -- pipeline validos
    signal valid_d1 : std_logic := '0';
    signal valid_d2 : std_logic := '0';
    signal valid_d3 : std_logic := '0';

begin

    process(clk)
        variable deriv_temp : signed(12 downto 0);
        variable sq_full    : signed(25 downto 0);
        variable sum_temp   : unsigned(26 downto 0);
        variable decay      : unsigned(26 downto 0);
    begin
        if rising_edge(clk) then
            if rst = '1' then
                prev_sample <= (others => '0');
                deriv       <= (others => '0');
                squared     <= (others => '0');
                win         <= (others => (others => '0'));
                win_sum     <= (others => '0');
                win_count   <= (others => '0');
                threshold   <= THR_INIT;
                peak_found  <= '0';
                refract_cnt <= (others => '0');
                in_refract  <= '0';
                vuln_cnt    <= (others => '0');
                in_vuln     <= '0';
                last_peak   <= (others => '0');
                valid_d1    <= '0';
                valid_d2    <= '0';
                valid_d3    <= '0';
            else
                -- pipeline de validos
                valid_d1 <= in_valid;
                valid_d2 <= valid_d1;
                valid_d3 <= valid_d2;

                -- etapa 1: derivada (muestra actual - muestra anterior)
                if in_valid = '1' then
                    deriv_temp  := resize(signed('0' & ecg_in), 13)
                                 - prev_sample;
                    deriv       <= deriv_temp;
                    prev_sample <= resize(signed('0' & ecg_in), 13);
                end if;

                -- etapa 2: cuadrado, sin truncamiento
                if valid_d1 = '1' then
                    sq_full := deriv * deriv;
                    squared <= unsigned(sq_full(23 downto 0));
                end if;

                -- etapa 3: integracion ventana movil 8 muestras
                if valid_d2 = '1' then
                    win(1 to 7) <= win(0 to 6);
                    win(0)      <= squared;

                    sum_temp := (others => '0');
                    for i in 0 to 6 loop
                        sum_temp := sum_temp + resize(win(i), 27);
                    end loop;
                    sum_temp := sum_temp + resize(squared, 27);
                    win_sum  <= sum_temp;

                    if win_count < 8 then
                        win_count <= win_count + 1;
                    end if;
                end if;

                -- temporizadores: decrementan una vez por muestra
                if valid_d3 = '1' then
                    if in_refract = '1' then
                        if refract_cnt > 0 then
                            refract_cnt <= refract_cnt - 1;
                        else
                            in_refract <= '0';
                        end if;
                    end if;

                    if in_vuln = '1' then
                        if vuln_cnt > 0 then
                            vuln_cnt <= vuln_cnt - 1;
                        else
                            in_vuln <= '0';
                        end if;
                    end if;
                end if;

                -- etapa 4: umbral adaptivo + deteccion pico
                peak_found <= '0';
                if valid_d3 = '1' and win_count = 8 and in_refract = '0' then

                    -- dentro de la ventana el criterio es doble: umbral
                    -- adaptivo y tres veces la energia del ultimo complejo
                    if (win_sum > threshold) and
                       ((in_vuln = '0') or
                        (resize(win_sum, 29) >
                         (resize(last_peak, 29)
                          + shift_left(resize(last_peak, 29), 1))))
                    then
                        peak_found <= '1';

                        -- actualizar umbral: 75% viejo + 25% nuevo pico
                        threshold <= shift_right(threshold, 1)
                                   + shift_right(threshold, 2)
                                   + shift_right(win_sum, 2);

                        -- referencia de energia para la ventana vulnerable
                        last_peak <= win_sum;

                        -- refractario absoluto: 72 muestras = 200 ms
                        refract_cnt <= to_unsigned(72, 8);
                        in_refract  <= '1';

                        -- umbral secundario, contado desde este pico
                        vuln_cnt <= to_unsigned(VULN_LEN, 9);
                        in_vuln  <= '1';
                    else
                        -- decaimiento lento con termino constante:
                        -- garantiza descenso tambien para umbrales pequenos
                        decay := shift_right(threshold, 6) + 1;
                        if threshold > (THR_MIN + decay) then
                            threshold <= threshold - decay;
                        else
                            threshold <= THR_MIN;
                        end if;
                    end if;
                end if;

            end if;
        end if;
    end process;

    r_peak     <= peak_found;
    energy_out <= std_logic_vector(win_sum(26 downto 11));

end architecture rtl;
