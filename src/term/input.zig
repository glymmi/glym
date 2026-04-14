//! Terminal input parser.
//!
//! Decodes raw bytes coming from a terminal into structured Key events.
//! Handles ASCII, ctrl+letter, basic control keys, UTF-8 codepoints, the
//! common CSI/SS3 escape sequences for arrows, navigation and F1 through
//! F12, modifier-aware sequences (Shift/Alt/Ctrl) and Alt+key combos.

const std = @import("std");

/// Modifier keys that may accompany a key press.
pub const Modifiers = packed struct {
    shift: bool = false,
    ctrl: bool = false,
    alt: bool = false,
};

/// The logical identity of a key press.
pub const KeyCode = union(enum) {
    char: u21,
    enter,
    tab,
    backspace,
    escape,
    arrow_up,
    arrow_down,
    arrow_left,
    arrow_right,
    home,
    end,
    page_up,
    page_down,
    insert,
    delete,
    f: u8,
};

/// A fully decoded key event: a `KeyCode` plus any active `Modifiers`.
pub const Key = struct {
    code: KeyCode,
    modifiers: Modifiers = .{},
};

/// Mouse button identifiers.
pub const MouseButton = enum(u8) {
    left = 0,
    middle = 1,
    right = 2,
    scroll_up = 64,
    scroll_down = 65,
    none = 3,
};

/// Mouse event with button, position and press/release state.
pub const MouseEvent = struct {
    button: MouseButton,
    row: u16,
    col: u16,
    pressed: bool,
};

/// Parsed input event: either a key press or a mouse action.
pub const Event = union(enum) {
    key: Key,
    mouse: MouseEvent,
};

/// The output of a successful `parse` call: the decoded event and how many
/// bytes were consumed from the input slice.
pub const ParseResult = struct {
    event: Event,
    consumed: usize,

    /// Convenience accessor for key events (backwards compat).
    pub fn key(self: ParseResult) ?Key {
        return switch (self.event) {
            .key => |k| k,
            else => null,
        };
    }
};

/// Parse the next key from a byte slice. Returns null when more bytes are
/// needed to complete the current sequence. Unknown or malformed escape
/// sequences yield a lone escape and consume only the ESC byte so the
/// caller can resync on the next call.
pub fn parse(bytes: []const u8) ?ParseResult {
    if (bytes.len == 0) return null;
    const b = bytes[0];

    if (b == 0x1b) return parseEscape(bytes);

    switch (b) {
        '\r', '\n' => return .{ .event = .{ .key = .{ .code = .enter } }, .consumed = 1 },
        '\t' => return .{ .event = .{ .key = .{ .code = .tab } }, .consumed = 1 },
        0x7f, 0x08 => return .{ .event = .{ .key = .{ .code = .backspace } }, .consumed = 1 },
        else => {},
    }

    if (b >= 0x01 and b <= 0x1a) {
        const letter: u21 = @as(u21, b) + ('a' - 1);
        return .{
            .event = .{ .key = .{ .code = .{ .char = letter }, .modifiers = .{ .ctrl = true } } },
            .consumed = 1,
        };
    }

    if (b < 0x80) {
        return .{ .event = .{ .key = .{ .code = .{ .char = b } } }, .consumed = 1 };
    }

    const len = std.unicode.utf8ByteSequenceLength(b) catch return null;
    if (bytes.len < len) return null;
    const cp = std.unicode.utf8Decode(bytes[0..len]) catch return null;
    return .{ .event = .{ .key = .{ .code = .{ .char = cp } } }, .consumed = len };
}

fn parseEscape(bytes: []const u8) ?ParseResult {
    if (bytes.len == 1) return .{ .event = .{ .key = .{ .code = .escape } }, .consumed = 1 };
    const second = bytes[1];
    if (second == '[') return parseCsi(bytes);
    if (second == 'O') return parseSs3(bytes);

    const inner = parse(bytes[1..]) orelse return loneEscape();
    var k = inner.key() orelse return loneEscape();
    k.modifiers.alt = true;
    return .{ .event = .{ .key = k }, .consumed = 1 + inner.consumed };
}

fn parseCsi(bytes: []const u8) ?ParseResult {
    if (bytes.len < 3) return null;
    const third = bytes[2];

    // SGR mouse: ESC [ < btn ; col ; row M/m
    if (third == '<') return parseSgrMouse(bytes);

    if (finalLetterToCode(third)) |code| {
        return .{ .event = .{ .key = .{ .code = code } }, .consumed = 3 };
    }

    if (third < '0' or third > '9') return loneEscape();

    var i: usize = 2;
    while (i < bytes.len and bytes[i] >= '0' and bytes[i] <= '9') : (i += 1) {}
    if (i >= bytes.len) return null;
    const first_num = std.fmt.parseInt(u32, bytes[2..i], 10) catch return loneEscape();

    var modifiers: Modifiers = .{};
    if (bytes[i] == ';') {
        const start = i + 1;
        i = start;
        while (i < bytes.len and bytes[i] >= '0' and bytes[i] <= '9') : (i += 1) {}
        if (i >= bytes.len) return null;
        if (i == start) return loneEscape();
        const mod_num = std.fmt.parseInt(u32, bytes[start..i], 10) catch return loneEscape();
        modifiers = decodeModifiers(mod_num);
    }

    const final = bytes[i];

    if (finalLetterToCode(final)) |code| {
        if (first_num != 1) return loneEscape();
        return .{ .event = .{ .key = .{ .code = code, .modifiers = modifiers } }, .consumed = i + 1 };
    }

    if (final == '~') {
        const code = numericToCode(first_num) orelse return loneEscape();
        return .{ .event = .{ .key = .{ .code = code, .modifiers = modifiers } }, .consumed = i + 1 };
    }

    return loneEscape();
}

fn parseSgrMouse(bytes: []const u8) ?ParseResult {
    // ESC [ < btn ; col ; row M/m
    var i: usize = 3;
    while (i < bytes.len and bytes[i] >= '0' and bytes[i] <= '9') : (i += 1) {}
    if (i >= bytes.len) return null;
    const btn_num = std.fmt.parseInt(u8, bytes[3..i], 10) catch return loneEscape();
    if (bytes[i] != ';') return loneEscape();
    i += 1;
    const col_start = i;
    while (i < bytes.len and bytes[i] >= '0' and bytes[i] <= '9') : (i += 1) {}
    if (i >= bytes.len) return null;
    const col_num = std.fmt.parseInt(u16, bytes[col_start..i], 10) catch return loneEscape();
    if (bytes[i] != ';') return loneEscape();
    i += 1;
    const row_start = i;
    while (i < bytes.len and bytes[i] >= '0' and bytes[i] <= '9') : (i += 1) {}
    if (i >= bytes.len) return null;
    const final = bytes[i];
    if (final != 'M' and final != 'm') return loneEscape();
    const row_num = std.fmt.parseInt(u16, bytes[row_start..i], 10) catch return loneEscape();
    const pressed = final == 'M';
    const button: MouseButton = switch (btn_num & 0xC3) {
        0 => .left,
        1 => .middle,
        2 => .right,
        3 => .none,
        64 => .scroll_up,
        65 => .scroll_down,
        else => .none,
    };
    return .{
        .event = .{ .mouse = .{
            .button = button,
            .row = if (row_num > 0) row_num - 1 else 0,
            .col = if (col_num > 0) col_num - 1 else 0,
            .pressed = pressed,
        } },
        .consumed = i + 1,
    };
}

fn parseSs3(bytes: []const u8) ?ParseResult {
    if (bytes.len < 3) return null;
    const code: KeyCode = switch (bytes[2]) {
        'P' => .{ .f = 1 },
        'Q' => .{ .f = 2 },
        'R' => .{ .f = 3 },
        'S' => .{ .f = 4 },
        'H' => .home,
        'F' => .end,
        'A' => .arrow_up,
        'B' => .arrow_down,
        'C' => .arrow_right,
        'D' => .arrow_left,
        else => return loneEscape(),
    };
    return .{ .event = .{ .key = .{ .code = code } }, .consumed = 3 };
}

fn finalLetterToCode(b: u8) ?KeyCode {
    return switch (b) {
        'A' => .arrow_up,
        'B' => .arrow_down,
        'C' => .arrow_right,
        'D' => .arrow_left,
        'H' => .home,
        'F' => .end,
        else => null,
    };
}

fn numericToCode(num: u32) ?KeyCode {
    return switch (num) {
        1, 7 => .home,
        2 => .insert,
        3 => .delete,
        4, 8 => .end,
        5 => .page_up,
        6 => .page_down,
        15 => .{ .f = 5 },
        17 => .{ .f = 6 },
        18 => .{ .f = 7 },
        19 => .{ .f = 8 },
        20 => .{ .f = 9 },
        21 => .{ .f = 10 },
        23 => .{ .f = 11 },
        24 => .{ .f = 12 },
        else => null,
    };
}

fn decodeModifiers(num: u32) Modifiers {
    if (num == 0 or num > 16) return .{};
    const bits = num - 1;
    return .{
        .shift = (bits & 1) != 0,
        .alt = (bits & 2) != 0,
        .ctrl = (bits & 4) != 0,
    };
}

fn loneEscape() ParseResult {
    return .{ .event = .{ .key = .{ .code = .escape } }, .consumed = 1 };
}

test "empty input returns null" {
    try std.testing.expect(parse("") == null);
}

test "lowercase ascii letter" {
    const r = parse("a").?;
    try std.testing.expectEqual(@as(usize, 1), r.consumed);
    try std.testing.expectEqual(@as(u21, 'a'), r.event.key.code.char);
    try std.testing.expect(!r.event.key.modifiers.ctrl);
}

test "uppercase ascii letter has no shift modifier set" {
    const r = parse("A").?;
    try std.testing.expectEqual(@as(u21, 'A'), r.event.key.code.char);
    try std.testing.expect(!r.event.key.modifiers.shift);
}

test "carriage return is enter" {
    const r = parse("\r").?;
    try std.testing.expectEqual(KeyCode.enter, r.event.key.code);
}

test "line feed is enter" {
    const r = parse("\n").?;
    try std.testing.expectEqual(KeyCode.enter, r.event.key.code);
}

test "tab" {
    const r = parse("\t").?;
    try std.testing.expectEqual(KeyCode.tab, r.event.key.code);
}

test "backspace from 0x7f" {
    const r = parse("\x7f").?;
    try std.testing.expectEqual(KeyCode.backspace, r.event.key.code);
}

test "backspace from 0x08" {
    const r = parse("\x08").?;
    try std.testing.expectEqual(KeyCode.backspace, r.event.key.code);
}

test "lone escape" {
    const r = parse("\x1b").?;
    try std.testing.expectEqual(KeyCode.escape, r.event.key.code);
    try std.testing.expectEqual(@as(usize, 1), r.consumed);
}

test "ctrl a" {
    const r = parse("\x01").?;
    try std.testing.expectEqual(@as(u21, 'a'), r.event.key.code.char);
    try std.testing.expect(r.event.key.modifiers.ctrl);
}

test "ctrl z" {
    const r = parse("\x1a").?;
    try std.testing.expectEqual(@as(u21, 'z'), r.event.key.code.char);
    try std.testing.expect(r.event.key.modifiers.ctrl);
}

test "utf8 two byte codepoint" {
    const r = parse("é").?;
    try std.testing.expectEqual(@as(usize, 2), r.consumed);
    try std.testing.expectEqual(@as(u21, 0x00e9), r.event.key.code.char);
}

test "utf8 four byte emoji" {
    const r = parse("🌟").?;
    try std.testing.expectEqual(@as(usize, 4), r.consumed);
    try std.testing.expectEqual(@as(u21, 0x1f31f), r.event.key.code.char);
}

test "incomplete utf8 returns null" {
    try std.testing.expect(parse("\xc3") == null);
}

test "invalid utf8 start byte returns null" {
    try std.testing.expect(parse("\xff") == null);
}

test "consumed only counts the parsed key" {
    const r = parse("ab").?;
    try std.testing.expectEqual(@as(usize, 1), r.consumed);
    try std.testing.expectEqual(@as(u21, 'a'), r.event.key.code.char);
}

test "csi arrow up" {
    const r = parse("\x1b[A").?;
    try std.testing.expectEqual(KeyCode.arrow_up, r.event.key.code);
    try std.testing.expectEqual(@as(usize, 3), r.consumed);
}

test "csi arrow down" {
    const r = parse("\x1b[B").?;
    try std.testing.expectEqual(KeyCode.arrow_down, r.event.key.code);
}

test "csi arrow right" {
    const r = parse("\x1b[C").?;
    try std.testing.expectEqual(KeyCode.arrow_right, r.event.key.code);
}

test "csi arrow left" {
    const r = parse("\x1b[D").?;
    try std.testing.expectEqual(KeyCode.arrow_left, r.event.key.code);
}

test "csi home and end" {
    try std.testing.expectEqual(KeyCode.home, parse("\x1b[H").?.event.key.code);
    try std.testing.expectEqual(KeyCode.end, parse("\x1b[F").?.event.key.code);
}

test "csi insert delete page" {
    try std.testing.expectEqual(KeyCode.insert, parse("\x1b[2~").?.event.key.code);
    try std.testing.expectEqual(KeyCode.delete, parse("\x1b[3~").?.event.key.code);
    try std.testing.expectEqual(KeyCode.page_up, parse("\x1b[5~").?.event.key.code);
    try std.testing.expectEqual(KeyCode.page_down, parse("\x1b[6~").?.event.key.code);
}

test "csi numeric home and end variants" {
    try std.testing.expectEqual(KeyCode.home, parse("\x1b[1~").?.event.key.code);
    try std.testing.expectEqual(KeyCode.home, parse("\x1b[7~").?.event.key.code);
    try std.testing.expectEqual(KeyCode.end, parse("\x1b[4~").?.event.key.code);
    try std.testing.expectEqual(KeyCode.end, parse("\x1b[8~").?.event.key.code);
}

test "csi function keys f5 to f12" {
    try std.testing.expectEqual(@as(u8, 5), parse("\x1b[15~").?.event.key.code.f);
    try std.testing.expectEqual(@as(u8, 6), parse("\x1b[17~").?.event.key.code.f);
    try std.testing.expectEqual(@as(u8, 7), parse("\x1b[18~").?.event.key.code.f);
    try std.testing.expectEqual(@as(u8, 8), parse("\x1b[19~").?.event.key.code.f);
    try std.testing.expectEqual(@as(u8, 9), parse("\x1b[20~").?.event.key.code.f);
    try std.testing.expectEqual(@as(u8, 10), parse("\x1b[21~").?.event.key.code.f);
    try std.testing.expectEqual(@as(u8, 11), parse("\x1b[23~").?.event.key.code.f);
    try std.testing.expectEqual(@as(u8, 12), parse("\x1b[24~").?.event.key.code.f);
}

test "ss3 function keys f1 to f4" {
    try std.testing.expectEqual(@as(u8, 1), parse("\x1bOP").?.event.key.code.f);
    try std.testing.expectEqual(@as(u8, 2), parse("\x1bOQ").?.event.key.code.f);
    try std.testing.expectEqual(@as(u8, 3), parse("\x1bOR").?.event.key.code.f);
    try std.testing.expectEqual(@as(u8, 4), parse("\x1bOS").?.event.key.code.f);
}

test "ss3 arrow keys" {
    try std.testing.expectEqual(KeyCode.arrow_up, parse("\x1bOA").?.event.key.code);
    try std.testing.expectEqual(KeyCode.arrow_down, parse("\x1bOB").?.event.key.code);
}

test "incomplete csi returns null" {
    try std.testing.expect(parse("\x1b[") == null);
    try std.testing.expect(parse("\x1b[1") == null);
    try std.testing.expect(parse("\x1b[15") == null);
}

test "incomplete ss3 returns null" {
    try std.testing.expect(parse("\x1bO") == null);
}

test "unknown csi final yields lone escape" {
    const r = parse("\x1b[Z").?;
    try std.testing.expectEqual(KeyCode.escape, r.event.key.code);
    try std.testing.expectEqual(@as(usize, 1), r.consumed);
}

test "unknown numeric csi yields lone escape" {
    const r = parse("\x1b[99~").?;
    try std.testing.expectEqual(KeyCode.escape, r.event.key.code);
    try std.testing.expectEqual(@as(usize, 1), r.consumed);
}

test "csi shift arrow right" {
    const r = parse("\x1b[1;2C").?;
    try std.testing.expectEqual(KeyCode.arrow_right, r.event.key.code);
    try std.testing.expect(r.event.key.modifiers.shift);
    try std.testing.expect(!r.event.key.modifiers.ctrl);
    try std.testing.expect(!r.event.key.modifiers.alt);
}

test "csi alt arrow left" {
    const r = parse("\x1b[1;3D").?;
    try std.testing.expectEqual(KeyCode.arrow_left, r.event.key.code);
    try std.testing.expect(r.event.key.modifiers.alt);
    try std.testing.expect(!r.event.key.modifiers.shift);
    try std.testing.expect(!r.event.key.modifiers.ctrl);
}

test "csi ctrl arrow up" {
    const r = parse("\x1b[1;5A").?;
    try std.testing.expectEqual(KeyCode.arrow_up, r.event.key.code);
    try std.testing.expect(r.event.key.modifiers.ctrl);
}

test "csi shift ctrl arrow down" {
    const r = parse("\x1b[1;6B").?;
    try std.testing.expectEqual(KeyCode.arrow_down, r.event.key.code);
    try std.testing.expect(r.event.key.modifiers.shift);
    try std.testing.expect(r.event.key.modifiers.ctrl);
}

test "csi all modifiers arrow right" {
    const r = parse("\x1b[1;8C").?;
    try std.testing.expectEqual(KeyCode.arrow_right, r.event.key.code);
    try std.testing.expect(r.event.key.modifiers.shift);
    try std.testing.expect(r.event.key.modifiers.alt);
    try std.testing.expect(r.event.key.modifiers.ctrl);
}

test "csi modifier 1 means no modifier" {
    const r = parse("\x1b[1;1A").?;
    try std.testing.expectEqual(KeyCode.arrow_up, r.event.key.code);
    try std.testing.expect(!r.event.key.modifiers.shift);
    try std.testing.expect(!r.event.key.modifiers.alt);
    try std.testing.expect(!r.event.key.modifiers.ctrl);
}

test "csi ctrl delete" {
    const r = parse("\x1b[3;5~").?;
    try std.testing.expectEqual(KeyCode.delete, r.event.key.code);
    try std.testing.expect(r.event.key.modifiers.ctrl);
}

test "csi shift f5" {
    const r = parse("\x1b[15;2~").?;
    try std.testing.expectEqual(@as(u8, 5), r.event.key.code.f);
    try std.testing.expect(r.event.key.modifiers.shift);
}

test "csi modified home" {
    const r = parse("\x1b[1;5H").?;
    try std.testing.expectEqual(KeyCode.home, r.event.key.code);
    try std.testing.expect(r.event.key.modifiers.ctrl);
}

test "alt plus letter" {
    const r = parse("\x1ba").?;
    try std.testing.expectEqual(@as(u21, 'a'), r.event.key.code.char);
    try std.testing.expect(r.event.key.modifiers.alt);
    try std.testing.expectEqual(@as(usize, 2), r.consumed);
}

test "alt plus uppercase letter" {
    const r = parse("\x1bX").?;
    try std.testing.expectEqual(@as(u21, 'X'), r.event.key.code.char);
    try std.testing.expect(r.event.key.modifiers.alt);
}

test "alt plus enter" {
    const r = parse("\x1b\r").?;
    try std.testing.expectEqual(KeyCode.enter, r.event.key.code);
    try std.testing.expect(r.event.key.modifiers.alt);
}

test "incomplete modified csi returns null" {
    try std.testing.expect(parse("\x1b[1;") == null);
    try std.testing.expect(parse("\x1b[1;5") == null);
}

test "sgr mouse left click" {
    const r = parse("\x1b[<0;10;5M").?;
    try std.testing.expectEqual(MouseButton.left, r.event.mouse.button);
    try std.testing.expectEqual(@as(u16, 4), r.event.mouse.row);
    try std.testing.expectEqual(@as(u16, 9), r.event.mouse.col);
    try std.testing.expect(r.event.mouse.pressed);
}

test "sgr mouse release" {
    const r = parse("\x1b[<0;10;5m").?;
    try std.testing.expectEqual(MouseButton.left, r.event.mouse.button);
    try std.testing.expect(!r.event.mouse.pressed);
}

test "sgr mouse scroll up" {
    const r = parse("\x1b[<64;1;1M").?;
    try std.testing.expectEqual(MouseButton.scroll_up, r.event.mouse.button);
}

test "sgr mouse scroll down" {
    const r = parse("\x1b[<65;1;1M").?;
    try std.testing.expectEqual(MouseButton.scroll_down, r.event.mouse.button);
}

test "incomplete sgr mouse returns null" {
    try std.testing.expect(parse("\x1b[<0;10;5") == null);
    try std.testing.expect(parse("\x1b[<0;10") == null);
    try std.testing.expect(parse("\x1b[<0") == null);
    try std.testing.expect(parse("\x1b[<") == null);
}
