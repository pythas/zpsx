const std = @import("std");
const Bus = @import("bus.zig").Bus;

pub inline fn signExtend(value: u16) u32 {
    return @bitCast(@as(i32, @as(i16, @bitCast(value))));
}

pub const Instruction = packed union {
    raw: u32,
    r: packed struct {
        funct: u6,
        sa: u5,
        rd: u5,
        rt: u5,
        rs: u5,
        opcode: u6,
    },
    i: packed struct {
        imm: u16,
        rt: u5,
        rs: u5,
        opcode: u6,
    },
    j: packed struct {
        address: u26,
        opcode: u6,
    },

    cop0_move: packed struct {
        sel: u3,
        zeros: u8,
        rd: u5,
        rt: u5,
        sub: u5,
        opcode: u6,
    },
};

const Exception = enum(u8) {
    syscall = 0x08,
};

pub const Cpu = struct {
    pc: u32,
    next_pc: u32,
    current_pc: u32,

    registers: [32]u32,
    cp0_registers: [32][8]u32,
    hi: u32,
    lo: u32,
    // next_instruction: Instruction,

    load_delay: struct { reg: u5, value: u32 },
    current_write: struct { reg: u5, value: u32 },

    bus: *Bus,

    const Self = @This();

    pub fn init(bus: *Bus) Self {
        const pc = 0xbfc0_0000;

        return .{
            .pc = pc,
            .next_pc = pc +% 4,
            .current_pc = pc,
            .registers = [_]u32{0xdeadfeed} ** 32,
            .cp0_registers = [_][8]u32{[_]u32{0} ** 8} ** 32,
            .hi = 0xdeadfeed,
            .lo = 0xdeadfeed,
            // .next_instruction = .{ .raw = 0 },
            .load_delay = .{ .reg = 0, .value = 0 },
            .current_write = .{ .reg = 0, .value = 0 },
            .bus = bus,
        };
    }

    pub fn deinit(self: *Self) void {
        _ = self;
    }

    fn getReg(self: *Self, index: u5) u32 {
        return self.registers[index];
    }

    fn setReg(self: *Self, index: u5, value: u32) void {
        self.current_write = .{ .reg = index, .value = value };
    }

    fn setRegDelayed(self: *Self, index: u5, value: u32) void {
        self.load_delay = .{ .reg = index, .value = value };
    }

    fn getCp0Reg(self: *Self, rd: u5, sel: u3) u32 {
        return self.cp0_registers[rd][sel];
    }

    fn setCp0Reg(self: *Self, rd: u5, sel: u3, value: u32) void {
        self.cp0_registers[rd][sel] = value;

        // TODO: handle side effects
    }

    fn isCacheIsolated(self: *Self) bool {
        const sr = self.getCp0Reg(12, 0);

        return (sr & 0x00010000) != 0;
    }

    pub fn step(self: *Self) void {
        // const instruction = self.next_instruction;
        //
        // self.next_instruction = @bitCast(self.bus.read32(self.pc));
        // self.pc = self.pc +% 4;

        const instruction: Instruction = @bitCast(self.bus.read32(self.pc));

        self.current_pc = self.pc;
        self.pc = self.next_pc;
        self.next_pc +%= 4;

        const pending_load = self.load_delay;

        self.load_delay = .{ .reg = 0, .value = 0 };
        self.current_write = .{ .reg = 0, .value = 0 };

        printInstruction(instruction);

        const opcode = instruction.r.opcode;

        switch (opcode) {
            0b000000 => {
                switch (instruction.r.funct) {
                    0b000000 => self.op_sll(instruction),
                    0b100101 => self.op_or(instruction),
                    0b100001 => self.op_addu(instruction),
                    0b101011 => self.op_sltu(instruction),
                    0b001000 => self.op_jr(instruction),
                    0b100100 => self.op_and(instruction),
                    0b100000 => self.op_add(instruction),
                    0b001001 => self.op_jalr(instruction),
                    0b100011 => self.op_subu(instruction),
                    0b000011 => self.op_sra(instruction),
                    0b011010 => self.op_div(instruction),
                    0b010010 => self.op_mflo(instruction),
                    0b000010 => self.op_srl(instruction),
                    0b011011 => self.op_divu(instruction),
                    0b010000 => self.op_mfhi(instruction),
                    0b101010 => self.op_slt(instruction),
                    0b001100 => self.op_syscall(instruction),
                    0b010011 => self.op_mtlo(instruction),
                    0b010001 => self.op_mthi(instruction),
                    else => unreachable,
                }
            },
            0b010000 => {
                switch (instruction.cop0_move.sub) {
                    0b00100 => self.op_mtc0(instruction),
                    0b00000 => self.op_mfc0(instruction),
                    else => unreachable,
                }
            },
            0b001111 => self.op_lui(instruction),
            0b001101 => self.op_ori(instruction),
            0b101011 => self.op_sw(instruction),
            0b001001 => self.op_addiu(instruction),
            0b000101 => self.op_bne(instruction),
            0b001000 => self.op_addi(instruction),
            0b100011 => self.op_lw(instruction),
            0b101001 => self.op_sh(instruction),
            0b001100 => self.op_andi(instruction),
            0b101000 => self.op_sb(instruction),
            0b100000 => self.op_lb(instruction),
            0b000100 => self.op_beq(instruction),
            0b000111 => self.op_bgtz(instruction),
            0b000110 => self.op_blez(instruction),
            0b100100 => self.op_lbu(instruction),
            0b000001 => {
                switch (instruction.i.rt) {
                    0b00000 => self.op_bltz(instruction),
                    0b00001 => self.op_bgez(instruction),
                    0b10000 => self.op_bltzal(instruction),
                    0b10001 => self.op_bgezal(instruction),
                    else => unreachable,
                }
            },
            0b001010 => self.op_slti(instruction),
            0b001011 => self.op_sltiu(instruction),

            0b000010 => self.op_j(instruction),
            0b000011 => self.op_jal(instruction),
            else => unreachable,
        }

        // apply pending load
        if (pending_load.reg != 0) {
            self.registers[pending_load.reg] = pending_load.value;
        }

        // apply current write
        if (self.current_write.reg != 0) {
            self.registers[self.current_write.reg] = self.current_write.value;
        }

        // hardwire $0 back to 0
        self.registers[0] = 0;
    }

    fn branch(self: *Self, offset: u32) void {
        // var pc = self.pc +% (offset << 2);
        // pc -%= 4; // compensate for branch delay

        self.next_pc = self.pc +% (offset << 2);
    }

    fn exception(self: *Self, cause: Exception) void {
        const sr = self.getCp0Reg(12, 0);
        const handler: u32 = if ((sr & (1 << 22)) != 0) 0xbfc0_0180 else 0x8000_0080;
        const mode = sr & 0x3f;

        // update status reg
        var new_sr = sr & ~@as(u32, 0x3f);
        new_sr |= (mode << 2) & 0x3f;
        self.setCp0Reg(12, 0, new_sr);

        // update cause reg with the exception
        const cause_code: u32 = @intFromEnum(cause);
        self.setCp0Reg(13, 0, cause_code << 2);

        // save current pc in epc
        self.setCp0Reg(14, 0, self.pc);

        self.pc = handler;
        self.next_pc = self.pc +% 4;
    }

    // cop0
    fn op_mtc0(self: *Self, instruction: Instruction) void {
        const c = instruction.cop0_move;

        const value = self.registers[c.rt];

        self.setCp0Reg(c.rd, c.sel, value);
    }

    fn op_mfc0(self: *Self, instruction: Instruction) void {
        const c = instruction.cop0_move;

        const value = self.getCp0Reg(c.rd, c.sel);

        // delayed write
        self.setRegDelayed(c.rt, value);
    }

    // i-type
    fn op_lui(self: *Self, instruction: Instruction) void {
        const i = instruction.i;

        const value: u32 = @as(u32, i.imm) << 16;

        self.setReg(i.rt, value);
    }

    fn op_ori(self: *Self, instruction: Instruction) void {
        const i = instruction.i;

        const value: u32 = self.getReg(i.rs) | i.imm;

        self.setReg(i.rt, value);
    }

    fn op_sw(self: *Self, instruction: Instruction) void {
        if (self.isCacheIsolated()) {
            std.debug.print("Ignoring store while cache is isolated\n", .{});
            return;
        }

        const i = instruction.i;

        const address = self.getReg(i.rs) +% signExtend(i.imm);
        const value = self.getReg(i.rt);

        self.bus.write32(address, value);
    }

    fn op_addiu(self: *Self, instruction: Instruction) void {
        const i = instruction.i;

        const value = self.getReg(i.rs) +% signExtend(i.imm);

        self.setReg(i.rt, value);
    }

    fn op_bne(self: *Self, instruction: Instruction) void {
        const i = instruction.i;

        if (self.getReg(i.rs) != self.getReg(i.rt)) {
            self.branch(signExtend(i.imm));
        }
    }

    fn op_addi(self: *Self, instruction: Instruction) void {
        const i = instruction.i;

        const rs_val: i32 = @bitCast(self.getReg(i.rs));
        const imm_val: i32 = @bitCast(signExtend(i.imm));

        const result = @addWithOverflow(rs_val, imm_val);

        if (result[1] != 0) {
            @panic("ADDI overflow"); // TODO: exception
        }

        self.setReg(i.rt, @bitCast(result[0]));
    }

    fn op_lw(self: *Self, instruction: Instruction) void {
        if (self.isCacheIsolated()) {
            std.debug.print("Ignoring load while cache is isolated\n", .{});
            return;
        }

        const i = instruction.i;

        const address = self.getReg(i.rs) +% signExtend(i.imm);
        const value = self.bus.read32(address);

        // delayed write
        self.setRegDelayed(i.rt, value);
    }

    fn op_sh(self: *Self, instruction: Instruction) void {
        if (self.isCacheIsolated()) {
            std.debug.print("Ignoring store while cache is isolated\n", .{});
            return;
        }

        const i = instruction.i;

        const address = self.getReg(i.rs) +% signExtend(i.imm);
        const value = self.getReg(i.rt);

        self.bus.write16(address, @truncate(value));
    }

    fn op_andi(self: *Self, instruction: Instruction) void {
        const i = instruction.i;

        const value: u32 = self.getReg(i.rs) & i.imm;

        self.setReg(i.rt, value);
    }

    fn op_sb(self: *Self, instruction: Instruction) void {
        if (self.isCacheIsolated()) {
            std.debug.print("Ignoring store while cache is isolated\n", .{});
            return;
        }

        const i = instruction.i;

        const address = self.getReg(i.rs) +% signExtend(i.imm);
        const value = self.getReg(i.rt);

        self.bus.write8(address, @truncate(value));
    }

    fn op_lb(self: *Self, instruction: Instruction) void {
        if (self.isCacheIsolated()) {
            std.debug.print("Ignoring load while cache is isolated\n", .{});
            return;
        }

        const i = instruction.i;

        const address = self.getReg(i.rs) +% signExtend(i.imm);
        const value = signExtend(@intCast(self.bus.read8(address)));

        // delayed write
        self.setRegDelayed(i.rt, value);
    }

    fn op_beq(self: *Self, instruction: Instruction) void {
        const i = instruction.i;

        if (self.getReg(i.rs) == self.getReg(i.rt)) {
            self.branch(signExtend(i.imm));
        }
    }

    fn op_bgtz(self: *Self, instruction: Instruction) void {
        const i = instruction.i;

        const value: i32 = @bitCast(self.getReg(i.rs));

        if (value > 0) {
            self.branch(signExtend(i.imm));
        }
    }

    fn op_blez(self: *Self, instruction: Instruction) void {
        const i = instruction.i;

        const value: i32 = @bitCast(self.getReg(i.rs));

        if (value <= 0) {
            self.branch(signExtend(i.imm));
        }
    }

    fn op_lbu(self: *Self, instruction: Instruction) void {
        if (self.isCacheIsolated()) {
            std.debug.print("Ignoring load while cache is isolated\n", .{});
            return;
        }

        const i = instruction.i;

        const address = self.getReg(i.rs) +% signExtend(i.imm);
        const value = self.bus.read8(address);

        // delayed write
        self.setRegDelayed(i.rt, value);
    }

    fn op_bltz(self: *Self, instruction: Instruction) void {
        const i = instruction.i;

        const value: i32 = @bitCast(self.getReg(i.rs));

        if (value < 0) {
            self.branch(signExtend(i.imm));
        }
    }

    fn op_bgez(self: *Self, instruction: Instruction) void {
        const i = instruction.i;

        const value: i32 = @bitCast(self.getReg(i.rs));

        if (value >= 0) {
            self.branch(signExtend(i.imm));
        }
    }

    fn op_bltzal(self: *Self, instruction: Instruction) void {
        const i = instruction.i;

        const value: i32 = @bitCast(self.getReg(i.rs));

        self.setReg(31, self.next_pc);

        if (value < 0) {
            self.branch(signExtend(i.imm));
        }
    }

    fn op_bgezal(self: *Self, instruction: Instruction) void {
        const i = instruction.i;

        const value: i32 = @bitCast(self.getReg(i.rs));

        self.setReg(31, self.next_pc);

        if (value >= 0) {
            self.branch(signExtend(i.imm));
        }
    }

    fn op_slti(self: *Self, instruction: Instruction) void {
        const i = instruction.i;

        const value: u32 = @intFromBool(@as(i32, @bitCast(self.getReg(i.rs))) < signExtend(i.imm));

        self.setReg(i.rt, value);
    }

    fn op_sltiu(self: *Self, instruction: Instruction) void {
        const i = instruction.i;

        const value: u32 = @intFromBool(self.getReg(i.rs) < signExtend(i.imm));

        self.setReg(i.rt, value);
    }

    // r-type
    fn op_sll(self: *Self, instruction: Instruction) void {
        const r = instruction.r;

        const value = self.getReg(r.rt) << r.sa;

        self.setReg(r.rd, value);
    }

    fn op_or(self: *Self, instruction: Instruction) void {
        const r = instruction.r;

        const value = self.getReg(r.rs) | self.getReg(r.rt);

        self.setReg(r.rd, value);
    }

    fn op_addu(self: *Self, instruction: Instruction) void {
        const r = instruction.r;

        const value = self.getReg(r.rs) +% self.getReg(r.rt);

        self.setReg(r.rd, value);
    }

    fn op_sltu(self: *Self, instruction: Instruction) void {
        const r = instruction.r;

        const value = self.getReg(r.rs) < self.getReg(r.rt);

        self.setReg(r.rd, if (value) 1 else 0);
    }

    fn op_jr(self: *Self, instruction: Instruction) void {
        const r = instruction.r;

        self.next_pc = self.getReg(r.rs);
    }

    fn op_and(self: *Self, instruction: Instruction) void {
        const r = instruction.r;

        const value = self.getReg(r.rs) & self.getReg(r.rt);

        self.setReg(r.rd, value);
    }

    fn op_add(self: *Self, instruction: Instruction) void {
        const r = instruction.r;

        const rs_val: i32 = @bitCast(self.getReg(r.rs));
        const rt_val: i32 = @bitCast(self.getReg(r.rt));

        const result = @addWithOverflow(rs_val, rt_val);

        if (result[1] != 0) {
            @panic("ADD overflow"); // TODO: exception
        }

        self.setReg(r.rd, @bitCast(result[0]));
    }

    fn op_jalr(self: *Self, instruction: Instruction) void {
        const r = instruction.r;

        self.setReg(r.rd, self.next_pc);
        self.next_pc = self.getReg(r.rs);
    }

    fn op_subu(self: *Self, instruction: Instruction) void {
        const r = instruction.r;

        const value = self.getReg(r.rs) -% self.getReg(r.rt);

        self.setReg(r.rd, value);
    }

    fn op_sra(self: *Self, instruction: Instruction) void {
        const r = instruction.r;

        const value = @as(i32, @bitCast(self.getReg(r.rt))) >> r.sa;

        self.setReg(r.rd, @bitCast(value));
    }

    fn op_div(self: *Self, instruction: Instruction) void {
        // TODO: division delay

        const r = instruction.r;

        const n: i32 = @bitCast(self.getReg(r.rs));
        const d: i32 = @bitCast(self.getReg(r.rt));

        if (d == 0) {
            self.hi = @bitCast(n);

            if (n >= 0) {
                self.lo = 0xffff_ffff;
            } else {
                self.lo = 0x0000_0001;
            }
        } else if (@as(u32, @bitCast(n)) == 0x8000_0000 and d == -1) {
            self.hi = 0x0000_0000;
            self.lo = 0x8000_0000;
        } else {
            self.hi = @bitCast(@rem(n, d));
            self.lo = @bitCast(@divTrunc(n, d));
        }
    }

    fn op_mflo(self: *Self, instruction: Instruction) void {
        const r = instruction.r;

        self.setReg(r.rd, self.lo);
    }

    fn op_srl(self: *Self, instruction: Instruction) void {
        const r = instruction.r;

        const value = self.getReg(r.rt) >> r.sa;

        self.setReg(r.rd, @bitCast(value));
    }

    fn op_divu(self: *Self, instruction: Instruction) void {
        // TODO: division delay..?

        const r = instruction.r;

        const n = self.getReg(r.rs);
        const d = self.getReg(r.rt);

        if (d == 0) {
            self.hi = n;

            self.lo = 0xffff_ffff;
        } else {
            self.hi = @rem(n, d);
            self.lo = @divTrunc(n, d);
        }
    }

    fn op_mfhi(self: *Self, instruction: Instruction) void {
        const r = instruction.r;

        self.setReg(r.rd, self.hi);
    }

    fn op_slt(self: *Self, instruction: Instruction) void {
        const r = instruction.r;

        const value = @as(i32, @bitCast(self.getReg(r.rs))) < @as(i32, @bitCast(self.getReg(r.rt)));

        self.setReg(r.rd, if (value) 1 else 0);
    }

    fn op_syscall(self: *Self, _: Instruction) void {
        self.exception(.syscall);
    }

    fn op_mtlo(self: *Self, instruction: Instruction) void {
        const r = instruction.r;

        self.lo = self.getReg(r.rs);
    }

    fn op_mthi(self: *Self, instruction: Instruction) void {
        const r = instruction.r;

        self.hi = self.getReg(r.rs);
    }

    // j-type
    fn op_j(self: *Self, instruction: Instruction) void {
        const j = instruction.j;

        self.next_pc = self.pc & 0xf000_0000 | @as(u32, j.address) << 2;
    }

    fn op_jal(self: *Self, instruction: Instruction) void {
        const j = instruction.j;

        self.setReg(31, self.next_pc);
        self.next_pc = self.pc & 0xf000_0000 | @as(u32, j.address) << 2;
    }
};

fn printInstruction(instruction: Instruction) void {
    const opcode = instruction.r.opcode;

    std.debug.print("Raw: 0x{X:0>8} | ", .{instruction.raw});

    switch (opcode) {
        0 => {
            const r = instruction.r;
            std.debug.print("R-Type: opcode={b:0>6} rs={d} rt={d} rd={d} sa={d} funct={d}\n", .{
                r.opcode, r.rs, r.rt, r.rd, r.sa, r.funct,
            });
        },
        2, 3 => {
            const j = instruction.j;
            std.debug.print("J-Type: opcode={b:0>6} address=0x{X:0>7}\n", .{
                j.opcode, j.address,
            });
        },
        else => {
            const i = instruction.i;
            std.debug.print("I-Type: opcode={b:0>6} rs={d} rt={d} imm=0x{X:0>4}\n", .{
                i.opcode, i.rs, i.rt, i.imm,
            });
        },
    }
}
