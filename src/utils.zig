pub inline fn signExtend16(value: u16) u32 {
    return @bitCast(@as(i32, @as(i16, @bitCast(value))));
}
