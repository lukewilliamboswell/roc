# META
~~~ini
description=Deep nesting with multiple captures - five-level nested lambda captures from all outer levels
type=expr
~~~
# SOURCE
~~~roc
|a| |b| |c| |d| |e| a + b + c + d + e
~~~
# EXPECTED
NIL
# PROBLEMS
NIL
# TOKENS
~~~zig
OpBar(1:1-1:2),LowerIdent(1:2-1:3),OpBar(1:3-1:4),OpBar(1:5-1:6),LowerIdent(1:6-1:7),OpBar(1:7-1:8),OpBar(1:9-1:10),LowerIdent(1:10-1:11),OpBar(1:11-1:12),OpBar(1:13-1:14),LowerIdent(1:14-1:15),OpBar(1:15-1:16),OpBar(1:17-1:18),LowerIdent(1:18-1:19),OpBar(1:19-1:20),LowerIdent(1:21-1:22),OpPlus(1:23-1:24),LowerIdent(1:25-1:26),OpPlus(1:27-1:28),LowerIdent(1:29-1:30),OpPlus(1:31-1:32),LowerIdent(1:33-1:34),OpPlus(1:35-1:36),LowerIdent(1:37-1:38),EndOfFile(1:38-1:38),
~~~
# PARSE
~~~clojure
(e-lambda @1.1-1.38
	(args
		(p-ident @1.2-1.3 (raw "a")))
	(e-lambda @1.5-1.38
		(args
			(p-ident @1.6-1.7 (raw "b")))
		(e-lambda @1.9-1.38
			(args
				(p-ident @1.10-1.11 (raw "c")))
			(e-lambda @1.13-1.38
				(args
					(p-ident @1.14-1.15 (raw "d")))
				(e-lambda @1.17-1.38
					(args
						(p-ident @1.18-1.19 (raw "e")))
					(e-binop @1.21-1.38 (op "+")
						(e-ident @1.21-1.22 (raw "a"))
						(e-binop @1.25-1.38 (op "+")
							(e-ident @1.25-1.26 (raw "b"))
							(e-binop @1.29-1.38 (op "+")
								(e-ident @1.29-1.30 (raw "c"))
								(e-binop @1.33-1.38 (op "+")
									(e-ident @1.33-1.34 (raw "d"))
									(e-ident @1.37-1.38 (raw "e")))))))))))
~~~
# FORMATTED
~~~roc
NO CHANGE
~~~
# CANONICALIZE
~~~clojure
(e-lambda @1.1-1.38
	(args
		(p-assign @1.2-1.3 (ident "a")))
	(e-lambda @1.5-1.38
		(args
			(p-assign @1.6-1.7 (ident "b")))
		(e-lambda @1.9-1.38
			(args
				(p-assign @1.10-1.11 (ident "c")))
			(e-lambda @1.13-1.38
				(args
					(p-assign @1.14-1.15 (ident "d")))
				(e-lambda @1.17-1.38
					(args
						(p-assign @1.18-1.19 (ident "e")))
					(captures
						(capture (name "a"))
						(capture (name "b"))
						(capture (name "c"))
						(capture (name "d")))
					(e-binop @1.21-1.38 (op "add")
						(e-lookup-local @1.21-1.22
							(p-assign @1.2-1.3 (ident "a")))
						(e-binop @1.25-1.38 (op "add")
							(e-lookup-local @1.25-1.26
								(p-assign @1.6-1.7 (ident "b")))
							(e-binop @1.29-1.38 (op "add")
								(e-lookup-local @1.29-1.30
									(p-assign @1.10-1.11 (ident "c")))
								(e-binop @1.33-1.38 (op "add")
									(e-lookup-local @1.33-1.34
										(p-assign @1.14-1.15 (ident "d")))
									(e-lookup-local @1.37-1.38
										(p-assign @1.18-1.19 (ident "e"))))))))))))
~~~
# TYPES
~~~clojure
(expr @1.1-1.38 (type "Num(_size) -> Num(_size2) -> Num(_size3) -> Num(_size4) -> Num(_size5) -> Num(_size6)"))
~~~
