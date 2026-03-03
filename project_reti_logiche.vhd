----------------------------------------------------------------------------------
-- Company: 
-- Engineer: 
-- 
-- Create Date: 03/03/2026 10:02:57 PM
-- Design Name: 
-- Module Name: project_reti_logiche - Behavioral
-- Project Name: 
-- Target Devices: 
-- Tool Versions: 
-- Description: 
-- 
-- Dependencies: 
-- 
-- Revision:
-- Revision 0.01 - File Created
-- Additional Comments:
-- 
----------------------------------------------------------------------------------


library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

-- Uncomment the following library declaration if using
-- arithmetic functions with Signed or Unsigned values
--use IEEE.NUMERIC_STD.ALL;

-- Uncomment the following library declaration if instantiating
-- any Xilinx leaf cells in this code.
--library UNISIM;
--use UNISIM.VComponents.all;

entity project_reti_logiche is
    port (
        i_clk : in std_logic;
        i_rst : in std_logic;
        i_start : in std_logic;
        i_task_id : in std_logic_vector(5 downto 0);
        i_task_priority : in std_logic_vector(1 downto 0);
        i_op : in std_logic_vector(1 downto 0);
        o_done : out std_logic;
        o_task_id : out std_logic_vector(5 downto 0);
        o_mem_addr: out std_logic_vector(15 downto 0);
        i_mem_data : in std_logic_vector(7 downto 0);
        o_mem_data: out std_logic_vector(7 downto 0);
        o_mem_we : out std_logic;
        o_mem_en : out std_logic
    );
end project_reti_logiche;

architecture Behavioral of project_reti_logiche is

type state_type is (RESET, INIT_MEM, IDLE, FETCH_SIZE, DECODE, OP00_CHECK_EMPTY, OP00_READ, OP00_MODIFY,
                    OP01_CHECK_EMPTY, OP01_FORCE_ZERO, OP01_READ_FIRST, OP01_SAVE, OP01_SHIFT_READ, OP01_SHIFT_WRITE, OP01_UPDATE,
                    OP11_CLEAR,
                    OP10_CHECK_EMPTY, OP10_FIND_READ, OP10_FIND_EVAL, OP10_CHECK_SHIFT, OP10_SHIFT_READ, OP10_SHIFT_WRITE, OP10_INSERT, OP10_UPDATE_SIZE,
                    DONE);
    signal current_state, next_state: state_type;

    -- Segnali interni per memorizzare dati temporanei
    signal num_tasks : unsigned(7 downto 0);
    signal current_addr : unsigned(15 downto 0);
    signal target_addr : unsigned(15 downto 0);
    signal extracted_id : std_logic_vector(5 downto 0);
    signal data_buffer : std_logic_vector(7 downto 0);
    signal concatenation : std_logic_vector(7 downto 0);
    
    signal next_num_tasks     : unsigned(7 downto 0);
    signal next_current_addr  : unsigned(15 downto 0);
    signal next_target_addr   : unsigned(15 downto 0);
    signal next_extracted_id  : std_logic_vector(5 downto 0);
    signal next_data_buffer   : std_logic_vector(7 downto 0);

begin

concatenation <= i_task_id & i_task_priority;

--PROCESSO SINCRONO

state_reg: process(i_clk, i_rst)
    begin
        if i_rst = '1' then
            -- Condizione di Reset Asincrono
            current_state <= RESET;
            
            -- Azzeramento di tutti i registri del datapath
            num_tasks <= (others => '0');
            current_addr <= (others => '0');
            target_addr <= (others => '0');
            extracted_id <= (others => '0');
            data_buffer <= (others => '0');
            
        elsif rising_edge(i_clk) then
            -- Aggiornamento sincrono al fronte di salita del clock
            current_state <= next_state;
            
            num_tasks <= next_num_tasks;
            current_addr <= next_current_addr;
            target_addr <= next_target_addr;
            extracted_id <= next_extracted_id;
            data_buffer <= next_data_buffer;
        end if;
    end process;

--PROCESSO COMBINATORIO
fsm_logic: process(current_state, i_start, i_op, i_mem_data, num_tasks, current_addr, target_addr, extracted_id, data_buffer, concatenation)
    begin
        -- Valori di default (mi servono per evitare latch)
        next_state <= current_state;
        next_num_tasks <= num_tasks;
        next_current_addr <= current_addr;
        next_target_addr <= target_addr;
        next_extracted_id <= extracted_id;
        next_data_buffer <= data_buffer;
        
        -- Uscite default
        o_mem_en <= '0';
        o_mem_we <= '0';
        o_mem_addr <= (others => '0');
        o_mem_data <= (others => '0');
        o_done <= '0';
        o_task_id <= extracted_id;

        case current_state is
            when RESET =>
                o_done <= '1';
                next_state <= INIT_MEM;

            when INIT_MEM =>
                o_done <= '1';
                o_mem_en <= '1';
                o_mem_we <= '1';
                o_mem_addr <= (others => '0');
                o_mem_data <= (others => '0');
                next_state <= IDLE;

            when IDLE =>
                if i_start = '1' then
                    next_state <= FETCH_SIZE;
                end if;

            when FETCH_SIZE =>
                o_mem_en <= '1';
                o_mem_addr <= (others => '0');
                next_state <= DECODE;

            when DECODE =>
                next_num_tasks <= unsigned(i_mem_data);
                if i_op = "00" then
                    next_state <= OP00_CHECK_EMPTY; -- Percorso: Modifica Priorità
                elsif i_op = "01" then
                    next_state <= OP01_CHECK_EMPTY; -- Percorso: Rimuovi Primo
                elsif i_op = "10" then
                    next_state <= OP10_CHECK_EMPTY; -- Percorso: Aggiungi Task
                elsif i_op = "11" then
                    next_state <= OP11_CLEAR;       -- Percorso: Svuota Lista
                else
                    next_state <= DONE;
                end if;
            
            -- Implementare qui gli altri stati... @Luca 10 @Riccardo 01

            when DONE =>
                o_done <= '1';
                if i_start = '0' then
                    next_state <= IDLE;
                end if;

            when others =>
                next_state <= RESET;
        end case;
    end process;

end Behavioral;


end Behavioral;
----------------------------------------------------------------------------------
-- Company: 
-- Engineer: 
-- 
-- Create Date: 03/03/2026 10:02:57 PM
-- Design Name: 
-- Module Name: project_reti_logiche - Behavioral
-- Project Name: 
-- Target Devices: 
-- Tool Versions: 
-- Description: 
-- 
-- Dependencies: 
-- 
-- Revision:
-- Revision 0.01 - File Created
-- Additional Comments:
-- 
----------------------------------------------------------------------------------


library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

-- Uncomment the following library declaration if using
-- arithmetic functions with Signed or Unsigned values
--use IEEE.NUMERIC_STD.ALL;

-- Uncomment the following library declaration if instantiating
-- any Xilinx leaf cells in this code.
--library UNISIM;
--use UNISIM.VComponents.all;

entity project_reti_logiche is
    port (
        i_clk : in std_logic;
        i_rst : in std_logic;
        i_start : in std_logic;
        i_task_id : in std_logic_vector(5 downto 0);
        i_task_priority : in std_logic_vector(1 downto 0);
        i_op : in std_logic_vector(1 downto 0);
        o_done : out std_logic;
        o_task_id : out std_logic_vector(5 downto 0);
        o_mem_addr: out std_logic_vector(15 downto 0);
        i_mem_data : in std_logic_vector(7 downto 0);
        o_mem_data: out std_logic_vector(7 downto 0);
        o_mem_we : out std_logic;
        o_mem_en : out std_logic
    );
end project_reti_logiche;

architecture Behavioral of project_reti_logiche is

type state_type is (RESET, INIT_MEM, IDLE, FETCH_SIZE, DECODE, OP00_CHECK_EMPTY, OP00_READ, OP00_MODIFY,
                    OP01_CHECK_EMPTY, OP01_FORCE_ZERO, OP01_READ_FIRST, OP01_SAVE, OP01_SHIFT_READ, OP01_SHIFT_WRITE, OP01_UPDATE,
                    OP11_CLEAR,
                    OP10_CHECK_EMPTY, OP10_FIND_READ, OP10_FIND_EVAL, OP10_CHECK_SHIFT, OP10_SHIFT_READ, OP10_SHIFT_WRITE, OP10_INSERT, OP10_UPDATE_SIZE,
                    DONE);
    signal current_state, next_state: state_type;

    -- Segnali interni per memorizzare dati temporanei
    signal num_tasks : unsigned(7 downto 0);
    signal current_addr : unsigned(15 downto 0);
    signal target_addr : unsigned(15 downto 0);
    signal extracted_id : std_logic_vector(5 downto 0);
    signal data_buffer : std_logic_vector(7 downto 0);
    signal concatenation : std_logic_vector(7 downto 0);
    

begin


end Behavioral;
