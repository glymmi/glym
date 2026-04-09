//! Text area example.
//!
//! Multi-line text editor inside a fixed viewport. Type, use arrows to
//! move, enter to break lines. Esc or ctrl+c quits.

const std = @import("std");
const glym = @import("glym");

const Model = struct { area: glym.widget.TextArea };
const App = union(enum) {};
const P = glym.Program(Model, App);

fn init(allocator: std.mem.Allocator) anyerror!Model {
    var area = try glym.widget.TextArea.init(allocator);
    try area.setValue("hello\nthis is a text area\ntype something");
    area.row = 0;
    area.col = 0;
    return .{ .area = area };
}

fn update(model: *Model, m: P.Msg) P.Cmd {
    switch (m) {
        .key => |k| {
            switch (k.code) {
                .escape => return .quit,
                .char => |c| if (c == 'c' and k.modifiers.ctrl) return .quit,
                else => {},
            }
            _ = model.area.handleKey(k) catch return .quit;
        },
        else => {},
    }
    return .none;
}

fn view(model: *Model, r: *P.Renderer) void {
    r.writeStyledText(1, 2, "Text area - arrows, enter, esc to quit", .{ .bold = true });
    model.area.view(r, 3, 2, 8, 40, .{ .fg = .{ .indexed = 15 } });
    var buf: [64]u8 = undefined;
    const status = std.fmt.bufPrint(&buf, "row {d}, col {d}", .{ model.area.row, model.area.col }) catch return;
    r.writeStyledText(12, 2, status, .{ .fg = .{ .indexed = 8 } });
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
