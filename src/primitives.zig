pub const Point = struct {
    x: i16,
    y: i16,

    pub inline fn fromWord(word: u32) Point {
        return .{
            .x = @bitCast(@as(u16, @truncate(word))),
            .y = @bitCast(@as(u16, @truncate(word >> 16))),
        };
    }

    pub inline fn offset(self: Point, dx: i16, dy: i16) Point {
        return .{
            .x = self.x + dx,
            .y = self.y + dy,
        };
    }
};

pub const Color = struct {
    r: u8,
    g: u8,
    b: u8,

    pub inline fn fromWord(word: u32) Color {
        return .{
            .r = @truncate(word),
            .g = @truncate(word >> 8),
            .b = @truncate(word >> 16),
        };
    }

    pub fn toVramColor(self: Color, semi_transparency_bit: u1) u16 {
        const r = @as(u16, self.r >> 3);
        const g = @as(u16, self.g >> 3);
        const b = @as(u16, self.b >> 3);

        return (@as(u16, semi_transparency_bit) << 15) | (b << 10) | (g << 5) | r;
    }
};
