-- ============================================================
-- TESTBENCH CASO LIMITE 1: OP=01 su lista vuota
-- Descrizione: Tentativo di rimozione da lista vuota.
--   RAM[0]=0 (nessun task). Il modulo deve restituire
--   o_task_id = "000000" e lasciare RAM[0] invariato a 0.
-- Perche': La specifica richiede esplicitamente che in caso
--   di lista vuota si restituisca ID_TASK=0 (0x000000).
-- ============================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity project_tb is
end project_tb;

architecture project_tb_arch of project_tb is
    constant CLOCK_PERIOD : time := 20 ns;
    signal tb_clk : std_logic := '0';
    signal tb_rst, tb_start, tb_done : std_logic;
    signal tb_o_task_id : std_logic_vector(5 downto 0);
    signal tb_task_priority, tb_op : std_logic_vector(1 downto 0);
    signal tb_i_task_id : std_logic_vector(5 downto 0);

    signal tb_o_mem_addr, exc_o_mem_addr, init_o_mem_addr : std_logic_vector(15 downto 0);
    signal tb_o_mem_data, exc_o_mem_data, init_o_mem_data : std_logic_vector(7 downto 0);
    signal tb_i_mem_data : std_logic_vector(7 downto 0);
    signal tb_o_mem_we, tb_o_mem_en,
           exc_o_mem_we, exc_o_mem_en,
           init_o_mem_we, init_o_mem_en : std_logic;

    type ram_type is array (65535 downto 0) of std_logic_vector(7 downto 0);
    signal RAM : ram_type := (others => "00000000");

    signal memory_control : std_logic := '0';

    component project_reti_logiche is
        port (
            i_clk           : in  std_logic;
            i_rst           : in  std_logic;
            i_start         : in  std_logic;
            i_task_id       : in  std_logic_vector(5 downto 0);
            i_task_priority : in  std_logic_vector(1 downto 0);
            i_op            : in  std_logic_vector(1 downto 0);
            o_done          : out std_logic;
            o_task_id       : out std_logic_vector(5 downto 0);
            o_mem_addr      : out std_logic_vector(15 downto 0);
            i_mem_data      : in  std_logic_vector(7 downto 0);
            o_mem_data      : out std_logic_vector(7 downto 0);
            o_mem_we        : out std_logic;
            o_mem_en        : out std_logic
        );
    end component project_reti_logiche;

begin
    UUT : project_reti_logiche
        port map (
            i_clk           => tb_clk,
            i_rst           => tb_rst,
            i_start         => tb_start,
            i_task_id       => tb_i_task_id,
            i_task_priority => tb_task_priority,
            i_op            => tb_op,
            o_done          => tb_done,
            o_task_id       => tb_o_task_id,
            o_mem_addr      => exc_o_mem_addr,
            i_mem_data      => tb_i_mem_data,
            o_mem_data      => exc_o_mem_data,
            o_mem_we        => exc_o_mem_we,
            o_mem_en        => exc_o_mem_en
        );

    tb_clk <= not tb_clk after CLOCK_PERIOD / 2;

    MEM : process (tb_clk)
    begin
        if tb_clk'event and tb_clk = '1' then
            if tb_o_mem_en = '1' then
                if tb_o_mem_we = '1' then
                    RAM(to_integer(unsigned(tb_o_mem_addr))) <= tb_o_mem_data after 1 ns;
                    tb_i_mem_data <= tb_o_mem_data after 1 ns;
                else
                    tb_i_mem_data <= RAM(to_integer(unsigned(tb_o_mem_addr))) after 1 ns;
                end if;
            end if;
        end if;
    end process;

    memory_signal_swapper : process (memory_control,
                                      init_o_mem_addr, init_o_mem_data, init_o_mem_en, init_o_mem_we,
                                      exc_o_mem_addr,  exc_o_mem_data,  exc_o_mem_en,  exc_o_mem_we)
    begin
        tb_o_mem_addr <= init_o_mem_addr;
        tb_o_mem_data <= init_o_mem_data;
        tb_o_mem_en   <= init_o_mem_en;
        tb_o_mem_we   <= init_o_mem_we;
        if memory_control = '1' then
            tb_o_mem_addr <= exc_o_mem_addr;
            tb_o_mem_data <= exc_o_mem_data;
            tb_o_mem_en   <= exc_o_mem_en;
            tb_o_mem_we   <= exc_o_mem_we;
        end if;
    end process;

    create_scenario : process
    begin
        wait for 50 ns;
        tb_start <= '0';
        tb_rst   <= '1';
        wait for 100 ns;
        tb_rst   <= '0';
        memory_control <= '1';
        wait until tb_done = '0';

        -- Verifica che dopo il reset RAM[0] = 0
        assert RAM(0) = "00000000"
            report "EDGE1 FALLITO: dopo reset RAM[0] != 0, actual=" &
                   integer'image(to_integer(unsigned(RAM(0))))
            severity failure;

        wait until falling_edge(tb_clk);

        -- STEP 0: OP=01 su lista vuota
        tb_op           <= "01";
        tb_i_task_id    <= "000000";
        tb_task_priority <= "00";
        tb_start        <= '1';

        wait until rising_edge(tb_done);

        -- o_task_id deve essere 000000
        assert tb_o_task_id = "000000"
            report "EDGE1 FALLITO: o_task_id atteso=0, reale=" &
                   integer'image(to_integer(unsigned(tb_o_task_id)))
            severity failure;

        -- RAM[0] deve restare 0 (lista ancora vuota)
        assert RAM(0) = "00000000"
            report "EDGE1 FALLITO: RAM[0] atteso=0, reale=" &
                   integer'image(to_integer(unsigned(RAM(0))))
            severity failure;

        tb_start <= '0';
        wait until falling_edge(tb_done);
        wait until falling_edge(tb_clk);

        report "EDGE1 OK: OP=01 su lista vuota restituisce task_id=0 e RAM[0]=0";
        assert false report "Simulation Ended! EDGE1 PASSATO" severity failure;
    end process;

end architecture;
