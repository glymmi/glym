//! Simple horizontal progress bar widget.
//!
//! Displays a filled/empty bar based on a 0.0-1.0 progress value. An
//! optional label is rendered to the left of the bar. `label`,
//! `fill_char` and `empty_char` are intentionally public so apps can
//! tweak them inline; use `setProgress` to keep the value clamped.

const std = @import("std");
const Renderer = @import("../renderer.zig").Renderer;
const Style = @import("shimmer").Style;

pub const ProgressBar = struct {
    progress: f32,
    label: []const u8,
    fill_char: u21,
    empty_char: u21,

    /// Create a progress bar. `progress` is clamped to 0.0-1.0.
    pub fn init(progress: f32) ProgressBar {
        return .{
            .progress = clamp(progress),
            .label = "",
            .fill_char = 0x2588, // full block
            .empty_char = 0x2591, // light shade
        };
    }

    /// Set the progress value (clamped to 0.0-1.0).
    pub fn setProgress(self: *ProgressBar, value: f32) void {
        self.progress = clamp(value);
    }

    /// Render the bar into a `width`-cell rectangle at (row, col).
    /// When a label is set, it is drawn first followed by a space, and the
    /// bar fills the remaining width.
    pub fn view(self: *const ProgressBar, r: *Renderer, row: u16, col: u16, width: u16, style: Style) void {
        if (width == 0) return;

        var bar_start: u16 = col;
        var bar_width: u16 = width;

        // Draw label if present.
        if (self.label.len > 0) {
            r.writeStyledText(row, col, self.label, style);
            const label_len = unicodeLen(self.label);
            const used = label_len + 1; // label + space
            if (used >= width) return;
            bar_start = col + @as(u16, @intCast(used));
            bar_width = width - @as(u16, @intCast(used));
        }

        const filled: u16 = @intFromFloat(@round(@as(f32, @floatFromInt(bar_width)) * self.progress));

        var p: u16 = 0;
        while (p < bar_width) : (p += 1) {
            const ch: u21 = if (p < filled) self.fill_char else self.empty_char;
            r.setCell(row, bar_start + p, .{ .char = ch, .style = style });
        }
    }

    fn clamp(v: f32) f32 {
        return @max(0.0, @min(1.0, v));
    }

    /// Count the number of unicode codepoints in a UTF-8 string.
    fn unicodeLen(s: []const u8) usize {
        var count: usize = 0;
        var i: usize = 0;
        while (i < s.len) {
            const len = std.unicode.utf8ByteSequenceLength(s[i]) catch return count;
            if (i + len > s.len) return count;
            i += len;
            count += 1;
        }
        return count;
    }
};

test "init clamps progress" {
    const bar = ProgressBar.init(1.5);
    try std.testing.expectEqual(@as(f32, 1.0), bar.progress);
    const bar2 = ProgressBar.init(-0.5);
    try std.testing.expectEqual(@as(f32, 0.0), bar2.progress);
}

test "setProgress clamps" {
    var bar = ProgressBar.init(0.0);
    bar.setProgress(0.75);
    try std.testing.expectEqual(@as(f32, 0.75), bar.progress);
    bar.setProgress(2.0);
    try std.testing.expectEqual(@as(f32, 1.0), bar.progress);
}

test "view fills correct number of cells" {
    const bar = ProgressBar.init(0.5);
    var r = try Renderer.init(std.testing.allocator, 1, 10);
    defer r.deinit();
    bar.view(&r, 0, 0, 10, .{});
    // 50% of 10 = 5 filled cells
    var filled: usize = 0;
    for (0..10) |i| {
        if (r.back[i].char == 0x2588) filled += 1;
    }
    try std.testing.expectEqual(@as(usize, 5), filled);
}

test "view at zero fills nothing" {
    const bar = ProgressBar.init(0.0);
    var r = try Renderer.init(std.testing.allocator, 1, 10);
    defer r.deinit();
    bar.view(&r, 0, 0, 10, .{});
    for (0..10) |i| {
        try std.testing.expectEqual(@as(u21, 0x2591), r.back[i].char);
    }
}

test "view at one fills everything" {
    const bar = ProgressBar.init(1.0);
    var r = try Renderer.init(std.testing.allocator, 1, 10);
    defer r.deinit();
    bar.view(&r, 0, 0, 10, .{});
    for (0..10) |i| {
        try std.testing.expectEqual(@as(u21, 0x2588), r.back[i].char);
    }
}

test "view with label leaves space for label" {
    var bar = ProgressBar.init(1.0);
    bar.label = "CPU";
    var r = try Renderer.init(std.testing.allocator, 1, 20);
    defer r.deinit();
    bar.view(&r, 0, 0, 14, .{});
    // "CPU" = 3 chars + 1 space = 4 used, 10 remaining for bar
    try std.testing.expectEqual(@as(u21, 'C'), r.back[0].char);
    try std.testing.expectEqual(@as(u21, 'P'), r.back[1].char);
    try std.testing.expectEqual(@as(u21, 'U'), r.back[2].char);
    // bar starts at col 4
    try std.testing.expectEqual(@as(u21, 0x2588), r.back[4].char);
}

test "view with zero width is a no-op" {
    const bar = ProgressBar.init(0.5);
    var r = try Renderer.init(std.testing.allocator, 1, 10);
    defer r.deinit();
    bar.view(&r, 0, 0, 0, .{});
    // back buffer should stay at default (space)
    try std.testing.expectEqual(@as(u21, ' '), r.back[0].char);
}

test "custom fill and empty chars" {
    var bar = ProgressBar.init(0.5);
    bar.fill_char = '#';
    bar.empty_char = '-';
    var r = try Renderer.init(std.testing.allocator, 1, 4);
    defer r.deinit();
    bar.view(&r, 0, 0, 4, .{});
    try std.testing.expectEqual(@as(u21, '#'), r.back[0].char);
    try std.testing.expectEqual(@as(u21, '#'), r.back[1].char);
    try std.testing.expectEqual(@as(u21, '-'), r.back[2].char);
    try std.testing.expectEqual(@as(u21, '-'), r.back[3].char);
}
