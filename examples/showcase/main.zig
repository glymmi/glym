//! Styling showcase.
//!
//! Static demo that exercises every styling primitive in glym at once:
//! the five border presets, every text attribute, the palette scales,
//! gradient text, hex parsing, darken/lighten and Style.merge. Designed
//! for an 80x32 terminal. Press q or esc to quit.

const std = @import("std");
const glym = @import("glym");

const style = glym.style;
const palette = style.palette;
const Style = style.Style;
const Border = style.Border;
const Rgb = style.Rgb;

const Model = struct {};
const App = union(enum) {};
const P = glym.Program(Model, App);

fn init(_: std.mem.Allocator) anyerror!Model {
    return .{};
}

fn update(_: *Model, m: P.Msg) P.Cmd {
    switch (m) {
        .key => |k| {
            switch (k.code) {
                .escape => return .quit,
                .char => |c| {
                    if (c == 'q') return .quit;
                    if (c == 'c' and k.modifiers.ctrl) return .quit;
                },
                else => {},
            }
        },
        else => {},
    }
    return .none;
}

// -- shared styles --

const muted: Style = .{ .fg = .{ .rgb = palette.slate_500 }, .italic = true };
const label: Style = .{ .fg = .{ .rgb = palette.slate_300 } };
const heading: Style = .{ .fg = .{ .rgb = palette.violet_300 }, .bold = true };
const accent_border: Style = .{ .fg = .{ .rgb = palette.violet_500 } };

// -- sections --

fn drawTitle(r: *P.Renderer) void {
    r.writeGradientText(1, 0, "      glym styling showcase      ", palette.violet_300, palette.sky_300, .{ .bold = true });
    r.writeCenteredText(2, 0, r.cols, "press q or esc to quit", muted);
}

const BorderEntry = struct { name: []const u8, border: Border };

const border_entries = [_]BorderEntry{
    .{ .name = "sharp", .border = Border.sharp },
    .{ .name = "rounded", .border = Border.rounded },
    .{ .name = "double", .border = Border.double },
    .{ .name = "thick", .border = Border.thick },
    .{ .name = "ascii", .border = Border.ascii },
};

fn drawBorderShowcase(r: *P.Renderer) void {
    r.writeStyledText(4, 2, "Borders", heading);
    const top: u16 = 5;
    const box_w: u16 = 14;
    const box_h: u16 = 4;
    const gap: u16 = 1;
    var col: u16 = 2;
    for (border_entries) |entry| {
        r.drawBorder(top, col, box_h, box_w, entry.border, accent_border);
        r.writeCenteredText(top + 1, col, box_w, entry.name, label);
        col += box_w + gap;
    }
}

fn drawAttributeShowcase(r: *P.Renderer) void {
    r.writeStyledText(11, 2, "Text attributes", heading);
    const base: Style = .{ .fg = .{ .rgb = palette.slate_300 } };
    const samples = [_]struct { text: []const u8, override: Style }{
        .{ .text = "bold", .override = .{ .bold = true } },
        .{ .text = "dim", .override = .{ .dim = true } },
        .{ .text = "italic", .override = .{ .italic = true } },
        .{ .text = "underline", .override = .{ .underline = true } },
        .{ .text = "reverse", .override = .{ .reverse = true } },
        .{ .text = "strike", .override = .{ .strikethrough = true } },
    };
    var col: u16 = 2;
    for (samples) |s| {
        // Style.merge: build the rendered style by stacking the base
        // surface color with the attribute under test.
        const merged = Style.merge(base, s.override);
        r.writeStyledText(12, col, s.text, merged);
        col += @as(u16, @intCast(s.text.len)) + 2;
    }
}

const PaletteRow = struct { name: []const u8, stops: []const Rgb };

const slate_stops = [_]Rgb{ palette.slate_50, palette.slate_300, palette.slate_500, palette.slate_700, palette.slate_900 };
const rose_stops = [_]Rgb{ palette.rose_300, palette.rose_500, palette.rose_700 };
const sky_stops = [_]Rgb{ palette.sky_300, palette.sky_500, palette.sky_700 };
const amber_stops = [_]Rgb{ palette.amber_300, palette.amber_500, palette.amber_700 };
const emerald_stops = [_]Rgb{ palette.emerald_300, palette.emerald_500, palette.emerald_700 };
const violet_stops = [_]Rgb{ palette.violet_300, palette.violet_500, palette.violet_700 };

const palette_rows = [_]PaletteRow{
    .{ .name = "slate", .stops = &slate_stops },
    .{ .name = "rose", .stops = &rose_stops },
    .{ .name = "sky", .stops = &sky_stops },
    .{ .name = "amber", .stops = &amber_stops },
    .{ .name = "emerald", .stops = &emerald_stops },
    .{ .name = "violet", .stops = &violet_stops },
};

fn drawPalette(r: *P.Renderer) void {
    r.writeStyledText(14, 2, "Palette", heading);
    var row: u16 = 15;
    for (palette_rows) |entry| {
        r.writeStyledText(row, 2, entry.name, label);
        var col: u16 = 12;
        for (entry.stops) |stop| {
            const swatch: Style = .{ .bg = .{ .rgb = stop } };
            r.fillRect(row, col, 1, 6, .{ .char = ' ', .style = swatch });
            col += 7;
        }
        row += 1;
    }
}

fn drawColorHelpers(r: *P.Renderer) void {
    r.writeStyledText(22, 2, "Color helpers", heading);

    // Hex parsing: roll a few literals through Rgb.fromHex.
    const hex_pairs = [_]struct { name: []const u8, hex: []const u8 }{
        .{ .name = "#ff6b9d", .hex = "#ff6b9d" },
        .{ .name = "#5bcef7", .hex = "#5bcef7" },
        .{ .name = "#facc15", .hex = "#facc15" },
    };
    var col: u16 = 2;
    for (hex_pairs) |pair| {
        const c = Rgb.fromHex(pair.hex) catch continue;
        const s: Style = .{ .fg = .{ .rgb = c }, .bold = true };
        r.writeStyledText(23, col, pair.name, s);
        col += @as(u16, @intCast(pair.name.len)) + 2;
    }

    // Darken / lighten ramps from a single seed color.
    const seed = Rgb.fromHex("#8b5cf6") catch palette.violet_500;
    r.writeStyledText(24, 2, "darken", label);
    var x: u16 = 12;
    var t: f32 = 0;
    while (t <= 1.001) : (t += 0.2) {
        const swatch: Style = .{ .bg = .{ .rgb = seed.darken(t) } };
        r.fillRect(24, x, 1, 4, .{ .char = ' ', .style = swatch });
        x += 5;
    }
    r.writeStyledText(25, 2, "lighten", label);
    x = 12;
    t = 0;
    while (t <= 1.001) : (t += 0.2) {
        const swatch: Style = .{ .bg = .{ .rgb = seed.lighten(t) } };
        r.fillRect(25, x, 1, 4, .{ .char = ' ', .style = swatch });
        x += 5;
    }
}

fn drawPanel(r: *P.Renderer) void {
    // Self-contained panel demonstrating drawBorderTitled + an inner
    // gradient line.
    const top: u16 = 27;
    const left: u16 = 2;
    const w: u16 = 76;
    const h: u16 = 4;
    r.drawBorderTitled(top, left, h, w, Border.rounded, accent_border, "merge + gradient", heading);
    r.writeGradientText(top + 1, left + 2, "from violet, through sky, to emerald (gradient text)", palette.violet_500, palette.emerald_500, .{ .bold = true });
    r.writeStyledText(top + 2, left + 2, "drawBorderTitled frames the panel without a fill.", muted);
}

fn view(_: *Model, r: *P.Renderer) void {
    drawTitle(r);
    drawBorderShowcase(r);
    drawAttributeShowcase(r);
    drawPalette(r);
    drawColorHelpers(r);
    drawPanel(r);
}

pub fn main() !void {
    var gpa: std.heap.GeneralPurposeAllocator(.{}) = .{};
    defer _ = gpa.deinit();

    const program: P = .{
        .allocator = gpa.allocator(),
        .init_fn = init,
        .update_fn = update,
        .view_fn = view,
    };
    try program.runSafely();
}
