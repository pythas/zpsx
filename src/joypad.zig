const std = @import("std");

pub const Joypad = struct {
    data: u32,
    status: u32,
    mode: u32,
    control: u32,
    baud: u32,

    const Self = @This();

    pub fn init() Self {
        return .{
            .data = 0,
            .status = 0,
            .mode = 0,
            .control = 0,
            .baud = 0,
        };
    }

    pub fn read16(self: *Self, offset: u32) u16 {
        _ = self;

        return switch (offset) {
            else => std.debug.print("joypad: Unhandled read16 from offset {x}\n", .{offset}),
        };
    }

    pub fn write16(self: *Self, offset: u32, value: u16) void {
        switch (offset) {
            0x0a => self.control = value,
            else => std.debug.print("joypad: Unhandled write16 from offset {x}\n", .{offset}),
        }
    }
};
