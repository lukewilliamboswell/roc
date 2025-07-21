# META
~~~ini
description=Fully applied lambda with captures - (|a,b| |c| a + b + c)(1,2)(3) should equal 6
type=expr
~~~
# SOURCE
~~~roc
(|a, b| |c| a + b + c)(1, 2)(3)
~~~
# EXPECTED
NIL
# PROBLEMS
NIL
# TOKENS
~~~zig
OpenRound(1:1-1:2),OpBar(1:2-1:3),LowerIdent(1:3-1:4),Comma(1:4-1:5),LowerIdent(1:6-1:7),OpBar(1:7-1:8),OpBar(1:9-1:10),LowerIdent(1:10-1:11),OpBar(1:11-1:12),LowerIdent(1:13-1:14),OpPlus(1:15-1:16),LowerIdent(1:17-1:18),OpPlus(1:19-1:20),LowerIdent(1:21-1:22),CloseRound(1:22-1:23),NoSpaceOpenRound(1:23-1:24),Int(1:24-1:25),Comma(1:25-1:26),Int(1:27-1:28),CloseRound(1:28-1:29),NoSpaceOpenRound(1:29-1:30),Int(1:30-1:31),CloseRound(1:31-1:32),EndOfFile(1:32-1:32),
~~~
# PARSE
~~~clojure
(e-apply @1.1-1.29
	(e-tuple @1.1-1.23
		(e-lambda @1.2-1.22
			(args
				(p-ident @1.3-1.4 (raw "a"))
				(p-ident @1.6-1.7 (raw "b")))
			(e-lambda @1.9-1.22
				(args
					(p-ident @1.10-1.11 (raw "c")))
				(e-binop @1.13-1.22 (op "+")
					(e-ident @1.13-1.14 (raw "a"))
					(e-binop @1.17-1.22 (op "+")
						(e-ident @1.17-1.18 (raw "b"))
						(e-ident @1.21-1.22 (raw "c")))))))
	(e-int @1.24-1.25 (raw "1"))
	(e-int @1.27-1.28 (raw "2")))
~~~
# FORMATTED
~~~roc
(|a, b| |c| a + b + c)(1, 2)
~~~
# CANONICALIZE
~~~clojure
(e-call @1.1-1.29
	(e-lambda @1.2-1.22
		(args
			(p-assign @1.3-1.4 (ident "a"))
			(p-assign @1.6-1.7 (ident "b")))
		(e-lambda @1.9-1.22
			(args
				(p-assign @1.10-1.11 (ident "c")))
			(captures
				(capture (name "a"))
				(capture (name "b")))
			(e-binop @1.13-1.22 (op "add")
				(e-lookup-local @1.13-1.14
					(p-assign @1.3-1.4 (ident "a")))
				(e-binop @1.17-1.22 (op "add")
					(e-lookup-local @1.17-1.18
						(p-assign @1.6-1.7 (ident "b")))
					(e-lookup-local @1.21-1.22
						(p-assign @1.10-1.11 (ident "c")))))))
	(e-int @1.24-1.25 (value "1"))
	(e-int @1.27-1.28 (value "2")))
~~~
# TYPES
~~~clojure
(expr @1.1-1.29 (type "Num(_size) -> Num(_size2)"))
~~~
