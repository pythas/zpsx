const std = @import("std");

pub const State = enum {
    idle,
    awaiting_cmd,
    read_id,
    read_buttons_1,
    read_buttons_2,
};

pub const Joypad = struct {
    data: u32,
    status: u32,
    mode: u32,
    control: u32,
    baud: u32,
    state: State,

    const Self = @This();

    pub fn init() Self {
        return .{
            .data = 0,
            .status = 0x0005,
            .mode = 0,
            .control = 0,
            .baud = 0,
            .state = .idle,
        };
    }

    pub fn read16(self: *Self, offset: u32) u16 {
        return switch (offset) {
            0x04 => @truncate(self.status),
            0x0a => @truncate(self.control),
            else => {
                std.debug.print("joypad: Unhandled read16 from offset {x}\n", .{offset});
                return 0;
            },
        };
    }

    pub fn write16(self: *Self, offset: u32, value: u16) void {
        switch (offset) {
            0x08 => self.mode = value,
            0x0a => self.control = value,
            0x0e => self.baud = value,
            else => std.debug.print("joypad: Unhandled write16 from offset {x}\n", .{offset}),
        }
    }

    pub fn read8(self: *Self, offset: u32) u8 {
        return switch (offset) {
            0x00 => @truncate(self.data),
            else => {
                std.debug.print("joypad: Unhandled read8 from offset {x}\n", .{offset});
                return 0;
            },
        };
    }

    pub fn write8(self: *Self, offset: u32, value: u8) void {
        switch (offset) {
            0x00 => {
                var response: u8 = 0xff;

                switch (self.state) {
                    .idle => {
                        if (value == 0x01) {
                            self.state = .awaiting_cmd;
                            response = 0xff;
                        }
                    },
                    .awaiting_cmd => {
                        if (value == 0x42) {
                            self.state = .read_id;
                            response = 0x41;
                        } else {
                            self.state = .idle;
                        }
                    },
                    .read_id => {
                        self.state = .read_buttons_1;
                        response = 0x5a;
                    },
                    .read_buttons_1 => {
                        self.state = .read_buttons_2;
                        response = 0xff;
                    },
                    .read_buttons_2 => {
                        self.state = .idle;
                        response = 0xff;
                    },
                }

                self.data = response;
                self.status |= 0x0002;
                self.status |= 0x0200;
            },
            else => std.debug.print("joypad: Unhandled write8 from offset {x}\n", .{offset}),
        }
    }
};
