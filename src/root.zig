//! glym - tiny glimmers for your terminal.
//!
//! Public entry point. Downstream users import everything they need from here
//! via `const glym = @import("glym");`.

const std = @import("std");

/// ANSI escape sequence helpers (cursor movement, screen control).
pub const ansi = @import("term/ansi.zig");
/// Raw mode toggling for the controlling terminal.
pub const raw = @import("term/raw.zig");
/// Terminal size queries (rows and columns).
pub const size = @import("term/size.zig");
/// Terminal input parser (bytes to structured Key events).
pub const input = @import("term/input.zig");
/// Double-buffered screen renderer with diff-based flushing.
pub const renderer = @import("renderer.zig");
/// Styling primitives re-exported from shimmer.
pub const style = @import("style.zig");
/// Message types for the MVU runtime.
pub const msg = @import("msg.zig");
/// Command types for the MVU runtime.
pub const cmd = @import("cmd.zig");
/// MVU runtime module.
pub const program = @import("program.zig");
/// Generic MVU runtime, parameterized over Model and AppMsg.
pub const Program = program.Program;
/// Terminal color support level (truecolor, 256, basic, none).
pub const ColorLevel = @import("shimmer").ColorLevel;
/// Detect the terminal color support level for the current process.
pub const detectColorLevel = program.detectColorLevel;

/// Semantic version of the glym library.
pub const version = "0.0.1";

test "version is non-empty" {
    try std.testing.expect(version.len > 0);
}

test {
    std.testing.refAllDecls(@This());
}
