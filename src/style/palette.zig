//! Catppuccin Mocha palette.
//!
//! Hand-crafted by the Catppuccin team and used by most of the modern
//! TUI ecosystem (Neovim, Helix, Bat, Btop, Lazygit, Starship...). 14
//! accent hues plus a 6-stop neutral surface scale and a 4-stop text
//! ramp. Apps that want a fully custom look can ignore the palette and
//! build their own. License: MIT, see https://github.com/catppuccin.

const Rgb = @import("shimmer").Rgb;

// -- accents --
pub const rosewater: Rgb = .{ .r = 0xf5, .g = 0xe0, .b = 0xdc };
pub const flamingo: Rgb = .{ .r = 0xf2, .g = 0xcd, .b = 0xcd };
pub const pink: Rgb = .{ .r = 0xf5, .g = 0xc2, .b = 0xe7 };
pub const mauve: Rgb = .{ .r = 0xcb, .g = 0xa6, .b = 0xf7 };
pub const red: Rgb = .{ .r = 0xf3, .g = 0x8b, .b = 0xa8 };
pub const maroon: Rgb = .{ .r = 0xeb, .g = 0xa0, .b = 0xac };
pub const peach: Rgb = .{ .r = 0xfa, .g = 0xb3, .b = 0x87 };
pub const yellow: Rgb = .{ .r = 0xf9, .g = 0xe2, .b = 0xaf };
pub const green: Rgb = .{ .r = 0xa6, .g = 0xe3, .b = 0xa1 };
pub const teal: Rgb = .{ .r = 0x94, .g = 0xe2, .b = 0xd5 };
pub const sky: Rgb = .{ .r = 0x89, .g = 0xdc, .b = 0xeb };
pub const sapphire: Rgb = .{ .r = 0x74, .g = 0xc7, .b = 0xec };
pub const blue: Rgb = .{ .r = 0x89, .g = 0xb4, .b = 0xfa };
pub const lavender: Rgb = .{ .r = 0xb4, .g = 0xbe, .b = 0xfe };

// -- text ramp (lightest to darkest) --
pub const text: Rgb = .{ .r = 0xcd, .g = 0xd6, .b = 0xf4 };
pub const subtext1: Rgb = .{ .r = 0xba, .g = 0xc2, .b = 0xde };
pub const subtext0: Rgb = .{ .r = 0xa6, .g = 0xad, .b = 0xc8 };
pub const overlay2: Rgb = .{ .r = 0x93, .g = 0x99, .b = 0xb2 };
pub const overlay1: Rgb = .{ .r = 0x7f, .g = 0x84, .b = 0x9c };
pub const overlay0: Rgb = .{ .r = 0x6c, .g = 0x70, .b = 0x86 };

// -- surfaces (lightest to darkest) --
pub const surface2: Rgb = .{ .r = 0x58, .g = 0x5b, .b = 0x70 };
pub const surface1: Rgb = .{ .r = 0x45, .g = 0x47, .b = 0x5a };
pub const surface0: Rgb = .{ .r = 0x31, .g = 0x32, .b = 0x44 };
pub const base: Rgb = .{ .r = 0x1e, .g = 0x1e, .b = 0x2e };
pub const mantle: Rgb = .{ .r = 0x18, .g = 0x18, .b = 0x25 };
pub const crust: Rgb = .{ .r = 0x11, .g = 0x11, .b = 0x1b };

const std = @import("std");

test "palette stops are distinct" {
    try std.testing.expect(!std.meta.eql(mauve, lavender));
    try std.testing.expect(!std.meta.eql(blue, sapphire));
    try std.testing.expect(!std.meta.eql(base, mantle));
}

test "Catppuccin Mocha mauve matches the published hex" {
    try std.testing.expectEqual(@as(u8, 0xcb), mauve.r);
    try std.testing.expectEqual(@as(u8, 0xa6), mauve.g);
    try std.testing.expectEqual(@as(u8, 0xf7), mauve.b);
}
