library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity fpbaseconv_tb is
end fpbaseconv_tb;

architecture Behavioral of fpbaseconv_tb is
    constant clk_period : time := 10 ns;
    signal clk : std_logic := '0';
    signal rst : std_logic;

    constant precision : integer := 17;
    constant exp_precision : integer := 8;
    constant nscalestages : integer := 7;

	signal scaling : signed(nscalestages-1 downto 0);
	signal ratio : unsigned(precision-1 downto 0);
	signal strobe : std_logic := '0';
begin

    clk <= not clk after clk_period/2; 

    stim : process
    begin
        rst <= '1';
        wait for clk_period * 10;
        rst <= '0';
        wait for clk_period;

		scaling <= to_signed(-19, scaling'length);
--		ratio   <= '1' & x"797D";
		ratio   <= '1' & x"7981";
        wait for clk_period;
        strobe <= '1';
        wait for clk_period;
        strobe <= '0';

        wait;
    end process;

    dut : entity work.fpbaseconv
        generic map (
            precision => precision,
            exp_precision => exp_precision,
            nscalestages => nscalestages )
        port map (
			mantissa => open,
			exponent => open,
			busy => open,
			scaling => scaling,
			ratio => ratio,
			strobe => strobe,
            clk => clk,
            rst => rst );

end Behavioral;

