# META
~~~ini
description=Multiple variable captures - inner lambda captures multiple outer variables
type=expr
~~~
# SOURCE
~~~roc
|a, b| |c| a + b + c
~~~
# EXPECTED
NIL
# PROBLEMS
NIL
# TOKENS
~~~zig
OpBar(1:1-1:2),LowerIdent(1:2-1:3),Comma(1:3-1:4),LowerIdent(1:5-1:6),OpBar(1:6-1:7),OpBar(1:8-1:9),LowerIdent(1:9-1:10),OpBar(1:10-1:11),LowerIdent(1:12-1:13),OpPlus(1:14-1:15),LowerIdent(1:16-1:17),OpPlus(1:18-1:19),LowerIdent(1:20-1:21),EndOfFile(1:21-1:21),
~~~
# PARSE
~~~clojure
(e-lambda @1.1-1.21
	(args
		(p-ident @1.2-1.3 (raw "a"))
		(p-ident @1.5-1.6 (raw "b")))
	(e-lambda @1.8-1.21
		(args
			(p-ident @1.9-1.10 (raw "c")))
		(e-binop @1.12-1.21 (op "+")
			(e-ident @1.12-1.13 (raw "a"))
			(e-binop @1.16-1.21 (op "+")
				(e-ident @1.16-1.17 (raw "b"))
				(e-ident @1.20-1.21 (raw "c"))))))
~~~
# FORMATTED
~~~roc
NO CHANGE
~~~
# CANONICALIZE
~~~clojure
(e-lambda @1.1-1.21
	(args
		(p-assign @1.2-1.3 (ident "a"))
		(p-assign @1.5-1.6 (ident "b")))
	(e-lambda @1.8-1.21
		(args
			(p-assign @1.9-1.10 (ident "c")))
		(captures
			(capture (name "a"))
			(capture (name "b")))
		(e-binop @1.12-1.21 (op "add")
			(e-lookup-local @1.12-1.13
				(p-assign @1.2-1.3 (ident "a")))
			(e-binop @1.16-1.21 (op "add")
				(e-lookup-local @1.16-1.17
					(p-assign @1.5-1.6 (ident "b")))
				(e-lookup-local @1.20-1.21
					(p-assign @1.9-1.10 (ident "c")))))))
~~~
# TYPES
~~~clojure
(expr @1.1-1.21 (type "Num(_size), Num(_size2) -> Num(_size3) -> Num(_size4)"))
~~~
