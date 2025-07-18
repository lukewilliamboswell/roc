// CodeMirror mode for Roc language
(function (mod) {
  if (typeof exports == "object" && typeof module == "object")
    // CommonJS
    mod(require("../../lib/codemirror"));
  else if (typeof define == "function" && define.amd)
    // AMD
    define(["../../lib/codemirror"], mod); // Plain browser env
  else mod(CodeMirror);
})(function (CodeMirror) {
  "use strict";

  CodeMirror.defineMode("roc", function (config) {
    var ERRORCLASS = "error";

    function wordRegexp(words) {
      return new RegExp("^((" + words.join(")|(") + "))\\b");
    }

    // Roc keywords
    var keywords = wordRegexp([
      "if",
      "else",
      "match",
      "when",
      "is",
      "as",
      "and",
      "or",
      "not",
      "where",
      "import",
      "exposing",
      "module",
      "interface",
      "app",
      "package",
      "platform",
      "expect",
      "dbg",
      "crash",
      "try",
      "var",
      "return",
      "for",
      "in",
    ]);

    // Roc builtin Types and constructors
    var builtins = wordRegexp([
      "List",
      "Dict",
      "Set",
      "Str",
      "Num",
      "Bool",
      "Result",
      "Box",
      "U8",
      "U16",
      "U32",
      "U64",
      "U128",
      "Int",
      "I8",
      "I16",
      "I32",
      "I64",
      "I128",
      "F32",
      "F64",
      "Dec",
      "Frac",
      "Ok",
      "Err",
      "True",
      "False",
      "None",
      "Some",
      "Red",
      "Blue",
      "Green",
    ]);

    var operators =
      /^(\?\?|=>|->|\+|\-|\*|\/|==|!=|<=|>=|<|>|\|\||&&|!|=|\||&|\^|%)/;
    var punctuation = /^[,;\.:\[\]{}()]/;

    function tokenBase(stream, state) {
      var ch = stream.next();

      // Handle comments
      if (ch == "#") {
        stream.skipToEnd();
        return "comment";
      }

      // Handle strings (including interpolation)
      if (ch == '"') {
        state.tokenize = tokenString('"');
        return state.tokenize(stream, state);
      }

      // Handle character literals
      if (ch == "'") {
        state.tokenize = tokenString("'");
        return state.tokenize(stream, state);
      }

      // Handle numbers (including floats and hex)
      if (/\d/.test(ch)) {
        stream.eatWhile(/[\d]/);
        if (stream.eat(".")) {
          stream.eatWhile(/[\d]/);
        }
        if (stream.eat(/[eE]/)) {
          stream.eat(/[+\-]/);
          stream.eatWhile(/[\d]/);
        }
        return "number";
      }

      // Handle hex numbers
      if (ch == "0" && (stream.peek() == "x" || stream.peek() == "X")) {
        stream.next();
        stream.eatWhile(/[\da-fA-F]/);
        return "number";
      }

      // Handle binary numbers
      if (ch == "0" && (stream.peek() == "b" || stream.peek() == "B")) {
        stream.next();
        stream.eatWhile(/[01]/);
        return "number";
      }

      // Handle octal numbers
      if (ch == "0" && (stream.peek() == "o" || stream.peek() == "O")) {
        stream.next();
        stream.eatWhile(/[0-7]/);
        return "number";
      }

      // Handle lambda syntax |arg|
      if (ch == "|") {
        return "keyword";
      }

      // Handle multi-character operators first
      var next = stream.peek();
      if (ch == "?" && next == "?") {
        stream.next();
        return "operator";
      }
      if (ch == "=" && next == ">") {
        stream.next();
        return "operator";
      }
      if (ch == "-" && next == ">") {
        stream.next();
        return "operator";
      }

      if (ch == "|" && next == "|") {
        stream.next();
        return "operator";
      }
      if (ch == "&" && next == "&") {
        stream.next();
        return "operator";
      }
      if (ch == "=" && next == "=") {
        stream.next();
        return "operator";
      }
      if (ch == "!" && next == "=") {
        stream.next();
        return "operator";
      }
      if (ch == "<" && next == "=") {
        stream.next();
        return "operator";
      }
      if (ch == ">" && next == "=") {
        stream.next();
        return "operator";
      }

      // Handle single-character operators
      if (operators.test(ch)) {
        return "operator";
      }

      // Handle punctuation
      if (punctuation.test(ch)) {
        return "punctuation";
      }

      // Handle identifiers and keywords
      if (/[a-zA-Z_]/.test(ch)) {
        stream.eatWhile(/[\w]/);

        // Check for effect suffix (!)
        var hasEffect = false;
        if (stream.peek() == "!") {
          stream.next();
          hasEffect = true;
        }

        var word = stream.current();
        var baseWord = hasEffect ? word.slice(0, -1) : word;

        // Check for keywords
        if (keywords.test(baseWord)) {
          return "keyword";
        }

        // Check for built-in constructors
        if (builtins.test(baseWord)) {
          return "builtin";
        }

        // Check for types (capitalized identifiers)
        if (/^[A-Z]/.test(baseWord)) {
          return "type";
        }

        // Check for constants (ALL_CAPS)
        if (/^[A-Z_][A-Z0-9_]*$/.test(baseWord)) {
          return "constant";
        }

        // Effect functions get special styling
        if (hasEffect) {
          return "variable-effect";
        }

        return "variable";
      }

      // Handle underscore (wildcard pattern)
      if (ch == "_") {
        if (stream.eatWhile(/\w/)) {
          return "variable";
        }
        return "keyword"; // standalone underscore
      }

      // Handle dots, double dots, and triple dots
      if (ch == ".") {
        if (stream.peek() == ".") {
          stream.next(); // consume second dot
          if (stream.peek() == ".") {
            stream.next(); // consume third dot
            return "keyword"; // triple dot is a placeholder
          }
          return "keyword"; // double dot is for spread/rest patterns
        }
        return "punctuation"; // single dot is for record access
      }

      // Handle type annotations :
      if (ch == ":") {
        return "punctuation";
      }

      // Handle backslash for lambda
      if (ch == "\\") {
        return "keyword";
      }

      return ERRORCLASS;
    }

    function tokenString(quote) {
      return function (stream, state) {
        var escaped = false,
          next,
          end = false;
        while ((next = stream.next()) != null) {
          if (next == quote && !escaped) {
            end = true;
            break;
          }
          // Handle string interpolation
          if (next == "$" && stream.peek() == "{" && !escaped) {
            stream.next(); // consume {
            state.tokenize = tokenInterpolation;
            return "string";
          }
          escaped = !escaped && next == "\\";
        }
        if (end || !escaped) {
          state.tokenize = tokenBase;
        }
        return "string";
      };
    }

    function tokenInterpolation(stream, state) {
      var depth = 1;
      var ch;
      while ((ch = stream.next()) != null) {
        if (ch == "{") depth++;
        if (ch == "}") {
          depth--;
          if (depth == 0) {
            state.tokenize = tokenString('"');
            return "string-interpolation";
          }
        }
      }
      return "string-interpolation";
    }

    return {
      startState: function () {
        return {
          tokenize: tokenBase,
          indentStack: null,
          dedent: 0,
        };
      },

      token: function (stream, state) {
        if (stream.eatSpace()) return null;

        var style = state.tokenize(stream, state);
        return style;
      },

      indent: function (state, textAfter) {
        if (state.tokenize != tokenBase) return 0;
        return 0; // Simple indentation for now
      },

      lineComment: "#",
      blockCommentStart: null,
      blockCommentEnd: null,
      fold: "indent",
    };
  });

  CodeMirror.defineMIME("text/x-roc", "roc");
});
