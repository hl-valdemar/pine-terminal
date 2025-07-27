const std = @import("std");
const Terminal = @import("terminal.zig").Terminal;
const ColorValue = @import("colors.zig").ColorValue;
const ColorRGB = @import("colors.zig").ColorRGB;

pub const TermColor = struct {
    fg: ColorValue = .{ .palette = 7 }, // default white
    bg: ColorValue = .{ .palette = 0 }, // default black

    /// Create a color from palette indices.
    pub fn fromPalette(fg: u8, bg: u8) TermColor {
        return .{
            .fg = .{ .palette = fg },
            .bg = .{ .palette = bg },
        };
    }

    /// Create a color from RGB values.
    pub fn fromRGB(fg: ColorRGB, bg: ColorRGB) TermColor {
        return .{
            .fg = .{ .rgb = fg },
            .bg = .{ .rgb = bg },
        };
    }
};

pub const Cell = struct {
    char: u21 = ' ', // unicode character
    color: TermColor = .{},
};

/// Double-buffered screen for efficient rendering.
pub const Screen = struct {
    width: u16,
    height: u16,
    front_buffer: []Cell,
    back_buffer: []Cell,
    allocator: std.mem.Allocator,
    term: *Terminal,

    pub fn init(allocator: std.mem.Allocator, term: *Terminal) !Screen {
        const size = try term.getSize();
        const buffer_size = size.width * size.height;

        const screen = Screen{
            .width = size.width,
            .height = size.height,
            .front_buffer = try allocator.alloc(Cell, buffer_size),
            .back_buffer = try allocator.alloc(Cell, buffer_size),
            .allocator = allocator,
            .term = term,
        };

        // initialize buffers
        for (screen.front_buffer) |*cell| {
            cell.* = .{};
        }
        for (screen.back_buffer) |*cell| {
            cell.* = .{};
        }

        return screen;
    }

    pub fn deinit(self: *Screen) void {
        self.allocator.free(self.front_buffer);
        self.allocator.free(self.back_buffer);
    }

    /// Set a cell in the back buffer.
    pub fn setCell(self: *Screen, x: u16, y: u16, char: u21, color: TermColor) void {
        if (x >= self.width or y >= self.height) return;
        const idx = y * self.width + x;
        self.back_buffer[idx] = .{ .char = char, .color = color };
    }

    /// Draw a string at position.
    pub fn drawString(self: *Screen, x: u16, y: u16, text: []const u8, color: TermColor) void {
        var px = x;
        for (text) |char| {
            if (px >= self.width) break;
            self.setCell(px, y, char, color);
            px += 1;
        }
    }

    /// Draw a box.
    pub fn drawBox(self: *Screen, x: u16, y: u16, w: u16, h: u16, color: TermColor) void {
        // unicode box drawing characters
        const horizontal = '─';
        const vertical = '│';
        const top_left = '┌';
        const top_right = '┐';
        const bottom_left = '└';
        const bottom_right = '┘';

        // corners
        self.setCell(x, y, top_left, color);
        self.setCell(x + w - 1, y, top_right, color);
        self.setCell(x, y + h - 1, bottom_left, color);
        self.setCell(x + w - 1, y + h - 1, bottom_right, color);

        // horizontal lines
        var i: u16 = 1;
        while (i < w - 1) : (i += 1) {
            self.setCell(x + i, y, horizontal, color);
            self.setCell(x + i, y + h - 1, horizontal, color);
        }

        // vertical lines
        i = 1;
        while (i < h - 1) : (i += 1) {
            self.setCell(x, y + i, vertical, color);
            self.setCell(x + w - 1, y + i, vertical, color);
        }
    }

    /// Fill a rectangle.
    pub fn fillRect(self: *Screen, x: u16, y: u16, w: u16, h: u16, char: u21, color: TermColor) void {
        var py: u16 = 0;
        while (py < h) : (py += 1) {
            var px: u16 = 0;
            while (px < w) : (px += 1) {
                self.setCell(x + px, y + py, char, color);
            }
        }
    }

    /// Clear the back buffer.
    pub fn clear(self: *Screen) void {
        for (self.back_buffer) |*cell| {
            cell.* = .{};
        }
    }

    /// Render only changed cells (differential rendering).
    pub fn render(self: *Screen) !void {
        var last_color: ?TermColor = null;
        var buffer: [64]u8 = undefined;
        var output = std.ArrayList(u8).init(self.allocator);
        defer output.deinit();

        var y: u16 = 0;
        while (y < self.height) : (y += 1) {
            var x: u16 = 0;
            var needs_move = true;

            while (x < self.width) : (x += 1) {
                const idx = y * self.width + x;
                const back = self.back_buffer[idx];
                const front = self.front_buffer[idx];

                // skip if cell hasn't changed
                if (back.char == front.char and
                    back.color.fg.eql(front.color.fg) and
                    back.color.bg.eql(front.color.bg))
                {
                    needs_move = true;
                    continue;
                }

                // move cursor if needed
                if (needs_move) {
                    const move_seq = try std.fmt.bufPrint(&buffer, "\x1B[{};{}H", .{ y + 1, x + 1 });
                    try output.appendSlice(move_seq);
                    needs_move = false;
                }

                // set colors if changed
                if (last_color == null or
                    !last_color.?.fg.eql(back.color.fg) or
                    !last_color.?.bg.eql(back.color.bg))
                {

                    // generate color sequence based on color type
                    const color_seq = switch (back.color.fg) {
                        .palette => |fg_pal| switch (back.color.bg) {
                            .palette => |bg_pal| try std.fmt.bufPrint(&buffer, "\x1B[38;5;{};48;5;{}m", .{ fg_pal, bg_pal }),
                            .rgb => |bg_rgb| try std.fmt.bufPrint(&buffer, "\x1B[38;5;{};48;2;{};{};{}m", .{ fg_pal, bg_rgb.r, bg_rgb.g, bg_rgb.b }),
                        },
                        .rgb => |fg_rgb| switch (back.color.bg) {
                            .palette => |bg_pal| try std.fmt.bufPrint(&buffer, "\x1B[38;2;{};{};{};48;5;{}m", .{ fg_rgb.r, fg_rgb.g, fg_rgb.b, bg_pal }),
                            .rgb => |bg_rgb| try std.fmt.bufPrint(&buffer, "\x1B[38;2;{};{};{};48;2;{};{};{}m", .{ fg_rgb.r, fg_rgb.g, fg_rgb.b, bg_rgb.r, bg_rgb.g, bg_rgb.b }),
                        },
                    };

                    try output.appendSlice(color_seq);
                    last_color = back.color;
                }

                // write character
                if (back.char < 128) {
                    try output.append(@intCast(back.char));
                } else {
                    // handle unicode
                    var utf8_buf: [4]u8 = undefined;
                    const len = try std.unicode.utf8Encode(back.char, &utf8_buf);
                    try output.appendSlice(utf8_buf[0..len]);
                }

                // update front buffer
                self.front_buffer[idx] = back;
            }
        }

        // write all changes at once
        if (output.items.len > 0) {
            try self.term.write(output.items);
            try self.term.flush();
        }
    }

    /// Force full redraw.
    pub fn forceRedraw(self: *Screen) !void {
        // mark all cells as dirty with impossible color values
        for (self.front_buffer) |*cell| {
            cell.* = .{ .char = 0, .color = .{ .fg = .{ .palette = 255 }, .bg = .{ .palette = 255 } } };
        }
        try self.render();
    }
};
