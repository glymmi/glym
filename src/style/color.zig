//! Terminal colors and SGR sequence helpers.
//!
//! `Color` covers the three flavors a modern terminal accepts: the default
//! color, an indexed palette entry (0..255 covering basic, bright and the
//! 6x6x6 cube plus grays) and direct RGB. The `fgSequence` and `bgSequence`
//! helpers write the right SGR escape into a caller-provided buffer so the
//! renderer can stay alloc-free on the hot path.

const std = @import("std");

pub const Rgb = struct {
    r: u8,
    g: u8,
    b: u8,

    /// Parse a `#rrggbb` or `rrggbb` hex string into an `Rgb`. Returns
    /// `error.InvalidHex` on length or digit problems.
    pub fn fromHex(hex: []const u8) !Rgb {
        var s = hex;
        if (s.len > 0 and s[0] == '#') s = s[1..];
        if (s.len != 6) return error.InvalidHex;
        return .{
            .r = std.fmt.parseInt(u8, s[0..2], 16) catch return error.InvalidHex,
            .g = std.fmt.parseInt(u8, s[2..4], 16) catch return error.InvalidHex,
            .b = std.fmt.parseInt(u8, s[4..6], 16) catch return error.InvalidHex,
        };
    }

    /// Move the color toward black by `amount` (0..1).
    pub fn darken(self: Rgb, amount: f32) Rgb {
        return lerpRgb(self, .{ .r = 0, .g = 0, .b = 0 }, amount);
    }

    /// Move the color toward white by `amount` (0..1).
    pub fn lighten(self: Rgb, amount: f32) Rgb {
        return lerpRgb(self, .{ .r = 255, .g = 255, .b = 255 }, amount);
    }
};

pub const Color = union(enum) {
    default,
    indexed: u8,
    rgb: Rgb,

    /// Return a version of this color that the given terminal level can
    /// actually display. Truecolor passes through. On a 256-palette
    /// terminal, RGB collapses to the nearest 6x6x6 cube or grayscale
    /// ramp entry. On a basic 16-color terminal, RGB and palette entries
    /// collapse to the nearest ANSI color. On `.none`, everything
    /// collapses to `.default`.
    pub fn downgrade(self: Color, level: ColorLevel) Color {
        return switch (level) {
            .truecolor => self,
            .palette_256 => switch (self) {
                .rgb => |c| .{ .indexed = rgbToPalette256(c) },
                else => self,
            },
            .basic => switch (self) {
                .default => self,
                .indexed => |n| if (n < 16) self else .{ .indexed = rgbToBasic16(indexedToRgb(n)) },
                .rgb => |c| .{ .indexed = rgbToBasic16(c) },
            },
            .none => .default,
        };
    }
};

/// Terminal color support level. The runtime detects this at startup and
/// the renderer uses it to downgrade colors the terminal cannot display.
pub const ColorLevel = enum {
    /// No color support. All colors render as default.
    none,
    /// Basic 16-color ANSI (SGR 30-37, 90-97).
    basic,
    /// 256-color indexed palette (SGR 38;5).
    palette_256,
    /// Direct 24-bit RGB (SGR 38;2).
    truecolor,
};

/// Standard xterm RGB values for the 16 ANSI colors. Indexed by color
/// number 0..15.
const ansi16_rgb = [16]Rgb{
    .{ .r = 0, .g = 0, .b = 0 },
    .{ .r = 128, .g = 0, .b = 0 },
    .{ .r = 0, .g = 128, .b = 0 },
    .{ .r = 128, .g = 128, .b = 0 },
    .{ .r = 0, .g = 0, .b = 128 },
    .{ .r = 128, .g = 0, .b = 128 },
    .{ .r = 0, .g = 128, .b = 128 },
    .{ .r = 192, .g = 192, .b = 192 },
    .{ .r = 128, .g = 128, .b = 128 },
    .{ .r = 255, .g = 0, .b = 0 },
    .{ .r = 0, .g = 255, .b = 0 },
    .{ .r = 255, .g = 255, .b = 0 },
    .{ .r = 0, .g = 0, .b = 255 },
    .{ .r = 255, .g = 0, .b = 255 },
    .{ .r = 0, .g = 255, .b = 255 },
    .{ .r = 255, .g = 255, .b = 255 },
};

/// Steps used by the xterm 6x6x6 color cube on each axis.
const cube_steps = [6]u8{ 0, 95, 135, 175, 215, 255 };

fn nearestCubeStep(v: u8) u8 {
    var best: u8 = 0;
    var best_dist: i32 = std.math.maxInt(i32);
    var i: u8 = 0;
    while (i < 6) : (i += 1) {
        const d: i32 = @as(i32, v) - @as(i32, cube_steps[i]);
        const dist = d * d;
        if (dist < best_dist) {
            best_dist = dist;
            best = i;
        }
    }
    return best;
}

/// Map an RGB color to the nearest entry in the 256-color palette. The
/// result is always >= 16 so it does not shadow the basic ANSI colors.
pub fn rgbToPalette256(c: Rgb) u8 {
    // Grayscale ramp is a better match for near-gray colors than the
    // cube because it has 24 steps instead of 6.
    const is_gray = c.r == c.g and c.g == c.b;
    if (is_gray) {
        if (c.r < 8) return 16;
        if (c.r > 248) return 231;
        return 232 + (c.r - 8) / 10;
    }
    const r6 = nearestCubeStep(c.r);
    const g6 = nearestCubeStep(c.g);
    const b6 = nearestCubeStep(c.b);
    return 16 + 36 * r6 + 6 * g6 + b6;
}

/// Map an RGB color to the nearest entry in the basic 16-color palette.
pub fn rgbToBasic16(c: Rgb) u8 {
    var best: u8 = 0;
    var best_dist: i32 = std.math.maxInt(i32);
    var i: u8 = 0;
    while (i < 16) : (i += 1) {
        const e = ansi16_rgb[i];
        const dr: i32 = @as(i32, c.r) - @as(i32, e.r);
        const dg: i32 = @as(i32, c.g) - @as(i32, e.g);
        const db: i32 = @as(i32, c.b) - @as(i32, e.b);
        const dist = dr * dr + dg * dg + db * db;
        if (dist < best_dist) {
            best_dist = dist;
            best = i;
        }
    }
    return best;
}

/// Convert a 256-palette index to an approximate RGB value. Used when
/// downgrading a 256-palette color to a narrower level.
pub fn indexedToRgb(n: u8) Rgb {
    if (n < 16) return ansi16_rgb[n];
    if (n >= 232) {
        const v: u8 = 8 + (n - 232) * 10;
        return .{ .r = v, .g = v, .b = v };
    }
    const k: u8 = n - 16;
    const r6: u8 = k / 36;
    const g6: u8 = (k / 6) % 6;
    const b6: u8 = k % 6;
    return .{ .r = cube_steps[r6], .g = cube_steps[g6], .b = cube_steps[b6] };
}

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

test "Rgb.fromHex parses with hash" {
    const c = try Rgb.fromHex("#ff6b9d");
    try std.testing.expectEqual(@as(u8, 0xff), c.r);
    try std.testing.expectEqual(@as(u8, 0x6b), c.g);
    try std.testing.expectEqual(@as(u8, 0x9d), c.b);
}

test "Rgb.fromHex parses without hash" {
    const c = try Rgb.fromHex("00ff80");
    try std.testing.expectEqual(@as(u8, 0), c.r);
    try std.testing.expectEqual(@as(u8, 255), c.g);
    try std.testing.expectEqual(@as(u8, 128), c.b);
}

test "Rgb.fromHex rejects bad length" {
    try std.testing.expectError(error.InvalidHex, Rgb.fromHex("#fff"));
}

test "Rgb.fromHex rejects non-hex digits" {
    try std.testing.expectError(error.InvalidHex, Rgb.fromHex("#zzzzzz"));
}

test "Rgb.darken at 0 returns the same color" {
    const c: Rgb = .{ .r = 100, .g = 150, .b = 200 };
    try std.testing.expectEqual(c, c.darken(0));
}

test "Rgb.darken at 1 returns black" {
    const c: Rgb = .{ .r = 100, .g = 150, .b = 200 };
    try std.testing.expectEqual(Rgb{ .r = 0, .g = 0, .b = 0 }, c.darken(1));
}

test "Rgb.lighten at 1 returns white" {
    const c: Rgb = .{ .r = 100, .g = 150, .b = 200 };
    try std.testing.expectEqual(Rgb{ .r = 255, .g = 255, .b = 255 }, c.lighten(1));
}

test "rgbToPalette256 pure red maps to cube red" {
    // cube_steps[5] = 255, so (255,0,0) is 16 + 36*5 + 0 + 0 = 196.
    try std.testing.expectEqual(@as(u8, 196), rgbToPalette256(.{ .r = 255, .g = 0, .b = 0 }));
}

test "rgbToPalette256 white maps to cube white" {
    try std.testing.expectEqual(@as(u8, 231), rgbToPalette256(.{ .r = 255, .g = 255, .b = 255 }));
}

test "rgbToPalette256 mid gray maps to grayscale ramp" {
    const idx = rgbToPalette256(.{ .r = 128, .g = 128, .b = 128 });
    try std.testing.expect(idx >= 232 and idx <= 255);
}

test "rgbToBasic16 red wins for pure red" {
    try std.testing.expectEqual(@as(u8, 9), rgbToBasic16(.{ .r = 255, .g = 0, .b = 0 }));
}

test "rgbToBasic16 black wins for pure black" {
    try std.testing.expectEqual(@as(u8, 0), rgbToBasic16(.{ .r = 0, .g = 0, .b = 0 }));
}

test "rgbToBasic16 white wins for pure white" {
    try std.testing.expectEqual(@as(u8, 15), rgbToBasic16(.{ .r = 255, .g = 255, .b = 255 }));
}

test "indexedToRgb roundtrips basic colors" {
    try std.testing.expectEqual(Rgb{ .r = 255, .g = 0, .b = 0 }, indexedToRgb(9));
}

test "Color.downgrade truecolor passes RGB through" {
    const c: Color = .{ .rgb = .{ .r = 12, .g = 34, .b = 56 } };
    try std.testing.expectEqual(c, c.downgrade(.truecolor));
}

test "Color.downgrade palette_256 collapses RGB" {
    const c: Color = .{ .rgb = .{ .r = 255, .g = 0, .b = 0 } };
    const out = c.downgrade(.palette_256);
    try std.testing.expectEqual(@as(u8, 196), out.indexed);
}

test "Color.downgrade basic collapses RGB to ANSI 16" {
    const c: Color = .{ .rgb = .{ .r = 255, .g = 0, .b = 0 } };
    const out = c.downgrade(.basic);
    try std.testing.expectEqual(@as(u8, 9), out.indexed);
}

test "Color.downgrade basic collapses 256 palette to ANSI 16" {
    const c: Color = .{ .indexed = 196 };
    const out = c.downgrade(.basic);
    try std.testing.expectEqual(@as(u8, 9), out.indexed);
}

test "Color.downgrade basic leaves low indexed alone" {
    const c: Color = .{ .indexed = 5 };
    try std.testing.expectEqual(c, c.downgrade(.basic));
}

test "Color.downgrade none erases everything" {
    const c: Color = .{ .rgb = .{ .r = 1, .g = 2, .b = 3 } };
    try std.testing.expectEqual(Color.default, c.downgrade(.none));
}
