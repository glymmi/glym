//! Input example.
//!
//! Shows the TextInput widget embedded in an MVU app. Type into the box,
//! see what you typed echoed below. Esc or ctrl+c quits.

const std = @import("std");
const glym = @import("glym");

const Model = struct { input: glym.widget.TextInput };
const App = union(enum) {};
const P = glym.Program(Model, App);

fn init(allocator: std.mem.Allocator) anyerror!Model {
    return .{ .input = glym.widget.TextInput.init(allocator) };
}

fn update(model: *Model, m: P.Msg) P.Cmd {
    switch (m) {
        .key => |k| {
            switch (k.code) {
                .escape => return .quit,
                .char => |c| if (c == 'c' and k.modifiers.ctrl) return .quit,
                else => {},
            }
            _ = model.input.handleKey(k) catch return .quit;
        },
        else => {},
    }
    return .none;
}

fn view(model: *const Model, r: *P.Renderer) void {
    r.writeStyledText(1, 2, "Type something:", .{ .bold = true });
    model.input.view(r, 3, 2, 30, .{ .fg = .{ .indexed = 15 } });
    r.writeStyledText(5, 2, "You typed:", .{ .fg = .{ .indexed = 8 } });
    for (model.input.value.items, 0..) |cp, i| {
        if (i >= 30) break;
        r.setCell(5, 13 + @as(u16, @intCast(i)), .{ .char = cp });
    }
    r.writeStyledText(7, 2, "esc or ctrl+c to quit", .{ .fg = .{ .indexed = 8 } });
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
