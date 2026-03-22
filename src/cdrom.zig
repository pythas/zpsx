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

    pub fn fromSlice(data: []const u8) Self {
        var self = Self.init();

        for (data) |b| {
            self.push(b);
        }

        return self;
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

const Interrupt = enum(u5) {
    none = 0,
    data_ready = 1,
    complete = 2,
    acknowledge = 3,
    data_end = 4,
    error_status = 5,
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

const DriveStatus = packed struct(u8) {
    error_status: u1 = 0,
    motor_on: u1 = 0,
    seek_error: u1 = 0,
    id_error: u1 = 0,
    shell_open: u1 = 0,
    reading: u1 = 0,
    seeking: u1 = 0,
    playing: u1 = 0,
};

const PendingResponse = struct {
    interrupt: u5,
    payload: Fifo,
    delay: u32,

    const Self = @This();

    pub fn init() Self {
        return .{
            .interrupt = 0,
            .payload = Fifo.init(),
            .delay = 0,
        };
    }
};

pub const Cdrom = struct {
    allocator: std.mem.Allocator,

    status: StatusRegister,
    drive_status: DriveStatus,

    parameter: Fifo,
    response: Fifo,

    interrupt_status: u5,
    interrupt_mask: u5,

    pending_command: ?u8,
    command_delay: u32,

    pending_response: ?PendingResponse,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator) Self {
        return .{
            .allocator = allocator,
            .status = @bitCast(@as(u8, 0b0001_1000)), // parameter_fifo_empty, parameter_fifo_writable
            .drive_status = @bitCast(@as(u8, 0b0000_0010)), // motor_on
            .parameter = Fifo.init(),
            .response = Fifo.init(),
            .interrupt_status = 0,
            .interrupt_mask = 0,
            .pending_command = null,
            .command_delay = 0,
            .pending_response = null,
        };
    }

    pub fn read8(self: *Self, offset: u32) u8 {
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
                    1 => {
                        self.interrupt_status &= ~@as(u5, @truncate(value));

                        // when interrupt is acknowledged, check for pending second response
                        // TODO: should support multiple pending responses
                        if (self.interrupt_status == 0) {
                            if (self.pending_response) |*pending| {
                                if (pending.delay == 0) {
                                    // deliver immediately
                                    self.deliverPendingResponse();
                                }
                            }
                        }
                    },
                    else => std.debug.print("cdrom: Unhandled write8 to offset {x} with value {x} (Bank: {d})\n", .{ offset, value, self.status.index }),
                }
            },
            else => {
                std.debug.print("cdrom: Unhandled write8 to offset {x} with value {x} (Bank: {d})\n", .{ offset, value, self.status.index });
            },
        }
    }

    fn deliverPendingResponse(self: *Self) void {
        if (self.pending_response) |pending| {
            self.response = pending.payload;
            self.interrupt_status = pending.interrupt;
            self.pending_response = null;
        }
    }

    pub fn step(self: *Self, cycles: u32, intc: *InterruptController) void {
        // process pending command
        if (self.command_delay > 0) {
            if (cycles < self.command_delay) {
                self.command_delay -= cycles;
            } else {
                self.command_delay = 0;

                if (self.pending_command) |cmd| {
                    self.pending_command = null;
                    self.processCommand(cmd, intc);
                }
            }
        }

        // process pending second response
        if (self.pending_response) |*pending| {
            if (pending.delay > 0) {
                if (cycles < pending.delay) {
                    pending.delay -= cycles;
                } else {
                    pending.delay = 0;

                    // only deliver if no interrupt is pending
                    if (self.interrupt_status == 0) {
                        self.deliverPendingResponse();
                        intc.trigger(.cdrom);
                    }
                }
            }
        }
    }

    fn acknowledge(
        self: *Self,
        intc: *InterruptController,
        drive_status: DriveStatus,
        interrupt: Interrupt,
    ) void {
        self.response.clear();
        self.response.push(@bitCast(drive_status));
        self.interrupt_status = @intFromEnum(interrupt);
        intc.trigger(.cdrom);
    }

    fn executeCommand(self: *Self, command: u8) void {
        self.pending_command = command;
        self.command_delay = 30_000;
    }

    fn processCommand(self: *Self, command: u8, intc: *InterruptController) void {
        switch (command) {
            0x01 => { // GetStat
                self.acknowledge(intc, self.drive_status, .acknowledge);
            },
            0x1a => { // GetId
                self.acknowledge(intc, self.drive_status, .acknowledge);

                // no disc
                const status = DriveStatus{ .id_error = 1 };

                self.pending_response = .{
                    .interrupt = @intFromEnum(Interrupt.error_status),
                    .payload = Fifo.fromSlice(&.{
                        @bitCast(status),
                        0x40,
                        0x00,
                        0x00,
                        0x00,
                        0x00,
                        0x00,
                        0x00,
                    }),
                    .delay = 20_000,
                };
            },
            0x19 => {
                const sub_command = self.parameter.pop();

                switch (sub_command) {
                    0x20 => { // CD-ROM version
                        self.response = Fifo.fromSlice(&.{
                            0x94,
                            0x09,
                            0x19,
                            0xc0,
                        });
                        self.interrupt_status = @intFromEnum(Interrupt.acknowledge);

                        intc.trigger(.cdrom);
                    },
                    else => std.debug.print("cdrom: Unhandled sub command {x}\n", .{command}),
                }
            },
            else => std.debug.print("cdrom: Unhandled command {x}\n", .{command}),
        }
    }
};
