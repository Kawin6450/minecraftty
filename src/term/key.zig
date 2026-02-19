pub const Key = union(enum) {
    none,

    ch: u8,

    up,
    down,
    left,
    right,

    esc,

    unknown,

    pub fn getch(self: Key) ?u8 {
        if (self == .ch) {
            return self.ch;
        }
        return null;
    }
};
