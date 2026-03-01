const ig = @import("cimgui_docking");

pub const WindowConfig = struct {
    pos: ig.ImVec2,
    size: ig.ImVec2,
    visible: bool = true,
};

pub const UiState = struct {
    registers: WindowConfig,
    disassembly: WindowConfig,
    vram: WindowConfig,

    pub fn init() UiState {
        return .{
            .registers = .{
                .pos = .{ .x = 10, .y = 30 },
                .size = .{ .x = 300, .y = 600 },
                .visible = true,
            },
            .disassembly = .{
                .pos = .{ .x = 320, .y = 30 + 290 + 10 },
                .size = .{ .x = 400, .y = 290 },
                .visible = true,
            },
            .vram = .{
                .pos = .{ .x = 320, .y = 30 },
                .size = .{ .x = 400, .y = 290 },
                .visible = true,
            },
        };
    }
};
