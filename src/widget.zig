//! Built-in widgets for glym.
//!
//! Each widget is a small struct with `init`, `deinit`, `handleKey` and
//! `view` methods. Widgets are designed to be embedded in a host MVU app:
//! the app forwards key events and decides where to render the widget.

const std = @import("std");

pub const text_input = @import("widget/text_input.zig");
pub const TextInput = text_input.TextInput;

pub const list = @import("widget/list.zig");
pub const List = list.List;

pub const text_area = @import("widget/text_area.zig");
pub const TextArea = text_area.TextArea;

pub const progress_bar = @import("widget/progress_bar.zig");
pub const ProgressBar = progress_bar.ProgressBar;

test {
    std.testing.refAllDecls(@This());
    _ = text_input;
    _ = list;
    _ = text_area;
    _ = progress_bar;
}
