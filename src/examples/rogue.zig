const std = @import("std");
const pterm = @import("pine-terminal");

const Tile = enum {
    floor,
    wall,

    fn getAppearance(self: Tile) struct { char: u21, color: pterm.TermColor } {
        return switch (self) {
            .floor => .{ .char = ' ', .color = pterm.TermColor.fromRGB(
                .{ .r = 100, .g = 100, .b = 100 },
                pterm.colors.black.rgb,
            ) },
            .wall => .{ .char = '#', .color = pterm.TermColor.fromRGB(
                .{ .r = 136, .g = 140, .b = 141 },
                pterm.colors.black.rgb,
            ) },
        };
    }
};

const Player = struct {
    color: pterm.TermColor = .{
        .fg = pterm.colors.white,
        .bg = pterm.colors.black,
    },
    symbol: u8 = '@',
    x: u16 = 0,
    y: u16 = 0,
};

pub fn main() !void {
    var gpa = std.heap.DebugAllocator(.{}).init;
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // initialize terminal with rgb support
    var term = try pterm.Terminal.init(.{
        .enable_mouse = false,
        .alternate_screen = true,
        .hide_cursor = true,
    });
    defer term.deinit();

    var screen = try pterm.Screen.init(allocator, &term);
    defer screen.deinit();

    const MAP_WIDTH = 50;
    const MAP_HEIGHT = 25;
    var map: [MAP_HEIGHT][MAP_WIDTH]Tile = undefined;

    // initialize map
    for (&map) |*row| {
        for (row) |*tile| {
            tile.* = .floor;
        }
    }

    // add walls around the edge
    for (0..MAP_WIDTH) |x| {
        map[0][x] = .wall;
        map[MAP_HEIGHT - 1][x] = .wall;
    }
    for (0..MAP_HEIGHT) |y| {
        map[y][0] = .wall;
        map[y][MAP_WIDTH - 1] = .wall;
    }

    var player = Player{
        .x = @divTrunc(MAP_WIDTH, 2),
        .y = @divTrunc(MAP_HEIGHT, 2),
    };

    var should_close = false;
    while (!should_close) {
        // clear the screen
        screen.clear();

        // draw the map
        for (0..MAP_HEIGHT) |y| {
            for (0..MAP_WIDTH) |x| {
                const tile = map[y][x];
                const appearance = tile.getAppearance();
                screen.setCell(@intCast(x), @intCast(y), appearance.char, appearance.color);
            }
        }

        // draw the player
        screen.setCell(player.x, player.y, player.symbol, player.color);

        // render to the screen
        try screen.render();

        // handle input
        if (try term.pollEvent()) |event| {
            switch (event) {
                .key => |key| switch (key) {
                    .char => |c| {
                        if (c == 'q') should_close = true;
                    },
                    .arrow => |arrow| {
                        const new_x = switch (arrow) {
                            .left => player.x - 1,
                            .right => player.x + 1,
                            else => player.x,
                        };
                        const new_y = switch (arrow) {
                            .up => player.y - 1,
                            .down => player.y + 1,
                            else => player.y,
                        };

                        // check bounds and collision
                        if (new_x > 0 and new_y < MAP_WIDTH - 1 and
                            new_y > 0 and new_y < MAP_HEIGHT - 1)
                        {
                            const target_tile = map[@intCast(new_y)][@intCast(new_x)];
                            if (target_tile != .wall) {
                                player.x = new_x;
                                player.y = new_y;
                            }
                        }
                    },
                    else => {},
                },
                else => {},
            }
        }
    }
}
