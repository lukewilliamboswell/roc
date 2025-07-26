# `roc repl` CLI Integration Design

This document outlines the plan for integrating the Zig-based REPL functionality into the `roc` command-line interface.

## 1. Overview

The goal is to provide a feature-complete REPL (Read-Eval-Print Loop) accessible via the `roc repl` command, replacing the stubbed-out `rocRepl` function in `src/main.zig`. The core evaluation logic already exists in `src/repl/eval.zig`, and this plan focuses on building the user-facing CLI front-end around it.

We will aim for an experience that is both familiar to users of the old Rust-based REPL and improved by leveraging the new compiler's infrastructure, particularly for error reporting.

## 2. CLI Functionality

The `roc repl` command will be the entry point for the interactive shell.

### Invocation and Options

The command will be invoked as follows:

```sh
roc repl [OPTIONS]
```

It will support the same options as the previous implementation for consistency:

-   `--no-color`: Disables ANSI color codes in the output.
-   `--no-header`: Suppresses the initial welcome header.
-   `--help`: Prints the help message for the `repl` subcommand.

### Interactive Session

-   **Header:** On startup (unless `--no-header` is used), the REPL will display a welcoming header:

    ```
      The rockin' roc repl
    ────────────────────────

    Enter an expression, or :help, or :q to quit.
    ```

-   **Prompt:** User input will be preceded by a `» ` prompt.

-   **Input Loop:** The REPL will read one line of input at a time from standard input.

-   **Special Commands:** The REPL will support meta-commands prefixed with a colon (`:`):
    -   `:q` or `:exit`: Terminates the REPL session.
    -   `:help`: Displays a help message with available commands and usage examples.

## 3. Implementation Plan

### `src/main.zig` - `rocRepl` function

The existing `rocRepl` function will be updated to contain the main loop for the REPL.

```zig
// In src/main.zig

fn rocRepl(gpa: Allocator, args: cli_args.ReplArgs) !void {
    // 1. Handle --no-header argument
    if (!args.no_header) {
        // Print the standard REPL header
    }

    // 2. Initialize the Repl state
    var repl = try repl.Repl.init(gpa);
    defer repl.deinit();

    // 3. Start the input loop
    const stdin = std.io.getStdIn().reader();
    const stdout = std.io.getStdOut().writer();
    var buffer: [1024]u8 = undefined;

    while (true) {
        try stdout.writeAll("» ");

        const line = try stdin.readUntilDelimiterOrEof(&buffer, '\n');

        if (line) |input| {
            const trimmed_input = std.mem.trim(u8, input, " \t\r");

            // 4. Handle special commands
            if (std.mem.eql(u8, trimmed_input, ":q") or std.mem.eql(u8, trimmed_input, ":exit")) {
                break;
            } else if (std.mem.eql(u8, trimmed_input, ":help")) {
                // Print help text
                continue;
            }

            // 5. Evaluate the expression
            const result = try repl.step(trimmed_input);
            defer gpa.free(result);

            // 6. Print the result
            // This will be enhanced to include type info and error handling
            try stdout.print("{s}\n", .{result});

        } else {
            // End of file (Ctrl+D)
            break;
        }
    }
}
```

### `src/repl/eval.zig` - `Repl.step` Enhancements

The `Repl.step` function needs to be enhanced to return more than just a string. A structured result will allow for better error and type reporting.

```zig
// In src/repl/eval.zig

pub const StepResult = union(enum) {
    value: struct {
        string: []const u8,
        type_str: []const u8,
    },
    report: reporting.Report,
};

pub fn step(self: *Repl, input: []const u8) !StepResult {
    // ... existing evaluation logic ...

    // On success:
    // return StepResult{ .value = .{ .string = "54", .type_str = "Num *" } };

    // On failure:
    // return StepResult{ .report = ... };
}
```

## 4. Output and Error Reporting

A key goal is to provide rich, consistent feedback to the user.

### Success Output

For a successful evaluation, the REPL will print the resulting value, followed by its inferred type, using color to distinguish them.

Example: `54 : Num *`

The `rocRepl` function will use the `StepResult.value` to format this output, applying colors unless `--no-color` is specified.

### Error and Warning Reporting

If `Repl.step` returns a `StepResult.report`, the `rocRepl` function will use the `reporting` module to render it directly to the terminal.

```zig
// In rocRepl function, inside the loop:

const step_result = try repl.step(trimmed_input);

switch (step_result) {
    .value => |val| {
        // Print formatted value and type
        try stdout.print("{s} : {s}\n", .{val.string, val.type_str});
        gpa.free(val.string);
        gpa.free(val.type_str);
    },
    .report => |*report| {
        // Use the existing reporting infrastructure
        reporting.renderReportToTerminal(
            report,
            stderr.any(),
            ColorPalette.ANSI,
            reporting.ReportingConfig.initColorTerminal()
        ) catch {};
    },
}
```

This approach ensures that errors in the REPL look identical to errors from file-based compilation, providing a consistent user experience.

## 5. Testing Strategy

To be determined ... for now we will manually QA using the terminal and stdio.

## 6. Developer Experience Review

From an end-user's perspective, the following aspects are crucial for a good developer experience:

-   **Clarity and Consistency:** The prompt should be minimal (`» `), and the output format for values/types and errors should be consistent with the rest of the Roc toolchain. Using the `reporting` module directly achieves this.
-   **Discoverability:** The initial header and the `:help` command are essential for new users to understand how to use and exit the REPL.
-   **Readability:** The use of color is important for quickly distinguishing between values, types, and error messages. The `--no-color` flag provides an escape hatch for terminal environments that don't support it.
-   **Responsiveness:** The REPL should feel fast. The Zig implementation should be very performant.

### Future Enhancements

While not part of the initial integration, the following features should be considered for future improvements:

-   **Line Editing and History:** Integrate a library like `linenoise-zig` to provide command history (using up/down arrows) and advanced line editing capabilities.
-   **Multi-line Input:** Develop a mechanism to allow users to enter expressions that span multiple lines, perhaps by detecting open brackets or ending a line with a specific character.
-   **Tab Completion:** Add context-aware tab completion for variables and functions defined in the current REPL session.
