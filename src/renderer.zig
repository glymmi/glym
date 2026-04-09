//! Screen renderer.
//!
//! Owns a back buffer that the view writes into and a front buffer that
//! mirrors what is currently on screen. On flush, the renderer diffs the two
//! and emits the minimum cursor moves and characters needed to make the
//! terminal match the back buffer. Styling support lands later.

const std = @import("std");
const Style = @import("style/style.zig").Style;
const color = @import("style/color.zig");
const Rgb = color.Rgb;
const border_mod = @import("style/border.zig");
const Border = border_mod.Border;

pub const Cell = struct {
    char: u21 = ' ',
    style: Style = .{},
};

pub const Renderer = struct {
    allocator: std.mem.Allocator,
    rows: u16,
    cols: u16,
    front: []Cell,
    back: []Cell,
    out: std.ArrayList(u8),

    /// Allocate a renderer for a terminal of the given size. The back buffer
    /// starts blank and the front buffer is set to a sentinel so the first
    /// flush draws every visible cell.
    pub fn init(allocator: std.mem.Allocator, rows: u16, cols: u16) !Renderer {
        const len = @as(usize, rows) * @as(usize, cols);
        const front = try allocator.alloc(Cell, len);
        errdefer allocator.free(front);
        const back = try allocator.alloc(Cell, len);
        @memset(front, .{ .char = 0 });
        @memset(back, .{ .char = ' ' });
        return .{
            .allocator = allocator,
            .rows = rows,
            .cols = cols,
            .front = front,
            .back = back,
            .out = .{},
        };
    }

    pub fn deinit(self: *Renderer) void {
        self.allocator.free(self.front);
        self.allocator.free(self.back);
        self.out.deinit(self.allocator);
    }

    /// Resize the buffers. The next flush will redraw the entire screen.
    pub fn resize(self: *Renderer, rows: u16, cols: u16) !void {
        const new_len = @as(usize, rows) * @as(usize, cols);
        const new_front = try self.allocator.alloc(Cell, new_len);
        errdefer self.allocator.free(new_front);
        const new_back = try self.allocator.alloc(Cell, new_len);
        @memset(new_front, .{ .char = 0 });
        @memset(new_back, .{ .char = ' ' });
        self.allocator.free(self.front);
        self.allocator.free(self.back);
        self.front = new_front;
        self.back = new_back;
        self.rows = rows;
        self.cols = cols;
    }

    /// Reset the back buffer to blank cells.
    pub fn clear(self: *Renderer) void {
        @memset(self.back, .{ .char = ' ' });
    }

    /// Write a single cell into the back buffer. Out-of-bounds writes are
    /// silently ignored. This is a raw overwrite primitive: it does not
    /// look at the existing cell. Use `applyCell` (or the higher-level
    /// `writeStyledText` / `drawBorder` helpers) when you want to layer
    /// a new fg/attribute on top of an existing background.
    pub fn setCell(self: *Renderer, row: u16, col: u16, cell: Cell) void {
        if (row >= self.rows or col >= self.cols) return;
        const idx = @as(usize, row) * self.cols + col;
        self.back[idx] = cell;
    }

    /// Layer a new char and style onto an existing cell. Any field of
    /// `new_style` left at its default (fg/bg = `.default`, attributes
    /// false) inherits from the cell already in the back buffer, so a
    /// border drawn over a filled rect keeps the rect's background and
    /// text written on top of the same rect picks it up too.
    pub fn applyCell(self: *Renderer, row: u16, col: u16, ch: u21, new_style: Style) void {
        if (row >= self.rows or col >= self.cols) return;
        const idx = @as(usize, row) * self.cols + col;
        const existing = self.back[idx];
        self.back[idx] = .{ .char = ch, .style = Style.merge(existing.style, new_style) };
    }

    /// Write a UTF-8 string starting at (row, col), one cell per codepoint.
    /// Stops at the right edge of the row. Wide characters are not yet
    /// handled.
    pub fn writeText(self: *Renderer, row: u16, col: u16, text: []const u8) void {
        self.writeStyledText(row, col, text, .{});
    }

    /// Like `writeText` but applies the given style to every cell. Any
    /// field of `style` left at its default inherits the existing
    /// background under the text, so writing on top of a filled panel
    /// preserves the panel color.
    pub fn writeStyledText(self: *Renderer, row: u16, col: u16, text: []const u8, style: Style) void {
        if (row >= self.rows) return;
        var c = col;
        var i: usize = 0;
        while (i < text.len) {
            if (c >= self.cols) break;
            const len = std.unicode.utf8ByteSequenceLength(text[i]) catch return;
            if (i + len > text.len) return;
            const cp = std.unicode.utf8Decode(text[i .. i + len]) catch return;
            self.applyCell(row, c, cp, style);
            c += 1;
            i += len;
        }
    }

    /// Write text with a horizontal RGB gradient from `start` to `end`. The
    /// `base` style provides any non-color attributes (bold, italic, bg...).
    /// Each codepoint gets an interpolated foreground color.
    pub fn writeGradientText(
        self: *Renderer,
        row: u16,
        col: u16,
        text: []const u8,
        start: Rgb,
        end: Rgb,
        base: Style,
    ) void {
        if (row >= self.rows) return;
        var cp_count: usize = 0;
        {
            var i: usize = 0;
            while (i < text.len) {
                const len = std.unicode.utf8ByteSequenceLength(text[i]) catch return;
                if (i + len > text.len) return;
                i += len;
                cp_count += 1;
            }
        }
        if (cp_count == 0) return;
        var c = col;
        var i: usize = 0;
        var idx: usize = 0;
        while (i < text.len) {
            if (c >= self.cols) break;
            const len = std.unicode.utf8ByteSequenceLength(text[i]) catch return;
            const cp = std.unicode.utf8Decode(text[i .. i + len]) catch return;
            const t: f32 = if (cp_count == 1)
                0
            else
                @as(f32, @floatFromInt(idx)) / @as(f32, @floatFromInt(cp_count - 1));
            var s = base;
            s.fg = .{ .rgb = color.lerpRgb(start, end, t) };
            self.applyCell(row, c, cp, s);
            c += 1;
            i += len;
            idx += 1;
        }
    }

    /// Fill a rectangle with `cell`. Out-of-bounds writes are silently
    /// clipped. Useful for painting solid panels behind text.
    pub fn fillRect(self: *Renderer, row: u16, col: u16, height: u16, width: u16, cell: Cell) void {
        var dr: u16 = 0;
        while (dr < height) : (dr += 1) {
            var dc: u16 = 0;
            while (dc < width) : (dc += 1) {
                self.setCell(row + dr, col + dc, cell);
            }
        }
    }

    /// Write a string centered horizontally inside a `width`-cell wide
    /// region starting at (row, col). Strings longer than the region are
    /// truncated from the right.
    pub fn writeCenteredText(self: *Renderer, row: u16, col: u16, width: u16, text: []const u8, style: Style) void {
        const cp_count = utf8CodepointCount(text);
        if (cp_count >= width) {
            self.writeStyledText(row, col, text, style);
            return;
        }
        const offset: u16 = @intCast((@as(usize, width) - cp_count) / 2);
        self.writeStyledText(row, col + offset, text, style);
    }

    /// Draw a border rectangle of `border` glyphs styled with `style`.
    /// The rectangle's interior is left untouched. A `height` or `width`
    /// below 2 collapses to a no-op.
    pub fn drawBorder(self: *Renderer, row: u16, col: u16, height: u16, width: u16, border: Border, style: Style) void {
        if (height < 2 or width < 2) return;
        const last_row = row + height - 1;
        const last_col = col + width - 1;
        // Corners.
        self.applyCell(row, col, border.top_left, style);
        self.applyCell(row, last_col, border.top_right, style);
        self.applyCell(last_row, col, border.bottom_left, style);
        self.applyCell(last_row, last_col, border.bottom_right, style);
        // Top and bottom edges.
        var c: u16 = col + 1;
        while (c < last_col) : (c += 1) {
            self.applyCell(row, c, border.top, style);
            self.applyCell(last_row, c, border.bottom, style);
        }
        // Left and right edges.
        var r: u16 = row + 1;
        while (r < last_row) : (r += 1) {
            self.applyCell(r, col, border.left, style);
            self.applyCell(r, last_col, border.right, style);
        }
    }

    /// Draw a border with a centered title sitting on the top edge. The
    /// title is padded with a single space on each side and styled with
    /// `title_style`.
    pub fn drawBorderTitled(
        self: *Renderer,
        row: u16,
        col: u16,
        height: u16,
        width: u16,
        border: Border,
        style: Style,
        title: []const u8,
        title_style: Style,
    ) void {
        self.drawBorder(row, col, height, width, border, style);
        if (width < 4 or title.len == 0) return;
        const title_len = utf8CodepointCount(title);
        // Reserve a 1-cell space on each side of the title.
        const max_title: u16 = width - 4;
        const shown: u16 = if (title_len > max_title) max_title else @intCast(title_len);
        const start_col: u16 = col + (width - shown - 2) / 2;
        self.applyCell(row, start_col, ' ', style);
        self.writeStyledText(row, start_col + 1, title, title_style);
        self.applyCell(row, start_col + 1 + shown, ' ', style);
    }

    /// Draw a filled bordered box: paint the interior with `fill`, then
    /// the border on top with `border_style`. The fill is contained
    /// inside the frame: the border row and column themselves keep
    /// whatever sits behind them, so the panel's background stops
    /// exactly at the border line. A common building block for panels,
    /// modals, and tooltips.
    pub fn drawBox(
        self: *Renderer,
        row: u16,
        col: u16,
        height: u16,
        width: u16,
        border: Border,
        border_style: Style,
        fill: Style,
    ) void {
        if (height == 0 or width == 0) return;
        if (height >= 2 and width >= 2) {
            self.fillRect(row + 1, col + 1, height - 2, width - 2, .{ .char = ' ', .style = fill });
        } else {
            // Degenerate rect with no room for an interior: just fill
            // the whole thing so something is visible.
            self.fillRect(row, col, height, width, .{ .char = ' ', .style = fill });
        }
        self.drawBorder(row, col, height, width, border, border_style);
    }

    /// Diff the back buffer against the front buffer and produce the bytes
    /// to send to the terminal. The returned slice is owned by the renderer
    /// and is valid until the next flush call.
    pub fn flush(self: *Renderer) ![]const u8 {
        self.out.clearRetainingCapacity();
        var move_buf: [32]u8 = undefined;
        var style_buf: [64]u8 = undefined;
        var enc: [4]u8 = undefined;
        var current_style: ?Style = null;
        var r: u16 = 0;
        while (r < self.rows) : (r += 1) {
            var c: u16 = 0;
            while (c < self.cols) : (c += 1) {
                const idx = @as(usize, r) * self.cols + c;
                const back = self.back[idx];
                const front = self.front[idx];
                if (back.char == front.char and Style.eql(back.style, front.style)) continue;
                const move = try std.fmt.bufPrint(&move_buf, "\x1b[{d};{d}H", .{ r + 1, c + 1 });
                try self.out.appendSlice(self.allocator, move);
                if (current_style == null or !Style.eql(back.style, current_style.?)) {
                    const seq = try back.style.sequence(&style_buf);
                    try self.out.appendSlice(self.allocator, seq);
                    current_style = back.style;
                }
                const n = std.unicode.utf8Encode(back.char, &enc) catch {
                    self.front[idx] = back;
                    continue;
                };
                try self.out.appendSlice(self.allocator, enc[0..n]);
                self.front[idx] = back;
            }
        }
        return self.out.items;
    }
};

fn utf8CodepointCount(text: []const u8) u16 {
    var n: u16 = 0;
    var i: usize = 0;
    while (i < text.len) {
        const len = std.unicode.utf8ByteSequenceLength(text[i]) catch return n;
        if (i + len > text.len) return n;
        i += len;
        n += 1;
    }
    return n;
}

test "init sets dimensions" {
    var r = try Renderer.init(std.testing.allocator, 5, 10);
    defer r.deinit();
    try std.testing.expectEqual(@as(u16, 5), r.rows);
    try std.testing.expectEqual(@as(u16, 10), r.cols);
}

test "flush emits move and char for written cell" {
    var r = try Renderer.init(std.testing.allocator, 3, 3);
    defer r.deinit();
    r.setCell(1, 2, .{ .char = 'X' });
    const out = try r.flush();
    try std.testing.expect(std.mem.indexOf(u8, out, "\x1b[2;3H") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "X") != null);
}

test "second flush is empty when nothing changed" {
    var r = try Renderer.init(std.testing.allocator, 2, 2);
    defer r.deinit();
    r.setCell(0, 0, .{ .char = 'A' });
    _ = try r.flush();
    const out2 = try r.flush();
    try std.testing.expectEqual(@as(usize, 0), out2.len);
}

test "second flush emits only the changed cell" {
    var r = try Renderer.init(std.testing.allocator, 2, 2);
    defer r.deinit();
    _ = try r.flush();
    r.setCell(0, 1, .{ .char = 'Z' });
    const out2 = try r.flush();
    try std.testing.expect(std.mem.indexOf(u8, out2, "\x1b[1;2H") != null);
    try std.testing.expect(std.mem.indexOf(u8, out2, "Z") != null);
    try std.testing.expect(std.mem.indexOf(u8, out2, "\x1b[1;1H") == null);
}

test "setCell out of bounds is a no-op" {
    var r = try Renderer.init(std.testing.allocator, 2, 2);
    defer r.deinit();
    r.setCell(10, 10, .{ .char = 'X' });
    _ = try r.flush();
}

test "writeText writes ascii cells" {
    var r = try Renderer.init(std.testing.allocator, 1, 5);
    defer r.deinit();
    r.writeText(0, 0, "hi");
    const out = try r.flush();
    try std.testing.expect(std.mem.indexOf(u8, out, "h") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "i") != null);
}

test "writeText stops at right edge" {
    var r = try Renderer.init(std.testing.allocator, 1, 3);
    defer r.deinit();
    r.writeText(0, 1, "abcdef");
    try std.testing.expectEqual(@as(u21, 'a'), r.back[1].char);
    try std.testing.expectEqual(@as(u21, 'b'), r.back[2].char);
}

test "writeText handles utf8 codepoints" {
    var r = try Renderer.init(std.testing.allocator, 1, 3);
    defer r.deinit();
    r.writeText(0, 0, "é");
    try std.testing.expectEqual(@as(u21, 0x00e9), r.back[0].char);
}

test "clear resets back buffer to spaces" {
    var r = try Renderer.init(std.testing.allocator, 2, 2);
    defer r.deinit();
    r.setCell(0, 0, .{ .char = 'X' });
    r.clear();
    try std.testing.expectEqual(@as(u21, ' '), r.back[0].char);
}

test "flush emits style sequence when a styled cell changes" {
    var r = try Renderer.init(std.testing.allocator, 2, 2);
    defer r.deinit();
    _ = try r.flush();
    r.setCell(0, 0, .{ .char = 'X', .style = .{ .fg = .{ .indexed = 1 }, .bold = true } });
    const out = try r.flush();
    try std.testing.expect(std.mem.indexOf(u8, out, "\x1b[0;1;31m") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "X") != null);
}

test "writeStyledText applies the given style to every cell" {
    var r = try Renderer.init(std.testing.allocator, 1, 5);
    defer r.deinit();
    r.writeStyledText(0, 0, "hi", .{ .fg = .{ .indexed = 1 }, .bold = true });
    try std.testing.expect(r.back[0].style.bold);
    try std.testing.expectEqual(@as(u21, 'h'), r.back[0].char);
    try std.testing.expectEqual(@as(u21, 'i'), r.back[1].char);
    try std.testing.expect(r.back[1].style.bold);
}

test "writeGradientText interpolates fg across cells" {
    var r = try Renderer.init(std.testing.allocator, 1, 5);
    defer r.deinit();
    const a: Rgb = .{ .r = 0, .g = 0, .b = 0 };
    const b: Rgb = .{ .r = 200, .g = 0, .b = 0 };
    r.writeGradientText(0, 0, "abc", a, b, .{});
    try std.testing.expectEqual(@as(u8, 0), r.back[0].style.fg.rgb.r);
    try std.testing.expectEqual(@as(u8, 100), r.back[1].style.fg.rgb.r);
    try std.testing.expectEqual(@as(u8, 200), r.back[2].style.fg.rgb.r);
}

test "writeGradientText preserves base attributes" {
    var r = try Renderer.init(std.testing.allocator, 1, 3);
    defer r.deinit();
    const a: Rgb = .{ .r = 0, .g = 0, .b = 0 };
    const b: Rgb = .{ .r = 255, .g = 255, .b = 255 };
    r.writeGradientText(0, 0, "ab", a, b, .{ .bold = true, .italic = true });
    try std.testing.expect(r.back[0].style.bold);
    try std.testing.expect(r.back[0].style.italic);
}

test "flush detects pure style change without char change" {
    var r = try Renderer.init(std.testing.allocator, 1, 1);
    defer r.deinit();
    r.setCell(0, 0, .{ .char = 'A' });
    _ = try r.flush();
    r.setCell(0, 0, .{ .char = 'A', .style = .{ .fg = .{ .indexed = 2 } } });
    const out = try r.flush();
    try std.testing.expect(std.mem.indexOf(u8, out, "\x1b[0;32m") != null);
}

test "resize updates dimensions and forces full redraw" {
    var r = try Renderer.init(std.testing.allocator, 2, 2);
    defer r.deinit();
    r.setCell(0, 0, .{ .char = 'A' });
    _ = try r.flush();
    try r.resize(3, 4);
    try std.testing.expectEqual(@as(u16, 3), r.rows);
    try std.testing.expectEqual(@as(u16, 4), r.cols);
    r.setCell(2, 3, .{ .char = 'Z' });
    const out = try r.flush();
    try std.testing.expect(std.mem.indexOf(u8, out, "\x1b[3;4H") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "Z") != null);
}

test "fillRect paints a uniform region" {
    var r = try Renderer.init(std.testing.allocator, 4, 4);
    defer r.deinit();
    r.fillRect(1, 1, 2, 2, .{ .char = '#' });
    try std.testing.expectEqual(@as(u21, ' '), r.back[0].char);
    try std.testing.expectEqual(@as(u21, '#'), r.back[5].char);
    try std.testing.expectEqual(@as(u21, '#'), r.back[6].char);
    try std.testing.expectEqual(@as(u21, '#'), r.back[9].char);
    try std.testing.expectEqual(@as(u21, '#'), r.back[10].char);
}

test "writeCenteredText centers a short string" {
    var r = try Renderer.init(std.testing.allocator, 1, 10);
    defer r.deinit();
    r.writeCenteredText(0, 0, 10, "hi", .{});
    // (10 - 2) / 2 = 4 -> "h" at col 4, "i" at col 5
    try std.testing.expectEqual(@as(u21, ' '), r.back[3].char);
    try std.testing.expectEqual(@as(u21, 'h'), r.back[4].char);
    try std.testing.expectEqual(@as(u21, 'i'), r.back[5].char);
}

test "drawBorder draws corners and edges" {
    var r = try Renderer.init(std.testing.allocator, 4, 4);
    defer r.deinit();
    r.drawBorder(0, 0, 4, 4, Border.sharp, .{});
    try std.testing.expectEqual(@as(u21, 0x250C), r.back[0].char);
    try std.testing.expectEqual(@as(u21, 0x2510), r.back[3].char);
    try std.testing.expectEqual(@as(u21, 0x2514), r.back[12].char);
    try std.testing.expectEqual(@as(u21, 0x2518), r.back[15].char);
    try std.testing.expectEqual(@as(u21, 0x2500), r.back[1].char);
    try std.testing.expectEqual(@as(u21, 0x2502), r.back[4].char);
    // Interior stays untouched.
    try std.testing.expectEqual(@as(u21, ' '), r.back[5].char);
}

test "drawBorder is a no-op for tiny rectangles" {
    var r = try Renderer.init(std.testing.allocator, 2, 2);
    defer r.deinit();
    r.drawBorder(0, 0, 1, 4, Border.sharp, .{});
    try std.testing.expectEqual(@as(u21, ' '), r.back[0].char);
}

test "drawBorderTitled places title on the top edge" {
    var r = try Renderer.init(std.testing.allocator, 3, 12);
    defer r.deinit();
    r.drawBorderTitled(0, 0, 3, 12, Border.rounded, .{}, "hi", .{});
    // " hi " centered on 12-col top edge: shown=2, start=(12-2-2)/2=4
    // -> col 4 = ' ', col 5 = 'h', col 6 = 'i', col 7 = ' '
    try std.testing.expectEqual(@as(u21, ' '), r.back[4].char);
    try std.testing.expectEqual(@as(u21, 'h'), r.back[5].char);
    try std.testing.expectEqual(@as(u21, 'i'), r.back[6].char);
    try std.testing.expectEqual(@as(u21, ' '), r.back[7].char);
}

test "writeStyledText inherits underlying background" {
    var r = try Renderer.init(std.testing.allocator, 1, 5);
    defer r.deinit();
    const panel: Style = .{ .bg = .{ .indexed = 4 } };
    r.fillRect(0, 0, 1, 5, .{ .char = ' ', .style = panel });
    r.writeStyledText(0, 1, "hi", .{ .fg = .{ .indexed = 7 }, .bold = true });
    try std.testing.expectEqual(@as(u21, 'h'), r.back[1].char);
    try std.testing.expectEqual(@as(u8, 7), r.back[1].style.fg.indexed);
    try std.testing.expectEqual(@as(u8, 4), r.back[1].style.bg.indexed);
    try std.testing.expect(r.back[1].style.bold);
}

test "drawBorder inherits underlying background" {
    var r = try Renderer.init(std.testing.allocator, 3, 3);
    defer r.deinit();
    const panel: Style = .{ .bg = .{ .indexed = 4 } };
    r.fillRect(0, 0, 3, 3, .{ .char = ' ', .style = panel });
    const border_style: Style = .{ .fg = .{ .indexed = 5 } };
    r.drawBorder(0, 0, 3, 3, Border.sharp, border_style);
    // Top-left corner: fg from border, bg bleeds through from the fill.
    try std.testing.expectEqual(@as(u21, 0x250C), r.back[0].char);
    try std.testing.expectEqual(@as(u8, 5), r.back[0].style.fg.indexed);
    try std.testing.expectEqual(@as(u8, 4), r.back[0].style.bg.indexed);
}

test "drawBox fills the interior and frames it" {
    var r = try Renderer.init(std.testing.allocator, 3, 3);
    defer r.deinit();
    const fill: Style = .{ .bg = .{ .indexed = 4 } };
    r.drawBox(0, 0, 3, 3, Border.sharp, .{}, fill);
    // Interior cell carries the fill style.
    try std.testing.expectEqual(@as(u21, ' '), r.back[4].char);
    try std.testing.expect(Style.eql(r.back[4].style, fill));
    // Border corners overwrite the fill char.
    try std.testing.expectEqual(@as(u21, 0x250C), r.back[0].char);
}

test "drawBox keeps the fill out of the border row and column" {
    var r = try Renderer.init(std.testing.allocator, 3, 3);
    defer r.deinit();
    const fill: Style = .{ .bg = .{ .indexed = 4 } };
    r.drawBox(0, 0, 3, 3, Border.sharp, .{}, fill);
    // Border cells must NOT carry the fill background.
    try std.testing.expect(!std.meta.eql(r.back[0].style.bg, fill.bg)); // top-left
    try std.testing.expect(!std.meta.eql(r.back[2].style.bg, fill.bg)); // top-right
    try std.testing.expect(!std.meta.eql(r.back[6].style.bg, fill.bg)); // bottom-left
    try std.testing.expect(!std.meta.eql(r.back[1].style.bg, fill.bg)); // top edge
    try std.testing.expect(!std.meta.eql(r.back[3].style.bg, fill.bg)); // left edge
}
