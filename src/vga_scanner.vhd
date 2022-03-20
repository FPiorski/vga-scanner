--------------------------------------------------------------------------------
-- Project:       vga-scanner
-- File:          vga_scanner.vhd
--
-- Creation date: 2022-03-19
--
-- Author:        FPiorski
-- License:       CERN-OHL-W-2.0
--------------------------------------------------------------------------------
LIBRARY IEEE;
USE IEEE.STD_LOGIC_1164.ALL;
USE IEEE.NUMERIC_STD.ALL;

ENTITY vga_scanner IS
    GENERIC
    (
        g_sys_clk_hz    : positive := 50_000_000;

        g_gate_time_ms  : positive :=     10_000;
        g_cnt_nibbles   : positive :=          8;
        g_delay_after   : positive :=      1_000; --result ready assert time in i_px_clk cycles

        g_px_clk_edge   : string   :=     "FALL"; --RISE/FALL
        g_hsync_act_low : boolean  :=       TRUE;
        g_vsync_act_low : boolean  :=       TRUE;

        g_uart_baud     : positive :=    115_200
    );
    PORT
    (
        --System
        i_clk       : IN    std_logic;
        i_rst_n     : IN    std_logic;

        --Measured interface
        i_px_clk    : IN    std_logic;
        i_hsync     : IN    std_logic;
        i_vsync     : IN    std_logic;

        --UART
        i_uart_rx   : IN    std_logic;
        o_uart_tx   :   OUT std_logic
    );
END vga_scanner;

ARCHITECTURE RTL OF vga_scanner IS

    CONSTANT C_counter_bits       : integer                              := 4 * g_cnt_nibbles;

    TYPE     T_state IS (IDLE, MEAS, GATE, DELAY);
    SIGNAL   r_state_cur          : T_state                              := IDLE;
    SIGNAL   w_state_next         : T_state;

    SIGNAL   r_trig               : std_logic                            := '0';
    SIGNAL   r_gate               : std_logic                            := '0';

    CONSTANT C_delay_cnt_mod      : integer                              := g_sys_clk_hz / 1000 * 10; --10ms
    SIGNAL   r_delay_cnt          : integer RANGE 0 TO C_delay_cnt_mod-1 := 0;

    CONSTANT C_gate_cnt_mod       : integer                              := g_sys_clk_hz / 1000 * g_gate_time_ms;
    SIGNAL   r_gate_cnt           : integer RANGE 0 TO C_gate_cnt_mod-1  := 0;


    SIGNAL   w_px_clk             : std_logic;
    SIGNAL   w_hsync              : std_logic;
    SIGNAL   w_vsync              : std_logic;

    SIGNAL   w_uart_rx_data       : std_logic_vector(7 downto 0);
    SIGNAL   w_uart_rx_data_valid : std_logic;

    SIGNAL   w_result             : std_logic_vector(C_counter_bits-1 downto 0);
    SIGNAL   w_result_valid       : std_logic;

BEGIN

    P_update_state : PROCESS(i_clk)
    BEGIN
        IF (rising_edge(i_clk)) THEN
            IF (i_rst_n = '0') THEN
                r_state_cur <= IDLE;
            ELSE
                r_state_cur <= w_state_next;
            END IF;
        END IF;
    END PROCESS;

    P_decide_next_state : PROCESS(r_state_cur,
                                  w_uart_rx_data, w_uart_rx_data_valid,
                                  w_result_valid,
                                  r_gate_cnt,
                                  r_delay_cnt)
    BEGIN

        w_state_next <= r_state_cur;

        CASE r_state_cur IS
            WHEN IDLE =>
                IF (w_uart_rx_data_valid = '1') THEN
                    IF (w_uart_rx_data = std_logic_vector(to_unsigned(character'POS('1'), 8))  OR
                        w_uart_rx_data = std_logic_vector(to_unsigned(character'POS('2'), 8))  OR
                        w_uart_rx_data = std_logic_vector(to_unsigned(character'POS('3'), 8))  OR
                        w_uart_rx_data = std_logic_vector(to_unsigned(character'POS('4'), 8))) THEN
                        w_state_next <= MEAS;
                    ELSIF (w_uart_rx_data = std_logic_vector(to_unsigned(character'POS('f'), 8))) THEN
                        w_state_next <= GATE;
                    END IF;
                END IF;

            WHEN MEAS =>
                IF (w_result_valid = '1') THEN
                    w_state_next <= DELAY;
                END IF;

            WHEN GATE =>
                IF (r_gate_cnt >= C_gate_cnt_mod-1) THEN
                    w_state_next <= DELAY;
                END IF;

            WHEN DELAY =>
                IF (r_delay_cnt >= C_delay_cnt_mod-1) THEN
                    w_state_next <= IDLE;
                END IF;

        END CASE;

    END PROCESS;

    P_trig : PROCESS(i_clk)
    BEGIN
        IF (rising_edge(i_clk)) THEN
            IF (i_rst_n = '0') THEN
                r_trig <= '0';
            ELSE
                IF (r_state_cur = MEAS) THEN
                    r_trig <= '1';
                ELSE
                    r_trig <= '0';
                END IF;
            END IF;
        END IF;
    END PROCESS;

    P_gate : PROCESS(i_clk)
    BEGIN
        IF (rising_edge(i_clk)) THEN
            IF (i_rst_n = '0') THEN
                r_gate_cnt <=  0;
                r_gate     <= '0';
            ELSE
                IF (r_state_cur = GATE) THEN

                    r_gate <= '1';

                    IF (r_gate_cnt < C_gate_cnt_mod-1) THEN
                        r_gate_cnt <= r_gate_cnt + 1;
                    END IF;
                ELSE
                    r_gate_cnt <=  0;
                    r_gate     <= '0';
                END IF;
            END IF;
        END IF;
    END PROCESS;

    P_delay_counter : PROCESS(i_clk)
    BEGIN
        IF (rising_edge(i_clk)) THEN
            IF (i_rst_n = '0') THEN
                r_delay_cnt <= 0;
            ELSE
                IF (r_state_cur = DELAY) THEN
                    IF (r_delay_cnt < C_delay_cnt_mod-1) THEN
                        r_delay_cnt <= r_delay_cnt + 1;
                    END IF;
                ELSE
                    r_delay_cnt <= 0;
                END IF;
            END IF;
        END IF;
    END PROCESS;


    measure_inst : ENTITY work.measure
        GENERIC MAP
        (
            g_cnt_nibbles  => g_cnt_nibbles,
            g_delay_after  => g_delay_after
        )
        PORT MAP
        (
            i_rst_n        => i_rst_n,

            i_clk          => w_px_clk,
            i_hsync        => w_hsync,
            i_vsync        => w_vsync,

            i_mode         => w_uart_rx_data(1 downto 0),

            i_trig         => r_trig,
            i_gate         => r_gate,

            o_result       => w_result,
            o_result_valid => w_result_valid
        );

    uart_rx_inst : ENTITY work.uart_rx
        GENERIC MAP
        (
            g_sys_clk_hz => g_sys_clk_hz,
            g_uart_baud  => g_uart_baud
        )
        PORT MAP
        (
            i_clk        => i_clk,
            i_rst_n      => i_rst_n,

            i_uart_rx    => i_uart_rx,

            o_data       => w_uart_rx_data,
            o_data_valid => w_uart_rx_data_valid
        );

    uart_tx_inst : ENTITY work.uart_tx
        GENERIC MAP
        (
            g_sys_clk_hz  => g_sys_clk_hz,
            g_uart_baud   => g_uart_baud,
            g_cnt_nibbles => g_cnt_nibbles
        )
        PORT MAP
        (
            i_clk        => i_clk,
            i_rst_n      => i_rst_n,

            o_uart_tx    => o_uart_tx,

            i_data       => w_result,
            i_data_valid => w_result_valid
        );


    ASSERT (g_px_clk_edge = "RISE" OR g_px_clk_edge = "FALL")
        REPORT "vga_scanner: Check g_px_clk_edge aka at which edge of i_px_clk are the other signals valid" SEVERITY error;

    G_rising_edge_px_clk  : IF g_px_clk_edge = "RISE" GENERATE
        w_px_clk <=     i_px_clk;
    END GENERATE G_rising_edge_px_clk;
    G_falling_edge_px_clk : IF g_px_clk_edge = "FALL" GENERATE
        w_px_clk <= NOT i_px_clk;
    END GENERATE G_falling_edge_px_clk;

    G_hsync_active_low  : IF g_hsync_act_low = TRUE GENERATE
        w_hsync <=     i_hsync;
    END GENERATE G_hsync_active_low;
    G_hsync_active_high : IF g_hsync_act_low = FALSE GENERATE
        w_hsync <= NOT i_hsync;
    END GENERATE G_hsync_active_high;

    G_vsync_active_low  : IF g_vsync_act_low = TRUE GENERATE
        w_vsync <=     i_vsync;
    END GENERATE G_vsync_active_low;
    G_vsync_active_high : IF g_vsync_act_low = FALSE GENERATE
        w_vsync <= NOT i_vsync;
    END GENERATE G_vsync_active_high;

END ARCHITECTURE;
