const std = @import("std");

const sokol = @import("sokol");
const sg = sokol.gfx;

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

    vertex_buffer: []Vertex,
    vertex_count: usize,

    bind: sg.Bindings = .{},
    pip: sg.Pipeline = .{},
    pass_action: sg.PassAction = .{},
    render_target: sg.Image,
    view: sg.View,
    sampled_view: sg.View,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator) !Self {
        const vertex_buffer = try allocator.alloc(Vertex, 65536);

        var bind = sg.Bindings{};
        bind.vertex_buffers[0] = sg.makeBuffer(.{
            .size = 65536 * @sizeOf(Vertex),
            .usage = .{ .stream_update = true },
            .label = "psx_vertex_buffer",
        });

        const render_target = sg.makeImage(.{
            .usage = .{ .color_attachment = true },
            .width = 1024,
            .height = 512,
            .pixel_format = .RGBA8,
            .sample_count = 1,
            .label = "vram_render_target",
        });

        const view = sg.makeView(.{
            .color_attachment = .{ .image = render_target },
            .label = "vram_view",
        });

        const sampled_view = sg.makeView(.{
            .texture = .{ .image = render_target },
            .label = "vram_sampled_view",
        });

        var shd_desc = sg.ShaderDesc{};
        shd_desc.vertex_func.source = @embedFile("shaders/vram.vert");
        shd_desc.fragment_func.source = @embedFile("shaders/vram.frag");

        const shd = sg.makeShader(shd_desc);

        var pip_desc = sg.PipelineDesc{
            .shader = shd,
            .primitive_type = .TRIANGLES,
            .depth = .{ .pixel_format = .NONE },
            .label = "vram_pipeline",
        };
        pip_desc.layout.attrs[0].format = .FLOAT2;
        pip_desc.layout.attrs[1].format = .UBYTE4N;
        pip_desc.colors[0].pixel_format = .RGBA8;

        const pip = sg.makePipeline(pip_desc);

        var pass_action = sg.PassAction{};
        pass_action.colors[0] = .{
            .load_action = .CLEAR,
            .clear_value = .{ .r = 0.0, .g = 0.0, .b = 0.0, .a = 1.0 },
        };

        return .{
            .allocator = allocator,
            .vertex_buffer = vertex_buffer,
            .vertex_count = 0,
            .bind = bind,
            .pip = pip,
            .render_target = render_target,
            .view = view,
            .sampled_view = sampled_view,
            .pass_action = pass_action,
        };
    }

    pub fn deinit(self: *Self) void {
        sg.destroyView(self.sampled_view);
        sg.destroyView(self.view);
        sg.destroyImage(self.render_target);
        self.allocator.free(self.vertex_buffer);
    }

    pub fn flush(self: *Self) void {
        if (self.vertex_count == 0) return;

        const data_desc = sg.Range{
            .ptr = self.vertex_buffer.ptr,
            .size = self.vertex_count * @sizeOf(Vertex),
        };
        sg.updateBuffer(self.bind.vertex_buffers[0], data_desc);

        var attachments = sg.Attachments{};
        attachments.colors[0] = self.view;

        sg.beginPass(.{ .action = self.pass_action, .attachments = attachments });
        sg.applyPipeline(self.pip);
        sg.applyBindings(self.bind);
        sg.draw(0, @intCast(self.vertex_count), 1);
        sg.endPass();

        // switch to LOAD to preserve VRAM content after initial clear
        self.pass_action.colors[0].load_action = .LOAD;
        self.vertex_count = 0;
    }

    pub fn pushShadedTriangle(
        self: *Self,
        p1: Point,
        c1: Color,
        p2: Point,
        c2: Color,
        p3: Point,
        c3: Color,
    ) void {
        if (self.vertex_count + 3 > self.vertex_buffer.len) return;

        const fx1 = (@as(f32, @floatFromInt(p1.x)) / 512.0) - 1.0;
        const fy1 = 1.0 - (@as(f32, @floatFromInt(p1.y)) / 256.0);
        const fx2 = (@as(f32, @floatFromInt(p2.x)) / 512.0) - 1.0;
        const fy2 = 1.0 - (@as(f32, @floatFromInt(p2.y)) / 256.0);
        const fx3 = (@as(f32, @floatFromInt(p3.x)) / 512.0) - 1.0;
        const fy3 = 1.0 - (@as(f32, @floatFromInt(p3.y)) / 256.0);

        self.vertex_buffer[self.vertex_count] = .{ .x = fx1, .y = fy1, .r = c1.r, .g = c1.g, .b = c1.b, .a = 255 };
        self.vertex_buffer[self.vertex_count + 1] = .{ .x = fx2, .y = fy2, .r = c2.r, .g = c2.g, .b = c2.b, .a = 255 };
        self.vertex_buffer[self.vertex_count + 2] = .{ .x = fx3, .y = fy3, .r = c3.r, .g = c3.g, .b = c3.b, .a = 255 };

        self.vertex_count += 3;
    }
};
