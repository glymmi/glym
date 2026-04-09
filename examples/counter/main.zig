//! Counter example.
//!
//! Placeholder for now. Becomes a real interactive counter driven by arrow
//! keys once the MVU runtime lands.

const std = @import("std");
const glym = @import("glym");

pub fn main() !void {
    std.debug.print("glym v{s} - counter example placeholder\n", .{glym.version});
}
