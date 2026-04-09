//! Style struct: foreground, background and text attributes.
//!
//! A `Style` value is attached to every cell in the renderer's buffer. The
//! `sequence` helper writes a single combined SGR escape into a caller
//! buffer so the renderer can emit it without allocating.

const std = @import("std");
const color_mod = @import("color.zig");

pub const Color = color_mod.Color;
pub const Rgb = color_mod.Rgb;

pub const Style = struct {
    fg: Color = .default,
    bg: Color = .default,
    bold: bool = false,
    italic: bool = false,
    underline: bool = false,
    reverse: bool = false,

    pub const default: Style = .{};

    pub fn eql(a: Style, b: Style) bool {
        return std.meta.eql(a, b);
    }

    /// Write a single combined SGR sequence for this style into `buf` and
    /// return the slice that was filled. Always starts with a reset so the
    /// caller can rely on the previous terminal state being cleared.
    /// `buf` should be at least 64 bytes to fit the worst case.
    pub fn sequence(self: Style, buf: []u8) ![]u8 {
        var n: usize = 0;
        n += (try std.fmt.bufPrint(buf[n..], "\x1b[0", .{})).len;
        if (self.bold) n += (try std.fmt.bufPrint(buf[n..], ";1", .{})).len;
        if (self.italic) n += (try std.fmt.bufPrint(buf[n..], ";3", .{})).len;
        if (self.underline) n += (try std.fmt.bufPrint(buf[n..], ";4", .{})).len;
        if (self.reverse) n += (try std.fmt.bufPrint(buf[n..], ";7", .{})).len;
        switch (self.fg) {
            .default => {},
            .indexed => |k| {
                if (k < 8) {
                    n += (try std.fmt.bufPrint(buf[n..], ";3{d}", .{k})).len;
                } else if (k < 16) {
                    n += (try std.fmt.bufPrint(buf[n..], ";9{d}", .{k - 8})).len;
                } else {
                    n += (try std.fmt.bufPrint(buf[n..], ";38;5;{d}", .{k})).len;
                }
            },
            .rgb => |c| n += (try std.fmt.bufPrint(buf[n..], ";38;2;{d};{d};{d}", .{ c.r, c.g, c.b })).len,
        }
        switch (self.bg) {
            .default => {},
            .indexed => |k| {
                if (k < 8) {
                    n += (try std.fmt.bufPrint(buf[n..], ";4{d}", .{k})).len;
                } else if (k < 16) {
                    n += (try std.fmt.bufPrint(buf[n..], ";10{d}", .{k - 8})).len;
                } else {
                    n += (try std.fmt.bufPrint(buf[n..], ";48;5;{d}", .{k})).len;
                }
            },
            .rgb => |c| n += (try std.fmt.bufPrint(buf[n..], ";48;2;{d};{d};{d}", .{ c.r, c.g, c.b })).len,
        }
        n += (try std.fmt.bufPrint(buf[n..], "m", .{})).len;
        return buf[0..n];
    }
};

test "default style sequence is reset" {
    var buf: [64]u8 = undefined;
    const s = try Style.default.sequence(&buf);
    try std.testing.expectEqualStrings("\x1b[0m", s);
}

test "bold only" {
    var buf: [64]u8 = undefined;
    const s = try (Style{ .bold = true }).sequence(&buf);
    try std.testing.expectEqualStrings("\x1b[0;1m", s);
}

test "bold and italic" {
    var buf: [64]u8 = undefined;
    const s = try (Style{ .bold = true, .italic = true }).sequence(&buf);
    try std.testing.expectEqualStrings("\x1b[0;1;3m", s);
}

test "fg basic red" {
    var buf: [64]u8 = undefined;
    const s = try (Style{ .fg = .{ .indexed = 1 } }).sequence(&buf);
    try std.testing.expectEqualStrings("\x1b[0;31m", s);
}

test "fg rgb red" {
    var buf: [64]u8 = undefined;
    const s = try (Style{ .fg = .{ .rgb = .{ .r = 255, .g = 0, .b = 0 } } }).sequence(&buf);
    try std.testing.expectEqualStrings("\x1b[0;38;2;255;0;0m", s);
}

test "bg basic blue" {
    var buf: [64]u8 = undefined;
    const s = try (Style{ .bg = .{ .indexed = 4 } }).sequence(&buf);
    try std.testing.expectEqualStrings("\x1b[0;44m", s);
}

test "all attributes combined" {
    var buf: [64]u8 = undefined;
    const s = try (Style{
        .fg = .{ .indexed = 200 },
        .bg = .{ .rgb = .{ .r = 0, .g = 128, .b = 255 } },
        .bold = true,
        .italic = true,
        .underline = true,
        .reverse = true,
    }).sequence(&buf);
    try std.testing.expectEqualStrings("\x1b[0;1;3;4;7;38;5;200;48;2;0;128;255m", s);
}

test "eql identifies equal styles" {
    const a: Style = .{ .fg = .{ .indexed = 5 }, .bold = true };
    const b: Style = .{ .fg = .{ .indexed = 5 }, .bold = true };
    try std.testing.expect(Style.eql(a, b));
}

test "eql distinguishes different styles" {
    const a: Style = .{ .bold = true };
    const b: Style = .{ .italic = true };
    try std.testing.expect(!Style.eql(a, b));
}

test "eql distinguishes different colors" {
    const a: Style = .{ .fg = .{ .indexed = 1 } };
    const b: Style = .{ .fg = .{ .indexed = 2 } };
    try std.testing.expect(!Style.eql(a, b));
}
