# META
~~~ini
description=Simple lambda capture expression for debugging - inner lambda captures outer parameter
type=expr
~~~
# SOURCE
~~~roc
((|x| |y| x + y)(42))(10)
~~~
# EXPECTED
NIL
# PROBLEMS
NIL
# TOKENS
~~~zig
OpenRound(1:1-1:2),NoSpaceOpenRound(1:2-1:3),OpBar(1:3-1:4),LowerIdent(1:4-1:5),OpBar(1:5-1:6),OpBar(1:7-1:8),LowerIdent(1:8-1:9),OpBar(1:9-1:10),LowerIdent(1:11-1:12),OpPlus(1:13-1:14),LowerIdent(1:15-1:16),CloseRound(1:16-1:17),NoSpaceOpenRound(1:17-1:18),Int(1:18-1:20),CloseRound(1:20-1:21),CloseRound(1:21-1:22),NoSpaceOpenRound(1:22-1:23),Int(1:23-1:25),CloseRound(1:25-1:26),EndOfFile(1:26-1:26),
~~~
# PARSE
~~~clojure
(e-apply @1.1-1.26
	(e-tuple @1.1-1.22
		(e-apply @1.2-1.21
			(e-tuple @1.2-1.17
				(e-lambda @1.3-1.16
					(args
						(p-ident @1.4-1.5 (raw "x")))
					(e-lambda @1.7-1.16
						(args
							(p-ident @1.8-1.9 (raw "y")))
						(e-binop @1.11-1.16 (op "+")
							(e-ident @1.11-1.12 (raw "x"))
							(e-ident @1.15-1.16 (raw "y"))))))
			(e-int @1.18-1.20 (raw "42"))))
	(e-int @1.23-1.25 (raw "10")))
~~~
# FORMATTED
~~~roc
NO CHANGE
~~~
# CANONICALIZE
~~~clojure
(e-call @1.1-1.26
	(e-call @1.2-1.21
		(e-lambda @1.3-1.16
			(args
				(p-assign @1.4-1.5 (ident "x")))
			(e-lambda @1.7-1.16
				(args
					(p-assign @1.8-1.9 (ident "y")))
				(captures
					(capture (name "x")))
				(e-binop @1.11-1.16 (op "add")
					(e-lookup-local @1.11-1.12
						(p-assign @1.4-1.5 (ident "x")))
					(e-lookup-local @1.15-1.16
						(p-assign @1.8-1.9 (ident "y"))))))
		(e-int @1.18-1.20 (value "42")))
	(e-int @1.23-1.25 (value "10")))
~~~
# TYPES
~~~clojure
(expr @1.1-1.26 (type "Num(_size)"))
~~~
