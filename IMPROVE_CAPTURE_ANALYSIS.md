# Plan: Improve Capture Analysis in Canonicalization

## 1. Goal

The primary goal is to shift the responsibility of complete and accurate lambda capture analysis from the interpreter to the canonicalization phase of the compiler. This will provide the interpreter with a definitive list of all required captures for every lambda, eliminating the need for the recursive, runtime analysis that currently exists as a workaround.

## 2. Background & Motivation

Currently, the capture analysis performed during canonicalization is incomplete and flawed. This forced the implementation of a workaround (`findCapturesInExpr`) within the interpreter to re-analyze the expression tree at runtime. This approach has two main drawbacks:

1.  **Inefficiency:** It performs redundant analysis during evaluation that should be handled once at compile-time.
2.  **Poor Design:** It breaks the separation of concerns. The interpreter, which should focus on execution, is burdened with a complex static analysis task.

By moving this logic into the canonicalization step, we can create a more robust, efficient, and maintainable system.

## 3. The Flaw in Canonicalization vs. The Interpreter's Workaround

The core of the problem lies in how scopes are handled during free variable analysis.

The interpreter's `findCapturesInExpr` function performs a **correct** recursive traversal. When it descends into a nested lambda, it correctly adds the nested lambda's parameters to its set of "bound" variables for the scope of that nested body. This prevents variables bound in an inner scope from being incorrectly identified as free in an outer scope.

The current canonicalization logic is flawed because it does not do this. It appears to collect all variable lookups from a lambda's body and subtract only the lambda's own parameters, without accounting for new scopes introduced by nested lambdas.

For example, in `(|y| (|x| (|z| x + y + z)(3))(2))(1)`, the canonicalizer incorrectly determines that the outermost lambda `|y|...` captures `x` and `z`. This is because it sees `x` and `z` used "somewhere inside" the body, but fails to recognize they are bound by the inner lambdas and are therefore not free variables in the outer scope.

## 4. Proposed Implementation Plan (Single-Pass Approach)

We will integrate a correct free variable analysis directly into the existing `canonicalize_expr` function. This is more efficient as it avoids a second traversal of the expression tree.

### 4.1. The Traversal Algorithm

The core idea is to modify `canonicalize_expr` to return not only the canonicalized `CIR.Expr.Idx`, but also the set of **free variables** discovered within that expression.

-   **Free Variables:** A variable is "free" in an expression if it is used within that expression but is not defined (bound) within that same expression.

The logic for the modified `canonicalize_expr` function would be as follows:

1.  **Modify Function Signature:** The function signature will change from `(env, ast_node) -> CIR.Expr.Idx` to `(env, ast_node) -> CanonicalizedExpr`, where `CanonicalizedExpr` is a struct containing `{ idx: CIR.Expr.Idx, free_vars: ?[]CIR.Pattern.Idx }`. The free variables will be managed using a scratch buffer (`scratch_free_vars`) and returned as a slice.

2.  **Base Cases:**
    *   When canonicalizing an `e_lookup_local` node, the function returns the new `CIR.Expr.Idx` and a `free_vars` slice containing just that single variable.
    *   For literals (`e_int`, `e_str`, etc.), it returns the `CIR.Expr.Idx` and an empty (or `null`) `free_vars` slice.

3.  **Recursive Step (Compound Expressions):**
    *   When canonicalizing a node like `e_binop`, `e_if`, `e_block`, or `e_call`, the function will first recursively call itself on all children expressions.
    *   It will then **union** the `free_vars` slices returned from these recursive calls to compute the set of free variables for the compound expression. This unioned set is then returned to its caller.

4.  **Special Case (`e_lambda`):**
    *   When canonicalizing a lambda, first recursively call `canonicalize_expr` on its body. This will return the body's `CIR.Expr.Idx` and its set of free variables.
    *   Determine the set of variables that are bound by the lambda's own parameters (e.g., by traversing the `lambda.args` patterns).
    *   The **true captures** for the lambda are the free variables of its body **minus** the variables bound by its parameters.
    *   This final, correct set of captures should be stored in the `lambda.captures` field in the CIR.
    *   The set of free variables that the lambda canonicalization function returns to *its* parent is this same set of true captures. The parent will then correctly handle them as free variables within its own body.

### 4.2. Implementation Steps

1.  **Update `canonicalizeExpr` Signature:**
    *   Change the return type of `canonicalizeExpr` and its helpers to `!?CanonicalizedExpr`.
    *   Update all call sites to handle the new struct. This includes receiving the `free_vars` slice and passing it up the call stack, unioning it with sets from sibling expressions.

2.  **Implement Free Variable Logic:**
    *   **`e_lookup_local`:** When a local variable is looked up, it is a free variable in the context of the current expression. Return a `CanonicalizedExpr` containing its `pattern_idx` in the `free_vars` slice.
    *   **Compound Expressions (`e_binop`, `e_if`, etc.):** After recursively canonicalizing children, union their returned `free_vars` slices.
    *   **`e_lambda`:** This is the most critical part.
        *   Recursively call `canonicalizeExpr` on the lambda body to get its free variables.
        *   Create a set of variables bound by the lambda's parameters.
        *   The lambda's **true captures** are `(body's free variables) - (lambda's parameters)`.
        *   Store this set in the `CIR.Expr.Lambda`'s `captures` field.
        *   The `free_vars` slice returned by the lambda's canonicalization to its parent must *also* be this same set of true captures.

3.  **Simplify the Interpreter:**
    *   Once the canonicalization is correct and all tests pass, the interpreter can be simplified.
    *   Delete the `findCapturesInExpr` function.
    *   Simplify `collectAndFilterCaptures` to trust and directly use the `lambda.captures` list from the CIR, without any filtering or re-analysis.

## 5. Expected Benefits

-   **Correctness by Design:** Capture analysis will be a well-defined, compile-time step.
-   **Performance:** The interpreter will be faster, and the compiler avoids a second, full traversal of the CIR.
-   **Improved Architecture:** A cleaner separation of concerns between the compiler's static analysis and the interpreter's execution logic.
