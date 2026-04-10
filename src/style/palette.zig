//! Catppuccin Mocha palette.
//!
//! Hand-crafted by the Catppuccin team and used by most of the modern
//! TUI ecosystem (Neovim, Helix, Bat, Btop, Lazygit, Starship...). 14
//! accent hues plus a 6-stop neutral surface scale and a 4-stop text
//! ramp. Apps that want a fully custom look can ignore the palette and
//! build their own. License: MIT, see https://github.com/catppuccin.

const Rgb = @import("shimmer").Rgb;

// -- accents --

/// Warm pinkish white accent.
pub const rosewater: Rgb = .{ .r = 0xf5, .g = 0xe0, .b = 0xdc };
/// Soft pink accent.
pub const flamingo: Rgb = .{ .r = 0xf2, .g = 0xcd, .b = 0xcd };
/// Vivid pink accent.
pub const pink: Rgb = .{ .r = 0xf5, .g = 0xc2, .b = 0xe7 };
/// Purple accent.
pub const mauve: Rgb = .{ .r = 0xcb, .g = 0xa6, .b = 0xf7 };
/// Red accent.
pub const red: Rgb = .{ .r = 0xf3, .g = 0x8b, .b = 0xa8 };
/// Muted red accent.
pub const maroon: Rgb = .{ .r = 0xeb, .g = 0xa0, .b = 0xac };
/// Orange accent.
pub const peach: Rgb = .{ .r = 0xfa, .g = 0xb3, .b = 0x87 };
/// Yellow accent.
pub const yellow: Rgb = .{ .r = 0xf9, .g = 0xe2, .b = 0xaf };
/// Green accent.
pub const green: Rgb = .{ .r = 0xa6, .g = 0xe3, .b = 0xa1 };
/// Teal accent.
pub const teal: Rgb = .{ .r = 0x94, .g = 0xe2, .b = 0xd5 };
/// Light blue accent.
pub const sky: Rgb = .{ .r = 0x89, .g = 0xdc, .b = 0xeb };
/// Deep blue accent.
pub const sapphire: Rgb = .{ .r = 0x74, .g = 0xc7, .b = 0xec };
/// Blue accent.
pub const blue: Rgb = .{ .r = 0x89, .g = 0xb4, .b = 0xfa };
/// Periwinkle accent.
pub const lavender: Rgb = .{ .r = 0xb4, .g = 0xbe, .b = 0xfe };

// -- text ramp (lightest to darkest) --

/// Primary text color (lightest).
pub const text: Rgb = .{ .r = 0xcd, .g = 0xd6, .b = 0xf4 };
/// Secondary text, slightly dimmer.
pub const subtext1: Rgb = .{ .r = 0xba, .g = 0xc2, .b = 0xde };
/// Tertiary text, dimmer still.
pub const subtext0: Rgb = .{ .r = 0xa6, .g = 0xad, .b = 0xc8 };
/// Overlay text, high contrast over surfaces.
pub const overlay2: Rgb = .{ .r = 0x93, .g = 0x99, .b = 0xb2 };
/// Overlay text, medium contrast.
pub const overlay1: Rgb = .{ .r = 0x7f, .g = 0x84, .b = 0x9c };
/// Overlay text, low contrast.
pub const overlay0: Rgb = .{ .r = 0x6c, .g = 0x70, .b = 0x86 };

// -- surfaces (lightest to darkest) --

/// Lightest surface, e.g. active element backgrounds.
pub const surface2: Rgb = .{ .r = 0x58, .g = 0x5b, .b = 0x70 };
/// Mid surface, e.g. hover backgrounds.
pub const surface1: Rgb = .{ .r = 0x45, .g = 0x47, .b = 0x5a };
/// Dark surface, e.g. panel backgrounds.
pub const surface0: Rgb = .{ .r = 0x31, .g = 0x32, .b = 0x44 };
/// Base background.
pub const base: Rgb = .{ .r = 0x1e, .g = 0x1e, .b = 0x2e };
/// Slightly darker than base, e.g. sidebars.
pub const mantle: Rgb = .{ .r = 0x18, .g = 0x18, .b = 0x25 };
/// Darkest background.
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
