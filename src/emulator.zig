const std = @import("std");
const utils = @import("utils.zig");

const Cpu = @import("cpu.zig").Cpu;
const Bus = @import("bus.zig").Bus;
const Instruction = @import("cpu.zig").Instruction;

pub const ExeHeader = extern struct {
    id: [8]u8,
    _pad0: [8]u8,
    initial_pc: u32,
    initial_gp: u32,
    dest_addr: u32,
    file_size: u32,
    data_start: u32,
    data_size: u32,
    bss_start: u32,
    bss_size: u32,
    sp_base: u32,
    sp_offset: u32,
    _reserved: [20]u8,
    marker_and_pad: [1972]u8,

    // comptime {
    //     std.debug.assert(@sizeOf(PsxExeHeader) == 2048);
    // }
};

pub const Emulator = struct {
    allocator: std.mem.Allocator,

    bus: Bus,
    cpu: Cpu,
    is_paused: bool,

    breakpoints: std.AutoHashMap(u32, void),
    temp_breakpoint: ?u32,

    const Self = @This();

    pub fn init(
        allocator: std.mem.Allocator,
        breakpoints: []const u32,
    ) !*Self {
        const self = try allocator.create(Self);

        self.* = .{
            .allocator = allocator,
            .bus = try Bus.init(allocator),
            .cpu = Cpu.init(&self.bus),
            .is_paused = false,
            .breakpoints = .init(allocator),
            .temp_breakpoint = null,
        };

        for (breakpoints) |breakpoint| {
            try self.breakpoints.put(breakpoint, {});
        }

        const bios_data = try utils.readBinaryFile(allocator, "roms/SCPH1001.BIN");
        defer allocator.free(bios_data);
        try self.bus.loadBios(bios_data);

        // TODO: fix and remove this... not sure why we have to pre-step
        for (0..10) |_| {
            self.cpu.step();
        }

        return self;
    }

    pub fn deinit(self: *Self) void {
        self.bus.deinit();
        self.cpu.deinit();
        self.breakpoints.deinit();
        self.allocator.destroy(self);
    }

    pub fn sideload_exe(self: *Self, exe: []const u8) !void {
        if (exe.len < 2048) return error.FileTooSmall;

        while (self.cpu.pc != 0x8003_0000) {
            self.step();
        }

        std.debug.print("---------------------------\n", .{});
        std.debug.print("SIDELOADING EXE\n", .{});
        std.debug.print("---------------------------\n", .{});

        const header: *const ExeHeader = @ptrCast(@alignCast(exe[0..2048]));

        const payload_size = header.file_size;
        std.debug.print("Payload Size:            {d} bytes (0x{x})\n", .{ payload_size, payload_size });

        const payload = exe[2048 .. 2048 + payload_size];
        const ram_offset = header.dest_addr & 0x001f_ffff;

        std.debug.print("Target Dest Addr:        0x{x}\n", .{header.dest_addr});
        std.debug.print("Calculated RAM Offset:   0x{x}\n", .{ram_offset});

        @memcpy(self.bus.ram.data[ram_offset .. ram_offset + payload_size], payload);
        std.debug.print(">> Payload copied to RAM successfully.\n\n", .{});

        std.debug.print("--- Register Init ---\n", .{});
        std.debug.print("Initial PC:              0x{x}\n", .{header.initial_pc});
        std.debug.print("Initial GP ($28):        0x{x}\n", .{header.initial_gp});

        self.cpu.pc = header.initial_pc;
        self.cpu.next_pc = header.initial_pc + 4;

        self.cpu.registers[28] = header.initial_gp;

        if (header.sp_base != 0) {
            const sp = header.sp_base + header.sp_offset;
            self.cpu.registers[29] = sp;
            self.cpu.registers[30] = sp;

            std.debug.print("SP Base:                 0x{x}\n", .{header.sp_base});
            std.debug.print("SP Offset:               0x{x}\n", .{header.sp_offset});
            std.debug.print("Calculated SP ($29/$30): 0x{x}\n", .{sp});
        } else {
            std.debug.print("SP Base is 0. Leaving $29/$30 untouched.\n", .{});
        }

        std.debug.print("---------------------------\n", .{});

        // var sp: u32 = 0x801f_fff0;
        //
        // if (header.sp_base != 0) {
        //     sp = header.sp_base + header.sp_offset;
        // }
        //
        // self.cpu.registers[29] = sp;
        // self.cpu.registers[30] = sp;
    }

    pub fn step(self: *Self) void {
        self.cpu.step();

        if (self.bus.dma.pending_channels != 0) {
            self.bus.processPendingDma();
        }
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

        const cycles_per_frame = 564_480;
        var cycles_executed: u32 = 0;

        while (cycles_executed < cycles_per_frame) {
            const start_cycles = self.cpu.cycles;
            self.step();
            const end_cycles = self.cpu.cycles;

            cycles_executed += if (end_cycles >= start_cycles)
                end_cycles - start_cycles
            else
                (std.math.maxInt(u32) - start_cycles) + end_cycles + 1;

            if (self.breakpoints.contains(self.cpu.pc) or (self.temp_breakpoint != null and self.cpu.pc == self.temp_breakpoint.?)) {
                self.is_paused = true;
                self.temp_breakpoint = null;
                break;
            }
        }
    }
};
