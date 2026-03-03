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
