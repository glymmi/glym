//! glym - tiny glimmers for your terminal.
//!
//! Public entry point. Downstream users import everything they need from here
//! via `const glym = @import("glym");`.

const std = @import("std");

pub const ansi = @import("term/ansi.zig");
pub const raw = @import("term/raw.zig");
pub const size = @import("term/size.zig");
pub const input = @import("term/input.zig");
pub const renderer = @import("renderer.zig");

pub const version = "0.0.1";

test "version is non-empty" {
    try std.testing.expect(version.len > 0);
}

test {
    std.testing.refAllDecls(@This());
}
