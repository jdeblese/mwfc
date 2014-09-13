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
        OLED_VDD : out std_logic;
        OLED_BAT : out std_logic;
        OLED_RST : out std_logic;
        OLED_CS : out std_logic;
        OLED_SCK : out std_logic;
        OLED_MOSI : out std_logic;
        OLED_CD : out std_logic;
        clk : in std_logic;
        rst : in std_logic );
end main;

architecture Behavioral of main is

    signal input, clk2 : std_logic;

    signal divoverflow : std_logic;

    signal final : unsigned(16 downto 0);
    signal order, orderlatch : signed(7 downto 0);

    constant bcdprecision : integer := 20;
    signal bcd, bcdlatch : std_logic_vector(bcdprecision-1 downto 0);

    signal dispen : std_logic_vector(3 downto 0);

    signal data : std_logic_vector(15 downto 0);

	signal tiledata : std_logic_vector(15 downto 0);
	signal tileaddr : std_logic_vector(9 downto 0);
	signal tilewen : std_logic;

	signal digit : unsigned(3 downto 0);
begin

	fc : entity work.mwfc
		generic map (
			precision => final'length,
			bcdprecision => bcd'length )
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

    data <= bcd(bcd'high downto bcd'high - 15);

    disp : entity work.driveseg
        port map (
            data => data,
            seg_c => dispc,
            seg_a => dispa,
            en => dispen,
            clk => clk,
            rst => rst );

	gpu : entity work.otile
		port map (
			clk => clk,
			rst => rst,
			data => tiledata,
			addr => tileaddr,
			wen => tilewen,
			OLED_VDD => OLED_VDD,
			OLED_BAT => OLED_BAT,
			OLED_RST => OLED_RST,
			OLED_CS => OLED_CS,
			OLED_SCK => OLED_SCK,
			OLED_MOSI => OLED_MOSI,
			OLED_CD => OLED_CD );

	-- Increment digit on every clock tic
	process(clk)
		variable div : unsigned(22 downto 0);
	begin
		if rising_edge(clk) then
			digit <= digit + "1";
			if div = "0" then
				bcdlatch <= bcd;
				orderlatch <= order;
			end if;
			div := div + "1";
		end if;
	end process;

	-- Set the data depending on the digit
	process(digit, orderlatch, bcdlatch)
		variable place : signed(order'range);
		variable sdigit : signed(digit'length downto digit'low);
		constant bcddigits : integer := bcdprecision / 4;
		variable diff : integer;
	begin
		sdigit := signed("0" & std_logic_vector(digit));
		-- The counter 'digit' includes the thousands separators, so compute
		-- the actual order of the digit currently being displayed
		case digit(3 downto 2) is
			-- digit = 0 corresponds to 100 MHz, so the 8th place
			when "00" => place := to_signed(8, place'length) - sdigit;
			when "01" => place := to_signed(9, place'length) - sdigit;
			when "10" => place := to_signed(10, place'length) - sdigit;
			when "11" => place := to_signed(11, place'length) - sdigit;
			when others => place := (others => '0');
		end case;

		if digit = x"3" then
			if orderlatch > to_signed(6 - bcddigits, order'length) then
				tiledata <= x"002c";
			else
				tiledata <= x"0020";
			end if;
		elsif digit = x"7" then
			if orderlatch > to_signed(3 - bcddigits, order'length) then
				tiledata <= x"002c";
			else
				tiledata <= x"0020";
			end if;
		elsif digit = x"b" then
			tiledata <= x"002e";
		elsif digit = x"f" then
			tiledata <= x"0020";
		elsif place < orderlatch then
			tiledata <= x"0030";
		elsif place > (orderlatch + to_signed(bcddigits-1, order'length)) then
			tiledata <= x"0020";
		else
			diff := to_integer(place - orderlatch);
			assert diff >= 0 report "diff should always be > 0" severity error;
			assert diff < bcddigits report "diff should not exceed the number of bcd digits" severity error;
			tiledata <= x"000" & bcdlatch(4*diff + 3 downto 4*diff);
		end if;
	end process;

	tilewen <= '1';
	tileaddr <= "00" & x"6" & std_logic_vector(digit);

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

