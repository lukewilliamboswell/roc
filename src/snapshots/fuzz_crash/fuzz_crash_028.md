# META
~~~ini
description=fuzz crash
type=file
~~~
# SOURCE
~~~roc
# Thnt!
app [main!] { pf: platform "c" }

import pf.Stdout exposing [line!, e!]

import Stdot
		exposing [ #tem
		] # Cose

import p .S exposing [func as fry, Custom.*]

import Bae as Gooe
import
	Ba
Map(a, b) : List(a), (a -> b) -> List(b)
MapML( # Cere
	a, # Anre
	b,
) # Ag
	: # Aon
		List( #rg
		),
		(a -> b) -> # row
			List(			b	) #

Foo : (Bar, Baz)

line : ( # Cpen
	Bar, #
	Baz, #m
) # Co
Some(a) : { foo : Ok(a), bar : g }
Ml(a) : { # d
	bar : Som# Afld
}

Soine(a) : { #d
	bar : Som
} #
Maya) : [ #
] #se

Func(a) : Maybe(a), a -> Maybe(a)

ane = |num| if num 2 else 5

add_one : U64 -> U64
add_ne = |num| {
	other = 1
	if num {
		dbg # bug
() #r
		0
	} else {
		dbg 123
		other
	}
}

match_time = |
	a, #rg
	b,
| # As
	match a {lue | Red => {
			x x
		}
		Blue		=> 1
		"foo" => # ent
00
		"foo" | "bar" => 20[1, 2, 3, .. as rest] # t
			=> ment
		[1, 2 | 5, 3, .. as rest] => 123
		[
		] => 1	3.14 => 314
		3.14 | 6.28 => 314
		(1, 2, 3) => 123
		(1, 2 | 5, 3) => 123
		{ foo: 1, bar: 2, ..rest } => 12->add(34)
		{ # Afpen
oo #
				: #ue
	1, #eld
ar: 2,
			..} => 12
		{ foo: 1, bar: 2 | 7 } => 12
		{
	o: 1,
			} =>212
		Ok(123) => 12
	}

expect # Cord
	blah == 1 # nt

main! : (String) -> Result({}, _)
ma= |_| { # Yee
	world = "d"
	var number = 123
	expect blah == 1
	tag = Blue
	return #d
		tag  Jus
	...
	match_time(
		...
	)
nc(
		dbg # bug
2, #r
	)
	crash "Unrnt
	tag_ = Ok(number)
	i= "H, ${world}"
t = [
		add_one(dbg # Afist
er, # afarg
		),	456, # ee
	]
	for n in list {
	line!("Ag ${n} to ${er}")
		+ n
	}
	rd = { foo: 123, bar: "H", baz: tag, qux: Ok(world),ned }
	tuple = (123, "World", tag, Ok(world), (nd, tuple), [1, 2, 3])
	mle = (
		123,
		"World",ag1,
		Ok(world), # nt
		(ne, tuple),
		[1, 2, 3],
	)
	b = Err(foo) ?? 12 > 5 * 5 or 13 + 2 < 5 and 10 - 1 >= 16 or 12 <= 3 / 5
le =(arg1)?.od()?.ned()?.recd?
	line!(
		"Ho${ #
			r(number) # xpr
		} ",
	)
} # Cocl

y : {}
e = {}

t : V((a,c))

expect {
	f= 1
h == foo
}
~~~
# EXPECTED
ASCII CONTROL CHARACTER - :0:0:0:0
ASCII CONTROL CHARACTER - :0:0:0:0
ASCII CONTROL CHARACTER - :0:0:0:0
LEADING ZERO - :0:0:0:0
ASCII CONTROL CHARACTER - :0:0:0:0
UNCLOSED STRING - :0:0:0:0
PARSE ERROR - fuzz_crash_028.md:40:5:40:6
UNEXPECTED TOKEN IN EXPRESSION - fuzz_crash_028.md:40:7:40:8
UNDECLARED TYPE - fuzz_crash_028.md:26:8:26:11
UNDECLARED TYPE - fuzz_crash_028.md:26:13:26:16
UNDECLARED TYPE - fuzz_crash_028.md:32:19:32:21
UNDECLARED TYPE VARIABLE - fuzz_crash_028.md:32:32:32:33
UNDECLARED TYPE - fuzz_crash_028.md:34:8:34:11
UNDECLARED TYPE - fuzz_crash_028.md:38:8:38:11
UNDECLARED TYPE - fuzz_crash_028.md:43:11:43:16
UNDECLARED TYPE - fuzz_crash_028.md:43:26:43:31
MODULE NOT FOUND - fuzz_crash_028.md:4:1:4:38
MODULE NOT FOUND - fuzz_crash_028.md:6:1:8:4
NOT IMPLEMENTED - :0:0:0:0
MODULE NOT FOUND - fuzz_crash_028.md:10:1:10:46
MODULE NOT FOUND - fuzz_crash_028.md:12:1:12:19
MODULE NOT FOUND - fuzz_crash_028.md:13:1:14:4
UNDECLARED TYPE - fuzz_crash_028.md:29:2:29:5
UNDECLARED TYPE - fuzz_crash_028.md:30:2:30:5
INVALID STATEMENT - fuzz_crash_028.md:40:7:40:8
INVALID STATEMENT - fuzz_crash_028.md:40:9:41:2
INVALID STATEMENT - fuzz_crash_028.md:48:1:48:5
EMPTY TUPLE NOT ALLOWED - fuzz_crash_028.md:52:1:52:3
UNDEFINED VARIABLE - fuzz_crash_028.md:65:4:65:5
UNDEFINED VARIABLE - fuzz_crash_028.md:65:6:65:7
UNUSED VARIABLE - fuzz_crash_028.md:64:11:64:14
UNDEFINED VARIABLE - fuzz_crash_028.md:71:7:71:11
UNUSED VARIABLE - fuzz_crash_028.md:1:1:1:1
NOT IMPLEMENTED - :0:0:0:0
UNUSED VARIABLE - fuzz_crash_028.md:1:1:1:1
NOT IMPLEMENTED - :0:0:0:0
NOT IMPLEMENTED - :0:0:0:0
UNUSED VARIABLE - fuzz_crash_028.md:78:21:78:27
NOT IMPLEMENTED - :0:0:0:0
NOT IMPLEMENTED - :0:0:0:0
UNUSED VARIABLE - fuzz_crash_028.md:62:2:62:3
UNDEFINED VARIABLE - fuzz_crash_028.md:93:2:93:6
UNDECLARED TYPE - fuzz_crash_028.md:95:10:95:16
UNDEFINED VARIABLE - fuzz_crash_028.md:99:9:99:13
UNDEFINED VARIABLE - fuzz_crash_028.md:107:1:107:3
UNDEFINED VARIABLE - fuzz_crash_028.md:115:3:115:10
UNDEFINED VARIABLE - fuzz_crash_028.md:116:1:116:3
NOT IMPLEMENTED - :0:0:0:0
UNDEFINED VARIABLE - fuzz_crash_028.md:123:54:123:57
UNDEFINED VARIABLE - fuzz_crash_028.md:124:42:124:44
UNDEFINED VARIABLE - fuzz_crash_028.md:127:11:127:14
UNDEFINED VARIABLE - fuzz_crash_028.md:132:10:132:13
NOT IMPLEMENTED - :0:0:0:0
UNDEFINED VARIABLE - fuzz_crash_028.md:136:4:136:5
UNUSED VARIABLE - fuzz_crash_028.md:112:2:112:6
UNUSED VARIABLE - fuzz_crash_028.md:113:2:113:3
UNUSED VARIABLE - fuzz_crash_028.md:114:1:114:2
UNUSED VARIABLE - fuzz_crash_028.md:123:2:123:4
UNUSED VARIABLE - fuzz_crash_028.md:125:2:125:5
UNUSED VARIABLE - fuzz_crash_028.md:133:1:133:3
UNUSED VARIABLE - fuzz_crash_028.md:132:2:132:3
UNDECLARED TYPE - fuzz_crash_028.md:144:5:144:6
UNDEFINED VARIABLE - fuzz_crash_028.md:148:1:148:2
UNDEFINED VARIABLE - fuzz_crash_028.md:148:6:148:9
UNUSED VARIABLE - fuzz_crash_028.md:147:2:147:3
INCOMPATIBLE MATCH PATTERNS - fuzz_crash_028.md:64:2:64:2
TYPE MISMATCH - fuzz_crash_028.md:104:2:104:12
# PROBLEMS
**ASCII CONTROL CHARACTER**
ASCII control characters are not allowed in Roc source code.

**ASCII CONTROL CHARACTER**
ASCII control characters are not allowed in Roc source code.

**ASCII CONTROL CHARACTER**
ASCII control characters are not allowed in Roc source code.

**LEADING ZERO**
Numbers cannot have leading zeros.

**ASCII CONTROL CHARACTER**
ASCII control characters are not allowed in Roc source code.

**UNCLOSED STRING**
This string is missing a closing quote.

**PARSE ERROR**
Type applications require parentheses around their type arguments.

I found a type followed by what looks like a type argument, but they need to be connected with parentheses.

Instead of:
    **List U8**

Use:
    **List(U8)**

Other valid examples:
    `Dict(Str, Num)`
    `Result(a, Str)`
    `Maybe(List(U64))`

Here is the problematic code:
**fuzz_crash_028.md:40:5:40:6:**
```roc
Maya) : [ #
```
    ^


**UNEXPECTED TOKEN IN EXPRESSION**
The token **:** is not expected in an expression.
Expressions can be identifiers, literals, function calls, or operators.

Here is the problematic code:
**fuzz_crash_028.md:40:7:40:8:**
```roc
Maya) : [ #
```
      ^


**UNDECLARED TYPE**
The type _Bar_ is not declared in this scope.

This type is referenced here:
**fuzz_crash_028.md:26:8:26:11:**
```roc
Foo : (Bar, Baz)
```
       ^^^


**UNDECLARED TYPE**
The type _Baz_ is not declared in this scope.

This type is referenced here:
**fuzz_crash_028.md:26:13:26:16:**
```roc
Foo : (Bar, Baz)
```
            ^^^


**UNDECLARED TYPE**
The type _Ok_ is not declared in this scope.

This type is referenced here:
**fuzz_crash_028.md:32:19:32:21:**
```roc
Some(a) : { foo : Ok(a), bar : g }
```
                  ^^


**UNDECLARED TYPE VARIABLE**
The type variable _g_ is not declared in this scope.

Type variables must be introduced in a type annotation before they can be used.

This type variable is referenced here:
**fuzz_crash_028.md:32:32:32:33:**
```roc
Some(a) : { foo : Ok(a), bar : g }
```
                               ^


**UNDECLARED TYPE**
The type _Som_ is not declared in this scope.

This type is referenced here:
**fuzz_crash_028.md:34:8:34:11:**
```roc
	bar : Som# Afld
```
       ^^^


**UNDECLARED TYPE**
The type _Som_ is not declared in this scope.

This type is referenced here:
**fuzz_crash_028.md:38:8:38:11:**
```roc
	bar : Som
```
       ^^^


**UNDECLARED TYPE**
The type _Maybe_ is not declared in this scope.

This type is referenced here:
**fuzz_crash_028.md:43:11:43:16:**
```roc
Func(a) : Maybe(a), a -> Maybe(a)
```
          ^^^^^


**UNDECLARED TYPE**
The type _Maybe_ is not declared in this scope.

This type is referenced here:
**fuzz_crash_028.md:43:26:43:31:**
```roc
Func(a) : Maybe(a), a -> Maybe(a)
```
                         ^^^^^


**MODULE NOT FOUND**
The module `pf.Stdout` was not found in this Roc project.

You're attempting to use this module here:
**fuzz_crash_028.md:4:1:4:38:**
```roc
import pf.Stdout exposing [line!, e!]
```
^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^


**MODULE NOT FOUND**
The module `Stdot` was not found in this Roc project.

You're attempting to use this module here:
**fuzz_crash_028.md:6:1:8:4:**
```roc
import Stdot
		exposing [ #tem
		] # Cose
```


**NOT IMPLEMENTED**
This feature is not yet implemented: malformed import module name contains null bytes

This error doesn't have a proper diagnostic report yet. Let us know if you want to help improve Roc's error messages!

**MODULE NOT FOUND**
The module `MALFORMED_IMPORT` was not found in this Roc project.

You're attempting to use this module here:
**fuzz_crash_028.md:10:1:10:46:**
```roc
import p .S exposing [func as fry, Custom.*]
```
^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^


**MODULE NOT FOUND**
The module `Bae` was not found in this Roc project.

You're attempting to use this module here:
**fuzz_crash_028.md:12:1:12:19:**
```roc
import Bae as Gooe
```
^^^^^^^^^^^^^^^^^^


**MODULE NOT FOUND**
The module `Ba` was not found in this Roc project.

You're attempting to use this module here:
**fuzz_crash_028.md:13:1:14:4:**
```roc
import
	Ba
```


**UNDECLARED TYPE**
The type _Bar_ is not declared in this scope.

This type is referenced here:
**fuzz_crash_028.md:29:2:29:5:**
```roc
	Bar, #
```
 ^^^


**UNDECLARED TYPE**
The type _Baz_ is not declared in this scope.

This type is referenced here:
**fuzz_crash_028.md:30:2:30:5:**
```roc
	Baz, #m
```
 ^^^


**INVALID STATEMENT**
The statement `expression` is not allowed at the top level.
Only definitions, type annotations, and imports are allowed at the top level.

**fuzz_crash_028.md:40:7:40:8:**
```roc
Maya) : [ #
```
      ^


**INVALID STATEMENT**
The statement `expression` is not allowed at the top level.
Only definitions, type annotations, and imports are allowed at the top level.

**fuzz_crash_028.md:40:9:41:2:**
```roc
Maya) : [ #
] #se
```


**INVALID STATEMENT**
The statement `expression` is not allowed at the top level.
Only definitions, type annotations, and imports are allowed at the top level.

**fuzz_crash_028.md:48:1:48:5:**
```roc
add_ne = |num| {
```
^^^^


**EMPTY TUPLE NOT ALLOWED**
I am part way through parsing this tuple, but it is empty:
**fuzz_crash_028.md:52:1:52:3:**
```roc
() #r
```
^^

If you want to represent nothing, try using an empty record: `{}`.

**UNDEFINED VARIABLE**
Nothing is named `x` in this scope.
Is there an `import` or `exposing` missing up-top?

**fuzz_crash_028.md:65:4:65:5:**
```roc
			x x
```
   ^


**UNDEFINED VARIABLE**
Nothing is named `x` in this scope.
Is there an `import` or `exposing` missing up-top?

**fuzz_crash_028.md:65:6:65:7:**
```roc
			x x
```
     ^


**UNUSED VARIABLE**
Variable `lue` is not used anywhere in your code.

If you don't need this variable, prefix it with an underscore like `_lue` to suppress this warning.
The unused variable is declared here:
**fuzz_crash_028.md:64:11:64:14:**
```roc
	match a {lue | Red => {
```
          ^^^


**UNDEFINED VARIABLE**
Nothing is named `ment` in this scope.
Is there an `import` or `exposing` missing up-top?

**fuzz_crash_028.md:71:7:71:11:**
```roc
			=> ment
```
      ^^^^


**UNUSED VARIABLE**
Variable `rest` is not used anywhere in your code.

If you don't need this variable, prefix it with an underscore like `_rest` to suppress this warning.
The unused variable is declared here:
**fuzz_crash_028.md:1:1:1:1:**
```roc
# Thnt!
```



**NOT IMPLEMENTED**
This feature is not yet implemented: alternatives pattern outside match expression

This error doesn't have a proper diagnostic report yet. Let us know if you want to help improve Roc's error messages!

**UNUSED VARIABLE**
Variable `rest` is not used anywhere in your code.

If you don't need this variable, prefix it with an underscore like `_rest` to suppress this warning.
The unused variable is declared here:
**fuzz_crash_028.md:1:1:1:1:**
```roc
# Thnt!
```



**NOT IMPLEMENTED**
This feature is not yet implemented: alternatives pattern outside match expression

This error doesn't have a proper diagnostic report yet. Let us know if you want to help improve Roc's error messages!

**NOT IMPLEMENTED**
This feature is not yet implemented: canonicalize local_dispatch expression

This error doesn't have a proper diagnostic report yet. Let us know if you want to help improve Roc's error messages!

**UNUSED VARIABLE**
Variable `rest` is not used anywhere in your code.

If you don't need this variable, prefix it with an underscore like `_rest` to suppress this warning.
The unused variable is declared here:
**fuzz_crash_028.md:78:21:78:27:**
```roc
		{ foo: 1, bar: 2, ..rest } => 12->add(34)
```
                    ^^^^^^


**NOT IMPLEMENTED**
This feature is not yet implemented: report an error when unable to resolve field identifier

This error doesn't have a proper diagnostic report yet. Let us know if you want to help improve Roc's error messages!

**NOT IMPLEMENTED**
This feature is not yet implemented: alternatives pattern outside match expression

This error doesn't have a proper diagnostic report yet. Let us know if you want to help improve Roc's error messages!

**UNUSED VARIABLE**
Variable `b` is not used anywhere in your code.

If you don't need this variable, prefix it with an underscore like `_b` to suppress this warning.
The unused variable is declared here:
**fuzz_crash_028.md:62:2:62:3:**
```roc
	b,
```
 ^


**UNDEFINED VARIABLE**
Nothing is named `blah` in this scope.
Is there an `import` or `exposing` missing up-top?

**fuzz_crash_028.md:93:2:93:6:**
```roc
	blah == 1 # nt
```
 ^^^^


**UNDECLARED TYPE**
The type _String_ is not declared in this scope.

This type is referenced here:
**fuzz_crash_028.md:95:10:95:16:**
```roc
main! : (String) -> Result({}, _)
```
         ^^^^^^


**UNDEFINED VARIABLE**
Nothing is named `blah` in this scope.
Is there an `import` or `exposing` missing up-top?

**fuzz_crash_028.md:99:9:99:13:**
```roc
	expect blah == 1
```
        ^^^^


**UNDEFINED VARIABLE**
Nothing is named `nc` in this scope.
Is there an `import` or `exposing` missing up-top?

**fuzz_crash_028.md:107:1:107:3:**
```roc
nc(
```
^^


**UNDEFINED VARIABLE**
Nothing is named `add_one` in this scope.
Is there an `import` or `exposing` missing up-top?

**fuzz_crash_028.md:115:3:115:10:**
```roc
		add_one(dbg # Afist
```
  ^^^^^^^


**UNDEFINED VARIABLE**
Nothing is named `er` in this scope.
Is there an `import` or `exposing` missing up-top?

**fuzz_crash_028.md:116:1:116:3:**
```roc
er, # afarg
```
^^


**NOT IMPLEMENTED**
This feature is not yet implemented: statement type in block

This error doesn't have a proper diagnostic report yet. Let us know if you want to help improve Roc's error messages!

**UNDEFINED VARIABLE**
Nothing is named `ned` in this scope.
Is there an `import` or `exposing` missing up-top?

**fuzz_crash_028.md:123:54:123:57:**
```roc
	rd = { foo: 123, bar: "H", baz: tag, qux: Ok(world),ned }
```
                                                     ^^^


**UNDEFINED VARIABLE**
Nothing is named `nd` in this scope.
Is there an `import` or `exposing` missing up-top?

**fuzz_crash_028.md:124:42:124:44:**
```roc
	tuple = (123, "World", tag, Ok(world), (nd, tuple), [1, 2, 3])
```
                                         ^^


**UNDEFINED VARIABLE**
Nothing is named `ag1` in this scope.
Is there an `import` or `exposing` missing up-top?

**fuzz_crash_028.md:127:11:127:14:**
```roc
		"World",ag1,
```
          ^^^


**UNDEFINED VARIABLE**
Nothing is named `foo` in this scope.
Is there an `import` or `exposing` missing up-top?

**fuzz_crash_028.md:132:10:132:13:**
```roc
	b = Err(foo) ?? 12 > 5 * 5 or 13 + 2 < 5 and 10 - 1 >= 16 or 12 <= 3 / 5
```
         ^^^


**NOT IMPLEMENTED**
This feature is not yet implemented: canonicalize suffix_single_question expression

This error doesn't have a proper diagnostic report yet. Let us know if you want to help improve Roc's error messages!

**UNDEFINED VARIABLE**
Nothing is named `r` in this scope.
Is there an `import` or `exposing` missing up-top?

**fuzz_crash_028.md:136:4:136:5:**
```roc
			r(number) # xpr
```
   ^


**UNUSED VARIABLE**
Variable `tag_` is not used anywhere in your code.

If you don't need this variable, prefix it with an underscore like `_tag_` to suppress this warning.
The unused variable is declared here:
**fuzz_crash_028.md:112:2:112:6:**
```roc
	tag_ = Ok(number)
```
 ^^^^


**UNUSED VARIABLE**
Variable `i` is not used anywhere in your code.

If you don't need this variable, prefix it with an underscore like `_i` to suppress this warning.
The unused variable is declared here:
**fuzz_crash_028.md:113:2:113:3:**
```roc
	i= "H, ${world}"
```
 ^


**UNUSED VARIABLE**
Variable `t` is not used anywhere in your code.

If you don't need this variable, prefix it with an underscore like `_t` to suppress this warning.
The unused variable is declared here:
**fuzz_crash_028.md:114:1:114:2:**
```roc
t = [
```
^


**UNUSED VARIABLE**
Variable `rd` is not used anywhere in your code.

If you don't need this variable, prefix it with an underscore like `_rd` to suppress this warning.
The unused variable is declared here:
**fuzz_crash_028.md:123:2:123:4:**
```roc
	rd = { foo: 123, bar: "H", baz: tag, qux: Ok(world),ned }
```
 ^^


**UNUSED VARIABLE**
Variable `mle` is not used anywhere in your code.

If you don't need this variable, prefix it with an underscore like `_mle` to suppress this warning.
The unused variable is declared here:
**fuzz_crash_028.md:125:2:125:5:**
```roc
	mle = (
```
 ^^^


**UNUSED VARIABLE**
Variable `le` is not used anywhere in your code.

If you don't need this variable, prefix it with an underscore like `_le` to suppress this warning.
The unused variable is declared here:
**fuzz_crash_028.md:133:1:133:3:**
```roc
le =(arg1)?.od()?.ned()?.recd?
```
^^


**UNUSED VARIABLE**
Variable `b` is not used anywhere in your code.

If you don't need this variable, prefix it with an underscore like `_b` to suppress this warning.
The unused variable is declared here:
**fuzz_crash_028.md:132:2:132:3:**
```roc
	b = Err(foo) ?? 12 > 5 * 5 or 13 + 2 < 5 and 10 - 1 >= 16 or 12 <= 3 / 5
```
 ^


**UNDECLARED TYPE**
The type _V_ is not declared in this scope.

This type is referenced here:
**fuzz_crash_028.md:144:5:144:6:**
```roc
t : V((a,c))
```
    ^


**UNDEFINED VARIABLE**
Nothing is named `h` in this scope.
Is there an `import` or `exposing` missing up-top?

**fuzz_crash_028.md:148:1:148:2:**
```roc
h == foo
```
^


**UNDEFINED VARIABLE**
Nothing is named `foo` in this scope.
Is there an `import` or `exposing` missing up-top?

**fuzz_crash_028.md:148:6:148:9:**
```roc
h == foo
```
     ^^^


**UNUSED VARIABLE**
Variable `f` is not used anywhere in your code.

If you don't need this variable, prefix it with an underscore like `_f` to suppress this warning.
The unused variable is declared here:
**fuzz_crash_028.md:147:2:147:3:**
```roc
	f= 1
```
 ^


**INCOMPATIBLE MATCH PATTERNS**
The pattern in the third branch of this `match` differs from previous ones:
**fuzz_crash_028.md:64:2:**
```roc
	match a {lue | Red => {
			x x
		}
		Blue		=> 1
		"foo" => # ent
00
		"foo" | "bar" => 20[1, 2, 3, .. as rest] # t
			=> ment
		[1, 2 | 5, 3, .. as rest] => 123
		[
		] => 1	3.14 => 314
		3.14 | 6.28 => 314
		(1, 2, 3) => 123
		(1, 2 | 5, 3) => 123
		{ foo: 1, bar: 2, ..rest } => 12->add(34)
		{ # Afpen
oo #
				: #ue
	1, #eld
ar: 2,
			..} => 12
		{ foo: 1, bar: 2 | 7 } => 12
		{
	o: 1,
			} =>212
		Ok(123) => 12
	}
```
  ^^^^^

The third pattern has this type:
    _Str_

But all the previous patterns have this type: 
    _[Red, Blue]_others_

All patterns in an `match` must have compatible types.



**TYPE MISMATCH**
This expression is used in an unexpected way:
**fuzz_crash_028.md:104:2:104:12:**
```roc
	match_time(
```
 ^^^^^^^^^^

It is of type:
    _[Red, Blue]_others, _arg2 -> Error_

But you are trying to use it as:
    __arg -> _ret_

# TOKENS
~~~zig
KwApp(2:1-2:4),OpenSquare(2:5-2:6),LowerIdent(2:6-2:11),CloseSquare(2:11-2:12),OpenCurly(2:13-2:14),LowerIdent(2:15-2:17),OpColon(2:17-2:18),KwPlatform(2:19-2:27),StringStart(2:28-2:29),StringPart(2:29-2:30),StringEnd(2:30-2:31),CloseCurly(2:32-2:33),
KwImport(4:1-4:7),LowerIdent(4:8-4:10),NoSpaceDotUpperIdent(4:10-4:17),KwExposing(4:18-4:26),OpenSquare(4:27-4:28),LowerIdent(4:28-4:33),Comma(4:33-4:34),LowerIdent(4:35-4:37),CloseSquare(4:37-4:38),
KwImport(6:1-6:7),UpperIdent(6:8-6:13),
KwExposing(7:3-7:11),OpenSquare(7:12-7:13),
CloseSquare(8:3-8:4),
KwImport(10:1-10:7),LowerIdent(10:8-10:9),DotUpperIdent(10:11-10:13),KwExposing(10:14-10:22),OpenSquare(10:23-10:24),LowerIdent(10:24-10:28),KwAs(10:29-10:31),LowerIdent(10:32-10:35),Comma(10:35-10:36),UpperIdent(10:37-10:43),DotStar(10:43-10:45),CloseSquare(10:45-10:46),
KwImport(12:1-12:7),UpperIdent(12:8-12:11),KwAs(12:12-12:14),UpperIdent(12:15-12:19),
KwImport(13:1-13:7),
UpperIdent(14:2-14:4),
UpperIdent(15:1-15:4),NoSpaceOpenRound(15:4-15:5),LowerIdent(15:5-15:6),Comma(15:6-15:7),LowerIdent(15:8-15:9),CloseRound(15:9-15:10),OpColon(15:11-15:12),UpperIdent(15:13-15:17),NoSpaceOpenRound(15:17-15:18),LowerIdent(15:18-15:19),CloseRound(15:19-15:20),Comma(15:20-15:21),OpenRound(15:22-15:23),LowerIdent(15:23-15:24),OpArrow(15:25-15:27),LowerIdent(15:28-15:29),CloseRound(15:29-15:30),OpArrow(15:31-15:33),UpperIdent(15:34-15:38),NoSpaceOpenRound(15:38-15:39),LowerIdent(15:39-15:40),CloseRound(15:40-15:41),
UpperIdent(16:1-16:6),NoSpaceOpenRound(16:6-16:7),
LowerIdent(17:2-17:3),Comma(17:3-17:4),
LowerIdent(18:2-18:3),Comma(18:3-18:4),
CloseRound(19:1-19:2),
OpColon(20:2-20:3),
UpperIdent(21:3-21:7),NoSpaceOpenRound(21:7-21:8),
CloseRound(22:3-22:4),Comma(22:4-22:5),
OpenRound(23:3-23:4),LowerIdent(23:4-23:5),OpArrow(23:6-23:8),LowerIdent(23:9-23:10),CloseRound(23:10-23:11),OpArrow(23:12-23:14),
UpperIdent(24:4-24:8),NoSpaceOpenRound(24:8-24:9),LowerIdent(24:12-24:13),CloseRound(24:14-24:15),
UpperIdent(26:1-26:4),OpColon(26:5-26:6),OpenRound(26:7-26:8),UpperIdent(26:8-26:11),Comma(26:11-26:12),UpperIdent(26:13-26:16),CloseRound(26:16-26:17),
LowerIdent(28:1-28:5),OpColon(28:6-28:7),OpenRound(28:8-28:9),
UpperIdent(29:2-29:5),Comma(29:5-29:6),
UpperIdent(30:2-30:5),Comma(30:5-30:6),
CloseRound(31:1-31:2),
UpperIdent(32:1-32:5),NoSpaceOpenRound(32:5-32:6),LowerIdent(32:6-32:7),CloseRound(32:7-32:8),OpColon(32:9-32:10),OpenCurly(32:11-32:12),LowerIdent(32:13-32:16),OpColon(32:17-32:18),UpperIdent(32:19-32:21),NoSpaceOpenRound(32:21-32:22),LowerIdent(32:22-32:23),CloseRound(32:23-32:24),Comma(32:24-32:25),LowerIdent(32:26-32:29),OpColon(32:30-32:31),LowerIdent(32:32-32:33),CloseCurly(32:34-32:35),
UpperIdent(33:1-33:3),NoSpaceOpenRound(33:3-33:4),LowerIdent(33:4-33:5),CloseRound(33:5-33:6),OpColon(33:7-33:8),OpenCurly(33:9-33:10),
LowerIdent(34:2-34:5),OpColon(34:6-34:7),UpperIdent(34:8-34:11),
CloseCurly(35:1-35:2),
UpperIdent(37:1-37:6),NoSpaceOpenRound(37:6-37:7),LowerIdent(37:7-37:8),CloseRound(37:8-37:9),OpColon(37:10-37:11),OpenCurly(37:12-37:13),
LowerIdent(38:2-38:5),OpColon(38:6-38:7),UpperIdent(38:8-38:11),
CloseCurly(39:1-39:2),
UpperIdent(40:1-40:5),CloseRound(40:5-40:6),OpColon(40:7-40:8),OpenSquare(40:9-40:10),
CloseSquare(41:1-41:2),
UpperIdent(43:1-43:5),NoSpaceOpenRound(43:5-43:6),LowerIdent(43:6-43:7),CloseRound(43:7-43:8),OpColon(43:9-43:10),UpperIdent(43:11-43:16),NoSpaceOpenRound(43:16-43:17),LowerIdent(43:17-43:18),CloseRound(43:18-43:19),Comma(43:19-43:20),LowerIdent(43:21-43:22),OpArrow(43:23-43:25),UpperIdent(43:26-43:31),NoSpaceOpenRound(43:31-43:32),LowerIdent(43:32-43:33),CloseRound(43:33-43:34),
LowerIdent(45:1-45:4),OpAssign(45:5-45:6),OpBar(45:7-45:8),LowerIdent(45:8-45:11),OpBar(45:11-45:12),KwIf(45:13-45:15),LowerIdent(45:16-45:19),Int(45:20-45:21),KwElse(45:22-45:26),Int(45:27-45:28),
LowerIdent(47:1-47:8),OpColon(47:9-47:10),UpperIdent(47:11-47:14),OpArrow(47:15-47:17),UpperIdent(47:18-47:21),
LowerIdent(48:1-48:5),LowerIdent(48:6-48:8),OpAssign(48:9-48:10),OpBar(48:11-48:12),LowerIdent(48:12-48:15),OpBar(48:15-48:16),OpenCurly(48:17-48:18),
LowerIdent(49:2-49:7),OpAssign(49:8-49:9),Int(49:10-49:11),
KwIf(50:2-50:4),LowerIdent(50:5-50:8),OpenCurly(50:9-50:10),
KwDbg(51:3-51:6),
OpenRound(52:1-52:2),CloseRound(52:2-52:3),
Int(53:3-53:4),
CloseCurly(54:2-54:3),KwElse(54:4-54:8),OpenCurly(54:9-54:10),
KwDbg(55:3-55:6),Int(55:7-55:10),
LowerIdent(56:3-56:8),
CloseCurly(57:2-57:3),
CloseCurly(58:1-58:2),
LowerIdent(60:1-60:11),OpAssign(60:12-60:13),OpBar(60:14-60:15),
LowerIdent(61:2-61:3),Comma(61:3-61:4),
LowerIdent(62:2-62:3),Comma(62:3-62:4),
OpBar(63:1-63:2),
KwMatch(64:2-64:7),LowerIdent(64:8-64:9),OpenCurly(64:10-64:11),LowerIdent(64:11-64:14),OpBar(64:15-64:16),UpperIdent(64:17-64:20),OpFatArrow(64:21-64:23),OpenCurly(64:24-64:25),
LowerIdent(65:4-65:5),LowerIdent(65:6-65:7),
CloseCurly(66:3-66:4),
UpperIdent(67:3-67:7),OpFatArrow(67:9-67:11),Int(67:12-67:13),
StringStart(68:3-68:4),StringPart(68:4-68:7),StringEnd(68:7-68:8),OpFatArrow(68:9-68:11),
Int(69:1-69:3),
StringStart(70:3-70:4),StringPart(70:4-70:7),StringEnd(70:7-70:8),OpBar(70:9-70:10),StringStart(70:11-70:12),StringPart(70:12-70:15),StringEnd(70:15-70:16),OpFatArrow(70:17-70:19),Int(70:20-70:22),OpenSquare(70:22-70:23),Int(70:23-70:24),Comma(70:24-70:25),Int(70:26-70:27),Comma(70:27-70:28),Int(70:29-70:30),Comma(70:30-70:31),DoubleDot(70:32-70:34),KwAs(70:35-70:37),LowerIdent(70:38-70:42),CloseSquare(70:42-70:43),
OpFatArrow(71:4-71:6),LowerIdent(71:7-71:11),
OpenSquare(72:3-72:4),Int(72:4-72:5),Comma(72:5-72:6),Int(72:7-72:8),OpBar(72:9-72:10),Int(72:11-72:12),Comma(72:12-72:13),Int(72:14-72:15),Comma(72:15-72:16),DoubleDot(72:17-72:19),KwAs(72:20-72:22),LowerIdent(72:23-72:27),CloseSquare(72:27-72:28),OpFatArrow(72:29-72:31),Int(72:32-72:35),
OpenSquare(73:3-73:4),
CloseSquare(74:3-74:4),OpFatArrow(74:5-74:7),Int(74:8-74:9),Float(74:10-74:14),OpFatArrow(74:15-74:17),Int(74:18-74:21),
Float(75:3-75:7),OpBar(75:8-75:9),Float(75:10-75:14),OpFatArrow(75:15-75:17),Int(75:18-75:21),
OpenRound(76:3-76:4),Int(76:4-76:5),Comma(76:5-76:6),Int(76:7-76:8),Comma(76:8-76:9),Int(76:10-76:11),CloseRound(76:11-76:12),OpFatArrow(76:13-76:15),Int(76:16-76:19),
OpenRound(77:3-77:4),Int(77:4-77:5),Comma(77:5-77:6),Int(77:7-77:8),OpBar(77:9-77:10),Int(77:11-77:12),Comma(77:12-77:13),Int(77:14-77:15),CloseRound(77:15-77:16),OpFatArrow(77:17-77:19),Int(77:20-77:23),
OpenCurly(78:3-78:4),LowerIdent(78:5-78:8),OpColon(78:8-78:9),Int(78:10-78:11),Comma(78:11-78:12),LowerIdent(78:13-78:16),OpColon(78:16-78:17),Int(78:18-78:19),Comma(78:19-78:20),DoubleDot(78:21-78:23),LowerIdent(78:23-78:27),CloseCurly(78:28-78:29),OpFatArrow(78:30-78:32),Int(78:33-78:35),OpArrow(78:35-78:37),LowerIdent(78:37-78:40),NoSpaceOpenRound(78:40-78:41),Int(78:41-78:43),CloseRound(78:43-78:44),
OpenCurly(79:3-79:4),
LowerIdent(80:1-80:3),
OpColon(81:5-81:6),
Int(82:2-82:3),Comma(82:3-82:4),
LowerIdent(83:1-83:3),OpColon(83:3-83:4),Int(83:5-83:6),Comma(83:6-83:7),
DoubleDot(84:4-84:6),CloseCurly(84:6-84:7),OpFatArrow(84:8-84:10),Int(84:11-84:13),
OpenCurly(85:3-85:4),LowerIdent(85:5-85:8),OpColon(85:8-85:9),Int(85:10-85:11),Comma(85:11-85:12),LowerIdent(85:13-85:16),OpColon(85:16-85:17),Int(85:18-85:19),OpBar(85:20-85:21),Int(85:22-85:23),CloseCurly(85:24-85:25),OpFatArrow(85:26-85:28),Int(85:29-85:31),
OpenCurly(86:3-86:4),
LowerIdent(87:2-87:3),OpColon(87:3-87:4),Int(87:5-87:6),Comma(87:6-87:7),
CloseCurly(88:4-88:5),OpFatArrow(88:6-88:8),Int(88:8-88:11),
UpperIdent(89:3-89:5),NoSpaceOpenRound(89:5-89:6),Int(89:6-89:9),CloseRound(89:9-89:10),OpFatArrow(89:11-89:13),Int(89:14-89:16),
CloseCurly(90:2-90:3),
KwExpect(92:1-92:7),
LowerIdent(93:2-93:6),OpEquals(93:7-93:9),Int(93:10-93:11),
LowerIdent(95:1-95:6),OpColon(95:7-95:8),OpenRound(95:9-95:10),UpperIdent(95:10-95:16),CloseRound(95:16-95:17),OpArrow(95:18-95:20),UpperIdent(95:21-95:27),NoSpaceOpenRound(95:27-95:28),OpenCurly(95:28-95:29),CloseCurly(95:29-95:30),Comma(95:30-95:31),Underscore(95:32-95:33),CloseRound(95:33-95:34),
LowerIdent(96:1-96:3),OpAssign(96:3-96:4),OpBar(96:5-96:6),Underscore(96:6-96:7),OpBar(96:7-96:8),OpenCurly(96:9-96:10),
LowerIdent(97:2-97:7),OpAssign(97:8-97:9),StringStart(97:10-97:11),StringPart(97:11-97:12),StringEnd(97:12-97:13),
KwVar(98:2-98:5),LowerIdent(98:6-98:12),OpAssign(98:13-98:14),Int(98:15-98:18),
KwExpect(99:2-99:8),LowerIdent(99:9-99:13),OpEquals(99:14-99:16),Int(99:17-99:18),
LowerIdent(100:2-100:5),OpAssign(100:6-100:7),UpperIdent(100:8-100:12),
KwReturn(101:2-101:8),
LowerIdent(102:3-102:6),UpperIdent(102:8-102:11),
TripleDot(103:2-103:5),
LowerIdent(104:2-104:12),NoSpaceOpenRound(104:12-104:13),
TripleDot(105:3-105:6),
CloseRound(106:2-106:3),
LowerIdent(107:1-107:3),NoSpaceOpenRound(107:3-107:4),
KwDbg(108:3-108:6),
Int(109:1-109:2),Comma(109:2-109:3),
CloseRound(110:2-110:3),
KwCrash(111:2-111:7),StringStart(111:8-111:9),StringPart(111:9-111:14),StringEnd(111:14-111:14),
LowerIdent(112:2-112:6),OpAssign(112:7-112:8),UpperIdent(112:9-112:11),NoSpaceOpenRound(112:11-112:12),LowerIdent(112:12-112:18),CloseRound(112:18-112:19),
LowerIdent(113:2-113:3),OpAssign(113:3-113:4),StringStart(113:5-113:6),StringPart(113:6-113:9),OpenStringInterpolation(113:9-113:11),LowerIdent(113:11-113:16),CloseStringInterpolation(113:16-113:17),StringPart(113:17-113:17),StringEnd(113:17-113:18),
LowerIdent(114:1-114:2),OpAssign(114:3-114:4),OpenSquare(114:5-114:6),
LowerIdent(115:3-115:10),NoSpaceOpenRound(115:10-115:11),KwDbg(115:11-115:14),
LowerIdent(116:1-116:3),Comma(116:3-116:4),
CloseRound(117:3-117:4),Comma(117:4-117:5),Int(117:6-117:9),Comma(117:9-117:10),
CloseSquare(118:2-118:3),
KwFor(119:2-119:5),LowerIdent(119:6-119:7),KwIn(119:8-119:10),LowerIdent(119:11-119:15),OpenCurly(119:16-119:17),
LowerIdent(120:2-120:7),NoSpaceOpenRound(120:7-120:8),StringStart(120:8-120:9),StringPart(120:9-120:12),OpenStringInterpolation(120:12-120:14),LowerIdent(120:14-120:15),CloseStringInterpolation(120:15-120:16),StringPart(120:16-120:20),OpenStringInterpolation(120:20-120:22),LowerIdent(120:22-120:24),CloseStringInterpolation(120:24-120:25),StringPart(120:25-120:25),StringEnd(120:25-120:26),CloseRound(120:26-120:27),
OpPlus(121:3-121:4),LowerIdent(121:5-121:6),
CloseCurly(122:2-122:3),
LowerIdent(123:2-123:4),OpAssign(123:5-123:6),OpenCurly(123:7-123:8),LowerIdent(123:9-123:12),OpColon(123:12-123:13),Int(123:14-123:17),Comma(123:17-123:18),LowerIdent(123:19-123:22),OpColon(123:22-123:23),StringStart(123:24-123:25),StringPart(123:25-123:26),StringEnd(123:26-123:27),Comma(123:27-123:28),LowerIdent(123:29-123:32),OpColon(123:32-123:33),LowerIdent(123:34-123:37),Comma(123:37-123:38),LowerIdent(123:39-123:42),OpColon(123:42-123:43),UpperIdent(123:44-123:46),NoSpaceOpenRound(123:46-123:47),LowerIdent(123:47-123:52),CloseRound(123:52-123:53),Comma(123:53-123:54),LowerIdent(123:54-123:57),CloseCurly(123:58-123:59),
LowerIdent(124:2-124:7),OpAssign(124:8-124:9),OpenRound(124:10-124:11),Int(124:11-124:14),Comma(124:14-124:15),StringStart(124:16-124:17),StringPart(124:17-124:22),StringEnd(124:22-124:23),Comma(124:23-124:24),LowerIdent(124:25-124:28),Comma(124:28-124:29),UpperIdent(124:30-124:32),NoSpaceOpenRound(124:32-124:33),LowerIdent(124:33-124:38),CloseRound(124:38-124:39),Comma(124:39-124:40),OpenRound(124:41-124:42),LowerIdent(124:42-124:44),Comma(124:44-124:45),LowerIdent(124:46-124:51),CloseRound(124:51-124:52),Comma(124:52-124:53),OpenSquare(124:54-124:55),Int(124:55-124:56),Comma(124:56-124:57),Int(124:58-124:59),Comma(124:59-124:60),Int(124:61-124:62),CloseSquare(124:62-124:63),CloseRound(124:63-124:64),
LowerIdent(125:2-125:5),OpAssign(125:6-125:7),OpenRound(125:8-125:9),
Int(126:3-126:6),Comma(126:6-126:7),
StringStart(127:3-127:4),StringPart(127:4-127:9),StringEnd(127:9-127:10),Comma(127:10-127:11),LowerIdent(127:11-127:14),Comma(127:14-127:15),
UpperIdent(128:3-128:5),NoSpaceOpenRound(128:5-128:6),LowerIdent(128:6-128:11),CloseRound(128:11-128:12),Comma(128:12-128:13),
OpenRound(129:3-129:4),LowerIdent(129:4-129:6),Comma(129:6-129:7),LowerIdent(129:8-129:13),CloseRound(129:13-129:14),Comma(129:14-129:15),
OpenSquare(130:3-130:4),Int(130:4-130:5),Comma(130:5-130:6),Int(130:7-130:8),Comma(130:8-130:9),Int(130:10-130:11),CloseSquare(130:11-130:12),Comma(130:12-130:13),
CloseRound(131:2-131:3),
LowerIdent(132:2-132:3),OpAssign(132:4-132:5),UpperIdent(132:6-132:9),NoSpaceOpenRound(132:9-132:10),LowerIdent(132:10-132:13),CloseRound(132:13-132:14),OpDoubleQuestion(132:15-132:17),Int(132:18-132:20),OpGreaterThan(132:21-132:22),Int(132:23-132:24),OpStar(132:25-132:26),Int(132:27-132:28),OpOr(132:29-132:31),Int(132:32-132:34),OpPlus(132:35-132:36),Int(132:37-132:38),OpLessThan(132:39-132:40),Int(132:41-132:42),OpAnd(132:43-132:46),Int(132:47-132:49),OpBinaryMinus(132:50-132:51),Int(132:52-132:53),OpGreaterThanOrEq(132:54-132:56),Int(132:57-132:59),OpOr(132:60-132:62),Int(132:63-132:65),OpLessThanOrEq(132:66-132:68),Int(132:69-132:70),OpSlash(132:71-132:72),Int(132:73-132:74),
LowerIdent(133:1-133:3),OpAssign(133:4-133:5),NoSpaceOpenRound(133:5-133:6),LowerIdent(133:6-133:10),CloseRound(133:10-133:11),NoSpaceOpQuestion(133:11-133:12),NoSpaceDotLowerIdent(133:12-133:15),NoSpaceOpenRound(133:15-133:16),CloseRound(133:16-133:17),NoSpaceOpQuestion(133:17-133:18),NoSpaceDotLowerIdent(133:18-133:22),NoSpaceOpenRound(133:22-133:23),CloseRound(133:23-133:24),NoSpaceOpQuestion(133:24-133:25),NoSpaceDotLowerIdent(133:25-133:30),NoSpaceOpQuestion(133:30-133:31),
LowerIdent(134:2-134:7),NoSpaceOpenRound(134:7-134:8),
StringStart(135:3-135:4),StringPart(135:4-135:6),OpenStringInterpolation(135:6-135:8),
LowerIdent(136:4-136:5),NoSpaceOpenRound(136:5-136:6),LowerIdent(136:6-136:12),CloseRound(136:12-136:13),
CloseStringInterpolation(137:3-137:4),StringPart(137:4-137:5),StringEnd(137:5-137:6),Comma(137:6-137:7),
CloseRound(138:2-138:3),
CloseCurly(139:1-139:2),
LowerIdent(141:1-141:2),OpColon(141:3-141:4),OpenCurly(141:5-141:6),CloseCurly(141:6-141:7),
LowerIdent(142:1-142:2),OpAssign(142:3-142:4),OpenCurly(142:5-142:6),CloseCurly(142:6-142:7),
LowerIdent(144:1-144:2),OpColon(144:3-144:4),UpperIdent(144:5-144:6),NoSpaceOpenRound(144:6-144:7),NoSpaceOpenRound(144:7-144:8),LowerIdent(144:8-144:9),Comma(144:9-144:10),LowerIdent(144:10-144:11),CloseRound(144:11-144:12),CloseRound(144:12-144:13),
KwExpect(146:1-146:7),OpenCurly(146:8-146:9),
LowerIdent(147:2-147:3),OpAssign(147:3-147:4),Int(147:5-147:6),
LowerIdent(148:1-148:2),OpEquals(148:3-148:5),LowerIdent(148:6-148:9),
CloseCurly(149:1-149:2),EndOfFile(149:2-149:2),
~~~
# PARSE
~~~clojure
(file @2.1-149.2
	(app @2.1-2.33
		(provides @2.5-2.12
			(exposed-lower-ident @2.6-2.11
				(text "main!")))
		(record-field @2.15-2.31 (name "pf")
			(e-string @2.28-2.31
				(e-string-part @2.29-2.30 (raw "c"))))
		(packages @2.13-2.33
			(record-field @2.15-2.31 (name "pf")
				(e-string @2.28-2.31
					(e-string-part @2.29-2.30 (raw "c"))))))
	(statements
		(s-import @4.1-4.38 (raw "pf.Stdout")
			(exposing
				(exposed-lower-ident @4.28-4.33
					(text "line!"))
				(exposed-lower-ident @4.35-4.37
					(text "e!"))))
		(s-import @6.1-8.4 (raw "Stdot"))
		(s-import @10.1-10.46 (raw "p.S")
			(exposing
				(exposed-lower-ident @10.24-10.35
					(text "func")
					(as "fry"))
				(exposed-upper-ident-star @10.37-10.45 (text "Custom"))))
		(s-import @12.1-12.19 (raw "Bae") (alias "Gooe"))
		(s-import @13.1-14.4 (raw "Ba"))
		(s-type-decl @15.1-15.41
			(header @15.1-15.10 (name "Map")
				(args
					(ty-var @15.5-15.6 (raw "a"))
					(ty-var @15.8-15.9 (raw "b"))))
			(ty-fn @15.13-15.41
				(ty-apply @15.13-15.20
					(ty @15.13-15.17 (name "List"))
					(ty-var @15.18-15.19 (raw "a")))
				(ty-fn @15.23-15.29
					(ty-var @15.23-15.24 (raw "a"))
					(ty-var @15.28-15.29 (raw "b")))
				(ty-apply @15.34-15.41
					(ty @15.34-15.38 (name "List"))
					(ty-var @15.39-15.40 (raw "b")))))
		(s-type-decl @16.1-24.15
			(header @16.1-19.2 (name "MapML")
				(args
					(ty-var @17.2-17.3 (raw "a"))
					(ty-var @18.2-18.3 (raw "b"))))
			(ty-fn @21.3-24.15
				(ty-apply @21.3-22.4
					(ty @21.3-21.7 (name "List")))
				(ty-fn @23.4-23.10
					(ty-var @23.4-23.5 (raw "a"))
					(ty-var @23.9-23.10 (raw "b")))
				(ty-apply @24.4-24.15
					(ty @24.4-24.8 (name "List"))
					(ty-var @24.12-24.13 (raw "b")))))
		(s-type-decl @26.1-26.17
			(header @26.1-26.4 (name "Foo")
				(args))
			(ty-tuple @26.7-26.17
				(ty @26.8-26.11 (name "Bar"))
				(ty @26.13-26.16 (name "Baz"))))
		(s-type-anno @28.1-31.2 (name "line")
			(ty-tuple @28.8-31.2
				(ty @29.2-29.5 (name "Bar"))
				(ty @30.2-30.5 (name "Baz"))))
		(s-type-decl @32.1-32.35
			(header @32.1-32.8 (name "Some")
				(args
					(ty-var @32.6-32.7 (raw "a"))))
			(ty-record @32.11-32.35
				(anno-record-field @32.13-32.24 (name "foo")
					(ty-apply @32.19-32.24
						(ty @32.19-32.21 (name "Ok"))
						(ty-var @32.22-32.23 (raw "a"))))
				(anno-record-field @32.26-32.33 (name "bar")
					(ty-var @32.32-32.33 (raw "g")))))
		(s-type-decl @33.1-35.2
			(header @33.1-33.6 (name "Ml")
				(args
					(ty-var @33.4-33.5 (raw "a"))))
			(ty-record @33.9-35.2
				(anno-record-field @34.2-34.11 (name "bar")
					(ty @34.8-34.11 (name "Som")))))
		(s-type-decl @37.1-39.2
			(header @37.1-37.9 (name "Soine")
				(args
					(ty-var @37.7-37.8 (raw "a"))))
			(ty-record @37.12-39.2
				(anno-record-field @38.2-38.11 (name "bar")
					(ty @38.8-38.11 (name "Som")))))
		(s-malformed @40.1-40.6 (tag "expected_colon_after_type_annotation"))
		(e-malformed @40.7-40.8 (reason "expr_unexpected_token"))
		(e-list @40.9-41.2)
		(s-type-decl @43.1-43.34
			(header @43.1-43.8 (name "Func")
				(args
					(ty-var @43.6-43.7 (raw "a"))))
			(ty-fn @43.11-43.34
				(ty-apply @43.11-43.19
					(ty @43.11-43.16 (name "Maybe"))
					(ty-var @43.17-43.18 (raw "a")))
				(ty-var @43.21-43.22 (raw "a"))
				(ty-apply @43.26-43.34
					(ty @43.26-43.31 (name "Maybe"))
					(ty-var @43.32-43.33 (raw "a")))))
		(s-decl @45.1-45.28
			(p-ident @45.1-45.4 (raw "ane"))
			(e-lambda @45.7-45.28
				(args
					(p-ident @45.8-45.11 (raw "num")))
				(e-if-then-else @45.13-45.28
					(e-ident @45.16-45.19 (raw "num"))
					(e-int @45.20-45.21 (raw "2"))
					(e-int @45.27-45.28 (raw "5")))))
		(s-type-anno @47.1-47.21 (name "add_one")
			(ty-fn @47.11-47.21
				(ty @47.11-47.14 (name "U64"))
				(ty @47.18-47.21 (name "U64"))))
		(e-ident @48.1-48.5 (raw "add_"))
		(s-decl @48.6-58.2
			(p-ident @48.6-48.8 (raw "ne"))
			(e-lambda @48.11-58.2
				(args
					(p-ident @48.12-48.15 (raw "num")))
				(e-block @48.17-58.2
					(statements
						(s-decl @49.2-49.11
							(p-ident @49.2-49.7 (raw "other"))
							(e-int @49.10-49.11 (raw "1")))
						(e-if-then-else @50.2-57.3
							(e-ident @50.5-50.8 (raw "num"))
							(e-block @50.9-54.3
								(statements
									(s-dbg @51.3-52.3
										(e-tuple @52.1-52.3))
									(e-int @53.3-53.4 (raw "0"))))
							(e-block @54.9-57.3
								(statements
									(s-dbg @55.3-55.10
										(e-int @55.7-55.10 (raw "123")))
									(e-ident @56.3-56.8 (raw "other")))))))))
		(s-decl @60.1-90.3
			(p-ident @60.1-60.11 (raw "match_time"))
			(e-lambda @60.14-90.3
				(args
					(p-ident @61.2-61.3 (raw "a"))
					(p-ident @62.2-62.3 (raw "b")))
				(e-match
					(e-ident @64.8-64.9 (raw "a"))
					(branches
						(branch @64.11-66.4
							(p-alternatives
								(p-ident @64.11-64.14 (raw "lue"))
								(p-tag @64.17-64.20 (raw "Red")))
							(e-block @64.24-66.4
								(statements
									(e-ident @65.4-65.5 (raw "x"))
									(e-ident @65.6-65.7 (raw "x")))))
						(branch @67.3-67.13
							(p-tag @67.3-67.7 (raw "Blue"))
							(e-int @67.12-67.13 (raw "1")))
						(branch @68.3-69.3
							(p-string @68.3-68.8 (raw """))
							(e-int @69.1-69.3 (raw "00")))
						(branch @70.3-70.22
							(p-alternatives
								(p-string @70.3-70.8 (raw """))
								(p-string @70.11-70.16 (raw """)))
							(e-int @70.20-70.22 (raw "20")))
						(branch @70.22-71.11
							(p-list @70.22-70.43
								(p-int @70.23-70.24 (raw "1"))
								(p-int @70.26-70.27 (raw "2"))
								(p-int @70.29-70.30 (raw "3"))
								(p-list-rest @70.32-70.42 (name "rest")))
							(e-ident @71.7-71.11 (raw "ment")))
						(branch @72.3-72.35
							(p-list @72.3-72.28
								(p-int @72.4-72.5 (raw "1"))
								(p-alternatives
									(p-int @72.7-72.8 (raw "2"))
									(p-int @72.11-72.12 (raw "5")))
								(p-int @72.14-72.15 (raw "3"))
								(p-list-rest @72.17-72.27 (name "rest")))
							(e-int @72.32-72.35 (raw "123")))
						(branch @73.3-74.9
							(p-list @73.3-74.4)
							(e-int @74.8-74.9 (raw "1")))
						(branch @74.10-74.21
							(p-frac @74.10-74.14 (raw "3.14"))
							(e-int @74.18-74.21 (raw "314")))
						(branch @75.3-75.21
							(p-alternatives
								(p-frac @75.3-75.7 (raw "3.14"))
								(p-frac @75.10-75.14 (raw "6.28")))
							(e-int @75.18-75.21 (raw "314")))
						(branch @76.3-76.19
							(p-tuple @76.3-76.12
								(p-int @76.4-76.5 (raw "1"))
								(p-int @76.7-76.8 (raw "2"))
								(p-int @76.10-76.11 (raw "3")))
							(e-int @76.16-76.19 (raw "123")))
						(branch @77.3-77.23
							(p-tuple @77.3-77.16
								(p-int @77.4-77.5 (raw "1"))
								(p-alternatives
									(p-int @77.7-77.8 (raw "2"))
									(p-int @77.11-77.12 (raw "5")))
								(p-int @77.14-77.15 (raw "3")))
							(e-int @77.20-77.23 (raw "123")))
						(branch @78.3-78.44
							(p-record @78.3-78.29
								(field @78.5-78.11 (name "foo") (rest false)
									(p-int @78.10-78.11 (raw "1")))
								(field @78.13-78.19 (name "bar") (rest false)
									(p-int @78.18-78.19 (raw "2")))
								(field @78.21-78.27 (name "rest") (rest true)))
							(e-local-dispatch @78.33-78.44
								(e-int @78.33-78.35 (raw "12"))
								(e-apply @78.35-78.44
									(e-ident @78.37-78.37 (raw "add"))
									(e-int @78.41-78.43 (raw "34")))))
						(branch @79.3-84.13
							(p-record @79.3-84.7
								(field @80.1-82.3 (name "oo") (rest false)
									(p-int @82.2-82.3 (raw "1")))
								(field @83.1-83.6 (name "ar") (rest false)
									(p-int @83.5-83.6 (raw "2")))
								(field @84.4-84.6 (name "app") (rest true)))
							(e-int @84.11-84.13 (raw "12")))
						(branch @85.3-85.31
							(p-record @85.3-85.25
								(field @85.5-85.11 (name "foo") (rest false)
									(p-int @85.10-85.11 (raw "1")))
								(field @85.13-85.23 (name "bar") (rest false)
									(p-alternatives
										(p-int @85.18-85.19 (raw "2"))
										(p-int @85.22-85.23 (raw "7")))))
							(e-int @85.29-85.31 (raw "12")))
						(branch @86.3-88.11
							(p-record @86.3-88.5
								(field @87.2-87.6 (name "o") (rest false)
									(p-int @87.5-87.6 (raw "1"))))
							(e-int @88.8-88.11 (raw "212")))
						(branch @89.3-89.16
							(p-tag @89.3-89.10 (raw "Ok")
								(p-int @89.6-89.9 (raw "123")))
							(e-int @89.14-89.16 (raw "12")))))))
		(s-expect @92.1-93.11
			(e-binop @93.2-93.11 (op "==")
				(e-ident @93.2-93.6 (raw "blah"))
				(e-int @93.10-93.11 (raw "1"))))
		(s-type-anno @95.1-95.34 (name "main!")
			(ty-fn @95.9-95.34
				(ty-tuple @95.9-95.17
					(ty @95.10-95.16 (name "String")))
				(ty-apply @95.21-95.34
					(ty @95.21-95.27 (name "Result"))
					(ty-record @95.28-95.30)
					(_))))
		(s-decl @96.1-139.2
			(p-ident @96.1-96.3 (raw "ma"))
			(e-lambda @96.5-139.2
				(args
					(p-underscore))
				(e-block @96.9-139.2
					(statements
						(s-decl @97.2-97.13
							(p-ident @97.2-97.7 (raw "world"))
							(e-string @97.10-97.13
								(e-string-part @97.11-97.12 (raw "d"))))
						(s-var @98.2-98.18 (name "number")
							(e-int @98.15-98.18 (raw "123")))
						(s-expect @99.2-99.18
							(e-binop @99.9-99.18 (op "==")
								(e-ident @99.9-99.13 (raw "blah"))
								(e-int @99.17-99.18 (raw "1"))))
						(s-decl @100.2-100.12
							(p-ident @100.2-100.5 (raw "tag"))
							(e-tag @100.8-100.12 (raw "Blue")))
						(s-return @101.2-102.6
							(e-ident @102.3-102.6 (raw "tag")))
						(e-tag @102.8-102.11 (raw "Jus"))
						(e-ellipsis)
						(e-apply @104.2-106.3
							(e-ident @104.2-104.12 (raw "match_time"))
							(e-ellipsis))
						(e-apply @107.1-110.3
							(e-ident @107.1-107.3 (raw "nc"))
							(e-dbg
								(e-int @109.1-109.2 (raw "2"))))
						(s-crash @111.2-111.14
							(e-string @111.8-111.14
								(e-string-part @111.9-111.14 (raw "Unrnt"))))
						(s-decl @112.2-112.19
							(p-ident @112.2-112.6 (raw "tag_"))
							(e-apply @112.9-112.19
								(e-tag @112.9-112.11 (raw "Ok"))
								(e-ident @112.12-112.18 (raw "number"))))
						(s-decl @113.2-113.18
							(p-ident @113.2-113.3 (raw "i"))
							(e-string @113.5-113.18
								(e-string-part @113.6-113.9 (raw "H, "))
								(e-ident @113.11-113.16 (raw "world"))
								(e-string-part @113.17-113.17 (raw ""))))
						(s-decl @114.1-118.3
							(p-ident @114.1-114.2 (raw "t"))
							(e-list @114.5-118.3
								(e-apply @115.3-117.4
									(e-ident @115.3-115.10 (raw "add_one"))
									(e-dbg
										(e-ident @116.1-116.3 (raw "er"))))
								(e-int @117.6-117.9 (raw "456"))))
						(s-for @119.2-122.3
							(p-ident @119.6-119.7 (raw "n"))
							(e-ident @119.11-119.15 (raw "list"))
							(e-block @119.16-122.3
								(statements
									(e-binop @120.2-121.6 (op "+")
										(e-apply @120.2-120.27
											(e-ident @120.2-120.7 (raw "line!"))
											(e-string @120.8-120.26
												(e-string-part @120.9-120.12 (raw "Ag "))
												(e-ident @120.14-120.15 (raw "n"))
												(e-string-part @120.16-120.20 (raw " to "))
												(e-ident @120.22-120.24 (raw "er"))
												(e-string-part @120.25-120.25 (raw ""))))
										(e-ident @121.5-121.6 (raw "n"))))))
						(s-decl @123.2-123.59
							(p-ident @123.2-123.4 (raw "rd"))
							(e-record @123.7-123.59
								(field (field "foo")
									(e-int @123.14-123.17 (raw "123")))
								(field (field "bar")
									(e-string @123.24-123.27
										(e-string-part @123.25-123.26 (raw "H"))))
								(field (field "baz")
									(e-ident @123.34-123.37 (raw "tag")))
								(field (field "qux")
									(e-apply @123.44-123.53
										(e-tag @123.44-123.46 (raw "Ok"))
										(e-ident @123.47-123.52 (raw "world"))))
								(field (field "ned"))))
						(s-decl @124.2-124.64
							(p-ident @124.2-124.7 (raw "tuple"))
							(e-tuple @124.10-124.64
								(e-int @124.11-124.14 (raw "123"))
								(e-string @124.16-124.23
									(e-string-part @124.17-124.22 (raw "World")))
								(e-ident @124.25-124.28 (raw "tag"))
								(e-apply @124.30-124.39
									(e-tag @124.30-124.32 (raw "Ok"))
									(e-ident @124.33-124.38 (raw "world")))
								(e-tuple @124.41-124.52
									(e-ident @124.42-124.44 (raw "nd"))
									(e-ident @124.46-124.51 (raw "tuple")))
								(e-list @124.54-124.63
									(e-int @124.55-124.56 (raw "1"))
									(e-int @124.58-124.59 (raw "2"))
									(e-int @124.61-124.62 (raw "3")))))
						(s-decl @125.2-131.3
							(p-ident @125.2-125.5 (raw "mle"))
							(e-tuple @125.8-131.3
								(e-int @126.3-126.6 (raw "123"))
								(e-string @127.3-127.10
									(e-string-part @127.4-127.9 (raw "World")))
								(e-ident @127.11-127.14 (raw "ag1"))
								(e-apply @128.3-128.12
									(e-tag @128.3-128.5 (raw "Ok"))
									(e-ident @128.6-128.11 (raw "world")))
								(e-tuple @129.3-129.14
									(e-ident @129.4-129.6 (raw "ne"))
									(e-ident @129.8-129.13 (raw "tuple")))
								(e-list @130.3-130.12
									(e-int @130.4-130.5 (raw "1"))
									(e-int @130.7-130.8 (raw "2"))
									(e-int @130.10-130.11 (raw "3")))))
						(s-decl @132.2-132.74
							(p-ident @132.2-132.3 (raw "b"))
							(e-binop @132.6-132.74 (op "or")
								(e-binop @132.6-132.28 (op ">")
									(e-binop @132.6-132.20 (op "??")
										(e-apply @132.6-132.14
											(e-tag @132.6-132.9 (raw "Err"))
											(e-ident @132.10-132.13 (raw "foo")))
										(e-int @132.18-132.20 (raw "12")))
									(e-binop @132.23-132.28 (op "*")
										(e-int @132.23-132.24 (raw "5"))
										(e-int @132.27-132.28 (raw "5"))))
								(e-binop @132.32-132.74 (op "or")
									(e-binop @132.32-132.59 (op "and")
										(e-binop @132.32-132.42 (op "<")
											(e-binop @132.32-132.38 (op "+")
												(e-int @132.32-132.34 (raw "13"))
												(e-int @132.37-132.38 (raw "2")))
											(e-int @132.41-132.42 (raw "5")))
										(e-binop @132.47-132.59 (op ">=")
											(e-binop @132.47-132.53 (op "-")
												(e-int @132.47-132.49 (raw "10"))
												(e-int @132.52-132.53 (raw "1")))
											(e-int @132.57-132.59 (raw "16"))))
									(e-binop @132.63-132.74 (op "<=")
										(e-int @132.63-132.65 (raw "12"))
										(e-binop @132.69-132.74 (op "/")
											(e-int @132.69-132.70 (raw "3"))
											(e-int @132.73-132.74 (raw "5")))))))
						(s-decl @133.1-133.31
							(p-ident @133.1-133.3 (raw "le"))
							(e-field-access @133.5-133.31
								(e-field-access @133.5-133.25
									(e-field-access @133.5-133.18
										(e-question-suffix @133.5-133.12
											(e-tuple @133.5-133.11
												(e-ident @133.6-133.10 (raw "arg1"))))
										(e-question-suffix @133.12-133.18
											(e-apply @133.12-133.17
												(e-ident @133.12-133.15 (raw "od")))))
									(e-question-suffix @133.18-133.25
										(e-apply @133.18-133.24
											(e-ident @133.18-133.22 (raw "ned")))))
								(e-question-suffix @133.25-133.31
									(e-ident @133.25-133.30 (raw "recd")))))
						(e-apply @134.2-138.3
							(e-ident @134.2-134.7 (raw "line!"))
							(e-string @135.3-137.6
								(e-string-part @135.4-135.6 (raw "Ho"))
								(e-apply @136.4-136.13
									(e-ident @136.4-136.5 (raw "r"))
									(e-ident @136.6-136.12 (raw "number")))
								(e-string-part @137.4-137.5 (raw " "))))))))
		(s-type-anno @141.1-141.7 (name "y")
			(ty-record @141.5-141.7))
		(s-decl @142.1-142.7
			(p-ident @142.1-142.2 (raw "e"))
			(e-record @142.5-142.7))
		(s-type-anno @144.1-144.13 (name "t")
			(ty-apply @144.5-144.13
				(ty @144.5-144.6 (name "V"))
				(ty-tuple @144.7-144.12
					(ty-var @144.8-144.9 (raw "a"))
					(ty-var @144.10-144.11 (raw "c")))))
		(s-expect @146.1-149.2
			(e-block @146.8-149.2
				(statements
					(s-decl @147.2-147.6
						(p-ident @147.2-147.3 (raw "f"))
						(e-int @147.5-147.6 (raw "1")))
					(e-binop @148.1-148.9 (op "==")
						(e-ident @148.1-148.2 (raw "h"))
						(e-ident @148.6-148.9 (raw "foo"))))))))
~~~
# FORMATTED
~~~roc
# Thnt!
app [main!] { pf: platform "c" }

import pf.Stdout exposing [line!, e!]

import Stdot # Cose

import p.S exposing [func as fry, Custom.*]

import Bae as Gooe
import
	Ba
Map(a, b) : List(a), (a -> b) -> List(b)
MapML( # Cere
	a, # Anre
	b,
) # Ag
	: # Aon
		List(),
		(a -> b) -> # row
			List(b)

Foo : (Bar, Baz)

line : ( # Cpen
	Bar,
	Baz, # m
) # Co
Some(a) : { foo : Ok(a), bar : g }
Ml(a) : { # d
	bar : Som, # Afld
}

Soine(a) : { # d
	bar : Som,
}
[] # se

Func(a) : Maybe(a), a -> Maybe(a)

ane = |num| if num 2 else 5

add_one : U64 -> U64
add_
ne = |num| {
	other = 1
	if num {
		dbg # bug
			() # r
		0
	} else {
		dbg 123
		other
	}
}

match_time = |
	a, # rg
	b,
| # As
	match a {
		lue | Red => {
			x
			x
		}
		Blue => 1
		"foo" => # ent
			00
		"foo" | "bar" => 20
		[1, 2, 3, .. as rest] # t
			=> ment
		[1, 2 | 5, 3, .. as rest] => 123
		[] => 1
		3.14 => 314
		3.14 | 6.28 => 314
		(1, 2, 3) => 123
		(1, 2 | 5, 3) => 123
		{ foo: 1, bar: 2, ..rest } => 12->add(34)
		{ # Afpen
			oo
				: # ue
					1, # eld
			ar: 2,
			..,
		} => 12
		{ foo: 1, bar: 2 | 7 } => 12
		{
			o: 1,
		} => 212
		Ok(123) => 12
	}

expect # Cord
	blah == 1 # nt

main! : (String) -> Result({}, _)
ma = |_| { # Yee
	world = "d"
	var number = 123
	expect blah == 1
	tag = Blue
	return # d
		tag
	Jus
	...
	match_time(
		...,
	)
	nc(
		dbg # bug
			2, # r
	)
	crash "Unrnt"
	tag_ = Ok(number)
	i = "H, ${world}"
	t = [
		add_one(
			dbg # Afist
				er, # afarg
		),
		456, # ee
	]
	for n in list {
		line!("Ag ${n} to ${er}")
			+ n
	}
	rd = { foo: 123, bar: "H", baz: tag, qux: Ok(world), ned }
	tuple = (123, "World", tag, Ok(world), (nd, tuple), [1, 2, 3])
	mle = (
		123,
		"World",
		ag1,
		Ok(world), # nt
		(ne, tuple),
		[1, 2, 3],
	)
	b = Err(foo) ?? 12 > 5 * 5 or 13 + 2 < 5 and 10 - 1 >= 16 or 12 <= 3 / 5
	le = (arg1)?.od()?.ned()?.recd?
	line!(
		"Ho${
			r(number) # xpr
		} ",
	)
} # Cocl

y : {}
e = {}

t : V((a, c))

expect {
	f = 1
	h == foo
}
~~~
# CANONICALIZE
~~~clojure
(can-ir
	(d-let
		(p-assign @45.1-45.4 (ident "ane"))
		(e-lambda @45.7-45.28
			(args
				(p-assign @45.8-45.11 (ident "num")))
			(e-if @45.13-45.28
				(if-branches
					(if-branch
						(e-lookup-local @45.16-45.19
							(p-assign @45.8-45.11 (ident "num")))
						(e-int @45.20-45.21 (value "2"))))
				(if-else
					(e-int @45.27-45.28 (value "5"))))))
	(d-let
		(p-assign @48.6-48.8 (ident "ne"))
		(e-lambda @48.11-58.2
			(args
				(p-assign @48.12-48.15 (ident "num")))
			(e-block @48.17-58.2
				(s-let @49.2-49.11
					(p-assign @49.2-49.7 (ident "other"))
					(e-int @49.10-49.11 (value "1")))
				(e-if @50.2-57.3
					(if-branches
						(if-branch
							(e-lookup-local @50.5-50.8
								(p-assign @48.12-48.15 (ident "num")))
							(e-block @50.9-54.3
								(s-dbg @51.3-52.3
									(e-runtime-error (tag "empty_tuple")))
								(e-int @53.3-53.4 (value "0")))))
					(if-else
						(e-block @54.9-57.3
							(s-dbg @55.3-55.10
								(e-int @55.7-55.10 (value "123")))
							(e-lookup-local @56.3-56.8
								(p-assign @49.2-49.7 (ident "other")))))))))
	(d-let
		(p-assign @60.1-60.11 (ident "match_time"))
		(e-lambda @60.14-90.3
			(args
				(p-assign @61.2-61.3 (ident "a"))
				(p-assign @62.2-62.3 (ident "b")))
			(e-match @64.2-90.3
				(match @64.2-90.3
					(cond
						(e-lookup-local @64.8-64.9
							(p-assign @61.2-61.3 (ident "a"))))
					(branches
						(branch
							(patterns
								(pattern (degenerate false)
									(p-assign @64.11-64.14 (ident "lue")))
								(pattern (degenerate false)
									(p-applied-tag @64.17-64.20)))
							(value
								(e-block @64.24-66.4
									(s-expr @65.4-65.5
										(e-runtime-error (tag "ident_not_in_scope")))
									(e-runtime-error (tag "ident_not_in_scope")))))
						(branch
							(patterns
								(pattern (degenerate false)
									(p-applied-tag @67.3-67.7)))
							(value
								(e-int @67.12-67.13 (value "1"))))
						(branch
							(patterns
								(pattern (degenerate false)
									(p-str @68.3-68.8 (text """))))
							(value
								(e-int @69.1-69.3 (value "0"))))
						(branch
							(patterns
								(pattern (degenerate false)
									(p-str @70.3-70.8 (text """)))
								(pattern (degenerate false)
									(p-str @70.11-70.16 (text """))))
							(value
								(e-int @70.20-70.22 (value "20"))))
						(branch
							(patterns
								(pattern (degenerate false)
									(p-list @70.22-70.43
										(patterns
											(p-int @70.23-70.24 (value "1"))
											(p-int @70.26-70.27 (value "2"))
											(p-int @70.29-70.30 (value "3")))
										(rest-at (index 3)
											(p-assign @1.1-1.1 (ident "rest"))))))
							(value
								(e-runtime-error (tag "ident_not_in_scope"))))
						(branch
							(patterns
								(pattern (degenerate false)
									(p-list @72.3-72.28
										(patterns
											(p-int @72.4-72.5 (value "1"))
											(p-runtime-error @1.1-1.1 (tag "not_implemented"))
											(p-int @72.14-72.15 (value "3")))
										(rest-at (index 3)
											(p-assign @1.1-1.1 (ident "rest"))))))
							(value
								(e-int @72.32-72.35 (value "123"))))
						(branch
							(patterns
								(pattern (degenerate false)
									(p-list @73.3-74.4
										(patterns))))
							(value
								(e-int @74.8-74.9 (value "1"))))
						(branch
							(patterns
								(pattern (degenerate false)
									(p-small-dec @74.10-74.14)))
							(value
								(e-int @74.18-74.21 (value "314"))))
						(branch
							(patterns
								(pattern (degenerate false)
									(p-small-dec @75.3-75.7))
								(pattern (degenerate false)
									(p-small-dec @75.10-75.14)))
							(value
								(e-int @75.18-75.21 (value "314"))))
						(branch
							(patterns
								(pattern (degenerate false)
									(p-tuple @76.3-76.12
										(patterns
											(p-int @76.4-76.5 (value "1"))
											(p-int @76.7-76.8 (value "2"))
											(p-int @76.10-76.11 (value "3"))))))
							(value
								(e-int @76.16-76.19 (value "123"))))
						(branch
							(patterns
								(pattern (degenerate false)
									(p-tuple @77.3-77.16
										(patterns
											(p-int @77.4-77.5 (value "1"))
											(p-runtime-error @1.1-1.1 (tag "not_implemented"))
											(p-int @77.14-77.15 (value "3"))))))
							(value
								(e-int @77.20-77.23 (value "123"))))
						(branch
							(patterns
								(pattern (degenerate false)
									(p-record-destructure @78.3-78.29
										(destructs
											(record-destruct @78.5-78.11 (label "foo") (ident "foo")
												(sub-pattern
													(p-int @78.10-78.11 (value "1"))))
											(record-destruct @78.13-78.19 (label "bar") (ident "bar")
												(sub-pattern
													(p-int @78.18-78.19 (value "2"))))
											(record-destruct @78.21-78.27 (label "rest") (ident "rest")
												(required
													(p-assign @78.21-78.27 (ident "rest"))))))))
							(value
								(e-runtime-error (tag "not_implemented"))))
						(branch
							(patterns
								(pattern (degenerate false)
									(p-runtime-error @84.4-84.6 (tag "not_implemented"))))
							(value
								(e-int @84.11-84.13 (value "12"))))
						(branch
							(patterns
								(pattern (degenerate false)
									(p-record-destructure @85.3-85.25
										(destructs
											(record-destruct @85.5-85.11 (label "foo") (ident "foo")
												(sub-pattern
													(p-int @85.10-85.11 (value "1"))))
											(record-destruct @85.13-85.23 (label "bar") (ident "bar")
												(sub-pattern
													(p-runtime-error @1.1-1.1 (tag "not_implemented"))))))))
							(value
								(e-int @85.29-85.31 (value "12"))))
						(branch
							(patterns
								(pattern (degenerate false)
									(p-record-destructure @86.3-88.5
										(destructs
											(record-destruct @87.2-87.6 (label "o") (ident "o")
												(sub-pattern
													(p-int @87.5-87.6 (value "1"))))))))
							(value
								(e-int @88.8-88.11 (value "212"))))
						(branch
							(patterns
								(pattern (degenerate false)
									(p-applied-tag @89.3-89.10)))
							(value
								(e-int @89.14-89.16 (value "12")))))))))
	(d-let
		(p-assign @96.1-96.3 (ident "ma"))
		(e-closure @96.5-139.2
			(captures
				(capture @48.6-48.8 (ident "ne"))
				(capture @60.1-60.11 (ident "match_time"))
				(capture @124.2-124.7 (ident "tuple")))
			(e-lambda @96.5-139.2
				(args
					(p-underscore @96.6-96.7))
				(e-block @96.9-139.2
					(s-let @97.2-97.13
						(p-assign @97.2-97.7 (ident "world"))
						(e-string @97.10-97.13
							(e-literal @97.11-97.12 (string "d"))))
					(s-var @98.2-98.18
						(p-assign @98.2-98.18 (ident "number"))
						(e-int @98.15-98.18 (value "123")))
					(s-expect @99.2-99.18
						(e-binop @99.9-99.18 (op "eq")
							(e-runtime-error (tag "ident_not_in_scope"))
							(e-int @99.17-99.18 (value "1"))))
					(s-let @100.2-100.12
						(p-assign @100.2-100.5 (ident "tag"))
						(e-tag @100.8-100.12 (name "Blue")))
					(s-return @101.2-102.6
						(e-lookup-local @102.3-102.6
							(p-assign @100.2-100.5 (ident "tag"))))
					(s-expr @102.8-102.11
						(e-tag @102.8-102.11 (name "Jus")))
					(s-expr @103.2-103.5
						(e-not-implemented @1.1-1.1))
					(s-expr @104.2-106.3
						(e-call @104.2-106.3
							(e-lookup-local @104.2-104.12
								(p-assign @60.1-60.11 (ident "match_time")))
							(e-not-implemented @1.1-1.1)))
					(s-expr @107.1-110.3
						(e-call @107.1-110.3
							(e-runtime-error (tag "ident_not_in_scope"))
							(e-dbg @108.3-109.2
								(e-int @109.1-109.2 (value "2")))))
					(s-crash @111.2-111.14 (msg "Unrnt"))
					(s-let @112.2-112.19
						(p-assign @112.2-112.6 (ident "tag_"))
						(e-tag @112.9-112.11 (name "Ok")
							(args
								(e-lookup-local @112.12-112.18
									(p-assign @98.2-98.18 (ident "number"))))))
					(s-let @113.2-113.18
						(p-assign @113.2-113.3 (ident "i"))
						(e-string @113.5-113.18
							(e-literal @113.6-113.9 (string "H, "))
							(e-lookup-local @113.11-113.16
								(p-assign @97.2-97.7 (ident "world")))
							(e-literal @113.17-113.17 (string ""))))
					(s-let @114.1-118.3
						(p-assign @114.1-114.2 (ident "t"))
						(e-list @114.5-118.3
							(elems
								(e-call @115.3-117.4
									(e-runtime-error (tag "ident_not_in_scope"))
									(e-dbg @115.11-116.3
										(e-runtime-error (tag "ident_not_in_scope"))))
								(e-int @117.6-117.9 (value "456")))))
					(s-let @123.2-123.59
						(p-assign @123.2-123.4 (ident "rd"))
						(e-record @123.7-123.59
							(fields
								(field (name "foo")
									(e-int @123.14-123.17 (value "123")))
								(field (name "bar")
									(e-string @123.24-123.27
										(e-literal @123.25-123.26 (string "H"))))
								(field (name "baz")
									(e-lookup-local @123.34-123.37
										(p-assign @100.2-100.5 (ident "tag"))))
								(field (name "qux")
									(e-tag @123.44-123.46 (name "Ok")
										(args
											(e-lookup-local @123.47-123.52
												(p-assign @97.2-97.7 (ident "world"))))))
								(field (name "ned")
									(e-runtime-error (tag "ident_not_in_scope"))))))
					(s-let @124.2-124.64
						(p-assign @124.2-124.7 (ident "tuple"))
						(e-tuple @124.10-124.64
							(elems
								(e-int @124.11-124.14 (value "123"))
								(e-string @124.16-124.23
									(e-literal @124.17-124.22 (string "World")))
								(e-lookup-local @124.25-124.28
									(p-assign @100.2-100.5 (ident "tag")))
								(e-tag @124.30-124.32 (name "Ok")
									(args
										(e-lookup-local @124.33-124.38
											(p-assign @97.2-97.7 (ident "world")))))
								(e-tuple @124.41-124.52
									(elems
										(e-runtime-error (tag "ident_not_in_scope"))
										(e-lookup-local @124.46-124.51
											(p-assign @124.2-124.7 (ident "tuple")))))
								(e-list @124.54-124.63
									(elems
										(e-int @124.55-124.56 (value "1"))
										(e-int @124.58-124.59 (value "2"))
										(e-int @124.61-124.62 (value "3")))))))
					(s-let @125.2-131.3
						(p-assign @125.2-125.5 (ident "mle"))
						(e-tuple @125.8-131.3
							(elems
								(e-int @126.3-126.6 (value "123"))
								(e-string @127.3-127.10
									(e-literal @127.4-127.9 (string "World")))
								(e-runtime-error (tag "ident_not_in_scope"))
								(e-tag @128.3-128.5 (name "Ok")
									(args
										(e-lookup-local @128.6-128.11
											(p-assign @97.2-97.7 (ident "world")))))
								(e-tuple @129.3-129.14
									(elems
										(e-lookup-local @129.4-129.6
											(p-assign @48.6-48.8 (ident "ne")))
										(e-lookup-local @129.8-129.13
											(p-assign @124.2-124.7 (ident "tuple")))))
								(e-list @130.3-130.12
									(elems
										(e-int @130.4-130.5 (value "1"))
										(e-int @130.7-130.8 (value "2"))
										(e-int @130.10-130.11 (value "3")))))))
					(s-let @132.2-132.74
						(p-assign @132.2-132.3 (ident "b"))
						(e-binop @132.6-132.74 (op "or")
							(e-binop @132.6-132.28 (op "gt")
								(e-binop @132.6-132.20 (op "null_coalesce")
									(e-tag @132.6-132.9 (name "Err")
										(args
											(e-runtime-error (tag "ident_not_in_scope"))))
									(e-int @132.18-132.20 (value "12")))
								(e-binop @132.23-132.28 (op "mul")
									(e-int @132.23-132.24 (value "5"))
									(e-int @132.27-132.28 (value "5"))))
							(e-binop @132.32-132.74 (op "or")
								(e-binop @132.32-132.59 (op "and")
									(e-binop @132.32-132.42 (op "lt")
										(e-binop @132.32-132.38 (op "add")
											(e-int @132.32-132.34 (value "13"))
											(e-int @132.37-132.38 (value "2")))
										(e-int @132.41-132.42 (value "5")))
									(e-binop @132.47-132.59 (op "ge")
										(e-binop @132.47-132.53 (op "sub")
											(e-int @132.47-132.49 (value "10"))
											(e-int @132.52-132.53 (value "1")))
										(e-int @132.57-132.59 (value "16"))))
								(e-binop @132.63-132.74 (op "le")
									(e-int @132.63-132.65 (value "12"))
									(e-binop @132.69-132.74 (op "div")
										(e-int @132.69-132.70 (value "3"))
										(e-int @132.73-132.74 (value "5")))))))
					(s-let @133.1-133.31
						(p-assign @133.1-133.3 (ident "le"))
						(e-dot-access @133.5-133.31 (field "unknown")
							(receiver
								(e-dot-access @133.5-133.25 (field "unknown")
									(receiver
										(e-dot-access @133.5-133.18 (field "unknown")
											(receiver
												(e-runtime-error (tag "not_implemented")))))))))
					(e-call @134.2-138.3
						(e-lookup-external @134.2-134.7
							(module-idx "0")
							(target-node-idx "0"))
						(e-string @135.3-137.6
							(e-literal @135.4-135.6 (string "Ho"))
							(e-call @136.4-136.13
								(e-runtime-error (tag "ident_not_in_scope"))
								(e-lookup-local @136.6-136.12
									(p-assign @98.2-98.18 (ident "number"))))
							(e-literal @137.4-137.5 (string " "))))))))
	(d-let
		(p-assign @142.1-142.2 (ident "e"))
		(e-empty_record @142.5-142.7))
	(s-alias-decl @15.1-15.41
		(ty-header @15.1-15.10 (name "Map")
			(ty-args
				(ty-var @15.5-15.6 (name "a"))
				(ty-var @15.8-15.9 (name "b"))))
		(ty-fn @15.13-15.41 (effectful false)
			(ty-apply @15.13-15.20 (symbol "List")
				(ty-var @15.18-15.19 (name "a")))
			(ty-parens @15.22-15.30
				(ty-fn @15.23-15.29 (effectful false)
					(ty-var @15.23-15.24 (name "a"))
					(ty-var @15.28-15.29 (name "b"))))
			(ty-apply @15.34-15.41 (symbol "List")
				(ty-var @15.39-15.40 (name "b")))))
	(s-alias-decl @16.1-24.15
		(ty-header @16.1-19.2 (name "MapML")
			(ty-args
				(ty-var @17.2-17.3 (name "a"))
				(ty-var @18.2-18.3 (name "b"))))
		(ty-fn @21.3-24.15 (effectful false)
			(ty-apply @21.3-22.4 (symbol "List"))
			(ty-parens @23.3-23.11
				(ty-fn @23.4-23.10 (effectful false)
					(ty-var @23.4-23.5 (name "a"))
					(ty-var @23.9-23.10 (name "b"))))
			(ty-apply @24.4-24.15 (symbol "List")
				(ty-var @24.12-24.13 (name "b")))))
	(s-alias-decl @26.1-26.17
		(ty-header @26.1-26.4 (name "Foo"))
		(ty-tuple @26.7-26.17
			(ty @26.8-26.11 (name "Bar"))
			(ty @26.13-26.16 (name "Baz"))))
	(s-alias-decl @32.1-32.35
		(ty-header @32.1-32.8 (name "Some")
			(ty-args
				(ty-var @32.6-32.7 (name "a"))))
		(ty-record @32.11-32.35
			(field (field "foo")
				(ty-apply @32.19-32.24 (symbol "Ok")
					(ty-var @32.22-32.23 (name "a"))))
			(field (field "bar")
				(ty-malformed @32.32-32.33))))
	(s-alias-decl @33.1-35.2
		(ty-header @33.1-33.6 (name "Ml")
			(ty-args
				(ty-var @33.4-33.5 (name "a"))))
		(ty-record @33.9-35.2
			(field (field "bar")
				(ty @34.8-34.11 (name "Som")))))
	(s-alias-decl @37.1-39.2
		(ty-header @37.1-37.9 (name "Soine")
			(ty-args
				(ty-var @37.7-37.8 (name "a"))))
		(ty-record @37.12-39.2
			(field (field "bar")
				(ty @38.8-38.11 (name "Som")))))
	(s-alias-decl @43.1-43.34
		(ty-header @43.1-43.8 (name "Func")
			(ty-args
				(ty-var @43.6-43.7 (name "a"))))
		(ty-fn @43.11-43.34 (effectful false)
			(ty-apply @43.11-43.19 (symbol "Maybe")
				(ty-var @43.17-43.18 (name "a")))
			(ty-var @43.21-43.22 (name "a"))
			(ty-apply @43.26-43.34 (symbol "Maybe")
				(ty-var @43.32-43.33 (name "a")))))
	(s-import @4.1-4.38 (module "pf.Stdout") (qualifier "pf")
		(exposes
			(exposed (name "line!") (wildcard false))
			(exposed (name "e!") (wildcard false))))
	(s-import @6.1-8.4 (module "Stdot")
		(exposes))
	(s-import @10.1-10.46 (module "MALFORMED_IMPORT") (qualifier "p")
		(exposes
			(exposed (name "func") (alias "fry") (wildcard false))
			(exposed (name "Custom") (wildcard true))))
	(s-import @12.1-12.19 (module "Bae") (alias "Gooe")
		(exposes))
	(s-import @13.1-14.4 (module "Ba")
		(exposes))
	(s-expect @92.1-93.11
		(e-binop @93.2-93.11 (op "eq")
			(e-runtime-error (tag "ident_not_in_scope"))
			(e-int @93.10-93.11 (value "1"))))
	(s-expect @146.1-149.2
		(e-block @146.8-149.2
			(s-let @147.2-147.6
				(p-assign @147.2-147.3 (ident "f"))
				(e-int @147.5-147.6 (value "1")))
			(e-binop @148.1-148.9 (op "eq")
				(e-runtime-error (tag "ident_not_in_scope"))
				(e-runtime-error (tag "ident_not_in_scope"))))))
~~~
# TYPES
~~~clojure
(inferred-types
	(defs
		(patt @45.1-45.4 (type "Bool -> Num(_size)"))
		(patt @48.6-48.8 (type "Bool -> Num(_size)"))
		(patt @60.1-60.11 (type "Error"))
		(patt @96.1-96.3 (type "_arg -> _ret"))
		(patt @142.1-142.2 (type "{}")))
	(type_decls
		(alias @15.1-15.41 (type "Map(a, b)")
			(ty-header @15.1-15.10 (name "Map")
				(ty-args
					(ty-var @15.5-15.6 (name "a"))
					(ty-var @15.8-15.9 (name "b")))))
		(alias @16.1-24.15 (type "MapML(a, b)")
			(ty-header @16.1-19.2 (name "MapML")
				(ty-args
					(ty-var @17.2-17.3 (name "a"))
					(ty-var @18.2-18.3 (name "b")))))
		(alias @26.1-26.17 (type "Foo")
			(ty-header @26.1-26.4 (name "Foo")))
		(alias @32.1-32.35 (type "Some(a)")
			(ty-header @32.1-32.8 (name "Some")
				(ty-args
					(ty-var @32.6-32.7 (name "a")))))
		(alias @33.1-35.2 (type "Ml(a)")
			(ty-header @33.1-33.6 (name "Ml")
				(ty-args
					(ty-var @33.4-33.5 (name "a")))))
		(alias @37.1-39.2 (type "Soine(a)")
			(ty-header @37.1-37.9 (name "Soine")
				(ty-args
					(ty-var @37.7-37.8 (name "a")))))
		(alias @43.1-43.34 (type "Func(a)")
			(ty-header @43.1-43.8 (name "Func")
				(ty-args
					(ty-var @43.6-43.7 (name "a"))))))
	(expressions
		(expr @45.7-45.28 (type "Bool -> Num(_size)"))
		(expr @48.11-58.2 (type "Bool -> Num(_size)"))
		(expr @60.14-90.3 (type "Error"))
		(expr @96.5-139.2 (type "_arg -> _ret"))
		(expr @142.5-142.7 (type "{}"))))
~~~
