const std = @import("std");

pub const StatusRegister = packed struct(u8) {
    index: u2,
    adpcm_playing: u1,
    parameter_fifo_empty: u1,
    parameter_fifo_writable: u1,
    result_fifo_readable: u1,
    data_request: u1,
    command_busy: u1,
};

pub const Cdrom = struct {
    allocator: std.mem.Allocator,

    status: StatusRegister,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator) Self {
        return .{
            .allocator = allocator,
            .status = @bitCast(@as(u8, 0x18)),
        };
    }

    pub fn read8(self: *Self, address: u32) u8 {
        return switch (address) {
            0x00 => @bitCast(self.status),
            else => {
                std.debug.print("cdrom: Unhandled read8 from offset {x} (Bank: {d})\n", .{ address, self.status.index });
                return 0;
            },
        };
    }

    pub fn write8(self: *Self, address: u32, value: u8) void {
        switch (address) {
            0x00 => {
                self.status.index = @truncate(value); // only writeable bit
            },
            else => {
                std.debug.print("cdrom: Unhandled write8 to offset {x} with value {x} (Bank: {d})\n", .{ address, value, self.status.index });
            },
        }
    }
};
