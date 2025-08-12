//! Common RGB color constants.

const std = @import("std");

// basic colors
pub const black = ColorValue{ .rgb = .{ .r = 0, .g = 0, .b = 0 } };
pub const white = ColorValue{ .rgb = .{ .r = 255, .g = 255, .b = 255 } };
pub const red = ColorValue{ .rgb = .{ .r = 255, .g = 0, .b = 0 } };
pub const green = ColorValue{ .rgb = .{ .r = 0, .g = 255, .b = 0 } };
pub const blue = ColorValue{ .rgb = .{ .r = 0, .g = 0, .b = 255 } };
pub const yellow = ColorValue{ .rgb = .{ .r = 255, .g = 255, .b = 0 } };
pub const cyan = ColorValue{ .rgb = .{ .r = 0, .g = 255, .b = 255 } };
pub const magenta = ColorValue{ .rgb = .{ .r = 255, .g = 0, .b = 255 } };

pub const ColorRGB = struct { r: u8, g: u8, b: u8 };

pub const ColorValue = union(enum) {
    palette: u8, // 256-color palette index
    rgb: ColorRGB, // RGB true color

    pub fn eql(self: ColorValue, other: ColorValue) bool {
        return switch (self) {
            .palette => |p| switch (other) {
                .palette => |op| p == op,
                .rgb => false,
            },
            .rgb => |rgb| switch (other) {
                .rgb => |orgb| rgb.r == orgb.r and rgb.g == orgb.g and rgb.b == orgb.b,
                .palette => false,
            },
        };
    }
};

/// convert HSL to RGB.
pub fn hslToRgb(h: f32, s: f32, l: f32) ColorRGB {
    const c = (1.0 - @abs(2.0 * l - 1.0)) * s;
    const x = c * (1.0 - @abs(@mod(h / 60.0, 2.0) - 1.0));
    const m = l - c / 2.0;

    var r: f32 = 0;
    var g: f32 = 0;
    var b: f32 = 0;

    if (h < 60) {
        r = c;
        g = x;
        b = 0;
    } else if (h < 120) {
        r = x;
        g = c;
        b = 0;
    } else if (h < 180) {
        r = 0;
        g = c;
        b = x;
    } else if (h < 240) {
        r = 0;
        g = x;
        b = c;
    } else if (h < 300) {
        r = x;
        g = 0;
        b = c;
    } else {
        r = c;
        g = 0;
        b = x;
    }

    return .{
        .r = @intFromFloat((r + m) * 255.0),
        .g = @intFromFloat((g + m) * 255.0),
        .b = @intFromFloat((b + m) * 255.0),
    };
}

/// Blend two RGB colors.
pub fn blendRgb(color1: ColorRGB, color2: ColorRGB, factor: f32) ColorRGB {
    const f = std.math.clamp(factor, 0.0, 1.0);
    return .{
        .r = @intFromFloat(@as(f32, @floatFromInt(color1.r)) * (1.0 - f) + @as(f32, @floatFromInt(color2.r)) * f),
        .g = @intFromFloat(@as(f32, @floatFromInt(color1.g)) * (1.0 - f) + @as(f32, @floatFromInt(color2.g)) * f),
        .b = @intFromFloat(@as(f32, @floatFromInt(color1.b)) * (1.0 - f) + @as(f32, @floatFromInt(color2.b)) * f),
    };
}

/// Darken a color by a factor (0-1).
pub fn darken(color: ColorRGB, factor: f32) ColorRGB {
    const f = std.math.clamp(1.0 - factor, 0.0, 1.0);
    return .{
        .r = @intFromFloat(@as(f32, @floatFromInt(color.r)) * f),
        .g = @intFromFloat(@as(f32, @floatFromInt(color.g)) * f),
        .b = @intFromFloat(@as(f32, @floatFromInt(color.b)) * f),
    };
}

/// Lighten a color by a factor (0-1).
pub fn lighten(color: ColorRGB, factor: f32) ColorRGB {
    const f = std.math.clamp(factor, 0.0, 1.0);
    return .{
        .r = @intFromFloat(@as(f32, @floatFromInt(color.r)) + (255.0 - @as(f32, @floatFromInt(color.r))) * f),
        .g = @intFromFloat(@as(f32, @floatFromInt(color.g)) + (255.0 - @as(f32, @floatFromInt(color.g))) * f),
        .b = @intFromFloat(@as(f32, @floatFromInt(color.b)) + (255.0 - @as(f32, @floatFromInt(color.b))) * f),
    };
}

/// Convert 256-color palette to approximate RGB.
pub fn palette256ToRgb(index: u8) ColorRGB {
    // 0-15: basic 16 colors
    if (index < 16) {
        return switch (index) {
            0 => .{ .r = 0, .g = 0, .b = 0 }, // black
            1 => .{ .r = 128, .g = 0, .b = 0 }, // red
            2 => .{ .r = 0, .g = 128, .b = 0 }, // green
            3 => .{ .r = 128, .g = 128, .b = 0 }, // yellow
            4 => .{ .r = 0, .g = 0, .b = 128 }, // blue
            5 => .{ .r = 128, .g = 0, .b = 128 }, // magenta
            6 => .{ .r = 0, .g = 128, .b = 128 }, // cyan
            7 => .{ .r = 192, .g = 192, .b = 192 }, // light gray
            8 => .{ .r = 128, .g = 128, .b = 128 }, // gray
            9 => .{ .r = 255, .g = 0, .b = 0 }, // bright red
            10 => .{ .r = 0, .g = 255, .b = 0 }, // bright green
            11 => .{ .r = 255, .g = 255, .b = 0 }, // bright yellow
            12 => .{ .r = 0, .g = 0, .b = 255 }, // bright blue
            13 => .{ .r = 255, .g = 0, .b = 255 }, // bright magenta
            14 => .{ .r = 0, .g = 255, .b = 255 }, // bright cyan
            15 => .{ .r = 255, .g = 255, .b = 255 }, // white
            else => unreachable,
        };
    }

    // 16-231: 6x6x6 color cube
    if (index < 232) {
        const cube_index = index - 16;
        const r_idx = cube_index / 36;
        const g_idx = (cube_index % 36) / 6;
        const b_idx = cube_index % 6;

        const levels = [_]u8{ 0, 95, 135, 175, 215, 255 };
        return .{
            .r = levels[r_idx],
            .g = levels[g_idx],
            .b = levels[b_idx],
        };
    }

    // 232-255: Grayscale
    const gray_level = (index - 232) * 10 + 8;
    return .{ .r = gray_level, .g = gray_level, .b = gray_level };
}

// /// Terminal capability detection.
// pub const TerminalCapabilities = struct {
//     supports_rgb: bool = false,
//     supports_256: bool = true,
//
//     /// Detect terminal color capabilities from environment.
//     pub fn detect() TerminalCapabilities {
//         var caps = TerminalCapabilities{};
//
//         // check COLORTERM for truecolor support
//         if (std.process.getEnvVarOwned(std.heap.page_allocator, "COLORTERM")) |colorterm| {
//             defer std.heap.page_allocator.free(colorterm);
//             if (std.mem.eql(u8, colorterm, "truecolor") or std.mem.eql(u8, colorterm, "24bit")) {
//                 caps.supports_rgb = true;
//             }
//         } else |_| {}
//
//         // check TERM for 256 color support
//         if (std.process.getEnvVarOwned(std.heap.page_allocator, "TERM")) |term| {
//             defer std.heap.page_allocator.free(term);
//             if (std.mem.indexOf(u8, term, "256color") != null) {
//                 caps.supports_256 = true;
//             }
//         } else |_| {}
//
//         return caps;
//     }
// };

// utility: dynamic lighting effect
pub fn calculateLighting(
    base_color: ColorRGB,
    light_source: struct { x: i16, y: i16, intensity: f32, color: ColorRGB },
    cell_pos: struct { x: i16, y: i16 },
) ColorRGB {
    const dx = @as(f32, @floatFromInt(cell_pos.x - light_source.x));
    const dy = @as(f32, @floatFromInt(cell_pos.y - light_source.y));
    const distance = @sqrt(dx * dx + dy * dy);

    // calculate falloff
    const falloff = std.math.clamp(1.0 - (distance / light_source.intensity), 0.0, 1.0);

    if (falloff <= 0.0) {
        return base_color;
    }

    // blend light color with base color
    const lit_color = blendRgb(base_color, light_source.color, falloff * 0.5);

    // apply brightness
    return lighten(lit_color, falloff * 0.3);
}
