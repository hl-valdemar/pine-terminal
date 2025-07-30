const std = @import("std");
const builtin = @import("builtin");

/// Input events that can be received from the terminal.
pub const Event = union(enum) {
    key: Key,
    resize: struct { width: u16, height: u16 },
    mouse: Mouse,

    pub const Key = union(enum) {
        char: u8,
        ctrl: u8, // ctrl+a through ctrl+z
        alt: u8, // alt+key combinations
        function: u8, // F1-F12
        arrow: Arrow,
        special: Special,

        pub const Arrow = enum {
            up,
            down,
            left,
            right,
        };
        pub const Special = enum {
            escape,
            enter,
            backspace,
            tab,
            delete,
            home,
            end,
            page_up,
            page_down,
        };
    };

    pub const Mouse = struct {
        x: u16,
        y: u16,
        button: Button,
        action: Action,

        pub const Button = enum {
            left,
            middle,
            right,
            scroll_up,
            scroll_down,
        };
        pub const Action = enum {
            press,
            release,
            drag,
        };
    };
};

/// Terminal configuration options.
pub const Config = struct {
    /// Enable mouse support.
    enable_mouse: bool = false,
    /// Use alternate screen buffer (preserves terminal content on exit).
    alternate_screen: bool = true,
    /// Hide cursor.
    hide_cursor: bool = true,
};

/// Main terminal interface.
pub const Terminal = switch (builtin.os.tag) {
    .macos => struct {
        old_termios: std.c.termios,
        raw_termios: std.c.termios,
        config: Config,

        /// Initialize the terminal with raw mode.
        pub fn init(config: Config) !Terminal {
            var self = Terminal{
                .old_termios = undefined,
                .raw_termios = undefined,
                .config = config,
            };

            // save current terminal settings
            _ = std.c.tcgetattr(std.c.STDIN_FILENO, &self.old_termios);

            // configure raw mode
            self.raw_termios = self.old_termios;

            // input flags
            self.raw_termios.lflag.ECHO = false;
            self.raw_termios.lflag.ICANON = false;
            self.raw_termios.lflag.ISIG = false;
            self.raw_termios.lflag.IEXTEN = false;

            // output flags
            self.raw_termios.iflag.IXON = false;
            self.raw_termios.iflag.ICRNL = false;
            self.raw_termios.iflag.BRKINT = false;
            self.raw_termios.iflag.INPCK = false;
            self.raw_termios.iflag.ISTRIP = false;

            self.raw_termios.oflag.OPOST = false;
            self.raw_termios.cflag.CSIZE = .CS8;

            // set up non-blocking read with timeout
            self.raw_termios.cc[@intFromEnum(std.c.V.TIME)] = 0;
            self.raw_termios.cc[@intFromEnum(std.c.V.MIN)] = 1;

            // apply settings
            _ = std.c.tcsetattr(std.c.STDIN_FILENO, .FLUSH, &self.raw_termios);

            // additional setup based on config
            if (config.alternate_screen) {
                try self.write("\x1B[?1049h"); // enter alternate screen
            }

            if (config.hide_cursor) {
                try self.write("\x1B[?25l"); // hide cursor
            }

            if (config.enable_mouse) {
                try self.write("\x1B[?1000h"); // enable mouse reporting
                try self.write("\x1B[?1006h"); // enable SGR mouse mode
            }

            return self;
        }

        /// Restore terminal to original state.
        pub fn deinit(self: *Terminal) void {
            if (self.config.enable_mouse) {
                self.write("\x1B[?1006l") catch {};
                self.write("\x1B[?1000l") catch {};
            }

            if (self.config.hide_cursor) {
                self.write("\x1B[?25h") catch {}; // show cursor
            }

            if (self.config.alternate_screen) {
                self.write("\x1B[?1049l") catch {}; // exit alternate screen
            }

            // restore original terminal settings
            _ = std.c.tcsetattr(std.c.STDIN_FILENO, .FLUSH, &self.old_termios);
        }

        /// Read next input event (blocking).
        pub fn readEvent(self: *Terminal) !Event {
            var buffer: [1]u8 = undefined;
            _ = std.c.read(std.c.STDIN_FILENO, &buffer, 1);

            return self.parseEvent(buffer[0]);
        }

        /// Read next input event (non-blocking).
        pub fn pollEvent(self: *Terminal) !?Event {
            // temporarily set non-blocking mode
            var temp_termios = self.raw_termios;
            temp_termios.cc[@intFromEnum(std.c.V.TIME)] = 0;
            temp_termios.cc[@intFromEnum(std.c.V.MIN)] = 0;
            _ = std.c.tcsetattr(std.c.STDIN_FILENO, .NOW, &temp_termios);
            defer _ = std.c.tcsetattr(std.c.STDIN_FILENO, .NOW, &self.raw_termios);

            var buffer: [1]u8 = undefined;
            const bytes_read = std.c.read(std.c.STDIN_FILENO, &buffer, 1);

            if (bytes_read <= 0) return null;

            return try self.parseEvent(buffer[0]);
        }

        fn parseEvent(self: *Terminal, first_byte: u8) !Event {
            // handle escape sequences
            if (first_byte == '\x1B') {
                return self.parseEscapeSequence();
            }

            // handle special ascii characters
            switch (first_byte) {
                0...8 => {
                    // ctrl+a through ctrl+z
                    return Event{ .key = .{ .ctrl = first_byte + 'a' - 1 } };
                },
                '\t' => return Event{ .key = .{ .special = .tab } },
                '\n' => return Event{ .key = .{ .special = .enter } },
                11...12 => {
                    // ctrl+a through ctrl+z
                    return Event{ .key = .{ .ctrl = first_byte + 'a' - 1 } };
                },
                '\r' => return Event{ .key = .{ .special = .enter } },
                14...26 => {
                    // ctrl+a through ctrl+z
                    return Event{ .key = .{ .ctrl = first_byte + 'a' - 1 } };
                },
                127 => return Event{ .key = .{ .special = .backspace } },
                32...126 => return Event{ .key = .{ .char = first_byte } },
                else => return Event{ .key = .{ .char = first_byte } },
            }
        }

        fn parseEscapeSequence(self: *Terminal) !Event {
            // temporarily set timeout for reading escape sequences
            var temp_termios = self.raw_termios;
            temp_termios.cc[@intFromEnum(std.c.V.TIME)] = 1; // 100ms timeout
            temp_termios.cc[@intFromEnum(std.c.V.MIN)] = 0;
            _ = std.c.tcsetattr(std.c.STDIN_FILENO, .NOW, &temp_termios);
            defer _ = std.c.tcsetattr(std.c.STDIN_FILENO, .NOW, &self.raw_termios);

            var buffer: [32]u8 = undefined;
            const bytes_read = std.c.read(std.c.STDIN_FILENO, &buffer, buffer.len);

            if (bytes_read <= 0) {
                return Event{ .key = .{ .special = .escape } };
            }

            const seq = buffer[0..@intCast(bytes_read)];

            // parse common sequences
            if (std.mem.eql(u8, seq, "[A")) return Event{ .key = .{ .arrow = .up } };
            if (std.mem.eql(u8, seq, "[B")) return Event{ .key = .{ .arrow = .down } };
            if (std.mem.eql(u8, seq, "[C")) return Event{ .key = .{ .arrow = .right } };
            if (std.mem.eql(u8, seq, "[D")) return Event{ .key = .{ .arrow = .left } };

            // alt+key (ESC followed by character)
            if (seq.len == 1 and seq[0] >= 32 and seq[0] <= 126) {
                return Event{ .key = .{ .alt = seq[0] } };
            }

            // mouse events (if enabled)
            if (self.config.enable_mouse and seq.len > 3 and seq[0] == '[' and seq[1] == '<') {
                // SGR mouse protocol parsing would go here
                // format: ESC[<button;x;y(M/m)
            }

            // unrecognized sequence
            return Event{ .key = .{ .special = .escape } };
        }

        /// clear the entire screen
        pub fn clear(self: *Terminal) !void {
            try self.write("\x1B[2J\x1B[H");
        }

        /// move cursor to position (1-indexed)
        pub fn setCursor(self: *Terminal, x: u16, y: u16) !void {
            var buf: [32]u8 = undefined;
            const seq = try std.fmt.bufPrint(&buf, "\x1B[{};{}H", .{ y, x });
            try self.write(seq);
        }

        /// set text color using 256-color palette (0-255)
        pub fn setForeground256(self: *Terminal, color: u8) !void {
            var buf: [32]u8 = undefined;
            const seq = try std.fmt.bufPrint(&buf, "\x1B[38;5;{}m", .{color});
            try self.write(seq);
        }

        /// set background color using 256-color palette (0-255)
        pub fn setBackground256(self: *Terminal, color: u8) !void {
            var buf: [32]u8 = undefined;
            const seq = try std.fmt.bufPrint(&buf, "\x1B[48;5;{}m", .{color});
            try self.write(seq);
        }

        /// set text color using RGB (true color)
        pub fn setForegroundRGB(self: *Terminal, r: u8, g: u8, b: u8) !void {
            var buf: [32]u8 = undefined;
            const seq = try std.fmt.bufPrint(&buf, "\x1B[38;2;{};{};{}m", .{ r, g, b });
            try self.write(seq);
        }

        /// set background color using RGB (true color)
        pub fn setBackgroundRGB(self: *Terminal, r: u8, g: u8, b: u8) !void {
            var buf: [32]u8 = undefined;
            const seq = try std.fmt.bufPrint(&buf, "\x1B[48;2;{};{};{}m", .{ r, g, b });
            try self.write(seq);
        }

        /// set both foreground and background colors using RGB
        pub fn setColorsRGB(self: *Terminal, fg: struct { r: u8, g: u8, b: u8 }, bg: struct { r: u8, g: u8, b: u8 }) !void {
            var buf: [64]u8 = undefined;
            const seq = try std.fmt.bufPrint(&buf, "\x1B[38;2;{};{};{};48;2;{};{};{}m", .{ fg.r, fg.g, fg.b, bg.r, bg.g, bg.b });
            try self.write(seq);
        }

        /// reset all attributes
        pub fn resetAttributes(self: *Terminal) !void {
            try self.write("\x1B[0m");
        }

        /// get terminal size
        pub fn getSize(self: *Terminal) !struct { width: u16, height: u16 } {
            _ = self;
            var size: std.c.winsize = undefined;
            if (std.c.ioctl(std.c.STDOUT_FILENO, std.c.T.IOCGWINSZ, &size) != 0) {
                return error.TerminalSizeError;
            }
            return .{ .width = size.col, .height = size.row };
        }

        /// write raw data to terminal
        pub fn write(self: *Terminal, data: []const u8) !void {
            _ = self;
            _ = try std.io.getStdOut().write(data);
        }

        /// flush output
        pub fn flush(self: *Terminal) !void {
            _ = self;
            // try std.io.getStdOut().writer().context.flush();
        }
    },
    else => @panic("UNIMPLEMENTED!"),
};
