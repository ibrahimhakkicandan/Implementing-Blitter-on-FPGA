module vga_sync
  (input logic        clk,
  input logic        clk_25mhz,
   output logic       hsync,
   output logic       vsync,
	input logic [15:0] data_in,
   output logic [2:0] rgb,
	input logic hold_ack,
	output logic hold,
	input logic [15:0] xPixel,
	input logic [15:0] yPixel,
	output logic [15:0] gpu_data_out,
	output logic [11:0] address
	);

   logic pixel_tick, video_on;
	logic [1:0] counter;
	logic [11:0] pc;
   logic [9:0] h_count;
	logic [9:0] h_index;
	logic [9:0] v_index;
	logic [2:0] color_reg [0:1] ;//color registers 
   logic [9:0] v_count;
	logic [15:0] color_data [0:4] ;
	logic x;
	logic y;
   localparam HD       = 1280, //horizontal display area
              HF       = 216,  //horizontal front porch
              HB       = 80,  //horizontal back porch6
              HFB      = 136,  //horizontal flyback
              VD       = 960, //vertical display area
              VT       = 1,  //vertical top porch
              VB       = 30,  //vertical bottom porch
              VFB      = 3,   //vertical flyback
                  LINE_END = HF+HD+HB+HFB-1,
              PAGE_END = VT+VD+VB+VFB-1; // burayı 640x480 yap 
				  
	
	logic [6:0] cnt = 0;
	logic clk_40mhz;

always @(posedge clk) begin
  if (cnt == 6'd49) begin
    clk_40mhz <= ~clk_40mhz; // Toggle the output clock
    cnt <= 0; // Reset the counter
  end
  else begin
    cnt <= cnt + 1; // Increment the counter
  end
end
	
	  

   always_ff @(posedge clk_25mhz) // bu yüz mhz geliyor düzelt
	begin
        if (h_count == LINE_END)
          begin
              h_count <= 0;
                  if (v_count == PAGE_END)
						begin
                        v_count <= 0;
								
								
								end
                  else
                     v_count <= v_count + 1;
                     end
        else
			 begin
          h_count <= h_count + 1;
			 
			
			 end
     end
	  
	  always_ff @(posedge clk)
			begin
			
			if(h_count>=0 && h_count<640 && v_count<VD)
				begin
				h_index<=15-((h_count-(h_count%8))/8);
				if(h_count<128)
					v_index<=0;
				else
				v_index<=((h_count-(h_count%128))/128);
				end
				
				
			end
	  
	  always_ff @(posedge clk)
	  begin
	  
						if(v_count+VB+VFB-3==PAGE_END)
						begin
						pc<=12'h055;
						end
	   if((h_count+HB+HFB-1==LINE_END && (v_count+VB+VFB-3)%8==0) || (h_count+HB+HFB-1==LINE_END && v_count+VB+VFB-3==PAGE_END))
			hold<=1;
			
		
			if(hold_ack==1)
			begin
	
				address<=pc;
				
				if(pc % 5 ==0) 
					begin
					color_data[4]<= data_in;
					
					end
				else if(pc % 5 ==1)
					begin
					color_data[0]<= data_in;
					
					end
				else if(pc % 5 ==2)
					begin
					color_data[1]<= data_in;
					
					end
				else if(pc % 5 ==3)
					begin
					color_data[2]<= data_in;
					
					end
				else
					begin
					color_data[3]<= data_in;
					hold<=0;
					
						
					end
				
				pc<=pc+1;
			 end
		
	  end
	  
	  
   always_comb
        begin
            
             if((xPixel-5 <= h_count) && (h_count <= xPixel+6) && (yPixel-5 <= v_count) && (v_count <= yPixel+6))
                rgb = 3'b001;
					 
				 else if (h_count<640 && h_count>=0 && v_count < VD && h_count<HD)
						rgb = color_reg[color_data[v_index][h_index]];
				 
				   else
				      rgb = 3'b000;
					
        end
   // added by us
	 
   assign hsync = (h_count >= (HD+HB) && h_count <= (HFB+HD+HB-1));
   assign vsync = (v_count >= (VD+VB) && v_count <= (VD+VB+VFB-1));

   initial
     begin
	  color_reg[0]=3'b010;// register 0 beyaz renk
	  color_reg[1]=3'b100;// register 1 siyah renk
	 
		  pc=12'h055;
		  hold=0;
        h_count = 0;;
        v_count = 0;
    
		 
     end
	  
	  

endmodule