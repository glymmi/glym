//! Border presets.
//!
//! A `Border` is just the eight box-drawing codepoints used by the
//! renderer's drawBorder helper. Five common presets ship out of the
//! box; apps can mix and match by writing a custom struct literal.

const std = @import("std");

pub const Border = struct {
    top_left: u21,
    top: u21,
    top_right: u21,
    left: u21,
    right: u21,
    bottom_left: u21,
    bottom: u21,
    bottom_right: u21,

    /// Sharp single-line corners. The default.
    pub const sharp: Border = .{
        .top_left = 0x250C,
        .top = 0x2500,
        .top_right = 0x2510,
        .left = 0x2502,
        .right = 0x2502,
        .bottom_left = 0x2514,
        .bottom = 0x2500,
        .bottom_right = 0x2518,
    };

    /// Rounded single-line corners.
    pub const rounded: Border = .{
        .top_left = 0x256D,
        .top = 0x2500,
        .top_right = 0x256E,
        .left = 0x2502,
        .right = 0x2502,
        .bottom_left = 0x2570,
        .bottom = 0x2500,
        .bottom_right = 0x256F,
    };

    /// Double line.
    pub const double: Border = .{
        .top_left = 0x2554,
        .top = 0x2550,
        .top_right = 0x2557,
        .left = 0x2551,
        .right = 0x2551,
        .bottom_left = 0x255A,
        .bottom = 0x2550,
        .bottom_right = 0x255D,
    };

    /// Thick single line.
    pub const thick: Border = .{
        .top_left = 0x250F,
        .top = 0x2501,
        .top_right = 0x2513,
        .left = 0x2503,
        .right = 0x2503,
        .bottom_left = 0x2517,
        .bottom = 0x2501,
        .bottom_right = 0x251B,
    };

    /// Plain ASCII fallback for terminals that cannot render box drawing.
    pub const ascii: Border = .{
        .top_left = '+',
        .top = '-',
        .top_right = '+',
        .left = '|',
        .right = '|',
        .bottom_left = '+',
        .bottom = '-',
        .bottom_right = '+',
    };

    /// Half-block / quadrant border that aligns to the cell edges
    /// instead of sitting at the cell center. Pair this with `drawBox`
    /// (which fills the whole rect including the border row and column)
    /// to get a perfectly flush "Lipgloss-style" panel where the border
    /// stroke meets the interior fill with no visible gap on either
    /// side.
    pub const block: Border = .{
        .top_left = 0x259B, // ▛
        .top = 0x2580, // ▀
        .top_right = 0x259C, // ▜
        .left = 0x258C, // ▌
        .right = 0x2590, // ▐
        .bottom_left = 0x2599, // ▙
        .bottom = 0x2584, // ▄
        .bottom_right = 0x259F, // ▟
    };
};

test "sharp and rounded differ on corners only" {
    try std.testing.expect(Border.sharp.top != Border.rounded.top or Border.sharp.top_left != Border.rounded.top_left);
    try std.testing.expectEqual(Border.sharp.top, Border.rounded.top);
    try std.testing.expect(Border.sharp.top_left != Border.rounded.top_left);
}

test "ascii preset uses pure ascii" {
    try std.testing.expectEqual(@as(u21, '+'), Border.ascii.top_left);
    try std.testing.expectEqual(@as(u21, '-'), Border.ascii.top);
    try std.testing.expectEqual(@as(u21, '|'), Border.ascii.left);
}
