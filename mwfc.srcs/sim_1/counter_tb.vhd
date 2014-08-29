library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

use IEEE.NUMERIC_STD.ALL;

entity counter_tb is
end counter_tb;

architecture Behavioral of counter_tb is
    constant precision : integer := 13;
    constant measureinterval : integer := 256;  -- 8191;
    constant inputbits : integer := precision + 5;
    constant timerbits : integer := 18;

    signal clk, clk2 : std_logic := '0';
    constant clk_period : time := 10 ns;
--    constant clk2_period : time := 1.25 ns;
--    constant clk2_period : time := 2.272727 ms;
--    constant clk2_period : time := 27 ns;
--    constant clk2_period : time := 25 ns;
--    constant clk2_period : time := 24.985 ns;
--    constant clk2_period : time := 12.3107226 ns;
    constant clk2_period : time := clk_period * 3.14159;

    signal rst : std_logic;

    signal tcount : unsigned(timerbits-1 downto 0);
    signal icount : unsigned(inputbits-1 downto 0);

    signal divstrobe : std_logic;
begin

    -- Count the number of timer and input tics in the given
    -- measurement interval, taking a whole number of input tics.
    dut : entity work.counter 
        generic map (
            Tlen => tcount'length,
            Ilen => icount'length,
            measureinterval => measureinterval )
        port map (
            timer => clk,
            input => clk2,
            tcount => tcount,
            icount => icount,
--          overflow => open,
            enable => '1',
            strobe => divstrobe,
            rst => rst);

    clk <= not clk after clk_period/2; 
    clk2 <= not clk2 after clk2_period/2; 

    stim : process
    begin
        rst <= '1';
        wait for 100 ns;
        rst <= '0';
        
        wait;
    end process;

end Behavioral;
