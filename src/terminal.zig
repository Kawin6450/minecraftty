const std = @import("std");
const builtin = @import("builtin");

const Backend = if (builtin.target.os.tag == .windows) @import("term/windows.zig").WindowsTerm else @import("term/posix.zig").PosixTerm;

pub const Terminal = struct {
    backend: Backend,

    pub fn init() !Terminal {
        var t: Terminal = .{
            .backend = try Backend.init(),
        };

        try t.backend.enableAltBuffer();
        try t.backend.hideCursor();
        try t.backend.enableRawInput();
        try t.backend.flush();

        return t;
    }

    pub fn deinit(t: *Terminal) void {
        t.backend.resetColors() catch {};
        t.backend.disableAltBuffer() catch {};
        t.backend.showCursor() catch {};
        t.backend.disableRawInput() catch {};
        t.backend.flush() catch {
            std.debug.print("Failed writing to terminal on deinit.", .{});
        };

        t.backend.deinit();
    }
};
