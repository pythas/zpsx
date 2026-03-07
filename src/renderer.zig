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

        var points = [3]Point{ p1, p2, p3 };
        var colors = [3]Color{ c1, c2, c3 };

        var area = edgeFunction(points[0], points[1], points[2]);

        if (area < 0) {
            std.mem.swap(Point, &points[1], &points[2]);
            std.mem.swap(Color, &colors[1], &colors[2]);
            area = -area;
        }

        if (area == 0) return;

        var bbx = Bbx.fromPoints(&points);

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
                const p = Point{
                    .x = @intCast(x),
                    .y = @intCast(y),
                };

                const w0 = edgeFunction(points[1], points[2], p);
                const w1 = edgeFunction(points[2], points[0], p);
                const w2 = edgeFunction(points[0], points[1], p);

                if (w0 >= 0 and w1 >= 0 and w2 >= 0) {
                    const area_64: i64 = area;

                    // calc barycentric coords
                    // shift up by 12 bits simulating fixed points representation
                    // NOTE: this is not hardware accurate . implement DDA
                    const w0_fixed = @divTrunc(@as(i64, w0) << 12, area_64);
                    const w1_fixed = @divTrunc(@as(i64, w1) << 12, area_64);
                    const w2_fixed = @divTrunc(@as(i64, w2) << 12, area_64);

                    // interpolate using weights
                    const r = (w0_fixed * colors[0].r + w1_fixed * colors[1].r + w2_fixed * colors[2].r) >> 12;
                    const g = (w0_fixed * colors[0].g + w1_fixed * colors[1].g + w2_fixed * colors[2].g) >> 12;
                    const b = (w0_fixed * colors[0].b + w1_fixed * colors[1].b + w2_fixed * colors[2].b) >> 12;

                    gpu.putPixel(@as(i16, @intCast(x)), @as(i16, @intCast(y)), @as(u8, @intCast(r)), @as(u8, @intCast(g)), @as(u8, @intCast(b)));
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

fn edgeFunction(a: Point, b: Point, c: Point) i32 {
    const ax: i32 = a.x;
    const ay: i32 = a.y;
    const bx: i32 = b.x;
    const by: i32 = b.y;
    const cx: i32 = c.x;
    const cy: i32 = c.y;

    return (cx - ax) * (by - ay) - (cy - ay) * (bx - ax);
}
