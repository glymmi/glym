//! Styling primitives for glym.
//!
//! Re-exports from `shimmer` so glym apps can write
//! `glym.style.Style{ .bold = true }` without depending on shimmer
//! directly. The Catppuccin Mocha `palette` is glym-specific and
//! lives in `style/palette.zig`.

const std = @import("std");
const shimmer = @import("shimmer");

pub const color = shimmer.color;
pub const palette = @import("style/palette.zig");

pub const Color = shimmer.Color;
pub const Rgb = shimmer.Rgb;
pub const ColorLevel = shimmer.ColorLevel;
pub const Style = shimmer.Style;
pub const Border = shimmer.Border;

test {
    std.testing.refAllDecls(@This());
}
