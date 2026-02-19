const std = @import("std");
const Key = @import("key.zig").Key;

// ANSI escape codes: https://gist.github.com/fnky/458719343aabd01cfb17a3a4f7296797
pub const PosixTerm = struct {
    stdout: std.fs.File.Writer,
    stdin: std.fs.File.Reader,

    original_termios: std.posix.termios,

    pub fn init() !PosixTerm {
        var t: PosixTerm = undefined;

        var stdout_buffer: [1024]u8 = undefined;
        t.stdout = std.fs.File.stdout().writer(&stdout_buffer);
        var stdin_reader: [2]u8 = undefined;
        t.stdin = std.fs.File.stdin().reader(&stdin_reader);

        t.original_termios = try std.posix.tcgetattr(std.posix.STDIN_FILENO);

        return t;
    }
    pub fn deinit(t: *PosixTerm) void {
        _ = t;
    }

    pub fn flush(t: *PosixTerm) !void {
        try t.stdout.interface.flush();
    }

    pub fn writeAll(t: *PosixTerm, bytes: []const u8) !void {
        try t.stdout.interface.writeAll(bytes);
    }

    pub fn readKey(t: *PosixTerm) !Key {
        var buffer: [8]u8 = undefined;
        const size = try t.stdin.interface.readSliceShort(&buffer);

        if (size == 1) {
            if (buffer[0] == '\x1b') {
                return .esc;
            } else {
                return .{ .ch = buffer[0] };
            }
        }

        const seq = buffer[0..size];
        if (std.mem.eql(u8, seq, "\x1b[A")) {
            return .up;
        } else if (std.mem.eql(u8, seq, "\x1b[B")) {
            return .down;
        } else if (std.mem.eql(u8, seq, "\x1b[C")) {
            return .right;
        } else if (std.mem.eql(u8, seq, "\x1b[D")) {
            return .left;
        }

        return .unknown;
    }

    pub fn setForeground(t: *PosixTerm, color: [3]u8) !void {
        try t.stdout.interface.print("\x1b[38;2;{};{};{}m", .{ color[0], color[1], color[2] });
    }
    pub fn setBackground(t: *PosixTerm, color: [3]u8) !void {
        try t.stdout.interface.print("\x1b[48;2;{};{};{}m", .{ color[0], color[1], color[2] });
    }
    pub fn resetColors(t: *PosixTerm) !void {
        try t.stdout.interface.writeAll("\x1b[0m");
    }

    pub fn enableAltBuffer(t: *PosixTerm) !void {
        try t.stdout.interface.writeAll("\x1b[?1049h");
    }
    pub fn disableAltBuffer(t: *PosixTerm) !void {
        try t.stdout.interface.writeAll("\x1b[?1049l");
    }

    pub fn hideCursor(t: *PosixTerm) !void {
        try t.stdout.interface.writeAll("\x1b[?25l");
    }
    pub fn showCursor(t: *PosixTerm) !void {
        try t.stdout.interface.writeAll("\x1b[?25h");
    }

    pub fn setCursorPos(t: *PosixTerm, x: u16, y: u16) !void {
        try t.stdout.interface.print("\x1b[{};{};H", .{ x, y });
    }

    // Thanks to https://www.reddit.com/r/Zig/comments/b0dyfe/polling_for_key_presses/
    pub fn enableRawInput(t: *PosixTerm) !void {
        var new_termios = t.original_termios; // Make a local copy

        // Raw mode input
        new_termios.iflag.BRKINT = false;
        new_termios.iflag.ICRNL = false;
        new_termios.iflag.INPCK = false;
        new_termios.iflag.ISTRIP = false;
        new_termios.iflag.IXON = false;

        new_termios.lflag.ECHO = false;
        new_termios.lflag.ICANON = false;
        new_termios.lflag.IEXTEN = false;
        new_termios.lflag.ISIG = false;

        // Non-blocking reads
        new_termios.cc[@intFromEnum(std.posix.V.MIN)] = 0;
        new_termios.cc[@intFromEnum(std.posix.V.TIME)] = 0;

        try std.posix.tcsetattr(std.posix.STDIN_FILENO, .NOW, new_termios);
    }
    pub fn disableRawInput(t: *PosixTerm) !void {
        try std.posix.tcsetattr(std.posix.STDIN_FILENO, .NOW, t.original_termios);
    }
};

// const max_num_len = 4;
// pub fn getSize(t: *const Terminal) !struct { w: u16, h: u16 } {
//     const original_termios = try std.posix.tcgetattr(std.posix.STDIN_FILENO);
//     var new_termios = original_termios;
//     new_termios.cc[@intFromEnum(std.posix.V.MIN)] = 1;
//     try std.posix.tcsetattr(std.posix.STDIN_FILENO, .NOW, new_termios);
//
//     // Save cursor position, move to really large value, request the new position, then restore the old position
//     try t.stdout.writeAll("\x1b[s\x1b[9999;9999H\x1b[6n\x1b[u");
//
//     // Read the cursor pos code from stdin - ESC[#;#R
//     var cursor_pos_code: [max_num_len * 2 + 4]u8 = undefined;
//     var cursor_pos_code_len: u8 = 0;
//     while (true) {
//         const ch = try t.stdin.readByte();
//         cursor_pos_code[cursor_pos_code_len] = ch;
//         cursor_pos_code_len += 1;
//         if (ch == 'R') {
//             break;
//         }
//     }
//
//     var i: u8 = 2;
//     var h_str: [max_num_len]u8 = undefined;
//     var h_str_len: u8 = 0;
//     for (cursor_pos_code[i..]) |ch| {
//         if (ch == ';') {
//             break;
//         }
//         h_str[h_str_len] = cursor_pos_code[i];
//         i += 1;
//         h_str_len += 1;
//     }
//     i += 1;
//     var w_str: [max_num_len]u8 = undefined;
//     var w_str_len: u8 = 0;
//     for (cursor_pos_code[i..]) |ch| {
//         if (ch == 'R') {
//             break;
//         }
//         w_str[w_str_len] = cursor_pos_code[i];
//         i += 1;
//         w_str_len += 1;
//     }
//
//     try std.posix.tcsetattr(std.posix.STDIN_FILENO, .NOW, original_termios);
//
//     return .{
//         .w = try std.fmt.parseInt(u16, w_str[0..w_str_len], 10),
//         .h = try std.fmt.parseInt(u16, h_str[0..h_str_len], 10),
//     };
// }
