//! Message types for the MVU runtime.
//!
//! `Msg` is a generic tagged union that wraps a few built-in messages from
//! the runtime (key input, terminal resize, quit) together with the user's
//! own application message type. The user defines their AppMsg union, the
//! runtime feeds them a `Msg(AppMsg)` in `update`.

const std = @import("std");
const input = @import("term/input.zig");
const term_size = @import("term/size.zig");

/// Build a message union for the given application message type. The
/// returned tagged union wraps built-in runtime events (`key`, `resize`,
/// `quit`) together with the caller's own `AppMsg`.
pub fn Msg(comptime AppMsg: type) type {
    return union(enum) {
        key: input.Key,
        mouse: input.MouseEvent,
        resize: term_size.Size,
        quit,
        app: AppMsg,
    };
}

test "Msg wraps a key event" {
    const M = Msg(void);
    const m: M = .{ .key = .{ .code = .enter } };
    try std.testing.expect(std.meta.activeTag(m) == .key);
}

test "Msg carries a quit variant" {
    const M = Msg(void);
    const m: M = .quit;
    try std.testing.expect(std.meta.activeTag(m) == .quit);
}

test "Msg carries a resize variant" {
    const M = Msg(void);
    const m: M = .{ .resize = .{ .rows = 24, .cols = 80 } };
    try std.testing.expect(std.meta.activeTag(m) == .resize);
    try std.testing.expectEqual(@as(u16, 24), m.resize.rows);
}

test "Msg wraps an app payload" {
    const App = union(enum) { tick, increment };
    const M = Msg(App);
    const m: M = .{ .app = .increment };
    try std.testing.expect(std.meta.activeTag(m) == .app);
    try std.testing.expect(std.meta.activeTag(m.app) == .increment);
}
