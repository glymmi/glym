//! Multi-line text area widget.
//!
//! Stores content as a list of lines, each a buffer of unicode codepoints.
//! Supports vertical cursor movement, enter to split lines, and vertical
//! scroll to keep the cursor visible within a fixed-height viewport.

const std = @import("std");
const input = @import("../term/input.zig");
const Renderer = @import("../renderer.zig").Renderer;
const Style = @import("../style/style.zig").Style;

pub const TextArea = struct {
    allocator: std.mem.Allocator,
    lines: std.ArrayList(std.ArrayList(u21)),
    row: usize,
    col: usize,
    scroll: usize,

    pub fn init(allocator: std.mem.Allocator) !TextArea {
        var lines: std.ArrayList(std.ArrayList(u21)) = .{};
        try lines.append(allocator, .{});
        return .{
            .allocator = allocator,
            .lines = lines,
            .row = 0,
            .col = 0,
            .scroll = 0,
        };
    }

    pub fn deinit(self: *TextArea) void {
        for (self.lines.items) |*line| {
            line.deinit(self.allocator);
        }
        self.lines.deinit(self.allocator);
    }

    /// Replace the entire content with a UTF-8 string. Newlines split into
    /// separate lines. Cursor moves to the end.
    pub fn setValue(self: *TextArea, text: []const u8) !void {
        for (self.lines.items) |*line| {
            line.deinit(self.allocator);
        }
        self.lines.clearRetainingCapacity();
        try self.lines.append(self.allocator, .{});
        var i: usize = 0;
        while (i < text.len) {
            if (text[i] == '\n') {
                try self.lines.append(self.allocator, .{});
                i += 1;
                continue;
            }
            const len = std.unicode.utf8ByteSequenceLength(text[i]) catch return error.InvalidUtf8;
            if (i + len > text.len) return error.InvalidUtf8;
            const cp = std.unicode.utf8Decode(text[i .. i + len]) catch return error.InvalidUtf8;
            const last = &self.lines.items[self.lines.items.len - 1];
            try last.append(self.allocator, cp);
            i += len;
        }
        self.row = self.lines.items.len - 1;
        self.col = self.lines.items[self.row].items.len;
    }

    /// Return the content as a freshly allocated UTF-8 string with newlines
    /// between lines. Caller owns the slice.
    pub fn valueAlloc(self: *const TextArea, allocator: std.mem.Allocator) ![]u8 {
        var out: std.ArrayList(u8) = .{};
        errdefer out.deinit(allocator);
        var enc: [4]u8 = undefined;
        for (self.lines.items, 0..) |line, li| {
            if (li > 0) try out.append(allocator, '\n');
            for (line.items) |cp| {
                const n = try std.unicode.utf8Encode(cp, &enc);
                try out.appendSlice(allocator, enc[0..n]);
            }
        }
        return out.toOwnedSlice(allocator);
    }

    /// Number of lines in the buffer.
    pub fn lineCount(self: *const TextArea) usize {
        return self.lines.items.len;
    }

    /// Apply a key event. Returns true if consumed.
    pub fn handleKey(self: *TextArea, key: input.Key) !bool {
        switch (key.code) {
            .char => |cp| {
                if (key.modifiers.ctrl or key.modifiers.alt) return false;
                const line = &self.lines.items[self.row];
                try line.insert(self.allocator, self.col, cp);
                self.col += 1;
                return true;
            },
            .enter => {
                const line = &self.lines.items[self.row];
                var new_line: std.ArrayList(u21) = .{};
                // Move chars after cursor to the new line
                if (self.col < line.items.len) {
                    try new_line.appendSlice(self.allocator, line.items[self.col..]);
                    line.shrinkRetainingCapacity(self.col);
                }
                try self.lines.insert(self.allocator, self.row + 1, new_line);
                self.row += 1;
                self.col = 0;
                return true;
            },
            .backspace => {
                if (self.col > 0) {
                    const line = &self.lines.items[self.row];
                    _ = line.orderedRemove(self.col - 1);
                    self.col -= 1;
                } else if (self.row > 0) {
                    // Merge current line into previous
                    const prev_len = self.lines.items[self.row - 1].items.len;
                    const current = self.lines.orderedRemove(self.row);
                    if (current.items.len > 0) {
                        try self.lines.items[self.row - 1].appendSlice(self.allocator, current.items);
                    }
                    var removed = current;
                    removed.deinit(self.allocator);
                    self.row -= 1;
                    self.col = prev_len;
                }
                return true;
            },
            .delete => {
                const line = &self.lines.items[self.row];
                if (self.col < line.items.len) {
                    _ = line.orderedRemove(self.col);
                } else if (self.row + 1 < self.lines.items.len) {
                    // Merge next line into current
                    const next = self.lines.orderedRemove(self.row + 1);
                    if (next.items.len > 0) {
                        try self.lines.items[self.row].appendSlice(self.allocator, next.items);
                    }
                    var removed = next;
                    removed.deinit(self.allocator);
                }
                return true;
            },
            .arrow_left => {
                if (self.col > 0) {
                    self.col -= 1;
                } else if (self.row > 0) {
                    self.row -= 1;
                    self.col = self.lines.items[self.row].items.len;
                }
                return true;
            },
            .arrow_right => {
                const line_len = self.lines.items[self.row].items.len;
                if (self.col < line_len) {
                    self.col += 1;
                } else if (self.row + 1 < self.lines.items.len) {
                    self.row += 1;
                    self.col = 0;
                }
                return true;
            },
            .arrow_up => {
                if (self.row > 0) {
                    self.row -= 1;
                    self.col = @min(self.col, self.lines.items[self.row].items.len);
                }
                return true;
            },
            .arrow_down => {
                if (self.row + 1 < self.lines.items.len) {
                    self.row += 1;
                    self.col = @min(self.col, self.lines.items[self.row].items.len);
                }
                return true;
            },
            .home => {
                self.col = 0;
                return true;
            },
            .end => {
                self.col = self.lines.items[self.row].items.len;
                return true;
            },
            else => return false,
        }
    }

    /// Compute scroll offset to keep `target_row` visible within `height`.
    pub fn clampedScroll(target_row: usize, line_count: usize, height: usize, current: usize) usize {
        if (height == 0 or line_count == 0) return 0;
        var off = current;
        if (target_row < off) {
            off = target_row;
        } else if (target_row >= off + height) {
            off = target_row - height + 1;
        }
        const max = if (line_count > height) line_count - height else 0;
        if (off > max) off = max;
        return off;
    }

    /// Render the text area into a rectangle of `height` rows and `width`
    /// columns starting at (row, col). The cursor cell is drawn with the
    /// reverse attribute. Lines are truncated at width.
    pub fn view(self: *TextArea, r: *Renderer, row: u16, col: u16, height: u16, width: u16, style: Style) void {
        if (height == 0 or width == 0) return;
        self.scroll = clampedScroll(self.row, self.lines.items.len, height, self.scroll);
        var line: u16 = 0;
        while (line < height) : (line += 1) {
            const li = self.scroll + line;
            var p: u16 = 0;
            if (li < self.lines.items.len) {
                const data = self.lines.items[li].items;
                while (p < width) : (p += 1) {
                    var s = style;
                    var ch: u21 = ' ';
                    if (p < data.len) ch = data[p];
                    if (li == self.row and p == self.col) s.reverse = true;
                    r.setCell(row + line, col + p, .{ .char = ch, .style = s });
                }
            } else {
                while (p < width) : (p += 1) {
                    r.setCell(row + line, col + p, .{ .char = ' ', .style = style });
                }
            }
        }
    }
};

// -- tests: init and deinit --

test "init starts with one empty line" {
    var ta = try TextArea.init(std.testing.allocator);
    defer ta.deinit();
    try std.testing.expectEqual(@as(usize, 1), ta.lineCount());
    try std.testing.expectEqual(@as(usize, 0), ta.row);
    try std.testing.expectEqual(@as(usize, 0), ta.col);
}

// -- tests: setValue / valueAlloc --

test "setValue splits on newlines" {
    var ta = try TextArea.init(std.testing.allocator);
    defer ta.deinit();
    try ta.setValue("abc\ndef\nghi");
    try std.testing.expectEqual(@as(usize, 3), ta.lineCount());
    try std.testing.expectEqual(@as(usize, 3), ta.lines.items[0].items.len);
    try std.testing.expectEqual(@as(u21, 'd'), ta.lines.items[1].items[0]);
    try std.testing.expectEqual(@as(usize, 2), ta.row);
    try std.testing.expectEqual(@as(usize, 3), ta.col);
}

test "setValue handles trailing newline" {
    var ta = try TextArea.init(std.testing.allocator);
    defer ta.deinit();
    try ta.setValue("a\n");
    try std.testing.expectEqual(@as(usize, 2), ta.lineCount());
    try std.testing.expectEqual(@as(usize, 0), ta.lines.items[1].items.len);
}

test "valueAlloc roundtrips content" {
    var ta = try TextArea.init(std.testing.allocator);
    defer ta.deinit();
    try ta.setValue("hello\nworld");
    const out = try ta.valueAlloc(std.testing.allocator);
    defer std.testing.allocator.free(out);
    try std.testing.expectEqualStrings("hello\nworld", out);
}

test "setValue handles utf8" {
    var ta = try TextArea.init(std.testing.allocator);
    defer ta.deinit();
    try ta.setValue("cafe\u{0301}");
    try std.testing.expectEqual(@as(usize, 5), ta.lines.items[0].items.len);
}

// -- tests: character insertion --

test "insert character advances col" {
    var ta = try TextArea.init(std.testing.allocator);
    defer ta.deinit();
    _ = try ta.handleKey(.{ .code = .{ .char = 'a' } });
    _ = try ta.handleKey(.{ .code = .{ .char = 'b' } });
    try std.testing.expectEqual(@as(usize, 2), ta.lines.items[0].items.len);
    try std.testing.expectEqual(@as(usize, 2), ta.col);
}

test "ctrl char is not consumed" {
    var ta = try TextArea.init(std.testing.allocator);
    defer ta.deinit();
    const consumed = try ta.handleKey(.{
        .code = .{ .char = 'c' },
        .modifiers = .{ .ctrl = true },
    });
    try std.testing.expect(!consumed);
}

// -- tests: enter splits lines --

test "enter splits line at cursor" {
    var ta = try TextArea.init(std.testing.allocator);
    defer ta.deinit();
    try ta.setValue("abcd");
    ta.col = 2;
    ta.row = 0;
    _ = try ta.handleKey(.{ .code = .enter });
    try std.testing.expectEqual(@as(usize, 2), ta.lineCount());
    try std.testing.expectEqual(@as(u21, 'a'), ta.lines.items[0].items[0]);
    try std.testing.expectEqual(@as(u21, 'b'), ta.lines.items[0].items[1]);
    try std.testing.expectEqual(@as(u21, 'c'), ta.lines.items[1].items[0]);
    try std.testing.expectEqual(@as(usize, 1), ta.row);
    try std.testing.expectEqual(@as(usize, 0), ta.col);
}

// -- tests: backspace --

test "backspace within line removes char" {
    var ta = try TextArea.init(std.testing.allocator);
    defer ta.deinit();
    try ta.setValue("abc");
    _ = try ta.handleKey(.{ .code = .backspace });
    try std.testing.expectEqual(@as(usize, 2), ta.lines.items[0].items.len);
    try std.testing.expectEqual(@as(usize, 2), ta.col);
}

test "backspace at line start merges with previous" {
    var ta = try TextArea.init(std.testing.allocator);
    defer ta.deinit();
    try ta.setValue("ab\ncd");
    ta.row = 1;
    ta.col = 0;
    _ = try ta.handleKey(.{ .code = .backspace });
    try std.testing.expectEqual(@as(usize, 1), ta.lineCount());
    try std.testing.expectEqual(@as(usize, 4), ta.lines.items[0].items.len);
    try std.testing.expectEqual(@as(usize, 0), ta.row);
    try std.testing.expectEqual(@as(usize, 2), ta.col);
}

test "backspace at start of first line is a no-op" {
    var ta = try TextArea.init(std.testing.allocator);
    defer ta.deinit();
    try ta.setValue("abc");
    ta.col = 0;
    _ = try ta.handleKey(.{ .code = .backspace });
    try std.testing.expectEqual(@as(usize, 3), ta.lines.items[0].items.len);
}

// -- tests: delete --

test "delete within line removes char under cursor" {
    var ta = try TextArea.init(std.testing.allocator);
    defer ta.deinit();
    try ta.setValue("abc");
    ta.col = 1;
    _ = try ta.handleKey(.{ .code = .delete });
    try std.testing.expectEqual(@as(usize, 2), ta.lines.items[0].items.len);
    try std.testing.expectEqual(@as(u21, 'c'), ta.lines.items[0].items[1]);
}

test "delete at end of line merges with next" {
    var ta = try TextArea.init(std.testing.allocator);
    defer ta.deinit();
    try ta.setValue("ab\ncd");
    ta.row = 0;
    ta.col = 2;
    _ = try ta.handleKey(.{ .code = .delete });
    try std.testing.expectEqual(@as(usize, 1), ta.lineCount());
    try std.testing.expectEqual(@as(usize, 4), ta.lines.items[0].items.len);
}

// -- tests: arrow keys --

test "arrow up and down move between lines" {
    var ta = try TextArea.init(std.testing.allocator);
    defer ta.deinit();
    try ta.setValue("abc\ndef");
    ta.row = 0;
    ta.col = 2;
    _ = try ta.handleKey(.{ .code = .arrow_down });
    try std.testing.expectEqual(@as(usize, 1), ta.row);
    try std.testing.expectEqual(@as(usize, 2), ta.col);
    _ = try ta.handleKey(.{ .code = .arrow_up });
    try std.testing.expectEqual(@as(usize, 0), ta.row);
}

test "arrow down clamps col to shorter line" {
    var ta = try TextArea.init(std.testing.allocator);
    defer ta.deinit();
    try ta.setValue("abcdef\nxy");
    ta.row = 0;
    ta.col = 5;
    _ = try ta.handleKey(.{ .code = .arrow_down });
    try std.testing.expectEqual(@as(usize, 1), ta.row);
    try std.testing.expectEqual(@as(usize, 2), ta.col);
}

test "arrow left wraps to previous line" {
    var ta = try TextArea.init(std.testing.allocator);
    defer ta.deinit();
    try ta.setValue("ab\ncd");
    ta.row = 1;
    ta.col = 0;
    _ = try ta.handleKey(.{ .code = .arrow_left });
    try std.testing.expectEqual(@as(usize, 0), ta.row);
    try std.testing.expectEqual(@as(usize, 2), ta.col);
}

test "arrow right wraps to next line" {
    var ta = try TextArea.init(std.testing.allocator);
    defer ta.deinit();
    try ta.setValue("ab\ncd");
    ta.row = 0;
    ta.col = 2;
    _ = try ta.handleKey(.{ .code = .arrow_right });
    try std.testing.expectEqual(@as(usize, 1), ta.row);
    try std.testing.expectEqual(@as(usize, 0), ta.col);
}

test "home and end on current line" {
    var ta = try TextArea.init(std.testing.allocator);
    defer ta.deinit();
    try ta.setValue("abcdef");
    ta.col = 3;
    _ = try ta.handleKey(.{ .code = .home });
    try std.testing.expectEqual(@as(usize, 0), ta.col);
    _ = try ta.handleKey(.{ .code = .end });
    try std.testing.expectEqual(@as(usize, 6), ta.col);
}

test "unhandled key returns false" {
    var ta = try TextArea.init(std.testing.allocator);
    defer ta.deinit();
    try std.testing.expect(!try ta.handleKey(.{ .code = .{ .f = 5 } }));
}

// -- tests: scroll math --

test "clampedScroll keeps target visible scrolling down" {
    try std.testing.expectEqual(@as(usize, 3), TextArea.clampedScroll(5, 10, 3, 0));
}

test "clampedScroll keeps target visible scrolling up" {
    try std.testing.expectEqual(@as(usize, 2), TextArea.clampedScroll(2, 10, 3, 5));
}

test "clampedScroll preserves offset when target is visible" {
    try std.testing.expectEqual(@as(usize, 2), TextArea.clampedScroll(3, 10, 5, 2));
}

test "clampedScroll returns 0 for zero height" {
    try std.testing.expectEqual(@as(usize, 0), TextArea.clampedScroll(5, 10, 0, 3));
}

// -- tests: view rendering --

test "view writes lines into renderer" {
    var ta = try TextArea.init(std.testing.allocator);
    defer ta.deinit();
    try ta.setValue("ab\ncd");
    ta.row = 0;
    ta.col = 0;
    var r = try Renderer.init(std.testing.allocator, 5, 10);
    defer r.deinit();
    ta.view(&r, 0, 0, 3, 10, .{});
    try std.testing.expectEqual(@as(u21, 'a'), r.back[0].char);
    try std.testing.expectEqual(@as(u21, 'b'), r.back[1].char);
    try std.testing.expectEqual(@as(u21, 'c'), r.back[10].char);
    try std.testing.expectEqual(@as(u21, 'd'), r.back[11].char);
}

test "view marks cursor cell with reverse" {
    var ta = try TextArea.init(std.testing.allocator);
    defer ta.deinit();
    try ta.setValue("ab\ncd");
    ta.row = 1;
    ta.col = 1;
    var r = try Renderer.init(std.testing.allocator, 5, 10);
    defer r.deinit();
    ta.view(&r, 0, 0, 3, 10, .{});
    try std.testing.expect(r.back[11].style.reverse);
    try std.testing.expect(!r.back[0].style.reverse);
}

test "view scrolls to keep cursor visible" {
    var ta = try TextArea.init(std.testing.allocator);
    defer ta.deinit();
    try ta.setValue("a\nb\nc\nd\ne");
    ta.row = 4;
    ta.col = 0;
    var r = try Renderer.init(std.testing.allocator, 3, 5);
    defer r.deinit();
    ta.view(&r, 0, 0, 3, 5, .{});
    try std.testing.expectEqual(@as(usize, 2), ta.scroll);
    try std.testing.expectEqual(@as(u21, 'c'), r.back[0].char);
    try std.testing.expectEqual(@as(u21, 'e'), r.back[10].char);
}

test "view fills empty rows below content" {
    var ta = try TextArea.init(std.testing.allocator);
    defer ta.deinit();
    try ta.setValue("a");
    ta.row = 0;
    ta.col = 0;
    var r = try Renderer.init(std.testing.allocator, 3, 5);
    defer r.deinit();
    ta.view(&r, 0, 0, 3, 5, .{});
    try std.testing.expectEqual(@as(u21, 'a'), r.back[0].char);
    try std.testing.expectEqual(@as(u21, ' '), r.back[5].char);
}

test "view with zero height is a no-op" {
    var ta = try TextArea.init(std.testing.allocator);
    defer ta.deinit();
    var r = try Renderer.init(std.testing.allocator, 1, 5);
    defer r.deinit();
    ta.view(&r, 0, 0, 0, 5, .{});
    try std.testing.expectEqual(@as(u21, ' '), r.back[0].char);
}
