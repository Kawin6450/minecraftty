const std = @import("std");
const Key = @import("key.zig").Key;
const win = std.os.windows;

pub const WindowsTerm = struct {
    stdout_file: std.fs.File.Writer,
    stdout: std.io.BufferedWriter(4096, std.fs.File.Writer),
    stdin: std.fs.File.Reader,

    h_stdout: win.HANDLE,
    h_stdin: win.HANDLE,
    original_mode: win.DWORD,

    pub fn init() !WindowsTerm {
        var t: WindowsTerm = undefined;

        t.stdout_file = std.io.getStdOut().writer();
        t.stdout = std.io.bufferedWriter(t.stdout_file);
        t.stdin = std.io.getStdIn().reader();

        t.h_stdout = try win.GetStdHandle(win.STD_OUTPUT_HANDLE);
        t.h_stdin = try win.GetStdHandle(win.STD_INPUT_HANDLE);
        // Store original stdin mode so it can be reset later
        if (win.kernel32.GetConsoleMode(t.h_stdin, &t.original_mode) == win.FALSE) {
            std.debug.print("Failed to GetConsoleMode: {}\n", .{win.GetLastError()});
            return error.FailGetConsoleMode;
        }
        // Enable ANSI escape codes
        var outmode: win.DWORD = undefined;
        if (win.kernel32.GetConsoleMode(t.h_stdout, &outmode) == win.FALSE) {
            return error.FailGetConsoleMode;
        }
        outmode |= win.ENABLE_VIRTUAL_TERMINAL_PROCESSING;
        if (win.kernel32.SetConsoleMode(t.h_stdout, outmode) == win.FALSE) {
            return error.FailSetConsoleMode;
        }
        // Switch to Unicode code page
        if (win.kernel32.SetConsoleOutputCP(65001) == win.FALSE) {
            return error.FailSetConsoleCodePage;
        }

        return t;
    }
    pub fn deinit(t: *WindowsTerm) void {
        _ = t;
    }

    pub fn flush(t: *WindowsTerm) !void {
        try t.stdout.flush();
    }

    pub fn writeAll(t: *WindowsTerm, bytes: []const u8) !void {
        try t.stdout.writer().writeAll(bytes);
    }

    // https://learn.microsoft.com/en-us/windows/console/readconsoleinput
    const KEY_EVENT_RECORD = extern struct {
        bKeyDown: win.BOOL,
        wRepeatCount: win.WORD,
        wVirtualKeyCode: win.WORD,
        wVirtualScanCode: win.WORD,
        uChar: extern union {
            UnicodeChar: win.WCHAR,
            AsciiChar: win.CHAR,
        },
        dwControlKeyState: win.DWORD,
    };
    const MOUSE_EVENT_RECORD = extern struct {
        dwMousePosition: win.COORD,
        dwButtonState: win.DWORD,
        dwControlKeyState: win.DWORD,
        dwEventFlags: win.DWORD,
    };
    const WINDOW_BUFFER_SIZE_RECORD = extern struct {
        dwSize: win.COORD,
    };
    const MENU_EVENT_RECORD = extern struct {
        dwCommandId: win.UINT,
    };
    const FOCUS_EVENT_RECORD = extern struct {
        bSetFocus: win.BOOL,
    };
    const INPUT_RECORD = extern struct {
        EventType: enum(win.WORD) {
            KEY_EVENT = 0x0001,
            MOUSE_EVENT = 0x0002,
            WINDOW_BUFFER_SIZE_EVENT = 0x0004,
            MENU_EVENT = 0x0008,
            FOCUS_EVENT = 0x0010,
        },
        Event: extern union {
            KeyEvent: KEY_EVENT_RECORD,
            MouseEvent: MOUSE_EVENT_RECORD,
            WindowBufferSizeEvent: WINDOW_BUFFER_SIZE_RECORD,
            MenuEvent: MENU_EVENT_RECORD,
            FocusEvent: FOCUS_EVENT_RECORD,
        },
    };
    extern "kernel32" fn ReadConsoleInputW(
        hConsoleInput: win.HANDLE,
        lpBuffer: *INPUT_RECORD,
        nLength: win.DWORD,
        lpNumberOfEventsRead: *win.DWORD,
    ) callconv(.winapi) win.BOOL;
    pub fn readKey(t: *WindowsTerm) !Key {
        var input: INPUT_RECORD = undefined;
        var num_evts_read: win.DWORD = undefined;
        if (ReadConsoleInputW(t.h_stdin, &input, 1, &num_evts_read) == win.FALSE) {
            return error.FailReadConsoleInput;
        }

        if (num_evts_read == 0) {
            return .none;
        }

        if (input.EventType == .KEY_EVENT) {
            if (input.Event.KeyEvent.bKeyDown == win.FALSE) {
                return .none;
            }
            // https://learn.microsoft.com/en-us/windows/win32/inputdev/virtual-key-codes
            return switch (input.Event.KeyEvent.wVirtualKeyCode) {
                0x1b => .esc,

                0x25 => .left,
                0x26 => .up,
                0x27 => .right,
                0x28 => .down,

                else => {
                    if (input.Event.KeyEvent.uChar.AsciiChar == 0) {
                        return .unknown;
                    } else {
                        return .{ .ch = input.Event.KeyEvent.uChar.AsciiChar };
                    }
                },
            };
        } else {
            return .none;
        }
    }

    pub fn setForeground(t: *WindowsTerm, color: [3]u8) !void {
        try t.stdout.writer().print("\x1b[38;2;{};{};{}m", .{ color[0], color[1], color[2] });
    }
    pub fn setBackground(t: *WindowsTerm, color: [3]u8) !void {
        try t.stdout.writer().print("\x1b[48;2;{};{};{}m", .{ color[0], color[1], color[2] });
    }
    pub fn resetColors(t: *WindowsTerm) !void {
        try t.stdout.writer().writeAll("\x1b[0m");
    }

    pub fn enableAltBuffer(t: *WindowsTerm) !void {
        try t.stdout.writer().writeAll("\x1b[?1049h");
    }
    pub fn disableAltBuffer(t: *WindowsTerm) !void {
        try t.stdout.writer().writeAll("\x1b[?1049l");
    }

    pub fn hideCursor(t: *WindowsTerm) !void {
        try t.stdout.writer().writeAll("\x1b[?25l");
    }
    pub fn showCursor(t: *WindowsTerm) !void {
        try t.stdout.writer().writeAll("\x1b[?25h");
    }

    pub fn setCursorPos(t: *WindowsTerm, x: u16, y: u16) !void {
        try t.stdout.writer().print("\x1b[{};{};H", .{ x, y });
    }

    pub fn enableRawInput(t: *WindowsTerm) !void {
        var original_mode: u32 = undefined;
        if (win.kernel32.GetConsoleMode(t.h_stdin, &original_mode) == win.FALSE) {
            std.debug.print("Failed to GetConsoleMode to enable raw input {}\n", .{win.GetLastError()});
            return error.FailGetConsoleMode;
        }

        // https://learn.microsoft.com/en-us/windows/console/setconsolemode
        const not_raw_mode: u32 = 0x0002 | 0x0004 | 0x0001; // ENABLE_LINE_INPUT, ENABLE_ECHO_INPUT, ENABLE_PROCESSED_INPUT
        const new_mode = original_mode & ~not_raw_mode;
        if (win.kernel32.SetConsoleMode(t.h_stdin, new_mode) == win.FALSE) {
            std.debug.print("Failed to SetConsoleMode to enable raw input {}\n", .{win.GetLastError()});
            return error.FailSetConsoleMode;
        }

        t.original_mode = original_mode;
    }
    pub fn disableRawInput(t: *WindowsTerm) !void {
        if (win.kernel32.SetConsoleMode(t.h_stdin, t.original_mode) == win.FALSE) {
            std.debug.print("Failed to SetConsoleMode to disable raw input\n", .{});
            return error.FailSetConsoleMode;
        }
    }
};
