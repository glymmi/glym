//! Styling primitives for glym.
//!
//! Re-exports from `shimmer` so glym apps can write
//! `glym.style.Style{ .bold = true }` without depending on shimmer
//! directly. The Catppuccin Mocha `palette` is glym-specific and
//! lives in `style/palette.zig`.

const std = @import("std");
const shimmer = @import("shimmer");

/// Color helpers (lerp, conversion).
pub const color = shimmer.color;
/// Catppuccin Mocha palette constants.
pub const palette = @import("style/palette.zig");

/// Foreground or background color (default, indexed, rgb).
pub const Color = shimmer.Color;
/// 24-bit RGB triplet.
pub const Rgb = shimmer.Rgb;
/// Terminal color support level (truecolor, 256, basic, none).
pub const ColorLevel = shimmer.ColorLevel;
/// Visual attributes for a cell (fg, bg, bold, italic, ...).
pub const Style = shimmer.Style;
/// Box-drawing glyphs for border rendering.
pub const Border = shimmer.Border;

test {
    std.testing.refAllDecls(@This());
}
