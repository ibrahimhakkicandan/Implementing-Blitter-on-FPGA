`ifndef DEFINES_SV
`define DEFINES_SV

package defines;
   typedef logic [15:0] data_t;
   typedef logic [15:0] addr_t;

   parameter AXI_ADDR_WIDTH = 16;
   parameter AXI_DATA_WIDTH = 16;
endpackage

interface intf_mmu;
   logic           ready;
   logic           valid;
   logic           wt_en;
   logic           rd_en;
   defines::addr_t rd_addr;
   defines::addr_t wt_addr;
   defines::data_t wt_data;
   defines::data_t rd_data;

   modport master(output wt_en, rd_en, wt_addr, wt_data, rd_addr, input rd_data, ready, valid);
   modport slave(input wt_en, rd_en, wt_addr, wt_data, rd_addr, output rd_data, ready, valid);
endinterface

interface intf_sram;
   logic           wt_en;
   defines::addr_t wt_addr;
   defines::data_t wt_data;
   defines::addr_t rd_addr;
   defines::data_t rd_data;

   modport master(output wt_en, wt_addr, wt_data, rd_addr, input rd_data);
   modport slave(input wt_en, wt_addr, wt_data, rd_addr, output rd_data);
endinterface

interface intf_rom;
   defines::addr_t rd_addr;
   defines::data_t rd_data;

   modport master(output rd_addr, input rd_data);
   modport slave(input rd_addr, output rd_data);
endinterface


interface intf_peripheral;
   logic           wt_en;
   logic           rd_en;
   defines::addr_t addr;
   defines::data_t wt_data;
   defines::data_t rd_data;

   modport master(output wt_en, rd_en, addr, wt_data, input rd_data);
   modport slave(input wt_en, rd_en, addr, wt_data, output rd_data);
endinterface

// AMBA AXI-4 bus interface
// See table A10-1 and A10-3 for default values of optional signals not included here.
interface intf_axi4;
   // Global signals (Table A2-1)
   logic m_aclk;
   logic m_aresetn;

   // Write address channel (Table A2-2)
   logic [AXI_ADDR_WIDTH - 1:0] m_awaddr;
   logic [7:0]                  m_awlen;
   logic [2:0]                  m_awsize;
   logic [2:0]                  m_awprot;
   logic                        m_awvalid;
   logic                        s_awready;

   // Write data channel (Table A2-3)
   logic [AXI_DATA_WIDTH - 1:0] m_wdata;
   logic                        m_wlast;
   logic                        m_wvalid;
   logic                        s_wready;

   // Write response channel (Table A2-4)
   logic s_bvalid;
   logic m_bready;

   // Read address channel (Table A2-5)
   logic [AXI_ADDR_WIDTH - 1:0] m_araddr;
   logic [7:0]                  m_arlen;
   logic [2:0]                  m_arsize;
   logic [2:0]                  m_arprot;
   logic                        m_arvalid;
   logic                        s_arready;

   // Read data channel (Table A2-6)
   logic [AXI_DATA_WIDTH - 1:0] s_rdata;
   logic                        s_rvalid;
   logic                        m_rready;

   modport master(input s_awready, s_wready, s_bvalid, s_arready, s_rvalid, s_rdata,
                  output m_awaddr, m_awlen, m_awsize, m_awvalid, m_wdata, m_wlast, m_wvalid, m_bready, m_araddr,
                  m_arlen, m_arsize, m_arvalid, m_rready, m_aclk, m_aresetn, m_arprot, m_awprot);
   modport slave(input m_awaddr, m_awlen, m_awsize, m_awvalid, m_wdata, m_wlast, m_wvalid, m_bready,
                 m_araddr, m_arlen, m_arsize, m_arvalid, m_rready, m_aclk, m_aresetn, m_arprot, m_awprot,
                 output s_awready, s_wready, s_bvalid, s_arready, s_rvalid, s_rdata);
endinterface

`endif
