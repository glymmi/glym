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

/// The output of a successful `parse` call: the decoded key and how many
/// bytes were consumed from the input slice.
pub const ParseResult = struct {
    key: Key,
    consumed: usize,
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
        '\r', '\n' => return .{ .key = .{ .code = .enter }, .consumed = 1 },
        '\t' => return .{ .key = .{ .code = .tab }, .consumed = 1 },
        0x7f, 0x08 => return .{ .key = .{ .code = .backspace }, .consumed = 1 },
        else => {},
    }

    if (b >= 0x01 and b <= 0x1a) {
        const letter: u21 = @as(u21, b) + ('a' - 1);
        return .{
            .key = .{ .code = .{ .char = letter }, .modifiers = .{ .ctrl = true } },
            .consumed = 1,
        };
    }

    if (b < 0x80) {
        return .{ .key = .{ .code = .{ .char = b } }, .consumed = 1 };
    }

    const len = std.unicode.utf8ByteSequenceLength(b) catch return null;
    if (bytes.len < len) return null;
    const cp = std.unicode.utf8Decode(bytes[0..len]) catch return null;
    return .{ .key = .{ .code = .{ .char = cp } }, .consumed = len };
}

fn parseEscape(bytes: []const u8) ?ParseResult {
    if (bytes.len == 1) return .{ .key = .{ .code = .escape }, .consumed = 1 };
    const second = bytes[1];
    if (second == '[') return parseCsi(bytes);
    if (second == 'O') return parseSs3(bytes);

    const inner = parse(bytes[1..]) orelse return loneEscape();
    var key = inner.key;
    key.modifiers.alt = true;
    return .{ .key = key, .consumed = 1 + inner.consumed };
}

fn parseCsi(bytes: []const u8) ?ParseResult {
    if (bytes.len < 3) return null;
    const third = bytes[2];

    if (finalLetterToCode(third)) |code| {
        return .{ .key = .{ .code = code }, .consumed = 3 };
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
        return .{ .key = .{ .code = code, .modifiers = modifiers }, .consumed = i + 1 };
    }

    if (final == '~') {
        const code = numericToCode(first_num) orelse return loneEscape();
        return .{ .key = .{ .code = code, .modifiers = modifiers }, .consumed = i + 1 };
    }

    return loneEscape();
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
    return .{ .key = .{ .code = code }, .consumed = 3 };
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
    return .{ .key = .{ .code = .escape }, .consumed = 1 };
}

test "empty input returns null" {
    try std.testing.expect(parse("") == null);
}

test "lowercase ascii letter" {
    const r = parse("a").?;
    try std.testing.expectEqual(@as(usize, 1), r.consumed);
    try std.testing.expectEqual(@as(u21, 'a'), r.key.code.char);
    try std.testing.expect(!r.key.modifiers.ctrl);
}

test "uppercase ascii letter has no shift modifier set" {
    const r = parse("A").?;
    try std.testing.expectEqual(@as(u21, 'A'), r.key.code.char);
    try std.testing.expect(!r.key.modifiers.shift);
}

test "carriage return is enter" {
    const r = parse("\r").?;
    try std.testing.expectEqual(KeyCode.enter, r.key.code);
}

test "line feed is enter" {
    const r = parse("\n").?;
    try std.testing.expectEqual(KeyCode.enter, r.key.code);
}

test "tab" {
    const r = parse("\t").?;
    try std.testing.expectEqual(KeyCode.tab, r.key.code);
}

test "backspace from 0x7f" {
    const r = parse("\x7f").?;
    try std.testing.expectEqual(KeyCode.backspace, r.key.code);
}

test "backspace from 0x08" {
    const r = parse("\x08").?;
    try std.testing.expectEqual(KeyCode.backspace, r.key.code);
}

test "lone escape" {
    const r = parse("\x1b").?;
    try std.testing.expectEqual(KeyCode.escape, r.key.code);
    try std.testing.expectEqual(@as(usize, 1), r.consumed);
}

test "ctrl a" {
    const r = parse("\x01").?;
    try std.testing.expectEqual(@as(u21, 'a'), r.key.code.char);
    try std.testing.expect(r.key.modifiers.ctrl);
}

test "ctrl z" {
    const r = parse("\x1a").?;
    try std.testing.expectEqual(@as(u21, 'z'), r.key.code.char);
    try std.testing.expect(r.key.modifiers.ctrl);
}

test "utf8 two byte codepoint" {
    const r = parse("é").?;
    try std.testing.expectEqual(@as(usize, 2), r.consumed);
    try std.testing.expectEqual(@as(u21, 0x00e9), r.key.code.char);
}

test "utf8 four byte emoji" {
    const r = parse("🌟").?;
    try std.testing.expectEqual(@as(usize, 4), r.consumed);
    try std.testing.expectEqual(@as(u21, 0x1f31f), r.key.code.char);
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
    try std.testing.expectEqual(@as(u21, 'a'), r.key.code.char);
}

test "csi arrow up" {
    const r = parse("\x1b[A").?;
    try std.testing.expectEqual(KeyCode.arrow_up, r.key.code);
    try std.testing.expectEqual(@as(usize, 3), r.consumed);
}

test "csi arrow down" {
    const r = parse("\x1b[B").?;
    try std.testing.expectEqual(KeyCode.arrow_down, r.key.code);
}

test "csi arrow right" {
    const r = parse("\x1b[C").?;
    try std.testing.expectEqual(KeyCode.arrow_right, r.key.code);
}

test "csi arrow left" {
    const r = parse("\x1b[D").?;
    try std.testing.expectEqual(KeyCode.arrow_left, r.key.code);
}

test "csi home and end" {
    try std.testing.expectEqual(KeyCode.home, parse("\x1b[H").?.key.code);
    try std.testing.expectEqual(KeyCode.end, parse("\x1b[F").?.key.code);
}

test "csi insert delete page" {
    try std.testing.expectEqual(KeyCode.insert, parse("\x1b[2~").?.key.code);
    try std.testing.expectEqual(KeyCode.delete, parse("\x1b[3~").?.key.code);
    try std.testing.expectEqual(KeyCode.page_up, parse("\x1b[5~").?.key.code);
    try std.testing.expectEqual(KeyCode.page_down, parse("\x1b[6~").?.key.code);
}

test "csi numeric home and end variants" {
    try std.testing.expectEqual(KeyCode.home, parse("\x1b[1~").?.key.code);
    try std.testing.expectEqual(KeyCode.home, parse("\x1b[7~").?.key.code);
    try std.testing.expectEqual(KeyCode.end, parse("\x1b[4~").?.key.code);
    try std.testing.expectEqual(KeyCode.end, parse("\x1b[8~").?.key.code);
}

test "csi function keys f5 to f12" {
    try std.testing.expectEqual(@as(u8, 5), parse("\x1b[15~").?.key.code.f);
    try std.testing.expectEqual(@as(u8, 6), parse("\x1b[17~").?.key.code.f);
    try std.testing.expectEqual(@as(u8, 7), parse("\x1b[18~").?.key.code.f);
    try std.testing.expectEqual(@as(u8, 8), parse("\x1b[19~").?.key.code.f);
    try std.testing.expectEqual(@as(u8, 9), parse("\x1b[20~").?.key.code.f);
    try std.testing.expectEqual(@as(u8, 10), parse("\x1b[21~").?.key.code.f);
    try std.testing.expectEqual(@as(u8, 11), parse("\x1b[23~").?.key.code.f);
    try std.testing.expectEqual(@as(u8, 12), parse("\x1b[24~").?.key.code.f);
}

test "ss3 function keys f1 to f4" {
    try std.testing.expectEqual(@as(u8, 1), parse("\x1bOP").?.key.code.f);
    try std.testing.expectEqual(@as(u8, 2), parse("\x1bOQ").?.key.code.f);
    try std.testing.expectEqual(@as(u8, 3), parse("\x1bOR").?.key.code.f);
    try std.testing.expectEqual(@as(u8, 4), parse("\x1bOS").?.key.code.f);
}

test "ss3 arrow keys" {
    try std.testing.expectEqual(KeyCode.arrow_up, parse("\x1bOA").?.key.code);
    try std.testing.expectEqual(KeyCode.arrow_down, parse("\x1bOB").?.key.code);
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
    try std.testing.expectEqual(KeyCode.escape, r.key.code);
    try std.testing.expectEqual(@as(usize, 1), r.consumed);
}

test "unknown numeric csi yields lone escape" {
    const r = parse("\x1b[99~").?;
    try std.testing.expectEqual(KeyCode.escape, r.key.code);
    try std.testing.expectEqual(@as(usize, 1), r.consumed);
}

test "csi shift arrow right" {
    const r = parse("\x1b[1;2C").?;
    try std.testing.expectEqual(KeyCode.arrow_right, r.key.code);
    try std.testing.expect(r.key.modifiers.shift);
    try std.testing.expect(!r.key.modifiers.ctrl);
    try std.testing.expect(!r.key.modifiers.alt);
}

test "csi alt arrow left" {
    const r = parse("\x1b[1;3D").?;
    try std.testing.expectEqual(KeyCode.arrow_left, r.key.code);
    try std.testing.expect(r.key.modifiers.alt);
    try std.testing.expect(!r.key.modifiers.shift);
    try std.testing.expect(!r.key.modifiers.ctrl);
}

test "csi ctrl arrow up" {
    const r = parse("\x1b[1;5A").?;
    try std.testing.expectEqual(KeyCode.arrow_up, r.key.code);
    try std.testing.expect(r.key.modifiers.ctrl);
}

test "csi shift ctrl arrow down" {
    const r = parse("\x1b[1;6B").?;
    try std.testing.expectEqual(KeyCode.arrow_down, r.key.code);
    try std.testing.expect(r.key.modifiers.shift);
    try std.testing.expect(r.key.modifiers.ctrl);
}

test "csi all modifiers arrow right" {
    const r = parse("\x1b[1;8C").?;
    try std.testing.expectEqual(KeyCode.arrow_right, r.key.code);
    try std.testing.expect(r.key.modifiers.shift);
    try std.testing.expect(r.key.modifiers.alt);
    try std.testing.expect(r.key.modifiers.ctrl);
}

test "csi modifier 1 means no modifier" {
    const r = parse("\x1b[1;1A").?;
    try std.testing.expectEqual(KeyCode.arrow_up, r.key.code);
    try std.testing.expect(!r.key.modifiers.shift);
    try std.testing.expect(!r.key.modifiers.alt);
    try std.testing.expect(!r.key.modifiers.ctrl);
}

test "csi ctrl delete" {
    const r = parse("\x1b[3;5~").?;
    try std.testing.expectEqual(KeyCode.delete, r.key.code);
    try std.testing.expect(r.key.modifiers.ctrl);
}

test "csi shift f5" {
    const r = parse("\x1b[15;2~").?;
    try std.testing.expectEqual(@as(u8, 5), r.key.code.f);
    try std.testing.expect(r.key.modifiers.shift);
}

test "csi modified home" {
    const r = parse("\x1b[1;5H").?;
    try std.testing.expectEqual(KeyCode.home, r.key.code);
    try std.testing.expect(r.key.modifiers.ctrl);
}

test "alt plus letter" {
    const r = parse("\x1ba").?;
    try std.testing.expectEqual(@as(u21, 'a'), r.key.code.char);
    try std.testing.expect(r.key.modifiers.alt);
    try std.testing.expectEqual(@as(usize, 2), r.consumed);
}

test "alt plus uppercase letter" {
    const r = parse("\x1bX").?;
    try std.testing.expectEqual(@as(u21, 'X'), r.key.code.char);
    try std.testing.expect(r.key.modifiers.alt);
}

test "alt plus enter" {
    const r = parse("\x1b\r").?;
    try std.testing.expectEqual(KeyCode.enter, r.key.code);
    try std.testing.expect(r.key.modifiers.alt);
}

test "incomplete modified csi returns null" {
    try std.testing.expect(parse("\x1b[1;") == null);
    try std.testing.expect(parse("\x1b[1;5") == null);
}
