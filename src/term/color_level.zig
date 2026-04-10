//! Terminal color support detection.
//!
//! At startup the runtime inspects the environment and the stdout handle
//! to decide how many colors the terminal can show. The result is a
//! `ColorLevel` that the renderer uses to downgrade any color the
//! terminal cannot display. The pure `classify` function takes the raw
//! inputs so tests can cover the matrix without touching the real env.

const std = @import("std");
const builtin = @import("builtin");
const ColorLevel = @import("shimmer").ColorLevel;

/// Classify the terminal from raw inputs. Exposed as a pure function so
/// tests can drive every branch without a real terminal.
///
/// The rules, in order:
///   1. No TTY or `TERM=dumb` -> `.none`.
///   2. `COLORTERM` is `truecolor` or `24bit` -> `.truecolor`.
///   3. `TERM` contains `256` -> `.palette_256`.
///   4. Anything else -> `.basic`.
pub fn classify(term: ?[]const u8, colorterm: ?[]const u8, is_tty: bool) ColorLevel {
    if (!is_tty) return .none;
    if (term) |t| {
        if (std.mem.eql(u8, t, "dumb")) return .none;
    }
    if (colorterm) |c| {
        if (std.mem.eql(u8, c, "truecolor") or std.mem.eql(u8, c, "24bit")) {
            return .truecolor;
        }
    }
    if (term) |t| {
        if (std.mem.indexOf(u8, t, "256") != null) return .palette_256;
    }
    return .basic;
}

/// Read the `TERM` environment variable, or return null if unset. On
/// Windows this always returns null for now: the env-var path will move
/// over when the Windows input pipeline does.
pub fn readTerm() ?[]const u8 {
    if (builtin.os.tag == .windows) return null;
    return std.posix.getenv("TERM");
}

/// Read the `COLORTERM` environment variable, or return null if unset.
pub fn readColorterm() ?[]const u8 {
    if (builtin.os.tag == .windows) return null;
    return std.posix.getenv("COLORTERM");
}

test "classify no tty returns none" {
    try std.testing.expectEqual(ColorLevel.none, classify("xterm-256color", "truecolor", false));
}

test "classify TERM dumb returns none" {
    try std.testing.expectEqual(ColorLevel.none, classify("dumb", null, true));
}

test "classify COLORTERM truecolor wins" {
    try std.testing.expectEqual(ColorLevel.truecolor, classify("xterm", "truecolor", true));
}

test "classify COLORTERM 24bit also truecolor" {
    try std.testing.expectEqual(ColorLevel.truecolor, classify("xterm", "24bit", true));
}

test "classify TERM with 256 returns palette_256" {
    try std.testing.expectEqual(ColorLevel.palette_256, classify("xterm-256color", null, true));
}

test "classify default tty is basic" {
    try std.testing.expectEqual(ColorLevel.basic, classify("xterm", null, true));
}

test "classify missing env still basic on tty" {
    try std.testing.expectEqual(ColorLevel.basic, classify(null, null, true));
}

test "readTerm returns a string or null without crashing" {
    if (builtin.os.tag == .windows) {
        try std.testing.expectEqual(@as(?[]const u8, null), readTerm());
    } else {
        // On POSIX, result depends on the environment. Just verify no crash.
        _ = readTerm();
    }
}

test "readColorterm returns a string or null without crashing" {
    if (builtin.os.tag == .windows) {
        try std.testing.expectEqual(@as(?[]const u8, null), readColorterm());
    } else {
        _ = readColorterm();
    }
}
