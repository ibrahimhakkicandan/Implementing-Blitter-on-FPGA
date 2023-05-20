module hw3 ( input i_clk50,
 input ps2c,
 input ps2d,
 output logic ground,
 output logic [2:0] rgb,
 output logic hsync,
 output logic vsync,
 output logic denme,
 output logic hold,
 output logic [3:0] grounds,
 output logic [6:0] display
 );
 

logic [15:0] data_all;
logic  [15:0] x;
logic  [15:0] y;
logic ack;


logic [11:0] cpu_address;
logic [11:0] gpu_address;
logic [15:0] gpu_data_in;
//memory map is defined here
localparam BEGINMEM=12'h000,
ENDMEM=12'h200,
XPOSITION=12'hb01,
YPOSITION=12'hb02,
KEYBOARD=12'h900,
VGA=12'hb00;

// memory chip
logic [15:0] memory [0:511];
// cpu's input-output pins
logic [15:0] data_out,deneme_data;
logic [15:0] data_in;
logic [11:0] address;
logic memwt,locked,reset;
logic pll_clk_100mhz;
logic pll_clk_25mhz;


// keyboard data out
logic [15:0] o_keyboard_data;

//multiplexer for cpu input
assign reset = !pll_locked;

vga_sync vga(
    .clk(i_clk50),
    .hsync(hsync),
    .vsync(vsync),
    .rgb(rgb),
	 .data_in(gpu_data_in),
	 .xPixel(x),
	 .yPixel(y),
	 .hold_ack(hold_ack),
	 .hold(hold),
	 .address(gpu_address),
	 .gpu_data_out(gpu_data_out),
	 .clk_25mhz(pll_clk_100mhz)

    ); 
	 
intf_axi4 axi_bus ();

ctrl_sdram ctrl_sdram_0
  (.i_clk(pll_clk_100mhz),
   .i_reset(reset)
	);


pk pk(
	 .inclk0(i_clk50),
	 .c0(pll_clk_100mhz),
	 
	 .locked(pll_locked)
	 );
	
keyboard keyboard(
    .clk(pll_clk_100mhz),
    .ps2d(ps2d),
    .ps2c(ps2c),
    .ack(ack),
    .dout(o_keyboard_data)
    ); 

bird bird (
    .clk(pll_clk_100mhz),
    .data_in(data_in),
	 .hold_ack(hold_ack),
	 .hold(hold),
    .data_out(data_out),
    .address(cpu_address),
    .memwt(memwt),
    ); 
	 
sevensegment sevensegment (
	.clk(i_clk50),
	.grounds(grounds),
	.display(display),
	.din(deneme_data)
	);
always_comb
begin

if(hold_ack ==1)
begin
	address=gpu_address;
	gpu_data_in=data_in;
end
	else
	begin
   gpu_data_in=data_out;
	address=cpu_address;/// burası düzenlenek
	end
end



always_ff @(posedge pll_clk_100mhz)
	begin
		if (axi_bus.s_awready) begin
		axi_bus.m_awaddr <= 8'h00000000;
		axi_bus.m_awvalid <= 1;
		axi_bus.m_awlen <= 0;
		axi_bus.m_awsize <= 3'b001;
		end
		
		if (axi_bus.s_wready) begin
		axi_bus.m_wdata <= 4'h4321;
		end
		
		
		
		
	end
	
always_ff @(posedge pll_clk_100mhz)
	begin
		if (axi_bus.s_arready) begin
		axi_bus.m_araddr <= 8'h00000000;
		axi_bus.m_arvalid <= 1;
		axi_bus.m_arlen <= 0;
		axi_bus.m_arsize <= 3'b001;
		end
		
		
		
		if (axi_bus.m_rready) begin
		deneme_data<=axi_bus.s_rdata;
		end
		
		
	end

	always_ff @(posedge pll_clk_100mhz)
	begin
	if(deneme_data==4'h4321)begin
		denme=1;
		end
	end
	
	
	
always_comb
if ( (BEGINMEM<=address) && (address<=ENDMEM) )
begin
ack=0;
data_in=memory[address];
end

else if (address==VGA)
begin
ack=0;
data_in=memory[address];
end

else if (address==KEYBOARD+1) // status
begin 
data_in= o_keyboard_data;
ack=0; // ?
end 

else if (address==KEYBOARD) // data
begin 
data_in= o_keyboard_data;
ack=1;
end 

else begin
ack=0;
data_in=16'hf345; //default
end



//multiplexer for cpu output
always_ff @(posedge pll_clk_100mhz) //data output port of the cpu
if (memwt)
begin
if ( (BEGINMEM<=address) && (address<=ENDMEM) )
memory[address]<=data_out;
else if (address==XPOSITION)
x<=data_out;
else if (address==YPOSITION)
y<=data_out;
end

 
initial begin
	
    $readmemh("ram.dat", memory);
end
endmodule