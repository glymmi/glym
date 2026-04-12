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
const color_level_mod = @import("term/color_level.zig");
const shimmer = @import("shimmer");
const renderer_mod = @import("renderer.zig");
const msg_mod = @import("msg.zig");
const cmd_mod = @import("cmd.zig");

/// Build an MVU runtime parameterized over the user's Model and AppMsg
/// types. The caller supplies init, update and view functions and calls
/// `run`, which drives the terminal read/parse/update/render loop.
pub fn Program(comptime Model: type, comptime AppMsg: type) type {
    return struct {
        const Self = @This();

        /// Runtime message union wrapping keys, resize and app events.
        pub const Msg = msg_mod.Msg(AppMsg);
        /// Runtime command union (`none`, `quit`, `custom`, `async_task`).
        pub const Cmd = cmd_mod.Cmd(AppMsg);
        /// Screen renderer used by the view function.
        pub const Renderer = renderer_mod.Renderer;
        /// Terminal color support level.
        pub const ColorLevel = shimmer.ColorLevel;
        /// Result of a single `step`: keep the loop going or quit.
        pub const StepResult = enum { keep_running, quit };

        /// Signature for the model constructor.
        pub const InitFn = *const fn (std.mem.Allocator) anyerror!Model;
        /// Signature for the update function (model + msg -> cmd).
        pub const UpdateFn = *const fn (*Model, Msg) Cmd;
        /// Signature for the view function (model + renderer -> void).
        pub const ViewFn = *const fn (*Model, *Renderer) void;
        /// Signature for the optional model destructor.
        pub const DeinitFn = *const fn (*Model, std.mem.Allocator) void;

        allocator: std.mem.Allocator,
        init_fn: InitFn,
        update_fn: UpdateFn,
        view_fn: ViewFn,
        /// Optional model cleanup. Called on every exit path from `run`.
        /// Contract: init allocates, deinit frees, run handles the rest.
        deinit_fn: ?DeinitFn = null,
        /// Optional override for terminal color support. When null,
        /// `run` detects the level from `TERM` / `COLORTERM` and the
        /// stdout TTY check, then passes it to the renderer so RGB
        /// colors get downgraded on terminals that cannot show them.
        /// Apps that want to pick the level themselves (for example
        /// from a CLI flag or for tests) can set this explicitly.
        /// Apps that want to read the detected level can call
        /// `glym.detectColorLevel` before constructing the program.
        color_level: ?ColorLevel = null,

        /// Run a single update + command pass on the given model. Exposed
        /// so tests can drive the runtime without a real terminal. When
        /// called outside `run`, async commands execute inline because
        /// there is no worker pool to dispatch to.
        pub fn step(self: Self, model: *Model, m: Msg) anyerror!StepResult {
            return self.stepInner(model, m, null);
        }

        fn stepInner(self: Self, model: *Model, m: Msg, runner: ?*AsyncRunner) anyerror!StepResult {
            const c = self.update_fn(model, m);
            return self.runCmd(c, model, runner);
        }

        fn runCmd(self: Self, c: Cmd, model: *Model, runner: ?*AsyncRunner) anyerror!StepResult {
            return switch (c) {
                .none => .keep_running,
                .quit => .quit,
                .custom => |func| blk: {
                    const result = try func(self.allocator);
                    if (result) |app_msg| {
                        break :blk try self.stepInner(model, .{ .app = app_msg }, runner);
                    }
                    break :blk .keep_running;
                },
                .async_task => |func| blk: {
                    if (async_supported) {
                        if (runner) |rn| {
                            try rn.spawn(func);
                            break :blk .keep_running;
                        }
                    }
                    // No runner (e.g. tests via step) or no thread support:
                    // run inline so the result is observable.
                    const result = try func(self.allocator);
                    if (result) |app_msg| {
                        break :blk try self.stepInner(model, .{ .app = app_msg }, runner);
                    }
                    break :blk .keep_running;
                },
                .batch => |cmds| blk: {
                    for (cmds) |sub| {
                        if (try self.runCmd(sub, model, runner) == .quit) {
                            break :blk .quit;
                        }
                    }
                    break :blk .keep_running;
                },
            };
        }

        /// Worker pool that runs `Cmd.async_task` off the main loop. On
        /// POSIX it owns a `std.Thread.Pool`, a results queue, and a
        /// self-pipe so the main loop's `poll` wakes up as soon as a job
        /// produces a follow-up message. On Windows it is a stub and the
        /// runtime falls back to running async tasks inline.
        const async_supported = builtin.os.tag != .windows and @sizeOf(AppMsg) > 0;

        const AsyncRunner = if (!async_supported) struct {
            fn init(self: *AsyncRunner, _: std.mem.Allocator) !void {
                _ = self;
            }
            fn deinit(self: *AsyncRunner) void {
                _ = self;
            }
        } else struct {
            allocator: std.mem.Allocator,
            pool: std.Thread.Pool = undefined,
            mutex: std.Thread.Mutex = .{},
            results: std.ArrayList(AppMsg) = .{},
            wake_read_fd: std.posix.fd_t = -1,
            wake_write_fd: std.posix.fd_t = -1,
            initialized: bool = false,

            const TaskFn = *const fn (std.mem.Allocator) anyerror!?AppMsg;

            fn init(self: *AsyncRunner, allocator: std.mem.Allocator) !void {
                const fds = try std.posix.pipe();
                self.* = .{
                    .allocator = allocator,
                    .wake_read_fd = fds[0],
                    .wake_write_fd = fds[1],
                };
                try self.pool.init(.{ .allocator = allocator });
                self.initialized = true;
            }

            fn deinit(self: *AsyncRunner) void {
                if (!self.initialized) return;
                self.pool.deinit();
                self.results.deinit(self.allocator);
                std.posix.close(self.wake_read_fd);
                std.posix.close(self.wake_write_fd);
                self.initialized = false;
            }

            fn spawn(self: *AsyncRunner, func: TaskFn) !void {
                try self.pool.spawn(workerEntry, .{ self, func });
            }

            fn workerEntry(self: *AsyncRunner, func: TaskFn) void {
                const result = func(self.allocator) catch return;
                if (result) |app_msg| {
                    self.mutex.lock();
                    self.results.append(self.allocator, app_msg) catch {
                        self.mutex.unlock();
                        return;
                    };
                    self.mutex.unlock();
                    const byte = [_]u8{1};
                    _ = std.posix.write(self.wake_write_fd, &byte) catch {};
                }
            }

            fn drain(self: *AsyncRunner, out: *std.ArrayList(AppMsg)) !void {
                self.mutex.lock();
                defer self.mutex.unlock();
                try out.appendSlice(self.allocator, self.results.items);
                self.results.clearRetainingCapacity();
            }
        };

        /// Set the terminal up, drive the loop until quit, then restore
        /// the terminal. Every exit path, error or clean, leaves the alt
        /// screen, restores the cursor and raw mode, and runs `deinit_fn`.
        pub fn run(self: Self) !void {
            const stdin_handle = stdinHandle();
            const stdout_handle = stdoutHandle();

            var raw_mode = try raw.RawMode.enable(stdin_handle);
            defer raw_mode.disable() catch {};

            // Windows: enable VT processing on stdout so the terminal
            // interprets ANSI escape sequences instead of printing them
            // raw. Restored on exit via the saved original mode.
            const stdout_vt: ?VtMode = if (builtin.os.tag == .windows)
                enableVtProcessing(stdout_handle)
            else
                null;
            defer if (stdout_vt) |vt| restoreVtProcessing(stdout_handle, vt);

            try writeAll(stdout_handle, ansi.enter_alt_screen);
            defer writeAll(stdout_handle, ansi.leave_alt_screen) catch {};

            try writeAll(stdout_handle, ansi.hide_cursor);
            defer writeAll(stdout_handle, ansi.show_cursor) catch {};

            try writeAll(stdout_handle, ansi.clear_screen);

            // POSIX resize wakeup: a self-pipe driven by SIGWINCH lets the
            // read loop wake up the moment the terminal is resized, even
            // when the user has not pressed a key. Windows still relies on
            // the per-iteration size poll until we move to ReadConsoleInput.
            var resize_pipe: ResizePipe = .{};
            try resize_pipe.install();
            defer resize_pipe.uninstall();

            var runner: AsyncRunner = undefined;
            try runner.init(self.allocator);
            defer runner.deinit();

            const current_size = term_size.get(stdout_handle) catch term_size.Size{ .rows = 24, .cols = 80 };

            var renderer = try renderer_mod.Renderer.init(self.allocator, current_size.rows, current_size.cols);
            defer renderer.deinit();
            renderer.color_level = self.color_level orelse detectColorLevel(stdout_handle);

            var model = try self.init_fn(self.allocator);
            defer if (self.deinit_fn) |df| df(&model, self.allocator);

            // Send the initial terminal size as a resize event so
            // apps can start background work (e.g. packet capture)
            // immediately without waiting for the first keypress.
            _ = try self.stepInner(&model, .{ .resize = current_size }, &runner);

            renderer.clear();
            self.view_fn(&model, &renderer);
            try writeAll(stdout_handle, try renderer.flush());

            var read_buf: [256]u8 = undefined;
            var pending: std.ArrayList(u8) = .{};
            defer pending.deinit(self.allocator);

            var async_results: if (async_supported) std.ArrayList(AppMsg) else void =
                if (async_supported) .{} else {};
            defer if (async_supported) async_results.deinit(self.allocator);

            while (true) {
                const async_fd: AsyncFd = if (builtin.os.tag == .windows) {} else if (async_supported) runner.wake_read_fd else -1;
                const wake = try resize_pipe.wait(stdin_handle, async_fd);

                var should_quit = false;
                if (wake.input_ready) {
                    const n = readBytes(stdin_handle, &read_buf) catch |err| switch (err) {
                        error.ReadFailed => break,
                        else => return err,
                    };
                    // On Windows, n==0 means ReadConsoleInputW consumed
                    // non-key events (focus, mouse). Treat like a tick.
                    // On POSIX, n==0 means EOF.
                    if (n == 0) {
                        if (builtin.os.tag != .windows) break;
                    } else {
                        try pending.appendSlice(self.allocator, read_buf[0..n]);

                        while (input.parse(pending.items)) |result| {
                            const remaining = pending.items[result.consumed..];
                            std.mem.copyForwards(u8, pending.items[0..remaining.len], remaining);
                            pending.shrinkRetainingCapacity(remaining.len);

                            const wrapped: Msg = .{ .key = result.key };
                            if (try self.stepInner(&model, wrapped, &runner) == .quit) {
                                should_quit = true;
                                break;
                            }
                        }
                    }
                }

                // Windows tick: when no real key input arrived (timeout
                // or only non-key console events), run one update with a
                // null-char key so inline async_task chains keep running.
                if (builtin.os.tag == .windows) {
                    if (!wake.input_ready or pending.items.len == 0) {
                        if (try self.stepInner(&model, .{ .key = .{ .code = .{ .char = 0 } } }, &runner) == .quit) {
                            should_quit = true;
                        }
                    }
                }
                if (should_quit) break;

                // Drain async task results into the model.
                if (wake.async_ready and async_supported) {
                    async_results.clearRetainingCapacity();
                    try runner.drain(&async_results);
                    for (async_results.items) |app_msg| {
                        if (try self.stepInner(&model, .{ .app = app_msg }, &runner) == .quit) {
                            should_quit = true;
                            break;
                        }
                    }
                }
                if (should_quit) break;

                // Resize check: triggered by SIGWINCH on POSIX, or polled
                // every iteration on Windows.
                if (wake.resize_ready or builtin.os.tag == .windows) {
                    if (term_size.get(stdout_handle)) |new_size| {
                        if (new_size.rows != renderer.rows or new_size.cols != renderer.cols) {
                            try renderer.resize(new_size.rows, new_size.cols);
                            if (try self.stepInner(&model, .{ .resize = new_size }, &runner) == .quit) break;
                        }
                    } else |_| {}
                }

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

/// Detect the terminal color support level for the current process.
/// Reads `TERM` and `COLORTERM` and checks whether `stdout_handle` is a
/// TTY. Safe to call before constructing a `Program` so apps can pick
/// alternate palettes when running on a limited terminal.
pub fn detectColorLevel(stdout_handle: raw.Handle) shimmer.ColorLevel {
    const is_tty = if (builtin.os.tag == .windows)
        true
    else
        std.posix.isatty(stdout_handle);
    return color_level_mod.classify(
        color_level_mod.readTerm(),
        color_level_mod.readColorterm(),
        is_tty,
    );
}

// SIGWINCH self-pipe state. The signal handler can only call
// async-signal-safe functions, so it just writes a single byte to a pipe
// that the main loop polls alongside stdin.
const sigwinch = if (builtin.os.tag == .windows) struct {} else struct {
    var write_fd: std.posix.fd_t = -1;

    fn handler(_: i32) callconv(.c) void {
        if (write_fd >= 0) {
            const byte = [_]u8{1};
            _ = std.posix.write(write_fd, &byte) catch {};
        }
    }
};

const Wake = struct {
    input_ready: bool,
    resize_ready: bool,
    async_ready: bool,
};

const ResizePipe = struct {
    read_fd: if (builtin.os.tag == .windows) void else std.posix.fd_t = if (builtin.os.tag == .windows) {} else -1,
    installed: bool = false,
    old_action: if (builtin.os.tag == .windows) void else std.posix.Sigaction = undefined,

    fn install(self: *ResizePipe) !void {
        if (builtin.os.tag == .windows) return;
        const fds = try std.posix.pipe();
        self.read_fd = fds[0];
        sigwinch.write_fd = fds[1];
        var act: std.posix.Sigaction = .{
            .handler = .{ .handler = sigwinch.handler },
            .mask = std.mem.zeroes(std.posix.sigset_t),
            .flags = std.posix.SA.RESTART,
        };
        std.posix.sigaction(std.posix.SIG.WINCH, &act, &self.old_action);
        self.installed = true;
    }

    fn uninstall(self: *ResizePipe) void {
        if (builtin.os.tag == .windows) return;
        if (!self.installed) return;
        std.posix.sigaction(std.posix.SIG.WINCH, &self.old_action, null);
        std.posix.close(sigwinch.write_fd);
        std.posix.close(self.read_fd);
        sigwinch.write_fd = -1;
        self.installed = false;
    }

    fn wait(self: *ResizePipe, stdin_handle: raw.Handle, async_fd: AsyncFd) !Wake {
        if (builtin.os.tag == .windows) {
            // Wait up to 50ms for console input. Returns immediately
            // when input is available, or after timeout so the tick
            // path can run inline async_task chains.
            const rc = std.os.windows.kernel32.WaitForSingleObject(stdin_handle, 50);
            return .{ .input_ready = rc == 0, .resize_ready = false, .async_ready = false };
        }
        var fd_buf: [3]std.posix.pollfd = undefined;
        fd_buf[0] = .{ .fd = stdin_handle, .events = std.posix.POLL.IN, .revents = 0 };
        fd_buf[1] = .{ .fd = self.read_fd, .events = std.posix.POLL.IN, .revents = 0 };
        var n: usize = 2;
        if (async_fd >= 0) {
            fd_buf[2] = .{ .fd = async_fd, .events = std.posix.POLL.IN, .revents = 0 };
            n = 3;
        }
        _ = try std.posix.poll(fd_buf[0..n], -1);
        var resize_ready = false;
        if (fd_buf[1].revents & std.posix.POLL.IN != 0) {
            var drain: [16]u8 = undefined;
            _ = std.posix.read(self.read_fd, &drain) catch {};
            resize_ready = true;
        }
        var async_ready = false;
        if (n == 3 and fd_buf[2].revents & std.posix.POLL.IN != 0) {
            var drain: [16]u8 = undefined;
            _ = std.posix.read(async_fd, &drain) catch {};
            async_ready = true;
        }
        const input_ready = (fd_buf[0].revents & std.posix.POLL.IN) != 0;
        return .{ .input_ready = input_ready, .resize_ready = resize_ready, .async_ready = async_ready };
    }
};

const AsyncFd = if (builtin.os.tag == .windows) void else std.posix.fd_t;

// (WinTimer removed: replaced by WaitForSingleObject timeout +
// ReadConsoleInputW which does not block on non-key events.)

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
        return readConsoleInput(handle, buf);
    }
    return std.posix.read(handle, buf) catch return error.ReadFailed;
}

// Windows console input via ReadConsoleInputW. Reads input records
// directly and extracts character bytes from KEY_EVENT records. Unlike
// ReadFile, this does not block on non-key events (focus, mouse,
// window buffer size) that WaitForSingleObject signals for.
fn readConsoleInput(handle: raw.Handle, buf: []u8) !usize {
    if (builtin.os.tag != .windows) return error.ReadFailed;

    const KEY_EVENT: u16 = 0x0001;

    const KeyEventRecord = extern struct {
        bKeyDown: std.os.windows.BOOL,
        wRepeatCount: u16,
        wVirtualKeyCode: u16,
        wVirtualScanCode: u16,
        uChar: u16,
        dwControlKeyState: u32,
    };

    const InputRecord = extern struct {
        EventType: u16,
        pad: u16 = 0,
        Event: KeyEventRecord,
    };

    const k32 = struct {
        extern "kernel32" fn ReadConsoleInputW(
            hConsoleInput: std.os.windows.HANDLE,
            lpBuffer: [*]InputRecord,
            nLength: u32,
            lpNumberOfEventsRead: *u32,
        ) callconv(.winapi) std.os.windows.BOOL;
    };

    var records: [32]InputRecord = undefined;
    var count: u32 = 0;
    if (k32.ReadConsoleInputW(handle, &records, 32, &count) == 0)
        return error.ReadFailed;

    var pos: usize = 0;
    for (records[0..count]) |rec| {
        if (rec.EventType == KEY_EVENT and rec.Event.bKeyDown != 0) {
            const ch = rec.Event.uChar;
            if (ch == 0) continue;
            if (pos >= buf.len) break;
            // UTF-16 code unit to UTF-8
            if (ch < 0x80) {
                buf[pos] = @intCast(ch);
                pos += 1;
            } else if (ch < 0x800) {
                if (pos + 1 >= buf.len) break;
                buf[pos] = @intCast(0xC0 | (ch >> 6));
                buf[pos + 1] = @intCast(0x80 | (ch & 0x3F));
                pos += 2;
            } else {
                if (pos + 2 >= buf.len) break;
                buf[pos] = @intCast(0xE0 | (ch >> 12));
                buf[pos + 1] = @intCast(0x80 | ((ch >> 6) & 0x3F));
                buf[pos + 2] = @intCast(0x80 | (ch & 0x3F));
                pos += 3;
            }
        }
    }
    return pos;
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

// Windows stdout VT processing. Enables ANSI escape sequence
// interpretation which is off by default on older Windows consoles.
// Also sets the output code page to UTF-8 so Unicode characters
// (box-drawing, etc.) render correctly.
const VtMode = struct {
    original_mode: u32,
    original_cp: u32,
};

const ENABLE_PROCESSED_OUTPUT: u32 = 0x0001;
const ENABLE_VIRTUAL_TERMINAL_PROCESSING: u32 = 0x0004;

extern "kernel32" fn SetConsoleOutputCP(wCodePageID: u32) callconv(.winapi) std.os.windows.BOOL;
extern "kernel32" fn GetConsoleOutputCP() callconv(.winapi) u32;

fn enableVtProcessing(handle: raw.Handle) ?VtMode {
    if (builtin.os.tag != .windows) return null;
    var mode: u32 = 0;
    if (std.os.windows.kernel32.GetConsoleMode(handle, &mode) == 0) return null;
    const new_mode = mode | ENABLE_PROCESSED_OUTPUT | ENABLE_VIRTUAL_TERMINAL_PROCESSING;
    if (std.os.windows.kernel32.SetConsoleMode(handle, new_mode) == 0) return null;
    const old_cp = GetConsoleOutputCP();
    _ = SetConsoleOutputCP(65001); // UTF-8
    return .{ .original_mode = mode, .original_cp = old_cp };
}

fn restoreVtProcessing(handle: raw.Handle, vt: VtMode) void {
    if (builtin.os.tag != .windows) return;
    _ = std.os.windows.kernel32.SetConsoleMode(handle, vt.original_mode);
    _ = SetConsoleOutputCP(vt.original_cp);
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
