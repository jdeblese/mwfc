library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

library UNISIM;
use UNISIM.VComponents.all;

entity main is
    Port (
        dispc : out std_logic_vector(7 downto 0);
        dispa : out std_logic_vector(3 downto 0);
        btn : in std_logic_vector(4 downto 1);
        led : out std_logic_vector(7 downto 0);
        clk : in std_logic;
        rst : in std_logic );
end main;

architecture Behavioral of main is

	constant precision : integer := 13;
	constant measureinterval : integer := 8191;

    signal input, clk2 : std_logic;

    signal divoverflow : std_logic;

	signal final : unsigned(precision downto 0);
	signal order : signed(7 downto 0);

    signal bcd : std_logic_vector(15 downto 0);

    signal dispen : std_logic_vector(3 downto 0);

    signal data : std_logic_vector(15 downto 0);

begin

	fc : entity work.mwfc
		generic map (
			precision => precision,
			measureinterval => measureinterval)
		port map (
			rawfrq => final,
			bcdfrq => bcd,
			ord => order,
			overflow => divoverflow,
			clk => clk,
			clk2 => clk2,
			rst => rst );

    led <= std_logic_vector(order);
    dispen <= "1111" when divoverflow = '0' else "0000";

    data <= bcd;

    disp : entity work.driveseg
        port map (
            data => data,
            seg_c => dispc,
            seg_a => dispa,
            en => dispen,
            clk => clk,
            rst => rst );

    inclk : BUFG port map ( O => clk2, I => input );

	-- Input test signal: divides clk by 2 * (2 + btn)
    clkdiv : process(clk,rst)
        variable count : unsigned(10 downto 0);
        variable half : unsigned(count'range);
    begin
        if rising_edge(clk) then
            half := to_unsigned(2, half'length) + unsigned(btn & "000");

            if count = half - "1" then
                input <= '1';
            elsif count = shift_left(half,1) - "1" then
                input <= '0';
            end if;

            if rst = '1' then
                count := (others => '0');
            elsif count = shift_left(half,1) - "1" then
                count := (others => '0');
            else
                count := count + "1";
            end if;
        end if;
    end process;

end Behavioral;

