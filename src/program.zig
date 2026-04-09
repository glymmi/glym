//! MVU runtime.
//!
//! Generic over the user's Model and AppMsg types. The user supplies init,
//! update and view functions and calls Program.run, which sets the terminal
//! up, drives the read/parse/update/render loop, and restores the terminal
//! on exit. The runtime stays synchronous for now: a thread pool for async
//! commands lands later.

const std = @import("std");
const builtin = @import("builtin");

const ansi = @import("term/ansi.zig");
const raw = @import("term/raw.zig");
const term_size = @import("term/size.zig");
const input = @import("term/input.zig");
const renderer_mod = @import("renderer.zig");
const msg_mod = @import("msg.zig");
const cmd_mod = @import("cmd.zig");

pub fn Program(comptime Model: type, comptime AppMsg: type) type {
    return struct {
        const Self = @This();

        pub const Msg = msg_mod.Msg(AppMsg);
        pub const Cmd = cmd_mod.Cmd(AppMsg);
        pub const Renderer = renderer_mod.Renderer;
        pub const StepResult = enum { keep_running, quit };

        pub const InitFn = *const fn (std.mem.Allocator) anyerror!Model;
        pub const UpdateFn = *const fn (*Model, Msg) Cmd;
        pub const ViewFn = *const fn (*Model, *Renderer) void;
        pub const DeinitFn = *const fn (*Model, std.mem.Allocator) void;

        allocator: std.mem.Allocator,
        init_fn: InitFn,
        update_fn: UpdateFn,
        view_fn: ViewFn,
        /// Optional model cleanup. Called on every exit path from `run`.
        /// Contract: init allocates, deinit frees, run handles the rest.
        deinit_fn: ?DeinitFn = null,

        /// Run a single update + command pass on the given model. Exposed
        /// so tests can drive the runtime without a real terminal.
        pub fn step(self: Self, model: *Model, m: Msg) anyerror!StepResult {
            const c = self.update_fn(model, m);
            return self.runCmd(c, model);
        }

        fn runCmd(self: Self, c: Cmd, model: *Model) anyerror!StepResult {
            return switch (c) {
                .none => .keep_running,
                .quit => .quit,
                .custom => |func| blk: {
                    const result = try func(self.allocator);
                    if (result) |app_msg| {
                        break :blk try self.step(model, .{ .app = app_msg });
                    }
                    break :blk .keep_running;
                },
            };
        }

        /// Set the terminal up, drive the loop until quit, then restore
        /// the terminal. Every exit path, error or clean, leaves the alt
        /// screen, restores the cursor and raw mode, and runs `deinit_fn`.
        pub fn run(self: Self) !void {
            const stdin_handle = stdinHandle();
            const stdout_handle = stdoutHandle();

            var raw_mode = try raw.RawMode.enable(stdin_handle);
            defer raw_mode.disable() catch {};

            try writeAll(stdout_handle, ansi.enter_alt_screen);
            defer writeAll(stdout_handle, ansi.leave_alt_screen) catch {};

            try writeAll(stdout_handle, ansi.hide_cursor);
            defer writeAll(stdout_handle, ansi.show_cursor) catch {};

            try writeAll(stdout_handle, ansi.clear_screen);

            const current_size = term_size.get(stdout_handle) catch term_size.Size{ .rows = 24, .cols = 80 };

            var renderer = try renderer_mod.Renderer.init(self.allocator, current_size.rows, current_size.cols);
            defer renderer.deinit();

            var model = try self.init_fn(self.allocator);
            defer if (self.deinit_fn) |df| df(&model, self.allocator);

            renderer.clear();
            self.view_fn(&model, &renderer);
            try writeAll(stdout_handle, try renderer.flush());

            var read_buf: [256]u8 = undefined;
            var pending: std.ArrayList(u8) = .{};
            defer pending.deinit(self.allocator);

            while (true) {
                const n = readBytes(stdin_handle, &read_buf) catch |err| switch (err) {
                    error.ReadFailed => break,
                    else => return err,
                };
                if (n == 0) break;
                try pending.appendSlice(self.allocator, read_buf[0..n]);

                var should_quit = false;
                while (input.parse(pending.items)) |result| {
                    const remaining = pending.items[result.consumed..];
                    std.mem.copyForwards(u8, pending.items[0..remaining.len], remaining);
                    pending.shrinkRetainingCapacity(remaining.len);

                    const wrapped: Msg = .{ .key = result.key };
                    if (try self.step(&model, wrapped) == .quit) {
                        should_quit = true;
                        break;
                    }
                }
                if (should_quit) break;

                if (term_size.get(stdout_handle)) |new_size| {
                    if (new_size.rows != renderer.rows or new_size.cols != renderer.cols) {
                        try renderer.resize(new_size.rows, new_size.cols);
                        if (try self.step(&model, .{ .resize = new_size }) == .quit) break;
                    }
                } else |_| {}

                renderer.clear();
                self.view_fn(&model, &renderer);
                try writeAll(stdout_handle, try renderer.flush());
            }
        }

        /// Same as `run`, but on error writes the terminal restore
        /// sequences one more time before propagating. A safety net for
        /// users who would otherwise be left staring at a broken TTY.
        pub fn runSafely(self: Self) !void {
            self.run() catch |err| {
                const stdout_handle = stdoutHandle();
                writeAll(stdout_handle, ansi.show_cursor) catch {};
                writeAll(stdout_handle, ansi.leave_alt_screen) catch {};
                return err;
            };
        }
    };
}

fn stdinHandle() raw.Handle {
    if (builtin.os.tag == .windows) {
        return std.os.windows.peb().ProcessParameters.hStdInput;
    }
    return std.posix.STDIN_FILENO;
}

fn stdoutHandle() raw.Handle {
    if (builtin.os.tag == .windows) {
        return std.os.windows.peb().ProcessParameters.hStdOutput;
    }
    return std.posix.STDOUT_FILENO;
}

fn readBytes(handle: raw.Handle, buf: []u8) !usize {
    if (builtin.os.tag == .windows) {
        var read_count: u32 = 0;
        if (std.os.windows.kernel32.ReadFile(handle, buf.ptr, @intCast(buf.len), &read_count, null) == 0)
            return error.ReadFailed;
        return read_count;
    }
    return std.posix.read(handle, buf) catch return error.ReadFailed;
}

fn writeAll(handle: raw.Handle, bytes: []const u8) !void {
    if (builtin.os.tag == .windows) {
        var remaining = bytes;
        while (remaining.len > 0) {
            var written: u32 = 0;
            if (std.os.windows.kernel32.WriteFile(handle, remaining.ptr, @intCast(remaining.len), &written, null) == 0)
                return error.WriteFailed;
            if (written == 0) return error.WriteFailed;
            remaining = remaining[written..];
        }
        return;
    }
    var remaining = bytes;
    while (remaining.len > 0) {
        const n = std.posix.write(handle, remaining) catch return error.WriteFailed;
        if (n == 0) return error.WriteFailed;
        remaining = remaining[n..];
    }
}

test "step propagates quit from update" {
    const Model = struct { count: i32 = 0 };
    const App = union(enum) { noop };
    const P = Program(Model, App);

    const H = struct {
        fn initFn(_: std.mem.Allocator) anyerror!Model {
            return .{};
        }
        fn updateFn(_: *Model, _: P.Msg) P.Cmd {
            return .quit;
        }
        fn viewFn(_: *Model, _: *P.Renderer) void {}
    };

    const prog: P = .{
        .allocator = std.testing.allocator,
        .init_fn = H.initFn,
        .update_fn = H.updateFn,
        .view_fn = H.viewFn,
    };

    var model: Model = .{};
    const r = try prog.step(&model, .{ .key = .{ .code = .enter } });
    try std.testing.expectEqual(P.StepResult.quit, r);
}

test "step keeps running when update returns none" {
    const Model = struct {};
    const App = union(enum) { noop };
    const P = Program(Model, App);

    const H = struct {
        fn initFn(_: std.mem.Allocator) anyerror!Model {
            return .{};
        }
        fn updateFn(_: *Model, _: P.Msg) P.Cmd {
            return .none;
        }
        fn viewFn(_: *Model, _: *P.Renderer) void {}
    };

    const prog: P = .{
        .allocator = std.testing.allocator,
        .init_fn = H.initFn,
        .update_fn = H.updateFn,
        .view_fn = H.viewFn,
    };

    var model: Model = .{};
    const r = try prog.step(&model, .{ .key = .{ .code = .escape } });
    try std.testing.expectEqual(P.StepResult.keep_running, r);
}

test "step mutates model on app msg" {
    const Model = struct { count: i32 = 0 };
    const App = union(enum) { increment };
    const P = Program(Model, App);

    const H = struct {
        fn initFn(_: std.mem.Allocator) anyerror!Model {
            return .{};
        }
        fn updateFn(model: *Model, m: P.Msg) P.Cmd {
            switch (m) {
                .app => |a| switch (a) {
                    .increment => model.count += 1,
                },
                else => {},
            }
            return .none;
        }
        fn viewFn(_: *Model, _: *P.Renderer) void {}
    };

    const prog: P = .{
        .allocator = std.testing.allocator,
        .init_fn = H.initFn,
        .update_fn = H.updateFn,
        .view_fn = H.viewFn,
    };

    var model: Model = .{ .count = 0 };
    _ = try prog.step(&model, .{ .app = .increment });
    try std.testing.expectEqual(@as(i32, 1), model.count);
}

test "step runs custom command and feeds the result back into update" {
    const Model = struct { hits: u32 = 0 };
    const App = union(enum) { ping, pong };
    const P = Program(Model, App);

    const H = struct {
        fn initFn(_: std.mem.Allocator) anyerror!Model {
            return .{};
        }
        fn pingCmd(_: std.mem.Allocator) anyerror!?App {
            return .pong;
        }
        fn updateFn(model: *Model, m: P.Msg) P.Cmd {
            switch (m) {
                .app => |a| switch (a) {
                    .ping => return .{ .custom = pingCmd },
                    .pong => {
                        model.hits += 1;
                        return .none;
                    },
                },
                else => {},
            }
            return .none;
        }
        fn viewFn(_: *Model, _: *P.Renderer) void {}
    };

    const prog: P = .{
        .allocator = std.testing.allocator,
        .init_fn = H.initFn,
        .update_fn = H.updateFn,
        .view_fn = H.viewFn,
    };

    var model: Model = .{};
    _ = try prog.step(&model, .{ .app = .ping });
    try std.testing.expectEqual(@as(u32, 1), model.hits);
}
