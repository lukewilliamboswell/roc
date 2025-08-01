# META
~~~ini
description=fuzz crash
type=file
~~~
# SOURCE
~~~roc
 HO||v
~~~
# EXPECTED
ASCII CONTROL CHARACTER - :0:0:0:0
ASCII CONTROL CHARACTER - :0:0:0:0
MISSING HEADER - fuzz_crash_006.md:1:2:1:4
INVALID STATEMENT - fuzz_crash_006.md:1:4:1:8
# PROBLEMS
**ASCII CONTROL CHARACTER**
ASCII control characters are not allowed in Roc source code.

**ASCII CONTROL CHARACTER**
ASCII control characters are not allowed in Roc source code.

**MISSING HEADER**
Roc files must start with a module header.

For example:
        module [main]
or for an app:
        app [main!] { pf: platform "../basic-cli/platform.roc" }

Here is the problematic code:
**fuzz_crash_006.md:1:2:1:4:**
```roc
 HO||v
```
 ^^


**INVALID STATEMENT**
The statement `expression` is not allowed at the top level.
Only definitions, type annotations, and imports are allowed at the top level.

**fuzz_crash_006.md:1:4:1:8:**
```roc
 HO||v
```
   ^^^^


# TOKENS
~~~zig
UpperIdent(1:2-1:4),OpBar(1:4-1:5),OpBar(1:6-1:7),LowerIdent(1:7-1:8),EndOfFile(1:8-1:8),
~~~
# PARSE
~~~clojure
(file @1.2-1.8
	(malformed-header @1.2-1.4 (tag "missing_header"))
	(statements
		(e-lambda @1.4-1.8
			(args)
			(e-ident @1.7-1.8 (raw "v")))))
~~~
# FORMATTED
~~~roc
|| v
~~~
# CANONICALIZE
~~~clojure
(can-ir (empty true))
~~~
# TYPES
~~~clojure
(inferred-types
	(defs)
	(expressions))
~~~
