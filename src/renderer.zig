//! Screen renderer.
//!
//! Owns a back buffer that the view writes into and a front buffer that
//! mirrors what is currently on screen. On flush, the renderer diffs the two
//! and emits the minimum cursor moves and characters needed to make the
//! terminal match the back buffer. Styling support lands later.

const std = @import("std");

pub const Cell = struct {
    char: u21 = ' ',
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
    /// silently ignored.
    pub fn setCell(self: *Renderer, row: u16, col: u16, cell: Cell) void {
        if (row >= self.rows or col >= self.cols) return;
        const idx = @as(usize, row) * self.cols + col;
        self.back[idx] = cell;
    }

    /// Write a UTF-8 string starting at (row, col), one cell per codepoint.
    /// Stops at the right edge of the row. Wide characters are not yet
    /// handled.
    pub fn writeText(self: *Renderer, row: u16, col: u16, text: []const u8) void {
        if (row >= self.rows) return;
        var c = col;
        var i: usize = 0;
        while (i < text.len) {
            if (c >= self.cols) break;
            const len = std.unicode.utf8ByteSequenceLength(text[i]) catch return;
            if (i + len > text.len) return;
            const cp = std.unicode.utf8Decode(text[i .. i + len]) catch return;
            self.setCell(row, c, .{ .char = cp });
            c += 1;
            i += len;
        }
    }

    /// Diff the back buffer against the front buffer and produce the bytes
    /// to send to the terminal. The returned slice is owned by the renderer
    /// and is valid until the next flush call.
    pub fn flush(self: *Renderer) ![]const u8 {
        self.out.clearRetainingCapacity();
        var move_buf: [32]u8 = undefined;
        var enc: [4]u8 = undefined;
        var r: u16 = 0;
        while (r < self.rows) : (r += 1) {
            var c: u16 = 0;
            while (c < self.cols) : (c += 1) {
                const idx = @as(usize, r) * self.cols + c;
                if (self.back[idx].char == self.front[idx].char) continue;
                const move = try std.fmt.bufPrint(&move_buf, "\x1b[{d};{d}H", .{ r + 1, c + 1 });
                try self.out.appendSlice(self.allocator, move);
                const n = std.unicode.utf8Encode(self.back[idx].char, &enc) catch {
                    self.front[idx] = self.back[idx];
                    continue;
                };
                try self.out.appendSlice(self.allocator, enc[0..n]);
                self.front[idx] = self.back[idx];
            }
        }
        return self.out.items;
    }
};

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
    try std.testing.expect(std.mem.indexOf(u8, out, "\x1b[2;3HX") != null);
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
    try std.testing.expect(std.mem.indexOf(u8, out2, "\x1b[1;2HZ") != null);
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
    try std.testing.expect(std.mem.indexOf(u8, out, "\x1b[3;4HZ") != null);
}
