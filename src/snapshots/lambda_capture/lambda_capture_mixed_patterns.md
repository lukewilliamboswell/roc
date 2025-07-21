# META
~~~ini
description=Mixed capture patterns in block expression - some lambdas capture, others don't
type=expr
~~~
# SOURCE
~~~roc
|base| {
    simple = |x| base + 1
    no_capture = |y| y * 2
    multi_capture = |a, b| base + a + b
    
    simple(1)
}
~~~
# EXPECTED
UNUSED VARIABLE - lambda_capture_mixed_patterns.md:2:15:2:16
UNUSED VARIABLE - lambda_capture_mixed_patterns.md:3:5:3:15
UNUSED VARIABLE - lambda_capture_mixed_patterns.md:4:5:4:18
# PROBLEMS
**UNUSED VARIABLE**
Variable `x` is not used anywhere in your code.

If you don't need this variable, prefix it with an underscore like `_x` to suppress this warning.
The unused variable is declared here:
**lambda_capture_mixed_patterns.md:2:15:2:16:**
```roc
    simple = |x| base + 1
```
              ^


**UNUSED VARIABLE**
Variable `no_capture` is not used anywhere in your code.

If you don't need this variable, prefix it with an underscore like `_no_capture` to suppress this warning.
The unused variable is declared here:
**lambda_capture_mixed_patterns.md:3:5:3:15:**
```roc
    no_capture = |y| y * 2
```
    ^^^^^^^^^^


**UNUSED VARIABLE**
Variable `multi_capture` is not used anywhere in your code.

If you don't need this variable, prefix it with an underscore like `_multi_capture` to suppress this warning.
The unused variable is declared here:
**lambda_capture_mixed_patterns.md:4:5:4:18:**
```roc
    multi_capture = |a, b| base + a + b
```
    ^^^^^^^^^^^^^


# TOKENS
~~~zig
OpBar(1:1-1:2),LowerIdent(1:2-1:6),OpBar(1:6-1:7),OpenCurly(1:8-1:9),
LowerIdent(2:5-2:11),OpAssign(2:12-2:13),OpBar(2:14-2:15),LowerIdent(2:15-2:16),OpBar(2:16-2:17),LowerIdent(2:18-2:22),OpPlus(2:23-2:24),Int(2:25-2:26),
LowerIdent(3:5-3:15),OpAssign(3:16-3:17),OpBar(3:18-3:19),LowerIdent(3:19-3:20),OpBar(3:20-3:21),LowerIdent(3:22-3:23),OpStar(3:24-3:25),Int(3:26-3:27),
LowerIdent(4:5-4:18),OpAssign(4:19-4:20),OpBar(4:21-4:22),LowerIdent(4:22-4:23),Comma(4:23-4:24),LowerIdent(4:25-4:26),OpBar(4:26-4:27),LowerIdent(4:28-4:32),OpPlus(4:33-4:34),LowerIdent(4:35-4:36),OpPlus(4:37-4:38),LowerIdent(4:39-4:40),
LowerIdent(6:5-6:11),NoSpaceOpenRound(6:11-6:12),Int(6:12-6:13),CloseRound(6:13-6:14),
CloseCurly(7:1-7:2),EndOfFile(7:2-7:2),
~~~
# PARSE
~~~clojure
(e-lambda @1.1-7.2
	(args
		(p-ident @1.2-1.6 (raw "base")))
	(e-block @1.8-7.2
		(statements
			(s-decl @2.5-2.26
				(p-ident @2.5-2.11 (raw "simple"))
				(e-lambda @2.14-2.26
					(args
						(p-ident @2.15-2.16 (raw "x")))
					(e-binop @2.18-2.26 (op "+")
						(e-ident @2.18-2.22 (raw "base"))
						(e-int @2.25-2.26 (raw "1")))))
			(s-decl @3.5-3.27
				(p-ident @3.5-3.15 (raw "no_capture"))
				(e-lambda @3.18-3.27
					(args
						(p-ident @3.19-3.20 (raw "y")))
					(e-binop @3.22-3.27 (op "*")
						(e-ident @3.22-3.23 (raw "y"))
						(e-int @3.26-3.27 (raw "2")))))
			(s-decl @4.5-4.40
				(p-ident @4.5-4.18 (raw "multi_capture"))
				(e-lambda @4.21-4.40
					(args
						(p-ident @4.22-4.23 (raw "a"))
						(p-ident @4.25-4.26 (raw "b")))
					(e-binop @4.28-4.40 (op "+")
						(e-ident @4.28-4.32 (raw "base"))
						(e-binop @4.35-4.40 (op "+")
							(e-ident @4.35-4.36 (raw "a"))
							(e-ident @4.39-4.40 (raw "b"))))))
			(e-apply @6.5-6.14
				(e-ident @6.5-6.11 (raw "simple"))
				(e-int @6.12-6.13 (raw "1"))))))
~~~
# FORMATTED
~~~roc
|base| {
	simple = |x| base + 1
	no_capture = |y| y * 2
	multi_capture = |a, b| base + a + b

	simple(1)
}
~~~
# CANONICALIZE
~~~clojure
(e-lambda @1.1-7.2
	(args
		(p-assign @1.2-1.6 (ident "base")))
	(e-block @1.8-7.2
		(s-let @2.5-2.26
			(p-assign @2.5-2.11 (ident "simple"))
			(e-lambda @2.14-2.26
				(args
					(p-assign @2.15-2.16 (ident "x")))
				(captures
					(capture (name "base")))
				(e-binop @2.18-2.26 (op "add")
					(e-lookup-local @2.18-2.22
						(p-assign @1.2-1.6 (ident "base")))
					(e-int @2.25-2.26 (value "1")))))
		(s-let @3.5-3.27
			(p-assign @3.5-3.15 (ident "no_capture"))
			(e-lambda @3.18-3.27
				(args
					(p-assign @3.19-3.20 (ident "y")))
				(e-binop @3.22-3.27 (op "mul")
					(e-lookup-local @3.22-3.23
						(p-assign @3.19-3.20 (ident "y")))
					(e-int @3.26-3.27 (value "2")))))
		(s-let @4.5-4.40
			(p-assign @4.5-4.18 (ident "multi_capture"))
			(e-lambda @4.21-4.40
				(args
					(p-assign @4.22-4.23 (ident "a"))
					(p-assign @4.25-4.26 (ident "b")))
				(captures
					(capture (name "base")))
				(e-binop @4.28-4.40 (op "add")
					(e-lookup-local @4.28-4.32
						(p-assign @1.2-1.6 (ident "base")))
					(e-binop @4.35-4.40 (op "add")
						(e-lookup-local @4.35-4.36
							(p-assign @4.22-4.23 (ident "a")))
						(e-lookup-local @4.39-4.40
							(p-assign @4.25-4.26 (ident "b")))))))
		(e-call @6.5-6.14
			(e-lookup-local @6.5-6.11
				(p-assign @2.5-2.11 (ident "simple")))
			(e-int @6.12-6.13 (value "1")))))
~~~
# TYPES
~~~clojure
(expr @1.1-7.2 (type "Num(_size) -> Num(_size2)"))
~~~
