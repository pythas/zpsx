const std = @import("std");

const sokol = @import("sokol");
const sg = sokol.gfx;

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

    pub fn push_shaded_triangle(
        self: *Self,
        x1: i16,
        y1: i16,
        c1: u32,
        x2: i16,
        y2: i16,
        c2: u32,
        x3: i16,
        y3: i16,
        c3: u32,
    ) void {
        if (self.vertex_count + 3 > self.vertex_buffer.len) return;

        const fx1 = (@as(f32, @floatFromInt(x1)) / 512.0) - 1.0;
        const fy1 = 1.0 - (@as(f32, @floatFromInt(y1)) / 256.0);
        const fx2 = (@as(f32, @floatFromInt(x2)) / 512.0) - 1.0;
        const fy2 = 1.0 - (@as(f32, @floatFromInt(y2)) / 256.0);
        const fx3 = (@as(f32, @floatFromInt(x3)) / 512.0) - 1.0;
        const fy3 = 1.0 - (@as(f32, @floatFromInt(y3)) / 256.0);

        self.vertex_buffer[self.vertex_count] = .{ .x = fx1, .y = fy1, .r = @truncate(c1), .g = @truncate(c1 >> 8), .b = @truncate(c1 >> 16), .a = 255 };
        self.vertex_buffer[self.vertex_count + 1] = .{ .x = fx2, .y = fy2, .r = @truncate(c2), .g = @truncate(c2 >> 8), .b = @truncate(c2 >> 16), .a = 255 };
        self.vertex_buffer[self.vertex_count + 2] = .{ .x = fx3, .y = fy3, .r = @truncate(c3), .g = @truncate(c3 >> 8), .b = @truncate(c3 >> 16), .a = 255 };
        self.vertex_count += 3;
    }
};
