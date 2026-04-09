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

// -- text input scenario --

const InputApp = struct {
    const Model = struct {
        input: glym.widget.TextInput,
        submitted: bool = false,
    };
    const App = union(enum) {};
    const P = glym.Program(Model, App);

    fn init(a: std.mem.Allocator) anyerror!Model {
        return .{ .input = try glym.widget.TextInput.init(a) };
    }

    fn deinit(model: *Model, _: std.mem.Allocator) void {
        model.input.deinit();
    }

    fn update(model: *Model, m: P.Msg) P.Cmd {
        switch (m) {
            .key => |k| {
                if (k.code == .enter) {
                    model.submitted = true;
                    return .none;
                }
                _ = model.input.handleKey(k) catch return .quit;
            },
            else => {},
        }
        return .none;
    }

    fn view(model: *Model, r: *P.Renderer) void {
        model.input.view(r, 0, 0, 10, .{});
    }
};

test "text_input: type a word and press enter" {
    const prog: InputApp.P = .{
        .allocator = allocator,
        .init_fn = InputApp.init,
        .update_fn = InputApp.update,
        .view_fn = InputApp.view,
        .deinit_fn = InputApp.deinit,
    };
    var model = try prog.init_fn(allocator);
    defer InputApp.deinit(&model, allocator);
    var r = try Renderer.init(allocator, 1, 10);
    defer r.deinit();

    for ("hi") |c| {
        _ = try prog.step(&model, .{ .key = .{ .code = .{ .char = c } } });
    }
    try std.testing.expectEqual(@as(usize, 2), model.input.value.items.len);
    try std.testing.expect(!model.submitted);

    InputApp.view(&model, &r);
    try std.testing.expectEqual(@as(u21, 'h'), r.back[0].char);
    try std.testing.expectEqual(@as(u21, 'i'), r.back[1].char);

    _ = try prog.step(&model, .{ .key = .{ .code = .enter } });
    try std.testing.expect(model.submitted);
}

// -- text area scenario --

const AreaApp = struct {
    const Model = struct { area: glym.widget.TextArea };
    const App = union(enum) {};
    const P = glym.Program(Model, App);

    fn init(a: std.mem.Allocator) anyerror!Model {
        return .{ .area = try glym.widget.TextArea.init(a) };
    }

    fn deinit(model: *Model, _: std.mem.Allocator) void {
        model.area.deinit();
    }

    fn update(model: *Model, m: P.Msg) P.Cmd {
        switch (m) {
            .key => |k| _ = model.area.handleKey(k) catch return .quit,
            else => {},
        }
        return .none;
    }

    fn view(model: *Model, r: *P.Renderer) void {
        model.area.view(r, 0, 0, 3, 10, .{});
    }
};

test "text_area: split a line with enter" {
    const prog: AreaApp.P = .{
        .allocator = allocator,
        .init_fn = AreaApp.init,
        .update_fn = AreaApp.update,
        .view_fn = AreaApp.view,
        .deinit_fn = AreaApp.deinit,
    };
    var model = try prog.init_fn(allocator);
    defer AreaApp.deinit(&model, allocator);
    var r = try Renderer.init(allocator, 3, 10);
    defer r.deinit();

    for ("ab") |c| {
        _ = try prog.step(&model, .{ .key = .{ .code = .{ .char = c } } });
    }
    _ = try prog.step(&model, .{ .key = .{ .code = .enter } });
    for ("cd") |c| {
        _ = try prog.step(&model, .{ .key = .{ .code = .{ .char = c } } });
    }

    try std.testing.expectEqual(@as(usize, 2), model.area.lineCount());
    try std.testing.expectEqual(@as(usize, 1), model.area.row);
    try std.testing.expectEqual(@as(usize, 2), model.area.col);

    AreaApp.view(&model, &r);
    try std.testing.expectEqual(@as(u21, 'a'), r.back[0].char);
    try std.testing.expectEqual(@as(u21, 'b'), r.back[1].char);
    try std.testing.expectEqual(@as(u21, 'c'), r.back[10].char);
    try std.testing.expectEqual(@as(u21, 'd'), r.back[11].char);
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

// -- list scenario --

const ListApp = struct {
    const Model = struct { list: glym.widget.List };
    const App = union(enum) {};
    const P = glym.Program(Model, App);

    const items = [_][]const u8{ "alpha", "beta", "gamma" };

    fn init(_: std.mem.Allocator) anyerror!Model {
        return .{ .list = glym.widget.List.init(&items) };
    }

    fn update(model: *Model, m: P.Msg) P.Cmd {
        switch (m) {
            .key => |k| _ = model.list.handleKey(k) catch return .quit,
            else => {},
        }
        return .none;
    }

    fn view(model: *Model, r: *P.Renderer) void {
        model.list.view(r, 0, 0, 3, 10, .{});
    }
};

test "list: arrow keys move selection and clamp at the ends" {
    const prog: ListApp.P = .{
        .allocator = allocator,
        .init_fn = ListApp.init,
        .update_fn = ListApp.update,
        .view_fn = ListApp.view,
    };
    var model = try prog.init_fn(allocator);
    var r = try Renderer.init(allocator, 3, 10);
    defer r.deinit();

    _ = try prog.step(&model, .{ .key = .{ .code = .arrow_down } });
    _ = try prog.step(&model, .{ .key = .{ .code = .arrow_down } });
    _ = try prog.step(&model, .{ .key = .{ .code = .arrow_down } });
    try std.testing.expectEqual(@as(usize, 2), model.list.selected);

    _ = try prog.step(&model, .{ .key = .{ .code = .home } });
    try std.testing.expectEqual(@as(usize, 0), model.list.selected);

    ListApp.view(&model, &r);
    // First row is selected, so its cells carry the reverse attribute.
    try std.testing.expect(r.back[0].style.reverse);
    try std.testing.expect(!r.back[10].style.reverse);
    try std.testing.expectEqual(@as(u21, 'a'), r.back[0].char);
    try std.testing.expectEqual(@as(u21, 'b'), r.back[10].char);
}
