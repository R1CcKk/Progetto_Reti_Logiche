-- ============================================================
-- TESTBENCH CASO LIMITE 9: Reset asincrono durante un'operazione
-- Descrizione: Si avvia un'operazione OP=10 (insert), poi si
--   genera un reset asincrono MENTRE l'operazione e' in corso.
--   Il modulo deve:
--   1. Interrompere l'operazione e tornare allo stato iniziale
--   2. Scrivere 0 in RAM[0]
--   3. Portare DONE=1 durante l'init, poi DONE=0
--   4. Essere pronto a ricevere nuove operazioni
--   Si verifica poi che un'operazione successiva funzioni correttamente.
-- Perche': Il reset e' asincrono e puo' arrivare in qualsiasi
--   momento. La FSM deve gestirlo senza corrompere lo stato.
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

        -- === RESET INIZIALE ===
        tb_start <= '0';
        tb_rst   <= '1';
        wait for 100 ns;
        tb_rst   <= '0';
        memory_control <= '1';
        wait until tb_done = '0';

        assert RAM(0) = "00000000"
            report "EDGE9 FALLITO: dopo primo reset RAM[0] != 0" severity failure;

        wait until falling_edge(tb_clk);

        -- === AVVIO OPERAZIONE OP=10 ===
        tb_op            <= "10";
        tb_i_task_id     <= "011001"; -- ID=25
        tb_task_priority <= "01";
        tb_start         <= '1';

        -- Aspetta solo 1 ciclo di clock (operazione non completata)
        wait until rising_edge(tb_clk);
        wait for 5 ns; -- Metà del clock period, siamo durante l'operazione

        -- === RESET ASINCRONO DURANTE L'OPERAZIONE ===
        tb_rst <= '1';
        wait for 30 ns;  -- Reset asserted per 1.5 cicli circa
        tb_rst <= '0';
        tb_start <= '0';

        -- Aspetta che il modulo completi l'inizializzazione post-reset
        wait until tb_done = '0';

        -- Verifica che RAM[0] sia stato riscritto a 0 dal reset
        assert RAM(0) = "00000000"
            report "EDGE9 FALLITO: dopo reset asincrono RAM[0] != 0, reale=" &
                   integer'image(to_integer(unsigned(RAM(0))))
            severity failure;

        wait until falling_edge(tb_clk);

        -- === OPERAZIONE DOPO IL RESET: deve funzionare normalmente ===
        -- Insert ID=30 P=2
        tb_op            <= "10";
        tb_i_task_id     <= "011110"; -- ID=30
        tb_task_priority <= "10";
        tb_start         <= '1';

        wait until rising_edge(tb_done);

        -- RAM[0]=1, RAM[1]=ID=30|P=2 = 01111010
        assert RAM(0) = "00000001"
            report "EDGE9 FALLITO: dopo reset+insert RAM[0] atteso=1, reale=" &
                   integer'image(to_integer(unsigned(RAM(0))))
            severity failure;

        assert RAM(1) = "01111010"
            report "EDGE9 FALLITO: dopo reset+insert RAM[1] atteso=0x7A (ID=30,P=2), reale=" &
                   integer'image(to_integer(unsigned(RAM(1))))
            severity failure;

        tb_start <= '0';
        wait until falling_edge(tb_done);
        wait until falling_edge(tb_clk);

        report "EDGE9 OK: reset asincrono durante op gestito correttamente";
        assert false report "Simulation Ended! EDGE9 PASSATO" severity failure;
    end process;

end architecture;
