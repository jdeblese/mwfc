library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity hex2bcd is
    Generic ( precision : integer;
              width : integer;
              bits : integer );
    Port ( hex : in unsigned (precision-1 downto 0);
           bcd : out STD_LOGIC_VECTOR (width-1 downto 0);
           strobe : in STD_LOGIC;
           rst : in STD_LOGIC;
           clk : in STD_LOGIC );
end hex2bcd;

architecture Behavioral of hex2bcd is
    signal shifter, shifter_next : unsigned (precision+width-1 downto 0);
    signal busy, busy_next : std_logic;
    signal count, count_next : unsigned(bits-1 downto 0);
    signal bcd_int, bcd_next : unsigned(bcd'range);
begin

    bcd <= std_logic_vector(bcd_int);

    process(clk)
    begin
        if rising_edge(clk) then
            if rst = '1' then
                busy <= '0';
            else
                shifter <= shifter_next;
                busy <= busy_next;
                count <= count_next;
                bcd_int <= bcd_next;
            end if;
        end if;
    end process;

    process(hex, strobe, shifter, busy, count, bcd_int)
        variable shifter_new : unsigned (precision+width-1 downto 0);
        variable busy_new : std_logic;
        variable count_new : unsigned(count'range);
        variable a, b, c, d, e : integer;
    begin
        a := shifter_new'high; -- Thousands
        b := a - 4;            -- Hundreds
        c := b - 4;            -- Tens
        d := c - 4;            -- Ones
        e := d - 4;            -- Binary

        shifter_new := shifter;
        busy_new := busy;
        count_new := count;

        bcd_next <= bcd_int;

        if busy /= '1' and strobe = '1' then
            shifter_new := (others => '0');
            shifter_new(hex'range) := hex;
            busy_new := '1';
            count_new := (others => '0');
        end if;

        if count = precision then
            busy_new := '0';
            bcd_next <= shifter(shifter'high downto shifter'high-width+1);
            count_new := (others => '0');
        elsif busy = '1' then
            if shifter_new(a downto b+1) > "0100" then
                shifter_new(a downto b+1) := shifter_new(a downto b+1) + "0011";
            end if;
            if shifter_new(b downto c+1) > "0100" then
                shifter_new(b downto c+1) := shifter_new(b downto c+1) + "0011";
            end if;
            if shifter_new(c downto d+1) > "0100" then
                shifter_new(c downto d+1) := shifter_new(c downto d+1) + "0011";
            end if;
            if shifter_new(d downto e+1) > "0100" then
                shifter_new(d downto e+1) := shifter_new(d downto e+1) + "0011";
            end if;
            shifter_new := shift_left(shifter_new, 1);
            count_new := count + "1";
        end if;

        shifter_next <= shifter_new;
        busy_next <= busy_new;
        count_next <= count_new;
    end process;


end Behavioral;
