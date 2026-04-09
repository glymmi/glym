//! Styling primitives for glym.
//!
//! Currently re-exports the color module. The Style struct (bold, italic,
//! fg, bg, ...) lands in the next commit and will live alongside the color
//! types here.

const std = @import("std");

pub const color = @import("style/color.zig");
pub const Color = color.Color;
pub const Rgb = color.Rgb;

test {
    std.testing.refAllDecls(@This());
    _ = color;
}
