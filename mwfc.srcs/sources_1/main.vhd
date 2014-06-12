library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

use IEEE.NUMERIC_STD.ALL;

package constants is
    constant precision : integer := 13;
    constant measureinterval : integer := 8191;  -- FIXME precision^2 - 1

    constant timerbits : integer := 18;
    constant inputbits : integer := precision + 5;

    constant nscalestages : integer := 6;  -- FIXME log2 of maxscalefactor
end constants;

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

use IEEE.NUMERIC_STD.ALL;

library UNISIM;
use UNISIM.VComponents.all;

use work.constants.all;

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

    signal input, clk2 : std_logic;

    signal tcount, isync1 : unsigned(timerbits-1 downto 0);
    signal icount, isync0 : unsigned(inputbits-1 downto 0);
    
    signal scaling : signed(nscalestages-1 downto 0);

    signal ratio : unsigned(precision-1 downto 0);
    
    signal divbusy, divoverflow, divstrobe : std_logic;

	signal final : unsigned(precision downto 0);
	signal order : signed(7 downto 0);

    type A is array (0 to 31) of integer;
    constant digits : A := (
		0, 0, 0, 0, 0, 0, 0, 0, 0,
		2,
		3, 3, 3, 3,
        4, 4, 4,
        5, 5, 5,
        6, 6, 6, 6,
        7, 7, 7,
        8, 8, 8,
        9, 9 );
	type B is array(0 to 31) of unsigned(precision + 2 downto 0);
	constant corrections : B := (
		x"0000", x"0000", x"0000", x"0000", x"0000", x"0000", x"0000", x"0000", x"0000",
		x"3200",
		x"FA00", x"7D00", x"3E80", x"1F40",
		x"9C40", x"4E20", x"2710",
		x"C350", x"61A8", x"30D4",
		x"F424", x"7A12", x"3D09", x"1E85",
		x"9897", x"4C4B", x"2626",
		x"BEBC", x"5F5E", x"2FAF",
		x"EE6B", x"7736" );

    signal bcd : std_logic_vector(15 downto 0);
    signal gpustrobe : std_logic;

    signal dispen : std_logic_vector(3 downto 0);

    signal data : std_logic_vector(15 downto 0);

begin

--  led(led'high) <= divoverflow;
--  led(led'high-1 downto 0) <= (others => '0');
--  led(led'high-1 downto scaling'length) <= (others => '0');
--  led(scaling'range) <= std_logic_vector(scaling);
    led <= std_logic_vector(order);
    dispen <= "1111" when divoverflow = '0' else "0000";

    data <= bcd;
--  data <= std_logic_vector(tcount(15 downto 0)) when btn = "0001" else
--          std_logic_vector(isync1(15 downto 0)) when btn = "0010" else
--          "00" & std_logic_vector(ratio)        when btn = "0100" else
--          "0000000000" & std_logic_vector(scaling) when btn = "1000" else
--          bcd;

    disp : entity work.driveseg
        port map (
            data => data,
            seg_c => dispc,
            seg_a => dispa,
            en => dispen,
            clk => clk,
            rst => rst );

    conv : entity work.hex2bcd
        generic map (
            precision => final'length,
            width => 16,
            bits => 4 )
        port map (
            hex => final,
            bcd => bcd,
            strobe => gpustrobe,
            rst => rst,
            clk => clk );

    process(clk)
        variable counter : unsigned(2 downto 0);
    begin
        if rising_edge(clk) then
            gpustrobe <= '0';
            if divbusy = '1' then
                counter := "100";
            else
                if counter = "001" then
                    gpustrobe <= '1';
                end if;
                if counter > "0" then
                    counter := counter - "1";
                end if;
            end if;
        end if;
    end process;

	process(clk)
        variable C0 : unsigned(corrections(0)'range);
		variable S0 : integer;
		variable F1, F2, F3 : unsigned(ratio'length + corrections(0)'length - 1 downto 0);
        variable O1, O2 : signed(order'range);
	begin
		if rising_edge(clk) then
            -- Pipeline stage 3
			if divoverflow = '0' then
				F3 := shift_right(F2, 4);
				-- Round based on highest truncated bit
				if F3(0) = '1' then
					final <= F3(final'high+1 downto 1) + "1";
				else
					final <= F3(final'high+1 downto 1);
				end if;
			end if;
            order <= O2;

            -- Pipeline stage 2
			if divoverflow = '0' then
				if F1 < shift_left(to_unsigned(1000, F1'length),5) then
					-- Five bits, because retaining one to round
					--F2 := shift_left(F1(F1'high / 2 downto 0),1) * 5;
					F2 := shift_left(F1,1) + shift_left(F1,3);
					O2 := O1 - 1;
                else
                    F2 := F1;
                    O2 := O1;
				end if;
			end if;

            -- Pipeline stage 1
			O1 := to_signed(8, order'length) - digits(S0);
			if divoverflow = '0' then
				-- corrections is shifted up precision+3 bits
                -- Pipeline the access to corrections
                -- Multiply is a slow operation
				F1 := shift_right(ratio * C0, precision + 3 - 1 - 4);
            end if;

            -- Pipeline stage 0
			S0 := -to_integer(scaling);
            C0 := corrections(S0);
		end if;
	end process;


	-- Count the number of timer and input tics in the given
	-- measurement interval, taking a whole number of input tics.
    stage1 : entity work.counter
        generic map (
            Tlen => tcount'length,
            ILen => icount'length,
            measureinterval => measureinterval )
        port map (
            timer => clk,
            input => clk2,
            tcount => tcount,
            icount => icount,
            enable => '1',
            strobe => divstrobe,
            rst => rst);

    process(clk)
    begin
        if rising_edge(clk) then
            isync1 <= (others => '0');
            isync1(isync0'range) <= isync0;
            isync0 <= icount;
        end if;
    end process;

    -- Divide M by N
    stage2 : entity work.fpdiv
        generic map (
            size => tcount'length,
            precision => ratio'length,
            pscale => scaling'length )
        port map (
            dividend => isync1,
            divisor => tcount,
            quotient => ratio,
            scale => scaling,
            busy => divbusy,
            overflow => divoverflow,
            strobe => divstrobe,
            clk => clk,
            rst => rst );

    inclk : BUFG port map ( O => clk2, I => input );

    clkdiv : process(clk,rst)
        variable count : unsigned(7 downto 0);
        variable half : unsigned(7 downto 0);
    begin
        if rising_edge(clk) then
            half := to_unsigned(2, half'length) + unsigned("0000" & btn);

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

