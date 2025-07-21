# META
~~~ini
description=Comprehensive lambda capture detection with multiple scenarios
type=expr
~~~
# SOURCE
~~~roc
{
    basic: |x| |y| x + y,
    multi: |a, b| |c| a + b + c,
    nested: |outer| |middle| |inner| outer + middle + inner,
    simple: |x| x + 1,
    mixed: |base| |n| n + base,
}
~~~
# EXPECTED
NIL
# PROBLEMS
NIL
# TOKENS
~~~zig
OpenCurly(1:1-1:2),
LowerIdent(2:5-2:10),OpColon(2:10-2:11),OpBar(2:12-2:13),LowerIdent(2:13-2:14),OpBar(2:14-2:15),OpBar(2:16-2:17),LowerIdent(2:17-2:18),OpBar(2:18-2:19),LowerIdent(2:20-2:21),OpPlus(2:22-2:23),LowerIdent(2:24-2:25),Comma(2:25-2:26),
LowerIdent(3:5-3:10),OpColon(3:10-3:11),OpBar(3:12-3:13),LowerIdent(3:13-3:14),Comma(3:14-3:15),LowerIdent(3:16-3:17),OpBar(3:17-3:18),OpBar(3:19-3:20),LowerIdent(3:20-3:21),OpBar(3:21-3:22),LowerIdent(3:23-3:24),OpPlus(3:25-3:26),LowerIdent(3:27-3:28),OpPlus(3:29-3:30),LowerIdent(3:31-3:32),Comma(3:32-3:33),
LowerIdent(4:5-4:11),OpColon(4:11-4:12),OpBar(4:13-4:14),LowerIdent(4:14-4:19),OpBar(4:19-4:20),OpBar(4:21-4:22),LowerIdent(4:22-4:28),OpBar(4:28-4:29),OpBar(4:30-4:31),LowerIdent(4:31-4:36),OpBar(4:36-4:37),LowerIdent(4:38-4:43),OpPlus(4:44-4:45),LowerIdent(4:46-4:52),OpPlus(4:53-4:54),LowerIdent(4:55-4:60),Comma(4:60-4:61),
LowerIdent(5:5-5:11),OpColon(5:11-5:12),OpBar(5:13-5:14),LowerIdent(5:14-5:15),OpBar(5:15-5:16),LowerIdent(5:17-5:18),OpPlus(5:19-5:20),Int(5:21-5:22),Comma(5:22-5:23),
LowerIdent(6:5-6:10),OpColon(6:10-6:11),OpBar(6:12-6:13),LowerIdent(6:13-6:17),OpBar(6:17-6:18),OpBar(6:19-6:20),LowerIdent(6:20-6:21),OpBar(6:21-6:22),LowerIdent(6:23-6:24),OpPlus(6:25-6:26),LowerIdent(6:27-6:31),Comma(6:31-6:32),
CloseCurly(7:1-7:2),EndOfFile(7:2-7:2),
~~~
# PARSE
~~~clojure
(e-record @1.1-7.2
	(field (field "basic")
		(e-lambda @2.12-2.25
			(args
				(p-ident @2.13-2.14 (raw "x")))
			(e-lambda @2.16-2.25
				(args
					(p-ident @2.17-2.18 (raw "y")))
				(e-binop @2.20-2.25 (op "+")
					(e-ident @2.20-2.21 (raw "x"))
					(e-ident @2.24-2.25 (raw "y"))))))
	(field (field "multi")
		(e-lambda @3.12-3.32
			(args
				(p-ident @3.13-3.14 (raw "a"))
				(p-ident @3.16-3.17 (raw "b")))
			(e-lambda @3.19-3.32
				(args
					(p-ident @3.20-3.21 (raw "c")))
				(e-binop @3.23-3.32 (op "+")
					(e-ident @3.23-3.24 (raw "a"))
					(e-binop @3.27-3.32 (op "+")
						(e-ident @3.27-3.28 (raw "b"))
						(e-ident @3.31-3.32 (raw "c")))))))
	(field (field "nested")
		(e-lambda @4.13-4.60
			(args
				(p-ident @4.14-4.19 (raw "outer")))
			(e-lambda @4.21-4.60
				(args
					(p-ident @4.22-4.28 (raw "middle")))
				(e-lambda @4.30-4.60
					(args
						(p-ident @4.31-4.36 (raw "inner")))
					(e-binop @4.38-4.60 (op "+")
						(e-ident @4.38-4.43 (raw "outer"))
						(e-binop @4.46-4.60 (op "+")
							(e-ident @4.46-4.52 (raw "middle"))
							(e-ident @4.55-4.60 (raw "inner"))))))))
	(field (field "simple")
		(e-lambda @5.13-5.22
			(args
				(p-ident @5.14-5.15 (raw "x")))
			(e-binop @5.17-5.22 (op "+")
				(e-ident @5.17-5.18 (raw "x"))
				(e-int @5.21-5.22 (raw "1")))))
	(field (field "mixed")
		(e-lambda @6.12-6.31
			(args
				(p-ident @6.13-6.17 (raw "base")))
			(e-lambda @6.19-6.31
				(args
					(p-ident @6.20-6.21 (raw "n")))
				(e-binop @6.23-6.31 (op "+")
					(e-ident @6.23-6.24 (raw "n"))
					(e-ident @6.27-6.31 (raw "base")))))))
~~~
# FORMATTED
~~~roc
{
	basic: |x| |y| x + y,
	multi: |a, b| |c| a + b + c,
	nested: |outer| |middle| |inner| outer + middle + inner,
	simple: |x| x + 1,
	mixed: |base| |n| n + base,
}
~~~
# CANONICALIZE
~~~clojure
(e-record @1.1-7.2
	(fields
		(field (name "basic")
			(e-lambda @2.12-2.25
				(args
					(p-assign @2.13-2.14 (ident "x")))
				(e-lambda @2.16-2.25
					(args
						(p-assign @2.17-2.18 (ident "y")))
					(captures
						(capture (name "x")))
					(e-binop @2.20-2.25 (op "add")
						(e-lookup-local @2.20-2.21
							(p-assign @2.13-2.14 (ident "x")))
						(e-lookup-local @2.24-2.25
							(p-assign @2.17-2.18 (ident "y")))))))
		(field (name "multi")
			(e-lambda @3.12-3.32
				(args
					(p-assign @3.13-3.14 (ident "a"))
					(p-assign @3.16-3.17 (ident "b")))
				(e-lambda @3.19-3.32
					(args
						(p-assign @3.20-3.21 (ident "c")))
					(captures
						(capture (name "a"))
						(capture (name "b")))
					(e-binop @3.23-3.32 (op "add")
						(e-lookup-local @3.23-3.24
							(p-assign @3.13-3.14 (ident "a")))
						(e-binop @3.27-3.32 (op "add")
							(e-lookup-local @3.27-3.28
								(p-assign @3.16-3.17 (ident "b")))
							(e-lookup-local @3.31-3.32
								(p-assign @3.20-3.21 (ident "c"))))))))
		(field (name "nested")
			(e-lambda @4.13-4.60
				(args
					(p-assign @4.14-4.19 (ident "outer")))
				(e-lambda @4.21-4.60
					(args
						(p-assign @4.22-4.28 (ident "middle")))
					(e-lambda @4.30-4.60
						(args
							(p-assign @4.31-4.36 (ident "inner")))
						(captures
							(capture (name "outer"))
							(capture (name "middle")))
						(e-binop @4.38-4.60 (op "add")
							(e-lookup-local @4.38-4.43
								(p-assign @4.14-4.19 (ident "outer")))
							(e-binop @4.46-4.60 (op "add")
								(e-lookup-local @4.46-4.52
									(p-assign @4.22-4.28 (ident "middle")))
								(e-lookup-local @4.55-4.60
									(p-assign @4.31-4.36 (ident "inner")))))))))
		(field (name "simple")
			(e-lambda @5.13-5.22
				(args
					(p-assign @5.14-5.15 (ident "x")))
				(e-binop @5.17-5.22 (op "add")
					(e-lookup-local @5.17-5.18
						(p-assign @5.14-5.15 (ident "x")))
					(e-int @5.21-5.22 (value "1")))))
		(field (name "mixed")
			(e-lambda @6.12-6.31
				(args
					(p-assign @6.13-6.17 (ident "base")))
				(e-lambda @6.19-6.31
					(args
						(p-assign @6.20-6.21 (ident "n")))
					(captures
						(capture (name "base")))
					(e-binop @6.23-6.31 (op "add")
						(e-lookup-local @6.23-6.24
							(p-assign @6.20-6.21 (ident "n")))
						(e-lookup-local @6.27-6.31
							(p-assign @6.13-6.17 (ident "base")))))))))
~~~
# TYPES
~~~clojure
(expr @1.1-7.2 (type "{ basic: Num(_size) -> Num(_size2) -> Num(_size3), multi: Num(_size4), Num(_size5) -> Num(_size6) -> Num(_size7), nested: Num(_size8) -> Num(_size9) -> Num(_size10) -> Num(_size11), simple: Num(_size12) -> Num(_size13), mixed: Num(_size14) -> Num(_size15) -> Num(_size16) }"))
~~~
