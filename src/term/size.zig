//! Terminal size queries.
//!
//! Reads the current rows and columns of a terminal handle. Backed by
//! TIOCGWINSZ on posix and GetConsoleScreenBufferInfo on windows. Resize
//! events are surfaced through the runtime, not from this module.

const std = @import("std");
const builtin = @import("builtin");
const raw = @import("raw.zig");

pub const Error = error{
    NotATerminal,
    GetSizeFailed,
};

pub const Size = struct {
    rows: u16,
    cols: u16,
};

pub const Winsize = extern struct {
    ws_row: u16,
    ws_col: u16,
    ws_xpixel: u16,
    ws_ypixel: u16,
};

const TIOCGWINSZ: u32 = switch (builtin.os.tag) {
    .linux => 0x5413,
    .macos, .freebsd, .netbsd, .openbsd, .dragonfly => 0x40087468,
    else => 0,
};

/// Read the current rows and columns of the given terminal handle.
pub fn get(handle: raw.Handle) Error!Size {
    if (builtin.os.tag == .windows) {
        var info: std.os.windows.CONSOLE_SCREEN_BUFFER_INFO = undefined;
        if (std.os.windows.kernel32.GetConsoleScreenBufferInfo(handle, &info) == 0)
            return error.GetSizeFailed;
        const cols: u16 = @intCast(info.srWindow.Right - info.srWindow.Left + 1);
        const rows: u16 = @intCast(info.srWindow.Bottom - info.srWindow.Top + 1);
        return .{ .rows = rows, .cols = cols };
    } else {
        if (!std.posix.isatty(handle)) return error.NotATerminal;
        var ws: Winsize = undefined;
        const rc = std.c.ioctl(handle, TIOCGWINSZ, &ws);
        if (rc != 0) return error.GetSizeFailed;
        return fromWinsize(ws);
    }
}

/// Pure helper: convert a posix winsize struct to a Size. Exposed for tests
/// and for callers that already have a winsize from another source.
pub fn fromWinsize(ws: Winsize) Size {
    return .{ .rows = ws.ws_row, .cols = ws.ws_col };
}

test "fromWinsize maps rows and cols" {
    const ws: Winsize = .{ .ws_row = 24, .ws_col = 80, .ws_xpixel = 0, .ws_ypixel = 0 };
    const size = fromWinsize(ws);
    try std.testing.expectEqual(@as(u16, 24), size.rows);
    try std.testing.expectEqual(@as(u16, 80), size.cols);
}

test "fromWinsize ignores pixel fields" {
    const ws: Winsize = .{ .ws_row = 50, .ws_col = 200, .ws_xpixel = 1920, .ws_ypixel = 1080 };
    const size = fromWinsize(ws);
    try std.testing.expectEqual(@as(u16, 50), size.rows);
    try std.testing.expectEqual(@as(u16, 200), size.cols);
}

test "Size holds plain rows and cols" {
    const s: Size = .{ .rows = 10, .cols = 20 };
    try std.testing.expectEqual(@as(u16, 10), s.rows);
    try std.testing.expectEqual(@as(u16, 20), s.cols);
}
