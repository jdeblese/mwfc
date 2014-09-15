library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

library UNISIM;
use UNISIM.VComponents.all;

entity mwfc is
    Generic (
        precision : integer := 13;
        bcdprecision : integer := 16 );
    Port (
        rawfrq : out unsigned(precision - 1 downto 0);  -- May need an extra bit of margin
        bcdfrq : out std_logic_vector(bcdprecision - 1 downto 0);
        ord : out signed(7 downto 0);
        overflow : out std_logic;
        clk : in std_logic;
        clk2 : in std_logic;
        rst : in std_logic );
end mwfc;

architecture Behavioral of mwfc is
    -- The following constants are taken from the accuracy calculation
    -- on the associated spreadsheet
    constant hfbitmargin : integer := 2;  -- FIXME should be 2
    constant lfbitmargin : integer := 19;

    constant inputbits : integer := precision + hfbitmargin;
    constant timerbits : integer := lfbitmargin;
    constant nscalestages : integer := 7;  -- FIXME log2 of maxscalefactor

    signal tcount, isync1 : unsigned(timerbits-1 downto 0);
    signal icount, isync0 : unsigned(inputbits-1 downto 0);

    signal scaling : signed(nscalestages-1 downto 0);

    signal ratio : unsigned(precision-1 downto 0);

    signal divbusy, divoverflow, divstrobe : std_logic;

    signal bcdstrobe : std_logic;

    signal final : unsigned(rawfrq'range);
    signal order : signed(ord'range);

    constant measureinterval : integer := 2**precision;

    signal bcd : std_logic_vector(bcdfrq'range);

	signal convbusy, convstrobe : std_logic;
begin
    -- The current values of the corrections arrays expect this
    -- given precision
    assert precision = 17 report "Mismatch in precision!" severity error;

    ord <= order;
    bcdfrq <= bcd;
    rawfrq <= final;
    overflow <= divoverflow;

    conv : entity work.hex2bcd
        generic map (
            precision => final'length,
            width => bcd'length,
            bits => 5,
			ndigits => 5 )  -- log2 of precision
        port map (
            hex => final,
            bcd => bcd,
            strobe => bcdstrobe,
            rst => rst,
            clk => clk );

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

    -- Synchronize the reciprocal counter to the 'clk' clock domain
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

	process(clk,rst)
		variable divold : std_logic;
	begin
		if rst = '1' then
			divold := '0';
		elsif rising_edge(clk) then
			if divold = '0' and divbusy = '1' then
				convstrobe <= '1';
			else
				convstrobe <= '0';
			end if;
			divold := divbusy;
		end if;
	end process;

	stage3 : entity work.fpbaseconv
		generic map (
			precision => final'length,
			exp_precision => order'length,
			nscalestages => nscalestages )
		port map (
			mantissa => final,
			exponent => order,
			busy => convbusy,
			scaling => scaling,
			ratio => ratio,
			strobe => convstrobe,
			clk => clk,
			rst => rst );

	process(clk,rst)
		variable convold : std_logic;
	begin
		if rst = '1' then
			convold := '0';
		elsif rising_edge(clk) then
			if convold = '0' and convbusy = '1' then
				bcdstrobe <= '1';
			else
				bcdstrobe <= '0';
			end if;
			convold := convbusy;
		end if;
	end process;

end Behavioral;

