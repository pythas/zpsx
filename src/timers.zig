const std = @import("std");

const InterruptController = @import("interrupt.zig").InterruptController;

pub const TimerCurrentValue = packed struct(u32) {
    value: u16,
    garbage: u16,
};

pub const TimerMode = packed struct(u32) {
    sync_enable: u1,
    sync_mode: u2,
    reset_target: u1,
    irq_when_target: u1,
    irq_when_ffff: u1,
    irq_repeat_mode: u1,
    irq_pulse_mode: u1,
    clock_source: u2,
    interrupt_request: u1,
    reached_target: u1,
    reached_ffff: u1,
    unknown: u3,
    garbage: u16,
};

pub const TimerTargetValue = packed struct(u32) {
    target: u16,
    garbage: u16,
};

pub const Timer = struct {
    current: TimerCurrentValue,
    mode: TimerMode,
    target: TimerTargetValue,

    const Self = @This();

    pub fn init() Self {
        return .{
            .current = @bitCast(@as(u32, 0)),
            .mode = @bitCast(@as(u32, 0)),
            .target = @bitCast(@as(u32, 0)),
        };
    }
};

pub const Timers = struct {
    timers: [3]Timer,

    sys_clock_timer: u32,
    dot_clock_timer: u32,
    hblank_timer: u32,

    const Self = @This();

    pub fn init() Self {
        return .{
            .timers = [_]Timer{Timer.init()} ** 3,
            .sys_clock_timer = 0,
            .dot_clock_timer = 0,
            .hblank_timer = 0,
        };
    }

    pub fn read32(self: *Self, offset: u32) u32 {
        return switch (offset) {
            0x00...0x2f => {
                const timer_index = offset / 0x10;
                const register_offset = offset % 0x10;
                const timer = &self.timers[timer_index];

                return switch (register_offset) {
                    0x0 => @bitCast(timer.current),
                    0x4 => {
                        const mode = @as(u32, @bitCast(timer.mode));

                        timer.mode.reached_target = 0;
                        timer.mode.reached_ffff = 0;

                        return mode;
                    },
                    0x8 => @bitCast(timer.target),
                    else => {
                        std.debug.print("timers: Unhandled read from gap: {x}\n", .{offset});
                        return 0;
                    },
                };
            },
            else => {
                std.debug.print("timers: Unhandled read32 from offset: {x}\n", .{offset});
                return 0;
            },
        };
    }

    pub fn write32(self: *Self, offset: u32, value: u32) void {
        switch (offset) {
            0x00...0x2f => {
                const timer_index = offset / 0x10;
                const register_offset = offset % 0x10;
                const timer = &self.timers[timer_index];

                switch (register_offset) {
                    0x0 => timer.current = @bitCast(value),
                    0x4 => {
                        timer.mode = @bitCast(value);

                        timer.mode.interrupt_request = 1;
                        timer.current.value = 0;
                    },
                    0x8 => timer.target = @bitCast(value),
                    else => std.debug.print("timers: Unhandled write to gap: {x}\n", .{offset}),
                }
            },
            else => std.debug.print("timers: Unhandled write32 to offset: {x}\n", .{offset}),
        }
    }

    pub fn read16(self: *Self, offset: u32) u16 {
        const aligned_offset = offset & ~@as(u32, 2);

        const full_word = self.read32(aligned_offset);

        if ((offset & 2) == 0) {
            return @as(u16, @truncate(full_word));
        } else {
            return @as(u16, @truncate(full_word >> 16));
        }
    }

    pub fn step(self: *Self, cycles: u32, intc: *InterruptController) void {
        self.sys_clock_timer += cycles;
        const div8_ticks = self.sys_clock_timer / 8;
        self.sys_clock_timer %= 8;

        // cpu * 11 / 7
        self.dot_clock_timer += cycles * 11;
        const dot_ticks = self.dot_clock_timer / 7;
        self.dot_clock_timer %= 7;

        // one tick per 3413 cpu cycles
        self.hblank_timer += cycles;
        var hblank_ticks: u32 = 0;
        if (self.hblank_timer >= 3413) {
            hblank_ticks = 1;
            self.hblank_timer -= 3413;
        }

        for (&self.timers, 0..) |*timer, i| {
            var ticks: u32 = 0;
            const source = timer.mode.clock_source;

            if (i == 0) {
                ticks = if (source == 1 or source == 3) dot_ticks else cycles;
            } else if (i == 1) {
                ticks = if (source == 1 or source == 3) hblank_ticks else cycles;
            } else if (i == 2) {
                ticks = if (source == 2 or source == 3) div8_ticks else cycles;
            }

            if (ticks == 0) continue;

            for (0..ticks) |_| {
                timer.current.value +%= 1;

                if (timer.current.value == timer.target.target) {
                    timer.mode.reached_target = 1;

                    // reset if the mode asks for it
                    if (timer.mode.reset_target == 1) {
                        timer.current.value = 0;
                    }

                    if (timer.mode.irq_when_target == 1) {
                        triggerIrq(i, intc);
                    }
                }

                // overflow
                if (timer.current.value == 0xffff) {
                    timer.mode.reached_ffff = 1;

                    if (timer.mode.irq_when_ffff == 1) {
                        triggerIrq(i, intc);
                    }
                }
            }
        }
    }

    fn triggerIrq(index: usize, intc: *InterruptController) void {
        switch (index) {
            0 => intc.trigger(.timer0),
            1 => intc.trigger(.timer1),
            2 => intc.trigger(.timer2),
            else => unreachable,
        }
    }
};
