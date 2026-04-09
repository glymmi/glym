//! Styling primitives for glym.
//!
//! Re-exports the color types, the `Style` struct, and an opinionated
//! starter `palette` of named RGB constants. Apps that want a fully
//! custom look can ignore the palette and build their own.

const std = @import("std");

pub const color = @import("style/color.zig");
const style_mod = @import("style/style.zig");
pub const palette = @import("style/palette.zig");
const border_mod = @import("style/border.zig");

pub const Color = color.Color;
pub const Rgb = color.Rgb;
pub const Style = style_mod.Style;
pub const Border = border_mod.Border;

test {
    std.testing.refAllDecls(@This());
    _ = color;
    _ = style_mod;
    _ = palette;
    _ = border_mod;
}
