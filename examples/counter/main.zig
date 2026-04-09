//! Counter example.
//!
//! Minimal interactive counter driven by the arrow keys. Press up/down to
//! change the value, q or ctrl+c to quit. Demonstrates the full glym MVU
//! loop end to end in under fifty lines.

const std = @import("std");
const glym = @import("glym");

const Model = struct { count: i32 = 0 };
const App = union(enum) {};
const P = glym.Program(Model, App);

fn init(_: std.mem.Allocator) anyerror!Model {
    return .{};
}

fn update(model: *Model, m: P.Msg) P.Cmd {
    switch (m) {
        .key => |k| switch (k.code) {
            .arrow_up => model.count += 1,
            .arrow_down => model.count -= 1,
            .char => |c| {
                if (c == 'q') return .quit;
                if (c == 'c' and k.modifiers.ctrl) return .quit;
            },
            else => {},
        },
        else => {},
    }
    return .none;
}

const pink: glym.style.Rgb = .{ .r = 255, .g = 107, .b = 157 };
const cyan: glym.style.Rgb = .{ .r = 91, .g = 206, .b = 247 };

fn view(model: *Model, r: *P.Renderer) void {
    var buf: [64]u8 = undefined;
    const line = std.fmt.bufPrint(&buf, "Counter: {d}", .{model.count}) catch return;
    r.writeGradientText(1, 2, line, pink, cyan, .{ .bold = true });
    r.writeStyledText(3, 2, "up/down to change, q to quit", .{ .fg = .{ .indexed = 8 } });
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const program: P = .{
        .allocator = gpa.allocator(),
        .init_fn = init,
        .update_fn = update,
        .view_fn = view,
    };
    try program.run();
}
