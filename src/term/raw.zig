//! Raw mode toggling for the controlling terminal.
//!
//! Disables echo, line buffering and signal generation so the program can
//! read keypresses one byte at a time. Captures the original terminal state
//! on enable so disable can restore it cleanly.

const std = @import("std");
const builtin = @import("builtin");

pub const Error = error{
    NotATerminal,
    GetAttrFailed,
    SetAttrFailed,
};

pub const Handle = if (builtin.os.tag == .windows)
    std.os.windows.HANDLE
else
    std.posix.fd_t;

const Original = if (builtin.os.tag == .windows) u32 else std.posix.termios;

pub const RawMode = struct {
    handle: Handle,
    original: Original,

    /// Switch the given terminal handle into raw mode and return a value that
    /// remembers the original state for later restoration.
    pub fn enable(handle: Handle) Error!RawMode {
        if (builtin.os.tag == .windows) {
            var mode: u32 = 0;
            if (std.os.windows.kernel32.GetConsoleMode(handle, &mode) == 0)
                return error.GetAttrFailed;
            const new_mode = windowsRawFlags(mode);
            if (std.os.windows.kernel32.SetConsoleMode(handle, new_mode) == 0)
                return error.SetAttrFailed;
            return .{ .handle = handle, .original = mode };
        } else {
            const posix = std.posix;
            if (!posix.isatty(handle)) return error.NotATerminal;
            const original = posix.tcgetattr(handle) catch return error.GetAttrFailed;
            const raw = posixRawFlags(original);
            posix.tcsetattr(handle, .FLUSH, raw) catch return error.SetAttrFailed;
            return .{ .handle = handle, .original = original };
        }
    }

    /// Restore the terminal to the state captured by enable.
    pub fn disable(self: RawMode) Error!void {
        if (builtin.os.tag == .windows) {
            if (std.os.windows.kernel32.SetConsoleMode(self.handle, self.original) == 0)
                return error.SetAttrFailed;
        } else {
            std.posix.tcsetattr(self.handle, .FLUSH, self.original) catch
                return error.SetAttrFailed;
        }
    }
};

/// Pure helper that derives a raw-mode termios from an existing one.
/// Exposed for tests and for users composing their own terminal setup.
pub fn posixRawFlags(old: std.posix.termios) std.posix.termios {
    if (builtin.os.tag == .windows) @compileError("posixRawFlags is POSIX only");
    var t = old;
    t.lflag.ECHO = false;
    t.lflag.ICANON = false;
    t.lflag.ISIG = false;
    t.lflag.IEXTEN = false;
    t.iflag.IXON = false;
    t.iflag.ICRNL = false;
    t.iflag.BRKINT = false;
    t.iflag.INPCK = false;
    t.iflag.ISTRIP = false;
    t.oflag.OPOST = false;
    t.cflag.CSIZE = .CS8;
    t.cc[@intFromEnum(std.posix.V.MIN)] = 1;
    t.cc[@intFromEnum(std.posix.V.TIME)] = 0;
    return t;
}

/// Pure helper that derives a raw-mode Windows console input mode from an
/// existing one. Exposed for tests and custom setups.
pub fn windowsRawFlags(old: u32) u32 {
    const ENABLE_PROCESSED_INPUT: u32 = 0x0001;
    const ENABLE_LINE_INPUT: u32 = 0x0002;
    const ENABLE_ECHO_INPUT: u32 = 0x0004;
    const ENABLE_VIRTUAL_TERMINAL_INPUT: u32 = 0x0200;
    var m = old;
    m &= ~(ENABLE_PROCESSED_INPUT | ENABLE_LINE_INPUT | ENABLE_ECHO_INPUT);
    m |= ENABLE_VIRTUAL_TERMINAL_INPUT;
    return m;
}

test "windowsRawFlags clears line/echo/processed and sets vt input" {
    const ENABLE_PROCESSED_INPUT: u32 = 0x0001;
    const ENABLE_LINE_INPUT: u32 = 0x0002;
    const ENABLE_ECHO_INPUT: u32 = 0x0004;
    const ENABLE_VIRTUAL_TERMINAL_INPUT: u32 = 0x0200;

    const start = ENABLE_PROCESSED_INPUT | ENABLE_LINE_INPUT | ENABLE_ECHO_INPUT;
    const got = windowsRawFlags(start);

    try std.testing.expect(got & ENABLE_PROCESSED_INPUT == 0);
    try std.testing.expect(got & ENABLE_LINE_INPUT == 0);
    try std.testing.expect(got & ENABLE_ECHO_INPUT == 0);
    try std.testing.expect(got & ENABLE_VIRTUAL_TERMINAL_INPUT != 0);
}

test "windowsRawFlags preserves unrelated bits" {
    const OTHER: u32 = 0x1000;
    const got = windowsRawFlags(OTHER);
    try std.testing.expect(got & OTHER != 0);
}

test "posixRawFlags clears canonical/echo/signal flags" {
    if (builtin.os.tag == .windows) return error.SkipZigTest;
    var t = std.mem.zeroes(std.posix.termios);
    t.lflag.ECHO = true;
    t.lflag.ICANON = true;
    t.lflag.ISIG = true;
    const got = posixRawFlags(t);
    try std.testing.expect(!got.lflag.ECHO);
    try std.testing.expect(!got.lflag.ICANON);
    try std.testing.expect(!got.lflag.ISIG);
    try std.testing.expectEqual(@as(u8, 1), got.cc[@intFromEnum(std.posix.V.MIN)]);
}
