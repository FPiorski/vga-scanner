--------------------------------------------------------------------------------
-- Project:       vga-scanner
-- File:          uart_rx.vhd
--
-- Creation date: 2022-03-19
--
-- Author:        FPiorski
-- License:       CERN-OHL-W-2.0
--------------------------------------------------------------------------------
LIBRARY IEEE;
USE IEEE.STD_LOGIC_1164.ALL;

ENTITY uart_rx IS
    GENERIC
    (
        g_sys_clk_hz    : positive := 50_000_000;
        g_uart_baud     : positive :=    115_200
    );
    PORT
    (
        --System
        i_clk        : IN    std_logic;
        i_rst_n      : IN    std_logic;

        --UART serial input
        i_uart_rx    : IN    std_logic;

        --Parallel data output
        o_data       :   OUT std_logic_vector(7 downto 0);
        o_data_valid :   OUT std_logic
    );
END uart_rx;

ARCHITECTURE RTL OF uart_rx IS

    TYPE     T_state IS (IDLE, DATA, STOP, ERROR);
    SIGNAL   r_state_cur          : T_state                               := IDLE;
    SIGNAL   w_state_next         : T_state;

    CONSTANT C_streak_cnt_mod     : integer                               := 20;
    SIGNAL   r_streak_cnt         : integer RANGE 0 TO C_streak_cnt_mod-1 :=  0;

    CONSTANT C_clk_cnt_mod        : integer                               := g_sys_clk_hz / g_uart_baud;
    SIGNAL   r_clk_cnt            : integer RANGE 0 TO C_clk_cnt_mod-1    :=  0;
    SIGNAL   r_uart_clk_edge      : std_logic                             := '0';

    CONSTANT C_bit_cnt_mod        : integer                               :=  8;
    SIGNAL   r_bit_cnt            : integer RANGE 0 TO C_bit_cnt_mod-1    :=  0;

    SIGNAL   r_data               : std_logic_vector(7 downto 0)          := (OTHERS => '0');
    SIGNAL   r_data_valid         : std_logic                             := '0';

BEGIN

    o_data       <= r_data;
    o_data_valid <= r_data_valid;


    P_update_state : PROCESS(i_clk)
    BEGIN
        IF (rising_edge(i_clk)) THEN
            IF (i_rst_n = '0') THEN
                r_state_cur <= IDLE;
            ELSE
                IF (r_uart_clk_edge = '1') THEN
                    r_state_cur <= w_state_next;
                END IF;
            END IF;
        END IF;
    END PROCESS;

    P_decide_next_state : PROCESS(r_state_cur, i_uart_rx, r_bit_cnt, r_streak_cnt)
    BEGIN

        w_state_next <= r_state_cur;

        CASE r_state_cur IS
            WHEN IDLE =>
                IF (i_uart_rx = '0') THEN
                    w_state_next <= DATA;
                END IF;

            WHEN DATA =>
                IF (r_bit_cnt = C_bit_cnt_mod-1) THEN
                    w_state_next <= STOP;
                END IF;

            WHEN STOP =>
                IF (i_uart_rx /= '1') THEN
                    w_state_next <= ERROR;
                ELSE
                    w_state_next <= IDLE;
                END IF;

            WHEN ERROR =>
                IF (r_streak_cnt >= C_streak_cnt_mod-1) THEN
                    w_state_next <= IDLE;
                END IF;

        END CASE;

    END PROCESS;

    P_uart_shift_register : PROCESS(i_clk)
    BEGIN
        IF (rising_edge(i_clk)) THEN
            IF (i_rst_n = '0') THEN
                r_data    <= (OTHERS => '0');
                r_bit_cnt <= 0;
            ELSE
                IF (r_uart_clk_edge = '1') THEN
                    IF (r_state_cur = DATA) THEN
                        r_data <= i_uart_rx & r_data(7 downto 1); --UART is LSb first
                        IF (r_bit_cnt < C_bit_cnt_mod-1) THEN
                            r_bit_cnt <= r_bit_cnt + 1;
                        END IF;
                    ELSE
                        r_bit_cnt <= 0;
                    END IF;
                END IF;
            END IF;
        END IF;
    END PROCESS;

    P_uart_clk : PROCESS(i_clk)
    BEGIN
        IF (rising_edge(i_clk)) THEN
            IF (i_rst_n = '0') THEN
                r_clk_cnt       <=  0;
                r_uart_clk_edge <= '0';
            ELSE
                IF (r_clk_cnt < C_clk_cnt_mod-1) THEN
                    r_clk_cnt       <= r_clk_cnt + 1;
                    r_uart_clk_edge <= '0';
                ELSE
                    r_clk_cnt       <=  0;
                    r_uart_clk_edge <= '1';
                END IF;
            END IF;
        END IF;
    END PROCESS;

    P_streak_cnt : PROCESS(i_clk)
    BEGIN
        IF (rising_edge(i_clk)) THEN
            IF (i_rst_n = '0') THEN
                r_streak_cnt <= 0;
            ELSE
                IF (r_state_cur = ERROR) THEN
                    IF (i_uart_rx = '1') THEN
                        IF (r_streak_cnt < C_streak_cnt_mod-1) THEN
                            r_streak_cnt <= r_streak_cnt + 1;
                        END IF;
                    ELSE
                        r_streak_cnt <= 0;
                    END IF;
                ELSE
                    r_streak_cnt <= 0;
                END IF;
            END IF;
        END IF;
    END PROCESS;

    P_data_valid : PROCESS(i_clk)
    BEGIN
        IF (rising_edge(i_clk)) THEN
            IF (i_rst_n = '0') THEN
                r_data_valid <= '0';
            ELSE
                IF (r_state_cur = STOP AND w_state_next = IDLE AND r_uart_clk_edge = '1') THEN
                    r_data_valid <= '1';
                ELSE
                    r_data_valid <= '0';
                END IF;
            END IF;
        END IF;
    END PROCESS;

END ARCHITECTURE;
