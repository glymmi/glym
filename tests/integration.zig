//! Integration tests.
//!
//! Drive a real Program with synthetic Msg sequences and verify both
//! model state and rendered back-buffer cells. These complement the
//! pure unit tests inside src/ by exercising the full update + view
//! pipeline end to end without touching a real terminal.

const std = @import("std");
const glym = @import("glym");

const Renderer = glym.renderer.Renderer;
const allocator = std.testing.allocator;

// -- counter scenario --

const Counter = struct {
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
                .char => |c| if (c == 'q') return .quit,
                else => {},
            },
            else => {},
        }
        return .none;
    }

    fn view(model: *Model, r: *P.Renderer) void {
        var buf: [32]u8 = undefined;
        const line = std.fmt.bufPrint(&buf, "n={d}", .{model.count}) catch return;
        r.writeText(0, 0, line);
    }
};

test "counter: arrows mutate model and q quits" {
    const prog: Counter.P = .{
        .allocator = allocator,
        .init_fn = Counter.init,
        .update_fn = Counter.update,
        .view_fn = Counter.view,
    };
    var model = try prog.init_fn(allocator);
    var r = try Renderer.init(allocator, 1, 10);
    defer r.deinit();

    _ = try prog.step(&model, .{ .key = .{ .code = .arrow_up } });
    _ = try prog.step(&model, .{ .key = .{ .code = .arrow_up } });
    _ = try prog.step(&model, .{ .key = .{ .code = .arrow_up } });
    _ = try prog.step(&model, .{ .key = .{ .code = .arrow_down } });
    try std.testing.expectEqual(@as(i32, 2), model.count);

    Counter.view(&model, &r);
    try std.testing.expectEqual(@as(u21, 'n'), r.back[0].char);
    try std.testing.expectEqual(@as(u21, '='), r.back[1].char);
    try std.testing.expectEqual(@as(u21, '2'), r.back[2].char);

    const result = try prog.step(&model, .{ .key = .{ .code = .{ .char = 'q' } } });
    try std.testing.expectEqual(Counter.P.StepResult.quit, result);
}

// -- async task scenario --

const AsyncApp = struct {
    const Model = struct { hits: u32 = 0 };
    const App = union(enum) { pong };
    const P = glym.Program(Model, App);

    fn init(_: std.mem.Allocator) anyerror!Model {
        return .{};
    }

    fn pingTask(_: std.mem.Allocator) anyerror!?App {
        return .pong;
    }

    fn update(model: *Model, m: P.Msg) P.Cmd {
        switch (m) {
            .key => return .{ .async_task = pingTask },
            .app => |a| switch (a) {
                .pong => model.hits += 1,
            },
            else => {},
        }
        return .none;
    }

    fn view(_: *Model, _: *P.Renderer) void {}
};

test "async_task: step runs the task inline and feeds the result back" {
    const prog: AsyncApp.P = .{
        .allocator = allocator,
        .init_fn = AsyncApp.init,
        .update_fn = AsyncApp.update,
        .view_fn = AsyncApp.view,
    };
    var model = try prog.init_fn(allocator);

    // Outside `run`, async_task runs synchronously so the result is
    // observable immediately. Inside `run`, the same Cmd would be
    // dispatched to the worker pool and surface on a later iteration.
    _ = try prog.step(&model, .{ .key = .{ .code = .enter } });
    try std.testing.expectEqual(@as(u32, 1), model.hits);
}
