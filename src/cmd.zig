//! Command types for the MVU runtime.
//!
//! A `Cmd` is the value `update` returns to describe an effect the runtime
//! should perform. `none` does nothing, `quit` tells the runtime to exit
//! cleanly, `custom` runs a function inline on the main loop, and
//! `async_task` hands a function to a worker pool so a slow operation
//! (network, disk) does not block input. Both kinds may return an
//! optional follow-up app message that the runtime feeds back into
//! `update`.

const std = @import("std");

pub fn Cmd(comptime AppMsg: type) type {
    return union(enum) {
        none,
        quit,
        custom: *const fn (std.mem.Allocator) anyerror!?AppMsg,
        async_task: *const fn (std.mem.Allocator) anyerror!?AppMsg,
    };
}

test "Cmd defaults to none" {
    const C = Cmd(void);
    const c: C = .none;
    try std.testing.expect(std.meta.activeTag(c) == .none);
}

test "Cmd carries a quit variant" {
    const C = Cmd(void);
    const c: C = .quit;
    try std.testing.expect(std.meta.activeTag(c) == .quit);
}

test "Cmd custom returns an app message" {
    const App = union(enum) { hello };
    const C = Cmd(App);
    const Helper = struct {
        fn run(_: std.mem.Allocator) anyerror!?App {
            return .hello;
        }
    };
    const c: C = .{ .custom = &Helper.run };
    try std.testing.expect(std.meta.activeTag(c) == .custom);
    const result = try c.custom(std.testing.allocator);
    try std.testing.expect(std.meta.activeTag(result.?) == .hello);
}

test "Cmd custom can return null to skip" {
    const C = Cmd(void);
    const Helper = struct {
        fn run(_: std.mem.Allocator) anyerror!?void {
            return null;
        }
    };
    const c: C = .{ .custom = &Helper.run };
    const result = try c.custom(std.testing.allocator);
    try std.testing.expect(result == null);
}
