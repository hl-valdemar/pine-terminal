// global settings //

pub const std_options = std.Options{
    .logFn = log.logFn,
};

// public exports //

pub const log = @import("log.zig");
pub const colors = @import("colors.zig");

pub const Terminal = terminal.Terminal;
pub const Event = terminal.Event;
pub const KeyEvent = terminal.Event.Key;
pub const MouseEvent = terminal.Event.Mouse;
pub const Screen = screen.Screen;
pub const TermColor = screen.TermColor;
pub const ColorValue = colors.ColorValue;
pub const ColorRGB = colors.ColorRGB;

// private imports //

const std = @import("std");
const terminal = @import("terminal.zig");
const screen = @import("screen.zig");
