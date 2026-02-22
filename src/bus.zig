const std = @import("std");
const Bios = @import("bios.zig").Bios;

pub const Bus = struct {
    allocator: std.mem.Allocator,

    bios: Bios,
    ram: [2 * 1024 * 1024]u8,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator) !Self {
        const bios = try Bios.init(allocator);

        return .{
            .allocator = allocator,
            .bios = bios,
            .ram = [_]u8{0} ** (2 * 1024 * 1024),
        };
    }

    pub fn deinit(self: *Self) void {
        self.bios.deinit();
    }

    pub fn loadBios(self: *Self, data: []const u8) !void {
        try self.bios.load(data);
    }

    pub fn read(self: *Self, address: u32) u32 {
        return switch (address) {
            0x0000_0000...0x0020_0000 => std.mem.readInt(u32, self.ram[address..][0..4], .little),
            0xbfc0_0000...0xbfc8_0000 => self.bios.read(address - 0xbfc0_0000),
            else => std.debug.panic("Unsupported read: {x}", .{address}),
        };
    }

    pub fn write(self: *Self, address: u32, value: u32) void {
        std.debug.print("WRITE: 0x{x:0>8}: 0x{x:0>8}\n", .{ address, value });

        switch (address) {
            0x0000_0000...0x0020_0000 => std.mem.writeInt(u32, self.ram[address..][0..4], value, .little),
            0x1f801000...0x1f801024 => std.debug.print("Unhandled write to MEMCONTROL\n", .{}),
            0x1f801060...0x1f801064 => std.debug.print("Unhandled write to RAM_SIZE\n", .{}),
            0xfffe0130...0xfffe0134 => std.debug.print("Unhandled write to CACHE_CONTROL\n", .{}),
            else => std.debug.panic("Unsupported write: {x}", .{address}),
        }
    }
};
