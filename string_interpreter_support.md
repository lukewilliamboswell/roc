# Add String Support to the Interpreter

## Goals
- Evaluate string literals into `RocStr` on the interpreter stack.
- Manage heap via `RocOps` bridged to the interpreter’s allocator.
- Deallocate big strings via `decref` at the right points.
- Avoid aliasing bugs until `incref` semantics are intentionally introduced.

## Phase 1: String Literal Evaluation

### Task 1.1: Add RocOps allocator bridge
**Why**: `RocStr`’s heap behavior is driven via `RocOps` (alloc/realloc/dealloc). The interpreter’s allocator becomes the heap for Roc values and enables accounting in tests.

**Plan**:
- Add field to `Interpreter`:
  - `roc_ops: builtins.host_abi.RocOps`
- In `Interpreter.init`:
  - Initialize `roc_ops` with:
    - ctx: pointer to the interpreter’s `std.mem.Allocator`.
    - function pointers: `rocAlloc`, `rocRealloc`, `rocDealloc`
- Implement wrappers with exact `RocOps` ABI:
  - `rocAlloc(ctx, size, alignment) -> ?[*]u8`
  - `rocRealloc(ctx, old_ptr, old_size, new_size, alignment) -> ?[*]u8`
  - `rocDealloc(ctx, ptr, alignment) -> void`
- Respect `alignment` in all calls. Use aligned alloc/free. For realloc, if the allocator doesn't support it directly, allocate new, copy, and free old.
- No special work in `deinit` for `roc_ops`.

### Task 1.2: Implement e_str handling
**Why**: Create a `RocStr` using the builtin API and place it on the stack with the correct layout.

**Plan**:
- In `evalExpr`, implement `.e_str`:
  - Resolve the `Layout` for `Str` via the layout store. Ensure it corresponds to `@sizeOf(builtins.str.RocStr)` and `@alignOf(builtins.str.RocStr)`.
  - `pushStackValue` for that layout to reserve space on `stack_memory`.
  - Construct a `RocStr` using `RocStr.init(slice, &self.roc_ops)`.
  - Copy the resulting `RocStr` into the reserved location.
- **Ownership**: The `RocStr` instance now lives at the stack location and must be decref’d when the value is destroyed unless moved.

## Phase 2: Cleanup and Ownership

### Task 2.1: Enhance popStackValue for cleanup
**Why**: Centralize release of big-string references and avoid leaks.

**Plan**:
- Change signature: `popStackValue(self: *Interpreter, cleanup: bool) !StackValue`
- After popping:
  - If `cleanup` and layout is `Str`, call `decref` on the `RocStr` pointer using `&self.roc_ops`.
  - Small strings: `decref` is a no-op per the builtin's implementation; do not branch on small/big here.

### Task 2.2: Integrate cleanup in evaluation
**Why**: Ensure all discard paths release big strings; preserve values on move/return.

**Plan**:
- Replace discard pops with `popStackValue(true)` in:
  - `completeBinop` operands.
  - `checkIfCondition` condition value.
  - `w_block_cleanup` sites.
- Use `popStackValue(false)` when returning values from blocks/functions or moving a value.
- **Aliasing constraint for v1**: Do not create additional aliases of the same `RocStr` unless you also implement `incref`. Moves are safe; copies that leave both old and new live are not.

## Phase 3: Aggregates, Bindings, and Closures

### Task 3.1: Records/Tuples
**Why**: Ensure string fields in aggregates follow ownership rules.

**Plan**:
- When putting a `RocStr` into a record/tuple, use move semantics.
- When aggregates are cleaned up, ensure their string fields are decref'd.

### Task 3.2: Pattern binding
**Why**: Avoid dangling references to popped stack values.

**Plan**:
- If a binding references a stack value by pointer, never pop the underlying value before the binding ends.
- When copying a `RocStr` for a binding, treat it as a move.

### Task 3.3: Closures and captures
**Why**: Strings captured by closures may outlive the stack frame.

**Plan**:
- If capturing a `RocStr` by value, it must be moved into the closure's storage.
- Postpone aliasing patterns (e.g., one string captured by multiple closures) until `incref` is supported.

## Phase 4: Future Work (String operations and aliasing)

### Task 4.1: String operations
- Add `Str.concat`, `Str.trim`, etc., via builtins.
- For ops returning references or sharing strings, implement `incref` and `decref` correctly.

### Task 4.2: Incref semantics
- Introduce `incref` whenever aliasing is created.

## Phase 5: Tracing and Error Handling

### Task 5.1: Tracing
- Enhance `traceValue` for `Str` to print content and whether it's small/big.
- Add trace points for `roc_ops` calls and `decref`.

### Task 5.2: Error handling
- Ensure allocator wrappers return null on OOM and propagate it as an `EvalError`.

## Phase 6: Validation and Tests

### Core tests in `src/eval/test/eval_test.zig`
1.  **Evaluate small string**: Verify content and that no heap allocation occurs.
2.  **Evaluate large string**: Verify content and that heap allocation occurs and is freed.
3.  **String scope and cleanup**: Verify `decref` is called for big strings when they go out of scope.
4.  **Return string**: Verify a returned string is not prematurely deallocated.

### Additional tests
5.  **Aggregates containing strings**: Ensure fields are cleaned up correctly.
6.  **Binding and move semantics**: Ensure no double-free or leak occurs.
7.  **Control flow cleanup**: Ensure temporary strings in `if` branches are cleaned up.
8.  **Closure capture**: Test capture-by-value and cleanup.

### Success criteria
- All new tests pass and the allocator reports no leaks.
- No double-decref on moved values.
- No dangling references.
- Tracing shows the expected lifecycle for small and big strings.
