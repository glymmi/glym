# Building a custom widget

Widgets are reusable UI components that handle input and render themselves
into a `Renderer`. This guide documents the contract every widget follows
and walks through building a simple toggle widget from scratch.

## The widget contract

Every widget is a struct with four entry points:

```zig
pub const MyWidget = struct {
    // fields: internal state

    pub fn init(allocator: std.mem.Allocator) !MyWidget { ... }
    pub fn deinit(self: *MyWidget, allocator: std.mem.Allocator) void { ... }
    pub fn handleKey(self: *MyWidget, key: glym.input.Key) !bool { ... }
    pub fn view(self: *MyWidget, r: *Renderer, row: u16, col: u16, width: u16, style: Style) void { ... }
};
```

### init

Takes an explicit allocator and returns the widget in its initial state.
If the widget needs heap memory (dynamic lists, text buffers), allocate
it here. Widgets that have no heap state can ignore the allocator.

### deinit

Frees everything `init` allocated. Receives the same allocator.

### handleKey

Receives a `glym.input.Key` (a `KeyCode` plus `Modifiers`). Mutates the
widget state as needed and returns `true` when the key was consumed,
`false` otherwise. The host application uses the return value to decide
whether to propagate the key to other widgets or to its own `update`.

### view

Renders the widget into the renderer's back buffer at the rectangle
defined by `(row, col, width)`. Rules:

- **Widgets do not own their position.** The caller decides where the
  widget sits. Never store row/col as widget state.
- **Render exactly `width` cells.** Pad with spaces if the content is
  shorter, truncate if it is longer. This keeps the layout predictable.
- **Use `applyCell` or `writeStyledText` instead of `setCell`** when you
  want the widget to layer on top of an existing background (panels,
  borders). Fields left at their default inherit from the cell underneath.

## Worked example: a toggle

A labeled boolean toggle. Space flips it. Renders as `[x] label` or
`[ ] label`.

```zig
const std = @import("std");
const glym = @import("glym");
const Renderer = glym.renderer.Renderer;
const Style = glym.style.Style;

pub const Toggle = struct {
    label: []const u8,
    on: bool,

    pub fn init(label: []const u8) Toggle {
        return .{ .label = label, .on = false };
    }

    pub fn handleKey(self: *Toggle, key: glym.input.Key) !bool {
        if (key.code == .char and key.code.char == ' ') {
            self.on = !self.on;
            return true;
        }
        return false;
    }

    pub fn view(self: *Toggle, r: *Renderer, row: u16, col: u16, width: u16, style: Style) void {
        const mark: u21 = if (self.on) 'x' else ' ';
        // "[x] " prefix = 4 cells
        r.applyCell(row, col, '[', style);
        r.applyCell(row, col + 1, mark, style);
        r.applyCell(row, col + 2, ']', style);
        r.applyCell(row, col + 3, ' ', style);

        // Label, truncated to remaining width.
        const label_start = col + 4;
        if (label_start >= col +| width) return;
        const max_label: u16 = (col +| width) - label_start;
        var c: u16 = 0;
        var i: usize = 0;
        while (i < self.label.len and c < max_label) {
            const len = std.unicode.utf8ByteSequenceLength(self.label[i]) catch return;
            if (i + len > self.label.len) return;
            const cp = std.unicode.utf8Decode(self.label[i .. i + len]) catch return;
            r.applyCell(row, label_start + c, cp, style);
            c += 1;
            i += len;
        }
        // Pad remaining cells.
        while (c < max_label) : (c += 1) {
            r.applyCell(row, label_start + c, ' ', style);
        }
    }
};
```

This toggle has no heap state, so `init` does not take an allocator and
there is no `deinit`. That is fine - the contract only requires them when
the widget allocates.

## Using it in a program

Wire the widget into your model and delegate keys in `update`:

```zig
const Model = struct {
    toggle: Toggle,
};

fn init(_: std.mem.Allocator) anyerror!Model {
    return .{ .toggle = Toggle.init("Dark mode") };
}

fn update(model: *Model, m: P.Msg) P.Cmd {
    switch (m) {
        .key => |k| {
            _ = model.toggle.handleKey(k) catch {};
            if (k.code == .char and k.code.char == 'q') return .quit;
        },
        else => {},
    }
    return .none;
}

fn view(model: *Model, r: *P.Renderer) void {
    model.toggle.view(r, 1, 2, 30, .{});
}
```

## Testing

Test the pure logic with a real `Renderer` instance from
`std.testing.allocator`. No mocking needed.

```zig
test "space toggles on" {
    var t = Toggle.init("test");
    _ = try t.handleKey(.{ .code = .{ .char = ' ' } });
    try std.testing.expect(t.on);
}

test "unhandled key returns false" {
    var t = Toggle.init("test");
    const consumed = try t.handleKey(.{ .code = .{ .char = 'x' } });
    try std.testing.expect(!consumed);
}

test "view renders the mark" {
    var r = try glym.renderer.Renderer.init(std.testing.allocator, 1, 20);
    defer r.deinit();
    var t = Toggle.init("hi");
    t.on = true;
    t.view(&r, 0, 0, 10, .{});
    try std.testing.expectEqual(@as(u21, 'x'), r.back[1].char);
}
```

## Checklist

- `init` takes an explicit allocator (or no allocator if there is no
  heap state).
- `deinit` frees everything `init` allocated.
- `handleKey` returns `!bool`.
- `view` takes `(row, col, width, style)` and renders exactly `width`
  cells.
- Tests cover key handling and rendered output against a real `Renderer`.
