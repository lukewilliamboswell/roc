const std = @import("std");
const vaxis = @import("vaxis");
const Repl = @import("repl").Repl;

const ReplDriver = @This();

gpa: std.mem.Allocator,
vx: vaxis.Vaxis,
text_input: vaxis.widgets.TextInput,
repl_engine: *Repl,
history: std.ArrayListUnmanaged([]const u8),

pub fn init(gpa: std.mem.Allocator, repl_engine: *Repl) !ReplDriver {
    // Initialize vaxis and text input
    // Connect to existing Repl engine
    return ReplDriver{
        .gpa = gpa,
        .vx = try vaxis.Vaxis.init(gpa, .{}), // TODO
        .text_input = undefined, // TODO
        .repl_engine = repl_engine, // TODO implement RocOps for this, see various examples around
        .history = .{},
    };
}

pub fn run(self: *ReplDriver) !void {
    // Main event loop
    while (true) {
        const event = try self.vx.nextEvent();
        switch (event) {
            .key_press => |key| try self.handleKey(key),
            // Handle other events...
        }
    }
}

fn handleKey(self: *ReplDriver, key: vaxis.Key) !void {
    switch (key.codepoint) {
        '\n' => try self.evaluateCurrentInput(), // Enter
        '\x04' => return, // Ctrl+D (exit)
        // Up/Down arrows for history
        // Pass other keys to text_input
    }
}

test "repl driver test" {
    @panic("ASDF");
}
