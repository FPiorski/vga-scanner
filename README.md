# vga-scanner
Some RTL code to measure VGA (parallel RGB, whatever) timing

There's no CDC for the gate signal so the frequency measurement is slightly different every time (all that is needed to remedy this is to add a synchronizer chain on the gate input of measure.vhd, but I wanted to see just by how much would gate metastability change the result).

To use this connect with an 8N1 UART and send '1'-'4' or 'f' to trigger a measurement. 'f' is pixel clock counter with a 10 second gate time, 1 is hsync period, 2 is hsync pulse width, 3 and 4 are the same for vsync. You'll get back the in hexadecimal + '\r\n'.

Yeah, the code could be prettier and could be more generalized, but it could also not exist at all, because this measurement could be done with a logic analyzer. I used what I had on hand and wrote this in a Saturday afternoon.

Result with my Siglent SDS1104X-E's LCD panel I needed to know the timing info of:

![Measurement results](1647799768.png?raw=true "Measurement results")
Interpretation:

Pixel clock: 27.5MHz (275000852 pixel clock periods in 10s)

Hsync period: 0x420 = 1056 px_clk cycles
Hsync pulse width: 0x14 = 20 px_clk cycles
Vsync period: 0x875A0 = 554400 px_clk cycles = 525 lines
Vsync pulse width: 0x2940 = 10560 px_clk cycles = 10 lines

Vsync cycles being an integer multiple of hsync period cycles pretty much proves there's no off-by-1 error in my RTL

This all maps to a screen refresh rate is 49.(603174) Hz, interesting.
