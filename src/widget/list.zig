//! Vertical selection list widget.
//!
//! Displays a scrollable list of text items with keyboard navigation.
//! The selected item is rendered with the reverse attribute set. The
//! `view` function mutates `offset` to keep the selection visible, so
//! it takes a `*List`, not a `*const List`.

const std = @import("std");
const input = @import("../term/input.zig");
const Renderer = @import("../renderer.zig").Renderer;
const Style = @import("../style/style.zig").Style;

pub const List = struct {
    items: []const []const u8,
    selected: usize,
    offset: usize,

    pub fn init(items: []const []const u8) List {
        return .{
            .items = items,
            .selected = 0,
            .offset = 0,
        };
    }

    /// Replace the items slice. Clamps selection to the new length.
    pub fn setItems(self: *List, items: []const []const u8) void {
        self.items = items;
        if (items.len == 0) {
            self.selected = 0;
            self.offset = 0;
        } else {
            if (self.selected >= items.len) self.selected = items.len - 1;
        }
    }

    /// Move selection to the given index, clamped to the item count.
    pub fn select(self: *List, index: usize) void {
        if (self.items.len == 0) return;
        self.selected = @min(index, self.items.len - 1);
    }

    /// Return the currently selected item, or null if the list is empty.
    pub fn selectedItem(self: *const List) ?[]const u8 {
        if (self.items.len == 0) return null;
        return self.items[self.selected];
    }

    /// Apply a key event to the widget. Returns true if the key was
    /// consumed, false if the host app should handle it. Returns an
    /// error union for signature symmetry with the other widgets, but
    /// the list itself never allocates and never fails.
    pub fn handleKey(self: *List, key: input.Key) !bool {
        if (self.items.len == 0) return false;
        switch (key.code) {
            .arrow_up => {
                if (self.selected > 0) self.selected -= 1;
                return true;
            },
            .arrow_down => {
                if (self.selected < self.items.len - 1) self.selected += 1;
                return true;
            },
            .home => {
                self.selected = 0;
                return true;
            },
            .end => {
                self.selected = self.items.len - 1;
                return true;
            },
            else => return false,
        }
    }

    /// Compute a clamped scroll offset that keeps `selected` visible
    /// within `height` rows. Pure function for testability.
    pub fn clampedOffset(selected: usize, item_count: usize, height: usize, current: usize) usize {
        if (height == 0 or item_count == 0) return 0;
        var off = current;
        if (selected < off) {
            off = selected;
        } else if (selected >= off + height) {
            off = selected - height + 1;
        }
        const max = if (item_count > height) item_count - height else 0;
        if (off > max) off = max;
        return off;
    }

    /// Render the list into a rectangle of `height` rows and `width`
    /// columns starting at (row, col). The selected row is drawn with
    /// the reverse attribute set. Empty rows below the last item are
    /// filled with spaces.
    pub fn view(self: *List, r: *Renderer, row: u16, col: u16, height: u16, width: u16, style: Style) void {
        if (height == 0 or width == 0) return;
        self.offset = clampedOffset(self.selected, self.items.len, height, self.offset);
        var line: u16 = 0;
        while (line < height) : (line += 1) {
            const item_idx = self.offset + line;
            var s = style;
            if (item_idx < self.items.len and item_idx == self.selected) s.reverse = true;
            var p: u16 = 0;
            if (item_idx < self.items.len) {
                const text = self.items[item_idx];
                var i: usize = 0;
                while (i < text.len and p < width) {
                    const len = std.unicode.utf8ByteSequenceLength(text[i]) catch break;
                    if (i + len > text.len) break;
                    const cp = std.unicode.utf8Decode(text[i .. i + len]) catch break;
                    r.setCell(row + line, col + p, .{ .char = cp, .style = s });
                    p += 1;
                    i += len;
                }
            }
            while (p < width) : (p += 1) {
                r.setCell(row + line, col + p, .{ .char = ' ', .style = s });
            }
        }
    }
};

// -- tests: pure selection logic --

test "init starts at index 0" {
    const items = [_][]const u8{ "one", "two", "three" };
    const l = List.init(&items);
    try std.testing.expectEqual(@as(usize, 0), l.selected);
    try std.testing.expectEqual(@as(usize, 0), l.offset);
}

test "arrow down advances selection" {
    const items = [_][]const u8{ "a", "b", "c" };
    var l = List.init(&items);
    try std.testing.expect(try l.handleKey(.{ .code = .arrow_down }));
    try std.testing.expectEqual(@as(usize, 1), l.selected);
}

test "arrow down stops at last item" {
    const items = [_][]const u8{ "a", "b" };
    var l = List.init(&items);
    l.selected = 1;
    _ = try l.handleKey(.{ .code = .arrow_down });
    try std.testing.expectEqual(@as(usize, 1), l.selected);
}

test "arrow up decrements selection" {
    const items = [_][]const u8{ "a", "b", "c" };
    var l = List.init(&items);
    l.selected = 2;
    try std.testing.expect(try l.handleKey(.{ .code = .arrow_up }));
    try std.testing.expectEqual(@as(usize, 1), l.selected);
}

test "arrow up stops at first item" {
    const items = [_][]const u8{ "a", "b" };
    var l = List.init(&items);
    _ = try l.handleKey(.{ .code = .arrow_up });
    try std.testing.expectEqual(@as(usize, 0), l.selected);
}

test "home jumps to first item" {
    const items = [_][]const u8{ "a", "b", "c" };
    var l = List.init(&items);
    l.selected = 2;
    try std.testing.expect(try l.handleKey(.{ .code = .home }));
    try std.testing.expectEqual(@as(usize, 0), l.selected);
}

test "end jumps to last item" {
    const items = [_][]const u8{ "a", "b", "c" };
    var l = List.init(&items);
    try std.testing.expect(try l.handleKey(.{ .code = .end }));
    try std.testing.expectEqual(@as(usize, 2), l.selected);
}

test "unhandled key returns false" {
    const items = [_][]const u8{"a"};
    var l = List.init(&items);
    try std.testing.expect(!try l.handleKey(.{ .code = .{ .f = 5 } }));
}

test "empty list ignores all keys" {
    const items = [_][]const u8{};
    var l = List.init(&items);
    try std.testing.expect(!try l.handleKey(.{ .code = .arrow_down }));
    try std.testing.expect(!try l.handleKey(.{ .code = .arrow_up }));
}

test "selectedItem returns current item" {
    const items = [_][]const u8{ "a", "b" };
    var l = List.init(&items);
    l.selected = 1;
    try std.testing.expectEqualStrings("b", l.selectedItem().?);
}

test "selectedItem returns null on empty list" {
    const items = [_][]const u8{};
    const l = List.init(&items);
    try std.testing.expect(l.selectedItem() == null);
}

test "setItems clamps selection" {
    const big = [_][]const u8{ "a", "b", "c", "d" };
    var l = List.init(&big);
    l.selected = 3;
    const small = [_][]const u8{ "x", "y" };
    l.setItems(&small);
    try std.testing.expectEqual(@as(usize, 1), l.selected);
}

test "select clamps to bounds" {
    const items = [_][]const u8{ "a", "b" };
    var l = List.init(&items);
    l.select(100);
    try std.testing.expectEqual(@as(usize, 1), l.selected);
}

// -- tests: scroll math --

test "clampedOffset keeps selected visible when scrolling down" {
    try std.testing.expectEqual(@as(usize, 3), List.clampedOffset(5, 10, 3, 0));
}

test "clampedOffset keeps selected visible when scrolling up" {
    try std.testing.expectEqual(@as(usize, 2), List.clampedOffset(2, 10, 3, 5));
}

test "clampedOffset preserves offset when selected is visible" {
    try std.testing.expectEqual(@as(usize, 2), List.clampedOffset(3, 10, 5, 2));
}

test "clampedOffset clamps to max when items fit" {
    try std.testing.expectEqual(@as(usize, 0), List.clampedOffset(0, 3, 10, 0));
}

test "clampedOffset returns 0 for zero height" {
    try std.testing.expectEqual(@as(usize, 0), List.clampedOffset(5, 10, 0, 3));
}

test "clampedOffset returns 0 for zero items" {
    try std.testing.expectEqual(@as(usize, 0), List.clampedOffset(0, 0, 5, 3));
}

test "clampedOffset caps at max offset" {
    // 10 items, height 3, max offset is 7
    try std.testing.expectEqual(@as(usize, 7), List.clampedOffset(9, 10, 3, 0));
}

// -- tests: view rendering --

test "view writes items into renderer" {
    const items = [_][]const u8{ "ab", "cd" };
    var l = List.init(&items);
    var r = try Renderer.init(std.testing.allocator, 5, 10);
    defer r.deinit();
    l.view(&r, 0, 0, 2, 10, .{});
    try std.testing.expectEqual(@as(u21, 'a'), r.back[0].char);
    try std.testing.expectEqual(@as(u21, 'b'), r.back[1].char);
    try std.testing.expectEqual(@as(u21, 'c'), r.back[10].char);
    try std.testing.expectEqual(@as(u21, 'd'), r.back[11].char);
}

test "view marks selected row with reverse" {
    const items = [_][]const u8{ "a", "b" };
    var l = List.init(&items);
    l.selected = 1;
    var r = try Renderer.init(std.testing.allocator, 5, 5);
    defer r.deinit();
    l.view(&r, 0, 0, 2, 5, .{});
    try std.testing.expect(!r.back[0].style.reverse);
    try std.testing.expect(r.back[5].style.reverse);
}

test "view fills remaining width with spaces" {
    const items = [_][]const u8{"a"};
    var l = List.init(&items);
    var r = try Renderer.init(std.testing.allocator, 1, 5);
    defer r.deinit();
    l.view(&r, 0, 0, 1, 5, .{});
    try std.testing.expectEqual(@as(u21, 'a'), r.back[0].char);
    try std.testing.expectEqual(@as(u21, ' '), r.back[1].char);
    try std.testing.expectEqual(@as(u21, ' '), r.back[4].char);
}

test "view fills empty rows below items" {
    const items = [_][]const u8{"a"};
    var l = List.init(&items);
    var r = try Renderer.init(std.testing.allocator, 3, 5);
    defer r.deinit();
    l.view(&r, 0, 0, 3, 5, .{});
    try std.testing.expectEqual(@as(u21, 'a'), r.back[0].char);
    try std.testing.expectEqual(@as(u21, ' '), r.back[5].char);
}

test "view scrolls to keep selection visible" {
    const items = [_][]const u8{ "a", "b", "c", "d", "e" };
    var l = List.init(&items);
    l.selected = 4;
    var r = try Renderer.init(std.testing.allocator, 3, 5);
    defer r.deinit();
    l.view(&r, 0, 0, 3, 5, .{});
    // offset should be 2, showing items c, d, e
    try std.testing.expectEqual(@as(usize, 2), l.offset);
    try std.testing.expectEqual(@as(u21, 'c'), r.back[0].char);
    try std.testing.expectEqual(@as(u21, 'e'), r.back[10].char);
    try std.testing.expect(r.back[10].style.reverse);
}

test "view with zero height is a no-op" {
    const items = [_][]const u8{"a"};
    var l = List.init(&items);
    var r = try Renderer.init(std.testing.allocator, 1, 5);
    defer r.deinit();
    l.view(&r, 0, 0, 0, 5, .{});
    try std.testing.expectEqual(@as(u21, ' '), r.back[0].char);
}
