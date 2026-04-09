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

/// Linearly interpolate between two RGB colors. `t` is clamped to [0, 1].
pub fn lerpRgb(a: Rgb, b: Rgb, t: f32) Rgb {
    const clamped = std.math.clamp(t, 0.0, 1.0);
    const ar: f32 = @floatFromInt(a.r);
    const ag: f32 = @floatFromInt(a.g);
    const ab: f32 = @floatFromInt(a.b);
    const br: f32 = @floatFromInt(b.r);
    const bg: f32 = @floatFromInt(b.g);
    const bb: f32 = @floatFromInt(b.b);
    return .{
        .r = @intFromFloat(@round(ar + (br - ar) * clamped)),
        .g = @intFromFloat(@round(ag + (bg - ag) * clamped)),
        .b = @intFromFloat(@round(ab + (bb - ab) * clamped)),
    };
}

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

test "lerpRgb at t 0 returns the start color" {
    const a: Rgb = .{ .r = 255, .g = 0, .b = 0 };
    const b: Rgb = .{ .r = 0, .g = 0, .b = 255 };
    const got = lerpRgb(a, b, 0);
    try std.testing.expectEqual(a, got);
}

test "lerpRgb at t 1 returns the end color" {
    const a: Rgb = .{ .r = 255, .g = 0, .b = 0 };
    const b: Rgb = .{ .r = 0, .g = 0, .b = 255 };
    const got = lerpRgb(a, b, 1);
    try std.testing.expectEqual(b, got);
}

test "lerpRgb at t 0.5 returns the midpoint" {
    const a: Rgb = .{ .r = 0, .g = 0, .b = 0 };
    const b: Rgb = .{ .r = 200, .g = 100, .b = 50 };
    const got = lerpRgb(a, b, 0.5);
    try std.testing.expectEqual(@as(u8, 100), got.r);
    try std.testing.expectEqual(@as(u8, 50), got.g);
    try std.testing.expectEqual(@as(u8, 25), got.b);
}

test "lerpRgb clamps t below 0" {
    const a: Rgb = .{ .r = 10, .g = 20, .b = 30 };
    const b: Rgb = .{ .r = 200, .g = 200, .b = 200 };
    try std.testing.expectEqual(a, lerpRgb(a, b, -0.5));
}

test "lerpRgb clamps t above 1" {
    const a: Rgb = .{ .r = 10, .g = 20, .b = 30 };
    const b: Rgb = .{ .r = 200, .g = 200, .b = 200 };
    try std.testing.expectEqual(b, lerpRgb(a, b, 2.0));
}
