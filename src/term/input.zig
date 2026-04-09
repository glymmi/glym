//! Terminal input parser.
//!
//! Decodes raw bytes coming from a terminal into structured Key events.
//! This file currently handles ASCII, ctrl+letter, the basic control keys
//! (enter, tab, backspace, escape) and UTF-8 codepoints. Special keys,
//! modifiers and mouse events land in later commits.

const std = @import("std");

pub const Modifiers = packed struct {
    shift: bool = false,
    ctrl: bool = false,
    alt: bool = false,
};

pub const KeyCode = union(enum) {
    char: u21,
    enter,
    tab,
    backspace,
    escape,
};

pub const Key = struct {
    code: KeyCode,
    modifiers: Modifiers = .{},
};

pub const ParseResult = struct {
    key: Key,
    consumed: usize,
};

/// Parse the next key from a byte slice. Returns null when the slice is
/// empty, when more bytes are needed to complete a UTF-8 codepoint, or when
/// the input is invalid.
pub fn parse(bytes: []const u8) ?ParseResult {
    if (bytes.len == 0) return null;
    const b = bytes[0];

    switch (b) {
        '\r', '\n' => return .{ .key = .{ .code = .enter }, .consumed = 1 },
        '\t' => return .{ .key = .{ .code = .tab }, .consumed = 1 },
        0x7f, 0x08 => return .{ .key = .{ .code = .backspace }, .consumed = 1 },
        0x1b => return .{ .key = .{ .code = .escape }, .consumed = 1 },
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
