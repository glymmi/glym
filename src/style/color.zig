//! Terminal colors and SGR sequence helpers.
//!
//! `Color` covers the three flavors a modern terminal accepts: the default
//! color, an indexed palette entry (0..255 covering basic, bright and the
//! 6x6x6 cube plus grays) and direct RGB. The `fgSequence` and `bgSequence`
//! helpers write the right SGR escape into a caller-provided buffer so the
//! renderer can stay alloc-free on the hot path.

const std = @import("std");

pub const Rgb = struct { r: u8, g: u8, b: u8 };

pub const Color = union(enum) {
    default,
    indexed: u8,
    rgb: Rgb,
};

/// Write the foreground SGR sequence for `color` into `buf` and return the
/// slice that was filled. `buf` must be at least 20 bytes.
pub fn fgSequence(buf: []u8, color: Color) ![]u8 {
    return switch (color) {
        .default => std.fmt.bufPrint(buf, "\x1b[39m", .{}),
        .indexed => |n| {
            if (n < 8) return std.fmt.bufPrint(buf, "\x1b[3{d}m", .{n});
            if (n < 16) return std.fmt.bufPrint(buf, "\x1b[9{d}m", .{n - 8});
            return std.fmt.bufPrint(buf, "\x1b[38;5;{d}m", .{n});
        },
        .rgb => |c| std.fmt.bufPrint(buf, "\x1b[38;2;{d};{d};{d}m", .{ c.r, c.g, c.b }),
    };
}

/// Write the background SGR sequence for `color` into `buf` and return the
/// slice that was filled. `buf` must be at least 20 bytes.
pub fn bgSequence(buf: []u8, color: Color) ![]u8 {
    return switch (color) {
        .default => std.fmt.bufPrint(buf, "\x1b[49m", .{}),
        .indexed => |n| {
            if (n < 8) return std.fmt.bufPrint(buf, "\x1b[4{d}m", .{n});
            if (n < 16) return std.fmt.bufPrint(buf, "\x1b[10{d}m", .{n - 8});
            return std.fmt.bufPrint(buf, "\x1b[48;5;{d}m", .{n});
        },
        .rgb => |c| std.fmt.bufPrint(buf, "\x1b[48;2;{d};{d};{d}m", .{ c.r, c.g, c.b }),
    };
}

test "fg default" {
    var buf: [32]u8 = undefined;
    const s = try fgSequence(&buf, .default);
    try std.testing.expectEqualStrings("\x1b[39m", s);
}

test "fg indexed basic red" {
    var buf: [32]u8 = undefined;
    const s = try fgSequence(&buf, .{ .indexed = 1 });
    try std.testing.expectEqualStrings("\x1b[31m", s);
}

test "fg indexed basic white" {
    var buf: [32]u8 = undefined;
    const s = try fgSequence(&buf, .{ .indexed = 7 });
    try std.testing.expectEqualStrings("\x1b[37m", s);
}

test "fg indexed bright red" {
    var buf: [32]u8 = undefined;
    const s = try fgSequence(&buf, .{ .indexed = 9 });
    try std.testing.expectEqualStrings("\x1b[91m", s);
}

test "fg indexed bright white" {
    var buf: [32]u8 = undefined;
    const s = try fgSequence(&buf, .{ .indexed = 15 });
    try std.testing.expectEqualStrings("\x1b[97m", s);
}

test "fg indexed 256 palette" {
    var buf: [32]u8 = undefined;
    const s = try fgSequence(&buf, .{ .indexed = 200 });
    try std.testing.expectEqualStrings("\x1b[38;5;200m", s);
}

test "fg indexed boundary 16" {
    var buf: [32]u8 = undefined;
    const s = try fgSequence(&buf, .{ .indexed = 16 });
    try std.testing.expectEqualStrings("\x1b[38;5;16m", s);
}

test "fg rgb" {
    var buf: [32]u8 = undefined;
    const s = try fgSequence(&buf, .{ .rgb = .{ .r = 255, .g = 128, .b = 0 } });
    try std.testing.expectEqualStrings("\x1b[38;2;255;128;0m", s);
}

test "bg default" {
    var buf: [32]u8 = undefined;
    const s = try bgSequence(&buf, .default);
    try std.testing.expectEqualStrings("\x1b[49m", s);
}

test "bg indexed basic green" {
    var buf: [32]u8 = undefined;
    const s = try bgSequence(&buf, .{ .indexed = 2 });
    try std.testing.expectEqualStrings("\x1b[42m", s);
}

test "bg indexed bright cyan" {
    var buf: [32]u8 = undefined;
    const s = try bgSequence(&buf, .{ .indexed = 14 });
    try std.testing.expectEqualStrings("\x1b[106m", s);
}

test "bg indexed 256 palette" {
    var buf: [32]u8 = undefined;
    const s = try bgSequence(&buf, .{ .indexed = 200 });
    try std.testing.expectEqualStrings("\x1b[48;5;200m", s);
}

test "bg rgb" {
    var buf: [32]u8 = undefined;
    const s = try bgSequence(&buf, .{ .rgb = .{ .r = 0, .g = 128, .b = 255 } });
    try std.testing.expectEqualStrings("\x1b[48;2;0;128;255m", s);
}
