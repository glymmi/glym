//! Styling primitives for glym.
//!
//! Currently re-exports the color module. The Style struct (bold, italic,
//! fg, bg, ...) lands in the next commit and will live alongside the color
//! types here.

const std = @import("std");

pub const color = @import("style/color.zig");
const style_mod = @import("style/style.zig");

pub const Color = color.Color;
pub const Rgb = color.Rgb;
pub const Style = style_mod.Style;

test {
    std.testing.refAllDecls(@This());
    _ = color;
    _ = style_mod;
}
