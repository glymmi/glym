//! ANSI escape sequence helpers.
//!
//! Only the small subset we need to bootstrap the renderer. New sequences
//! (SGR colors, scroll regions, etc.) get added here as the renderer grows.

const std = @import("std");

/// The ASCII escape byte (`\x1b`).
pub const ESC = "\x1b";
/// Control Sequence Introducer (`ESC [``).
pub const CSI = ESC ++ "[";

/// Clear the entire screen and move the cursor to 1,1.
pub const clear_screen = CSI ++ "2J" ++ CSI ++ "H";

/// Hide the text cursor.
pub const hide_cursor = CSI ++ "?25l";
/// Show the text cursor.
pub const show_cursor = CSI ++ "?25h";

/// Enter the alternate screen buffer.
pub const enter_alt_screen = CSI ++ "?1049h";
/// Leave the alternate screen buffer and restore the main one.
pub const leave_alt_screen = CSI ++ "?1049l";

/// Reset all SGR attributes to their defaults.
pub const reset = CSI ++ "0m";

/// Move the cursor to (row, col), 1-indexed. Caller owns the returned slice.
pub fn moveCursor(allocator: std.mem.Allocator, row: u16, col: u16) ![]u8 {
    return std.fmt.allocPrint(allocator, CSI ++ "{d};{d}H", .{ row, col });
}

test "constants are non-empty" {
    try std.testing.expect(clear_screen.len > 0);
    try std.testing.expect(hide_cursor.len > 0);
    try std.testing.expect(enter_alt_screen.len > 0);
    try std.testing.expect(reset.len > 0);
}

test "moveCursor formats correctly" {
    const allocator = std.testing.allocator;
    const seq = try moveCursor(allocator, 3, 7);
    defer allocator.free(seq);
    try std.testing.expectEqualStrings("\x1b[3;7H", seq);
}
