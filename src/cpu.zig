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

pub fn printInstruction(instruction: Instruction) void {
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

pub const Cpu = struct {
    pc: u32,
    registers: [32]u32,
    cp0_registers: [32][8]u32,
    next_instruction: Instruction,

    load_delay: struct { reg: u5, value: u32 },
    current_write: struct { reg: u5, value: u32 },

    bus: *Bus,

    const Self = @This();

    pub fn init(bus: *Bus) Self {
        return .{
            .pc = 0xbfc0_0000,
            .registers = [_]u32{0xdeadfeed} ** 32,
            .cp0_registers = [_][8]u32{[_]u32{0} ** 8} ** 32,
            .next_instruction = .{ .raw = 0 },
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
        const instruction = self.next_instruction;
        self.next_instruction = @bitCast(self.bus.read(self.pc));
        self.pc = self.pc +% 4;

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
                    else => unreachable,
                }
            },
            0b010000 => {
                switch (instruction.cop0_move.sub) {
                    0b00100 => self.op_mtc0(instruction),
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

            0b000010 => self.op_j(instruction),
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
        var pc = self.pc +% (offset << 2);
        pc -%= 4; // compensate for branch delay

        self.pc = pc;
    }

    // cop0
    fn op_mtc0(self: *Self, instruction: Instruction) void {
        const c = instruction.cop0_move;

        const value = self.registers[c.rt];

        self.setCp0Reg(c.rd, c.sel, value);
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

        self.bus.write(address, value);
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
        const value = self.bus.read(address);

        // delayed write
        self.setRegDelayed(i.rt, value);
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

    // j-type
    fn op_j(self: *Self, instruction: Instruction) void {
        const j = instruction.j;

        self.pc = self.pc & 0xf000_0000 | @as(u32, j.address) << 2;
    }
};
