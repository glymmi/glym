//! Progress bar example.
//!
//! Three bars at different levels. Use left/right arrows to adjust the
//! selected bar, up/down to switch between bars. Esc or ctrl+c quits.

const std = @import("std");
const glym = @import("glym");

const Model = struct {
    bars: [3]glym.widget.ProgressBar,
    selected: usize,
};

const App = union(enum) {};
const P = glym.Program(Model, App);

fn init(_: std.mem.Allocator) anyerror!Model {
    var bars: [3]glym.widget.ProgressBar = undefined;
    bars[0] = glym.widget.ProgressBar.init(0.25);
    bars[0].label = "CPU";
    bars[1] = glym.widget.ProgressBar.init(0.60);
    bars[1].label = "MEM";
    bars[2] = glym.widget.ProgressBar.init(0.10);
    bars[2].label = "DSK";
    return .{ .bars = bars, .selected = 0 };
}

fn update(model: *Model, m: P.Msg) P.Cmd {
    switch (m) {
        .key => |k| {
            switch (k.code) {
                .escape => return .quit,
                .char => |c| if (c == 'c' and k.modifiers.ctrl) return .quit,
                .arrow_up => {
                    if (model.selected > 0) model.selected -= 1;
                },
                .arrow_down => {
                    if (model.selected < model.bars.len - 1) model.selected += 1;
                },
                .arrow_right => {
                    const p = model.bars[model.selected].progress;
                    model.bars[model.selected].setProgress(p + 0.05);
                },
                .arrow_left => {
                    const p = model.bars[model.selected].progress;
                    model.bars[model.selected].setProgress(p - 0.05);
                },
                else => {},
            }
        },
        else => {},
    }
    return .none;
}

fn view(model: *Model, r: *P.Renderer) void {
    r.writeStyledText(1, 2, "Progress bars - arrows to adjust, esc to quit", .{ .fg = .{ .indexed = 8 } });
    for (0..model.bars.len) |i| {
        const row: u16 = @intCast(3 + i * 2);
        var style: glym.style.Style = .{ .fg = .{ .indexed = 15 } };
        if (i == model.selected) style.bold = true;
        model.bars[i].view(r, row, 2, 30, style);
    }
}

pub fn main() !void {
    const program: P = .{
        .allocator = std.heap.page_allocator,
        .init_fn = init,
        .update_fn = update,
        .view_fn = view,
    };
    try program.run();
}
