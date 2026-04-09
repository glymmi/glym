//! Built-in widgets for glym.
//!
//! Each widget is a small struct with `init`, `deinit`, `handleKey` and
//! `view` methods. Widgets are designed to be embedded in a host MVU app:
//! the app forwards key events and decides where to render the widget.

const std = @import("std");

pub const text_input = @import("widget/text_input.zig");
pub const TextInput = text_input.TextInput;

test {
    std.testing.refAllDecls(@This());
    _ = text_input;
}
