//! Async fetch example.
//!
//! Press space to kick off a fake background fetch. The task sleeps for
//! half a second on a worker thread and then sends its result back as
//! an app message. The UI keeps responding to keypresses while the
//! fetch is in flight, demonstrating Cmd.async_task. Esc or ctrl+c
//! quits.

const std = @import("std");
const glym = @import("glym");

const Model = struct {
    in_flight: u32 = 0,
    completed: u32 = 0,
    last_value: i32 = 0,
};

const App = union(enum) {
    fetched: i32,
};

const P = glym.Program(Model, App);

fn init(_: std.mem.Allocator) anyerror!Model {
    return .{};
}

fn fetchTask(_: std.mem.Allocator) anyerror!?App {
    // Pretend to do real work. The main loop stays responsive while
    // this thread sleeps because we are running on the worker pool.
    std.Thread.sleep(500 * std.time.ns_per_ms);
    const seed: u64 = @intCast(std.time.milliTimestamp());
    var prng = std.Random.DefaultPrng.init(seed);
    const value = prng.random().intRangeAtMost(i32, 1, 100);
    return .{ .fetched = value };
}

fn update(model: *Model, m: P.Msg) P.Cmd {
    switch (m) {
        .key => |k| {
            switch (k.code) {
                .escape => return .quit,
                .char => |c| {
                    if (c == 'c' and k.modifiers.ctrl) return .quit;
                    if (c == ' ') {
                        model.in_flight += 1;
                        return .{ .async_task = fetchTask };
                    }
                },
                else => {},
            }
        },
        .app => |a| switch (a) {
            .fetched => |value| {
                if (model.in_flight > 0) model.in_flight -= 1;
                model.completed += 1;
                model.last_value = value;
            },
        },
        else => {},
    }
    return .none;
}

fn view(model: *Model, r: *P.Renderer) void {
    r.writeStyledText(1, 2, "Async fetch demo", .{ .bold = true });
    r.writeStyledText(3, 2, "space to fetch, esc or ctrl+c to quit", .{ .fg = .{ .indexed = 8 } });

    var buf: [64]u8 = undefined;
    const stats = std.fmt.bufPrint(&buf, "in flight: {d}   completed: {d}", .{ model.in_flight, model.completed }) catch return;
    r.writeText(5, 2, stats);

    if (model.completed > 0) {
        var buf2: [64]u8 = undefined;
        const last = std.fmt.bufPrint(&buf2, "last value: {d}", .{model.last_value}) catch return;
        r.writeStyledText(6, 2, last, .{ .fg = .{ .indexed = 14 } });
    }

    if (model.in_flight > 0) {
        r.writeStyledText(8, 2, "loading...", .{ .fg = .{ .indexed = 11 } });
    }
}

pub fn main() !void {
    var gpa: std.heap.GeneralPurposeAllocator(.{}) = .{};
    defer _ = gpa.deinit();

    const program: P = .{
        .allocator = gpa.allocator(),
        .init_fn = init,
        .update_fn = update,
        .view_fn = view,
    };
    try program.runSafely();
}
