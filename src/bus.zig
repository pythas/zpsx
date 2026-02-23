const std = @import("std");
const Bios = @import("bios.zig").Bios;
const Ram = @import("ram.zig").Ram;

const Range = struct {
    start: u32,
    end: u32,
};
// 0x1f80_1074
const memory_map = struct {
    pub const ram = Range{ .start = 0x0000_0000, .end = 0x0020_0000 - 1 };
    pub const irq_control = Range{ .start = 0x1f80_1070, .end = 0x1f80_1078 - 1 };
    pub const timers = Range{ .start = 0x1f80_1100, .end = 0x1f80_1130 - 1 };
    pub const exp1 = Range{ .start = 0x1f00_0000, .end = 0x1f80_0000 - 1 };
    pub const scratchpad = Range{ .start = 0x1f80_0000, .end = 0x1f80_0400 - 1 };
    pub const hardware_io = Range{ .start = 0x1f80_1000, .end = 0x1f80_2000 - 1 };
    pub const exp2 = Range{ .start = 0x1f80_2000, .end = 0x1f80_4000 - 1 };
    pub const exp3 = Range{ .start = 0x1fa0_0000, .end = 0x1fc0_0000 - 1 };
    pub const bios = Range{ .start = 0x1fc0_0000, .end = 0x1fc8_0000 - 1 };
    pub const cache_control = Range{ .start = 0xfffe_0000, .end = 0xfffe_0200 - 1 };
};

pub const Bus = struct {
    allocator: std.mem.Allocator,

    ram: Ram,
    bios: Bios,

    const Self = @This();
    const RegionMasks = [_]u32{
        0xffff_ffff, 0xffff_ffff, 0xffff_ffff, 0xffff_ffff, // KUSEG: 2048MB
        0x7fff_ffff, // KSEG0: 512MB
        0x1fff_ffff, // KSEG1: 512MB
        0xffff_ffff, 0xffff_ffff, // KSEG2: 1024MB
    };

    pub fn init(allocator: std.mem.Allocator) !Self {
        const bios = try Bios.init(allocator);
        const ram = try Ram.init(allocator);

        return .{
            .allocator = allocator,
            .ram = ram,
            .bios = bios,
        };
    }

    pub fn deinit(self: *Self) void {
        self.bios.deinit();
    }

    pub fn loadBios(self: *Self, data: []const u8) !void {
        try self.bios.load(data);
    }

    fn physicalAddress(virtual_address: u32) u32 {
        const index = virtual_address >> 29;

        return virtual_address & RegionMasks[index];
    }

    pub fn read32(self: *Self, virtual_address: u32) u32 {
        const address = physicalAddress(virtual_address);

        // std.debug.print(
        //     "read32: V:0x{x:0>8} P:0x{x:0>8}\n",
        //     .{ virtual_address, address },
        // );

        return switch (address) {
            memory_map.ram.start...memory_map.ram.end => self.ram.read32(address),
            memory_map.irq_control.start...memory_map.irq_control.end => 0x00,
            memory_map.bios.start...memory_map.bios.end => self.bios.read32(address - memory_map.bios.start),
            else => std.debug.panic("bus: Unsupported read32: {x}", .{address}),
        };
    }

    pub fn write32(self: *Self, virtual_address: u32, value: u32) void {
        // TODO: panic at unaligned store

        const address = physicalAddress(virtual_address);

        // std.debug.print(
        //     "write32: V:0x{x:0>8} P:0x{x:0>8} VAL:0x{x:0>8}\n",
        //     .{ virtual_address, address, value },
        // );

        switch (address) {
            memory_map.ram.start...memory_map.ram.end => self.ram.write32(address, value),
            memory_map.irq_control.start...memory_map.irq_control.end => std.debug.print("bus: Unhandled write32 to IRQ_CONTROL\n", .{}),
            0x1f80_1000...0x1f80_1024 => std.debug.print("bus: Unhandled write32 to MEMCONTROL\n", .{}),
            0x1f80_1060...0x1f80_1064 => std.debug.print("bus: Unhandled write32 to RAM_SIZE\n", .{}),
            memory_map.cache_control.start...memory_map.cache_control.end => std.debug.print("bus: Unhandled write32 to CACHE_CONTROL\n", .{}),
            else => std.debug.panic("bus: Unsupported write32: {x}", .{address}),
        }
    }

    pub fn write16(self: *Self, virtual_address: u32, value: u16) void {
        // TODO: panic at unaligned store

        const address = physicalAddress(virtual_address);

        _ = self;
        _ = value;

        // std.debug.print(
        //     "write16: V:0x{x:0>8} P:0x{x:0>8} VAL:0x{x:0>8}\n",
        //     .{ virtual_address, address, value },
        // );

        switch (address) {
            memory_map.timers.start...memory_map.timers.end => std.debug.print("bus: Unhandled write16 to TIMERS\n", .{}),
            0x1f80_1c00...0x1f80_1e7f => std.debug.print("bus: Unhandled write16 to SPU\n", .{}),
            else => std.debug.panic("bus: Unsupported write16: {x}", .{address}),
        }
    }

    pub fn read8(self: *Self, virtual_address: u32) u32 {
        const address = physicalAddress(virtual_address);

        // std.debug.print(
        //     "read8: V:0x{x:0>8} P:0x{x:0>8}\n",
        //     .{ virtual_address, address },
        // );

        return switch (address) {
            memory_map.ram.start...memory_map.ram.end => self.ram.read8(address),
            memory_map.exp1.start...memory_map.exp1.end => 0xff,
            memory_map.bios.start...memory_map.bios.end => self.bios.read8(address - memory_map.bios.start),
            else => std.debug.panic("bus: Unsupported read8: {x}", .{address}),
        };
    }

    pub fn write8(self: *Self, virtual_address: u32, value: u8) void {
        // TODO: panic at unaligned store

        const address = physicalAddress(virtual_address);

        // std.debug.print(
        //     "write8: V:0x{x:0>8} P:0x{x:0>8} VAL:0x{x:0>8}\n",
        //     .{ virtual_address, address, value },
        // );

        switch (address) {
            memory_map.ram.start...memory_map.ram.end => self.ram.write8(address, value),
            memory_map.exp2.start...memory_map.exp2.end => std.debug.print("bus: Unhandled write8 to EXPANSION_2\n", .{}),
            else => std.debug.panic("bus: Unsupported write8: {x}", .{address}),
        }
    }
};
