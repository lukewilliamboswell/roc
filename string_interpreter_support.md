# Plan for Adding String Support to the Interpreter

This document outlines the plan to add support for `String` literals to the Roc interpreter in a minimal way. The implementation will focus on handling the `e_str` expression type in `src/eval/interpreter.zig` and correctly managing memory using the `RocStr` definitions from `src/builtins/str.zig`.

## Phase 1: String Literal Evaluation

The first phase is to enable the interpreter to recognize and evaluate string literals, creating `RocStr` values on its stack.

### Task 1.1: Establish `RocOps` for Memory Management

The `RocStr` builtin requires a `RocOps` struct to handle memory allocations.

1.  **In `src/eval/interpreter.zig`:**
2.  Add a `roc_ops: builtins.host_abi.RocOps` field to the `Interpreter` struct.
3.  In `Interpreter.init`, create and initialize the `roc_ops` instance. This will involve creating static wrapper functions (`rocAlloc`, `rocRealloc`, `rocDealloc`) that bridge Zig's `std.mem.Allocator` with the function pointer interface of `RocOps`. The interpreter's own allocator will be passed as the context pointer, effectively making it the "heap" for Roc values.

#### Memory Allocation Strategy

-   **Small Strings**: For strings that fit within the `RocStr` struct's inline buffer (`SMALL_STR_MAX_LENGTH`), no heap allocation is performed. The string data is stored directly on the interpreter's `stack_memory`.
-   **Large Strings**: For strings that exceed this size, `RocStr.init` will use the `roc_ops` function pointers to request a new allocation from the interpreter's main allocator. The `RocStr` on the stack will then hold a pointer to this heap-allocated buffer.

### Task 1.2: Implement `e_str` Expression Handling

This task involves teaching the interpreter what to do when it encounters a string literal (`e_str`).

1.  **In `src/eval/interpreter.zig`'s `evalExpr` function:**
2.  Locate the `case .e_str => ...` which is currently unimplemented.
3.  Get the layout for the string type. We will assume a `Layout` for `Str` can be resolved to represent `RocStr` with a size of `@sizeOf(RocStr)`.
4.  Use `pushStackValue` to allocate space for the `RocStr` struct on the interpreter's `stack_memory`.
5.  Call `builtins.str.RocStr.init()` using the string literal data from the `e_str` expression and the `roc_ops` instance created in Task 1.1.
6.  Copy the `RocStr` struct returned by `init` into the memory allocated on the stack.

## Phase 2: Memory Management for Strings

To prevent memory leaks, we must correctly manage the reference count of `RocStr` values. Big strings are reference-counted, and we must call `decref` when they are no longer needed.

### Task 2.1: Enhance `popStackValue` for Cleanup

We will modify the primary stack-popping function to handle the cleanup of reference-counted values.

1.  **In `src/eval/interpreter.zig`:**
2.  Modify `popStackValue` to accept a boolean `cleanup` parameter: `popStackValue(self: *Interpreter, cleanup: bool) !StackValue`.
3.  Inside the function, after popping a `Value`, check if `cleanup` is `true` and if the value's layout corresponds to a `Str`.
4.  If both are true, get a pointer to the `RocStr` on the stack and call its `decref(&self.roc_ops)` method.

### Task 2.2: Integrate Cleanup Logic

Update the interpreter's evaluation logic to use the new `popStackValue(true)` for cleanup.

1.  **In `src/eval/interpreter.zig`:**
2.  Review all calls to `popStackValue` or direct manipulations of `self.value_stack.items.len`.
3.  In places where values are consumed and discarded (e.g., operands in `completeBinop`, the condition in `checkIfCondition`, values in `w_block_cleanup`), replace the old pop logic with a call to `popStackValue(true)`.
4.  In places where a value is being moved or is the result of a function (e.g., the final result of a block or function call), use `popStackValue(false)` to avoid premature deallocation.

## Phase 3: Validation and Testing

We will add a suite of tests to `src/eval/test/eval_test.zig` to ensure the correctness of the string implementation.

### Test Cases

1.  **Evaluate Small String**: Test the evaluation of a string literal that fits within the small string optimization. Verify that the resulting `RocStr` is correct and no heap allocation occurs.
2.  **Evaluate Large String**: Test the evaluation of a string literal that exceeds the small string limit. Verify that the `RocStr` is correctly allocated on the heap.
3.  **String Scope and Cleanup**: Evaluate a Roc expression where a string is defined within a block and goes out of scope. Use a testing allocator to verify that `dealloc` is called for large strings, confirming that `decref` is working correctly.
4.  **Return String**: Evaluate a Roc expression that returns a string from a block or function. Verify that the string is not prematurely deallocated and the correct value is returned.

## Phase 4: Future Work

This plan covers the minimal implementation for string literals. Further work will be required to support a full range of string operations.

*   **String Operations**: Implement handlers for binary operations (`Str.concat`) and function calls (`Str.split`, `Str.trim`, etc.) by calling the corresponding functions in `builtins/str.zig`.
*   **Reference Count `incref`**: Ensure that operations that share strings correctly increment their reference counts to prevent use-after-free bugs. For example, when a string is passed to multiple functions or stored in multiple data structures.