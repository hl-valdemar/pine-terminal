const std = @import("std");
const pterm = @import("pine-terminal");
const Terminal = pterm.Terminal;
const Screen = pterm.Screen;
const TermColor = pterm.TermColor;
const colors = pterm.colors;

const Tile = enum {
    floor,
    wall,
    water,
    grass,
    torch,

    fn getAppearance(self: Tile) struct { char: u21, color: TermColor } {
        return switch (self) {
            .floor => .{ .char = '.', .color = TermColor.fromRGB(
                .{ .r = 100, .g = 100, .b = 100 },
                .{ .r = 20, .g = 20, .b = 20 },
            ) },
            .wall => .{ .char = '#', .color = TermColor.fromRGB(
                .{ .r = 136, .g = 140, .b = 141 },
                .{ .r = 40, .g = 40, .b = 40 },
            ) },
            .water => .{ .char = '~', .color = TermColor.fromRGB(
                .{ .r = 33, .g = 150, .b = 243 },
                .{ .r = 10, .g = 50, .b = 100 },
            ) },
            .grass => .{ .char = '"', .color = TermColor.fromRGB(
                .{ .r = 46, .g = 125, .b = 50 },
                .{ .r = 20, .g = 40, .b = 20 },
            ) },
            .torch => .{ .char = '†', .color = TermColor.fromRGB(
                .{ .r = 255, .g = 200, .b = 0 },
                .{ .r = 100, .g = 50, .b = 0 },
            ) },
        };
    }
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // initialize terminal with rgb support
    var term = try Terminal.init(.{
        .enable_mouse = false,
        .alternate_screen = true,
        .hide_cursor = true,
    });
    defer term.deinit();

    var screen = try Screen.init(allocator, &term);
    defer screen.deinit();

    // create a simple map
    const MAP_WIDTH = 50;
    const MAP_HEIGHT = 25;
    var map: [MAP_HEIGHT][MAP_WIDTH]Tile = undefined;

    // initialize map
    for (&map) |*row| {
        for (row) |*tile| {
            tile.* = .floor;
        }
    }

    // add some features
    // walls around the edge
    for (0..MAP_WIDTH) |x| {
        map[0][x] = .wall;
        map[MAP_HEIGHT - 1][x] = .wall;
    }
    for (0..MAP_HEIGHT) |y| {
        map[y][0] = .wall;
        map[y][MAP_WIDTH - 1] = .wall;
    }

    // add a room
    for (10..20) |x| {
        map[5][x] = .wall;
        map[15][x] = .wall;
    }
    for (5..16) |y| {
        map[y][10] = .wall;
        map[y][19] = .wall;
    }

    // add water feature
    for (25..35) |x| {
        for (8..12) |y| {
            map[y][x] = .water;
        }
    }

    // add grass area
    for (30..40) |x| {
        for (16..20) |y| {
            map[y][x] = .grass;
        }
    }

    // add torches
    map[5][11] = .torch;
    map[5][18] = .torch;
    map[15][11] = .torch;
    map[15][18] = .torch;

    // game state
    var player_x: i16 = 25;
    var player_y: i16 = 12;
    var time: f32 = 0;

    // light sources
    const LightSource = struct {
        x: i16,
        y: i16,
        intensity: f32,
        color: pterm.ColorRGB,
        flicker: bool,
    };

    var light_sources = std.ArrayList(LightSource).init(allocator);
    defer light_sources.deinit();

    // add torch lights
    try light_sources.append(.{
        .x = 11,
        .y = 5,
        .intensity = 8,
        .color = .{ .r = 255, .g = 150, .b = 50 },
        .flicker = true,
    });
    try light_sources.append(.{
        .x = 18,
        .y = 5,
        .intensity = 8,
        .color = .{ .r = 255, .g = 150, .b = 50 },
        .flicker = true,
    });
    try light_sources.append(.{
        .x = 11,
        .y = 15,
        .intensity = 8,
        .color = .{ .r = 255, .g = 150, .b = 50 },
        .flicker = true,
    });
    try light_sources.append(.{
        .x = 18,
        .y = 15,
        .intensity = 8,
        .color = .{ .r = 255, .g = 150, .b = 50 },
        .flicker = true,
    });

    // add player light
    try light_sources.append(.{
        .x = player_x,
        .y = player_y,
        .intensity = 5,
        .color = .{ .r = 200, .g = 200, .b = 150 },
        .flicker = false,
    });

    while (true) {
        // update time for animations
        time += 0.05;

        // update player light position
        light_sources.items[light_sources.items.len - 1].x = player_x;
        light_sources.items[light_sources.items.len - 1].y = player_y;

        // clear screen
        screen.clear();

        // render map with lighting
        for (0..MAP_HEIGHT) |y| {
            for (0..MAP_WIDTH) |x| {
                const tile = map[y][x];
                var appearance = tile.getAppearance();

                // apply lighting
                var lit_fg = switch (appearance.color.fg) {
                    .rgb => |rgb| rgb,
                    .palette => colors.palette256ToRgb(appearance.color.fg.palette),
                };
                var lit_bg = switch (appearance.color.bg) {
                    .rgb => |rgb| rgb,
                    .palette => colors.palette256ToRgb(appearance.color.bg.palette),
                };

                // start with darkness
                lit_fg = colors.darken(lit_fg, 0.8);
                lit_bg = colors.darken(lit_bg, 0.9);

                // apply each light source
                for (light_sources.items) |light| {
                    var intensity = light.intensity;

                    // add flicker effect
                    if (light.flicker) {
                        intensity += @sin(time * 10.0 + @as(f32, @floatFromInt(light.x + light.y))) * 1.5;
                    }

                    const light_color = colors.calculateLighting(
                        lit_fg,
                        .{ .x = light.x, .y = light.y, .intensity = intensity, .color = light.color },
                        .{ .x = @intCast(x), .y = @intCast(y) },
                    );

                    lit_fg = light_color;
                }

                // special effects for certain tiles
                if (tile == .water) {
                    // animate water
                    const wave = @sin(time * 2.0 + @as(f32, @floatFromInt(x + y))) * 0.2 + 0.5;
                    lit_fg = colors.lighten(lit_fg, wave * 0.3);
                    appearance.char = if (wave > 0.5) '≈' else '~';
                }

                // set the cell with calculated colors
                screen.setCell(@intCast(x), @intCast(y), appearance.char, TermColor.fromRGB(lit_fg, lit_bg));
            }
        }

        // draw entities
        // player with golden glow
        const player_color = TermColor.fromRGB(.{ .r = 255, .g = 215, .b = 0 }, .{ .r = 50, .g = 40, .b = 0 });
        screen.setCell(@intCast(player_x), @intCast(player_y), '@', player_color);

        // ui with gradient health bar
        const ui_y = MAP_HEIGHT;
        screen.drawString(0, ui_y, "Health: ", TermColor.fromPalette(7, 0));

        const health_percent: f32 = 0.75; // 75% health
        const bar_width = 20;
        for (0..bar_width) |i| {
            const filled = i < @as(usize, @intFromFloat(bar_width * health_percent));
            if (filled) {
                // gradient from green to red based on position
                const gradient_pos = @as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(bar_width));
                const bar_color = colors.blendRgb(
                    .{ .r = 67, .g = 160, .b = 71 }, // green
                    .{ .r = 229, .g = 57, .b = 53 }, // red
                    gradient_pos,
                );
                screen.setCell(8 + @as(u16, @intCast(i)), ui_y, '█', TermColor.fromRGB(
                    bar_color,
                    .{ .r = 0, .g = 0, .b = 0 },
                ));
            } else {
                screen.setCell(8 + @as(u16, @intCast(i)), ui_y, '█', TermColor.fromRGB(
                    pterm.colors.lighten(pterm.colors.black.rgb, 0.2),
                    pterm.colors.black.rgb,
                ));
            }
        }

        // instructions
        screen.drawString(0, ui_y + 1, "Use arrows to move, 'q' to quit", TermColor.fromPalette(8, 0));

        try screen.render();

        // handle input (non-blocking for smooth animation)
        if (try term.pollEvent()) |event| {
            switch (event) {
                .key => |key| switch (key) {
                    .char => |c| if (c == 'q') break,
                    .arrow => |arrow| {
                        const new_x = switch (arrow) {
                            .left => player_x - 1,
                            .right => player_x + 1,
                            else => player_x,
                        };
                        const new_y = switch (arrow) {
                            .up => player_y - 1,
                            .down => player_y + 1,
                            else => player_y,
                        };

                        // check bounds and collision
                        if (new_x > 0 and new_x < MAP_WIDTH - 1 and
                            new_y > 0 and new_y < MAP_HEIGHT - 1)
                        {
                            const target_tile = map[@intCast(new_y)][@intCast(new_x)];
                            if (target_tile != .wall) {
                                player_x = new_x;
                                player_y = new_y;
                            }
                        }
                    },
                    else => {},
                },
                else => {},
            }
        }

        // small delay for animation
        std.time.sleep(50_000_000); // 50ms
    }
}
