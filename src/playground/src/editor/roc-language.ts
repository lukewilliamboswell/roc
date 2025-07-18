import {
  StreamLanguage,
  LanguageSupport,
  StringStream,
} from "@codemirror/language";

interface StreamState {
  context?: string;
  tokenize?: (stream: any, state: StreamState) => string | null;
}

export function rocStreamLanguage(): LanguageSupport {
  return new LanguageSupport(
    StreamLanguage.define({
      name: "roc",

      startState(): StreamState {
        return {};
      },

      token(stream: StringStream, state: StreamState): string | null {
        // Skip whitespace
        if (stream.eatSpace()) return null;

        const ch = stream.next();
        if (!ch) return null;

        // Comments
        if (ch === "#") {
          stream.skipToEnd();
          return "comment";
        }

        // Strings
        if (ch === '"' || ch === "'") {
          const quote = ch;
          let escaped = false;
          let next: string | void;

          while ((next = stream.next()) !== undefined) {
            if (next === quote && !escaped) {
              return "string";
            }

            // String interpolation
            if (next === "$" && stream.peek() === "{" && !escaped) {
              stream.next(); // consume {
              let depth = 1;
              while (depth > 0 && (next = stream.next()) !== undefined) {
                if (next === "{") depth++;
                if (next === "}") depth--;
              }
              return "string special";
            }

            escaped = !escaped && next === "\\";
          }
          return "string";
        }

        // Numbers
        if (/\d/.test(ch)) {
          stream.eatWhile(/\d/);
          if (stream.eat(".")) {
            stream.eatWhile(/\d/);
          }
          if (stream.eat(/[eE]/)) {
            stream.eat(/[+-]/);
            stream.eatWhile(/\d/);
          }
          return "number";
        }

        // Hex numbers
        if (ch === "0" && /[xX]/.test(stream.peek() || "")) {
          stream.next();
          stream.eatWhile(/[0-9a-fA-F]/);
          return "number";
        }

        // Multi-character operators
        const next = stream.peek();
        if (
          (ch === "?" && next === "?") ||
          (ch === "=" && next === ">") ||
          (ch === "-" && next === ">") ||
          (ch === "|" && next === "|") ||
          (ch === "&" && next === "&") ||
          (ch === "=" && next === "=") ||
          (ch === "!" && next === "=") ||
          (ch === "<" && next === "=") ||
          (ch === ">" && next === "=")
        ) {
          stream.next();
          return "operator";
        }

        // Single-character operators
        if ("+-*/<>!|&^%".indexOf(ch) !== -1) {
          return "operator";
        }

        // Punctuation
        if ("=,;.:[]{}".indexOf(ch) !== -1) {
          return "punctuation";
        }

        // Identifiers and keywords
        if (/[a-zA-Z_]/.test(ch)) {
          stream.eatWhile(/[\w]/);

          // Check for effect suffix
          if (stream.peek() === "!") {
            stream.next();
          }

          const word = stream.current();
          const baseWord = word.endsWith("!") ? word.slice(0, -1) : word;

          // Keywords
          const keywords: string[] = [
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
          ];

          if (keywords.includes(baseWord)) {
            return "keyword";
          }

          // Built-in types
          const builtins: string[] = [
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
          ];

          if (builtins.includes(baseWord)) {
            return "type";
          }

          // Type names (capitalized)
          if (/^[A-Z]/.test(baseWord)) {
            return "type";
          }

          // Constants (ALL_CAPS)
          if (/^[A-Z_][A-Z0-9_]*$/.test(baseWord)) {
            return "constant";
          }

          return "variable";
        }

        // Underscore (wildcard)
        if (ch === "_") {
          if (stream.eatWhile(/\w/)) {
            return "variable";
          }
          return "keyword";
        }

        return null;
      },

      languageData: {
        commentTokens: { line: "#" },
        indentOnInput: /^\s*[\}\]\)]$/,
      },
    }),
  );
}
