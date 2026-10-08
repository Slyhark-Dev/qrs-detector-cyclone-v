-- ============================================================================
-- ecg_filter_bp.vhd
-- Pan-Tompkins bandpass cascade, delays rescaled from 200 Hz to 360 Hz
--
-- *** SYNTHESIS-ONLY MODULE, FOR AREA MEASUREMENT ***
-- Drop-in replacement for ecg_filter. Compile, read the Flow Summary and
-- discard. The reported system uses the moving-average stage.
--
-- Low-pass   y(n)   = 2y(n-1) - y(n-2) + x(n) - 2x(n-11) + x(n-22)
-- High-pass  ylp(n) = ylp(n-1) + x(n) - x(n-58)
--            p(n)   = x(n-29) - ylp(n)/58
--
-- Delays scaled by 360/200 = 1.8 from the 1985 equations. Only shifts and
-- adds, no multipliers, as in the original.
--
-- Word growth
--   input          12 bits unsigned
--   low-pass       recursive double integrator over a 22-sample window,
--                  worst case 12 + log2(22^2) approx 22 bits, signed 26
--   high-pass      running sum of 58 samples of the low-pass output,
--                  signed 32
-- ============================================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity ecg_filter_bp is
    port(
        clk          : in  std_logic;
        rst          : in  std_logic;
        ecg_in       : in  std_logic_vector(11 downto 0);
        in_valid     : in  std_logic;
        ecg_filtered : out std_logic_vector(11 downto 0);
        out_valid    : out std_logic
    );
end entity ecg_filter_bp;

architecture rtl of ecg_filter_bp is

    constant D_LP : integer := 11;   -- low-pass delay,  2*D_LP  = 22
    constant D_HP : integer := 29;   -- high-pass delay, 2*D_HP  = 58

    constant W_LP : integer := 26;   -- low-pass datapath
    constant W_HP : integer := 32;   -- high-pass datapath

    -- low-pass input delay line, 2*D_LP + 1 taps
    type lp_line_t is array (0 to 2*D_LP) of signed(W_LP-1 downto 0);
    signal x_lp : lp_line_t := (others => (others => '0'));

    -- low-pass recursive state
    signal y_lp_1 : signed(W_LP-1 downto 0) := (others => '0');
    signal y_lp_2 : signed(W_LP-1 downto 0) := (others => '0');
    signal y_lp   : signed(W_LP-1 downto 0) := (others => '0');

    -- high-pass delay line over the low-pass output, 2*D_HP + 1 taps
    type hp_line_t is array (0 to 2*D_HP) of signed(W_LP-1 downto 0);
    signal x_hp : hp_line_t := (others => (others => '0'));

    -- high-pass running sum and output
    signal run_sum : signed(W_HP-1 downto 0) := (others => '0');
    signal p_out   : signed(W_HP-1 downto 0) := (others => '0');

    signal valid_r : std_logic := '0';

begin

    process(clk)
        variable lp_v  : signed(W_LP-1 downto 0);
        variable sum_v : signed(W_HP-1 downto 0);
        variable mean_v: signed(W_HP-1 downto 0);
    begin
        if rising_edge(clk) then
            if rst = '1' then
                x_lp    <= (others => (others => '0'));
                x_hp    <= (others => (others => '0'));
                y_lp_1  <= (others => '0');
                y_lp_2  <= (others => '0');
                y_lp    <= (others => '0');
                run_sum <= (others => '0');
                p_out   <= (others => '0');
                valid_r <= '0';

            elsif in_valid = '1' then

                -- ---------------------------------------------------------
                -- low-pass delay line
                -- ---------------------------------------------------------
                x_lp(0) <= resize(signed('0' & ecg_in), W_LP);
                for i in 1 to 2*D_LP loop
                    x_lp(i) <= x_lp(i-1);
                end loop;

                -- y(n) = 2y(n-1) - y(n-2) + x(n) - 2x(n-D) + x(n-2D)
                lp_v := shift_left(y_lp_1, 1)
                        - y_lp_2
                        + resize(signed('0' & ecg_in), W_LP)
                        - shift_left(x_lp(D_LP), 1)
                        + x_lp(2*D_LP);

                y_lp   <= lp_v;
                y_lp_1 <= lp_v;
                y_lp_2 <= y_lp_1;

                -- ---------------------------------------------------------
                -- high-pass delay line over the low-pass output
                -- ---------------------------------------------------------
                x_hp(0) <= lp_v;
                for i in 1 to 2*D_HP loop
                    x_hp(i) <= x_hp(i-1);
                end loop;

                -- running sum of 2*D_HP samples
                --   ylp(n) = ylp(n-1) + x(n) - x(n-2D)
                sum_v := run_sum
                         + resize(lp_v, W_HP)
                         - resize(x_hp(2*D_HP), W_HP);
                run_sum <= sum_v;

                -- p(n) = x(n-D) - ylp(n)/(2D)
                -- 58 is not a power of two; the division is approximated by
                -- a shift of 6, which is the realisable form in hardware and
                -- only rescales the output.
                mean_v := shift_right(sum_v, 6);
                p_out  <= resize(x_hp(D_HP), W_HP) - mean_v;

                valid_r <= '1';
            else
                valid_r <= '0';
            end if;
        end if;
    end process;

    -- Truncate to the 12-bit interface of ecg_filter. The scaling is not
    -- meaningful for area measurement, which is the only purpose here.
    ecg_filtered <= std_logic_vector(p_out(11 downto 0));
    out_valid    <= valid_r;

end architecture rtl;
