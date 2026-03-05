library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity project_reti_logiche is
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
end project_reti_logiche;

architecture Behavioral of project_reti_logiche is

    type state_type is (
        S_RESET,
        S_IDLE,
        S_FETCH_SIZE,
        S_DECODE,
        -- OP00
        S_OP00_READ,
        S_OP00_MODIFY,
        -- OP01
        S_OP01_READ_FIRST,
        S_OP01_SAVE,
        S_OP01_SHIFT_READ,
        S_OP01_SHIFT_WRITE,
        S_OP01_UPDATE,
        -- OP10
        S_OP10_FIND_READ,
        S_OP10_FIND_EVAL,
        S_OP10_SHIFT_READ,
        S_OP10_SHIFT_WRITE,
        S_OP10_INSERT,
        S_OP10_UPDATE_SIZE,
        -- OP11
        S_OP11_CLEAR,
        -- Stato di attesa: garantisce che l'ultima scrittura in RAM
        -- sia completata prima di alzare o_done.
        -- PERCHÉ: o_done è combinatorio su current_state. Se andassimo
        -- direttamente in S_DONE dallo stato di scrittura finale,
        -- o_done diventerebbe 1 pochi ns dopo il fronte che ha anche
        -- scatenato la scrittura della RAM. Il TB cattura rising_edge(o_done)
        -- e controlla RAM prima che la RAM abbia finito di aggiornarsi.
        -- Con S_WAIT_DONE ci passa un intero ciclo di clock: la RAM è
        -- sicuramente aggiornata quando il ciclo successivo porta in S_DONE.
        S_WAIT_DONE,
        S_DONE
    );

    signal current_state : state_type;
    signal next_state    : state_type;

    signal num_tasks    : unsigned(7 downto 0);
    signal current_addr : unsigned(15 downto 0);
    signal target_addr  : unsigned(15 downto 0);
    signal extracted_id : std_logic_vector(5 downto 0);

    signal next_num_tasks    : unsigned(7 downto 0);
    signal next_current_addr : unsigned(15 downto 0);
    signal next_target_addr  : unsigned(15 downto 0);
    signal next_extracted_id : std_logic_vector(5 downto 0);

begin

    state_reg: process(i_clk, i_rst)
    begin
        if i_rst = '1' then
            current_state <= S_RESET;
        elsif rising_edge(i_clk) then
            current_state <= next_state;
        end if;
    end process;

    datapath_regs: process(i_clk, i_rst)
    begin
        if i_rst = '1' then
            num_tasks    <= (others => '0');
            current_addr <= (others => '0');
            target_addr  <= (others => '0');
            extracted_id <= (others => '0');
        elsif rising_edge(i_clk) then
            num_tasks    <= next_num_tasks;
            current_addr <= next_current_addr;
            target_addr  <= next_target_addr;
            extracted_id <= next_extracted_id;
        end if;
    end process;

    comb: process(current_state, i_start, i_op,
                  i_task_id, i_task_priority,
                  num_tasks, current_addr, target_addr,
                  extracted_id, i_mem_data)
    begin
        -- Default: mantieni stato e registri, uscite inattive
        next_state        <= current_state;
        next_num_tasks    <= num_tasks;
        next_current_addr <= current_addr;
        next_target_addr  <= target_addr;
        next_extracted_id <= extracted_id;

        o_done     <= '0';
        o_task_id  <= extracted_id;
        o_mem_en   <= '0';
        o_mem_we   <= '0';
        o_mem_addr <= (others => '0');
        o_mem_data <= (others => '0');

        case current_state is

            -- =======================================================
            -- RESET: emette scrittura 0 in addr 0, DONE=1.
            -- La RAM campiona questa scrittura sul fronte che ci porta
            -- fuori da S_RESET, quindi addr 0 sarà 0 da subito.
            -- =======================================================
            when S_RESET =>
                o_done         <= '1';
                o_mem_en       <= '1';
                o_mem_we       <= '1';
                o_mem_addr     <= (others => '0');
                o_mem_data     <= (others => '0');
                next_num_tasks <= (others => '0');
                next_state     <= S_IDLE;

            -- =======================================================
            -- IDLE: attende i_start. DONE=0.
            -- =======================================================
            when S_IDLE =>
                if i_start = '1' then
                    next_state <= S_FETCH_SIZE;
                end if;

            -- =======================================================
            -- FETCH: legge addr 0 (num_tasks).
            -- Ciclo T: emette richiesta.
            -- Ciclo T+1 (S_DECODE): i_mem_data è stabile.
            -- =======================================================
            when S_FETCH_SIZE =>
                o_mem_en   <= '1';
                o_mem_we   <= '0';
                o_mem_addr <= (others => '0');
                next_state <= S_DECODE;

            -- =======================================================
            -- DECODE: i_mem_data = num_tasks (dato stabile da RAM).
            -- Decide l'operazione e gestisce subito il caso lista vuota.
            -- PERCHÉ qui e non in uno stato CHECK_EMPTY separato:
            -- i_mem_data è già disponibile, aggiungere uno stato
            -- intermedio spreca un ciclo senza fare nulla.
            -- =======================================================
            when S_DECODE =>
                next_num_tasks    <= unsigned(i_mem_data);
                next_current_addr <= to_unsigned(1, 16);
                next_target_addr  <= (others => '0');
                next_extracted_id <= (others => '0');

                if i_op = "00" then
                    -- Lista vuota: niente da modificare
                    if unsigned(i_mem_data) = 0 then
                        next_state <= S_DONE;
                    else
                        next_state <= S_OP00_READ;
                    end if;

                elsif i_op = "01" then
                    -- Lista vuota: extracted_id rimane 0 (default), uscita 0
                    if unsigned(i_mem_data) = 0 then
                        next_state <= S_DONE;
                    else
                        next_state <= S_OP01_READ_FIRST;
                    end if;

                elsif i_op = "10" then
                    if unsigned(i_mem_data) = 0 then
                        -- Lista vuota: inserimento diretto in addr 1,
                        -- nessuna ricerca della posizione necessaria.
                        next_target_addr <= to_unsigned(1, 16);
                        next_state       <= S_OP10_INSERT;
                    else
                        next_state <= S_OP10_FIND_READ;
                    end if;

                elsif i_op = "11" then
                    next_state <= S_OP11_CLEAR;

                else
                    next_state <= S_DONE;
                end if;

            -- =======================================================
            -- OP00: incrementa valore di priorità (satura a 3).
            -- Scansione da addr 1 a addr num_tasks.
            -- =======================================================
            when S_OP00_READ =>
                -- Ciclo T: richiesta lettura indirizzo corrente
                o_mem_en   <= '1';
                o_mem_we   <= '0';
                o_mem_addr <= std_logic_vector(current_addr);
                next_state <= S_OP00_MODIFY;

            when S_OP00_MODIFY =>
                -- Ciclo T+1: i_mem_data = byte del task corrente
                -- Scrittura immediata del valore modificato
                o_mem_en   <= '1';
                o_mem_we   <= '1';
                o_mem_addr <= std_logic_vector(current_addr);
                if i_mem_data(1 downto 0) = "11" then
                    o_mem_data <= i_mem_data(7 downto 2) & "11";
                else
                    o_mem_data <= i_mem_data(7 downto 2) &
                                  std_logic_vector(unsigned(i_mem_data(1 downto 0)) + 1);
                end if;
                next_current_addr <= current_addr + 1;
                -- PERCHÉ "=": current_addr va esattamente da 1 a num_tasks.
                -- Con ">=", termineremmo un ciclo prima dell'ultimo task.
                if current_addr = resize(num_tasks, 16) then
                    next_state <= S_WAIT_DONE;  -- ultima scrittura: aspetta un ciclo
                else
                    next_state <= S_OP00_READ;
                end if;

            -- =======================================================
            -- OP01: rimuovi primo task, shifta lista, decrementa count.
            -- =======================================================
            when S_OP01_READ_FIRST =>
                o_mem_en   <= '1';
                o_mem_we   <= '0';
                o_mem_addr <= std_logic_vector(to_unsigned(1, 16));
                next_state <= S_OP01_SAVE;

            when S_OP01_SAVE =>
                -- i_mem_data = primo task [ID_TASK(7:2) | PRIORITY(1:0)]
                next_extracted_id <= i_mem_data(7 downto 2);
                next_current_addr <= to_unsigned(2, 16);
                if num_tasks = 1 then
                    -- Un solo task: niente shift, aggiorna solo il contatore
                    next_state <= S_OP01_UPDATE;
                else
                    next_state <= S_OP01_SHIFT_READ;
                end if;

            when S_OP01_SHIFT_READ =>
                -- Leggi addr[i], lo scriveremo in addr[i-1]
                o_mem_en   <= '1';
                o_mem_we   <= '0';
                o_mem_addr <= std_logic_vector(current_addr);
                next_state <= S_OP01_SHIFT_WRITE;

            when S_OP01_SHIFT_WRITE =>
                -- i_mem_data = contenuto di addr[i], scrivi in addr[i-1]
                o_mem_en   <= '1';
                o_mem_we   <= '1';
                o_mem_addr <= std_logic_vector(current_addr - 1);
                o_mem_data <= i_mem_data;
                next_current_addr <= current_addr + 1;
                if current_addr = resize(num_tasks, 16) then
                    next_state <= S_OP01_UPDATE;
                else
                    next_state <= S_OP01_SHIFT_READ;
                end if;

            when S_OP01_UPDATE =>
                o_mem_en       <= '1';
                o_mem_we       <= '1';
                o_mem_addr     <= (others => '0');
                o_mem_data     <= std_logic_vector(num_tasks - 1);
                next_num_tasks <= num_tasks - 1;
                next_state     <= S_WAIT_DONE;

            -- =======================================================
            -- OP10: inserisci nuovo task mantenendo l'ordinamento.
            -- Trova la prima posizione in cui la priorità esistente
            -- è STRETTAMENTE MAGGIORE di quella del nuovo task.
            -- Il nuovo task va DOPO quelli con pari priorità (in coda).
            -- =======================================================
            when S_OP10_FIND_READ =>
                o_mem_en   <= '1';
                o_mem_we   <= '0';
                o_mem_addr <= std_logic_vector(current_addr);
                next_state <= S_OP10_FIND_EVAL;

            when S_OP10_FIND_EVAL =>
                -- PERCHÉ ">=" invece di "=" per il controllo sull'ultimo task:
                -- difensivo contro qualsiasi caso in cui current_addr
                -- potesse superare num_tasks (prevenzione loop infinito).
                if i_mem_data(1 downto 0) > i_task_priority then
                    -- Priorità peggiore trovata: inserimento qui, shift necessario
                    next_target_addr  <= current_addr;
                    next_current_addr <= resize(num_tasks, 16);
                    next_state        <= S_OP10_SHIFT_READ;
                elsif current_addr >= resize(num_tasks, 16) then
                    -- Ultimo task raggiunto, priorità <=: inserimento in coda
                    -- Non serve shift: la nuova posizione è num_tasks + 1
                    next_target_addr <= resize(num_tasks, 16) + 1;
                    next_state       <= S_OP10_INSERT;
                else
                    next_current_addr <= current_addr + 1;
                    next_state        <= S_OP10_FIND_READ;
                end if;

            when S_OP10_SHIFT_READ =>
                -- Leggi addr[i] per spostarlo in addr[i+1] (shift a destra)
                o_mem_en   <= '1';
                o_mem_we   <= '0';
                o_mem_addr <= std_logic_vector(current_addr);
                next_state <= S_OP10_SHIFT_WRITE;

            when S_OP10_SHIFT_WRITE =>
                -- Scrivi i_mem_data in addr[i+1]
                o_mem_en   <= '1';
                o_mem_we   <= '1';
                o_mem_addr <= std_logic_vector(current_addr + 1);
                o_mem_data <= i_mem_data;
                if current_addr = target_addr then
                    -- Abbiamo shiftato fino alla posizione target: inserisci
                    next_state <= S_OP10_INSERT;
                else
                    next_current_addr <= current_addr - 1;
                    next_state        <= S_OP10_SHIFT_READ;
                end if;

            when S_OP10_INSERT =>
                o_mem_en   <= '1';
                o_mem_we   <= '1';
                o_mem_addr <= std_logic_vector(target_addr);
                o_mem_data <= i_task_id & i_task_priority;
                next_state <= S_OP10_UPDATE_SIZE;

            when S_OP10_UPDATE_SIZE =>
                o_mem_en       <= '1';
                o_mem_we       <= '1';
                o_mem_addr     <= (others => '0');
                o_mem_data     <= std_logic_vector(num_tasks + 1);
                next_num_tasks <= num_tasks + 1;
                next_state     <= S_WAIT_DONE;

            -- =======================================================
            -- OP11: svuota la lista (scrive 0 in addr 0).
            -- =======================================================
            when S_OP11_CLEAR =>
                o_mem_en       <= '1';
                o_mem_we       <= '1';
                o_mem_addr     <= (others => '0');
                o_mem_data     <= (others => '0');
                next_num_tasks <= (others => '0');
                next_state     <= S_WAIT_DONE;

            -- =======================================================
            -- WAIT_DONE: ciclo vuoto tra ultima scrittura e o_done.
            -- Garantisce che la RAM abbia completato l'aggiornamento
            -- prima che il TB veda rising_edge(o_done).
            -- =======================================================
            when S_WAIT_DONE =>
                next_state <= S_DONE;

            -- =======================================================
            -- DONE: segnala completamento, attende abbassamento di START.
            -- =======================================================
            when S_DONE =>
                o_done    <= '1';
                o_task_id <= extracted_id;
                if i_start = '0' then
                    next_state <= S_IDLE;
                end if;

            when others =>
                next_state <= S_RESET;

        end case;
    end process;

end Behavioral;
