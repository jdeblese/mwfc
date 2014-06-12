library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity counter is
    Generic ( Tlen : integer;
              Ilen : integer;
			  measureinterval : integer );
    Port ( timer : in STD_LOGIC;
           input : in STD_LOGIC;
           tcount : out UNSIGNED (Tlen-1 downto 0);
           icount : out UNSIGNED (Ilen-1 downto 0);
--		   overflow : out STD_LOGIC;
           enable : in STD_LOGIC;
		   strobe : out STD_LOGIC;
           rst : in  STD_LOGIC);
end counter;

architecture Behavioral of counter is
    signal input_en, input_en_next : std_logic;
    signal M, icount_int, icount_next : unsigned (icount'range);

    signal timer_en, timer_en_next : std_logic;
    signal N, tcount_int, tcount_next : unsigned (tcount'range);
    
    signal done, done_next : std_logic;

	signal sync_ien : std_logic_vector(1 downto 0);

	signal tover, tover_next, iover, iover_next : std_logic;

	signal strobe_next : std_logic;
begin

    icount <= icount_int;
    tcount <= tcount_int;

--	overflow <= tover or iover;

	process(rst,timer)
	begin
		if rst = '1' then
			sync_ien <= (others => '0');
		elsif rising_edge(timer) then
			sync_ien <= sync_ien(0) & input_en;
		end if;
	end process;

    comb : process(enable, input_en, sync_ien, icount_int, timer_en, tcount_int, done, M, N, tover, iover)
        variable input_en_new, timer_en_new, done_new : std_logic;
		variable tover_new, iover_new : std_logic;
    begin
        input_en_new := input_en;
        timer_en_new := timer_en;
        done_new := done;
        
        tcount_next <= tcount_int;
        icount_next <= icount_int;

		tover_new := tover;
		iover_new := iover;

		strobe_next <= '0';
        
		if timer_en = '1' and N + "1" = "0" then
			tover_new := '1';
		end if;

		if input_en = '1' and M + "1" = "0" then
			iover_new := '1';
		end if;

		-- Start the 'input' counter on its next rising edge, if permitted
		-- DANGER: crosses clock domain
		--     input 'timer_en' and 'done' is in the 'timer' domain
		--     input 'enable' is in an unknown domain
		--     output 'input_en' is in the 'input' domain
        if input_en = '0' and timer_en = '0' and done = '0' then
            input_en_new := '1';
        end if;
        
		-- If the 'input' counter is on, start the 'timer' counter on its
		-- next rising edge, if not already done so
        if sync_ien(1) = '1' then
            timer_en_new := '1';
        end if;
        
		-- Indicate when the minimum measurement interval has been reached
		-- Subtract 2 tics to compensate for the 'input_en' synchronizer
        if N = to_unsigned(measureinterval - 2, N'length) then
            done_new := '1';
        end if;
        
		-- If we've measured long enough, turn off the 'input' counter on
		-- its next rising edge, and latch out the counter value
		-- DANGER: crosses clock domain
		--     input done is in the 'timer' domain
		--     outputs are all in the 'input' domain
		--     impractical to sync to 'input', as 'input' is slow vs 'timer'
		--         if synced, icount >= 3
        if done = '1' and input_en = '1' then
            input_en_new := '0';
            icount_next <= M + "1";
			iover_new := '0';
        end if;
        
		-- If the 'input' counter has been turned off, turn off the 'timer'
		-- counter on its next rising edge and latch out the value
        if timer_en = '1' and sync_ien(1) = '0' then
            timer_en_new := '0';
            tcount_next <= N;
			tover_new := '0';
        end if;
        
		-- If timer_en is off, disable the measurement interval flag
        if done = '1' and sync_ien(1) = '0' and timer_en = '0' then
            done_new := '0';
			strobe_next <= '1';
        end if;
        
        input_en_next <= input_en_new;
        timer_en_next <= timer_en_new;
        done_next <= done_new;
		tover_next <= tover_new;
		iover_next <= iover_new;
    end process;

	-- Processes synchronous to the 'timer' clock
    tmem : process(rst, timer)
    begin
        if rst = '1' then
            timer_en <= '0';
            done <= '0';
            N <= (others => '0');
            tcount_int <= (others => '1');
			tover <= '0';
			strobe <= '0';
        elsif rising_edge(timer) then
            if timer_en = '1' then
                N <= N + "1";
            else
                N <= (others => '0');
            end if;
            timer_en <= timer_en_next;
            done <= done_next;
            tcount_int <= tcount_next;
			tover <= tover_next;
			strobe <= strobe_next;
        end if;
    end process;

	-- Processes synchronous to the 'input' clock
    imem : process(rst, input)
    begin
        if rst = '1' then
            input_en <= '0';
            M <= (others => '0');
            icount_int <= (others => '0');
			iover <= '0';
        elsif rising_edge(input) then
            if input_en = '1' then
                M <= M + "1";
            else
                M <= (others => '0');
            end if;
            input_en <= input_en_next;
            icount_int <= icount_next;
			iover <= iover_next;
        end if;
    end process;

end Behavioral;
