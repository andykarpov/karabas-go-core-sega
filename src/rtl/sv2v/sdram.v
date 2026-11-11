module sdram (
	SDRAM_DQ,
	SDRAM_A,
	SDRAM_DQML,
	SDRAM_DQMH,
	SDRAM_BA,
	SDRAM_nCS,
	SDRAM_nWE,
	SDRAM_nRAS,
	SDRAM_nCAS,
	init_n,
	clk,
	romwr_req,
	romwr_ack,
	romwr_a,
	romwr_d,
	romrd_req,
	romrd_ack,
	romrd_a,
	romrd_q,
	ram68k_req,
	ram68k_ack,
	ram68k_we,
	ram68k_a,
	ram68k_d,
	ram68k_q,
	ram68k_u_n,
	ram68k_l_n,
	sram_req,
	sram_ack,
	sram_we,
	sram_a,
	sram_d,
	sram_q,
	sram_u_n,
	sram_l_n,
	vram_req,
	vram_ack,
	vram_we,
	vram_a,
	vram_d,
	vram_q,
	vram_u_n,
	vram_l_n,
	vram32_req,
	vram32_ack,
	vram32_a,
	vram32_q,
	svp_ram1_req,
	svp_ram1_ack,
	svp_ram1_we,
	svp_ram1_a,
	svp_ram1_d,
	svp_ram1_q,
	svp_ram2_req,
	svp_ram2_ack,
	svp_ram2_we,
	svp_ram2_a,
	svp_ram2_d,
	svp_ram2_q,
	svp_ram2_u_n,
	svp_ram2_l_n,
	svp_rom_req,
	svp_rom_ack,
	svp_rom_a,
	svp_rom_q
);
	inout wire [15:0] SDRAM_DQ;
	output reg [12:0] SDRAM_A;
	output reg SDRAM_DQML;
	output reg SDRAM_DQMH;
	output reg [1:0] SDRAM_BA;
	output wire SDRAM_nCS;
	output wire SDRAM_nWE;
	output wire SDRAM_nRAS;
	output wire SDRAM_nCAS;
	input init_n;
	input clk;
	input romwr_req;
	output reg romwr_ack;
	input [23:1] romwr_a;
	input [15:0] romwr_d;
	input romrd_req;
	output reg romrd_ack;
	input [23:1] romrd_a;
	output reg [15:0] romrd_q;
	input ram68k_req;
	output reg ram68k_ack;
	input ram68k_we;
	input [15:1] ram68k_a;
	input [15:0] ram68k_d;
	output reg [15:0] ram68k_q;
	input ram68k_u_n;
	input ram68k_l_n;
	input sram_req;
	output reg sram_ack;
	input sram_we;
	input [15:1] sram_a;
	input [15:0] sram_d;
	output reg [15:0] sram_q;
	input sram_u_n;
	input sram_l_n;
	input vram_req;
	output reg vram_ack;
	input vram_we;
	input [15:1] vram_a;
	input [15:0] vram_d;
	output reg [15:0] vram_q;
	input vram_u_n;
	input vram_l_n;
	input vram32_req;
	output reg vram32_ack;
	input [15:1] vram32_a;
	output reg [31:0] vram32_q;
	input svp_ram1_req;
	output reg svp_ram1_ack;
	input svp_ram1_we;
	input [16:1] svp_ram1_a;
	input [15:0] svp_ram1_d;
	output reg [15:0] svp_ram1_q;
	input svp_ram2_req;
	output reg svp_ram2_ack;
	input svp_ram2_we;
	input [16:1] svp_ram2_a;
	input [15:0] svp_ram2_d;
	output reg [15:0] svp_ram2_q;
	input svp_ram2_u_n;
	input svp_ram2_l_n;
	input svp_rom_req;
	output reg svp_rom_ack;
	input [23:1] svp_rom_a;
	output reg [15:0] svp_rom_q;
	localparam RASCAS_DELAY = 3'd3;
	localparam BURST_LENGTH = 3'b001;
	localparam ACCESS_TYPE = 1'b0;
	localparam CAS_LATENCY = 3'd3;
	localparam OP_MODE = 2'b00;
	localparam NO_WRITE_BURST = 1'b0;
	localparam MODE = {3'b000, NO_WRITE_BURST, OP_MODE, CAS_LATENCY, ACCESS_TYPE, BURST_LENGTH};
	localparam RFRSH_CYCLES = 11'd842;
	localparam STATE_RAS0 = 4'd0;
	localparam STATE_RAS1 = 4'd4;
	localparam STATE_CAS0 = STATE_RAS0 + RASCAS_DELAY;
	localparam STATE_CAS1 = 4'd8;
	localparam STATE_CAS1b = 4'd0;
	localparam STATE_DS0 = STATE_CAS0 + 1'd1;
	localparam STATE_DS0b = STATE_CAS0 + 4'd2;
	localparam STATE_READ0 = (STATE_CAS0 + CAS_LATENCY) + 4'd2;
	localparam STATE_READ0b = 4'd0;
	localparam STATE_DS1 = 4'd0;
	localparam STATE_READ1 = 4'd4;
	localparam STATE_LAST = 4'd8;
	reg [3:0] t;
	localparam PORT_NONE = 4'd0;
	reg init = 1'b1;
	reg [3:0] next_port [0:1];
	reg [1:0] oe_latch;
	reg refresh;
	reg [1:0] we_latch;
	always @(posedge clk) begin
		t <= t + 1'd1;
		if ((((((t == 4'd4) && !oe_latch[1]) && !we_latch[1]) && (next_port[0] == PORT_NONE)) && !refresh) && !init)
			t <= STATE_RAS0;
		if (t == STATE_LAST)
			t <= STATE_RAS0;
	end
	reg [4:0] reset;
	always @(posedge clk or negedge init_n)
		if (!init_n) begin
			reset <= 5'h1f;
			init <= 1'b1;
		end
		else begin
			if ((t == STATE_LAST) && (reset != 0))
				reset <= reset - 5'd1;
			init <= reset != 0;
		end
	localparam CMD_INHIBIT = 4'b1111;
	localparam CMD_NOP = 4'b0111;
	localparam CMD_ACTIVE = 4'b0011;
	localparam CMD_READ = 4'b0101;
	localparam CMD_WRITE = 4'b0100;
	localparam CMD_BURST_TERMINATE = 4'b0110;
	localparam CMD_PRECHARGE = 4'b0010;
	localparam CMD_AUTO_REFRESH = 4'b0001;
	localparam CMD_LOAD_MODE = 4'b0000;
	reg [3:0] sd_cmd;
	reg [15:0] sd_din;
	assign SDRAM_nCS = sd_cmd[3];
	assign SDRAM_nRAS = sd_cmd[2];
	assign SDRAM_nCAS = sd_cmd[1];
	assign SDRAM_nWE = sd_cmd[0];
	reg [24:1] addr_latch [0:1];
	reg [24:1] addr_latch_next [0:1];
	reg [15:0] din_latch [0:1];
	reg [15:0] din_next [0:1];
	reg [1:0] oe_next;
	reg [1:0] we_next;
	reg [1:0] ds [0:1];
	reg [1:0] ds_next [0:1];
	reg [15:0] dq_reg;
	reg drive_dq;
	assign SDRAM_DQ = (drive_dq ? dq_reg : 16'bzzzzzzzzzzzzzzzz);
	localparam PORT_SRAM = 4'd1;
	localparam PORT_ROM = 4'd2;
	localparam PORT_RAM68K = 4'd3;
	localparam PORT_VRAM = 4'd4;
	localparam PORT_VRAM32 = 4'd5;
	localparam PORT_SVP1 = 4'd6;
	localparam PORT_SVP2 = 4'd7;
	localparam PORT_SVPROM = 4'd8;
	localparam PORT_ROMWR = 4'd9;
	reg port_state [0:9];
	reg [3:0] port [0:1];
	reg [10:0] refresh_cnt;
	wire need_refresh = refresh_cnt >= RFRSH_CYCLES;
	always @(*) begin
		din_next[0] = 0;
		if (refresh) begin
			next_port[0] = PORT_NONE;
			addr_latch_next[0] = addr_latch[0];
			{oe_next[0], we_next[0]} = 0;
			ds_next[0] = 0;
		end
		else if (sram_req ^ port_state[PORT_SRAM]) begin
			next_port[0] = PORT_SRAM;
			addr_latch_next[0] = {9'b101111111, sram_a};
			{oe_next[0], we_next[0]} = {~sram_we, sram_we};
			ds_next[0] = {~sram_u_n, ~sram_l_n};
			din_next[0] = sram_d;
		end
		else if (romwr_req ^ port_state[PORT_ROMWR]) begin
			next_port[0] = PORT_ROMWR;
			addr_latch_next[0] = {1'b0, romwr_a};
			{oe_next[0], we_next[0]} = 2'b01;
			ds_next[0] = 2'b11;
			din_next[0] = romwr_d;
		end
		else if (romrd_req ^ port_state[PORT_ROM]) begin
			next_port[0] = PORT_ROM;
			addr_latch_next[0] = {1'b0, romrd_a};
			{oe_next[0], we_next[0]} = 2'b10;
			ds_next[0] = 2'b11;
		end
		else if (ram68k_req ^ port_state[PORT_RAM68K]) begin
			next_port[0] = PORT_RAM68K;
			addr_latch_next[0] = {9'b101111110, ram68k_a};
			{oe_next[0], we_next[0]} = {~ram68k_we, ram68k_we};
			ds_next[0] = {~ram68k_u_n, ~ram68k_l_n};
			din_next[0] = ram68k_d;
		end
		else if (svp_ram1_req ^ port_state[PORT_SVP1]) begin
			next_port[0] = PORT_SVP1;
			addr_latch_next[0] = {8'b10111110, svp_ram1_a};
			{oe_next[0], we_next[0]} = {~svp_ram1_we, svp_ram1_we};
			ds_next[0] = 2'b11;
			din_next[0] = svp_ram1_d;
		end
		else if (svp_ram2_req ^ port_state[PORT_SVP2]) begin
			next_port[0] = PORT_SVP2;
			addr_latch_next[0] = {8'b10111110, svp_ram2_a};
			{oe_next[0], we_next[0]} = {~svp_ram2_we, svp_ram2_we};
			ds_next[0] = {~svp_ram2_u_n, ~svp_ram2_l_n};
			din_next[0] = svp_ram2_d;
		end
		else if (svp_rom_req ^ port_state[PORT_SVPROM]) begin
			next_port[0] = PORT_SVPROM;
			addr_latch_next[0] = {1'b0, svp_rom_a};
			{oe_next[0], we_next[0]} = 2'b10;
			ds_next[0] = 2'b11;
		end
		else begin
			next_port[0] = PORT_NONE;
			addr_latch_next[0] = addr_latch[0];
			{oe_next[0], we_next[0]} = 0;
			ds_next[0] = 0;
		end
	end
	always @(*)
		if (vram_req ^ port_state[PORT_VRAM]) begin
			next_port[1] = PORT_VRAM;
			addr_latch_next[1] = {9'b111111111, vram_a};
			{oe_next[1], we_next[1]} = {~vram_we, vram_we};
			ds_next[1] = {~vram_u_n, ~vram_l_n};
		end
		else if (vram32_req ^ port_state[PORT_VRAM32]) begin
			next_port[1] = PORT_VRAM32;
			addr_latch_next[1] = {9'b111111111, vram32_a};
			{oe_next[1], we_next[1]} = 2'b10;
			ds_next[1] = 2'b11;
		end
		else begin
			next_port[1] = PORT_NONE;
			addr_latch_next[1] = addr_latch[1];
			{oe_next[1], we_next[1]} = 0;
			ds_next[1] = 0;
		end
	always @(posedge clk) begin
		sd_din <= SDRAM_DQ;
		drive_dq <= 1'b0;
		{SDRAM_DQMH, SDRAM_DQML} <= 2'b11;
		sd_cmd <= CMD_NOP;
		refresh_cnt <= refresh_cnt + 1'd1;
		if (init) begin
			if (t == STATE_RAS0) begin
				if (reset == 15) begin
					sd_cmd <= CMD_PRECHARGE;
					SDRAM_A[10] <= 1'b1;
				end
				if ((reset == 10) || (reset == 8))
					sd_cmd <= CMD_AUTO_REFRESH;
				if (reset == 2) begin
					sd_cmd <= CMD_LOAD_MODE;
					SDRAM_A <= MODE;
					SDRAM_BA <= 2'b00;
				end
			end
		end
		else begin
			if (t == STATE_RAS1) begin
				port[0] <= next_port[0];
				addr_latch[0] <= addr_latch_next[0];
				{oe_latch[0], we_latch[0]} <= {oe_next[0], we_next[0]};
				ds[0] <= ds_next[0];
				din_latch[0] <= din_next[0];
				if (next_port[0] != PORT_NONE) begin
					port_state[next_port[0]] <= ~port_state[next_port[0]];
					SDRAM_A <= addr_latch_next[0][22:10];
					SDRAM_BA <= addr_latch_next[0][24:23];
				end
			end
			if ((t == (STATE_RAS1 + 1)) && (port[0] != PORT_NONE))
				sd_cmd <= CMD_ACTIVE;
			if (t == STATE_RAS0) begin
				refresh <= 1'b0;
				port[1] <= next_port[1];
				addr_latch[1] <= addr_latch_next[1];
				{oe_latch[1], we_latch[1]} <= {oe_next[1], we_next[1]};
				ds[1] <= ds_next[1];
				din_latch[1] <= vram_d;
				if (next_port[1] != PORT_NONE) begin
					port_state[next_port[1]] <= ~port_state[next_port[1]];
					sd_cmd <= CMD_ACTIVE;
					SDRAM_A <= addr_latch_next[1][22:10];
					SDRAM_BA <= addr_latch_next[1][24:23];
				end
				if ((((next_port[1] == PORT_NONE) && need_refresh) && !we_latch[0]) && !oe_latch[0]) begin
					refresh <= 1'b1;
					refresh_cnt <= 0;
					sd_cmd <= CMD_AUTO_REFRESH;
				end
			end
			if ((t == STATE_CAS1) && (we_latch[0] || oe_latch[0])) begin
				sd_cmd <= (we_latch[0] ? CMD_WRITE : CMD_READ);
				if (we_latch[0]) begin
					dq_reg <= din_latch[0];
					{SDRAM_DQMH, SDRAM_DQML} <= ~ds[0] | {2 {we_latch[0]}};
					case (port[0])
						PORT_ROMWR: romwr_ack <= romwr_req;
						PORT_SRAM: sram_ack <= sram_req;
						PORT_RAM68K: ram68k_ack <= ram68k_req;
						PORT_SVP1: svp_ram1_ack <= svp_ram1_req;
						PORT_SVP2: svp_ram2_ack <= svp_ram2_req;
						default:
							;
					endcase
				end
				SDRAM_A <= {4'b0010, addr_latch[0][9:2], addr_latch[0][1] ^ we_latch[0]};
				SDRAM_BA <= addr_latch[0][24:23];
			end
			if ((t == STATE_CAS1b) && we_latch[0]) begin
				{SDRAM_DQMH, SDRAM_DQML} <= ~ds[0];
				drive_dq <= 1'b1;
			end
			if ((t == STATE_CAS0) && (we_latch[1] || oe_latch[1])) begin
				sd_cmd <= (we_latch[1] ? CMD_WRITE : CMD_READ);
				if (we_latch[1]) begin
					dq_reg <= din_latch[1];
					{SDRAM_DQMH, SDRAM_DQML} <= ~ds[1] | {2 {we_latch[1]}};
					if (port[1] == PORT_VRAM)
						vram_ack <= vram_req;
				end
				SDRAM_A <= {4'b0010, addr_latch[1][9:2], addr_latch[1][1] ^ we_latch[1]};
				SDRAM_BA <= addr_latch[1][24:23];
			end
			if ((t == (STATE_CAS0 + 1)) && we_latch[1]) begin
				{SDRAM_DQMH, SDRAM_DQML} <= ~ds[1];
				drive_dq <= 1'b1;
			end
			if ((t == STATE_DS1) && oe_latch[0])
				{SDRAM_DQMH, SDRAM_DQML} <= ~ds[0];
			if ((t == STATE_READ1) && oe_latch[0])
				case (port[0])
					PORT_ROM: begin
						romrd_q <= sd_din;
						romrd_ack <= romrd_req;
					end
					PORT_RAM68K: begin
						ram68k_q <= sd_din;
						ram68k_ack <= ram68k_req;
					end
					PORT_SRAM: begin
						sram_q <= sd_din;
						sram_ack <= sram_req;
					end
					PORT_SVP1: begin
						svp_ram1_q <= sd_din;
						svp_ram1_ack <= svp_ram1_req;
					end
					PORT_SVP2: begin
						svp_ram2_q <= sd_din;
						svp_ram2_ack <= svp_ram2_req;
					end
					PORT_SVPROM: begin
						svp_rom_q <= sd_din;
						svp_rom_ack <= svp_rom_req;
					end
					default:
						;
				endcase
			if (((t == STATE_DS0) || (t == STATE_DS0b)) && oe_latch[1])
				{SDRAM_DQMH, SDRAM_DQML} <= ~ds[1];
			if ((t == STATE_READ0) && oe_latch[1])
				case (port[1])
					PORT_VRAM32: vram32_q[15:0] <= sd_din;
					PORT_VRAM: begin
						vram_q <= sd_din;
						vram_ack <= vram_req;
					end
					default:
						;
				endcase
			if ((t == STATE_READ0b) && oe_latch[1])
				case (port[1])
					PORT_VRAM32: begin
						vram32_q[31:16] <= sd_din;
						vram32_ack <= vram32_req;
					end
					default:
						;
				endcase
		end
	end
endmodule
