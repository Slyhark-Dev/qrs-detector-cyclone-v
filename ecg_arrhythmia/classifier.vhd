-- ============================================================================
-- classifier.vhd
-- Modulo 5: Clasificador de frecuencia cardiaca — maquina de estados
-- Proyecto: ECG Arritmias FPGA DE1-SoC
--
-- Clasifica tres estados a partir de la frecuencia cardiaca instantanea:
--   Normal      : 60 a 100 BPM
--   Bradicardia : BPM < 60
--   Taquicardia : BPM > 100
--
-- VERSION 2:
--   Se retira la rama de fibrilacion auricular. El criterio anterior
--   comparaba el rango de cuatro intervalos RR contra rr_mean/4 +
--   rr_mean/16. Evaluado contra los episodios anotados de AFIB y AFL
--   del MIT-BIH sobre 44 registros, alcanzo una predictividad positiva
--   de 26,7 %: la ectopia ventricular produce la misma firma de
--   irregularidad que la fibrilacion auricular, y una ventana de cuatro
--   latidos no permite distinguirlas. La practica clinica emplea
--   segmentos de 30 s o mas con medidas robustas de irregularidad.
--
--
--   Consecuencia sobre la interfaz: los puertos rr_mean, rr_max y
--   rr_min dejan de ser necesarios y se retiran.
--
-- Codificacion de salida: 00 normal, 01 bradicardia, 10 taquicardia.
-- El valor 11 queda reservado.
-- ============================================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity classifier is
    port(
        clk          : in  std_logic;                    -- reloj 50 MHz
        rst          : in  std_logic;                    -- reset activo alto
        bpm_in       : in  std_logic_vector(7 downto 0); -- BPM de rr_calculator
        bpm_valid    : in  std_logic;                    -- pulso BPM nuevo
        arrhyth_code : out std_logic_vector(1 downto 0); -- 00=normal,01=bradi,10=taqui
        alert_level  : out std_logic_vector(1 downto 0); -- 00=sin,01=baja,10=media
        class_valid  : out std_logic                     -- pulso clasificacion nueva
    );
end entity classifier;

architecture rtl of classifier is

    -- estados de la maquina
    type state_t is (ST_IDLE, ST_CLASSIFY);
    signal state : state_t := ST_IDLE;

    -- umbrales de frecuencia cardiaca
    constant BPM_BRADI : unsigned(7 downto 0) := to_unsigned(60, 8);
    constant BPM_TAQUI : unsigned(7 downto 0) := to_unsigned(100, 8);

    -- codigos de clasificacion
    constant CODE_NORMAL : std_logic_vector(1 downto 0) := "00";
    constant CODE_BRADI  : std_logic_vector(1 downto 0) := "01";
    constant CODE_TAQUI  : std_logic_vector(1 downto 0) := "10";

    -- niveles de alerta
    constant ALERT_NONE : std_logic_vector(1 downto 0) := "00";
    constant ALERT_MID  : std_logic_vector(1 downto 0) := "10";

    -- registros internos
    signal code_reg  : std_logic_vector(1 downto 0) := CODE_NORMAL;
    signal alert_reg : std_logic_vector(1 downto 0) := ALERT_NONE;
    signal valid_reg : std_logic := '0';

    -- valor capturado
    signal bpm_cap : unsigned(7 downto 0) := (others => '0');

begin

    process(clk)
    begin
        if rising_edge(clk) then
            if rst = '1' then
                state     <= ST_IDLE;
                code_reg  <= CODE_NORMAL;
                alert_reg <= ALERT_NONE;
                valid_reg <= '0';
                bpm_cap   <= (others => '0');
            else
                valid_reg <= '0';

                case state is

                    when ST_IDLE =>
                        -- esperar nuevo BPM
                        if bpm_valid = '1' then
                            bpm_cap <= unsigned(bpm_in);
                            state   <= ST_CLASSIFY;
                        end if;

                    when ST_CLASSIFY =>
                        -- clasificar por frecuencia cardiaca
                        if bpm_cap < BPM_BRADI then
                            code_reg  <= CODE_BRADI;
                            alert_reg <= ALERT_MID;
                        elsif bpm_cap > BPM_TAQUI then
                            code_reg  <= CODE_TAQUI;
                            alert_reg <= ALERT_MID;
                        else
                            code_reg  <= CODE_NORMAL;
                            alert_reg <= ALERT_NONE;
                        end if;

                        valid_reg <= '1';
                        state     <= ST_IDLE;

                end case;
            end if;
        end if;
    end process;

    -- asignacion de salidas
    arrhyth_code <= code_reg;
    alert_level  <= alert_reg;
    class_valid  <= valid_reg;

end architecture rtl;
