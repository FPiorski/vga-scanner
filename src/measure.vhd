--------------------------------------------------------------------------------
-- Project:       vga-scanner
-- File:          measure.vhd
--
-- Creation date: 2022-03-19
--
-- Author:        FPiorski
-- License:       CERN-OHL-W-2.0
--------------------------------------------------------------------------------
LIBRARY IEEE;
USE IEEE.STD_LOGIC_1164.ALL;
USE IEEE.NUMERIC_STD.ALL;

ENTITY measure IS
    GENERIC
    (
        g_cnt_nibbles  : positive :=     8;
        g_delay_after  : positive := 1_000
    );
    PORT
    (
        --System
        i_rst_n        : IN    std_logic;

        --Pixel clock, hsync and vsync
        i_clk          : IN    std_logic;
        i_hsync        : IN    std_logic;
        i_vsync        : IN    std_logic;

        i_mode         : IN    std_logic_vector(1 downto 0);

        i_trig         : IN    std_logic;
        i_gate         : IN    std_logic;

        o_result       :   OUT std_logic_vector;
        o_result_valid :   OUT std_logic
    );
END measure;

ARCHITECTURE RTL OF measure IS

    CONSTANT C_counter_bits       : integer                              := 4 * g_cnt_nibbles;
    SIGNAL   r_counter            : integer                              := 0;

    TYPE     T_state IS (IDLE,
                         HSYNC_PERIOD_WAIT_FOR_EDGE, HSYNC_PERIOD_CNT,
                         HSYNC_WIDTH_WAIT_FOR_EDGE, HSYNC_WIDTH_CNT,
                         VSYNC_PERIOD_WAIT_FOR_EDGE, VSYNC_PERIOD_CNT,
                         VSYNC_WIDTH_WAIT_FOR_EDGE, VSYNC_WIDTH_CNT,
                         GATED_CNT,
                         DELAY);
    SIGNAL   r_state_cur          : T_state                              := IDLE;
    SIGNAL   w_state_next         : T_state;

    SIGNAL   r_hsync_prev         : std_logic                            := '1';
    SIGNAL   r_vsync_prev         : std_logic                            := '1';

    CONSTANT C_delay_cnt_mod      : integer                              := g_delay_after;
    SIGNAL   r_delay_cnt          : integer RANGE 0 TO C_delay_cnt_mod-1 := 0;

    SIGNAL   r_result_valid       : std_logic                            := '0';

BEGIN

    o_result       <= std_logic_vector(to_unsigned(r_counter, C_counter_bits));
    o_result_valid <= r_result_valid;


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
                                  i_trig, i_gate, i_mode,
                                  i_hsync, i_vsync,
                                  r_delay_cnt)
    BEGIN

        w_state_next <= r_state_cur;

        CASE r_state_cur IS
            WHEN IDLE =>
                IF (i_gate = '1') THEN
                    w_state_next <= GATED_CNT;
                ELSIF (i_trig = '1') THEN
                    CASE i_mode IS
                        WHEN "01" =>
                            w_state_next <= HSYNC_PERIOD_WAIT_FOR_EDGE;
                        WHEN "10" =>
                            w_state_next <= HSYNC_WIDTH_WAIT_FOR_EDGE;
                        WHEN "11" =>
                            w_state_next <= VSYNC_PERIOD_WAIT_FOR_EDGE;
                        WHEN "00" =>
                            w_state_next <= VSYNC_WIDTH_WAIT_FOR_EDGE;
                        WHEN OTHERS =>
                            NULL;
                    END CASE;
                END IF;

            WHEN GATED_CNT =>
                IF (i_gate = '0') THEN
                    w_state_next <= DELAY;
                END IF;

            WHEN HSYNC_PERIOD_WAIT_FOR_EDGE =>
                IF (r_hsync_prev = '1' AND i_hsync = '0') THEN --falling edge
                    w_state_next <= HSYNC_PERIOD_CNT;
                END IF;
            WHEN HSYNC_PERIOD_CNT =>
                IF (r_hsync_prev = '1' AND i_hsync = '0') THEN --falling edge
                    w_state_next <= DELAY;
                END IF;

            WHEN HSYNC_WIDTH_WAIT_FOR_EDGE =>
                IF (r_hsync_prev = '1' AND i_hsync = '0') THEN --falling edge
                    w_state_next <= HSYNC_WIDTH_CNT;
                END IF;
            WHEN HSYNC_WIDTH_CNT =>
                IF (r_hsync_prev = '0' AND i_hsync = '1') THEN -- rising edge
                    w_state_next <= DELAY;
                END IF;

            WHEN VSYNC_PERIOD_WAIT_FOR_EDGE =>
                IF (r_vsync_prev = '1' AND i_vsync = '0') THEN --falling edge
                    w_state_next <= VSYNC_PERIOD_CNT;
                END IF;
            WHEN VSYNC_PERIOD_CNT =>
                IF (r_vsync_prev = '1' AND i_vsync = '0') THEN --falling edge
                    w_state_next <= DELAY;
                END IF;

            WHEN VSYNC_WIDTH_WAIT_FOR_EDGE =>
                IF (r_vsync_prev = '1' AND i_vsync = '0') THEN --falling edge
                    w_state_next <= VSYNC_WIDTH_CNT;
                END IF;
            WHEN VSYNC_WIDTH_CNT =>
                IF (r_vsync_prev = '0' AND i_vsync = '1') THEN -- rising edge
                    w_state_next <= DELAY;
                END IF;


            WHEN DELAY =>
                IF (r_delay_cnt >= C_delay_cnt_mod-1) THEN
                    w_state_next <= IDLE;
                END IF;

        END CASE;

    END PROCESS;

    P_sample_hsync_vsync : PROCESS(i_clk)
    BEGIN
        IF (rising_edge(i_clk)) THEN
            r_hsync_prev <= i_hsync;
            r_vsync_prev <= i_vsync;
        END IF;
    END PROCESS;

    P_measure : PROCESS(i_clk)
    BEGIN
        IF (rising_edge(i_clk)) THEN
            IF (i_rst_n = '0') THEN
                r_counter <= 0;
            ELSE
                IF (r_state_cur = IDLE) THEN
                    r_counter <= 0;
                ELSIF ((r_state_cur = HSYNC_PERIOD_CNT)  OR
                       (r_state_cur = HSYNC_WIDTH_CNT)   OR
                       (r_state_cur = VSYNC_PERIOD_CNT)  OR
                       (r_state_cur = VSYNC_WIDTH_CNT)   OR
                       (r_state_cur = GATED_CNT)       ) THEN
                    r_counter <= r_counter + 1;
                END IF;
            END IF;
        END IF;
    END PROCESS;

    P_result_valid : PROCESS(i_clk)
    BEGIN
        IF (rising_edge(i_clk)) THEN
            IF (i_rst_n = '0') THEN
                r_result_valid <= '0';
            ELSE
                IF (r_state_cur = IDLE) THEN
                    r_result_valid <= '0';
                ELSIF (r_state_cur = DELAY) THEN
                    r_result_valid <= '1';
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

END ARCHITECTURE;
