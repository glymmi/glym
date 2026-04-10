# Using glym layers standalone

glym's layers are independent. You can use the terminal primitives and
the renderer without the MVU runtime. This is useful when you already
have your own event loop, need a one-shot styled output, or want to
build a custom runtime on top of glym's lower layers.

## Layer independence

```
term/ansi.zig    escape constants, no state
term/raw.zig     raw mode toggle, no deps on renderer or program
term/input.zig   byte-to-key parser, no deps on renderer or program
term/size.zig    terminal size query, no deps on renderer or program
renderer.zig     double-buffered screen, depends on style only
style.zig        re-exports from shimmer, no deps on anything above
```

Nothing in `term/` or `renderer.zig` imports `program.zig`. You can
import any of them without pulling in the runtime.

## Example 1: raw ANSI output

Write styled text to the terminal without a renderer or runtime. Useful
for CLI tools that need a splash of color or a formatted header.

```zig
const std = @import("std");
const glym = @import("glym");

pub fn main() !void {
    const stdout = std.io.getStdOut().writer();

    // Move to row 1, col 1 and clear screen.
    try stdout.writeAll(glym.ansi.clear_screen);

    // Write bold red text using raw SGR sequences.
    try stdout.writeAll("\x1b[1;31m");
    try stdout.writeAll("Error: something went wrong");
    try stdout.writeAll("\x1b[0m\n");

    // Use the moveCursor helper (allocating).
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const move = try glym.ansi.moveCursor(gpa.allocator(), 5, 10);
    defer gpa.allocator().free(move);
    try stdout.writeAll(move);
    try stdout.writeAll("Cursor placed at row 5, col 10\n");
}
```

Available constants in `glym.ansi`:

| Constant            | Effect                                    |
|---------------------|-------------------------------------------|
| `clear_screen`      | Clear screen and move cursor to 1,1       |
| `hide_cursor`       | Hide the text cursor                      |
| `show_cursor`       | Show the text cursor                      |
| `enter_alt_screen`  | Switch to the alternate screen buffer     |
| `leave_alt_screen`  | Restore the main screen buffer            |
| `reset`             | Reset all SGR attributes                  |

## Example 2: raw mode and input parsing

Read individual keypresses without the runtime. Useful for building a
custom event loop or a key-driven menu.

```zig
const std = @import("std");
const glym = @import("glym");

pub fn main() !void {
    const stdin = std.posix.STDIN_FILENO;
    const stdout = std.io.getStdOut().writer();

    // Enter raw mode so we get one keypress at a time.
    var raw_mode = try glym.raw.RawMode.enable(stdin);
    defer raw_mode.disable() catch {};

    try stdout.writeAll("Press keys (q to quit):\r\n");

    var buf: [256]u8 = undefined;
    while (true) {
        const n = std.posix.read(stdin, &buf) catch break;
        if (n == 0) break;

        // Parse keys from the raw bytes.
        var remaining = buf[0..n];
        while (glym.input.parse(remaining)) |result| {
            switch (result.key.code) {
                .char => |c| {
                    if (c == 'q') {
                        try stdout.writeAll("\r\nBye.\r\n");
                        return;
                    }
                    var enc: [4]u8 = undefined;
                    const len = std.unicode.utf8Encode(c, &enc) catch continue;
                    try stdout.writeAll(enc[0..len]);
                },
                .enter => try stdout.writeAll("\r\n"),
                .arrow_up => try stdout.writeAll("[up]"),
                .arrow_down => try stdout.writeAll("[down]"),
                .escape => try stdout.writeAll("[esc]"),
                else => try stdout.writeAll("[?]"),
            }
            remaining = remaining[result.consumed..];
        }
    }
}
```

## Example 3: renderer without the runtime

Use the double-buffered renderer for efficient screen updates in your
own loop. You handle raw mode, reading input, and writing output
yourself.

```zig
const std = @import("std");
const glym = @import("glym");
const Renderer = glym.renderer.Renderer;
const Style = glym.style.Style;
const Border = glym.style.Border;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const stdin = std.posix.STDIN_FILENO;
    const stdout = std.posix.STDOUT_FILENO;

    // Terminal setup (normally the runtime does this).
    var raw_mode = try glym.raw.RawMode.enable(stdin);
    defer raw_mode.disable() catch {};

    const size = try glym.size.get(stdout);
    var r = try Renderer.init(allocator, size.rows, size.cols);
    defer r.deinit();

    try writeAll(stdout, glym.ansi.enter_alt_screen);
    defer writeAll(stdout, glym.ansi.leave_alt_screen) catch {};
    try writeAll(stdout, glym.ansi.hide_cursor);
    defer writeAll(stdout, glym.ansi.show_cursor) catch {};

    // Draw a frame.
    r.drawBorder(0, 0, size.rows, size.cols, Border.rounded, .{ .fg = .{ .indexed = 8 } });
    r.writeStyledText(2, 2, "Standalone renderer", .{ .bold = true });
    r.writeStyledText(4, 2, "Press any key to quit.", .{});
    try writeAll(stdout, try r.flush());

    // Wait for one keypress, then exit.
    var buf: [16]u8 = undefined;
    _ = std.posix.read(stdin, &buf) catch {};
}

fn writeAll(fd: std.posix.fd_t, bytes: []const u8) !void {
    var remaining = bytes;
    while (remaining.len > 0) {
        const n = std.posix.write(fd, remaining) catch return error.WriteFailed;
        if (n == 0) return error.WriteFailed;
        remaining = remaining[n..];
    }
}
```

The renderer's `flush` returns a byte slice containing only the escape
sequences needed to update changed cells. On the first call it paints
the full screen (the front buffer starts as a sentinel). On later calls
it emits only the diff, so you can call it in a loop and get efficient
incremental updates for free.

## When to use the runtime instead

The standalone approach gives you full control, but you take on:

- Raw mode setup and teardown on every exit path.
- Input reading, buffering, and parsing.
- Resize detection (SIGWINCH on POSIX, polling on Windows).
- Coordinating async work with the render loop.

If you need all of that, `glym.Program` handles it for you. See the
[first-app guide](first-app.md) to get started with the runtime.
