const std = @import("std");
const utils = @import("utils.zig");

const Cpu = @import("cpu.zig").Cpu;
const Bus = @import("bus.zig").Bus;

pub const Emulator = struct {
    bus: Bus,
    cpu: Cpu,
    is_paused: bool,

    breakpoints: std.AutoHashMap(u32, void),

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator) !*Self {
        const self = try allocator.create(Self);

        self.bus = try Bus.init(allocator);
        self.cpu = Cpu.init(&self.bus);
        self.is_paused = false;
        self.breakpoints = .init(allocator);

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
        allocator.destroy(self);
    }

    pub fn step(self: *Self) void {
        self.cpu.step();
    }

    pub fn runFrame(self: *Self) void {
        if (self.is_paused) return;

        for (0..10000) |_| {
            self.step();

            if (self.breakpoints.contains(self.cpu.pc)) {
                self.is_paused = true;
                break;
            }
        }
    }
};
