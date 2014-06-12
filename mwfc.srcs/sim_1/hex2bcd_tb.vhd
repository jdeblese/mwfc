library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity hex2bcd_tb is
end hex2bcd_tb;

architecture Behavioral of hex2bcd_tb is

    constant clk_period : time := 10 ns;
    signal clk : std_logic := '0';
    signal rst : std_logic := '1';

    signal strobe : std_logic := '0';

    signal hex : unsigned(12 downto 0);

begin

    clk <= not clk after clk_period/2; 

    stim : process
    begin
        wait for clk_period * 10;
        rst <= '0';
        wait for clk_period;

        hex <= to_unsigned(400, hex'length);
        strobe <= '1';
        wait for clk_period;
        strobe <= '0';
        wait for clk_period * 15;

        hex <= to_unsigned(8191, hex'length);
        strobe <= '1';
        wait for clk_period;
        strobe <= '0';
        wait for clk_period * 15;

        hex <= to_unsigned(4096, hex'length);
        strobe <= '1';
        wait for clk_period;
        strobe <= '0';
        wait for clk_period * 15;

        hex <= to_unsigned(1, hex'length);
        strobe <= '1';
        wait for clk_period;
        strobe <= '0';
        wait for clk_period * 15;

        wait;
    end process;

    dut : entity work.hex2bcd
        generic map (
            precision => hex'length,
            width => 16,
            bits => 4 )
        port map (
            hex => hex,
            bcd => open,
            strobe => strobe,
            rst => rst,
            clk => clk );

end Behavioral;
