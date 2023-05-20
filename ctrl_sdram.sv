`include "defines.sv"
import defines::*;

module ctrl_sdram
  #(parameter DATA_WIDTH         = 16,
    parameter ROW_ADDR_WIDTH     = 13,
    parameter COL_ADDR_WIDTH     = 9,
    parameter BANK_ADDR_WIDTH    = 2,
    parameter SDRAM_CLK_FREQ     = 100,
    parameter SDRAM_BURST_LENGTH = 1,
    parameter SDRAM_BURST_TYPE   = "Sequential",
    parameter SDRAM_LATENCY_MODE = 2)
   (input logic                i_clk,
    input logic                i_reset,
    output logic [12:0]        o_dram_addr,
    inout [(DATA_WIDTH - 1):0] io_dram_dq,
    output logic [1:0]         o_dram_ba,
    output logic [1:0]         o_dram_dqm,
    output logic               o_dram_ras_n,
    output logic               o_dram_cas_n,
    output logic               o_dram_cke,
    output logic               o_dram_we_n,
    output logic               o_dram_cs_n,
    intf_axi4.slave            axi_bus);

   localparam SDRAM_BURST_IDX_WIDTH = $clog2(SDRAM_BURST_LENGTH);
   localparam N_BANKS               = 4;
   localparam MEMORY_SIZE           = (1 << (ROW_ADDR_WIDTH + COL_ADDR_WIDTH)) * N_BANKS * (DATA_WIDTH / 8);
   localparam INTERNAL_ADDR_WIDTH   = ROW_ADDR_WIDTH + COL_ADDR_WIDTH + $clog2(N_BANKS);
   localparam SDRAM_ADDR_WIDTH      = $size(o_dram_addr);
   localparam SDRAM_MODE            = SDRAM_ADDR_WIDTH'('b000_0_00_010_0_000);
   localparam TIMER_WIDTH           = 24;

   localparam T_POWERON            = 10000;              // 100us
   localparam T_REFRESH            = 6400000;            // 64ms
   localparam T_ROW_PRECHARGE      = 2;                  // t_RP
   localparam T_AUTO_REFRESH_CYCLE = 6;                  // t_RC
   localparam T_RAS_CAS_DELAY      = SDRAM_LATENCY_MODE; // t_RCD
   localparam T_CAS_LATENCY        = SDRAM_LATENCY_MODE; // t_CAS

   typedef enum {
      S_IDLE,
      S_INIT_SEQ_POWERON,
      S_INIT_SEQ_PRECHARGE,
      S_INIT_SEQ_AUTO_REFRESH0,
      S_INIT_SEQ_AUTO_REFRESH1,
      S_INIT_SEQ_MODE_REGISTER_SET,
      S_READ_SEQ_ROW_DEACTIVATE,
      S_READ_SEQ_ROW_ACTIVATE,
      S_READ_SEQ_CAS_WAIT,
      S_READ_SEQ_READ,
      S_WRITE_SEQ_ROW_DEACTIVATE,
      S_WRITE_SEQ_ROW_ACTIVATE,
      S_WRITE_SEQ_WRITE,
      S_AUTO_REFRESH_SEQ_PRECHARGE,
      S_AUTO_REFRESH_SEQ_AUTO_REFRESH
   } state_t;

   typedef enum logic [3:0] {
      CMD_DEVICE_DESELECT   = 4'b1xxx,
      CMD_NOP               = 4'b0111,
      CMD_BURST_STOP        = 4'b0110,
      CMD_READ              = 4'b0101,
      CMD_WRITE             = 4'b0100,
      CMD_ROW_ACTIVATE      = 4'b0011,
      CMD_PRECHARGE         = 4'b0010,
      CMD_AUTO_REFRESH      = 4'b0001,
      CMD_MODE_REGISTER_SET = 4'b0000
   } cmd_t;

   logic [(TIMER_WIDTH - 1):0]         refresh_timer, refresh_timer_nxt;
   logic [(TIMER_WIDTH - 1):0]         delay_timer, delay_timer_nxt;
   logic [(ROW_ADDR_WIDTH - 1):0]      bank_active_row [N_BANKS];
   logic [(N_BANKS - 1):0]             bank_is_active;
   logic                               wt_en;
   logic [(INTERNAL_ADDR_WIDTH - 1):0] wt_addr;
   logic [7:0]                         wt_length;
   logic                               wt_pending;
   logic [($clog2(N_BANKS) - 1):0]     wt_bank_addr;
   logic [(COL_ADDR_WIDTH - 1):0]      wt_col_addr;
   logic [(ROW_ADDR_WIDTH - 1):0]      wt_row_addr;
   logic [(INTERNAL_ADDR_WIDTH - 1):0] rd_addr;
   logic [7:0]                         rd_length;
   logic                               rd_pending;
   logic [($clog2(N_BANKS) - 1):0]     rd_bank_addr;
   logic [(COL_ADDR_WIDTH - 1):0]      rd_col_addr;
   logic [(ROW_ADDR_WIDTH - 1):0]      rd_row_addr;
   cmd_t                               cmd;
   state_t                             state, state_nxt;

   always_ff @(posedge i_clk, posedge i_reset)
     begin: MANAGEMENT
        if (i_reset) begin
           for (int i = 0; i < N_BANKS; i++) begin
              bank_active_row[i] <= 0;
              bank_is_active[i] <= 0;
           end

           state <= S_INIT_SEQ_POWERON;
           delay_timer <= '0;
           refresh_timer <= TIMER_WIDTH'(T_REFRESH);
        end else begin
           delay_timer <= delay_timer_nxt;
           refresh_timer <= refresh_timer_nxt;
           state <= state_nxt;
           case (state)
             S_READ_SEQ_ROW_ACTIVATE:
               begin
                  bank_active_row[rd_bank_addr] <= rd_row_addr;
                  bank_is_active[rd_bank_addr] <= 1;
               end
             S_WRITE_SEQ_ROW_ACTIVATE:
               begin
                  bank_active_row[wt_bank_addr] <= wt_row_addr;
                  bank_is_active[wt_bank_addr] <= 1;
               end
             S_AUTO_REFRESH_SEQ_PRECHARGE:
               begin
                  for (int i = 0; i < N_BANKS; i++) begin
                     bank_is_active[i] <= 0;
                  end
               end
             default:;
           endcase
        end
     end

   always_ff @(posedge i_clk, posedge i_reset)
     begin: AXI4
        if (i_reset) begin
           rd_addr <= '0;
           rd_length <= '0;
           rd_pending <= '0;

           wt_addr <= '0;
           wt_length <= '0;
           wt_pending <= '0;
        end else begin
           if (wt_pending && state == S_WRITE_SEQ_WRITE && state_nxt != S_WRITE_SEQ_WRITE) begin
              // The bus transfer may be longer than the SDRAM burst.
              // Determine if we are done yet.
              wt_length <= wt_length - 8'(SDRAM_BURST_LENGTH);
              wt_addr <= wt_addr + INTERNAL_ADDR_WIDTH'(SDRAM_BURST_LENGTH);
              if (wt_length == SDRAM_BURST_LENGTH - 1) begin
                 wt_pending <= 0;
              end
           end else if (axi_bus.m_awvalid && !wt_pending) begin
              // Start a write burst
              // axi_bus.m_awaddr is in terms of bytes.  Convert to # of transfers.
              wt_addr <= INTERNAL_ADDR_WIDTH'(axi_bus.m_awaddr[AXI_ADDR_WIDTH - 1:$clog2(DATA_WIDTH / 8)]);
              wt_length <= axi_bus.m_awlen;
              wt_pending <= 1'b1;
           end

           if (rd_pending && state == S_READ_SEQ_READ && state_nxt != S_READ_SEQ_READ) begin
              rd_length <= rd_length - 8'(SDRAM_BURST_LENGTH);
              rd_addr <= rd_addr + INTERNAL_ADDR_WIDTH'(SDRAM_BURST_LENGTH);
              if (rd_length == SDRAM_BURST_LENGTH - 1) begin
                 rd_pending <= 0;
              end
           end else if (axi_bus.m_arvalid && !rd_pending) begin
              // Start a read burst
              // axi_bus.m_araddr is in terms of bytes.  Convert to # of transfers.
              rd_addr <= INTERNAL_ADDR_WIDTH'(axi_bus.m_araddr[AXI_ADDR_WIDTH - 1:$clog2(DATA_WIDTH / 8)]);
              rd_length <= axi_bus.m_arlen;
              rd_pending <= 1'b1;
           end
        end
     end

   always_comb
     begin: FSM
        cmd = CMD_NOP;
        o_dram_ba = 0;
        o_dram_addr = 0;
        o_dram_dqm = 2'b11;
        wt_en = 0;
        delay_timer_nxt = 0;
        state_nxt = state;

        if (refresh_timer != 0) begin
           refresh_timer_nxt = refresh_timer - TIMER_WIDTH'(1);
        end else begin
           refresh_timer_nxt = 0;
        end

        if (delay_timer != 0) begin
           delay_timer_nxt = delay_timer - TIMER_WIDTH'(1);
        end else begin
           case (state)
             S_IDLE:
               begin
                  if (refresh_timer == 0) begin
                     state_nxt = |bank_is_active ? S_AUTO_REFRESH_SEQ_PRECHARGE : S_AUTO_REFRESH_SEQ_AUTO_REFRESH;
                  end else if (rd_pending && (!wt_pending || wt_addr != rd_addr)) begin
                     if (!bank_is_active[rd_bank_addr]) begin
                        state_nxt = S_READ_SEQ_ROW_ACTIVATE;
                     end else if (rd_row_addr != bank_active_row[rd_bank_addr]) begin
                        state_nxt = S_READ_SEQ_ROW_DEACTIVATE;
                     end else begin
                        state_nxt = S_READ_SEQ_CAS_WAIT;
                     end
                  end else if (wt_pending && (!rd_pending || wt_addr == rd_addr)) begin
                     if (!bank_is_active[wt_bank_addr]) begin
                        state_nxt = S_WRITE_SEQ_ROW_ACTIVATE;
                     end else if (wt_row_addr != bank_active_row[wt_bank_addr]) begin
                        state_nxt = S_WRITE_SEQ_ROW_DEACTIVATE;
                     end else begin
                        state_nxt = S_WRITE_SEQ_WRITE;
                     end
                  end
               end
             S_INIT_SEQ_POWERON:
               begin
                  delay_timer_nxt = TIMER_WIDTH'(T_POWERON);
                  state_nxt = S_INIT_SEQ_PRECHARGE;
               end
             S_INIT_SEQ_PRECHARGE:
               begin
                  cmd = CMD_PRECHARGE;
                  o_dram_addr = SDRAM_ADDR_WIDTH'('b00_1_0000000000);
                  delay_timer_nxt = TIMER_WIDTH'(T_ROW_PRECHARGE);
                  state_nxt = S_INIT_SEQ_AUTO_REFRESH0;
               end
             S_INIT_SEQ_AUTO_REFRESH0:
               begin
                  cmd = CMD_AUTO_REFRESH;
                  delay_timer_nxt = TIMER_WIDTH'(T_AUTO_REFRESH_CYCLE);
                  refresh_timer_nxt = TIMER_WIDTH'(T_REFRESH);
                  state_nxt = S_INIT_SEQ_AUTO_REFRESH1;
               end
             S_INIT_SEQ_AUTO_REFRESH1:
               begin
                  cmd = CMD_AUTO_REFRESH;
                  delay_timer_nxt = TIMER_WIDTH'(T_AUTO_REFRESH_CYCLE);
                  refresh_timer_nxt = TIMER_WIDTH'(T_REFRESH);
                  state_nxt = S_INIT_SEQ_MODE_REGISTER_SET;
               end
             S_INIT_SEQ_MODE_REGISTER_SET:
               begin
                  cmd = CMD_MODE_REGISTER_SET;
                  o_dram_ba = 2'b00;
                  o_dram_addr = SDRAM_MODE;
                  state_nxt = S_IDLE;
               end
             S_READ_SEQ_ROW_DEACTIVATE:
               begin
                  cmd = CMD_PRECHARGE;
                  o_dram_ba = rd_bank_addr;
                  o_dram_addr = 0;
                  delay_timer_nxt = TIMER_WIDTH'(T_ROW_PRECHARGE);
                  state_nxt = S_READ_SEQ_ROW_ACTIVATE;
               end
             S_READ_SEQ_ROW_ACTIVATE:
               begin
                  cmd = CMD_ROW_ACTIVATE;
                  o_dram_ba = rd_bank_addr;
                  o_dram_addr = SDRAM_ADDR_WIDTH'(rd_row_addr);
                  delay_timer_nxt = TIMER_WIDTH'(T_RAS_CAS_DELAY);
                  state_nxt = S_READ_SEQ_CAS_WAIT;
               end
             S_READ_SEQ_CAS_WAIT:
               begin
                  cmd = CMD_READ;
                  o_dram_ba = rd_bank_addr;
                  o_dram_addr = SDRAM_ADDR_WIDTH'(rd_col_addr);
                  o_dram_dqm = 2'b00;
                  delay_timer_nxt = TIMER_WIDTH'(T_CAS_LATENCY);
                  state_nxt = S_READ_SEQ_READ;
               end
             S_READ_SEQ_READ:
               begin
                  state_nxt = S_IDLE;
               end
             S_WRITE_SEQ_ROW_DEACTIVATE:
               begin
                  cmd = CMD_PRECHARGE;
                  o_dram_ba = wt_bank_addr;
                  o_dram_addr = 0;
                  delay_timer_nxt = TIMER_WIDTH'(T_ROW_PRECHARGE);
                  state_nxt = S_WRITE_SEQ_ROW_ACTIVATE;
               end
             S_WRITE_SEQ_ROW_ACTIVATE:
               begin
                  cmd = CMD_ROW_ACTIVATE;
                  o_dram_ba = wt_bank_addr;
                  o_dram_addr = SDRAM_ADDR_WIDTH'(wt_row_addr);
                  delay_timer_nxt = TIMER_WIDTH'(T_RAS_CAS_DELAY);
                  state_nxt = S_WRITE_SEQ_WRITE;
               end
             S_WRITE_SEQ_WRITE:
               begin
                  cmd = CMD_WRITE;
                  o_dram_ba = wt_bank_addr;
                  o_dram_addr = SDRAM_ADDR_WIDTH'(wt_col_addr);
                  o_dram_dqm = 2'b00;
                  wt_en = 1;
                  state_nxt = S_IDLE;
               end
             S_AUTO_REFRESH_SEQ_PRECHARGE:
               begin
                  cmd = CMD_PRECHARGE;
                  o_dram_addr = SDRAM_ADDR_WIDTH'('b00_1_0000000000);
                  delay_timer_nxt = TIMER_WIDTH'(T_ROW_PRECHARGE);
                  state_nxt = S_AUTO_REFRESH_SEQ_AUTO_REFRESH;
               end
             S_AUTO_REFRESH_SEQ_AUTO_REFRESH:
               begin
                  cmd = CMD_AUTO_REFRESH;
                  delay_timer_nxt = TIMER_WIDTH'(T_AUTO_REFRESH_CYCLE);
                  refresh_timer_nxt = TIMER_WIDTH'(T_REFRESH);
                  state_nxt = S_IDLE;
               end
             default:
               begin
                  state_nxt = S_IDLE;
               end
           endcase
        end
     end

   assign {wt_row_addr, wt_bank_addr, wt_col_addr} = wt_addr;
   assign {rd_row_addr, rd_bank_addr, rd_col_addr} = rd_addr;

   assign {o_dram_cs_n, o_dram_ras_n, o_dram_cas_n, o_dram_we_n} = cmd;
   assign io_dram_dq = wt_en ? axi_bus.m_wdata : {DATA_WIDTH{1'hZ}};
   assign o_dram_cke = 1'b1;

   assign axi_bus.s_arready = !rd_pending;
   assign axi_bus.s_awready = !wt_pending;
   assign axi_bus.s_rvalid = (state == S_READ_SEQ_READ && state_nxt == S_IDLE) ? 1'b1 : 1'b0;
   assign axi_bus.s_wready = (state == S_IDLE && state_nxt == S_IDLE) ? 1'b1 : 1'b0;
   // assign axi_bus.s_wready = wt_en;
   assign axi_bus.s_bvalid = 1;
   assign axi_bus.s_rdata = (axi_bus.m_rready && axi_bus.s_rvalid) ? io_dram_dq : DATA_WIDTH'(0);

endmodule
