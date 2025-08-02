# A Robust Plan for Interpreter String Support

This plan integrates full reference counting, error handling, and tracing from the start to ensure a correct, maintainable, and reliable implementation.

---

### **Part 1: Core `RocStr` Lifecycle & Memory Management**

This part establishes the foundation for creating and destroying strings.

#### **Task 1.1: `RocOps` Allocator Bridge**

*   **Goal**: Bridge the interpreter's allocator to the `RocStr` builtin, enabling heap allocation for large strings.
*   **Plan**:
    1.  Add `roc_ops: builtins.host_abi.RocOps` to the `Interpreter` struct.
    2.  In `Interpreter.init`, initialize `roc_ops` by pointing its `ctx` to the interpreter's allocator and wiring up static `rocAlloc`, `rocRealloc`, and `rocDealloc` wrapper functions.
*   **Error Handling & Assertions**:
    *   The `rocAlloc`/`rocRealloc` wrappers must handle allocation failures from the underlying allocator by returning `null`. This allows `RocStr` to gracefully handle out-of-memory (OOM) conditions.
    *   Assert that `alignment` parameters are respected.
*   **Tracing**:
    *   Add `traceInfo` calls inside the `rocAlloc`, `rocRealloc`, and `rocDealloc` wrappers to log heap activity (e.g., "rocAlloc: requested {d} bytes, got ptr {}"). This is crucial for debugging memory management.

#### **Task 1.2: `e_str` Literal Evaluation**

*   **Goal**: Evaluate a string literal (`e_str`) into a `RocStr` on the interpreter's stack.
*   **Plan**:
    1.  In `evalExpr`, implement the `.e_str` case.
    2.  Resolve the `Layout` for `Str`.
    3.  Use `pushStackValue` to reserve space for the `RocStr` struct.
    4.  Call `builtins.str.RocStr.init()` with the literal's slice and `&self.roc_ops`.
    5.  Copy the resulting `RocStr` struct to the stack.
*   **Error Handling & Assertions**:
    *   Add `std.debug.assert(layout_size == @sizeOf(RocStr))` to prevent regressions if the `RocStr` struct changes.
    *   Properly handle a potential OOM error returned from `RocStr.init` by propagating an `EvalError.OutOfMemory`.
*   **Tracing**:
    *   In `traceValue`, add a case for `Str` to print its content and whether it is "small" or "big".
    *   After creating a string in the `.e_str` handler, trace the new value.

#### **Task 1.3: Reference Counting (`incref` & `decref`)**

*   **Goal**: Implement correct reference counting to prevent memory leaks and use-after-free bugs.
*   **Plan**:
    1.  **Modify `popStackValue`**: Change its signature to `popStackValue(self: *Interpreter, cleanup: bool) !StackValue`. If `cleanup` is `true` and the value is a `Str`, it **must** call `decref` on the `RocStr`.
    2.  **Create `increfStackValue` helper**: This function will take a `StackValue`. If the value is a `Str`, it will call `incref` on the `RocStr`.
    3.  **Integrate `incref`**: Call `increfStackValue` whenever a `RocStr` is aliased:
        *   In `e_lookup_local`, before pushing the found value to the stack.
        *   When a string is passed as a function argument (inside `handleLambdaCall`).
        *   When a string is copied into a record or tuple field.
    4.  **Integrate `decref`**: Use `popStackValue(true)` in all code paths where a temporary value is discarded (e.g., after a `completeBinop`, for an `if` condition). Use `popStackValue(false)` only when moving a value that will be cleaned up later (e.g., returning from a function).
*   **Tracing**:
    *   Inside `popStackValue`, trace when `decref` is called on a string.
    *   Inside `increfStackValue`, trace when `incref` is called.

---

### **Part 2: Builtin String Operations (`Str.concat`)**

*   **Goal**: Add support for the `Str.concat` builtin function to prove the architecture for handling string operations.
*   **Plan**:
    1.  **Identify `Str.concat` Calls**: In the `handleLambdaCall` logic, add a mechanism to detect when the function being called is the `Str.concat` builtin. This can be done by inspecting the function's name from the CIR.
    2.  **Handle the Builtin Call**: When a `Str.concat` call is identified, instead of proceeding with the generic lambda call logic, we will:
        *   Pop the two `RocStr` arguments from the stack. Since `strConcat` consumes them, we will pop them with cleanup to ensure `decref` is called.
        *   Call the `builtins.str.strConcat` function, passing the two popped strings and `&self.roc_ops`.
        *   Push the new `RocStr` returned by the function onto the stack.
        *   The work for the call is now complete, so we will not schedule a `w_lambda_return`.
*   **Ownership**: The two original `RocStr` arguments are consumed (and `decref`'d). The new concatenated string returned by `strConcatC` has a reference count of 1 and is now owned by the stack.

---

### **Part 3: Validation & Testing**

*   **Goal**: Create a comprehensive test suite in `src/eval/test/eval_test.zig` to validate correctness, reliability, and the handling of edge cases.
*   **Plan**:
    1.  **Small & Large Strings**: Test creation, returning, and cleanup. Use a `std.testing.allocator` to assert that `alloc` is called for large strings and not for small ones, and that `dealloc` is always called for large strings upon cleanup.
    2.  **Reference Counting**:
        *   Create a large string, bind it to a name, and then use that name twice in a tuple `(s, s)`. Verify with tracing and the testing allocator that `incref` is called once and `decref` is called twice.
        *   Verify that returning a string from a function does not cause a use-after-free.
    3.  **`Str.concat` Test**: Concatenate two large strings and verify the result is correct and that the original strings are properly deallocated.
    4.  **Unhappy Path (OOM)**: Create a test that uses a special allocator designed to fail after a certain number of allocations. Attempt to create a large string and assert that the interpreter correctly returns `EvalError.OutOfMemory` instead of crashing.
