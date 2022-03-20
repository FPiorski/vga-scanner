# vga-scanner
Some RTL code to measure VGA (parallel RGB, whatever) timing

There's no CDC for the gate signal so the frequency measurement is slightly different every time (all that is needed to remedy this is to add a synchronizer chain on the gate input of measure.vhd, but I wanted to see just by how much would gate metastability change the result).

To use this connect with an 8N1 UART and send '1'-'4' or 'f' to trigger a measurement. 'f' is pixel clock counter with a 10 second gate time, 1 is hsync period, 2 is hsync pulse width, 3 and 4 are the same for vsync. You'll get back the in hexadecimal + '\r\n'.

Yeah, the code could be prettier and could be more generalized, but it could also not exist at all, because this measurement could be done with a logic analyzer. I used what I had on hand and wrote this in a Saturday afternoon.

Result with my Siglent SDS1104X-E's LCD panel I needed to know the timing info of:

![Measurement results](1647799768.png?raw=true "Measurement results")

