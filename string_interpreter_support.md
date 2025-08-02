# A Plan for Interpreter String Support

This plan addresses the critical discovery that Roc strings support interpolation with embedded expressions (e.g., `"Hello ${world}"`). Strings are represented as `e_str` expressions containing spans of segments, where each segment can be either a string literal (`e_str_segment`) or any other expression that needs to be evaluated and converted to a string.

---

## **Part 0: Understanding String Architecture**

### **String Representation in Roc CIR:**
- **`e_str`**: Contains a `span` of expression segments that make up the complete string
- **`e_str_segment`**: A literal string part (e.g., `"Hello "` in `"Hello ${name}"`)
- **Interpolated expressions**: Any non-`e_str_segment` in the span (e.g., `name` in `"Hello ${name}"`)
- **Desugaring**: Complex interpolations are desugared into `Str.concat` calls with `CalledVia.string_interpolation`

### **Example Transformations:**
```roc
"Hello ${name}"           -> e_str with span: [e_str_segment("Hello "), e_lookup_local(name)]
"${first} ${last}"        -> e_str with span: [e_lookup_local(first), e_str_segment(" "), e_lookup_local(last)]
"Result: ${calc(x, y)}"   -> e_str with span: [e_str_segment("Result: "), e_call(...)]
```

---

## **Part 1: Foundation Infrastructure**

#### **Task 1.1: Enhanced Error Types for String Interpolation**

*   **Goal**: Add comprehensive error handling for string interpolation scenarios.
*   **Plan**:
    ```zig
    pub const EvalError = error{
        // ... existing errors
        StringAllocationFailed,
        StringReferenceCountCorrupted,
        StringBuiltinFailed,
        StringLiteralCorrupted,
        StringInterpolationFailed,
        StringSegmentEvaluationFailed,
        StringConversionFailed,
    };
    ```

#### **Task 1.2: String Conversion Infrastructure**

*   **Goal**: Add infrastructure to convert any expression result to a string representation.
*   **Plan**:
    1.  **Implement `valueToString`**: Convert any `StackValue` to a `RocStr`:
        ```zig
        fn valueToString(self: *Interpreter, value: StackValue) EvalError!builtins.str.RocStr {
            switch (value.layout.tag) {
                .scalar => switch (value.layout.data.scalar.tag) {
                    .str => {
                        // Already a string, clone it
                        const existing_str: *const builtins.str.RocStr = @ptrCast(@alignCast(value.ptr.?));
                        return existing_str.clone(&self.roc_ops) catch |err| switch (err) {
                            error.OutOfMemory => {
                                self.traceWarn("Failed to clone string for interpolation, using empty string");
                                return builtins.str.RocStr.empty();
                            },
                            else => return error.StringConversionFailed,
                        };
                    },
                    .int => {
                        // Convert integer to string using builtin
                        const int_val = self.readIntFromMemoryAndTrace(value.ptr.?, value.layout.data.scalar.data.int);
                        return builtins.str.exportFromInt(int_val, &self.roc_ops) catch |err| switch (err) {
                            error.OutOfMemory => {
                                self.traceWarn("Failed to convert int to string, using placeholder");
                                return builtins.str.RocStr.fromSlice("<int>", &self.roc_ops) catch builtins.str.RocStr.empty();
                            },
                            else => return error.StringConversionFailed,
                        };
                    },
                    .frac => {
                        // Convert float to string using builtin
                        const float_val = @as(*f64, @ptrCast(@alignCast(value.ptr.?))).*;
                        return builtins.str.exportFromFloat(float_val, &self.roc_ops) catch |err| switch (err) {
                            error.OutOfMemory => {
                                self.traceWarn("Failed to convert float to string, using placeholder");
                                return builtins.str.RocStr.fromSlice("<float>", &self.roc_ops) catch builtins.str.RocStr.empty();
                            },
                            else => return error.StringConversionFailed,
                        };
                    },
                    .bool => {
                        // Convert boolean to string
                        const bool_val = @as(*u8, @ptrCast(@alignCast(value.ptr.?))).*;
                        const str_content = if (bool_val != 0) "True" else "False";
                        return builtins.str.RocStr.fromSlice(str_content, &self.roc_ops) catch |err| switch (err) {
                            error.OutOfMemory => builtins.str.RocStr.empty(),
                            else => return error.StringConversionFailed,
                        };
                    },
                    else => {
                        // For other types, use a placeholder representation
                        self.traceWarn("Cannot convert {} to string, using placeholder", .{value.layout.data.scalar.tag});
                        const placeholder = try std.fmt.allocPrint(self.allocator, "<{s}>", .{@tagName(value.layout.data.scalar.tag)});
                        defer self.allocator.free(placeholder);
                        return builtins.str.RocStr.fromSlice(placeholder, &self.roc_ops) catch builtins.str.RocStr.empty();
                    },
                },
                else => {
                    // For complex types, use a placeholder
                    self.traceWarn("Cannot convert {} to string, using placeholder", .{value.layout.tag});
                    const placeholder = try std.fmt.allocPrint(self.allocator, "<{s}>", .{@tagName(value.layout.tag)});
                    defer self.allocator.free(placeholder);
                    return builtins.str.RocStr.fromSlice(placeholder, &self.roc_ops) catch builtins.str.RocStr.empty();
                },
            }
        }
        ```

#### **Task 1.3: RocOps Allocator Bridge**

*   **Goal**: Bridge the interpreter's allocator to the `RocStr` builtin, enabling heap allocation for large strings.
*   **Plan**:
    1.  Add `roc_ops: builtins.host_abi.RocOps` to the `Interpreter` struct.
    2.  In `Interpreter.init`, initialize `roc_ops` by pointing its `ctx` to the interpreter's allocator and wiring up static `rocAlloc`, `rocRealloc`, and `rocDealloc` wrapper functions.
*   **Error Handling & Assertions**:
    *   The `rocAlloc`/`rocRealloc` wrappers must handle allocation failures by calling `roc_ops.crash()` with a descriptive message (following the RocOps contract).
    *   Assert that `alignment` parameters are respected.
*   **Tracing**:
    *   Add `traceInfo` calls inside the wrappers to log heap activity.

---

## **Part 2: String Interpolation Evaluation (`e_str`)**

#### **Task 2.1: String Segment Evaluation Work Items**

*   **Goal**: Add work items to handle string interpolation evaluation.
*   **Plan**:
    1.  **Add new work kinds**:
        ```zig
        pub const WorkKind = enum {
            // ... existing work kinds
            w_str_interpolation_start,   // Begin evaluating string segments
            w_str_interpolation_segment, // Evaluate next segment
            w_str_interpolation_combine, // Combine all evaluated segments
        };
        ```
    2.  **Add `StringInterpolationState`** to track progress:
        ```zig
        const StringInterpolationState = struct {
            span: ModuleEnv.Expr.Span,
            current_segment: u32,
            segments_evaluated: std.ArrayList(builtins.str.RocStr),

            fn deinit(self: *StringInterpolationState, allocator: std.mem.Allocator) void {
                for (self.segments_evaluated.items) |*segment| {
                    segment.decref(); // Clean up if evaluation fails
                }
                self.segments_evaluated.deinit();
            }
        };
        ```

#### **Task 2.2: `e_str` Expression Evaluation**

*   **Goal**: Implement evaluation of interpolated strings by processing each segment in the span.
*   **Plan**:
    1.  **Implement the `e_str` case in `evalExpr`**:
        ```zig
        .e_str => |str_expr| {
            const segments = self.env.store.sliceExpr(str_expr.span);
            if (segments.len == 0) {
                // Empty string
                const layout_idx = try self.getLayoutIdx(Layout.str());
                const empty_str_value = try self.pushStackValue(layout_idx);
                const roc_str_ptr: *builtins.str.RocStr = @ptrCast(@alignCast(empty_str_value.ptr.?));
                roc_str_ptr.* = builtins.str.RocStr.empty();
                try self.traceValue("empty_e_str", empty_str_value);
                return;
            }

            // Store interpolation state in the work item's extra field
            const state_ptr = try self.allocator.create(StringInterpolationState);
            state_ptr.* = StringInterpolationState{
                .span = str_expr.span,
                .current_segment = 0,
                .segments_evaluated = std.ArrayList(builtins.str.RocStr).init(self.allocator),
            };

            // Schedule completion work
            self.schedule_work(WorkItem{
                .kind = .w_str_interpolation_combine,
                .expr_idx = expr_idx,
                .extra = @intFromPtr(state_ptr),
            });

            // Schedule evaluation of first segment
            self.schedule_work(WorkItem{
                .kind = .w_str_interpolation_segment,
                .expr_idx = segments[0],
                .extra = @intFromPtr(state_ptr),
            });
        },
        ```

#### **Task 2.3: String Segment Evaluation Handler**

*   **Goal**: Handle evaluation of individual string segments (both literals and expressions).
*   **Plan**:
    1.  **Implement `w_str_interpolation_segment` handler**:
        ```zig
        .w_str_interpolation_segment => {
            const state_ptr: *StringInterpolationState = @ptrFromInt(work_item.extra);
            const segments = self.env.store.sliceExpr(state_ptr.span);
            const current_expr = work_item.expr_idx;

            // Check what type of segment this is
            const segment_expr = self.env.store.getExpr(current_expr);
            switch (segment_expr) {
                .e_str_segment => |str_seg| {
                    // This is a literal string segment
                    const literal_content = self.env.strings.getName(str_seg.literal);
                    const segment_str = builtins.str.RocStr.fromSlice(literal_content, &self.roc_ops) catch |err| switch (err) {
                        error.OutOfMemory => {
                            self.traceWarn("Failed to create string segment, using empty");
                            builtins.str.RocStr.empty();
                        },
                        else => return error.StringSegmentEvaluationFailed,
                    };

                    try state_ptr.segments_evaluated.append(segment_str);
                    self.traceInfo("Added literal segment: \"{s}\"", .{literal_content});
                },
                else => {
                    // This is an interpolated expression - we need to evaluate it first
                    // Schedule work to convert the result to string after evaluation
                    self.schedule_work(WorkItem{
                        .kind = .w_str_interpolation_convert,
                        .expr_idx = current_expr,
                        .extra = @intFromPtr(state_ptr),
                    });

                    // Schedule evaluation of the expression
                    self.schedule_work(WorkItem{
                        .kind = .w_eval_expr,
                        .expr_idx = current_expr,
                    });

                    return; // Don't continue to next segment yet
                },
            }

            // Move to next segment
            state_ptr.current_segment += 1;
            if (state_ptr.current_segment < segments.len) {
                self.schedule_work(WorkItem{
                    .kind = .w_str_interpolation_segment,
                    .expr_idx = segments[state_ptr.current_segment],
                    .extra = @intFromPtr(state_ptr),
                });
            }
        },

        .w_str_interpolation_convert => {
            const state_ptr: *StringInterpolationState = @ptrFromInt(work_item.extra);

            // Pop the evaluated expression result
            const expr_result = try self.popStackValue(true); // cleanup=true

            // Convert the result to a string
            const string_result = try self.valueToString(expr_result);
            try state_ptr.segments_evaluated.append(string_result);

            self.traceInfo("Added interpolated segment (converted from {})", .{expr_result.layout.tag});

            // Continue with next segment
            const segments = self.env.store.sliceExpr(state_ptr.span);
            state_ptr.current_segment += 1;
            if (state_ptr.current_segment < segments.len) {
                self.schedule_work(WorkItem{
                    .kind = .w_str_interpolation_segment,
                    .expr_idx = segments[state_ptr.current_segment],
                    .extra = @intFromPtr(state_ptr),
                });
            }
        },
        ```

#### **Task 2.4: String Combination Handler**

*   **Goal**: Combine all evaluated string segments into a final `RocStr`.
*   **Plan**:
    1.  **Implement `w_str_interpolation_combine` handler**:
        ```zig
        .w_str_interpolation_combine => {
            const state_ptr: *StringInterpolationState = @ptrFromInt(work_item.extra);
            defer {
                state_ptr.deinit(self.allocator);
                self.allocator.destroy(state_ptr);
            }

            const layout_idx = try self.getLayoutIdx(Layout.str());
            const result_value = try self.pushStackValue(layout_idx);
            const result_ptr: *builtins.str.RocStr = @ptrCast(@alignCast(result_value.ptr.?));

            if (state_ptr.segments_evaluated.items.len == 0) {
                // No segments, create empty string
                result_ptr.* = builtins.str.RocStr.empty();
            } else if (state_ptr.segments_evaluated.items.len == 1) {
                // Single segment, just move it
                result_ptr.* = state_ptr.segments_evaluated.items[0];
                // Clear the list so deinit doesn't decref it
                state_ptr.segments_evaluated.clearRetainingCapacity();
            } else {
                // Multiple segments, concatenate them
                result_ptr.* = state_ptr.segments_evaluated.items[0];

                for (state_ptr.segments_evaluated.items[1..]) |segment| {
                    const new_result = builtins.str.strConcat(result_ptr.*, segment, &self.roc_ops) catch |err| switch (err) {
                        error.OutOfMemory => {
                            self.traceWarn("String concatenation failed during interpolation");
                            // Keep what we have so far
                            break;
                        },
                        else => return error.StringInterpolationFailed,
                    };

                    // Replace result with concatenated version
                    result_ptr.decref(&self.roc_ops);
                    result_ptr.* = new_result;
                }

                // Clear the list so deinit doesn't decref the segments we consumed
                state_ptr.segments_evaluated.clearRetainingCapacity();
            }

            try self.traceValue("interpolated_string", result_value);
        },
        ```

---

## **Part 3: Simple String Literals (`e_str_segment`)**

#### **Task 3.1: `e_str_segment` Evaluation**

*   **Goal**: Handle simple string literal segments that don't require interpolation.
*   **Plan**:
    1.  **Implement the `e_str_segment` case in `evalExpr`**:
        ```zig
        .e_str_segment => |str_seg| {
            // Get the string literal content
            const literal_content = self.env.strings.getName(str_seg.literal);

            // Allocate stack space for RocStr
            const layout_idx = try self.getLayoutIdx(Layout.str());
            const roc_str_value = try self.pushStackValue(layout_idx);
            const roc_str_ptr: *builtins.str.RocStr = @ptrCast(@alignCast(roc_str_value.ptr.?));

            // Initialize the RocStr
            roc_str_ptr.* = builtins.str.RocStr.fromSlice(literal_content, &self.roc_ops) catch |err| switch (err) {
                error.OutOfMemory => {
                    self.traceWarn("String literal allocation failed, using empty string");
                    builtins.str.RocStr.empty();
                },
                else => return error.StringAllocationFailed,
            };

            try self.traceValue("e_str_segment", roc_str_value);
        },
        ```

---

## **Part 4: Reference Counting & Memory Management**

#### **Task 4.1: Comprehensive Reference Counting**

*   **Goal**: Implement correct reference counting for strings and composite types containing strings to prevent memory leaks and use-after-free bugs.
*   **Plan**:
    1.  **Modify `popStackValue`**: Change its signature to `popStackValue(self: *Interpreter, cleanup: bool) !StackValue`. If `cleanup` is `true`, call a new `cleanupValue` helper.
    2.  **Implement `cleanupValue`**: This function recursively handles reference counting for all types:
        ```zig
        fn cleanupValue(self: *Interpreter, value: StackValue) EvalError!void {
            switch (value.layout.tag) {
                .scalar => switch (value.layout.data.scalar.tag) {
                    .str => {
                        if (value.ptr) |ptr| {
                            const roc_str: *builtins.str.RocStr = @ptrCast(@alignCast(ptr));
                            roc_str.decref(&self.roc_ops);
                            self.traceInfo("decref string at {*}", .{roc_str});
                        }
                    },
                    else => {},
                },
                .record => try self.cleanupRecordFields(value),
                .tuple => try self.cleanupTupleElements(value),
                .closure => try self.cleanupClosureCaptures(value),
                else => {},
            }
        }
        ```
    3.  **Implement composite type cleanup**: Add `cleanupRecordFields`, `cleanupTupleElements`, and `cleanupClosureCaptures` that iterate through fields and recursively call `cleanupValue`.
    4.  **Create `increfValue` helper**: This function increments reference counts when values are aliased:
        ```zig
        fn increfValue(self: *Interpreter, value: StackValue) EvalError!void {
            switch (value.layout.tag) {
                .scalar => switch (value.layout.data.scalar.tag) {
                    .str => {
                        if (value.ptr) |ptr| {
                            const roc_str: *builtins.str.RocStr = @ptrCast(@alignCast(ptr));
                            roc_str.incref(&self.roc_ops);
                            self.traceInfo("incref string at {*}", .{roc_str});
                        }
                    },
                    else => {},
                },
                .record => try self.increfRecordFields(value),
                .tuple => try self.increfTupleElements(value),
                .closure => try self.increfClosureCaptures(value),
                else => {},
            }
        }
        ```
    5.  **Integrate reference counting**: Call `increfValue` when values are aliased:
        *   In `e_lookup_local`, before pushing the found value to the stack.
        *   When arguments are passed to function calls (inside `handleLambdaCall`).
        *   When values are copied into record or tuple fields.
        *   When values are stored in closures.
        *   During string interpolation when segments are duplicated.
*   **Error Handling**:
    *   Wrap reference counting operations in error handling that logs warnings but continues evaluation.
    *   Add corruption detection by validating reference counts are within reasonable bounds.
*   **Tracing**:
    *   Log all `incref`/`decref` operations with the memory address and current reference count.
    *   Add `traceRefcountSummary()` that periodically reports reference counting statistics.

#### **Task 4.2: Enhanced Tracing for Strings**

*   **Goal**: Add comprehensive tracing for string operations.
*   **Plan**:
    1.  **Update `traceValue` for strings**:
        ```zig
        .str => {
            const roc_str: *const builtins.str.RocStr = @ptrCast(@alignCast(value.ptr.?));
            const content = roc_str.asSlice();
            const truncated = if (content.len > 50) content[0..47] ++ "..." else content;
            const size_type = if (roc_str.isSmallStr()) "small" else "big";
            const refcount = if (!roc_str.isSmallStr()) roc_str.refcount() else 1;
            writer.print("str({s},rc={}) \"{s}\"\n", .{ size_type, refcount, truncated }) catch {};
        },
        ```

---

## **Part 5: Builtin String Operations**

#### **Task 5.1: Builtin Detection and `Str.concat`**

*   **Goal**: Add support for `Str.concat` and other string builtins, including those generated by string interpolation desugaring.
*   **Plan**:
    1.  **Add builtin detection to `evalExpr`**: Add a new case for `e_call` expressions that checks if the call target is a builtin function:
        ```zig
        .e_call => |call_data| {
            if (try self.detectBuiltinCall(expr_idx, call_data)) {
                // Builtin was handled, continue with next work item
                return;
            } else {
                // Schedule regular lambda call
                self.schedule_work(WorkItem{
                    .kind = .w_lambda_call,
                    .expr_idx = expr_idx,
                    .extra = call_data.args.span.len,
                });
            }
        },
        ```
    2.  **Implement `detectBuiltinCall`**: This function examines the call target and arguments to determine if it's a known builtin:
        ```zig
        fn detectBuiltinCall(self: *Interpreter, expr_idx: ModuleEnv.Expr.Idx, call_data: anytype) !bool {
            const args = self.env.store.sliceExpr(call_data.args);
            if (args.len == 0) return false;
            
            const target_expr = self.env.store.getExpr(args[0]);
            switch (target_expr) {
                .e_lookup_external => |lookup| {
                    const symbol_name = self.env.idents.getName(lookup.name);
                    if (std.mem.eql(u8, symbol_name, "strConcat")) {
                        return self.handleStrConcatBuiltin(args[1..], call_data.called_via);
                    }
                    // Add other string builtins here
                },
                else => {},
            }
            return false;
        }
        ```
    3.  **Implement `handleStrConcatBuiltin`**: This function handles the `Str.concat` call:
        ```zig
        fn handleStrConcatBuiltin(self: *Interpreter, args: []const ModuleEnv.Expr.Idx, called_via: base.CalledVia) !bool {
            if (args.len != 2) {
                self.traceWarn("Str.concat expects exactly 2 arguments, got {}", .{args.len});
                return error.StringBuiltinFailed;
            }
            
            // Schedule completion work
            self.schedule_work(WorkItem{ 
                .kind = .w_str_concat_complete,
                .expr_idx = 0, // Not used for this work type
                .extra = if (called_via == .string_interpolation) 1 else 0, // Track interpolation context
            });
            
            // Schedule evaluation of both string arguments
            self.schedule_work(WorkItem{ .kind = .w_eval_expr, .expr_idx = args[1] });
            self.schedule_work(WorkItem{ .kind = .w_eval_expr, .expr_idx = args[0] });
            return true;
        }
        ```
    4.  **Add `w_str_concat_complete` work kind**: Handle the completion of string concatenation:
        ```zig
        .w_str_concat_complete => {
            const str2 = try self.popStackValue(true); // cleanup=true, consumes the string
            const str1 = try self.popStackValue(true); // cleanup=true, consumes the string
            
            const roc_str1: *const builtins.str.RocStr = @ptrCast(@alignCast(str1.ptr.?));
            const roc_str2: *const builtins.str.RocStr = @ptrCast(@alignCast(str2.ptr.?));
            
            // Allocate result on stack
            const result_layout_idx = try self.getLayoutIdx(Layout.str());
            const result_value = try self.pushStackValue(result_layout_idx);
            const result_ptr: *builtins.str.RocStr = @ptrCast(@alignCast(result_value.ptr.?));
            
            // Perform concatenation
            result_ptr.* = builtins.str.strConcat(roc_str1.*, roc_str2.*, &self.roc_ops) catch |err| switch (err) {
                error.OutOfMemory => {
                    self.traceWarn("String concatenation failed due to OOM, returning empty string");
                    builtins.str.RocStr.empty();
                },
                else => return error.StringBuiltinFailed,
            };
            
            const is_interpolation = work_item.extra != 0;
            if (is_interpolation) {
                self.traceInfo("concat_result (interpolation)");
            }
            try self.traceValue("concat_result", result_value);
        },
        ```
*   **Special Handling**: When `called_via == .string_interpolation`, this indicates the concatenation was generated by string interpolation desugaring, which can be useful for debugging and tracing.
*   **Ownership**: The two original `RocStr` arguments are consumed (and `decref`'d through `popStackValue(true)`). The new concatenated string has a reference count of 1 and is now owned by the stack.
*   **Error Recovery**: If concatenation fails, create an empty string and log a warning, allowing evaluation to continue.

---

## **Part 6: Validation & Testing**

#### **Task 6.1: String Interpolation Tests**

*   **Goal**: Comprehensive testing of string interpolation scenarios.
*   **Plan**:
    ```zig
    test "string interpolation - basic cases" {
        const test_cases = [_]struct { src: []const u8, expected: []const u8 }{
            .{ .src = "\"Hello ${\"world\"}\"", .expected = "Hello world" },
            .{ .src = "\"Count: ${42}\"", .expected = "Count: 42" },
            .{ .src = "\"${\"A\"} ${\"B\"} ${\"C\"}\"", .expected = "A B C" },
            .{ .src = "\"Result: ${1 + 2}\"", .expected = "Result: 3" },
        };
        // Test each case
    }

    test "string interpolation - empty and edge cases" {
        const test_cases = [_]struct { src: []const u8, expected: []const u8 }{
            .{ .src = "\"${\"\"}\"", .expected = "" },
            .{ .src = "\"${True}\"", .expected = "True" },
            .{ .src = "\"${False}\"", .expected = "False" },
        };
        // Test each case
    }

    test "string interpolation - memory management" {
        // Test that interpolated strings are properly reference counted
        // Test that failed interpolations don't leak memory
    }

    test "string interpolation - error recovery" {
        // Test behavior when interpolated expressions fail to evaluate
        // Verify that partial results are handled gracefully
    }
    ```

#### **Task 6.2: Integration Tests**

*   **Goal**: Test string interpolation within larger language constructs.
*   **Plan**:
    ```zig
    test "strings in complex expressions with interpolation" {
        const sources = [_][]const u8{
            "if True \"Hello ${\"world\"}\" else \"Goodbye\"",
            "{ greeting = \"Hello ${\"Alice\"}\", farewell = \"Goodbye ${\"Bob\"}\" }",
            "| name | \"Welcome ${name}\"",  // Lambda with string interpolation
        };
        // Test each case
    }
    ```

---

## **Summary**

This revised plan addresses the critical insight that Roc strings support interpolation with embedded expressions. The key changes:

1. **🔧 String Architecture Understanding**: Strings are `e_str` expressions with spans containing mixed literal and expression segments
2. **🔄 Interpolation Evaluation**: Multi-step evaluation process with state tracking for complex interpolated strings
3. **🔀 Type Conversion**: Infrastructure to convert any expression result to a string representation
4. **📊 Comprehensive Testing**: Extensive test coverage for interpolation scenarios, error cases, and memory management
5. **🛡️ Error Recovery**: Graceful handling of failed interpolations following "Inform Don't Block" philosophy

This approach ensures that both simple string literals (`"hello"`) and complex interpolated strings (`"Hello ${calculateName(user)}"`) are handled correctly while maintaining robust memory management and error recovery.
