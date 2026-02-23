const std = @import("std");

const Size = 2 * 1024 * 1024;

pub const Ram = struct {
    allocator: std.mem.Allocator,

    data: []u8,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator) !Self {
        const data = try allocator.alloc(u8, Size);

        @memset(data, 0);

        return .{
            .allocator = allocator,
            .data = data,
        };
    }

    pub fn deinit(self: *Self) void {
        self.allocator.free(self.data);
    }

    pub fn read32(self: *Self, address: u32) u32 {
        return std.mem.readInt(u32, self.data[address..][0..4], .little);
    }

    pub fn write32(self: *Self, address: u32, value: u32) void {
        std.mem.writeInt(u32, self.data[address..][0..4], value, .little);
    }

    pub fn read16(self: *Self, address: u32) u16 {
        return std.mem.readInt(u16, self.data[address..][0..2], .little);
    }

    pub fn write16(self: *Self, address: u32, value: u16) void {
        std.mem.writeInt(u16, self.data[address..][0..2], value, .little);
    }

    pub fn read8(self: *Self, address: u32) u8 {
        return self.data[address];
    }

    pub fn write8(self: *Self, address: u32, value: u8) void {
        self.data[address] = value;
    }
};
