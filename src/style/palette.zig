//! Opinionated starter palette.
//!
//! A small Tailwind-inspired set of named RGB colors so apps can pick a
//! coherent look without hand-tuning hex values. Six scales (slate,
//! rose, sky, amber, emerald, violet) with three or five stops each.
//! Stops are roughly: 300 light, 500 mid, 700 dark; slate also has 50
//! and 900 for surfaces. These are constants — pick them at use sites,
//! do not mutate them.

const Rgb = @import("color.zig").Rgb;

// -- slate (neutrals) --
pub const slate_50: Rgb = .{ .r = 248, .g = 250, .b = 252 };
pub const slate_300: Rgb = .{ .r = 203, .g = 213, .b = 225 };
pub const slate_500: Rgb = .{ .r = 100, .g = 116, .b = 139 };
pub const slate_700: Rgb = .{ .r = 51, .g = 65, .b = 85 };
pub const slate_900: Rgb = .{ .r = 15, .g = 23, .b = 42 };

// -- rose --
pub const rose_300: Rgb = .{ .r = 253, .g = 164, .b = 175 };
pub const rose_500: Rgb = .{ .r = 244, .g = 63, .b = 94 };
pub const rose_700: Rgb = .{ .r = 190, .g = 18, .b = 60 };

// -- sky --
pub const sky_300: Rgb = .{ .r = 125, .g = 211, .b = 252 };
pub const sky_500: Rgb = .{ .r = 14, .g = 165, .b = 233 };
pub const sky_700: Rgb = .{ .r = 3, .g = 105, .b = 161 };

// -- amber --
pub const amber_300: Rgb = .{ .r = 252, .g = 211, .b = 77 };
pub const amber_500: Rgb = .{ .r = 245, .g = 158, .b = 11 };
pub const amber_700: Rgb = .{ .r = 180, .g = 83, .b = 9 };

// -- emerald --
pub const emerald_300: Rgb = .{ .r = 110, .g = 231, .b = 183 };
pub const emerald_500: Rgb = .{ .r = 16, .g = 185, .b = 129 };
pub const emerald_700: Rgb = .{ .r = 4, .g = 120, .b = 87 };

// -- violet --
pub const violet_300: Rgb = .{ .r = 196, .g = 181, .b = 253 };
pub const violet_500: Rgb = .{ .r = 139, .g = 92, .b = 246 };
pub const violet_700: Rgb = .{ .r = 109, .g = 40, .b = 217 };

const std = @import("std");

test "palette stops are distinct" {
    try std.testing.expect(!std.meta.eql(rose_300, rose_500));
    try std.testing.expect(!std.meta.eql(sky_500, slate_500));
}
