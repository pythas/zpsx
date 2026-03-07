const std = @import("std");

const sokol = @import("sokol");
const sg = sokol.gfx;

const Gpu = @import("gpu.zig").Gpu;
const Point = @import("gpu.zig").Point;
const Color = @import("gpu.zig").Color;

pub const Vertex = extern struct {
    x: f32,
    y: f32,
    r: u8,
    g: u8,
    b: u8,
    a: u8 = 255,
};

pub const Renderer = struct {
    allocator: std.mem.Allocator,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator) !Self {
        return .{
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Self) void {
        _ = self;
    }

    pub fn flush(self: *Self) void {
        _ = self;
    }

    // pub fn pushShadedTriangle(
    //     self: *Self,
    //     p1: Point,
    //     c1: Color,
    //     p2: Point,
    //     c2: Color,
    //     p3: Point,
    //     c3: Color,
    // ) void {
    //     if (self.vertex_count + 3 > self.vertex_buffer.len) return;
    //
    //     const fx1 = (@as(f32, @floatFromInt(p1.x)) / 512.0) - 1.0;
    //     const fy1 = 1.0 - (@as(f32, @floatFromInt(p1.y)) / 256.0);
    //     const fx2 = (@as(f32, @floatFromInt(p2.x)) / 512.0) - 1.0;
    //     const fy2 = 1.0 - (@as(f32, @floatFromInt(p2.y)) / 256.0);
    //     const fx3 = (@as(f32, @floatFromInt(p3.x)) / 512.0) - 1.0;
    //     const fy3 = 1.0 - (@as(f32, @floatFromInt(p3.y)) / 256.0);
    //
    //     self.vertex_buffer[self.vertex_count] = .{ .x = fx1, .y = fy1, .r = c1.r, .g = c1.g, .b = c1.b, .a = 255 };
    //     self.vertex_buffer[self.vertex_count + 1] = .{ .x = fx2, .y = fy2, .r = c2.r, .g = c2.g, .b = c2.b, .a = 255 };
    //     self.vertex_buffer[self.vertex_count + 2] = .{ .x = fx3, .y = fy3, .r = c3.r, .g = c3.g, .b = c3.b, .a = 255 };
    //
    //     self.vertex_count += 3;
    // }

    pub fn pushShadedTriangle(
        self: *Self,
        gpu: *Gpu,
        p1: Point,
        c1: Color,
        p2: Point,
        c2: Color,
        p3: Point,
        c3: Color,
    ) void {
        _ = self;
        // _ = c1;
        _ = c2;
        _ = c3;

        var bbx = Bbx.fromPoints(&.{ p1, p2, p3 });

        bbx.min_x = @max(bbx.min_x, @as(i16, @intCast(gpu.drawing_area_left)));
        bbx.max_x = @min(bbx.max_x, @as(i16, @intCast(gpu.drawing_area_right)));
        bbx.min_y = @max(bbx.min_y, @as(i16, @intCast(gpu.drawing_area_top)));
        bbx.max_y = @min(bbx.max_y, @as(i16, @intCast(gpu.drawing_area_bottom)));

        if (bbx.min_x > bbx.max_x or bbx.min_y > bbx.max_y) {
            return;
        }

        var y: i32 = bbx.min_y;
        while (y <= bbx.max_y) : (y += 1) {
            var x: i32 = bbx.min_x;
            while (x <= bbx.max_x) : (x += 1) {
                var inside = true;
                inside &= edgeFunction(p1, p2, x, y);
                inside &= edgeFunction(p2, p3, x, y);
                inside &= edgeFunction(p3, p1, x, y);

                if (inside) {
                    gpu.putPixel(@as(i16, @intCast(x)), @as(i16, @intCast(y)), c1.r, c1.g, c1.b);
                }
            }
        }
    }
};

const Bbx = struct {
    min_x: i16,
    max_x: i16,
    min_y: i16,
    max_y: i16,

    pub fn fromPoints(points: []const Point) Bbx {
        var bbx = Bbx{
            .min_x = std.math.maxInt(i16),
            .max_x = std.math.minInt(i16),
            .min_y = std.math.maxInt(i16),
            .max_y = std.math.minInt(i16),
        };

        for (points) |point| {
            bbx.min_x = @min(bbx.min_x, point.x);
            bbx.max_x = @max(bbx.max_x, point.x);
            bbx.min_y = @min(bbx.min_y, point.y);
            bbx.max_y = @max(bbx.max_y, point.y);
        }

        return bbx;
    }
};

fn edgeFunction(a: Point, b: Point, cx: i32, cy: i32) bool {
    const ax: i32 = a.x;
    const ay: i32 = a.y;
    const bx: i32 = b.x;
    const by: i32 = b.y;

    return ((cx - ax) * (by - ay) - (cy - ay) * (bx - ax) >= 0);
}
