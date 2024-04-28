-- cpu.vhd: Simple 8-bit CPU (BrainFuck interpreter)
-- Copyright (C) 2022 Brno University of Technology,
--                    Faculty of Information Technology
-- Author(s): Valentyn Vorobec <xvorob02 AT stud.fit.vutbr.cz>
--
library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_arith.all;
use ieee.std_logic_unsigned.all;

-- ----------------------------------------------------------------------------
--                        Entity declaration
-- ----------------------------------------------------------------------------
entity cpu is
 port (
   CLK   : in std_logic;  -- hodinovy signal
   RESET : in std_logic;  -- asynchronni reset procesoru
   EN    : in std_logic;  -- povoleni cinnosti procesoru
 
   -- synchronni pamet RAM
   DATA_ADDR  : out std_logic_vector(12 downto 0); -- adresa do pameti
   DATA_WDATA : out std_logic_vector(7 downto 0); -- mem[DATA_ADDR] <- DATA_WDATA pokud DATA_EN='1'
   DATA_RDATA : in std_logic_vector(7 downto 0);  -- DATA_RDATA <- ram[DATA_ADDR] pokud DATA_EN='1'
   DATA_RDWR  : out std_logic;                    -- cteni (0) / zapis (1)
   DATA_EN    : out std_logic;                    -- povoleni cinnosti
   
   -- vstupni port
   IN_DATA   : in std_logic_vector(7 downto 0);   -- IN_DATA <- stav klavesnice pokud IN_VLD='1' a IN_REQ='1'
   IN_VLD    : in std_logic;                      -- data platna
   IN_REQ    : out std_logic;                     -- pozadavek na vstup data
   
   -- vystupni port
   OUT_DATA : out  std_logic_vector(7 downto 0);  -- zapisovana data
   OUT_BUSY : in std_logic;                       -- LCD je zaneprazdnen (1), nelze zapisovat
   OUT_WE   : out std_logic                       -- LCD <- OUT_DATA pokud OUT_WE='1' a OUT_BUSY='0'
 );
end cpu;


-- ----------------------------------------------------------------------------
--                      Architecture declaration
-- ----------------------------------------------------------------------------
architecture behavioral of cpu is
  type FSMstate is (
    s_start,
    s_fetch,
    s_decode,
    s_ptr_inc,
    s_ptr_dec,
    s_val_inc,
    s_val_dec,
    s_val_inc_mx,
    s_val_dec_mx,
    s_val_print,
    s_val_save,
    s_while_open,
    s_while_open1,
    s_while_close,
    s_while_close1,
    s_dowhile_open,
    s_dowhile_open1,
    s_dowhile_close,
    s_dowhile_close1,
    s_null,
    HALT
  );

  type InstType is (
    i_ptr_inc,
    i_ptr_dec,
    i_val_inc,
    i_val_dec,
    i_val_print,
    i_val_save,
    i_while_open,
    i_while_close,
    i_dowhile_open,
    i_dowhile_close,
    i_null,
    i_halt
  );

  signal pstate : FSMstate := s_start;
  signal nstate : FSMstate;

  signal reg_pc: std_logic_vector(12 downto 0) := "0000000000000";
  signal reg_ptr: std_logic_vector(12 downto 0) := "1000000000000";
  signal reg_cnt: std_logic_vector(7 downto 0) := "00000000";

  signal reg_pc_inc: std_logic;
  signal reg_pc_dec: std_logic;
  signal reg_ptr_inc: std_logic;
  signal reg_ptr_dec: std_logic;
  signal reg_cnt_inc: std_logic;
  signal reg_cnt_dec: std_logic;
  signal reg_dec: InstType;

  signal mx1_sel: std_logic;
  signal mx2_sel: std_logic_vector (1 downto 0);

begin
  mx1_process: process(mx1_sel, reg_pc, reg_ptr)
  begin
    if mx1_sel = '0' then
      DATA_ADDR <= reg_pc;
    elsif mx1_sel = '1' then
      DATA_ADDR <= reg_ptr;
    end if; 
  end process;
  
 mx2_process: process(DATA_RDATA, IN_DATA, mx2_sel)
  begin
    case mx2_sel is 
      when "00" => DATA_WDATA <= IN_DATA;
      when "01" => DATA_WDATA <= DATA_RDATA + 1;
      when "10" => DATA_WDATA <= DATA_RDATA - 1;
      when others => DATA_WDATA <= (others => '0');
    end case;
  end process;

  cnt_process: process(CLK, RESET, reg_cnt_inc, reg_cnt_dec)
  begin
    if RESET = '1' then
      reg_cnt <= (others => '0');
    elsif rising_edge(CLK) then
      if reg_cnt_inc = '1' then
        reg_cnt <= reg_cnt + 1;
      elsif reg_cnt_dec = '1' then
        reg_cnt <= reg_cnt - 1;
      end if;
    end if;
  end process;

  pc_process: process(CLK, RESET, reg_pc_inc, reg_pc_dec)
  begin
    if RESET = '1' then
      reg_pc <= (others => '0');
    elsif rising_edge(CLK) then
      if reg_pc_inc = '1' then
        reg_pc <= reg_pc + 1;
      elsif reg_pc_dec = '1' then
        reg_pc <= reg_pc - 1;
      end if;
    end if;
  end process;

  ptr_process: process(CLK, RESET, reg_ptr_inc, reg_ptr_dec)
  begin
    if RESET = '1' then
      reg_ptr <= "1000000000000";
    elsif rising_edge(CLK) then
      if reg_ptr_inc = '1' then
        reg_ptr <= reg_ptr + 1;
      elsif reg_ptr_dec = '1' then
        reg_ptr <= reg_ptr - 1;
      end if;
    end if;
  end process;

  dec_process: process(DATA_RDATA)
  begin
    case DATA_RDATA is
      when X"3E" =>             -- 0x3E >
        reg_dec <= i_ptr_inc;
      when X"3C" =>             -- 0x3C <
        reg_dec <= i_ptr_dec;
      when X"2B" =>             -- 0x2B +
        reg_dec <= i_val_inc;
      when X"2D" =>             -- 0x2D -
        reg_dec <= i_val_dec;
      when X"2E" =>             -- 0x2E .
        reg_dec <= i_val_print;
      when X"2C" =>             -- 0x2C ,
        reg_dec <= i_val_save;
      when X"5B" =>             -- 0x5B [
        reg_dec <= i_while_open;
      when X"5D" =>             -- 0x5D ]
        reg_dec <= i_while_close;
      when X"28" =>             -- 0x28 )
        reg_dec <= i_dowhile_open;
      when X"29" =>             -- 0x29 )
        reg_dec <= i_dowhile_close;
      when X"00" =>             -- 0x00 null
        reg_dec <= i_halt;
      when others =>            -- comments 
        reg_dec <= i_null;
    end case;
  end process;

  state_logic: process(CLK, RESET, EN) is
  begin
    if RESET = '1' then
      pstate <= s_start;
    elsif rising_edge(CLK) then
      if EN = '1' then
        pstate <= nstate;
      end if;
    end if;
  end process;

  FSM: process(OUT_BUSY, IN_VLD, DATA_RDATA, pstate, reg_dec) is
  begin

    reg_pc_inc <= '0'; 
    reg_pc_dec <= '0';
    reg_ptr_inc <= '0'; 
    reg_ptr_dec <= '0';
    reg_cnt_inc <= '0'; 
    reg_cnt_dec <= '0';

    mx1_sel <= '0';
    mx2_sel <= "00";

    DATA_RDWR <= '0';
    DATA_EN <= '0';
    IN_REQ <= '0';
    OUT_DATA <= (others => '0');
    OUT_WE <= '0';
  
    case pstate is
      -- STATE START
      when s_start => 
        nstate <= s_fetch;

      -- STATE FETCH
      when s_fetch => 
        DATA_EN <= '1';
        nstate <= s_decode;

      -- STATE DECODE
      when s_decode => 
        case reg_dec is 
          when i_ptr_inc =>
            DATA_EN <= '1';
            reg_pc_inc <= '1';
            reg_ptr_inc <= '1';
            nstate <= s_fetch;
          when i_ptr_dec =>
            DATA_EN <= '1';
            reg_pc_inc <= '1';
            reg_ptr_dec <= '1';
            nstate <= s_fetch;
          when i_val_inc =>
            DATA_EN <= '1';
            mx1_sel <= '1';
            nstate <= s_val_inc_mx;
          when i_val_dec =>
            DATA_EN <= '1';
            mx1_sel <= '1';
            nstate <= s_val_dec_mx;
          when i_val_print =>
            DATA_EN <= '1';
            mx1_sel <= '1';
            nstate <= s_val_print;
          when i_val_save =>
            IN_REQ <= '1';
            DATA_EN <= '1';
            mx1_sel <= '1';
            nstate <= s_val_save; 
          when i_while_open =>
            DATA_EN <= '1';
            mx1_sel <= '1';
            reg_pc_inc <= '1';
            nstate <= s_while_open;
          when i_while_close =>
            nstate <= s_while_close;
          when i_dowhile_open =>
            reg_pc_inc <= '1';
            nstate <= s_fetch;
          when i_dowhile_close =>
            DATA_EN <= '1';
            mx1_sel <= '1';
            reg_pc_inc <= '1';
            nstate <= s_dowhile_close;
          when i_halt => 
            nstate <= HALT;
          when others => 
            reg_pc_inc <= '1';
            nstate <= s_fetch;
        end case;
      
        when HALT => 
          reg_pc_inc <= '1';
          nstate <= s_fetch;
        when s_dowhile_close =>
          if DATA_RDATA = "00000000" then
            reg_pc_inc <= '1';
            nstate <= s_fetch;
          else 
            DATA_EN <= '1';
            reg_pc_dec <= '1';
            nstate <= s_dowhile_close1;
          end if;
  
        when s_dowhile_close1 =>
          if reg_dec = i_dowhile_open then
            reg_pc_inc <= '1';
            nstate <= s_fetch;
          else
            DATA_EN <= '1';
            reg_pc_dec <= '1';
            nstate <= s_dowhile_close1;
          end if;

      -- STATE INCREASE VALUE
      when s_val_inc_mx =>
        DATA_EN <= '1';
        DATA_RDWR <= '1';
        mx1_sel <= '1';
        mx2_sel <= "01";
        reg_pc_inc <= '1';
        nstate <= s_fetch;

      -- STATE DECREASE VALUE
      when s_val_dec_mx =>
        DATA_EN <= '1';
        DATA_RDWR <= '1';
        mx1_sel <= '1';
        mx2_sel <= "10";
        reg_pc_inc <= '1';
        nstate <= s_fetch;

      -- STATE PRINT VALUE
      when s_val_print =>
        if OUT_BUSY = '1' then
          DATA_EN <= '1';
          mx1_sel <= '1';
          nstate <= s_val_print;
        else
          OUT_WE <= '1';
          OUT_DATA <= DATA_RDATA;
          mx1_sel <= '1';
          reg_pc_inc <= '1';
          nstate <= s_fetch;
        end if;

      -- STATE SAVE VALUE
      when s_val_save =>
        if IN_VLD = '1' then
          DATA_EN <= '1';
          DATA_RDWR <= '1';
          mx1_sel <= '1';
          reg_pc_inc <= '1';
          nstate <=s_fetch;
        else
          IN_REQ <= '1';
          DATA_EN <= '1';
          mx1_sel <= '1';
          nstate <= s_val_save;
        end if;
        
      when s_while_open =>
        if DATA_RDATA = "00000000" then
          DATA_EN <= '1';
          reg_cnt_inc <= '1';
          nstate <= s_while_open1;
        else 
          nstate <= s_fetch;
        end if;

      when s_while_open1 =>
        if reg_dec = i_while_close then
          nstate <= s_fetch;
        else
          DATA_EN <= '1';
          reg_pc_inc <= '1';
          nstate <= s_while_open1;
        end if;

      when s_while_close =>
      if DATA_RDATA = "00000000" then
        reg_pc_inc <= '1';
        nstate <= s_fetch;
      else 
        DATA_EN <= '1';
        reg_pc_dec <= '1';
        nstate <= s_while_close1;
      end if;

      when s_while_close1 =>
        if reg_dec = i_while_open then
          reg_pc_inc <= '1';
          nstate <= s_fetch;
        else
          DATA_EN <= '1';
          reg_pc_dec <= '1';
          nstate <= s_while_close1;
        end if;
      when others =>
        nstate <= s_fetch;
    end case;
  end process;
end behavioral;

