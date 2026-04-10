# Architecture

glym is a TUI library for Zig built around the Model-View-Update (MVU)
pattern. It owns its full stack from raw terminal control to a high-level
runtime, organized as independent layers that can be used together or
separately.

## Layers

```
program.zig      MVU runtime (top level)
  |
  +-- msg.zig          message types (key, resize, quit, app)
  +-- cmd.zig          command types (none, quit, custom, async_task)
  +-- renderer.zig     double-buffered screen renderer
  |     +-- style.zig  re-exports from shimmer (Style, Color, Rgb, Border)
  +-- term/
        +-- input.zig  byte-to-key parser
        +-- raw.zig    raw mode toggle (termios on POSIX, console on Windows)
        +-- size.zig   terminal size via ioctl / GetConsoleScreenBufferInfo
        +-- ansi.zig   escape sequence constants and helpers
```

Dependencies flow strictly downward. `term/` knows nothing about the
renderer or the runtime. `renderer.zig` uses `style.zig` for cell
attributes but does not depend on `program.zig`. `msg.zig` and `cmd.zig`
only depend on `term/input.zig` and `term/size.zig` for their payload
types.

### term/

Low-level terminal primitives. Each file is self-contained:

- **ansi.zig** - escape sequence constants (`clear_screen`, `hide_cursor`,
  `enter_alt_screen`, `reset`) and a `moveCursor` allocating helper.
- **raw.zig** - `RawMode` struct that captures the original terminal state
  on `enable` and restores it on `disable`. POSIX path uses `tcgetattr` /
  `tcsetattr`; Windows path uses `GetConsoleMode` / `SetConsoleMode`.
  Pure helpers `posixRawFlags` and `windowsRawFlags` are exposed for
  testing and composition.
- **input.zig** - `parse(bytes) -> ?ParseResult` decodes one key from a
  byte slice. Handles ASCII, ctrl+letter, UTF-8 codepoints, CSI/SS3
  escape sequences, arrows, function keys, navigation keys, and
  modifier-aware variants (shift, alt, ctrl). Returns the decoded `Key`
  and how many bytes were consumed. Returns `null` when more bytes are
  needed. Unknown sequences yield a lone escape consuming one byte so
  the caller can resync.
- **size.zig** - `get(handle) -> Size` reads the terminal dimensions.
  POSIX uses `TIOCGWINSZ` (value differs by OS). Windows uses
  `GetConsoleScreenBufferInfo`.

### style.zig

Re-exports `Style`, `Color`, `Rgb`, `ColorLevel` and `Border` from
the shimmer package so glym apps write `glym.style.Style{ .bold = true }`
without depending on shimmer directly. Also exposes `color` (lerp and
conversion helpers) and `palette` (Catppuccin Mocha constants).

### renderer.zig

Double-buffered screen renderer. Owns a `front` buffer (what is on
screen) and a `back` buffer (what the view wants). The view writes into
`back` through helpers like `setCell`, `writeText`, `writeStyledText`,
`writeGradientText`, `fillRect`, `writeCenteredText`, `drawBorder` and
`drawBorderTitled`. When the frame is done, `flush` diffs `front` against
`back` cell by cell and emits only the escape sequences needed to
reconcile the two:

1. Walk every `(row, col)` position.
2. Skip cells where `back[idx].char == front[idx].char` and the styles
   match (`Style.eql`).
3. For each changed cell, emit a cursor-move escape (`\x1b[row;colH`),
   then the SGR style sequence (only if the style changed since the last
   emitted cell), then the UTF-8 encoded codepoint.
4. Copy `back[idx]` into `front[idx]` so the next flush sees the current
   screen state.

The `front` buffer initializes with `char = 0` (a sentinel that never
matches a real character), so the very first flush paints every visible
cell. The `back` buffer initializes with spaces.

**Hot-path constraints:** `flush` never allocates. Cursor-move sequences
use a 32-byte stack buffer, style sequences use a 64-byte stack buffer,
and UTF-8 encoding uses a 4-byte buffer. The output bytes accumulate in
an `ArrayList(u8)` that is cleared (retaining capacity) at the start of
each flush.

`applyCell` layers a new character and style on top of whatever is already
in the back buffer: any field left at its default (fg/bg = `.default`,
attributes = `false`) inherits from the existing cell. This lets borders
drawn over a filled rectangle keep the rectangle's background, and text
written on top of a panel pick up the panel color.

### msg.zig / cmd.zig

Generic tagged unions parameterized over the user's `AppMsg` type:

- `Msg(AppMsg)` wraps `key` (an `input.Key`), `resize` (a `size.Size`),
  `quit`, and `app` (the user's own message).
- `Cmd(AppMsg)` wraps `none`, `quit`, `custom` (a synchronous function
  that runs inline on the main loop) and `async_task` (a function
  dispatched to a worker pool). Both `custom` and `async_task` may
  return an optional follow-up `AppMsg` that the runtime feeds back into
  `update`.

### program.zig

The MVU runtime. `Program(Model, AppMsg)` is a comptime-generic struct
that the user constructs with four function pointers:

- `init_fn(allocator) -> !Model` - create the initial model.
- `update_fn(*Model, Msg) -> Cmd` - handle a message, mutate the model,
  return a command.
- `view_fn(*Model, *Renderer)` - write the current model state into the
  renderer's back buffer.
- `deinit_fn(*Model, allocator)` (optional) - free model resources on
  exit.

`run()` does the following:

1. Enable raw mode, enter the alt screen, hide the cursor.
2. Install a `SIGWINCH` handler (POSIX) that writes to a self-pipe so
   the read loop wakes on resize without waiting for a keypress.
3. Initialize an async runner (thread pool + result queue + self-pipe
   wakeup) on supported platforms.
4. Query terminal size, create the renderer, call `init_fn`, render the
   first frame.
5. Enter the main loop:
   - `poll` on stdin, the resize pipe and the async-result pipe.
   - On input: read bytes, feed them to `input.parse` in a loop, call
     `update` for each decoded key, run the returned command.
   - On async result: drain the result queue, feed each `AppMsg` back
     through `update`.
   - On resize signal: query the new size, call `renderer.resize`, send
     a `resize` message through `update`.
   - After processing events: `clear` the back buffer, call `view_fn`,
     `flush` the diff to the terminal.
6. On exit (quit command, read error, or propagated error): restore cursor,
   leave alt screen, disable raw mode, call `deinit_fn`. Every exit path
   is covered by `defer` blocks.

`step(model, msg)` is exposed publicly so tests can drive the runtime
without a real terminal. When called outside `run`, async tasks execute
inline (no pool).

Windows support: the read path uses `ReadFile` (blocking), resize is
polled every iteration instead of signal-driven, and async tasks run
inline until the input pipeline switches to `ReadConsoleInput`.

## Writing a custom widget

Widgets in the glym ecosystem (shipped via the `spark` package) follow a
consistent shape:

```zig
pub const MyWidget = struct {
    // internal state, allocated in init

    pub fn init(allocator: std.mem.Allocator) !MyWidget {
        // allocate and return
    }

    pub fn deinit(self: *MyWidget, allocator: std.mem.Allocator) void {
        // free resources
    }

    pub fn handleKey(self: *MyWidget, key: glym.input.Key) !bool {
        // mutate state, return true if the key was consumed
    }

    pub fn view(self: *MyWidget, r: *glym.renderer.Renderer, row: u16, col: u16, width: u16, style: glym.style.Style) void {
        // write into the renderer at the given rectangle
    }
};
```

Key rules:

- **Widgets do not own their position.** The caller passes `row`, `col`
  and `width` into `view`. Widgets never store layout state.
- **`handleKey` returns `!bool`.** Return `true` when the key was
  consumed so the host can decide whether to propagate it.
- **Allocators are explicit.** `init` takes an allocator, and methods
  that need allocation receive it as a parameter.
- **Render exactly `width` cells.** Pad with spaces if the content is
  shorter. Truncate if it is longer.
- **Tests cover pure logic.** Test key handling and state transitions
  with a real `Renderer` instance (allocated with `testing.allocator`),
  not by mocking.
