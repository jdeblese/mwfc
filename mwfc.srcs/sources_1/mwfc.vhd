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

    signal baseconvstrobe : std_logic;

    signal final : unsigned(rawfrq'range);
    signal order : signed(ord'range);

    constant measureinterval : integer := 2**precision;
    type A is array (0 to 35) of integer;
    constant digits : A := (
        0, 0, 0, 0,
        1, 1, 1,     -- 2^4 to 2^6
        2, 2, 2,     -- 2^7 to 2^9
        3, 3, 3, 3,  -- 2^10 to 2^13
        4, 4, 4,     -- 2^14 to 2^16
        5, 5, 5,     -- 2^17 to 2^19
        6, 6, 6, 6,  -- 2^20 to 2^23
        7, 7, 7,     -- 2^24 to 2^26
        8, 8, 8,     -- 2^27 to 2^29
        9, 9, 9, 9,  -- 2^30 to 2^33
        10, 10 );    -- 2^34 to 2^35
    type B is array(0 to 35) of unsigned(precision + 2 downto 0);
    constant corrections : B := (
        x"00000", x"80000", x"40000", x"20000",
        x"A0000", x"50000", x"28000",
        x"C8000", x"64000", x"32000",
        x"FA000", x"7D000", x"3E800", x"1F400",
        x"9C400", x"4E200", x"27100",
        x"C3500", x"61A80", x"30D40",
        x"F4240", x"7A120", x"3D090", x"1E848",
        x"98968", x"4C4B4", x"2625A",
        x"BEBC2", x"5F5E1", x"2FAF1",
        x"EE6B3", x"77359", x"3B9AD", x"1DCD6",
        x"95030", x"4A818" );

    signal bcd : std_logic_vector(bcdfrq'range);
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
            strobe => baseconvstrobe,
            rst => rst,
            clk => clk );

	process(clk,rst)
        variable C0 : unsigned(corrections(0)'range);
		variable S0 : integer;
		variable F1, F2, F3 : unsigned(ratio'length + corrections(0)'length - 1 downto 0);
        variable O1, O2 : signed(order'range);
        variable divstate : std_logic;
        variable bcstrobe : std_logic_vector(3 downto 0);  -- 4-stage pipeline
	begin
        if rst = '1' then
            S0 := 0;
            C0 := (others => '0');
            divstate := '0';
            bcstrobe := (others => '0');
            baseconvstrobe <= '0';
        elsif rising_edge(clk) then
            -- Pipeline stage 3
            --   Shift and round the final value
			if divoverflow = '0' then
				F3 := shift_right(F2, 4);
				-- Round based on highest truncated bit
                if F2(0) = '1' then
					final <= F3(final'high+1 downto 1) + "1";
				else
					final <= F3(final'high+1 downto 1);
				end if;
			end if;
            order <= O2;

            -- Pipeline stage 2
            --   Check if an additional scaling factor is needed
			if divoverflow = '0' then
                -- This comparison will give a warning at the start of a simulation due to F1 being unknown
				if F1 < shift_left(to_unsigned(1000, F1'length),5) then
                    -- Five bits, because four bits precision + 1 rounding
                    -- Multiply by 10 (8 + 2)
					F2 := shift_left(F1,1) + shift_left(F1,3);
					O2 := O1 - 1;
                else
                    F2 := F1;
                    O2 := O1;
				end if;
			end if;

            -- Pipeline stage 1
            --   Compute the base-10 exponent and mantissa
            O1 := to_signed(8, order'length) - digits(S0);  -- Get fp base-10 exponent
			if divoverflow = '0' then
                -- the values in 'corrections' are shifted up precision+3 bits
                -- Multiply is a slow operation
				F1 := shift_right(ratio * C0, precision + 3 - 1 - 4);
            end if;

            -- Pipeline stage 0
            --   Look up certain values
            S0 := -to_integer(scaling);  -- Floating-point base-2 exponent
            C0 := corrections(S0);

            -- Misc.
            if divstate = '1' and divbusy = '0' then
                bcstrobe := bcstrobe(bcstrobe'high-1 downto 0) & '1';
            else
                bcstrobe := bcstrobe(bcstrobe'high-1 downto 0) & '0';
            end if;
            divstate := divbusy;
            baseconvstrobe <= bcstrobe(bcstrobe'high);
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

end Behavioral;

