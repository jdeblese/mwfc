library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity fpdiv_tb is
end fpdiv_tb;

architecture Behavioral of fpdiv_tb is
    constant clk_period : time := 10 ns;
    signal clk : std_logic := '0';
    signal rst : std_logic;

    signal dividend : unsigned (17 downto 0);
    signal divisor : unsigned (17 downto 0);
    signal quotient : unsigned (12 downto 0);
    signal scale : signed (4 downto 0);
    signal busy : std_logic;
    signal overflow : std_logic;
    signal strobe : std_logic := '0';
begin

    clk <= not clk after clk_period/2; 

    stim : process
    begin
        rst <= '1';
        wait for clk_period * 10;
        rst <= '0';
        wait for clk_period;

        assert busy = '0' report "Divider is still busy" severity error;
        dividend <= to_unsigned(27, dividend'length);
        divisor <= to_unsigned(4, divisor'length);
        strobe <= '1';
        wait for clk_period;
        strobe <= '0';
        wait for clk_period * 24;
        assert quotient = 6912 report "Bad quotient" severity error;
        assert scale = -10 report "Bad scale" severity error;

        assert busy = '0' report "Divider is still busy" severity error;
        dividend <= to_unsigned(3277, dividend'length);
        divisor <= to_unsigned(8192, divisor'length);
        strobe <= '1';
        wait for clk_period;
        strobe <= '0';
        wait for clk_period * 24;
        assert quotient = 6554 report "Bad quotient" severity error;
        assert scale = -14 report "Bad scale" severity error;

        assert busy = '0' report "Divider is still busy" severity error;
        dividend <= to_unsigned(1, dividend'length);
        divisor <= to_unsigned(8193, divisor'length);
        strobe <= '1';
        wait for clk_period;
        strobe <= '0';
        wait for clk_period * 36;
        assert overflow = '1' report "Test should overflow" severity error;

        assert busy = '0' report "Divider is still busy" severity error;
        dividend <= to_unsigned(1, dividend'length);
        divisor <= to_unsigned(9, divisor'length);
        strobe <= '1';
        wait for clk_period;
        strobe <= '0';
        wait for clk_period * 24;
        assert quotient = 7280 report "Bad quotient" severity error;
        assert scale = -16 report "Bad scale" severity error;

        assert busy = '0' report "Divider is still busy" severity error;
        dividend <= (others => '1');
        divisor <= to_unsigned(1, divisor'length);
        strobe <= '1';
        wait for clk_period;
        strobe <= '0';
        wait for clk_period * 24;
        assert overflow = '1' report "Test should have overflowed" severity error;

        -- FIXME formulate a divisor overflow test

        wait;
    end process;

    dut : entity work.fpdiv
        generic map (
            size => dividend'length,
            precision => quotient'length,
            pscale => scale'length )
        port map (
            dividend => dividend,
            divisor => divisor,
            quotient => quotient,
            scale => scale,
            busy => busy,
            overflow => overflow,
            strobe => strobe,
            clk => clk,
            rst => rst );

end Behavioral;

