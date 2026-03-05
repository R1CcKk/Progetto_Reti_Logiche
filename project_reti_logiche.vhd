library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

-- ============================================================================
-- MODULO: project_reti_logiche
-- Gestisce una lista ordinata di task memorizzata su RAM esterna.
-- Ogni task è un byte: [ID_TASK(7:2) | PRIORITY(1:0)]
-- La RAM è organizzata come:
--   addr 0        → numero di task presenti nella lista (0 = lista vuota)
--   addr 1..N     → task ordinati per priorità crescente (0=max, 3=min)
--
-- Protocollo handshake START-DONE:
--   1. Logica esterna pone i_start='1' con i_op (e i_task_id/i_task_priority) stabili
--   2. Il modulo esegue l'operazione
--   3. Il modulo pone o_done='1' a operazione completata
--   4. La logica esterna abbassa i_start
--   5. Il modulo abbassa o_done e torna pronto
-- ============================================================================
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

    -- =========================================================================
    -- TIPO ENUMERATO: stati della FSM
    -- Ogni stato corrisponde a un ciclo di clock in cui la logica combinatoria
    -- produce un set preciso di uscite e di valori next_*.
    -- =========================================================================
    type state_type is (
        S_RESET,        -- post-reset: scrive 0 in addr 0, DONE=1
        S_IDLE,         -- attende i_start='1'
        S_LOAD_COUNT,   -- ciclo T: emette richiesta lettura addr 0
        S_DECODE,       -- ciclo T+1: legge num_tasks da i_mem_data, decide operazione
        -- OP00: incrementa valore numerico di priorità (satura a 3 = priorità minima)
        S_OP00_READ,    -- ciclo T: richiesta lettura task corrente
        S_OP00_MODIFY,  -- ciclo T+1: legge e riscrive con priorità incrementata
        -- OP01: rimuovi primo task (addr 1), shifta lista, decrementa contatore
        S_OP01_READ_FIRST,  -- legge addr 1 (il task da estrarre)
        S_OP01_SAVE,        -- salva ID estratto, prepara lo shift
        S_OP01_SHIFT_READ,  -- legge addr[i] per copiarlo in addr[i-1]
        S_OP01_SHIFT_WRITE, -- scrive i_mem_data in addr[i-1], avanza
        S_OP01_UPDATE,      -- decrementa num_tasks in addr 0
        -- OP10: inserisci nuovo task mantenendo ordinamento per priorità
        S_OP10_FIND_READ,   -- legge task a current_addr per confronto priorità
        S_OP10_COMPARE,   -- decide: inserisci qui, in coda, o avanza
        S_OP10_SHIFT_READ,  -- legge addr[i] per spostarlo in addr[i+1] (shift destra)
        S_OP10_SHIFT_WRITE, -- scrive i_mem_data in addr[i+1], decrementa
        S_OP10_INSERT,      -- scrive il nuovo task in target_addr
        S_OP10_UPDATE_SIZE, -- incrementa num_tasks in addr 0
        -- OP11: svuota lista
        S_OP11_CLEAR,   -- scrive 0 in addr 0
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
        S_DONE          -- o_done=1, attende i_start='0' per tornare in IDLE
    );

    -- Registro di stato (Q del flip-flop di stato)
    signal current_state : state_type;
    -- Ingresso del flip-flop di stato (calcolato dalla logica combinatoria)
    signal next_state    : state_type;

    -- =========================================================================
    -- REGISTRI DEL DATAPATH
    -- Ogni segnale "xxx" è il valore attuale (Q del flip-flop).
    -- Ogni segnale "next_xxx" è il valore futuro (D del flip-flop),
    -- calcolato dalla logica combinatoria e caricato al fronte di clock successivo.
    --
    -- PERCHÉ questa separazione: in VHDL, aggiornare un segnale dentro un processo
    -- non lo rende disponibile immediatamente. Il nuovo valore è visibile solo
    -- al ciclo successivo. Usare next_* rende esplicita questa distinzione e
    -- previene errori in cui si legge un valore credendolo aggiornato.
    -- =========================================================================

    -- Copia locale di RAM[0]: numero di task presenti.
    -- Letta una volta in S_DECODE, poi usata in tutti gli stati successivi
    -- senza dover rileggere la RAM ad ogni ciclo.
    signal num_tasks    : unsigned(7 downto 0);

    -- Indirizzo corrente durante le scansioni (OP00, OP01 shift, OP10 find/shift).
    -- Parte da 1 (primo task) e avanza o retrocede secondo l'operazione.
    -- 16 bit perché deve essere compatibile con o_mem_addr (16 bit).
    signal current_addr : unsigned(15 downto 0);

    -- Posizione di inserimento calcolata da OP10 in S_OP10_COMPARE.
    -- Salvata in un registro separato perché current_addr viene modificato
    -- durante lo shift e non può essere usato per ricordare la destinazione.
    signal target_addr  : unsigned(15 downto 0);

    -- ID del task estratto da OP01. Salvato in un registro perché i_mem_data
    -- viene sovrascritto dai cicli di shift successivi alla lettura iniziale.
    -- Presentato su o_task_id quando o_done='1'.
    signal extracted_id : std_logic_vector(5 downto 0);

    signal next_num_tasks    : unsigned(7 downto 0);
    signal next_current_addr : unsigned(15 downto 0);
    signal next_target_addr  : unsigned(15 downto 0);
    signal next_extracted_id : std_logic_vector(5 downto 0);

begin

    -- =========================================================================
    -- PROCESSO 1: state_reg — Registro di Stato
    -- Implementa fisicamente il flip-flop che memorizza lo stato corrente della FSM.
    --
    -- Reset ASINCRONO (primo ramo dell'if): non aspetta il clock. Appena i_rst='1'
    -- la FSM torna in S_RESET immediatamente, indipendentemente dallo stato del clock.
    -- Questo garantisce uno stato noto anche se il clock non è ancora stabile.
    --
    -- Aggiornamento SINCRONO (rising_edge): al fronte di salita, current_state
    -- acquisisce il valore di next_state calcolato dalla logica combinatoria
    -- nell'intervallo precedente. Tra un fronte e l'altro, current_state è congelato.
    -- =========================================================================
    state_reg: process(i_clk, i_rst)
    begin
        if i_rst = '1' then
            current_state <= S_RESET;
        elsif rising_edge(i_clk) then
            current_state <= next_state;
        end if;
    end process;

    -- =========================================================================
    -- PROCESSO 2: datapath_regs — Registri del Datapath
    -- Stessa struttura di state_reg, ma gestisce i quattro registri di supporto.
    -- Separato da state_reg per chiarezza e per garantire un reset esplicito
    -- di ogni registro a un valore noto (tutti zero).
    --
    -- I valori di reset sono coerenti con lo stato iniziale del sistema:
    --   num_tasks=0    → lista vuota, coerente con la scrittura di 0 in addr 0
    --   current_addr=0 → neutro, verrà impostato a 1 in S_DECODE prima dell'uso
    --   target_addr=0  → neutro
    --   extracted_id=0 → se OP01 fosse chiamata su lista vuota, restituirebbe 0
    -- =========================================================================
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

    -- =========================================================================
    -- PROCESSO 3: comb — Logica Combinatoria
    -- È l'unico processo puramente combinatorio: nessun fronte di clock,
    -- nessuna memoria. Ricalcola immediatamente tutte le uscite e i valori
    -- next_* ogni volta che uno dei segnali in sensitivity list cambia.
    --
    -- SENSITIVITY LIST: deve contenere TUTTI i segnali letti nel processo.
    -- Se un segnale mancasse, il simulatore non rieseguirebbe il processo
    -- quando quel segnale cambia, causando discrepanze tra simulazione e sintesi.
    --
    -- VALORI DI DEFAULT (prima del case): ogni segnale viene assegnato prima
    -- del case statement. Questo è fondamentale per evitare latch indesiderati:
    -- se un segnale non fosse assegnato in tutti i rami del case, il sintetizzatore
    -- dedurrebbe che il valore deve essere "mantenuto" e inserirebbe un latch.
    -- I latch non intenzionali rendono il circuito sensibile ai glitch e
    -- possono causare comportamenti non deterministici.
    -- =========================================================================
    comb: process(current_state, i_start, i_op,
                  i_task_id, i_task_priority,
                  num_tasks, current_addr, target_addr,
                  extracted_id, i_mem_data)
    begin
        -- Default: mantieni stato e registri, uscite inattive
        next_state        <= current_state;  -- se non modificato: rimani nello stato attuale
        next_num_tasks    <= num_tasks;
        next_current_addr <= current_addr;
        next_target_addr  <= target_addr;
        next_extracted_id <= extracted_id;

        o_done     <= '0';
        o_task_id  <= extracted_id;  -- presentato sempre, valido solo quando o_done='1'
        o_mem_en   <= '0';           -- RAM disabilitata per default
        o_mem_we   <= '0';           -- lettura per default
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
                -- Aspettiamo i_start='1' prima di leggere addr 0,
                -- così siamo certi che anche i_op sia già valido.
                if i_start = '1' then
                    next_state <= S_LOAD_COUNT;
                end if;
                -- Se i_start='0': next_state rimane S_IDLE (per il default)

            -- =======================================================
            -- FETCH: legge addr 0 (num_tasks).
            -- Ciclo T: emette richiesta.
            -- Ciclo T+1 (S_DECODE): i_mem_data è stabile.
            -- =======================================================
            when S_LOAD_COUNT =>
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
                -- Salva num_tasks nel registro interno per gli stati successivi.
                -- Usiamo i_mem_data (non num_tasks) per i confronti qui sotto,
                -- perché num_tasks verrà aggiornato solo al prossimo fronte di clock.
                next_num_tasks    <= unsigned(i_mem_data);
                next_current_addr <= to_unsigned(1, 16); -- la scansione parte sempre da addr 1
                next_target_addr  <= (others => '0');
                -- Reset a 0: se la lista è vuota e andiamo in S_DONE direttamente,
                -- extracted_id sarà già 0 (valore corretto per lista vuota in OP01).
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
            -- Pattern di lettura a 2 cicli (senza latch intermedio):
            --   S_OP00_READ   → ciclo T:   emette richiesta
            --   S_OP00_MODIFY → ciclo T+1: i_mem_data stabile, legge e riscrive
            -- =======================================================
            when S_OP00_READ =>
                -- Ciclo T: richiesta lettura indirizzo corrente
                o_mem_en   <= '1';
                o_mem_we   <= '0';
                o_mem_addr <= std_logic_vector(current_addr);
                next_state <= S_OP00_MODIFY;

            when S_OP00_MODIFY =>
                -- Ciclo T+1: i_mem_data = byte del task corrente = [ID(7:2) | PRIO(1:0)]
                -- Leggiamo e scriviamo nello stesso ciclo: efficiente, nessun ciclo sprecato.
                o_mem_en   <= '1';
                o_mem_we   <= '1';  -- scrittura immediata del valore modificato
                o_mem_addr <= std_logic_vector(current_addr);  -- stesso indirizzo della lettura
                if i_mem_data(1 downto 0) = "11" then
                    -- Saturazione: priorità già al minimo (3), non incrementare
                    o_mem_data <= i_mem_data(7 downto 2) & "11";
                else
                    -- Incremento: i 6 bit alti (ID) rimangono invariati,
                    -- i 2 bit bassi (PRIORITY) vengono incrementati di 1
                    o_mem_data <= i_mem_data(7 downto 2) &
                                  std_logic_vector(unsigned(i_mem_data(1 downto 0)) + 1);
                end if;
                -- Prepara l'indirizzo per la prossima iterazione (usato nel ciclo READ successivo)
                next_current_addr <= current_addr + 1;
                -- PERCHÉ "=": current_addr va esattamente da 1 a num_tasks.
                -- Con ">=", termineremmo un ciclo prima dell'ultimo task.
                -- resize necessario: num_tasks è 8 bit, current_addr è 16 bit.
                if current_addr = resize(num_tasks, 16) then
                    next_state <= S_WAIT_DONE;  -- ultima scrittura: aspetta un ciclo
                else
                    next_state <= S_OP00_READ;
                end if;

            -- =======================================================
            -- OP01: rimuovi primo task, shifta lista, decrementa count.
            -- =======================================================
            when S_OP01_READ_FIRST =>
                -- Leggi sempre addr 1: è il primo e unico task da estrarre
                o_mem_en   <= '1';
                o_mem_we   <= '0';
                o_mem_addr <= std_logic_vector(to_unsigned(1, 16));
                next_state <= S_OP01_SAVE;

            when S_OP01_SAVE =>
                -- i_mem_data = [ID_TASK(7:2) | PRIORITY(1:0)] del primo task
                -- Salviamo solo i 6 bit alti: sono l'ID che va restituito in output
                next_extracted_id <= i_mem_data(7 downto 2);
                -- Lo shift copierà addr[2]→addr[1], addr[3]→addr[2], ecc.
                next_current_addr <= to_unsigned(2, 16);
                if num_tasks = 1 then
                    -- Un solo task: niente shift, aggiorna solo il contatore.
                    -- Se facessimo lo shift con N=1, leggeremmo addr 2 che non esiste.
                    next_state <= S_OP01_UPDATE;
                else
                    next_state <= S_OP01_SHIFT_READ;
                end if;

            when S_OP01_SHIFT_READ =>
                -- Ciclo T: leggi addr[i], nel ciclo successivo lo scriveremo in addr[i-1]
                o_mem_en   <= '1';
                o_mem_we   <= '0';
                o_mem_addr <= std_logic_vector(current_addr);
                next_state <= S_OP01_SHIFT_WRITE;

            when S_OP01_SHIFT_WRITE =>
                -- Ciclo T+1: i_mem_data = contenuto di addr[i]
                -- Uso diretto di i_mem_data: non serve un registro latch intermedio
                -- perché i_mem_data è già stabile in questo ciclo.
                o_mem_en   <= '1';
                o_mem_we   <= '1';
                o_mem_addr <= std_logic_vector(current_addr - 1);  -- scrivi una posizione prima
                o_mem_data <= i_mem_data;
                next_current_addr <= current_addr + 1;  -- avanza per il prossimo shift
                -- Fine shift quando abbiamo copiato l'ultimo task valido (addr num_tasks)
                if current_addr = resize(num_tasks, 16) then
                    next_state <= S_OP01_UPDATE;
                else
                    next_state <= S_OP01_SHIFT_READ;
                end if;

            when S_OP01_UPDATE =>
                -- Aggiorna il contatore in addr 0 e nel registro interno
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
                -- Ciclo T: leggi il task a current_addr per confrontarne la priorità
                o_mem_en   <= '1';
                o_mem_we   <= '0';
                o_mem_addr <= std_logic_vector(current_addr);
                next_state <= S_OP10_COMPARE;

            when S_OP10_COMPARE =>
                -- Ciclo T+1: i_mem_data(1:0) = priorità del task a current_addr
                -- PERCHÉ ">=" invece di "=" per il controllo sull'ultimo task:
                -- difensivo contro qualsiasi caso in cui current_addr
                -- potesse superare num_tasks (prevenzione loop infinito).
                if i_mem_data(1 downto 0) > i_task_priority then
                    -- Il task corrente ha priorità PEGGIORE del nuovo (numero più grande).
                    -- Il nuovo task va inserito QUI. Bisogna shiftare a destra
                    -- tutti i task da current_addr fino a num_tasks per fare spazio.
                    next_target_addr  <= current_addr;
                    -- Lo shift parte dall'ultimo task e scende fino a current_addr
                    next_current_addr <= resize(num_tasks, 16);
                    next_state        <= S_OP10_SHIFT_READ;
                elsif current_addr >= resize(num_tasks, 16) then
                    -- Ultimo task raggiunto, priorità <=: inserimento in coda
                    -- Non serve shift: la nuova posizione è num_tasks + 1
                    next_target_addr <= resize(num_tasks, 16) + 1;
                    next_state       <= S_OP10_INSERT;
                else
                    -- Il task corrente ha priorità <= nuova: continua la ricerca
                    next_current_addr <= current_addr + 1;
                    next_state        <= S_OP10_FIND_READ;
                end if;

            when S_OP10_SHIFT_READ =>
                -- Ciclo T: leggi addr[i] per spostarlo in addr[i+1] (shift verso destra)
                -- current_addr parte da num_tasks e decrementa fino a target_addr
                o_mem_en   <= '1';
                o_mem_we   <= '0';
                o_mem_addr <= std_logic_vector(current_addr);
                next_state <= S_OP10_SHIFT_WRITE;

            when S_OP10_SHIFT_WRITE =>
                -- Ciclo T+1: i_mem_data = contenuto di addr[i], lo copiamo in addr[i+1]
                o_mem_en   <= '1';
                o_mem_we   <= '1';
                o_mem_addr <= std_logic_vector(current_addr + 1);  -- destinazione: una posizione avanti
                o_mem_data <= i_mem_data;
                if current_addr = target_addr then
                    -- Abbiamo shiftato fino alla posizione target: la cella è libera, inserisci
                    next_state <= S_OP10_INSERT;
                else
                    -- Continua lo shift: decrementa (andiamo da num_tasks verso target_addr)
                    next_current_addr <= current_addr - 1;
                    next_state        <= S_OP10_SHIFT_READ;
                end if;

            when S_OP10_INSERT =>
                -- Scrivi il nuovo task nella posizione calcolata.
                -- Concatenazione: [i_task_id(5:0) | i_task_priority(1:0)] = 8 bit totali
                o_mem_en   <= '1';
                o_mem_we   <= '1';
                o_mem_addr <= std_logic_vector(target_addr);
                o_mem_data <= i_task_id & i_task_priority;
                next_state <= S_OP10_UPDATE_SIZE;

            when S_OP10_UPDATE_SIZE =>
                -- Aggiorna il contatore in addr 0 e nel registro interno
                o_mem_en       <= '1';
                o_mem_we       <= '1';
                o_mem_addr     <= (others => '0');
                o_mem_data     <= std_logic_vector(num_tasks + 1);
                next_num_tasks <= num_tasks + 1;
                next_state     <= S_WAIT_DONE;

            -- =======================================================
            -- OP11: svuota la lista (scrive 0 in addr 0).
            -- La specifica permette di lasciare invariato il contenuto
            -- di addr 1..N: scrivere solo addr 0 è sufficiente.
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
                -- Nessuna uscita attiva, nessun accesso in RAM.
                -- Il solo scopo è far passare un fronte di clock tra
                -- l'ultima scrittura e l'alzata di o_done.
                next_state <= S_DONE;

            -- =======================================================
            -- DONE: segnala completamento, attende abbassamento di START.
            -- =======================================================
            when S_DONE =>
                o_done    <= '1';
                o_task_id <= extracted_id;  -- valido per OP01, 0 negli altri casi
                -- Aspetta che la logica esterna abbassi i_start (fine handshake).
                -- Solo allora o_done torna a 0 e il modulo è pronto per la prossima operazione.
                if i_start = '0' then
                    next_state <= S_IDLE;
                end if;
                -- Se i_start='1': next_state rimane S_DONE (per il default), DONE resta 1

            -- Stato non raggiungibile in condizioni normali.
            -- Presente per completezza e per sicurezza contro corruzioni di stato.
            when others =>
                next_state <= S_RESET;

        end case;
    end process;

end Behavioral;
