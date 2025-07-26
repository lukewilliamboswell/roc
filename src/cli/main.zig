const std = @import("std");
const roc = @import("roc");
const repl = roc.repl;
const vaxis = @import("vaxis");
const Cell = vaxis.Cell;
const TextInput = vaxis.widgets.TextInput;
const border = vaxis.widgets.border;

const Allocator = std.mem.Allocator;

// This can contain internal events as well as Vaxis events.
// Internal events can be posted into the same queue as vaxis events to allow
// for a single event loop with exhaustive switching.
const Event = union(enum) {
    key_press: vaxis.Key,
    winsize: vaxis.Winsize,
    focus_in,
    foo: u8,
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer {
        const deinit_status = gpa.deinit();
        //fail test; can't try in defer as defer is executed after we return
        if (deinit_status == .leak) {
            std.log.err("memory leak", .{});
        }
    }
    const alloc = gpa.allocator();

    // Initialize a tty
    var tty = try vaxis.Tty.init();
    defer tty.deinit();

    // Initialize Vaxis
    var vx = try vaxis.init(alloc, .{});
    // deinit takes an optional allocator. If your program is exiting, you can
    // choose to pass a null allocator to save some exit time.
    defer vx.deinit(alloc, tty.anyWriter());

    // The event loop requires an intrusive init. We create an instance with
    // stable pointers to Vaxis and our TTY, then init the instance. Doing so
    // installs a signal handler for SIGWINCH on posix TTYs
    //
    // This event loop is thread safe. It reads the tty in a separate thread
    var loop: vaxis.Loop(Event) = .{
        .tty = &tty,
        .vaxis = &vx,
    };
    try loop.init();

    // Start the read loop. This puts the terminal in raw mode and begins
    // reading user input
    try loop.start();
    defer loop.stop();

    // Optionally enter the alternate screen
    try vx.enterAltScreen(tty.anyWriter());

    // init our text input widget. The text input widget needs an allocator to
    // store the contents of the input
    var text_input = TextInput.init(alloc, &vx.unicode);
    defer text_input.deinit();

    var repl_instance = try repl.Repl.init(alloc);
    defer repl_instance.deinit();

    var history = std.ArrayList([]const u8).init(alloc);
    defer {
        for (history.items) |item| {
            alloc.free(item);
        }
        history.deinit();
    }

    // Sends queries to terminal to detect certain features. This should always
    // be called after entering the alt screen, if you are using the alt screen
    try vx.queryTerminal(tty.anyWriter(), 1 * std.time.ns_per_s);

    while (true) {
        // nextEvent blocks until an event is in the queue
        const event = loop.nextEvent();
        // exhaustive switching ftw. Vaxis will send events if your Event enum
        // has the fields for those events (ie "key_press", "winsize")
        switch (event) {
            .key_press => |key| {
                if (key.matches('c', .{ .ctrl = true })) {
                    break;
                } else if (key.matches('l', .{ .ctrl = true })) {
                    vx.queueRefresh();
                } else if (key.code == .enter) {
                    const input = text_input.text();
                    if (input.len > 0) {
                        try history.append(try alloc.dupe(u8, input));
                        const step_result = try repl_instance.step(input);
                        switch (step_result) {
                            .value => |val| {
                                defer alloc.free(val.string);
                                defer alloc.free(val.type_str);
                                if (val.type_str.len > 0) {
                                    try history.append(try std.fmt.allocPrint(alloc, "{s} : {s}", .{ val.string, val.type_str }));
                                } else {
                                    try history.append(try alloc.dupe(u8, val.string));
                                }
                            },
                            .report => |report_str| {
                                defer alloc.free(report_str);
                                try history.append(try alloc.dupe(u8, report_str));
                            },
                            .exit => |msg| {
                                defer alloc.free(msg);
                                try history.append(try alloc.dupe(u8, msg));
                                break;
                            },
                        }
                        text_input.clear();
                    }
                } else {
                    try text_input.update(.{ .key_press = key });
                }
            },

            .winsize => |ws| try vx.resize(alloc, tty.anyWriter(), ws),
            else => {},
        }

        const win = vx.window();
        win.clear();

        // Draw history
        var y: u16 = 0;
        for (history.items) |item| {
            _ = win.print(y, 0, item, .{});
            y += 1;
        }

        // Create a bordered child window for the input
        const child = win.child(.{
            .x_off = 0,
            .y_off = win.height - 1,
            .width = win.width,
            .height = 1,
        });

        // Draw the text_input in the child window
        text_input.draw(child);

        try vx.render(tty.anyWriter());
    }
}
