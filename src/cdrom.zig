const std = @import("std");

const InterruptController = @import("interrupt.zig").InterruptController;

pub const Fifo = struct {
    buffer: [16]u8,

    read_cursor: u4,
    write_cursor: u4,

    length: u5,

    const Self = @This();

    pub fn init() Self {
        return .{
            .buffer = [_]u8{0} ** 16,
            .read_cursor = 0,
            .write_cursor = 0,
            .length = 0,
        };
    }

    pub fn push(self: *Self, value: u8) void {
        if (self.length >= 16) {
            std.debug.print("cdrom: FIFO overflow\n", .{});
            return;
        }

        self.buffer[self.write_cursor] = value;
        self.write_cursor +%= 1;
        self.length += 1;
    }

    pub fn pop(self: *Self) u8 {
        if (self.length == 0) {
            std.debug.print("cdrom: FIFO underflow\n", .{});
            return 0;
        }

        const value = self.buffer[self.read_cursor];
        self.read_cursor +%= 1;
        self.length -= 1;

        return value;
    }

    pub fn clear(self: *Self) void {
        self.read_cursor = 0;
        self.write_cursor = 0;
        self.length = 0;
    }

    pub fn isEmpty(self: *Self) bool {
        return self.length == 0;
    }
};

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

    parameter: Fifo,
    response: Fifo,

    interrupt_status: u5,
    interrupt_mask: u5,

    pending_command: ?u8,
    command_delay: u32,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator) Self {
        return .{
            .allocator = allocator,
            .status = @bitCast(@as(u8, 0x18)),
            .parameter = Fifo.init(),
            .response = Fifo.init(),
            .interrupt_status = 0,
            .interrupt_mask = 0,
            .pending_command = null,
            .command_delay = 0,
        };
    }

    pub fn read8(self: *Self, offset: u32) u8 {
        std.debug.print("cdrom: read8 from offset {x} (Bank: {d})\n", .{ offset, self.status.index });

        return switch (offset) {
            0x00 => {
                // NOTE: not sure if we should persist this
                var current_status = self.status;
                current_status.parameter_fifo_empty = if (self.parameter.isEmpty()) 1 else 0;
                current_status.parameter_fifo_writable = if (self.parameter.length < 16) 1 else 0;
                current_status.result_fifo_readable = if (self.response.isEmpty()) 0 else 1;

                return @bitCast(current_status);
            },
            0x01 => self.response.pop(),
            0x03 => switch (self.status.index) {
                1 => @as(u8, self.interrupt_status) | 0xE0,
                else => 0,
            },
            else => {
                std.debug.print("cdrom: Unhandled read8 from offset {x} (Bank: {d})\n", .{ offset, self.status.index });
                return 0;
            },
        };
    }

    pub fn write8(self: *Self, offset: u32, value: u8) void {
        std.debug.print("cdrom: write8 to offset {x} with value {x} (Bank: {d})\n", .{ offset, value, self.status.index });

        switch (offset) {
            0x00 => {
                self.status.index = @truncate(value); // only writeable bit
            },
            0x01 => {
                switch (self.status.index) {
                    0 => self.executeCommand(value),
                    else => std.debug.print("cdrom: Unhandled write8 to offset {x} with value {x} (Bank: {d})\n", .{ offset, value, self.status.index }),
                }
            },
            0x02 => {
                switch (self.status.index) {
                    0 => self.parameter.push(value),
                    1 => self.interrupt_mask = @truncate(value),
                    else => std.debug.print("cdrom: Unhandled write8 to offset {x} with value {x} (Bank: {d})\n", .{ offset, value, self.status.index }),
                }
            },
            0x03 => {
                switch (self.status.index) {
                    1 => self.interrupt_status &= ~@as(u5, @truncate(value)),
                    else => std.debug.print("cdrom: Unhandled write8 to offset {x} with value {x} (Bank: {d})\n", .{ offset, value, self.status.index }),
                }
            },
            else => {
                std.debug.print("cdrom: Unhandled write8 to offset {x} with value {x} (Bank: {d})\n", .{ offset, value, self.status.index });
            },
        }
    }

    pub fn step(self: *Self, cycles: u32, intc: *InterruptController) void {
        if (self.command_delay == 0) return;

        if (cycles < self.command_delay) {
            self.command_delay -= cycles;
            return;
        }

        self.command_delay = 0;

        const cmd = self.pending_command orelse return;

        self.pending_command = null;
        self.processCommand(cmd, intc);
    }

    fn executeCommand(self: *Self, command: u8) void {
        self.pending_command = command;
        self.command_delay = 30_000;
    }

    fn processCommand(self: *Self, command: u8, intc: *InterruptController) void {
        switch (command) {
            0x19 => {
                const sub_command = self.parameter.pop();

                switch (sub_command) {
                    0x20 => {
                        self.response.push(0x94);
                        self.response.push(0x09);
                        self.response.push(0x19);
                        self.response.push(0xc0);

                        self.interrupt_status = 3;

                        intc.trigger(.cdrom);
                    },
                    else => std.debug.print("cdrom: Unhandled sub command {x}\n", .{command}),
                }
            },
            else => std.debug.print("cdrom: Unhandled command {x}\n", .{command}),
        }
    }
};
