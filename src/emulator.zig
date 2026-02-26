const std = @import("std");
const utils = @import("utils.zig");

const Cpu = @import("cpu.zig").Cpu;
const Bus = @import("bus.zig").Bus;
const Instruction = @import("cpu.zig").Instruction;

pub const Emulator = struct {
    bus: Bus,
    cpu: Cpu,
    is_paused: bool,

    breakpoints: std.AutoHashMap(u32, void),
    temp_breakpoint: ?u32,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator) !*Self {
        const self = try allocator.create(Self);

        self.bus = try Bus.init(allocator);
        self.cpu = Cpu.init(&self.bus);
        self.is_paused = false;
        self.breakpoints = .init(allocator);
        self.temp_breakpoint = null;

        try self.breakpoints.put(0xbfc0_0034, {});

        const bios_data = try utils.readBinaryFile(allocator, "roms/SCPH1001.BIN");
        defer allocator.free(bios_data);
        try self.bus.loadBios(bios_data);

        // TODO: fix and remove this... not sure why we have to pre-step
        for (0..10) |_| {
            self.cpu.step();
        }

        return self;
    }

    pub fn deinit(self: *Self, allocator: std.mem.Allocator) void {
        self.bus.deinit();
        self.cpu.deinit();
        self.breakpoints.deinit();
        allocator.destroy(self);
    }

    pub fn step(self: *Self) void {
        self.cpu.step();
    }

    pub fn stepOver(self: *Self) void {
        const instruction: Instruction = @bitCast(self.bus.read32(self.cpu.pc));

        var is_call = false;
        if (instruction.i.opcode == 0x03) { // jal
            is_call = true;
        } else if (instruction.r.opcode == 0x00 and instruction.r.funct == 0x09) { // jalr
            is_call = true;
        } else if (instruction.i.opcode == 0x01 and (instruction.i.rt == 0x10 or instruction.i.rt == 0x11)) { // bltzal, bgezal
            is_call = true;
        }

        if (is_call) {
            self.temp_breakpoint = self.cpu.pc + 8;
            self.is_paused = false;
        } else {
            self.step();
        }
    }

    pub fn stepOut(self: *Self) void {
        self.temp_breakpoint = self.cpu.registers[31];
        self.is_paused = false;
    }

    pub fn runFrame(self: *Self) void {
        if (self.is_paused) return;

        for (0..10000) |_| {
            self.step();

            if (self.breakpoints.contains(self.cpu.pc) or (self.temp_breakpoint != null and self.cpu.pc == self.temp_breakpoint.?)) {
                self.is_paused = true;
                self.temp_breakpoint = null;
                break;
            }
        }
    }
};
