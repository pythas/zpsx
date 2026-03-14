// for mutl/multu:
// pending_hi: u32,
// pending_lo: u32,
// mul_delay: u32,
//
// todo:
// LWCn
// SWCn
// illegal instruction exception (0x0a)

const std = @import("std");
const Bus = @import("bus.zig").Bus;
const utils = @import("utils.zig");

pub const Cop0 = struct {
    data_registers: [32]u32,

    const Self = @This();

    pub fn init() Self {
        return .{
            .data_registers = [_]u32{0} ** 32,
        };
    }

    pub fn getDataRegister(self: *Self, register: u5) u32 {
        return self.data_registers[register];
    }

    pub fn setDataRegister(self: *Self, register: u5, value: u32) void {
        self.data_registers[register] = value;

        // TODO: handle side effects
    }
};

pub const Cop2 = struct {
    data_registers: [32]u32,
    control_registers: [32]u32,

    const Self = @This();

    pub fn init() Self {
        return .{
            .data_registers = [_]u32{0} ** 32,
            .control_registers = [_]u32{0} ** 32,
        };
    }

    pub fn getDataRegister(self: *Self, register: u5) u32 {
        return self.data_registers[register];
    }

    pub fn setDataRegister(self: *Self, register: u5, value: u32) void {
        self.data_registers[register] = value;

        // TODO: handle side effects
    }

    pub fn getControlRegister(self: *Self, register: u5) u32 {
        return self.control_registers[register];
    }

    pub fn setControlRegister(self: *Self, register: u5, value: u32) void {
        self.control_registers[register] = value;

        // TODO: handle side effects
    }
};

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

    cop_move: packed struct {
        zeros: u11,
        rd: u5,
        rt: u5,
        sub: u5,
        opcode: u6,
    },
};

const Exception = enum(u8) {
    interrupt = 0x00,
    syscall = 0x08,
    brk = 0x09,
    overflow = 0x0c,
    load_address_misaligned = 0x04,
    store_address_misaligned = 0x05,
    cop = 0x0b,
};

const LoadDelaySlot = struct {
    reg: u5,
    value: u32,
};

pub const Cpu = struct {
    pc: u32,
    next_pc: u32,
    current_pc: u32,

    cycles: u32,

    is_branch: bool,
    is_delay_slot: bool,

    registers: [32]u32,
    cop0: Cop0,
    cop2: Cop2,
    hi: u32,
    lo: u32,

    load: LoadDelaySlot,
    next_load: LoadDelaySlot,

    current_write: struct { reg: u5, value: u32 },

    bus: *Bus,

    const Self = @This();

    pub fn init(bus: *Bus) Self {
        const pc = 0xbfc0_0000;

        return .{
            .pc = pc,
            .next_pc = pc +% 4,
            .current_pc = pc,
            .cycles = 0,
            .is_branch = false,
            .is_delay_slot = false,
            .registers = [_]u32{0xdeadfeed} ** 32,
            .cop0 = Cop0.init(),
            .cop2 = Cop2.init(),
            .hi = 0xdeadfeed,
            .lo = 0xdeadfeed,
            .load = .{ .reg = 0, .value = 0 },
            .next_load = .{ .reg = 0, .value = 0 },
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
        self.next_load = .{ .reg = index, .value = value };
    }

    fn isCacheIsolated(self: *Self) bool {
        const sr = self.cop0.getDataRegister(12);

        return (sr & 0x00010000) != 0;
    }

    pub fn step(self: *Self) void {
        // // tty
        // const pc = self.pc & 0x1fff_ffff;
        // if (pc == 0xa0 and self.getReg(9) == 0x3c or (pc == 0xb0 and self.getReg(9) == 0x3d)) {
        //     const char: u8 = @truncate(self.getReg(4));
        //     std.debug.print("{c}", .{char});
        // }

        const current_cause = self.cop0.getDataRegister(13);
        if (self.bus.intc.is_active()) {
            self.cop0.setDataRegister(13, current_cause | 0x0400);
        } else {
            self.cop0.setDataRegister(13, current_cause & ~@as(u32, 0x0400));
        }

        // check IEc and IM2
        const sr = self.cop0.getDataRegister(12);
        if (!self.is_branch and (sr & 0x01) != 0 and (sr & 0x0400) != 0) {
            if (self.bus.intc.is_active()) {
                self.exception(.interrupt);
            }
        }

        // irq
        if (self.cycles % 564480 == 0) {
            self.bus.intc.trigger(.vblank);
        }

        const instruction: Instruction = @bitCast(self.bus.read32(self.pc));
        self.current_pc = self.pc;

        // check alignment
        if (self.current_pc % 4 != 0) {
            self.exception(.load_address_misaligned);
            return;
        }

        self.pc = self.next_pc;
        self.next_pc +%= 4;

        self.cycles += 1;

        self.load = self.next_load;
        self.next_load = .{ .reg = 0, .value = 0 };

        self.current_write = .{ .reg = 0, .value = 0 };

        self.is_delay_slot = self.is_branch;
        self.is_branch = false;

        self.bus.timers.step(1);
        self.bus.cdrom.step(1, &self.bus.intc);

        switch (instruction.r.opcode) {
            0b000000 => {
                switch (instruction.r.funct) {
                    0b000000 => self.opSll(instruction),
                    0b100101 => self.opOr(instruction),
                    0b100001 => self.opAddu(instruction),
                    0b101011 => self.opSltu(instruction),
                    0b001000 => self.opJr(instruction),
                    0b100100 => self.opAnd(instruction),
                    0b100000 => self.opAdd(instruction),
                    0b001001 => self.opJalr(instruction),
                    0b100011 => self.opSubu(instruction),
                    0b000011 => self.opSra(instruction),
                    0b011010 => self.opDiv(instruction),
                    0b010010 => self.opMflo(instruction),
                    0b000010 => self.opSrl(instruction),
                    0b011011 => self.opDivu(instruction),
                    0b010000 => self.opMfhi(instruction),
                    0b101010 => self.opSlt(instruction),
                    0b001100 => self.opSyscall(instruction),
                    0b010011 => self.opMtlo(instruction),
                    0b010001 => self.opMthi(instruction),
                    0b000100 => self.opSllv(instruction),
                    0b100111 => self.opNor(instruction),
                    0b000111 => self.opSrav(instruction),
                    0b000110 => self.opSrlv(instruction),
                    0b011001 => self.opMultu(instruction),
                    0b100110 => self.opXor(instruction),
                    0b001101 => self.opBreak(instruction),
                    0b011000 => self.opMult(instruction),
                    0b100010 => self.opSub(instruction),
                    else => unreachable,
                }
            },
            0b010000 => {
                switch (instruction.cop_move.sub) {
                    0b00100 => self.opMtcz(instruction),
                    0b00000 => self.opMfcz(instruction),
                    0b10000 => self.opRfe(instruction),

                    else => unreachable,
                }
            },
            0b010001 => {
                self.exception(.cop);
            },

            0b010011 => {
                self.exception(.cop);
            },
            0b010010 => {
                switch (instruction.cop_move.sub) {
                    0b00110 => self.opCtcz(instruction),
                    else => std.debug.print("NOPE: {b}\n", .{instruction.cop_move.sub}),
                }
            },
            0b001111 => self.opLui(instruction),
            0b001101 => self.opOri(instruction),
            0b101011 => self.opSw(instruction),
            0b001001 => self.opAddiu(instruction),
            0b000101 => self.opBne(instruction),
            0b001000 => self.opAddi(instruction),
            0b100011 => self.opLw(instruction),
            0b101001 => self.opSh(instruction),
            0b001100 => self.opAndi(instruction),
            0b101000 => self.opSb(instruction),
            0b100000 => self.opLb(instruction),
            0b000100 => self.opBeq(instruction),
            0b000111 => self.opBgtz(instruction),
            0b000110 => self.opBlez(instruction),
            0b100100 => self.opLbu(instruction),
            0b000001 => {
                switch (instruction.i.rt) {
                    0b00000 => self.opBltz(instruction),
                    0b00001 => self.opBgez(instruction),
                    0b10000 => self.opBltzal(instruction),
                    0b10001 => self.opBgezal(instruction),
                    else => unreachable,
                }
            },
            0b001010 => self.opSlti(instruction),
            0b001011 => self.opSltiu(instruction),
            0b100101 => self.opLhu(instruction),
            0b100001 => self.opLh(instruction),
            0b001110 => self.opXori(instruction),
            0b100010 => self.opLwl(instruction),
            0b100110 => self.opLwr(instruction),
            0b101010 => self.opSwl(instruction),
            0b101110 => self.opSwr(instruction),

            0b000010 => self.opJ(instruction),
            0b000011 => self.opJal(instruction),
            else => unreachable,
        }

        // apply pending load
        if (self.load.reg != 0) {
            self.registers[self.load.reg] = self.load.value;
        }

        // apply current write
        if (self.current_write.reg != 0) {
            self.registers[self.current_write.reg] = self.current_write.value;
        }

        // hardwire $0 back to 0
        self.registers[0] = 0;
    }

    fn branch(self: *Self, offset: u32) void {
        self.next_pc = self.pc +% (offset << 2);
        self.is_branch = true;
    }

    fn exception(self: *Self, cause: Exception) void {
        const sr = self.cop0.getDataRegister(12);
        const handler: u32 = if ((sr & (1 << 22)) != 0) 0xbfc0_0180 else 0x8000_0080;
        const mode = sr & 0x3f;

        // update status reg
        const new_sr = sr & ~@as(u32, 0x3f) | (mode << 2) & 0x3f;
        self.cop0.setDataRegister(12, new_sr);

        // update cause reg with the exception
        const old_cause = self.cop0.getDataRegister(13);
        const cause_code: u32 = @intFromEnum(cause);
        const new_cause = (old_cause & ~@as(u32, 0x7C)) | (cause_code << 2);
        self.cop0.setDataRegister(13, new_cause);

        // save current pc in epc
        const epc = if (cause == .interrupt) self.pc else self.current_pc;
        self.cop0.setDataRegister(14, epc);

        if (self.is_delay_slot) {
            // adjust epc to point and branch instruction
            self.cop0.setDataRegister(14, epc -% 4);

            // set BD bit in the cause register
            self.cop0.setDataRegister(13, self.cop0.getDataRegister(13) | 0x8000_0000);
        } else {
            // clear BD bit in the cause register
            self.cop0.setDataRegister(13, self.cop0.getDataRegister(13) & ~@as(u32, 0x8000_0000));
        }

        self.pc = handler;
        self.next_pc = self.pc +% 4;
    }

    // copz
    fn opMtcz(self: *Self, instruction: Instruction) void {
        const c = instruction.cop_move;

        const value = self.registers[c.rt];

        switch (c.opcode) {
            0b010000 => self.cop0.setDataRegister(c.rd, value),
            else => unreachable,
        }
    }

    fn opMfcz(self: *Self, instruction: Instruction) void {
        const c = instruction.cop_move;

        const value = self.cop0.getDataRegister(c.rd);

        switch (c.opcode) {
            0b010000 => self.setRegDelayed(c.rt, value),
            else => unreachable,
        }
    }

    fn opRfe(self: *Self, _: Instruction) void {
        const mode = self.cop0.getDataRegister(12) & 0x3f;

        const new_sr = (self.cop0.getDataRegister(12) & ~@as(u32, 0x3f)) | (mode >> 2);
        self.cop0.setDataRegister(12, new_sr);
    }

    fn opSrav(self: *Self, instruction: Instruction) void {
        const r = instruction.r;

        const value = @as(i32, @bitCast(self.getReg(r.rt))) >> @as(u5, @truncate(self.getReg(r.rs)));

        self.setReg(r.rd, @bitCast(value));
    }

    fn opSrlv(self: *Self, instruction: Instruction) void {
        const r = instruction.r;

        const value = self.getReg(r.rt) >> @as(u5, @truncate(self.getReg(r.rs)));

        self.setReg(r.rd, value);
    }

    fn opCtcz(self: *Self, instruction: Instruction) void {
        const c = instruction.cop_move;

        const value = self.getReg(c.rt);

        switch (c.opcode) {
            0b010010 => self.cop2.setControlRegister(c.rd, value),
            else => unreachable,
        }
    }

    // i-type
    fn opLui(self: *Self, instruction: Instruction) void {
        const i = instruction.i;

        const value: u32 = @as(u32, i.imm) << 16;

        self.setReg(i.rt, value);
    }

    fn opOri(self: *Self, instruction: Instruction) void {
        const i = instruction.i;

        const value: u32 = self.getReg(i.rs) | i.imm;

        self.setReg(i.rt, value);
    }

    fn opSw(self: *Self, instruction: Instruction) void {
        if (self.isCacheIsolated()) {
            // std.debug.print("Ignoring store while cache is isolated\n", .{});
            return;
        }

        const i = instruction.i;

        const address = self.getReg(i.rs) +% utils.signExtend16(i.imm);
        if (address % 4 != 0) {
            self.exception(.store_address_misaligned);
            return;
        }

        const value = self.getReg(i.rt);
        self.bus.write32(address, value);
    }

    fn opAddiu(self: *Self, instruction: Instruction) void {
        const i = instruction.i;

        const value = self.getReg(i.rs) +% utils.signExtend16(i.imm);

        self.setReg(i.rt, value);
    }

    fn opBne(self: *Self, instruction: Instruction) void {
        const i = instruction.i;

        if (self.getReg(i.rs) != self.getReg(i.rt)) {
            self.branch(utils.signExtend16(i.imm));
        }
    }

    fn opAddi(self: *Self, instruction: Instruction) void {
        const i = instruction.i;

        const rs_val: i32 = @bitCast(self.getReg(i.rs));
        const imm_val: i32 = @bitCast(utils.signExtend16(i.imm));

        const result = @addWithOverflow(rs_val, imm_val);

        if (result[1] != 0) {
            self.exception(.overflow);
            return;
        }

        self.setReg(i.rt, @bitCast(result[0]));
    }

    fn opLw(self: *Self, instruction: Instruction) void {
        if (self.isCacheIsolated()) {
            // std.debug.print("Ignoring load while cache is isolated\n", .{});
            return;
        }

        const i = instruction.i;

        const address = self.getReg(i.rs) +% utils.signExtend16(i.imm);
        if (address % 4 != 0) {
            self.exception(.load_address_misaligned);
            return;
        }

        const value = self.bus.read32(address);
        self.setRegDelayed(i.rt, value);
    }

    fn opSh(self: *Self, instruction: Instruction) void {
        if (self.isCacheIsolated()) {
            // std.debug.print("Ignoring store while cache is isolated\n", .{});
            return;
        }

        const i = instruction.i;

        const address = self.getReg(i.rs) +% utils.signExtend16(i.imm);
        if (address % 2 != 0) {
            self.exception(.store_address_misaligned);
            return;
        }

        const value = self.getReg(i.rt);
        self.bus.write16(address, @truncate(value));
    }

    fn opAndi(self: *Self, instruction: Instruction) void {
        const i = instruction.i;

        const value: u32 = self.getReg(i.rs) & i.imm;

        self.setReg(i.rt, value);
    }

    fn opSb(self: *Self, instruction: Instruction) void {
        if (self.isCacheIsolated()) {
            // std.debug.print("Ignoring store while cache is isolated\n", .{});
            return;
        }

        const i = instruction.i;

        const address = self.getReg(i.rs) +% utils.signExtend16(i.imm);
        const value = self.getReg(i.rt);

        self.bus.write8(address, @truncate(value));
    }

    fn opLb(self: *Self, instruction: Instruction) void {
        if (self.isCacheIsolated()) {
            // std.debug.print("Ignoring load while cache is isolated\n", .{});
            return;
        }

        const i = instruction.i;

        const address = self.getReg(i.rs) +% utils.signExtend16(i.imm);
        const value = utils.signExtend8(self.bus.read8(address));

        self.setRegDelayed(i.rt, value);
    }

    fn opBeq(self: *Self, instruction: Instruction) void {
        const i = instruction.i;

        if (self.getReg(i.rs) == self.getReg(i.rt)) {
            self.branch(utils.signExtend16(i.imm));
        }
    }

    fn opBgtz(self: *Self, instruction: Instruction) void {
        const i = instruction.i;

        const value: i32 = @bitCast(self.getReg(i.rs));

        if (value > 0) {
            self.branch(utils.signExtend16(i.imm));
        }
    }

    fn opBlez(self: *Self, instruction: Instruction) void {
        const i = instruction.i;

        const value: i32 = @bitCast(self.getReg(i.rs));

        if (value <= 0) {
            self.branch(utils.signExtend16(i.imm));
        }
    }

    fn opLbu(self: *Self, instruction: Instruction) void {
        if (self.isCacheIsolated()) {
            // std.debug.print("Ignoring load while cache is isolated\n", .{});
            return;
        }

        const i = instruction.i;

        const address = self.getReg(i.rs) +% utils.signExtend16(i.imm);
        const value = self.bus.read8(address);

        self.setRegDelayed(i.rt, value);
    }

    fn opBltz(self: *Self, instruction: Instruction) void {
        const i = instruction.i;

        const value: i32 = @bitCast(self.getReg(i.rs));

        if (value < 0) {
            self.branch(utils.signExtend16(i.imm));
        }
    }

    fn opBgez(self: *Self, instruction: Instruction) void {
        const i = instruction.i;

        const value: i32 = @bitCast(self.getReg(i.rs));

        if (value >= 0) {
            self.branch(utils.signExtend16(i.imm));
        }
    }

    fn opBltzal(self: *Self, instruction: Instruction) void {
        const i = instruction.i;

        const value: i32 = @bitCast(self.getReg(i.rs));

        self.setReg(31, self.next_pc);

        if (value < 0) {
            self.branch(utils.signExtend16(i.imm));
        }
    }

    fn opBgezal(self: *Self, instruction: Instruction) void {
        const i = instruction.i;

        const value: i32 = @bitCast(self.getReg(i.rs));

        self.setReg(31, self.next_pc);

        if (value >= 0) {
            self.branch(utils.signExtend16(i.imm));
        }
    }

    fn opSlti(self: *Self, instruction: Instruction) void {
        const i = instruction.i;

        const value: u32 = @intFromBool(@as(i32, @bitCast(self.getReg(i.rs))) < utils.signExtend16(i.imm));

        self.setReg(i.rt, value);
    }

    fn opSltiu(self: *Self, instruction: Instruction) void {
        const i = instruction.i;

        const value: u32 = @intFromBool(self.getReg(i.rs) < utils.signExtend16(i.imm));

        self.setReg(i.rt, value);
    }

    fn opLhu(self: *Self, instruction: Instruction) void {
        const i = instruction.i;

        const address = self.getReg(i.rs) +% utils.signExtend16(i.imm);
        if (address % 2 != 0) {
            self.exception(.load_address_misaligned);
            return;
        }

        const value = self.bus.read16(address);
        self.setRegDelayed(i.rt, value);
    }

    fn opLh(self: *Self, instruction: Instruction) void {
        const i = instruction.i;

        const address = self.getReg(i.rs) +% utils.signExtend16(i.imm);
        if (address % 2 != 0) {
            self.exception(.load_address_misaligned);
            return;
        }

        const value = utils.signExtend16(self.bus.read16(address));
        self.setRegDelayed(i.rt, @bitCast(value));
    }

    fn opXori(self: *Self, instruction: Instruction) void {
        const i = instruction.i;

        const value: u32 = self.getReg(i.rs) ^ i.imm;

        self.setReg(i.rt, value);
    }

    fn opLwl(self: *Self, instruction: Instruction) void {
        if (self.isCacheIsolated()) {
            // std.debug.print("Ignoring load while cache is isolated\n", .{});
            return;
        }

        const i = instruction.i;

        // calc unaligned address and the aligned base address
        const address = self.getReg(i.rs) +% utils.signExtend16(i.imm);
        const aligned_address = address & ~@as(u32, 3);
        const aligned_word = self.bus.read32(aligned_address);

        // bypass load delay restriction
        var current_value = self.getReg(i.rt);
        if (self.load.reg == i.rt) {
            current_value = self.load.value;
        }

        // shift and merge based on byte offset
        const result: u32 = switch (address & 3) {
            0 => (current_value & 0x00ff_ffff) | (aligned_word << 24),
            1 => (current_value & 0x0000_ffff) | (aligned_word << 16),
            2 => (current_value & 0x0000_00ff) | (aligned_word << 8),
            3 => aligned_word,
            else => unreachable,
        };

        self.setRegDelayed(i.rt, result);
    }

    fn opLwr(self: *Self, instruction: Instruction) void {
        if (self.isCacheIsolated()) {
            // std.debug.print("Ignoring load while cache is isolated\n", .{});
            return;
        }

        const i = instruction.i;

        const address = self.getReg(i.rs) +% utils.signExtend16(i.imm);
        const aligned_address = address & ~@as(u32, 3);
        const aligned_word = self.bus.read32(aligned_address);

        var current_value = self.getReg(i.rt);
        if (self.load.reg == i.rt) {
            current_value = self.load.value;
        }

        const result: u32 = switch (address & 3) {
            0 => aligned_word,
            1 => (current_value & 0xff00_0000) | (aligned_word >> 8),
            2 => (current_value & 0xffff_0000) | (aligned_word >> 16),
            3 => (current_value & 0xffff_ff00) | (aligned_word >> 24),
            else => unreachable,
        };

        self.setRegDelayed(i.rt, result);
    }

    fn opSwl(self: *Self, instruction: Instruction) void {
        if (self.isCacheIsolated()) {
            // std.debug.print("Ignoring store while cache is isolated\n", .{});
            return;
        }

        const i = instruction.i;

        const address = self.getReg(i.rs) +% utils.signExtend16(i.imm);
        const aligned_address = address & ~@as(u32, 3);
        const aligned_word = self.bus.read32(aligned_address);

        const reg_value = self.getReg(i.rt);

        const result: u32 = switch (address & 3) {
            0 => (aligned_word & 0xffff_ff00) | (reg_value >> 24),
            1 => (aligned_word & 0xffff_0000) | (reg_value >> 16),
            2 => (aligned_word & 0xff00_0000) | (reg_value >> 8),
            3 => reg_value,
            else => unreachable,
        };

        self.bus.write32(aligned_address, result);
    }

    fn opSwr(self: *Self, instruction: Instruction) void {
        if (self.isCacheIsolated()) {
            std.debug.print("Ignoring store while cache is isolated\n", .{});
            return;
        }

        const i = instruction.i;

        const address = self.getReg(i.rs) +% utils.signExtend16(i.imm);
        const aligned_address = address & ~@as(u32, 3);
        const aligned_word = self.bus.read32(aligned_address);

        const reg_value = self.getReg(i.rt);

        const result: u32 = switch (address & 3) {
            0 => reg_value,
            1 => (aligned_word & 0x0000_00ff) | (reg_value << 8),
            2 => (aligned_word & 0x0000_ffff) | (reg_value << 16),
            3 => (aligned_word & 0x00ff_ffff) | (reg_value << 24),
            else => unreachable,
        };

        self.bus.write32(aligned_address, result);
    }

    // r-type
    fn opSll(self: *Self, instruction: Instruction) void {
        const r = instruction.r;

        const value = self.getReg(r.rt) << r.sa;

        self.setReg(r.rd, value);
    }

    fn opOr(self: *Self, instruction: Instruction) void {
        const r = instruction.r;

        const value = self.getReg(r.rs) | self.getReg(r.rt);

        self.setReg(r.rd, value);
    }

    fn opAddu(self: *Self, instruction: Instruction) void {
        const r = instruction.r;

        const value = self.getReg(r.rs) +% self.getReg(r.rt);

        self.setReg(r.rd, value);
    }

    fn opSltu(self: *Self, instruction: Instruction) void {
        const r = instruction.r;

        const value = self.getReg(r.rs) < self.getReg(r.rt);

        self.setReg(r.rd, if (value) 1 else 0);
    }

    fn opJr(self: *Self, instruction: Instruction) void {
        const r = instruction.r;

        self.next_pc = self.getReg(r.rs);
        self.is_branch = true;
    }

    fn opAnd(self: *Self, instruction: Instruction) void {
        const r = instruction.r;

        const value = self.getReg(r.rs) & self.getReg(r.rt);

        self.setReg(r.rd, value);
    }

    fn opAdd(self: *Self, instruction: Instruction) void {
        const r = instruction.r;

        const rs_val: i32 = @bitCast(self.getReg(r.rs));
        const rt_val: i32 = @bitCast(self.getReg(r.rt));

        const result = @addWithOverflow(rs_val, rt_val);

        if (result[1] != 0) {
            self.exception(.overflow);
            return;
        }

        self.setReg(r.rd, @bitCast(result[0]));
    }

    fn opJalr(self: *Self, instruction: Instruction) void {
        const r = instruction.r;

        self.setReg(r.rd, self.next_pc);
        self.next_pc = self.getReg(r.rs);
        self.is_branch = true;
    }

    fn opSubu(self: *Self, instruction: Instruction) void {
        const r = instruction.r;

        const value = self.getReg(r.rs) -% self.getReg(r.rt);

        self.setReg(r.rd, value);
    }

    fn opSra(self: *Self, instruction: Instruction) void {
        const r = instruction.r;

        const value = @as(i32, @bitCast(self.getReg(r.rt))) >> r.sa;

        self.setReg(r.rd, @bitCast(value));
    }

    fn opDiv(self: *Self, instruction: Instruction) void {
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

    fn opMflo(self: *Self, instruction: Instruction) void {
        const r = instruction.r;

        self.setReg(r.rd, self.lo);
    }

    fn opSrl(self: *Self, instruction: Instruction) void {
        const r = instruction.r;

        const value = self.getReg(r.rt) >> r.sa;

        self.setReg(r.rd, @bitCast(value));
    }

    fn opDivu(self: *Self, instruction: Instruction) void {
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

    fn opMfhi(self: *Self, instruction: Instruction) void {
        const r = instruction.r;

        self.setReg(r.rd, self.hi);
    }

    fn opSlt(self: *Self, instruction: Instruction) void {
        const r = instruction.r;

        const value = @as(i32, @bitCast(self.getReg(r.rs))) < @as(i32, @bitCast(self.getReg(r.rt)));

        self.setReg(r.rd, if (value) 1 else 0);
    }

    fn opSyscall(self: *Self, _: Instruction) void {
        self.exception(.syscall);
    }

    fn opMtlo(self: *Self, instruction: Instruction) void {
        const r = instruction.r;

        self.lo = self.getReg(r.rs);
    }

    fn opMthi(self: *Self, instruction: Instruction) void {
        const r = instruction.r;

        self.hi = self.getReg(r.rs);
    }

    fn opSllv(self: *Self, instruction: Instruction) void {
        const r = instruction.r;

        const value = self.getReg(r.rt) << @as(u5, @truncate(self.getReg(r.rs)));

        self.setReg(r.rd, value);
    }

    fn opNor(self: *Self, instruction: Instruction) void {
        const r = instruction.r;

        const value = ~(self.getReg(r.rs) | self.getReg(r.rt));

        self.setReg(r.rd, value);
    }

    fn opMultu(self: *Self, instruction: Instruction) void {
        const r = instruction.r;

        const a: u64 = self.getReg(r.rs);
        const b: u64 = self.getReg(r.rt);

        const value = a * b;

        self.hi = @truncate(value >> 32);
        self.lo = @truncate(value);
    }

    fn opXor(self: *Self, instruction: Instruction) void {
        const r = instruction.r;

        const value = self.getReg(r.rs) ^ self.getReg(r.rt);

        self.setReg(r.rd, value);
    }

    fn opBreak(self: *Self, _: Instruction) void {
        self.exception(.brk);
    }

    fn opMult(self: *Self, instruction: Instruction) void {
        const r = instruction.r;

        const a: i64 = @as(i32, @bitCast(self.getReg(r.rs)));
        const b: i64 = @as(i32, @bitCast(self.getReg(r.rt)));

        const value: u64 = @bitCast(a * b);

        self.hi = @truncate(value >> 32);
        self.lo = @truncate(value);
    }

    fn opSub(self: *Self, instruction: Instruction) void {
        const r = instruction.r;

        const rs_val: i32 = @bitCast(self.getReg(r.rs));
        const rt_val: i32 = @bitCast(self.getReg(r.rt));

        const result = @subWithOverflow(rs_val, rt_val);

        if (result[1] != 0) {
            self.exception(.overflow);
            return;
        }

        self.setReg(r.rd, @bitCast(result[0]));
    }

    // j-type
    fn opJ(self: *Self, instruction: Instruction) void {
        const j = instruction.j;

        self.next_pc = self.pc & 0xf000_0000 | @as(u32, j.address) << 2;
        self.is_branch = true;
    }

    fn opJal(self: *Self, instruction: Instruction) void {
        const j = instruction.j;

        self.setReg(31, self.next_pc);
        self.next_pc = self.pc & 0xf000_0000 | @as(u32, j.address) << 2;
        self.is_branch = true;
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
