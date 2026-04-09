//! Single-line text input widget.
//!
//! Stores its value as a buffer of unicode codepoints so editing operations
//! stay simple and never deal with UTF-8 byte arithmetic. Apps drive it by
//! forwarding key events to `handleKey` and asking the widget to render
//! itself into a renderer rectangle via `view`. Horizontal scrolling keeps
//! the cursor visible when the value is longer than the rendered width.

const std = @import("std");
const input = @import("../term/input.zig");
const Renderer = @import("../renderer.zig").Renderer;
const Style = @import("../style/style.zig").Style;

pub const TextInput = struct {
    allocator: std.mem.Allocator,
    value: std.ArrayList(u21),
    cursor: usize,

    pub fn init(allocator: std.mem.Allocator) TextInput {
        return .{
            .allocator = allocator,
            .value = .{},
            .cursor = 0,
        };
    }

    pub fn deinit(self: *TextInput) void {
        self.value.deinit(self.allocator);
    }

    /// Replace the value with the given UTF-8 string and place the cursor at
    /// the end. Returns InvalidUtf8 if the input is not valid UTF-8.
    pub fn setValue(self: *TextInput, text: []const u8) !void {
        self.value.clearRetainingCapacity();
        var i: usize = 0;
        while (i < text.len) {
            const len = std.unicode.utf8ByteSequenceLength(text[i]) catch return error.InvalidUtf8;
            if (i + len > text.len) return error.InvalidUtf8;
            const cp = std.unicode.utf8Decode(text[i .. i + len]) catch return error.InvalidUtf8;
            try self.value.append(self.allocator, cp);
            i += len;
        }
        self.cursor = self.value.items.len;
    }

    /// Return the current value as a freshly allocated UTF-8 string. Caller
    /// owns the slice.
    pub fn valueAlloc(self: *const TextInput, allocator: std.mem.Allocator) ![]u8 {
        var out: std.ArrayList(u8) = .{};
        errdefer out.deinit(allocator);
        var enc: [4]u8 = undefined;
        for (self.value.items) |cp| {
            const n = try std.unicode.utf8Encode(cp, &enc);
            try out.appendSlice(allocator, enc[0..n]);
        }
        return out.toOwnedSlice(allocator);
    }

    /// Apply a key event to the widget. Returns true if the key was
    /// consumed by the input, false if the host app should handle it.
    pub fn handleKey(self: *TextInput, key: input.Key) !bool {
        switch (key.code) {
            .char => |cp| {
                if (key.modifiers.ctrl or key.modifiers.alt) return false;
                try self.value.insert(self.allocator, self.cursor, cp);
                self.cursor += 1;
                return true;
            },
            .backspace => {
                if (self.cursor > 0) {
                    _ = self.value.orderedRemove(self.cursor - 1);
                    self.cursor -= 1;
                }
                return true;
            },
            .delete => {
                if (self.cursor < self.value.items.len) {
                    _ = self.value.orderedRemove(self.cursor);
                }
                return true;
            },
            .arrow_left => {
                if (self.cursor > 0) self.cursor -= 1;
                return true;
            },
            .arrow_right => {
                if (self.cursor < self.value.items.len) self.cursor += 1;
                return true;
            },
            .home => {
                self.cursor = 0;
                return true;
            },
            .end => {
                self.cursor = self.value.items.len;
                return true;
            },
            else => return false,
        }
    }

    /// Render the widget into a `width`-cell wide rectangle starting at
    /// (row, col). The cursor cell is drawn with the reverse attribute set.
    pub fn view(self: *const TextInput, r: *Renderer, row: u16, col: u16, width: u16, style: Style) void {
        if (width == 0) return;
        const w: usize = width;
        const scroll: usize = if (self.cursor >= w) self.cursor - w + 1 else 0;
        var p: u16 = 0;
        while (p < width) : (p += 1) {
            const vi = scroll + p;
            var s = style;
            var ch: u21 = ' ';
            if (vi < self.value.items.len) ch = self.value.items[vi];
            if (vi == self.cursor) s.reverse = true;
            r.setCell(row, col + p, .{ .char = ch, .style = s });
        }
    }
};

test "init starts empty with cursor at 0" {
    var ti = TextInput.init(std.testing.allocator);
    defer ti.deinit();
    try std.testing.expectEqual(@as(usize, 0), ti.value.items.len);
    try std.testing.expectEqual(@as(usize, 0), ti.cursor);
}

test "insert advances cursor" {
    var ti = TextInput.init(std.testing.allocator);
    defer ti.deinit();
    _ = try ti.handleKey(.{ .code = .{ .char = 'h' } });
    _ = try ti.handleKey(.{ .code = .{ .char = 'i' } });
    try std.testing.expectEqual(@as(usize, 2), ti.value.items.len);
    try std.testing.expectEqual(@as(usize, 2), ti.cursor);
    try std.testing.expectEqual(@as(u21, 'h'), ti.value.items[0]);
    try std.testing.expectEqual(@as(u21, 'i'), ti.value.items[1]);
}

test "ctrl plus char is not consumed" {
    var ti = TextInput.init(std.testing.allocator);
    defer ti.deinit();
    const consumed = try ti.handleKey(.{
        .code = .{ .char = 'c' },
        .modifiers = .{ .ctrl = true },
    });
    try std.testing.expect(!consumed);
    try std.testing.expectEqual(@as(usize, 0), ti.value.items.len);
}

test "backspace removes previous char" {
    var ti = TextInput.init(std.testing.allocator);
    defer ti.deinit();
    try ti.setValue("abc");
    _ = try ti.handleKey(.{ .code = .backspace });
    try std.testing.expectEqual(@as(usize, 2), ti.value.items.len);
    try std.testing.expectEqual(@as(u21, 'b'), ti.value.items[1]);
    try std.testing.expectEqual(@as(usize, 2), ti.cursor);
}

test "backspace at start is a no-op" {
    var ti = TextInput.init(std.testing.allocator);
    defer ti.deinit();
    try ti.setValue("abc");
    ti.cursor = 0;
    _ = try ti.handleKey(.{ .code = .backspace });
    try std.testing.expectEqual(@as(usize, 3), ti.value.items.len);
    try std.testing.expectEqual(@as(usize, 0), ti.cursor);
}

test "delete removes the char under cursor" {
    var ti = TextInput.init(std.testing.allocator);
    defer ti.deinit();
    try ti.setValue("abc");
    ti.cursor = 1;
    _ = try ti.handleKey(.{ .code = .delete });
    try std.testing.expectEqual(@as(usize, 2), ti.value.items.len);
    try std.testing.expectEqual(@as(u21, 'a'), ti.value.items[0]);
    try std.testing.expectEqual(@as(u21, 'c'), ti.value.items[1]);
    try std.testing.expectEqual(@as(usize, 1), ti.cursor);
}

test "delete at end is a no-op" {
    var ti = TextInput.init(std.testing.allocator);
    defer ti.deinit();
    try ti.setValue("abc");
    _ = try ti.handleKey(.{ .code = .delete });
    try std.testing.expectEqual(@as(usize, 3), ti.value.items.len);
}

test "arrow left and right move the cursor" {
    var ti = TextInput.init(std.testing.allocator);
    defer ti.deinit();
    try ti.setValue("abc");
    _ = try ti.handleKey(.{ .code = .arrow_left });
    try std.testing.expectEqual(@as(usize, 2), ti.cursor);
    _ = try ti.handleKey(.{ .code = .arrow_left });
    _ = try ti.handleKey(.{ .code = .arrow_left });
    _ = try ti.handleKey(.{ .code = .arrow_left });
    try std.testing.expectEqual(@as(usize, 0), ti.cursor);
    _ = try ti.handleKey(.{ .code = .arrow_right });
    try std.testing.expectEqual(@as(usize, 1), ti.cursor);
}

test "home and end jump to bounds" {
    var ti = TextInput.init(std.testing.allocator);
    defer ti.deinit();
    try ti.setValue("abc");
    ti.cursor = 1;
    _ = try ti.handleKey(.{ .code = .home });
    try std.testing.expectEqual(@as(usize, 0), ti.cursor);
    _ = try ti.handleKey(.{ .code = .end });
    try std.testing.expectEqual(@as(usize, 3), ti.cursor);
}

test "unhandled key returns false" {
    var ti = TextInput.init(std.testing.allocator);
    defer ti.deinit();
    const consumed = try ti.handleKey(.{ .code = .{ .f = 5 } });
    try std.testing.expect(!consumed);
}

test "setValue parses utf8" {
    var ti = TextInput.init(std.testing.allocator);
    defer ti.deinit();
    try ti.setValue("héllo");
    try std.testing.expectEqual(@as(usize, 5), ti.value.items.len);
    try std.testing.expectEqual(@as(u21, 0x00e9), ti.value.items[1]);
    try std.testing.expectEqual(@as(usize, 5), ti.cursor);
}

test "valueAlloc encodes back to utf8" {
    var ti = TextInput.init(std.testing.allocator);
    defer ti.deinit();
    try ti.setValue("héllo");
    const out = try ti.valueAlloc(std.testing.allocator);
    defer std.testing.allocator.free(out);
    try std.testing.expectEqualStrings("héllo", out);
}

test "view writes value into renderer" {
    var ti = TextInput.init(std.testing.allocator);
    defer ti.deinit();
    try ti.setValue("hi");
    ti.cursor = 0;
    var r = try Renderer.init(std.testing.allocator, 1, 10);
    defer r.deinit();
    ti.view(&r, 0, 0, 10, .{});
    try std.testing.expectEqual(@as(u21, 'h'), r.back[0].char);
    try std.testing.expectEqual(@as(u21, 'i'), r.back[1].char);
}

test "view marks cursor cell with reverse" {
    var ti = TextInput.init(std.testing.allocator);
    defer ti.deinit();
    try ti.setValue("hi");
    var r = try Renderer.init(std.testing.allocator, 1, 10);
    defer r.deinit();
    ti.view(&r, 0, 0, 10, .{});
    try std.testing.expect(r.back[2].style.reverse);
}

test "view scrolls horizontally to keep cursor visible" {
    var ti = TextInput.init(std.testing.allocator);
    defer ti.deinit();
    try ti.setValue("abcdefghij");
    var r = try Renderer.init(std.testing.allocator, 1, 5);
    defer r.deinit();
    ti.view(&r, 0, 0, 5, .{});
    try std.testing.expectEqual(@as(u21, 'g'), r.back[0].char);
    try std.testing.expect(r.back[4].style.reverse);
}

test "view fills the rest with spaces when value is short" {
    var ti = TextInput.init(std.testing.allocator);
    defer ti.deinit();
    try ti.setValue("a");
    var r = try Renderer.init(std.testing.allocator, 1, 5);
    defer r.deinit();
    ti.view(&r, 0, 0, 5, .{});
    try std.testing.expectEqual(@as(u21, 'a'), r.back[0].char);
    try std.testing.expectEqual(@as(u21, ' '), r.back[2].char);
}
