# Your first glym app

This guide walks through building a minimal interactive counter in under
50 lines. By the end you will have a working TUI that responds to
keyboard input, redraws efficiently, and exits cleanly.

## Prerequisites

- Zig 0.15.x stable.
- glym added as a dependency in your `build.zig.zon`.

## The counter

Create `src/main.zig` and paste the following:

```zig
const std = @import("std");
const glym = @import("glym");

const Model = struct { count: i32 = 0 };
const App = union(enum) {};
const P = glym.Program(Model, App);

fn init(_: std.mem.Allocator) anyerror!Model {
    return .{};
}

fn update(model: *Model, m: P.Msg) P.Cmd {
    switch (m) {
        .key => |k| switch (k.code) {
            .arrow_up => model.count += 1,
            .arrow_down => model.count -= 1,
            .char => |c| {
                if (c == 'q') return .quit;
                if (c == 'c' and k.modifiers.ctrl) return .quit;
            },
            else => {},
        },
        else => {},
    }
    return .none;
}

const pink: glym.style.Rgb = .{ .r = 255, .g = 107, .b = 157 };
const cyan: glym.style.Rgb = .{ .r = 91, .g = 206, .b = 247 };

fn view(model: *Model, r: *P.Renderer) void {
    var buf: [64]u8 = undefined;
    const line = std.fmt.bufPrint(&buf, "Counter: {d}", .{model.count}) catch return;
    r.writeGradientText(1, 2, line, pink, cyan, .{ .bold = true });
    r.writeStyledText(3, 2, "up/down to change, q to quit", .{ .fg = .{ .indexed = 8 } });
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const program: P = .{
        .allocator = gpa.allocator(),
        .init_fn = init,
        .update_fn = update,
        .view_fn = view,
    };
    try program.run();
}
```

That is 54 lines including the file header. Here is what each piece does.

## Breakdown

### Model

```zig
const Model = struct { count: i32 = 0 };
```

A plain struct holding your application state. No traits, no interfaces,
just data. The runtime never inspects it - it only passes it to your
functions.

### AppMsg

```zig
const App = union(enum) {};
```

Your custom message type. The counter does not need any app-level messages
(it reacts to keys directly), so this is an empty union. A more complex
app would add variants like `data_loaded`, `timer_tick`, etc.

### Program

```zig
const P = glym.Program(Model, App);
```

`Program` is a comptime-generic type parameterized over your `Model` and
`AppMsg`. It generates the concrete `Msg`, `Cmd` and `Renderer` types
that your functions use.

### init

```zig
fn init(_: std.mem.Allocator) anyerror!Model {
    return .{};
}
```

Called once when the program starts. It receives an allocator for anything
the model needs to own. The counter has no heap state, so the allocator
is unused.

### update

```zig
fn update(model: *Model, m: P.Msg) P.Cmd {
    // ...
    return .none;
}
```

Called every time a message arrives. `P.Msg` is a tagged union with
variants `key`, `resize`, `quit` and `app`. Mutate the model, then
return a command:

- `.none` - do nothing, just redraw.
- `.quit` - exit the program cleanly.
- `.custom` - run a synchronous function inline on the main loop.
- `.async_task` - dispatch a function to a worker pool off the main loop.

### view

```zig
fn view(model: *Model, r: *P.Renderer) void {
    // write into the renderer
}
```

Called after every update. Write into the renderer's back buffer using
helpers like `writeText`, `writeStyledText`, `writeGradientText`,
`fillRect`, `drawBorder`, etc. The runtime clears the buffer before
calling `view` and diffs it against the previous frame automatically -
you always describe the full screen, not incremental patches.

### main

```zig
const program: P = .{
    .allocator = gpa.allocator(),
    .init_fn = init,
    .update_fn = update,
    .view_fn = view,
};
try program.run();
```

Construct the program with your four function pointers and call `run()`.
The runtime handles raw mode, the alt screen, the cursor, input parsing,
resize detection, and cleanup on exit. You can optionally set `deinit_fn`
to clean up model resources and `color_level` to override terminal color
detection.

## Running it

```sh
zig build run-counter
```

Press up/down arrows to change the count, `q` or ctrl+c to quit.

## Next steps

- Add a `deinit_fn` when your model allocates (see the input example).
- Use `Cmd.custom` to run side effects that produce follow-up messages.
- Use `Cmd.async_task` for slow operations (network, disk) that should
  not block the input loop.
- Read [architecture.md](../architecture.md) for the full layer breakdown.
